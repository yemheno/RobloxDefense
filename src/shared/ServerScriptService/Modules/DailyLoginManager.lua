-- ServerScriptService/Modules/DailyLoginManager.lua
--[[
    Server-authoritative daily login reward system.

    Data lives in data.Account.DailyLogin = {
        lastClaimDate = 0,    -- os.time() of last claim (date granularity)
        streak        = 0,    -- consecutive days logged in
        totalDays     = 0,    -- lifetime total login days
    }

    Streak resets if the player misses a calendar day.
    Rewards scale with streak (day 1 = small, day 7 = big, day 30 = jackpot).

    Network events:
      Client → Server    "ClaimDailyLogin"     → triggers DailyLoginResult
      Client → Server    "GetDailyLoginStatus" → triggers DailyLoginStatus
      Server → Client    "DailyLoginResult"    → { ok, reward, streak, totalDays }
      Server → Client    "DailyLoginStatus"    → { canClaim, streak, totalDays, nextReward }

    Public API:
      DailyLoginManager.Init()
      DailyLoginManager.CheckAndClaim(player) → bool, rewardTable
      DailyLoginManager.CanClaim(player) → bool
      DailyLoginManager.GetRewardForDay(streak) → { {type, amount}, ... }
]]

local DailyLoginManager = {}
local Modules = script.Parent

-- Lazily loaded
local NetworkManager    = nil
local PlayerDataManager = nil
local CurrencyManager   = nil

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

local _InventoryManager = nil
local function getInventoryManager()
    if not _InventoryManager then
        _InventoryManager = require(Modules:WaitForChild("InventoryManager"))
    end
    return _InventoryManager
end

local function getCurrencyManager()
    if not CurrencyManager then
        CurrencyManager = require(Modules:WaitForChild("CurrencyManager"))
    end
    return CurrencyManager
end

-- §DL1 fix: per-player claim lock so two simultaneous "ClaimDailyLogin"
-- packets in the same network frame can't both pass CanClaim and grant
-- duplicate rewards.
local claimLock = setmetatable({}, { __mode = "k" })

-- ═══════════════════════════════════════════════════════════
-- REWARD TABLE
-- ═══════════════════════════════════════════════════════════
-- Rewards cycle every 30 days. Every 7th day is a big reward.
-- Day 30 is the jackpot. After day 30, it loops (streak mod 30).

local DAILY_REWARDS = {
    -- Day 1-6: small rewards
    [1]  = { {"Merits", 100} },
    [2]  = { {"Merits", 150} },
    [3]  = { {"Merits", 200}, {"Essence", 2} },
    [4]  = { {"Merits", 250} },
    [5]  = { {"Merits", 300}, {"Essence", 3} },
    [6]  = { {"Merits", 350} },
    -- Day 7: weekly bonus
    [7]  = { {"Merits", 1000}, {"Essence", 10} },
    -- Day 8-13
    [8]  = { {"Merits", 200} },
    [9]  = { {"Merits", 250}, {"Essence", 3} },
    [10] = { {"Merits", 300} },
    [11] = { {"Merits", 350}, {"Essence", 4} },
    [12] = { {"Merits", 400} },
    [13] = { {"Merits", 450}, {"Essence", 5} },
    -- Day 14: bi-weekly bonus
    [14] = { {"Merits", 2000}, {"Essence", 20} },
    -- Day 15-20
    [15] = { {"Merits", 300} },
    [16] = { {"Merits", 350}, {"Essence", 4} },
    [17] = { {"Merits", 400} },
    [18] = { {"Merits", 450}, {"Essence", 5} },
    [19] = { {"Merits", 500} },
    [20] = { {"Merits", 550}, {"Essence", 6} },
    -- Day 21: three-week bonus
    [21] = { {"Merits", 3000}, {"Essence", 30} },
    -- Day 22-29
    [22] = { {"Merits", 400} },
    [23] = { {"Merits", 450}, {"Essence", 5} },
    [24] = { {"Merits", 500} },
    [25] = { {"Merits", 550}, {"Essence", 6} },
    [26] = { {"Merits", 600} },
    [27] = { {"Merits", 650}, {"Essence", 7} },
    [28] = { {"Merits", 700}, {"Essence", 8} },
    [29] = { {"Merits", 800}, {"Essence", 10} },
    -- Day 30: monthly jackpot
    [30] = { {"Merits", 10000}, {"Essence", 100}, {"RespecToken", 1} },
}

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

--- Returns today's date as a comparable integer (YYYYMMDD).
local function getDateId(timestamp)
    local d = os.date("!*t", timestamp)
    return d.year * 10000 + d.month * 100 + d.day
end

--- Check if the last claim was yesterday using os.time arithmetic (robust across rollovers)
local function isYesterday(lastTimestamp)
    if lastTimestamp == 0 then return false end
    local now      = os.time()
    local todayId  = getDateId(now)
    local lastId   = getDateId(lastTimestamp)
    if todayId == lastId then return false end -- same day

    -- Check if lastTimestamp was yesterday
    local yesterday = now - 86400
    local yesterdayId = getDateId(yesterday)
    return lastId == yesterdayId
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════

--- Get the reward list for a given streak day.
function DailyLoginManager.GetRewardForDay(streak)
    local day = ((streak - 1) % 30) + 1  -- cycles 1-30
    return DAILY_REWARDS[day] or { {"Merits", 100} }
