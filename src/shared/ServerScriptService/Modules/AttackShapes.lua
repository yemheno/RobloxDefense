-- ServerScriptService/Modules/AttackShapes

local AttackShapes = {}

--[[
    ═══════════════════════════════════════════════════════════
    ATTACK SHAPES MODULE
    ═══════════════════════════════════════════════════════════
    
    Pure geometry calculations for hit detection.
    Returns list of models (mobs/players) within a shape.
    
    Used by:
    - AttackHandler (player attacks)
    - MobAI (mob attacks) [future]
    - SkillSystem (abilities) [future]
    - Hazards (traps, etc.) [future]
    
    ═══════════════════════════════════════════════════════════
    SHAPES:
    
    Cone      ▽   - Triangle in front (melee slash, breath attack)
    Circle    ●   - Full circle around point (explosion, spin attack)
    Ring      ◯   - Donut shape (shockwave, avoid center)
    Rectangle ▭   - Box in front (thrust, beam)
    
    ═══════════════════════════════════════════════════════════
]]

-- HELPER FUNCTIONS
-- Get position of a model (mob or player)
local function getModelPosition(model)
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if rootPart then
		return rootPart.Position
	end
	-- Fallback: try to get bounding box center (GetBoundingBox → CFrame, Vector3 size)
	local ok, cf = pcall(function() return model:GetBoundingBox() end)
	return ok and cf and cf.Position or nil
end

-- Get all potential targets in workspace
-- §T2/Z7: dead-but-not-yet-destroyed models are skipped up front —
-- downstream DamageMob no-ops on them anyway; this just saves the
-- geometry work in the shape loops (and dedupes the two scan blocks).
local function collectFrom(container, filterAttribute, targets)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			local humanoid = child:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health > 0 then
				if not filterAttribute or child:GetAttribute(filterAttribute) then
					table.insert(targets, child)
				end
			end
		end
	end
end

local function getPotentialTargets(filterAttribute)
	local targets = {}
	collectFrom(workspace, filterAttribute, targets)
	local mobsFolder = workspace:FindFirstChild("Mobs")
	if mobsFolder then
		collectFrom(mobsFolder, filterAttribute, targets)
	end
	return targets
end

-- ═══════════════════════════════════════════════════════════
-- CONE SHAPE
-- ═══════════════════════════════════════════════════════════
--[[
    Parameters:
    - origin: Vector3 (center point, usually attacker position)
    - direction: Vector3 (facing direction, usually attacker LookVector)
    - range: number (how far the cone extends)
    - angle: number (total cone width in degrees, e.g., 90 = 45° each side)
    - filterAttribute: string (optional, e.g., "IsMob" to only hit mobs)
    
    Returns: { Model, Model, ... }
]]

function AttackShapes.GetTargetsInCone(origin, direction, range, angle, filterAttribute)
	local targets = getPotentialTargets(filterAttribute)
	local hitTargets = {}

	-- Normalize direction (ignore Y for horizontal cone)
	local flatDirection = Vector3.new(direction.X, 0, direction.Z).Unit
	local halfAngle = angle / 2

	for _, target in ipairs(targets) do
		local targetPos = getModelPosition(target)
		if targetPos then
			-- Vector from origin to target (ignore Y)
			local toTarget = Vector3.new(targetPos.X - origin.X, 0, targetPos.Z - origin.Z)
			local distance = toTarget.Magnitude

			-- Check range
			if distance <= range and distance > 0 then
				-- Check angle
				local targetDirection = toTarget.Unit
				local dot = flatDirection:Dot(targetDirection)
				local angleBetween = math.deg(math.acos(math.clamp(dot, -1, 1)))

				if angleBetween <= halfAngle then
					table.insert(hitTargets, target)
				end
			end
		end
	end

	return hitTargets
end

-- ═══════════════════════════════════════════════════════════
-- CIRCLE SHAPE
-- ═══════════════════════════════════════════════════════════
--[[
    Parameters:
    - origin: Vector3 (center of circle)
    - radius: number (circle radius)
    - filterAttribute: string (optional)
    
    Returns: { Model, Model, ... }
]]

function AttackShapes.GetTargetsInCircle(origin, radius, filterAttribute)
	local targets = getPotentialTargets(filterAttribute)
	local hitTargets = {}

	for _, target in ipairs(targets) do
		local targetPos = getModelPosition(target)
		if targetPos then
			-- 2D distance (ignore Y)
			local distance = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(origin.X, 0, origin.Z)).Magnitude

			if distance <= radius then
				table.insert(hitTargets, target)
			end
		end
	end

	return hitTargets
