-- ServerScriptService/Modules/AchievementManager.lua
--[[
    Server-side achievement system.

    Subscribes to event hooks from:
      • AttackHandler   (mob kill: OnMobKilled)
      • HitTracker      (hit dealt/received, combo)
      • CurrencyManager (merits: OnMeritsAdded, essence: OnEssenceAdded)
      • MobSpawner      (wave completed: OnWaveCompleted)

    Direct-call hooks (called by other systems):
      • AchievementManager.OnHealingDone(player, amount)      ← SkillEffects
      • AchievementManager.OnReviveDone(player)               ← LifeStewardSkills
      • AchievementManager.OnWeaponLevelUp(player, newLevel)  ← WeaponXPSystem
      • AchievementManager.OnTalentAllocated(player)          ← TalentManager

    Attribute hook (§AGX/X18b):
      • player "Level" attribute → stats.accountLevel (+ Evaluate). Every
        level write goes through PlayerDataManager.SetAccountData, which
        sets that attribute, so natural level-ups and admin SetLevel both
        land here without touching PlayerDataManager.

    Stats are merged into player save data under:
      data.Account.Achievements = { stats = {...}, unlocked = {...},
                                    talentPoints = {...} }
      §AGX/BTP: talentPoints is the "TalentPoint" reward ledger,
      { ["<achId>:<tier>"] = amount }. A tier's point is granted only when
      its key is absent, so unlock + login backfill can never double-grant,
      and tiers unlocked before the reward existed are paid on next load.

    Network events:
      Client → Server   "GetAchievements"     → replies with AchievementsData
      Server → Client   "AchievementsData"    → { stats, unlocked }
      Server → Client   "AchievementUnlocked" → { id, name, desc, icon, category,
                                                   tier, maxTier, rewards }
]]

local AchievementManager = {}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = script.Parent

-- Eagerly loaded (pure-data, always available)
local AchievementConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AchievementConfig"))

-- Lazily loaded (avoid circular deps / init-order issues)
local NetworkManager    = nil
local PlayerDataManager = nil
local CurrencyManager   = nil

local function getCurrencyManager()
    if not CurrencyManager then
        CurrencyManager = require(Modules:WaitForChild("CurrencyManager"))
    end
    return CurrencyManager
end

-- §AGX/X18b: lazy CharacterManager ref for the "AppearanceChange" reward.
local _CharacterManager = nil
local function getCharacterManager()
    if _CharacterManager == nil then
        local mod = Modules:FindFirstChild("CharacterManager")
        local ok, cm = false, nil
        if mod then ok, cm = pcall(require, mod) end
        _CharacterManager = (ok and type(cm) == "table") and cm or false
    end
    return _CharacterManager or nil
end

-- §AGX/BTP: lazy TalentManager ref for the "TalentPoint" reward (it stores
-- data.Account.BonusTalentPoints and pushes TalentStateUpdate).
local _TalentManager = nil
local function getTalentManager()
    if _TalentManager == nil then
        local mod = Modules:FindFirstChild("TalentManager")
        local ok, tm = false, nil
        if mod then ok, tm = pcall(require, mod) end
        _TalentManager = (ok and type(tm) == "table") and tm or false
    end
    return _TalentManager or nil
end

-- §AGX/X18b: per-player "Level" attribute connection (accountLevel stat).
local levelConns = {} -- [player] = RBXScriptConnection

local _InventoryManager = nil
local function getInventoryManager()
    if not _InventoryManager then
        _InventoryManager = require(Modules:WaitForChild("InventoryManager"))
    end
    return _InventoryManager
end

-- §NM-D2: lazy ReadyGate ref. The unlock toast push is fired in response
-- to a kill / damage event, which CAN happen on the very first server
-- frame after a player joins (achievements evaluate before client UI
-- has subscribed). Routing through ReadyGate ensures the first-tier
-- unlock toast actually lands on the client.
local _ReadyGate = nil
local function fireAchievementUnlocked(player, payload)
    if _ReadyGate == nil then
        local mod = Modules:FindFirstChild("ReadyGate")
        if mod then
            local ok, rg = pcall(require, mod)
            if ok then _ReadyGate = rg end
        end
        if not _ReadyGate then _ReadyGate = false end
    end
    if _ReadyGate then
        _ReadyGate.FireClient(player, "AchievementUnlocked", payload)
    else
        NetworkManager.FireClient(player, "AchievementUnlocked", payload)
    end
