-- StarterPlayerScripts/Modules/MobVisuals

local MobVisuals = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- Track active skill visuals
local activeSkillCasts = {}  -- { [skillCastId] = { ... } }
local mobAnimations = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function MobVisuals.Init()
	-- Basic attack animations
	NetworkManager.OnServerEvent("MobAttack", function(data)
		MobVisuals.OnMobAttack(data)
	end)

	-- Skill casts (with hit detection)
	NetworkManager.OnServerEvent("MobSkillCast", function(data)
		MobVisuals.OnMobSkillCast(data)
	end)

	-- Confirmed hit feedback
	NetworkManager.OnServerEvent("MobSkillHit", function(data)
		MobVisuals.OnMobSkillHit(data)
	end)

	print("[MobVisuals] Initialized (Client-Auth Hit Detection)")
end

-- ═══════════════════════════════════════════════════════════
-- BASIC ATTACK
-- ═══════════════════════════════════════════════════════════

function MobVisuals.OnMobAttack(data)
	local mob = data.mob
	local animationId = data.animationId

	if not mob or not mob.Parent then return end
	if not animationId then return end

	MobVisuals.PlayAnimation(mob, animationId)
end

-- ═══════════════════════════════════════════════════════════
-- SKILL CAST (Client-Auth Hit Detection)
-- ═══════════════════════════════════════════════════════════

function MobVisuals.OnMobSkillCast(data)
	local skillCastId = data.skillCastId
	local mob = data.mob
	local origin = data.origin
	local animationId = data.animationId
	local damageDelay = data.damageDelay or 0.5
	local damageWindow = data.damageWindow or 0.3
	local shape = data.shape
	local shapeParams = data.shapeParams or {}
	local visual = data.visual or {}

	if not mob or not mob.Parent then return end

	-- Play animation
	if animationId then
		MobVisuals.PlayAnimation(mob, animationId)
	end

	-- Store cast data
	activeSkillCasts[skillCastId] = {
		origin = origin,
		shape = shape,
		shapeParams = shapeParams,
		damageDelay = damageDelay,
		damageWindow = damageWindow,
		startTime = tick(),
		hitChecked = false,
		reported = false,
	}

	-- Show warning visual
	if visual.type then
		MobVisuals.CreateWarningVisual(origin, shape, shapeParams, visual, damageDelay)
	end

	-- Schedule hit check at damage frame
	task.delay(damageDelay, function()
		MobVisuals.CheckSkillHit(skillCastId, data)
	end)

	-- Cleanup after damage window
	task.delay(damageDelay + damageWindow + 1, function()
		activeSkillCasts[skillCastId] = nil
	end)
end

-- ═══════════════════════════════════════════════════════════
-- HIT DETECTION (Client-Side)
-- ═══════════════════════════════════════════════════════════

function MobVisuals.CheckSkillHit(skillCastId, skillData)
	local castInfo = activeSkillCasts[skillCastId]
	if not castInfo or castInfo.hitChecked then return end

	castInfo.hitChecked = true

	local character = LocalPlayer.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then return end

	local playerPos = rootPart.Position
	local origin = castInfo.origin
	local shape = castInfo.shape
	local shapeParams = castInfo.shapeParams

	-- Check if player is in the skill's area
	local isHit = MobVisuals.IsPositionInShape(playerPos, origin, shape, shapeParams)

	if isHit then
		-- Report hit to server
		castInfo.reported = true
		NetworkManager.FireServer("MobSkillHitReport", {
			skillCastId = skillCastId,
			position = playerPos,
		})

		-- Show impact visual immediately (responsive feedback)
		MobVisuals.CreateImpactVisual(origin, shape, shapeParams, skillData.visual or {})
	end
end

function MobVisuals.IsPositionInShape(position, origin, shape, params)
	local range = params.range or 10
	local distance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(origin.X, 0, origin.Z)).Magnitude

	if shape == "Circle" then
		return distance <= range

	elseif shape == "Cone" then
		if distance > range then return false end

		local direction = params.direction or Vector3.new(1, 0, 0)
		local toPlayer = (position - origin).Unit
		local angle = math.deg(math.acos(direction:Dot(toPlayer)))
		local halfAngle = (params.angle or 90) / 2

		return angle <= halfAngle

	elseif shape == "Rectangle" then
		local length = params.range or 10
		local width = params.width or 5
		local direction = params.direction or Vector3.new(1, 0, 0)

		local toPlayer = position - origin
		local forward = direction
		local right = Vector3.new(-forward.Z, 0, forward.X)

		local forwardDist = toPlayer:Dot(forward)
		local rightDist = math.abs(toPlayer:Dot(right))

		return forwardDist >= 0 and forwardDist <= length and rightDist <= width / 2

	elseif shape == "Ring" then
		local outerRange = range
		local innerRange = params.innerRadius or 0

		return distance <= outerRange and distance >= innerRange
	end

	-- Default: circle check
	return distance <= range
end

-- ═══════════════════════════════════════════════════════════
-- CONFIRMED HIT FEEDBACK
-- ═══════════════════════════════════════════════════════════

function MobVisuals.OnMobSkillHit(data)
	-- Server confirmed we got hit
	-- Could add screen shake, flash, etc.
	local skillId = data.skillId
	local damage = data.damage

	-- Screen flash (simple feedback)
	MobVisuals.ScreenFlash(Color3.fromRGB(255, 0, 0), 0.2)
