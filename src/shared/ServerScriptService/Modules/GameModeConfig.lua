-- ServerScriptService/Modules/GameModeConfig
--[[
    Central registry of all game modes.
    Each mode defines its ID, display info, party constraints,
    spawn location, scene name, and feature toggles.
    
    Add new modes here. The Matchmaking and Scene systems read this config.
]]

local GameModeConfig = {}

-- ═══════════════════════════════════════════════════════════
-- GAME MODES
-- ═══════════════════════════════════════════════════════════

GameModeConfig.Modes = {
	Defense = {
		id           = "Defense",
		name         = "Defense",
		description  = "Defend the line against waves of enemies.",
		icon         = "rbxassetid://0",          -- placeholder
		available    = true,
		sortOrder    = 1,

		-- Party
		minPlayers   = 1,
		maxPlayers   = 4,
		soloAllowed  = true,

		-- Scene
		sceneName    = "Defense",
		spawnPoint   = "DefenseSpawn",             -- name of the SpawnLocation / Part

		-- Feature toggles for this mode
		features     = {
			fixedCamera    = true,                 -- isometric / fixed camera
			skillsEnabled  = true,
			attackEnabled  = true,
			pvpEnabled     = false,
		},
	},

	-- Future modes (placeholders) ──────────────────────────
	CentralBoss = {
		id           = "CentralBoss",
		name         = "Central Boss",
		description  = "Fight a powerful boss with your party.",
		icon         = "rbxassetid://0",          -- placeholder
		-- §AGX/X19: off until the arena has content (BACKLOG §AGX/X28-NEXT, §CB1).
		-- Matchmaking checks this server-side, so crafted queues fail too.
		-- §AGX/X28: core boss fight is authored (BossEncounter). FLIP HERE
		-- (and in lobby MainMenu.lua MODES) to `true` after Studio testing.
		available    = false,
		sortOrder    = 2,

		minPlayers   = 1,
		maxPlayers   = 4,
		soloAllowed  = true,

		sceneName    = "Boss",
		spawnPoint   = "BossSpawn",

		features     = {
			fixedCamera    = true,
			skillsEnabled  = true,
			attackEnabled  = true,
			pvpEnabled     = false,
		},
	},

	HordeMode = {
		id           = "HordeMode",
		name         = "Horde Mode",
		description  = "Survive endless waves in a top-down arena.",
		icon         = "rbxassetid://0",          -- placeholder
		available    = true,
		sortOrder    = 3,

		minPlayers   = 1,
		maxPlayers   = 4,
		soloAllowed  = true,

		sceneName    = "Horde",
		spawnPoint   = "HordeSpawn",

		features     = {
			fixedCamera    = true,
			skillsEnabled  = true,
			attackEnabled  = true,
			pvpEnabled     = false,
		},

		-- §36: Horde Mode multipliers (relative to Defense at equivalent level)
		mobMultipliers = {
			hpMult     = 0.60,
			damageMult = 0.85,
			armorMult  = 0.80,
		},
		rewardMultipliers = {
			xpMult      = 0.45,
			meritsMult  = 0.50,
			essenceMult = 0.60,
		},
	},

	-- Future modes (placeholders) ──────────────────────────
	Arena = {
		id           = "Arena",
		name         = "Arena",
		description  = "Coming soon — PvP Arena.",
		icon         = "rbxassetid://0",
		available    = false,
		sortOrder    = 2,

		minPlayers   = 2,
		maxPlayers   = 4,
		soloAllowed  = false,

		sceneName    = "Arena",
		spawnPoint   = "ArenaSpawn",

		features     = {
			fixedCamera    = true,
			skillsEnabled  = true,
			attackEnabled  = true,
			pvpEnabled     = true,
		},
	},

	Raid = {
		id           = "Raid",
		name         = "Raid",
		description  = "Coming soon — Cooperative boss encounters.",
		icon         = "rbxassetid://0",
		available    = false,
		sortOrder    = 3,

		minPlayers   = 4,
		maxPlayers   = 4,
		soloAllowed  = false,

		sceneName    = "Raid",
		spawnPoint   = "RaidSpawn",

		features     = {
			fixedCamera    = false,
			skillsEnabled  = true,
			attackEnabled  = true,
			pvpEnabled     = false,
		},
	},

	Exploration = {
		id           = "Exploration",
		name         = "Exploration",
		description  = "Coming soon — Open-world exploration.",
		icon         = "rbxassetid://0",
		available    = false,
		sortOrder    = 4,

		minPlayers   = 1,
		maxPlayers   = 4,
		soloAllowed  = true,

		sceneName    = "Exploration",
		spawnPoint   = "ExplorationSpawn",

		features     = {
			fixedCamera    = false,
			skillsEnabled  = true,
			attackEnabled  = true,
			pvpEnabled     = false,
		},
	},
}

-- ═══════════════════════════════════════════════════════════
-- VILLAGE (not a "game mode" — it's the lobby/hub scene)
-- ═══════════════════════════════════════════════════════════

GameModeConfig.Village = {
	sceneName    = "Village",
	spawnPoint   = "VillageSpawn",

	features     = {
		fixedCamera    = false,       -- free camera in village
		skillsEnabled  = false,       -- no combat in village
		attackEnabled  = false,
		pvpEnabled     = false,
	},
}

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function GameModeConfig.GetMode(modeId)
	return GameModeConfig.Modes[modeId]
end

function GameModeConfig.GetAvailableModes()
	local available = {}
	for _, mode in pairs(GameModeConfig.Modes) do
		if mode.available then
			table.insert(available, mode)
		end
	end
	table.sort(available, function(a, b)
		return a.sortOrder < b.sortOrder
	end)
	return available
end

function GameModeConfig.IsModeAvailable(modeId)
	local mode = GameModeConfig.Modes[modeId]
	return mode and mode.available == true
end

-- ═══════════════════════════════════════════════════════════
-- §10: CHALLENGE MODIFIER BONUSES
-- ═══════════════════════════════════════════════════════════

GameModeConfig.ChallengeModifiers = {
	standard = { xpBonus = 0.08, meritsBonus = 0.10, essenceBonus = 0.04 },
	lethal   = { xpBonus = 0.12, meritsBonus = 0.15, essenceBonus = 0.06 },
}

GameModeConfig.ChallengeModifierCaps = {
	xpBonus      = 0.40,
	meritsBonus  = 0.50,
	essenceBonus = 0.20,
}

--- Compute total bonus multipliers (1 + sum of modifiers, capped) for a set of active modifiers.
--- @param activeModifiers table<string, string> — { modifierName = tier } where tier is "standard" or "lethal"
--- @return table { xp: number, merits: number, essence: number } — multipliers (1.0 = no bonus)
function GameModeConfig.GetChallengeBonus(activeModifiers)
	local caps = GameModeConfig.ChallengeModifierCaps
	local totalXP, totalMerits, totalEssence = 0, 0, 0

	if activeModifiers then
		for _, tier in pairs(activeModifiers) do
			local bonus = GameModeConfig.ChallengeModifiers[tier]
			if bonus then
				totalXP      = totalXP      + bonus.xpBonus
				totalMerits  = totalMerits  + bonus.meritsBonus
				totalEssence = totalEssence + bonus.essenceBonus
			end
		end
	end

	return {
		xp      = 1 + math.min(totalXP, caps.xpBonus),
		merits  = 1 + math.min(totalMerits, caps.meritsBonus),
		essence = 1 + math.min(totalEssence, caps.essenceBonus),
	}
end

function GameModeConfig.Init()
end

return GameModeConfig
