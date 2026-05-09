-- ServerScriptService/Modules/WeaponConfig

local WeaponConfig = {}

--============================================
-- LEVEL SCALING
--============================================
-- Scales every 10 levels: multiplier = (1 + SCALE_PERCENT) ^ floor(level/10)
WeaponConfig.LEVEL_SCALE_PERCENT = 0.05  -- 5% per 10 levels (tunable)

--============================================
-- WEAPON LEVEL HARD CAPS
--============================================
--[[
    Weapon level is gated behind player account level.
    At each hard-cap player level, 10 more weapon levels unlock.

    Player level    Max weapon level
    ─────────────   ────────────────
    1   – 49        10
    50  – 99        20
    100 – 149       30
    150 – 199       40
    200+            50  (absolute maximum)

    Talent points = total weapon levels across ALL owned weapons on ALL classes.
    Each class has 2 weapons, so per-class ceiling is 2 × 50 = 100.
    With the 4 alpha classes that's 8 weapons × 50 = 320 talent points endgame;
    future class additions grow the budget linearly.
]]
function WeaponConfig.GetMaxWeaponLevel(playerLevel)
	if     playerLevel < 50  then return 10
	elseif playerLevel < 100 then return 20
	elseif playerLevel < 150 then return 30
	elseif playerLevel < 200 then return 40
	else                          return 50
	end
end

--============================================
-- XP SYSTEM — CURVE
--============================================
--[[
    Curve formula: floor(80 + 120 × L^1.7)
    Same formula extends naturally through level 50 (the new endgame cap).

    Tier breakdown (each tier covers ~50 player levels):
      T1  wlv  1→10  :   20,066 XP  (~2 hrs — quick, hits cap early)
      T2  wlv 10→20  :  116,554 XP  (~12 hrs)
      T3  wlv 20→30  :  278,961 XP  (~30 hrs)
      T4  wlv 30→40  :  496,543 XP  (~52 hrs)
      T5  wlv 40→50  :  792,984 XP  (~83 hrs — unlocked at player lv 200)
]]
WeaponConfig.XP_TABLE = {
	[ 1] =    200,  [ 2] =    469,  [ 3] =    856,  [ 4] =   1346,
	[ 5] =   1931,  [ 6] =   2603,  [ 7] =   3359,  [ 8] =   4195,
	[ 9] =   5107,  [10] =   6094,  [11] =   7152,  [12] =   8279,
	[13] =   9474,  [14] =  10736,  [15] =  12062,  [16] =  13451,
	[17] =  14903,  [18] =  16415,  [19] =  17988,  [20] =  19620,
	[21] =  21310,  [22] =  23057,  [23] =  24860,  [24] =  26720,
	[25] =  28634,  [26] =  30603,  [27] =  32626,  [28] =  34701,
	[29] =  36830,  [30] =  39010,  [31] =  41241,  [32] =  43524,
	[33] =  45857,  [34] =  48240,  [35] =  50673,  [36] =  53155,
	[37] =  55686,  [38] =  58265,  [39] =  60892,  [40] =  63566,
	[41] =  66288,  [42] =  69057,  [43] =  71872,  [44] =  74733,
	[45] =  77640,  [46] =  80593,  [47] =  83591,  [48] =  86634,
	[49] =  89722,  [50] =  92854,
}

--- Returns XP required to advance FROM weaponLevel to weaponLevel+1.
function WeaponConfig.GetXPRequired(weaponLevel)
	return WeaponConfig.XP_TABLE[weaponLevel] or 99999999
end

--============================================
-- XP SYSTEM — PER-CLASS RATES
--============================================
--[[
    Each class role earns weapon XP from a different combat source.
    Rates are tuned so all roles reach weapon level 40 in ~95-100 hours.

    Role    Source              Rate
    ────    ──────────────────  ──────────────────────────────────────────
    dps     mob kills           10 XP / normal kill  (5× mini, 20× boss)
    tank    incoming damage     16 XP / 100 HP incoming (pre-DR), cap 200/hit
    healer  healing + revives   15 XP / 100 HP healed; 6 XP/buff; 120 XP/revive
    support buffs + revives     same as healer (support may heal less, buff more)
]]
WeaponConfig.XP_MOB_MULTIPLIER = {
	Normal = 1.0,
	Mini   = 5.0,
	Boss   = 20.0,
}

WeaponConfig.XP_RATES = {
	-- ── DPS ──────────────────────────────────────────────
	DPS_BASE          = 10,   -- base XP per normal mob kill

	-- ── Tank ─────────────────────────────────────────────
	-- Counts INCOMING damage (before DR) so high-defense tanks aren't penalised.
	TANK_PER_100_DMG  = 16,   -- XP per 100 incoming HP
	TANK_MAX_PER_HIT  = 200,  -- single-hit cap (avoids abuse from massive one-shots)

	-- ── Healer / Support ──────────────────────────────────
	SUPP_PER_100_HEAL = 15,   -- XP per 100 HP healed (only effective heals count)
	SUPP_PER_BUFF     = 6,    -- XP per buff application
	SUPP_PER_REVIVE   = 120,  -- XP per full ally revive
}

