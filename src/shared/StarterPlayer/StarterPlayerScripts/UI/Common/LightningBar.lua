-- UI/Common/LightningBar.lua
--[[
    LightningBar  (§BEAUTY/P2 — animated vitals bar with lightning crackle)
    =======================================================================
    react-lua port of Pablo's WebGL Lightning exploration. Roblox has no
    shaders, so the effect is composed from primitives:

      • fill        Frame + UIGradient (color stays code-side, per brief)
      • bolts       procedural jagged polyline of thin rotated Frames,
                    regenerated at BOLT_HZ with random noise (the
                    "fbm crackle"), drawn twice: glow pass + core pass
      • sparks      UIParticles emitter at the fill's leading edge
      • chrome      Theme.Images.barFrame 9-slice + barShine overlay when
                    ids are pasted; graceful dark-frame fallback until then

    The bolt/spark layers are imperative (driven from useEffect via refs)
    so the 8–12 Hz crackle never touches React re-renders.

    Usage:
        React.createElement(LightningBar, {
            value       = 0.62,                          -- 0..1 (required)
            color       = Color3.fromRGB(90, 190, 255),  -- mana blue default
            size        = UDim2.new(0.3, 0, 0, 26),
            position    = UDim2.fromScale(0.5, 0.9),
            anchorPoint = Vector2.new(0.5, 0.5),
            intensity   = 1,      -- 0 disables bolts, ~2 = frantic
            speed       = 1,      -- crackle regen multiplier
            sparks      = true,   -- edge sparks on/off
            zIndex      = 20,
        })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent:WaitForChild("Theme"))
local UIParticles = require(script.Parent:WaitForChild("UIParticles"))
-- §AGX/UI-FIX: shell#4: the HUD mounts this bar inside UIScaleRoot.Local,
-- so AbsoluteSize (screen px) must be divided by the applied scale before
-- it is written back as Offset (bolts, spark spawn points).
local UIScaleRoot = require(script.Parent:WaitForChild("UIScaleRoot"))

local BASE_BOLT_HZ = 8      -- regenerations/sec at speed = 1
local SEGMENTS     = 10     -- polyline steps across the fill
local PAD_PX       = 4      -- inner padding inside the frame chrome
local TRACK_COLOR  = Color3.fromRGB(10, 10, 18)

--============================================
-- Imperative bolt layer
--============================================
local function buildSegmentFrames(layer, count, zIndex)
	local frames = {}
	for i = 1, count do
		local core = Instance.new("Frame")
		core.Name = "BoltCore" .. i
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.BorderSizePixel = 0
		core.ZIndex = zIndex + 2
		core.Parent = layer

		local glow = Instance.new("Frame")
		glow.Name = "BoltGlow" .. i
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.BorderSizePixel = 0
		glow.ZIndex = zIndex + 1
		glow.Parent = layer

		frames[i] = { core = core, glow = glow }
	end
	return frames
end

local function regenBolt(layer, frames, color, intensity, applied)
	-- §AGX/UI-FIX: shell#4: screen px -> local (design) px.
	local size = layer.AbsoluteSize / math.max(applied or 1, 0.01)
	local w, h = size.X, size.Y
	if w < 20 or h < 4 then
		for _, f in ipairs(frames) do
			f.core.Visible = false
			f.glow.Visible = false
		end
		return
	end

	-- jagged polyline, endpoints pinned to the vertical center
	local pts = {}
	for i = 0, SEGMENTS do
		local x = (i / SEGMENTS) * w
		local y
		if i == 0 or i == SEGMENTS then
			y = h / 2
		else
			y = h / 2 + (math.random() - 0.5) * h * 0.75
		end
		pts[i + 1] = Vector2.new(x, y)
	end

	-- whole-bolt flicker (the hash11(iTime) of the shader)
	local flicker = 0.55 + math.random() * 0.45   -- 0.55..1
	local coreAlpha = math.clamp(flicker * intensity, 0, 1)

	for i = 1, SEGMENTS do
		local a, b = pts[i], pts[i + 1]
		local d = b - a
		local len = d.Magnitude
		local mid = (a + b) / 2
		local rot = math.deg(math.atan2(d.Y, d.X))
		local f = frames[i]

		f.core.Visible = true
		f.core.Position = UDim2.fromOffset(mid.X, mid.Y)
		f.core.Size = UDim2.fromOffset(len + 1, 2)
		f.core.Rotation = rot
		f.core.BackgroundColor3 = Color3.new(1, 1, 1):Lerp(color, 0.25)
		f.core.BackgroundTransparency = 1 - coreAlpha

		f.glow.Visible = true
		f.glow.Position = UDim2.fromOffset(mid.X, mid.Y)
		f.glow.Size = UDim2.fromOffset(len + 3, 6)
		f.glow.Rotation = rot
		f.glow.BackgroundColor3 = color
		f.glow.BackgroundTransparency = 1 - coreAlpha * 0.35
	end
end

--============================================
-- Component
--============================================
local function LightningBar(props)
	local value     = math.clamp(props.value or 0, 0, 1)
	local color     = props.color or Color3.fromRGB(90, 190, 255)
	local intensity = props.intensity ~= nil and props.intensity or 1
	local speed     = props.speed or 1
	local sparks    = props.sparks ~= false
	local zBase     = props.zIndex or 20

	local fillRef = React.useRef(nil)
	local boltLayerRef = React.useRef(nil)

	-- §AGX/UI-FIX: shell#4: UIScale applied above this bar (1 when mounted
	-- in an unscaled tree). A ref, so the crackle loop reads the latest.
	local applied = UIScaleRoot.useUIScale().applied
	local appliedRef = React.useRef(applied)
	appliedRef.current = applied
	local emitterRef = React.useRef(nil)

	-- Bolt crackle loop (imperative, off the React render path)
	React.useEffect(function()
		local layer = boltLayerRef.current
		if not layer or intensity <= 0 then return end

		local frames = buildSegmentFrames(layer, SEGMENTS, zBase + 2)
		local accum, interval = 0, 1 / (BASE_BOLT_HZ * speed)
		local conn = RunService.Heartbeat:Connect(function(dt)
			accum += dt
			if accum >= interval then
				accum = 0
				regenBolt(layer, frames, color, intensity, appliedRef.current)
			end
		end)

		return function()
			conn:Disconnect()
			for _, f in ipairs(frames) do
				f.core:Destroy()
				f.glow:Destroy()
			end
		end
	end, { intensity, speed, color, zBase })

	-- Edge sparks (UIParticles on the fill's leading edge)
	React.useEffect(function()
		local fill = fillRef.current
		if not fill or not sparks or intensity <= 0 then return end

		local emitter = UIParticles.new(fill, {
			sprite    = "pSpark",
			color     = color,
			rate      = 4 * intensity,
			lifetime  = { 0.3, 0.7 },
			speed     = { 20, 60 },
			direction = 0,          -- outward, past the edge
			spread    = 70,
			size      = { 4, 10 },
			gravity   = 40,
			rotation  = { -180, 180 },
			spawn     = "right",
			zIndex    = zBase + 4,
			uiScale   = appliedRef.current,   -- §AGX/UI-FIX: shell#4
		})
		emitterRef.current = emitter   -- §AGX/UI-FIX: shell#4

		return function()
			if emitterRef.current == emitter then emitterRef.current = nil end
			emitter:Destroy()
		end
	end, { sparks, intensity, color, zBase })

	-- §AGX/UI-FIX: shell#4: keep the live emitter's scale current.
	React.useEffect(function()
		local emitter = emitterRef.current
		if emitter then emitter:SetUIScale(applied) end
	end, { applied })

	-- Chrome: real 9-slice art when pasted, dark fallback until then
	local frameImg = Theme.GetImage("barFrame")
	local shineImg = Theme.GetImage("barShine")

	local body = {
		Track = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = TRACK_COLOR,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = zBase,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			Padding = React.createElement("UIPadding", {
				PaddingLeft   = UDim.new(0, PAD_PX),
				PaddingRight  = UDim.new(0, PAD_PX),
				PaddingTop    = UDim.new(0, PAD_PX),
				PaddingBottom = UDim.new(0, PAD_PX),
			}),
			Fill = React.createElement("Frame", {
				ref = fillRef,
				Size = UDim2.fromScale(value, 1),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = zBase + 1,
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 3),
				}),
				Gradient = React.createElement("UIGradient", {
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(0, 0, 0), 0.45)),
						ColorSequenceKeypoint.new(1, color),
					}),
				}),
				BoltLayer = React.createElement("Frame", {
					ref = boltLayerRef,
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ZIndex = zBase + 2,
				}),
			}),
		}),
	}

	if shineImg then
		body.Shine = React.createElement("ImageLabel", {
			Image = shineImg.id,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = zBase + 5,
		})
	end

	local outerProps = {
		Size = props.size or UDim2.new(0.25, 0, 0, 24),
		Position = props.position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = zBase,
	}

	if frameImg then
		outerProps.Image = frameImg.id
		outerProps.ScaleType = Enum.ScaleType.Slice
		outerProps.SliceCenter = frameImg.slice
		return React.createElement("ImageLabel", outerProps, body)
	end

	-- Fallback chrome: dark frame + thin electric trim (until ids land)
	body.Stroke = React.createElement("UIStroke", {
		Color = color,
		Thickness = 1,
		Transparency = 0.35,
	})
	return React.createElement("Frame", outerProps, body)
end

return LightningBar
