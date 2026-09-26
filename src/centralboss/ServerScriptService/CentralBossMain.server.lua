-- centralboss/ServerScriptService/CentralBossMain.server.lua
--[[
    CentralBoss place bootstrap.

    Distinction from LaneDefense:
      • Mode identifier is "CentralBoss" (reported to TeleportDataReader).
      • No DefenseLine — single-arena boss fight.
      • A "BossPoint" Part in Workspace is the boss spawn and the players'
        facing target. BossEncounter falls back (MobSpawn /
        origin) and creates one if it is missing.
      • §AGX/X28: the fight is run by Modules/BossEncounter (core: phases,
        adds, HP bar, victory). Start button → Preparing → Defending →
        boss spawns. No lane waves: suppressWaveStart + RequestNextWave off.

    Helpers (Load, RequireLoaded, IsAdmin) live in PlaceBootstrap.
    Common per-player lifecycle (OnPlayerReady) and ambient loops
    (Vitals + HP regen) live in PlaceLifecycle.
]]

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

-- §T0P2/G3: bounded wait + loud error, never a silent infinite hang.
local SharedModules = SSS:WaitForChild("Modules", 10)
    or error("[CentralBossMain] ServerScriptService.Modules missing after 10 s — place structure broken", 0)

local Boot      = require(SharedModules:WaitForChild("PlaceBootstrap"))
local Lifecycle = require(SharedModules:WaitForChild("PlaceLifecycle"))
local ctx       = Boot.MakeContext("CentralBoss")
local IsAdmin   = ctx.IsAdmin

-- §T0P2/X19: no _G.CentralBossRequireLoaded (it was a write-only global).

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
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "MobAssetLoader")
if ctx.loaded["MobAssetLoader"] then ctx.loaded["MobAssetLoader"].Load() end
ctx.Load(SharedModules, "MobAI")
ctx.Load(SharedModules, "WaveConfig")
ctx.Load(SharedModules, "MobSpawner")
-- §AGX/X28: no lane waves in this place — block client RequestNextWave (X5).
if ctx.loaded["MobSpawner"] then ctx.loaded["MobSpawner"].ClientWaveRequestsDisabled = true end

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
-- CENTRALBOSS-SPECIFIC
-- ───────────────────────────────────────────────────────────
ctx.loaded["TeleportDataReader"] = require(SharedModules:WaitForChild("TeleportDataReader"))
ctx.loaded["TeleportDataReader"].Init("CentralBoss")

-- §T0P2/X2: difficulty is lobby-owned (DQ-B) and resolves with the
-- first processed player's teleport data, not at boot (where it
-- always reads "Normal").
ctx.loaded["TeleportDataReader"].OnDifficultyResolved(function(difficulty)
    local spawner = ctx.loaded["MobSpawner"]
    if spawner then spawner.SetDifficulty(tostring(difficulty)) end
    print("[CentralBoss] Difficulty resolved:", difficulty)
end)

-- §AGX/SEC: §T0P2-ADMIN — admin panel backend is Studio-only.
if ctx.IsStudio then ctx.Load(SharedModules, "AdminTesting") end

Players.PlayerRemoving:Connect(function(player)
    local tdr = ctx.loaded["TeleportDataReader"]
    if tdr and tdr.OnPlayerRemoving then tdr.OnPlayerRemoving(player) end
end)

ctx.Load(SharedModules, "ReturnTeleporter")

-- §AGX/X28: boss fight controller (place-local modules).
local BossModules = script.Parent:WaitForChild("Modules", 10)
    or error("[CentralBossMain] CentralBoss.Modules missing after 10 s — place structure broken", 0)
ctx.Load(BossModules, "BossEncounter")

