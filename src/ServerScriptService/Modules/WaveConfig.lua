-- ServerScriptService/Modules/WaveConfig

local WaveConfig = {}

--[[
    Wave Configuration - Defines wave composition and progression.
    Mobs are referenced by ID (from MobRegistry).
]]

local WAVE_DEFINITIONS = {
	[1] = {
		mobCount = 3,
		spawnWeights = { Zombie = 1 },
		guaranteed = {},
		spawnInterval = 2.0,
	},
	[2] = {
		mobCount = 5,
		spawnWeights = { Zombie = 1 },
		guaranteed = {},
		spawnInterval = 1.8,
	},
	[3] = {
		mobCount = 6,
		spawnWeights = { Zombie = 1 },
		guaranteed = {},
		spawnInterval = 1.5,
	},
	[4] = {
		mobCount = 8,
		spawnWeights = { Zombie = 1 },
		guaranteed = {},
		spawnInterval = 1.3,
	},
	[5] = {
		mobCount = 5,
		spawnWeights = { Zombie = 1 },
		guaranteed = { "Ogre" },
		spawnInterval = 1.5,
	},
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

function WaveConfig.GetWave(waveNumber)
	if WAVE_DEFINITIONS[waveNumber] then
		local wave = WAVE_DEFINITIONS[waveNumber]
		wave.level = wave.level or waveNumber
		return wave
	end
	return WaveConfig.GenerateProceduralWave(waveNumber)
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