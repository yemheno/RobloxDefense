-- UI/Shell/MenuFlyout.lua
--[[
    §AGX/UI-P3: rail flyout (class menu; shell-spec §4.5, B4). Opened by
    MenuRail for the Character and Progress groups only (D3):
        PanelStack.open("menuFlyout", { group, place, anchor })

    Props: group (id), place?, anchor = Vector2 GUI px of the rail button's
           left-centre (AbsolutePosition space, shared by every ScreenGui),
           onClose (PanelHost).
    A card at AP(1,0.5), (anchor.X - G, anchor.Y), clamped to the layer, with
    a nub pointing at the rail button. One row of tiles (Desktop 88x64,
    Tablet 96x72): icon + label (>= 12) + a second line with the lock
    reason. A tile runs PanelStack.replace(id) (the flyout gives way); an
    action entry runs closeAll("self") then the action (PanelStack.open).
    Outside click: PanelHost's scrim (menu entries are dismissOnBackdrop);
    outside a PanelHost the flyout draws its own transparent scrim.
    *(verify in Studio)* AbsolutePosition of the HUD (AppGui) and PanelGui
    share one space; if not, the clamp still keeps the card on screen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent.Parent:WaitForChild("Common")
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))
local Text          = require(Common:WaitForChild("Text"))
local Badge         = require(script.Parent:WaitForChild("Badge"))
local MenuIcon      = require(script.Parent:WaitForChild("MenuIcon"))

local e = React.createElement
local R = Theme.Roles
local MM = Theme.Metrics.menu
local Model = MenuIcon.Model

local PAD    = Theme.Space.md   -- 12
local HEAD_H = 18
local NUB    = 12

