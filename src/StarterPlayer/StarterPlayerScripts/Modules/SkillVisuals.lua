-- StarterPlayerScripts/Modules/SkillVisuals

local SkillVisuals = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- References
local NetworkManager = nil

-- Animation cache
local animationTracks = {} -- [animId] = AnimationTrack

-- Active effects
local activeEffects = {} -- [effectId] = { connection, parts, etc }

-- Debug mode
local DEBUG_VISUALS = true

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function SkillVisuals.Init()
	local Modules = script.Parent
	NetworkManager = require(Modules:WaitForChild("NetworkManager"))

	-- Listen for skill activation (play animation)
	NetworkManager.OnServerEvent("SkillActivated", function(data)
		SkillVisuals.OnSkillActivated(data)
	end)

	-- Listen for visual-only events (effects for all players)
	NetworkManager.OnServerEvent("SkillVisual", function(data)
		SkillVisuals.OnSkillVisual(data)
	end)

	-- Listen for buff events
	NetworkManager.OnServerEvent("BuffApplied", function(data)
		SkillVisuals.OnBuffApplied(data)
	end)

	NetworkManager.OnServerEvent("BuffRemoved", function(data)
		SkillVisuals.OnBuffRemoved(data)
	end)

	print("[SkillVisuals] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- SKILL ACTIVATED (Local player only - plays animation)
-- ═══════════════════════════════════════════════════════════

function SkillVisuals.OnSkillActivated(data)
	local skillData = data.skillData
	if not skillData then return end

	-- Play animation
	if skillData.animation then
		SkillVisuals.PlayAnimation(skillData.animation, skillData.animationDuration)
	end

	-- Show local debug shape (optional)
	if DEBUG_VISUALS and skillData.shape then
		SkillVisuals.ShowLocalShape(skillData)
	end

	print("[SkillVisuals] Skill activated:", skillData.name or data.skillId)
end

-- ═══════════════════════════════════════════════════════════
-- SKILL VISUAL (All players see this)
-- ═══════════════════════════════════════════════════════════

function SkillVisuals.OnSkillVisual(data)
	local visualType = data.visualType

	if visualType == "Boomerang" then
		SkillVisuals.CreateBoomerangVisual(data)

	elseif visualType == "Taunt" then
		SkillVisuals.CreateTauntVisual(data)

	elseif visualType == "Dash" then
		SkillVisuals.CreateDashTrail(data)

	elseif visualType == "Buff" then
		SkillVisuals.CreateBuffAura(data)

	elseif visualType == "Shape" then
		SkillVisuals.CreateShapeVisual(data)
	end
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATION PLAYBACK
-- ═══════════════════════════════════════════════════════════

function SkillVisuals.PlayAnimation(animationId, duration)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Get or create track
	local track = SkillVisuals.GetTrack(animationId, animator)
	if not track then return end

	-- Play
	track.Priority = Enum.AnimationPriority.Action2
	track:Play(0.1)

	-- Stop after duration
	if duration then
		task.delay(duration, function()
			if track and track.IsPlaying then
				track:Stop(0.1)
			end
		end)
	end
end

function SkillVisuals.GetTrack(animationId, animator)
	if animationTracks[animationId] then
		return animationTracks[animationId]
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if success and track then
		animationTracks[animationId] = track
		return track
	end

	warn("[SkillVisuals] Failed to load animation:", animationId)
	return nil
end

-- ═══════════════════════════════════════════════════════════
-- VISUAL EFFECTS
-- ═══════════════════════════════════════════════════════════

function SkillVisuals.CreateBoomerangVisual(data)
	local startPos = data.startPos
	local direction = data.direction or Vector3.new(1, 0, 0)
	local range = data.range or 25
	local travelTime = data.travelTime or 0.4
	local returnDelay = data.returnDelay or 0.1
	local color = data.color or Color3.fromRGB(100, 150, 255)

	-- Create projectile
	local projectile = Instance.new("Part")
	projectile.Name = "BoomerangVisual"
	projectile.Size = Vector3.new(3, 0.5, 3)
	projectile.Shape = Enum.PartType.Cylinder
	projectile.Color = color
	projectile.Material = Enum.Material.Neon
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CFrame = CFrame.new(startPos) * CFrame.Angles(0, 0, math.rad(90))
	projectile.Parent = workspace

	local endPos = startPos + (direction * range)

	-- Spin effect
	local spinConnection
	spinConnection = RunService.Heartbeat:Connect(function()
		if projectile and projectile.Parent then
			projectile.CFrame = projectile.CFrame * CFrame.Angles(0, math.rad(30), 0)
		else
			spinConnection:Disconnect()
		end
	end)

	-- Outgoing tween
	local outTween = TweenService:Create(projectile, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
		CFrame = CFrame.new(endPos) * CFrame.Angles(0, 0, math.rad(90))
	})

	outTween:Play()
	outTween.Completed:Connect(function()
		task.wait(returnDelay)

		-- Get player's current position for return
		local targetPlayer = SkillVisuals.GetPlayerById(data.playerId)
		local returnPos = startPos
		if targetPlayer and targetPlayer.Character then
			local rootPart = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				returnPos = rootPart.Position
			end
		end

		local returnTween = TweenService:Create(projectile, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
			CFrame = CFrame.new(returnPos) * CFrame.Angles(0, 0, math.rad(90))
		})

		returnTween:Play()
		returnTween.Completed:Connect(function()
			spinConnection:Disconnect()
			projectile:Destroy()
		end)
	end)
