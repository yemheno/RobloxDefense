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

-- BonusManager: used by the admin ModifySystemStat path so debug stat
-- changes survive BonusManager.Recalculate (which is the single writer
-- into data.Bonus). PlayerBonusSystem.SetBonus / ModifyBonus also route
-- through BonusManager "other" source now (§PDM-D3) — direct data.Bonus
-- writes are no longer a thing.
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

-- §AGX/X8: InputActions is the canonical action/default-binding table.
-- It lives under StarterPlayerScripts (client folder) but is pure data
-- (names + Enum values), and StarterPlayer's contents exist on the
-- server too, so we read it from there rather than keep a second copy.
-- `false` = looked, not found (house lazy-getter pattern, Audit §5.3).
local _InputActions = nil
local function getInputActions()
	if _InputActions ~= nil then
		return _InputActions or nil
	end
	local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local mods = sps and sps:FindFirstChild("Modules")
	local inputSystem = mods and mods:FindFirstChild("InputSystem")
	local mod = inputSystem and inputSystem:FindFirstChild("InputActions")
	if not mod then
		_InputActions = false
		warn("[SharedEventHandlers] InputActions not found — keybind allowlist falls back to saved actions.")
		return nil
	end
	local ok, result = pcall(require, mod)
	_InputActions = ok and type(result) == "table" and type(result.Definitions) == "table" and result or false
	return _InputActions or nil
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

-- §AGX/X8: SaveKeybindings limits. The payload is stored verbatim in the
-- DataStore profile, so an oversized or non-UTF-8 table would make every
-- save of that profile fail.
local KEYBIND_MAX_ENTRIES  = 64   -- total (action, platform) pairs kept
local KEYBIND_MAX_SCANNED  = 256  -- stop walking a hostile table after this many keys
local KEYBIND_MAX_NAME_LEN = 32
local KEYBIND_MIN_INTERVAL = 0.5  -- s between accepted saves per player
local KEYBIND_PLATFORMS_FALLBACK = { Keyboard = true, Gamepad = true, Touch = true }
-- InputSystem.LoadBindings also resolves Enum.UserInputType names and
-- SettingsUI binds mouse buttons that way, so these stay valid values.
local KEYBIND_EXTRA_INPUT_NAMES = { MouseButton1 = true, MouseButton2 = true, MouseButton3 = true }
local lastKeybindSave = setmetatable({}, { __mode = "k" })

local function isValidKeyName(v)
	if type(v) ~= "string" or #v == 0 or #v > KEYBIND_MAX_NAME_LEN then return false end
	if utf8.len(v) == nil then return false end
	if KEYBIND_EXTRA_INPUT_NAMES[v] then return true end
	local ok, item = pcall(function() return Enum.KeyCode[v] end)
	return ok and item ~= nil
end

-- Allowed platforms for one action: the platform keys of its defaults.
-- Without the catalog, fall back to actions the player already has saved.
local function allowedPlatformsFor(actionName, savedBindings)
	local ia = getInputActions()
	if ia then
		local def = ia.Definitions[actionName]
		if type(def) ~= "table" or type(def.defaults) ~= "table" then return nil end
		return def.defaults
	end
	if type(savedBindings) == "table" and type(savedBindings[actionName]) == "table" then
		return KEYBIND_PLATFORMS_FALLBACK
	end
	return nil
end

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
	-- §T0P2/X11: no retry loop. The old 40×0.25 s wait parked a thread
	-- per request — at the default 30/s rate limit one client could
	-- stack ~300 yielding threads. The data-ready auto-push above
	-- already covers the load race; if data isn't there yet, the push
	-- will arrive the moment it is.
	NetworkManager.GetEvent("GetPlayerInfo")
	NetworkManager.OnClientEvent("GetPlayerInfo", function(player)
		if not DataManager.GetData(player) then return end
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

		-- §T0P2/X12: use the canonical ResetAllocation instead of an
		-- inline copy. The inline version had already drifted: it
		-- skipped the character-health reapply, so a respec that
		-- dropped VIT left inflated HP until the next respawn.
		DataManager.ResetAllocation(player)

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
	-- §AGX/X8: allowlist actions (InputActions catalog) and platforms (that
	-- action's defaults), require real KeyCode names (plus mouse buttons),
	-- cap lengths/counts and rate-limit. Invalid entries are dropped, not
	-- the whole table. The old type-only check let a client store any
	-- table, including non-UTF-8 strings that break every profile save.
	NetworkManager.OnClientEvent("SaveKeybindings", function(player, serialized)
		if type(serialized) ~= "table" then return end
		local now = os.clock()
		local last = lastKeybindSave[player]
		if last and now - last < KEYBIND_MIN_INTERVAL then return end
		local data = DataManager.GetData(player)
		if not data or not data.Account then return end
		lastKeybindSave[player] = now

		local saved = data.Account.Keybindings
		local clean = {}
		local kept, scanned = 0, 0
		for actionName, platforms in pairs(serialized) do
			scanned += 1
			if scanned > KEYBIND_MAX_SCANNED or kept >= KEYBIND_MAX_ENTRIES then break end
			local allowed = type(actionName) == "string" and type(platforms) == "table"
				and allowedPlatformsFor(actionName, saved)
			if allowed then
				local cleanPlatforms = nil
				for platform, keyName in pairs(platforms) do
					scanned += 1
					if scanned > KEYBIND_MAX_SCANNED or kept >= KEYBIND_MAX_ENTRIES then break end
					if type(platform) == "string" and allowed[platform] ~= nil and isValidKeyName(keyName) then
						cleanPlatforms = cleanPlatforms or {}
						cleanPlatforms[platform] = keyName
						kept += 1
					end
				end
				if cleanPlatforms then
					clean[actionName] = cleanPlatforms
				end
			end
		end
		data.Account.Keybindings = clean
	end)

	print("[SharedEventHandlers] Registered")
end

return SharedEventHandlers
