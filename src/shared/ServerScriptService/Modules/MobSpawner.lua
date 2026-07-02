-- ServerScriptService/Modules/MobSpawner

local MobSpawner = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = script.Parent
local MobAI = require(Modules:WaitForChild("MobAI"))
local MobRegistry = require(Modules:WaitForChild("MobRegistry"))
local WaveConfig = require(Modules:WaitForChild("WaveConfig"))
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local MobSpawnHelper = require(Modules:WaitForChild("MobSpawnHelper"))  -- §T3/W9

-- RunModifiers (lazy-loaded)
local RunModifiers      = nil
local runModifiersLoaded = false

local function getRunModifiers()
	if not runModifiersLoaded then
		runModifiersLoaded = true
		local rm = Modules:FindFirstChild("RunModifiers")
		if rm then RunModifiers = require(rm) end
	end
	return RunModifiers
end

-- CosmeticManager loaded lazily (applies mob visual variants)
local CosmeticManager = nil

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

-- §2.2e: Wave cap and future infinite mode.
--
--   MaxWave = 12 is the current Horde Mode alpha design. A run is twelve
--   authored waves with anchored party-level scaling; the run ends at wave 12
--   and AllWavesCompleted fires so HordeModeMain can award victory rewards.
--
--   Setting MaxWave = nil disables the cap and the spawner will keep
--   auto-advancing indefinitely. This is the intended hook for a future
--   "Endless / Infinite Horde" mode. When that ships we should:
--     1. Let the mode select its own cap (nil = endless, N = capped).
--     2. Promote MaxWave from this CONFIG table into a mode-scoped setting
--        (e.g. HordeMode vs EndlessMode pass their own value via Setup()).
--     3. Make sure WaveConfig has a fallback for wave numbers beyond the
--        authored list (procedural difficulty curve).
--     4. Revisit reward pacing — current merit/xp payouts assume a 12-wave
--        ceiling.
local CONFIG = {
	AutoAdvanceWaves = true,
	AutoAdvanceDelay = 7,    -- 7s between waves (was 3)
	MaxWave = 12,            -- fixed 12-wave run; set to nil for endless (see §2.2e note above)
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

-- Optional hook: called before mob spawning starts.  If set, SpawnWave waits
-- for it to complete.  LaneDefenseMain uses this to gate spawns on vote resolution.
local preSpawnHook = nil

-- Active difficulty tier name ("Normal" | "Hard" | "Nightmare")
local activeDifficulty = nil
local activeDifficultyOverrides = nil   -- cached { hpMult, damageMult, armorMult, speedBonus }

-- Party anchor level: when set, mob level = (anchorLevel - 1) + floor((wave-1)/2)
-- so level starts 1 below party and gains +1 every 2 waves.
local partyAnchorLevel = nil

-- Frozen reward level for XP delta calculation (min 5).
-- Set once by SetPartyAnchorLevel(); mobs carry this as RewardLevel attribute.
local rewardLevel = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function MobSpawner.Init()
	-- §2.2a fix: hard-error if the mobs folder never arrives. Previously Init
	-- would warn and fall through, letting CacheTemplates crash later on a nil
	-- FindFirstChild and masking the real cause behind a zero template count.
	mobsFolder = ReplicatedStorage:WaitForChild("Mobs", 10)
	if not mobsFolder then
		error("[MobSpawner] ReplicatedStorage/Mobs folder not found after 10s — " ..
			"check MobAssetLoader; cannot continue without templates.", 2)
	end
	MobSpawner.CacheTemplates()

	-- §MS-INIT1: resolve spawnPoint eagerly when present, but DO NOT
	-- hard-error here. HordeMode loads this module for type sharing but
	-- never calls StartWave — it uses HordeModeSpawner instead. Failing
	-- Init in that place would cascade-fail every later module load. The
	-- real hard-fail moves into StartWave, which only runs in places that
	-- actually need a MobSpawn part (LaneDefense, CentralBoss).
	spawnPoint = workspace:FindFirstChild("MobSpawn")
	if not spawnPoint then
		warn("[MobSpawner] workspace/MobSpawn not found at Init — wave-driven " ..
			"spawning will hard-error if StartWave is later called. This is normal " ..
			"in HordeMode, expected to be present in LaneDefense / CentralBoss.")
	end

	-- Lazy-load CosmeticManager (may not exist yet at Init time)
	task.spawn(function()
		local cm = Modules:FindFirstChild("CosmeticManager")
		if cm then
			CosmeticManager = require(cm)
		end
	end)

	NetworkManager.GetEvent("WaveStarted")
	NetworkManager.GetEvent("WaveCompleted")
	NetworkManager.GetEvent("AllWavesCompleted")
	NetworkManager.GetEvent("RequestNextWave")

	NetworkManager.OnClientEvent("RequestNextWave", function(_player)
		if waveState == "idle" then
			MobSpawner.StartNextWave()
		end
	end)

	print("  AutoAdvanceWaves:", CONFIG.AutoAdvanceWaves)
	print("  Templates cached:", MobSpawner.GetTemplateCount())
end

-- ═══════════════════════════════════════════════════════════
-- DIFFICULTY
-- ═══════════════════════════════════════════════════════════

--- Set the active difficulty tier for all subsequent waves.
--- @param tierName string  "Normal", "Hard", or "Nightmare"
function MobSpawner.SetDifficulty(tierName)
	local ok, DifficultyConfig = pcall(function()
		local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
		if not shared then return nil end
		local mod = shared:FindFirstChild("DifficultyConfig")
		if not mod then return nil end
		return require(mod)
	end)

	if ok and DifficultyConfig and DifficultyConfig.IsValid then
		if DifficultyConfig.IsValid(tierName) then
			activeDifficulty = tierName
			local diff = DifficultyConfig.GetDifficulty(tierName)
			activeDifficultyOverrides = {
				hpMult      = diff.hpMult,
				damageMult  = diff.damageMult,
				armorMult   = diff.armorMult,
				speedBonus  = diff.speedBonus,
			}
			print("[MobSpawner] Difficulty set to:", tierName)
		else
			warn("[MobSpawner] Invalid difficulty tier:", tierName, "— defaulting to Normal")
			activeDifficulty = "Normal"
			activeDifficultyOverrides = nil
		end
	else
		warn("[MobSpawner] DifficultyConfig not available — using Normal difficulty")
		activeDifficulty = "Normal"
		activeDifficultyOverrides = nil
	end
end

function MobSpawner.GetDifficulty()
	return activeDifficulty or "Normal"
end

--- Anchor mob levels to the party's highest player level.
--- Also freezes the RewardLevel (min 5) for the entire run.
--- Has no effect until the next wave spawn.
function MobSpawner.SetPartyAnchorLevel(level)
	partyAnchorLevel = math.max(1, level or 1)
	rewardLevel      = math.max(5, partyAnchorLevel)  -- frozen for XP delta; min 5
	print("[MobSpawner] Party anchor level:", partyAnchorLevel, "| RewardLevel:", rewardLevel)
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
				warn("[MobSpawner] Missing template for", mobId, ":", templateName,
					"— not found in", mobsFolder:GetFullName())
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

--- Set a function that is called (and awaited) before every wave's mobs begin
--- spawning.  The function receives (waveNumber) and should return when ready.
function MobSpawner.SetPreSpawnHook(fn)
	preSpawnHook = fn
end

-- §LD-V2 fix: split the wave-started signal into two parts.
-- FireWaveStarted now ONLY fires server-side callbacks (used by
-- LaneDefenseMain to start the tactical vote — needs to run BEFORE the
-- preSpawnHook waits for that vote to resolve).
-- BroadcastWaveStarted fires the network event the HUD listens to for
-- the "WAVE N" banner; this is delayed in SpawnWave until AFTER the
-- preSpawnHook completes so the banner appears the moment mobs are
-- about to spawn, not while the vote card is still on screen.
local function FireWaveStarted(waveNumber, mobCount, level)
	for _, callback in ipairs(onWaveStartedCallbacks) do
		task.spawn(callback, waveNumber, mobCount, level)
	end
end

local function BroadcastWaveStarted(waveNumber, mobCount, level)
	NetworkManager.FireAllClients("WaveStarted", {
		wave = waveNumber,
		mobCount = mobCount,
		level = level,
	})
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
	-- §MS-INIT1: enforce MobSpawn presence here, not at Init.
	-- Re-resolve in case a map streamed it in late.
	if not spawnPoint then
		spawnPoint = workspace:FindFirstChild("MobSpawn")
	end
	if not spawnPoint then
		error("[MobSpawner] StartWave called but workspace/MobSpawn is missing. " ..
			"This place needs a Part named 'MobSpawn' or it must use HordeModeSpawner " ..
			"and never call StartWave.", 2)
	end
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

	local waveData = WaveConfig.GetWave(waveNumber, activeDifficulty)

	currentWave = waveNumber
	waveState = "spawning"
	mobsSpawnedThisWave = 0
	local guaranteed = waveData.guaranteed or {}
	mobsToSpawnThisWave = waveData.mobCount + #guaranteed

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
	-- Wait for pre-spawn hook (e.g. tactical vote) before spawning.
	-- §2.2d: pcall the hook so a thrown error can't dead-lock the wave,
	-- and log the actual elapsed time on both success and timeout so we
	-- can tell whether 10s is a reasonable budget in practice.
	-- §LD-V2 fix: bumped budget from 10s → 20s. Vote timer is 10s and the
	-- §LD-V1 card-display hold adds 3.5s more, so realistic vote-driven
	-- pre-spawns are ~13–14s; the old 10s budget would have started
	-- timing out spuriously after the V1 fix.
	if preSpawnHook then
		local PRE_SPAWN_HOOK_TIMEOUT = 20
		local hookDone = false
		local hookErr = nil
		local startClock = os.clock()
		task.spawn(function()
			local ok, err = pcall(preSpawnHook, currentWave)
			if not ok then
				hookErr = err
				warn("[MobSpawner] preSpawnHook threw: " .. tostring(err))
			end
			hookDone = true
		end)
		local elapsed = 0
		while not hookDone and elapsed < PRE_SPAWN_HOOK_TIMEOUT do
			task.wait(0.1)
			elapsed = elapsed + 0.1
		end
		local actualElapsed = os.clock() - startClock
		if not hookDone then
			warn(string.format(
				"[MobSpawner] preSpawnHook timed out after %.1fs (budget %ds) — proceeding without its result. " ..
				"If this fires regularly, raise PRE_SPAWN_HOOK_TIMEOUT or shorten the hook.",
				actualElapsed, PRE_SPAWN_HOOK_TIMEOUT
			))
		elseif hookErr then
			warn(string.format("[MobSpawner] preSpawnHook completed with error in %.2fs.", actualElapsed))
		elseif actualElapsed > PRE_SPAWN_HOOK_TIMEOUT * 0.8 then
			warn(string.format(
				"[MobSpawner] preSpawnHook took %.2fs (>80%% of %ds budget) — near timeout.",
				actualElapsed, PRE_SPAWN_HOOK_TIMEOUT
			))
		end
	end

	-- §LD-V2: now that the pre-spawn hook (vote / card display / etc.) has
	-- resolved, broadcast the WaveStarted client event so the HUD banner
	-- appears in sync with mobs actually arriving. Server-side
	-- onWaveStartedCallbacks already fired earlier in StartWave so any
	-- mode-specific wave-trigger logic (vote start, danger reset) ran on
	-- time.
	BroadcastWaveStarted(currentWave, mobsToSpawnThisWave, waveData.level)

	-- Compute effective mob level.
	-- When anchored to party level: starts at partyAnchorLevel-1, +1 every 2 waves.
	-- Falls back to wave number if no anchor is set.
	local level
	if partyAnchorLevel then
		level = math.max(1, (partyAnchorLevel - 1) + math.floor((currentWave - 1) / 2))
	else
		level = waveData.level or currentWave
	end

	local rm = getRunModifiers()

	-- Apply RunModifiers to wave parameters
	local spawnInterval = waveData.spawnInterval
	local mobCount      = waveData.mobCount
	if rm then
		spawnInterval = math.max(0.3, spawnInterval * (1 + rm.GetModifier("spawnIntervalScalar")))
		mobCount      = math.ceil(mobCount * (1 + rm.GetModifier("normalMobCountScalar")))
	end

	-- Build effective difficulty overrides with RunModifiers stacked on top
	local effectiveOverrides = activeDifficultyOverrides
	if rm then
		local baseOverrides = activeDifficultyOverrides or { hpMult = 1, damageMult = 1, armorMult = 1, speedBonus = 0 }
		local hpS = rm.GetModifier("hpScalar")
		local dmgS = rm.GetModifier("damageScalar")
		local armS = rm.GetModifier("armorFlatBonus")
		if hpS ~= 0 or dmgS ~= 0 or armS ~= 0 then
			effectiveOverrides = {
				hpMult     = baseOverrides.hpMult     * (1 + hpS),
				damageMult = baseOverrides.damageMult * (1 + dmgS),
				armorMult  = baseOverrides.armorMult,
				speedBonus = baseOverrides.speedBonus,
				armorFlatBonus = armS,
			}
		end
	end

	-- §2.2b: waves can't silently miss mobs. If SpawnMob returns nil after its
	-- internal pcall retries, we re-queue the same mobId (bounded by
	-- MAX_WAVE_REQUEUES per slot) so the wave completes at the intended count.
	local MAX_WAVE_REQUEUES = 3
	for _, mobId in ipairs(waveData.guaranteed or {}) do
		if waveState == "idle" then return end -- abort if reset during spawn
		local spawned, tries = nil, 0
		while not spawned and tries < MAX_WAVE_REQUEUES and waveState ~= "idle" do
			spawned = MobSpawner.SpawnMob(mobId, level, effectiveOverrides)
			tries = tries + 1
			if not spawned then
				warn(string.format(
					"[MobSpawner] Guaranteed spawn failed for %s (try %d/%d); re-queueing.",
					tostring(mobId), tries, MAX_WAVE_REQUEUES
				))
				task.wait(0.25)
			end
		end
		if not spawned and waveState ~= "idle" then
			-- §T3/W9: with never-fail clone, reaching here means a CONFIG
			-- error (unknown mobId / missing template) — requeues can't fix it.
			warn(string.format(
				"[MobSpawner] Guaranteed slot %s UNRECOVERABLE (config error?) after %d re-queues — wave count will be short.",
				tostring(mobId), MAX_WAVE_REQUEUES
			))
		end
		mobsSpawnedThisWave = mobsSpawnedThisWave + 1
		task.wait(spawnInterval)
	end

	-- Consume extra miniboss charges: inject as first N normal-slot spawns
	local minibossesInjected = 0
	if rm then
		while rm.ConsumeMinibossCharge() do
			minibossesInjected = minibossesInjected + 1
		end
	end

	for i = 1, mobCount do
		if waveState == "idle" then return end -- abort if reset during spawn
		local mobId
		if minibossesInjected > 0 then
			-- Pick the heaviest available mob type for injected minibosses
			if waveData.spawnWeights.Ogre then mobId = "Ogre"
			elseif waveData.spawnWeights.Troll then mobId = "Troll"
			else mobId = MobSpawner.GetRandomMobId(waveData.spawnWeights) end
			minibossesInjected = minibossesInjected - 1
		else
			mobId = MobSpawner.GetRandomMobId(waveData.spawnWeights)
		end
		-- §2.2b: re-queue on SpawnMob failure so wave counts stay intact.
		local spawned, tries = nil, 0
		while not spawned and tries < MAX_WAVE_REQUEUES and waveState ~= "idle" do
			spawned = MobSpawner.SpawnMob(mobId, level, effectiveOverrides)
			tries = tries + 1
			if not spawned then
				warn(string.format(
					"[MobSpawner] Wave spawn failed for %s (try %d/%d); re-queueing.",
					tostring(mobId), tries, MAX_WAVE_REQUEUES
				))
				task.wait(0.25)
			end
		end
		if not spawned and waveState ~= "idle" then
			-- §T3/W9: only reachable on a config error now (see above).
			warn(string.format(
				"[MobSpawner] Wave slot %s UNRECOVERABLE (config error?) after %d re-queues — wave count will be short.",
				tostring(mobId), MAX_WAVE_REQUEUES
			))
		end
		mobsSpawnedThisWave = mobsSpawnedThisWave + 1
		task.wait(spawnInterval)
	end

	waveState = "active"
	MobSpawner.WaitForWaveClear()
end

function MobSpawner.WaitForWaveClear()
	waveState = "clearing"

	while MobAI.IsAnyMobAlive() do
		task.wait(0.5)
		-- Abort if Reset() was called externally (e.g. game over / defeat)
		if waveState == "idle" then return end
	end

	-- Double-check: another system may have called Reset() between the last
	-- IsAnyMobAlive() check and here — bail if state was already reset.
	if waveState ~= "clearing" then return end

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

		task.wait(CONFIG.AutoAdvanceDelay)
		-- Check again after delay — game may have ended during the wait
		if waveState ~= "idle" then return end
		MobSpawner.StartNextWave()
	end
end

function MobSpawner.StartNextWave()
	return MobSpawner.StartWave(currentWave + 1)
end

-- ═══════════════════════════════════════════════════════════
-- MOB SPAWNING
-- ═══════════════════════════════════════════════════════════

function MobSpawner.SpawnMob(mobId, level, overridesArg)
	level = level or 1

	local template = mobTemplates[mobId]
	if not template then
		warn("[MobSpawner] No template for mob:", mobId)
		return nil
	end

	local effectiveOverrides = overridesArg or activeDifficultyOverrides
	local mobData = MobRegistry.GetScaledMob(mobId, level, effectiveOverrides)
	if not mobData then
		warn("[MobSpawner] Invalid mob:", mobId)
		return nil
	end

	-- §T3/W9a: NEVER-FAIL clone (Pablo: runs must always deliver the full
	-- mob count — a skipped miniboss is a blunder). Retries forever with
	-- backoff; returns nil only if the wave was reset while retrying.
	local mob = MobSpawnHelper.CloneTemplate(template, mobId, "[MobSpawner]",
		function() return waveState == "idle" end)
	if not mob then return nil end

	mob.Name = mobData.name or mobId
	mob:SetAttribute("IsMob", true)
	mob:SetAttribute("MobId", mobId)
	mob:SetAttribute("MobTier", mobData.mobTier or "normal")
	mob:SetAttribute("Level", level)
	mob:SetAttribute("RewardLevel", rewardLevel or math.max(5, level))
	mob:SetAttribute("MobElement", mobData.element or "None")
	mob:SetAttribute("Armor", mobData.armor or 0)
	mob:SetAttribute("KnockbackResist", mobData.knockbackResist or 0)

	-- §2.2c fix: spawnPoint is resolved eagerly in Init(); no lazy fallback here.

	local humanoid = mob:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.MaxHealth = mobData.health
		humanoid.Health = mobData.health
	end

	-- Parent before positioning so the physics context is live.
	-- PivotTo moves the ENTIRE assembled model as a unit, which avoids a
	-- race where Motor6D joints haven't snapped on the first physics frame
	-- (the root cause of the "phantom box at spawn" intermittent bug).
	mob.Parent = workspace
	if spawnPoint then
		-- §T3/W9b: uniform scatter across the WHOLE spawn part (was a
		-- fixed-X, ±5-stud-Z line). Resize the spawn part in Studio to
		-- reshape the area. Keeps the §LD-MS1 3-stud ground-clip lift.
		mob:PivotTo(MobSpawnHelper.GetSpawnCFrame(spawnPoint, 3))
	end

	MobAI.RegisterMob(mob, mobId, level, activeDifficultyOverrides)

	-- Apply cosmetic variant (recolor / features) if CosmeticManager is loaded
	if CosmeticManager then
		CosmeticManager.ApplyMobVariant(mob, mobId)
	end

	return mob
end

-- §T3/W9: delegates to the shared helper (was a verbatim copy of the
-- same algorithm living in HordeModeSpawner too).
function MobSpawner.GetRandomMobId(weights)
	return MobSpawnHelper.PickWeightedId(weights)
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

function MobSpawner.SetAutoAdvance(enabled)
	CONFIG.AutoAdvanceWaves = enabled
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
	-- §T3/W1: clear the per-run level anchors. Servers are one-run today
	-- (DQ-C), but if Reset is ever used for an in-place rerun, a stale
	-- anchor would spawn old-party-level mobs for a fresh party.
	partyAnchorLevel = nil
	rewardLevel = nil
	print("[MobSpawner] Reset complete")
end

return MobSpawner