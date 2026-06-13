-- centralboss/ServerScriptService/CentralBossMain.server.lua
--[[
    CentralBoss place bootstrap.

    Distinction from LaneDefense:
      • Mode identifier is "CentralBoss" (reported to TeleportDataReader).
      • No DefenseLine — single-arena boss fight.
      • A "BossPoint" Part in Workspace is expected for character facing
        targets. Map designers place it; the server doesn't enforce it.
      • The boss fight itself is currently UNAUTHORED — see warn at bottom.

    Helpers (Load, RequireLoaded, IsAdmin) live in PlaceBootstrap.
    Common per-player lifecycle (OnPlayerReady) and ambient loops
    (Vitals + HP regen) live in PlaceLifecycle.
]]

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

-- §T0P2/G3: bounded wait + loud error (was: silent infinite hang).
local SharedModules = SSS:WaitForChild("Modules", 10)
    or error("[CentralBossMain] ServerScriptService.Modules missing after 10 s — place structure broken", 0)

local Boot      = require(SharedModules:WaitForChild("PlaceBootstrap"))
local Lifecycle = require(SharedModules:WaitForChild("PlaceLifecycle"))
local ctx       = Boot.MakeContext("CentralBoss")
local IsAdmin   = ctx.IsAdmin

-- §T0P2/X19: _G.CentralBossRequireLoaded removed — write-only global.

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
-- first processed player's teleport data — not at boot, where it was
-- always "Normal".
ctx.loaded["TeleportDataReader"].OnDifficultyResolved(function(difficulty)
    local spawner = ctx.loaded["MobSpawner"]
    if spawner then spawner.SetDifficulty(tostring(difficulty)) end
    print("[CentralBoss] Difficulty resolved:", difficulty)
end)

ctx.Load(SharedModules, "AdminTesting")

Players.PlayerRemoving:Connect(function(player)
    local tdr = ctx.loaded["TeleportDataReader"]
    if tdr and tdr.OnPlayerRemoving then tdr.OnPlayerRemoving(player) end
end)

ctx.Load(SharedModules, "ReturnTeleporter")

-- ───────────────────────────────────────────────────────────
-- VALIDATE CRITICAL MODULES
-- (No boss/vote modules required here — place is currently unauthored.)
-- ───────────────────────────────────────────────────────────
ctx.RequireLoaded("PlayerDataManager")
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
NetworkManager.OnClientEvent("DebugCommand", function(player, command, ...)
    if not IsAdmin(player) then return end
    local args = {...}
    if command == "skipWave" then
        MobSpawner.ForceCompleteWave()
    elseif command == "addXP" then
        local amount = args[1] or 100
        DataManager.AddExperience(player, amount)
    end
end)

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

-- §CB1: this place currently has NO authored boss fight. Bootstrap loads
-- shared modules and registers wave callbacks, but nothing calls
-- MobSpawner.Start() and no boss is spawned. A player teleporting here
-- will see an empty arena. We surface this loudly at boot so testers
-- (and the dev console) make it obvious instead of looking like a
-- network problem. Remove this warn once the boss fight is wired.
warn("[CentralBoss] ⚠ Mode is UNAUTHORED — no boss will spawn. " ..
    "This bootstrap is a placeholder. See docs/TODO.md → 'CentralBoss " ..
    "authored content'.")
