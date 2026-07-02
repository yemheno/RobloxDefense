-- ServerScriptService/Modules/ClassSkills/BaseSkills

local BaseSkills = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedGeometry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedGeometry"))

-- Dependencies (set by SkillManager.Init)
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
				if rootPart and SharedGeometry.IsInShape(rootPart.Position, params.origin, shapeName, params) then
					table.insert(allies, otherPlayer)
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

	return true
end

-- ═══════════════════════════════════════════════════════════
-- MOUSE-TARGET HELPERS
-- ═══════════════════════════════════════════════════════════

--- Clamp a target position to a maximum range from the player (flat / XZ only).
--- If the target is within range it is returned unchanged (Y stays as-is).
--- If the target is beyond the range, it is moved to the edge along the XZ line.
function BaseSkills.ClampTargetPosition(playerPos, targetPos, maxRange)
	if not targetPos then return playerPos end

	local offset     = targetPos - playerPos
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)

	if flatOffset.Magnitude <= maxRange then
		-- Within range – keep the original target position
		return targetPos
	end

	-- Beyond range – clamp to max distance on the XZ plane, keep player Y
	local clamped = flatOffset.Unit * maxRange
	return Vector3.new(playerPos.X + clamped.X, playerPos.Y, playerPos.Z + clamped.Z)
end

--- §LD-SK1: Deterministic forward-cast resolver.
--- Returns the world-space landing position for an AoE / placed-effect
--- skill, computed as `playerPos + lookDir * castDistance`. This
--- replaces the previous "use the mouse position the client sent"
--- pattern, which was inconsistent across input devices and (more
--- importantly) was always nil because the SkillInput client never
--- actually sent `inputData.targetPosition` — meaning the AoE landed
--- at the player's feet while the visual preview followed the mouse.
---
--- Per-skill cast distance is read from `skill.castDistance`; if not
--- set, defaults to `skill.maxRange * 0.6` (rounded down by the
--- caller's needs) which puts the AoE comfortably ahead of the
--- caster without overshooting the visual indicator.
function BaseSkills.GetForwardCastPosition(player, skill, inputData)
	local rootPart = BaseSkills.GetPlayerRootPart(player)
	if not rootPart then return Vector3.zero end

	local playerPos = rootPart.Position

	-- Prefer the client-supplied lookDirection (already flat, normalized,
	-- and matches the FaceDirection / FaceMouse correction the client
	-- applied). Fall back to the server's view of CFrame.LookVector.
	local lookDir
	if inputData and typeof(inputData.lookDirection) == "Vector3"
		and inputData.lookDirection.Magnitude > 0.001 then
		lookDir = inputData.lookDirection
	else
		local lv = rootPart.CFrame.LookVector
		lookDir = Vector3.new(lv.X, 0, lv.Z)
	end

	if lookDir.Magnitude < 0.001 then
		lookDir = Vector3.new(0, 0, -1)
	else
		lookDir = lookDir.Unit
	end

	local castDistance = skill.castDistance or ((skill.maxRange or 30) * 0.6)
	return playerPos + lookDir * castDistance
end

--- §T2/Z3: single cast-direction resolver — replaces six copy-pasted
--- variants across Aegis/Arcanist/Hunter skill files. Returns a flat,
--- normalized, never-NaN direction.
---
--- inputData handling is deliberate:
---   • Pass `inputData`  → prefer the client's lookDirection (Hunter
---     projectile skills — matches the client's aim correction).
---   • Pass `nil`        → server CFrame.LookVector only (Aegis /
---     Arcanist melee & beam skills keep their server-authoritative
---     aim; passing inputData here would CHANGE aiming behavior).
---
--- The zero-guard runs AFTER flattening: the old Hunter client-look
--- branch normalized `Vector3.new(x, 0, z)` unguarded, so a vertical
--- lookDirection (e.g. (0,1,0) — magnitude 1, passed the pre-check)
--- produced a NaN direction that poisoned the shape math.
function BaseSkills.GetCastDirection(rootPart, inputData)
	local flat
	if inputData and typeof(inputData.lookDirection) == "Vector3"
		and inputData.lookDirection.Magnitude > 0.001 then
		local cl = inputData.lookDirection
		flat = Vector3.new(cl.X, 0, cl.Z)
	end
	if not flat or flat.Magnitude < 0.001 then
		local lv = rootPart.CFrame.LookVector
		flat = Vector3.new(lv.X, 0, lv.Z)
	end
	if flat.Magnitude < 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

-- ═══════════════════════════════════════════════════════════
-- SHARED SKILL GETTERS (injected into class modules to avoid duplication)
-- ═══════════════════════════════════════════════════════════

--- Inject standard getter functions into a class skill module.
--- Call from each class module: BaseSkills.InjectGetters(AegisSkills)
function BaseSkills.InjectGetters(classModule)
	function classModule.GetSkillBySlot(slot)
		return classModule.Skills[slot]
	end

	function classModule.GetSkillById(skillId)
		for _, skill in pairs(classModule.Skills) do
			if skill.id == skillId then return skill end
		end
		return nil
	end

	function classModule.GetAllSkills()
		return classModule.Skills
	end

	function classModule.GetSkillCount()
		local count = 0
		for _ in pairs(classModule.Skills) do count = count + 1 end
		return count
	end
end

return BaseSkills