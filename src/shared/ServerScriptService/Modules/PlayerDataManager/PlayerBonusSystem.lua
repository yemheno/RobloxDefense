-- ServerScriptService/Modules/PlayerDataManager/PlayerBonusSystem
--[[
    PlayerBonusSystem
    =================
    Thin facade over BonusManager. There is exactly ONE write path into
    `data.Bonus[stat]` and it goes through BonusManager.

    Sources used here:
      • "weapon"       — written by ApplyWeaponBonuses, refreshed via RefreshWeaponStats
      • "armor"        — written by ApplyArmorBonuses, refreshed via RefreshArmorStats
      • "other"        — Set/ModifyBonus go here (debug, ad-hoc effects).
                          Anything that wants its own source key (talents, buffs,
                          accessories, achievements) should call BonusManager
                          directly so the source can be cleared independently.

    Reads return the AGGREGATED value from `data.Bonus[stat]`, which
    BonusManager.Recalculate keeps current.

    §PDM-D1: no fallback path. BonusManager is a Tier-0 dependency loaded by
    every place; if it isn't available we hard-error rather than silently
    bypass it (the old fallback wrote directly to data.Bonus and got clobbered
    by the next Recalculate — that's the V3 CODE_AUDIT race).
    §PDM-D2: GetSystemStat/SetSystemStat aliases removed — use GetBonus/SetBonus.
    §PDM-D3: SetBonus/ModifyBonus now route through BonusManager "other" source
    so direct writes survive subsequent Recalculate calls.
]]

local PlayerBonusSystem = {}

local Modules = script.Parent.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))

-- Set by PlayerDataManager
PlayerBonusSystem.PlayerDataManager = nil
PlayerBonusSystem.GetDataStore = nil

-- BonusManager is mandatory. Loaded in Init.
local BonusManager = nil

local function requireBonusManager()
	if BonusManager then return BonusManager end
	error(
		"[PlayerBonusSystem] BonusManager not loaded. This is a Tier-0 dependency — "
		.. "the place bootstrap must Load(SharedModules, 'BonusManager') before any "
		.. "module touches player bonuses.",
		2
	)
end

--============================================
-- INITIALIZATION
--============================================
function PlayerBonusSystem.Init()
	local bmMod = Modules:FindFirstChild("BonusManager")
	if bmMod then BonusManager = require(bmMod) end

	-- Don't hard-error in Init itself — the bootstrap may load BonusManager
	-- right after PlayerDataManager. We re-check at every write site instead.
end

--============================================
-- BONUS STAT READS
-- Reads the AGGREGATED total written by BonusManager.Recalculate.
-- No source-specific reads from here — use BonusManager.GetAggregatedBonus
-- directly if you need one.
--============================================
function PlayerBonusSystem.GetBonus(player, bonusName)
	local data = PlayerBonusSystem.GetDataStore()[player]
	if not data then return 0 end
	return data.Bonus[bonusName] or 0
end

