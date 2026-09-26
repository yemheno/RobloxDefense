-- UI/Common/Card.lua
--[[
    §AGX/UI-P1v2: Card, list/grid item (replaces 7 variants; visual-system.md §4.2).

    Card{
        title     = string?,  subtitle = string?,
        icon      = Theme.Icons key | rbxassetid?,  -- 40 px thumbnail, left
        rarity    = "common"|"uncommon"|"rare"|"epic"|"legendary"?,  -- stroke colour
        selected  = false,    -- blue focus ring (body accent)
        locked    = false,    -- dimmed + lock glyph, not tappable
        badge     = string?,  -- small corner tag ("NEW", "x3", "EQUIPPED")
        footer    = element?, -- e.g. a CurrencyPill price or a Button
        onActivated = function()?,  -- whole card becomes a tap target (>= 44 px)
        size      = UDim2 (default full width, auto height),
        layoutOrder, zIndex, children (extra body content)
    }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))

local e = React.createElement
local R = Theme.Roles
local M = Theme.Metrics.card

local THUMB = 40

local function Card(props)
	local ff = useFormFactor()
	local headTy = Theme.typeFor("heading", ff.kind)
	local capTy  = Theme.typeFor("caption", ff.kind)
	local locked = props.locked == true
	local tappable = props.onActivated ~= nil and not locked
	local z = props.zIndex or 1

	local strokeColor, strokeT = R.border.subtle, 0.35
	if props.selected then
		strokeColor, strokeT = R.border.focus, 0
	elseif props.rarity and R.rarity[props.rarity] then
		strokeColor, strokeT = R.rarity[props.rarity], 0.1
	end

	local iconId = nil
	if type(props.icon) == "string" then
		iconId = (string.sub(props.icon, 1, 13) == "rbxassetid://") and props.icon or Theme.GetIcon(props.icon)
	end
	local hasThumb = props.icon ~= nil
	local textLeft = hasThumb and (THUMB + Theme.Space.md) or 0

	local body = {
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0, Theme.Space.xs),
		}),
		title = props.title and e("TextLabel", {
			LayoutOrder            = 1,
			Size                   = UDim2.new(1, 0, 0, headTy.lineHeight),
			BackgroundTransparency = 1,
			Text                   = (locked and (Theme.Glyphs.lock .. " ") or "") .. props.title,
			TextColor3             = locked and R.text.secondary or R.text.primary,
			FontFace               = headTy.font,
			TextSize               = headTy.size,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			TextXAlignment         = Enum.TextXAlignment.Left,
			ZIndex                 = z + 1,
		}, { tsize = e("UITextSizeConstraint", { MinTextSize = headTy.min, MaxTextSize = headTy.max }) }) or nil,
		subtitle = props.subtitle and e("TextLabel", {
			LayoutOrder            = 2,
			Size                   = UDim2.new(1, 0, 0, 0),
			AutomaticSize          = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text                   = props.subtitle,
			TextColor3             = R.text.secondary,
			FontFace               = capTy.font,
			TextSize               = capTy.size,
			TextWrapped            = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
			ZIndex                 = z + 1,
		}, { tsize = e("UITextSizeConstraint", { MinTextSize = capTy.min, MaxTextSize = capTy.max }) }) or nil,
		extra = props.children and e("Frame", {
			LayoutOrder            = 3,
			Size                   = UDim2.fromScale(1, 0),
			AutomaticSize          = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex                 = z + 1,
		}, props.children) or nil,
		footer = props.footer and e("Frame", {
			LayoutOrder            = 4,
			Size                   = UDim2.fromScale(1, 0),
			AutomaticSize          = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex                 = z + 1,
		}, { content = props.footer }) or nil,
	}

	return e(tappable and "TextButton" or "Frame", {
		Name                   = "Card",
		Size                   = props.size or UDim2.new(1, 0, 0, 0),
		AutomaticSize          = (props.size == nil) and Enum.AutomaticSize.Y or nil,
		BackgroundColor3       = props.selected and Theme.Palette.navy650 or R.surface.raised,
		BackgroundTransparency = locked and 0.35 or 0,
		BorderSizePixel        = 0,
		LayoutOrder            = props.layoutOrder,
		ZIndex                 = z,
		Text                   = tappable and "" or nil,
		AutoButtonColor        = if tappable then false else nil,
		Selectable             = tappable or nil,
		[React.Event.Activated] = tappable and props.onActivated or nil,
	}, {
		corner  = e("UICorner", { CornerRadius = Theme.Radius.lg }),
		stroke  = e("UIStroke", {
			Color = strokeColor, Transparency = strokeT,
			Thickness = props.selected and Theme.Stroke.focus or Theme.Stroke.base,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		minSize = tappable and e("UISizeConstraint", { MinSize = Vector2.new(M.minTap, M.minTap) }) or nil,
		padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, M.pad), PaddingRight = UDim.new(0, M.pad),
			PaddingTop = UDim.new(0, M.pad), PaddingBottom = UDim.new(0, M.pad),
		}),
		thumb = hasThumb and e("Frame", {
			Size             = UDim2.fromOffset(THUMB, THUMB),
			BackgroundColor3 = R.surface.sunken,
			BorderSizePixel  = 0,
			ZIndex           = z + 1,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
			image = iconId and e("ImageLabel", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = iconId,
				ImageTransparency = locked and 0.5 or 0, ZIndex = z + 2,
			}) or e("TextLabel", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
				Text = Theme.Glyphs[props.icon] or string.upper(string.sub(tostring(props.icon), 1, 1)),
				TextColor3 = R.text.secondary, FontFace = Theme.FontFaces.heavy, TextSize = 20, ZIndex = z + 2,
			}),
		}) or nil,
		body = e("Frame", {
			Position               = UDim2.fromOffset(textLeft, 0),
			Size                   = UDim2.new(1, -textLeft, 0, 0),
			AutomaticSize          = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex                 = z + 1,
		}, body),
		badge = props.badge and e("TextLabel", {
			AnchorPoint            = Vector2.new(1, 0),
			Position               = UDim2.new(1, M.pad - 4, 0, -(M.pad - 4)),
			Size                   = UDim2.fromOffset(0, 18),
			AutomaticSize          = Enum.AutomaticSize.X,
			BackgroundColor3       = R.accent.secondary,
			BorderSizePixel        = 0,
			Text                   = string.upper(props.badge),
			TextColor3             = R.text.onAccent,
			FontFace               = Theme.FontFaces.bold,
			TextSize               = 12,
			ZIndex                 = z + 3,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
			pad    = e("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
		}) or nil,
	})
end

return Card
