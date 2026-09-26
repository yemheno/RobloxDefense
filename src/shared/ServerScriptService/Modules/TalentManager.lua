-- ServerScriptService/Modules/TalentManager
--[[
    Server-authoritative talent allocation / refund manager.

    Responsibilities
    ════════════════
    • Maintain per-player set of allocated node ids (persisted in PlayerData).
    • Validate allocation requests (path connectivity, cost, not-already-taken).
    • Notify TalentEffectAggregator after any change.
    • Send full talent state to clients on request / after change.

    Persistence
    ═══════════
    Allocated talent ids are stored in  data.Account.AllocatedTalents = { [nodeId] = true }
    Talent points spent / available are derived at runtime:
        available = TalentPointProvider.GetTotalPoints(player) - #allocatedNodes
    TalentPointProvider is an abstract interface (stub for now).

    Respec
    ══════
    TalentManager.RespecAll(player) clears all nodes and re-aggregates.
    Full respec costs are future work — the API shape is here.
]]

local TalentManager = {}

local Modules = script.Parent

-- Lazy-load dependencies
local TreeConfig           = nil
local Validator            = nil
local EffectAggregator     = nil
local DataManager          = nil
local NetworkManager       = nil
local PlayerDataConfig     = nil

local function getTreeConfig()
	if not TreeConfig then
		local RS = game:GetService("ReplicatedStorage")
		TreeConfig = require(RS:WaitForChild("Shared"):WaitForChild("TalentTreeConfig"))
	end
	return TreeConfig
end

local function getValidator()
	if not Validator then Validator = require(Modules:WaitForChild("TalentTreeValidator")) end
	return Validator
end

local function getEffectAggregator()
	if not EffectAggregator then EffectAggregator = require(Modules:WaitForChild("TalentEffectAggregator")) end
	return EffectAggregator
end

local function getDataManager()
	if not DataManager then DataManager = require(Modules:WaitForChild("PlayerDataManager")) end
	return DataManager
end

local _CurrencyManager = nil
local function getCurrencyManager()
	if not _CurrencyManager then
		_CurrencyManager = require(Modules:WaitForChild("CurrencyManager"))
	end
	return _CurrencyManager
end

-- §AGX/UI-P4: player-facing rejections get a toast (callers drop the
-- return value). NotifyService never throws, and a missing module is
-- skipped, so logic doesn't depend on it.
local NotifyService = nil
local function notifyReject(player, text)
	if not NotifyService then
		local mod = script.Parent:FindFirstChild("NotifyService")
		if mod then
			local ok, svc = pcall(require, mod)
			if ok then NotifyService = svc end
		end
	end
	if NotifyService then NotifyService.Toast(player, "error", text) end
end

local function getNetworkManager()
	if not NetworkManager then NetworkManager = require(Modules:WaitForChild("NetworkManager")) end
	return NetworkManager
end

local function getPlayerDataConfig()
	-- PlayerDataConfig lives in SSS/Modules — NOT in ReplicatedStorage/Shared.
	-- Using RS:WaitForChild here would yield indefinitely and hang every respec.
	if not PlayerDataConfig then
		PlayerDataConfig = require(Modules:WaitForChild("PlayerDataConfig"))
	end
	return PlayerDataConfig
end

-- Lazy-load InventoryManager (used by the respec path for scroll consumption).
local _InventoryManager = nil
local function getInventoryManager()
	if not _InventoryManager then
		_InventoryManager = require(Modules:WaitForChild("InventoryManager"))
	end
	return _InventoryManager
end

-- ═══════════════════════════════════════════════════════════
-- TALENT POINT PROVIDER
-- ═══════════════════════════════════════════════════════════
--[[
    Talent points = SUM of every owned weapon's level across EVERY class.
    Each class has 2 weapons, each weapon caps at 50, so the per-class
    ceiling is 100 points.  Alpha launches with 4 classes (Aegis, Arcanist,
    Hunter, LifeSteward) = 8 weapons × 50 = 400 points at full endgame
    (§AGX/X25).
    Budget grows linearly as new classes ship.

    BonusTalentPoints (data.Account) can be granted by events/quests
    and stack on top of the weapon-level budget.
    §AGX/BTP: the live grant path is TalentManager.GrantBonusPoints, called
    by AchievementManager for "TalentPoint" tier rewards (AchievementConfig).
    AdminTesting.AddTalentPts still writes the field directly (debug only).
]]

