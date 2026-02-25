-- ServerScriptService/Modules/MobSpawner

local MobSpawner = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = script.Parent
local MobAI = require(Modules:WaitForChild("MobAI"))
local MobRegistry = require(Modules:WaitForChild("MobRegistry"))
local WaveConfig = require(Modules:WaitForChild("WaveConfig"))
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

local CONFIG = {
	AutoAdvanceWaves = true,
	AutoAdvanceDelay = 3,
	MaxWave = nil,
}

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local mobsFolder = nil
local mobTemplates = {}
local spawnPoint = nil

local currentWave = 0
local waveState = "idle"
local mobsSpawnedThisWave = 0
local mobsToSpawnThisWave = 0

local onWaveStartedCallbacks = {}
local onWaveCompletedCallbacks = {}
local onAllWavesCompletedCallbacks = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function MobSpawner.Init()
	spawnPoint = workspace:FindFirstChild("MobSpawn")
	if not spawnPoint then
		warn("[MobSpawner] MobSpawn not found in workspace!")
	end

	mobsFolder = ReplicatedStorage:FindFirstChild("Mobs")
	if mobsFolder then
		MobSpawner.CacheTemplates()
	else
		warn("[MobSpawner] ReplicatedStorage/Mobs folder not found!")
	end

	NetworkManager.GetEvent("WaveStarted")
	NetworkManager.GetEvent("WaveCompleted")
	NetworkManager.GetEvent("AllWavesCompleted")
	NetworkManager.GetEvent("RequestNextWave")

	NetworkManager.OnClientEvent("RequestNextWave", function(player)
		if waveState == "idle" then
			print("[MobSpawner]", player.Name, "requested next wave")
			MobSpawner.StartNextWave()
		end
	end)

	print("[MobSpawner] Initialized")
	print("  AutoAdvanceWaves:", CONFIG.AutoAdvanceWaves)
	print("  Templates cached:", MobSpawner.GetTemplateCount())
end

function MobSpawner.CacheTemplates()
	local mobIds = MobRegistry.GetMobIds()

	for _, mobId in ipairs(mobIds) do
		local mobData = MobRegistry.GetMob(mobId)
		if mobData then
			local templateName = mobData.template or "MobTemplate"
			local template = mobsFolder:FindFirstChild(templateName)

			if template then
				mobTemplates[mobId] = template
			else
				warn("[MobSpawner] Missing template for", mobId, ":", templateName)
			end
		end
	end
end

function MobSpawner.GetTemplateCount()
	local count = 0
	for _ in pairs(mobTemplates) do count = count + 1 end
	return count
end

-- ═══════════════════════════════════════════════════════════
-- CALLBACKS
-- ═══════════════════════════════════════════════════════════

function MobSpawner.OnWaveStarted(callback)
	table.insert(onWaveStartedCallbacks, callback)
end

function MobSpawner.OnWaveCompleted(callback)
	table.insert(onWaveCompletedCallbacks, callback)
end

function MobSpawner.OnAllWavesCompleted(callback)
	table.insert(onAllWavesCompletedCallbacks, callback)
end

local function FireWaveStarted(waveNumber, mobCount, level)
	NetworkManager.FireAllClients("WaveStarted", {
		wave = waveNumber,
		mobCount = mobCount,
		level = level,
	})
	for _, callback in ipairs(onWaveStartedCallbacks) do
		task.spawn(callback, waveNumber, mobCount, level)
	end
end

local function FireWaveCompleted(waveNumber)
	NetworkManager.FireAllClients("WaveCompleted", { wave = waveNumber })
	for _, callback in ipairs(onWaveCompletedCallbacks) do
		task.spawn(callback, waveNumber)
	end
end

local function FireAllWavesCompleted()
	NetworkManager.FireAllClients("AllWavesCompleted", { finalWave = currentWave })
	for _, callback in ipairs(onAllWavesCompletedCallbacks) do
		task.spawn(callback, currentWave)
	end
end

-- ═══════════════════════════════════════════════════════════
-- WAVE CONTROL
-- ═══════════════════════════════════════════════════════════

function MobSpawner.StartWave(waveNumber)
	if waveState ~= "idle" then
		warn("[MobSpawner] Cannot start wave - state:", waveState)
		return false
	end

	waveNumber = waveNumber or (currentWave + 1)

	if CONFIG.MaxWave and waveNumber > CONFIG.MaxWave then
		print("[MobSpawner] All waves completed!")
		FireAllWavesCompleted()
		return false
	end

	local waveData = WaveConfig.GetWave(waveNumber)

	currentWave = waveNumber
	waveState = "spawning"
	mobsSpawnedThisWave = 0
	mobsToSpawnThisWave = waveData.mobCount + #waveData.guaranteed

	print("[MobSpawner] ═══════════════════════════════════")
	print("[MobSpawner] Starting Wave", waveNumber, "(Level", waveData.level .. ")")
	print("[MobSpawner] Mobs to spawn:", mobsToSpawnThisWave)
	print("[MobSpawner] ═══════════════════════════════════")

	FireWaveStarted(waveNumber, mobsToSpawnThisWave, waveData.level)

	task.spawn(function()
		MobSpawner.SpawnWave(waveData)
	end)

	return true
