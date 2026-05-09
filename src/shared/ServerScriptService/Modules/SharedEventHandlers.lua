-- ServerScriptService/Modules/SharedEventHandlers.lua
--[[
    Registers the event handlers that are identical across both
    Lobby and LaneDefense bootstraps:
      • GetPlayerInfo  → PlayerInfoUpdate
      • GetStats       → StatsUpdate
      • AllocateStat   → StatsUpdate
      • ModifySystemStat (admin only)

    Usage in bootstrap:
        SharedEventHandlers.Register({
            NetworkManager    = NetworkManager,
            DataManager       = DataManager,
            Config            = Config,            -- PlayerDataConfig
            ResourceManager   = ResourceManager,   -- optional (may be nil in some places)
            IsAdmin           = IsAdmin,           -- admin guard function
        })
]]

local SharedEventHandlers = {}

-- ═══════════════════════════════════════════════════════════
-- INTERNAL STATE (set by Register)
-- ═══════════════════════════════════════════════════════════

local NetworkManager  = nil
local DataManager     = nil
local Config          = nil
local ResourceManager = nil
local IsAdmin         = nil

-- CurrencyManager is loaded lazily to avoid circular deps
local _CurrencyManager = nil
local function getCurrencyManager()
	if not _CurrencyManager then
		_CurrencyManager = require(script.Parent:WaitForChild("CurrencyManager"))
	end
	return _CurrencyManager
end

-- BonusManager: used by ModifySystemStat so debug stat changes survive BonusManager.Recalculate.
-- Direct data.Bonus writes (via DataManager.SetSystemStat) are overwritten on next Recalculate;
-- routing through BonusManager's "other" source persists them correctly.
local _BonusManager = nil
local function getBonusManager()
	if not _BonusManager then
		_BonusManager = require(script.Parent:WaitForChild("BonusManager"))
	end
	return _BonusManager
end

-- InventoryManager: loaded lazily — used by the stat-respec path to consume
-- a respec_scroll from the player's inventory (replaces the deprecated
-- data.Account.RespecTokens counter).
local _InventoryManager = nil
local function getInventoryManager()
	if not _InventoryManager then
		_InventoryManager = require(script.Parent:WaitForChild("InventoryManager"))
	end
	return _InventoryManager
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

local DERIVED_STAT_KEYS = {
	"Health", "Damage", "Armor", "Penetration",
	"CritChance", "CritDamage", "CooldownReduction", "StatusResistance",
}

local function buildStatsPayload(player)
	local data = DataManager.GetData(player)
	if not data then return nil end

	local className = data.ActiveClass
	local classData = data.Classes[className]
	local allocated = {}
	for _, s in ipairs(Config.PrimaryStats) do
		allocated[s] = (classData and classData.Allocated and classData.Allocated[s]) or 0
	end

	local derived = {}
	for _, key in ipairs(DERIVED_STAT_KEYS) do
		derived[key] = DataManager.GetTotalStat(player, key)
	end

	return {
		level       = data.Account.Level or 1,
		unallocated = DataManager.GetUnallocatedPoints(player) or 0,
		allocated   = allocated,
		derived     = derived,
	}
end

-- ═══════════════════════════════════════════════════════════
-- REGISTRATION
-- ═══════════════════════════════════════════════════════════

--- Push a fresh StatsUpdate to a single player.
--- Call this from OnPlayerReady (after ClassManager / InventoryManager have run)
--- so the client's stats panel is accurate the moment the server is ready,
--- without requiring the player to open the menu manually.
function SharedEventHandlers.PushStatsUpdate(player)
	local payload = buildStatsPayload(player)
	if payload then
		NetworkManager.FireClient(player, "StatsUpdate", payload)
	end
end