local TalentPointProvider = {}

--[[
    Primary budget: SUM of every owned weapon's level across EVERY class.
    Each class has two weapons, each weapon caps at 50, so per-class ceiling
    is 100 points.  The equipped weapon for a class lives at
    classData.EquippedWeapon; all others live in classData.OwnedWeapons (the
    two buckets never overlap — WeaponManager.SwitchWeapon moves instances
    between them).

    A player with zero owned weapons still gets 1 point so new accounts
    aren't completely locked out of the talent tree before their starter
    weapon is assigned.
]]
function TalentPointProvider.GetTotalPoints(player)
	local dm   = getDataManager()
	local data = dm.GetData(player)
	if not data then return 0 end

	local total = 0

	if data.Classes then
		for _, classData in pairs(data.Classes) do
			if classData.EquippedWeapon and classData.EquippedWeapon.level then
				total = total + classData.EquippedWeapon.level
			end
			if classData.OwnedWeapons then
				for _, weapon in pairs(classData.OwnedWeapons) do
					if weapon.level then
						total = total + weapon.level
					end
				end
			end
		end
	end

	-- Floor of 1 so brand-new accounts still have a starter point available.
	if total < 1 then total = 1 end

	-- Bonus points from events, quests, admin grants, etc.
	local bonus = data.Account.BonusTalentPoints or 0

	return total + bonus
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

--- Get the allocated set  { [nodeId]=true } from persisted data.
local function getAllocated(player)
	local dm   = getDataManager()
	local data = dm.GetData(player)
	if not data then return {} end
	if not data.Account.AllocatedTalents then
		data.Account.AllocatedTalents = {}
	end
	return data.Account.AllocatedTalents
end

