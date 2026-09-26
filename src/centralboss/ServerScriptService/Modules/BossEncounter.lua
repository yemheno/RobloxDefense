-- centralboss/ServerScriptService/Modules/BossEncounter.lua
--[[
    §AGX/X28: CentralBoss fight controller (core).

    Flow (normal GameStateManager path, NOT RequestNextWave — X5):
        Start button → RequestStartGame → Preparing (countdown) → Defending
        Defending  → StartFight: spawn the boss at workspace.BossPoint
        boss HP    → BossPhases behavior flips phases (Mobs/IronWarden.lua)
                     → "BossPhase" attribute → announce + adds (here)
        boss dies  → normal mob death path (DamageHandler → KillRewardManager
                     → XP / boss drops / achievements) → TriggerVictory
        party wipe → DeathSystem (X40 revives, then TriggerDefeat)
        Idle / return to lobby → Cleanup (Janitor; MobSpawner.Reset also
                     destroys every registered mob in ResetGame)

    Network (declared in NetworkManager's manifest):
        BossStateUpdate  { active, bossId, name, hp, maxHp, phase,
                           phaseCount, phaseName, level, difficulty }
                         throttled: ≤5 Hz, sent on ≥1% HP change (or any
                         change after 1 s), plus immediately on spawn /
                         phase / end; snapshot to late joiners on ClientReady.
        BossPhaseChanged { phase, phaseCount, name, text, final? }

    Tuning lives in the boss definition (Mobs/IronWarden.lua). Place-level
    knobs are in CONFIG below.
]]

local BossEncounter = {}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS               = game:GetService("ServerScriptService")

local SharedModules  = SSS:WaitForChild("Modules")
local Janitor        = require(SharedModules:WaitForChild("Janitor"))
local MobSpawnHelper = require(SharedModules:WaitForChild("MobSpawnHelper"))
local PlaceholderRig = require(script.Parent:WaitForChild("PlaceholderRig"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local STATES = require(Shared).GameStates

-- ═══════════════════════════════════════════════════════════
-- CONFIG (place-level; fight tuning is in the boss definition)
-- ═══════════════════════════════════════════════════════════
local CONFIG = {
	BossId            = "iron_warden",           -- MobRegistry id to spawn
	BossPointName     = "BossPoint",             -- spawn + player facing target
	-- Used (in order) when BossPoint is missing; last resort = world origin.
	-- ("BossSpawn" is deliberately absent: GameModeConfig uses that name for
	-- the PLAYER spawn.)
	FallbackSpawnNames = { "MobSpawn" },
	-- Keep BossPoint under the boss so the client FacePoint / camera
	-- follow it (FacePoint live-tracks the part). Restored on cleanup.
	TrackBossPoint    = true,
	WatchInterval     = 0.1,                     -- death / BossPoint tracking tick
	HpSendInterval    = 0.2,                     -- ≤5 Hz
	HpSendMinFraction = 0.01,                    -- send on ≥1% change...
	HpSendStaleAfter  = 1.0,                     -- ...or any change after 1 s
	AddLift           = 3,                       -- studs above floor for adds
	-- Placeholder look for adds when their template (Troll / Ogre) is missing.
	PlaceholderAdd    = { scale = 1.4, bodyColor = Color3.fromRGB(95, 130, 80),
	                      accentColor = Color3.fromRGB(255, 80, 80) },
}

local LOG = "[BossEncounter]"

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════
local deps  = nil   -- set by Setup
local fight = nil   -- current fight record (nil between fights)

-- ═══════════════════════════════════════════════════════════
-- HELPERS (all defined before first use)
-- ═══════════════════════════════════════════════════════════

local _DifficultyConfig = nil
local function getDifficultyConfig()
	if _DifficultyConfig ~= nil then return _DifficultyConfig or nil end
	local mod = Shared:FindFirstChild("DifficultyConfig")
	local ok, result = false, nil
	if mod then ok, result = pcall(require, mod) end
	_DifficultyConfig = (ok and result) or false
	if not _DifficultyConfig then
		warn(LOG, "DifficultyConfig unavailable — boss uses Normal multipliers.")
	end
	return _DifficultyConfig or nil
end

local function anyPlayerAlive()
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("DeathState") == "Alive" then return true end
	end
	return false
end

local function highestPlayerLevel()
	local highest = 1
	local pdm = deps and deps.PlayerDataManager
	for _, p in ipairs(Players:GetPlayers()) do
		local lvl = pdm and pdm.GetAccountData(p, "Level") or 1
		if type(lvl) == "number" and lvl > highest then highest = lvl end
	end
	return highest
end

--- Difficulty overrides in the exact shape MobSpawner.SetDifficulty builds
--- (consumed by MobRegistry.GetScaledMob via MobAI.RegisterMob).
local function difficultyOverrides()
	local diffName = "Normal"
	local tdr = deps and deps.TeleportDataReader
	if tdr and tdr.GetDifficulty then
		diffName = tostring(tdr.GetDifficulty() or "Normal")
	end
	local dc = getDifficultyConfig()
	local diff = dc and dc.GetDifficulty(diffName) or nil
	return {
		hpMult     = diff and diff.hpMult or 1,
		damageMult = diff and diff.damageMult or 1,
		armorMult  = diff and diff.armorMult or 1,
		speedBonus = diff and diff.speedBonus or 0,
	}, diffName
end

local function isFightLive(f)
	return f ~= nil and fight == f and not f.ended
end

local function rayParamsExcluding(extra)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(list, p.Character) end
	end
	for _, inst in ipairs(extra or {}) do
		if inst then table.insert(list, inst) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	return params
end

--- Floor height under `pos` (falls back to pos.Y).
local function floorY(pos, exclude)
	local result = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -500, 0),
		rayParamsExcluding(exclude))
	return result and result.Position.Y or pos.Y
end

--- Resolve (or create) the BossPoint part. Returns part, created.
local function resolveBossPoint()
	local point = workspace:FindFirstChild(CONFIG.BossPointName)
	if point and point:IsA("BasePart") then
		return point, false
	end

	local fallbackPos = Vector3.new(0, 5, 0)
	local fallbackName = "world origin"
	for _, name in ipairs(CONFIG.FallbackSpawnNames) do
		local alt = workspace:FindFirstChild(name)
		if alt and alt:IsA("BasePart") then
			fallbackPos = alt.Position
			fallbackName = name
			break
		end
	end
	warn(string.format("%s workspace.%s missing — spawning at %s and creating a BossPoint there.",
		LOG, CONFIG.BossPointName, fallbackName))

	-- Created so the client FacePoint / FixedBossView have a target.
	point = Instance.new("Part")
	point.Name = CONFIG.BossPointName
	point.Size = Vector3.new(1, 1, 1)
	point.Anchored = true
	point.CanCollide = false
	point.CanQuery = false
	point.CanTouch = false
	point.Transparency = 1
	point.Position = fallbackPos
	point.Parent = workspace
	return point, true
end

-- ── Networking ──────────────────────────────────────────────

local function buildState(f)
	local def = f.def
	local hum = f.humanoid
	local phase = f.announcedPhase
	local phaseDef = def.phases and def.phases[phase]
	return {
		active     = (not f.ended) and hum ~= nil and hum.Health > 0,
		bossId     = def.id,
		name       = def.name or def.id,
		hp         = hum and math.max(0, math.floor(hum.Health + 0.5)) or 0,
		maxHp      = hum and math.floor(hum.MaxHealth + 0.5) or 0,
		phase      = phase,
		phaseCount = def.phases and #def.phases or 1,
		phaseName  = phaseDef and phaseDef.name or nil,
		level      = f.level,
		difficulty = f.difficulty,
	}
end

local function broadcastState(f)
	if not f or not deps then return end
	local state = buildState(f)
	f.lastSentHp = state.hp
	f.lastSentAt = os.clock()
	deps.NetworkManager.FireAllClients("BossStateUpdate", state)
end

local function broadcastInactive()
	if not deps then return end
	deps.NetworkManager.FireAllClients("BossStateUpdate", { active = false })
end

-- ── Adds (phase summons) ────────────────────────────────────

local function countAliveAdds(f)
	local n = 0
	for mob in pairs(f.adds) do
		local hum = mob.Parent and mob:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			n += 1
		else
			f.adds[mob] = nil
		end
	end
	return n
end

--- Last-resort add when the mob's template is missing in this place:
--- same attributes MobSpawner.SpawnMob sets, placeholder body.
local function spawnPlaceholderAdd(f, mobId)
	local MobRegistry = deps.MobRegistry
	local mobDef = MobRegistry.GetMob(mobId)
	if not mobDef then return nil end
	local rigOpts = table.clone(CONFIG.PlaceholderAdd)
	rigOpts.name  = mobDef.name or mobId
	rigOpts.label = (mobDef.name or mobId) .. " (placeholder)"
	local mob = PlaceholderRig.Build(rigOpts)
	mob:SetAttribute("IsMob", true)
	mob:SetAttribute("MobId", mobId)
	mob:SetAttribute("MobTier", mobDef.mobTier or "normal")
	mob:SetAttribute("Level", f.level)
	mob:SetAttribute("RewardLevel", f.rewardLevel)
	mob:SetAttribute("MobElement", mobDef.element or "None")
	mob:SetAttribute("KnockbackResist", mobDef.knockbackResist or 0)
	mob.Parent = workspace
	local data = deps.MobAI.RegisterMob(mob, mobId, f.level, f.addOverrides)
	if not data then
		mob:Destroy()
		return nil
	end
	mob:SetAttribute("Armor", data.config.armor or 0)
	return mob
end

local function spawnAdd(f, summon)
	local mobId = MobSpawnHelper.PickWeightedId(summon.pool or {})
	if not mobId then return end
	-- Guard: never let a pool typo summon another boss.
	if deps.MobRegistry.GetMobTier(mobId) == "boss" then
		warn(LOG, "summon pool contains boss-tier mob", mobId, "— skipped.")
		return
	end

	-- Normal spawn helper first (template clone + difficulty + RewardLevel);
	-- placeholder body only when this place has no template for it.
	local mob = deps.MobSpawner.SpawnMob(mobId, f.level)
	if not mob then
		mob = spawnPlaceholderAdd(f, mobId)
	end
	if not mob then
		warn(LOG, "could not summon add", mobId)
		return
	end

	local center = f.root and f.root.Position or f.spawnPos
	local angle = math.random() * math.pi * 2
	local radius = summon.radius or 18
	local pos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local y = floorY(pos, { f.boss, mob, f.bossPoint })
	mob:PivotTo(CFrame.new(pos.X, y + PlaceholderRig.GetStandOffset(mob) + 0.5, pos.Z))
	f.adds[mob] = true
end

local function startSummonLoop(f, summon)
	f.janitor:Add(task.spawn(function()
		task.wait(summon.firstDelay or 2)
		while isFightLive(f) do
			if deps.GameStateManager.IsDefending() and anyPlayerAlive() then
				local cap = summon.maxAlive or 4
				for _ = 1, (summon.count or 2) do
					if not isFightLive(f) or countAliveAdds(f) >= cap then break end
					spawnAdd(f, summon)
				end
			end
			task.wait(summon.every or 20)
		end
	end), "summonLoop")   -- keyed: a later summoning phase replaces the loop
end

-- ── Phases ──────────────────────────────────────────────────

local function onPhaseChanged(f, index)
	if not isFightLive(f) or type(index) ~= "number" then return end
	if index <= f.announcedPhase then return end   -- respawn / re-apply: no repeat
	f.announcedPhase = index

	local phase = f.def.phases and f.def.phases[index] or {}
	deps.NetworkManager.FireAllClients("BossPhaseChanged", {
		phase      = index,
		phaseCount = f.def.phases and #f.def.phases or 1,
		name       = phase.name or ("Phase " .. index),
		text       = phase.announce or ((f.def.name or "Boss") .. " — " .. (phase.name or ("Phase " .. index))),
	})
	broadcastState(f)
	print(string.format("%s %s entered phase %d (%s)", LOG, f.def.id, index, tostring(phase.name)))

	if phase.summon then
		startSummonLoop(f, phase.summon)
	end
end

-- ── Victory ─────────────────────────────────────────────────

local function onBossDefeated(f)
	if not f or f.defeated or fight ~= f then return end
	f.defeated = true
	f.ended = true

	-- Clear the arena: leftover adds pay nothing.
	for mob in pairs(f.adds) do
		if mob.Parent then mob:Destroy() end
	end
	table.clear(f.adds)

	deps.NetworkManager.FireAllClients("BossPhaseChanged", {
		phase = f.announcedPhase,
		phaseCount = f.def.phases and #f.def.phases or 1,
		name  = "Defeated",
		text  = (f.def.name or "The boss") .. " has fallen!",
		final = true,
	})
	broadcastState(f)
	print(LOG, f.def.id, "defeated — triggering victory")
	deps.GameStateManager.TriggerVictory()
end

-- ── Spawning the boss ───────────────────────────────────────

--- Spawn (or re-spawn) the boss. `hpFraction` restores HP on a re-spawn.
local function spawnBoss(f, hpFraction)
	local def = f.def
	local MobAI = deps.MobAI

	local model
	local mobsFolder = ReplicatedStorage:FindFirstChild("Mobs")
	local template = def.template and mobsFolder and mobsFolder:FindFirstChild(def.template)
	if template then
		model = MobSpawnHelper.CloneTemplate(template, def.id, LOG, function()
			return not isFightLive(f)
		end)
	else
		local rigOpts = table.clone(def.placeholderRig or {})
		rigOpts.name = def.name or def.id
		model = PlaceholderRig.Build(rigOpts)
	end
	if not model then return false end

	model.Name = def.name or def.id
	model:SetAttribute("IsMob", true)
	model:SetAttribute("IsBoss", true)
	model:SetAttribute("MobId", def.id)
	model:SetAttribute("MobTier", def.mobTier or "boss")
	model:SetAttribute("Level", f.level)
	model:SetAttribute("RewardLevel", f.rewardLevel)
	model:SetAttribute("MobElement", def.element or "None")
	model:SetAttribute("KnockbackResist", def.knockbackResist or 0)

	model.Parent = workspace
	local y = floorY(f.spawnPos, { model, f.bossPoint })
	local yaw = f.spawnYaw or CFrame.new()
	model:PivotTo(CFrame.new(f.spawnPos.X, y + PlaceholderRig.GetStandOffset(model), f.spawnPos.Z) * yaw)

	local mobData = MobAI.RegisterMob(model, def.id, f.level, f.bossOverrides)
	if not mobData then
		warn(LOG, "MobAI.RegisterMob failed for", def.id, "— boss not spawned")
		model:Destroy()
		return false
	end
	model:SetAttribute("Armor", mobData.config.armor or 0)

	local humanoid = mobData.humanoid
	if hpFraction and hpFraction > 0 and hpFraction < 1 then
		humanoid.Health = math.max(1, humanoid.MaxHealth * hpFraction)
	end

	-- §AGX/X45: pin physics to the server (no client-owned boss).
	local root = mobData.rootPart
	pcall(function() root:SetNetworkOwner(nil) end)

	f.boss, f.humanoid, f.root = model, humanoid, root
	f.janitor:Add(model, "bossModel")

	-- Per-boss connections die with the model (§5.2 LinkToInstance).
	local bossJan = Janitor.new()
	bossJan:LinkToInstance(model)
	f.janitor:Add(bossJan, "bossJanitor")
	bossJan:Add(humanoid.Died:Connect(function()
		onBossDefeated(f)
	end))
	bossJan:Add(model:GetAttributeChangedSignal("BossPhase"):Connect(function()
		onPhaseChanged(f, model:GetAttribute("BossPhase"))
	end))

	-- BossPhases.Init already set phase 1 inside RegisterMob.
	onPhaseChanged(f, model:GetAttribute("BossPhase") or 1)
	broadcastState(f)
	return true
end

-- ── Loops ───────────────────────────────────────────────────

local function watchLoop(f)
	while isFightLive(f) do
		task.wait(CONFIG.WatchInterval)
		if not isFightLive(f) then break end
		local hum, boss = f.humanoid, f.boss

		if hum and hum.Health <= 0 then
			onBossDefeated(f)
			break
		end

		if boss and not boss.Parent then
			-- Removed WITHOUT dying (fell off the map, deleted in Studio).
			local frac = (hum and hum.MaxHealth > 0) and (hum.Health / hum.MaxHealth) or 1
			if deps.GameStateManager.IsDefending() then
				warn(string.format("%s boss left the workspace alive (%.0f%% HP) — re-spawning.", LOG, frac * 100))
				f.boss, f.humanoid, f.root = nil, nil, nil
				spawnBoss(f, frac)
			end
		elseif CONFIG.TrackBossPoint and f.root and f.bossPoint and f.bossPoint.Parent then
			local rp = f.root.Position
			local bp = f.bossPoint.Position
			if (Vector3.new(rp.X, bp.Y, rp.Z) - bp).Magnitude > 0.25 then
				f.bossPoint.CFrame = f.bossPoint.CFrame.Rotation + Vector3.new(rp.X, bp.Y, rp.Z)
			end
		end
	end
end

local function hpLoop(f)
	while fight == f and not f.defeated do
		task.wait(CONFIG.HpSendInterval)
		local hum = f.humanoid
		if hum and fight == f and not f.ended then
			local hp = math.max(0, math.floor(hum.Health + 0.5))
			local last = f.lastSentHp or -1
			if hp ~= last then
				local bigEnough = math.abs(hp - last) >= hum.MaxHealth * CONFIG.HpSendMinFraction
				local stale = (os.clock() - (f.lastSentAt or 0)) >= CONFIG.HpSendStaleAfter
				if bigEnough or stale then
					broadcastState(f)
				end
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════

function BossEncounter.Init()
	-- Events are declared in NetworkManager's manifest; touch them so a
	-- missing manifest entry fails loudly at boot, not mid-fight.
	local nm = require(SharedModules:WaitForChild("NetworkManager"))
	nm.GetEvent("BossStateUpdate")
	nm.GetEvent("BossPhaseChanged")
end

--- Tear down the current fight (idempotent). Destroys the boss, adds,
--- loops and a created BossPoint; restores a designer-placed BossPoint.
function BossEncounter.Cleanup()
	local f = fight
	if not f then return end
	fight = nil
	f.ended = true
	f.janitor:Destroy()
	broadcastInactive()
end

--- Called on entering Defending.
function BossEncounter.StartFight()
	if not deps then
		warn(LOG, "StartFight before Setup — ignored")
		return
	end
	BossEncounter.Cleanup()

	local def = deps.MobRegistry.GetMob(CONFIG.BossId)
	if not def then
		warn(LOG, "boss", CONFIG.BossId, "is not registered in MobRegistry — no fight.")
		return
	end
	local bossCfg = def.boss or {}

	local jan = Janitor.new()
	local f = {
		janitor        = jan,
		def            = def,
		adds           = {},
		announcedPhase = 0,
		ended          = false,
		defeated       = false,
	}
	fight = f

	-- Level: party anchor (highest player level), same rule as the lane.
	local anchor = highestPlayerLevel()
	f.level       = math.max(1, anchor + (bossCfg.levelOffset or 0))
	f.rewardLevel = math.max(5, anchor)
	-- Adds spawned through MobSpawner carry the same frozen RewardLevel.
	deps.MobSpawner.SetPartyAnchorLevel(anchor)

	-- Difficulty (DifficultyConfig via TeleportDataReader) × player count.
	local overrides, diffName = difficultyOverrides()
	local playerCount = math.max(1, #Players:GetPlayers())
	local playerMult = 1 + (bossCfg.hpPerExtraPlayer or 0.75) * (playerCount - 1)
	f.difficulty   = diffName
	f.addOverrides = overrides
	f.bossOverrides = {
		hpMult     = overrides.hpMult * playerMult,
		damageMult = overrides.damageMult,
		armorMult  = overrides.armorMult,
		speedBonus = overrides.speedBonus,
	}

	-- Arena.
	local point, created = resolveBossPoint()
	f.bossPoint = point
	f.spawnPos  = point.Position
	f.spawnYaw  = point.CFrame.Rotation
	local originalCFrame = point.CFrame
	jan:Add(function()
		if created then
			point:Destroy()
		elseif point.Parent then
			point.CFrame = originalCFrame
		end
	end)
	-- Adds are destroyed with the fight (MobSpawner.Reset also sweeps them).
	jan:Add(function()
		for mob in pairs(f.adds) do
			if mob.Parent then mob:Destroy() end
		end
		table.clear(f.adds)
	end)

	print(string.format("%s spawning %s — Lv %d, %s, %d player(s), HP x%.2f (difficulty %.2f × players %.2f)",
		LOG, def.id, f.level, diffName, playerCount,
		f.bossOverrides.hpMult, overrides.hpMult, playerMult))

	if not spawnBoss(f, nil) then
		BossEncounter.Cleanup()
		return
	end

	jan:Add(task.spawn(watchLoop, f))
	jan:Add(task.spawn(hpLoop, f))
end

--- Called on Victory / Defeat: stop loops (boss & adds stay until Idle).
function BossEncounter.StopFight(newState)
	local f = fight
	if not f then return end
	f.ended = true
	if newState == STATES.DEFEAT then
		broadcastInactive()
	end
end

function BossEncounter.GetBoss()
	return fight and fight.boss or nil
end

--- Studio/admin helper: set boss HP to a fraction of max (e.g. 0.5 to
--- jump to phase 2). Kills go through DamageHandler, not this.
function BossEncounter.DebugSetHpFraction(fraction)
	local f = fight
	if type(fraction) ~= "number" or fraction ~= fraction then return false end
	if not (f and f.humanoid and f.humanoid.Health > 0) then return false end
	fraction = math.clamp(fraction, 0.01, 1)
	f.humanoid.Health = f.humanoid.MaxHealth * fraction
	return true
end

--- Wire the encounter into this place. Call once after LateInit.
--- d = { GameStateManager, MobAI, MobRegistry, MobSpawner, NetworkManager,
---       TeleportDataReader, PlayerDataManager, ReadyGate }
function BossEncounter.Setup(d)
	assert(d and d.GameStateManager and d.MobAI and d.MobRegistry and d.MobSpawner
		and d.NetworkManager, "BossEncounter.Setup: missing dependencies")
	deps = d

	-- The fight, not wave 1, starts on Defending (see header / X5).
	d.GameStateManager.suppressWaveStart = true
	-- Arena targeting: no lane X-filter, no perception cap, idle (not
	-- marching -X) when nobody is targetable.
	d.MobAI.SetHordeModeTargeting(true)

	d.GameStateManager.OnStateChanged(function(newState)
		if newState == STATES.DEFENDING then
			BossEncounter.StartFight()
		elseif newState == STATES.VICTORY or newState == STATES.DEFEAT then
			BossEncounter.StopFight(newState)
		elseif newState == STATES.IDLE then
			BossEncounter.Cleanup()
		end
	end)
	d.GameStateManager.OnReturnToLobby(function()
		BossEncounter.Cleanup()
	end)

	-- Late joiners / reloads get the current bar once their UI is up.
	if d.ReadyGate and d.ReadyGate.OnReady then
		d.ReadyGate.OnReady(function(player)
			local f = fight
			if f and not f.ended and player.Parent then
				d.NetworkManager.FireClient(player, "BossStateUpdate", buildState(f))
			end
		end)
	end
end

return BossEncounter