end

-- In-memory per-player entry: [player] = { stats = {...}, unlocked = {...} }
local playerCache = {}

-- Throttled evaluation: at most once per EVAL_INTERVAL seconds per player.
local EVAL_INTERVAL = 1.0
local dirtyPlayers  = {}   -- [player] = true
local evalScheduled = {}   -- [player] = true

-- Guard against re-entrant unlock chains (Unlock → AddMerits → Evaluate → Unlock)
-- §AM1: per-player guard, so one player's unlock chain can't swallow
-- another player's simultaneous unlock.
local isUnlocking = {} -- [player] = true

-- ═══════════════════════════════════════════════════════════
-- STAT TEMPLATE
-- ═══════════════════════════════════════════════════════════

local function DefaultStats()
    return {
        -- Combat
        totalKills        = 0,
        killsByMobId      = {},
        killsByTier       = { normal = 0, miniboss = 0, boss = 0 },
        hitsDelivered     = 0,
        hitsReceived      = 0,
        totalDamageDealt  = 0,
        totalDamageTaken  = 0,
        criticalHits      = 0,
        bestCombo         = 0,
        -- Survival
        wavesSurvived     = 0,
        highestWave       = 0,
        -- Healer role
        healingDone       = 0,
        revivesDone       = 0,
        -- Collection
        meritsCollected   = 0,
        essenceEarned     = 0,
        -- Weapon / Talent
        weaponLevelMax    = 0,
        talentNodesAllocated = 0,
        -- Cap mastery kills (gated by player level at time of boss kill)
        capMasteryKills   = { cap50 = 0, cap100 = 0, cap150 = 0, cap200 = 0 },
        -- §AGX/X18b: account level mirror (set on load + every level-up)
        accountLevel      = 0,
    }
end

