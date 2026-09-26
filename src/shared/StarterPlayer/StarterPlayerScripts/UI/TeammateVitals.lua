-- shared/StarterPlayerScripts/UI/TeammateVitals.lua
--[[
    Teammate health display — shared combat component.

    Shows a compact strip of name + HP bar for every connected player
    except the local player. Positioned on the right side of the screen.
    Used by LaneDefense, CentralBoss, and HordeMode.

    Server broadcasts "VitalsUpdate" every ~1 s with a table keyed by
    userId → { name, hp, maxHp, class, level }.
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

-- ── Palette ───────────────────────────────────────────────
local C = {
	panel_bg   = Color3.fromRGB(16, 16, 22),
	bar_bg     = Color3.fromRGB(40, 40, 56),
	bar_hp     = Color3.fromRGB(60, 190, 90),
	bar_low    = Color3.fromRGB(200, 60, 60),
	text       = Color3.fromRGB(210, 210, 225),
	text_dim   = Color3.fromRGB(130, 130, 150),
	stub_text  = Color3.fromRGB(100, 100, 130),
	power_c    = Color3.fromRGB(255, 180, 40),
}

-- ═══════════════════════════════════════════════════════════
-- VITAL BAR (per-teammate row)
-- ═══════════════════════════════════════════════════════════
local function TeammateMember(props)
	local teammate = props.teammate
	local rowH     = props.rowH or ROW_H
	local hpFrac   = math.max(0, math.min(1, teammate.hp / math.max(teammate.maxHp, 1)))
	local isLow    = hpFrac < 0.30

	return React.createElement("Frame", {
		Size             = UDim2.new(1, 0, 0, rowH),  -- §AGX/UI-P1 / §AGX/UI-P5: rect.rowH
		LayoutOrder      = props.order or 0,
		BackgroundColor3 = C.panel_bg,
		BackgroundTransparency = 0.25,
		BorderSizePixel  = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),

		-- Name + class label
		Label = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.03, 0.08),
			Size                   = UDim2.fromScale(0.94, 0.42),
			BackgroundTransparency = 1,
			Text                   = teammate.name .. "  [" .. (teammate.class or "?") .. "]",
			TextColor3             = C.text,
			TextXAlignment         = Enum.TextXAlignment.Left,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
		}, {
			minText = React.createElement("UITextSizeConstraint", { MinTextSize = 12 }),  -- §AGX/UI-P1
		}),
		PowerBadge = (teammate.powerLevel and teammate.powerLevel > 0) and React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(1, 0),
			Position               = UDim2.fromScale(0.97, 0.08),
			Size                   = UDim2.fromScale(0.28, 0.42),
			BackgroundTransparency = 1,
			Text                   = "⚡" .. tostring(teammate.powerLevel),
			TextColor3             = C.power_c,
			TextXAlignment         = Enum.TextXAlignment.Right,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
		}, {
			minText = React.createElement("UITextSizeConstraint", { MinTextSize = 12 }),  -- §AGX/UI-P1
		}) or nil,

		-- HP bar track
		BarBg = React.createElement("Frame", {
			Position         = UDim2.fromScale(0.03, 0.58),
			Size             = UDim2.fromScale(0.94, 0.30),
			BackgroundColor3 = C.bar_bg,
			BorderSizePixel  = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			-- Filled portion
			Fill = React.createElement("Frame", {
				Size             = UDim2.fromScale(hpFrac, 1),
				BackgroundColor3 = isLow and C.bar_low or C.bar_hp,
				BorderSizePixel  = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			}),
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
			return React.createElement("TextLabel", {
				AnchorPoint            = rect and rect.anchorPoint or Vector2.new(1, 0),
				Position               = rect and rect.position or UDim2.new(1, -8, 0, 120),
				Size                   = rect and UDim2.fromOffset(rect.width, rowH)
					or UDim2.fromScale(0.089, 0.020),
				BackgroundTransparency = 1,
				Text                   = "[TeammateVitals — waiting]",
				TextColor3             = C.stub_text,
				TextScaled             = true,
				Font                   = Enum.Font.Gotham,
			}, {
				minText = React.createElement("UITextSizeConstraint", { MinTextSize = 12 }),  -- §AGX/UI-P1
			})
		end
		return nil
	end

	-- Build the rows
	local rows = {}
	for i, teammate in ipairs(teammates) do
		rows["member_" .. i] = React.createElement(TeammateMember, {
			teammate = teammate,
			order    = i,  -- §AGX/UI-P1: keep the alphabetical order in the list
			rowH     = rowH,
		})
	end
	rows.layout = React.createElement("UIListLayout", {
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
	return React.createElement("ScrollingFrame", {
		AnchorPoint      = anchor,
		Position         = pos,
		Size             = UDim2.new(width.X.Scale, width.X.Offset, 0, height),
		BackgroundTransparency = 1,
		BorderSizePixel  = 0,
		CanvasSize       = UDim2.new(0, 0, 0, contentH),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = (height < contentH) and 4 or 0,
		ScrollingEnabled = height < contentH,
		Active           = height < contentH,  -- don't sink world clicks unless it scrolls
	}, rows)
end

return TeammateVitals
