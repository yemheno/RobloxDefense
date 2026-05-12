-- StarterPlayerScripts/Modules/ClientProjectile
-- Client-side projectile: visual rendering, movement and hit detection.
-- The attacking player's client fires a local projectile, detects mob hits
-- locally, and reports verified hits to the server via PlayerHitReport.

local ClientProjectile = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local SharedGeometry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedGeometry"))

local HIT_BOX_SIZE = Vector3.new(4, 4, 4)
local SPAWN_OFFSET = 3

local projectileTemplate = nil
local activeProjectiles = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function ClientProjectile.Init()
	local folder = ReplicatedStorage:WaitForChild("Projectiles", 5)
	if folder then
		projectileTemplate = folder:FindFirstChild("BasicProjectile")
	end
	if not projectileTemplate then
		warn("[ClientProjectile] BasicProjectile template not found")
	end

	RunService.RenderStepped:Connect(function(dt)
		ClientProjectile.Update(dt)
	end)

end

-- ═══════════════════════════════════════════════════════════
-- FIRE (owned by local player — runs hit detection)
-- ═══════════════════════════════════════════════════════════

function ClientProjectile.Fire(origin, direction, config, attackId)
	if not projectileTemplate then return end

	local part = projectileTemplate:Clone()
	part.Anchored = true
	part.CanCollide = false
	part.Position = origin + direction * SPAWN_OFFSET
	part.Parent = workspace

	table.insert(activeProjectiles, {
		part = part,
		direction = direction,
		config = config,
		spawnTime = os.clock(),
		hitCount = 0,
		hitTargets = {},
		attackId = attackId,
	})
end

-- ═══════════════════════════════════════════════════════════
-- FIRE VISUAL-ONLY (other players' projectiles — no hit detection)
-- ═══════════════════════════════════════════════════════════

function ClientProjectile.FireVisual(origin, direction, config)
	if not projectileTemplate then return end

	local part = projectileTemplate:Clone()
	part.Anchored = true
	part.CanCollide = false
	part.Position = origin + direction * SPAWN_OFFSET
	part.Parent = workspace

	table.insert(activeProjectiles, {
		part = part,
		direction = direction,
		config = config,
		spawnTime = os.clock(),
		hitCount = 0,
		hitTargets = {},
		visualOnly = true,
	})
end

-- ═══════════════════════════════════════════════════════════
-- UPDATE LOOP (runs on RenderStepped)
-- ═══════════════════════════════════════════════════════════

function ClientProjectile.Update(dt)
	for i = #activeProjectiles, 1, -1 do
		local data = activeProjectiles[i]

		if ClientProjectile.ShouldRemove(data) then
			ClientProjectile.Destroy(data, i)
		else
			-- Move
			data.part.Position = data.part.Position + data.direction * data.config.speed * dt

			-- Hit detection (only for local player's own projectiles)
			if not data.visualOnly then
				local hit = ClientProjectile.CheckHit(data)
				if hit then
					local destroy = ClientProjectile.OnHit(data, hit)
					if destroy then
						ClientProjectile.Destroy(data, i)
					end
				end
			end
		end
	end
end

function ClientProjectile.ShouldRemove(data)
	if not data.part or not data.part.Parent then return true end
	return (os.clock() - data.spawnTime) > data.config.lifetime
end

-- ═══════════════════════════════════════════════════════════
-- HIT DETECTION (client-side spatial query)
-- ═══════════════════════════════════════════════════════════

function ClientProjectile.CheckHit(data)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { data.part }

	local parts = workspace:GetPartBoundsInBox(
		CFrame.new(data.part.Position),
		HIT_BOX_SIZE,
		params
	)

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:GetAttribute("IsMob") and model:FindFirstChild("Humanoid") then
			local hum = model:FindFirstChild("Humanoid")
			if hum.Health > 0 and not data.hitTargets[model] then
				return model
			end
		end
	end

	return nil
end

function ClientProjectile.OnHit(data, mob)
	local t = data.config.type

	if t == "Pierce" then
		return ClientProjectile.HandlePierceHit(data, mob)
	elseif t == "AoE" then
		return ClientProjectile.HandleAoEHit(data, mob)
	end

	return true
end

-- ═══════════════════════════════════════════════════════════
-- PIERCE — single-target passthrough
-- ═══════════════════════════════════════════════════════════

function ClientProjectile.HandlePierceHit(data, mob)
	local maxHits = data.config.maxHits or 1
	local reduction = data.config.damageReduction or 0
	local minFraction = data.config.minDamageFraction or 0.2
	local mult = math.max(minFraction, 1 - data.hitCount * reduction)

	NetworkManager.FireServer("PlayerHitReport", {
		target = mob,
		damageMultiplier = mult,
		attackId = data.attackId,
	})

	data.hitTargets[mob] = true
	data.hitCount = data.hitCount + 1
	return data.hitCount >= maxHits
end

-- ═══════════════════════════════════════════════════════════
-- AOE — explode on first impact, hit everything in radius
-- ═══════════════════════════════════════════════════════════

function ClientProjectile.HandleAoEHit(data, mob)
	local sp = data.config.shapeParams or { range = 8 }
	local radius = sp.range or 8
	local primaryMult = data.config.primaryMultiplier or 1.5
	local splashMult = data.config.splashMultiplier or 1.0
	local pos = data.part.Position

	local targets = ClientProjectile.GetMobsInRadius(pos, radius)
	for _, target in ipairs(targets) do
		NetworkManager.FireServer("PlayerHitReport", {
			target = target,
			damageMultiplier = (target == mob) and primaryMult or splashMult,
			attackId = data.attackId,
		})
	end

	return true
end

function ClientProjectile.GetMobsInRadius(position, radius)
	local mobs = {}

	local function scan(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute("IsMob") and child:FindFirstChild("Humanoid") then
				local hum = child:FindFirstChild("Humanoid")
				if hum.Health > 0 then
					local rp = child:FindFirstChild("HumanoidRootPart") or child.PrimaryPart
					if rp and SharedGeometry.IsInCircle(rp.Position, position, radius) then
						table.insert(mobs, child)
					end
				end
			end
		end
	end

	scan(workspace)
	local mobsFolder = workspace:FindFirstChild("Mobs")
	if mobsFolder then scan(mobsFolder) end

	return mobs
end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════

function ClientProjectile.Destroy(data, index)
	if data.part and data.part.Parent then
		data.part:Destroy()
	end
	table.remove(activeProjectiles, index)
end

return ClientProjectile