-- Ensure saved stats have all fields (adds new fields to existing saves).
local function MergeDefaults(saved)
    local defaults = DefaultStats()
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            saved[k] = type(v) == "table" and {} or v
        end
    end
    -- Sub-table: killsByTier
    if not saved.killsByTier then
        saved.killsByTier = { normal = 0, miniboss = 0, boss = 0 }
    else
        saved.killsByTier.normal   = saved.killsByTier.normal   or 0
        saved.killsByTier.miniboss = saved.killsByTier.miniboss or 0
        saved.killsByTier.boss     = saved.killsByTier.boss     or 0
    end
    -- Sub-table: killsByMobId
    if not saved.killsByMobId then saved.killsByMobId = {} end
    -- Sub-table: capMasteryKills
    if not saved.capMasteryKills then
        saved.capMasteryKills = { cap50 = 0, cap100 = 0, cap150 = 0, cap200 = 0 }
    else
        saved.capMasteryKills.cap50  = saved.capMasteryKills.cap50  or 0
        saved.capMasteryKills.cap100 = saved.capMasteryKills.cap100 or 0
        saved.capMasteryKills.cap150 = saved.capMasteryKills.cap150 or 0
        saved.capMasteryKills.cap200 = saved.capMasteryKills.cap200 or 0
    end
    return saved
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function AchievementManager.Init()
    NetworkManager    = require(Modules:WaitForChild("NetworkManager"))
    PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))

    NetworkManager.GetEvent("GetAchievements")
    NetworkManager.GetEvent("AchievementsData")
    NetworkManager.GetEvent("AchievementUnlocked")

    -- Client requests data (e.g. when opening the achievements panel)
    NetworkManager.OnClientEvent("GetAchievements", function(player)
        AchievementManager.SendData(player)
    end)

    -- Player lifecycle
    -- §AM7: subscribe to OnPlayerDataReady so SetupPlayer runs immediately
    -- when player data is loaded, not after a polling delay. PlayerAdded is
    -- still wired as a fallback in case OnPlayerDataReady is missing on the
    -- currently loaded PlayerDataManager build.
    if PlayerDataManager.OnPlayerDataReady then
        PlayerDataManager.OnPlayerDataReady(AchievementManager.SetupPlayer)
    else
        Players.PlayerAdded:Connect(AchievementManager.SetupPlayer)
    end
    Players.PlayerRemoving:Connect(AchievementManager.SaveAndCleanup)
    for _, p in ipairs(Players:GetPlayers()) do
        if not playerCache[p] then
            AchievementManager.SetupPlayer(p)
        end
    end

    -- ── Hook: DamageHandler kill events ──────────────────────────────────
    task.spawn(function()
        local ah = Modules:FindFirstChild("AttackHandler")
        if ah then
            local ok, AttackHandler = pcall(require, ah)
            if ok then
                local DamageHandler = AttackHandler.GetSystems().Damage
                if DamageHandler and DamageHandler.OnMobKilled then
                    DamageHandler.OnMobKilled(function(player, info)
                        AchievementManager.OnKill(player, info)
                    end)
                end
            end
        end
    end)

    -- ── Hook: HitTracker ────────────────────────────────────────────────
    task.spawn(function()
        local ht = Modules:FindFirstChild("HitTracker")
        if ht then
            local ok, HT = pcall(require, ht)
            if ok then
                if HT.OnHitDealt then
                    HT.OnHitDealt(function(player, hitData)
                        AchievementManager.OnHitDealt(player, hitData)
                    end)
                end
                if HT.OnHitReceived then
                    HT.OnHitReceived(function(player, hitData)
                        AchievementManager.OnHitReceived(player, hitData)
                    end)
                end
                if HT.OnComboUpdated then
                    HT.OnComboUpdated(function(player, combo)
                        AchievementManager.UpdateBestCombo(player, combo)
                    end)
                end
            end
        end
    end)

    -- ── Hook: CurrencyManager — Merits ───────────────────────────────────
    task.spawn(function()
        local cm = Modules:FindFirstChild("CurrencyManager")
        if cm then
            local ok, CM = pcall(require, cm)
            if ok and CM.OnMeritsAdded then
                CM.OnMeritsAdded(function(player, amount)
                    AchievementManager.OnMeritsAdded(player, amount)
                end)
            end
        end
    end)

    -- ── Hook: CurrencyManager — Essence ──────────────────────────────────
    task.spawn(function()
        local cm = Modules:FindFirstChild("CurrencyManager")
        if cm then
            local ok, CM = pcall(require, cm)
            if ok and CM.OnEssenceAdded then
                CM.OnEssenceAdded(function(player, amount)
                    AchievementManager.OnEssenceEarned(player, amount)
                end)
            end
        end
    end)

    -- ── Hook: MobSpawner wave events ──────────────────────────────────────
    task.spawn(function()
        local ms = Modules:FindFirstChild("MobSpawner")
        if ms then
            local ok, MS = pcall(require, ms)
            if ok and MS.OnWaveCompleted then
                MS.OnWaveCompleted(function(waveNumber)
                    AchievementManager.OnWaveCompleted(waveNumber)
                end)
            end
        end
    end)

end

-- ═══════════════════════════════════════════════════════════
-- PLAYER LIFECYCLE
-- ═══════════════════════════════════════════════════════════

