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

-- Lazy-loaded
local HitTracker = nil
local MonitoringSystem = nil

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
function MobAI.SetHordeGlobalSpeedMult(mult)
	if not hordeModeTargeting then return end
	hordeGlobalSpeedMult = mult
	for _, data in pairs(activeMobs) do
		if data.state ~= STATES.DEAD and data.humanoid and not paused then
			data.humanoid.WalkSpeed = (data.baseSpeed or data.config.speed) * mult
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
	-- Immediately freeze or unfreeze walk speed for every active mob
	for mob, data in pairs(activeMobs) do
		if data.state ~= STATES.DEAD and data.humanoid then
			local restoreSpeed = (data.baseSpeed or data.config.speed)
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

function MobAI.Init()
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

	print("[MobAI] Initialized (Hybrid Client-Auth)")
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

	humanoid.Died:Connect(function()
		MobAI.OnMobDied(mob)
	end)

	mob.AncestryChanged:Connect(function(_, parent)
		if not parent then
			MobAI.UnregisterMob(mob)
		end
	end)

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
end

function MobAI.UnregisterMob(mob)
	if activeMobs[mob] then
		activeMobs[mob].state = STATES.DEAD

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

function MobAI.Update(dt)
	if paused then return end
	local now = os.clock()

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
				data.humanoid.WalkSpeed = data.baseSpeed * targetMult
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
	local attackCastId = data.mob:GetFullName() .. "_basic_" .. tostring(now) .. "_" .. castIdCounter

	-- Store pending attack for client-auth resolution
	pendingBasicAttacks[attackCastId] = {
		mobData = data,
		target = target,
		timestamp = now,
		reportedHit = false,
		resolved = false,
	}

	-- Broadcast to all clients (animation + hit detection for target)
	NetworkManager.FireAllClients("MobBasicAttackCast", {
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
	local skillCastId = data.mob:GetFullName() .. "_" .. skill.id .. "_" .. tostring(now)

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

	-- Broadcast skill cast to all clients
	NetworkManager.FireAllClients("MobSkillCast", {
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

	-- Entry will be swept by the reaper thread (§2.1c) 2-17s after cast;
	-- explicit cleanup no longer needed here.
end

-- ═══════════════════════════════════════════════════════════
-- EFFECTS
-- ═══════════════════════════════════════════════════════════

function MobAI.ApplyEffectToPlayer(player, effect, origin)
	local char = player.Character
	if not char then return end

	local humanoid = char:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if effect.type == "Stun" then
		local originalSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 0
		player:SetAttribute("IsStunned", true)

		task.delay(effect.duration or 1, function()
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = originalSpeed
				player:SetAttribute("IsStunned", nil)
			end
		end)

	elseif effect.type == "Slow" then
		local originalSpeed = humanoid.WalkSpeed
		local slowAmount = (effect.amount or 50) / 100
		humanoid.WalkSpeed = originalSpeed * (1 - slowAmount)
		player:SetAttribute("IsSlowed", true)

		task.delay(effect.duration or 2, function()
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = originalSpeed
				player:SetAttribute("IsSlowed", nil)
			end
		end)

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
		-- Entry will be swept by the reaper thread (§2.1c).
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

	-- Entry will be swept by the reaper thread (§2.1c).
end

-- ═══════════════════════════════════════════════════════════
-- TARGET FINDING
-- ═══════════════════════════════════════════════════════════

function MobAI.FindTarget(data)
	local rootPart = data.rootPart
	local config = data.config
	local mobX = rootPart.Position.X

	if data.forcedTarget then
		local forcedChar = data.forcedTarget.Character
		if forcedChar then
			local forcedHumanoid = forcedChar:FindFirstChild("Humanoid")
			if forcedHumanoid and forcedHumanoid.Health > 0
				and data.forcedTarget:GetAttribute("DeathState") == "Alive" then
				return data.forcedTarget
			end
		end
		data.forcedTarget = nil
	end

	local bestTarget = nil
	local bestDistance = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local isTaunting = player:GetAttribute("IsTaunting")

		local character = player.Character
		if not character then continue end

		local playerRoot = character:FindFirstChild("HumanoidRootPart")
		if not playerRoot then continue end

		local playerHumanoid = character:FindFirstChild("Humanoid")
		if not playerHumanoid or playerHumanoid.Health <= 0 then continue end

		-- Only target players who are alive and able to act
		if player:GetAttribute("DeathState") ~= "Alive" then continue end

		local playerX = playerRoot.Position.X
		-- LaneDefense: only target players to the left (-X direction).
		-- Skip this check in HordeMode where mobs chase any direction.
		if not hordeModeTargeting and playerX >= mobX then continue end

		local distance = (rootPart.Position - playerRoot.Position).Magnitude
		-- In HordeMode mobs track across unlimited distance; taunts always override.
		if not hordeModeTargeting and distance > config.perceptionRange and not isTaunting then
			continue
		end

		if isTaunting then return player end

		if distance < bestDistance then
			bestDistance = distance
			bestTarget = player
		end
	end

	return bestTarget
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function MobAI.IsInAttackRange(data, player)
	if not player then return false end
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
				mobHumanoid:TakeDamage(reflectDamage)
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
	return MobAI.GetActiveMobCount() > 0
end

function MobAI.GetAllMobData()
	return activeMobs
end

return MobAI