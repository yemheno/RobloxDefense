-- ServerScriptService/Modules/ResourceManager

local ResourceManager = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local ClassManager -- Lazy loaded to avoid circular dependency

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

local CONFIG = {
	UpdateRate = 0.1,              -- How often to run regen/decay (seconds)
	NotifyClientOnChange = true,   -- Fire event when resource changes
	NotifyThreshold = 1,           -- Minimum change to notify client
}

-- ═══════════════════════════════════════════════════════════
-- INTERNAL STATE
-- ═══════════════════════════════════════════════════════════

local playerResources = {}  -- { [player] = { current, max, className, lastUpdate } }
local ClassBehaviors = {}   -- { [className] = behaviorModule }

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function ResourceManager.Init()
	-- Load ClassManager
	ClassManager = require(Modules:WaitForChild("ClassManager"))

	-- Load all class behaviors
	local behaviorsFolder = Modules:FindFirstChild("ClassBehaviors")
	if behaviorsFolder then
		for _, behaviorModule in ipairs(behaviorsFolder:GetChildren()) do
			if behaviorModule:IsA("ModuleScript") then
				local success, behavior = pcall(require, behaviorModule)
				if success then
					-- Extract class name from module name (e.g., "AegisBehavior" → "Aegis")
					local className = behaviorModule.Name:gsub("Behavior", "")
					ClassBehaviors[className] = behavior

					if behavior.Init then
						behavior.Init()
					end

					print("[ResourceManager] Loaded behavior:", className)
				else
					warn("[ResourceManager] Failed to load behavior:", behaviorModule.Name, behavior)
				end
			end
		end
	else
		warn("[ResourceManager] ClassBehaviors folder not found!")
	end

	-- Create network events
	NetworkManager.GetEvent("ResourceUpdate")

	-- Player connections
	Players.PlayerAdded:Connect(ResourceManager.SetupPlayer)
	Players.PlayerRemoving:Connect(ResourceManager.RemovePlayer)

	-- Setup existing players
	for _, player in ipairs(Players:GetPlayers()) do
		ResourceManager.SetupPlayer(player)
	end

	-- Update loop for regen/decay
	RunService.Heartbeat:Connect(function(dt)
		ResourceManager.Update(dt)
	end)

	print("[ResourceManager] Initialized with", ResourceManager.GetBehaviorCount(), "behaviors")
end

function ResourceManager.SetupPlayer(player)
	local className = ClassManager.GetClassName(player)
	local behavior = ClassBehaviors[className]

	local maxResource = 100
	local startingResource = 0

	if behavior and behavior.CONFIG then
		maxResource = behavior.CONFIG.MaxResource or 100
		startingResource = behavior.CONFIG.StartingResource or 0
	end

	playerResources[player] = {
		current = startingResource,
		max = maxResource,
		className = className,
		lastUpdate = tick(),
		lastNotifiedValue = startingResource,
	}

	-- Notify client of initial state
	ResourceManager.NotifyClient(player, true)

	print("[ResourceManager] Setup for", player.Name, "- Class:", className, "- Resource:", startingResource, "/", maxResource)
end

function ResourceManager.RemovePlayer(player)
	playerResources[player] = nil
end

-- ═══════════════════════════════════════════════════════════
-- CORE OPERATIONS
-- ═══════════════════════════════════════════════════════════

function ResourceManager.GetResource(player)
	local data = playerResources[player]
	return data and data.current or 0
end

function ResourceManager.GetMaxResource(player)
	local data = playerResources[player]
	return data and data.max or 100
end

function ResourceManager.GetResourcePercent(player)
	local data = playerResources[player]
	if not data or data.max == 0 then return 0 end
	return (data.current / data.max) * 100
end

function ResourceManager.GetResourceName(player)
	local data = playerResources[player]
	if not data then return "Resource" end

	local behavior = ClassBehaviors[data.className]
	if behavior and behavior.CONFIG and behavior.CONFIG.ResourceName then
		return behavior.CONFIG.ResourceName
	end

	return "Resource"
end

function ResourceManager.SetResource(player, value)
	local data = playerResources[player]
	if not data then return false end

	local oldValue = data.current
	data.current = math.clamp(value, 0, data.max)

	-- Check for full/empty callbacks
	if oldValue < data.max and data.current >= data.max then
		ResourceManager.OnResourceFull(player)
	elseif oldValue > 0 and data.current <= 0 then
		ResourceManager.OnResourceEmpty(player)
	end

	ResourceManager.NotifyClient(player)
	return true
end

function ResourceManager.ModifyResource(player, amount)
	local data = playerResources[player]
	if not data then return false end

	return ResourceManager.SetResource(player, data.current + amount)
end

function ResourceManager.SetResourcePercent(player, percent)
	local data = playerResources[player]
	if not data then return false end

	local value = (percent / 100) * data.max
	return ResourceManager.SetResource(player, value)
end

-- ═══════════════════════════════════════════════════════════
-- UPDATE LOOP (Regen/Decay)
-- ═══════════════════════════════════════════════════════════

