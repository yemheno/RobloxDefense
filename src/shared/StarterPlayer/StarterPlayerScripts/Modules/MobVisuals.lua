-- StarterPlayerScripts/Modules/MobVisuals

local MobVisuals = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer

-- §AGX/X35: must match DefenseAnimation.BREACH_TAG on the server.
local BREACH_TAG = "DefenseBreach"
local breachPlayed = setmetatable({}, { __mode = "k" })  -- [mob] = true

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local SharedGeometry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedGeometry"))

-- Track active skill visuals
local activeSkillCasts = {}  -- { [skillCastId] = { ... } }

-- AnimationSystem loaded lazily
local AnimationSystem = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function MobVisuals.Init()
	-- Lazy-load AnimationSystem
	task.spawn(function()
		local as = Modules:FindFirstChild("AnimationSystem")
		if as then
			AnimationSystem = require(as)
		end
	end)

	-- Basic attack hit detection (client-auth)
	NetworkManager.OnServerEvent("MobBasicAttackCast", function(data)
		MobVisuals.OnMobBasicAttackCast(data)
	end)

	-- Skill casts (with hit detection)
	NetworkManager.OnServerEvent("MobSkillCast", function(data)
		MobVisuals.OnMobSkillCast(data)
	end)

	-- Confirmed hit feedback
	NetworkManager.OnServerEvent("MobSkillHit", function(data)
		MobVisuals.OnMobSkillHit(data)
	end)

	-- Mob death VFX
	NetworkManager.OnServerEvent("MobDeath", function(data)
		MobVisuals.OnMobDeath(data)
	end)

	-- §AGX/X35: defense-line breach visual (was a server-side per-part
	-- tween). The server freezes the mob, sets BreachStyle/BreachDuration
	-- and tags it; we play the style on our local copy of the parts.
	CollectionService:GetInstanceAddedSignal(BREACH_TAG):Connect(function(mob)
		MobVisuals.PlayBreachVisual(mob)
	end)
	for _, mob in ipairs(CollectionService:GetTagged(BREACH_TAG)) do
		MobVisuals.PlayBreachVisual(mob)
	end

end

-- ═══════════════════════════════════════════════════════════
-- BASIC ATTACK HIT DETECTION (Client-Auth)
-- ═══════════════════════════════════════════════════════════

function MobVisuals.OnMobBasicAttackCast(data)
	local mob = data.mob
	local animationId = data.animationId
	local damageDelay = data.damageDelay or 0.25
	local attackRange = data.attackRange or 5
	local attackCastId = data.attackCastId
	local targetPlayer = data.targetPlayer

	if not mob or not mob.Parent then return end

	-- Play animation (all clients see this)
	if animationId then
		MobVisuals.PlayAnimation(mob, animationId)
	end

	-- Only the targeted player runs hit detection
	if targetPlayer ~= LocalPlayer then return end

	-- Schedule hit check at damage frame
	task.delay(damageDelay, function()
		local character = LocalPlayer.Character
		if not character then return end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChild("Humanoid")
		if not rootPart or not humanoid or humanoid.Health <= 0 then return end

		if not mob or not mob.Parent then return end
		local mobRoot = mob:FindFirstChild("HumanoidRootPart") or mob.PrimaryPart
		if not mobRoot then return end

		local dist = (rootPart.Position - mobRoot.Position).Magnitude
		if dist <= attackRange then
			-- In range at damage frame → report hit
			NetworkManager.FireServer("MobBasicAttackHitReport", {
				attackCastId = attackCastId,
			})
		end
	end)
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
		startTime = os.clock(),
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
	return SharedGeometry.IsInShape(position, origin, shape, params)
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
	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then return end

	-- Frames must live inside a ScreenGui to render
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DamageFlashGui"
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local flash = Instance.new("Frame")
	flash.Name = "DamageFlash"
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 0.7
	flash.BorderSizePixel = 0
	flash.Parent = screenGui

	local tween = TweenService:Create(flash, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		BackgroundTransparency = 1,
	})

	tween:Play()
	tween.Completed:Connect(function()
		screenGui:Destroy()
	end)
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATION PLAYBACK
-- ═══════════════════════════════════════════════════════════

