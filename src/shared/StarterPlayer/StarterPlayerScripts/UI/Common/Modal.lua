-- UI/Common/Modal.lua
--[[
    §AGX/UI-P1v2: Modal, a small centred dialog over a scrim (visual-system.md
    §4.2; D8: tap-outside closes SMALL dialogs only, so it is on by default here
    and never on Window).

    Modal{
        title       = string?,
        onDismiss   = function()?,   -- scrim tap, close button (and the shell's back)
        dismissible = true,
        width       = 420,           -- design px; clamped to 92 % of the screen
        actions     = { Button props, ... }?,  -- right-aligned footer row
        zIndex      = Theme.Z.modal,
        children    = body content (design px)
    }
    Self-scaling (UIScaleRoot.Local), so it is correct in a legacy tree too.
    The scrim is Active: nothing behind a modal can be clicked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common      = script.Parent
local Theme       = require(Common:WaitForChild("Theme"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local Text        = require(Common:WaitForChild("Text"))
local Button      = require(Common:WaitForChild("Button"))
local IconButton  = require(Common:WaitForChild("IconButton"))

local e = React.createElement
local R = Theme.Roles
local M = Theme.Metrics.modal

local function Modal(props)
	local z = props.zIndex or Theme.Z.modal
	local dismissible = props.dismissible ~= false
	local width = props.width or M.width
	local pad = Theme.Space.lg

	local actions = nil
	if props.actions and #props.actions > 0 then
		local row = {
			layout = e("UIListLayout", {
				FillDirection       = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				SortOrder           = Enum.SortOrder.LayoutOrder,
				Padding             = UDim.new(0, Theme.Space.sm),
			}),
		}
		for i, a in ipairs(props.actions) do
			local p = table.clone(a)
			p.layoutOrder = i
			p.zIndex = z + 3
			row["a" .. i] = e(Button, p)
		end
		actions = e("Frame", {
			LayoutOrder            = 3,
			Size                   = UDim2.new(1, 0, 0, Theme.Metrics.button.md),
			BackgroundTransparency = 1,
			ZIndex                 = z + 2,
		}, row)
	end

	return e(UIScaleRoot.Local, { name = "Modal", zIndex = z }, {
		scrim = e("TextButton", {
			Name                   = "Scrim",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = R.surface.scrim,
			BackgroundTransparency = Theme.Elevation.overlay.scrim,
			BorderSizePixel        = 0,
			AutoButtonColor        = false,
			Active                 = true,
			Selectable             = false,
			Text                   = "",
			ZIndex                 = z,
			[React.Event.Activated] = function()
				if dismissible and props.onDismiss then props.onDismiss() end
			end,
		}),
		panel = e("Frame", {
			Name                   = "Dialog",
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			-- min(width, 92 % of the layer): scale width capped by MaxSize
			Size                   = UDim2.new(M.maxWidthScale, 0, 0, 0),
			AutomaticSize          = Enum.AutomaticSize.Y,
			BackgroundColor3       = R.surface.panel,
			BorderSizePixel        = 0,
			Active                 = true,
			ZIndex                 = z + 1,
		}, {
			limit   = e("UISizeConstraint", { MaxSize = Vector2.new(width, math.huge) }),
			corner  = e("UICorner", { CornerRadius = Theme.Radius.lg }),
			stroke  = e("UIStroke", { Color = R.border.subtle, Thickness = Theme.Stroke.base }),
			padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, pad), PaddingRight = UDim.new(0, pad),
				PaddingTop = UDim.new(0, pad), PaddingBottom = UDim.new(0, pad),
			}),
			layout  = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder     = Enum.SortOrder.LayoutOrder,
				Padding       = UDim.new(0, Theme.Space.md),
			}),
			header = (props.title or (dismissible and props.onDismiss)) and e("Frame", {
				LayoutOrder            = 1,
				Size                   = UDim2.new(1, 0, 0, Theme.Metrics.iconButton.sm),
				BackgroundTransparency = 1,
				ZIndex                 = z + 2,
			}, {
				title = props.title and e(Text, {
					style  = "heading",
					text   = props.title,
					size   = UDim2.new(1, -(Theme.Metrics.iconButton.sm + Theme.Space.sm), 1, 0),
					zIndex = z + 2,
				}) or nil,
				close = (dismissible and props.onDismiss) and e(IconButton, {
					icon        = "close",
					variant     = "ghost",
					size        = "sm",
					anchorPoint = Vector2.new(1, 0.5),
					position    = UDim2.fromScale(1, 0.5),
					onActivated = props.onDismiss,
					zIndex      = z + 2,
				}) or nil,
			}) or nil,
			body = e("Frame", {
				LayoutOrder            = 2,
				Size                   = UDim2.fromScale(1, 0),
				AutomaticSize          = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ZIndex                 = z + 2,
			}, props.children),
			actions = actions,
		}),
	})
end

return Modal
