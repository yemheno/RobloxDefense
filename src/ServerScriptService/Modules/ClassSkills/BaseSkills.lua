-- ServerScriptService/Modules/ClassSkills/BaseSkills

local BaseSkills = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Dependencies (set by SkillExecutor)
BaseSkills.AttackShapes = nil
BaseSkills.StatsManager = nil
BaseSkills.NetworkManager = nil
BaseSkills.MobAI = nil
BaseSkills.SkillManager = nil
BaseSkills.DamageHandler = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function BaseSkills.Init(dependencies)
	BaseSkills.AttackShapes = dependencies.AttackShapes
	BaseSkills.StatsManager = dependencies.StatsManager
	BaseSkills.NetworkManager = dependencies.NetworkManager
	BaseSkills.MobAI = dependencies.MobAI
	BaseSkills.SkillManager = dependencies.SkillManager
	BaseSkills.DamageHandler = dependencies.DamageHandler

	print("[BaseSkills] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- DAMAGE UTILITIES
-- ═══════════════════════════════════════════════════════════

function BaseSkills.DamageMob(mob, player, damageMultiplier, sourceSkill, attackElement)
	local humanoid = mob:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil end

	if BaseSkills.DamageHandler then
		local result = BaseSkills.DamageHandler.DamageMob(mob, player, {
			damageMultiplier = damageMultiplier or 1,
			sourceSkill = sourceSkill,
			attackElement = attackElement,  -- nil → DamageHandler falls back to weapon element
		})
		if result then
			return true, result.isKill
		end
		return false, false
	end

	-- Emergency fallback (should never happen)
	warn("[BaseSkills] No DamageHandler! Using direct damage")
	humanoid:TakeDamage(10)
	return true, humanoid.Health <= 0
end

function BaseSkills.DamageTargets(targets, player, damageMultiplier, sourceSkill, attackElement)
	local hitCount = 0
	local killCount = 0

	for _, mob in ipairs(targets) do
		local hit, killed = BaseSkills.DamageMob(mob, player, damageMultiplier, sourceSkill, attackElement)
		if hit then
			hitCount = hitCount + 1
			if killed then killCount = killCount + 1 end
		end
	end

	return hitCount, killCount
end

-- ═══════════════════════════════════════════════════════════
-- TARGET FINDING
-- ═══════════════════════════════════════════════════════════

function BaseSkills.GetTargetsInShape(origin, direction, skill)
	return BaseSkills.AttackShapes.GetTargetsInShape(skill.shape, {
		origin = origin,
		direction = direction,
		range = skill.shapeParams.range,
		angle = skill.shapeParams.angle,
		width = skill.shapeParams.width,
		innerRadius = skill.shapeParams.innerRadius,
		filterAttribute = "IsMob",
	})
end

function BaseSkills.GetTargetsInCircle(origin, radius)
	return BaseSkills.AttackShapes.GetTargetsInCircle(origin, radius, "IsMob")
end

function BaseSkills.GetAlliesInShape(excludePlayer, shapeName, params)
	local allies = {}

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= excludePlayer then
			local char = otherPlayer.Character
			if char then
				local rootPart = char:FindFirstChild("HumanoidRootPart")
				if rootPart then
					local inShape = false

					if shapeName == "Cone" then
						local toAlly = rootPart.Position - params.origin
						local flatDir = Vector3.new(params.direction.X, 0, params.direction.Z).Unit
						local toAllyFlat = Vector3.new(toAlly.X, 0, toAlly.Z)

						if toAllyFlat.Magnitude <= params.range then
							local dot = flatDir:Dot(toAllyFlat.Unit)
							local angle = math.deg(math.acos(math.clamp(dot, -1, 1)))
							if angle <= (params.angle / 2) then
								inShape = true
							end
						end

					elseif shapeName == "Circle" then
						local dist = (rootPart.Position - params.origin).Magnitude
						inShape = dist <= params.range
					end

					if inShape then
						table.insert(allies, otherPlayer)
					end
				end
			end
		end
	end

	return allies
end

-- ═══════════════════════════════════════════════════════════
-- VISUAL HELPERS
-- ═══════════════════════════════════════════════════════════

function BaseSkills.SendVisualToAll(visualType, data)
	data.visualType = visualType
	BaseSkills.NetworkManager.FireAllClients("SkillVisual", data)
end

function BaseSkills.SendVisualToPlayer(player, visualType, data)
	data.visualType = visualType
	BaseSkills.NetworkManager.FireClient(player, "SkillVisual", data)
end

-- ═══════════════════════════════════════════════════════════
-- PLAYER UTILITIES
-- ═══════════════════════════════════════════════════════════

function BaseSkills.GetPlayerPosition(player)
	local character = player.Character
	if not character then return nil end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	return rootPart and rootPart.Position or nil
end

function BaseSkills.GetPlayerRootPart(player)
	local character = player.Character
	if not character then return nil end

	return character:FindFirstChild("HumanoidRootPart")
end

function BaseSkills.GetPlayerHumanoid(player)
	local character = player.Character
	if not character then return nil end

	return character:FindFirstChild("Humanoid")
end

-- ═══════════════════════════════════════════════════════════
-- GENERIC SKILL: DASH (All classes use this!)
-- ═══════════════════════════════════════════════════════════

function BaseSkills.ExecuteDash(player, skill, inputData)
	local rootPart = BaseSkills.GetPlayerRootPart(player)
	local humanoid = BaseSkills.GetPlayerHumanoid(player)
	if not rootPart or not humanoid then return false end

	-- DEBUG: Check what we're receiving
	print("[BaseSkills] Dash inputData:", inputData)
	print("[BaseSkills] moveDirection:", inputData and inputData.moveDirection)

	-- Use CLIENT-SENT direction (accurate!)
	local direction
	local moveDirection = inputData and inputData.moveDirection or Vector3.zero

	if moveDirection and moveDirection.Magnitude > 0.1 then
		direction = Vector3.new(moveDirection.X, 0, moveDirection.Z).Unit
	else
		-- Fallback when standing still
		direction = skill.fallbackDirection or Vector3.new(-1, 0, 0)
	end

	local startPos = rootPart.Position
	local endPos = startPos + (direction * skill.dashDistance)

	-- Raycast for walls
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {player.Character}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayResult = workspace:Raycast(startPos, direction * skill.dashDistance, rayParams)
	if rayResult then
		endPos = rayResult.Position - (direction * 2)
	end

	-- Keep Y position
	endPos = Vector3.new(endPos.X, startPos.Y, endPos.Z)

	if skill.unstoppable then
		player:SetAttribute("IsDashing", true)
	end

	-- Send visual
	BaseSkills.SendVisualToAll("Dash", {
		skillId = skill.id,
		playerId = player.UserId,
		startPos = startPos,
		endPos = endPos,
		direction = direction,
		duration = skill.dashDuration,
		color = skill.debugColor,
	})

	-- Perform dash
	rootPart.Anchored = true
	local tweenInfo = TweenInfo.new(skill.dashDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local tween = TweenService:Create(rootPart, tweenInfo, {
		CFrame = CFrame.new(endPos) * CFrame.Angles(0, math.atan2(-direction.X, -direction.Z), 0)
	})

	tween:Play()
	tween.Completed:Connect(function()
		rootPart.Anchored = false
		player:SetAttribute("IsDashing", false)
	end)

	print("[BaseSkills] Dash - Dir:", direction)
	return true
end

-- ═══════════════════════════════════════════════════════════
-- GENERIC SKILL: SIMPLE DAMAGE (Shape + Damage)
-- ═══════════════════════════════════════════════════════════

function BaseSkills.ExecuteSimpleDamage(player, skill, inputData)
	local rootPart = BaseSkills.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position
	local direction = Vector3.new(1, 0, 0)

	local targets = BaseSkills.GetTargetsInShape(origin, direction, skill)
	local hitCount = BaseSkills.DamageTargets(targets, player, skill.damageMultiplier or 1, skill.id, skill.element)

	print("[BaseSkills]", skill.name, "- Hits:", hitCount)
	return true
end

return BaseSkills