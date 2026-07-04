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

    Features kept from v1: node states, click allocate / refund,
    points counter, Respec All, hover tooltip, close button.

    Architecture unchanged:
      Topology  ← TalentTreeConfig (ReplicatedStorage.Shared)
      State     ← TalentClient (subscribe pattern)
      Actions   → TalentClient (fire-and-forget → server responds)
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
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
		[React.Event.Activated] = function()
			if isAllocatable and not isAllocated then
				props.onAllocate(node.id)
			elseif isAllocated and canRefund then
				props.onRefund(node.id)
			end
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
-- Tooltip
-- ═══════════════════════════════════════════════════════════

local function Tooltip(props)
	local node = props.nodeDef
	if not node then return nil end

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

	local branch = node.tags and node.tags[1]
	local header = node.name .. "  [" .. string.upper(node.type or "") .. "]"
	if branch then header = header .. "  ·  " .. branch end

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
		}),
		descLbl = React.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 0.30), BackgroundTransparency = 1,
			Text = node.description or "", TextColor3 = C.text_dim,
			Font = Enum.Font.Gotham, TextScaled = true, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2,
		}),
		effectsLbl = React.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 0.25), BackgroundTransparency = 1,
			Text = table.concat(lines, "\n"), TextColor3 = C.allocated,
			Font = Enum.Font.GothamBold, TextScaled = true, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3,
		}),
		costLbl = React.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 0.15), BackgroundTransparency = 1,
			Text = (node.cost or 1) > 0 and ("Cost: " .. (node.cost or 1) .. " point") or "Free",
			TextColor3 = C.text_dim, Font = Enum.Font.Gotham, TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 4,
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- TalentTreeUI  (root)
-- ═══════════════════════════════════════════════════════════

local function TalentTreeUI(props)
	local onClose = props.onClose

	local talentState, setTalentState = React.useState(TalentClient.GetState())
	local hoveredNode, setHoveredNode = React.useState(nil)

	-- Pan
	local dragOffset, setDragOffset   = React.useState(Vector2.new(0, 0))
	local isDragging        = React.useRef(false)
	local dragStartMouse    = React.useRef(Vector2.new(0, 0))
	local offsetAtDragStart = React.useRef(Vector2.new(0, 0))
	local latestDragOffset  = React.useRef(Vector2.new(0, 0))

	-- Zoom (§T10/U2)
	local cell, setCell = React.useState(DEFAULT_CELL)

	local canvasRef = React.useRef(nil)
	local canvasSize, setCanvasSize = React.useState(Vector2.new(1200, 800))

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
		local moveConn = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				if not isDragging.current then return end
				local pos    = input.Position
				local delta  = Vector2.new(pos.X, pos.Y) - dragStartMouse.current
				local newOff = offsetAtDragStart.current + delta
				latestDragOffset.current = newOff
				setDragOffset(newOff)
			elseif input.UserInputType == Enum.UserInputType.MouseWheel then
				-- Zoom only while the cursor is over the canvas
				local canvas = canvasRef.current
				if canvas then
					local p  = input.Position
					local ap = canvas.AbsolutePosition
					local as = canvas.AbsoluteSize
					if p.X >= ap.X and p.X <= ap.X + as.X and p.Y >= ap.Y and p.Y <= ap.Y + as.Y then
						setCell(function(c)
							return math.clamp(c + input.Position.Z * 4, MIN_CELL, MAX_CELL)
						end)
					end
				end
			end
		end)

		local endConn = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				isDragging.current = false
			end
		end)

		return function()
			moveConn:Disconnect()
			endConn:Disconnect()
		end
	end, {})

	React.useEffect(function()
		task.defer(function()
			local canvas = canvasRef.current
			if canvas then
				setCanvasSize(Vector2.new(canvas.AbsoluteSize.X, canvas.AbsoluteSize.Y))
			end
		end)
	end, {})

	local allocated      = talentState.allocatedNodes or {}
	local allocatableSet = {}
	for _, id in ipairs(TalentClient.GetAllocatableNodes()) do
		allocatableSet[id] = true
	end

	-- Pixel projection of the ORGANIC coordinates
	local function toPixels(id)
		local p = displayPos[id]
		return canvasSize.X * CENTER_X + p.x * cell + dragOffset.X,
		       canvasSize.Y * CENTER_Y + p.y * cell + dragOffset.Y
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
				thickness = math.max(2, 3 * cell / DEFAULT_CELL),
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
			px = px, py = py, cell = cell,
			onAllocate    = function(id) TalentClient.AllocateNode(id) end,
			onRefund      = function(id) TalentClient.RefundNode(id) end,
			onHover       = function(nd) setHoveredNode(nd) end,
			onLeave       = function() setHoveredNode(nil) end,
		})
	end

	children.tooltip = React.createElement(Tooltip, { nodeDef = hoveredNode })

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
			Text             = "Respec  (Token / 500 ♦)",
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
			[React.Event.InputBegan] = function(_, input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					isDragging.current        = true
					dragStartMouse.current    = Vector2.new(input.Position.X, input.Position.Y)
					offsetAtDragStart.current = latestDragOffset.current
				end
			end,
		}, children),

		legend = React.createElement("Frame", {
			AnchorPoint            = Vector2.new(0, 1),
			Position               = UDim2.fromScale(0.01, 0.98),
			Size                   = UDim2.fromScale(0.24, 0.08),
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
				Text                   = "Click = Allocate  |  Drag = Pan  |  Scroll = Zoom",
				TextColor3             = C.text_dim,
				Font                   = Enum.Font.Gotham,
				TextScaled             = true,
				ZIndex                 = 16,
			}),
		}),
	})
end

return TalentTreeUI
