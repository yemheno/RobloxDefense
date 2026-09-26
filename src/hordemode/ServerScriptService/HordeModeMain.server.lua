-- hordemode/ServerScriptService/HordeModeMain.server.lua
--[[
    HordeMode place bootstrap.

    Reads TeleportData from the Lobby place (party, difficulty, mode).

    Distinction from LaneDefense / CentralBoss:
      • Mode identifier is "HordeMode".
      • Camera is TopDown (player faces mouse cursor / virtual joystick).
      • No DefenseLine — players face mobs from all directions.
      • Spawning is driven by HordeModeSpawner (not MobSpawner waves).
      • A vote loop fires every 45 s with a 2 s heads-up + freeze window.
      • A run timer (10 m 30 s of play time, excluding pauses) ends the run.

    Helpers (Load, RequireLoaded, IsAdmin) live in PlaceBootstrap.
    Common per-player lifecycle (OnPlayerReady) and ambient loops
    (Vitals + HP regen) live in PlaceLifecycle.
]]

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

-- §T0P2/G3: bounded waits + loud error (was: silent infinite hang).
local SharedModules    = SSS:WaitForChild("Modules", 10)
    or error("[HordeModeMain] ServerScriptService.Modules missing after 10 s — place structure broken", 0)
local HordeFolder      = SSS:WaitForChild("HordeMode", 10)
    or error("[HordeModeMain] ServerScriptService.HordeMode missing after 10 s — place structure broken", 0)
local HordeModeModules = HordeFolder:WaitForChild("Modules", 10)
    or error("[HordeModeMain] ServerScriptService.HordeMode.Modules missing after 10 s — place structure broken", 0)

local Boot      = require(SharedModules:WaitForChild("PlaceBootstrap"))
local Lifecycle = require(SharedModules:WaitForChild("PlaceLifecycle"))
local ctx       = Boot.MakeContext("HordeMode")
local IsAdmin   = ctx.IsAdmin

-- §T0P2/X19: _G.HordeModeRequireLoaded removed — write-only global.

-- ───────────────────────────────────────────────────────────
-- CONFIG
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "PlayerDataConfig")
ctx.Load(SharedModules, "WeaponConfig")
ctx.Load(SharedModules, "ArmorConfig")
ctx.Load(SharedModules, "GearUpgradeConfig")  -- §CFG-D1: shared upgrade tables
ctx.Load(SharedModules, "ClassConfig")
ctx.Load(SharedModules, "CharacterConfig")
ctx.Load(SharedModules, "GameModeConfig")
ctx.Load(SharedModules, "ProjectileConfig")
ctx.Load(SharedModules, "StatusEffectTypes")

-- ───────────────────────────────────────────────────────────
-- NETWORK + READY GATE
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "NetworkManager")
ctx.Load(SharedModules, "ReadyGate")

-- ───────────────────────────────────────────────────────────
-- PLAYER DATA + CHARACTER
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "PlayerDataManager")
ctx.Load(SharedModules, "CharacterManager")

-- ───────────────────────────────────────────────────────────
-- REGISTRIES
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "WeaponRegistry")
ctx.Load(SharedModules, "ArmorRegistry")
ctx.Load(SharedModules, "SkillRegistry")
ctx.Load(SharedModules, "MobSkillRegistry")
ctx.Load(SharedModules, "MobRegistry")

-- ───────────────────────────────────────────────────────────
-- STATS, CURRENCY, BONUSES
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "StatsManager")
ctx.Load(SharedModules, "CurrencyManager")

ctx.Load(SharedModules, "BonusManager")
if ctx.loaded["BonusManager"] and ctx.loaded["PlayerDataManager"] then
    ctx.loaded["BonusManager"].InjectDataManager(ctx.loaded["PlayerDataManager"])
end

ctx.Load(SharedModules, "TalentEffectAggregator")
ctx.Load(SharedModules, "TalentManager")
ctx.Load(SharedModules, "BonusExpSystem")