function AchievementManager.SetupPlayer(player)
    -- Idempotency guard — Init() may both call this directly (for already-in-
    -- game players) and register us as an OnPlayerDataReady callback.
    if playerCache[player] then return end

    task.spawn(function()
        if playerCache[player] then return end
        -- §AM7: short bounded poll. Init also registers
        -- AchievementManager.SetupPlayer with PlayerDataManager.OnPlayerDataReady
        -- so for normal joins the callback fires this function with data already
        -- loaded; the loop below only protects the already-in-game path.
        local account = nil
        local data = PlayerDataManager.GetData(player)
        if data and data.Account then
            account = data.Account
        else
            for _ = 1, 30 do
                task.wait(0.5)
                if not player.Parent then return end
                data = PlayerDataManager.GetData(player)
                if data and data.Account then
                    account = data.Account
                    break
                end
            end
        end

        if not account then
            warn("[AchievementManager] Could not load data for", player.Name)
            playerCache[player] = {
                stats        = DefaultStats(),
                unlocked     = {},
                talentPoints = {}, -- §AGX/BTP
            }
            return
        end

        local saved = account.Achievements
        playerCache[player] = {
            stats    = saved and MergeDefaults(saved.stats    or DefaultStats()) or DefaultStats(),
            unlocked = saved and (saved.unlocked or {}) or {},
            -- §AGX/BTP: TalentPoint reward ledger (see header).
            talentPoints = (saved and type(saved.talentPoints) == "table") and saved.talentPoints or {},
        }

        -- §AGX/X18b: account level → stats.accountLevel, now and on every
        -- level-up. Players already at/above a threshold (e.g. Veteran, 50)
        -- unlock via the Evaluate at the end of this setup.
        playerCache[player].stats.accountLevel = tonumber(account.Level) or 0
        if levelConns[player] then levelConns[player]:Disconnect() end
        levelConns[player] = player:GetAttributeChangedSignal("Level"):Connect(function()
            AchievementManager.OnAccountLevelChanged(player, player:GetAttribute("Level"))
        end)

        -- ── Migrate legacy unlocked format ─────────────────────────────
        -- Old: unlocked[id] = timestamp (>=1_700_000_000) or true
        -- New: unlocked[id] = tierNumber (1..10)
        local migrated = false
        for id, val in pairs(playerCache[player].unlocked) do
            if type(val) == "boolean" or (type(val) == "number" and val > 1000) then
                playerCache[player].unlocked[id] = 1
                migrated = true
            end
        end
        if migrated then
            AchievementManager.PersistNow(player)
        end

        -- §AGX/X18b: login catch-up (accountLevel is only known here).
        AchievementManager.Evaluate(player)
        -- §AGX/BTP: pay TalentPoint rewards of tiers unlocked before the
        -- reward existed (or whose grant failed). Ledger-guarded.
        AchievementManager.BackfillTalentPoints(player)
        AchievementManager.PersistNow(player)

        print("[AchievementManager] Loaded data for", player.Name,
            "| Kills:", playerCache[player].stats.totalKills,
            "| Unlocked:", (function()
                local n = 0
                for _ in pairs(playerCache[player].unlocked) do n = n + 1 end
                return n
            end)())
    end)
end

function AchievementManager.SaveAndCleanup(player)
    if levelConns[player] then  -- §AGX/X18b
        levelConns[player]:Disconnect()
        levelConns[player] = nil
    end
    local pdata = playerCache[player]
    if not pdata then return end
    if dirtyPlayers[player] then
        dirtyPlayers[player] = nil
        AchievementManager.Evaluate(player)
    end
    evalScheduled[player] = nil
    AchievementManager.PersistNow(player)
    playerCache[player] = nil
    isUnlocking[player]  = nil
end

-- ═══════════════════════════════════════════════════════════
-- THROTTLED EVALUATION HELPER
-- ═══════════════════════════════════════════════════════════

