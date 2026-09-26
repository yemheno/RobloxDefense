-- ServerScriptService/Modules/MobAI

local MobAI = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = script.Parent
local MobRegistry = require(Modules:WaitForChild("MobRegistry"))
local MobSkillRegistry = require(Modules:WaitForChild("MobSkillRegistry"))
local StatsManager = require(Modules:WaitForChild("StatsManager"))
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local MobBehaviors   = require(Modules:WaitForChild("MobBehaviors"))
local MobSpawnHelper = require(Modules:WaitForChild("MobSpawnHelper"))  -- §AGX/X45: PinServerOwnership

-- Lazy-loaded
local HitTracker = nil
local MonitoringSystem = nil

-- §AGX/X12: DamageHandler, lazy (§5.3 pattern, `false` = looked, not found).
-- Thorns kills route through DamageHandler.ApplyRawDamage and the Died
-- safety net asks IsDeathHandled. Lazy so there's no load-order coupling
-- with AttackHandler.
local _DamageHandler = nil
local function getDamageHandler()
	if _DamageHandler ~= nil then
		return _DamageHandler or nil
	end
	local ah = Modules:FindFirstChild("AttackHandler")
	local mod = ah and ah:FindFirstChild("DamageHandler")
	if not mod then
		_DamageHandler = false
		warn("[MobAI] DamageHandler not found — Thorns kills skip the death path.")
		return nil
	end
	local ok, result = pcall(require, mod)
	_DamageHandler = ok and result or false
	return _DamageHandler or nil
end

-- §AGX/X12: a registered mob whose Humanoid died but that nobody Destroy()ed
-- within this window (a kill from a path that still bypasses HandleMobDeath)
-- is removed, so corpses can't pile up and bloat AttackShapes scans.
local UNHANDLED_CORPSE_TIMEOUT = 2

-- ═══════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════

-- §2.1d: debug-log gate. Flip to true locally when diagnosing MobAI issues.
-- Production default: false — registering a single wave spews hundreds of
-- lines otherwise.
local DEBUG_MOB_AI = false

local STATES = {
	PATROL = "Patrol",
	CHASE = "Chase",
	ATTACK = "Attack",
	SKILL = "Skill",
	DEAD = "Dead",
}

local PATROL_DIRECTION = Vector3.new(-1, 0, 0)
local UPDATE_INTERVAL = 0.2

-- ─────────────────────────────────────────────────────────
-- TARGETING MODE
-- When hordeMode targeting is enabled:
--   • The X-axis lane filter is skipped (mobs can target any direction)
--   • The perceptionRange cap is ignored (mobs chase regardless of distance)
-- Call MobAI.SetHordeModeTargeting(true) before spawning mobs in HordeMode.
-- ─────────────────────────────────────────────────────────
local hordeModeTargeting = false

-- Horde-only global speed multiplier (escalates over time to prevent infinite kiting).
-- Applied on top of each mob's registered base speed.
local hordeGlobalSpeedMult = 1.0

-- ═══════════════════════════════════════════════════════════
-- STATE  (declared here so all closures below can see them)
-- ═══════════════════════════════════════════════════════════

local activeMobs = {}

-- Pause flag (must be declared before SetHordeGlobalSpeedMult so the closure sees it)
local paused = false

--- Enable / disable HordeMode targeting rules.
--- Must be called on the server before mobs are registered.
function MobAI.SetHordeModeTargeting(enabled)
	hordeModeTargeting = enabled == true
	if not hordeModeTargeting then
		hordeGlobalSpeedMult = 1.0  -- reset when leaving horde mode
	end
	if DEBUG_MOB_AI then
		print("[MobAI] HordeMode targeting:", hordeModeTargeting and "ON" or "OFF")
	end
end

--- Apply a global speed multiplier to all active horde mobs.
--- Each mob's WalkSpeed is set to baseSpeed × mult.
--- No-op when hordeModeTargeting is false (safety guard).
--- @param mult number  new multiplier (e.g. 1.15 for +15% on top of registered speed)
-- §T3/W6 note: only ever called with 1.0 today (HordeModeSpawner.Stop
-- reset) — phase speed boosts are baked into each mob's baseSpeed at
-- spawn instead. Kept as the seam for a future live global speed lever.
function MobAI.SetHordeGlobalSpeedMult(mult)
	if not hordeModeTargeting then return end
	hordeGlobalSpeedMult = mult
	for _, data in pairs(activeMobs) do
		if data.state ~= STATES.DEAD and data.humanoid and not paused then
			-- §T3/W6: preserve frenzyMult (was dropped, same as SetPaused).
			data.humanoid.WalkSpeed = (data.baseSpeed or data.config.speed)
				* (data.frenzyMult or 1) * mult
		end
	end
end

-- Pending skill hits awaiting client responses
-- { [skillCastId] = { skill, mobData, origin, timestamp, playersInRange, reportedHits } }
local pendingSkillHits = {}

-- Pending basic-attack hits awaiting client reports (client-auth)
-- { [attackCastId] = { mobData, target, timestamp, reportedHit, resolved } }
local pendingBasicAttacks = {}

-- Counter for unique cast IDs to prevent collisions from timestamp-based generation
local castIdCounter = 0

