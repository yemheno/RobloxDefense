-- ServerScriptService/Modules/NPCManager/init.lua
--[[
    Core NPC system.
    
    Responsibilities:
      • Spawn NPC models from NPCRegistry definitions.
      • Handle proximity-based interaction (player walks up, presses E / clicks).
      • Route interaction to the correct handler submodule (Shop, Quest, Lore, Teleport).
      • Play passive idle animations on NPC humanoids.
      • Clean up NPC instances when no longer needed.
    
    Architecture:
      NPCManager (this file)
        ├── NPCRegistry        – NPC definitions (name, type, position, dialog, etc.)
        ├── ShopHandler        – Opens/runs shop UI for shop NPCs
        ├── QuestHandler       – Mission/quest dialogue + state
        ├── LoreHandler        – Lore / story dialogue
        └── TeleportHandler    – Teleport-type NPCs
    
    Network events:
      NPCInteract     (client → server)  { npcId }
      NPCDialogue     (server → client)  { npcId, dialogueData, ... }
      NPCShopOpen     (server → client)  { npcId, shopData }
      NPCQuestOffer   (server → client)  { npcId, questData }
      NPCTeleportOffer(server → client)  { npcId, destinations }
      NPCResponse     (client → server)  { npcId, response, ... }
]]

local NPCManager = {}

local Players = game:GetService("Players")

local SSS = game:GetService("ServerScriptService")
local SharedModules = SSS:WaitForChild("Modules")
local NetworkManager = nil  -- lazy

-- Sub-modules (lazy-loaded in Init)
local NPCRegistry          = nil
local ShopHandler          = nil
local QuestHandler         = nil
local LoreHandler          = nil
local TeleportHandler      = nil
local MatchmakingHandler   = nil
local WeaponSmithHandler   = nil

-- ── Runtime state ─────────────────────────────────────────
local spawnedNPCs  = {}   -- [npcId] = { model, definition, ... }
local npcFolder    = nil  -- workspace.NPCs folder

-- Interaction range (studs) — player must be within this to interact
local INTERACT_RANGE = 12

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

--[[  deps (optional table):
      SceneManager  — lobby-specific scene switcher; nil in places with no scenes
      npcs          — array of NPC definitions from the place's own NPC registry
                      (e.g. LobbyNPCRegistry). When nil, no NPCs are spawned.
]]--
function NPCManager.Init(deps)
	deps = deps or {}
	NetworkManager  = require(SharedModules:WaitForChild("NetworkManager"))
	NPCRegistry           = require(script:WaitForChild("NPCRegistry"))
	ShopHandler           = require(script:WaitForChild("ShopHandler"))
	QuestHandler          = require(script:WaitForChild("QuestHandler"))
	LoreHandler           = require(script:WaitForChild("LoreHandler"))
	TeleportHandler       = require(script:WaitForChild("TeleportHandler"))
	MatchmakingHandler    = require(script:WaitForChild("MatchmakingHandler"))
	WeaponSmithHandler    = require(script:WaitForChild("WeaponSmithHandler"))

	-- Feed place-specific NPC definitions into the registry.
	-- If deps.npcs is nil or empty, NPCRegistry stays empty → nothing spawns.
	if deps.npcs then
		NPCRegistry.SetNPCs(deps.npcs)
	end

	-- Initialize submodules (pass place-specific deps through)
	ShopHandler.Init(NPCManager, NetworkManager)
	QuestHandler.Init(NPCManager, NetworkManager)
	LoreHandler.Init(NPCManager, NetworkManager)
	TeleportHandler.Init(NPCManager, NetworkManager, deps.SceneManager)
	MatchmakingHandler.Init(NPCManager, NetworkManager, deps.MatchmakingManager)
	WeaponSmithHandler.Init(NPCManager, NetworkManager)

	-- Network events
	NetworkManager.GetEvent("NPCInteract")
	NetworkManager.GetEvent("NPCDialogue")
	NetworkManager.GetEvent("NPCShopOpen")
	NetworkManager.GetEvent("NPCQuestOffer")
	NetworkManager.GetEvent("NPCTeleportOffer")
	NetworkManager.GetEvent("NPCResponse")
	NetworkManager.GetEvent("NPCProximity")       -- server → client (show interact prompt)

	-- Listen for interaction requests
	NetworkManager.OnClientEvent("NPCInteract", function(player, data)
		if data and data.npcId then
			NPCManager.HandleInteraction(player, data.npcId)
		end
	end)

	-- Listen for responses (dialog choices, shop purchases, quest accept, etc.)
	NetworkManager.OnClientEvent("NPCResponse", function(player, data)
		if data and data.npcId then
			NPCManager.HandleResponse(player, data)
		end
	end)

	-- Create NPC folder in workspace
	npcFolder = workspace:FindFirstChild("NPCs")
	if not npcFolder then
		npcFolder = Instance.new("Folder")
		npcFolder.Name = "NPCs"
		npcFolder.Parent = workspace
	end

	-- Spawn all registered NPCs
	NPCManager.SpawnAllNPCs()

