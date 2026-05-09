-- ServerScriptService/Modules/VisualEquipmentManager.lua
--[[
    Handles the visual attachment of weapon/armor Accessories to player characters.

    Architecture:
      • Weapon accessories are stored in ServerStorage.Weapons/
        named "[ClassName]_w[slot]"  (e.g. "Arcanist_w1", "Arcanist_w2")
      • Armor accessories are stored in ServerStorage.Armors/  (future)
        named "[ClassName]_a[slot]"  (e.g. "Arcanist_a1")
      • Each weapon definition carries a `weaponSlot` integer (1 or 2).
      • Cloning a Roblox Accessory directly into the character model causes
        the engine to auto-attach it via the built-in AttachmentPoint — no
        manual welding is needed.  Grip offsets are baked into the asset.

    Adding a new weapon accessory:
      1. Export the Accessory from Studio to
         src/shared/ServerStorage/Weapons/[ClassName]_w[slot].rbxmx
      2. Rojo syncs it automatically — no code changes required.

    Adding a new armor accessory (future):
      1. Export to src/shared/ServerStorage/Armors/[ClassName]_a[slot].rbxmx
      2. Call AttachClassArmor(player, className, armorSlot) at equip time.
]]

local VisualEquipmentManager = {}

local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

-- Accessory folder references set in Init
local WeaponsFolder = nil  -- ServerStorage.Weapons
local ArmorsFolder  = nil  -- ServerStorage.Armors (future)

-- Per-player tracking: what is currently equipped visually
-- [userId] = {
--   weaponAccessory = Instance|nil,
--   weaponClass     = string|nil,
--   weaponSlot      = number|nil,
--   armorAccessory  = Instance|nil,
--   armorClass      = string|nil,
--   armorSlot       = number|nil,
-- }
local playerVisuals = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function VisualEquipmentManager.Init()
	WeaponsFolder = ServerStorage:WaitForChild("Weapons", 10)
	if not WeaponsFolder then
		warn("[VisualEquipmentManager] ServerStorage.Weapons not found!")
	end

	-- Armors folder loaded when armor assets are available
	ArmorsFolder = ServerStorage:FindFirstChild("Armors")

	-- Cleanup on player leaving
	Players.PlayerRemoving:Connect(function(player)
		VisualEquipmentManager.ClearAll(player)
		playerVisuals[player.UserId] = nil
	end)

	-- Re-attach on respawn
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(_character)
			task.wait(0.5)
			VisualEquipmentManager.ReattachAll(player)
		end)
	end)

	-- Handle players already in game
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			task.spawn(function()
				task.wait(0.2)
				VisualEquipmentManager.ReattachAll(player)
			end)
		end
		player.CharacterAdded:Connect(function(_character)
			task.wait(0.5)
			VisualEquipmentManager.ReattachAll(player)
		end)
	end

	print("[VisualEquipmentManager] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- INTERNAL HELPERS
-- ═══════════════════════════════════════════════════════════

local function GetVisuals(player)
	local uid = player.UserId
	if not playerVisuals[uid] then
		playerVisuals[uid] = {}
	end
	return playerVisuals[uid]
end

-- §LD-VE1: stay exempt from CharacterManager's accessory-killer watcher.
-- Match the same magic string CharacterManager uses internally.
local CHAR_TEMPLATE_TAG = "_TemplateCharacterMesh"

-- §LD-VE3: the Roblox Accessory engine actively destroys/replaces
-- auto-managed `AccessoryWeld` instances when AccessoryType doesn't
-- agree with the body part the engine wants to attach to. Pablo's
-- Arcanist_w1 has AccessoryType=Hat (default), so the engine tries
-- to weld it to the Head, fails (no HatAttachment in the Handle),
-- then *destroys* whatever weld it created or finds — including any
-- weld we install. Workaround: use a CUSTOM-NAMED Weld
-- ("ManualGripWeld") so the engine doesn't recognise it as its own
-- and leaves it alone. We also stamp an attribute on the weld so
-- our re-watcher can recognise it.
local CUSTOM_WELD_NAME = "ManualGripWeld"

-- Map of accessory Handle attachment NAME → matching body part name.
-- Used both to resolve where to weld AND to look up the body part's
-- own attachment (when present) so we can mirror the auto-attach
-- math (Part0.CFrame * C0 == Part1.CFrame * C1, with C0=handleAtt
-- and C1=bodyAtt).
local ATTACHMENT_TARGET = {
	RightGripAttachment  = { partName = "Right Arm" },
	LeftGripAttachment   = { partName = "Left Arm"  },
	HatAttachment        = { partName = "Head"      },
	HairAttachment       = { partName = "Head"      },
	FaceFrontAttachment  = { partName = "Head"      },
	FaceCenterAttachment = { partName = "Head"      },
	NeckAttachment       = { partName = "Head"      },
}

-- Hard-coded R6 fallback grip CFrames — used as C1 when the body
-- part doesn't carry a matching attachment (some custom rigs strip
-- the default ones during ApplyDescription / CharacterMesh swaps).
local R6_GRIP_FALLBACKS = {
	["Right Arm"] = CFrame.new(0, -1, 0),
	["Left Arm"]  = CFrame.new(0, -1, 0),
	["Head"]      = CFrame.new(0,  0.5, 0),
	["Torso"]     = CFrame.new(0,  0,   0),
}

