-- StarterPlayerScripts/Modules/AchievementClient.lua
--[[
    Client-side achievement cache.

    Subscribes to:
      "AchievementUnlocked"  → fires OnUnlocked callbacks (feeds the toast)
      "AchievementsData"     → full sync { stats, unlocked }

    Public API:
      Init()
      Request()                → fires "GetAchievements" to server
      GetUnlocked()            → { [id] = unixTimestamp }
      GetStats()               → player stats table
      IsUnlocked(id)           → bool
      OnUnlocked(fn)           → subscribe; returns unsub function
]]

local AchievementClient = {}

local Modules        = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- Local cache
local cachedUnlocked = {}
local cachedStats    = {}

-- Subscribers
local unlockCallbacks = {}
local dataCallbacks   = {}

-- ═══════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════

function AchievementClient.Init()
    NetworkManager.OnServerEvent("AchievementUnlocked", function(data)
        -- Store tier number (new format); data.tier may be nil for old saves
        cachedUnlocked[data.id] = data.tier or 1
        for _, cb in ipairs(unlockCallbacks) do
            pcall(cb, data)
        end
    end)

    NetworkManager.OnServerEvent("AchievementsData", function(data)
        cachedUnlocked = data.unlocked or {}
        cachedStats    = data.stats    or {}
        for _, cb in ipairs(dataCallbacks) do
            pcall(cb)
        end
    end)

    AchievementClient.Request()
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════

function AchievementClient.Request()
    NetworkManager.FireServer("GetAchievements")
end

function AchievementClient.GetUnlocked()
    return cachedUnlocked
end

function AchievementClient.GetStats()
    return cachedStats
end

function AchievementClient.IsUnlocked(id)
    local tier = cachedUnlocked[id]
    return type(tier) == "number" and tier >= 1
end

--- Returns the current tier level for an achievement (0 if not started).
function AchievementClient.GetTier(id)
    local tier = cachedUnlocked[id]
    if type(tier) == "number" then return tier end
    -- Legacy boolean/timestamp: treat as tier 1
    if tier then return 1 end
    return 0
end

--- Subscribe to unlock events. Returns an unsubscribe function.
function AchievementClient.OnUnlocked(callback)
    table.insert(unlockCallbacks, callback)
    return function()
        for i, cb in ipairs(unlockCallbacks) do
            if cb == callback then
                table.remove(unlockCallbacks, i)
                break
            end
        end
    end
end

--- Subscribe to initial data load. Returns an unsubscribe function.
function AchievementClient.OnDataReceived(callback)
    table.insert(dataCallbacks, callback)
    return function()
        for i, cb in ipairs(dataCallbacks) do
            if cb == callback then
                table.remove(dataCallbacks, i)
                break
            end
        end
    end
end

return AchievementClient