--============================================
-- REFINEMENT SYSTEM
--============================================
WeaponConfig.REFINEMENT_MAX = 15

-- Ceilings: can't drop below these levels
WeaponConfig.REFINEMENT_CEILINGS = { 0, 3, 6, 9, 12 }

-- Temper pity system (§14 rework) — per-band thresholds
-- Gains per step position inside any band (1st/2nd/3rd above floor)
WeaponConfig.TEMPER_GAIN_BY_STEP = { 1, 2, 3 }
-- Threshold scales with band difficulty; higher bands need more temper to pity
WeaponConfig.TEMPER_THRESHOLDS = {
	[3]  = 10,  -- band +3→+6  (rates 90/80/70%)
	[6]  = 18,  -- band +6→+9  (rates 60/50/40%)
	[9]  = 28,  -- band +9→+12 (rates 30/22/15%)
	[12] = 36,  -- band +12→+15 (rates 10/6/3%) — repeated each tier
}

-- Chance to downgrade on fail (except at ceiling)
-- DOWNGRADE_CHANCE removed: failure uses positional step logic (§13)

-- Success chance per refinement level (per §13)
WeaponConfig.REFINEMENT_SUCCESS = {
	[0] = 1.00,   -- +0 → +1
	[1] = 1.00,   -- +1 → +2
	[2] = 1.00,   -- +2 → +3
	[3] = 0.90,   -- +3 → +4
	[4] = 0.80,   -- +4 → +5
	[5] = 0.70,   -- +5 → +6
	[6] = 0.60,   -- +6 → +7
	[7] = 0.50,   -- +7 → +8
	[8] = 0.40,   -- +8 → +9
	[9] = 0.30,   -- +9 → +10
	[10] = 0.22,  -- +10 → +11
	[11] = 0.15,  -- +11 → +12
	[12] = 0.10,  -- +12 → +13
	[13] = 0.06,  -- +13 → +14
	[14] = 0.03,  -- +14 → +15
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
WeaponConfig.REROLL_BASE_COST = 300
WeaponConfig.REROLL_TIER_MULTIPLIER = 1.46

-- Cost = baseCost * (multiplier ^ (tier - 1))
-- Tier I: 300, Tier II: 438, Tier III: 639
function WeaponConfig.GetRerollCost(tier)
	return math.floor(
		WeaponConfig.REROLL_BASE_COST * 
			(WeaponConfig.REROLL_TIER_MULTIPLIER ^ (tier - 1))
	)
end

--============================================
-- COST TABLES
--============================================
-- Refinement cost per attempt. Index = current refinement level.
-- Refinement cost in Merits per attempt (per §13)
WeaponConfig.REFINEMENT_COST = {
	[0]  = 300,    [1]  = 500,    [2]  = 800,    [3]  = 1200,
	[4]  = 1800,   [5]  = 3000,   [6]  = 5000,   [7]  = 8000,
	[8]  = 12000,  [9]  = 18000,  [10] = 27000,  [11] = 40000,
	[12] = 60000,  [13] = 90000,  [14] = 140000,
}
WeaponConfig.REFINEMENT_CURRENCY = "Merits"

-- Tier upgrade cost in Essence (per §12). Index = current tier.
WeaponConfig.TIER_COST = {
	[1]  = 10,  [2]  = 15,  [3]  = 25,  [4]  = 40,
	[5]  = 60,  [6]  = 90,  [7]  = 130, [8]  = 180,
	[9]  = 250, [10] = 350, [11] = 500,
}

-- Minimum refinement required for tier upgrade (per §12)
WeaponConfig.TIER_MIN_REFINE = {
	[1] = 1,  [2] = 3,  [3] = 4,  [4] = 6,
	[5] = 7,  [6] = 8,  [7] = 9,  [8] = 10,
	[9] = 11, [10] = 12, [11] = 13,
}
WeaponConfig.TIER_CURRENCY = "Essence"

function WeaponConfig.GetRefinementCost(refinement)
	return WeaponConfig.REFINEMENT_COST[refinement] or 0
end

function WeaponConfig.GetTierCost(tier)
	return WeaponConfig.TIER_COST[tier] or 0
end

--============================================
-- STARTER WEAPONS
--============================================
-- Each class starts with this weapon at level 1
WeaponConfig.STARTER_WEAPONS = {
	Aegis        = "SwordAndShield",
	Arcanist     = "ApprenticeWand",
	Hunter       = "ShortBow",
	LifeSteward  = "LifeTotem",
}

return WeaponConfig