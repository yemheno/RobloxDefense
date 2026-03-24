-- ReplicatedStorage/Shared/SharedGeometry.lua
-- Pure point-in-shape math shared by client and server.
-- All checks are 2-D (XZ plane); Y is ignored.

local SharedGeometry = {}

function SharedGeometry.FlatDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- ═══════════════════════════════════════════════════════════
-- POINT-IN-SHAPE TESTS
-- ═══════════════════════════════════════════════════════════

function SharedGeometry.IsInCircle(pos: Vector3, origin: Vector3, range: number): boolean
	return SharedGeometry.FlatDistance(pos, origin) <= range
end

function SharedGeometry.IsInCone(pos: Vector3, origin: Vector3, direction: Vector3, range: number, angle: number): boolean
	local dx = pos.X - origin.X
	local dz = pos.Z - origin.Z
	local dist = math.sqrt(dx * dx + dz * dz)

	if dist > range then return false end
	if dist < 0.001 then return true end

	local toTarget = Vector3.new(dx, 0, dz).Unit
	local flatDir  = Vector3.new(direction.X, 0, direction.Z).Unit
	local dot = math.clamp(flatDir:Dot(toTarget), -1, 1)
	return math.deg(math.acos(dot)) <= angle / 2
end

function SharedGeometry.IsInRectangle(pos: Vector3, origin: Vector3, direction: Vector3, length: number, width: number): boolean
	local dx = pos.X - origin.X
	local dz = pos.Z - origin.Z
	local toTarget = Vector3.new(dx, 0, dz)

	local flatDir = Vector3.new(direction.X, 0, direction.Z).Unit
	local right   = Vector3.new(-flatDir.Z, 0, flatDir.X)

	local forwardDist = toTarget:Dot(flatDir)
	local sideDist    = math.abs(toTarget:Dot(right))

	return forwardDist >= 0 and forwardDist <= length and sideDist <= width / 2
end

function SharedGeometry.IsInRing(pos: Vector3, origin: Vector3, outerRadius: number, innerRadius: number): boolean
	local dist = SharedGeometry.FlatDistance(pos, origin)
	return dist <= outerRadius and dist >= innerRadius
end

-- ═══════════════════════════════════════════════════════════
-- GENERIC DISPATCHER
-- ═══════════════════════════════════════════════════════════

function SharedGeometry.IsInShape(pos: Vector3, origin: Vector3, shapeName: string, params)
	local range     = params.range or 10
	local direction = params.direction or Vector3.new(1, 0, 0)

	if shapeName == "Circle" then
		return SharedGeometry.IsInCircle(pos, origin, range)

	elseif shapeName == "Cone" then
		return SharedGeometry.IsInCone(pos, origin, direction, range, params.angle or 90)

	elseif shapeName == "Rectangle" then
		return SharedGeometry.IsInRectangle(pos, origin, direction, range, params.width or 5)

	elseif shapeName == "Ring" then
		return SharedGeometry.IsInRing(pos, origin, range, params.innerRadius or 0)
	end

	-- Default: circle fallback
	return SharedGeometry.IsInCircle(pos, origin, range)
end

return SharedGeometry