local function scheduleEvaluation(player)
    dirtyPlayers[player] = true
    if evalScheduled[player] then return end
    evalScheduled[player] = true
    task.delay(EVAL_INTERVAL, function()
        evalScheduled[player] = nil
        if dirtyPlayers[player] then
            dirtyPlayers[player] = nil
            AchievementManager.Evaluate(player)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
-- EVENT HOOKS — COMBAT
-- ═══════════════════════════════════════════════════════════

function AchievementManager.OnKill(player, info)
    local pdata = playerCache[player]
    if not pdata then return end
    local s = pdata.stats

    local mobId   = info.mobId   or "Unknown"
    local mobTier = info.mobTier or "normal"

    -- General kill tracking
    s.totalKills                  = s.totalKills + 1
    s.killsByMobId[mobId]         = (s.killsByMobId[mobId] or 0) + 1
    if s.killsByTier[mobTier] ~= nil then
        s.killsByTier[mobTier]    = s.killsByTier[mobTier] + 1
    end

    -- ── Cap mastery tracking ───────────────────────────────────────────
    -- Check if this boss kill qualifies for a cap mastery stat increment.
    local capEntry = AchievementConfig.CapMasteryMap[mobId]
    if capEntry and mobTier == "boss" then
        local playerLevel = 1
        if PlayerDataManager then
            playerLevel = PlayerDataManager.GetAccountData(player, "Level") or 1
        end
        if playerLevel <= capEntry.levelCap then
            s.capMasteryKills[capEntry.statKey] = s.capMasteryKills[capEntry.statKey] + 1
        end
    end

    AchievementManager.Evaluate(player)
    AchievementManager.PersistNow(player)
end

function AchievementManager.OnHitDealt(player, hitData)
    local pdata = playerCache[player]
    if not pdata then return end
    local s = pdata.stats

    s.hitsDelivered    = s.hitsDelivered    + 1
    s.totalDamageDealt = s.totalDamageDealt + (hitData.damage or 0)
    if hitData.isCrit then
        s.criticalHits = s.criticalHits + (hitData.critProcs or 1)
    end

    scheduleEvaluation(player)
end

function AchievementManager.OnHitReceived(player, hitData)
    local pdata = playerCache[player]
    if not pdata then return end
    local s = pdata.stats

    s.hitsReceived     = s.hitsReceived     + 1
    s.totalDamageTaken = s.totalDamageTaken + (hitData.damage or 0)

    scheduleEvaluation(player)
end

function AchievementManager.UpdateBestCombo(player, combo)
    local pdata = playerCache[player]
    if not pdata then return end
    if combo > pdata.stats.bestCombo then
        pdata.stats.bestCombo = combo
        AchievementManager.Evaluate(player)
    end
end

-- ═══════════════════════════════════════════════════════════
-- EVENT HOOKS — SURVIVAL
-- ═══════════════════════════════════════════════════════════

function AchievementManager.OnWaveCompleted(waveNumber)
    for player, pdata in pairs(playerCache) do
        pdata.stats.wavesSurvived = pdata.stats.wavesSurvived + 1
        if waveNumber > pdata.stats.highestWave then
            pdata.stats.highestWave = waveNumber
        end
        AchievementManager.Evaluate(player)
        AchievementManager.PersistNow(player)
    end
end

-- ═══════════════════════════════════════════════════════════
-- EVENT HOOKS — HEALER ROLE
-- ═══════════════════════════════════════════════════════════

--- Called by SkillEffects.HealPlayer with the ACTUAL hp healed (overheal excluded).
function AchievementManager.OnHealingDone(player, amount)
    local pdata = playerCache[player]
    if not pdata or (amount or 0) <= 0 then return end
    pdata.stats.healingDone = pdata.stats.healingDone + amount
    scheduleEvaluation(player)
end

--- Called by LifeStewardSkills after a successful revive.
function AchievementManager.OnReviveDone(player)
    local pdata = playerCache[player]
    if not pdata then return end
    pdata.stats.revivesDone = pdata.stats.revivesDone + 1
    AchievementManager.Evaluate(player)
    AchievementManager.PersistNow(player)
end

-- ═══════════════════════════════════════════════════════════
-- EVENT HOOKS — COLLECTION
-- ═══════════════════════════════════════════════════════════

function AchievementManager.OnMeritsAdded(player, amount)
    local pdata = playerCache[player]
    if not pdata then return end
    pdata.stats.meritsCollected = pdata.stats.meritsCollected + amount
    AchievementManager.Evaluate(player)
end

--- Called by CurrencyManager.AddEssence via OnEssenceAdded callback.
function AchievementManager.OnEssenceEarned(player, amount)
    local pdata = playerCache[player]
    if not pdata or (amount or 0) <= 0 then return end
    pdata.stats.essenceEarned = pdata.stats.essenceEarned + amount
    scheduleEvaluation(player)
end

-- ═══════════════════════════════════════════════════════════
-- EVENT HOOKS — WEAPON / TALENT
-- ═══════════════════════════════════════════════════════════

--- Called by WeaponXPSystem.processXP when at least one weapon level is gained.
function AchievementManager.OnWeaponLevelUp(player, newLevel)
    local pdata = playerCache[player]
    if not pdata then return end
    if newLevel > pdata.stats.weaponLevelMax then
        pdata.stats.weaponLevelMax = newLevel
        AchievementManager.Evaluate(player)
        AchievementManager.PersistNow(player)
    end
end

-- ═══════════════════════════════════════════════════════════
-- EVENT HOOKS — ACCOUNT LEVEL  (§AGX/X18b)
-- ═══════════════════════════════════════════════════════════

--- Fired by the player's "Level" attribute (set by
--- PlayerDataManager.SetAccountData on every level write). Keeps the
--- highest level seen, so an admin level-down never lowers the stat.
function AchievementManager.OnAccountLevelChanged(player, newLevel)
    local pdata = playerCache[player]
    newLevel = tonumber(newLevel)
    if not pdata or not newLevel then return end
    if newLevel > (pdata.stats.accountLevel or 0) then
        pdata.stats.accountLevel = newLevel
        AchievementManager.Evaluate(player)
        AchievementManager.PersistNow(player)
    end
