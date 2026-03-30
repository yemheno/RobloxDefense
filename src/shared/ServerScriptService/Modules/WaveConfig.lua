-- ServerScriptService/Modules/WaveConfig

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaveConfig = {}

local DifficultyConfig = nil
local function getDifficultyConfig()
	if not DifficultyConfig then
		local ok, cfg = pcall(require, ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DifficultyConfig", 5))
		if ok then DifficultyConfig = cfg end
	end
	return DifficultyConfig
end

--[[
    Wave Configuration - Defines wave composition and progression.
    Mobs are referenced by ID (from MobRegistry).
]]

-- 12-wave baseline (Normal difficulty). MobSpawner applies countMult/intervalMult
-- on top via DifficultyConfig. Mob levels are anchored to party level at runtime
-- by MobSpawner.SetPartyAnchorLevel() — the level field here is a wave-number
-- fallback only.
local WAVE_DEFINITIONS = {
	[1]  = { mobCount = 10, spawnWeights = { Zombie = 1 }, guaranteed = {},          spawnInterval = 2.5 },
	[2]  = { mobCount = 12, spawnWeights = { Zombie = 1 }, guaranteed = {},          spawnInterval = 2.4 },
	[3]  = { mobCount = 14, spawnWeights = { Zombie = 1 }, guaranteed = {},          spawnInterval = 2.3 },
	[4]  = { mobCount = 16, spawnWeights = { Zombie = 1 }, guaranteed = { "Troll" }, spawnInterval = 2.1 },
	[5]  = { mobCount = 18, spawnWeights = { Zombie = 1 }, guaranteed = {},          spawnInterval = 2.0 },
	[6]  = { mobCount = 20, spawnWeights = { Zombie = 1 }, guaranteed = {},          spawnInterval = 1.9 },
	[7]  = { mobCount = 22, spawnWeights = { Zombie = 1 }, guaranteed = { "Troll" }, spawnInterval = 1.8 },
	[8]  = { mobCount = 24, spawnWeights = { Zombie = 1 }, guaranteed = {},          spawnInterval = 1.7 },
	[9]  = { mobCount = 26, spawnWeights = { Zombie = 1 }, guaranteed = {},          spawnInterval = 1.6 },
	[10] = { mobCount = 28, spawnWeights = { Zombie = 1 }, guaranteed = { "Ogre" },  spawnInterval = 1.5 },
	[11] = { mobCount = 30, spawnWeights = { Zombie = 1 }, guaranteed = {},          spawnInterval = 1.4 },
	[12] = { mobCount = 32, spawnWeights = { Zombie = 1 }, guaranteed = { "Ogre" },  spawnInterval = 1.3 },
}

local PROCEDURAL_CONFIG = {
	baseMobCount = 5,
	mobCountPerWave = 1,
	maxMobCount = 30,
	baseSpawnInterval = 1.5,
	minSpawnInterval = 0.5,
	spawnIntervalDecay = 0.05,
	minibossInterval = 5,
	availableMobs = { "Zombie" },
	availableMinibosses = { "Ogre", "Troll" },
}

-- ── Deep copy helper for nested tables ──────────────────────
local function deepCopy(tbl)
	if type(tbl) ~= "table" then return tbl end
	local copy = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			copy[k] = deepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

function WaveConfig.GetWave(waveNumber, difficulty)
	local base
	if WAVE_DEFINITIONS[waveNumber] then
		-- Return a deep copy to avoid mutating the template
		local template = WAVE_DEFINITIONS[waveNumber]
		base = deepCopy(template)
		base.level = base.level or waveNumber
	else
		base = WaveConfig.GenerateProceduralWave(waveNumber)
	end

	-- Apply difficulty multipliers to count and spawn interval
	local dc = getDifficultyConfig()
	local diff = dc and dc.GetDifficulty(difficulty) or nil
	if diff then
		base.mobCount      = math.ceil(base.mobCount * diff.countMult)
		base.spawnInterval = base.spawnInterval * diff.intervalMult
		base.difficulty    = difficulty  -- pass through so consumers can read it
	end

	return base
end

function WaveConfig.GenerateProceduralWave(waveNumber)
	local config = PROCEDURAL_CONFIG

	local mobCount = math.min(
		config.baseMobCount + (waveNumber - 1) * config.mobCountPerWave,
		config.maxMobCount
	)

	local spawnInterval = math.max(
		config.baseSpawnInterval - (waveNumber - 1) * config.spawnIntervalDecay,
		config.minSpawnInterval
	)

	local spawnWeights = {}
	for _, mobId in ipairs(config.availableMobs) do
		spawnWeights[mobId] = 1
	end

	local guaranteed = {}
	if waveNumber >= 5 and (waveNumber - 5) % config.minibossInterval == 0 then
		local minibossIndex = math.random(1, #config.availableMinibosses)
		table.insert(guaranteed, config.availableMinibosses[minibossIndex])
	end

	return {
		mobCount = mobCount,
		spawnWeights = spawnWeights,
		guaranteed = guaranteed,
		spawnInterval = spawnInterval,
		level = waveNumber,
	}
end

return WaveConfig