end

-- ═══════════════════════════════════════════════════════════
-- NPC SPAWNING
-- ═══════════════════════════════════════════════════════════

function NPCManager.SpawnAllNPCs()
	for _, def in ipairs(NPCRegistry.GetAll()) do
		NPCManager.SpawnNPC(def)
	end
end

function NPCManager.SpawnNPC(def)
	if spawnedNPCs[def.id] then
		warn("[NPCManager] NPC already spawned:", def.id)
		return
	end

	-- Create a simple NPC model.
	-- In production, you'd clone a model from ReplicatedStorage / ServerStorage.
	-- For now we create a placeholder humanoid rig.
	local model = NPCManager.CreateNPCModel(def)
	model.Parent = npcFolder

	spawnedNPCs[def.id] = {
		model      = model,
		definition = def,
	}

	print("[NPCManager] Spawned NPC:", def.id, "(" .. def.name .. ") at", tostring(def.position))
end

function NPCManager.CreateNPCModel(def)
	-- Placeholder NPC model (a simple Part + Humanoid + BillboardGui name tag).
	-- Replace with proper R15 character clones in production.
	local model = Instance.new("Model")
	model.Name = "NPC_" .. def.id

	-- Root part
	local rootPart = Instance.new("Part")
	rootPart.Name       = "HumanoidRootPart"
	rootPart.Size       = Vector3.new(2, 2, 1)
	rootPart.Anchored   = true
	rootPart.CanCollide = true
	rootPart.Transparency = 1
	rootPart.CFrame     = CFrame.new(def.position)
	rootPart.Parent     = model

	-- Torso (visible part)
	local torso = Instance.new("Part")
	torso.Name       = "Torso"
	torso.Size       = Vector3.new(2, 2, 1)
	torso.Anchored   = true
	torso.CanCollide = false
	torso.CFrame     = CFrame.new(def.position)
	torso.BrickColor = def.color or BrickColor.new("Medium stone grey")
	torso.Parent     = model

	-- Head
	local head = Instance.new("Part")
	head.Name        = "Head"
	head.Shape       = Enum.PartType.Ball
	head.Size        = Vector3.new(1.2, 1.2, 1.2)
	head.Anchored    = true
	head.CanCollide  = false
	head.CFrame      = CFrame.new(def.position + Vector3.new(0, 1.8, 0))
	head.BrickColor  = BrickColor.new("Light orange")
	head.Parent      = model

	-- Humanoid (for animations in the future)
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth    = 100
	humanoid.Health       = 100
	humanoid.WalkSpeed    = 0  -- NPCs don't walk by default
	humanoid.Parent       = model

	model.PrimaryPart = rootPart

	-- Set attributes for the client to read
	rootPart:SetAttribute("IsNPC", true)
	rootPart:SetAttribute("NPCId", def.id)
	rootPart:SetAttribute("NPCName", def.name)
	rootPart:SetAttribute("NPCType", def.npcType)

	-- Name tag billboard
	local billboard = Instance.new("BillboardGui")
	billboard.Name        = "NameTag"
	billboard.Adornee     = head
	billboard.Size        = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance  = 40
	billboard.Parent      = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size                   = UDim2.fromScale(1, 0.6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                   = def.name
	nameLabel.TextColor3             = Color3.fromRGB(255, 220, 100)
	nameLabel.Font                   = Enum.Font.GothamBold
	nameLabel.TextScaled             = true
	nameLabel.Parent                 = billboard

	local typeLabel = Instance.new("TextLabel")
	typeLabel.Size                   = UDim2.fromScale(1, 0.4)
	typeLabel.Position               = UDim2.fromScale(0, 0.6)
	typeLabel.BackgroundTransparency = 1
	typeLabel.Text                   = "<" .. (def.title or def.npcType) .. ">"
	typeLabel.TextColor3             = Color3.fromRGB(180, 180, 180)
	typeLabel.Font                   = Enum.Font.Gotham
	typeLabel.TextScaled             = true
	typeLabel.Parent                 = billboard

	return model
end

-- ═══════════════════════════════════════════════════════════
-- INTERACTION
-- ═══════════════════════════════════════════════════════════

function NPCManager.HandleInteraction(player, npcId)
	local npcData = spawnedNPCs[npcId]
	if not npcData then
		warn("[NPCManager] NPC not found:", npcId)
		return
	end

	-- Range check
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local npcRoot = npcData.model:FindFirstChild("HumanoidRootPart")
	if not npcRoot then return end

	local distance = (rootPart.Position - npcRoot.Position).Magnitude
	if distance > INTERACT_RANGE then
		warn("[NPCManager]", player.Name, "too far from NPC", npcId, "- dist:", math.floor(distance))
		return
	end

	-- Route to handler based on NPC type
	local def = npcData.definition
	local npcType = def.npcType

	print("[NPCManager]", player.Name, "interacting with", def.name, "(type:", npcType, ")")

	if npcType == "Shop" then
		ShopHandler.OnInteract(player, def)
	elseif npcType == "Quest" then
		QuestHandler.OnInteract(player, def)
	elseif npcType == "Lore" then
		LoreHandler.OnInteract(player, def)
	elseif npcType == "Teleport" then
		TeleportHandler.OnInteract(player, def)
	elseif npcType == "Matchmaking" then
		MatchmakingHandler.OnInteract(player, def)
	elseif npcType == "WeaponSmith" then
		WeaponSmithHandler.OnInteract(player, def)
	else
		-- Default: show generic dialogue if available
		if def.dialogue then
			LoreHandler.OnInteract(player, def)
		else
			warn("[NPCManager] No handler for NPC type:", npcType)
		end
	end
end

function NPCManager.HandleResponse(player, data)
	if type(data) ~= "table" then return end
	local npcData = spawnedNPCs[data.npcId]
	if not npcData then return end

	-- §AGX/X29: responses skipped the range check that interacts have.
	-- Doubled range so walking a few steps with the dialog open still works.
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local npcRoot = npcData.model and npcData.model:FindFirstChild("HumanoidRootPart")
	if not rootPart or not npcRoot then return end
	if not ((rootPart.Position - npcRoot.Position).Magnitude <= INTERACT_RANGE * 2) then return end

	local npcType = npcData.definition.npcType

	if npcType == "Shop" then
		ShopHandler.OnResponse(player, npcData.definition, data)
	elseif npcType == "Quest" then
		QuestHandler.OnResponse(player, npcData.definition, data)
	elseif npcType == "Lore" then
		LoreHandler.OnResponse(player, npcData.definition, data)
	elseif npcType == "Teleport" then
		TeleportHandler.OnResponse(player, npcData.definition, data)
	elseif npcType == "Matchmaking" then
		MatchmakingHandler.OnResponse(player, npcData.definition, data)
	elseif npcType == "WeaponSmith" then
		WeaponSmithHandler.OnResponse(player, npcData.definition, data)
	end
end

-- ═══════════════════════════════════════════════════════════
-- QUERIES
-- ═══════════════════════════════════════════════════════════

function NPCManager.GetNPCRegistry()
	return NPCRegistry
end

return NPCManager
