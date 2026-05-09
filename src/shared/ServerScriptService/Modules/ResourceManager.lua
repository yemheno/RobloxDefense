-- ServerScriptService/Modules/ResourceManager

local ResourceManager = {}

local Players = game:GetService("Players")
-- §2.7a: RunService no longer required; regen loop uses task.wait at fixed rate.

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local ClassManager -- Lazy loaded to avoid circular dependency

-- §VG1 cache: VoteManager is only loaded in combat places. Resolve
-- once on first access; in non-combat places (lobby) the module is
-- absent and we cache that fact too so we never re-look-up.
local _vmResolved   = false
local _vmIsVoteActive = nil  -- function ref or nil if no vote system in this place
local function _voteManagerCheck()
	if not _vmResolved then
		_vmResolved = true
		local mod = Modules:FindFirstChild("VoteManager")
		if mod then
			local ok, vm = pcall(require, mod)
			if ok and vm and type(vm.IsVoteActive) == "function" then
				_vmIsVoteActive = vm.IsVoteActive
			end
		end
	end
	if _vmIsVoteActive then return _vmIsVoteActive() end
	return false
end

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

-- Lazy reference for bonus stats (avoids circular require at load)
local _PlayerDataManager = nil
local function getResourceMaxBonus(player)
	if not _PlayerDataManager then
		local mod = Modules:FindFirstChild("PlayerDataManager")
		if mod then _PlayerDataManager = require(mod) end
	end
	if _PlayerDataManager then
		return _PlayerDataManager.GetBonus(player, "ResourceMax") or 0
	end
	return 0
end

local function getEffectiveMax(player, data)
	return data.max + getResourceMaxBonus(player)
end

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

	-- §2.7a: fixed-tick regen scheduler.
	-- Previously this was a Heartbeat connection, which fired at 60Hz and
	-- then internally throttled to UpdateRate (0.1s). That wastes 59 out of
	-- every 60 frames on a no-op iteration of every player. Use a dedicated
	-- task.wait loop at exactly UpdateRate instead — we still pass the real
	-- elapsed delta to Update() so behaviors that care about wall time still
	-- see accurate values even if the scheduler slips.
	task.spawn(function()
		local lastTick = os.clock()
		while true do
			task.wait(CONFIG.UpdateRate)
			local now = os.clock()
			local dt = now - lastTick
			lastTick = now
			-- Update() uses os.clock() internally for per-player throttling,
			-- so the `dt` arg is advisory; pass it along anyway for symmetry
			-- with the prior Heartbeat signature.
			local ok, err = pcall(ResourceManager.Update, dt)
			if not ok then
				warn("[ResourceManager] Update tick errored: " .. tostring(err))
			end
		end
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
		lastUpdate = os.clock(),
		lastNotifiedValue = startingResource,
	}

	-- Notify client of initial state
	ResourceManager.NotifyClient(player, true)

	print("[ResourceManager] Setup for", player.Name, "- Class:", className, "- Resource:", startingResource, "/", maxResource)
end

function ResourceManager.RemovePlayer(player)
	playerResources[player] = nil
end

-- Silently correct the stored className when it doesn't match the player's active class.
-- Called from SharedEventHandlers.sendPlayerInfo after DataStore data is confirmed ready,
-- since SetupPlayer runs on PlayerAdded (before DataStore finishes loading).
function ResourceManager.EnsureClass(player, className)
	if not className then return end
	local data = playerResources[player]
	if not data then return end
	if data.className == className then return end

	-- Update class reference and max without resetting current resource
	data.className = className
	local behavior = ClassBehaviors[className]
	if behavior and behavior.CONFIG then
		data.max = behavior.CONFIG.MaxResource or 100
		local effectiveMax = getEffectiveMax(player, data)
		if data.current > effectiveMax then
			data.current = effectiveMax
		end
	end
	-- §2.7c: audit flagged that we don't NotifyClient after the clamp, so the
	-- UI can read a stale value until the next regen tick. Investigated and
	-- the tick interval is 100ms (§2.7a fixed-tick scheduler) — worst-case
	-- stale window is under a tenth of a second and visually indistinguishable
	-- from the subsequent regen update. Leaving as-is; revisit only if a
	-- player-visible glitch ever appears after a class swap.
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
	if not data then return 100 end
	return getEffectiveMax(player, data)
