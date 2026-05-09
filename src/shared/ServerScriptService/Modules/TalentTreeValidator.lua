-- ServerScriptService/Modules/TalentTreeValidator
--[[
    Dev-time integrity checker for TalentTreeConfig.
    Call TalentTreeValidator.Validate() during server init (debug only)
    or from a command.  Returns { ok: boolean, errors: {string} }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TalentTreeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TalentTreeConfig"))

local TalentTreeValidator = {}

function TalentTreeValidator.Validate()
	local errors = {}
	local nodeMap = TalentTreeConfig.GetNodeMap()
	local adj     = TalentTreeConfig.GetAdjacencyList()

	-- 1) Duplicate id check
	local seenIds = {}
	for _, node in ipairs(TalentTreeConfig.Nodes) do
		if seenIds[node.id] then
			table.insert(errors, "Duplicate node id: " .. node.id)
		end
		seenIds[node.id] = true
	end

	-- 2) Required fields
	local requiredFields = { "id", "name", "type", "x", "y", "cost", "effects", "description" }
	for _, node in ipairs(TalentTreeConfig.Nodes) do
		for _, field in ipairs(requiredFields) do
			if node[field] == nil then
				table.insert(errors, string.format("Node '%s' missing field '%s'", node.id, field))
			end
		end
		-- type check
		if node.type and node.type ~= "small" and node.type ~= "notable" and node.type ~= "keystone" then
			table.insert(errors, string.format("Node '%s' has invalid type '%s'", node.id, tostring(node.type)))
		end
	end

	-- 3) Edges reference existing nodes
	for i, edge in ipairs(TalentTreeConfig.Edges) do
		if not nodeMap[edge[1]] then
			table.insert(errors, string.format("Edge %d references unknown node '%s'", i, tostring(edge[1])))
		end
		if not nodeMap[edge[2]] then
			table.insert(errors, string.format("Edge %d references unknown node '%s'", i, tostring(edge[2])))
		end
	end

	-- 4) Start node exists
	if not nodeMap[TalentTreeConfig.StartNodeId] then
		table.insert(errors, "Start node '" .. tostring(TalentTreeConfig.StartNodeId) .. "' not found")
	end

	-- 5) Graph connectivity — every node reachable from start via BFS
	if nodeMap[TalentTreeConfig.StartNodeId] then
		local visited = {}
		local queue   = { TalentTreeConfig.StartNodeId }
		visited[TalentTreeConfig.StartNodeId] = true
		while #queue > 0 do
			local current = table.remove(queue, 1)
			for _, neighbor in ipairs(adj[current] or {}) do
				if not visited[neighbor] then
					visited[neighbor] = true
					table.insert(queue, neighbor)
				end
			end
		end
		for _, node in ipairs(TalentTreeConfig.Nodes) do
			if not visited[node.id] then
				table.insert(errors, "Node '" .. node.id .. "' is unreachable from start node")
			end
		end
	end

	-- 6) Each effect entry has (stat OR primary) + (value OR rule)
	--    Effects support two identifier formats:
	--      { stat    = "FlatAttack", value = N }   — derived / secondary stat bonus
	--      { primary = "MIG"|"VIT"|"PRE"|"MAG"|"RSV", value = N }  — primary stat bonus
	--      { stat    = "...", rule = true }         — keystone toggle flag
	for _, node in ipairs(TalentTreeConfig.Nodes) do
		if node.effects then
			for j, eff in ipairs(node.effects) do
				if not eff.stat and not eff.primary then
					table.insert(errors, string.format("Node '%s' effect #%d missing 'stat' or 'primary'", node.id, j))
				end
				if eff.value == nil and not eff.rule then
					table.insert(errors, string.format("Node '%s' effect #%d has neither 'value' nor 'rule'", node.id, j))
				end
			end
		end
	end

	-- 7) Node count guard (soft max reflects the intended full web size)
	local nodeCount = TalentTreeConfig.GetNodeCount()
	if nodeCount > 350 then
		table.insert(errors, string.format("Node count (%d) exceeds soft max of 350", nodeCount))
	end

	local ok = #errors == 0
	if not ok then
		warn("[TalentTreeValidator] " .. #errors .. " error(s):")
		for _, e in ipairs(errors) do
			warn("  • " .. e)
		end
	else
		print("[TalentTreeValidator] All checks passed (" .. nodeCount .. " nodes)")
	end

	return { ok = ok, errors = errors }
end

return TalentTreeValidator
