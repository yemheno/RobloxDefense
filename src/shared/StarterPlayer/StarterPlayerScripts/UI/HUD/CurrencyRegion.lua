-- UI/HUD/CurrencyRegion.lua
--[[
    §AGX/UI-P5: Essence / Merits / Power row.
    Essence and Merits use CurrencyPill (Theme.Currency identity: art from
    Theme.GetIcon("essence"/"merits"), glyph fallback until the ids land).
    Power has no currency identity, so it gets a pill in the same shape.
    props: rect (design px), currency { essence, merits }, power, visible
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent.Parent:WaitForChild("Common")
local Theme         = require(Common:WaitForChild("Theme"))
local CurrencyPill  = require(Common:WaitForChild("CurrencyPill"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))

local e = React.createElement
local R = Theme.Roles
local M = Theme.Metrics.pill

local POWER_GLYPH = "⚡"

local function compact(n)
	n = n or 0
	if math.abs(n) >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if math.abs(n) >= 1e4 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

local function PowerPill(props)
	local ff = useFormFactor()
	local ty = Theme.typeFor("numeric", ff.kind)
	local color = R.accent.primary   -- HUD vitals chrome (D1 Hybrid)
	return e("Frame", {
		Name                   = "PowerPill",
		Size                   = UDim2.fromOffset(0, M.height),
		AutomaticSize          = Enum.AutomaticSize.X,
		BackgroundColor3       = R.surface.sunken,
		BackgroundTransparency = 0.1,
		BorderSizePixel        = 0,
		LayoutOrder            = props.layoutOrder,
	}, {
		corner  = e("UICorner", { CornerRadius = Theme.Radius.pill }),
		stroke  = e("UIStroke", {
			Color = color, Thickness = Theme.Stroke.hair, Transparency = 0.55,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, M.padX),
		}),
		layout  = e("UIListLayout", {
			FillDirection     = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder         = Enum.SortOrder.LayoutOrder,
			Padding           = UDim.new(0, 6),
		}),
		icon = e("TextLabel", {
			LayoutOrder            = 1,
			Size                   = UDim2.fromOffset(M.icon, M.icon),
			BackgroundTransparency = 1,
			Text                   = POWER_GLYPH,
			TextColor3             = color,
			FontFace               = Theme.FontFaces.heavy,
			TextSize               = M.icon - 4,
		}),
		amount = e("TextLabel", {
			LayoutOrder            = 2,
			Size                   = UDim2.fromScale(0, 1),
			AutomaticSize          = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text                   = compact(props.value),
			TextColor3             = color,
			FontFace               = ty.font,
			TextSize               = ty.size,
		}, {
			tsize = e("UITextSizeConstraint", { MinTextSize = ty.min, MaxTextSize = ty.max }),
		}),
	})
end

local function CurrencyRegion(props)
	local r = props.rect
	local currency = props.currency or {}
	return e("Frame", {
		Name                   = "Currencies",
		AnchorPoint            = r.anchorPoint,
		Position               = r.position,
		Size                   = r.size,
		BackgroundTransparency = 1,
		Visible                = props.visible,
	}, {
		layout = e("UIListLayout", {
			FillDirection       = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment   = Enum.VerticalAlignment.Center,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Padding             = UDim.new(0, Theme.Space.xs),
		}),
		essence = e(CurrencyPill, {
			currency = "essence", value = currency.essence or 0, compact = true, layoutOrder = 1,
		}),
		merits = e(CurrencyPill, {
			currency = "merits", value = currency.merits or 0, compact = true, layoutOrder = 2,
		}),
		power = e(PowerPill, { value = props.power or 0, layoutOrder = 3 }),
	})
end

return CurrencyRegion
