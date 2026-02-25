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

local STATES = {
	PATROL = "Patrol",
	CHASE = "Chase",
	ATTACK = "Attack",
	SKILL = "Skill",
	DEAD = "Dead",
}

local PATROL_DIRECTION = Vector3.new(-1, 0, 0)
local UPDATE_INTERVAL = 0.2

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local activeMobs = {}

-- Pending skill hits awaiting client responses
-- { [skillCastId] = { skill, mobData, origin, timestamp, playersInRange, reportedHits } }
local pendingSkillHits = {}

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
	NetworkManager.GetEvent("MobAttack")
	NetworkManager.GetEvent("MobSkillCast")
	NetworkManager.GetEvent("MobSkillHit")

	-- Client hit reports
	NetworkManager.OnClientEvent("MobSkillHitReport", function(player, data)
		MobAI.OnClientHitReport(player, data)
	end)

	RunService.Heartbeat:Connect(function(dt)
		MobAI.Update(dt)
	end)

	print("[MobAI] Initialized (Hybrid Client-Auth)")
end

-- ═══════════════════════════════════════════════════════════
-- REGISTER / UNREGISTER MOBS
-- ═══════════════════════════════════════════════════════════

function MobAI.RegisterMob(mob, mobId, level)
	level = level or 1

	local config = MobRegistry.GetScaledMob(mobId, level)
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
	local now = tick()
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
	print("[MobAI] Registered:", mobId, "Lv." .. level .. tierText, 
		"| HP:", config.health, "| DMG:", config.damage,
		skillCount > 0 and ("| Skills: " .. skillCount) or "")

	return mobData
end

function MobAI.OnMobDied(mob)
	MobAI.UnregisterMob(mob)
end

function MobAI.UnregisterMob(mob)
	if activeMobs[mob] then
		activeMobs[mob].state = STATES.DEAD
		activeMobs[mob] = nil
	end
end

-- ═══════════════════════════════════════════════════════════
-- MAIN UPDATE LOOP
-- ═══════════════════════════════════════════════════════════

function MobAI.Update(dt)
	local now = tick()

	for mob, data in pairs(activeMobs) do
		if data.state == STATES.DEAD then continue end

		if not mob or not mob.Parent or not data.humanoid or data.humanoid.Health <= 0 then
			MobAI.UnregisterMob(mob)
			continue
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

	-- Send animation
	local animationId = config.animations and config.animations.attack
	if animationId then
		NetworkManager.FireAllClients("MobAttack", {
			mob = data.mob,
			animationId = animationId,
			duration = config.attackDuration or 0.5,
		})
	end

	-- Delayed damage (server-auth for basic attacks - they're melee)
	local damageDelay = config.damageDelay or 0.25
	task.delay(damageDelay, function()
		if not target or not target.Character then return end
		if data.state == STATES.DEAD then return end
		if not MobAI.IsInAttackRange(data, target) then return end

		local damage = config.damage * (data.damageMultiplier or 1.0)
		MobAI.DamagePlayer(target, damage, data)
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

	local tierText = data.mobTier ~= "normal" and " [" .. data.mobTier:upper() .. "]" or ""
	print("[MobAI]", data.mobId .. tierText, "casting:", skill.name)
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
			if root and hum and hum.Health > 0 then
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
		timestamp = tick(),
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

	pending.damageApplied = true

	local skill = pending.skill
	local mobData = pending.mobData
	local origin = pending.origin

	-- Apply damage to all players who reported being hit
	for player, hitData in pairs(pending.reportedHits) do
		-- Verify player still valid
		local char = player.Character
		if char then
			local hum = char:FindFirstChild("Humanoid")
			if hum and hum.Health > 0 then
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
		end
	end

	-- Clean up after short delay
	task.delay(5, function()
		pendingSkillHits[skillCastId] = nil
	end)
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

			local bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.Velocity = force
			bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			bodyVelocity.Parent = rootPart

			task.delay(0.2, function()
				if bodyVelocity and bodyVelocity.Parent then
					bodyVelocity:Destroy()
				end
			end)
		end
	end
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
			if forcedHumanoid and forcedHumanoid.Health > 0 then
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

		local playerX = playerRoot.Position.X
		if playerX >= mobX then continue end

		local distance = (rootPart.Position - playerRoot.Position).Magnitude
		if distance > config.perceptionRange and not isTaunting then
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
-- TAUNT SUPPORT
-- ═══════════════════════════════════════════════════════════

function MobAI.SetForcedTarget(mob, player, duration)
	local data = activeMobs[mob]
	if not data then return end

	data.forcedTarget = player
	data.tauntEndTime = tick() + duration
end

function MobAI.ClearForcedTarget(mob)
	local data = activeMobs[mob]
	if not data then return end

	data.forcedTarget = nil
	data.tauntEndTime = 0
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

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local mobPenetration = mobData.config.penetration or 0
	local finalDamage = StatsManager.CalculateDamageTaken(player, baseDamage, mobPenetration)

	humanoid:TakeDamage(finalDamage)

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

	local tierText = mobData.mobTier ~= "normal" and " [" .. mobData.mobTier:upper() .. "]" or ""
	local skillText = skillId and (" (" .. skillId .. ")") or ""
	print("[MobAI]", mobData.mobId .. tierText .. skillText, "dealt", math.floor(finalDamage), "to", player.Name)
end

function MobAI.HandlePlayerDeath(player, mobData)
	print("[MobAI]", player.Name, "killed by", mobData.mobId, "Lv." .. mobData.level)
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

function MobAI.GetMobsByTier(tier)
	local mobs = {}
	for mob, data in pairs(activeMobs) do
		if data.mobTier == tier then
			table.insert(mobs, mob)
		end
	end
	return mobs
end

function MobAI.GetAllMobData()
	return activeMobs
end

function MobAI.GetMobsInRange(position, range)
	local mobs = {}
	for mob, data in pairs(activeMobs) do
		if data.rootPart then
			local distance = (data.rootPart.Position - position).Magnitude
			if distance <= range then
				table.insert(mobs, mob)
			end
		end
	end
	return mobs
end

return MobAI