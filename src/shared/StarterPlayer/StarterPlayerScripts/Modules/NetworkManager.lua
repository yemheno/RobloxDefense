-- Client NetworkManager

local NetworkManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local eventsFolder = nil
local remoteEvents = {}

-- §NM-CLIENT-RACE: under memory pressure the server can take longer than
-- 3 s to finish pre-registering its ~100 RemoteEvents in NetworkManager.Init.
-- The OLD client GetEvent used WaitForChild(name, 3) and silently returned
-- nil on timeout, which meant any client `OnServerEvent` registered before
-- the matching server event existed had its listener PERMANENTLY DROPPED.
-- The most painful case: PlayerAttack.Init's "CombatConfig" listener loses
-- the race → combatConfig stays nil forever → DoAttack silently returns at
-- the `if not combatConfig then return end` guard → player can't basic
-- attack for the entire session. Matches Pablo's "transversal battle-mode
-- bug only when memory is high" report.
--
-- New behavior: GetEvent waits indefinitely by default (the events ARE
-- coming, the server registers them all in its boot loop), and
-- OnServerEvent defers the connection in a worker thread so Init never
-- blocks. Callers see a connection-stub immediately whose :Disconnect
-- tears down the real connection once it lands.
local DEFAULT_FIRE_TIMEOUT = 5  -- short wait for FireServer; if event truly missing, give up

-- INITIALIZATION
function NetworkManager.Init()
	eventsFolder = ReplicatedStorage:WaitForChild("Events")
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
		warn("[NetworkManager] GetEvent called before Init():", eventName)
		return nil
	end

	-- Wait for event. Pass nil through to WaitForChild for infinite wait;
	-- pass a number for bounded wait.
	local event
	if timeout then
		event = eventsFolder:WaitForChild(eventName, timeout)
	else
		event = eventsFolder:WaitForChild(eventName)
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
		-- If Init hasn't run yet, wait for eventsFolder to materialize.
		while not eventsFolder do task.wait(0.1) end
		local event = eventsFolder:WaitForChild(eventName)  -- infinite wait
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