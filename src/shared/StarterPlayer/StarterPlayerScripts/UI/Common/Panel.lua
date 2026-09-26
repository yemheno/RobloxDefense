-- UI/Common/Panel.lua
--[[
    §AGX/UI-P1v2: Panel, the surface for sections/cards/wells (visual-system.md §4.2).

    Panel{
        elevation = "flat"|"raised"|"sunken",   default "raised"
        padding   = Theme.Space key | number,    default "md" (12)
        radius    = Theme.Radius key,            default "md"
        layout    = nil|"vertical"|"horizontal", adds a UIListLayout
        gap       = Theme.Space key | number,    default "sm"
        align     = "start"|"center"|"end",      cross-axis alignment for layout
        stroke    = true,                        border.subtle hairline (false = none)
        accent    = nil | role path | Color3,    override stroke colour (selection etc.)
        size      = UDim2 (default fill parent), autoSize = nil|"X"|"Y"|"XY",
        clip      = false, transparency = 0,
        position, anchorPoint, layoutOrder, zIndex, name, children
    }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Theme = require(script.Parent:WaitForChild("Theme"))

local e = React.createElement
local R = Theme.Roles

local AUTO = { X = Enum.AutomaticSize.X, Y = Enum.AutomaticSize.Y, XY = Enum.AutomaticSize.XY }
local H_ALIGN = { start = Enum.HorizontalAlignment.Left, center = Enum.HorizontalAlignment.Center, ["end"] = Enum.HorizontalAlignment.Right }
local V_ALIGN = { start = Enum.VerticalAlignment.Top, center = Enum.VerticalAlignment.Center, ["end"] = Enum.VerticalAlignment.Bottom }

local function Panel(props)
	local elevation = Theme.Elevation[props.elevation or "raised"] or Theme.Elevation.raised
	local fill = R.surface[elevation.surface or "raised"] or R.surface.raised
	local pad = Theme.space(props.padding or "md")
	local z = props.zIndex or 1

	local strokeColor = nil
	if props.accent then
		strokeColor = Theme.color(props.accent)
	elseif props.stroke ~= false and elevation.stroke then
		strokeColor = R.border.subtle
	end

	local children = {
		corner  = e("UICorner", { CornerRadius = Theme.Radius[props.radius or "md"] or Theme.Radius.md }),
		padding = pad > 0 and e("UIPadding", {
			PaddingLeft = UDim.new(0, pad), PaddingRight = UDim.new(0, pad),
			PaddingTop = UDim.new(0, pad), PaddingBottom = UDim.new(0, pad),
		}) or nil,
		stroke  = strokeColor and e("UIStroke", {
			Color           = strokeColor,
			Thickness       = props.accent and Theme.Stroke.strong or Theme.Stroke[elevation.stroke or "hair"],
			Transparency    = props.accent and 0 or 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}) or nil,
		layout  = props.layout and e("UIListLayout", {
			FillDirection       = props.layout == "horizontal" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Padding             = UDim.new(0, Theme.space(props.gap or "sm")),
			HorizontalAlignment = props.layout == "vertical" and (H_ALIGN[props.align or "start"]) or nil,
			VerticalAlignment   = props.layout == "horizontal" and (V_ALIGN[props.align or "center"]) or nil,
		}) or nil,
	}
	if props.children then
		for k, v in pairs(props.children) do children[k] = v end
	end

	return e("Frame", {
		Name                   = props.name or "Panel",
		AnchorPoint            = props.anchorPoint,
		Position               = props.position,
		Size                   = props.size or UDim2.fromScale(1, 1),
		AutomaticSize          = props.autoSize and AUTO[props.autoSize] or nil,
		BackgroundColor3       = fill,
		BackgroundTransparency = props.transparency or 0,
		BorderSizePixel        = 0,
		ClipsDescendants       = props.clip == true,
		LayoutOrder            = props.layoutOrder,
		ZIndex                 = z,
	}, children)
end

return Panel