-- ───────────────────────────────────────────────────────────
-- CLASS + EQUIPMENT + COSMETICS
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "ClassManager")
ctx.Load(SharedModules, "WeaponManager")
ctx.Load(SharedModules, "ArmorManager")
ctx.Load(SharedModules, "VisualEquipmentManager")
ctx.Load(SharedModules, "AnimationConfig")
ctx.Load(SharedModules, "CosmeticConfig")
ctx.Load(SharedModules, "CosmeticManager")

-- ───────────────────────────────────────────────────────────
-- ACHIEVEMENTS / EQUIPMENT / INVENTORY / DAILY / SHOP / LEADERBOARD
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "AchievementManager")
ctx.Load(SharedModules, "EquipmentHandler")
ctx.Load(SharedModules, "InventoryManager")
ctx.Load(SharedModules, "DailyLoginManager")
ctx.Load(SharedModules, "ShopManager")
ctx.Load(SharedModules, "LeaderboardManager")

-- ───────────────────────────────────────────────────────────
-- COMBAT SUPPORT
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "HitTracker")
ctx.Load(SharedModules, "ResourceManager")
ctx.Load(SharedModules, "AttackShapes")
ctx.Load(SharedModules, "ElementalSystem")

-- ───────────────────────────────────────────────────────────
-- DROPS
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "DropTableConfig")
ctx.Load(SharedModules, "DropManager")

-- ───────────────────────────────────────────────────────────
-- MONITORING + SHARED HANDLERS
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "MonitoringSystem")
ctx.Load(SharedModules, "SharedEventHandlers")

-- ───────────────────────────────────────────────────────────
-- HORDE ASSET PRE-LOAD
-- Moves ServerStorage.Models.Mobs → ReplicatedStorage.Mobs so MobSpawner
-- finds templates when it initialises.
-- ───────────────────────────────────────────────────────────
ctx.Load(HordeModeModules, "HordeModeMapLoader")
if ctx.loaded["HordeModeMapLoader"] then
    ctx.loaded["HordeModeMapLoader"].LoadAssets()
end

-- ───────────────────────────────────────────────────────────
-- MOB SYSTEMS
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "MobAI")
-- Switch MobAI into HordeMode: no X-axis lane filter, no perception cap.
if ctx.loaded["MobAI"] then ctx.loaded["MobAI"].SetHordeModeTargeting(true) end
ctx.Load(SharedModules, "WaveConfig")
ctx.Load(SharedModules, "MobSpawner")

-- ───────────────────────────────────────────────────────────
-- COMBAT
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "AttackHandler")
ctx.Load(SharedModules, "SkillEffects")
ctx.Load(SharedModules, "SkillManager")
ctx.Load(SharedModules, "KillRewardManager")
ctx.Load(SharedModules, "DeathSystem")
ctx.Load(SharedModules, "GameStateManager")

-- ───────────────────────────────────────────────────────────
-- HORDEMODE-SPECIFIC
-- ───────────────────────────────────────────────────────────
ctx.loaded["TeleportDataReader"] = require(SharedModules:WaitForChild("TeleportDataReader"))
ctx.loaded["TeleportDataReader"].Init("HordeMode")

-- §T0P2/X2: "Normal" is only the pre-arrival default. The real
-- difficulty is lobby-owned (DQ-B) and arrives with the first processed
-- player's teleport data — the OnDifficultyResolved hook below (after
-- the spawner loads) updates this local, the spawner, and VoteManager.
-- The old boot-time GetDifficulty() read always returned "Normal".
local hordeDifficulty = "Normal"

-- §AGX/SEC: §T0P2-ADMIN — admin panel backend is Studio-only.
if ctx.IsStudio then ctx.Load(SharedModules, "AdminTesting") end

Players.PlayerRemoving:Connect(function(player)
    local tdr = ctx.loaded["TeleportDataReader"]
    if tdr and tdr.OnPlayerRemoving then tdr.OnPlayerRemoving(player) end
end)

