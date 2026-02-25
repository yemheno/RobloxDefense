-- ServerScriptService/Modules/SkillManager

local SkillManager = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = script.Parent

-- Dependencies (lazy load)
local NetworkManager = nil
local ResourceManager = nil
local StatsManager = nil
local ClassManager = nil
local AttackShapes = nil
local SkillRegistry = nil

-- Child modules
local SkillExecutor = nil

-- Player tracking
local playerCooldowns = {}    -- [player] = { [skillId] = endTime }
local activeBuffs = {}        -- [player] = { [buffId] = buffData }
local playerCasting = {}      -- [player] = { skillId, endTime, skill } or nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function SkillManager.Init()
	-- Load dependencies
	NetworkManager = require(Modules:WaitForChild("NetworkManager"))
	ResourceManager = require(Modules:WaitForChild("ResourceManager"))
	StatsManager = require(Modules:WaitForChild("StatsManager"))
	ClassManager = require(Modules:WaitForChild("ClassManager"))
	AttackShapes = require(Modules:WaitForChild("AttackShapes"))
	SkillRegistry = require(Modules:WaitForChild("SkillRegistry"))

	-- Load child modules
	SkillExecutor = require(script:WaitForChild("SkillExecutor"))
	SkillExecutor.Init(SkillManager)

	-- Create network events
	NetworkManager.GetEvent("SkillRequest")
	NetworkManager.GetEvent("SkillActivated")
	NetworkManager.GetEvent("SkillFailed")
	NetworkManager.GetEvent("SkillCooldownUpdate")
	NetworkManager.GetEvent("SkillCastStarted")     -- NEW
	NetworkManager.GetEvent("SkillCastCompleted")   -- NEW
	NetworkManager.GetEvent("SkillCastInterrupted") -- NEW
	NetworkManager.GetEvent("BuffApplied")
	NetworkManager.GetEvent("BuffRemoved")

	-- Listen for skill requests
	NetworkManager.OnClientEvent("SkillRequest", function(player, skillId, inputData)
		SkillManager.TryUseSkill(player, skillId, inputData)
	end)

	-- Player lifecycle
	Players.PlayerAdded:Connect(function(player)
		SkillManager.SetupPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		SkillManager.RemovePlayer(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		SkillManager.SetupPlayer(player)
	end

	-- Update loop (buffs + casting)
	RunService.Heartbeat:Connect(function(dt)
		SkillManager.UpdateBuffs(dt)
		SkillManager.UpdateCasting(dt)
	end)

	print("[SkillManager] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- PLAYER SETUP / CLEANUP
-- ═══════════════════════════════════════════════════════════

function SkillManager.SetupPlayer(player)
	playerCooldowns[player] = {}
	activeBuffs[player] = {}
	playerCasting[player] = nil

	-- Send initial skill data to client
	local className = ClassManager.GetClassName(player)
	local classSkills = SkillRegistry.GetClassSkillIds(className)

	NetworkManager.FireClient(player, "SkillCooldownUpdate", {
		skills = classSkills,
		cooldowns = {},
	})
end

function SkillManager.RemovePlayer(player)
	playerCooldowns[player] = nil
	activeBuffs[player] = nil
	playerCasting[player] = nil
end

-- ═══════════════════════════════════════════════════════════
-- CASTING SYSTEM
-- ═══════════════════════════════════════════════════════════

function SkillManager.StartCasting(player, skill, inputData)
	local character = player.Character
	if not character then return false end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return false end

	-- Store original walk speed
	local originalWalkSpeed = humanoid.WalkSpeed

	-- Lock movement if needed
	if skill.lockMovement then
		humanoid.WalkSpeed = 0
	end

	-- Set casting state
	playerCasting[player] = {
		skillId = skill.id,
		skill = skill,
		inputData = inputData,
		endTime = tick() + skill.castTime,
		originalWalkSpeed = originalWalkSpeed,
	}

	-- Set attributes for other systems to check
	player:SetAttribute("IsCasting", true)
	if skill.lockSkills then
		player:SetAttribute("CastingLockSkills", true)
	end
	if skill.lockAttack then
		player:SetAttribute("CastingLockAttack", true)
	end

	-- Notify client
	NetworkManager.FireClient(player, "SkillCastStarted", {
		skillId = skill.id,
		castTime = skill.castTime,
		skillData = skill,
	})

	-- Notify all clients for animation
	NetworkManager.FireAllClients("SkillActivated", {
		skillId = skill.id,
		playerId = player.UserId,
		skillData = skill,
		isCasting = true,
	})

	print("[SkillManager]", player.Name, "casting", skill.name, "for", skill.castTime, "s")

	return true
end

function SkillManager.CompleteCasting(player, castData)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	local skill = castData.skill

	-- Restore walk speed
	if humanoid and skill.lockMovement then
		humanoid.WalkSpeed = castData.originalWalkSpeed
	end

	-- Clear casting state
	playerCasting[player] = nil
	player:SetAttribute("IsCasting", false)
	player:SetAttribute("CastingLockSkills", false)
	player:SetAttribute("CastingLockAttack", false)

	-- Notify client
	NetworkManager.FireClient(player, "SkillCastCompleted", {
		skillId = skill.id,
	})

	-- Execute the skill effect
	local success = SkillExecutor.Execute(player, skill, castData.inputData)

	if success then
		print("[SkillManager]", player.Name, "completed", skill.name)
	end
end

function SkillManager.InterruptCasting(player, reason)
	local castData = playerCasting[player]
	if not castData then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	local skill = castData.skill

	-- Restore walk speed
	if humanoid and skill.lockMovement then
		humanoid.WalkSpeed = castData.originalWalkSpeed
	end

	-- Refund resource (partial or full?)
	ResourceManager.ModifyResource(player, skill.resourceCost)

	-- Reset cooldown (skill was interrupted, shouldn't go on cooldown)
	SkillManager.ResetCooldown(player, skill.id)

	-- Clear casting state
	playerCasting[player] = nil
	player:SetAttribute("IsCasting", false)
	player:SetAttribute("CastingLockSkills", false)
	player:SetAttribute("CastingLockAttack", false)

	-- Notify client
	NetworkManager.FireClient(player, "SkillCastInterrupted", {
		skillId = skill.id,
		reason = reason or "Interrupted",
	})

	print("[SkillManager]", player.Name, "cast interrupted:", skill.name, "-", reason)
end

function SkillManager.UpdateCasting(dt)
	local now = tick()

	for player, castData in pairs(playerCasting) do
		if castData and now >= castData.endTime then
			SkillManager.CompleteCasting(player, castData)
		end
	end
end

function SkillManager.IsCasting(player)
	return playerCasting[player] ~= nil
end

function SkillManager.GetCastingSkill(player)
	local castData = playerCasting[player]
	return castData and castData.skill or nil
end

-- ═══════════════════════════════════════════════════════════
-- SKILL USAGE
-- ═══════════════════════════════════════════════════════════

function SkillManager.TryUseSkill(player, skillId, inputData)
	local skill = nil
	local className = ClassManager.GetClassName(player)

	-- Handle slot-based requests
	if type(skillId) == "string" and skillId:sub(1, 5) == "slot_" then
		local slot = tonumber(skillId:sub(6))

		skill = SkillRegistry.GetSkillBySlot(className, slot)

		if not skill then
			SkillManager.SendFailure(player, skillId, "No skill in slot " .. slot)
			return false
		end

		skillId = skill.id
	else
		skill = SkillRegistry.GetSkill(skillId)
		if not skill then
			SkillManager.SendFailure(player, skillId, "Invalid skill")
			return false
		end

		if not SkillRegistry.IsSkillForClass(skillId, className) then
			SkillManager.SendFailure(player, skillId, "Wrong class")
			return false
		end
	end

	-- Check if already casting
	if SkillManager.IsCasting(player) then
		SkillManager.SendFailure(player, skillId, "Already casting")
		return false
	end

	-- Check cooldown
	local canUse, remaining = SkillManager.CheckCooldown(player, skillId)
	if not canUse then
		SkillManager.SendFailure(player, skillId, "On cooldown", remaining)
		return false
	end

	-- Check resource
	local currentResource = ResourceManager.GetResource(player)
	if currentResource < skill.resourceCost then
		SkillManager.SendFailure(player, skillId, "Not enough " .. ResourceManager.GetResourceName(player))
		return false
	end

	-- Check if player can act (not stunned, etc.)
	if not SkillManager.CanPlayerAct(player) then
		SkillManager.SendFailure(player, skillId, "Cannot act")
		return false
	end

	-- All checks passed! Execute or start casting
	return SkillManager.ExecuteSkill(player, skill, inputData)
end

function SkillManager.ExecuteSkill(player, skill, inputData)
	-- Deduct resource
	ResourceManager.ModifyResource(player, -skill.resourceCost)

	-- Start cooldown
	SkillManager.StartCooldown(player, skill.id, skill.cooldown)

	-- Check if skill has cast time
	if skill.castTime and skill.castTime > 0 then
		-- Start casting (skill executes after cast time)
		return SkillManager.StartCasting(player, skill, inputData)
	else
		-- Instant skill - execute immediately
		NetworkManager.FireClient(player, "SkillActivated", {
			skillId = skill.id,
			skillData = skill,
		})

		local success = SkillExecutor.Execute(player, skill, inputData)

		if success then
			print("[SkillManager]", player.Name, "used", skill.name)
		end

		return success
	end
end

-- ═══════════════════════════════════════════════════════════
-- COOLDOWN MANAGEMENT
-- ═══════════════════════════════════════════════════════════

function SkillManager.CheckCooldown(player, skillId)
	local cooldowns = playerCooldowns[player]
	if not cooldowns then return true, 0 end

	local endTime = cooldowns[skillId]
	if not endTime then return true, 0 end

	local now = tick()
	if now >= endTime then
		cooldowns[skillId] = nil
		return true, 0
	end

	return false, endTime - now
end

function SkillManager.StartCooldown(player, skillId, duration)
	if not playerCooldowns[player] then
		playerCooldowns[player] = {}
	end

	playerCooldowns[player][skillId] = tick() + duration

	NetworkManager.FireClient(player, "SkillCooldownUpdate", {
		skillId = skillId,
		cooldown = duration,
		endTime = playerCooldowns[player][skillId],
	})
end

function SkillManager.GetCooldownRemaining(player, skillId)
	local canUse, remaining = SkillManager.CheckCooldown(player, skillId)
	return remaining
end

function SkillManager.ResetCooldown(player, skillId)
	if playerCooldowns[player] then
		playerCooldowns[player][skillId] = nil

		NetworkManager.FireClient(player, "SkillCooldownUpdate", {
			skillId = skillId,
			cooldown = 0,
			reset = true,
		})
	end
end

-- ═══════════════════════════════════════════════════════════
-- BUFF MANAGEMENT
-- ═══════════════════════════════════════════════════════════

function SkillManager.ApplyBuff(player, buffId, buffData)
	if not activeBuffs[player] then
		activeBuffs[player] = {}
	end

	activeBuffs[player][buffId] = {
		data = buffData,
		endTime = tick() + buffData.duration,
		appliedAt = tick(),
	}

	SkillManager.ApplyBuffEffect(player, buffData)

	NetworkManager.FireClient(player, "BuffApplied", {
		buffId = buffId,
		buffData = buffData,
	})

	print("[SkillManager]", player.Name, "gained buff:", buffId)
end

function SkillManager.RemoveBuff(player, buffId)
	local buffs = activeBuffs[player]
	if not buffs or not buffs[buffId] then return end

	local buffInfo = buffs[buffId]

	SkillManager.RemoveBuffEffect(player, buffInfo.data)

	buffs[buffId] = nil

	NetworkManager.FireClient(player, "BuffRemoved", {
		buffId = buffId,
	})

	print("[SkillManager]", player.Name, "lost buff:", buffId)
end

function SkillManager.ApplyBuffEffect(player, buffData)
	if buffData.type == "DamageReduction" then
		local current = StatsManager.GetBonus(player, "DamageReduction") or 0
		StatsManager.SetBonus(player, "DamageReduction", current + buffData.amount)
	end
end

function SkillManager.RemoveBuffEffect(player, buffData)
	if buffData.type == "DamageReduction" then
		local current = StatsManager.GetBonus(player, "DamageReduction") or 0
		StatsManager.SetBonus(player, "DamageReduction", current - buffData.amount)
	end
end

function SkillManager.UpdateBuffs(dt)
	local now = tick()

	for player, buffs in pairs(activeBuffs) do
		for buffId, buffInfo in pairs(buffs) do
			if now >= buffInfo.endTime then
				SkillManager.RemoveBuff(player, buffId)
			end
		end
	end
end

function SkillManager.HasBuff(player, buffId)
	local buffs = activeBuffs[player]
	return buffs and buffs[buffId] ~= nil
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function SkillManager.CanPlayerAct(player)
	if player:GetAttribute("IsStunned") then
		return false
	end

	-- Check for interrupt-able casting (OFF for now)
	-- if player:GetAttribute("IsCasting") then
	--     local castingSkill = SkillManager.GetCastingSkill(player)
	--     if castingSkill and castingSkill.canBeInterrupted then
	--         -- Could interrupt here
	--     end
	-- end

	return true
end

function SkillManager.SendFailure(player, skillId, reason, cooldownRemaining)
	NetworkManager.FireClient(player, "SkillFailed", {
		skillId = skillId,
		reason = reason,
		cooldownRemaining = cooldownRemaining,
	})
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS (For external modules)
-- ═══════════════════════════════════════════════════════════

function SkillManager.GetSkillRegistry()
	return SkillRegistry
end

function SkillManager.GetAttackShapes()
	return AttackShapes
end

function SkillManager.GetStatsManager()
	return StatsManager
end

function SkillManager.GetNetworkManager()
	return NetworkManager
end

return SkillManager