-- StarterPlayerScripts/Modules/TalentClient
--[[
    Client-side adapter for the talent tree.

    Responsibilities:
      • Cache the latest TalentStateUpdate from server.
      • Compute "allocatable" node set locally (for UI highlighting).
      • Expose a clean API for React components to subscribe to.
      • Send allocation / refund / respec requests to server.
]]

local TalentClient = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerScripts     = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts")
local Modules           = PlayerScripts:WaitForChild("Modules")
local NetworkManager    = require(Modules:WaitForChild("NetworkManager"))

-- TalentTreeConfig lives in ReplicatedStorage.Shared (accessible to both server + client)
local TreeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TalentTreeConfig"))

-- ── State ─────────────────────────────────────────────────
local state = {
	allocatedNodes   = {},   -- { [nodeId] = true }
	pointsSpent      = 0,
	pointsTotal      = 0,
	pointsAvailable  = 0,
}

-- Listeners: table of functions that receive the full state whenever it changes.
local listeners = {}

local function notifyListeners()
	for _, fn in ipairs(listeners) do
		pcall(fn, state)
	end
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function TalentClient.Init()
	NetworkManager.OnServerEvent("TalentStateUpdate", function(data)
		-- Rebuild allocated set from list
		local set = {}
		if data.allocatedNodes then
			for _, id in ipairs(data.allocatedNodes) do
				set[id] = true
			end
		end
		state.allocatedNodes  = set
		state.pointsSpent     = data.pointsSpent or 0
		state.pointsTotal     = data.pointsTotal or 0
		state.pointsAvailable = data.pointsAvailable or 0
		notifyListeners()
	end)

	-- Request initial state from server
	task.defer(function()
		NetworkManager.FireServer("GetTalentState")
	end)
end

-- ═══════════════════════════════════════════════════════════
-- SUBSCRIBE / UNSUBSCRIBE
-- ═══════════════════════════════════════════════════════════

function TalentClient.Subscribe(callback)
	table.insert(listeners, callback)
	-- Immediately fire with current state
	pcall(callback, state)
	-- Return unsubscribe function
	return function()
		for i, fn in ipairs(listeners) do
			if fn == callback then
				table.remove(listeners, i)
				break
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- STATE GETTERS
-- ═══════════════════════════════════════════════════════════

function TalentClient.GetState()
	return state
end

function TalentClient.IsAllocated(nodeId)
	return state.allocatedNodes[nodeId] == true
end

--- Compute which nodes can currently be allocated (for UI glow).
function TalentClient.GetAllocatableNodes()
	local adj      = TreeConfig.GetAdjacencyList()
	local result   = {}
	local allocated = state.allocatedNodes

	for _, node in ipairs(TreeConfig.Nodes) do
		if not allocated[node.id] and (node.cost or 1) <= state.pointsAvailable then
			for _, neighbor in ipairs(adj[node.id] or {}) do
				if allocated[neighbor] then
					table.insert(result, node.id)
					break
				end
			end
		end
	end
	return result
end

--- Is this node a leaf that can be refunded?
function TalentClient.CanRefund(nodeId)
	if nodeId == TreeConfig.StartNodeId then return false end
	if not state.allocatedNodes[nodeId] then return false end

	local adj = TreeConfig.GetAdjacencyList()
	local count = 0
	for _, neighbor in ipairs(adj[nodeId] or {}) do
		if state.allocatedNodes[neighbor] then
			count = count + 1
		end
	end
	return count <= 1
end

-- ═══════════════════════════════════════════════════════════
-- ACTIONS (fire-and-forget — server will respond with state update)
-- ═══════════════════════════════════════════════════════════

function TalentClient.AllocateNode(nodeId)
	NetworkManager.FireServer("AllocateTalent", nodeId)
end

-- Individual refund disabled — use full respec
function TalentClient.RefundNode(_nodeId)
	warn("[TalentClient] Individual refund disabled; use RespecAll")
end

function TalentClient.RespecAll()
	NetworkManager.FireServer("RespecTalents")
end

-- Subscribe to RespecResult from server
local respecCallbacks = {}
function TalentClient.OnRespecResult(callback)
	table.insert(respecCallbacks, callback)
	return function()
		for i, cb in ipairs(respecCallbacks) do
			if cb == callback then table.remove(respecCallbacks, i) break end
		end
	end
end

-- Wire listener (call once, in Init or lazily)
do
	task.defer(function()
		NetworkManager.OnServerEvent("RespecResult", function(data)
			for _, cb in ipairs(respecCallbacks) do
				cb(data)
			end
		end)
	end)
end

return TalentClient