end

function SkillVisuals.CreateTauntVisual(data)
	local origin = data.origin
	local range = data.range or 12
	local color = data.color or Color3.fromRGB(255, 200, 50)

	-- Expanding ring
	local ring = Instance.new("Part")
	ring.Name = "TauntRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.5, 2, 2)
	ring.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.3
	ring.Parent = workspace

	local maxSize = range * 2
	local tween = TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.5, maxSize, maxSize),
		Transparency = 1,
	})

	tween:Play()
	tween.Completed:Connect(function()
		ring:Destroy()
	end)
end

function SkillVisuals.CreateDashTrail(data)
	local startPos = data.startPos
	local endPos = data.endPos
	local duration = data.duration or 0.2
	local color = data.color or Color3.fromRGB(255, 100, 100)

	local trailCount = 5

	for i = 1, trailCount do
		task.delay(duration * (i / trailCount), function()
			-- Interpolate position
			local t = i / trailCount
			local pos = startPos:Lerp(endPos, t)

			local trail = Instance.new("Part")
			trail.Name = "DashTrail"
			trail.Size = Vector3.new(1, 2, 1)
			trail.Position = pos
			trail.Anchored = true
			trail.CanCollide = false
			trail.Material = Enum.Material.Neon
			trail.Color = color
			trail.Transparency = 0.5
			trail.Parent = workspace

			local tween = TweenService:Create(trail, TweenInfo.new(0.3), {
				Transparency = 1,
				Size = Vector3.new(0.1, 0.1, 0.1),
			})
			tween:Play()
			tween.Completed:Connect(function()
				trail:Destroy()
			end)
		end)
	end
end

-- ═══════════════════════════════════════════════════════════
-- BUFF VISUALS
-- ═══════════════════════════════════════════════════════════

function SkillVisuals.OnBuffApplied(data)
	local buffId = data.buffId
	local buffData = data.buffData

	-- Only show aura for damage reduction buffs
	if buffData.type == "DamageReduction" then
		SkillVisuals.CreateLocalBuffAura(buffId, buffData)
	end
end

function SkillVisuals.OnBuffRemoved(data)
	local buffId = data.buffId

	-- Remove aura effect
	if activeEffects[buffId] then
		local effect = activeEffects[buffId]
		if effect.connection then
			effect.connection:Disconnect()
		end
		if effect.part and effect.part.Parent then
			effect.part:Destroy()
		end
		activeEffects[buffId] = nil
	end
end

function SkillVisuals.CreateLocalBuffAura(buffId, buffData)
	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local color = Color3.fromRGB(50, 255, 50) -- Green for damage reduction
	local size = 8

	if buffData.amount >= 100 then
		color = Color3.fromRGB(255, 215, 0) -- Gold for immunity
		size = 10
	elseif buffData.amount >= 50 then
		color = Color3.fromRGB(100, 255, 100) -- Bright green
	end

	local aura = Instance.new("Part")
	aura.Name = "BuffAura_" .. buffId
	aura.Shape = Enum.PartType.Ball
	aura.Size = Vector3.new(size, size, size)
	aura.CFrame = rootPart.CFrame
	aura.Anchored = true
	aura.CanCollide = false
	aura.Material = Enum.Material.ForceField
	aura.Color = color
	aura.Transparency = 0.7
	aura.Parent = workspace

	-- Follow player (CLIENT-SIDE = no lag!)
	local connection = RunService.Heartbeat:Connect(function()
		if not aura or not aura.Parent then return end
		if not rootPart or not rootPart.Parent then
			aura:Destroy()
			return
		end
		aura.CFrame = rootPart.CFrame
	end)

	-- Store for cleanup
	activeEffects[buffId] = {
		part = aura,
		connection = connection,
	}

	-- Auto-remove after duration
	if buffData.duration then
		task.delay(buffData.duration, function()
			SkillVisuals.OnBuffRemoved({ buffId = buffId })
		end)
	end
