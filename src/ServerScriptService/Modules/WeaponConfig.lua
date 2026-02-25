-- ServerScriptService/Modules/WeaponConfig

local WeaponConfig = {}

--============================================
-- LEVEL SCALING
--============================================
-- Scales every 10 levels: multiplier = (1 + SCALE_PERCENT) ^ floor(level/10)
WeaponConfig.LEVEL_SCALE_PERCENT = 0.05  -- 5% per 10 levels (tunable)

-- Max weapon level = floor(PlayerLevel / 10) * 10
-- Calculated dynamically, no cap stored here

--============================================
-- XP SYSTEM
--============================================
-- Weapon gains XP from mobs in range [WeaponLevel - 10, WeaponLevel + 10]
WeaponConfig.XP_LEVEL_RANGE = 10

-- Base XP per kill (modified by mob level relative to weapon)
-- Formula: baseXP * (1 + (mobLevel - weaponLevel) * 0.1)
WeaponConfig.XP_BASE = 1

-- Bonus XP for special mobs
WeaponConfig.XP_MOB_MULTIPLIER = {
	Normal = 1,
	Mini = 5,
	Boss = 10,
}

-- XP required to level up: 100 + (weaponLevel ^ 2) * 10
-- Level 1→2: 110 XP
-- Level 10→11: 1100 XP
-- Level 50→51: 25100 XP
function WeaponConfig.GetXPRequired(weaponLevel)
	return 100 + (weaponLevel ^ 2) * 10
end

--============================================
-- REFINEMENT SYSTEM
--============================================
WeaponConfig.REFINEMENT_MAX = 15

-- Ceilings: can't drop below these levels
WeaponConfig.REFINEMENT_CEILINGS = { 0, 3, 6, 9, 12 }

-- Chance to downgrade on fail (except at ceiling)
WeaponConfig.REFINEMENT_DOWNGRADE_CHANCE = 0.30

-- Success chance per refinement level
WeaponConfig.REFINEMENT_SUCCESS = {
	[0] = 1.00,   -- +0 → +1
	[1] = 1.00,   -- +1 → +2
	[2] = 1.00,   -- +2 → +3
	[3] = 0.80,   -- +3 → +4
	[4] = 0.70,   -- +4 → +5
	[5] = 0.60,   -- +5 → +6
	[6] = 0.50,   -- +6 → +7
	[7] = 0.40,   -- +7 → +8
	[8] = 0.30,   -- +8 → +9
	[9] = 0.20,   -- +9 → +10
	[10] = 0.15,  -- +10 → +11
	[11] = 0.10,  -- +11 → +12
	[12] = 0.05,  -- +12 → +13
	[13] = 0.03,  -- +13 → +14
	[14] = 0.01,  -- +14 → +15
}

-- Check if a refinement level is a ceiling
function WeaponConfig.IsCeiling(refinement)
	for _, ceiling in ipairs(WeaponConfig.REFINEMENT_CEILINGS) do
		if refinement == ceiling then
			return true
		end
	end
	return false
end

-- Get the ceiling below a given refinement level
function WeaponConfig.GetCeilingBelow(refinement)
	local result = 0
	for _, ceiling in ipairs(WeaponConfig.REFINEMENT_CEILINGS) do
		if ceiling < refinement then
			result = ceiling
		end
	end
	return result
end

--============================================
-- TIER SYSTEM
--============================================
WeaponConfig.TIER_MAX = 12

-- Bonus slots per tier (for random bonuses)
WeaponConfig.TIER_BONUS_SLOTS = {
	[1] = 2,  [2] = 2,  [3] = 3,  [4] = 3,
	[5] = 3,  [6] = 4,  [7] = 4,  [8] = 4,
	[9] = 5,  [10] = 5, [11] = 5, [12] = 5,
}

-- Multiplier for bonus value ranges per tier
WeaponConfig.TIER_VALUE_MULTIPLIER = {
	[1] = 1.0,  [2] = 1.1,  [3] = 1.2,  [4] = 1.3,
	[5] = 1.4,  [6] = 1.5,  [7] = 1.6,  [8] = 1.7,
	[9] = 1.8,  [10] = 1.9, [11] = 2.0, [12] = 2.2,
}

-- How many bonus pool options are unlocked per tier
-- (indices 1 to N of the weapon's bonusPool)
WeaponConfig.TIER_POOL_UNLOCKS = {
	[1] = 3,   [2] = 4,   [3] = 5,   [4] = 6,
	[5] = 7,   [6] = 8,   [7] = 9,   [8] = 10,
	[9] = 11,  [10] = 12, [11] = 13, [12] = 99,  -- 99 = all
}

-- Attack bonus per tier (percentage)
WeaponConfig.TIER_ATK_BONUS = {
	[1] = 0.00,  [2] = 0.05,  [3] = 0.10,  [4] = 0.15,
	[5] = 0.20,  [6] = 0.25,  [7] = 0.30,  [8] = 0.35,
	[9] = 0.40,  [10] = 0.45, [11] = 0.50, [12] = 0.60,
}

--============================================
-- REROLL SYSTEM
--============================================
WeaponConfig.REROLL_CURRENCY = "Merits"
WeaponConfig.REROLL_BASE_COST = 100
WeaponConfig.REROLL_TIER_MULTIPLIER = 1.5

-- Cost = baseCost * (multiplier ^ (tier - 1))
-- Tier I: 100, Tier II: 150, Tier III: 225, Tier VI: ~759
function WeaponConfig.GetRerollCost(tier)
	return math.floor(
		WeaponConfig.REROLL_BASE_COST * 
			(WeaponConfig.REROLL_TIER_MULTIPLIER ^ (tier - 1))
	)
end

--============================================
-- STARTER WEAPONS
--============================================
-- Each class starts with this weapon at level 1
WeaponConfig.STARTER_WEAPONS = {
	Aegis    = "SwordAndShield",
	Arcanist = "ApprenticeWand",
	Hunter   = "ShortBow",
}

return WeaponConfig