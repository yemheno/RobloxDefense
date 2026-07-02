-- lanedefense/ServerScriptService/LaneDefenseMain.server.lua
--[[
    LaneDefense place bootstrap.

    Loads shared core + all combat systems.
    Reads TeleportData from the Lobby place (party, difficulty, mode).

    Lobby-specific systems (party, matchmaking, NPC, scene) are NOT loaded
    — they live only in the lobby place.

    Helpers (Load, RequireLoaded, IsAdmin) live in PlaceBootstrap.
    Common per-player lifecycle (OnPlayerReady) and ambient loops
    (Vitals + HP regen) live in PlaceLifecycle.
]]

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

-- §T0P2/G3: bounded wait + loud error (was: silent infinite hang).
local SharedModules = SSS:WaitForChild("Modules", 10)
    or error("[LaneDefenseMain] ServerScriptService.Modules missing after 10 s — place structure broken", 0)

local Boot      = require(SharedModules:WaitForChild("PlaceBootstrap"))
local Lifecycle = require(SharedModules:WaitForChild("PlaceLifecycle"))
local ctx       = Boot.MakeContext("LaneDefense")
local IsAdmin   = ctx.IsAdmin

-- §T0P2/X19: _G.LaneDefenseRequireLoaded removed — write-only global.

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
-- MOB SYSTEMS
-- MobAssetLoader moves ServerStorage.Mobs → ReplicatedStorage before
-- MobSpawner.Init() can clone templates from it.
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "MobAssetLoader")
if ctx.loaded["MobAssetLoader"] then ctx.loaded["MobAssetLoader"].Load() end
ctx.Load(SharedModules, "MobAI")
ctx.Load(SharedModules, "WaveConfig")
ctx.Load(SharedModules, "MobSpawner")

-- ───────────────────────────────────────────────────────────
-- DEFENSE LINE
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "DefenseLine")

-- ───────────────────────────────────────────────────────────
-- COMBAT (attacks, skills, kill rewards, death system, state machine)
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "AttackHandler")
ctx.Load(SharedModules, "SkillEffects")
ctx.Load(SharedModules, "SkillManager")
ctx.Load(SharedModules, "KillRewardManager")
ctx.Load(SharedModules, "DeathSystem")
ctx.Load(SharedModules, "GameStateManager")

-- ───────────────────────────────────────────────────────────
-- VOTE SYSTEM
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "CardRegistry")
ctx.Load(SharedModules, "RunModifiers")
ctx.Load(SharedModules, "VoteManager")

-- ───────────────────────────────────────────────────────────
-- LANEDEFENSE-SPECIFIC
-- ───────────────────────────────────────────────────────────
ctx.loaded["TeleportDataReader"] = require(SharedModules:WaitForChild("TeleportDataReader"))
ctx.loaded["TeleportDataReader"].Init("Defense")

-- §T0P2/X2: difficulty arrives with the FIRST processed player's
-- teleport data (lobby-owned — DQ-B), not at boot. The old boot-time
-- GetDifficulty() read always returned "Normal" because ProcessPlayer
-- hadn't run yet — the lobby's difficulty selection never reached the
-- spawner. OnDifficultyResolved fires once, validated, when it's real.
ctx.loaded["TeleportDataReader"].OnDifficultyResolved(function(difficulty)
    local spawner = ctx.loaded["MobSpawner"]
    if spawner then spawner.SetDifficulty(tostring(difficulty)) end
    local vm = ctx.loaded["VoteManager"]
    if vm then vm.SetRunState({ difficulty = tostring(difficulty) }) end
    print("[LaneDefense] Difficulty resolved:", difficulty)
end)