ctx.Load(HordeModeModules, "HordeModeSpawner")
ctx.Load(HordeModeModules, "HordePauseManager")
ctx.Load(SharedModules, "ReturnTeleporter")

-- ───────────────────────────────────────────────────────────
-- VOTE SYSTEM
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "CardRegistry")
ctx.Load(SharedModules, "RunModifiers")
ctx.Load(SharedModules, "VoteManager")

-- ───────────────────────────────────────────────────────────
-- VALIDATE CRITICAL MODULES
-- ───────────────────────────────────────────────────────────
ctx.RequireLoaded("PlayerDataManager")
ctx.RequireLoaded("MobAI")
ctx.RequireLoaded("MobRegistry")
ctx.RequireLoaded("HordeModeSpawner")
ctx.RequireLoaded("VoteManager")
ctx.RequireLoaded("NetworkManager")
ctx.RequireLoaded("StatsManager")
ctx.RequireLoaded("CurrencyManager")
ctx.RequireLoaded("GameStateManager")
ctx.RequireLoaded("SharedEventHandlers")

-- ───────────────────────────────────────────────────────────
-- LATE INIT
-- ───────────────────────────────────────────────────────────
ctx.loaded["GameStateManager"].LateInit()

-- ───────────────────────────────────────────────────────────
-- SHORTCUTS (after load+validate, before wiring)
-- ───────────────────────────────────────────────────────────
local NetworkManager    = ctx.loaded["NetworkManager"]
local DataManager       = ctx.loaded["PlayerDataManager"]
local Config            = ctx.loaded["PlayerDataConfig"]
local ResourceManager   = ctx.loaded["ResourceManager"]
local GameStateManager  = ctx.loaded["GameStateManager"]
local MobSpawner        = ctx.loaded["MobSpawner"]
local MobAI             = ctx.loaded["MobAI"]
local HordeModeSpawner  = ctx.loaded["HordeModeSpawner"]
local HordePauseManager = ctx.loaded["HordePauseManager"]
local VoteManager       = ctx.loaded["VoteManager"]
local RunModifiers      = ctx.loaded["RunModifiers"]
local TeleportDataReader = ctx.loaded["TeleportDataReader"]
local ReturnTeleporter   = ctx.loaded["ReturnTeleporter"]

-- ───────────────────────────────────────────────────────────
-- RUN-TIMING STATE
-- §HM3 fix: declared at the top of the chunk so the OnStateChanged
-- closure correctly captures them as locals, not globals.
-- ───────────────────────────────────────────────────────────
local hordeStartTime     = os.clock()
local hordeRunActive     = true
local totalPauseDuration = 0
local pauseStartedAt     = nil

-- ───────────────────────────────────────────────────────────
-- GAME STATE EVENTS
-- §T0P2/X13 (DQ-C): HordeMode servers are ONE-RUN by design — players
-- are returned to the lobby at the end and the server dies. The old
-- OnStateChanged closure re-armed the run timers "on each Defending
-- entry", but the vote loop and run-timer threads below exit
-- permanently after the first run, so a re-armed state machine would
-- have had no votes and no end-timer. Deleted rather than made
-- restartable. If re-runs in one server ever become a thing, restart
-- the two loops here too.
-- ───────────────────────────────────────────────────────────
GameStateManager.OnReturnToLobby(function()
    if RunModifiers then RunModifiers.Reset() end
    if ReturnTeleporter then ReturnTeleporter.TeleportAllToLobby() end
end)

-- §AGX/D-FIX2: end the run flag on ANY run end, not just the run timer.
-- A team-wipe TriggerDefeat left hordeRunActive true, so the vote loop
-- could open a vote and Pause/Resume the horde over the DEFEAT screen
-- during the ReturnToLobbyDelay. (Not a re-arm — see §T0P2/X13 above.)
GameStateManager.OnStateChanged(function(newState)
    if newState == "Defeat" or newState == "Victory" then
        hordeRunActive = false
    end
end)