--- Freeze / unfreeze all active mob AI (used by HordePauseManager).
-- (paused declared near top of STATE block so SetHordeGlobalSpeedMult can see it)
function MobAI.SetPaused(isPaused)
	paused = isPaused == true
	-- Immediately freeze or unfreeze walk speed for every active mob.
	-- §T3/W6: restore includes frenzyMult — the old restore dropped it,
	-- so a resumed mob ran at pre-frenzy speed for up to 5 s until the
	-- next frenzy tick happened to rewrite WalkSpeed.
	for mob, data in pairs(activeMobs) do
		if data.state ~= STATES.DEAD and data.humanoid then
			local restoreSpeed = (data.baseSpeed or data.config.speed)
				* (data.frenzyMult or 1)
				* (hordeModeTargeting and hordeGlobalSpeedMult or 1)
			data.humanoid.WalkSpeed = paused and 0 or restoreSpeed
		end
	end
	if DEBUG_MOB_AI then
		print("[MobAI] Paused:", paused and "ON" or "OFF")
	end
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

local _initialized = false

function MobAI.Init()
	-- §T3/W5: run-once guard. A second Init would wire duplicate network
	-- handlers, a duplicate Heartbeat, and a duplicate reaper thread.
	if _initialized then return end
	_initialized = true

	local HitTrackerModule = Modules:FindFirstChild("HitTracker")
	if HitTrackerModule then
		HitTracker = require(HitTrackerModule)
	end

	local MonitoringModule = Modules:FindFirstChild("MonitoringSystem")
	if MonitoringModule then
		MonitoringSystem = require(MonitoringModule)
	end

	-- Network events
	NetworkManager.GetEvent("MobSkillCast")
	NetworkManager.GetEvent("MobSkillHit")
	NetworkManager.GetEvent("MobBasicAttackCast")

	-- Client hit reports (skills)
	NetworkManager.OnClientEvent("MobSkillHitReport", function(player, data)
		MobAI.OnClientHitReport(player, data)
	end)

	-- Client hit reports (basic attacks — client-auth)
	NetworkManager.OnClientEvent("MobBasicAttackHitReport", function(player, data)
		MobAI.OnBasicAttackHitReport(player, data)
	end)

	RunService.Heartbeat:Connect(function(dt)
		MobAI.Update(dt)
	end)

	-- §2.1c / §3.5 reaper: sweep pending skill/basic-attack tables periodically
	-- so stale entries cannot leak if per-entry cleanup is ever skipped
	-- (thrown callback, disconnected player mid-resolution, frozen client that
	-- never reports). TTL is generous (15s) — longer than any legitimate
	-- resolution window.
	task.spawn(function()
		local TTL = 15
		while true do
			task.wait(2)
			local cutoff = os.clock() - TTL
			for castId, entry in pairs(pendingSkillHits) do
				if (entry.timestamp or 0) < cutoff then
					pendingSkillHits[castId] = nil
				end
			end
			for castId, entry in pairs(pendingBasicAttacks) do
				if (entry.timestamp or 0) < cutoff then
					pendingBasicAttacks[castId] = nil
				end
			end
		end
	end)

end

-- ═══════════════════════════════════════════════════════════
-- REGISTER / UNREGISTER MOBS
-- ═══════════════════════════════════════════════════════════

function MobAI.RegisterMob(mob, mobId, level, difficultyOverrides)
	level = level or 1

	local config = MobRegistry.GetScaledMob(mobId, level, difficultyOverrides)
	if not config then
		warn("[MobAI] Invalid mob type:", mobId)
		return nil
	end

	local humanoid = mob:FindFirstChild("Humanoid")
	local rootPart = mob:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		warn("[MobAI] Mob missing Humanoid or HumanoidRootPart")
		return nil
	end

	humanoid.MaxHealth = config.health
	humanoid.Health = config.health
	humanoid.WalkSpeed = config.speed

	mob:SetAttribute("MobId", mobId)
	mob:SetAttribute("MobTier", config.mobTier or "normal")

	-- Resolve skills
	local resolvedSkills = {}
	if config.skills then
		resolvedSkills = MobSkillRegistry.ResolveSkills(config.skills)
	end

	-- Initialize cooldowns
	local skillCooldowns = {}
	local now = os.clock()
	for skillId, skillData in pairs(resolvedSkills) do
		if skillData.startOnCooldown then
			skillCooldowns[skillId] = now + skillData.cooldown
		else
			skillCooldowns[skillId] = 0
		end
	end

	local mobData = {
		mob = mob,
		humanoid = humanoid,
		rootPart = rootPart,
		config = config,
		mobId = mobId,
		level = level,
		mobTier = config.mobTier or "normal",
		state = STATES.PATROL,
		target = nil,
		lastAttackTime = 0,
		lastUpdateTime = 0,
		-- Skills
		resolvedSkills = resolvedSkills,
		skillCooldowns = skillCooldowns,
		skillPriority = config.skillPriority or {},
		activeSkill = nil,
		skillEndTime = 0,
		-- Attack animation
		isAttacking = false,
		attackEndTime = 0,
		-- Taunt
		forcedTarget = nil,
		tauntEndTime = 0,
		-- Behavior system
		damageMultiplier = 1.0,
		behaviors = {},
		-- Speed escalation base (overwritten by spawner after phase speedMult is applied)
		baseSpeed = config.speed,
		-- §FRENZY1: per-mob anti-kite. Tracks alive-time so a single mob
		-- left chasing accelerates without punishing the player for the
		-- new wave. See applyFrenzy() below for the curve.
		spawnTime    = os.clock(),
		frenzyMult   = 1.0,  -- last applied mult; cached so we only push WalkSpeed when it changes
	}

	activeMobs[mob] = mobData

	-- §AGX/X45: pin mob physics to the server. RegisterMob is the one
	-- path every spawner (Lane SpawnMob, HordeModeSpawner, CentralBoss
	-- boss + placeholder adds) calls right after parenting to workspace.
	MobSpawnHelper.PinServerOwnership(rootPart, mobData.mobTier)

	-- Resolve and initialize behaviors declared by this mob
	if config.behaviors then
		for _, behaviorDef in ipairs(config.behaviors) do
			local behaviorModule = MobBehaviors[behaviorDef.type]
			if behaviorModule then
				table.insert(mobData.behaviors, { mod = behaviorModule, cfg = behaviorDef })
				if behaviorModule.Init then
					behaviorModule.Init(mobData, behaviorDef)
				end
			else
				warn("[MobAI] Unknown behavior type:", behaviorDef.type, "on mob:", mobId)
			end
		end
	end

	-- §T3/W4 (§14b): track the per-mob connections so UnregisterMob can
	-- disconnect them explicitly — a mob :Destroy()ed without firing Died
	-- no longer leaves dangling closures holding the mob table alive.
	mobData.connections = {
		humanoid.Died:Connect(function()
			MobAI.OnMobDied(mob)
		end),
		mob.AncestryChanged:Connect(function(_, parent)
			if not parent then
				MobAI.UnregisterMob(mob)
			end
		end),
	}

	local tierText = config.mobTier ~= "normal" and " [" .. config.mobTier:upper() .. "]" or ""
	local skillCount = #(config.skillPriority or {})
	if DEBUG_MOB_AI then
		print("[MobAI] Registered:", mobId, "Lv." .. level .. tierText,
			"| HP:", config.health, "| DMG:", config.damage,
			skillCount > 0 and ("| Skills: " .. skillCount) or "")
	end

	return mobData
