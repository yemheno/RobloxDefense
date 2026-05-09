-- ServerScriptService/Modules/ArmorManager
--[[
    Core armor equipment system — mirrors WeaponManager structure.

    Manages:
      • Starter armor assignment per class
      • Armor stat calculation (defense, bonusHealth, random bonuses)
      • Armor switching & unlocking
      • Child systems: ArmorRefinement, ArmorTierSystem, ArmorBonusSystem

    NOTE: Armor XP was removed — only weapons level up. Total weapon levels
    across all classes grant talent points (see WeaponXPSystem).
]]

local ArmorManager = {}

local Players = game:GetService("Players")

local Modules           = script.Parent
local ArmorConfig       = require(Modules:WaitForChild("ArmorConfig"))
local ArmorRegistry     = require(Modules:WaitForChild("ArmorRegistry"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
local NetworkManager    = require(Modules:WaitForChild("NetworkManager"))
-- NOTE: Armor visual attachment was removed. Body appearance is now
-- handled by CosmeticManager (color/material-based outfits).

-- Child systems (loaded in Init)
local Refinement
local TierSystem
local BonusSystem

--============================================
-- INITIALIZATION
--============================================

local initializedPlayers = {}

function ArmorManager.Init()
	Refinement  = require(script:WaitForChild("ArmorRefinement"))
	TierSystem  = require(script:WaitForChild("ArmorTierSystem"))
	BonusSystem = require(script:WaitForChild("ArmorBonusSystem"))

	-- Factory systems (EquipmentTierSystem) look for .Manager;
	-- keep .ArmorManager for any legacy direct references.
	Refinement.Manager  = ArmorManager
	TierSystem.Manager  = ArmorManager
	BonusSystem.Manager = ArmorManager
	Refinement.ArmorManager  = ArmorManager
	TierSystem.ArmorManager  = ArmorManager
	BonusSystem.ArmorManager = ArmorManager

	BonusSystem.Init()
	Refinement.Init()
	TierSystem.Init()

	-- Network events
	NetworkManager.GetEvent("ArmorEquipped")

	-- Setup starter armors with deduplication guard
	local function ensureArmorSetup(player)
		if initializedPlayers[player] then return end
		initializedPlayers[player] = true

		task.spawn(function()
			-- Wait up to 5s for PlayerDataManager to set up the player.
			for _ = 1, 50 do
				if PlayerDataManager.GetActiveClassData(player) then break end
				task.wait(0.1)
			end
			ArmorManager.EnsureStarterArmor(player)
		end)
	end

	-- Handle future joins
	Players.PlayerAdded:Connect(ensureArmorSetup)

	-- Handle players who already joined before Init ran
	for _, player in ipairs(Players:GetPlayers()) do
		ensureArmorSetup(player)
	end

	-- Clean up on player leaving
	Players.PlayerRemoving:Connect(function(player)
		initializedPlayers[player] = nil
	end)

	print("[ArmorManager] Initialized")
end

--============================================
-- ARMOR INSTANCE CREATION
--============================================
function ArmorManager.CreateArmorInstance(armorId)
	local armorDef = ArmorRegistry.GetArmor(armorId)
	if not armorDef then
		warn("[ArmorManager] Armor not found:", armorId)
		return nil
	end

	local initialBonuses = BonusSystem.RollBonuses(armorId, 1)

	return {
		armorId    = armorId,
		level      = 1,
		xp         = 0,
		refinement = 0,
		tier       = 1,
		bonuses    = initialBonuses,
	}
end

--============================================
-- STARTER ARMOR
--============================================
function ArmorManager.EnsureStarterArmor(player)
	local activeClass = PlayerDataManager.GetActiveClass(player)
	local classData   = PlayerDataManager.GetActiveClassData(player)

	if not classData then
		warn("[ArmorManager] No class data for", player.Name)
		return
	end

	-- §LD-W1 follow-up: same early-return shape as WeaponManager — for
	-- a returning player with EquippedArmor already in saved data we'd
	-- skip the ArmorEquipped echo, leaving the EquipmentUI without a
	-- snapshot until the next refresh. (No visual to attach yet — see
	-- §V2 in TODO_PARKING_LOT — but we still need the client event.)
	if classData.EquippedArmor and classData.EquippedArmor.armorId then
		NetworkManager.FireClient(player, "ArmorEquipped", {
			armorId   = classData.EquippedArmor.armorId,
			armorData = classData.EquippedArmor,
			stats     = ArmorManager.GetCalculatedStats(player),
		})
		return
	end

	local starterArmorId = ArmorRegistry.GetStarterArmorId(activeClass)
	if not starterArmorId then
		warn("[ArmorManager] No starter armor for class:", activeClass)
		return
	end

	local armorInstance = ArmorManager.CreateArmorInstance(starterArmorId)
	if armorInstance then
		classData.EquippedArmor = armorInstance
		print("[ArmorManager] Gave starter armor to", player.Name, ":", starterArmorId)

		PlayerDataManager.RefreshArmorStats(player)

		NetworkManager.FireClient(player, "ArmorEquipped", {
			armorId   = starterArmorId,
			armorData = armorInstance,
			stats     = ArmorManager.GetCalculatedStats(player),
		})
	end
end

--============================================
-- ARMOR ACCESS
--============================================
function ArmorManager.GetEquippedArmor(player, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return nil end
	return classData.EquippedArmor
end

function ArmorManager.GetEquippedArmorDef(player)
	local armorInstance = ArmorManager.GetEquippedArmor(player)
	if not armorInstance then return nil end
	return ArmorRegistry.GetArmor(armorInstance.armorId)
end

function ArmorManager.GetCalculatedStats(player)
	local armorInstance = ArmorManager.GetEquippedArmor(player)
	if not armorInstance then
		return {
			defense     = 0,
			bonusHealth = 0,
			bonuses     = {},
		}
	end

	local armorId    = armorInstance.armorId
	local level      = armorInstance.level
	local refinement = armorInstance.refinement
	local tier       = armorInstance.tier

	return {
		defense     = ArmorRegistry.CalculateDefense(armorId, level, refinement, tier),
		bonusHealth = ArmorRegistry.CalculateBonusHealth(armorId, level, tier),
		bonuses     = armorInstance.bonuses,
	}
end

--============================================
-- ARMOR SWITCHING & UNLOCKING
--============================================
function ArmorManager.SwitchArmor(player, armorId)
	local activeClass = PlayerDataManager.GetActiveClass(player)
	if not ArmorRegistry.IsArmorForClass(armorId, activeClass) then
		return false, "Armor not available for your class"
	end

	local classData = PlayerDataManager.GetActiveClassData(player)
	if not classData then return false, "No class data" end

	local ownedArmors  = classData.OwnedArmors or {}
	local armorInstance = ownedArmors[armorId]

	if not armorInstance then
		return false, "You don't own this armor"
	end

	-- Store current armor
	if classData.EquippedArmor then
		local currentId = classData.EquippedArmor.armorId
		ownedArmors[currentId] = classData.EquippedArmor
	end

	classData.EquippedArmor = armorInstance
	classData.OwnedArmors   = ownedArmors

	PlayerDataManager.RefreshArmorStats(player)

	NetworkManager.FireClient(player, "ArmorEquipped", {
		armorId   = armorId,
		armorData = armorInstance,
		stats     = ArmorManager.GetCalculatedStats(player),
	})

	print("[ArmorManager]", player.Name, "switched to:", armorId)
	return true, "Armor equipped!"
end

function ArmorManager.UnlockArmor(player, armorId)
	local activeClass = PlayerDataManager.GetActiveClass(player)
	if not ArmorRegistry.IsArmorForClass(armorId, activeClass) then
		return false, "Armor not available for your class"
	end

	local classData = PlayerDataManager.GetActiveClassData(player)
	if not classData then return false, "No class data" end

	classData.OwnedArmors = classData.OwnedArmors or {}
	if classData.OwnedArmors[armorId] then
		return false, "Armor already owned"
	end

	local armorInstance = ArmorManager.CreateArmorInstance(armorId)
	if not armorInstance then return false, "Failed to create armor" end

	classData.OwnedArmors[armorId] = armorInstance
	print("[ArmorManager]", player.Name, "unlocked:", armorId)
	return true, "Armor unlocked!"
end

function ArmorManager.GetOwnedArmors(player)
	local classData = PlayerDataManager.GetActiveClassData(player)
	if not classData then return {} end

	local result = {}

	if classData.EquippedArmor then
		local armorId = classData.EquippedArmor.armorId
		result[armorId] = {
			instance   = classData.EquippedArmor,
			equipped   = true,
			definition = ArmorRegistry.GetArmor(armorId),
		}
	end

	for armorId, instance in pairs(classData.OwnedArmors or {}) do
		if not result[armorId] then
			result[armorId] = {
				instance   = instance,
				equipped   = false,
				definition = ArmorRegistry.GetArmor(armorId),
			}
		end
	end

	return result
end

--============================================
-- EXPOSE CHILD SYSTEMS
--============================================
function ArmorManager.GetSystems()
	return {
		Refinement = Refinement,
		Tier       = TierSystem,
		Bonus      = BonusSystem,
	}
end

--============================================
-- DEBUG
--============================================
function ArmorManager.GetDebugInfo(player)
	local armorInstance = ArmorManager.GetEquippedArmor(player)
	if not armorInstance then return "No armor equipped" end

	local stats    = ArmorManager.GetCalculatedStats(player)
	local refInfo  = Refinement.GetInfo(player)
	local tierInfo = TierSystem.GetInfo(player)

	local info = {
		"=== ArmorManager Debug ===",
		"Armor: " .. armorInstance.armorId,
		"Refinement: +" .. refInfo.refinement .. " (Success: " .. refInfo.successChance .. "%)",
		"Tier: " .. tierInfo.tier .. " (DEF Bonus: +" .. tierInfo.defBonus .. "%)",
		"--- Stats ---",
		"Defense: " .. stats.defense,
		"BonusHP: " .. stats.bonusHealth,
		"--- Bonuses ---",
	}

	for i, bonus in ipairs(armorInstance.bonuses or {}) do
		table.insert(info, "  " .. i .. ". " .. bonus.stat .. ": +" .. bonus.value)
	end

	return table.concat(info, "\n")
end

return ArmorManager