end

function SkillVisuals.CreateBuffAura(data)
	-- For other players' buff visuals
	local targetPlayer = SkillVisuals.GetPlayerById(data.playerId)
	if not targetPlayer or targetPlayer == player then return end -- Skip self (handled locally)

	local character = targetPlayer.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local color = data.color or Color3.fromRGB(50, 255, 50)
	local duration = data.duration or 4

	local aura = Instance.new("Part")
	aura.Name = "BuffAura"
	aura.Shape = Enum.PartType.Ball
	aura.Size = Vector3.new(8, 8, 8)
	aura.CFrame = rootPart.CFrame
	aura.Anchored = true
	aura.CanCollide = false
	aura.Material = Enum.Material.ForceField
	aura.Color = color
	aura.Transparency = 0.7
	aura.Parent = workspace

	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not aura or not aura.Parent or not rootPart or not rootPart.Parent then
			if connection then connection:Disconnect() end
			if aura and aura.Parent then aura:Destroy() end
			return
		end
		aura.CFrame = rootPart.CFrame
	end)

	task.delay(duration, function()
		if connection then connection:Disconnect() end
		if aura and aura.Parent then aura:Destroy() end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG SHAPES
-- ═══════════════════════════════════════════════════════════

function SkillVisuals.ShowLocalShape(skillData)
	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local origin = rootPart.Position
	local direction = Vector3.new(1, 0, 0)
	local color = skillData.debugColor or Color3.fromRGB(255, 255, 0)
	local duration = 0.5

	if skillData.shape == "Circle" then
		SkillVisuals.DebugCircle(origin, skillData.shapeParams.range, color, duration)

	elseif skillData.shape == "Rectangle" then
		SkillVisuals.DebugRectangle(origin, direction, skillData.shapeParams.range, skillData.shapeParams.width, color, duration)

	elseif skillData.shape == "Cone" then
		SkillVisuals.DebugCone(origin, direction, skillData.shapeParams.range, skillData.shapeParams.angle, color, duration)
	end
end

function SkillVisuals.CreateShapeVisual(data)
	local origin = data.origin
	local shape = data.shape
	local color = data.color or Color3.fromRGB(255, 255, 0)
	local duration = data.duration or 0.5

	if shape == "Circle" then
		SkillVisuals.DebugCircle(origin, data.range, color, duration)
	elseif shape == "Rectangle" then
		SkillVisuals.DebugRectangle(origin, data.direction, data.range, data.width, color, duration)
	elseif shape == "Cone" then
		SkillVisuals.DebugCone(origin, data.direction, data.range, data.angle, color, duration)
	end
end

function SkillVisuals.DebugCircle(origin, radius, color, duration)
	local part = Instance.new("Part")
	part.Name = "DebugCircle"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.5, radius * 2, radius * 2)
	part.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.5
	part.Parent = workspace

	Debris:AddItem(part, duration)
end

function SkillVisuals.DebugRectangle(origin, direction, length, width, color, duration)
	local part = Instance.new("Part")
	part.Name = "DebugRectangle"
	-- Size: X = width, Y = height, Z = length (along direction)
	part.Size = Vector3.new(width, 1, length)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.5

	-- Center position is origin + half length in direction
	local centerPos = origin + (direction * length / 2)

	-- Orient so Z+ (front) faces the direction
	part.CFrame = CFrame.lookAt(centerPos, centerPos + direction)

	part.Parent = workspace
	Debris:AddItem(part, duration)
end

function SkillVisuals.DebugCone(origin, direction, range, angle, color, duration)
	-- Simplified cone visual
	local part = Instance.new("WedgePart")
	part.Name = "DebugCone"

	local halfAngleRad = math.rad(angle / 2)
	local coneWidth = range * math.tan(halfAngleRad) * 2

	part.Size = Vector3.new(coneWidth, 1, range)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.5

	local centerPos = origin + (direction * range / 2)
	part.CFrame = CFrame.lookAt(centerPos, centerPos + direction) * CFrame.Angles(0, math.rad(180), 0)

	part.Parent = workspace
	Debris:AddItem(part, duration)
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function SkillVisuals.GetPlayerById(userId)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == userId then
			return p
		end
	end
	return nil
end

return SkillVisuals