end

function MobVisuals.ScreenFlash(color, duration)
	local screenGui = LocalPlayer:FindFirstChild("PlayerGui")
	if not screenGui then return end

	local flash = Instance.new("Frame")
	flash.Name = "DamageFlash"
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 0.7
	flash.BorderSizePixel = 0
	flash.ZIndex = 100
	flash.Parent = screenGui

	local tween = TweenService:Create(flash, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		BackgroundTransparency = 1,
	})

	tween:Play()
	tween.Completed:Connect(function()
		flash:Destroy()
	end)
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATION PLAYBACK
-- ═══════════════════════════════════════════════════════════

function MobVisuals.PlayAnimation(mob, animationId)
	local humanoid = mob:FindFirstChild("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	if mobAnimations[mob] and mobAnimations[mob].track then
		mobAnimations[mob].track:Stop(0.1)
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if success and track then
		track:Play()
		mobAnimations[mob] = { track = track }
		animation:Destroy()

		if not mob:GetAttribute("VisualTracked") then
			mob:SetAttribute("VisualTracked", true)
			mob.AncestryChanged:Connect(function(_, parent)
				if not parent then
					mobAnimations[mob] = nil
				end
			end)
		end
	else
		animation:Destroy()
	end
end

-- ═══════════════════════════════════════════════════════════
-- VISUAL EFFECTS
-- ═══════════════════════════════════════════════════════════

function MobVisuals.CreateWarningVisual(origin, shape, shapeParams, visual, duration)
	local visualType = visual.type
	local warningColor = visual.warningColor or Color3.fromRGB(255, 100, 100)
	local range = shapeParams.range or 10

	if visualType == "GroundSlam" or visualType == "Roar" or shape == "Circle" then
		MobVisuals.CreateCircleWarning(origin, range, warningColor, duration)
	end
end

function MobVisuals.CreateImpactVisual(origin, shape, shapeParams, visual)
	local visualType = visual.type
	local color = visual.color or Color3.fromRGB(255, 255, 255)
	local range = shapeParams.range or 10

	if visualType == "GroundSlam" then
		-- Shockwave ring expanding outward
		local ring = Instance.new("Part")
		ring.Name = "GroundSlamImpact"
		ring.Anchored = true
		ring.CanCollide = false
		ring.Material = Enum.Material.Neon
		ring.Color = color
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.5, 1, 1)
		ring.CFrame = CFrame.new(origin.X, origin.Y - 1, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = 0.3
		ring.Parent = workspace

		local expandTween = TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.5, range * 2, range * 2),
			Transparency = 1,
		})

		expandTween:Play()
		expandTween.Completed:Connect(function()
			ring:Destroy()
		end)

	elseif visualType == "Roar" then
		-- Expanding sphere
		local sphere = Instance.new("Part")
		sphere.Name = "RoarImpact"
		sphere.Anchored = true
		sphere.CanCollide = false
		sphere.Material = Enum.Material.ForceField
		sphere.Color = color
		sphere.Shape = Enum.PartType.Ball
		sphere.Size = Vector3.new(4, 4, 4)
		sphere.Position = origin
		sphere.Transparency = 0.5
		sphere.Parent = workspace

		local expandTween = TweenService:Create(sphere, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(range * 2, range * 2, range * 2),
			Transparency = 1,
		})

		expandTween:Play()
		expandTween.Completed:Connect(function()
			sphere:Destroy()
		end)

	else
		-- Generic circle pulse
		local circle = Instance.new("Part")
		circle.Name = "SkillImpact"
		circle.Anchored = true
		circle.CanCollide = false
		circle.Material = Enum.Material.Neon
		circle.Color = color
		circle.Shape = Enum.PartType.Cylinder
		circle.Size = Vector3.new(0.3, range * 2, range * 2)
		circle.CFrame = CFrame.new(origin.X, origin.Y - 1.5, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
		circle.Transparency = 0.3
		circle.Parent = workspace

		local fadeTween = TweenService:Create(circle, TweenInfo.new(0.5, Enum.EasingStyle.Linear), {
			Transparency = 1,
			Size = Vector3.new(0.3, range * 2.5, range * 2.5),
		})

		fadeTween:Play()
		fadeTween.Completed:Connect(function()
			circle:Destroy()
		end)
	end
end

function MobVisuals.CreateCircleWarning(origin, radius, color, duration)
	-- Pulsing warning circle on ground
	local warning = Instance.new("Part")
	warning.Name = "SkillWarning"
	warning.Anchored = true
	warning.CanCollide = false
	warning.Material = Enum.Material.Neon
	warning.Color = color
	warning.Shape = Enum.PartType.Cylinder
	warning.Size = Vector3.new(0.1, radius * 2, radius * 2)
	warning.CFrame = CFrame.new(origin.X, origin.Y - 1.8, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
	warning.Transparency = 0.5
	warning.Parent = workspace

	-- Pulse effect
	local pulseIn = TweenService:Create(warning, TweenInfo.new(duration / 4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 2, true), {
		Transparency = 0.2,
		Size = Vector3.new(0.1, radius * 2.1, radius * 2.1),
	})

	pulseIn:Play()

	-- Remove after duration
	task.delay(duration, function()
		if warning and warning.Parent then
			warning:Destroy()
		end
	end)
end

return MobVisuals