function MobVisuals.PlayAnimation(mob, animationId)
	if not AnimationSystem then return end
	AnimationSystem.Play(mob, animationId, {
		category = "attack",
		fadeIn   = 0.1,
	})
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

-- ═══════════════════════════════════════════════════════════
-- MOB DEATH VFX
-- ═══════════════════════════════════════════════════════════

function MobVisuals.OnMobDeath(data)
	local position = data.position
	if not position then return end

	local mobTier = data.mobTier or "normal"

	-- Colour based on mob tier
	local color = Color3.fromRGB(180, 180, 180)
	if mobTier == "elite" then
		color = Color3.fromRGB(200, 120, 255)
	elseif mobTier == "boss" then
		color = Color3.fromRGB(255, 60, 60)
	elseif mobTier == "miniboss" then
		color = Color3.fromRGB(255, 180, 50)
	end

	-- Burst sphere
	local sphere = Instance.new("Part")
	sphere.Name        = "MobDeathBurst"
	sphere.Shape       = Enum.PartType.Ball
	sphere.Size        = Vector3.new(2, 2, 2)
	sphere.Position    = position
	sphere.Anchored    = true
	sphere.CanCollide  = false
	sphere.Material    = Enum.Material.Neon
	sphere.Color       = color
	sphere.Transparency = 0.3
	sphere.Parent      = workspace

	local expandTween = TweenService:Create(
		sphere,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(6, 6, 6), Transparency = 1 }
	)
	expandTween:Play()
	expandTween.Completed:Connect(function()
		sphere:Destroy()
	end)
end

-- ═══════════════════════════════════════════════════════════
-- §AGX/X35: DEFENSE-LINE BREACH (client-side dissolve)
-- ═══════════════════════════════════════════════════════════
-- Ported from the old server DefenseAnimation styles. Local-only writes:
-- the server Destroys the mob after BreachDuration, which also ends the
-- tweens. "Explode" can't fling server-owned parts from the client, so it
-- breaks the joints locally and tweens each part outward instead.

function MobVisuals.PlayBreachVisual(mob)
	if not mob or not mob.Parent or breachPlayed[mob] then return end
	breachPlayed[mob] = true

	local style    = mob:GetAttribute("BreachStyle") or "Fade"
	local duration = mob:GetAttribute("BreachDuration") or 0.5

	local center
	if style == "Explode" then
		local root = mob:FindFirstChild("HumanoidRootPart")
		center = root and root.Position or mob:GetPivot().Position
		-- Local-only joint break so each part can be tweened on its own
		-- (the server used BreakJoints + velocities).
		for _, d in ipairs(mob:GetDescendants()) do
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				d:Destroy()
			end
		end
	end

	for _, part in ipairs(mob:GetDescendants()) do
		if part:IsA("BasePart") then
			local goal
			local info
			if style == "Dissolve" then
				info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				goal = { Transparency = 1, Color = Color3.fromRGB(255, 50, 50) }
			elseif style == "Shrink" then
				info = TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.In)
				goal = { Size = part.Size * 0.01, Transparency = 1 }
			elseif style == "Explode" then
				info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				local dir = part.Position - center
				if dir.Magnitude < 0.1 then
					dir = Vector3.new(math.random() - 0.5, 1, math.random() - 0.5)
				end
				local offset = dir.Unit * (30 * duration) + Vector3.new(0, 20 * duration, 0)
				goal = { Transparency = 1, CFrame = part.CFrame + offset }
			else -- "Fade" and unknown styles
				info = TweenInfo.new(duration, Enum.EasingStyle.Linear)
				goal = { Transparency = 1 }
			end
			TweenService:Create(part, info, goal):Play()
		end
	end
end

return MobVisuals