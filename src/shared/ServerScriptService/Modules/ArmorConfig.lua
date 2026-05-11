-- ServerScriptService/Modules/ArmorConfig
--[[
    ArmorConfig
    ===========
    Armor-specific tunables. Refinement / tier / reroll mechanics are
    SHARED with weapons and live in GearUpgradeConfig — see §CFG-D1.

    §CFG-D2: Armor XP was removed long ago (task #9 — only weapons level up).
    The previous XP_LEVEL_RANGE / XP_BASE / XP_MOB_MULTIPLIER / GetXPRequired
    fields had zero readers in the codebase and have been deleted.

    Owned by this file:
      • TIER_DEF_BONUS — tier scaling of defense stat
      • STARTER_ARMORS — per-class starter armor id
]]

local ArmorConfig = {}

--============================================
-- TIER DEFENSE BONUS  (armor-specific tier scaling)
--============================================
ArmorConfig.TIER_DEF_BONUS = {
	[1]  = 0.00,  [2]  = 0.05,  [3]  = 0.10,  [4]  = 0.15,
	[5]  = 0.20,  [6]  = 0.25,  [7]  = 0.30,  [8]  = 0.35,
	[9]  = 0.40,  [10] = 0.45,  [11] = 0.50,  [12] = 0.60,
}

--============================================
-- STARTER ARMORS
--============================================
ArmorConfig.STARTER_ARMORS = {
	Aegis       = "PlateArmor",
	Arcanist    = "SilkRobe",
	Hunter      = "LeatherArmor",
	LifeSteward = "BarkweaveVest",
}

return ArmorConfig
