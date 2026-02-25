-- ServerScriptService/Modules/SkillEffects

local SkillEffects = {}

local TweenService = game:GetService("TweenService")

-- Dependencies (set by SkillExecutor)
SkillEffects.AttackShapes = nil
SkillEffects.NetworkManager = nil
SkillEffects.MobAI = nil
SkillEffects.SkillManager = nil

local initialized = false

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function SkillEffects.Init(dependencies)
	-- If called without dependencies (from ServerLoader), skip
	-- SkillExecutor will call again with proper dependencies
	if not dependencies then
		print("[SkillEffects] Waiting for SkillExecutor to initialize with dependencies...")
		return
	end

	if initialized then return end

	SkillEffects.AttackShapes = dependencies.AttackShapes
	SkillEffects.NetworkManager = dependencies.NetworkManager
	SkillEffects.MobAI = dependencies.MobAI
	SkillEffects.SkillManager = dependencies.SkillManager

	initialized = true
	print("[SkillEffects] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- APPLY EFFECTS FROM SKILL CONFIG
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyEffects(player, effects, origin)
	for _, effect in ipairs(effects or {}) do
		SkillEffects.ApplyEffect(player, effect, origin)
	end
end

function SkillEffects.ApplyEffect(player, effect, origin)
	local effectType = effect.type

	if effectType == "Pull" then
		SkillEffects.ApplyPull(player, effect, origin)

	elseif effectType == "Taunt" then
		SkillEffects.ApplyTaunt(player, effect, origin)

	elseif effectType == "Stun" then
		SkillEffects.ApplyStun(player, effect, origin)

	elseif effectType == "DamageReduction" then
		SkillEffects.ApplyDamageReduction(player, effect, origin)

	elseif effectType == "Slow" then
		SkillEffects.ApplySlow(player, effect, origin)

	elseif effectType == "Knockback" then
		SkillEffects.ApplyKnockback(player, effect, origin)

	else
		warn("[SkillEffects] Unknown effect type:", effectType)
	end
end

-- ═══════════════════════════════════════════════════════════
-- PULL EFFECT
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyPull(player, effect, origin)
	local mobsInRange = SkillEffects.AttackShapes.GetTargetsInCircle(origin, effect.range, "IsMob")

	for _, mob in ipairs(mobsInRange) do
		local rootPart = mob:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local toPlayer = (origin - rootPart.Position)
			local pullDir = Vector3.new(toPlayer.X, 0, toPlayer.Z).Unit
			local pullDist = math.min(toPlayer.Magnitude - 3, effect.strength or 10)

			local endPos = rootPart.Position + (pullDir * pullDist)
			local tween = TweenService:Create(rootPart, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(endPos)
			})
			tween:Play()
		end
	end

	print("[SkillEffects] Pulled", #mobsInRange, "mobs")
end

-- ═══════════════════════════════════════════════════════════
-- TAUNT EFFECT
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyTaunt(player, effect, origin)
	if not SkillEffects.MobAI then 
		warn("[SkillEffects] MobAI not loaded")
		return 
	end

	player:SetAttribute("IsTaunting", true)

	local mobsInRange = SkillEffects.AttackShapes.GetTargetsInCircle(origin, effect.range, "IsMob")

	for _, mob in ipairs(mobsInRange) do
		local mobData = SkillEffects.MobAI.GetMobData(mob)
		if mobData then
			mobData.forcedTarget = player
			mobData.tauntEndTime = tick() + effect.duration
		end
	end

	task.delay(effect.duration, function()
		if player and player:GetAttribute("IsTaunting") then
			player:SetAttribute("IsTaunting", false)
		end
	end)

	print("[SkillEffects] Taunted", #mobsInRange, "mobs for", effect.duration, "s")
end

-- ═══════════════════════════════════════════════════════════
-- STUN EFFECT
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyStun(player, effect, origin)
	local mobsInRange = SkillEffects.AttackShapes.GetTargetsInCircle(origin, effect.range or 10, "IsMob")

	for _, mob in ipairs(mobsInRange) do
		local humanoid = mob:FindFirstChild("Humanoid")
		if humanoid then
			local originalSpeed = humanoid.WalkSpeed
			humanoid.WalkSpeed = 0
			mob:SetAttribute("IsStunned", true)

			task.delay(effect.duration, function()
				if mob and mob.Parent then
					humanoid.WalkSpeed = originalSpeed
					mob:SetAttribute("IsStunned", false)
				end
			end)
		end
	end

	print("[SkillEffects] Stunned", #mobsInRange, "mobs for", effect.duration, "s")
end

-- ═══════════════════════════════════════════════════════════
-- DAMAGE REDUCTION (Buff on player)
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyDamageReduction(player, effect, origin)
	if not SkillEffects.SkillManager then return end

	local buffId = "DamageReduction_" .. player.UserId .. "_" .. tick()

	if effect.target == "Self" then
		SkillEffects.SkillManager.ApplyBuff(player, buffId, effect)

	elseif effect.target == "AlliesBehind" then
		-- Get player's position
		local character = player.Character
		if not character then return end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end

		local behindDirection = Vector3.new(-1, 0, 0)

		-- Find allies in cone behind
		local allies = SkillEffects.GetAlliesInCone(
			player,
			rootPart.Position,
			behindDirection,
			effect.shapeParams.range,
			effect.shapeParams.angle
		)

		for _, allyPlayer in ipairs(allies) do
			SkillEffects.SkillManager.ApplyBuff(allyPlayer, buffId .. "_" .. allyPlayer.UserId, effect)
		end

		print("[SkillEffects] Protected", #allies, "allies behind")
	end
end

-- ═══════════════════════════════════════════════════════════
-- SLOW EFFECT
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplySlow(player, effect, origin)
	local mobsInRange = SkillEffects.AttackShapes.GetTargetsInCircle(origin, effect.range or 10, "IsMob")

	local slowPercent = effect.amount or 50

	for _, mob in ipairs(mobsInRange) do
		local humanoid = mob:FindFirstChild("Humanoid")
		if humanoid then
			local originalSpeed = humanoid.WalkSpeed
			humanoid.WalkSpeed = originalSpeed * (1 - slowPercent / 100)
			mob:SetAttribute("IsSlowed", true)

			task.delay(effect.duration, function()
				if mob and mob.Parent then
					humanoid.WalkSpeed = originalSpeed
					mob:SetAttribute("IsSlowed", false)
				end
			end)
		end
	end

	print("[SkillEffects] Slowed", #mobsInRange, "mobs by", slowPercent, "%")
end

-- ═══════════════════════════════════════════════════════════
-- KNOCKBACK EFFECT
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyKnockback(player, effect, origin)
	local mobsInRange = SkillEffects.AttackShapes.GetTargetsInCircle(origin, effect.range or 10, "IsMob")

	for _, mob in ipairs(mobsInRange) do
		local rootPart = mob:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local awayFromPlayer = (rootPart.Position - origin)
			local knockDir = Vector3.new(awayFromPlayer.X, 0, awayFromPlayer.Z).Unit
			local knockDist = effect.strength or 10

			local endPos = rootPart.Position + (knockDir * knockDist)
			local tween = TweenService:Create(rootPart, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(endPos)
			})
			tween:Play()
		end
	end

	print("[SkillEffects] Knocked back", #mobsInRange, "mobs")
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function SkillEffects.GetAlliesInCone(excludePlayer, origin, direction, range, angle)
	local allies = {}
	local Players = game:GetService("Players")

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= excludePlayer then
			local char = otherPlayer.Character
			if char then
				local rootPart = char:FindFirstChild("HumanoidRootPart")
				if rootPart then
					local toAlly = rootPart.Position - origin
					local flatDir = Vector3.new(direction.X, 0, direction.Z).Unit
					local toAllyFlat = Vector3.new(toAlly.X, 0, toAlly.Z)

					if toAllyFlat.Magnitude <= range and toAllyFlat.Magnitude > 0 then
						local dot = flatDir:Dot(toAllyFlat.Unit)
						local angleBetween = math.deg(math.acos(math.clamp(dot, -1, 1)))
						if angleBetween <= (angle / 2) then
							table.insert(allies, otherPlayer)
						end
					end
				end
			end
		end
	end

	return allies
end

return SkillEffects