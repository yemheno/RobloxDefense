-- UI/Common/Button.lua
--[[
    §AGX/UI-P1v2: Button (visual-system.md §4.2). D1 Hybrid:
      primary   orange plate/fill + ink text     -> the ONE main CTA per view
      secondary navy plate, blue inner line, white text (default)
      danger    red fill + white text (5.5:1)
      success   green fill + ink text (9.9:1)
      ghost     no fill, blue (link) text
      locked    navy500 fill + secondary text + lock glyph, not interactive

    Button{
        variant     = "secondary",
        size        = "sm"|"md"|"lg",     -- 44 / 48 / 56 design px tall (>= 44)
        label       = string,
        icon        = Theme.Icons key | rbxassetid string | nil,
        disabled    = false,             -- renders as locked, no Activated
        loading     = false,             -- "…" label, no Activated
        selected    = false,             -- focus-colour ring (toggles / segmented)
        onActivated = function(),
        tooltip     = string?,           -- hover / long-press (Tooltip.use)
        width       = number (design px) | UDim | nil (auto, min 88),
        position, anchorPoint, layoutOrder, zIndex, name
    }
    Uses Theme.Images.btn* 9-slice plates when their ids are pasted, else a
    flat fill + stroke with the same colours.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local Tooltip       = require(Common:WaitForChild("Tooltip"))
-- §AGX/UI-P7: gamepad focus ring (drawn only around the selected object).
local GamepadFocus  = require(Common:WaitForChild("GamepadFocus"))

local e  = React.createElement
local R  = Theme.Roles
local M  = Theme.Metrics.button

local VARIANTS = {
	primary   = { fill = R.accent.primary, text = R.text.onAccent, stroke = R.accent.primaryDeep, plate = "btnPrimary" },
	secondary = { fill = Theme.Palette.navy650, text = R.text.primary, stroke = R.accent.secondary, plate = "btnSecondary" },
	danger    = { fill = R.state.dangerFill, text = R.text.onDanger, stroke = Theme.Palette.red700, plate = "btnDanger" },
	success   = { fill = R.state.success, text = R.text.onAccent, stroke = nil, plate = nil },
	ghost     = { fill = nil, text = R.text.link, stroke = nil, plate = nil },
	locked    = { fill = R.state.locked, text = R.text.secondary, stroke = R.border.subtle, plate = "btnLocked" },
}

local function resolveIcon(icon)
	if not icon then return nil end
	if string.sub(icon, 1, 13) == "rbxassetid://" then return icon end
	return Theme.GetIcon(icon)
end

local function Button(props)
	local ff = useFormFactor()
	local tip = Tooltip.use(props.tooltip)
	local pressed, setPressed = React.useState(false)
	local hovered, setHovered = React.useState(false)

	local inert = props.disabled or props.loading or props.variant == "locked"
	local variantName = (props.disabled and "locked") or props.variant or "secondary"
	local v = VARIANTS[variantName] or VARIANTS.secondary
	local height = M[props.size or "md"] or M.md
	local ty = Theme.typeFor("label", ff.kind)
	local plate = v.plate and Theme.GetImage(v.plate) or nil

	local label = props.loading and "…" or (props.label or "")
	local iconId = resolveIcon(props.icon)
	local showLock = variantName == "locked"

	-- Width: explicit design px / UDim, else auto with a 88 px floor.
	local width = props.width
	local size, autoSize
	if type(width) == "number" then
		size = UDim2.fromOffset(width, height)
	elseif typeof(width) == "UDim" then
		size = UDim2.new(width.Scale, width.Offset, 0, height)
	else
		size = UDim2.fromOffset(0, height)
		autoSize = Enum.AutomaticSize.X
	end

	local fillT = v.fill and 0 or 1
	if not inert and v.fill then
		if pressed then fillT = 0.15 elseif hovered then fillT = 0.06 end
	end

	local z = props.zIndex or 1
	local strokeColor = props.selected and R.border.focus or ((not plate) and v.stroke or nil)
	local fixedWidth = autoSize == nil

	local children = {
		corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
		minSize = e("UISizeConstraint", { MinSize = Vector2.new(math.max(M.minWidth, height), height) }),
		stroke = strokeColor and e("UIStroke", {
			Color           = strokeColor,
			Thickness       = props.selected and Theme.Stroke.focus or Theme.Stroke.base,
			Transparency    = (inert and not props.selected) and 0.5 or 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}) or nil,
		-- 9-slice plate behind the content (only when the art id is pasted)
		plate = plate and e("ImageLabel", {
			Name                   = "Plate",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image                  = plate.id,
			ScaleType              = Enum.ScaleType.Slice,
			SliceCenter            = plate.slice,
			ImageTransparency      = pressed and 0.15 or 0,
			ZIndex                 = z,
		}) or nil,
		content = e("Frame", {
			Name                   = "Content",
			Size                   = fixedWidth and UDim2.fromScale(1, 1) or UDim2.fromScale(0, 1),
			AutomaticSize          = (not fixedWidth) and Enum.AutomaticSize.X or nil,
			BackgroundTransparency = 1,
			ZIndex                 = z + 1,
		}, {
			padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, M.padX), PaddingRight = UDim.new(0, M.padX),
			}),
			layout = e("UIListLayout", {
				FillDirection       = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment   = Enum.VerticalAlignment.Center,
				SortOrder           = Enum.SortOrder.LayoutOrder,
				Padding             = UDim.new(0, M.iconGap),
			}),
			lock = showLock and e("TextLabel", {
				LayoutOrder            = 0,
				Size                   = UDim2.fromOffset(M.icon, M.icon),
				BackgroundTransparency = 1,
				Text                   = Theme.Glyphs.lock,
				TextColor3             = v.text,
				TextSize               = ty.size,
				ZIndex                 = z + 1,
			}) or nil,
			icon = iconId and e("ImageLabel", {
				LayoutOrder            = 1,
				Size                   = UDim2.fromOffset(M.icon, M.icon),
				BackgroundTransparency = 1,
				Image                  = iconId,
				ImageTransparency      = inert and 0.4 or 0,
				ZIndex                 = z + 1,
			}) or nil,
			label = e("TextLabel", {
				LayoutOrder            = 2,
				Size                   = UDim2.fromScale(0, 1),
				AutomaticSize          = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				Text                   = string.upper(label),
				TextColor3             = v.text,
				FontFace               = ty.font,
				TextSize               = ty.size,
				ZIndex                 = z + 1,
			}, {
				tsize = e("UITextSizeConstraint", { MinTextSize = ty.min, MaxTextSize = ty.max }),
			}),
		}),
	}

	local buttonProps = {
		Name                   = props.name or ("Button_" .. label),
		AnchorPoint            = props.anchorPoint,
		Position               = props.position,
		Size                   = size,
		AutomaticSize          = autoSize,
		BackgroundColor3       = v.fill or R.surface.panel,
		BackgroundTransparency = plate and 1 or fillT,
		BorderSizePixel        = 0,
		AutoButtonColor        = false,
		Active                 = not inert,
		Selectable             = not inert,
		SelectionImageObject   = GamepadFocus.ring("md"),   -- §AGX/UI-P7
		Text                   = "",
		LayoutOrder            = props.layoutOrder,
		ZIndex                 = z,
		[React.Event.InputBegan] = function(rbx, input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				setPressed(true)
			end
			tip.onInputBegan(rbx, input)
		end,
		[React.Event.InputEnded] = function(_rbx, input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				setPressed(false)
			end
		end,
		[React.Event.MouseEnter] = function(rbx)
			setHovered(true)
			tip.onMouseEnter(rbx)
		end,
		[React.Event.MouseLeave] = function(rbx)
			setHovered(false)
			setPressed(false)
			tip.onMouseLeave(rbx)
		end,
		[React.Event.SelectionGained] = tip.onSelectionGained,
		[React.Event.SelectionLost]   = tip.onSelectionLost,
		[React.Event.Activated] = (not inert) and tip.wrapActivated(props.onActivated) or nil,
	}

	return e("TextButton", buttonProps, children)
end

return Button