--- Count how many points are currently spent (start node is free).
local function countSpent(allocated)
	local cfg     = getTreeConfig()
	local nodeMap = cfg.GetNodeMap()
	local total = 0
	for nodeId, _ in pairs(allocated) do
		local node = nodeMap[nodeId]
		if node then
			total = total + (node.cost or 1)
		end
	end
	return total
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function TalentManager.Init()
	-- Validate talent tree on startup — hard error on failure so bad tree configs
	-- are caught immediately rather than silently producing broken gameplay.
	local validatorResult = getValidator().Validate()
	if not validatorResult.ok then
		error("[TalentManager] Talent tree validation failed:\n" .. table.concat(validatorResult.errors, "\n"), 2)
	end

	local net = getNetworkManager()

	-- Pre-create remote events
	net.GetEvent("AllocateTalent")
	net.GetEvent("RespecTalents")
	net.GetEvent("GetTalentState")
	net.GetEvent("TalentStateUpdate")

	-- Client → Server: allocate a node
	net.OnClientEvent("AllocateTalent", function(player, nodeId)
		local success, msg = TalentManager.AllocateNode(player, nodeId)
		if not success then
			warn("[TalentManager] Allocate failed for", player.Name, ":", msg)
			-- §AGX/UI-P4: tell the player why, not just the log
			-- (not for the double-click lock, which isn't a real rejection).
			if msg ~= "Concurrent allocation request" then
				notifyReject(player, msg or "Can't allocate that talent.")
			end
		end
		-- Always send fresh state back
		TalentManager.SendState(player)
	end)

	-- Client → Server: full respec (costs 1 respec_scroll, else
	-- PlayerDataConfig.GetRespecCost(level).essence = 25 Essence).
	-- §AGX/X42: Essence-only by design (no Merit price; see PlayerDataConfig
	-- RESPEC COST).
	net.GetEvent("RespecResult")
	net.OnClientEvent("RespecTalents", function(player)
		local dm   = getDataManager()
		local cfg  = getPlayerDataConfig()
		local data = dm.GetData(player)
		if not data then return end

		-- Respec cost: 1 respec_scroll (from inventory) OR Essence fallback.
		-- RespecTokens counter is deprecated in favor of the inventory item.
		local inv = getInventoryManager()
		local hasScroll = inv.HasItem(player, "respec_scroll", 1)
		local cm = getCurrencyManager()
		local respecCost = cfg.GetRespecCost(data.Account.Level or 1)
		local canAfford = cm.CanAffordEssence(player, respecCost.essence)

		if not (hasScroll or canAfford) then
			net.FireClient(player, "RespecResult", { ok = false, reason = "Need " .. respecCost.essence .. " Essence or a Respec Scroll" })
			return
		end

		-- §T1: deduct the cost FIRST, then wipe talents, so a failed
		-- deduct loses nothing.
		local consumed = false
		if hasScroll then
			consumed = inv.ConsumeItem(player, "respec_scroll", 1) and true or false
		end
		if (not consumed) and canAfford then
			-- SpendEssence returns true on success, false on insufficient funds.
			consumed = cm.SpendEssence(player, respecCost.essence) and true or false
		end
		if not consumed then
			warn(string.format(
				"[TalentManager] Respec deduct failed for %s — aborting respec to protect progress.",
				player.Name))
			net.FireClient(player, "RespecResult", { ok = false, reason = "Could not deduct cost; please retry." })
			return
		end

		-- Cost deducted. Now perform the actual respec.
		TalentManager.RespecAll(player)

		net.FireClient(player, "RespecResult", { ok = true, type = "talents" })
		TalentManager.SendState(player)
	end)

	-- Client → Server: request current state
	net.OnClientEvent("GetTalentState", function(player)
		TalentManager.SendState(player)
	end)

end

-- ═══════════════════════════════════════════════════════════
-- PLAYER SETUP
-- ═══════════════════════════════════════════════════════════

function TalentManager.SetupPlayer(player)
	local allocated = getAllocated(player)

	-- Ensure start node is always allocated (free)
	local cfg = getTreeConfig()
	if not allocated[cfg.StartNodeId] then
		allocated[cfg.StartNodeId] = true
	end

	-- Rebuild effect aggregation from persisted state
	getEffectAggregator().Rebuild(player, allocated)
end

-- ═══════════════════════════════════════════════════════════
-- ALLOCATE
-- ═══════════════════════════════════════════════════════════

-- §T2: per-player allocation lock. Two AllocateTalent packets in
-- the same network frame would otherwise both pass the points check
-- before either mutates `allocated`, double-spending the same point.
local allocateLock = setmetatable({}, { __mode = "k" })

--- Try to allocate a node. Returns (success, message).
function TalentManager.AllocateNode(player, nodeId)
	if allocateLock[player] then
		return false, "Concurrent allocation request"
	end
	allocateLock[player] = true
	local function release(ok, msg) allocateLock[player] = nil; return ok, msg end

	local cfg      = getTreeConfig()
	local nodeMap  = cfg.GetNodeMap()
	local adj      = cfg.GetAdjacencyList()

	-- 1) Valid node?
	local node = nodeMap[nodeId]
	if not node then return release(false, "Unknown node id") end

	-- 2) Already allocated?
	local allocated = getAllocated(player)
	if allocated[nodeId] then return release(false, "Already allocated") end

	-- 3) Enough points?
	local spent     = countSpent(allocated)
	local available = TalentPointProvider.GetTotalPoints(player) - spent
	if (node.cost or 1) > available then return release(false, "Not enough talent points") end

	-- 4) Path connectivity: at least one allocated neighbor
	local hasAllocatedNeighbor = false
	for _, neighbor in ipairs(adj[nodeId] or {}) do
		if allocated[neighbor] then
			hasAllocatedNeighbor = true
			break
		end
	end
	if not hasAllocatedNeighbor then return release(false, "Not connected to allocated path") end

	-- 5) Level requirement (optional)
	if node.requirements and node.requirements.minLevel then
		local dm   = getDataManager()
		local data = dm.GetData(player)
		local level = data and data.Account.Level or 1
		if level < node.requirements.minLevel then
			return release(false, "Level requirement not met")
		end
	end

	-- 6) Prerequisite node (optional)
	if node.requirements and node.requirements.prerequisiteNodeId then
		if not allocated[node.requirements.prerequisiteNodeId] then
			return release(false, "Prerequisite node not allocated")
		end
	end

	-- ✓ Allocate
	allocated[nodeId] = true
	getEffectAggregator().OnNodeAllocated(player, node, allocated)

	-- Track cumulative allocations for the Talent Seeker achievement.
	do
		local amMod = Modules:FindFirstChild("AchievementManager")
		if amMod then
			local ok, am = pcall(require, amMod)
			if ok then am.OnTalentAllocated(player) end
		end
	end

	return release(true, "OK")
