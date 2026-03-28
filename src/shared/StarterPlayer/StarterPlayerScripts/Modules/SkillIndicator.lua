-- StarterPlayerScripts/Modules/SkillIndicator
--[[
	Creates flat on-ground hit-area indicators for skill visuals and cast previews.

	All indicators are flat parts with HEIGHT = 0.5 studs, placed at foot/ground
	level relative to the provided world origin.

	Public API
	──────────
	SkillIndicator.Flash(origin, dir, descs, duration)
	    Show one or more indicator shapes briefly then destroy.
	    origin   : Vector3   — world position (e.g. caster's HRP position)
	    dir      : Vector3?  — forward direction (nil = not needed for circles)
	    descs    : array of shape descriptors (see below)
	    duration : number    — total seconds before destruction (default 1.5)

	SkillIndicator.ShowPreview(key, getCFrame, descs)
	    Show a persistent indicator that tracks a moving CFrame each Heartbeat.
	    key        : string             — unique ID for later removal
	    getCFrame  : () → CFrame|nil    — called every frame; nil → auto-hide
	    descs      : array of shape descriptors

	SkillIndicator.HidePreview(key)
	    Remove a tracked cast-preview indicator by key.

	SkillIndicator.DescribeSkill(skillData)
	    Convert a skill config table into a descriptor array for ShowPreview.

	Shape descriptor format
	───────────────────────
	Circle  : { shape = "circle", radius = n, color = Color3 }
	Rect    : { shape = "rect",   length = n, width  = n, color = Color3 }
	Cone    : { shape = "cone",   range  = n, angle  = n, color = Color3 }
	           angle is in degrees (full spread angle, e.g. 90)
]]

local SkillIndicator = {}

local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")

-- Visual constants
local HEIGHT     = 0.5
-- Offset from HumanoidRootPart centre down to foot/ground plane
local FOOT_DELTA = -3.0
local TRANS      = 0.50

-- Active tracked (cast-preview) entries  [key] = { parts, connection }
local previews = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function footPos(origin)
	return Vector3.new(origin.X, origin.Y + FOOT_DELTA + HEIGHT * 0.5, origin.Z)
end

local function flatDir(v)
	local d = Vector3.new(v.X, 0, v.Z)
	return if d.Magnitude > 0.01 then d.Unit else Vector3.new(1, 0, 0)
end

local function basePart(name, color)
	local p       = Instance.new("Part")
	p.Name        = name
	p.Anchored    = true
	p.CanCollide  = false
	p.CastShadow  = false
	p.Material    = Enum.Material.Neon
	p.Transparency = TRANS
	p.Color       = color
	return p
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Shape constructors
-- ─────────────────────────────────────────────────────────────────────────────

local function makeCircle(origin, radius, color)
	local p    = basePart("SkillIndicator", color)
	p.Shape    = Enum.PartType.Cylinder
	p.Size     = Vector3.new(HEIGHT, radius * 2, radius * 2)
	p.CFrame   = CFrame.new(footPos(origin)) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent   = workspace
	return p
end

local function makeRect(origin, dir, length, width, color)
	local d      = flatDir(dir)
	local fo     = footPos(origin)
	local center = fo + d * (length * 0.5)
	local p      = basePart("SkillIndicator", color)
	p.Size       = Vector3.new(width, HEIGHT, length)
	p.CFrame     = CFrame.lookAt(center, center + d)
	p.Parent     = workspace
	return p
end

local function makeCone(origin, dir, range, angleDeg, color)
	local d         = flatDir(dir)
	local fo        = footPos(origin)
	local halfAngle = math.rad(angleDeg * 0.5)
	local baseWidth = math.sin(halfAngle) * range * 2
	local center    = fo + d * (range * 0.5)
	local p         = Instance.new("WedgePart")
	p.Name          = "SkillIndicator"
	p.Anchored      = true
	p.CanCollide    = false
	p.CastShadow    = false
	p.Material      = Enum.Material.Neon
	p.Transparency  = TRANS
	p.Color         = color
	p.Size          = Vector3.new(baseWidth, HEIGHT, range)
	p.CFrame        = CFrame.lookAt(center, center + d)
	p.Parent        = workspace
	return p
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Build one part from a descriptor + current origin/direction
-- ─────────────────────────────────────────────────────────────────────────────

local function buildOne(desc, origin, dir)
	local color = desc.color or Color3.fromRGB(255, 200, 50)
	if desc.shape == "circle" then
		return makeCircle(origin, desc.radius or 10, color)
	elseif desc.shape == "rect" then
		return makeRect(origin, dir or Vector3.new(1, 0, 0), desc.length or 20, desc.width or 6, color)
	elseif desc.shape == "cone" then
		return makeCone(origin, dir or Vector3.new(1, 0, 0), desc.range or 15, desc.angle or 60, color)
	end
	return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Update a part position from its descriptor (used every Heartbeat by previews)
-- ─────────────────────────────────────────────────────────────────────────────

local function updateOne(p, desc, origin, dir)
	if not p or not p.Parent then return end
	local fo = footPos(origin)
	local fd = flatDir(dir or Vector3.new(1, 0, 0))

	if desc.shape == "circle" then
		p.CFrame = CFrame.new(fo) * CFrame.Angles(0, 0, math.rad(90))
	elseif desc.shape == "rect" then
		local center = fo + fd * ((desc.length or 20) * 0.5)
		p.CFrame = CFrame.lookAt(center, center + fd)
	elseif desc.shape == "cone" then
		local center = fo + fd * ((desc.range or 15) * 0.5)
		p.CFrame = CFrame.lookAt(center, center + fd)
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: Flash
-- Show indicators for `duration` seconds then fade and destroy.
-- descs: array of shape descriptors.
-- ─────────────────────────────────────────────────────────────────────────────

function SkillIndicator.Flash(origin, dir, descs, duration)
	duration = duration or 1.5
	local parts = {}
	local useDir = dir or Vector3.new(1, 0, 0)
	for _, desc in ipairs(descs) do
		local p = buildOne(desc, origin, useDir)
		if p then table.insert(parts, p) end
	end
	if #parts == 0 then return end

	local holdTime = duration * 0.65
	local fadeTime = duration - holdTime

	task.delay(holdTime, function()
		for _, p in ipairs(parts) do
			if p and p.Parent then
				TweenService:Create(p, TweenInfo.new(fadeTime), { Transparency = 1 }):Play()
			end
		end
	end)

	task.delay(duration, function()
		for _, p in ipairs(parts) do
			if p and p.Parent then p:Destroy() end
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: ShowPreview
-- Shows a persistent indicator that re-positions every Heartbeat.
-- getCFrame : () → CFrame|nil  — returning nil auto-hides the preview.
-- ─────────────────────────────────────────────────────────────────────────────

function SkillIndicator.ShowPreview(key, getCFrame, descs)
	SkillIndicator.HidePreview(key)
	if #descs == 0 then return end

	local cf0   = getCFrame()
	if not cf0 then return end
	local parts = {}
	for _, desc in ipairs(descs) do
		local p = buildOne(desc, cf0.Position, cf0.LookVector)
		if p then table.insert(parts, p) end
	end
	if #parts == 0 then return end

	local connection = RunService.Heartbeat:Connect(function()
		local cf = getCFrame()
		if not cf then
			SkillIndicator.HidePreview(key)
			return
		end
		for i, p in ipairs(parts) do
			updateOne(p, descs[i], cf.Position, cf.LookVector)
		end
	end)

	previews[key] = { parts = parts, connection = connection }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: HidePreview
-- ─────────────────────────────────────────────────────────────────────────────

function SkillIndicator.HidePreview(key)
	local entry = previews[key]
	if not entry then return end
	if entry.connection then entry.connection:Disconnect() end
	for _, p in ipairs(entry.parts) do
		if p and p.Parent then p:Destroy() end
	end
	previews[key] = nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: DescribeSkill
-- Extract indicator descriptors from a skill config table.
-- Reads skill.shape + skill.shapeParams (primary shape) and
-- skill.effects (for Pull/Taunt-style radius-based effects).
-- ─────────────────────────────────────────────────────────────────────────────

function SkillIndicator.DescribeSkill(skillData)
	local descs   = {}
	local col     = skillData.debugColor or Color3.fromRGB(255, 200, 50)
	local seen    = {}   -- deduplicate by radius for circle-only case

	-- Primary shape
	if skillData.shape and skillData.shapeParams then
		local sp = skillData.shapeParams
		local s  = string.lower(skillData.shape)
		if s == "circle" then
			local r = sp.range or 10
			table.insert(descs, { shape = "circle", radius = r, color = col })
			seen[r] = true
		elseif s == "rectangle" or s == "rect" then
			table.insert(descs, { shape = "rect", length = sp.range or 20, width = sp.width or 6, color = col })
		elseif s == "cone" then
			table.insert(descs, { shape = "cone", range = sp.range or 15, angle = sp.angle or 60, color = col })
		end
	end

	-- Additional circles from effects that are genuinely separate AoEs
	-- (Pull and Taunt extend beyond the primary shape; movement effects like
	-- Knockback/Slow/Stun are applied WITHIN the primary shape and should not
	-- generate a redundant circle indicator).
	local AoE_EFFECT_TYPES = { Pull = true, Taunt = true, Heal = true, Shield = true }
	if skillData.effects then
		for _, eff in ipairs(skillData.effects) do
			if eff.range and eff.range > 0 and AoE_EFFECT_TYPES[eff.type] and not seen[eff.range] then
				seen[eff.range] = true
				table.insert(descs, { shape = "circle", radius = eff.range, color = col })
			end
		end
	end

	return descs
end

return SkillIndicator
