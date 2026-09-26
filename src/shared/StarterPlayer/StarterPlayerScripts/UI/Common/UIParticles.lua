-- UI/Common/UIParticles.lua
--[[
    UIParticles  (§BEAUTY/P1 — 2D particles for ScreenGui)
    ======================================================
    Roblox ParticleEmitters are 3D-world objects (and ViewportFrames don't
    render them), so UI particles are emulated with pooled ImageLabels
    stepped once per Heartbeat — one shared stepper for ALL emitters.

    Sprites come from Theme.Images (pGlow / pSpark / pBolt / pStreak /
    pEmber — WHITE on transparent, tinted via ImageColor3). Until asset
    ids are pasted, particles fall back to rounded Frames so effects stay
    visible in tests.

    Imperative API (from React: create in useEffect via a ref, Destroy in
    the cleanup — the reconciler ignores children it didn't create):

        local emitter = UIParticles.new(containerGuiObject, {
            sprite    = "pSpark",              -- Theme.Images key
            color     = Color3.fromRGB(90, 190, 255),
            rate      = 6,                     -- particles/sec (0 = burst-only)
            lifetime  = {0.4, 0.9},            -- s {min, max}
            speed     = {30, 80},              -- px/s {min, max}
            direction = -90,                   -- deg (0 = +X, -90 = up)
            spread    = 40,                    -- ± deg
            size      = {6, 14},               -- px {min, max}
            endScale  = 0.2,                   -- size multiplier at death
            gravity   = 0,                     -- px/s² (positive = down)
            rotation  = {-90, 90},             -- deg/s {min, max}
            spawn     = "full",                -- "full"|"center"|"top"|"right"
                                               -- or function(sizePx) -> Vector2
            zIndex    = 50,
            uiScale   = 1,                     -- §AGX/UI-FIX: shell#4: UIScale
                                               -- already applied above the
                                               -- container (UIScaleRoot
                                               -- useUIScale().applied)
        })
        emitter:Emit(12)        -- burst
        emitter:SetRate(10)
        emitter:SetEnabled(false)
        emitter:SetUIScale(applied)   -- §AGX/UI-FIX: shell#4
        emitter:Destroy()
]]

local RunService = game:GetService("RunService")
local Theme = require(script.Parent:WaitForChild("Theme"))

local UIParticles = {}
UIParticles.__index = UIParticles

local emitters = {}          -- set of live emitters
local stepperConn = nil

local function rand(range)
	return range[1] + math.random() * (range[2] - range[1])
end

--============================================
-- SPAWN REGIONS
--============================================
local SPAWN = {
	full   = function(s) return Vector2.new(math.random() * s.X, math.random() * s.Y) end,
	center = function(s) return Vector2.new(s.X / 2, s.Y / 2) end,
	top    = function(s) return Vector2.new(math.random() * s.X, 0) end,
	right  = function(s) return Vector2.new(s.X - 1, math.random() * s.Y) end,
}

--============================================
-- PARTICLE GUI (pooled)
--============================================
local function makeGui(self)
	local gui
	if self.spriteId then
		gui = Instance.new("ImageLabel")
		gui.Image = self.spriteId
		gui.ImageColor3 = self.config.color
		gui.BackgroundTransparency = 1
	else
		-- Placeholder fallback until Theme.Images ids are pasted.
		gui = Instance.new("Frame")
		gui.BackgroundColor3 = self.config.color
		gui.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = gui
	end
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.ZIndex = self.config.zIndex
	gui.Name = "UIParticle"
	return gui
end

local function setAlpha(gui, alpha) -- alpha = 1 opaque, 0 gone
	if gui:IsA("ImageLabel") then
		gui.ImageTransparency = 1 - alpha
	else
		gui.BackgroundTransparency = 1 - alpha
	end
end

--============================================
-- SHARED STEPPER
--============================================
local function step(dt)
	for emitter in pairs(emitters) do
		if not emitter.container or not emitter.container.Parent then
			emitter:Destroy()
			continue
		end

		-- continuous emission
		if emitter.enabled and emitter.rate > 0 then
			emitter.accum += emitter.rate * dt
			while emitter.accum >= 1 do
				emitter.accum -= 1
				emitter:_spawnOne()
			end
		end

		-- integrate live particles
		local list = emitter.active
		for i = #list, 1, -1 do
			local p = list[i]
			p.life -= dt
			if p.life <= 0 then
				p.gui.Visible = false
				table.remove(list, i)
				table.insert(emitter.pool, p.gui)
			else
				p.vy += emitter.config.gravity * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
				local frac = p.life / p.maxLife           -- 1 → 0
				local size = p.size0 * (emitter.config.endScale
					+ (1 - emitter.config.endScale) * frac)
				p.rot += p.rotV * dt
				p.gui.Position = UDim2.fromOffset(p.x, p.y)
				p.gui.Size = UDim2.fromOffset(size, size)
				p.gui.Rotation = p.rot
				-- quick fade-in (first 10%), linear fade-out after
				local alpha = math.min(1, (1 - frac) * 10) * frac
				setAlpha(p.gui, alpha)
			end
		end
	end

	if next(emitters) == nil and stepperConn then
		stepperConn:Disconnect()
		stepperConn = nil
	end
end

local function ensureStepper()
	if not stepperConn then
		stepperConn = RunService.Heartbeat:Connect(step)
	end
end

--============================================
-- EMITTER
--============================================
function UIParticles.new(container, config)
	assert(container and container:IsA("GuiObject"),
		"[UIParticles] container must be a GuiObject")

	local self = setmetatable({}, UIParticles)
	self.container = container
	self.config = {
		color     = config.color or Color3.fromRGB(255, 255, 255),
		lifetime  = config.lifetime or {0.4, 0.9},
		speed     = config.speed or {30, 80},
		direction = config.direction or -90,
		spread    = config.spread or 40,
		size      = config.size or {6, 14},
		endScale  = config.endScale or 0.2,
		gravity   = config.gravity or 0,
		rotation  = config.rotation or {0, 0},
		zIndex    = config.zIndex or 50,
	}
	local img = Theme.GetImage(config.sprite or "pGlow")
	self.spriteId = img and img.id or nil
	if typeof(config.spawn) == "function" then
		self.spawnFn = config.spawn
	else
		self.spawnFn = SPAWN[config.spawn] or SPAWN.full
	end
	self.rate = config.rate or 0
	-- §AGX/UI-FIX: shell#4: particles are written as Offset inside the
	-- container, which a UIScale above it multiplies again; the measured
	-- AbsoluteSize (screen px) is divided by this before it is used.
	self.uiScale = (type(config.uiScale) == "number" and config.uiScale > 0) and config.uiScale or 1
	self.enabled = true
	self.accum = 0
	self.active = {}
	self.pool = {}

	emitters[self] = true
	ensureStepper()
	return self
end

function UIParticles:_spawnOne()
	-- §AGX/UI-FIX: shell#4: screen px -> the container's local (design) px.
	local sizePx = self.container.AbsoluteSize / self.uiScale
	if sizePx.X < 1 or sizePx.Y < 1 then return end

	local gui = table.remove(self.pool) or makeGui(self)
	gui.Visible = true
	gui.Parent = self.container

	local pos = self.spawnFn(sizePx)
	local angle = math.rad(self.config.direction
		+ (math.random() - 0.5) * 2 * self.config.spread)
	local spd = rand(self.config.speed)
	local life = rand(self.config.lifetime)

	table.insert(self.active, {
		gui = gui,
		x = pos.X, y = pos.Y,
		vx = math.cos(angle) * spd,
		vy = math.sin(angle) * spd,
		life = life, maxLife = life,
		size0 = rand(self.config.size),
		rot = math.random() * 360,
		rotV = rand(self.config.rotation),
	})
end

function UIParticles:Emit(n)
	for _ = 1, n do
		self:_spawnOne()
	end
end

function UIParticles:SetRate(rate)
	self.rate = rate
end

function UIParticles:SetEnabled(enabled)
	self.enabled = enabled
end

--- §AGX/UI-FIX: shell#4: update the UIScale applied above the container.
function UIParticles:SetUIScale(applied)
	if type(applied) == "number" and applied > 0 then self.uiScale = applied end
end

function UIParticles:Destroy()
	emitters[self] = nil
	for _, p in ipairs(self.active) do
		p.gui:Destroy()
	end
	for _, gui in ipairs(self.pool) do
		gui:Destroy()
	end
	self.active, self.pool = {}, {}
	self.container = nil
end

return UIParticles
