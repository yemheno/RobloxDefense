-- UI/TalentTreeUI.lua
--[[
    React component: full-window talent tree viewer.  (§T10/U2)

    The tree config lays branches out as rectangular grid blocks (rows ×
    columns per branch). The CONFIG stays untouched; the renderer applies a
    deterministic ORGANIC TRANSFORM at render time so it reads as a tree:

      • polar re-projection around the Origin with per-node jitter
        (seeded from the node id — stable across sessions/clients)
      • radial bloom so inner rings breathe
      • per-branch color identity from node tags (hashed hue — any
        future branch gets its own tint automatically)
      • two-layer edges (shadow + core) with allocated / next-step
        highlighting, so paths read like limbs instead of wires
      • mouse-wheel zoom + background-drag pan
      • node states, points counter, Respec All, hover tooltip, close button

    §AGX/UI-P2, §AGX/UI-P6: touch model + Theme v2 (mobile.md M17 / §2.6;
    DESIGN_DECISIONS.md#ui-decisions UI-D1 / UI-D2 / UI-D12).
      • tap / click SELECTS a node → detail panel (bottom sheet on
        phone, side panel on desktop) with a 48 px Allocate / Refund
        button + disabled reason. A single click never spends
        (respec costs Essence). PC keeps hover tooltips and gets
        double-click = allocate for speed.
      • one-finger drag pans; a drag > TAP_SLOP px never counts as a tap
      • two-finger pinch zoom (clamped), + / − / Fit buttons (48 px)
      • opens fitted; on touch the zoom floor keeps nodes ≥ 44 px
      • The whole body lives in UIScaleRoot.Local, so every constant below
        is a DESIGN px (phone scale). Screen px from input / AbsoluteSize /
        AbsolutePosition are converted with UIScaleRoot.toLocal before they
        reach the view math (pan delta, pinch mid, wheel anchor, canvas
        size). Pinch ratios and TAP_SLOP stay in screen px.
      • Colours = Theme roles; detail panel, hover card, legend, zoom and
        header controls = Panel / Text / Button / IconButton / CurrencyPill.
        Allocate = the one primary CTA.
      • Touch detection = useFormFactor().isTouch.

    Architecture:
      Topology  ← TalentTreeConfig (ReplicatedStorage.Shared)
      State     ← TalentClient (subscribe pattern)
      Actions   → TalentClient (fire-and-forget → server responds)
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")  -- §AGX/UI-P2: map input coords → GUI space for zoom anchors
local RunService        = game:GetService("RunService")  -- §AGX/UI-FIX: R5: gamepad pan / zoom
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local TalentClient   = require(SharedModules:WaitForChild("TalentClient"))
local TreeConfig     = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TalentTreeConfig"))
local Common         = script.Parent:WaitForChild("Common")
local AppWindow      = require(Common:WaitForChild("AppWindow"))  -- §T10/U3
-- §AGX/UI-P6: shared components
local Theme          = require(Common:WaitForChild("Theme"))
local UIScaleRoot    = require(Common:WaitForChild("UIScaleRoot"))
local Text           = require(Common:WaitForChild("Text"))
local Button         = require(Common:WaitForChild("Button"))
local IconButton     = require(Common:WaitForChild("IconButton"))
local Panel          = require(Common:WaitForChild("Panel"))
local CurrencyPill   = require(Common:WaitForChild("CurrencyPill"))
local useFormFactor  = require(Common:WaitForChild("useFormFactor"))
local GamepadFocus   = require(Common:WaitForChild("GamepadFocus"))   -- §AGX/UI-FIX: R5

-- §AGX/UI-FIX: R5: PanelStack.useFirstFocus + EntryContext, nil-safe
-- (no-ops outside a PanelHost / without UI/Shell).
local useFirstFocus = function(_ref) end
local EntryContext = nil
do
	local shell = script.Parent:FindFirstChild("Shell")
	local mod = shell and shell:FindFirstChild("PanelStack")
	if mod then
		local ok, PanelStack = pcall(require, mod)
		if ok and type(PanelStack) == "table" then
			if type(PanelStack.useFirstFocus) == "function" then useFirstFocus = PanelStack.useFirstFocus end
			EntryContext = PanelStack.EntryContext
		end
	end
end
EntryContext = EntryContext or React.createContext(nil)

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

-- ── Layout constants (§AGX/UI-P6: design px, see header) ─────────────────────
local DEFAULT_CELL = 42     -- pixels per grid unit at zoom 1 (wheel-zoomable)
local MIN_CELL     = 22
local MAX_CELL     = 72
local NODE_SIZE    = 36     -- pixels (diameter) at DEFAULT_CELL; scales with zoom
local CENTER_X     = 0.5
local CENTER_Y     = 0.45

-- Radial layout tuning (§T10/U4 — true polar construction)
local RING_START   = 5.5    -- grid units: radius of depth-1 ring
local RING_STEP    = 3.4    -- grid units per depth ring
local SECTOR_FILL  = 0.78   -- fraction of each branch's sector actually used
local RING_JITTER  = 0.35   -- small radial wobble (grid units) so rings breathe
local ANGLE_JITTER = 0.03   -- radians of per-node wobble

-- §AGX/UI-P2: touch / selection tuning (mobile.md M17, §2.6; D12).
local TAP_SLOP        = 10     -- px: a press that moves further is a drag, never a tap
local TAP_GRACE_S     = 0.3    -- s: Activated arriving this soon after a drag release is swallowed
local MIN_TAP_PX      = 44     -- px: smallest node diameter allowed on touch
local DOUBLE_CLICK_S  = 0.35   -- s: PC double-click = allocate (single click only selects)
local ZOOM_STEP       = 1.25   -- multiplier per +/− button press
local WHEEL_STEP      = 4      -- cell px per wheel notch
local FIT_PAD         = 24     -- px margin around the layout when fitting
local EDGE_INSET      = 44     -- px: phone sheet / controls keep clear of notch + home bar
local CTRL_BTN        = 48     -- px: + / − / Fit buttons
local ACTION_BTN_H    = 48     -- px: Allocate / Refund button
local SHEET_FRAC      = 0.35   -- phone bottom sheet height (fraction of the canvas)
local SHEET_MAX_BODY  = 600    -- SCREEN px: touch canvases shorter than this get the bottom sheet
local SIDE_W          = 320    -- px: desktop side panel width
-- Nodes scale with cell (diameter = NODE_SIZE * cell / DEFAULT_CELL), so the
-- touch zoom floor is the cell at which a 1.0× node is MIN_TAP_PX wide (≈51.3).
local MIN_CELL_TOUCH  = math.min(MAX_CELL, MIN_TAP_PX * DEFAULT_CELL / NODE_SIZE)
-- TalentClient.RefundNode is a warn() stub ("Individual refund disabled;
-- use RespecAll", Modules/TalentClient.lua). Flip this when the server
-- supports single-node refunds; until then Refund renders disabled with
-- the reason instead of a button that silently does nothing.
local INDIVIDUAL_REFUND_ENABLED = false

-- §AGX/UI-FIX: R5: gamepad canvas controls (only while the tree is the top
-- entry and the input is Gamepad). Right stick pans; RT / RB zoom in, LT /
-- LB zoom out (LB / RB only while the entry has no Tabs). Priority one
-- above GamepadNav's RD_UIScroll / RD_UITabs (High + 1), owner-guarded.
local CAS_PAD_PAN   = "RD_TalentPan"
local CAS_PAD_ZOOM  = "RD_TalentZoom"
local PAD_PRIORITY  = Enum.ContextActionPriority.High.Value + 2
local PAD_DEADZONE  = 0.2
local PAD_PAN_SPEED = 900    -- design px / s at full stick
local PAD_ZOOM_RATE = 4      -- ZOOM_STEP steps / s while a zoom button is held
-- §AGX/UI-P6: display only; the server charges 1 Respec Scroll or
-- PlayerDataConfig.RESPEC_COSTS.*.essence (§AGX/X42).
local RESPEC_ESSENCE = 25
local TOOLTIP_W      = 360   -- design px: desktop hover card

-- §AGX/UI-P6: every colour is a Theme role.
-- Node states: allocated = state.success, allocatable = accent.secondary
-- (blue body accent), origin / keystone = rarity.legendary (gold).

local nodeMap = TreeConfig.GetNodeMap()

-- ═══════════════════════════════════════════════════════════
-- ORGANIC LAYOUT  (precomputed once — deterministic)
-- ═══════════════════════════════════════════════════════════

local function hash01(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 1000003
	end
	return h / 1000003
end

-- §T10/U4: TRUE radial construction. The stored config x/y are IGNORED except to
-- anchor each branch's sector direction. Layout is computed from the
-- GRAPH: BFS depth from the Origin = ring radius; each branch (node
-- tag) owns an angular sector; siblings on a ring spread across the
-- sector ordered by their parents' angles (keeps limbs untangled).
-- Keystones are deepest, so they land on the outer rim by themselves.

local displayPos = {}  -- [id] = { x, y } in grid units

do
	-- Adjacency
	local adj = {}
	for _, ed in ipairs(TreeConfig.Edges) do   -- §AGX/UI-P6: not `e` (createElement)
		adj[ed[1]] = adj[ed[1]] or {}; table.insert(adj[ed[1]], ed[2])
		adj[ed[2]] = adj[ed[2]] or {}; table.insert(adj[ed[2]], ed[1])
	end

	local startId = TreeConfig.StartNodeId or "start"

	-- Global BFS: depth + parent for every node
	local depth, parent = { [startId] = 0 }, {}
	local queue, qi = { startId }, 1
	while qi <= #queue do
		local cur = queue[qi]; qi += 1
		for _, nb in ipairs(adj[cur] or {}) do
			if depth[nb] == nil then
				depth[nb]  = depth[cur] + 1
				parent[nb] = cur
				table.insert(queue, nb)
			end
		end
	end

	-- Branch of a node = its primary tag; untagged nodes inherit their
	-- parent's branch (start has none).
	local branchOf = {}
	local function resolveBranch(id)
		if branchOf[id] ~= nil then return branchOf[id] end
		local node = nodeMap[id]
		local b = (node and node.tags and node.tags[1]) or nil
		if not b and parent[id] then
			b = resolveBranch(parent[id])
		end
		branchOf[id] = b or "misc"
		return branchOf[id]
	end

	-- Collect branches + their sector CENTER angle from the config
	-- centroid (keeps each branch roughly where you authored it: Warpath
	-- stays upper-left, etc.), then space sectors evenly by rank so they
	-- can't overlap.
	local branchList, branchSeen = {}, {}
	for _, node in ipairs(TreeConfig.Nodes) do
		if node.id ~= startId then
			local b = resolveBranch(node.id)
			if not branchSeen[b] then
				branchSeen[b] = { sumX = 0, sumY = 0, n = 0 }
				table.insert(branchList, b)
			end
			local s = branchSeen[b]
			s.sumX += node.x; s.sumY += node.y; s.n += 1
		end
	end
	for _, b in ipairs(branchList) do
		local s = branchSeen[b]
		s.centroidAngle = math.atan2(s.sumY / s.n, s.sumX / s.n)
	end
	table.sort(branchList, function(a, b)
		return branchSeen[a].centroidAngle < branchSeen[b].centroidAngle
	end)
	local sectorWidth = (2 * math.pi) / math.max(#branchList, 1)
	local sectorCenter = {}
	for rank, b in ipairs(branchList) do
		-- Even spacing, phase-anchored to the first branch's centroid.
		sectorCenter[b] = branchSeen[branchList[1]].centroidAngle
			+ (rank - 1) * sectorWidth
	end

	-- Group nodes per branch per depth
	local rings = {}  -- rings[branch][depth] = { id, ... }
	for _, node in ipairs(TreeConfig.Nodes) do
		if node.id ~= startId and depth[node.id] then
			local b = resolveBranch(node.id)
			rings[b] = rings[b] or {}
			rings[b][depth[node.id]] = rings[b][depth[node.id]] or {}
			table.insert(rings[b][depth[node.id]], node.id)
		end
	end

	-- Place: per branch, walk depths outward; slot each ring's nodes
	-- across the sector, ordered by their parent's placed angle (falling
	-- back to id for determinism). Parent-following keeps limbs coherent.
	local placedAngle = { [startId] = 0 }
	displayPos[startId] = { x = 0, y = 0 }

	for _, b in ipairs(branchList) do
		local byDepth = rings[b]
		if not byDepth then continue end
		local center = sectorCenter[b] or 0
		local half   = sectorWidth * SECTOR_FILL / 2
		local depths = {}
		for d in pairs(byDepth) do table.insert(depths, d) end
		table.sort(depths)

		for _, d in ipairs(depths) do
			local ids = byDepth[d]
			table.sort(ids, function(a, c)
				local pa = placedAngle[parent[a]] or 0
				local pc = placedAngle[parent[c]] or 0
				if pa ~= pc then return pa < pc end
				return a < c
			end)
			local n = #ids
			for i, id in ipairs(ids) do
				local t = (n == 1) and 0.5 or (i - 0.5) / n
				local angle = center + (t - 0.5) * 2 * half
					+ (hash01(id .. "@a") - 0.5) * 2 * ANGLE_JITTER
				local radius = RING_START + (d - 1) * RING_STEP
					+ (hash01(id .. "@r") - 0.5) * 2 * RING_JITTER
				placedAngle[id] = angle
				displayPos[id] = {
					x = math.cos(angle) * radius,
					y = math.sin(angle) * radius,
				}
			end
		end
	end

	-- Safety: any node unreachable from start (validator flags these
	-- anyway) still gets drawn — at its config position, dimly correct.
	for _, node in ipairs(TreeConfig.Nodes) do
		if not displayPos[node.id] then
			displayPos[node.id] = { x = node.x, y = node.y }
		end
	end
end

-- §AGX/UI-P2: layout bounds (grid units, padded by the largest node
-- radius) for "fit"; adjacency for the detail panel's prerequisites.
local LAYOUT_BOUNDS
do
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, p in pairs(displayPos) do
		minX = math.min(minX, p.x); maxX = math.max(maxX, p.x)
		minY = math.min(minY, p.y); maxY = math.max(maxY, p.y)
	end
	if minX == math.huge then minX, maxX, minY, maxY = 0, 0, 0, 0 end
	local r = (NODE_SIZE * 1.7 / 2) / DEFAULT_CELL
	LAYOUT_BOUNDS = { minX = minX - r, maxX = maxX + r, minY = minY - r, maxY = maxY + r }
end
local adjacency = TreeConfig.GetAdjacencyList()
local START_ID  = TreeConfig.StartNodeId or "start"

-- §AGX/UI-P6: touch = useFormFactor().isTouch; text floors come from
-- Text / Theme.typeFor.

-- ═══════════════════════════════════════════════════════════
-- BRANCH TINTS  (from node tags — deterministic hue per branch)
-- ═══════════════════════════════════════════════════════════

local branchTintCache = {}
local function branchTint(node)
	local tag = node.tags and node.tags[1]
	if not tag then return R.state.locked end
	local cached = branchTintCache[tag]
	if cached then return cached end
	local hue = hash01(tag)
	local tint = Color3.fromHSV(hue, 0.55, 0.85)
	branchTintCache[tag] = tint
	return tint
end

local function dimTint(color, f)
	return Color3.new(color.R * f, color.G * f, color.B * f)
end

-- ── Node visuals ──────────────────────────────────────────────────────────────
local function getNodeFill(node, isAllocated, isAllocatable)
	if node.x == 0 and node.y == 0 then return R.rarity.legendary end
	if isAllocated then return R.state.success end
	if isAllocatable then return dimTint(branchTint(node), 0.55) end
	return dimTint(branchTint(node), 0.28)  -- locked: faint branch identity
end

local function getNodeRing(node, isAllocated, isAllocatable)
	if node.type == "keystone" then return R.rarity.legendary end
	if isAllocated then return R.state.success end
	if isAllocatable then return R.accent.secondary end
	return dimTint(branchTint(node), 0.6)
end

local function getNodeSizeMultiplier(node)
	if node.x == 0 and node.y == 0 then return 1.7 end
	if node.type == "keystone" then return 1.45 end
	if node.type == "notable"  then return 1.2  end
	return 1.0
end

-- ═══════════════════════════════════════════════════════════
-- TalentNode
-- ═══════════════════════════════════════════════════════════

local function TalentNode(props)
	local node          = props.nodeDef
	local isAllocated   = props.isAllocated
	local isAllocatable = props.isAllocatable
	local canRefund     = props.canRefund
	local px            = props.px
	local py            = props.py
	local cell          = props.cell

	local sizeMul  = getNodeSizeMultiplier(node)
	local diameter = NODE_SIZE * (cell / DEFAULT_CELL) * sizeMul
	local showText = cell >= 30
	local isOrigin = node.x == 0 and node.y == 0

	return e("TextButton", {
		Name             = "Node_" .. tostring(node.id),   -- §AGX/UI-FIX: R5
		ref              = props.nodeRef,                  -- §AGX/UI-FIX: R5 (Origin only)
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.fromOffset(px, py),
		Size             = UDim2.fromOffset(diameter, diameter),
		BackgroundColor3 = getNodeFill(node, isAllocated, isAllocatable),
		BorderSizePixel  = 0,
		Text             = "",
		AutoButtonColor  = isAllocatable or canRefund,
		ZIndex           = 5,
		-- §AGX/UI-P2: D12 — Activated only SELECTS (parent decides; it also
		-- swallows taps that were really drags), so a tap never spends a point
		-- before the player can read the node.
		[React.Event.Activated] = function()
			props.onActivate(node)
		end,
		-- §AGX/UI-P2: a press that starts ON a node must still be able to pan
		-- / pinch, so forward it to the canvas gesture tracker (deduped there).
		[React.Event.InputBegan] = function(_, input)
			props.onPointerBegan(input)
		end,
		[React.Event.MouseEnter] = function()
			if props.onHover then props.onHover(node) end
		end,
		[React.Event.MouseLeave] = function()
			if props.onLeave then props.onLeave() end
		end,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
		stroke = e("UIStroke", {
			Color     = getNodeRing(node, isAllocated, isAllocatable),
			Thickness = (node.type == "keystone" and 3 or 2) * math.max(cell / DEFAULT_CELL, 0.7),
		}),
		-- Allocatable pulse ring (second stroke, brighter)
		glow = isAllocatable and e("UIStroke", {
			Color        = R.accent.secondary,
			Thickness    = 1,
			Transparency = 0.35,
		}) or nil,
		-- §AGX/UI-P2, §AGX/UI-P6: selection halo (focus role, blue) so the player
		-- sees which node the detail panel describes.
		selRing = props.isSelected and e("Frame", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			Size                   = UDim2.new(1, 10, 1, 10),
			BackgroundTransparency = 1,
			ZIndex                 = 5,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
			stroke = e("UIStroke", { Color = R.border.focus, Thickness = Theme.Stroke.focus }),
		}) or nil,
		-- §AGX/UI-P6: Text fit (label style floor/ceiling) replaces TextScaled.
		label = showText and e(Text, {
			style       = "label",
			text        = string.sub(node.name, 1, 5),
			color       = isOrigin and "text.onAccent" or "text.primary",
			align       = "center",
			fit         = true,
			anchorPoint = Vector2.new(0.5, 0.5),
			position    = UDim2.fromScale(0.5, 0.5),
			size        = UDim2.fromScale(0.85, 0.85),
			zIndex      = 6,
		}) or nil,
	})
end

-- ═══════════════════════════════════════════════════════════
-- EdgeLine  (two-layer: soft shadow under a bright core)
-- ═══════════════════════════════════════════════════════════

local function EdgeLine(props)
	local dx = props.x2 - props.x1
	local dy = props.y2 - props.y1
	local length = math.sqrt(dx * dx + dy * dy)
	local angle  = math.deg(math.atan2(dy, dx))
	local midX   = (props.x1 + props.x2) / 2
	local midY   = (props.y1 + props.y2) / 2
	local thick  = props.thickness or 3

	return e(React.Fragment, nil, {
		shadow = e("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = UDim2.fromOffset(midX, midY),
			Size             = UDim2.fromOffset(length, thick + 3),
			BackgroundColor3 = R.surface.sunken,
			BorderSizePixel  = 0,
			Rotation         = angle,
			ZIndex           = 2,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
		}),
		core = e("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = UDim2.fromOffset(midX, midY),
			Size             = UDim2.fromOffset(length, thick),
			BackgroundColor3 = props.color or R.border.subtle,
			BackgroundTransparency = props.transparency or 0,
			BorderSizePixel  = 0,
			Rotation         = angle,
			ZIndex           = 3,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- Node text helpers  (§AGX/UI-P2: shared by Tooltip + NodeDetail)
-- ═══════════════════════════════════════════════════════════

local function effectLines(node)
	local lines = {}
	for _, eff in ipairs(node.effects or {}) do
		local label = eff.stat or eff.primary or "?"
		if eff.rule then
			table.insert(lines, "★ " .. label .. " (passive)")
		elseif eff.value ~= nil then
			local sign = eff.value >= 0 and "+" or ""
			table.insert(lines, sign .. tostring(eff.value) .. " " .. label)
		end
	end
	return lines
end

local function nodeHeader(node)
	local branch = node.tags and node.tags[1]
	local header = node.name .. "  [" .. string.upper(node.type or "") .. "]"
	if branch then header = header .. "  ·  " .. branch end
	return header, branch
end

local function costText(node)
	local cost = node.cost or 1
	if cost <= 0 then return "Free" end
	return "Cost: " .. cost .. (cost == 1 and " point" or " points")
end

-- Talents unlock when ANY adjacent talent is allocated
-- (TalentClient.GetAllocatableNodes), so "prerequisites" = linked nodes.
local function prereqText(nodeId, allocated)
	local names, extra = {}, 0
	for _, nb in ipairs(adjacency[nodeId] or {}) do
		local def = nodeMap[nb]
		if def then
			if #names < 4 then
				table.insert(names, def.name .. (allocated[nb] and " ✓" or ""))
			else
				extra += 1
			end
		end
	end
	if #names == 0 then return "Requires: none" end
	local s = "Requires any one of: " .. table.concat(names, ", ")
	if extra > 0 then s = s .. " +" .. extra .. " more" end
	return s
end

-- ═══════════════════════════════════════════════════════════
-- NodeTooltip  (desktop hover only; touch uses NodeDetail)
-- §AGX/UI-P2, §AGX/UI-P6: not Common/Tooltip (that is the text bubble);
-- Panel + Text, design px, auto height, bottom-centre of the canvas.
-- ═══════════════════════════════════════════════════════════

local function NodeTooltip(props)
	local node = props.nodeDef
	if not node then return nil end

	local lines = effectLines(node)
	local header, branch = nodeHeader(node)

	return e(Panel, {
		name        = "NodeTooltip",
		elevation   = "raised",
		padding     = "md",
		layout      = "vertical",
		gap         = "xs",
		accent      = branch and branchTint(node) or "border.focus",
		anchorPoint = Vector2.new(0.5, 1),
		position    = UDim2.new(0.5, 0, 1, -SP.lg),
		size        = UDim2.fromOffset(TOOLTIP_W, 0),
		autoSize    = "Y",
		zIndex      = 20,
	}, {
		nameLbl = e(Text, {
			style = "label", text = header, layoutOrder = 1, zIndex = 21,
		}),
		descLbl = (node.description or "") ~= "" and e(Text, {
			style = "caption", text = node.description, color = "text.secondary",
			wrap = true, layoutOrder = 2, zIndex = 21,
		}) or nil,
		effectsLbl = #lines > 0 and e(Text, {
			style = "caption", text = table.concat(lines, "\n"), color = "state.success",
			wrap = true, layoutOrder = 3, zIndex = 21,
		}) or nil,
		costLbl = e(Text, {
			style = "caption", color = "text.secondary", wrap = true, layoutOrder = 4, zIndex = 21,
			-- §AGX/UI-P2: D12 — a click never spends; say how to allocate.
			text = costText(node) .. "   ·   Click: details   Double-click: allocate",
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- NodeDetail  (§AGX/UI-P2, §AGX/UI-P6: D12 selection panel)
--   mode "sheet": phone bottom sheet (~35% of the canvas, EDGE_INSET
--                 clear of the edges), info left, actions right.
--   mode "side":  desktop / tablet side panel on the right.
--   Always a 48 px action button; disabled buttons carry the reason.
--   Panel + scrolling Text column + Button (Allocate = primary
--   CTA, Refund = danger, disabled = locked) + IconButton close.
-- ═══════════════════════════════════════════════════════════

local function NodeDetail(props)
	local node   = props.nodeDef
	local status = props.status
	local isSheet = props.mode == "sheet"

	local header, branch = nodeHeader(node)
	local lines = effectLines(node)
	local body = node.description or ""
	if #lines > 0 then
		body = body .. (body ~= "" and "\n" or "") .. table.concat(lines, "   ")
	end
	local metaText = costText(node) .. "   ·   " .. prereqText(node.id, props.allocated)

	local actionBtn = e(Button, {
		name        = "NodeAction",
		variant     = (not status.enabled) and "locked"
			or (status.action == "refund" and "danger" or "primary"),
		size        = "md",   -- 48 design px (ACTION_BTN_H)
		width       = UDim.new(1, 0),
		label       = status.label,
		anchorPoint = Vector2.new(1, 1),
		position    = UDim2.fromScale(1, 1),
		zIndex      = 33,
		onActivated = status.enabled and function() props.onAction(status.action) end or nil,
	})

	local closeBtn = e(IconButton, {
		name        = "DetailClose",
		icon        = "close",
		variant     = "ghost",
		size        = "sm",   -- 44
		anchorPoint = Vector2.new(1, 0),
		position    = UDim2.fromScale(1, 0),
		zIndex      = 33,
		tooltip     = "Close details",
		onActivated = function() props.onClose() end,
	})

	-- Info column: scrolls when the text is longer than the panel.
	local info = e("ScrollingFrame", {
		Name                   = "Info",
		Size                   = isSheet and UDim2.new(1, -182, 1, 0)
			or UDim2.new(1, 0, 1, -(ACTION_BTN_H + SP.sm)),
		BackgroundTransparency = 1,
		BorderSizePixel        = 0,
		CanvasSize             = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize    = Enum.AutomaticSize.Y,
		ScrollingDirection     = Enum.ScrollingDirection.Y,
		ScrollBarThickness     = Theme.Metrics.scrollBar,
		ScrollBarImageColor3   = R.text.secondary,
		ZIndex                 = 31,
	}, {
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0, SP.xs),
		}),
		name = e(Text, {
			style = "label", text = header, layoutOrder = 1, zIndex = 32,
			-- leave room for the close button in the side panel
			size = UDim2.new(1, isSheet and 0 or -(Theme.Metrics.iconButton.sm + SP.xs), 0, 22),
		}),
		meta = e(Text, {
			style = "caption", text = metaText, color = "accent.secondary",
			wrap = true, layoutOrder = 2, zIndex = 32,
		}),
		desc = body ~= "" and e(Text, {
			style = "caption", text = body, color = "text.secondary",
			wrap = true, layoutOrder = 3, zIndex = 32,
		}) or nil,
		reason = status.reason and e(Text, {
			style = "caption", text = status.reason, color = "state.warning",
			wrap = true, layoutOrder = 4, zIndex = 32,
		}) or nil,
	})

	local children = {}

	if isSheet then
		-- info column | action column (close on top, 48 px action at bottom)
		children.info = info
		children.actions = e("Frame", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 170, 1, 0), BackgroundTransparency = 1, ZIndex = 31,
		}, { close = closeBtn, action = actionBtn })
	else
		children.info   = info
		children.close  = closeBtn
		children.action = actionBtn
	end

	-- Panel has no ref prop: the outer Frame carries panelRef (overlay hit test).
	local frameProps = {
		Name                   = "NodeDetail",
		BackgroundTransparency = 1,
		Active                 = true,   -- sink presses so they don't pan the canvas behind
		ZIndex                 = 30,
		ref                    = props.panelRef,
	}
	if isSheet then
		frameProps.AnchorPoint = Vector2.new(0.5, 1)
		frameProps.Position    = UDim2.new(0.5, 0, 1, -EDGE_INSET)
		frameProps.Size        = UDim2.new(1, -2 * EDGE_INSET, SHEET_FRAC, 0)
	else
		frameProps.AnchorPoint = Vector2.new(1, 0)
		frameProps.Position    = UDim2.new(1, -SP.lg, 0, SP.lg)
		frameProps.Size        = UDim2.new(0, SIDE_W, 0.62, 0)
	end

	return e("Frame", frameProps, {
		minSize = e("UISizeConstraint", {
			MinSize = isSheet and Vector2.new(0, 116) or Vector2.new(0, 300),
		}),
		panel = e(Panel, {
			elevation = "raised",
			padding   = "md",
			radius    = "lg",
			accent    = branch and branchTint(node) or "border.focus",
			zIndex    = 30,
		}, children),
	})
end

-- ═══════════════════════════════════════════════════════════
-- TalentTreeUI  (root)
-- ═══════════════════════════════════════════════════════════

local function TalentTreeUI(props)
	local onClose = props.onClose

	-- §AGX/UI-P2, §AGX/UI-P6: per-render touch check = useFormFactor().isTouch
	-- (Phone / Tablet); hooks unconditional.
	local ff = useFormFactor()
	local uiScale = UIScaleRoot.useUIScale()
	local isTouch = ff.isTouch == true
	-- §AGX/UI-P6: screen px -> design px inside the body's UIScaleRoot.Local.
	local scaleRef = React.useRef(uiScale.target)
	scaleRef.current = uiScale.target
	local minCell = isTouch and MIN_CELL_TOUCH or MIN_CELL

	local talentState, setTalentState = React.useState(TalentClient.GetState())
	local hoveredNode, setHoveredNode = React.useState(nil)
	local selectedId, setSelectedId   = React.useState(nil)  -- §AGX/UI-P2: D12 selection

	-- Pan
	local dragOffset, setDragOffset   = React.useState(Vector2.new(0, 0))
	local latestDragOffset  = React.useRef(Vector2.new(0, 0))

	-- Zoom. §T10/U2, §AGX/UI-P2: start at the touch floor so the first
	-- frame never draws sub-44 px nodes on touch; fitView() runs on mount.
	local cell, setCell = React.useState(isTouch and MIN_CELL_TOUCH or DEFAULT_CELL)
	local cellRef       = React.useRef(isTouch and MIN_CELL_TOUCH or DEFAULT_CELL)
	local minCellRef    = React.useRef(minCell)
	minCellRef.current  = minCell

	local canvasRef = React.useRef(nil)
	local canvasSize, setCanvasSize = React.useState(Vector2.new(1200, 800))
	local canvasSizeRef = React.useRef(Vector2.new(1200, 800))

	-- §AGX/UI-P2: overlays that must not start a pan when pressed.
	local controlsRef = React.useRef(nil)
	local panelRef    = React.useRef(nil)

	-- §AGX/UI-P2: gesture state (mouse drag, one-finger pan, pinch, tap guard).
	local gesture = React.useRef({
		touches       = {},        -- ordered { { input = InputObject, pos = Vector2 } }
		panInput      = nil,       -- InputObject driving the pan (MouseButton1 or a Touch)
		panStart      = Vector2.new(0, 0),
		offsetAtStart = Vector2.new(0, 0),
		moved         = 0,         -- max px from the press point this gesture
		tapBlocked    = false,     -- true once the gesture became a drag / pinch
		releasedAt    = 0,
		pinchDist     = nil,
		pinchCell     = nil,
		pinchMid      = nil,
	})
	local lastClick = React.useRef({ id = nil, t = 0 })
	local hasFitted = React.useRef(false)

	-- ── §AGX/UI-P2: view helpers (read refs only, so the []-dep effects
	--    below can safely hold the first render's closures) ─────────────
	local function setOffset(off)
		latestDragOffset.current = off
		setDragOffset(off)
	end

	local function setView(newCell, newOff)
		cellRef.current = newCell
		setCell(newCell)
		setOffset(newOff)
	end

	-- Zoom to targetCell keeping the canvas-local point `anchor` fixed.
	local function zoomAbout(targetCell, anchor)
		local old = cellRef.current
		local newCell = math.clamp(targetCell, minCellRef.current, MAX_CELL)
		if math.abs(newCell - old) < 1e-3 then return end
		local cs   = canvasSizeRef.current
		local base = Vector2.new(cs.X * CENTER_X, cs.Y * CENTER_Y)
		local off  = latestDragOffset.current
		local k    = newCell / old
		setView(newCell, anchor - base - (anchor - base - off) * k)
	end

	-- Fit the whole ring layout; if even the zoom floor can't fit it
	-- (true for the 301-node web on every screen), centre on the Origin
	-- at the floor instead of on the bounds centre.
	local function fitView()
		local cs = canvasSizeRef.current
		local b  = LAYOUT_BOUNDS
		local spanX = math.max(b.maxX - b.minX, 1)
		local spanY = math.max(b.maxY - b.minY, 1)
		local rawFit = math.min((cs.X - 2 * FIT_PAD) / spanX, (cs.Y - 2 * FIT_PAD) / spanY)
		local newCell = math.clamp(rawFit, minCellRef.current, MAX_CELL)
		local cx, cy = (b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2
		if newCell > rawFit + 1e-3 then cx, cy = 0, 0 end
		setView(newCell, Vector2.new(
			cs.X * (0.5 - CENTER_X) - cx * newCell,
			cs.Y * (0.5 - CENTER_Y) - cy * newCell
		))
	end

	-- Input positions are inset-relative; AbsolutePosition of a ScreenGui
	-- with IgnoreGuiInset is screen-relative. Convert before comparing.
	local function toGui(pos)
		local canvas = canvasRef.current
		local sg = canvas and canvas:FindFirstAncestorWhichIsA("ScreenGui")
		if sg and sg.IgnoreGuiInset then
			local inset = GuiService:GetGuiInset()
			return pos + inset
		end
		return pos
	end

	local function toCanvasLocal(pos)
		local canvas = canvasRef.current
		if not canvas then return UIScaleRoot.toLocal(pos, scaleRef.current) end
		-- §AGX/UI-P6: screen px -> design px
		return UIScaleRoot.toLocal(toGui(pos) - canvas.AbsolutePosition, scaleRef.current)
	end

	local function isInside(gui, pos)
		if not gui then return false end
		local p  = toGui(pos)
		local ap = gui.AbsolutePosition
		local as = gui.AbsoluteSize
		return p.X >= ap.X and p.X <= ap.X + as.X and p.Y >= ap.Y and p.Y <= ap.Y + as.Y
	end

	local function isOverOverlay(pos)
		return isInside(controlsRef.current, pos) or isInside(panelRef.current, pos)
	end

	local function touchIndex(input)
		for i, t in ipairs(gesture.current.touches) do
			if t.input == input then return i end
		end
		return nil
	end

	local function startPan(input, pos)
		local g = gesture.current
		g.panInput      = input
		g.panStart      = pos
		g.offsetAtStart = latestDragOffset.current
	end

	local function startPinch()
		local g = gesture.current
		local a, b = g.touches[1].pos, g.touches[2].pos
		g.pinchDist  = math.max((a - b).Magnitude, 1)
		g.pinchCell  = cellRef.current
		g.pinchMid   = (a + b) / 2
		g.panInput   = nil
		g.tapBlocked = true
	end

	local function trackPan(pos)
		local g = gesture.current
		local delta = pos - g.panStart
		g.moved = math.max(g.moved, delta.Magnitude)
		if g.moved > TAP_SLOP then g.tapBlocked = true end   -- screen px
		setOffset(g.offsetAtStart + UIScaleRoot.toLocal(delta, scaleRef.current))  -- §AGX/UI-P6
	end

	-- Press on the canvas or on a node (both call this; deduped).
	local function onPointerBegan(input)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
		local g   = gesture.current
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if t == Enum.UserInputType.MouseButton1 then
			if g.panInput == input then return end
			if isOverOverlay(pos) then return end
			g.moved, g.tapBlocked = 0, false
			startPan(input, pos)
			return
		end
		-- Touch: prune fingers whose End we somehow missed.
		for i = #g.touches, 1, -1 do
			local st = g.touches[i].input.UserInputState
			if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
				table.remove(g.touches, i)
			end
		end
		if touchIndex(input) then return end
		if isOverOverlay(pos) then return end
		table.insert(g.touches, { input = input, pos = pos })
		if #g.touches == 1 then
			g.moved, g.tapBlocked = 0, false
			g.pinchDist = nil
			startPan(input, pos)
		elseif #g.touches == 2 then
			startPinch()
		end
	end

	React.useEffect(function()
		local unsub = TalentClient.Subscribe(function(newState)
			setTalentState({
				allocatedNodes  = newState.allocatedNodes,
				pointsSpent     = newState.pointsSpent,
				pointsTotal     = newState.pointsTotal,
				pointsAvailable = newState.pointsAvailable,
			})
		end)
		return function()
			if unsub then unsub() end
		end
	end, {})

	React.useEffect(function()
		local g = gesture.current
		local moveConn = UserInputService.InputChanged:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseMovement then
				local pi = g.panInput
				if pi and pi.UserInputType == Enum.UserInputType.MouseButton1 then
					trackPan(Vector2.new(input.Position.X, input.Position.Y))
				end
			elseif t == Enum.UserInputType.Touch then
				-- §AGX/UI-P2: M17 — touch drag pans.
				local i = touchIndex(input)
				if not i then return end
				local pos = Vector2.new(input.Position.X, input.Position.Y)
				g.touches[i].pos = pos
				if #g.touches >= 2 and g.pinchDist then
					local a, b = g.touches[1].pos, g.touches[2].pos
					local mid  = (a + b) / 2
					local lastMid = g.pinchMid or mid
					g.pinchMid = mid
					zoomAbout(g.pinchCell * (a - b).Magnitude / g.pinchDist, toCanvasLocal(mid))
					-- two-finger pan (§AGX/UI-P6: screen -> design px)
					setOffset(latestDragOffset.current + UIScaleRoot.toLocal(mid - lastMid, scaleRef.current))
				elseif g.panInput == input then
					trackPan(pos)
				end
			elseif t == Enum.UserInputType.MouseWheel then
				-- Zoom only while the cursor is over the canvas
				local canvas = canvasRef.current
				local pos = Vector2.new(input.Position.X, input.Position.Y)
				if canvas and isInside(canvas, pos) then
					-- §AGX/UI-P2: zoom about the cursor, clamped via zoomAbout
					zoomAbout(cellRef.current + input.Position.Z * WHEEL_STEP, toCanvasLocal(pos))
				end
			end
		end)

		local endConn = UserInputService.InputEnded:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 then
				local pi = g.panInput
				if pi and pi.UserInputType == Enum.UserInputType.MouseButton1 then
					g.panInput   = nil
					g.releasedAt = os.clock()
				end
			elseif t == Enum.UserInputType.Touch then
				local i = touchIndex(input)
				if not i then return end
				table.remove(g.touches, i)
				g.pinchDist = nil
				if #g.touches >= 2 then
					startPinch()
				elseif #g.touches == 1 then
					-- pinch → pan hand-off: re-base on the remaining finger
					local r = g.touches[1]
					startPan(r.input, r.pos)
				else
					g.panInput   = nil
					g.releasedAt = os.clock()
				end
			end
		end)

		return function()
			moveConn:Disconnect()
			endConn:Disconnect()
		end
	end, {})

	-- §AGX/UI-P2: track canvas size (rotation / window resize) and fit
	-- the layout once, as soon as the real size is known.
	React.useEffect(function()
		local canvas = canvasRef.current
		if not canvas then return nil end
		local alive = true
		local function measure()
			if not alive then return end
			local s = canvas.AbsoluteSize
			if s.X < 2 or s.Y < 2 then return end
			-- §AGX/UI-P6: AbsoluteSize is screen px; the view math is design px.
			local v = UIScaleRoot.toLocal(Vector2.new(s.X, s.Y), scaleRef.current)
			canvasSizeRef.current = v
			setCanvasSize(v)
			if not hasFitted.current then
				hasFitted.current = true
				fitView()
			end
		end
		local conn = canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
		task.defer(measure)
		return function()
			alive = false
			conn:Disconnect()
		end
	end, { uiScale.target })   -- §AGX/UI-P6: re-measure when the uiScale changes

	-- §AGX/UI-FIX: R5: gamepad first focus = the Origin node (always at
	-- the view centre when the tree opens), never the header Respec.
	local originRef = React.useRef(nil)
	useFirstFocus(originRef)

	-- §AGX/UI-FIX: R5: gamepad pan / zoom while the tree is top.
	local gamepad = GamepadFocus.useGamepad()
	local entryCtx = React.useContext(EntryContext)
	local padOn = gamepad and (entryCtx == nil or entryCtx.top == true)
	local entryId = entryCtx and entryCtx.id or nil
	React.useEffect(function()
		if not padOn then return nil end
		local owner = {}
		local stick = Vector2.zero
		local zoomIn, zoomOut = false, false

		GamepadFocus.bindOwned(CAS_PAD_PAN, owner, function(_, state, input)
			-- Focus inside the detail panel: RD_UIScroll scrolls its text.
			local sel, panel = GuiService.SelectedObject, panelRef.current
			if sel and panel and sel:IsDescendantOf(panel) then
				stick = Vector2.zero
				return Enum.ContextActionResult.Pass
			end
			if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				stick = Vector2.zero
			else
				stick = Vector2.new(input.Position.X, input.Position.Y)
			end
			return Enum.ContextActionResult.Sink
		end, PAD_PRIORITY, Enum.KeyCode.Thumbstick2)

		GamepadFocus.bindOwned(CAS_PAD_ZOOM, owner, function(_, state, input)
			local k = input.KeyCode
			if k == Enum.KeyCode.ButtonL1 or k == Enum.KeyCode.ButtonR1 then
				-- LB / RB belong to the entry's Tabs when it has any.
				local canvas = canvasRef.current
				local entry = canvas and entryId and canvas:FindFirstAncestor(entryId)
				if entry and GamepadFocus.tabsIn(entry) then
					return Enum.ContextActionResult.Pass
				end
			end
			local held = state ~= Enum.UserInputState.End and state ~= Enum.UserInputState.Cancel
			if k == Enum.KeyCode.ButtonR2 or k == Enum.KeyCode.ButtonR1 then
				zoomIn = held
			else
				zoomOut = held
			end
			return Enum.ContextActionResult.Sink
		end, PAD_PRIORITY, Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR2,
			Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)

		local conn = RunService.Heartbeat:Connect(function(dt)
			local canvas = canvasRef.current
			if not canvas then return end
			local moved = false
			if stick.Magnitude >= PAD_DEADZONE then
				-- stick right / up looks right / up: the web moves left / down
				setOffset(latestDragOffset.current
					+ Vector2.new(-stick.X, stick.Y) * (PAD_PAN_SPEED * dt))
				moved = true
			end
			local z = (zoomIn and 1 or 0) - (zoomOut and 1 or 0)
			if z ~= 0 then
				zoomAbout(cellRef.current * ZOOM_STEP ^ (z * PAD_ZOOM_RATE * dt), canvasSizeRef.current / 2)
				moved = true
			end
			-- A node panned out of the clipped canvas can't stay focused.
			if moved then GamepadFocus.reselectInView(canvas) end
		end)

		return function()
			conn:Disconnect()
			GamepadFocus.unbindOwned(CAS_PAD_PAN, owner)
			GamepadFocus.unbindOwned(CAS_PAD_ZOOM, owner)
		end
	end, { padOn, entryId } :: { any })

	local allocated      = talentState.allocatedNodes or {}
	local pointsAvail    = talentState.pointsAvailable or 0
	local allocatableSet = {}
	for _, id in ipairs(TalentClient.GetAllocatableNodes()) do
		allocatableSet[id] = true
	end

	-- §AGX/UI-P2: render at no less than the platform floor (guards the
	-- frame before fitView and a touch/desktop flip).
	local renderCell = math.clamp(cell, minCell, MAX_CELL)
	-- §AGX/UI-P6: SHEET_MAX_BODY stays a SCREEN px threshold (canvasSize is
	-- design px), so tablets keep the side panel.
	local useSheet   = isTouch and canvasSize.Y * uiScale.target < SHEET_MAX_BODY

	-- Pixel projection of the ORGANIC coordinates
	local function toPixels(id)
		local p = displayPos[id]
		return canvasSize.X * CENTER_X + p.x * renderCell + dragOffset.X,
		       canvasSize.Y * CENTER_Y + p.y * renderCell + dragOffset.Y
	end

	-- §AGX/UI-P2: D12 — Allocate / Refund button state + disabled reason.
	local function nodeStatus(node)
		local id = node.id
		if id == START_ID then
			return { label = "Origin", enabled = false, reason = "Always allocated: every path starts here." }
		end
		if allocated[id] then
			if not TalentClient.CanRefund(id) then
				return { label = "Refund", enabled = false,
					reason = "Other talents depend on this one. Use Respec to reset." }
			end
			if not INDIVIDUAL_REFUND_ENABLED then
				return { label = "Refund", enabled = false,
					reason = "Single refunds are off. Use Respec (Scroll / " .. RESPEC_ESSENCE .. " Essence)." }
			end
			return { label = "Refund", enabled = true, action = "refund" }
		end
		local cost = node.cost or 1
		if allocatableSet[id] then
			return { label = cost == 1 and "Allocate (1 pt)" or ("Allocate (" .. cost .. " pts)"),
				enabled = true, action = "allocate" }
		end
		local connected = false
		for _, nb in ipairs(adjacency[id] or {}) do
			if allocated[nb] then connected = true; break end
		end
		if not connected then
			return { label = "Locked", enabled = false,
				reason = "Locked: allocate a linked talent first." }
		end
		return { label = "Allocate", enabled = false,
			reason = string.format("Not enough points (need %d, have %d).", cost, pointsAvail) }
	end

	-- §AGX/UI-P2: keep the selected node above the phone sheet.
	local function revealAboveSheet(id)
		local p  = displayPos[id]
		local cs = canvasSizeRef.current
		local off = latestDragOffset.current
		local y   = cs.Y * CENTER_Y + p.y * cellRef.current + off.Y
		local sheetTop = cs.Y * (1 - SHEET_FRAC) - EDGE_INSET
		local r = NODE_SIZE * (cellRef.current / DEFAULT_CELL)
		if y + r > sheetTop - 8 then
			setOffset(off + Vector2.new(0, sheetTop / 2 - y))
		end
	end

	-- §AGX/UI-P2: D12 tap/click handler. Drags never select; PC
	-- double-click on the same node allocates (speed path), a single
	-- click only selects.
	local function onNodeActivated(node)
		local g = gesture.current
		local pressing = g.panInput ~= nil or #g.touches > 0
		if g.tapBlocked and (pressing or os.clock() - g.releasedAt < TAP_GRACE_S) then
			return
		end
		local now = os.clock()
		local last = lastClick.current
		-- §AGX/UI-FIX: no double-A shortcut on gamepad — spending is only via
		-- the Allocate button (refund is off; respec costs Essence).
		if not isTouch and ff.input ~= "Gamepad" and last.id == node.id and now - last.t < DOUBLE_CLICK_S then
			lastClick.current = { id = nil, t = 0 }
			if allocatableSet[node.id] and not allocated[node.id] then
				TalentClient.AllocateNode(node.id)
			end
			return
		end
		lastClick.current = { id = node.id, t = now }
		setSelectedId(node.id)
		if useSheet then revealAboveSheet(node.id) end
	end

	local children = {}

	-- Edges (under nodes). Highlighting: allocated↔allocated = green,
	-- allocated↔allocatable = blue "next step", otherwise dim.
	for i, edge in ipairs(TreeConfig.Edges) do
		local n1 = nodeMap[edge[1]]
		local n2 = nodeMap[edge[2]]
		if n1 and n2 then
			local x1, y1 = toPixels(edge[1])
			local x2, y2 = toPixels(edge[2])

			local a1, a2 = allocated[edge[1]], allocated[edge[2]]
			-- §AGX/UI-P6: roles (dim = border.subtle, next = blue, active = green)
			local color, transparency = R.border.subtle, 0.25
			if a1 and a2 then
				color, transparency = R.state.success, 0
			elseif (a1 and allocatableSet[edge[2]]) or (a2 and allocatableSet[edge[1]]) then
				color, transparency = R.accent.secondary, 0.3
			end

			children["edge_" .. i] = e(EdgeLine, {
				x1 = x1, y1 = y1, x2 = x2, y2 = y2,
				color = color, transparency = transparency,
				thickness = math.max(2, 3 * renderCell / DEFAULT_CELL),
			})
		end
	end

	-- Nodes
	for _, node in ipairs(TreeConfig.Nodes) do
		local px, py = toPixels(node.id)
		children["node_" .. node.id] = e(TalentNode, {
			nodeDef       = node,
			isAllocated   = allocated[node.id] == true,
			isAllocatable = allocatableSet[node.id] == true,
			canRefund     = allocated[node.id] == true and TalentClient.CanRefund(node.id),
			isSelected    = selectedId == node.id,
			nodeRef       = (node.id == START_ID) and originRef or nil,   -- §AGX/UI-FIX: R5
			px = px, py = py, cell = renderCell,
			onActivate     = onNodeActivated,
			onPointerBegan = onPointerBegan,
			-- §AGX/UI-P2: hover tooltip is desktop-only (touch fires
			-- MouseEnter on tap; the detail panel covers touch).
			onHover       = function(nd) if not isTouch then setHoveredNode(nd) end end,
			onLeave       = function() setHoveredNode(nil) end,
		})
	end

	children.tooltip = e(NodeTooltip, { nodeDef = (not isTouch) and hoveredNode or nil })

	-- §T10/U3, §AGX/UI-P6: points counter + respec live in the standard header
	-- slot, inside AppWindow's scaled chrome (design px): numeric Text +
	-- danger Respec Button (44) + essence CurrencyPill.
	local avail = talentState.pointsAvailable or 0
	local headerContent = e("Frame", {
		Name                   = "TalentHeader",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		layout = e("UIListLayout", {
			FillDirection       = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment   = Enum.VerticalAlignment.Center,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Padding             = UDim.new(0, SP.sm),
		}),
		points = e(Text, {
			style       = "numeric",
			text        = string.format(
				"%d / %d  ·  %d free",
				talentState.pointsSpent or 0,
				talentState.pointsTotal or 0,
				avail
			),
			color       = avail > 0 and "accent.secondary" or "text.secondary",
			size        = UDim2.fromOffset(0, 24),
			autoSize    = "X",
			layoutOrder = 1,
		}),
		respecBtn = e(Button, {
			name        = "Respec",
			variant     = "danger",
			size        = "sm",
			label       = "Respec",
			layoutOrder = 2,
			tooltip     = "Resets every talent. Uses a Respec Scroll if you own one, otherwise Essence.",
			onActivated = function()
				TalentClient.RespecAll()
			end,
		}),
		respecCost = e(CurrencyPill, {
			currency = "essence", value = RESPEC_ESSENCE, cost = true, layoutOrder = 3,
		}),
	})

	local selectedNode = selectedId and nodeMap[selectedId] or nil
	local ctrlInset    = isTouch and EDGE_INSET or 12

	-- §AGX/UI-P2: platform wording (M17).
	local legendText = isTouch
		and "Tap = Select  |  Drag = Pan  |  Pinch = Zoom"
		or  "Click = Select  |  Double-click = Allocate  |  Drag = Pan  |  Scroll = Zoom"
	if gamepad then   -- §AGX/UI-FIX: R5 (gamepad only)
		legendText = "A = Select  |  Right stick = Pan  |  LT / RT = Zoom"
	end

	return e(AppWindow, {
		variant       = "fullscreen",
		title         = "Talent Tree",
		icon          = "talents",
		onClose       = onClose,
		headerContent = headerContent,
		zIndex        = 10,
	}, {
		-- §AGX/UI-P6: design px from here down (see header).
		content = e(UIScaleRoot.Local, { name = "TalentBody" }, {
			-- Soft vignette so the web feels lit from the Origin
			vignette = e("Frame", {
				Size                   = UDim2.fromScale(1, 1),
				BackgroundColor3       = R.surface.raised,
				BackgroundTransparency = 0.55,
				BorderSizePixel        = 0,
				ZIndex                 = 10,
			}, {
				grad = e("UIGradient", {
					Color = ColorSequence.new(R.surface.raised, R.surface.base),
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0,   1),
						NumberSequenceKeypoint.new(0.5, 0.75),
						NumberSequenceKeypoint.new(1,   0.35),
					}),
					Rotation = 90,
				}),
			}),

			-- (§T10/U3: header chrome — title, points, respec, close — lives in
			-- AppWindow; this table is the window BODY.)

			canvas = e("Frame", {
				Position               = UDim2.fromScale(0, 0),
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ClipsDescendants       = true,
				ZIndex                 = 11,
				ref                    = canvasRef,
				-- §AGX/UI-P2: shared tracker (mouse drag, touch pan, pinch).
				[React.Event.InputBegan] = function(_, input)
					onPointerBegan(input)
				end,
			}, children),

			-- §AGX/UI-P2, §AGX/UI-P6: + / − / Fit (48 design px, all platforms),
			-- top-left of the body; IconButton secondary (blue ring).
			zoomControls = e("Frame", {
				Position               = UDim2.fromOffset(ctrlInset, SP.md),
				Size                   = UDim2.fromOffset(CTRL_BTN, CTRL_BTN * 3 + 2 * SP.sm),
				BackgroundTransparency = 1,
				ZIndex                 = 25,
				ref                    = controlsRef,
			}, {
				layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder     = Enum.SortOrder.LayoutOrder,
					Padding       = UDim.new(0, SP.sm),
				}),
				zoomIn = e(IconButton, {
					name = "ZoomIn", icon = "plus", variant = "secondary", size = CTRL_BTN,
					layoutOrder = 1, zIndex = 26, tooltip = "Zoom in",
					onActivated = function()
						zoomAbout(cellRef.current * ZOOM_STEP, canvasSizeRef.current / 2)
					end,
				}),
				zoomOut = e(IconButton, {
					name = "ZoomOut", icon = "minus", variant = "secondary", size = CTRL_BTN,
					layoutOrder = 2, zIndex = 26, tooltip = "Zoom out",
					onActivated = function()
						zoomAbout(cellRef.current / ZOOM_STEP, canvasSizeRef.current / 2)
					end,
				}),
				fit = e(IconButton, {
					name = "Fit", icon = "fit", label = "Fit", variant = "secondary", size = CTRL_BTN,
					layoutOrder = 3, zIndex = 26, tooltip = "Fit the whole tree",
					onActivated = function() fitView() end,
				}),
			}),

			-- §AGX/UI-P2: D12 detail panel (sheet on phone, side panel otherwise).
			detail = selectedNode and e(NodeDetail, {
				nodeDef   = selectedNode,
				status    = nodeStatus(selectedNode),
				allocated = allocated,
				mode      = useSheet and "sheet" or "side",
				panelRef  = panelRef,
				onClose   = function() setSelectedId(nil) end,
				onAction  = function(action)
					if action == "allocate" then
						TalentClient.AllocateNode(selectedNode.id)
					elseif action == "refund" then
						TalentClient.RefundNode(selectedNode.id)
					end
				end,
			}) or nil,

			-- §AGX/UI-P2: hidden under an open phone sheet (it would sit behind it).
			legend = not (useSheet and selectedNode) and e(Panel, {
				name        = "Legend",
				elevation   = "flat",
				padding     = "sm",
				transparency = 0.3,
				anchorPoint = Vector2.new(0, 1),
				position    = UDim2.new(0, ctrlInset, 1, -SP.md),
				size        = UDim2.fromOffset(0, 32),
				autoSize    = "X",
				zIndex      = 15,
			}, {
				lbl = e(Text, {
					style    = "caption",
					text     = legendText,
					color    = "text.secondary",
					size     = UDim2.fromScale(0, 1),
					autoSize = "X",
					zIndex   = 16,
				}),
			}) or nil,
		}),
	})
end

return TalentTreeUI
