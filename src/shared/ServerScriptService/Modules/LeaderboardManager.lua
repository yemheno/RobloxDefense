-- ServerScriptService/Modules/LeaderboardManager.lua
--[[
    Server-side leaderboard system using OrderedDataStores.

    Maintains three leaderboards:
      PowerLevel      — computed via GearRating.GetDisplayPower() (unified Power Rating)
      HighestWave     — from data.Account.HighestWaveReached
      TotalPlayTime   — from data.Account.TotalPlayTime

    Each leaderboard is an OrderedDataStore. Scores are persisted periodically
    (every UPDATE_INTERVAL seconds) and on player removal.

    Clients can request leaderboard data via "GetLeaderboard" event.

    Network events:
      Client → Server    "GetLeaderboard"    → { board }  ("GearScore" | "HighestWave" | "TotalPlayTime")
      Server → Client    "LeaderboardData"   → { board, entries = { {rank, name, userId, score}, ... } }
      Server → Client    "PlayerGearScore"   → { score, breakdown }

    Public API:
      LeaderboardManager.Init()
      LeaderboardManager.UpdatePlayer(player)     — recalculate + persist
      LeaderboardManager.GetTopEntries(board, count) → { {rank, name, userId, score}, ... }
]]

local DataStoreService  = game:GetService("DataStoreService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeaderboardManager = {}

-- Name cache to avoid repeated GetNameFromUserIdAsync calls
local nameCache = {}
local Modules = script.Parent

-- Lazily loaded
local NetworkManager    = nil
local PlayerDataManager = nil
local GearRating        = nil

local function getNet()
    if not NetworkManager then
        NetworkManager = require(Modules:WaitForChild("NetworkManager"))
    end
    return NetworkManager
end

local function getDataManager()
    if not PlayerDataManager then
        PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
    end
    return PlayerDataManager
end

local function getGearRating()
    if not GearRating then
        GearRating = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GearRating"))
    end
    return GearRating
end

-- ═══════════════════════════════════════════════════════════
-- DATASTORES
-- ═══════════════════════════════════════════════════════════

local BOARD_NAMES = {
    GearScore     = "Leaderboard_GearScore_v1",
    HighestWave   = "Leaderboard_HighestWave_v1",
    TotalPlayTime = "Leaderboard_TotalPlayTime_v1",
}

--- Safely get an OrderedDataStore. Returns nil if DataStores are unavailable (Studio).
local stores = {}
local function getStore(board)
    if stores[board] then return stores[board] end
    local storeName = BOARD_NAMES[board]
    if not storeName then return nil end

    local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, storeName)
    if ok and store then
        stores[board] = store
        return store
    end
    return nil
end

-- §LB2: persistence cadence. Every player's score is persisted at
-- most once per UPDATE_INTERVAL — staggered (see scheduleNextUpdate
-- below) so a server full of players never thrash-writes them all at
-- the same minute. Two hours per player matches the standard pattern
-- used by big-roster games (e.g. ranking refreshes are not real-time).
-- The viewer's OWN row is replaced with their live GearScore inside
-- GetTopEntries before the data leaves the server, so a player never
-- sees their own number lag behind reality (§LB3).
local UPDATE_INTERVAL = 7200  -- 2 hours between periodic persists per player
local MAX_ENTRIES     = 50    -- top N entries per board

-- ═══════════════════════════════════════════════════════════
-- SCORE EXTRACTION
-- ═══════════════════════════════════════════════════════════

local function getScores(player)
    local dm   = getDataManager()
    local data = dm.GetData(player)
    if not data or not data.Account then return nil end

    local gr = getGearRating()
    local breakdown = gr.GetBreakdown(data)
    local powerLevel = breakdown.displayPower or breakdown.total or 0

    return {
        GearScore     = powerLevel,
        HighestWave   = data.Account.HighestWaveReached or 0,
        TotalPlayTime = math.floor(data.Account.TotalPlayTime or 0),
    }
end

-- ═══════════════════════════════════════════════════════════
-- PERSISTENCE
-- ═══════════════════════════════════════════════════════════

--- Write a player's scores to all OrderedDataStores.
local function persistScores(player, scores)
    if not scores then return end
    local key = "player_" .. tostring(player.UserId)

    for board, score in pairs(scores) do
        if score > 0 then
            local store = getStore(board)
            if store then
                local ok, err = pcall(store.SetAsync, store, key, score)
                if not ok then
                    warn("[LeaderboardManager] SetAsync failed for", board, ":", err)
                end
            end
        end
    end
end

--- Recalculate and persist scores for a player.
function LeaderboardManager.UpdatePlayer(player)
    local scores = getScores(player)
    if scores then
        -- Persist PowerLevel into player data for reference
        local dm = getDataManager()
        local data = dm.GetData(player)
        if data and data.Account then
            if not data.Account.Leaderboard then
                data.Account.Leaderboard = {}
            end
            data.Account.Leaderboard.GearScore = scores.GearScore
        end
        task.spawn(persistScores, player, scores)
    end
