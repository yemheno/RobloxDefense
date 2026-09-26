-- UI/TalentTreeUI.lua
--[[
    React component: full-window talent tree viewer.  (§T10/U2 rework)

    WHY THE REWORK: the tree config lays branches out as rectangular
    grid blocks (rows × columns per branch), and the old renderer drew
    them verbatim — straight rows, uniform spacing, straight lines.
    "Blocks of talents, no tree feeling" (Pablo). This version keeps
    the CONFIG untouched and applies a deterministic ORGANIC TRANSFORM
    at render time:

      • polar re-projection around the Origin with per-node jitter
        (seeded from the node id — stable across sessions/clients)
      • radial bloom so inner rings breathe
      • per-branch color identity from node tags (hashed hue — any
        future branch gets its own tint automatically)
      • two-layer edges (shadow + core) with allocated / next-step
        highlighting, so paths read like limbs instead of wires
      • mouse-wheel zoom + background-drag pan

    Features kept from v1: node states, points counter, Respec All,
    hover tooltip, close button.

    §AGX/UI-P2 (mobile.md M17 / §2.6, UI_REVAMP D12): touch rework.
      • tap / click SELECTS a node → detail panel (bottom sheet on
        phone, side panel on desktop) with a 48 px Allocate / Refund
        button + disabled reason. A single click no longer spends
        (respec costs Essence). PC keeps hover tooltips and gets
        double-click = allocate for speed.
      • one-finger drag pans; a drag > TAP_SLOP px never counts as a tap
      • two-finger pinch zoom (clamped), + / − / Fit buttons (48 px)
      • opens fitted; on touch the zoom floor keeps nodes ≥ 44 px

    Architecture unchanged:
      Topology  ← TalentTreeConfig (ReplicatedStorage.Shared)
      State     ← TalentClient (subscribe pattern)
      Actions   → TalentClient (fire-and-forget → server responds)
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")  -- §AGX/UI-P2: map input coords → GUI space for zoom anchors
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local TalentClient   = require(SharedModules:WaitForChild("TalentClient"))
local TreeConfig     = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TalentTreeConfig"))
local AppWindow      = require(script.Parent:WaitForChild("Common"):WaitForChild("AppWindow"))  -- §T10/U3

-- ── Layout constants ──────────────────────────────────────────────────────────
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
local WHEEL_STEP      = 4      -- cell px per wheel notch (unchanged from v2)
local FIT_PAD         = 24     -- px margin around the layout when fitting
local EDGE_INSET      = 44     -- px: phone sheet / controls keep clear of notch + home bar
local CTRL_BTN        = 48     -- px: + / − / Fit buttons
local ACTION_BTN_H    = 48     -- px: Allocate / Refund button
local SHEET_FRAC      = 0.35   -- phone bottom sheet height (fraction of the canvas)
local SHEET_MAX_BODY  = 600    -- px: touch canvases shorter than this get the bottom sheet
local SIDE_W          = 320    -- px: desktop side panel width
-- Nodes scale with cell (diameter = NODE_SIZE * cell / DEFAULT_CELL), so the
-- touch zoom floor is the cell at which a 1.0× node is MIN_TAP_PX wide (≈51.3).
local MIN_CELL_TOUCH  = math.min(MAX_CELL, MIN_TAP_PX * DEFAULT_CELL / NODE_SIZE)
-- TalentClient.RefundNode is a warn() stub ("Individual refund disabled;
-- use RespecAll", Modules/TalentClient.lua). Flip this when the server
-- supports single-node refunds; until then Refund renders disabled with
-- the reason instead of a button that silently does nothing.
local INDIVIDUAL_REFUND_ENABLED = false

-- ── Palette ───────────────────────────────────────────────────────────────────
local C = {
	bg           = Color3.fromRGB( 12,  12,  18),
	panel        = Color3.fromRGB( 18,  18,  26),
	allocated    = Color3.fromRGB( 80, 210, 120),
	allocatable  = Color3.fromRGB(120, 180, 255),
	locked       = Color3.fromRGB( 55,  55,  70),
	keystone_bg  = Color3.fromRGB(200, 170,  50),
	origin_bg    = Color3.fromRGB(255, 220, 100),
	text         = Color3.fromRGB(220, 220, 230),
	text_dim     = Color3.fromRGB(140, 140, 160),
	line_shadow  = Color3.fromRGB( 22,  22,  34),
	line         = Color3.fromRGB( 45,  45,  65),
	line_next    = Color3.fromRGB( 70, 110, 170),
	line_active  = Color3.fromRGB( 60, 180, 100),
	btn_text     = Color3.fromRGB(105, 190, 255),
	btn_stroke   = Color3.fromRGB( 60, 100, 180),
	close_bg     = Color3.fromRGB(180,  50,  50),
	tooltip_bg   = Color3.fromRGB( 22,  22,  32),
}

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

-- §T10/U4: TRUE radial construction (Pablo: "reposition from scratch,
-- polar coordinates"). The stored config x/y are IGNORED except to
-- anchor each branch's sector direction. Layout is computed from the
-- GRAPH: BFS depth from the Origin = ring radius; each branch (node
-- tag) owns an angular sector; siblings on a ring spread across the
-- sector ordered by their parents' angles (keeps limbs untangled).
-- Keystones are deepest, so they land on the outer rim by themselves.

local displayPos = {}  -- [id] = { x, y } in grid units

do
	-- Adjacency
	local adj = {}
	for _, e in ipairs(TreeConfig.Edges) do
		adj[e[1]] = adj[e[1]] or {}; table.insert(adj[e[1]], e[2])
		adj[e[2]] = adj[e[2]] or {}; table.insert(adj[e[2]], e[1])
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

-- §AGX/UI-P2: local touch detection while FormFactor is mid-edit.
-- TODO(FormFactor): replace with useFormFactor().isTouch once Modules/FormFactor lands.
local function isTouchDevice()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- §AGX/UI-P2: M11 — every TextScaled label here gets a 12 px floor.
local function minText()
	return React.createElement("UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = 40 })
end

-- ═══════════════════════════════════════════════════════════
-- BRANCH TINTS  (from node tags — deterministic hue per branch)
-- ═══════════════════════════════════════════════════════════

local branchTintCache = {}
local function branchTint(node)
	local tag = node.tags and node.tags[1]
	if not tag then return C.locked end
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
	if node.x == 0 and node.y == 0 then return C.origin_bg end
	if isAllocated then return C.allocated end
	if isAllocatable then return dimTint(branchTint(node), 0.55) end
	return dimTint(branchTint(node), 0.28)  -- locked: faint branch identity
end

local function getNodeRing(node, isAllocated, isAllocatable)
	if node.type == "keystone" then return C.keystone_bg end
	if isAllocated then return C.allocated end
	if isAllocatable then return C.allocatable end
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

	return React.createElement("TextButton", {
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.fromOffset(px, py),
		Size             = UDim2.fromOffset(diameter, diameter),
		BackgroundColor3 = getNodeFill(node, isAllocated, isAllocatable),
		BorderSizePixel  = 0,
		Text             = "",
		AutoButtonColor  = isAllocatable or canRefund,
		ZIndex           = 5,
		-- §AGX/UI-P2: D12 — Activated only SELECTS (parent decides; it also
		-- swallows taps that were really drags). It used to allocate/refund
		-- immediately, spending a point before the player could read the node.
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
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		stroke = React.createElement("UIStroke", {
			Color     = getNodeRing(node, isAllocated, isAllocatable),
			Thickness = (node.type == "keystone" and 3 or 2) * math.max(cell / DEFAULT_CELL, 0.7),
		}),
		-- Allocatable pulse ring (second stroke, brighter)
		glow = isAllocatable and React.createElement("UIStroke", {
			Color        = C.allocatable,
			Thickness    = 1,
			Transparency = 0.35,
		}) or nil,
		-- §AGX/UI-P2: selection halo so the player sees which node the
		-- detail panel describes (palette colour, no re-skin).
		selRing = props.isSelected and React.createElement("Frame", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			Size                   = UDim2.new(1, 10, 1, 10),
			BackgroundTransparency = 1,
			ZIndex                 = 5,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			stroke = React.createElement("UIStroke", { Color = C.text, Thickness = 2 }),
		}) or nil,
		label = showText and React.createElement("TextLabel", {
			Size                   = UDim2.fromScale(0.85, 0.85),
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			Text                   = string.sub(node.name, 1, 5),
			TextColor3             = (node.x == 0 and node.y == 0) and C.bg or C.text,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			ZIndex                 = 6,
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

	return React.createElement(React.Fragment, nil, {
		shadow = React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = UDim2.fromOffset(midX, midY),
			Size             = UDim2.fromOffset(length, thick + 3),
			BackgroundColor3 = C.line_shadow,
			BorderSizePixel  = 0,
			Rotation         = angle,
			ZIndex           = 2,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		}),
		core = React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = UDim2.fromOffset(midX, midY),
			Size             = UDim2.fromOffset(length, thick),
			BackgroundColor3 = props.color or C.line,
			BackgroundTransparency = props.transparency or 0,
			BorderSizePixel  = 0,
			Rotation         = angle,
			ZIndex           = 3,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
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
-- Tooltip  (desktop hover only — §AGX/UI-P2: touch uses NodeDetail)
-- ═══════════════════════════════════════════════════════════

local function Tooltip(props)
	local node = props.nodeDef
	if not node then return nil end

	local lines = effectLines(node)
	local header, branch = nodeHeader(node)

	return React.createElement("Frame", {
		AnchorPoint      = Vector2.new(0.5, 0),
		Position         = UDim2.fromScale(0.5, 0.82),
		Size             = UDim2.fromScale(0.30, 0.16),
		BackgroundColor3 = C.tooltip_bg,
		BorderSizePixel  = 0,
		ZIndex           = 20,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.04, 0) }),
		stroke = React.createElement("UIStroke", {
			Color = branch and branchTint(node) or C.btn_stroke,
			Thickness = 1,
		}),
		pad = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0.02, 0), PaddingRight = UDim.new(0.02, 0),
			PaddingTop  = UDim.new(0.05, 0), PaddingBottom = UDim.new(0.05, 0),
		}),
		layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0.02, 0),
		}),
		nameLbl = React.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 0.28), BackgroundTransparency = 1,
			Text = header, TextColor3 = C.text,
			Font = Enum.Font.GothamBold, TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1,
		}, { minText = minText() }),  -- §AGX/UI-P2: M11 12 px floor
		descLbl = React.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 0.30), BackgroundTransparency = 1,
			Text = node.description or "", TextColor3 = C.text_dim,
			Font = Enum.Font.Gotham, TextScaled = true, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2,
		}, { minText = minText() }),  -- §AGX/UI-P2: M11 12 px floor
		effectsLbl = React.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 0.25), BackgroundTransparency = 1,
			Text = table.concat(lines, "\n"), TextColor3 = C.allocated,
			Font = Enum.Font.GothamBold, TextScaled = true, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3,
		}, { minText = minText() }),  -- §AGX/UI-P2: M11 12 px floor
		costLbl = React.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 0.15), BackgroundTransparency = 1,
			-- §AGX/UI-P2: D12 — a click no longer spends; say how to allocate.
			Text = costText(node) .. "   ·   Click: details   Double-click: allocate",
			TextColor3 = C.text_dim, Font = Enum.Font.Gotham, TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 4,
		}, { minText = minText() }),  -- §AGX/UI-P2: M11 12 px floor
	})
