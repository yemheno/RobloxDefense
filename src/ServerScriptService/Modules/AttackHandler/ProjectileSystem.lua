-- ServerScriptService/Modules/AttackHandler/ProjectileSystem

local ProjectileSystem = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = script.Parent.Parent
local ClassManager = require(Modules:WaitForChild("ClassManager"))
local AttackShapes = require(Modules:WaitForChild("AttackShapes"))

-- Set by parent AttackHandler
ProjectileSystem.DamageHandler = nil
ProjectileSystem.GetAttackDirection = nil

-- Settings
local HIT_BOX_SIZE = Vector3.new(4, 4, 4)
local SPAWN_OFFSET_DISTANCE = 3

-- State
local projectileTemplate = nil
local activeProjectiles = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function ProjectileSystem.Init()
	local projectilesFolder = ReplicatedStorage:WaitForChild("Projectiles")
	projectileTemplate = projectilesFolder:WaitForChild("BasicProjectile")

	print("[ProjectileSystem] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- FIRE PROJECTILE
-- ═══════════════════════════════════════════════════════════

function ProjectileSystem.Fire(player, rootPart)
	if not projectileTemplate then
		warn("[ProjectileSystem] No projectile template!")
		return
	end

	-- Get projectile config from class
	local config = ClassManager.GetProjectileConfig(player)

	-- Get direction
	local direction = Vector3.new(1, 0, 0)
	if ProjectileSystem.GetAttackDirection then
		direction = ProjectileSystem.GetAttackDirection(rootPart)
	end

	-- Spawn position
	local spawnOffset = direction * SPAWN_OFFSET_DISTANCE

	-- Create projectile
	local projectile = projectileTemplate:Clone()
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.Position = rootPart.Position + spawnOffset
	projectile.Parent = workspace

	-- Track projectile
	table.insert(activeProjectiles, {
		part = projectile,
		spawnTime = tick(),
		owner = player,
		direction = direction,
		config = config,
		-- Pierce tracking
		hitCount = 0,
		hitTargets = {},
	})
end

-- ═══════════════════════════════════════════════════════════
-- UPDATE LOOP
-- ═══════════════════════════════════════════════════════════

function ProjectileSystem.Update(dt)
	for i = #activeProjectiles, 1, -1 do
		local data = activeProjectiles[i]
		local projectile = data.part

		if ProjectileSystem.ShouldRemove(data) then
			ProjectileSystem.DestroyProjectile(data, i)
		else
			ProjectileSystem.MoveProjectile(data, dt)

			local hit = ProjectileSystem.CheckHit(data)
			if hit then
				local shouldDestroy = ProjectileSystem.OnHit(data, hit)
				if shouldDestroy then
					ProjectileSystem.DestroyProjectile(data, i)
				end
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- PROJECTILE LOGIC
-- ═══════════════════════════════════════════════════════════

function ProjectileSystem.ShouldRemove(data)
	local projectile = data.part

	if not projectile or not projectile.Parent then
		return true
	end

	if (tick() - data.spawnTime) > data.config.lifetime then
		return true
	end

	return false
end

function ProjectileSystem.MoveProjectile(data, dt)
	local projectile = data.part
	local movement = data.direction * data.config.speed * dt
	projectile.Position = projectile.Position + movement
end

function ProjectileSystem.CheckHit(data)
	local projectile = data.part

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {projectile}

	local partsInBox = workspace:GetPartBoundsInBox(
		CFrame.new(projectile.Position),
		HIT_BOX_SIZE,
		overlapParams
	)

	for _, part in ipairs(partsInBox) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChild("Humanoid") and model:GetAttribute("IsMob") then
			-- Skip already hit targets (for Pierce)
			if not data.hitTargets[model] then
				return model
			end
		end
	end

	return nil
end

-- ═══════════════════════════════════════════════════════════
-- HIT HANDLING
-- ═══════════════════════════════════════════════════════════

function ProjectileSystem.OnHit(data, mob)
	local projectileType = data.config.type

	if projectileType == "Pierce" then
		return ProjectileSystem.HandlePierceHit(data, mob)
	elseif projectileType == "AoE" then
		return ProjectileSystem.HandleAoEHit(data, mob)
	else
		warn("[ProjectileSystem] Unknown projectile type:", projectileType)
		return true
	end
end

-- ═══════════════════════════════════════════════════════════
-- PIERCE: Goes through targets
-- ═══════════════════════════════════════════════════════════

function ProjectileSystem.HandlePierceHit(data, mob)
	local config = data.config
	local maxHits = config.maxHits or 1
	local damageReduction = config.damageReduction or 0

	-- Calculate damage multiplier based on hit count
	local multiplier = 1 - (data.hitCount * damageReduction)
	multiplier = math.max(0.2, multiplier)  -- Minimum 20% damage

	-- Apply damage
	if ProjectileSystem.DamageHandler then
		ProjectileSystem.DamageHandler.DamageMob(mob, data.owner, {
			damageMultiplier = multiplier,
		})
	end

	-- Track hit
	data.hitTargets[mob] = true
	data.hitCount = data.hitCount + 1

	-- Destroy if max hits reached
	return data.hitCount >= maxHits
end

-- ═══════════════════════════════════════════════════════════
-- AOE: Explodes on impact using AttackShapes
-- ═══════════════════════════════════════════════════════════

function ProjectileSystem.HandleAoEHit(data, mob)
	local config = data.config
	local shape = config.shape or "Circle"
	local shapeParams = config.shapeParams or { range = 8 }
	local primaryMultiplier = config.primaryMultiplier or 1.5

	-- Get impact position
	local impactPos = data.part.Position

	-- Build params for AttackShapes
	local params = {
		origin = impactPos,
		direction = data.direction,
		filterAttribute = "IsMob",
		range = shapeParams.range,
		angle = shapeParams.angle,
		width = shapeParams.width,
		innerRadius = shapeParams.innerRadius,
	}

	-- Get all targets in shape
	local targets = AttackShapes.GetTargetsInShape(shape, params)

	-- Damage all targets
	for _, target in ipairs(targets) do
		if ProjectileSystem.DamageHandler then
			-- Primary target (direct hit) gets multiplier, others get base damage
			local multiplier = (target == mob) and primaryMultiplier or 1.0
			ProjectileSystem.DamageHandler.DamageMob(target, data.owner, {
				damageMultiplier = multiplier,
			})
		end
	end

	-- Always destroy after AoE
	return true
end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════

function ProjectileSystem.DestroyProjectile(data, index)
	if data.part and data.part.Parent then
		data.part:Destroy()
	end
	table.remove(activeProjectiles, index)
end

function ProjectileSystem.RemovePlayer(player)
	for i = #activeProjectiles, 1, -1 do
		if activeProjectiles[i].owner == player then
			ProjectileSystem.DestroyProjectile(activeProjectiles[i], i)
		end
	end
end

function ProjectileSystem.GetActiveCount()
	return #activeProjectiles
end

return ProjectileSystem