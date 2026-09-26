-- UI/HUD/VitalsRegion.lua
--[[
    §AGX/UI-P5: the vitals region (shell-spec §4.1 / §4.2).
      variant "full" (Combat): HP / Resource / XP rows (moved from
          HUD.lua:808-878; same panel, same StatusBar rows).
      variant "chip" (Lobby / Plaza, mobile.md §2.5): Level + XP only, built
          from Theme v2 Text + Bar.
    props: rect (Layout RECT, design px), variant, info (PlayerInfo state), visible
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common    = script.Parent.Parent:WaitForChild("Common")
local Theme     = require(Common:WaitForChild("Theme"))
local Text      = require(Common:WaitForChild("Text"))
local Bar       = require(Common:WaitForChild("Bar"))
local StatusBar = require(script.Parent:WaitForChild("StatusBar"))

local e = React.createElement
local C = Theme.Colors
local R = Theme.Roles

local function row(order, bar)
	return e("Frame", {
		Size                   = UDim2.fromScale(1, 0.27),
		BackgroundTransparency = 1,
		LayoutOrder            = order,
	}, { bar = bar })
end

local function FullVitals(props)
	local info, r = props.info, props.rect
	-- Phone/tablet vitals are 220 wide; give the value column more room.
	local columns = (r.w < 300) and StatusBar.NARROW_COLUMNS or nil
	local alive = info.deathState == "Alive"
	return e("Frame", {
		Name                   = "Vitals",
		AnchorPoint            = r.anchorPoint,
		Position               = r.position,
		Size                   = r.size,
		BackgroundColor3       = C.panel,
		BackgroundTransparency = 0.30,
		BorderSizePixel        = 0,
		Visible                = props.visible,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
		layout = e("UIListLayout", {
			FillDirection     = Enum.FillDirection.Vertical,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder         = Enum.SortOrder.LayoutOrder,
			Padding           = UDim.new(0.03, 0),
		}),
		pad = e("UIPadding", {
			PaddingLeft   = UDim.new(0.03, 0),
			PaddingRight  = UDim.new(0.03, 0),
			PaddingTop    = UDim.new(0.03, 0),
			PaddingBottom = UDim.new(0.03, 0),
		}),
		hpRow = row(1, e(StatusBar.default, {
			label   = "HP",
			-- §HUD-HP1: 0 HP when knocked down or dead.
			current = alive and info.hp.cur or 0,
			max     = info.hp.max,
			color   = C.hp,
			columns = columns,
		})),
		resRow = row(2, e(StatusBar.default, {
			label   = info.res and info.res.name or "Resource",
			current = info.res and info.res.cur or 0,
			max     = info.res and info.res.max or 100,
			color   = C.resource,
			effect  = "lightning",  -- §BEAUTY/P2
			columns = columns,
		})),
		xpRow = row(3, e(StatusBar.default, {
			label   = "Lv" .. tostring(info.xp.level),
			current = info.xp.cur,
			max     = info.xp.max,
			color   = C.xp,
			columns = columns,
		})),
	})
end

local function ChipVitals(props)
	local info, r = props.info, props.rect
	local padX = Theme.Space.sm
	local levelW = 56
	return e("Frame", {
		Name                   = "VitalsChip",
		AnchorPoint            = r.anchorPoint,
		Position               = r.position,
		Size                   = r.size,
		BackgroundColor3       = R.surface.panel,
		BackgroundTransparency = 0.30,
		BorderSizePixel        = 0,
		Visible                = props.visible,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
		stroke = e("UIStroke", {
			Color = R.border.identity, Thickness = Theme.Stroke.hair, Transparency = 0.5,
		}),
		level = e(Text, {
			style    = "label",
			text     = "Lv " .. tostring(info.xp.level),
			color    = R.accent.primary,
			position = UDim2.fromOffset(padX, 0),
			size     = UDim2.new(0, levelW, 1, 0),
		}),
		xp = e(Bar, {
			kind        = "xp",
			value       = info.xp.cur,
			max         = info.xp.max,
			showValue   = true,
			vital       = true,
			anchorPoint = Vector2.new(0, 0.5),
			position    = UDim2.new(0, padX + levelW, 0.5, 0),
			size        = UDim2.new(1, -(2 * padX + levelW), 0, Theme.Metrics.bar.vitalHeight),
		}),
	})
end

local function VitalsRegion(props)
	if props.variant == "chip" then
		return e(ChipVitals, props)
	end
	return e(FullVitals, props)
end

return VitalsRegion
