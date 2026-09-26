-- ServerScriptService/Modules/GearUpgradeConfig
--[[
    GearUpgradeConfig
    =================
    Shared upgrade tables for BOTH weapons and armor — single source of
    truth for refinement, tier, and reroll mechanics.

    Why this exists
    ---------------
    Before T0.4, WeaponConfig and ArmorConfig each held byte-identical
    copies of every refinement / tier / reroll table. Balance tweaks
    applied to one and forgotten in the other silently desynced gear
    progression between weapon and armor. §CFG-D1 in the T0.4 audit
    enumerated 22 duplicated entries.

    After T0.4, this module owns the shared truth:
      • Refinement: REFINEMENT_MAX, CEILINGS, TEMPER_*, SUCCESS, COST, CURRENCY
      • Tier:       TIER_MAX, BONUS_SLOTS, VALUE_MULTIPLIER, POOL_UNLOCKS,
                    COST, MIN_REFINE, CURRENCY
      • Reroll:     CURRENCY, BASE_COST, TIER_MULTIPLIER
      • Helpers:    IsCeiling, GetCeilingBelow, GetRefinementCost,
                    GetTierCost, GetRerollCost

    WeaponConfig and ArmorConfig now hold ONLY type-specific fields:
      • WeaponConfig: XP system (weapons level up), TIER_ATK_BONUS,
                       STARTER_WEAPONS, GetMaxWeaponLevel
      • ArmorConfig:  TIER_DEF_BONUS, STARTER_ARMORS
                       (XP system removed — armor doesn't level, §CFG-D2)

    The shared factory systems (EquipmentRefinement, EquipmentTierSystem)
    are passed THIS module directly as their Config parameter — they only
    ever read shared fields.
]]

local GearUpgradeConfig = {}

--============================================
-- LEVEL SCALING (shared)
--============================================
-- multiplier = (1 + LEVEL_SCALE_PERCENT) ^ floor(level / 10)
GearUpgradeConfig.LEVEL_SCALE_PERCENT = 0.05  -- 5% per 10 levels

--============================================
-- REFINEMENT SYSTEM
--============================================
GearUpgradeConfig.REFINEMENT_MAX = 15

-- Ceilings: can't drop below these levels on a failed refine.
GearUpgradeConfig.REFINEMENT_CEILINGS = { 0, 3, 6, 9, 12 }

-- Temper pity system (§14)
-- Gain per step position inside a band (1st / 2nd / 3rd above floor).
GearUpgradeConfig.TEMPER_GAIN_BY_STEP = { 1, 2, 3 }

-- Threshold to pity within each ceiling band — higher bands need more
-- temper because their base success rates are lower.
GearUpgradeConfig.TEMPER_THRESHOLDS = {
	[3]  = 10,  -- band +3→+6  (rates 90/80/70%)
	[6]  = 18,  -- band +6→+9  (rates 60/50/40%)
	[9]  = 28,  -- band +9→+12 (rates 30/22/20%)
	-- §AGX/X43: with the softer band-12 rates below, pity is the
	-- backstop, not the main route.
	[12] = 18,  -- band +12→+15 (rates 18/14/10%)
}

-- Success chance per refinement level (per §13)
GearUpgradeConfig.REFINEMENT_SUCCESS = {
	[0]  = 1.00,  -- +0 → +1
	[1]  = 1.00,  -- +1 → +2
	[2]  = 1.00,  -- +2 → +3
	[3]  = 0.90,  -- +3 → +4
	[4]  = 0.80,  -- +4 → +5
	[5]  = 0.70,  -- +5 → +6
	[6]  = 0.60,  -- +6 → +7
	[7]  = 0.50,  -- +7 → +8
	[8]  = 0.40,  -- +8 → +9
	[9]  = 0.30,  -- +9 → +10
	[10] = 0.22,  -- +10 → +11
	-- §AGX/X43: late-game Merit wall. Only attempts that Chapter 3+ can make
	-- change (Ch2's cap +11 means its last attempt is at +10), so Chapters 1–2
	-- are untouched. Was 15/10/6/3%.
	[11] = 0.20,  -- +11 → +12
	[12] = 0.18,  -- +12 → +13
	[13] = 0.14,  -- +13 → +14
	[14] = 0.10,  -- +14 → +15
}

-- Refinement attempt cost in Merits (per §13).
-- §AGX/X43, §AGX/X9: +11 and up are tuned together with the band-12 rates
-- and threshold (Chapter 4 ladder costed by an exact DP of
-- EquipmentRefinement's rules, incl. the cap clamp). Numbers and hours:
-- BALANCE_NUMBERS.md#refinement-system.
GearUpgradeConfig.REFINEMENT_COST = {
	[0]  = 300,    [1]  = 500,    [2]  = 800,    [3]  = 1200,
	[4]  = 1800,   [5]  = 3000,   [6]  = 5000,   [7]  = 8000,
	[8]  = 12000,  [9]  = 18000,  [10] = 27000,  [11] = 30000,
	[12] = 36000,  [13] = 42000,  [14] = 50000,
}
GearUpgradeConfig.REFINEMENT_CURRENCY = "Merits"

function GearUpgradeConfig.IsCeiling(refinement)
	for _, ceiling in ipairs(GearUpgradeConfig.REFINEMENT_CEILINGS) do
		if refinement == ceiling then
			return true
		end
	end
	return false
end

function GearUpgradeConfig.GetCeilingBelow(refinement)
	local result = 0
	for _, ceiling in ipairs(GearUpgradeConfig.REFINEMENT_CEILINGS) do
		if ceiling < refinement then
			result = ceiling
		end
	end
	return result
end

function GearUpgradeConfig.GetRefinementCost(refinement)
	return GearUpgradeConfig.REFINEMENT_COST[refinement] or 0
end

--============================================
-- TIER SYSTEM
--============================================
GearUpgradeConfig.TIER_MAX = 12

-- Bonus slots per tier (random rolls unlocked).
GearUpgradeConfig.TIER_BONUS_SLOTS = {
	[1]  = 2,  [2]  = 2,  [3]  = 3,  [4]  = 3,
	[5]  = 3,  [6]  = 4,  [7]  = 4,  [8]  = 4,
	[9]  = 5,  [10] = 5,  [11] = 5,  [12] = 5,
}

-- Multiplier for bonus value ranges per tier.
GearUpgradeConfig.TIER_VALUE_MULTIPLIER = {
	[1]  = 1.0,  [2]  = 1.1,  [3]  = 1.2,  [4]  = 1.3,
	[5]  = 1.4,  [6]  = 1.5,  [7]  = 1.6,  [8]  = 1.7,
	[9]  = 1.8,  [10] = 1.9,  [11] = 2.0,  [12] = 2.2,
}

-- How many bonus pool entries are unlocked per tier (99 = all).
GearUpgradeConfig.TIER_POOL_UNLOCKS = {
	[1]  = 3,   [2]  = 4,   [3]  = 5,   [4]  = 6,
	[5]  = 7,   [6]  = 8,   [7]  = 9,   [8]  = 10,
	[9]  = 11,  [10] = 12,  [11] = 13,  [12] = 99,
}

-- Tier upgrade cost in Essence (per §12). Index = CURRENT tier.
GearUpgradeConfig.TIER_COST = {
	[1]  = 10,  [2]  = 15,  [3]  = 25,  [4]  = 40,
	[5]  = 60,  [6]  = 90,  [7]  = 130, [8]  = 180,
	[9]  = 250, [10] = 350, [11] = 500,
}

-- Minimum refinement required to upgrade out of each tier (per §12).
GearUpgradeConfig.TIER_MIN_REFINE = {
	[1] = 1,  [2] = 3,  [3] = 4,  [4] = 6,
	[5] = 7,  [6] = 8,  [7] = 9,  [8] = 10,
	[9] = 11, [10] = 12, [11] = 13,
}

GearUpgradeConfig.TIER_CURRENCY = "Essence"

function GearUpgradeConfig.GetTierCost(tier)
	return GearUpgradeConfig.TIER_COST[tier] or 0
end

--============================================
-- REROLL SYSTEM
--============================================
GearUpgradeConfig.REROLL_CURRENCY        = "Merits"
GearUpgradeConfig.REROLL_BASE_COST       = 300
GearUpgradeConfig.REROLL_TIER_MULTIPLIER = 1.46

-- Cost = baseCost × multiplier ^ (tier - 1)
-- Tier I: 300, Tier II: 438, Tier III: 639, ...
function GearUpgradeConfig.GetRerollCost(tier)
	return math.floor(
		GearUpgradeConfig.REROLL_BASE_COST *
			(GearUpgradeConfig.REROLL_TIER_MULTIPLIER ^ (tier - 1))
	)
end

return GearUpgradeConfig