-- ───────────────────────────────────────────────────────────
-- VALIDATE CRITICAL MODULES
-- ───────────────────────────────────────────────────────────
ctx.RequireLoaded("PlayerDataManager")
ctx.RequireLoaded("NetworkManager")
ctx.RequireLoaded("MobAI")              -- §AGX/X28
ctx.RequireLoaded("MobRegistry")        -- §AGX/X28
ctx.RequireLoaded("MobSpawner")         -- §AGX/X28
ctx.RequireLoaded("BossEncounter")      -- §AGX/X28
ctx.RequireLoaded("StatsManager")
ctx.RequireLoaded("CurrencyManager")
ctx.RequireLoaded("GameStateManager")
ctx.RequireLoaded("SharedEventHandlers")

-- ───────────────────────────────────────────────────────────
-- LATE INIT
-- ───────────────────────────────────────────────────────────
ctx.loaded["GameStateManager"].LateInit()

-- §AGX/WC: §PB-D3 — the manual Start button only works once every party
-- member expected here has sent ClientReady (20 s hard timeout after the
-- first ready player). Solo Studio opens on your own ClientReady.
ctx.loaded["GameStateManager"].EnableStartGate({ autoStart = false })

-- §AGX/X28: wire the fight into the Defending state (sets
-- suppressWaveStart, arena targeting, state/lobby callbacks).
ctx.loaded["BossEncounter"].Setup({
    GameStateManager   = ctx.loaded["GameStateManager"],
    MobAI              = ctx.loaded["MobAI"],
    MobRegistry        = ctx.loaded["MobRegistry"],
    MobSpawner         = ctx.loaded["MobSpawner"],
    NetworkManager     = ctx.loaded["NetworkManager"],
    TeleportDataReader = ctx.loaded["TeleportDataReader"],
    PlayerDataManager  = ctx.loaded["PlayerDataManager"],
    ReadyGate          = ctx.loaded["ReadyGate"],
})

-- ───────────────────────────────────────────────────────────
-- SHORTCUTS
-- ───────────────────────────────────────────────────────────
local Config            = ctx.loaded["PlayerDataConfig"]
local NetworkManager    = ctx.loaded["NetworkManager"]
local DataManager       = ctx.loaded["PlayerDataManager"]
local ResourceManager   = ctx.loaded["ResourceManager"]
local GameStateManager  = ctx.loaded["GameStateManager"]
local MobSpawner        = ctx.loaded["MobSpawner"]
local TeleportDataReader = ctx.loaded["TeleportDataReader"]
local ReturnTeleporter   = ctx.loaded["ReturnTeleporter"]

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
GameStateManager.OnReturnToLobby(function()
    if ReturnTeleporter then ReturnTeleporter.TeleportAllToLobby() end
end)

MobSpawner.OnWaveCompleted(function(waveNumber)
    local waveXP = 15 + (15 * waveNumber)
    for _, p in ipairs(Players:GetPlayers()) do
        DataManager.AddExperience(p, waveXP)
    end
end)

-- ───────────────────────────────────────────────────────────
-- DEBUG COMMANDS
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
        elseif command == "bossHP" then
            -- §AGX/X28: jump phases while testing, e.g. bossHP 0.5 → phase 2.
            local fraction = tonumber(args[1])
            if fraction then ctx.loaded["BossEncounter"].DebugSetHpFraction(fraction) end
        end
    end)
end

-- ───────────────────────────────────────────────────────────
-- AMBIENT LOOPS
-- ───────────────────────────────────────────────────────────
Lifecycle.StartVitalsLoop(ctx)

-- ───────────────────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ───────────────────────────────────────────────────────────
Lifecycle.WireOnPlayerReady(ctx, {
    extras = function(player)
        if TeleportDataReader then TeleportDataReader.ProcessPlayer(player) end
    end,
})

print(string.format("[CentralBoss] Place ready — %d modules loaded", (function()
    local n = 0
    for _ in pairs(ctx.loaded) do n = n + 1 end
    return n
end)()))

-- §CB1 / §AGX/X28: the core boss fight is wired (BossEncounter). The mode
-- stays hidden in the lobby (GameModeConfig / MainMenu `available = false`)
-- until Pablo tests it in Studio; next steps: BACKLOG §AGX/X28-NEXT.