-- MobSpawner is loaded for shared callbacks but HordeMode uses
-- HordeModeSpawner instead. Guard against accidental wave events.
MobSpawner.OnWaveStarted(function(waveNumber)
    warn("[HordeMode] Unexpected MobSpawner wave event — ignoring. Wave: " .. tostring(waveNumber))
end)
MobSpawner.OnWaveCompleted(function(waveNumber)
    warn("[HordeMode] Unexpected MobSpawner wave-complete event — ignoring. Wave: " .. tostring(waveNumber))
end)

-- ───────────────────────────────────────────────────────────
-- SHARED EVENT HANDLERS
-- ───────────────────────────────────────────────────────────
ctx.loaded["SharedEventHandlers"].Register({
    NetworkManager  = NetworkManager,
    DataManager     = DataManager,
    Config          = Config,
    ResourceManager = ResourceManager,
    IsAdmin         = IsAdmin,
})

-- ───────────────────────────────────────────────────────────
-- HORDE SPAWNER + PAUSE + VOTE SETUP
-- ───────────────────────────────────────────────────────────
HordeModeSpawner.Setup(MobAI, ctx.loaded["MobRegistry"])
HordeModeSpawner.SetDifficulty(hordeDifficulty)

-- §T0P2/X2: apply the real difficulty once it resolves. Updates the
-- hordeDifficulty upvalue too, so the vote loop's SetRunState pushes
-- report the true tier instead of the boot default.
TeleportDataReader.OnDifficultyResolved(function(difficulty)
    hordeDifficulty = tostring(difficulty)
    HordeModeSpawner.SetDifficulty(hordeDifficulty)
    VoteManager.SetRunState({ difficulty = hordeDifficulty })
    print("[HordeMode] Difficulty resolved:", hordeDifficulty)
end)

-- §3.1 fix: defer Start() until the first player's DataStore load
-- completes so the party-anchor level isn't read as the default 1.
local hordeSpawnerStarted = false
-- §AGX/D-FIX: N6 — level-watcher baseline, hoisted so anchor jumps can re-baseline it (a 1→2 anchor looked like a natural +1 tick).
local hordeLevelBaseline = HordeModeSpawner.GetLevel() or 1
local function startSpawnerOnce()
    if hordeSpawnerStarted then return end
    hordeSpawnerStarted = true

    local highest = 1
    for _, p in ipairs(Players:GetPlayers()) do
        local lvl = DataManager.GetAccountData(p, "Level") or 1
        if lvl > highest then highest = lvl end
    end
    -- §AGX/SEC: Start() FIRST. Its first call resets currentLevel /
    -- maxAutoLevel to CFG defaults, which silently clobbered an anchor
    -- applied before it (the per-player extras re-anchor masked this).
    HordeModeSpawner.Start()
    if highest > 1 then
        HordeModeSpawner.SetPartyAnchorLevel(highest)
    end
    -- §AGX/D-FIX: N6 — re-baseline after Start()+anchor so the jump isn't credited as a survived wave.
    hordeLevelBaseline = HordeModeSpawner.GetLevel() or hordeLevelBaseline
end

-- §AGX/WC: §PB-D3 — the spawner now also waits for the all-players-ready
-- gate (see the EnableStartGate block below). Both conditions must hold:
-- a loaded player (§3.1 anchor) AND the gate open.
local hordeGateOpen  = false
local hordeDataReady = false
local function tryStartSpawner()
    if hordeGateOpen and hordeDataReady then startSpawnerOnce() end
end

if DataManager.OnPlayerDataReady then
    DataManager.OnPlayerDataReady(function()
        hordeDataReady = true
        -- §AGX/D-FIX: S1 — same pcall as the gate path; a spawner throw must not break the data-ready callback chain.
        local ok, err = pcall(tryStartSpawner)
        if not ok then warn("[HordeMode] Spawner start failed:", err) end
    end)
else
    warn("[HordeMode] PlayerDataManager.OnPlayerDataReady missing; spawner waits for the start gate only")
    hordeDataReady = true
end

HordePauseManager.Setup({
    MobAI            = MobAI,
    HordeModeSpawner = HordeModeSpawner,
    NetworkManager   = NetworkManager,
})

