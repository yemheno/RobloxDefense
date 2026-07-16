-- StarterPlayerScripts/Modules/SkillVisuals

local SkillVisuals = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- References
local NetworkManager = nil

-- Lazily loaded optional modules
local AnimationSystem = nil
local SkillIndicator  = nil

-- Active effects
local activeEffects = {} -- [effectId] = { connection, parts, etc }

-- Debug mode
local DEBUG_VISUALS = false

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

local initialized = false

function SkillVisuals.Init()
	if initialized then return end
	initialized = true

	local Modules = script.Parent
	NetworkManager = require(Modules:WaitForChild("NetworkManager"))

	-- Lazy-load optional modules
	task.spawn(function()
		local as = Modules:FindFirstChild("AnimationSystem")
		if as then AnimationSystem = require(as) end
		local si = Modules:FindFirstChild("SkillIndicator")
		if si then SkillIndicator = require(si) end
	end)

	-- SkillManager loads ~40 modules into the server boot sequence, so its events
	-- may not be created until several seconds after the client connects.
	-- Subscribe via infinite WaitForChild inside task.spawn so a slow server boot
	-- can never silently break these connections (avoids the 3s NetworkManager timeout).
	local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")

	local function subscribe(name, handler)
		task.spawn(function()
			Events:WaitForChild(name).OnClientEvent:Connect(handler)
		end)
	end

	subscribe("SkillActivated",       function(data) SkillVisuals.OnSkillActivated(data)      end)
	subscribe("SkillVisual",          function(data) SkillVisuals.OnSkillVisual(data)         end)
	subscribe("BuffApplied",          function(data) SkillVisuals.OnBuffApplied(data)         end)
	subscribe("BuffRemoved",          function(data) SkillVisuals.OnBuffRemoved(data)         end)
	subscribe("SkillCastStarted",     function(data) SkillVisuals.OnSkillCastStarted(data)    end)
	subscribe("SkillCastCompleted",   function(data) SkillVisuals.OnSkillCastCompleted(data)  end)
	subscribe("SkillCastInterrupted", function(data) SkillVisuals.OnSkillCastInterrupted(data)end)

end

-- ═══════════════════════════════════════════════════════════
-- SKILL ACTIVATED (Local player only - plays animation)
-- ═══════════════════════════════════════════════════════════

function SkillVisuals.OnSkillActivated(data)
	-- Only play cast animation for the LOCAL player.
	-- When a cast-time skill fires FireAllClients("SkillActivated"), every
	-- client would otherwise play the animation on their own character.
	-- Roblox auto-replicates the caster's animation to all other clients,
	-- so we simply skip it for non-local casters.
	if data.playerId and data.playerId ~= player.UserId then return end

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
		-- Floor indicator circles for pull range and taunt range
		if SkillIndicator and data.origin then
			local col   = data.color or Color3.fromRGB(255, 200, 50)
			local descs = {}
			local seen  = {}
			if data.range then
				seen[data.range] = true
				table.insert(descs, { shape = "circle", radius = data.range, color = col })
			end
			if data.effects then
				for _, eff in ipairs(data.effects) do
					if eff.range and not seen[eff.range] then
						seen[eff.range] = true
						table.insert(descs, { shape = "circle", radius = eff.range, color = col })
					end
				end
			end
			if #descs > 0 then
				SkillIndicator.Flash(data.origin, nil, descs, 2)
			end
		end

	elseif visualType == "Dash" then
		SkillVisuals.CreateDashTrail(data)

	elseif visualType == "Buff" then
		SkillVisuals.CreateBuffAura(data)

	elseif visualType == "BattleBeast" then
		SkillVisuals.CreateBattleBeastVisual(data)

	elseif visualType == "Shape" then
		SkillVisuals.CreateShapeVisual(data)

	-- ── Arcanist placeholder visuals (flat indicator shapes until particle
	--    effects + animations are added) ─────────────────────────────────

	elseif visualType == "ArcaneBeam" then
		if SkillIndicator and data.origin and data.direction then
			SkillIndicator.Flash(data.origin, data.direction, {
				{ shape = "rect",
				  length = data.range or 40,
				  width  = data.width or 6,
				  color  = data.color or Color3.fromRGB(100, 200, 255) },
			}, 1.2)
		end

	elseif visualType == "FrostField" then
		if SkillIndicator and data.origin then
			SkillIndicator.Flash(data.origin, nil, {
				{ shape  = "circle",
				  radius = data.range or 14,
				  color  = data.color or Color3.fromRGB(100, 200, 255) },
			}, data.duration or 3)
		end

	elseif visualType == "ArcaneSurge" then
		if SkillIndicator and data.origin then
			SkillIndicator.Flash(data.origin,
				data.direction or Vector3.new(1, 0, 0),
				{
					{ shape = "cone",
					  range = data.range or 30,
					  angle = data.angle or 90,
					  color = data.color or Color3.fromRGB(150, 100, 255) },
				}, 1.2)
		end

	elseif visualType == "Meteorite" then
		if SkillIndicator and data.origin then
			SkillIndicator.Flash(data.origin, nil, {
				{ shape  = "circle",
				  radius = data.range or 20,
				  color  = data.color or Color3.fromRGB(255, 100, 30) },
			}, 2)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATION PLAYBACK