end

-- ═══════════════════════════════════════════════════════════
-- RESPEC ALL
-- ═══════════════════════════════════════════════════════════

function TalentManager.RespecAll(player)
	local cfg       = getTreeConfig()
	local allocated = getAllocated(player)

	-- Clear everything except start
	for nodeId, _ in pairs(allocated) do
		if nodeId ~= cfg.StartNodeId then
			allocated[nodeId] = nil
		end
	end

	-- Rebuild from scratch (empty except start)
	getEffectAggregator().Rebuild(player, allocated)

	return true, "OK"
end

-- ═══════════════════════════════════════════════════════════
-- BONUS POINTS  (§AGX/BTP)
-- ═══════════════════════════════════════════════════════════

--- §AGX/BTP: add `amount` permanent bonus talent points and push the new
--- state (pointsTotal already includes BonusTalentPoints). NOT idempotent
--- on its own: the caller guarantees one call per grant (AchievementManager
--- keeps a per-tier ledger). Returns true when the points were stored.
function TalentManager.GrantBonusPoints(player, amount, reason)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return false end
	local data = getDataManager().GetData(player)
	if not data or type(data.Account) ~= "table" then return false end
	local cur = tonumber(data.Account.BonusTalentPoints) or 0
	data.Account.BonusTalentPoints = cur + amount
	print(string.format("[TalentManager] +%d bonus talent point(s) for %s (%s) → %d",
		amount, player.Name, tostring(reason or "?"), cur + amount))
	TalentManager.SendState(player)
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SEND STATE TO CLIENT
-- ═══════════════════════════════════════════════════════════

-- §RG2: lazy ReadyGate ref — TalentStateUpdate is one of the
-- on-PlayerReady push events that races with TalentTreeUI's React mount.
-- Routing it through ReadyGate so the queue catches it if the player
-- hasn't ack'd ClientReady yet.
local _ReadyGate = nil
local function getReadyGate()
	if _ReadyGate ~= nil then return _ReadyGate end
	local Modules = script.Parent
	local mod = Modules:FindFirstChild("ReadyGate")
	if mod then
		local ok, rg = pcall(require, mod)
		if ok then _ReadyGate = rg end
	end
	if not _ReadyGate then _ReadyGate = false end  -- cache miss
	return _ReadyGate or nil
end

function TalentManager.SendState(player)
	local allocated = getAllocated(player)
	local spent     = countSpent(allocated)
	local total     = TalentPointProvider.GetTotalPoints(player)

	-- Convert allocated set → list of ids for serialization
	local allocatedList = {}
	for nodeId, _ in pairs(allocated) do
		table.insert(allocatedList, nodeId)
	end

	local payload = {
		allocatedNodes  = allocatedList,
		pointsSpent     = spent,
		pointsTotal     = total,
		pointsAvailable = total - spent,
	}

	local rg = getReadyGate()
	if rg and rg.FireClient then
		rg.FireClient(player, "TalentStateUpdate", payload)
	else
		getNetworkManager().FireClient(player, "TalentStateUpdate", payload)
	end
end

return TalentManager