--- Resolve where on the body part the grip point lives. Prefers the
--- body part's own Attachment (named like the Handle's attachment),
--- falls back to the R6 hard-coded grip offset.
local function resolveBodyAttachmentCFrame(bodyPart, attachmentName)
	if attachmentName then
		local bodyAtt = bodyPart:FindFirstChild(attachmentName)
		if bodyAtt and bodyAtt:IsA("Attachment") then
			return bodyAtt.CFrame
		end
	end
	return R6_GRIP_FALLBACKS[bodyPart.Name] or CFrame.new(0, -1, 0)
end

--- Build (or re-build) the manual grip weld on a freshly-attached
--- Accessory. Idempotent: if the weld already exists with our custom
--- name, its properties are overwritten in place; otherwise a new
--- Weld instance is created.
local function applyManualWeld(clone, character, fallbackPartName)
	local cloneHandle = clone:FindFirstChild("Handle")
	if not cloneHandle then return nil end

	local handleAtt = cloneHandle:FindFirstChildOfClass("Attachment")
	local targetMap = handleAtt and ATTACHMENT_TARGET[handleAtt.Name]
	local targetPartName = (targetMap and targetMap.partName) or fallbackPartName or "Right Arm"

	local targetPart = character:FindFirstChild(targetPartName)
	if not targetPart then
		warn("[VisualEquipmentManager] Body part not found for weld:", targetPartName)
		return nil
	end

	local c0 = (handleAtt and handleAtt.CFrame) or CFrame.identity
	local c1 = resolveBodyAttachmentCFrame(targetPart, handleAtt and handleAtt.Name)

	-- Reuse our existing custom weld if present, else create one.
	local weld = cloneHandle:FindFirstChild(CUSTOM_WELD_NAME)
	if not weld or not weld:IsA("Weld") then
		weld = Instance.new("Weld")
		weld.Name = CUSTOM_WELD_NAME
	end

	weld.Part0  = cloneHandle
	weld.Part1  = targetPart
	weld.C0     = c0
	weld.C1     = c1
	weld.Enabled = true
	weld.Parent = cloneHandle

	cloneHandle.CanCollide = false
	cloneHandle.Anchored   = false
	cloneHandle.Massless   = true

	return weld
end

