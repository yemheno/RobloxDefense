-- UI/HUD/StatusBar.lua
--[[
    label | [====-------] | current / max

    §AGX/UI-P5: colours come from the Theme v2 aliases
    (track / textDim / text), and the three column widths can be narrowed
    with `columns = { label, trackX, trackW, valueX, valueW }` (scale of the
    row) so the 220-design-px phone vitals still fit "1234 / 1234".
    props: label, current, max, color, effect ("lightning" | nil), columns
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common       = script.Parent.Parent:WaitForChild("Common")
local Theme        = require(Common:WaitForChild("Theme"))
local LightningBar = require(Common:WaitForChild("LightningBar"))

local C = Theme.Colors

local DEFAULT_COLUMNS = { label = 0.18, trackX = 0.19, trackW = 0.55, valueX = 0.75, valueW = 0.25 }
local NARROW_COLUMNS  = { label = 0.14, trackX = 0.15, trackW = 0.46, valueX = 0.63, valueW = 0.37 }

local function minText()
	return React.createElement("UITextSizeConstraint", { MinTextSize = 12 })
end

local function StatusBar(props)
	local label   = props.label or "?"
	local current = math.max(props.current or 0, 0)
	local max     = math.max(props.max or 1, 1)
	local color   = props.color
	local pct     = math.clamp(current / max, 0, 1)
	local valText = math.floor(current) .. " / " .. math.floor(max)
	local col     = props.columns or DEFAULT_COLUMNS

	-- §BEAUTY/P2: opt-in lightning crackle (Resource row).
	local track
	if props.effect == "lightning" then
		track = React.createElement(LightningBar, {
			value       = pct,
			color       = color,
			position    = UDim2.fromScale(col.trackX, 0.15),
			size        = UDim2.fromScale(col.trackW, 0.70),
			anchorPoint = Vector2.new(0, 0),
			intensity   = 0.9,
			zIndex      = 2,
		})
	else
		track = React.createElement("Frame", {
			Position         = UDim2.fromScale(col.trackX, 0.15),
			Size             = UDim2.fromScale(col.trackW, 0.70),
			BackgroundColor3 = C.track,
			BorderSizePixel  = 0,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			fill = React.createElement("Frame", {
				Size             = UDim2.fromScale(pct, 1),
				BackgroundColor3 = color,
				BorderSizePixel  = 0,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			}),
		})
	end

	return React.createElement("Frame", {
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		lbl = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0, 0),
			Size                   = UDim2.fromScale(col.label, 1),
			BackgroundTransparency = 1,
			Text                   = label,
			TextColor3             = C.textDim,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}, { minText = minText() }),

		track = track,

		val = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(col.valueX, 0),
			Size                   = UDim2.fromScale(col.valueW, 1),
			BackgroundTransparency = 1,
			Text                   = valText,
			TextColor3             = C.text,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}, { minText = minText() }),
	})
end

return {
	default        = StatusBar,
	DEFAULT_COLUMNS = DEFAULT_COLUMNS,
	NARROW_COLUMNS  = NARROW_COLUMNS,
}