-- §LD1 fix + §T3/W8: anchor mob levels to the highest player level,
-- re-computed on EVERY player's data-ready (mirrors HordeMode's extras
-- re-anchor). The old once-flag anchored to whichever player's data
-- loaded FIRST — a later-loading higher-level player never counted, so
-- subsequent waves under-scaled (carried G6). SetPartyAnchorLevel only
-- affects future waves, which is exactly what we want here.
local function applyLaneAnchor()
    local ok, err = pcall(function()
        local spawner = ctx.loaded["MobSpawner"]
        local pdm = ctx.loaded["PlayerDataManager"]
        if not spawner or not pdm then return end
        local highest = 1
        for _, player in ipairs(Players:GetPlayers()) do
            local lvl = pdm.GetAccountData(player, "Level") or 1
            if lvl > highest then highest = lvl end
        end
        spawner.SetPartyAnchorLevel(highest)
    end)
    if not ok then
        warn("[LaneDefense] Party anchor computation failed: " .. tostring(err))
    end
end

if ctx.loaded["PlayerDataManager"] and ctx.loaded["PlayerDataManager"].OnPlayerDataReady then
    ctx.loaded["PlayerDataManager"].OnPlayerDataReady(function() applyLaneAnchor() end)
else
    warn("[LaneDefense] PlayerDataManager.OnPlayerDataReady missing; applying anchor immediately")
    applyLaneAnchor()
end

ctx.Load(SharedModules, "AdminTesting")

-- TeleportDataReader cleanup on leave
Players.PlayerRemoving:Connect(function(player)
    local tdr = ctx.loaded["TeleportDataReader"]
    if tdr and tdr.OnPlayerRemoving then tdr.OnPlayerRemoving(player) end
end)

ctx.Load(SharedModules, "ReturnTeleporter")

-- ───────────────────────────────────────────────────────────
-- VALIDATE CRITICAL MODULES
-- ───────────────────────────────────────────────────────────
ctx.RequireLoaded("PlayerDataManager")
ctx.RequireLoaded("NetworkManager")
ctx.RequireLoaded("MobAI")
ctx.RequireLoaded("MobRegistry")
ctx.RequireLoaded("MobSpawner")
ctx.RequireLoaded("DefenseLine")
ctx.RequireLoaded("VoteManager")
ctx.RequireLoaded("StatsManager")
ctx.RequireLoaded("CurrencyManager")
ctx.RequireLoaded("GameStateManager")
ctx.RequireLoaded("SharedEventHandlers")

-- ───────────────────────────────────────────────────────────
-- LATE INIT
-- ───────────────────────────────────────────────────────────
ctx.loaded["GameStateManager"].LateInit()
ctx.loaded["DefenseLine"].LateInit()

-- Card / vote system
do
    local vm = ctx.loaded["VoteManager"]
    -- §T0P2/X2: "Normal" is only the pre-arrival default; the real
    -- difficulty lands via OnDifficultyResolved above.
    local laneDifficulty = "Normal"
    vm.Setup({
        NetworkManager   = ctx.loaded["NetworkManager"],
        CardRegistry     = ctx.loaded["CardRegistry"],
        RunModifiers     = ctx.loaded["RunModifiers"],
        PlayerDataManager = ctx.loaded["PlayerDataManager"],
        BonusManager     = ctx.loaded["BonusManager"],
        ResourceManager  = ctx.loaded["ResourceManager"],
        CurrencyManager  = ctx.loaded["CurrencyManager"],
    })
    vm.SetModeDeps({
        mobSpawner  = ctx.loaded["MobSpawner"],
        defenseLine = ctx.loaded["DefenseLine"],
    })
    vm.SetRunState({ difficulty = laneDifficulty, modeId = "Defense" })
end

-- ───────────────────────────────────────────────────────────
-- SHORTCUTS
-- ───────────────────────────────────────────────────────────
local Config            = ctx.loaded["PlayerDataConfig"]
local NetworkManager    = ctx.loaded["NetworkManager"]
local DataManager       = ctx.loaded["PlayerDataManager"]
local ResourceManager   = ctx.loaded["ResourceManager"]
local GameStateManager  = ctx.loaded["GameStateManager"]
local MobSpawner        = ctx.loaded["MobSpawner"]
local DefenseLine       = ctx.loaded["DefenseLine"]
local TeleportDataReader = ctx.loaded["TeleportDataReader"]
local ReturnTeleporter   = ctx.loaded["ReturnTeleporter"]
local VoteManager        = ctx.loaded["VoteManager"]
local RunModifiers       = ctx.loaded["RunModifiers"]

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
-- GAME STATE EVENTS
-- ───────────────────────────────────────────────────────────
GameStateManager.OnStateChanged(function(newState, oldState)
    -- §47.1: Defense line HP scales with highest player level on each new run.
    if newState == "Defending" then
        local highestLevel = 1
        for _, p in ipairs(Players:GetPlayers()) do
            local data = DataManager.GetData(p)
            if data and data.Account and data.Account.Level then
                highestLevel = math.max(highestLevel, data.Account.Level)
            end
        end
        DefenseLine.SetChapterLevel(highestLevel)
    end
end)

