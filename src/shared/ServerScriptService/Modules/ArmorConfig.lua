-- ServerScriptService/Modules/ArmorConfig
--[[
    Configuration for the armor equipment system.
    Mirrors WeaponConfig structure but for defensive gear.
    
    Each class has two armors: a starter and an unlock.
    Armors provide: base defense, bonus health, and random bonuses.
    Armors share refinement / tier / reroll systems with the weapon system.
]]

local ArmorConfig = {}

--============================================
-- LEVEL SCALING
--============================================
-- Scales every 10 levels: multiplier = (1 + SCALE_PERCENT) ^ floor(level/10)
ArmorConfig.LEVEL_SCALE_PERCENT = 0.05  -- 5% per 10 levels (same as weapons, tunable)

-- Max armor level = floor(PlayerLevel / 10) * 10  (same rule as weapons)

--============================================
-- XP SYSTEM
--============================================
-- Armor gains XP from mobs in range [ArmorLevel - 10, ArmorLevel + 10]
ArmorConfig.XP_LEVEL_RANGE = 10

-- Base XP per kill
ArmorConfig.XP_BASE = 1

-- Bonus XP for special mobs
ArmorConfig.XP_MOB_MULTIPLIER = {
	Normal = 1,
	Mini   = 5,
	Boss   = 10,
}

-- XP required to level up per §44.2: round(80 + 8 * Level^2)
function ArmorConfig.GetXPRequired(armorLevel)
	return math.floor(80 + 8 * armorLevel ^ 2 + 0.5)
end

--============================================
-- REFINEMENT SYSTEM
--============================================
ArmorConfig.REFINEMENT_MAX = 15

-- Ceilings: can't drop below these levels
ArmorConfig.REFINEMENT_CEILINGS = { 0, 3, 6, 9, 12 }

-- Temper pity system (§14 rework) — per-band thresholds
-- Gains per step position inside any band (1st/2nd/3rd above floor)
ArmorConfig.TEMPER_GAIN_BY_STEP = { 1, 2, 3 }
-- Threshold scales with band difficulty; higher bands need more temper to pity
ArmorConfig.TEMPER_THRESHOLDS = {
	[3]  = 10,  -- band +3→+6  (rates 90/80/70%)
	[6]  = 18,  -- band +6→+9  (rates 60/50/40%)
	[9]  = 28,  -- band +9→+12 (rates 30/22/15%)
	[12] = 36,  -- band +12→+15 (rates 10/6/3%) — repeated each tier
}

-- Chance to downgrade on fail (except at ceiling)
-- DOWNGRADE_CHANCE removed: failure uses positional step logic (§13)

-- Success chance per refinement level (per §13)
ArmorConfig.REFINEMENT_SUCCESS = {
	[0]  = 1.00,
	[1]  = 1.00,
	[2]  = 1.00,
	[3]  = 0.90,
	[4]  = 0.80,
	[5]  = 0.70,
	[6]  = 0.60,
	[7]  = 0.50,
	[8]  = 0.40,
	[9]  = 0.30,
	[10] = 0.22,
	[11] = 0.15,
	[12] = 0.10,
	[13] = 0.06,
	[14] = 0.03,
}

function ArmorConfig.IsCeiling(refinement)
	for _, ceiling in ipairs(ArmorConfig.REFINEMENT_CEILINGS) do
		if refinement == ceiling then
			return true
		end
	end
	return false
end

function ArmorConfig.GetCeilingBelow(refinement)
	local result = 0
	for _, ceiling in ipairs(ArmorConfig.REFINEMENT_CEILINGS) do
		if ceiling < refinement then
			result = ceiling
		end
	end
	return result
end

--============================================
-- TIER SYSTEM
--============================================
ArmorConfig.TIER_MAX = 12

