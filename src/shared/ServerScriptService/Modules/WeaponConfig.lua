-- ServerScriptService/Modules/WeaponConfig
--[[
    WeaponConfig
    ============
    Weapon-specific tunables. Refinement / tier / reroll mechanics are
    SHARED with armor and live in GearUpgradeConfig — see §CFG-D1.

    Owned by this file:
      • Weapon-level hard cap rules (player-level gated)
      • Weapon XP curve + per-role grant rates
      • TIER_ATK_BONUS — tier scaling of attack stat
      • STARTER_WEAPONS — per-class starter weapon id
]]

local WeaponConfig = {}

--============================================
-- WEAPON LEVEL HARD CAPS
--============================================
--[[
    Weapon level is gated behind player account level.
    Each hard-cap player level unlocks 10 more weapon levels.

    Player level    Max weapon level
    ─────────────   ────────────────
    1   – 49        10
    50  – 99        20
    100 – 149       30
    150 – 199       40
    200+            50 (absolute maximum)

    Talent points = total weapon levels across ALL owned weapons on ALL classes.
    Each class has 2 weapons, so per-class ceiling is 2 × 50 = 100.
    With the 4 alpha classes that's 8 × 50 = 320 endgame talent points;
    future classes grow the budget linearly.
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

--- XP required to advance FROM weaponLevel to weaponLevel+1.
function WeaponConfig.GetXPRequired(weaponLevel)
	return WeaponConfig.XP_TABLE[weaponLevel] or 99999999
end

--============================================
-- XP SYSTEM — PER-CLASS-ROLE RATES
--============================================
--[[
    Each class role earns weapon XP from a different combat source.
    Rates are tuned so all roles reach weapon level 40 in ~95-100 hours.

    Role    Source             Rate
    ────    ─────────────────  ──────────────────────────────────────────
    dps     mob kills          10 XP / normal kill  (5× mini, 20× boss)
    tank    incoming damage    16 XP / 100 HP incoming (pre-DR), cap 200/hit
    healer  healing + revives  15 XP / 100 HP healed; 6 XP/buff; 120 XP/revive
    support buffs + revives    same as healer (support may heal less, buff more)
]]
WeaponConfig.XP_MOB_MULTIPLIER = {
	Normal = 1.0,
	Mini   = 5.0,
	Boss   = 20.0,
}

WeaponConfig.XP_RATES = {
	-- ── DPS ──────────────────────────────────────────────
	DPS_BASE          = 10,   -- XP per normal mob kill

	-- ── Tank ─────────────────────────────────────────────
	-- Counts INCOMING damage (before DR) so defense doesn't penalise the role.
	TANK_PER_100_DMG  = 16,   -- XP per 100 incoming HP
	TANK_MAX_PER_HIT  = 200,  -- single-hit cap (anti-burst-abuse)

	-- ── Healer / Support ─────────────────────────────────
	SUPP_PER_100_HEAL = 15,   -- XP per 100 HP healed (only effective heals count)
	SUPP_PER_BUFF     = 6,    -- XP per buff application
	SUPP_PER_REVIVE   = 120,  -- XP per full ally revive
}

--============================================
-- TIER ATTACK BONUS  (weapon-specific tier scaling)
--============================================
WeaponConfig.TIER_ATK_BONUS = {
	[1]  = 0.00,  [2]  = 0.05,  [3]  = 0.10,  [4]  = 0.15,
	[5]  = 0.20,  [6]  = 0.25,  [7]  = 0.30,  [8]  = 0.35,
	[9]  = 0.40,  [10] = 0.45,  [11] = 0.50,  [12] = 0.60,
}

--============================================
-- STARTER WEAPONS
--============================================
-- Each class starts with this weapon at level 1.
WeaponConfig.STARTER_WEAPONS = {
	Aegis       = "SwordAndShield",
	Arcanist    = "ApprenticeWand",
	Hunter      = "ShortBow",
	LifeSteward = "LifeTotem",
}

return WeaponConfig
