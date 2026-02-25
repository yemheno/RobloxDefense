-- ServerScriptService/Modules/PlayerDataManager/PlayerBonusSystem

local PlayerBonusSystem = {}

local Modules = script.Parent.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))

-- Set by PlayerDataManager
PlayerBonusSystem.PlayerDataManager = nil
PlayerBonusSystem.GetDataStore = nil

--============================================
-- INITIALIZATION
--============================================
function PlayerBonusSystem.Init()
	print("[PlayerBonusSystem] Initialized")
end

--============================================
-- BONUS STATS ACCESS
--============================================
function PlayerBonusSystem.GetBonus(player, bonusName)
	local playerDataStore = PlayerBonusSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return 0 end

	return data.Bonus[bonusName] or 0
end

function PlayerBonusSystem.SetBonus(player, bonusName, value)
	local playerDataStore = PlayerBonusSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return false end

	data.Bonus[bonusName] = value
	return true
end

function PlayerBonusSystem.ModifyBonus(player, bonusName, delta)
	local playerDataStore = PlayerBonusSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return false end

	data.Bonus[bonusName] = (data.Bonus[bonusName] or 0) + delta
	return true
end

--============================================
-- SYSTEM STATS ACCESS
-- NOTE: SystemStats have been replaced by derived stats (GetTotalStat).
-- These functions now operate on the Bonus table, which holds flat modifiers
-- applied on top of primary-derived values (used by test events and buffs).
--============================================
function PlayerBonusSystem.GetSystemStat(player, statName)
	local playerDataStore = PlayerBonusSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return nil end

	return data.Bonus[statName]
end

function PlayerBonusSystem.SetSystemStat(player, statName, value)
	local playerDataStore = PlayerBonusSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return false end

	data.Bonus[statName] = value
	return true
end

--============================================
-- WEAPON BONUS MAPPING
--============================================
local BONUS_STAT_MAPPING = {
	flatAttack = "FlatAttack",
	attackSpeed = "AttackSpeed",
	skillDamage = "SkillDamage",
	thorns = "Thorns",
	lifesteal = "Lifesteal",
	cooldownReduction = "CooldownReduction",
	determination = "Determination",
	rage = "Rage",
	mana = "Mana",
	focus = "Focus",
	tauntDuration = "TauntDuration",
	bonusHealth = "BonusHealth",
	damageReduction = "DamageReduction",
	movementSpeed = "MovementSpeed",
	aoeSize = "AoESize",
	critChance = "CritChance",
	critDamage = "CritDamage",
}

function PlayerBonusSystem.BonusStatMapping(weaponStat)
	return BONUS_STAT_MAPPING[weaponStat]
end

--============================================
-- WEAPON BONUS APPLICATION
--============================================
local WEAPON_BONUS_STATS = {
	"FlatAttack", "AttackSpeed", "SkillDamage", "Thorns",
	"Lifesteal", "CooldownReduction", "Determination",
	"Rage", "Mana", "Focus", "TauntDuration",
	"BonusHealth", "DamageReduction", "MovementSpeed", "AoESize",
	"CritChance", "CritDamage",   -- flat bonuses on top of PRE-derived values
}

function PlayerBonusSystem.ApplyWeaponBonuses(player)
	local playerDataStore = PlayerBonusSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return end

	-- Reset weapon-related bonuses to 0
	for _, statName in ipairs(WEAPON_BONUS_STATS) do
		if data.Bonus[statName] ~= nil then
			data.Bonus[statName] = 0
		end
	end

	-- Get equipped weapon
	local weaponInstance = PlayerBonusSystem.PlayerDataManager.GetEquippedWeapon(player)
	if not weaponInstance or not weaponInstance.bonuses then
		return
	end

	-- Apply each bonus
	for _, bonus in ipairs(weaponInstance.bonuses) do
		local statName = BONUS_STAT_MAPPING[bonus.stat]
		if statName and data.Bonus[statName] ~= nil then
			data.Bonus[statName] = data.Bonus[statName] + bonus.value
		end
	end

	-- Update health if bonusHealth changed
	if player.Character then
		local StatSystem = PlayerBonusSystem.PlayerDataManager.GetSystems().Stat
		StatSystem.ApplyHealthToCharacter(player, player.Character)
	end
end

-- ApplyWeaponCritBonuses is no longer needed.
-- CritChance and CritDamage are flat bonus entries in the Bonus table
-- (on top of PRE-derived values) and are already handled by ApplyWeaponBonuses
-- via BONUS_STAT_MAPPING { critChance="CritChance", critDamage="CritDamage" }.

function PlayerBonusSystem.RefreshWeaponStats(player)
	PlayerBonusSystem.ApplyWeaponBonuses(player)
end

return PlayerBonusSystem