-- ═══════════════════════════════════════════════════════════

function SkillVisuals.PlayAnimation(animationId, duration)
	local character = player.Character
	if not character or not AnimationSystem then return end
	AnimationSystem.Play(character, animationId, {
		category = "skill",
		fadeIn   = 0.1,
		fadeOut  = 0.1,
		duration = duration,
	})
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
	-- §MEM/M3: re-applying the same buffId used to overwrite the
	-- activeEffects entry, orphaning the old aura + its Heartbeat
	-- connection forever. Tear down any existing entry first.
	if activeEffects[buffId] then
		SkillVisuals.OnBuffRemoved({ buffId = buffId })
	end

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
	-- §MEM/M3: on despawn this used to Destroy the aura but leave the
	-- Heartbeat connection firing forever (the sibling CreateBuffAura
	-- got this right). Route through OnBuffRemoved: disconnect + destroy
	-- + clear the registry entry in one place.
	local connection = RunService.Heartbeat:Connect(function()
		if not rootPart or not rootPart.Parent or not aura.Parent then
			SkillVisuals.OnBuffRemoved({ buffId = buffId })
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

function SkillVisuals.CreateBattleBeastVisual(data)
	-- Caster plays their animation (only on their own client — everyone else
	-- sees it via Roblox's automatic animation replication).
	if data.playerId == player.UserId and data.animation then
		SkillVisuals.PlayAnimation(data.animation, data.animationDuration or 1.2)
	end

	-- ── Burst ring visible to ALL players ────────────────────────────────────
	local casterPlayer = SkillVisuals.GetPlayerById(data.playerId)
	if not casterPlayer or not casterPlayer.Character then return end
	local rootPart = casterPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local color = data.color or Color3.fromRGB(50, 255, 50)
	-- Radius scales with self DR so a higher resource spend looks more dramatic
	local selfDR    = data.selfDR or 50
	local maxRadius = math.clamp(selfDR / 100 * 18 + 6, 8, 24)

	-- Brief inner flash
	local flash = Instance.new("Part")
	flash.Name       = "BattleBeastFlash"
	flash.Shape      = Enum.PartType.Ball
	flash.Size       = Vector3.new(4, 4, 4)
	flash.CFrame     = rootPart.CFrame
	flash.Anchored   = true
	flash.CanCollide = false
	flash.Material   = Enum.Material.Neon
	flash.Color      = color
	flash.Transparency = 0.2
	flash.Parent     = workspace

	TweenService:Create(
		flash,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 1, Size = Vector3.new(2, 2, 2) }
	):Play()
	task.delay(0.3, function()
		if flash.Parent then flash:Destroy() end
	end)

	-- Expanding ring
	local ring = Instance.new("Part")
	ring.Name           = "BattleBeastRing"
	ring.Shape          = Enum.PartType.Cylinder
	ring.Size           = Vector3.new(0.4, 1, 1)
	ring.CFrame         = rootPart.CFrame * CFrame.Angles(0, 0, math.pi / 2)
	ring.Anchored       = true
	ring.CanCollide     = false
	ring.Material       = Enum.Material.Neon
	ring.Color          = color
	ring.Transparency   = 0.2
	ring.Parent         = workspace

	TweenService:Create(
		ring,
		TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.4, maxRadius * 2, maxRadius * 2), Transparency = 1 }
	):Play()
	task.delay(0.6, function()
		if ring.Parent then ring:Destroy() end
	end)
end

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
-- SKILL CAST BAR
-- ═══════════════════════════════════════════════════════════

-- Active cast bars indexed by skillId
local activeCastBars = {}

