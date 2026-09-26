-- UI/Common/Tabs.lua
--[[
    §AGX/UI-P1v2: Tabs (visual-system.md §4.2; mobile.md §2.6). Replaces the
    4 TabButton implementations. Hybrid: active = blue underline + primary
    text (body accent), never orange.

    Tabs{
        items    = { { id, label, icon?, locked?, badge? }, ... },
        value    = id,                 -- active tab
        onChange = function(id),
        fill     = true,               -- equal-width segments across the bar
        size, position, anchorPoint, layoutOrder, zIndex
    }
    44 design px tall. On Phone with more than 4 items it becomes a
    horizontally scrolling chip row (each chip >= 88 x 44).

    §AGX/UI-P7: each tab carries the gamepad focus ring, and every mounted
    Tabs registers with GamepadFocus so PanelHost's LB / RB (only while the
    bar is inside the top panel and the input is Gamepad) cycles it,
    skipping locked items, through the same onChange a tap uses.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local GamepadFocus  = require(Common:WaitForChild("GamepadFocus"))   -- §AGX/UI-P7

local e = React.createElement
local R = Theme.Roles
local M = Theme.Metrics.tabs

local function Tab(props)
	local item, active, ty = props.item, props.active, props.ty
	local locked = item.locked == true
	local fg = locked and R.text.disabled or (active and R.text.primary or R.text.secondary)
	return e("TextButton", {
		Name                   = "Tab_" .. tostring(item.id),
		Size                   = props.size,
		AutomaticSize          = props.autoSize,
		BackgroundColor3       = active and R.surface.raised or R.surface.panel,
		BackgroundTransparency = active and 0 or 1,
		BorderSizePixel        = 0,
		AutoButtonColor        = false,
		Active                 = not locked,
		Selectable             = not locked,
		SelectionImageObject   = GamepadFocus.ring("sm"),   -- §AGX/UI-P7
		Text                   = "",
		LayoutOrder            = props.order,
		ZIndex                 = props.zIndex,
		[React.Event.Activated] = (not locked) and function()
			if props.onChange then props.onChange(item.id) end
		end or nil,
	}, {
		minSize = e("UISizeConstraint", { MinSize = Vector2.new(M.minWidth, M.height) }),
		pad     = e("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		label   = e("TextLabel", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text                   = (locked and (Theme.Glyphs.lock .. " ") or "") .. string.upper(item.label or tostring(item.id))
				.. (item.badge and ("  " .. tostring(item.badge)) or ""),
			TextColor3             = fg,
			FontFace               = ty.font,
			TextSize               = ty.size,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			ZIndex                 = (props.zIndex or 1) + 1,
		}, {
			tsize = e("UITextSizeConstraint", { MinTextSize = ty.min, MaxTextSize = ty.max }),
		}),
		underline = active and e("Frame", {
			AnchorPoint      = Vector2.new(0.5, 1),
			Position         = UDim2.fromScale(0.5, 1),
			Size             = UDim2.new(1, 0, 0, M.underline),
			BackgroundColor3 = R.accent.secondary,
			BorderSizePixel  = 0,
			ZIndex           = (props.zIndex or 1) + 1,
		}) or nil,
	})
end

local function Tabs(props)
	local ff = useFormFactor()
	local ty = Theme.typeFor("label", ff.kind)
	local items = props.items or {}
	local chips = ff.kind == "Phone" and #items > M.chipThreshold
	local fill = props.fill ~= false and not chips
	local z = props.zIndex or 1

	-- §AGX/UI-P7: LB / RB target (registration only; nothing is bound here).
	local rootRef = React.useRef(nil)
	local live = React.useRef(props)
	live.current = props
	React.useEffect(function()
		return GamepadFocus.registerTabs({
			getRoot = function() return rootRef.current end,
			cycle = function(dir)
				local p = live.current
				local list = p.items or {}
				local n = #list
				if n == 0 or type(p.onChange) ~= "function" then return nil end
				local idx = 1
				for i, it in ipairs(list) do
					if it.id == p.value then idx = i end
				end
				for step = 1, n - 1 do
					local j = ((idx - 1 + dir * step) % n) + 1
					if not list[j].locked then
						p.onChange(list[j].id)
						return list[j].id
					end
				end
				return nil
			end,
		})
	end, {})

	local children = {
		layout = e("UIListLayout", {
			FillDirection     = Enum.FillDirection.Horizontal,
			SortOrder         = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding           = UDim.new(0, chips and Theme.Space.xs or 0),
		}),
	}
	for i, item in ipairs(items) do
		children["t" .. i] = e(Tab, {
			item     = item,
			active   = item.id == props.value,
			onChange = props.onChange,
			order    = i,
			ty       = ty,
			zIndex   = z + 1,
			size     = fill and UDim2.new(1 / math.max(1, #items), 0, 1, 0) or UDim2.fromOffset(0, M.height),
			autoSize = (not fill) and Enum.AutomaticSize.X or nil,
		})
	end

	local common = {
		Name                   = "Tabs",
		AnchorPoint            = props.anchorPoint,
		Position               = props.position,
		Size                   = props.size or UDim2.new(1, 0, 0, M.height),
		BackgroundColor3       = R.surface.panel,
		BackgroundTransparency = 0,
		BorderSizePixel        = 0,
		LayoutOrder            = props.layoutOrder,
		ZIndex                 = z,
		ref                    = rootRef,   -- §AGX/UI-P7
	}

	if chips then
		common.CanvasSize          = UDim2.new(0, 0, 0, 0)
		common.AutomaticCanvasSize = Enum.AutomaticSize.X
		common.ScrollingDirection  = Enum.ScrollingDirection.X
		common.ScrollBarThickness  = 0
		common.ElasticBehavior     = Enum.ElasticBehavior.WhenScrollable
		return e("ScrollingFrame", common, children)
	end

	-- Segmented bar: tabs in a row, hairline divider under it (outside the list).
	return e("Frame", common, {
		row = e("Frame", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex                 = z,
		}, children),
		divider = e("Frame", {
			AnchorPoint      = Vector2.new(0, 1),
			Position         = UDim2.fromScale(0, 1),
			Size             = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = R.border.subtle,
			BorderSizePixel  = 0,
			ZIndex           = z,
		}),
	})
end

return Tabs
