-- UI/Shell/BadgeStore.lua
--[[
    §AGX/UI-P3: menu badge counts (docs/ui_audit/shell-spec.md §3.7).
    A module-level store; the Shell calls BadgeStore.init(place) once, the
    menu surfaces read it (Shell/Badge.lua renders the dot).

    API
        BadgeStore.init(place)          idempotent; subscribes to the sources
        BadgeStore.get(key) -> n        0 when unset
        BadgeStore.set(key, n)
        BadgeStore.clear(key)
        BadgeStore.sum(keys) -> n       group badge = OR (sum) of its entries
        BadgeStore.any() -> n           the collapsed ☰ badge (everything)
        BadgeStore.subscribe(cb) -> unsub      cb(counts)
        BadgeStore.useBadge(key) -> n          React
        BadgeStore.useBadges(keys?) -> n       React; nil keys = any()
        BadgeStore.forEntry(entryId) -> key | nil   (Registry entry.badge)

    SOURCES
        daily        DailyLoginStatus.canClaim -> 1; DailyLoginResult ok or a
                     later canClaim=false -> 0
        stats        StatsUpdate.unallocated (GetStats on init and whenever
                     PlayerInfoUpdate.level increases)
        talents      TalentClient.Subscribe -> state.pointsAvailable
        achievements AchievementClient.OnUnlocked -> +1; cleared when the
                     achievements entry opens (Registry clearBadgeOnOpen)
        party        PartyInvite (Lobby) -> 1; PartyUpdate or 30 s -> 0
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React = require(ReplicatedStorage.Packages.React)

local BadgeStore = {}

local counts = {}
local listeners = {}
local listenerSeq = 0
local initialized = false

local PARTY_TTL = 30

local function notify()
	local snap = table.clone(counts)
	for _, cb in pairs(listeners) do
		task.spawn(cb, snap)
	end
end

function BadgeStore.get(key)
	return counts[key] or 0
end

function BadgeStore.set(key, n)
	n = math.max(0, math.floor(tonumber(n) or 0))
	if (counts[key] or 0) == n then return end
	counts[key] = (n > 0) and n or nil
	notify()
end

function BadgeStore.clear(key)
	BadgeStore.set(key, 0)
end

function BadgeStore.sum(keys)
	local total = 0
	for _, k in ipairs(keys or {}) do
		total += counts[k] or 0
	end
	return total
end

function BadgeStore.any()
	local total = 0
	for _, n in pairs(counts) do total += n end
	return total
end

function BadgeStore.subscribe(cb)
	listenerSeq += 1
	local id = listenerSeq
	listeners[id] = cb
	return function() listeners[id] = nil end
end

-- ── Registry link ────────────────────────────────────────

local Registry = nil
local function getRegistry()
	if Registry then return Registry end
	local mod = script.Parent:FindFirstChild("Registry")
	if mod then
		local ok, res = pcall(require, mod)
		if ok then Registry = res end
	end
	return Registry
end

function BadgeStore.forEntry(entryId)
	local R = getRegistry()
	local entry = R and R.get(entryId)
	return entry and entry.badge or nil
end

-- ── Sources ──────────────────────────────────────────────

local function modules()
	return Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
end

local function tryRequire(name)
	local ok, res = pcall(function()
		return require(modules():WaitForChild(name, 5))
	end)
	return ok and res or nil
end

--- Subscribe to every badge source (idempotent). `place` gates the
--- Lobby-only sources (party).
function BadgeStore.init(place)
	if initialized then return end
	initialized = true

	task.spawn(function()
		local NetworkManager = tryRequire("NetworkManager")
		if NetworkManager then
			-- daily
			NetworkManager.OnServerEvent("DailyLoginStatus", function(data)
				if type(data) ~= "table" then return end
				BadgeStore.set("daily", data.canClaim and 1 or 0)
			end)
			NetworkManager.OnServerEvent("DailyLoginResult", function(data)
				if type(data) == "table" and data.ok then
					BadgeStore.clear("daily")
				end
			end)

			-- stats
			NetworkManager.OnServerEvent("StatsUpdate", function(data)
				if type(data) ~= "table" then return end
				BadgeStore.set("stats", data.unallocated or 0)
			end)
			local lastLevel = nil
			NetworkManager.OnServerEvent("PlayerInfoUpdate", function(data)
				if type(data) ~= "table" or type(data.level) ~= "number" then return end
				if lastLevel and data.level > lastLevel then
					NetworkManager.FireServer("GetStats")
				end
				lastLevel = data.level
			end)
			NetworkManager.FireServer("GetStats")

			-- party (Lobby only: parties are formed there)
			if place == "Lobby" then
				local partyToken = 0
				NetworkManager.OnServerEvent("PartyInvite", function()
					partyToken += 1
					local mine = partyToken
					BadgeStore.set("party", 1)
					task.delay(PARTY_TTL, function()
						if partyToken == mine then BadgeStore.clear("party") end
					end)
				end)
				NetworkManager.OnServerEvent("PartyUpdate", function()
					partyToken += 1
					BadgeStore.clear("party")
				end)
			end
		end

		-- talents
		local TalentClient = tryRequire("TalentClient")
		if TalentClient and TalentClient.Subscribe then
			TalentClient.Subscribe(function(state)
				BadgeStore.set("talents", type(state) == "table" and state.pointsAvailable or 0)
			end)
		end

		-- achievements
		local AchievementClient = tryRequire("AchievementClient")
		if AchievementClient and AchievementClient.OnUnlocked then
			AchievementClient.OnUnlocked(function()
				BadgeStore.set("achievements", BadgeStore.get("achievements") + 1)
			end)
		end
	end)

	-- clear-on-open (achievements)
	local stackMod = script.Parent:FindFirstChild("PanelStack")
	if stackMod then
		local ok, PanelStack = pcall(require, stackMod)
		if ok and PanelStack and PanelStack.onOpen then
			PanelStack.onOpen(function(_, entry)
				if entry and entry.clearBadgeOnOpen and entry.badge then
					BadgeStore.clear(entry.badge)
				end
			end)
		end
	end
end

-- ── React ────────────────────────────────────────────────

function BadgeStore.useBadge(key)
	local n, setN = React.useState(BadgeStore.get(key))
	React.useEffect(function()
		setN(BadgeStore.get(key))
		return BadgeStore.subscribe(function(c)
			setN(c[key] or 0)
		end)
	end, { key })
	return n
end

function BadgeStore.useBadges(keys)
	local function read()
		return keys and BadgeStore.sum(keys) or BadgeStore.any()
	end
	local n, setN = React.useState(read())
	local sig = keys and table.concat(keys, ",") or "*"
	React.useEffect(function()
		setN(read())
		return BadgeStore.subscribe(function()
			setN(read())
		end)
	end, { sig })
	return n
end

return BadgeStore
