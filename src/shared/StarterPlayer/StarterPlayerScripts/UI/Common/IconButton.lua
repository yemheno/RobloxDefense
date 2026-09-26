-- UI/Common/IconButton.lua
--[[
    §AGX/UI-P1v2: IconButton, a square tap target (visual-system.md §4.2).
    Replaces the 14 hand-rolled close buttons.

    IconButton{
        icon        = "close" | Theme.Icons key | "rbxassetid://..",
                      -- art from Theme.GetIcon when pasted, else Theme.Glyphs[icon]
        variant     = "ghost"|"secondary"|"primary"|"danger",   default "ghost"
        size        = "sm"|"md"|"lg" (44/48/56) | number (clamped to >= 44), default "md"
        onActivated = function(),
        tooltip     = string?,          -- hover / long-press
        label       = string?,          -- glyph fallback when neither art nor glyph exists
        badge       = number|string?,   -- small count bubble (top-right)
        disabled    = false,
        position, anchorPoint, layoutOrder, zIndex, name
    }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common  = script.Parent
local Theme   = require(Common:WaitForChild("Theme"))
local Tooltip = require(Common:WaitForChild("Tooltip"))
-- §AGX/UI-P7: gamepad focus ring (drawn only around the selected object).
local GamepadFocus = require(Common:WaitForChild("GamepadFocus"))

local e = React.createElement
local R = Theme.Roles
local M = Theme.Metrics.iconButton

local VARIANTS = {
	ghost     = { fill = nil,                   fg = R.text.primary,  stroke = nil },
	secondary = { fill = Theme.Palette.navy650, fg = R.text.primary,  stroke = R.accent.secondary },
	primary   = { fill = R.accent.primary,      fg = R.text.onAccent, stroke = nil },
	danger    = { fill = R.state.dangerFill,    fg = R.text.onDanger, stroke = nil },
}

local function IconButton(props)
	local tip = Tooltip.use(props.tooltip)
	local pressed, setPressed = React.useState(false)

	local v = VARIANTS[props.variant or "ghost"] or VARIANTS.ghost
	local side = props.size
	if type(side) ~= "number" then side = M[side or "md"] or M.md end
	side = math.max(M.sm, side)   -- 44 design px floor

	local icon = props.icon
	local imageId = nil
	if type(icon) == "string" then
		imageId = (string.sub(icon, 1, 13) == "rbxassetid://") and icon or Theme.GetIcon(icon)
	end
	local glyph = nil
	if not imageId then
		glyph = (type(icon) == "string" and Theme.Glyphs[icon]) or props.label
			or (type(icon) == "string" and string.upper(string.sub(icon, 1, 1))) or "?"
	end
	local disabled = props.disabled == true
	local z = props.zIndex or 1

	return e("TextButton", {
		Name                   = props.name or ("IconButton_" .. tostring(icon)),
		AnchorPoint            = props.anchorPoint,
		Position               = props.position,
		Size                   = UDim2.fromOffset(side, side),
		BackgroundColor3       = v.fill or R.surface.raised,
		BackgroundTransparency = v.fill and (pressed and 0.15 or 0) or (pressed and 0.4 or 1),
		BorderSizePixel        = 0,
		AutoButtonColor        = false,
		Active                 = not disabled,
		Selectable             = not disabled,
		SelectionImageObject   = GamepadFocus.ring("md"),   -- §AGX/UI-P7
		Text                   = "",
		LayoutOrder            = props.layoutOrder,
		ZIndex                 = z,
		[React.Event.InputBegan] = function(rbx, input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then setPressed(true) end
			tip.onInputBegan(rbx, input)
		end,
		[React.Event.InputEnded] = function(_rbx, input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then setPressed(false) end
		end,
		[React.Event.MouseEnter]      = tip.onMouseEnter,
		[React.Event.MouseLeave]      = function(rbx) setPressed(false); tip.onMouseLeave(rbx) end,
		[React.Event.SelectionGained] = tip.onSelectionGained,
		[React.Event.SelectionLost]   = tip.onSelectionLost,
		[React.Event.Activated] = (not disabled) and tip.wrapActivated(props.onActivated) or nil,
	}, {
		aspect = e("UIAspectRatioConstraint", { AspectRatio = 1 }),
		corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
		stroke = v.stroke and e("UIStroke", {
			Color = v.stroke, Thickness = Theme.Stroke.base,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}) or nil,
		image = imageId and e("ImageLabel", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			Size                   = UDim2.fromScale(0.62, 0.62),
			BackgroundTransparency = 1,
			Image                  = imageId,
			ImageTransparency      = disabled and 0.5 or 0,
			ZIndex                 = z + 1,
		}) or nil,
		glyph = glyph and e("TextLabel", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text                   = glyph,
			TextColor3             = disabled and R.text.disabled or v.fg,
			FontFace               = Theme.FontFaces.heavy,
			TextSize               = math.floor(side * M.glyph),
			ZIndex                 = z + 1,
		}) or nil,
		badge = props.badge and e("TextLabel", {
			AnchorPoint            = Vector2.new(1, 0),
			Position               = UDim2.new(1, 4, 0, -4),
			Size                   = UDim2.fromOffset(18, 18),
			AutomaticSize          = Enum.AutomaticSize.X,
			BackgroundColor3       = R.state.dangerFill,
			BorderSizePixel        = 0,
			Text                   = tostring(props.badge),
			TextColor3             = R.text.onDanger,
			FontFace               = Theme.FontFaces.bold,
			TextSize               = 12,
			ZIndex                 = z + 2,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
			pad    = e("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
		}) or nil,
	})
end

return IconButton