end

-- ═══════════════════════════════════════════════════════════
-- NodeDetail  (§AGX/UI-P2: D12 selection panel)
--   mode "sheet": phone bottom sheet (~35% of the canvas, EDGE_INSET
--                 clear of the edges), info left, actions right.
--   mode "side":  desktop / tablet side panel on the right.
--   Always a 48 px action button; disabled buttons carry the reason.
-- ═══════════════════════════════════════════════════════════

local function detailLabel(p)
	return React.createElement("TextLabel", {
		Size                   = p.size,
		BackgroundTransparency = 1,
		Text                   = p.text,
		TextColor3             = p.color or C.text,
		Font                   = p.font or Enum.Font.Gotham,
		TextScaled             = true,
		TextWrapped            = p.wrap == true,
		TextTruncate           = Enum.TextTruncate.AtEnd,
		TextXAlignment         = Enum.TextXAlignment.Left,
		TextYAlignment         = Enum.TextYAlignment.Top,
		LayoutOrder            = p.order,
		ZIndex                 = 32,
	}, { minText = minText() })  -- §AGX/UI-P2: M11 12 px floor
end

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

	local actionBtn = React.createElement("TextButton", {
		AnchorPoint      = Vector2.new(1, 1),
		Position         = UDim2.fromScale(1, 1),
		Size             = UDim2.new(1, 0, 0, ACTION_BTN_H),
		BackgroundColor3 = status.enabled and (status.action == "refund" and Color3.fromRGB(140, 50, 50) or C.allocated) or C.locked,
		BackgroundTransparency = status.enabled and 0 or 0.2,
		AutoButtonColor  = status.enabled,
		Active           = status.enabled,
		BorderSizePixel  = 0,
		Text             = status.label,
		TextColor3       = status.enabled and C.bg or C.text_dim,
		Font             = Enum.Font.GothamBold,
		TextScaled       = true,
		ZIndex           = 33,
		[React.Event.Activated] = function()
			if status.enabled then props.onAction(status.action) end
		end,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
		stroke = React.createElement("UIStroke", {
			Color = C.btn_stroke, Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		pad = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		}),
		minText = minText(),
	})

	local closeBtn = React.createElement("TextButton", {
		AnchorPoint      = Vector2.new(1, 0),
		Position         = UDim2.fromScale(1, 0),
		Size             = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.panel,
		BorderSizePixel  = 0,
		Text             = "×",
		TextColor3       = C.text_dim,
		Font             = Enum.Font.GothamBold,
		TextSize         = 24,
		ZIndex           = 33,
		[React.Event.Activated] = function() props.onClose() end,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
	})

	local reasonH = status.reason and 32 or 0

	local frameProps = {
		BackgroundColor3 = C.tooltip_bg,
		BorderSizePixel  = 0,
		Active           = true,   -- sink presses so they don't pan the canvas behind
		ZIndex           = 30,
		ref              = props.panelRef,
	}
	if isSheet then
		frameProps.AnchorPoint = Vector2.new(0.5, 1)
		frameProps.Position    = UDim2.new(0.5, 0, 1, -EDGE_INSET)
		frameProps.Size        = UDim2.new(1, -2 * EDGE_INSET, SHEET_FRAC, 0)
	else
		frameProps.AnchorPoint = Vector2.new(1, 0)
		frameProps.Position    = UDim2.new(1, -16, 0, 16)
		frameProps.Size        = UDim2.new(0, SIDE_W, 0.62, 0)
	end

	local infoChildren = {
		layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0, 4),
		}),
		name = detailLabel({
			size = UDim2.new(1, isSheet and 0 or -48, 0, 22), text = header,
			font = Enum.Font.GothamBold, order = 1,
		}),
		meta = detailLabel({
			size = UDim2.new(1, 0, 0, isSheet and 16 or 34), text = metaText,
			color = C.btn_text, wrap = not isSheet, order = 2,
		}),
		desc = detailLabel({
			size = UDim2.new(1, 0, 1, -(22 + (isSheet and 16 or 34) + reasonH + 12)),
			text = body, color = C.text_dim, wrap = true, order = 3,
		}),
		reason = status.reason and detailLabel({
			size = UDim2.new(1, 0, 0, reasonH - 4), text = status.reason,
			color = C.keystone_bg, wrap = true, order = 4,
		}) or nil,
	}

	local children = {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
		stroke = React.createElement("UIStroke", {
			Color = branch and branchTint(node) or C.btn_stroke, Thickness = 1,
		}),
		pad = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
			PaddingTop  = UDim.new(0, 8),  PaddingBottom = UDim.new(0, 8),
		}),
		size = React.createElement("UISizeConstraint", {
			MinSize = isSheet and Vector2.new(0, 116) or Vector2.new(0, 300),
		}),
	}

	if isSheet then
		-- info column | action column (close on top, 48 px action at bottom)
		children.info = React.createElement("Frame", {
			Size = UDim2.new(1, -182, 1, 0), BackgroundTransparency = 1, ZIndex = 31,
		}, infoChildren)
		children.actions = React.createElement("Frame", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 170, 1, 0), BackgroundTransparency = 1, ZIndex = 31,
		}, { close = closeBtn, action = actionBtn })
	else
		children.info = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 1, -(ACTION_BTN_H + 8)), BackgroundTransparency = 1, ZIndex = 31,
		}, infoChildren)
		children.close  = closeBtn
		children.action = actionBtn
	end

	return React.createElement("Frame", frameProps, children)
