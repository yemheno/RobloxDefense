-- UI/Shell/MenuRail.lua
--[[
    §AGX/UI-P3: the icon rail (D3; shell-spec §4.4-§4.5, B4). Desktop in every
    place, Tablet in Lobby/Plaza. Rendered by MenuSurface inside the HUD's
    rail rect (HUD root = design px under the HUD UIScale).

    MenuRail{ place, blocked? }
        Fills its parent: a vertical UIListLayout of the 6 groups, 44 design
        px cells (Theme.Layout[kind].rail: cell/gap/pad/icon), on a
        translucent navy plate.
        • Icon = Theme.GetIcon art, else the Theme.Glyphs emoji.
        • Badge = OR of the group's entries (BadgeStore via Badge.useBadges).
        • Group with no available entry: dimmed (state.locked plate); a tap
          explains why (toast).
        • Active group (its entry or its flyout is on top): blue inner bar +
          raised plate (Hybrid: blue is the body/selection accent).
        • state.blocked (a modal is up): the whole rail dims, taps ignored.
        • Tooltip = label (hover on PC, long-press on touch).
        Tap:
          Character / Progress (flyout groups, D3)  -> open("menuFlyout",
              { group, place, anchor = the button's left-centre in GUI px,
                rail = { pos, size } of this rail in GUI px (§AGX/UI-FIX: 10) });
              tap again -> closeAll("toggle")
          any other group -> its first available entry (open / toggle close)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent.Parent:WaitForChild("Common")
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local Tooltip       = require(Common:WaitForChild("Tooltip"))
local Badge         = require(script.Parent:WaitForChild("Badge"))
local MenuIcon      = require(script.Parent:WaitForChild("MenuIcon"))

local e = React.createElement
local R = Theme.Roles
local Model = MenuIcon.Model

local DEFAULT_RAIL = { cell = 44, gap = 8, pad = 6, icon = 28 }

local function RailButton(props)
	local g = props.group
	local locked = Model.availableCount(g) == 0
	local tip = Tooltip.use(props.tooltip)
	local hovered, setHovered = React.useState(false)
	local z = props.zIndex or 1
	local cell = props.cell
	local active = props.active
	local inert = props.blocked

	local fill, fillT = R.surface.raised, 1
	if active then
		fill, fillT = Theme.Palette.navy650, 0
	elseif hovered and not inert then
		fill, fillT = R.surface.raised, 0.2
	elseif locked then
		fill, fillT = R.state.locked, 0.55
	end

	return e("TextButton", {
		Name                   = "Rail_" .. tostring(g.id),
		Size                   = UDim2.fromOffset(cell, cell),
		BackgroundColor3       = fill,
		BackgroundTransparency = fillT,
		BorderSizePixel        = 0,
		AutoButtonColor        = false,
		Active                 = not inert,
		Selectable             = not inert,
		Text                   = "",
		LayoutOrder            = props.layoutOrder,
		ZIndex                 = z,
		[React.Event.InputBegan] = tip.onInputBegan,
		[React.Event.MouseEnter] = function(rbx) setHovered(true); tip.onMouseEnter(rbx) end,
		[React.Event.MouseLeave] = function(rbx) setHovered(false); tip.onMouseLeave(rbx) end,
		[React.Event.SelectionGained] = function(rbx) setHovered(true); tip.onSelectionGained(rbx) end,
		[React.Event.SelectionLost]   = function(rbx) setHovered(false); tip.onSelectionLost(rbx) end,
		[React.Event.Activated] = (not inert) and tip.wrapActivated(function(rbx)
			props.onActivated(g, rbx)
		end) or nil,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
		stroke = (active or hovered) and e("UIStroke", {
			Color = R.border.focus, Thickness = Theme.Stroke.base,
			Transparency = active and 0 or 0.4,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}) or nil,
		-- selection bar on the rail's outer (left) edge, toward the content
		bar = active and e("Frame", {
			AnchorPoint      = Vector2.new(0, 0.5),
			Position         = UDim2.new(0, -3, 0.5, 0),
			Size             = UDim2.new(0, 3, 0.6, 0),
			BackgroundColor3 = R.accent.secondary,
			BorderSizePixel  = 0,
			ZIndex           = z + 1,
		}, { corner = e("UICorner", { CornerRadius = Theme.Radius.pill }) }) or nil,
		icon = e(MenuIcon.Icon, {
			icon        = g.icon,
			glyph       = g.glyph,
			size        = props.iconSize,
			dim         = locked or inert,
			anchorPoint = Vector2.new(0.5, 0.5),
			position    = UDim2.fromScale(0.5, 0.5),
			zIndex      = z + 1,
		}),
		badge = (not inert) and e(Badge.View, { count = props.badge, zIndex = z + 3 }) or nil,
	})
end

local function MenuRail(props)
	local ff = useFormFactor()
	local state = Model.useStack()
	local getBadge = Badge.useBadges()
	local place = Model.resolvePlace(props.place, nil)
	local groups = React.useMemo(function() return Model.groups(place) end, { place })

	local rail = ff.design.rail or DEFAULT_RAIL
	local cell = rail.cell or DEFAULT_RAIL.cell
	local gap  = rail.gap or DEFAULT_RAIL.gap
	local pad  = rail.pad or DEFAULT_RAIL.pad
	local iconSize = rail.icon or DEFAULT_RAIL.icon
	local blocked = props.blocked == true or state.blocked == true
	local topId, topProps = Model.topOf(state)

	local function onGroup(g, rbx)
		if blocked then return end
		local PS = Model.PanelStack()
		if g.flyout then
			if not PS then return end
			if topId == "menuFlyout" and type(topProps) == "table" and topProps.group == g.id then
				PS.closeAll("toggle")
				return
			end
			local anchor = rbx.AbsolutePosition + Vector2.new(0, rbx.AbsoluteSize.Y / 2)
			-- §AGX/UI-FIX: 10 — the rail's own rect (GUI px), so the flyout's
			-- scrim leaves it uncovered: one tap on another group switches.
			local railFrame = rbx.Parent
			local railRect = (railFrame and railFrame:IsA("GuiObject"))
				and { pos = railFrame.AbsolutePosition, size = railFrame.AbsoluteSize } or nil
			PS.open("menuFlyout", { group = g.id, place = place, anchor = anchor, rail = railRect })
			return
		end
		for _, item in ipairs(g.items) do
			if item.available then
				Model.activate(item, place, { from = "rail" })
				return
			end
		end
		if g.items[1] then Model.toast(Model.reason(g.items[1], true)) end
	end

	local children = {
		layout = e("UIListLayout", {
			FillDirection       = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment   = Enum.VerticalAlignment.Center,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Padding             = UDim.new(0, gap),
		}),
		padding = e("UIPadding", {
			PaddingTop = UDim.new(0, pad), PaddingBottom = UDim.new(0, pad),
			PaddingLeft = UDim.new(0, pad), PaddingRight = UDim.new(0, pad),
		}),
		corner = e("UICorner", { CornerRadius = Theme.Radius.lg }),
		stroke = e("UIStroke", {
			Color = R.border.subtle, Thickness = Theme.Stroke.hair, Transparency = 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	}

	for i, g in ipairs(groups) do
		local isActive = false
		if topId == "menuFlyout" then
			isActive = type(topProps) == "table" and topProps.group == g.id
		elseif topId then
			for _, it in ipairs(g.items) do
				if it.id == topId then isActive = true end
			end
		end
		local direct = nil
		if not g.flyout then
			for _, it in ipairs(g.items) do
				if it.available then direct = it; break end
			end
		end
		local tooltip = g.label
		if direct then
			tooltip = direct.label
		elseif Model.availableCount(g) == 0 and g.items[1] then
			tooltip = g.label .. " — " .. Model.reason(g.items[1], true)
		end
		children["g" .. i] = e(RailButton, {
			group       = g,
			cell        = cell,
			iconSize    = iconSize,
			active      = isActive,
			blocked     = blocked,
			tooltip     = tooltip,
			badge       = Badge.sum(getBadge, Model.badgeKeys(g.items)),
			layoutOrder = i,
			zIndex      = 3,
			onActivated = onGroup,
		})
	end

	return e("Frame", {
		Name                   = "MenuRail",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundColor3       = R.surface.panel,
		BackgroundTransparency = blocked and 0.55 or 0.2,
		BorderSizePixel        = 0,
		ZIndex                 = 2,
	}, children)
end

return MenuRail
