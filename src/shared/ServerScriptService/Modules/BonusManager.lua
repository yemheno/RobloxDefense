-- ServerScriptService/Modules/BonusManager
--[[
    BonusManager
    ============
    Central aggregation layer for every stat bonus source. The ONLY writer
    into `data.Bonus[stat]`. Stat readers (StatsManager, GearRating,
    DamageSystem, etc.) keep reading `data.Bonus` exactly as before.

    Problem it solves
    ─────────────────
    Before BonusManager, weapons, skill buffs, and (future) talents all
    wrote directly to `data.Bonus[stat]`. ApplyWeaponBonuses() would
    zero-out weapon stats and re-add them, silently clobbering any buff
    that happened to share the same stat key.

    Architecture
    ────────────
    Each source gets its own isolated bonus table — `{ statName = value }`.
    Recalculate sums all sources for every known stat name and writes the
    total into `data.Bonus`.

    Registered sources (string keys):
        "weapon"      — weapon random rolls (flat)        — PlayerBonusSystem
        "armor"       — armor defense + rolls             — PlayerBonusSystem
        "buff"        — active SkillManager buffs         — SkillManager
        "talent"      — talent tree passives              — TalentEffectAggregator
        "achievement" — achievement bonuses (future)
        "innate"      — class innateBonuses               — ClassManager
        "acc_trinket" — equipped trinket                  — InventoryManager
        "acc_ring1"   — equipped ring 1                   — InventoryManager
        "acc_ring2"   — equipped ring 2                   — InventoryManager
        "other"       — ad-hoc / debug                    — PlayerBonusSystem
        "timed_<tag>" — temporary card buffs (auto-expire) — AddTimedBonus

    Write-time validation  (§T1.3/B1)
    ─────────────────────────────────
    Every write checks the stat name against PlayerDataConfig.BonusStats.
    Unknown names get warned-once and rejected. This catches typos at
    the source instead of letting them silently aggregate into a key
    that nobody reads.

    Recalculate pass  (§T1.3/B1)
    ────────────────────────────
    Single linear pass per call:
      1. Walk every source table once, building `aggregate[stat] = sum`.
      2. Walk every key in BonusStats: write `aggregate[stat]` (or the
         catalog default if no source has it) into `data.Bonus[stat]`.
    Replaces the previous quadratic dual-loop that also leaked
    stale-after-clear values for stats not in BonusStats.

    Public API
    ──────────
      BonusManager.Init()
      BonusManager.InjectDataManager(dm)

      -- Source-level writes (validated)
      BonusManager.SetSourceBonuses(player, source, bonusTable)
      BonusManager.SetSourceBonus  (player, source, stat, value)
      BonusManager.ModifySourceBonus(player, source, stat, delta)
      BonusManager.ClearSource     (player, source)

      -- Temporary buff with auto-cancel + refresh-on-reapply (§T1.3/B8)
      BonusManager.AddTimedBonus(player, tagName, statName, value, durationSec)

      -- Reads
      BonusManager.GetAggregatedBonus(player, stat) → number
      BonusManager.Recalculate(player)
]]

local BonusManager = {}

local Players = game:GetService("Players")
local Modules = script.Parent

-- DataManager is injected via BonusManager.InjectDataManager() by the
-- bootstrap after both modules are loaded. Breaks the static cyclic
-- require chain: BonusManager → PlayerDataManager → PlayerBonusSystem → BonusManager.
local DataManager = nil
local Config      = nil

local function getConfig()
    if not Config then
        Config = require(Modules:WaitForChild("PlayerDataConfig"))
    end
    return Config
end

--- Called by the bootstrap after PlayerDataManager is loaded.
function BonusManager.InjectDataManager(dm)
    DataManager = dm
end

-- ─────────────────────────────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────────────────────────────

-- Per-player source tables. Strong-keyed so we can clear deterministically
-- on PlayerRemoving; we don't rely on weak-GC for the cleanup contract.
-- playerBonuses[player][source][stat] = value
local playerBonuses = {}

-- §T1.3/B8: per-player, per-source pending-expire threads. When the same
-- timed bonus tag is re-applied, the previous thread is cancelled so the
-- new one's full duration takes effect (refresh, not stack-of-expirations).
-- Weak-keyed so leavers GC naturally; PlayerRemoving also clears for
-- determinism.
-- timedThreads[player][source] = thread
local timedThreads = setmetatable({}, { __mode = "k" })

-- §T1.3/B1: warn-once memoization for unknown stat names. Without this a
-- typo'd write inside a tight combat loop would spam the console.
local _warnedUnknownStats = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function BonusManager.Init()
    Players.PlayerAdded:Connect(function(player)
        BonusManager.SetupPlayer(player)
    end)
    Players.PlayerRemoving:Connect(function(player)
        playerBonuses[player] = nil
        -- Cancel any pending timed-bonus expire threads for this player.
        -- Each thread guards on `player.Parent` anyway, but cancelling is
        -- cheaper than letting the scheduler resume a no-op closure.
        local perPlayer = timedThreads[player]
        if perPlayer then
            for _, t in pairs(perPlayer) do pcall(task.cancel, t) end
            timedThreads[player] = nil
        end
    end)
    for _, p in ipairs(Players:GetPlayers()) do
        BonusManager.SetupPlayer(p)
    end
end

function BonusManager.SetupPlayer(player)
    if not playerBonuses[player] then
        playerBonuses[player] = {
            weapon      = {},
            armor       = {},
            buff        = {},
            talent      = {},
            achievement = {},
            innate      = {},
            acc_trinket = {},
            acc_ring1   = {},
            acc_ring2   = {},
            other       = {},
        }
    end