function SharedEventHandlers.Register(deps)
	NetworkManager  = deps.NetworkManager
	DataManager     = deps.DataManager
	Config          = deps.Config
	ResourceManager = deps.ResourceManager  -- may be nil
	IsAdmin         = deps.IsAdmin

	-- Pre-create outgoing events so they exist before any FireClient call
	NetworkManager.GetEvent("PlayerInfoUpdate")
	NetworkManager.GetEvent("StatsUpdate")
	NetworkManager.GetEvent("SaveKeybindings")

	-- ─────────────────────────────────────────────────────────────────────────
	-- HELPER: build and fire PlayerInfoUpdate for a player.
	-- Used both by the GetPlayerInfo handler and the auto-push on data ready.
	-- ─────────────────────────────────────────────────────────────────────────
	local function sendPlayerInfo(player)
		local data = DataManager.GetData(player)
		if not data then return end

		local activeClass = data.ActiveClass or "Aegis"

		-- Ensure ResourceManager has the correct class (SetupPlayer may have run before
		-- DataStore finished loading, leaving className = nil).
		if ResourceManager and ResourceManager.EnsureClass then
			ResourceManager.EnsureClass(player, activeClass)
		end

		local level    = data.Account.Level      or 1
		local xp       = data.Account.Experience or 0
		local xpNeeded = Config.GetXPForLevel(level)
		local resCur  = ResourceManager and ResourceManager.GetResource(player)     or 0
		local resMax  = ResourceManager and ResourceManager.GetMaxResource(player)  or 100
		local resName = ResourceManager and ResourceManager.GetResourceName(player) or "Resource"

		NetworkManager.FireClient(player, "PlayerInfoUpdate", {
			level           = level,
			activeClass     = activeClass,
			unlockedClasses = data.Account.UnlockedClasses  or { "Aegis" },
			xp              = xp,
			xpNeeded        = xpNeeded,
			essence         = data.Account.Essence          or 0,
			merits          = data.Account.Merits            or 0,
			resource        = resCur,
			maxResource     = resMax,
			resourceName    = resName,
			keybindings     = data.Account.Keybindings      or {},
		})
	end

	-- Auto-push PlayerInfoUpdate the moment a player's data finishes loading.
	-- This eliminates the race condition where GetPlayerInfo arrives before
	-- the DataStore load completes (causing an empty initial HUD).
	if DataManager.OnPlayerDataReady then
		DataManager.OnPlayerDataReady(function(player)
			sendPlayerInfo(player)
		end)
	end

	-- ── GetPlayerInfo ─────────────────────────────────────
	NetworkManager.GetEvent("GetPlayerInfo")
	NetworkManager.OnClientEvent("GetPlayerInfo", function(player)
		local data = DataManager.GetData(player)
		-- Data may still be loading from the DataStore — retry for up to 10 s.
		if not data then
			for _ = 1, 40 do
				task.wait(0.25)
				data = DataManager.GetData(player)
				if data then break end
			end
		end
		if not data then return end

		sendPlayerInfo(player)
	end)

	-- ── GetStats ──────────────────────────────────────────
	NetworkManager.GetEvent("GetStats")
	NetworkManager.OnClientEvent("GetStats", function(player)
		local payload = buildStatsPayload(player)
		if payload then
			NetworkManager.FireClient(player, "StatsUpdate", payload)
		end
	end)

	-- ── AllocateStat ──────────────────────────────────────
	NetworkManager.GetEvent("AllocateStat")
	NetworkManager.OnClientEvent("AllocateStat", function(player, statName, points)
		if type(statName) ~= "string" or type(points) ~= "number" then return end
		-- Only allocation allowed; deallocation removed (use full respec)
		if points > 0 then
			DataManager.AllocateStat(player, statName, points)
		end

		local payload = buildStatsPayload(player)
		if payload then
			NetworkManager.FireClient(player, "StatsUpdate", payload)
		end
	end)

	-- ── RespecStats (full stat respec: 500 Essence or 1 token) ────
	NetworkManager.GetEvent("RespecStats")
	NetworkManager.GetEvent("RespecResult")
	NetworkManager.OnClientEvent("RespecStats", function(player)
		local data = DataManager.GetData(player)
		if not data then return end

		-- Pay with inventory scroll first, then Essence.
		-- RespecTokens counter is deprecated in favor of the respec_scroll item.
		local inv = getInventoryManager()
		local hasScroll = inv.HasItem(player, "respec_scroll", 1)
		local cm = getCurrencyManager()
		local respecCost = Config.GetRespecCost(data.Account.Level or 1)
		local canAfford = cm.CanAffordEssence(player, respecCost.essence)

		if hasScroll then
			inv.ConsumeItem(player, "respec_scroll", 1)
		elseif canAfford then
			cm.SpendEssence(player, respecCost.essence)
		else
			NetworkManager.FireClient(player, "RespecResult", { ok = false, reason = "Need " .. respecCost.essence .. " Essence or a Respec Scroll" })
			return
		end

		-- Reset all stat allocations for the active class.
		-- Replace the table outright (same as ResetAllocation in StatSystem) so
		-- any orphaned keys that slipped through sanitization are also removed.
		local className = data.ActiveClass
		local classData = data.Classes[className]
		if classData then
			local fresh = {}
			for _, s in ipairs(Config.PrimaryStats) do
				fresh[s] = 0
			end
			classData.Allocated = fresh
		end

		NetworkManager.FireClient(player, "RespecResult", { ok = true, type = "stats" })

		local payload = buildStatsPayload(player)
		if payload then
			NetworkManager.FireClient(player, "StatsUpdate", payload)
		end
	end)

	-- ── ModifySystemStat (admin only) ─────────────────────
	NetworkManager.GetEvent("ModifySystemStat")
	NetworkManager.OnClientEvent("ModifySystemStat", function(player, statName, delta)
		if type(statName) ~= "string" or type(delta) ~= "number" then return end
		if not IsAdmin(player) then
			warn("[Security] ModifySystemStat blocked for", player.Name)
			return
		end

		-- Route through BonusManager "other" source so the change survives
		-- BonusManager.Recalculate() (direct data.Bonus writes are overwritten).
		local bm = getBonusManager()
		local currentValue = bm.GetAggregatedBonus(player, statName)
		local newDelta = delta
		if statName == "CritDamage" then
			newDelta = math.max(0.5 - currentValue, delta)
		elseif statName == "CritChance" then
			newDelta = math.max(-currentValue, delta)
		end
		bm.ModifySourceBonus(player, "other", statName, newDelta)
		print("[SharedEventHandlers]", player.Name, statName, ":", currentValue, "->", currentValue + newDelta)
	end)

	-- ── SaveKeybindings ───────────────────────────────────
	-- Client sends serialized overrides: { actionName = { Keyboard = "KeyName" } }
	-- Server stores them in data.Account.Keybindings (sent back on next PlayerInfoUpdate).
	NetworkManager.OnClientEvent("SaveKeybindings", function(player, serialized)
		if type(serialized) ~= "table" then return end
		local data = DataManager.GetData(player)
		if not data or not data.Account then return end

		-- Sanitize: only keep string action-names with table values of string key-names
		local clean = {}
		for actionName, platforms in pairs(serialized) do
			if type(actionName) == "string" and type(platforms) == "table" then
				local cleanPlatforms = {}
				for platform, keyName in pairs(platforms) do
					if type(platform) == "string" and type(keyName) == "string" then
						cleanPlatforms[platform] = keyName
					end
				end
				clean[actionName] = cleanPlatforms
			end
		end
		data.Account.Keybindings = clean
	end)

	print("[SharedEventHandlers] Registered")
end

return SharedEventHandlers