end

--- Called by TalentManager.AllocateNode after each successful allocation.
function AchievementManager.OnTalentAllocated(player)
    local pdata = playerCache[player]
    if not pdata then return end
    pdata.stats.talentNodesAllocated = pdata.stats.talentNodesAllocated + 1
    scheduleEvaluation(player)
end

-- ═══════════════════════════════════════════════════════════
-- EVALUATION & UNLOCK
-- ═══════════════════════════════════════════════════════════

function AchievementManager.Evaluate(player)
    local pdata = playerCache[player]
    if not pdata then return end

    for _, ach in ipairs(AchievementConfig.GetAll()) do
        local maxTier     = #ach.tiers
        local currentTier = pdata.unlocked[ach.id] or 0
        if currentTier >= maxTier then continue end

        local statVal = AchievementConfig.GetStatValue(ach, pdata.stats)

        for tier = currentTier + 1, maxTier do
            if (pdata.unlocked[ach.id] or 0) >= tier then continue end
            if statVal >= ach.tiers[tier] then
                AchievementManager.Unlock(player, ach, tier)
            else
                break
            end
        end
    end
end

--- §AGX/BTP: grant one tier's "TalentPoint" reward unless its ledger key
--- is already set. Returns true when points were granted now.
local function grantTalentPoints(player, pdata, ach, tier, amount)
    local key = ach.id .. ":" .. tostring(tier)
    if pdata.talentPoints[key] then return false end
    local ok = false
    local tm = getTalentManager()
    if tm and tm.GrantBonusPoints then
        ok = tm.GrantBonusPoints(player, amount, "achievement:" .. key) == true
    else
        local data = PlayerDataManager.GetData(player)
        if data and type(data.Account) == "table" then
            data.Account.BonusTalentPoints = (tonumber(data.Account.BonusTalentPoints) or 0) + amount
            ok = true
        end
    end
    if ok then pdata.talentPoints[key] = amount end
    return ok
end