end

-- ─────────────────────────────────────────────────────────────────────
-- VALIDATION  (§T1.3/B1)
-- ─────────────────────────────────────────────────────────────────────

--- Return true if `statName` is in PlayerDataConfig.BonusStats. On the
--- first unknown encounter we warn loudly so the typo / missing-catalog
--- entry surfaces; subsequent calls are silent for that name.
local function isValidStat(statName)
    local cfg = getConfig()
    if cfg.BonusStats[statName] ~= nil then return true end
    if not _warnedUnknownStats[statName] then
        _warnedUnknownStats[statName] = true
        warn(string.format(
            "[BonusManager] Rejected write to unknown stat %q. Add it to " ..
            "PlayerDataConfig.BonusStats or fix the caller's typo.",
            tostring(statName)
        ))
    end
    return false
end

-- ═══════════════════════════════════════════════════════════
-- SOURCE-LEVEL WRITES  (validated)
-- ═══════════════════════════════════════════════════════════

--- Replace all bonuses for a source and recalculate.
function BonusManager.SetSourceBonuses(player, source, bonusTable)
    BonusManager.SetupPlayer(player)
    local clean = {}
    if bonusTable then
        for stat, value in pairs(bonusTable) do
            if isValidStat(stat) then clean[stat] = value end
        end
    end
    playerBonuses[player][source] = clean
    BonusManager.Recalculate(player)
end

--- Set one stat within a source and recalculate.
function BonusManager.SetSourceBonus(player, source, stat, value)
    if not isValidStat(stat) then return end
    BonusManager.SetupPlayer(player)
    local srcTable = playerBonuses[player][source]
    if not srcTable then
        srcTable = {}
        playerBonuses[player][source] = srcTable
    end
    srcTable[stat] = value
    BonusManager.Recalculate(player)
end

--- Add delta to a single stat within a source, then recalculate.
function BonusManager.ModifySourceBonus(player, source, stat, delta)
    if not isValidStat(stat) then return end
    BonusManager.SetupPlayer(player)
    local srcTable = playerBonuses[player][source]
    if not srcTable then
        srcTable = {}
        playerBonuses[player][source] = srcTable
    end
    srcTable[stat] = (srcTable[stat] or 0) + delta
    BonusManager.Recalculate(player)
end

--- Reset a source to empty.
function BonusManager.ClearSource(player, source)
    BonusManager.SetupPlayer(player)
    playerBonuses[player][source] = {}
    BonusManager.Recalculate(player)
end

--- §T1.3/B8: apply a temporary stat bonus that auto-expires after
--- `durationSec`. Re-applying the same `tagName` REFRESHES the timer
--- instead of layering a second expiration on top — non-stacking buffs
--- behave intuitively.
function BonusManager.AddTimedBonus(player, tagName, statName, value, durationSec)
    if not isValidStat(statName) then return end

    local source = "timed_" .. tagName
    BonusManager.SetSourceBonus(player, source, statName, value)

    -- Cancel any prior expire-thread for this exact source.
    local perPlayer = timedThreads[player]
    if perPlayer then
        local existing = perPlayer[source]
        if existing then
            pcall(task.cancel, existing)
            perPlayer[source] = nil
        end
    end

    -- Start the fresh expire-thread.
    local newThread = task.delay(durationSec, function()
        if not player or not player.Parent then return end
        BonusManager.ClearSource(player, source)
        local perP = timedThreads[player]
        if perP then perP[source] = nil end
    end)

    perPlayer = timedThreads[player]
    if not perPlayer then
        perPlayer = {}
        timedThreads[player] = perPlayer
    end
    perPlayer[source] = newThread
end

-- ═══════════════════════════════════════════════════════════
-- READ HELPERS
-- ═══════════════════════════════════════════════════════════

--- Sum a single stat across ALL sources (without going through data.Bonus).
function BonusManager.GetAggregatedBonus(player, stat)
    local sources = playerBonuses[player]
    if not sources then return 0 end
    local total = 0
    for _, tbl in pairs(sources) do
        total = total + (tbl[stat] or 0)
    end
    return total
end

-- ═══════════════════════════════════════════════════════════
-- RECALCULATE  (§T1.3/B1 — single-pass aggregation)
-- ═══════════════════════════════════════════════════════════

--- Recompute every BonusStats entry from all sources, write totals into
--- data.Bonus. O(sources × averageStatsPerSource + |BonusStats|).
function BonusManager.Recalculate(player)
    if not DataManager then return end
    local data = DataManager.GetData(player)
    if not data then return end

    local cfg     = getConfig()
    local sources = playerBonuses[player]

    -- ── Pass 1: build aggregate map from observed source keys ─────────
    -- Only one walk over the source tables. Empty sources contribute zero
    -- via the BonusStats default fallback in Pass 2.
    local aggregate = {}
    if sources then
        for _, srcTable in pairs(sources) do
            for statName, value in pairs(srcTable) do
                aggregate[statName] = (aggregate[statName] or 0) + value
            end
        end
    end

    -- ── Pass 2: write every BonusStats key into data.Bonus ────────────
    -- Walking the catalog (not the aggregate) guarantees that a stat
    -- which used to have a value but has been cleared from every source
    -- gets reset to its default — fixes the previous stale-after-clear
    -- bug where data.Bonus held the last non-zero total forever.
    for statName, defaultValue in pairs(cfg.BonusStats) do
        local agg = aggregate[statName]
        if agg ~= nil then
            data.Bonus[statName] = defaultValue + agg
        else
            data.Bonus[statName] = defaultValue
        end
    end
end

return BonusManager
