-- ServerScriptService/Modules/PlayerDataManager/PlayerBonusSystem

local PlayerBonusSystem = {}

local Modules = script.Parent.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))

-- Set by PlayerDataManager
PlayerBonusSystem.PlayerDataManager = nil
PlayerBonusSystem.GetDataStore = nil

-- Optional: BonusManager (source-separated aggregation)
local BonusManager = nil

--============================================
-- INITIALIZATION
--============================================
function PlayerBonusSystem.Init()
	-- Try to load BonusManager if available
	local bmMod = Modules:FindFirstChild("BonusManager")
	if bmMod then BonusManager = require(bmMod) end

	print("[PlayerBonusSystem] Initialized" .. (BonusManager and " (BonusManager active)" or ""))
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
	if BonusManager then
		-- Route through BonusManager: build the weapon bonus table, set it as a source
		local weaponBonuses = {}
		local weaponInstance = PlayerBonusSystem.PlayerDataManager.GetEquippedWeapon(player)
		if weaponInstance and weaponInstance.bonuses then
			for _, bonus in ipairs(weaponInstance.bonuses) do
				local statName = BONUS_STAT_MAPPING[bonus.stat]
				if statName then
					weaponBonuses[statName] = (weaponBonuses[statName] or 0) + bonus.value
				end
			end
		end
		BonusManager.SetSourceBonuses(player, "weapon", weaponBonuses)

		-- Update health if bonusHealth changed
		if player.Character then
			local StatSystem = PlayerBonusSystem.PlayerDataManager.GetSystems().Stat
			StatSystem.ApplyHealthToCharacter(player, player.Character)
		end
		return
	end

	-- Fallback: direct write (BonusManager not loaded)
	local playerDataStore = PlayerBonusSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return end

	-- Reset all known weapon bonus stats to 0 (create if missing)
	for _, statName in ipairs(WEAPON_BONUS_STATS) do
		data.Bonus[statName] = 0
	end

	local weaponInstance = PlayerBonusSystem.PlayerDataManager.GetEquippedWeapon(player)
	if not weaponInstance or not weaponInstance.bonuses then return end

	for _, bonus in ipairs(weaponInstance.bonuses) do
		local statName = BONUS_STAT_MAPPING[bonus.stat]
		if statName then
			data.Bonus[statName] = (data.Bonus[statName] or 0) + bonus.value
		end
	end

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

--============================================
-- ARMOR BONUS APPLICATION
--============================================
local ArmorManagerRef = nil

function PlayerBonusSystem.ApplyArmorBonuses(player)
	if not BonusManager then return end

	-- Lazy-require to avoid circular dependency (ArmorManager → PlayerDataManager → this)
	if not ArmorManagerRef then
		local mod = Modules:FindFirstChild("ArmorManager")
		if mod then ArmorManagerRef = require(mod) end
	end
	if not ArmorManagerRef then return end

	local armorBonuses = {}
	local stats = ArmorManagerRef.GetCalculatedStats(player)

	-- Armor-level bonusHealth (scales with level/tier)
	if stats.bonusHealth and stats.bonusHealth > 0 then
		armorBonuses["BonusHealth"] = stats.bonusHealth
	end

	-- Random roll bonuses (same stat mapping as weapons)
	if stats.bonuses then
		for _, bonus in ipairs(stats.bonuses) do
			local statName = BONUS_STAT_MAPPING[bonus.stat]
			if statName then
				armorBonuses[statName] = (armorBonuses[statName] or 0) + bonus.value
			end
		end
	end

	BonusManager.SetSourceBonuses(player, "armor", armorBonuses)

	-- Refresh HP on character if bonusHealth changed
	if player.Character then
		local StatSystem = PlayerBonusSystem.PlayerDataManager.GetSystems().Stat
		StatSystem.ApplyHealthToCharacter(player, player.Character)
	end
end

function PlayerBonusSystem.RefreshArmorStats(player)
	PlayerBonusSystem.ApplyArmorBonuses(player)
end

return PlayerBonusSystem