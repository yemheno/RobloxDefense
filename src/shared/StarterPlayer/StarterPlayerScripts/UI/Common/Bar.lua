-- UI/Common/Bar.lua
--[[
    §AGX/UI-P1v2: Bar, the one progress bar (replaces 8 variants;
    visual-system.md §4.2).

    Bar{
        value, max = 1,
        kind      = "hp"|"resource"|"xp"|"boss"|"shield"|"progress",   default "progress"
        vital     = false,     -- HUD vitals chrome: orange identity frame (D1 Hybrid)
        label     = string?,   -- left caption above the bar
        showValue = false,     -- "value / max" right-aligned inside the bar
        segments  = number?,   -- tick marks (e.g. boss phases)
        effect    = nil|"lightning",  -- delegates to LightningBar (resource crackle)
        bossPhase = 1..3,      -- colour for kind = "boss"
        height    = number,    -- design px, default 16 (vital 20)
        size, position, anchorPoint, layoutOrder, zIndex
    }
    hp turns vital.hpLow under 25 %. Uses the barFrame 9-slice when its id
    is pasted, else a rounded track with a hairline.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local LightningBar  = require(Common:WaitForChild("LightningBar"))

local e = React.createElement
local R = Theme.Roles
local M = Theme.Metrics.bar

local function fillColor(kind, ratio, phase)
	if kind == "hp" then return ratio < 0.25 and R.vital.hpLow or R.vital.hp end
	if kind == "resource" then return R.vital.resource end
	if kind == "xp" then return R.vital.xp end
	if kind == "shield" then return R.vital.shield end
	if kind == "boss" then return R.vital.boss[math.clamp(phase or 1, 1, #R.vital.boss)] end
	return R.accent.secondary
end

local function formatNumber(n)
	n = math.floor((n or 0) + 0.5)
	if math.abs(n) >= 10000 then
		return string.format("%.1fK", n / 1000)
	end
	return tostring(n)
end

local function Bar(props)
	local ff = useFormFactor()
	local max = (props.max and props.max > 0) and props.max or 1
	local ratio = math.clamp((props.value or 0) / max, 0, 1)
	local kind = props.kind or "progress"
	local color = fillColor(kind, ratio, props.bossPhase)
	local height = props.height or (props.vital and M.vitalHeight or M.height)
	local z = props.zIndex or 1
	local numTy = Theme.typeFor("numeric", ff.kind)
	local capTy = Theme.typeFor("caption", ff.kind)
	local frameImg = Theme.GetImage("barFrame")
	local hasLabel = props.label ~= nil
	local labelH = hasLabel and (capTy.lineHeight + M.labelGap) or 0

	local track
	if props.effect == "lightning" then
		track = e(LightningBar, {
			value    = ratio,
			color    = color,
			size     = UDim2.new(1, 0, 0, height),
			position = UDim2.fromOffset(0, labelH),
			zIndex   = z + 1,
		})
	else
		local ticks = {}
		if props.segments and props.segments > 1 then
			for i = 1, props.segments - 1 do
				ticks["tick" .. i] = e("Frame", {
					AnchorPoint      = Vector2.new(0.5, 0),
					Position         = UDim2.fromScale(i / props.segments, 0),
					Size             = UDim2.new(0, 2, 1, 0),
					BackgroundColor3 = R.surface.base,
					BackgroundTransparency = 0.2,
					BorderSizePixel  = 0,
					ZIndex           = z + 3,
				})
			end
		end
		track = e("Frame", {
			Name             = "Track",
			Position         = UDim2.fromOffset(0, labelH),
			Size             = UDim2.new(1, 0, 0, height),
			BackgroundColor3 = R.surface.track,
			BorderSizePixel  = 0,
			ClipsDescendants = true,
			ZIndex           = z + 1,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.sm }),
			stroke = (not frameImg) and e("UIStroke", {
				Color           = props.vital and R.border.identity or R.border.subtle,
				Thickness       = props.vital and Theme.Stroke.strong or Theme.Stroke.hair,
				Transparency    = props.vital and 0.1 or 0.3,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}) or nil,
			fill = e("Frame", {
				Name             = "Fill",
				Size             = UDim2.fromScale(ratio, 1),
				BackgroundColor3 = color,
				BorderSizePixel  = 0,
				ZIndex           = z + 2,
			}, {
				corner = e("UICorner", { CornerRadius = Theme.Radius.sm }),
				grad = e("UIGradient", {
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(1, 0.25),
					}),
				}),
			}),
			ticks = e("Frame", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z + 3,
			}, ticks),
			value = props.showValue and e("TextLabel", {
				Size                   = UDim2.new(1, -8, 1, 0),
				Position               = UDim2.fromOffset(4, 0),
				BackgroundTransparency = 1,
				Text                   = formatNumber(props.value) .. " / " .. formatNumber(max),
				TextColor3             = R.text.primary,
				TextStrokeTransparency = 0.35,
				FontFace               = numTy.font,
				TextSize               = math.min(numTy.size, height),
				TextXAlignment         = Enum.TextXAlignment.Right,
				ZIndex                 = z + 4,
			}, {
				tsize = e("UITextSizeConstraint", { MinTextSize = numTy.min, MaxTextSize = numTy.max }),
			}) or nil,
			chrome = frameImg and e("ImageLabel", {
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image                  = frameImg.id,
				ScaleType              = Enum.ScaleType.Slice,
				SliceCenter            = frameImg.slice,
				ImageColor3            = props.vital and R.border.identity or Color3.new(1, 1, 1),
				ZIndex                 = z + 5,
			}) or nil,
		})
	end

	return e("Frame", {
		Name                   = "Bar_" .. kind,
		AnchorPoint            = props.anchorPoint,
		Position               = props.position,
		Size                   = props.size or UDim2.new(1, 0, 0, labelH + height),
		BackgroundTransparency = 1,
		LayoutOrder            = props.layoutOrder,
		ZIndex                 = z,
	}, {
		label = hasLabel and e("TextLabel", {
			Size                   = UDim2.new(1, 0, 0, capTy.lineHeight),
			BackgroundTransparency = 1,
			Text                   = props.label,
			TextColor3             = R.text.secondary,
			FontFace               = capTy.font,
			TextSize               = capTy.size,
			TextXAlignment         = Enum.TextXAlignment.Left,
			ZIndex                 = z + 1,
		}, {
			tsize = e("UITextSizeConstraint", { MinTextSize = capTy.min, MaxTextSize = capTy.max }),
		}) or nil,
		track = track,
	})
end

return Bar