--- Attach a fresh weld and stand up a watcher that re-applies it if
--- Roblox's Accessory engine destroys it. The watcher self-cleans
--- when the clone leaves the character.
local function attachWeldWithWatcher(clone, character, fallbackPartName)
	local cloneHandle = clone:FindFirstChild("Handle")
	if not cloneHandle then return end

	-- Belt-and-suspenders against AutomaticScalingEnabled flicker —
	-- CharacterManager already disables it for the first 30 s, but
	-- weapon equip can happen later (class switch, respawn) so make
	-- sure it's off here too.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function() humanoid.AutomaticScalingEnabled = false end)
	end

	-- §LD-VE4: clean up the Handle's physics. CanTouch is left at the
	-- default (true) — Pablo's working Female+Staff reference keeps it
	-- true and the TouchInterest object that Roblox auto-creates lives
	-- harmlessly alongside the AccessoryWeld; it does not replace it.
	-- The previous over-defensive CanTouch=false was changing model
	-- semantics needlessly.
	cloneHandle.CanCollide = false
	cloneHandle.Anchored   = false
	cloneHandle.Massless   = true

	-- Stamp the template tag so CharacterManager's accessory-killer
	-- watcher doesn't strip our clone (§LD-VE1).
	cloneHandle:SetAttribute(CHAR_TEMPLATE_TAG, true)
	clone:SetAttribute(CHAR_TEMPLATE_TAG, true)

	-- Apply the weld now. We always create our custom-named one
	-- (engine ignores it). If the engine ALSO created its own
	-- AccessoryWeld during the clone.Parent assignment, leave it
	-- alone — two welds at identical C0/C1 are harmless and the
	-- redundancy is what makes us robust to the Studio Rojo plugin
	-- swapping one of them out during a re-sync (§LD-VE3).
	applyManualWeld(clone, character, fallbackPartName)
	-- Diagnostic stamp: write the names + Part1 of every weld now
	-- on the Handle so we can confirm in-game what the engine did.
	for _, child in ipairs(cloneHandle:GetChildren()) do
		if child:IsA("Weld") or child:IsA("Motor6D") then
			print(string.format(
				"[VisualEquipmentManager] Handle weld inventory: %s (%s) → %s",
				child.Name, child.ClassName,
				tostring(child.Part1 and child.Part1.Name or "nil")))
		end
	end

	-- §LD-VE3 watcher: if the engine destroys our custom weld
	-- (which it shouldn't because of the unrecognised name, but the
	-- Studio Rojo plugin has been observed to swap it during a
	-- mid-session re-sync), re-apply it. Disconnects when the clone
	-- leaves the character so we don't leak a connection.
	local handleConn
	local ancestryConn
	handleConn = cloneHandle.ChildRemoved:Connect(function(child)
		if child:IsA("Weld") and child.Name == CUSTOM_WELD_NAME then
			if cloneHandle.Parent and clone.Parent == character then
				applyManualWeld(clone, character, fallbackPartName)
			end
		end
	end)
	ancestryConn = clone.AncestryChanged:Connect(function(_, parent)
		if parent ~= character then
			if handleConn then handleConn:Disconnect(); handleConn = nil end
			if ancestryConn then ancestryConn:Disconnect(); ancestryConn = nil end
		end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- INTERNAL: ASSET RESOLUTION
-- ═══════════════════════════════════════════════════════════

--- Resolve a weapon Accessory template from ServerStorage.Weapons.
--- Naming convention: "[ClassName]_w[slot]" (e.g. "Arcanist_w1").
local function resolveWeaponTemplate(className, slot)
	if not WeaponsFolder then return nil end
	local assetName = string.format("%s_w%d", className, slot)
	local asset = WeaponsFolder:FindFirstChild(assetName)
	if not asset then
		-- Fall back to any "ClassName_w1" if the requested slot is missing.
		asset = WeaponsFolder:FindFirstChild(className .. "_w1")
	end
	return asset, assetName
end

local function resolveArmorTemplate(className, slot)
	if not ArmorsFolder then return nil end
	local assetName = string.format("%s_a%d", className, slot)
	return ArmorsFolder:FindFirstChild(assetName), assetName
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════

--- Attach the Accessory for the given class + weapon slot to the
--- player's current Character. Idempotent: clears any previously
--- attached weapon for this player first. Tracks the active class
--- and slot in `playerVisuals` so respawn / class-switch can reattach.
function VisualEquipmentManager.AttachClassWeapon(player, className, weaponSlot)
	-- §LD-VE7: aggressive logging at the very top so we can diagnose
	-- "weapon not attaching" without guessing. Every observable
	-- early-exit reason gets its own message.
	print(string.format(
		"[VisualEquipmentManager] AttachClassWeapon ENTRY: player=%s class=%s slot=%s",
		tostring(player and player.Name), tostring(className), tostring(weaponSlot)))

	if not player then warn("[VisualEquipmentManager] no player") return end
	if not className then warn("[VisualEquipmentManager] no className for", player.Name) return end
	if not weaponSlot then warn("[VisualEquipmentManager] no weaponSlot for", player.Name) return end

	-- §VEM-DEDUPE: skip if the same class+slot is already attached and
	-- the live accessory is still parented to the current character.
	-- Multiple paths converge on this function (PlayerAdded poll,
	-- CharacterAdded retry, ClassManager.SwitchClass, WeaponManager.SwitchWeapon)
	-- and racing them produced 3 clone-then-destroy cycles in 3ms in the
	-- HordeMode log. Functionally fine but wasteful and noisy. Early return
	-- on a no-op keeps the same final state without churning Accessories.
	do
		local v = playerVisuals[player.UserId]
		if v
			and v.weaponClass == className
			and v.weaponSlot == weaponSlot
			and v.weaponAccessory
			and v.weaponAccessory.Parent == player.Character
		then
			return  -- already correct; keep the live attachment
		end
	end

	-- §LD-VE8: WAIT for the character. Previously this was a hard early
	-- return — but our primary caller (WeaponManager.Init's
	-- ensureWeaponSetup) is PlayerAdded-driven and only polls for
	-- CLASS DATA, not character readiness. DataStore async loads tend
	-- to finish before Roblox finishes spawning the character, so the
	-- old "if not character then return end" path was effectively a
	-- silent drop on first spawn. Hair worked because CharacterManager
	-- triggers from CharacterAdded directly (character always present).
	-- Polling here makes AttachClassWeapon usable from either trigger.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		print(string.format(
			"[VisualEquipmentManager] Waiting for character/humanoid for %s...", player.Name))
		for attempt = 1, 50 do  -- 5 seconds total
			if not player.Parent then
				warn("[VisualEquipmentManager]", player.Name, "left during character wait")
				return
			end
			task.wait(0.1)
			character = player.Character
			humanoid  = character and character:FindFirstChildOfClass("Humanoid")
			if character and humanoid then
				print(string.format(
					"[VisualEquipmentManager] Character ready for %s after %.1fs",
					player.Name, attempt * 0.1))
				break
			end
		end
	end
	if not character or not humanoid then
		warn(string.format(
			"[VisualEquipmentManager] %s never got a character+humanoid — abandoning weapon attach",
			player.Name))
		return
	end

	-- Always clear the previous weapon before attaching a new one
	-- so swapping classes/slots doesn't leave a ghost on the model.
	VisualEquipmentManager.ClearWeapon(player)

	local template, assetName = resolveWeaponTemplate(className, weaponSlot)
	if not template then
		warn(string.format(
			"[VisualEquipmentManager] No weapon asset for %s (slot %d) in ServerStorage.Weapons",
			tostring(className), tonumber(weaponSlot) or -1))
		return
	end

	local ok, clone = pcall(function() return template:Clone() end)
	if not ok or not clone then
		warn("[VisualEquipmentManager] Failed to clone weapon", assetName, ":", clone)
		return
	end

	-- §LD-VE5: Hard sanity. The previous truncation bug meant nothing
	-- was ever logged when a weapon failed to parent — it just
	-- silently went missing. Print every step so a future "weapon
	-- not in player model" report can be diagnosed from output alone.
	print(string.format(
		"[VisualEquipmentManager] AttachClassWeapon: cloning %s for %s (slot %d)",
		assetName, player.Name, weaponSlot))

	-- §LD-VE6 fix: stamp the template-tag attribute BEFORE parenting.
	-- CharacterManager wires a 15-second character.ChildAdded watcher
	-- that destroys any Accessory without this attribute (it's how
	-- Roblox's avatar-loader-injected accessories get cleared). Setting
	-- the tag AFTER `clone.Parent = character` is too late: ChildAdded
	-- fires synchronously on the assignment, the watcher reads the
	-- (still-untagged) accessory, and instantly :Destroy()s it.
	-- Pablo's "manual paste" experiment hit the exact same path —
	-- nothing he pasted ever had the tag, so the watcher always won.
	clone:SetAttribute(CHAR_TEMPLATE_TAG, true)
	local cloneHandlePre = clone:FindFirstChild("Handle")
	if cloneHandlePre then
		cloneHandlePre:SetAttribute(CHAR_TEMPLATE_TAG, true)
	end

	-- Parent NOW. With the tag in place, the killer watcher leaves us
	-- alone; the Roblox auto-attach flow runs and the engine's own
	-- AccessoryWeld appears. Our manual weld is installed afterward
	-- as a redundancy in case the engine's weld is removed mid-session
	-- (the Studio Rojo plugin re-sync race §LD-VE3).
	clone.Parent = character

	-- §LD-VE5: verify the parent operation actually took. If the engine
	-- rejected the parent (e.g. character was destroyed mid-call), bail
	-- before we waste time welding to a dead model.
	if clone.Parent ~= character then
		warn(string.format(
			"[VisualEquipmentManager] Parent failed for %s — clone.Parent is %s, expected character",
			assetName, tostring(clone.Parent)))
		pcall(function() clone:Destroy() end)
		return
	end

	attachWeldWithWatcher(clone, character, "Right Arm")

	-- Track for future respawn / class-switch reattach.
	local v = GetVisuals(player)
	v.weaponAccessory = clone
	v.weaponClass     = className
	v.weaponSlot      = weaponSlot

	print(string.format(
		"[VisualEquipmentManager] %s attached to %s (Right Arm)",
		assetName, player.Name))
end

--- Attach the Accessory for the given class + armor slot. Currently
--- unused — armor visuals are still handled by CosmeticManager
--- material/colour swaps. Stub kept so the public surface matches the
--- module's documentation and future armor accessories can wire in
--- without an API change.
function VisualEquipmentManager.AttachClassArmor(player, className, armorSlot)
	if not player or not className or not armorSlot then return end
	if not ArmorsFolder then return end

	-- §LD-VE8: same character-wait as AttachClassWeapon.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		for _ = 1, 50 do
			if not player.Parent then return end
			task.wait(0.1)
			character = player.Character
			humanoid  = character and character:FindFirstChildOfClass("Humanoid")
			if character and humanoid then break end
		end
	end
	if not character or not humanoid then return end

	VisualEquipmentManager.ClearArmor(player)

	local template, assetName = resolveArmorTemplate(className, armorSlot)
	if not template then
		-- Armors are optional today; warn once at debug verbosity.
		return
	end

	local ok, clone = pcall(function() return template:Clone() end)
	if not ok or not clone then
		warn("[VisualEquipmentManager] Failed to clone armor", assetName, ":", clone)
		return
	end

	-- §LD-VE6: same pre-parenting tag stamp as AttachClassWeapon.
	clone:SetAttribute(CHAR_TEMPLATE_TAG, true)
	local cloneHandle = clone:FindFirstChild("Handle")
	if cloneHandle then
		cloneHandle:SetAttribute(CHAR_TEMPLATE_TAG, true)
	end

	clone.Parent = character
	attachWeldWithWatcher(clone, character, "Torso")

	local v = GetVisuals(player)
	v.armorAccessory = clone
	v.armorClass     = className
	v.armorSlot      = armorSlot
end

--- Destroy the currently-attached weapon accessory (if any) and
--- forget the tracked slot. Class+slot tracking is preserved so
--- ReattachAll can put it back on the next character spawn.
function VisualEquipmentManager.ClearWeapon(player)
	local v = playerVisuals[player.UserId]
	if not v then return end
	if v.weaponAccessory and v.weaponAccessory.Parent then
		pcall(function() v.weaponAccessory:Destroy() end)
	end
	v.weaponAccessory = nil
end

function VisualEquipmentManager.ClearArmor(player)
	local v = playerVisuals[player.UserId]
	if not v then return end
	if v.armorAccessory and v.armorAccessory.Parent then
		pcall(function() v.armorAccessory:Destroy() end)
	end
	v.armorAccessory = nil
end

--- Drop both weapon and armor accessories. Used on player removal
--- (which also wipes tracking entirely) and as a defensive reset.
function VisualEquipmentManager.ClearAll(player)
	VisualEquipmentManager.ClearWeapon(player)
	VisualEquipmentManager.ClearArmor(player)
end

--- Re-attach using the last-known class+slot the player had. Called
--- on CharacterAdded after a 0.5 s settle wait so the new character's
--- joints are wired before we start welding. No-op if the player has
--- never had a weapon attached this session.
function VisualEquipmentManager.ReattachAll(player)
	local v = playerVisuals[player.UserId]
	if not v then return end

	-- Reset live references; the old accessory died with the old
	-- character anyway, but be explicit so ClearWeapon doesn't try
	-- to :Destroy() a stale instance later.
	v.weaponAccessory = nil
	v.armorAccessory  = nil

	if v.weaponClass and v.weaponSlot then
		VisualEquipmentManager.AttachClassWeapon(player, v.weaponClass, v.weaponSlot)
	end
	if v.armorClass and v.armorSlot then
		VisualEquipmentManager.AttachClassArmor(player, v.armorClass, v.armorSlot)
	end
end

return VisualEquipmentManager