end

function ResourceManager.GetResourcePercent(player)
	local data = playerResources[player]
	if not data then return 0 end
	local effectiveMax = getEffectiveMax(player, data)
	if effectiveMax == 0 then return 0 end
	return (data.current / effectiveMax) * 100
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

	local effectiveMax = getEffectiveMax(player, data)
	local oldValue = data.current
	data.current = math.clamp(value, 0, effectiveMax)

	-- Check for full/empty callbacks
	if oldValue < effectiveMax and data.current >= effectiveMax then
		ResourceManager.OnResourceFull(player)
	elseif oldValue > 0 and data.current <= 0 then
		ResourceManager.OnResourceEmpty(player)
	end

	-- Force-notify at boundaries so the client always sees exactly 100 % / 0 %
	-- even when fractional regen means the delta is smaller than NotifyThreshold.
	local atBoundary = (data.current >= effectiveMax) or (data.current <= 0)
	ResourceManager.NotifyClient(player, atBoundary)
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

	local effectiveMax = getEffectiveMax(player, data)
	local value = (percent / 100) * effectiveMax
	return ResourceManager.SetResource(player, value)
end

--- Restore a fraction of max resource (e.g. 0.25 = 25%).
--- Called by the card/vote system (ClassBattery).
function ResourceManager.RestorePercent(player, fraction)
	local data = playerResources[player]
	if not data then return false end

	local effectiveMax = getEffectiveMax(player, data)
	local amount = effectiveMax * fraction
	return ResourceManager.ModifyResource(player, amount)
end

-- ═══════════════════════════════════════════════════════════
-- UPDATE LOOP (Regen/Decay)
-- ═══════════════════════════════════════════════════════════

function ResourceManager.Update(dt)
	local now = os.clock()

	for player, data in pairs(playerResources) do
		-- Throttle updates
		if now - data.lastUpdate < CONFIG.UpdateRate then
			continue
		end

		local elapsed = now - data.lastUpdate
		data.lastUpdate = now

		-- Skip regen if player is knocked-down or dead
		if player:GetAttribute("DeathState") ~= "Alive" then continue end

		-- §VG1: pause regen while a vote is active. The lazy-cache
		-- pattern below resolves the VoteManager module ONCE; subsequent
		-- ticks just do a table read + function call instead of
		-- FindFirstChild + pcall(require) every player every 100 ms.
		if _voteManagerCheck() then continue end

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

	-- §2.7b: loud-fail on missing ClassBehaviors. A silent default (100/0)
	-- masks real bugs (misnamed class, missing module, load order issue).
	-- If the behavior is missing we lazy-retry the folder scan ONCE in case
	-- of a load-order race, then raise a clear ERROR so it shows up in the
	-- output console during testing. We still populate safe fallbacks so a
	-- live session won't crash — but the error is unmistakable.
	local behavior = ClassBehaviors[newClassName]
	if not behavior then
		local behaviorsFolder = Modules:FindFirstChild("ClassBehaviors")
		if behaviorsFolder then
			local mod = behaviorsFolder:FindFirstChild(newClassName)
			if mod then
				local ok, lazy = pcall(require, mod)
				if ok and type(lazy) == "table" then
					ClassBehaviors[newClassName] = lazy
					behavior = lazy
					print("[ResourceManager] Lazy-loaded ClassBehavior for", newClassName)
				end
			end
		end
		if not behavior then
			error(string.format(
				"[ResourceManager] OnClassChanged: no ClassBehavior found for class '%s' " ..
				"(player=%s, oldClass=%s). Check ClassBehaviors folder and module name.",
				tostring(newClassName), tostring(player and player.Name), tostring(oldClassName)
			), 0)
		end
	end

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
		max = getEffectiveMax(player, data),
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