end

function MobAI.OnMobDied(mob)
	MobAI.UnregisterMob(mob)

	-- §AGX/X12: safety net. The normal death path (HandleMobDeath) Destroys
	-- the mob synchronously; anything still parented after the timeout was
	-- killed by a path that skipped it. Unregistered mobs are invisible to
	-- MobSpawner.Reset / DefenseDetection, so nothing else would clean it.
	task.delay(UNHANDLED_CORPSE_TIMEOUT, function()
		if mob.Parent then
			local dh = getDamageHandler()
			if not (dh and dh.IsDeathHandled and dh.IsDeathHandled(mob)) then
				warn("[MobAI] Unhandled mob death — destroying corpse:", mob.Name)
			end
			mob:Destroy()
		end
	end)
end

function MobAI.UnregisterMob(mob)
	if activeMobs[mob] then
		activeMobs[mob].state = STATES.DEAD

		-- §T3/W4: disconnect the tracked per-mob connections.
		if activeMobs[mob].connections then
			for _, conn in ipairs(activeMobs[mob].connections) do
				pcall(conn.Disconnect, conn)
			end
			activeMobs[mob].connections = nil
		end

		-- Clean up pending skill hits and basic attacks for this mob.
		-- §2.1b fix: match by mob reference, NOT by castId substring. The old
		-- substring approach would misfire when two mobs had hierarchical name
		-- collisions (e.g. "Workspace.Mobs.Zombie" is a prefix of
		-- "Workspace.Mobs.Zombie.Variant") — a short-named mob dying could clear
		-- cast entries for a longer-named mob still alive.
		for castId, entry in pairs(pendingSkillHits) do
			if entry.mobData and entry.mobData.mob == mob then
				pendingSkillHits[castId] = nil
			end
		end
		for castId, entry in pairs(pendingBasicAttacks) do
			if entry.mobData and entry.mobData.mob == mob then
				pendingBasicAttacks[castId] = nil
			end
		end

		activeMobs[mob] = nil
	end
end

-- ═══════════════════════════════════════════════════════════
-- MAIN UPDATE LOOP
-- ═══════════════════════════════════════════════════════════

-- §FRENZY1: per-mob alive-time speed curve.
--   * 0–10 s    : base speed (grace window).
--   * 10 s→      : +5 % every 5 s.
--   * Cap        : +60 % over base (12 ticks = max at 70 s alive).
-- Returns the multiplier (>= 1.0). Cheap arithmetic, no allocations.
local FRENZY_GRACE_SEC      = 10
local FRENZY_TICK_SEC       = 5
local FRENZY_PER_TICK       = 0.05
local FRENZY_MAX_BONUS      = 0.60
local function frenzyMultFor(aliveSeconds)
	if aliveSeconds < FRENZY_GRACE_SEC then return 1.0 end
	local ticks = math.floor((aliveSeconds - FRENZY_GRACE_SEC) / FRENZY_TICK_SEC) + 1
	local bonus = math.min(ticks * FRENZY_PER_TICK, FRENZY_MAX_BONUS)
	return 1.0 + bonus
end

-- ═══════════════════════════════════════════════════════════
-- §SCALE/S2: range-scoped client broadcast
-- ═══════════════════════════════════════════════════════════
-- Mob cast/VFX events only matter to players who can see the mob.
-- Runs at event rate (per cast, not per frame) so a direct GetPlayers
-- walk is fine — and unlike the AI snapshot it must include downed /
-- spectating players, who still watch the fight.
local CAST_BROADCAST_RANGE = 150