local function MenuFlyout(props)
	local ff = useFormFactor()
	local scale = UIScaleRoot.useUIScale()
	local getBadge = Badge.useBadges()
	local entryCtx = Model.useEntry()
	local place = Model.resolvePlace(props.place, entryCtx)
	local groups = React.useMemo(function() return Model.groups(place) end, { place })
	local layer, setLayer = React.useState(nil)   -- { pos, size } of the root, GUI px
	local firstRef = React.useRef(nil)

	local PS = Model.PanelStack()
	if PS and type(PS.useFirstFocus) == "function" then PS.useFirstFocus(firstRef) end

	local group = nil
	for _, g in ipairs(groups) do
		if g.id == props.group then group = g end
	end

	local target = scale.target
	local tile = (ff.design.rail and ff.design.rail.tile) or Vector2.new(88, 64)
	local gap = MM.tileGap
	local G = ff.design.gap or 8
	local edge = ff.design.edge or 16

	local items = group and group.items or {}
	local n = math.max(1, #items)
	local cardW = PAD * 2 + n * tile.X + (n - 1) * gap
	local cardH = PAD + HEAD_H + Theme.Space.sm + tile.Y + PAD

	-- Placement in design px of this layer.
	local layerW = layer and layer.size.X / target or ff.viewport.X / target
	local layerH = layer and layer.size.Y / target or ff.viewport.Y / target
	local ax, ay
	if typeof(props.anchor) == "Vector2" and layer then
		ax = (props.anchor.X - layer.pos.X) / target - G
		ay = (props.anchor.Y - layer.pos.Y) / target
	else
		ax = layerW - edge - 56 - G   -- right edge, left of a rail-width strip
		ay = layerH / 2
	end
	local x = math.clamp(ax, cardW + edge, math.max(cardW + edge, layerW - edge))
	local y = math.clamp(ay, cardH / 2 + edge, math.max(cardH / 2 + edge, layerH - cardH / 2 - edge))
	-- nub stays on the anchor even when the card was clamped
	local nubY = math.clamp(ay - (y - cardH / 2), NUB, cardH - NUB)

	local tiles = {
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0, gap),
		}),
	}
	local firstSet = false
	for i, item in ipairs(items) do
		local useFirst = (not firstSet) and item.available
		if useFirst then firstSet = true end
		tiles["t" .. i] = e(MenuIcon.Tile, {
			item        = item,
			size        = tile,
			badge       = getBadge(item.badgeKey),
			layoutOrder = i,
			zIndex      = 6,
			tileRef     = useFirst and firstRef or nil,
			onActivated = function()
				Model.activate(item, place, { from = "menu" })
			end,
		})
	end

	local close = function(reason)
		if props.onClose then props.onClose(reason) end
	end

	return e(UIScaleRoot.Local, { name = "MenuFlyout", zIndex = 2 }, {
		root = e("Frame", {
			Name                   = "Layer",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex                 = 2,
			[React.Change.AbsoluteSize] = function(rbx)
				setLayer({ pos = rbx.AbsolutePosition, size = rbx.AbsoluteSize })
			end,
			[React.Change.AbsolutePosition] = function(rbx)
				setLayer({ pos = rbx.AbsolutePosition, size = rbx.AbsoluteSize })
			end,
		}, {
			-- Own scrim only outside a PanelHost (PanelHost draws the D8 one).
			scrim = (entryCtx == nil) and e("TextButton", {
				Name                   = "Scrim",
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				AutoButtonColor        = false,
				Selectable             = false,
				Text                   = "",
				ZIndex                 = 2,
				[React.Event.Activated] = function() close("backdrop") end,
			}) or nil,
			card = e("Frame", {
				Name             = "Flyout_" .. tostring(props.group),
				AnchorPoint      = Vector2.new(1, 0.5),
				Position         = UDim2.fromOffset(x, y),
				Size             = UDim2.fromOffset(cardW, cardH),
				BackgroundColor3 = R.surface.panel,
				BorderSizePixel  = 0,
				Active           = true,   -- taps on the card never reach the scrim
				ZIndex           = 4,
			}, {
				corner = e("UICorner", { CornerRadius = Theme.Radius.lg }),
				stroke = e("UIStroke", {
					Color = R.border.subtle, Thickness = Theme.Stroke.base, Transparency = 0.2,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
				nub = e("Frame", {
					Name             = "Nub",
					AnchorPoint      = Vector2.new(0.5, 0.5),
					Position         = UDim2.new(1, 0, 0, nubY),
					Size             = UDim2.fromOffset(NUB, NUB),
					Rotation         = 45,
					BackgroundColor3 = R.surface.panel,
					BorderSizePixel  = 0,
					ZIndex           = 3,
				}),
				head = e("Frame", {
					Name                   = "Head",
					Position               = UDim2.fromOffset(PAD, PAD),
					Size                   = UDim2.new(1, -2 * PAD, 0, HEAD_H),
					BackgroundTransparency = 1,
					ZIndex                 = 5,
				}, {
					marker = e("Frame", {
						AnchorPoint      = Vector2.new(0, 0.5),
						Position         = UDim2.fromScale(0, 0.5),
						Size             = UDim2.fromOffset(3, 14),
						BackgroundColor3 = R.accent.secondary,
						BorderSizePixel  = 0,
						ZIndex           = 5,
					}, { corner = e("UICorner", { CornerRadius = Theme.Radius.pill }) }),
					label = e(Text, {
						style    = "label",
						text     = group and group.label or "",
						upper    = true,
						color    = "text.secondary",
						size     = UDim2.new(1, -9, 1, 0),
						position = UDim2.fromOffset(9, 0),
						zIndex   = 5,
					}),
				}),
				tiles = e("Frame", {
					Name                   = "Tiles",
					Position               = UDim2.fromOffset(PAD, PAD + HEAD_H + Theme.Space.sm),
					Size                   = UDim2.new(1, -2 * PAD, 0, tile.Y),
					BackgroundTransparency = 1,
					ZIndex                 = 5,
				}, tiles),
			}),
		}),
	})
end

return MenuFlyout
