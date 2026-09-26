-- shared/StarterPlayerScripts/UI/TeammateVitals.lua
--[[
    Teammate health display — shared combat component.

    Shows a compact strip of name + HP bar for every connected player
    except the local player. Positioned on the right side of the screen.
    Used by LaneDefense, CentralBoss, and HordeMode.

    Server broadcasts "VitalsUpdate" every ~1 s with a table keyed by
    userId → { name, hp, maxHp, class, level }.

    §AGX/UI-P6: Theme v2 re-skin. Rows = a sunken Panel with a Text name
    line and the Common Bar (kind "hp"; turns vital.hpLow under 25 %,
    was 30 %). The private palette and TextScaled labels are gone. Row
    geometry still follows `rect` (§AGX/UI-P5) in design px.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

-- §AGX/UI-P1: M9 layout. Rows are fixed pixels, so the container height is
-- computed from the row count (it was a share of a 1080 px screen). The
-- HUD publishes where its regions end as client-local ReplicatedStorage
-- attributes (see HUD/Layout.lua, §AGX/UI-P1):
--   UI_TopLeftBottomPx / UI_TopLeftXPx: touch vitals stack (top-left) -> we
--       stack under it (off the right-side skill arc and the ⋮ toggle).
--   UI_TopRightBottomPx: bottom of the ☰/currency/killfeed block (desktop).
--   UI_NavToggleTopPx: top of the ⋮ toggle; the right column stops above it
--       and scrolls instead of running into it.
-- §AGX/UI-P5 (C2): optional `rect` prop. When the HUD mounts this panel
-- (HUD/PartyRegion, partyInHud) it passes its region and the attributes
-- above are ignored:
--   rect = { anchorPoint, position (UDim2), width, maxHeight, rowH, rowGap }
-- in the units of the parent (design px inside the HUD's UIScaleRoot). The
-- list grows away from the anchor and scrolls past maxHeight. Without
-- `rect` (standalone mount, Wave 1) nothing changes.
local ROW_H         = 38
local ROW_GAP       = 4
local EDGE_GAP_PX   = 8
local FALLBACK_TOP  = 120   -- the old fixed top, used before the HUD publishes
local ATTRS = { "UI_TopLeftBottomPx", "UI_TopLeftXPx", "UI_TopRightBottomPx", "UI_NavToggleTopPx" }

local function readLayout()
	local t = {}
	for _, name in ipairs(ATTRS) do
		t[name] = tonumber(ReplicatedStorage:GetAttribute(name))
	end
	return t
end

local function useHudLayout()
	local layout, setLayout = React.useState(readLayout)
	React.useEffect(function()
		local conns = {}
		for _, name in ipairs(ATTRS) do
			table.insert(conns, ReplicatedStorage:GetAttributeChangedSignal(name):Connect(function()
				setLayout(readLayout())
			end))
		end
		setLayout(readLayout())
		return function()
			for _, c in ipairs(conns) do c:Disconnect() end
		end
	end, {})
	return layout
end

local LocalPlayer   = Players.LocalPlayer
local SharedModules = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")


-- §AGX/UI-P6: shared components
local Common = script.Parent:WaitForChild("Common")
local Theme  = require(Common:WaitForChild("Theme"))
local Text   = require(Common:WaitForChild("Text"))
local Bar    = require(Common:WaitForChild("Bar"))
local Panel  = require(Common:WaitForChild("Panel"))

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

local ROW_PAD_Y = 3        -- design px above / between / below the two lines
local POWER_W   = 56       -- power badge column

-- ═══════════════════════════════════════════════════════════
-- VITAL BAR (per-teammate row)
-- ═══════════════════════════════════════════════════════════
local function TeammateMember(props)
	local teammate = props.teammate
	local rowH     = props.rowH or ROW_H   -- §AGX/UI-P1 / §AGX/UI-P5: rect.rowH
	local barH     = math.max(6, math.floor(rowH * 0.22))
	local nameH    = math.max(1, rowH - barH - 3 * ROW_PAD_Y)
	local hasPower = teammate.powerLevel and teammate.powerLevel > 0

	return e(Panel, {
		name         = "Teammate",
		elevation    = "sunken",
		padding      = "none",
		radius       = "sm",
		transparency = 0.25,
		size         = UDim2.new(1, 0, 0, rowH),
		layoutOrder  = props.order or 0,
	}, {
		-- Name + class label
		Label = e(Text, {
			style    = "caption",
			text     = teammate.name .. "  [" .. (teammate.class or "?") .. "]",
			color    = "text.primary",
			position = UDim2.fromOffset(SP.xs, ROW_PAD_Y),
			size     = UDim2.new(1, -(2 * SP.xs + (hasPower and POWER_W or 0)), 0, nameH),
		}),
		PowerBadge = hasPower and e(Text, {
			style       = "caption",
			text        = "⚡" .. tostring(teammate.powerLevel),
			color       = "state.warning",
			align       = "right",
			anchorPoint = Vector2.new(1, 0),
			position    = UDim2.new(1, -SP.xs, 0, ROW_PAD_Y),
			size        = UDim2.fromOffset(POWER_W, nameH),
		}) or nil,

		-- HP bar (§AGX/UI-P6: Common Bar)
		HP = e(Bar, {
			kind     = "hp",
			value    = teammate.hp or 0,
			max      = math.max(teammate.maxHp or 1, 1),
			height   = barH,
			position = UDim2.fromOffset(SP.xs, ROW_PAD_Y * 2 + nameH),
			size     = UDim2.new(1, -2 * SP.xs, 0, barH),
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- TEAMMATE VITALS PANEL
-- ═══════════════════════════════════════════════════════════
local function TeammateVitals(props)
	props = props or {}
	local rect = props.rect  -- §AGX/UI-P5 (C2)
	local rowH   = (rect and rect.rowH) or ROW_H
	local rowGap = (rect and rect.rowGap) or ROW_GAP
	local teammates, setTeammates = React.useState({})
	local hudLayout = useHudLayout()  -- §AGX/UI-P1 (unconditional hook)

	-- Listen for VitalsUpdate from server
	React.useEffect(function()
		local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

		local conn = NetworkManager.OnServerEvent("VitalsUpdate", function(vitals)
			if not vitals then return end

			-- Filter out the local player, build array
			local list = {}
			local localId = tostring(LocalPlayer.UserId)
			for id, data in pairs(vitals) do
				if id ~= localId then
					table.insert(list, data)
				end
			end

			-- Sort alphabetically by name for stable ordering
			table.sort(list, function(a, b) return a.name < b.name end)

			setTeammates(list)
		end)

		return function()
			if conn and type(conn) == "table" and conn.Disconnect then
				conn:Disconnect()
			end
		end
	end, {})

	-- Nothing to show when solo
	if #teammates == 0 then
		if game:GetService("RunService"):IsStudio() then
			-- §AGX/UI-P6: Text (caption floor) instead of a TextScaled label.
			return e(Text, {
				style       = "caption",
				text        = "[TeammateVitals — waiting]",
				color       = "text.disabled",
				align       = rect and "left" or "right",
				anchorPoint = rect and rect.anchorPoint or Vector2.new(1, 0),
				position    = rect and rect.position or UDim2.new(1, -8, 0, 120),
				size        = UDim2.fromOffset(rect and rect.width or 200, rowH),
			})
		end
		return nil
	end

	-- Build the rows
	local rows = {}
	for i, teammate in ipairs(teammates) do
		rows["member_" .. i] = e(TeammateMember, {
			teammate = teammate,
			order    = i,  -- §AGX/UI-P1: keep the alphabetical order in the list
			rowH     = rowH,
		})
	end
	rows.layout = e("UIListLayout", {
		SortOrder     = Enum.SortOrder.LayoutOrder,
		Padding       = UDim.new(0, rowGap),  -- §AGX/UI-P1
		FillDirection = Enum.FillDirection.Vertical,
	})

	-- §AGX/UI-P1: content height from the row count (n*38 + (n-1)*4).
	local contentH = #teammates * rowH + math.max(0, #teammates - 1) * rowGap
	local tlBottom = hudLayout.UI_TopLeftBottomPx
	local useLeft  = tlBottom ~= nil   -- HUD is in touch layout

	local anchor, pos, width, height
	if rect then
		-- §AGX/UI-P5 (C2): the HUD's party region; attributes ignored.
		anchor = rect.anchorPoint or Vector2.new(0, 0)
		pos    = rect.position
		width  = UDim2.new(0, rect.width or 200, 0, 0)
		height = math.max(rowH, math.min(contentH, rect.maxHeight or contentH))
	elseif useLeft then
		-- Touch: top-left, under the vitals stack.
		anchor = Vector2.new(0, 0)
		pos    = UDim2.fromOffset(hudLayout.UI_TopLeftXPx or EDGE_GAP_PX, tlBottom)
		width  = UDim2.new(0.20, 0, 0, 0)
		height = contentH
	else
		-- Desktop: right column, under the top-right block, above the ⋮ toggle.
		local top = math.max(FALLBACK_TOP, hudLayout.UI_TopRightBottomPx or 0)
		local limit = hudLayout.UI_NavToggleTopPx
		height = contentH
		if limit then
			height = math.max(ROW_H, math.min(contentH, limit - EDGE_GAP_PX - top))
		end
		anchor = Vector2.new(1, 0)
		pos    = UDim2.new(1, -EDGE_GAP_PX, 0, top)
		width  = UDim2.new(0.099, 0, 0, 0)
	end

	-- ScrollingFrame so a clipped list (tiny window, big party) still reaches
	-- every teammate; with room to spare it looks like the old Frame.
	return e("ScrollingFrame", {
		AnchorPoint      = anchor,
		Position         = pos,
		Size             = UDim2.new(width.X.Scale, width.X.Offset, 0, height),
		BackgroundTransparency = 1,
		BorderSizePixel  = 0,
		CanvasSize       = UDim2.new(0, 0, 0, contentH),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = (height < contentH) and 4 or 0,
		ScrollBarImageColor3 = R.text.secondary,   -- §AGX/UI-P6
		ScrollingEnabled = height < contentH,
		Active           = height < contentH,  -- don't sink world clicks unless it scrolls
	}, rows)
end

return TeammateVitals
