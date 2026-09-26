-- UI/Common/CurrencyPill.lua
--[[
    §AGX/UI-P1v2: CurrencyPill, the ONLY way to show a currency amount
    (replaces the 3 icon schemes). Identity per currency = Theme.Currency
    (icon + colour + glyph), never the accent colours.

    CurrencyPill{
        currency    = "merits"|"essence",
        value       = number,
        compact     = false,     -- 12.3K / 4.5M
        showLabel   = false,     -- "1,250 Merits"
        cost        = false,     -- price tag look (no fill); red when `insufficient`
        insufficient= false,
        onActivated = function()?,  -- makes it a 44 px tap target (e.g. "get more")
        position, anchorPoint, layoutOrder, zIndex
    }
    32 design px tall; 44 when tappable. Width is automatic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))

local e = React.createElement
local R = Theme.Roles
local M = Theme.Metrics.pill

local function withCommas(n)
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then out = string.sub(out, 2) end
	return (n < 0 and "-" or "") .. out
end

local function formatAmount(n, compact)
	n = n or 0
	if compact then
		local a = math.abs(n)
		if a >= 1e6 then return string.format("%.1fM", n / 1e6) end
		if a >= 1e4 then return string.format("%.1fK", n / 1e3) end
	end
	return withCommas(n)
end

local function CurrencyPill(props)
	local ff = useFormFactor()
	local spec = Theme.Currency[props.currency or "merits"] or Theme.Currency.merits
	local ty = Theme.typeFor("numeric", ff.kind)
	local tappable = props.onActivated ~= nil
	local height = tappable and M.tapHeight or M.height
	local iconId = Theme.GetIcon(spec.icon)
	local z = props.zIndex or 1

	local text = formatAmount(props.value, props.compact)
	if props.showLabel then text = text .. " " .. spec.label end
	local textColor = (props.cost and props.insufficient) and R.state.danger or spec.color

	return e(tappable and "TextButton" or "Frame", {
		Name                   = "CurrencyPill_" .. (props.currency or "merits"),
		AnchorPoint            = props.anchorPoint,
		Position               = props.position,
		Size                   = UDim2.fromOffset(0, height),
		AutomaticSize          = Enum.AutomaticSize.X,
		BackgroundColor3       = R.surface.sunken,
		BackgroundTransparency = props.cost and 1 or 0.1,
		BorderSizePixel        = 0,
		LayoutOrder            = props.layoutOrder,
		ZIndex                 = z,
		Text                   = tappable and "" or nil,
		AutoButtonColor        = if tappable then false else nil,
		[React.Event.Activated] = props.onActivated,
	}, {
		corner  = e("UICorner", { CornerRadius = Theme.Radius.pill }),
		stroke  = (not props.cost) and e("UIStroke", {
			Color = spec.color, Thickness = Theme.Stroke.hair, Transparency = 0.55,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}) or nil,
		padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, props.cost and 0 or 6), PaddingRight = UDim.new(0, M.padX),
		}),
		layout  = e("UIListLayout", {
			FillDirection     = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder         = Enum.SortOrder.LayoutOrder,
			Padding           = UDim.new(0, 6),
		}),
		icon = iconId and e("ImageLabel", {
			LayoutOrder            = 1,
			Size                   = UDim2.fromOffset(M.icon, M.icon),
			BackgroundTransparency = 1,
			Image                  = iconId,
			ZIndex                 = z + 1,
		}) or e("TextLabel", {
			LayoutOrder            = 1,
			Size                   = UDim2.fromOffset(M.icon, M.icon),
			BackgroundTransparency = 1,
			Text                   = spec.glyph,
			TextColor3             = spec.color,
			FontFace               = Theme.FontFaces.heavy,
			TextSize               = M.icon - 4,
			ZIndex                 = z + 1,
		}),
		amount = e("TextLabel", {
			LayoutOrder            = 2,
			Size                   = UDim2.fromScale(0, 1),
			AutomaticSize          = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text                   = text,
			TextColor3             = textColor,
			FontFace               = ty.font,
			TextSize               = ty.size,
			ZIndex                 = z + 1,
		}, {
			tsize = e("UITextSizeConstraint", { MinTextSize = ty.min, MaxTextSize = ty.max }),
		}),
	})
end

return CurrencyPill