end

function MobSpawner.SpawnWave(waveData)
	local level = waveData.level or currentWave

	for _, mobId in ipairs(waveData.guaranteed) do
		MobSpawner.SpawnMob(mobId, level)
		mobsSpawnedThisWave = mobsSpawnedThisWave + 1
		task.wait(waveData.spawnInterval)
	end

	for i = 1, waveData.mobCount do
		local mobId = MobSpawner.GetRandomMobId(waveData.spawnWeights)
		MobSpawner.SpawnMob(mobId, level)
		mobsSpawnedThisWave = mobsSpawnedThisWave + 1
		task.wait(waveData.spawnInterval)
	end

	waveState = "active"
	print("[MobSpawner] All mobs spawned - waiting for clear...")

	MobSpawner.WaitForWaveClear()
end

function MobSpawner.WaitForWaveClear()
	waveState = "clearing"

	while MobAI.IsAnyMobAlive() do
		task.wait(0.5)
	end

	waveState = "idle"

	print("[MobSpawner] ═══════════════════════════════════")
	print("[MobSpawner] Wave", currentWave, "COMPLETED!")
	print("[MobSpawner] ═══════════════════════════════════")

	FireWaveCompleted(currentWave)

	if CONFIG.AutoAdvanceWaves then
		if CONFIG.MaxWave and currentWave >= CONFIG.MaxWave then
			FireAllWavesCompleted()
			return
		end

		print("[MobSpawner] Next wave in", CONFIG.AutoAdvanceDelay, "seconds...")
		task.wait(CONFIG.AutoAdvanceDelay)
		MobSpawner.StartNextWave()
	end
end

function MobSpawner.StartNextWave()
	return MobSpawner.StartWave(currentWave + 1)
end

-- ═══════════════════════════════════════════════════════════
-- MOB SPAWNING
-- ═══════════════════════════════════════════════════════════

function MobSpawner.SpawnMob(mobId, level)
	level = level or 1

	local template = mobTemplates[mobId]
	if not template then
		warn("[MobSpawner] No template for mob:", mobId)
		return nil
	end

	local mobData = MobRegistry.GetScaledMob(mobId, level)
	if not mobData then
		warn("[MobSpawner] Invalid mob:", mobId)
		return nil
	end

	local mob = template:Clone()
	mob.Name = mobData.name or mobId
	mob:SetAttribute("IsMob", true)
	mob:SetAttribute("MobId", mobId)
	mob:SetAttribute("MobTier", mobData.mobTier or "normal")
	mob:SetAttribute("Level", level)
	mob:SetAttribute("MobElement", mobData.element or "None")

	local rootPart = mob:FindFirstChild("HumanoidRootPart")
	if rootPart and spawnPoint then
		local spawnPos = spawnPoint.CFrame
		local zOffset = (math.random() - 0.5) * 10
		rootPart.CFrame = spawnPos * CFrame.new(0, 0, zOffset)
	end

	local humanoid = mob:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.MaxHealth = mobData.health
		humanoid.Health = mobData.health
	end

	mob.Parent = workspace

	MobAI.RegisterMob(mob, mobId, level)

	return mob
end

function MobSpawner.GetRandomMobId(weights)
	local totalWeight = 0
	for _, weight in pairs(weights) do
		totalWeight = totalWeight + weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0

	for mobId, weight in pairs(weights) do
		cumulative = cumulative + weight
		if roll <= cumulative then
			return mobId
		end
	end

	for mobId, _ in pairs(weights) do
		return mobId
	end
end

-- ═══════════════════════════════════════════════════════════
-- TESTING / CONFIG
-- ═══════════════════════════════════════════════════════════

function MobSpawner.ForceCompleteWave()
	if waveState == "idle" then return false end

	for mob, _ in pairs(MobAI.GetAllMobData()) do
		local humanoid = mob:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end
	return true
end

function MobSpawner.SkipToWave(waveNumber)
	if waveState ~= "idle" then
		MobSpawner.ForceCompleteWave()
		task.wait(0.5)
	end
	currentWave = waveNumber - 1
	return MobSpawner.StartNextWave()
end

function MobSpawner.SetAutoAdvance(enabled)
	CONFIG.AutoAdvanceWaves = enabled
end

function MobSpawner.SetAutoAdvanceDelay(seconds)
	CONFIG.AutoAdvanceDelay = seconds
end

function MobSpawner.SetMaxWave(maxWave)
	CONFIG.MaxWave = maxWave
end

function MobSpawner.GetCurrentWave()
	return currentWave
end

function MobSpawner.IsWaveActive()
	return waveState ~= "idle"
end

function MobSpawner.GetWaveState()
	return waveState
end

function MobSpawner.GetWaveProgress()
	return mobsSpawnedThisWave, mobsToSpawnThisWave
end

function MobSpawner.Reset()
	for mob, _ in pairs(MobAI.GetAllMobData()) do
		if mob and mob.Parent then
			mob:Destroy()
		end
	end
	currentWave = 0
	waveState = "idle"
	mobsSpawnedThisWave = 0
	mobsToSpawnThisWave = 0
	print("[MobSpawner] Reset complete")
end

return MobSpawner