--============================================
-- BONUS STAT WRITES — route through BonusManager "other" source.
-- These are the ad-hoc paths (debug, ModifySystemStat, anything that
-- doesn't fit into a named source). Talents, buffs, weapon/armor bonuses,
-- and accessories should call BonusManager.SetSourceBonus(player, <source>, ...)
-- directly with their own source key so they can be cleared independently.
--============================================
function PlayerBonusSystem.SetBonus(player, bonusName, value)
	if not PlayerBonusSystem.GetDataStore()[player] then return false end
	local bm = requireBonusManager()
	bm.SetSourceBonus(player, "other", bonusName, value)
	return true
end

function PlayerBonusSystem.ModifyBonus(player, bonusName, delta)
	if not PlayerBonusSystem.GetDataStore()[player] then return false end
	local bm = requireBonusManager()
	bm.ModifySourceBonus(player, "other", bonusName, delta)
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
	-- §T0P2/X23: rage row deleted (pre-rework resource name).
	-- §AGX/D-FIX2: the X23 note claimed no registry rolls mana/focus — the
	-- Arcanist/Hunter weapon pools do, and LifeSteward gear rolls
	-- lifeEnergy, so those rolls were silently dropped. Pre-rework names
	-- map onto the current class resource (all flat max-pool points,
	-- same unit as the "+N Aether/Killer Instinct" talent nodes);
	-- ResourceManager adds the class's own key to its effective max.
	mana       = "Aether",          -- Arcanist weapon ("Bonus Mana")
	focus      = "KillerInstinct",  -- Hunter weapon ("Bonus Focus")
	lifeEnergy = "LifeEnergy",      -- LifeSteward weapon + armor
	-- §AGX/D-FIX2: healer + resist rolls had no row, so LifeSteward's top
	-- weapon/armor stats did nothing. Units already match the readers:
	-- HealingPower flat (HealingSystem.GetBaseHealing), HealingPercent
	-- percent points (/100 in CalculateHeal), StatusResistance percent
	-- points (StatCaps 0–60, MobAI reads GetTotalStat).
	healingPower     = "HealingPower",
	healingPercent   = "HealingPercent",
	statusResistance = "StatusResistance",
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
function PlayerBonusSystem.ApplyWeaponBonuses(player)
	local bm = requireBonusManager()

	-- Build the weapon-source bonus table from the equipped weapon's random rolls.
	local weaponBonuses = {}
	local weaponInstance = PlayerBonusSystem.PlayerDataManager.GetEquippedWeapon(player)
	if weaponInstance and weaponInstance.bonuses then
		for _, bonus in ipairs(weaponInstance.bonuses) do
			local statName = BONUS_STAT_MAPPING[bonus.stat]
			if statName then
				-- §AGX/BAL: gear critDamage rolls are percent (5–40); CritDamage is a
				-- multiplier (base 1.5, cap 1.8), so one raw roll used to pin the cap.
				local v = (statName == "CritDamage") and bonus.value / 100 or bonus.value
				weaponBonuses[statName] = (weaponBonuses[statName] or 0) + v
			end
		end
	end
	bm.SetSourceBonuses(player, "weapon", weaponBonuses)

	-- Refresh HP if bonusHealth changed.
	if player.Character then
		local StatSystem = PlayerBonusSystem.PlayerDataManager.GetSystems().Stat
		StatSystem.ApplyHealthToCharacter(player, player.Character)
	end
end

function PlayerBonusSystem.RefreshWeaponStats(player)
	PlayerBonusSystem.ApplyWeaponBonuses(player)
end

--============================================
-- ARMOR BONUS APPLICATION
--============================================
local ArmorManagerRef = nil

function PlayerBonusSystem.ApplyArmorBonuses(player)
	local bm = requireBonusManager()

	-- Lazy-require ArmorManager (avoids circular: ArmorManager → PlayerDataManager → this).
	if not ArmorManagerRef then
		local mod = Modules:FindFirstChild("ArmorManager")
		if mod then ArmorManagerRef = require(mod) end
	end
	if not ArmorManagerRef then return end

	local armorBonuses = {}
	local stats = ArmorManagerRef.GetCalculatedStats(player)

	if stats.bonusHealth and stats.bonusHealth > 0 then
		armorBonuses["BonusHealth"] = stats.bonusHealth
	end

	if stats.bonuses then
		for _, bonus in ipairs(stats.bonuses) do
			local statName = BONUS_STAT_MAPPING[bonus.stat]
			if statName then
				-- §AGX/BAL: gear critDamage rolls are percent (5–40); CritDamage is a
				-- multiplier (base 1.5, cap 1.8), so one raw roll used to pin the cap.
				local v = (statName == "CritDamage") and bonus.value / 100 or bonus.value
				armorBonuses[statName] = (armorBonuses[statName] or 0) + v
			end
		end
	end

	bm.SetSourceBonuses(player, "armor", armorBonuses)

	if player.Character then
		local StatSystem = PlayerBonusSystem.PlayerDataManager.GetSystems().Stat
		StatSystem.ApplyHealthToCharacter(player, player.Character)
	end
end

function PlayerBonusSystem.RefreshArmorStats(player)
	PlayerBonusSystem.ApplyArmorBonuses(player)
end

return PlayerBonusSystem