end

-- ═══════════════════════════════════════════════════════════
-- RING SHAPE (Donut)
-- ═══════════════════════════════════════════════════════════
--[[
    Parameters:
    - origin: Vector3 (center of ring)
    - outerRadius: number (outer edge)
    - innerRadius: number (inner edge, no damage here)
    - filterAttribute: string (optional)
    
    Returns: { Model, Model, ... }
]]

function AttackShapes.GetTargetsInRing(origin, outerRadius, innerRadius, filterAttribute)
	local targets = getPotentialTargets(filterAttribute)
	local hitTargets = {}

	for _, target in ipairs(targets) do
		local targetPos = getModelPosition(target)
		if targetPos then
			-- 2D distance (ignore Y)
			local distance = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(origin.X, 0, origin.Z)).Magnitude

			-- Must be between inner and outer radius
			if distance <= outerRadius and distance >= innerRadius then
				table.insert(hitTargets, target)
			end
		end
	end

	return hitTargets
end

-- ═══════════════════════════════════════════════════════════
-- RECTANGLE SHAPE
-- ═══════════════════════════════════════════════════════════
--[[
    Parameters:
    - origin: Vector3 (starting point, usually attacker position)
    - direction: Vector3 (facing direction)
    - length: number (how far forward)
    - width: number (how wide, total width)
    - filterAttribute: string (optional)
    
    Returns: { Model, Model, ... }
    
    Rectangle extends FROM origin in the direction specified.
    Width is centered on the direction line.
    
         width
        ←─────→
        ┌─────┐ ↑
        │     │ │ length
        │     │ │
        └──●──┘ ↓
         origin
           ↑
        direction
]]

function AttackShapes.GetTargetsInRectangle(origin, direction, length, width, filterAttribute)
	local targets = getPotentialTargets(filterAttribute)
	local hitTargets = {}

	-- Normalize direction (ignore Y)
	local flatDirection = Vector3.new(direction.X, 0, direction.Z).Unit

	-- Get perpendicular direction for width
	local rightDirection = Vector3.new(-flatDirection.Z, 0, flatDirection.X)

	local halfWidth = width / 2

	for _, target in ipairs(targets) do
		local targetPos = getModelPosition(target)
		if targetPos then
			-- Vector from origin to target (ignore Y)
			local toTarget = Vector3.new(targetPos.X - origin.X, 0, targetPos.Z - origin.Z)

			-- Project onto forward direction (length check)
			local forwardDist = toTarget:Dot(flatDirection)

			-- Project onto right direction (width check)
			local sideDist = math.abs(toTarget:Dot(rightDirection))

			-- Check bounds
			if forwardDist >= 0 and forwardDist <= length and sideDist <= halfWidth then
				table.insert(hitTargets, target)
			end
		end
	end

	return hitTargets
end

-- ═══════════════════════════════════════════════════════════
-- GENERIC SHAPE CALLER
-- ═══════════════════════════════════════════════════════════
--[[
    Convenience function to call any shape by name.
    
    Parameters:
    - shapeName: "Cone", "Circle", "Ring", "Rectangle"
    - params: table with shape-specific parameters
    
    Params table:
    {
        origin = Vector3,
        direction = Vector3,      -- For Cone, Rectangle
        range = number,           -- Cone length, Rectangle length, Circle/Ring radius
        angle = number,           -- Cone only
        width = number,           -- Rectangle only
        innerRadius = number,     -- Ring only
        filterAttribute = string, -- Optional
    }
]]

function AttackShapes.GetTargetsInShape(shapeName, params)
	local origin = params.origin
	local direction = params.direction or Vector3.new(1, 0, 0)
	local range = params.range or 10
	local filterAttribute = params.filterAttribute

	if shapeName == "Cone" then
		local angle = params.angle or 90
		return AttackShapes.GetTargetsInCone(origin, direction, range, angle, filterAttribute)

	elseif shapeName == "Circle" then
		return AttackShapes.GetTargetsInCircle(origin, range, filterAttribute)

	elseif shapeName == "Ring" then
		local innerRadius = params.innerRadius or 0
		return AttackShapes.GetTargetsInRing(origin, range, innerRadius, filterAttribute)

	elseif shapeName == "Rectangle" then
		local width = params.width or 4
		return AttackShapes.GetTargetsInRectangle(origin, direction, range, width, filterAttribute)

	else
		warn("[AttackShapes] Unknown shape:", shapeName)
		return {}
	end
end

return AttackShapes