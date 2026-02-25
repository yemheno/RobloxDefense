-- ServerScriptService/Modules/NetworkManager

local NetworkManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local eventsFolder = nil
local remoteEvents = {}


-- INITIALIZATION
function NetworkManager.Init()
	-- Create Events folder
	eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	print("[NetworkManager] Initialized")
end


-- GET OR CREATE EVENT
function NetworkManager.GetEvent(eventName)
	-- Return cached event if exists
	if remoteEvents[eventName] then
		return remoteEvents[eventName]
	end

	-- Check if already in folder
	local event = eventsFolder:FindFirstChild(eventName)

	-- Create if doesn't exist
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = eventName
		event.Parent = eventsFolder
		print("[NetworkManager] Created event:", eventName)
	end

	-- Cache and return
	remoteEvents[eventName] = event
	return event
end

-- FIRE EVENTS
function NetworkManager.FireClient(player, eventName, ...)
	local event = NetworkManager.GetEvent(eventName)
	event:FireClient(player, ...)
end

function NetworkManager.FireAllClients(eventName, ...)
	local event = NetworkManager.GetEvent(eventName)
	event:FireAllClients(...)
end


-- LISTEN FOR CLIENT EVENTS
function NetworkManager.OnClientEvent(eventName, callback)
	local event = NetworkManager.GetEvent(eventName)
	event.OnServerEvent:Connect(callback)
end

return NetworkManager