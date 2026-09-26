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
        "achievement" — achievement stat bonuses. §DISC/D5: CORE-planned,
                        keep this seam. Achievements will grant permanent
                        stat bonuses AND gate features (e.g. the chapter
                        hard-cap boss achievement unlocks levels past each
                        50). AchievementManager wires here when those land.
        "innate"      — class innateBonuses               — ClassManager
        "acc_trinket" — equipped trinket                  — InventoryManager
        "acc_ring1"   — equipped ring 1                   — InventoryManager
        "acc_ring2"   — equipped ring 2                   — InventoryManager
        "other"       — ad-hoc / debug                    — PlayerBonusSystem
        "timed_<tag>" — temporary card buffs (auto-expire) — AddTimedBonus
        "timed_consumable_<itemId>" — §AGX/X10b: consumable buffs
                        (Power Scroll, Fortune Incense, …) — ConsumableEffects.
                        Same AddTimedBonus path: re-use refreshes, leave clears.
        "aura_<UserId>" — §AGX/X11: Patron Saint / Fortune Favors party
                        auras on a MEMBER, keyed by the keystone OWNER's
                        UserId — StatsManager/PartyAura. Created on first
                        write like timed_<tag>; ClearSource on range/death/leave.

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
      BonusManager.GetTimedBonus(player, tagName, statName) → number  (§AGX/X10b)

      -- Reads
      BonusManager.GetAggregatedBonus(player, stat) → number
      BonusManager.Recalculate(player)

      -- §AGX/STATS: change hook
      BonusManager.OnChanged(fn) → disconnect()
          fn(player, changed) after a Recalculate that changed at least
          one data.Bonus value. `changed` = { [stat] = previousValue }.
          Readers that cache a derived value (WalkSpeed, the client's
          attack pacing) subscribe here instead of polling.
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

-- §AGX/STATS: OnChanged listeners (see header). Array, not a signal
-- object: the listener set is fixed at boot (DeathSystem, AttackHandler).
local changeListeners = {}
-- §AGX/STATS: data.Bonus is saved and re-loaded, so a first Recalculate
-- can "change" nothing while listeners have never seen the values. The
-- first Recalculate per player reports every stat as changed.
local notifiedOnce = setmetatable({}, { __mode = "k" })

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

    -- §T1.3/Y7: Recalculate's "write defaultValue + agg for every catalog
    -- entry" relies on EVERY BonusStats default being 0. If a future stat
    -- ships a non-zero default, a stat cleared from all sources would keep
    -- that default instead of zeroing the contribution — the exact
    -- stale-after-clear bug the single-pass design fixed. Assert the
    -- invariant loudly at boot so it can't regress silently.
    local cfg = getConfig()
    if cfg and cfg.BonusStats then
        for statName, defaultValue in pairs(cfg.BonusStats) do
            if defaultValue ~= 0 then
                warn(string.format(
                    "[BonusManager] INVARIANT VIOLATION: BonusStats.%s default is %s (expected 0). " ..
                    "Recalculate assumes all BonusStats defaults are 0; a non-zero default will not " ..
                    "clear when its sources are removed. Either make the default 0 or rework Recalculate.",
                    statName, tostring(defaultValue)))
            end
        end
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
    -- §T1.3/Y8: error-isolate the expiry. If ClearSource ever throws, an
    -- unguarded thread would die mid-cleanup, leaving the buff applied
    -- forever and the thread ref dangling until PlayerRemoving.
    local newThread = task.delay(durationSec, function()
        if not player or not player.Parent then return end
        local ok, err = pcall(BonusManager.ClearSource, player, source)
        if not ok then
            warn(string.format("[BonusManager] timed-bonus expiry for %s failed: %s", source, tostring(err)))
        end
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

--- §AGX/X10b: current value of one stat in a timed source (0 when absent
--- or expired). ConsumableEffects reads its own Ironskin contribution so a
--- refresh re-derives the bonus from armor WITHOUT the previous buff.
function BonusManager.GetTimedBonus(player, tagName, statName)
    local sources = playerBonuses[player]
    local src = sources and sources["timed_" .. tostring(tagName)]
    return (src and src[statName]) or 0
end

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
    -- §AGX/STATS: remember which values moved; `changed` is allocated
    -- only when something actually changed and someone listens.
    local bonus = data.Bonus
    local listening = #changeListeners > 0
    local firstPass = listening and not notifiedOnce[player]
    if firstPass then notifiedOnce[player] = true end
    local changed = nil
    for statName, defaultValue in pairs(cfg.BonusStats) do
        local agg = aggregate[statName]
        local newValue = (agg ~= nil) and (defaultValue + agg) or defaultValue
        if listening then
            local old = bonus[statName]
            if firstPass or old ~= newValue then
                changed = changed or {}
                changed[statName] = old or defaultValue
            end
        end
        bonus[statName] = newValue
    end

    if changed then
        for _, fn in ipairs(changeListeners) do
            local ok, err = pcall(fn, player, changed)
            if not ok then
                warn("[BonusManager] OnChanged listener failed: " .. tostring(err))
            end
        end
    end
end

--- §AGX/STATS: subscribe to data.Bonus changes. Returns a disconnect fn.
function BonusManager.OnChanged(fn)
    table.insert(changeListeners, fn)
    return function()
        local i = table.find(changeListeners, fn)
        if i then table.remove(changeListeners, i) end
    end
end

return BonusManager