end

--- Check if the player can claim today's login reward.
function DailyLoginManager.CanClaim(player)
    local dm   = getDataManager()
    local data = dm.GetData(player)
    if not data or not data.Account then return false end

    local login = data.Account.DailyLogin
    if not login then return true end -- never claimed

    local todayId = getDateId(os.time())
    local lastId  = getDateId(login.lastClaimDate or 0)

    return todayId ~= lastId  -- can claim if today ≠ last claim day
end

--- Claim the daily login reward. Returns success and reward info.
function DailyLoginManager.CheckAndClaim(player)
    -- §DL1: reject reentrant claims first, before re-reading state.
    if claimLock[player] then return false, nil end

    if not DailyLoginManager.CanClaim(player) then
        return false, nil
    end

    local dm   = getDataManager()
    local data = dm.GetData(player)
    if not data or not data.Account then return false, nil end

    claimLock[player] = true

    -- Ensure DailyLogin structure exists
    if not data.Account.DailyLogin then
        data.Account.DailyLogin = { lastClaimDate = 0, streak = 0, totalDays = 0 }
    end
    local login = data.Account.DailyLogin
    local now   = os.time()

    -- §DL1 follow-up: lock-in the eligibility window by mutating
    -- lastClaimDate FIRST so any concurrent CanClaim observes "claimed
    -- today". The streak/totalDays bookkeeping happens immediately after
    -- so the visible reward day matches the granted reward.
    local wasYesterday  = isYesterday(login.lastClaimDate or 0)
    local newStreak     = wasYesterday and ((login.streak or 0) + 1) or 1
    login.streak        = newStreak
    login.totalDays     = (login.totalDays or 0) + 1
    login.lastClaimDate = now

    -- Get reward for current streak day
    local rewardList = DailyLoginManager.GetRewardForDay(newStreak)

    -- Grant rewards (wrapped in pcall so a downstream error in
    -- AddMerits/AddEssence/AddItem doesn't release the lock without us
    -- hearing about it).
    local cm = getCurrencyManager()
    local rewardSummary = {}
    local grantOk, grantErr = pcall(function()
        for _, entry in ipairs(rewardList) do
            local rtype, amount = entry[1], entry[2]
            if rtype == "Merits" then
                cm.AddMerits(player, amount)
                table.insert(rewardSummary, amount .. " Merits")
            elseif rtype == "Essence" then
                cm.AddEssence(player, amount)
                table.insert(rewardSummary, amount .. " Essence")
            elseif rtype == "RespecToken" then
                -- RespecTokens counter is deprecated; grant respec_scroll inventory
                -- items instead so the new TalentManager/SharedEventHandlers paths
                -- can consume them.
                getInventoryManager().AddItem(player, "respec_scroll", amount)
                table.insert(rewardSummary, amount .. " Respec Scroll" .. (amount > 1 and "s" or ""))
            end
        end
    end)

    claimLock[player] = nil

    if not grantOk then
        warn("[DailyLoginManager] Reward grant failed for", player.Name, ":", grantErr)
    end

    print("[DailyLoginManager]", player.Name, "claimed Day", newStreak,
        "(Total:", login.totalDays .. ")", "→", table.concat(rewardSummary, ", "))

    return true, {
        rewards   = rewardSummary,
        streak    = newStreak,
        totalDays = login.totalDays,
    }
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DailyLoginManager.Init()
    local net = getNet()

    net.GetEvent("ClaimDailyLogin")
    net.GetEvent("GetDailyLoginStatus")
    net.GetEvent("DailyLoginResult")
    net.GetEvent("DailyLoginStatus")

    net.OnClientEvent("ClaimDailyLogin", function(player)
        local ok, result = DailyLoginManager.CheckAndClaim(player)
        if ok then
            net.FireClient(player, "DailyLoginResult", {
                ok        = true,
                rewards   = result.rewards,
                streak    = result.streak,
                totalDays = result.totalDays,
            })
        else
            net.FireClient(player, "DailyLoginResult", {
                ok     = false,
                reason = "Already claimed today",
            })
        end
    end)

    net.OnClientEvent("GetDailyLoginStatus", function(player)
        local dm   = getDataManager()
        local data = dm.GetData(player)
        if not data then return end

        local login    = data.Account.DailyLogin or { lastClaimDate = 0, streak = 0, totalDays = 0 }
        local canClaim = DailyLoginManager.CanClaim(player)

        -- Peek at what the next reward would be
        local nextStreak = canClaim
            and (isYesterday(login.lastClaimDate or 0) and (login.streak or 0) + 1 or 1)
            or (login.streak or 0)
        local nextReward = DailyLoginManager.GetRewardForDay(math.max(nextStreak, 1))

        -- Build summary strings for each reward
        local nextRewardSummary = {}
        for _, entry in ipairs(nextReward) do
            table.insert(nextRewardSummary, entry[2] .. " " .. entry[1])
        end

        net.FireClient(player, "DailyLoginStatus", {
            canClaim   = canClaim,
            streak     = login.streak or 0,
            totalDays  = login.totalDays or 0,
            nextReward = nextRewardSummary,
        })
    end)

    print("[DailyLoginManager] Initialized")
end

return DailyLoginManager