end

-- §AGX/UI-P2: 48 px zoom control (shown on every platform).
local function ZoomButton(props)
	return React.createElement("TextButton", {
		Size             = UDim2.fromOffset(CTRL_BTN, CTRL_BTN),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel  = 0,
		Text             = props.text,
		TextColor3       = C.btn_text,
		Font             = Enum.Font.GothamBold,
		TextSize         = props.textSize or 26,
		LayoutOrder      = props.order,
		ZIndex           = 26,
		[React.Event.Activated] = props.onActivated,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
		stroke = React.createElement("UIStroke", {
			Color = C.btn_stroke, Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- TalentTreeUI  (root)
-- ═══════════════════════════════════════════════════════════

local function TalentTreeUI(props)
	local onClose = props.onClose

	-- §AGX/UI-P2: per-render touch check (TODO(FormFactor) in isTouchDevice).
	local isTouch = isTouchDevice()
	local minCell = isTouch and MIN_CELL_TOUCH or MIN_CELL

	local talentState, setTalentState = React.useState(TalentClient.GetState())
	local hoveredNode, setHoveredNode = React.useState(nil)
	local selectedId, setSelectedId   = React.useState(nil)  -- §AGX/UI-P2: D12 selection

	-- Pan
	local dragOffset, setDragOffset   = React.useState(Vector2.new(0, 0))
	local latestDragOffset  = React.useRef(Vector2.new(0, 0))

	-- Zoom (§T10/U2). §AGX/UI-P2: start at the touch floor so the first
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
		if not canvas then return pos end
		return toGui(pos) - canvas.AbsolutePosition
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
		if g.moved > TAP_SLOP then g.tapBlocked = true end
		setOffset(g.offsetAtStart + delta)
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
				-- §AGX/UI-P2: M17 — touch moves used to be ignored entirely.
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
					setOffset(latestDragOffset.current + (mid - lastMid))  -- two-finger pan
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
			local v = Vector2.new(s.X, s.Y)
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
	end, {})

	local allocated      = talentState.allocatedNodes or {}
	local pointsAvail    = talentState.pointsAvailable or 0
	local allocatableSet = {}
	for _, id in ipairs(TalentClient.GetAllocatableNodes()) do
		allocatableSet[id] = true
	end

	-- §AGX/UI-P2: render at no less than the platform floor (guards the
	-- frame before fitView and a touch/desktop flip).
	local renderCell = math.clamp(cell, minCell, MAX_CELL)
	local useSheet   = isTouch and canvasSize.Y < SHEET_MAX_BODY

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
					reason = "Single refunds are off. Use Respec (Scroll / 25 ♦)." }
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
		if not isTouch and last.id == node.id and now - last.t < DOUBLE_CLICK_S then
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
			local color, transparency = C.line, 0.25
			if a1 and a2 then
				color, transparency = C.line_active, 0
			elseif (a1 and allocatableSet[edge[2]]) or (a2 and allocatableSet[edge[1]]) then
				color, transparency = C.line_next, 0
			end

			children["edge_" .. i] = React.createElement(EdgeLine, {
				x1 = x1, y1 = y1, x2 = x2, y2 = y2,
				color = color, transparency = transparency,
				thickness = math.max(2, 3 * renderCell / DEFAULT_CELL),
			})
		end
	end

	-- Nodes
	for _, node in ipairs(TreeConfig.Nodes) do
		local px, py = toPixels(node.id)
		children["node_" .. node.id] = React.createElement(TalentNode, {
			nodeDef       = node,
			isAllocated   = allocated[node.id] == true,
			isAllocatable = allocatableSet[node.id] == true,
			canRefund     = allocated[node.id] == true and TalentClient.CanRefund(node.id),
			isSelected    = selectedId == node.id,
			px = px, py = py, cell = renderCell,
			onActivate     = onNodeActivated,
			onPointerBegan = onPointerBegan,
			-- §AGX/UI-P2: hover tooltip is desktop-only (touch fires
			-- MouseEnter on tap; the detail panel covers touch).
			onHover       = function(nd) if not isTouch then setHoveredNode(nd) end end,
			onLeave       = function() setHoveredNode(nil) end,
		})
	end

	children.tooltip = React.createElement(Tooltip, { nodeDef = (not isTouch) and hoveredNode or nil })

	-- §T10/U3: points counter + respec live in the standard header slot.
	local headerContent = React.createElement(React.Fragment, nil, {
		points = React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0, 0.5),
			Position               = UDim2.fromScale(0, 0.5),
			Size                   = UDim2.fromScale(0.55, 0.8),
			BackgroundTransparency = 1,
			Text                   = string.format(
				"Points: %d / %d   (Available: %d)",
				talentState.pointsSpent or 0,
				talentState.pointsTotal or 0,
				talentState.pointsAvailable or 0
			),
			TextColor3 = C.btn_text,
			Font       = Enum.Font.GothamBold,
			TextScaled = true,
			ZIndex     = 14,
		}),
		respecBtn = React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0.5),
			Position         = UDim2.fromScale(1, 0.5),
			Size             = UDim2.fromScale(0.42, 0.85),
			BackgroundColor3 = Color3.fromRGB(140, 50, 50),
			BorderSizePixel  = 0,
			Text             = "Respec  (Scroll / 25 ♦)"  --[[ §AGX/X42 ]],
			TextColor3       = C.btn_text,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			ZIndex           = 14,
			[React.Event.Activated] = function()
				TalentClient.RespecAll()
			end,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
			stroke = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1 }),
		}),
	})

	local selectedNode = selectedId and nodeMap[selectedId] or nil
	local ctrlInset    = isTouch and EDGE_INSET or 12

	-- §AGX/UI-P2: platform wording (M17: legend was PC-only).
	local legendText = isTouch
		and "Tap = Select  |  Drag = Pan  |  Pinch = Zoom"
		or  "Click = Select  |  Double-click = Allocate  |  Drag = Pan  |  Scroll = Zoom"

	return React.createElement(AppWindow, {
		variant       = "fullscreen",
		title         = "Talent Tree",
		icon          = "talents",
		onClose       = onClose,
		headerContent = headerContent,
		zIndex        = 10,
	}, {
		-- Soft radial vignette so the web feels lit from the Origin
		vignette = React.createElement("Frame", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = Color3.fromRGB(30, 28, 44),
			BackgroundTransparency = 0.55,
			BorderSizePixel        = 0,
			ZIndex                 = 10,
		}, {
			grad = React.createElement("UIGradient", {
				Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(60, 60, 90)),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0,   1),
					NumberSequenceKeypoint.new(0.5, 0.75),
					NumberSequenceKeypoint.new(1,   0.35),
				}),
				Rotation = 90,
			}),
		}),

		-- (§T10/U3: header chrome — title, points, respec, close — now
		-- lives in AppWindow; this table is the window BODY.)

		canvas = React.createElement("Frame", {
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

		-- §AGX/UI-P2: + / − / Fit (48 px, all platforms), top-left of the body.
		zoomControls = React.createElement("Frame", {
			Position               = UDim2.fromOffset(ctrlInset, 12),
			Size                   = UDim2.fromOffset(CTRL_BTN, CTRL_BTN * 3 + 16),
			BackgroundTransparency = 1,
			ZIndex                 = 25,
			ref                    = controlsRef,
		}, {
			layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder     = Enum.SortOrder.LayoutOrder,
				Padding       = UDim.new(0, 8),
			}),
			zoomIn = React.createElement(ZoomButton, {
				text = "+", order = 1,
				onActivated = function()
					zoomAbout(cellRef.current * ZOOM_STEP, canvasSizeRef.current / 2)
				end,
			}),
			zoomOut = React.createElement(ZoomButton, {
				text = "−", order = 2,
				onActivated = function()
					zoomAbout(cellRef.current / ZOOM_STEP, canvasSizeRef.current / 2)
				end,
			}),
			fit = React.createElement(ZoomButton, {
				text = "Fit", order = 3, textSize = 16,
				onActivated = function() fitView() end,
			}),
		}),

		-- §AGX/UI-P2: D12 detail panel (sheet on phone, side panel otherwise).
		detail = selectedNode and React.createElement(NodeDetail, {
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
		legend = not (useSheet and selectedNode) and React.createElement("Frame", {
			AnchorPoint            = Vector2.new(0, 1),
			Position               = isTouch and UDim2.new(0, EDGE_INSET, 1, -12) or UDim2.fromScale(0.01, 0.98),
			Size                   = isTouch and UDim2.fromOffset(330, 32) or UDim2.fromScale(0.36, 0.06),
			BackgroundColor3       = C.panel,
			BackgroundTransparency = 0.3,
			BorderSizePixel        = 0,
			ZIndex                 = 15,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.15, 0) }),
			pad    = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0.03, 0), PaddingRight = UDim.new(0.03, 0),
			}),
			lbl = React.createElement("TextLabel", {
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text                   = legendText,
				TextColor3             = C.text_dim,
				Font                   = Enum.Font.Gotham,
				TextScaled             = true,
				ZIndex                 = 16,
			}, { minText = minText() }),  -- §AGX/UI-P2: M11 12 px floor
		}) or nil,
	})
end

return TalentTreeUI