-- §EASY/E4 (§AM4): HordeMode has no MobSpawner waves, so wavesSurvived /
-- highestWave never advanced for horde players. Watch the horde level
-- and feed each increment into the SAME public hook the wave system uses.
-- §AGX/X27: the same watcher also records HighestWaveReached (same level
-- number the achievement hook gets), so it no longer bails when
-- AchievementManager is missing.
-- §AGX/SEC: HighestWave semantics = the highest wave/level COMPLETED,
-- same as Lane (MobSpawner.OnWaveCompleted passes the wave just cleared)
-- and the achievement hook. Level N→N+1 means level N was survived, so we
-- report the OLD level; the old loop reported the level just REACHED
-- (one too high). Only a single-step tick counts as progress: the party
-- anchor (SetPartyAnchorLevel) and the Studio setHordeLevel command jump
-- the level, and those jumps used to be credited as dozens of "survived"
-- waves. Any other change just re-baselines. Natural ticks are 75 s apart
-- (HordeModeSpawner CFG.LEVEL_TICK_INTERVAL) against a 2 s poll.
task.spawn(function()
    local amMod = ctx.loaded["AchievementManager"]
    if amMod and not amMod.OnWaveCompleted then amMod = nil end
    -- §AGX/D-FIX: N6 — baseline lives in hordeLevelBaseline (re-set by anchors); no credit before the spawner runs.
    while hordeRunActive do
        task.wait(2)
        local lv = HordeModeSpawner.GetLevel() or hordeLevelBaseline
        if hordeSpawnerStarted and lv == hordeLevelBaseline + 1 then
            local completed = hordeLevelBaseline  -- the level just survived
            if amMod then amMod.OnWaveCompleted(completed) end
            GameStateManager.RecordWaveReached(completed)
        end
        hordeLevelBaseline = lv
    end
end)

VoteManager.Setup({
    NetworkManager    = NetworkManager,
    CardRegistry      = ctx.loaded["CardRegistry"],
    RunModifiers      = RunModifiers,
    PlayerDataManager = DataManager,
    BonusManager      = ctx.loaded["BonusManager"],
    ResourceManager   = ResourceManager,
    CurrencyManager   = ctx.loaded["CurrencyManager"],
})
VoteManager.SetModeDeps({ mobSpawner = HordeModeSpawner })
VoteManager.SetRunState({
    difficulty = hordeDifficulty,
    elapsed    = 0,
    modeId     = "HordeMode",
})

-- §T0P2/X13: one-run server; no OnStateChanged re-arm exists anymore.
-- "suppressWaveStart" keeps MobSpawner's wave 1 out of Defending (Horde
-- spawns via HordeModeSpawner).
-- §AGX/WC: §PB-D3 — no more SetState("Defending") at boot. The shared
-- start gate enters Defending itself (autoStart) once every party member
-- expected here has sent ClientReady, or 20 s after the first one did.
-- No Start button: RequestStartGame is refused in auto-start places and
-- the HUD shows "Waiting for party (x/y)…" until then. The spawner, vote
-- cadence and run timer start from the OnStartGateOpen hook below.
GameStateManager.suppressWaveStart = true
GameStateManager.EnableStartGate({ autoStart = true })

-- ───────────────────────────────────────────────────────────
-- DEBUG COMMANDS (admin-only)
-- ───────────────────────────────────────────────────────────
-- §AGX/SEC: §T0P2-ADMIN — the DebugCommand remote exists only in Studio
-- (NetworkManager studioOnly); outside Studio nothing is wired here.
if ctx.IsStudio then
    NetworkManager.OnClientEvent("DebugCommand", function(player, command, ...)
        if not IsAdmin(player) then return end
        local args = {...}

        if command == "skipWave" then
            MobSpawner.ForceCompleteWave()
        elseif command == "addXP" then
            local amount = tonumber(args[1]) or 100  -- §AGX/SEC: type-check client arg
            DataManager.AddExperience(player, amount)
        elseif command == "setHordeLevel" then
            HordeModeSpawner.SetLevel(tonumber(args[1]) or 1)
        elseif command == "stopHorde" then
            HordeModeSpawner.Stop()
        elseif command == "startHorde" then
            HordeModeSpawner.Start()
        elseif command == "pauseHorde" then
            HordePauseManager.Pause()
        elseif command == "resumeHorde" then
            HordePauseManager.Resume()
        elseif command == "toggleHordePause" then
            HordePauseManager.Toggle()
        end
    end)