-- Bonus slots per tier (for random bonuses)
ArmorConfig.TIER_BONUS_SLOTS = {
	[1] = 2,  [2] = 2,  [3] = 3,  [4] = 3,
	[5] = 3,  [6] = 4,  [7] = 4,  [8] = 4,
	[9] = 5,  [10] = 5, [11] = 5, [12] = 5,
}

-- Multiplier for bonus value ranges per tier
ArmorConfig.TIER_VALUE_MULTIPLIER = {
	[1] = 1.0,  [2] = 1.1,  [3] = 1.2,  [4] = 1.3,
	[5] = 1.4,  [6] = 1.5,  [7] = 1.6,  [8] = 1.7,
	[9] = 1.8,  [10] = 1.9, [11] = 2.0, [12] = 2.2,
}

-- How many bonus pool options are unlocked per tier
ArmorConfig.TIER_POOL_UNLOCKS = {
	[1] = 3,   [2] = 4,   [3] = 5,   [4] = 6,
	[5] = 7,   [6] = 8,   [7] = 9,   [8] = 10,
	[9] = 11,  [10] = 12, [11] = 13, [12] = 99,
}

-- Defense bonus per tier (percentage)
ArmorConfig.TIER_DEF_BONUS = {
	[1] = 0.00,  [2] = 0.05,  [3] = 0.10,  [4] = 0.15,
	[5] = 0.20,  [6] = 0.25,  [7] = 0.30,  [8] = 0.35,
	[9] = 0.40,  [10] = 0.45, [11] = 0.50, [12] = 0.60,
}

--============================================
-- REROLL SYSTEM
--============================================
ArmorConfig.REROLL_CURRENCY = "Merits"
ArmorConfig.REROLL_BASE_COST = 300
ArmorConfig.REROLL_TIER_MULTIPLIER = 1.46

function ArmorConfig.GetRerollCost(tier)
	return math.floor(
		ArmorConfig.REROLL_BASE_COST *
			(ArmorConfig.REROLL_TIER_MULTIPLIER ^ (tier - 1))
	)
end

--============================================
-- COST TABLES
--============================================
-- Refinement cost: flat per attempt. Index = current refinement level.
-- Refinement cost in Merits per attempt (per §13)
ArmorConfig.REFINEMENT_COST = {
	[0]  = 300,    [1]  = 500,    [2]  = 800,    [3]  = 1200,
	[4]  = 1800,   [5]  = 3000,   [6]  = 5000,   [7]  = 8000,
	[8]  = 12000,  [9]  = 18000,  [10] = 27000,  [11] = 40000,
	[12] = 60000,  [13] = 90000,  [14] = 140000,
}
ArmorConfig.REFINEMENT_CURRENCY = "Merits"

-- Tier upgrade cost in Essence (per §12). Index = current tier.
ArmorConfig.TIER_COST = {
	[1]  = 10,  [2]  = 15,  [3]  = 25,  [4]  = 40,
	[5]  = 60,  [6]  = 90,  [7]  = 130, [8]  = 180,
	[9]  = 250, [10] = 350, [11] = 500,
}

-- Minimum refinement required for tier upgrade (per §12)
ArmorConfig.TIER_MIN_REFINE = {
	[1] = 1,  [2] = 3,  [3] = 4,  [4] = 6,
	[5] = 7,  [6] = 8,  [7] = 9,  [8] = 10,
	[9] = 11, [10] = 12, [11] = 13,
}
ArmorConfig.TIER_CURRENCY = "Essence"

function ArmorConfig.GetRefinementCost(refinement)
	return ArmorConfig.REFINEMENT_COST[refinement] or 0
end

function ArmorConfig.GetTierCost(tier)
	return ArmorConfig.TIER_COST[tier] or 0
end

--============================================
-- STARTER ARMORS
--============================================
ArmorConfig.STARTER_ARMORS = {
	Aegis        = "PlateArmor",
	Arcanist     = "SilkRobe",
	Hunter       = "LeatherArmor",
	LifeSteward  = "BarkweaveVest",
}

return ArmorConfig