function ResourceManager.Update(dt)
	local now = tick()

	for player, data in pairs(playerResources) do
		-- Throttle updates
		if now - data.lastUpdate < CONFIG.UpdateRate then
			continue
		end

		local elapsed = now - data.lastUpdate
		data.lastUpdate = now

		-- Get behavior for this class
		local behavior = ClassBehaviors[data.className]
		if not behavior or not behavior.GetResourceRate then
			continue
		end

		-- Get HitTracker for timing info
		local HitTracker = Modules:FindFirstChild("HitTracker")
		local timeSinceHitDealt = math.huge
		local timeSinceHitReceived = math.huge

		if HitTracker then
			local ht = require(HitTracker)
			timeSinceHitDealt = ht.GetTimeSinceLastHitDealt(player)
			timeSinceHitReceived = ht.GetTimeSinceLastHitReceived(player)
		end

		-- Calculate rate from behavior
		local rate = behavior.GetResourceRate(player, {
			current = data.current,
			max = data.max,
			timeSinceHitDealt = timeSinceHitDealt,
			timeSinceHitReceived = timeSinceHitReceived,
		})

		if rate and rate ~= 0 then
			local change = rate * elapsed
			ResourceManager.ModifyResource(player, change)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- EVENT HOOKS (Called by HitTracker)
-- ═══════════════════════════════════════════════════════════

function ResourceManager.OnHitDealt(player, hitData)
	local data = playerResources[player]
	if not data then return end

	local behavior = ClassBehaviors[data.className]
	if not behavior or not behavior.OnHitDealt then return end

	local resourceChange = behavior.OnHitDealt(player, hitData, {
		current = data.current,
		max = data.max,
	})

	if resourceChange and resourceChange ~= 0 then
		ResourceManager.ModifyResource(player, resourceChange)
	end
end

function ResourceManager.OnHitReceived(player, hitData)
	local data = playerResources[player]
	if not data then return end

	local behavior = ClassBehaviors[data.className]
	if not behavior or not behavior.OnHitReceived then return end

	local resourceChange = behavior.OnHitReceived(player, hitData, {
		current = data.current,
		max = data.max,
	})

	if resourceChange and resourceChange ~= 0 then
		ResourceManager.ModifyResource(player, resourceChange)
	end
end

-- ═══════════════════════════════════════════════════════════
-- CLASS CHANGE (Called by ClassManager)
-- ═══════════════════════════════════════════════════════════

function ResourceManager.OnClassChanged(player, newClassName, oldClassName)
	local data = playerResources[player]
	if not data then return end

	-- Update class reference
	data.className = newClassName

	-- Get new class resource config from behavior
	local behavior = ClassBehaviors[newClassName]
	local maxResource = 100
	local startingResource = 0

	if behavior and behavior.CONFIG then
		maxResource = behavior.CONFIG.MaxResource or 100
		startingResource = behavior.CONFIG.StartingResource or 0
	end

	data.max = maxResource
	data.current = startingResource
	data.lastNotifiedValue = startingResource

	-- Notify client
	ResourceManager.NotifyClient(player, true)

	print("[ResourceManager]", player.Name, "class changed:", oldClassName, "→", newClassName, 
		"- Resource reset to:", startingResource, "/", maxResource)
end

-- ═══════════════════════════════════════════════════════════
-- CALLBACKS (Full/Empty)
-- ═══════════════════════════════════════════════════════════

function ResourceManager.OnResourceFull(player)
	local data = playerResources[player]
	if not data then return end

	local behavior = ClassBehaviors[data.className]
	if behavior and behavior.OnResourceFull then
		behavior.OnResourceFull(player)
	end

	-- Could fire event for UI effects
end

function ResourceManager.OnResourceEmpty(player)
	local data = playerResources[player]
	if not data then return end

	local behavior = ClassBehaviors[data.className]
	if behavior and behavior.OnResourceEmpty then
		behavior.OnResourceEmpty(player)
	end
end

-- ═══════════════════════════════════════════════════════════
-- CLIENT NOTIFICATION
-- ═══════════════════════════════════════════════════════════

function ResourceManager.NotifyClient(player, force)
	if not CONFIG.NotifyClientOnChange then return end

	local data = playerResources[player]
	if not data then return end

	-- Only notify if change is significant (or forced)
	local change = math.abs(data.current - data.lastNotifiedValue)
	if not force and change < CONFIG.NotifyThreshold then
		return
	end

	data.lastNotifiedValue = data.current

	NetworkManager.FireClient(player, "ResourceUpdate", {
		current = data.current,
		max = data.max,
		percent = ResourceManager.GetResourcePercent(player),
		name = ResourceManager.GetResourceName(player),
		className = data.className,
	})
end

-- ═══════════════════════════════════════════════════════════
-- BEHAVIOR ACCESS
-- ═══════════════════════════════════════════════════════════

function ResourceManager.GetBehavior(className)
	return ClassBehaviors[className]
end

function ResourceManager.GetBehaviorCount()
	local count = 0
	for _ in pairs(ClassBehaviors) do
		count = count + 1
	end
	return count
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function ResourceManager.GetDebugInfo(player)
	local data = playerResources[player]
	if not data then return "No resource data" end

	local behavior = ClassBehaviors[data.className]
	local behaviorConfig = behavior and behavior.CONFIG or {}

	local lines = {
		"=== ResourceManager Debug ===",
		"Class: " .. data.className,
		"Resource: " .. ResourceManager.GetResourceName(player),
		"Current: " .. string.format("%.1f", data.current),
		"Max: " .. data.max,
		"Percent: " .. string.format("%.1f%%", ResourceManager.GetResourcePercent(player)),
		"--- Behavior Config ---",
	}

	for key, value in pairs(behaviorConfig) do
		table.insert(lines, "  " .. key .. ": " .. tostring(value))
	end

	return table.concat(lines, "\n")
end

return ResourceManager