end

-- ───────────────────────────────────────────────────────────
-- AMBIENT LOOPS (vitals + regen)
-- ───────────────────────────────────────────────────────────
Lifecycle.StartVitalsLoop(ctx)

-- ───────────────────────────────────────────────────────────
-- HORDE VOTE CADENCE + RUN DURATION
--
-- Supply Vote every 45 s, Threat Vote every 90 s (alternating).
-- Run lasts RUN_DURATION seconds of *play time* — pause windows are
-- excluded because HordePauseManager freezes the mobs + spawner.
-- Budget math: 14 × 45 s = 630 s = 10 m 30 s (also 7 × 90 s).
--   Each vote pauses for ~12 s → 14 × 12 = 168 s pause.
--   Wall-clock ≈ 13 m 18 s; players see 10 m 30 s of action.
-- ───────────────────────────────────────────────────────────
local SUPPLY_INTERVAL = 45    -- seconds of play-time between votes
local RUN_DURATION    = 630   -- 10 m 30 s of play time

-- §AGX/WC: §PB-D3 — both loops now start when the start gate opens
-- (startHordeLoops, called from the OnStartGateOpen hook below), not at
-- boot, so the play clock and vote cadence count from the real start.
local hordeLoopsStarted = false
local function startHordeLoops()
    if hordeLoopsStarted then return end
    hordeLoopsStarted = true
    hordeStartTime = os.clock()
    VoteManager.SetRunState({ difficulty = hordeDifficulty, elapsed = 0, modeId = "HordeMode" })

    -- Single alternating vote loop.
    task.spawn(function()
        local voteIndex = 0
        task.wait(SUPPLY_INTERVAL)
        while HordeModeSpawner and hordeRunActive do
            voteIndex = voteIndex + 1
            local voteType = (voteIndex % 2 == 1) and "supply" or "threat"

            -- §AGX/D-FIX2: only open votes while actually Defending.
            if VoteManager and not VoteManager.IsVoteActive()
                and GameStateManager.GetState() == "Defending" then
                -- ① 2 s heads-up before the freeze
                NetworkManager.FireAllClients("VotePending", { voteType = voteType, countdown = 2 })
                task.wait(2)
                -- §AGX/SEC: the run can end during the heads-up; don't pause
                -- the horde and open a vote on top of the victory screen.
                if not hordeRunActive or GameStateManager.GetState() ~= "Defending" then break end  -- §AGX/D-FIX2

                -- ② Pause + start vote
                pauseStartedAt = os.clock()
                HordePauseManager.Pause()
                VoteManager.SetRunState({
                    difficulty = hordeDifficulty,
                    elapsed    = os.clock() - hordeStartTime - totalPauseDuration,
                    modeId     = "HordeMode",
                })
                VoteManager.StartVote(voteType)

                -- ③ Wait for vote to finish (incl. §VG4 display+countdown grace)
                local maxWait = os.clock() + 12  -- VOTE_TIMER_SEC(10) + buffer
                repeat task.wait(0.1) until not VoteManager.IsVoteActive() or os.clock() > maxWait

                -- ④ Resume combat (§HM12: only if the run hasn't ended during the vote)
                if pauseStartedAt then
                    totalPauseDuration = totalPauseDuration + (os.clock() - pauseStartedAt)
                    pauseStartedAt = nil
                end
                if hordeRunActive then
                    HordePauseManager.Resume()
                end
            end

            task.wait(SUPPLY_INTERVAL)
        end
    end)

    -- Run timer — stops spawning, waits for mobs to clear, ends the run.
    -- §HM1: counts play-time (excludes pauses). §HM11: capped mob-clear wait.
    task.spawn(function()
        while hordeRunActive do
            task.wait(1)
            local pauseExtra = pauseStartedAt and (os.clock() - pauseStartedAt) or 0
            local elapsedPlay = (os.clock() - hordeStartTime) - totalPauseDuration - pauseExtra
            if elapsedPlay >= RUN_DURATION then break end
        end
        hordeRunActive = false

        HordeModeSpawner.Stop()

        -- §HM11: cap mob-clear wait at 30 s so a stuck mob can't hang the
        -- end-of-run forever. After timeout we proceed; mobs are about to be
        -- wiped by the lobby teleport anyway.
        if MobAI then
            local waitDeadline = os.clock() + 30
            while MobAI.IsAnyMobAlive() and os.clock() < waitDeadline do
                task.wait(1)
            end
            if MobAI.IsAnyMobAlive() then
                warn("[HordeMode] Run-end mob clear timed out (30 s); proceeding to lobby return")
            end
        end

        if RunModifiers then RunModifiers.Reset() end
        GameStateManager.TriggerVictory()
    end)
end  -- startHordeLoops

-- §AGX/WC: §PB-D3 — the run begins here (the gate already switched the
-- state to Defending before callbacks fire).
GameStateManager.OnStartGateOpen(function()
    hordeGateOpen = true
    -- §AGX/D-FIX: S1 — loops FIRST (timer/victory/votes must run even if the spawner throws), spawner pcall'd.
    startHordeLoops()
    local ok, err = pcall(tryStartSpawner)
    if not ok then
        warn("[HordeMode] Spawner start failed (run timer still active):", err)
    end
end)

-- ───────────────────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- §HM2: extras run the place-specific TeleportDataReader.ProcessPlayer,
-- re-anchor the HordeModeSpawner level, and push the current GameState
-- to late-joiners so their HUD doesn't show the IDLE "Start Game" button.
-- ───────────────────────────────────────────────────────────
Lifecycle.WireOnPlayerReady(ctx, {
    extras = function(player)
        if TeleportDataReader then TeleportDataReader.ProcessPlayer(player) end

        -- Re-anchor mob levels to the highest currently-loaded player level
        -- now that this player's data is confirmed loaded.
        local highest = 1
        for _, p in ipairs(Players:GetPlayers()) do
            local lvl = DataManager.GetAccountData(p, "Level") or 1
            if lvl > highest then highest = lvl end
        end
        -- §AGX/D-FIX: only before the run starts. SetPartyAnchorLevel resets
        -- currentLevel and the phase clock, so a mid-run joiner used to rewind
        -- the whole party's horde progress. startSpawnerOnce re-reads every
        -- loaded player's level when the gate opens anyway.
        if not hordeSpawnerStarted then
            HordeModeSpawner.SetPartyAnchorLevel(highest)
            -- §AGX/D-FIX: N6 — a late-join re-anchor is a jump too; re-baseline so it isn't credited.
            hordeLevelBaseline = HordeModeSpawner.GetLevel() or hordeLevelBaseline
        end

        -- Push current game state to late-joiners.
        -- §T0P2/X9: ReadyGate-routed — this fires from the data-ready
        -- path, i.e. exactly the boot window where a bare FireClient
        -- drops if the client hasn't subscribed yet (the race this
        -- late-joiner fix exists to solve).
        local state = GameStateManager.GetState()
        local rg = ctx.loaded["ReadyGate"]
        local fire = rg and rg.FireClient or NetworkManager.FireClient
        fire(player, "GameStateChanged", {
            oldState  = state,
            newState  = state,
            timestamp = os.clock(),
        })
    end,
})

print(string.format("[HordeMode] Place ready — %d modules loaded", (function()
    local n = 0
    for _ in pairs(ctx.loaded) do n = n + 1 end
    return n
end)()))