--- alwaysInclude: player guaranteed to receive the event (e.g. the
--- attack target — client-auth hit detection needs it) even if their
--- character is missing or out of range.
function MobAI.FireNearbyClients(origin, alwaysInclude, eventName, payload)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == alwaysInclude then
			NetworkManager.FireClient(plr, eventName, payload)
		else
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			-- Characterless players (mid-respawn) get it too — cheap & safe.
			if not root or (root.Position - origin).Magnitude <= CAST_BROADCAST_RANGE then
				NetworkManager.FireClient(plr, eventName, payload)
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- §PERF/F1 (task #17): per-frame player snapshot
-- ═══════════════════════════════════════════════════════════
-- FindTarget used to call Players:GetPlayers() and redo ~4 attribute /
-- FindFirstChild lookups per player for EVERY mob AI tick (~360 calls/s
-- at 72 mobs — the hottest redundant work on a busy combat server).
-- All mobs ticking in the same Heartbeat frame now share one snapshot
-- containing only VALID targets (character + root + humanoid alive +
-- DeathState "Alive"), in GetPlayers() order.
local snapshotList     = {}   -- array of entries
local snapshotByPlayer = {}   -- [player] = entry
local snapshotStamp    = -1   -- `now` of the frame this snapshot is for

local function refreshSnapshot(now)
	if now == snapshotStamp then return end
	snapshotStamp = now
	table.clear(snapshotList)
	table.clear(snapshotByPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local hum  = character and character:FindFirstChild("Humanoid")
		if root and hum and hum.Health > 0
			and player:GetAttribute("DeathState") == "Alive" then
			local entry = {
				player     = player,
				root       = root,
				position   = root.Position,
				isTaunting = player:GetAttribute("IsTaunting") or false,
			}
			table.insert(snapshotList, entry)
			snapshotByPlayer[player] = entry
		end
	end
end

function MobAI.Update(dt)
	if paused then return end
	local now = os.clock()

	-- §PERF/F1: one snapshot per frame, shared by every mob below.
	if next(activeMobs) ~= nil then
		refreshSnapshot(now)
	end

	for mob, data in pairs(activeMobs) do
		if data.state == STATES.DEAD then continue end

		if not mob or not mob.Parent or not data.humanoid or data.humanoid.Health <= 0 then
			MobAI.UnregisterMob(mob)
			continue
		end

		-- §FRENZY1: apply per-mob speed escalation. We compute the
		-- target mult from alive-time and only re-write WalkSpeed when it
		-- actually changes (every 5 s in steady state) so this stays cheap.
		if data.spawnTime and data.baseSpeed then
			local alive = now - data.spawnTime
			local targetMult = frenzyMultFor(alive)
			if math.abs(targetMult - (data.frenzyMult or 1.0)) > 1e-3 then
				data.frenzyMult = targetMult
				-- §T3/W6: include the horde global mult so all three
				-- WalkSpeed writers (frenzy tick, SetPaused restore,
				-- SetHordeGlobalSpeedMult) compute the same product.
				data.humanoid.WalkSpeed = data.baseSpeed * targetMult
					* (hordeModeTargeting and hordeGlobalSpeedMult or 1)
			end
		end

		-- Clear expired taunt
		if data.forcedTarget and now > data.tauntEndTime then
			data.forcedTarget = nil
			data.tauntEndTime = 0
		end

		-- Check animation finished
		if data.isAttacking and now >= data.attackEndTime then
			data.isAttacking = false
		end

		-- Check skill finished
		if data.state == STATES.SKILL and now >= data.skillEndTime then
			data.activeSkill = nil
			data.state = STATES.CHASE
		end

		-- Throttle AI
		if now - data.lastUpdateTime < UPDATE_INTERVAL then continue end
		data.lastUpdateTime = now

		if data.state == STATES.SKILL then continue end

		-- Run behavior update hooks (e.g., Enrage checks HP threshold)
		for _, b in ipairs(data.behaviors) do
			if b.mod.Update then
				b.mod.Update(data, now)
			end
		end

		MobAI.UpdateState(data, now)
		MobAI.ExecuteState(data, now)
	end
end

-- ═══════════════════════════════════════════════════════════
-- STATE MACHINE
-- ═══════════════════════════════════════════════════════════

function MobAI.UpdateState(data, now)
	local currentState = data.state
	local target = MobAI.FindTarget(data)
	data.target = target

	if currentState == STATES.PATROL then
		if target then
			data.state = STATES.CHASE
		end

	elseif currentState == STATES.CHASE then
		if not target then
			data.state = STATES.PATROL
			return
		end
		if MobAI.IsInAttackRange(data, target) then
			data.state = STATES.ATTACK
		end

	elseif currentState == STATES.ATTACK then
		if not target then
			data.state = STATES.PATROL
			return
		end
		if not MobAI.IsInAttackRange(data, target) then
			data.state = STATES.CHASE
		end
	end
end

function MobAI.ExecuteState(data, now)
	if data.state == STATES.PATROL then
		MobAI.DoPatrol(data)
	elseif data.state == STATES.CHASE then
		MobAI.DoChase(data)
	elseif data.state == STATES.ATTACK then
		MobAI.DoAttack(data, now)
	end
end

function MobAI.DoPatrol(data)
	if hordeModeTargeting then
		-- In HordeMode, idle in place when no living target is available.
		-- This prevents mobs marching in a fixed direction when all players are downed.
		data.humanoid:MoveTo(data.rootPart.Position)
		return
	end
	-- LaneDefense: march toward the defense line
	local targetPos = data.rootPart.Position + (PATROL_DIRECTION * 50)
	data.humanoid:MoveTo(targetPos)
end

function MobAI.DoChase(data)
	local target = data.target
	if not target then return end

	-- §PERF/F1: snapshot fast path, direct lookups as fallback.
	local entry = snapshotByPlayer[target]
	if entry then
		data.humanoid:MoveTo(entry.position)
		return
	end

	local targetChar = target.Character
	if not targetChar then return end

	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return end

	data.humanoid:MoveTo(targetRoot.Position)
end

function MobAI.DoAttack(data, now)
	local target = data.target
	if not target then return end

	data.humanoid:MoveTo(data.rootPart.Position)

	-- Stunned / immobilized mobs cannot attack or use skills
	if data.mob:GetAttribute("IsStunned") then return end

	if data.isAttacking then return end

	-- Try skill first
	local skill = MobAI.GetAvailableSkill(data, target, now)
	if skill then
		MobAI.ExecuteSkill(data, skill, target, now)
		return
	end

	-- Basic attack cooldown
	if now - data.lastAttackTime < data.config.attackCooldown then
		return
	end

	MobAI.ExecuteBasicAttack(data, target, now)
end

-- ═══════════════════════════════════════════════════════════
-- BASIC ATTACK (Server-Auth - simple melee)
-- ═══════════════════════════════════════════════════════════

function MobAI.ExecuteBasicAttack(data, target, now)
	local config = data.config

	data.lastAttackTime = now
	data.isAttacking = true
	data.attackEndTime = now + (config.attackDuration or 0.5)

	local animationId = config.animations and config.animations.attack
	local damageDelay = config.damageDelay or 0.25
	castIdCounter = castIdCounter + 1
	-- §MEM/M7: cast ids are opaque match tokens (never parsed — grep
	-- verified). GetFullName() walked the whole ancestry building a string
	-- on every attack; the counter alone already guarantees uniqueness.
	local attackCastId = "b_" .. castIdCounter

	-- Store pending attack for client-auth resolution
	pendingBasicAttacks[attackCastId] = {
		mobData = data,
		target = target,
		timestamp = now,
		reportedHit = false,
		resolved = false,
	}

	-- §SCALE/S2: broadcast only to players near the mob (animation is
	-- invisible from across the map; was FireAllClients = O(M·P) sends/s
	-- under siege). The TARGET is always included — client-auth hit
	-- detection depends on this event reaching them.
	MobAI.FireNearbyClients(data.rootPart.Position, target, "MobBasicAttackCast", {
		attackCastId = attackCastId,
		mob = data.mob,
		targetPlayer = target,
		animationId = animationId,
		damageDelay = damageDelay,
		attackRange = config.attackRange,
	})

	-- Resolve after damage window closes (player must report by then)
	task.delay(damageDelay + 0.5, function()
		MobAI.ResolveBasicAttack(attackCastId)
	end)
end

-- ═══════════════════════════════════════════════════════════
-- SKILL SYSTEM (Client-Auth Hybrid)
-- ═══════════════════════════════════════════════════════════

function MobAI.GetAvailableSkill(data, target, now)
	if not data.resolvedSkills or #data.skillPriority == 0 then
		return nil
	end

	local targetChar = target.Character
	if not targetChar then return nil end

	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return nil end

	local distance = (data.rootPart.Position - targetRoot.Position).Magnitude
	local healthPercent = (data.humanoid.Health / data.humanoid.MaxHealth) * 100

	for _, skillId in ipairs(data.skillPriority) do
		local skill = data.resolvedSkills[skillId]
		if skill and MobAI.CanUseSkill(data, skill, distance, healthPercent, now) then
			return skill
		end
	end

	return nil
end

function MobAI.CanUseSkill(data, skill, distance, healthPercent, now)
	local readyTime = data.skillCooldowns[skill.id] or 0
	if now < readyTime then return false end

	local targeting = skill.targeting or {}

	if targeting.minRange and distance < targeting.minRange then
		return false
	end
	if targeting.maxRange and distance > targeting.maxRange then
		return false
	end
	if targeting.healthThreshold and healthPercent > targeting.healthThreshold then
		return false
	end

	return true
end

function MobAI.ExecuteSkill(data, skill, target, now)
	-- Set cooldown
	data.skillCooldowns[skill.id] = now + skill.cooldown

	-- Enter skill state
	data.state = STATES.SKILL
	data.activeSkill = skill
	data.skillEndTime = now + (skill.animationDuration or 1.0)
	data.isAttacking = true
	data.attackEndTime = data.skillEndTime

	data.humanoid:MoveTo(data.rootPart.Position)

	local origin = data.rootPart.Position
	-- §MEM/M7: same as attackCastId — counter-based opaque token. Bonus:
	-- the old timestamp-only id could collide for two same-skill casts in
	-- one clock print; the counter cannot.
	castIdCounter = castIdCounter + 1
	local skillCastId = "s_" .. skill.id .. "_" .. castIdCounter

	-- Find all players potentially in range
	local playersInRange = MobAI.GetPlayersInSkillRange(origin, skill)

	-- Record potential hits for monitoring
	if MonitoringSystem then
		for _, player in ipairs(playersInRange) do
			MonitoringSystem.RecordPotentialHit(player, {
				skillId = skill.id,
				mobId = data.mobId,
				origin = origin,
				range = skill.shapeParams and skill.shapeParams.range or 10,
				timestamp = now,
			})
		end
	end

	-- Store pending hit data
	pendingSkillHits[skillCastId] = {
		skill = skill,
		mobData = data,
		origin = origin,
		timestamp = now,
		playersInRange = playersInRange,
		reportedHits = {},
		damageApplied = false,
	}

	-- §SCALE/S2: scoped like MobBasicAttackCast. Players beyond broadcast
	-- range are also beyond every skill's hit range, so in-range clients
	-- can still self-report hits correctly.
	MobAI.FireNearbyClients(origin, nil, "MobSkillCast", {
		skillCastId = skillCastId,
		mob = data.mob,
		mobId = data.mobId,
		skillId = skill.id,
		skillName = skill.name,
		origin = origin,
		animationId = skill.animation,
		animationDuration = skill.animationDuration or 1.0,
		damageDelay = skill.damageDelay or 0.5,
		damageWindow = skill.damageWindow or 0.3,
		shape = skill.shape,
		shapeParams = skill.shapeParams,
		damageMultiplier = skill.damageMultiplier or 1.0,
		baseDamage = data.config.damage,
		effects = skill.effects,
		visual = skill.visual,
	})

	-- After damage window closes, apply damage to players who reported
	local totalDelay = (skill.damageDelay or 0.5) + (skill.damageWindow or 0.3) + 0.1
	task.delay(totalDelay, function()
		MobAI.ResolveSkillHits(skillCastId)
	end)
end

function MobAI.GetPlayersInSkillRange(origin, skill)
	local players = {}
	local range = skill.shapeParams and skill.shapeParams.range or 10

	-- Add generous buffer for lag tolerance
	local checkRange = range + 15

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			local hum = char:FindFirstChild("Humanoid")
			if root and hum and hum.Health > 0
				and player:GetAttribute("DeathState") == "Alive" then
				local dist = (root.Position - origin).Magnitude
				if dist <= checkRange then
					table.insert(players, player)
				end
			end
		end
	end

	return players
end

-- ═══════════════════════════════════════════════════════════
-- CLIENT HIT REPORTS
-- ═══════════════════════════════════════════════════════════

function MobAI.OnClientHitReport(player, data)
	local skillCastId = data.skillCastId
	local playerPosition = data.position

	local pending = pendingSkillHits[skillCastId]
	if not pending then
		-- Late or invalid report
		if MonitoringSystem then
			MonitoringSystem.LogEvent(player, "InvalidHitReport", {
				skillCastId = skillCastId,
			})
		end
		return
	end

	-- Already reported?
	if pending.reportedHits[player] then
		if MonitoringSystem then
			MonitoringSystem.LogEvent(player, "DuplicateHitReport", {
				skillCastId = skillCastId,
			})
		end
		return
	end

	-- Record the hit
	pending.reportedHits[player] = {
		position = playerPosition,
		timestamp = os.clock(),
	}

	-- Log to monitoring
	if MonitoringSystem then
		MonitoringSystem.RecordHitReport(player, {
			skillId = pending.skill.id,
			position = playerPosition,
		})
	end
end

function MobAI.ResolveSkillHits(skillCastId)
	local pending = pendingSkillHits[skillCastId]
	if not pending or pending.damageApplied then return end

	local skill = pending.skill
	local mobData = pending.mobData
	local origin = pending.origin

	-- §2.1a fix: race guard. A skill cast can be queued just as the mob
	-- dies; resolving after death would apply damage from a corpse.
	-- ResolveBasicAttack (line 793) already has this check; mirror it here.
	if not mobData or mobData.state == STATES.DEAD then
		pendingSkillHits[skillCastId] = nil
		return
	end

	pending.damageApplied = true

	-- Server-authoritative spatial validation:
	-- Check every player that was in range at cast time against their
	-- current position with a generous latency buffer.  Client reports
	-- are used only as advisory telemetry — the server decides who is hit.
	local skillRange = (skill.shapeParams and skill.shapeParams.range or 10)
	local hitRadius = skillRange + 15  -- generous buffer for movement + latency

	for _, player in ipairs(pending.playersInRange) do
		local char = player.Character
		if not char then continue end
		local root = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChild("Humanoid")
		if not root or not hum or hum.Health <= 0 then continue end

		-- Server spatial check: player within skill radius from cast origin
		local distance = (root.Position - origin).Magnitude
		if distance > hitRadius then continue end

		-- Apply skill + mob enrage multiplier
		local damage = mobData.config.damage
			* (skill.damageMultiplier or 1.0)
			* (mobData.damageMultiplier or 1.0)
		MobAI.DamagePlayer(player, damage, mobData, skill.id)

		-- Apply effects
		if skill.effects then
			for _, effect in ipairs(skill.effects) do
				MobAI.ApplyEffectToPlayer(player, effect, origin)
			end
		end

		-- Notify client of confirmed hit
		NetworkManager.FireClient(player, "MobSkillHit", {
			skillCastId = skillCastId,
			skillId = skill.id,
			damage = damage,
			effects = skill.effects,
		})
	end

	-- §T3/W3: delete eagerly — a resolved entry has no further use, and
	-- late client reports hit the "unknown castId → ignore" path anyway.
	-- The reaper (§2.1c) stays as the fallback for never-resolved casts.
	pendingSkillHits[skillCastId] = nil
end

-- ═══════════════════════════════════════════════════════════
-- EFFECTS
-- ═══════════════════════════════════════════════════════════

-- §AGX/X13: player Stun/Slow used to capture WalkSpeed and restore it via
-- task.delay. Overlaps (Roar slow → GroundSlam stun) restored the SLOWED
-- speed last and left players at half speed until respawn. Now each effect
-- stores an expiry on the humanoid and every expiry recomputes speed from
-- the character's natural speed ("BaseWalkSpeed", stamped by DeathSystem).
-- Knocked-down players and movement-locked casts own WalkSpeed; they read
-- "MoveFxSpeed" / "BaseWalkSpeed" when they restore.
-- Active slows per humanoid: { { mult, expires }, ... } (weak keys —
-- entries vanish with the character). Each slow keeps its OWN expiry so a
-- short strong slow doesn't inherit a long weak slow's duration.
local playerSlows = setmetatable({}, { __mode = "k" })

local function recomputePlayerMoveSpeed(player, humanoid)
	if not humanoid.Parent then return end
	local now     = os.clock()
	local stunned = (humanoid:GetAttribute("StunUntil") or 0) > now
	local base    = humanoid:GetAttribute("BaseWalkSpeed") or 16

	-- Strongest unexpired slow wins; prune the rest.
	local slowMult, slowUntil = nil, 0
	local list = playerSlows[humanoid]
	if list then
		for i = #list, 1, -1 do
			local e = list[i]
			if e.expires > now then
				slowMult  = slowMult and math.min(slowMult, e.mult) or e.mult
				slowUntil = math.max(slowUntil, e.expires)
			else
				table.remove(list, i)
			end
		end
		if #list == 0 then playerSlows[humanoid] = nil end
	end
	local slowed = slowMult ~= nil

	local target = base
	if stunned then
		target = 0
	elseif slowed then
		target = base * slowMult
	end

	player:SetAttribute("IsStunned", stunned or nil)
	player:SetAttribute("IsSlowed", slowed or nil)
	if stunned or slowed then
		humanoid:SetAttribute("MoveFxSpeed", target)
	else
		humanoid:SetAttribute("MoveFxSpeed", nil)
		humanoid:SetAttribute("StunUntil", nil)
	end

	if player:GetAttribute("DeathState") ~= nil and player:GetAttribute("DeathState") ~= "Alive" then return end
	if humanoid:GetAttribute("CastMoveLock") and not stunned then return end
	humanoid.WalkSpeed = target
end

-- Re-check at `delay`; if an effect is still active (task.delay and
-- os.clock can disagree by a frame, or a longer effect is pending),
-- re-arm for the remainder instead of leaving the player pinned.
local function scheduleMoveRecompute(player, humanoid, delay)
	task.delay(delay, function()
		if not (humanoid and humanoid.Parent and player.Parent) then return end
		recomputePlayerMoveSpeed(player, humanoid)
		local now = os.clock()
		local nextAt = math.huge
		local stunUntil = humanoid:GetAttribute("StunUntil") or 0
		if stunUntil > now then nextAt = stunUntil end
		for _, e in ipairs(playerSlows[humanoid] or {}) do
			if e.expires > now then nextAt = math.min(nextAt, e.expires) end
		end
		if nextAt < math.huge then
			scheduleMoveRecompute(player, humanoid, nextAt - now + 0.05)
		end
	end)
end

-- Knockdown/death clears mob movement effects (DeathSystem also clears
-- the attributes); exposed so both sides agree on the state.
function MobAI.ClearPlayerMoveEffects(humanoid)
	playerSlows[humanoid] = nil
end

function MobAI.ApplyEffectToPlayer(player, effect, origin)
	local char = player.Character
	if not char then return end

	local humanoid = char:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if effect.type == "Stun" or effect.type == "Slow" then
		-- Downed/dead players are pinned at Health 1; a stun landing then
		-- would outlive the revive (IsStunned blocking CanPlayerAct).
		local deathState = player:GetAttribute("DeathState")
		if deathState ~= nil and deathState ~= "Alive" then return end

		local now      = os.clock()
		local duration = effect.duration or (effect.type == "Stun" and 1 or 2)
		if effect.type == "Stun" then
			humanoid:SetAttribute("StunUntil", math.max(humanoid:GetAttribute("StunUntil") or 0, now + duration))
		else
			local list = playerSlows[humanoid]
			if not list then list = {}; playerSlows[humanoid] = list end
			table.insert(list, { mult = 1 - (effect.amount or 50) / 100, expires = now + duration })
		end
		recomputePlayerMoveSpeed(player, humanoid)
		scheduleMoveRecompute(player, humanoid, duration + 0.05)

	elseif effect.type == "Knockback" then
		local rootPart = char:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local direction = (rootPart.Position - origin).Unit
			local force = direction * (effect.strength or 30)

			local attachment = rootPart:FindFirstChild("RootAttachment")
				if not attachment then
					attachment = Instance.new("Attachment")
					attachment.Name = "RootAttachment"
					attachment.Parent = rootPart
				end
			local linearVelocity = Instance.new("LinearVelocity")
			linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
			linearVelocity.VectorVelocity = force
			linearVelocity.MaxForce = 1e5
			linearVelocity.Attachment0 = attachment
			linearVelocity.Parent = rootPart

			task.delay(0.2, function()
				if linearVelocity and linearVelocity.Parent then
					linearVelocity:Destroy()
				end
			end)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- CLIENT BASIC-ATTACK HIT REPORTS
-- ═══════════════════════════════════════════════════════════

function MobAI.OnBasicAttackHitReport(player, data)
	local attackCastId = data.attackCastId
	local pending = pendingBasicAttacks[attackCastId]
	if not pending or pending.resolved then return end
	if pending.target ~= player then return end

	pending.reportedHit = true
end

function MobAI.ResolveBasicAttack(attackCastId)
	local pending = pendingBasicAttacks[attackCastId]
	if not pending or pending.resolved then return end

	pending.resolved = true

	local data = pending.mobData
	if data.state == STATES.DEAD then
		pendingBasicAttacks[attackCastId] = nil  -- §T3/W3: eager delete
		return
	end

	-- Server-authoritative spatial validation:
	-- Apply damage if the target is still within range (with generous buffer
	-- for movement during the damage window). Client reports are advisory.
	local target = pending.target
	local shouldHit = false
	if target and target.Character then
		local playerRoot = target.Character:FindFirstChild("HumanoidRootPart")
		local mobRoot = data.rootPart
		if playerRoot and mobRoot and mobRoot.Parent then
			local distance = (mobRoot.Position - playerRoot.Position).Magnitude
			-- Buffer: 1.5× attack range + walkspeed × delay to account for movement
			local buffer = (data.config.attackRange or 8) * 1.5 + 16
			shouldHit = distance <= buffer
		end
	end

	if shouldHit then
		local damage = data.config.damage * (data.damageMultiplier or 1.0)
		MobAI.DamagePlayer(target, damage, data)
	end

	-- §T3/W3: delete eagerly (reaper stays as fallback for the unresolved).
	pendingBasicAttacks[attackCastId] = nil
end

-- ═══════════════════════════════════════════════════════════
-- TARGET FINDING
-- ═══════════════════════════════════════════════════════════

-- §PERF/F1: iterates the shared per-frame snapshot (built in Update)
-- instead of GetPlayers() + per-player lookups. Filter semantics are
-- identical — the snapshot already excludes characterless / dead /
-- non-"Alive" players, in the same GetPlayers() order.
function MobAI.FindTarget(data)
	local mobPos = data.rootPart.Position
	local config = data.config
	local mobX = mobPos.X

	if data.forcedTarget then
		-- Snapshot membership == exactly the old validity checks
		-- (character + humanoid alive + DeathState "Alive").
		if snapshotByPlayer[data.forcedTarget] then
			return data.forcedTarget
		end
		data.forcedTarget = nil
	end

	local bestTarget = nil
	local bestDistance = math.huge

	for _, entry in ipairs(snapshotList) do
		local playerPos = entry.position

		-- LaneDefense: only target players to the left (-X direction).
		-- Skip this check in HordeMode where mobs chase any direction.
		if not hordeModeTargeting and playerPos.X >= mobX then continue end

		local distance = (mobPos - playerPos).Magnitude
		-- In HordeMode mobs track across unlimited distance; taunts always override.
		if not hordeModeTargeting and distance > config.perceptionRange and not entry.isTaunting then
			continue
		end

		if entry.isTaunting then return entry.player end

		if distance < bestDistance then
			bestDistance = distance
			bestTarget = entry.player
		end
	end

	return bestTarget
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function MobAI.IsInAttackRange(data, player)
	if not player then return false end
	-- §PERF/F1: fast path via the frame snapshot (the target always came
	-- from FindTarget in the same tick). Direct lookups kept as fallback
	-- for out-of-band callers.
	local entry = snapshotByPlayer[player]
	if entry then
		return (data.rootPart.Position - entry.position).Magnitude
			<= data.config.attackRange
	end
	local character = player.Character
	if not character then return false end
	local playerRoot = character:FindFirstChild("HumanoidRootPart")
	if not playerRoot then return false end
	local distance = (data.rootPart.Position - playerRoot.Position).Magnitude
	return distance <= data.config.attackRange
end

-- ═══════════════════════════════════════════════════════════
-- DAMAGE
-- ═══════════════════════════════════════════════════════════

function MobAI.DamagePlayer(player, baseDamage, mobData, skillId)
	local character = player.Character
	if not character then return end

	-- Skip players who are knocked down or dead – DeathSystem handles their fate
	if player:GetAttribute("DeathState") ~= "Alive" then return end

	-- §DISC/D3b: wipe-revive grace — freshly revived players are
	-- untouchable for a few seconds.
	if player:GetAttribute("WipeInvulnerable") then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local mobPenetration = mobData.config.penetration or 0
	local finalDamage = StatsManager.CalculateDamageTaken(player, baseDamage, mobPenetration)

	humanoid:TakeDamage(finalDamage)

	-- Thorns: reflect a percentage of final damage back to the mob
	local thorns = StatsManager.GetBonus(player, "Thorns") or 0
	if thorns > 0 and mobData and mobData.mob then
		local mobHumanoid = mobData.mob:FindFirstChild("Humanoid")
		if mobHumanoid and mobHumanoid.Health > 0 then
			local reflectDamage = math.floor(finalDamage * thorns / 100)
			if reflectDamage > 0 then
				-- §AGX/X12: route through DamageHandler so a Thorns kill
				-- credits the player and runs the normal death path (was a
				-- bare TakeDamage: corpse left behind, no rewards).
				local dh = getDamageHandler()
				if dh and dh.ApplyRawDamage then
					dh.ApplyRawDamage(mobData.mob, reflectDamage, player)
				else
					mobHumanoid:TakeDamage(reflectDamage)
				end
			end
		end
	end

	if HitTracker then
		HitTracker.RecordHitReceived(player, {
			mobTier = mobData.mobTier,
			damage = finalDamage,
			rawDamage = baseDamage,
			mobId = mobData.mobId,
			mobLevel = mobData.level,
			skillId = skillId,
		})
	end

	if humanoid.Health <= 0 then
		MobAI.HandlePlayerDeath(player, mobData)
	end
end

function MobAI.HandlePlayerDeath(player, mobData)
	if DEBUG_MOB_AI then
		print("[MobAI]", player.Name, "killed by", mobData.mobId, "Lv." .. mobData.level)
	end
	NetworkManager.FireAllClients("PlayerDeath", {
		playerName = player.Name,
		killerMob = mobData.mobId,
		killerTier = mobData.mobTier,
		killerLevel = mobData.level,
	})
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC GETTERS
-- ═══════════════════════════════════════════════════════════

function MobAI.GetActiveMobCount()
	local count = 0
	for _ in pairs(activeMobs) do count = count + 1 end
	return count
end

function MobAI.GetMobData(mob)
	return activeMobs[mob]
end

function MobAI.IsAnyMobAlive()
	-- §MEM/M8: first-key test instead of counting all 70+ mobs.
	return next(activeMobs) ~= nil
end

function MobAI.GetAllMobData()
	return activeMobs
end

return MobAI