end

-- ═══════════════════════════════════════════════════════════
-- READING
-- ═══════════════════════════════════════════════════════════

-- §T5-T9/S4: per-board TTL cache for the sorted page. Every client
-- GetLeaderboard used to hit OrderedDataStore:GetSortedAsync directly —
-- a quota burn under concurrent requests. The RAW page is cached; the
-- §LB3 viewer-row substitution still runs per request on a copy, so
-- each viewer keeps seeing their live score.
local BOARD_CACHE_TTL = 30
local boardCache = {}  -- [board] = { time = os.clock(), page = {...} }

--- Fetch top entries from an OrderedDataStore.
--- Returns { {rank, name, userId, score}, ... }
function LeaderboardManager.GetTopEntries(board, count, viewer)
    count = count or MAX_ENTRIES

    local cached = boardCache[board]
    local pageData
    if cached and (os.clock() - cached.time) < BOARD_CACHE_TTL then
        pageData = cached.page
    else
        local store = getStore(board)
        if not store then return {} end
        local ok, pages = pcall(store.GetSortedAsync, store, false, count)
        if not ok or not pages then return {} end
        pageData = pages:GetCurrentPage()
        boardCache[board] = { time = os.clock(), page = pageData }
    end

    local entries = {}
    local rank = 0
    for _, entry in ipairs(pageData) do
        rank = rank + 1
        local userId = tonumber(string.match(entry.key, "player_(%d+)"))
        local playerName = "Unknown"
        if userId then
            -- Check cache first, then live Players, then async lookup
            if nameCache[userId] then
                playerName = nameCache[userId]
            else
                local live = Players:GetPlayerByUserId(userId)
                if live then
                    playerName = live.Name
                    nameCache[userId] = playerName
                else
                    local nameOk, name = pcall(function()
                        return Players:GetNameFromUserIdAsync(userId)
                    end)
                    if nameOk and name then
                        playerName = name
                    end
                    nameCache[userId] = playerName
                end
            end
        end
        local score = entry.value
        -- §LB3: viewer's own row reflects their LIVE score, not the
        -- (up to UPDATE_INTERVAL old) persisted one. Other players'
        -- rows stay as-stored — eventual consistency for them is the
        -- whole point of the staggered persist cadence.
        if viewer and userId == viewer.UserId then
            local fresh = getScores(viewer)
            if fresh and fresh[board] then
                score = fresh[board]
            end
        end

        table.insert(entries, {
            rank   = rank,
            name   = playerName,
            userId = userId,
            score  = score,
        })
    end

    return entries
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function LeaderboardManager.Init()
    local net = getNet()

    net.GetEvent("GetLeaderboard")
    net.GetEvent("LeaderboardData")
    net.GetEvent("PlayerGearScore")

    -- Client requests leaderboard data
    net.OnClientEvent("GetLeaderboard", function(player, board)
        if type(board) ~= "string" or not BOARD_NAMES[board] then return end

        -- §LB3: pass the player so GetTopEntries can replace their
        -- own row with the live computed score (other rows stay
        -- as-stored from the last persist tick).
        local entries = LeaderboardManager.GetTopEntries(board, MAX_ENTRIES, player)
        net.FireClient(player, "LeaderboardData", {
            board   = board,
            entries = entries,
        })
    end)

    -- Client requests their own power level / gear score
    net.OnClientEvent("PlayerGearScore", function(player)
        local dm   = getDataManager()
        local data = dm.GetData(player)
        if not data then return end

        local gr = getGearRating()
        local breakdown = gr.GetBreakdown(data)

        net.FireClient(player, "PlayerGearScore", {
            score     = breakdown.displayPower or breakdown.total,
            breakdown = breakdown,
        })

    end)

    -- §LB2: staggered per-player persist schedule.
    -- Instead of one big sweep every UPDATE_INTERVAL that thrashes
    -- a write for every connected player simultaneously, give each
    -- player their OWN cycle starting at a random offset within
    -- the interval. With 1 player or 1 billion, the per-player
    -- write rate is the same: 1 / UPDATE_INTERVAL. Total writes
    -- per second across the server scale linearly with players,
    -- not exponentially — and they're spread evenly across the
    -- window so DataStore quotas aren't hit in bursts.
    local function startPersistCycle(player)
        task.spawn(function()
            -- Random offset 0..UPDATE_INTERVAL so two players who
            -- joined in the same second don't share a tick.
            task.wait(math.random() * UPDATE_INTERVAL)
            while player.Parent do
                LeaderboardManager.UpdatePlayer(player)
                task.wait(UPDATE_INTERVAL)
            end
        end)
    end

    Players.PlayerAdded:Connect(startPersistCycle)
    for _, player in ipairs(Players:GetPlayers()) do
        startPersistCycle(player)
    end

    -- Update on player leave (final persist)
    Players.PlayerRemoving:Connect(function(player)
        LeaderboardManager.UpdatePlayer(player)
    end)

end

return LeaderboardManager