--- §AGX/BTP: login backfill for TalentPoint rewards (see header).
function AchievementManager.BackfillTalentPoints(player)
    local pdata = playerCache[player]
    if not pdata or not pdata.talentPoints then return end
    for _, ach in ipairs(AchievementConfig.GetAll()) do
        local reached = pdata.unlocked[ach.id] or 0
        if type(reached) == "number" and reached > 0 and ach.rewards then
            for tier = 1, math.min(reached, #ach.tiers) do
                local list = ach.rewards[tier]
                if list then
                    for _, entry in ipairs(list) do
                        if entry[1] == "TalentPoint" then
                            grantTalentPoints(player, pdata, ach, tier, entry[2])
                        end
                    end
                end
            end
        end
    end
end

function AchievementManager.Unlock(player, ach, tier)
    local pdata = playerCache[player]
    if not pdata then return end

    if isUnlocking[player] then return end
    isUnlocking[player] = true

    pdata.unlocked[ach.id] = tier
    AchievementManager.PersistNow(player)

    -- ── Grant tier rewards ─────────────────────────────────────
    local rewardList = ach.rewards and ach.rewards[tier]
    local rewardSummary = {}
    if rewardList then
        local cm   = getCurrencyManager()
        local data = PlayerDataManager.GetData(player)
        for _, entry in ipairs(rewardList) do
            local rtype, amount = entry[1], entry[2]
            if rtype == "Merits" then
                cm.AddMerits(player, amount)
                table.insert(rewardSummary, amount .. " Merits")
            elseif rtype == "Essence" then
                cm.AddEssence(player, amount)
                table.insert(rewardSummary, amount .. " Essence")
            elseif rtype == "RespecToken" and data then
                -- RespecTokens counter is deprecated; grant respec_scroll
                -- inventory items instead.
                getInventoryManager().AddItem(player, "respec_scroll", amount)
                table.insert(rewardSummary, amount .. " Respec Scroll" .. (amount > 1 and "s" or ""))
            elseif rtype == "AppearanceChange" then
                -- §AGX/X18b: STORE a free token (CharacterData.freeAppearanceTokens);
                -- never auto-open the creation screen. Spent from the menu.
                local cm = getCharacterManager()
                local stored = false
                if cm and cm.AddFreeAppearanceToken then
                    stored = cm.AddFreeAppearanceToken(player, amount, "achievement:" .. ach.id) == true
                end
                if not stored and data and type(data.Account) == "table" then
                    local cd = data.Account.CharacterData
                    if type(cd) ~= "table" then
                        cd = { isCreated = false }
                        data.Account.CharacterData = cd
                    end
                    local cur = type(cd.freeAppearanceTokens) == "number" and cd.freeAppearanceTokens or 0
                    cd.freeAppearanceTokens = cur + amount
                    stored = true
                end
                if stored then
                    table.insert(rewardSummary, amount .. " Free Appearance Change" .. (amount > 1 and "s" or ""))
                end
            elseif rtype == "TalentPoint" then
                -- §AGX/BTP: permanent data.Account.BonusTalentPoints, once per tier.
                if grantTalentPoints(player, pdata, ach, tier, amount) then
                    table.insert(rewardSummary, "+" .. amount .. " Talent Point" .. (amount > 1 and "s" or ""))
                end
            end
        end
    end

    fireAchievementUnlocked(player, {
        id       = ach.id,
        name     = ach.name,
        desc     = ach.desc,
        icon     = ach.icon,
        category = ach.category,
        tier     = tier,
        maxTier  = #ach.tiers,
        rewards  = rewardSummary,
    })

    print("[AchievementManager]", player.Name, "→", ach.name, "Tier", tier .. "/" .. #ach.tiers,  -- §AGX/X18b
        #rewardSummary > 0 and ("Rewards: " .. table.concat(rewardSummary, ", ")) or "")

    isUnlocking[player] = nil
end

-- ═══════════════════════════════════════════════════════════
-- PERSISTENCE
-- ═══════════════════════════════════════════════════════════

function AchievementManager.PersistNow(player)
    local pdata = playerCache[player]
    if not pdata then return end

    local data = PlayerDataManager.GetData(player)
    if data and data.Account then
        data.Account.Achievements = {
            stats        = pdata.stats,
            unlocked     = pdata.unlocked,
            talentPoints = pdata.talentPoints, -- §AGX/BTP
        }
    end
end

-- ═══════════════════════════════════════════════════════════
-- CLIENT DATA
-- ═══════════════════════════════════════════════════════════

function AchievementManager.SendData(player)
    local pdata = playerCache[player]
    if not pdata then
        if not player.Parent then return end
        task.delay(1, function()
            AchievementManager.SendData(player)
        end)
        return
    end

    NetworkManager.FireClient(player, "AchievementsData", {
        stats    = pdata.stats,
        unlocked = pdata.unlocked,
    })
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC GETTERS
-- ═══════════════════════════════════════════════════════════

function AchievementManager.GetStats(player)
    local pdata = playerCache[player]
    return pdata and pdata.stats or nil
end

function AchievementManager.GetUnlocked(player)
    local pdata = playerCache[player]
    return pdata and pdata.unlocked or {}
end

return AchievementManager
