-- Appended after TalentTreeConfig source (wrapped as TreeConfig).
-- Below is the ORGANIC LAYOUT block from UI/TalentTreeUI.lua (§T10/U4),
-- copied verbatim so the dumped positions are exactly what the game renders.

local RING_START   = 5.5
local RING_STEP    = 3.4
local SECTOR_FILL  = 0.78
local RING_JITTER  = 0.35
local ANGLE_JITTER = 0.03

local nodeMap = TreeConfig.GetNodeMap()

local function hash01(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 1000003
	end
	return h / 1000003
end

local displayPos = {}
local depth, parent = nil, nil
local branchOf = {}
local branchList = {}
local sectorCenter = {}

do
	local adj = {}
	for _, e in ipairs(TreeConfig.Edges) do
		adj[e[1]] = adj[e[1]] or {}; table.insert(adj[e[1]], e[2])
		adj[e[2]] = adj[e[2]] or {}; table.insert(adj[e[2]], e[1])
	end

	local startId = TreeConfig.StartNodeId or "start"

	depth, parent = { [startId] = 0 }, {}
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

	local branchSeen = {}
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
	for rank, b in ipairs(branchList) do
		sectorCenter[b] = branchSeen[branchList[1]].centroidAngle
			+ (rank - 1) * sectorWidth
	end

	local rings = {}
	for _, node in ipairs(TreeConfig.Nodes) do
		if node.id ~= startId and depth[node.id] then
			local b = resolveBranch(node.id)
			rings[b] = rings[b] or {}
			rings[b][depth[node.id]] = rings[b][depth[node.id]] or {}
			table.insert(rings[b][depth[node.id]], node.id)
		end
	end

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

	for _, node in ipairs(TreeConfig.Nodes) do
		if not displayPos[node.id] then
			displayPos[node.id] = { x = node.x, y = node.y }
		end
	end
end

-- ── JSON dump ────────────────────────────────────────────────

local function esc(s)
	return (s:gsub("\\", "\\\\"):gsub('"', '\\"'))
end

local parts = {}
local function w(s) parts[#parts + 1] = s end

w('{"nodes":[')
for i, node in ipairs(TreeConfig.Nodes) do
	local p = displayPos[node.id]
	local b = branchOf[node.id] or "origin"
	w(string.format(
		'%s{"id":"%s","name":"%s","type":"%s","branch":"%s","hue":%.6f,"depth":%d,"x":%.4f,"y":%.4f,"cx":%.4f,"cy":%.4f}',
		i > 1 and "," or "",
		esc(node.id), esc(node.name), esc(node.type), esc(b),
		hash01(b), depth[node.id] or -1, p.x, p.y, node.x, node.y))
end
w('],"edges":[')
for i, e in ipairs(TreeConfig.Edges) do
	w(string.format('%s["%s","%s"]', i > 1 and "," or "", esc(e[1]), esc(e[2])))
end
w('],"branches":[')
for i, b in ipairs(branchList) do
	w(string.format('%s{"name":"%s","center":%.6f,"hue":%.6f}',
		i > 1 and "," or "", esc(b), sectorCenter[b], hash01(b)))
end
w("]}")

print(table.concat(parts))
