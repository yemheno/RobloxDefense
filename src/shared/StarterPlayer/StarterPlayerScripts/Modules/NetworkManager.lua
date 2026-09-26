-- Client NetworkManager

local NetworkManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")          -- §AGX/UI-FREE: §NM-D6 watchdog
local RunService        = game:GetService("RunService")       -- §AGX/UI-FREE: §NM-D6 watchdog
local TeleportService   = game:GetService("TeleportService")  -- §AGX/UI-FREE: §NM-D6 Rejoin

local eventsFolder = nil
local remoteEvents = {}

-- §NM-CLIENT-RACE: under memory pressure the server can take longer than
-- 3 s to pre-register its ~100 RemoteEvents in NetworkManager.Init, and a
-- listener whose GetEvent timed out would be dropped for the session
-- (e.g. PlayerAttack's "CombatConfig" -> no basic attack at all). So
-- GetEvent waits indefinitely by default (the events ARE coming), and
-- OnServerEvent defers the connection in a worker thread so Init never
-- blocks. Callers see a connection-stub immediately whose :Disconnect
-- tears down the real connection once it lands.
local DEFAULT_FIRE_TIMEOUT = 5  -- short wait for FireServer; if event truly missing, give up

-- ═══════════════════════════════════════════════════════════
-- §AGX/UI-FREE: §NM-D6 / G25 HANG RECOVERY (connection watchdog)
-- ═══════════════════════════════════════════════════════════
-- The waits below are deliberately infinite, so a genuinely broken server
-- (crash, bad deploy, lost handshake) needs a way out. The watchdog does
-- NOT change any wait; it only watches the boot handshake:
--   • Init() starts the clock BEFORE its own WaitForChild("Events").
--   • ServerReady (ReadyGate-routed, fired by PlaceLifecycle in every
--     place, AFTER this client's ClientReady) is the "connected" signal.
--   • No ServerReady after STALL_SECONDS -> ONE sticky, non-modal Notify
--     banner "Still connecting…" with a Rejoin action, plus a warn naming
--     every remote still being waited on. The warn repeats at most every
--     LOG_REPEAT_SECONDS; the banner is keyed, so it can never stack.
--   • ServerReady arrives -> the banner is cleared (one "Connected" toast,
--     only if the banner was ever raised) and the watchdog thread exits.
-- Nothing is kicked or teleported automatically: don't kick slow PCs /
-- mobiles mid-load (ARCHITECTURE.md#network). While the LoadingScreen
-- overlay is up (DisplayOrder 1000) the banner waits in the Notify store
-- and shows the moment the overlay goes (its own 25 s failsafe).
-- After the handshake the server has registered every event, so a
-- deferred listener still waiting is a never-registered name (a code bug,
-- not a connection issue): it is logged once, never prompted.
local STALL_SECONDS      = 15    -- handshake / listener wait before we speak up
local LOG_REPEAT_SECONDS = 30    -- "still waiting" warn cadence while stalled
local REJOIN_COOLDOWN    = 10    -- s between Rejoin presses (TeleportService)
local STALL_BANNER_KEY   = "nm_stall"

local watchdogStarted = false
local handshakeDone   = false
local stallShown      = false
local bootClock       = nil
local pendingWaits    = {}   -- [token] = { name = string, since = os.clock() }
local lastRejoinAt    = -math.huge
local teleportConn    = nil

local function beginWait(name)
	local token = {}
	pendingWaits[token] = { name = name, since = os.clock() }
	return token
end

local function endWait(token)
	pendingWaits[token] = nil
end

-- One warn per wait that outlives the handshake (the server registers every
-- event before ServerReady, so this is a never-registered name).
local function logOrphan(token)
	local w = pendingWaits[token]
	if not w or w.logged then return end
	w.logged = true
	warn(string.format(
		"[NetworkManager] §NM-D6: still waiting for %q %ds after ServerReady — event never registered?",
		w.name, math.floor(os.clock() - w.since)))
end

local function pendingNames()
	local names = {}
	for _, w in pairs(pendingWaits) do
		table.insert(names, string.format("%s (%ds)", w.name, math.floor(os.clock() - w.since)))
	end
	table.sort(names)
	return (#names > 0) and table.concat(names, ", ") or "none"
end

-- Lazy getter (house pattern): Notify requires THIS module at load, so it
-- can only be required here, at stall time, never at the top.
local notifyModule = nil
local function getNotify()
	if notifyModule == nil then
		local ok, res = pcall(function()
			local ps = Players.LocalPlayer:WaitForChild("PlayerScripts")
			local ui = ps:WaitForChild("UI", 5)
			local common = ui and ui:WaitForChild("Common", 5)
			local mod = common and common:WaitForChild("Notify", 5)
			return mod and require(mod) or nil
		end)
		if ok and res then
			notifyModule = res
		else
			warn("[NetworkManager] §NM-D6: Notify unavailable for the stall prompt:", ok and "missing" or res)
			return nil
		end
	end
	return notifyModule
end

-- Rejoin target: the same place. In a reserved server (a match run) a
-- same-PlaceId teleport lands on a PUBLIC server that TeleportDataReader
-- bounces to the Lobby (§AGX/X4), so go to the Lobby directly.
local function rejoinTarget()
	local reserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
	if reserved then
		local ok, Shared = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Shared", 5))
		end)
		local lobbyId = ok and type(Shared) == "table" and Shared.PlaceIds and Shared.PlaceIds.Lobby
		if type(lobbyId) == "number" and lobbyId > 0 then
			return lobbyId
		end
	end
	return game.PlaceId
end

local function rejoin()
	local now = os.clock()
	if now - lastRejoinAt < REJOIN_COOLDOWN then return end   -- no double teleports
	lastRejoinAt = now

	local Notify = getNotify()
	if RunService:IsStudio() then
		warn("[NetworkManager] §NM-D6: Rejoin pressed (teleports do not work in Studio).")
		if Notify then Notify.toast("warning", "Rejoin isn't available in Studio.", { key = "nm_rejoin" }) end
		return
	end

	local player = Players.LocalPlayer
	if not teleportConn then
		-- Client-side failure feedback; the cooldown resets so the player can retry.
		teleportConn = player.OnTeleport:Connect(function(state)
			if state == Enum.TeleportState.Failed then
				lastRejoinAt = -math.huge
				warn("[NetworkManager] §NM-D6: Rejoin teleport failed.")
				local N = getNotify()
				if N then N.toast("error", "Rejoin failed. Try again in a moment.", { key = "nm_rejoin" }) end
			end
		end)
	end

	local target = rejoinTarget()
	warn(string.format("[NetworkManager] §NM-D6: Rejoin -> place %d (handshake still missing after %ds)",
		target, math.floor(os.clock() - (bootClock or now))))
	if Notify then Notify.toast("info", "Rejoining…", { key = "nm_rejoin" }) end
	local ok, err = pcall(function()
		TeleportService:Teleport(target, player)
	end)
	if not ok then
		lastRejoinAt = -math.huge
		warn("[NetworkManager] §NM-D6: Rejoin teleport errored:", err)
		if Notify then Notify.toast("error", "Rejoin failed. Try again in a moment.", { key = "nm_rejoin" }) end
	end
end

local function showStall()
	stallShown = true
	warn(string.format(
		"[NetworkManager] §NM-D6: no ServerReady after %ds — showing the Rejoin prompt. Waiting on: %s",
		STALL_SECONDS, pendingNames()))
	task.spawn(function()
		local Notify = getNotify()
		if not Notify or handshakeDone then return end
		Notify.banner("Still connecting…", {
			key      = STALL_BANNER_KEY,
			subtitle = "The server is taking longer than usual.",
			sticky   = true,
			priority = Notify.Priority.connection or "runState",
			action   = { label = "Rejoin", onActivated = rejoin },
		})
	end)
end

local function onHandshake()
	if handshakeDone then return end
	handshakeDone = true
	-- Waits that began before the handshake and still hang STALL_SECONDS
	-- later are orphans; log each once.
	task.delay(STALL_SECONDS, function()
		for token, w in pairs(pendingWaits) do
			if os.clock() - w.since >= STALL_SECONDS then logOrphan(token) end
		end
	end)
	if stallShown then
		warn(string.format("[NetworkManager] §NM-D6: ServerReady arrived after %ds — connection recovered.",
			math.floor(os.clock() - (bootClock or os.clock()))))
		task.spawn(function()
			local Notify = getNotify()
			if Notify then
				Notify.clearBanner(STALL_BANNER_KEY)
				Notify.toast("success", "Connected.", { key = STALL_BANNER_KEY })
			end
		end)
	end
end

local function startWatchdog()
	if watchdogStarted then return end
	watchdogStarted = true
	bootClock = os.clock()
	task.spawn(function()
		local lastLog = 0
		while not handshakeDone do
			local now = os.clock()
			if not stallShown then
				if now - bootClock >= STALL_SECONDS then
					showStall()
					lastLog = now
				end
			elseif now - lastLog >= LOG_REPEAT_SECONDS then
				lastLog = now
				warn(string.format("[NetworkManager] §NM-D6: still no ServerReady after %ds. Waiting on: %s",
					math.floor(now - bootClock), pendingNames()))
			end
			task.wait(1)
		end
	end)
end

--- §AGX/UI-FREE: true once this client's ServerReady handshake arrived.
function NetworkManager.IsConnected()
	return handshakeDone
end

-- INITIALIZATION
function NetworkManager.Init()
	-- §AGX/UI-FREE: §NM-D6: the clock starts BEFORE the Events wait, so a
	-- missing Events folder (server never booted) is caught too.
	startWatchdog()
	local token = beginWait("Events folder")
	eventsFolder = ReplicatedStorage:WaitForChild("Events")
	endWait(token)
	-- The handshake listener (deferred like any other; see OnServerEvent).
	NetworkManager.OnServerEvent("ServerReady", onHandshake)
end

-- GET EVENT (waits for it)
-- timeout: nil → wait indefinitely (default for listener registration);
--          number → wait up to N seconds.
function NetworkManager.GetEvent(eventName, timeout)
	-- Return cached event if exists
	if remoteEvents[eventName] then
		return remoteEvents[eventName]
	end

	if not eventsFolder then
		-- §AGX/UI-FREE: §NM-D6: a bounded call made before Init (e.g. the UI
		-- mount's ClientReady) must not be dropped here: that loses the
		-- handshake. Pick the folder up if it exists (bounded wait only).
		eventsFolder = ReplicatedStorage:FindFirstChild("Events")
			or (timeout and ReplicatedStorage:WaitForChild("Events", timeout))
			or nil
	end
	if not eventsFolder then
		warn("[NetworkManager] GetEvent called before Init():", eventName)
		return nil
	end

	-- Wait for event. Pass nil through to WaitForChild for infinite wait;
	-- pass a number for bounded wait.
	local event
	if timeout then
		event = eventsFolder:WaitForChild(eventName, timeout)
	else
		local token = beginWait(eventName)  -- §AGX/UI-FREE: §NM-D6 (named in stall logs)
		event = eventsFolder:WaitForChild(eventName)
		endWait(token)
	end

	if not event then
		warn("[NetworkManager] Event not found:", eventName)
		return nil
	end

	-- Cache and return
	remoteEvents[eventName] = event
	return event
end


-- FIRE TO SERVER
-- Bounded wait: if the event truly doesn't exist after a few seconds,
-- retrying isn't going to help — the server side never registered it.
function NetworkManager.FireServer(eventName, ...)
	local event = NetworkManager.GetEvent(eventName, DEFAULT_FIRE_TIMEOUT)
	if event then
		event:FireServer(...)
	end
end


-- LISTEN FOR SERVER EVENTS
-- Returns a connection-like object whose :Disconnect tears down the real
-- connection once it's ready. §NM-CLIENT-RACE: never silently drop the
-- listener — defer until the event arrives.
function NetworkManager.OnServerEvent(eventName, callback)
	-- Fast path: cached.
	if remoteEvents[eventName] then
		return remoteEvents[eventName].OnClientEvent:Connect(callback)
	end

	-- Fast path 2: already in folder but not cached yet.
	if eventsFolder then
		local immediate = eventsFolder:FindFirstChild(eventName)
		if immediate then
			remoteEvents[eventName] = immediate
			return immediate.OnClientEvent:Connect(callback)
		end
	end

	-- Slow path: defer the connection. Spawn a thread that waits forever
	-- for the event, then connects. Init returns immediately so module
	-- bootstrap is never blocked by a slow server registration.
	local realConn
	local disconnected = false
	task.spawn(function()
		-- §AGX/UI-FREE: §NM-D6: tracked so the stall log names it. Still
		-- waiting STALL_SECONDS after it was registered AND after the
		-- handshake -> logged ONCE (onHandshake sweeps the earlier ones).
		local token = beginWait(eventName)
		task.delay(STALL_SECONDS, function()
			if handshakeDone and not disconnected then logOrphan(token) end
		end)
		-- If Init hasn't run yet, wait for eventsFolder to materialize.
		while not eventsFolder do task.wait(0.1) end
		local event = eventsFolder:WaitForChild(eventName)  -- infinite wait
		endWait(token)
		if disconnected or not event then return end
		remoteEvents[eventName] = event
		realConn = event.OnClientEvent:Connect(callback)
	end)

	return {
		Disconnect = function()
			disconnected = true
			if realConn then
				realConn:Disconnect()
				realConn = nil
			end
		end,
	}
end

return NetworkManager