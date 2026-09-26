-- UI/Common/Text.lua
--[[
    §AGX/UI-P1v2: Text — every label in the new UI (visual-system.md §4.2).

    Text{
        style      = "display"|"title"|"heading"|"body"|"label"|"caption"|"numeric",
        text       = string,
        color      = "text.primary" (role path) | Color3,
        align      = "left"|"center"|"right",       default "left"
        valign     = "top"|"center"|"bottom",       default "center"
        wrap       = false,       -- multi-line; grows in Y (AutomaticSize.Y)
        fit        = false,       -- TextScaled inside a fixed box (min/max clamp)
        upper      = nil,         -- default from the style (display/title)
        autoSize   = nil|"X"|"Y"|"XY",
        truncate   = true,        -- "…" when a single line overflows
        richText   = false,
        size, position, anchorPoint, layoutOrder, zIndex, name, children
    }

    Sizing: design px. Default box = full width x the style's lineHeight.
    ALWAYS carries a UITextSizeConstraint with the style's per-form-factor
    min/max (Theme.Type), so `fit` text never drops below the floor and
    fixed TextSize is clamped into the same band.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))

local e = React.createElement

local X_ALIGN = {
	left   = Enum.TextXAlignment.Left,
	center = Enum.TextXAlignment.Center,
	right  = Enum.TextXAlignment.Right,
}
local Y_ALIGN = {
	top    = Enum.TextYAlignment.Top,
	center = Enum.TextYAlignment.Center,
	bottom = Enum.TextYAlignment.Bottom,
}
local AUTO = {
	X  = Enum.AutomaticSize.X,
	Y  = Enum.AutomaticSize.Y,
	XY = Enum.AutomaticSize.XY,
}

local function Text(props)
	local ff = useFormFactor()
	local ty = Theme.typeFor(props.style or "body", ff.kind)

	local upper = props.upper
	if upper == nil then upper = ty.upper end
	local str = tostring(props.text or "")
	if upper then str = string.upper(str) end

	local autoSize = props.autoSize and AUTO[props.autoSize] or nil
	if props.wrap and not autoSize then autoSize = Enum.AutomaticSize.Y end

	local children = {
		sizeLimit = e("UITextSizeConstraint", {
			MinTextSize = ty.min,
			MaxTextSize = ty.max,
		}),
	}
	if props.children then
		for k, v in pairs(props.children) do children[k] = v end
	end

	return e("TextLabel", {
		Name                   = props.name or "Text",
		AnchorPoint            = props.anchorPoint,
		Position               = props.position,
		Size                   = props.size or UDim2.new(1, 0, 0, ty.lineHeight),
		AutomaticSize          = autoSize,
		BackgroundTransparency = 1,
		Text                   = str,
		TextColor3             = Theme.color(props.color or "text.primary"),
		FontFace               = ty.font,
		TextSize               = ty.size,
		TextScaled             = props.fit == true,
		TextWrapped            = props.wrap == true or props.fit == true,
		TextTruncate           = (props.truncate ~= false and not props.wrap)
			and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None,
		TextXAlignment         = X_ALIGN[props.align or "left"] or Enum.TextXAlignment.Left,
		TextYAlignment         = Y_ALIGN[props.valign or "center"] or Enum.TextYAlignment.Center,
		RichText               = props.richText == true,
		LayoutOrder            = props.layoutOrder,
		ZIndex                 = props.zIndex,
	}, children)
end

return Text