function SkillVisuals.OnSkillCastStarted(data)
	local skillId  = data.skillId
	local castTime = data.castTime or 1
	local skillData = data.skillData or {}

	-- Remove any existing bar for this skill
	SkillVisuals.RemoveCastBar(skillId)

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end

	-- Create cast bar GUI
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CastBar_" .. tostring(skillId)
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 8

	local frame = Instance.new("Frame")
	frame.Name = "CastBarFrame"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.fromScale(0.5, 0.88)
	frame.Size = UDim2.fromScale(0.22, 0.035)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 160, 255)
	stroke.Thickness = 1.5
	stroke.Parent = frame

	-- Fill bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
	fill.BorderSizePixel = 0
	fill.Parent = frame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.3, 0)
	fillCorner.Parent = fill

	-- Label
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "Casting: " .. (skillData.name or skillId)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.ZIndex = 2
	label.Parent = frame

	screenGui.Parent = playerGui

	-- Animate fill over castTime
	local tween = TweenService:Create(fill, TweenInfo.new(castTime, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(1, 1),
	})
	tween:Play()

	activeCastBars[skillId] = {
		gui   = screenGui,
		tween = tween,
	}

	-- Show a ground-indicator preview during the cast.
	-- §LD-SK1 fix: the previous "MousePosition" branch used
	-- `player:GetMouse().Hit.p` which (a) is meaningless on touch and
	-- gamepad, and (b) didn't match the server's actual landing
	-- position — the server lands the AoE at a fixed distance ahead
	-- of the player via Base.GetForwardCastPosition. Mirror that
	-- calculation here so the preview circle and the damage area
	-- always overlap, regardless of input device.
	if SkillIndicator then
		local descs = SkillIndicator.DescribeSkill(skillData)
		if #descs > 0 then
			local key = "cast_" .. skillId
			local char     = player.Character
			local rootPart = char and char:FindFirstChild("HumanoidRootPart")
			if rootPart then
				if skillData.targetMode == "MousePosition"
					or skillData.targetMode == "Forward" then
					-- Forward-projected AoE preview (mirrors server logic).
					local castDistance = skillData.castDistance
						or ((skillData.maxRange or 30) * 0.6)
					SkillIndicator.ShowPreview(key, function()
						local rp = rootPart
						if not (rp and rp.Parent) then return nil end
						local lv = rp.CFrame.LookVector
						local flat = Vector3.new(lv.X, 0, lv.Z)
						if flat.Magnitude < 0.001 then
							flat = Vector3.new(0, 0, -1)
						else
							flat = flat.Unit
						end
						local pos = rp.Position + flat * castDistance
						return CFrame.new(pos)
					end, descs)
				else
					-- Player-centred preview (cone, point-blank circle, etc.)
					SkillIndicator.ShowPreview(key, function()
						return rootPart.Parent and rootPart.CFrame
					end, descs)
				end
			end
		end
	end
end

function SkillVisuals.OnSkillCastCompleted(data)
	SkillVisuals.RemoveCastBar(data.skillId)
	if SkillIndicator then
		SkillIndicator.HidePreview("cast_" .. (data.skillId or ""))
	end
end

function SkillVisuals.OnSkillCastInterrupted(data)
	local skillId = data.skillId
	local reason  = data.reason or "Interrupted"

	if SkillIndicator then
		SkillIndicator.HidePreview("cast_" .. (skillId or ""))
	end

	-- Flash the bar red before removing
	local entry = activeCastBars[skillId]
	if entry and entry.gui and entry.gui.Parent then
		local frame = entry.gui:FindFirstChild("CastBarFrame")
		if frame then
			local fill = frame:FindFirstChild("Fill")
			if fill then fill.BackgroundColor3 = Color3.fromRGB(255, 60, 60) end
			local lbl = frame:FindFirstChildOfClass("TextLabel")
			if lbl then lbl.Text = reason .. "!" end
		end
		-- Short delay so player sees the red flash, then remove
		task.delay(0.5, function()
			SkillVisuals.RemoveCastBar(skillId)
		end)
	else
		SkillVisuals.RemoveCastBar(skillId)
	end
end

function SkillVisuals.RemoveCastBar(skillId)
	local entry = activeCastBars[skillId]
	if not entry then return end
	if entry.tween then
		entry.tween:Cancel()
	end
	if entry.gui and entry.gui.Parent then
		entry.gui:Destroy()
	end
	activeCastBars[skillId] = nil
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