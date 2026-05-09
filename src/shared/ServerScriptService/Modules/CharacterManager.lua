-- ServerScriptService/Modules/CharacterManager
--[[
    CharacterManager
    ================
    Orchestrates the one-time character creation flow for new players
    and manages character template application throughout the session.

    Flow:
        1. Player joins → server checks CharacterData.isCreated
        2. If false  → fires "CharacterCreationRequired" to client
        3. Client shows creation screen (gender + skin color)
        4. Client fires "CharacterCreationComplete" with { gender, preset, skinColor }
        5. Server validates, saves to PlayerData, calls ApplyTemplate
        6. CharacterData.isCreated = true → never shown again

    Character Templates:
        Gender models live in ServerStorage/CharacterTemplates.
        Each contains CharacterMesh instances that define the body shape.
        ApplyTemplate clones those CharacterMesh items into the player's
        default R6 rig and sets BodyColors from the chosen skin color.

    If the template folder is missing the system degrades silently.
]]

local CharacterManager = {}

local Players        = game:GetService("Players")
local ServerStorage  = game:GetService("ServerStorage")
local StarterPlayer  = game:GetService("StarterPlayer")

local Modules           = script.Parent
local NetworkManager    = require(Modules:WaitForChild("NetworkManager"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
local CharacterConfig   = require(Modules:WaitForChild("CharacterConfig"))

-- Lazy-loaded to avoid circular deps
local CosmeticManager = nil

local TEMPLATES_FOLDER_NAME = "CharacterTemplates"
-- Tag used to identify cloned CharacterMesh items we added
local TEMPLATE_TAG = "_TemplateCharacterMesh"

-- Track connections per player to avoid leaks
local playerConnections = {}

local function GetTemplatesFolder()
	return ServerStorage:FindFirstChild(TEMPLATES_FOLDER_NAME)
end

-- ═══════════════════════════════════════════════════════════
-- TEMPLATE APPLICATION
-- ═══════════════════════════════════════════════════════════

--- Clone all CharacterMesh instances from the template (body + head).
local function ApplyCharacterMeshes(character, template)
	-- Remove any previously-applied template CharacterMeshes
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("CharacterMesh") and child:GetAttribute(TEMPLATE_TAG) then
			child:Destroy()
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		warn("[CharacterManager] R15 rig detected — CharacterMesh has no effect.")
		return 0
	end

	local appliedCount = 0
	for _, child in ipairs(template:GetChildren()) do
		if child:IsA("CharacterMesh") then
			local clone = child:Clone()
			clone:SetAttribute(TEMPLATE_TAG, true)
			clone.Parent = character
			appliedCount += 1
		end
	end
	return appliedCount
end

--- Force the correct Rthro head mesh + texture onto the player's Head Part.
--- CharacterMesh(BodyPart=Head) does NOT update character.Head.SpecialMesh at
--- runtime; we must set both MeshId AND TextureId explicitly.  Also strips the
--- player's avatar face Decal, which is distorted on an Rthro head mesh.
local function ApplyHeadAppearance(character, template, player)
	local head = character:FindFirstChild("Head")
	if not head then return end

	-- Read head mesh + texture from the template's Head Part SpecialMesh
	local templateHead = template:FindFirstChild("Head")
	local templateMeshId  = nil
	local templateTexture = nil
	if templateHead then
		local tm = templateHead:FindFirstChildOfClass("SpecialMesh")
		if tm then
			templateMeshId  = tm.MeshId
			templateTexture = tm.TextureId
		end
	end

	local function apply()
		if not head.Parent then return end
		local mesh = head:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			if templateMeshId  and templateMeshId  ~= "" then mesh.MeshId  = templateMeshId  end
			if templateTexture and templateTexture ~= "" then mesh.TextureId = templateTexture end
		end
		-- Remove avatar face Decal (distorted on Rthro head mesh)
		for _, child in ipairs(head:GetChildren()) do
			if child:IsA("Decal") and child.Name == "face" then
				child:Destroy()
			end
		end
	end

	apply()
	-- Re-apply after ApplyDescription may have reset SpecialMesh properties
	task.delay(0.15, apply)
	task.delay(1,    apply)

	-- Re-apply whenever Roblox's async avatar loader overwrites the head mesh.
	-- Setting MeshId to the same value does not re-fire Changed, so no loop.
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	if mesh and templateMeshId and templateMeshId ~= "" then
		local meshConn = mesh:GetPropertyChangedSignal("MeshId"):Connect(function()
			apply()
		end)
		if not playerConnections[player] then playerConnections[player] = {} end
		table.insert(playerConnections[player], meshConn)
		task.delay(15, function()
			meshConn:Disconnect()
		end)
	end

	-- Guard against the engine re-adding the face Decal
	local conn
	conn = head.ChildAdded:Connect(function(child)
		if child:IsA("Decal") and child.Name == "face" then
			child:Destroy()
		end
	end)
	if not playerConnections[player] then playerConnections[player] = {} end
	table.insert(playerConnections[player], conn)
	task.delay(10, function()
		conn:Disconnect()
	end)
end

--- Copy Motor6D C0/C1 joints from the template Torso to the character Torso.
--- Template files have the correct values baked in, so this is a direct copy.
local function ApplyMotor6DFromTemplate(character, template)
	local charTorso  = character:FindFirstChild("Torso")
	local templTorso = template:FindFirstChild("Torso")
	if not charTorso or not templTorso then
		warn("[CharacterManager] ApplyMotor6D — missing Torso:", charTorso ~= nil, templTorso ~= nil)
		return
	end
	local count = 0
	for _, templJoint in ipairs(templTorso:GetChildren()) do
		if templJoint:IsA("Motor6D") then
			local charJoint = charTorso:FindFirstChild(templJoint.Name)
			if charJoint then
				charJoint.C0 = templJoint.C0
				charJoint.C1 = templJoint.C1
				count += 1
			end
		end
	end
end

--- Weld armor Parts from an armor-type skin template onto the character.
--- Each armor Part (named e.g. "Torso", "Left Arm") is cloned and welded
--- to the same-named character body Part with an identity offset.
local ARMOR_PARTS = { "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local function ApplyArmorSkin(character, armorTemplate)
	-- Remove any previously-applied armor
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("_ArmorSkin") then
			child:Destroy()
		end
	end
	for _, partName in ipairs(ARMOR_PARTS) do
		local armorPart = armorTemplate:FindFirstChild(partName)
		local charPart  = character:FindFirstChild(partName)
		if armorPart and charPart then
			local clone = armorPart:Clone()
			clone:SetAttribute("_ArmorSkin", true)
			-- Disable internal armor welds/snaps (character animation drives positioning)
			for _, w in ipairs(clone:GetDescendants()) do
				if w:IsA("Weld") or w:IsA("Snap") then
					w.Enabled = false
				end
			end
			-- Weld armor piece directly to the character body part
			local weld = Instance.new("Weld")
			weld.Part0 = charPart
			weld.Part1 = clone
			weld.C0 = CFrame.identity
			weld.C1 = CFrame.identity
			weld.Parent = clone
			clone.Parent = character
		end
	end
end

--[[
    ApplyTemplate(player)
    Applies the gender template's full appearance to the player's R6 character:
      1. Humanoid:ApplyDescription() — sets body meshes, head mesh, and body
         proportions (triggering AutomaticScaling / Motor6D recalculation).
      2. ApplyHeadAppearance() — directly sets Head.SpecialMesh.MeshId + TextureId
         as a belt-and-suspenders guarantee for the Rthro head mesh.
      3. Re-adds the hair Accessory from the template (not in HumanoidDescription).
      4. ApplySkinColor() — overrides BodyColors with the saved skin color.
    Safe to call at any point; no-op if character or data is missing.
]]
function CharacterManager.ApplyTemplate(player)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.Account or not data.Account.CharacterData then return false end

	local cd = data.Account.CharacterData
	if not cd.isCreated then return false end

	local character = player.Character
	if not character then return false end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end

	local templateName = CharacterConfig.GetTemplateName(cd.preset, cd.gender)
	local folder = GetTemplatesFolder()

	if not folder then
		warn("[CharacterManager] CharacterTemplates folder not found — using default avatar for " .. player.Name)
		return false
	end

	local template = folder:FindFirstChild(templateName)
	if not template then
		warn("[CharacterManager] Template '" .. templateName .. "' not found — using default avatar for " .. player.Name)
		return false
	end

	-- Find the HumanoidDescription inside the template's Humanoid
	local templateHumanoid = template:FindFirstChildOfClass("Humanoid")
	local desc = templateHumanoid and templateHumanoid:FindFirstChildOfClass("HumanoidDescription")

	-- ── 0) Disable AutomaticScaling BEFORE ApplyDescription ──────────────────
	humanoid.AutomaticScalingEnabled = false

	-- ── 1) Apply body meshes (CharacterMesh only — no ApplyDescription) ─────────
	--    ApplyDescription resets Motor6D pivots even with BodyTypeScale=0,
	--    so we skip it entirely and apply CharacterMesh instances directly.
	ApplyCharacterMeshes(character, template)

	-- ── 1b) Write Motor6D values from template ────────────────────────────────
	--    Template files now have correct C0/C1 baked in.  Copy them directly.
	task.wait()
	ApplyMotor6DFromTemplate(character, template)

	-- ── 1c) Guard against Roblox's async avatar loader re-enabling scaling ─────
	local scalingConn = humanoid:GetPropertyChangedSignal("AutomaticScalingEnabled"):Connect(function()
		if humanoid.AutomaticScalingEnabled and character.Parent then
			humanoid.AutomaticScalingEnabled = false
			task.spawn(function()
				task.wait()
				if character.Parent then
					ApplyMotor6DFromTemplate(character, template)
				end
			end)
		end
	end)
	if not playerConnections[player] then playerConnections[player] = {} end
	table.insert(playerConnections[player], scalingConn)
	task.delay(30, function() scalingConn:Disconnect() end)

	-- ── 2) Guarantee correct head mesh + texture ──────────────────────────────
	ApplyHeadAppearance(character, template, player)

	-- Remove Roblox's ShirtGraphic Decal from the Torso.
	local torso = character:FindFirstChild("Torso")
	if torso then
		for _, child in ipairs(torso:GetChildren()) do
			if child:IsA("Decal") then child:Destroy() end
		end
	end

	-- ── 3) Hair accessory ────────────────────────────────────────────────────
	--    Set up the watcher FIRST so it catches anything Roblox's avatar loader
	--    injects during the task.wait() inside the loop below.
	local accessoryConn
	accessoryConn = character.ChildAdded:Connect(function(child)
		if child:IsA("Accessory") and not child:GetAttribute(TEMPLATE_TAG) then
			child:Destroy()
		end
	end)
	if not playerConnections[player] then playerConnections[player] = {} end
	table.insert(playerConnections[player], accessoryConn)
	task.delay(15, function() accessoryConn:Disconnect() end)

	-- §LD-CM2 fix: skip accessories that other systems have explicitly
	-- tagged as theirs (e.g. weapons attached by VisualEquipmentManager).
	-- The killer watcher above already respects this attribute; the hard
	-- wipe must too, otherwise weapons get destroyed every time we
	-- re-apply the template (gender change, respec, anything that calls
	-- ApplyTemplate after the initial spawn). Pablo saw exactly this
	-- after using the testing UI to flip gender — the staff was wiped.
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and not child:GetAttribute(TEMPLATE_TAG) then
			child:Destroy()
		end
	end
	for _, child in ipairs(template:GetChildren()) do
		if child:IsA("Accessory") then
			-- Read weld values from the template's existing AccessoryWeld BEFORE
			-- cloning. Roblox injects this weld at runtime into the template model
			-- with the correct C0/C1 — tune by editing HairAttachment.CFrame in Studio.
			-- Fallback to the attachment CFrame if no weld exists yet.
			local templateHandle = child:FindFirstChild("Handle")
			local templateWeld   = templateHandle and templateHandle:FindFirstChild("AccessoryWeld")
			local templateAtt    = templateHandle and templateHandle:FindFirstChildOfClass("Attachment")
			local c0 = (templateWeld and templateWeld.C0)
			         or (templateAtt and templateAtt.CFrame)
			         or CFrame.identity
			local c1 = (templateWeld and templateWeld.C1) or CFrame.identity

			local clone = child:Clone()
			clone:SetAttribute(TEMPLATE_TAG, true)

			-- Destroy all pre-existing AccessoryWelds from the clone so that
			-- Roblox creates exactly one when we parent it to the character.
			local cloneHandle = clone:FindFirstChild("Handle")
			if cloneHandle then
				for _, w in ipairs(cloneHandle:GetChildren()) do
					if w.Name == "AccessoryWeld" then w:Destroy() end
				end
			end

			clone.Parent = character

			-- Wait one frame for Roblox to auto-create its single AccessoryWeld.
			-- Roblox may also re-enable AutomaticScaling during this yield, which
			-- resets Motor6D pivots — re-apply them immediately after.
			task.wait()
			humanoid.AutomaticScalingEnabled = false
			ApplyMotor6DFromTemplate(character, template)

			if cloneHandle then
				local weld = cloneHandle:FindFirstChild("AccessoryWeld")
				if weld then
					weld.Part0 = cloneHandle
					weld.Part1 = character:FindFirstChild("Head")
					weld.C0 = c0
					weld.C1 = c1
				end
			end
		end
	end

	-- ── 4) Armor skin overlay (optional) ─────────────────────────────────────
	--    If the player has a non-default skin selected and it is an Armor type,
	--    clone the armor Parts and weld each one to its character body Part.
	local skinId = cd.skinId  -- may be nil for old saves → treated as "default"
	if skinId and skinId ~= "default" then
		local skinDef = CharacterConfig.GetSkin(skinId)
		if skinDef and skinDef.type == "Armor" and skinDef.template then
			local armorModel = folder:FindFirstChild(skinDef.template)
			if armorModel then
				ApplyArmorSkin(character, armorModel)
			else
				warn(("[CharacterManager] Armor template '%s' not found"):format(skinDef.template))
			end
		end
	end

	-- Apply skin color via BodyColors (overrides the description's colors)
	CharacterManager.ApplySkinColor(player)

	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKIN COLOR
-- ═══════════════════════════════════════════════════════════

--[[
    ApplySkinColor(player)
    Reads the saved skinColor id from CharacterData and sets all six
    BodyColors slots on the player's character uniformly.
]]
function CharacterManager.ApplySkinColor(player)
	local character = player.Character
	if not character then return end

	local cd = CharacterManager.GetCharacterData(player)
	if not cd then return end

	local skinEntry = CharacterConfig.GetSkinColor(cd.skinColor)
	if not skinEntry then
		-- Fallback: first skin color in the palette
		skinEntry = CharacterConfig.SkinColors[1]
	end
	if not skinEntry then return end

	local bodyColors = character:FindFirstChildOfClass("BodyColors")
	if not bodyColors then
		bodyColors = Instance.new("BodyColors")
		bodyColors.Parent = character
	end

	local c = skinEntry.color
	bodyColors.HeadColor3     = c
	bodyColors.TorsoColor3    = c
	bodyColors.LeftArmColor3  = c
	bodyColors.RightArmColor3 = c
	bodyColors.LeftLegColor3  = c
	bodyColors.RightLegColor3 = c
end

-- ═══════════════════════════════════════════════════════════
-- GENDERED CLASS TITLE
-- ═══════════════════════════════════════════════════════════

function CharacterManager.GetClassTitle(player, className)
	local data = PlayerDataManager.GetData(player)
	local gender = data and data.Account and data.Account.CharacterData and data.Account.CharacterData.gender
	return CharacterConfig.GetClassTitle(className, gender)
end

-- ═══════════════════════════════════════════════════════════
-- CHARACTER CREATION SAVE
-- ═══════════════════════════════════════════════════════════

local function SaveCharacterCreation(player, gender, preset, skinColor)
	local data = PlayerDataManager.GetData(player)
	if not data then
		warn("[CharacterManager] No data for", player.Name)
		return false
	end

	-- Validate
	if not CharacterConfig.IsValidGender(gender) then
		warn("[CharacterManager] Invalid gender from", player.Name, ":", tostring(gender))
		return false
	end
	if not CharacterConfig.IsValidPreset(preset) then
		-- Default to preset 1 for forward-compat
		preset = 1
	end
	if not CharacterConfig.IsValidSkinColor(skinColor) then
		skinColor = CharacterConfig.SkinColors[1].id
	end

	-- Save
	data.Account.CharacterData.gender    = gender
	data.Account.CharacterData.preset    = preset
	data.Account.CharacterData.skinColor = skinColor
	data.Account.CharacterData.isCreated = true

	print("[CharacterManager]", player.Name, "→ Created:", gender, "Skin:", skinColor)
	NetworkManager.FireClient(player, "CharacterCreationSaved", {
		gender    = gender,
		preset    = preset,
		skinColor = skinColor,
	})

	-- Apply immediately if the character already exists
	CharacterManager.ApplyTemplate(player)

	-- Also apply cosmetic visuals (outfit colors)
	if CosmeticManager then
		CosmeticManager.ApplyPlayerVisuals(player)
	end

	return true
end

-- ═══════════════════════════════════════════════════════════
-- FIRST-LOGIN CHECK
-- ═══════════════════════════════════════════════════════════

local function CheckFirstLogin(player)
	local data
	for _ = 1, 20 do
		data = PlayerDataManager.GetData(player)
		if data then break end
		task.wait(0.5)
	end

	if not data then
		warn("[CharacterManager] Timed out waiting for data –", player.Name)
		return
	end

	if not data.Account.CharacterData or not data.Account.CharacterData.isCreated then
		print("[CharacterManager]", player.Name, "→ First login, requesting character creation")
		NetworkManager.FireClient(player, "CharacterCreationRequired", {
			genders    = CharacterConfig.Genders,
			skinColors = CharacterConfig.SkinColors,
		})
	else
		CharacterManager.ApplyTemplate(player)
	end
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function CharacterManager.Init()
	-- Force R6 for all players so CharacterMesh works.
	-- CharacterMesh is a no-op on R15 characters.
	-- NOTE: StarterPlayer.CharacterRigType is not scriptable at runtime;
	-- configure it via Game Settings → Avatar in Studio instead.
	local ok, rigType = pcall(function()
		return StarterPlayer.CharacterRigType
	end)
	if ok and rigType ~= Enum.HumanoidRigType.R6 then
		local setOk = pcall(function()
			StarterPlayer.CharacterRigType = Enum.HumanoidRigType.R6
		end)
		if setOk then
			print("[CharacterManager] Forced StarterPlayer.CharacterRigType = R6")
		else
			warn("[CharacterManager] Cannot set CharacterRigType at runtime — please set Avatar type to R6 in Game Settings.")
		end
	elseif not ok then
		warn("[CharacterManager] CharacterRigType not accessible — please ensure Avatar type is R6 in Game Settings.")
	end

	NetworkManager.GetEvent("CharacterCreationRequired")
	NetworkManager.GetEvent("CharacterCreationSaved")
	NetworkManager.GetEvent("CharacterCreationComplete")
	NetworkManager.GetEvent("RequestCharacterStatus")
	NetworkManager.GetEvent("RequestCharacterCreationCheck")

	-- Client submission
	NetworkManager.OnClientEvent("CharacterCreationComplete", function(player, payload)
		if type(payload) ~= "table" then return end
		SaveCharacterCreation(player, payload.gender, payload.preset, payload.skinColor)
	end)

	-- Client requests its creation status (fixes race when UI mounts late)
	NetworkManager.OnClientEvent("RequestCharacterStatus", function(player)
		local data = PlayerDataManager.GetData(player)
		if not data then return end
		if not data.Account.CharacterData or not data.Account.CharacterData.isCreated then
			NetworkManager.FireClient(player, "CharacterCreationRequired", {
				genders    = CharacterConfig.Genders,
				skinColors = CharacterConfig.SkinColors,
			})
		end
	end)

	-- Also handle RequestCharacterCreationCheck (client-side alias)
	NetworkManager.OnClientEvent("RequestCharacterCreationCheck", function(player)
		local data = PlayerDataManager.GetData(player)
		if not data then return end
		if not data.Account.CharacterData or not data.Account.CharacterData.isCreated then
			NetworkManager.FireClient(player, "CharacterCreationRequired", {
				genders    = CharacterConfig.Genders,
				skinColors = CharacterConfig.SkinColors,
			})
		end
	end)

	-- Lazy-load CosmeticManager
	task.spawn(function()
		local cmMod = Modules:FindFirstChild("CosmeticManager")
		if cmMod then
			CosmeticManager = require(cmMod)
		end
	end)

	-- Clean up connections when a player leaves
	Players.PlayerRemoving:Connect(function(player)
		for _, conn in ipairs(playerConnections[player] or {}) do
			conn:Disconnect()
		end
		playerConnections[player] = nil
	end)

	Players.PlayerAdded:Connect(function(player)
		CheckFirstLogin(player)
		-- Re-apply on every respawn
		local charAddedConn = player.CharacterAdded:Connect(function()
			task.wait(0.5)
			CharacterManager.ApplyTemplate(player)
		end)
		if not playerConnections[player] then playerConnections[player] = {} end
		table.insert(playerConnections[player], charAddedConn)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			CheckFirstLogin(player)
			local charAddedConn = player.CharacterAdded:Connect(function()
				task.wait(0.5)
				CharacterManager.ApplyTemplate(player)
			end)
			if not playerConnections[player] then playerConnections[player] = {} end
			table.insert(playerConnections[player], charAddedConn)
		end)
	end

	print("[CharacterManager] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC GETTERS
-- ═══════════════════════════════════════════════════════════

function CharacterManager.GetCharacterData(player)
	local data = PlayerDataManager.GetData(player)
	return data and data.Account and data.Account.CharacterData
end

function CharacterManager.IsCreated(player)
	local cd = CharacterManager.GetCharacterData(player)
	return cd ~= nil and cd.isCreated == true
end

function CharacterManager.GetGender(player)
	local cd = CharacterManager.GetCharacterData(player)
	return cd and cd.gender
end

function CharacterManager.GetPreset(player)
	local cd = CharacterManager.GetCharacterData(player)
	return cd and cd.preset
end

function CharacterManager.GetSkinColorId(player)
	local cd = CharacterManager.GetCharacterData(player)
	return cd and cd.skinColor
end

return CharacterManager
