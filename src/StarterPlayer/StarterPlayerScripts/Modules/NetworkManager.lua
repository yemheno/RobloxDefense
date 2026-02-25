-- Client NetworkManager

local NetworkManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local eventsFolder = nil
local remoteEvents = {}

-- INITIALIZATION
function NetworkManager.Init()
	eventsFolder = ReplicatedStorage:WaitForChild("Events")
	print("[NetworkManager] Initialized (Client)")
end

-- GET EVENT (waits for it)
function NetworkManager.GetEvent(eventName)
	-- Return cached event if exists
	if remoteEvents[eventName] then
		return remoteEvents[eventName]
	end

	-- Wait for event
	local event = eventsFolder:WaitForChild(eventName, 10)

	if not event then
		warn("[NetworkManager] Event not found:", eventName)
		return nil
	end

	-- Cache and return
	remoteEvents[eventName] = event
	return event
end


-- FIRE TO SERVER
function NetworkManager.FireServer(eventName, ...)
	local event = NetworkManager.GetEvent(eventName)
	if event then
		event:FireServer(...)
	end
end


-- LISTEN FOR SERVER EVENTS
-- Returns the RBXScriptConnection so callers (e.g., React useEffect) can disconnect.
function NetworkManager.OnServerEvent(eventName, callback)
	local event = NetworkManager.GetEvent(eventName)
	if event then
		return event.OnClientEvent:Connect(callback)
	end
	return nil
end

return NetworkManager