GameStateManager.OnReturnToLobby(function()
    if RunModifiers then RunModifiers.Reset() end
    if ReturnTeleporter then ReturnTeleporter.TeleportAllToLobby() end
end)

MobSpawner.OnWaveStarted(function(waveNumber, _mobCount)
    -- Tactical Vote at the start of each wave
    if VoteManager and RunModifiers then
        RunModifiers.ResetWaveDanger()
        VoteManager.SetRunState({ waveNumber = waveNumber })
        VoteManager.StartVote("tactical")
    end
end)

-- Pre-spawn hook: wait for the vote to fully resolve (including the
-- §VG4 display + countdown grace) before letting the wave spawn.
if MobSpawner and VoteManager then
    MobSpawner.SetPreSpawnHook(function(_waveNumber)
        task.wait(0.1)  -- let OnWaveStarted callbacks fire
        while VoteManager.IsVoteActive() do task.wait(0.25) end
    end)
end

MobSpawner.OnWaveCompleted(function(waveNumber)
    -- Wave completion XP bonus: 15 + (15 × wave) to every active player.
    local waveXP = 15 + (15 * waveNumber)
    if RunModifiers then
        local danger = RunModifiers.GetTotalDangerBonus()
        waveXP = math.floor(waveXP * (1 + danger))
    end
    for _, p in ipairs(Players:GetPlayers()) do
        DataManager.AddExperience(p, waveXP)
    end
end)

DefenseLine.OnDestroyedCallback(function()
    GameStateManager.TriggerDefeat()
end)

-- ───────────────────────────────────────────────────────────
-- DEBUG COMMANDS (admin-only)
-- ───────────────────────────────────────────────────────────
NetworkManager.OnClientEvent("DebugCommand", function(player, command, ...)
    if not IsAdmin(player) then return end
    local args = {...}

    if command == "testDamage" then
        local tier = args[1] or "normal"
        local hp = args[2] or 50
        local atk = args[3] or 10
        DefenseLine.TestDamage(tier, hp, atk)
    elseif command == "healLine" then
        local amount = args[1] or 100
        DefenseLine.Heal(amount)
    elseif command == "setLineHP" then
        local hp = args[1] or DefenseLine.GetMaxHealth()
        DefenseLine.SetHealth(hp)
    elseif command == "skipWave" then
        MobSpawner.ForceCompleteWave()
    elseif command == "addXP" then
        local amount = args[1] or 100
        DataManager.AddExperience(player, amount)
    end
end)

-- ───────────────────────────────────────────────────────────
-- AMBIENT LOOPS (vitals + regen) — shared with Horde/CentralBoss.
-- ───────────────────────────────────────────────────────────
Lifecycle.StartVitalsLoop(ctx)

-- ───────────────────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ───────────────────────────────────────────────────────────
Lifecycle.WireOnPlayerReady(ctx, {
    extras = function(player)
        -- Read teleport data (party, difficulty, mode) for this player.
        if TeleportDataReader then TeleportDataReader.ProcessPlayer(player) end
        -- Send the defense line state so the HUD's defense bar is correct
        -- the moment the player joins.
        if DefenseLine then DefenseLine.SendStateToPlayer(player) end
    end,
})

print(string.format("[LaneDefense] Place ready — %d modules loaded", (function()
    local n = 0
    for _ in pairs(ctx.loaded) do n = n + 1 end
    return n
end)()))
