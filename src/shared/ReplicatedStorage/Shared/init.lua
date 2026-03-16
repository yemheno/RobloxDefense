-- shared/ReplicatedStorage/Shared/init.lua
--[[
    Shared constants, enums, and type tables accessible from both
    server (ServerScriptService) and client (StarterPlayerScripts)
    via ReplicatedStorage.Shared.

    This is the single source of truth for string keys that bridge
    network events, state machines, and UI components.
]]

local Shared = {}

-- ═══════════════════════════════════════════════════════════
-- GAME STATES (mirrors GameStateManager)
-- ═══════════════════════════════════════════════════════════
Shared.GameStates = {
	IDLE      = "Idle",
	PREPARING = "Preparing",
	DEFENDING = "Defending",
	VICTORY   = "Victory",
	DEFEAT    = "Defeat",
}

-- ═══════════════════════════════════════════════════════════
-- SCENES (lobby scene names)
-- ═══════════════════════════════════════════════════════════
Shared.Scenes = {
	VILLAGE = "Village",
	DEFENSE = "Defense",
	BOSS    = "Boss",
	HORDE   = "Horde",
	PLAZA   = "Plaza",
}

-- ═══════════════════════════════════════════════════════════
-- CLASSES
-- ═══════════════════════════════════════════════════════════
Shared.ClassNames = { "Aegis", "Arcanist", "Hunter" }

-- ═══════════════════════════════════════════════════════════
-- PRIMARY STATS
-- ═══════════════════════════════════════════════════════════
Shared.PrimaryStats = { "MIG", "VIT", "PRE", "MAG", "RSV" }

-- ═══════════════════════════════════════════════════════════
-- CURRENCY TYPES
-- ═══════════════════════════════════════════════════════════
Shared.CurrencyTypes = {
	ESSENCE = "Essence",
	MERITS  = "Merits",
}

-- ═══════════════════════════════════════════════════════════
-- GAME MODES
-- ═══════════════════════════════════════════════════════════
Shared.GameModes = {
	DEFENSE      = "Defense",
	CENTRAL_BOSS = "CentralBoss",
	HORDE_MODE   = "HordeMode",
	ARENA        = "Arena",       -- future
	RAID         = "Raid",        -- future
	EXPLORATION  = "Exploration", -- future
}

-- ═══════════════════════════════════════════════════════════
-- PLACE IDS (single source of truth)
-- ═══════════════════════════════════════════════════════════
Shared.PlaceIds = {
	Lobby       = 115774137563700,
	LaneDefense = 138768963731267,
	CentralBoss = 100848838772974,
	HordeMode   = 115735968204052,
	SocialPlaza = 103512111921765,
}

return Shared
