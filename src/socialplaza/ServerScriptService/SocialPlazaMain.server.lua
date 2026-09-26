-- socialplaza/ServerScriptService/SocialPlazaMain.server.lua
--[[
    Social Plaza place bootstrap.

    SocialPlaza is the dedicated sandbox for testing animations,
    cinematics, character appearance, and future open-world features.
    It mirrors the Lobby's player-data + cosmetic + economy stack so a
    player who teleports here has the same persistent state, but it
    intentionally drops:

      • NPC system (NPCManager, LobbyNPCRegistry, SceneManager)
      • Party / Matchmaking / Teleport (no launching into combat)
      • SkillRegistry (§PB-D2: no skills, no consumer)

    Combat systems (mobs, waves, defense line, attack handler) are NOT
    loaded — same as Lobby.

    Helpers (Load, RequireLoaded, IsAdmin) live in PlaceBootstrap.
    Common per-player lifecycle (OnPlayerReady) lives in PlaceLifecycle.
]]

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

-- §T0P2/G3: bounded wait + loud error (was: silent infinite hang).
local SharedModules = SSS:WaitForChild("Modules", 10)
    or error("[SocialPlazaMain] ServerScriptService.Modules missing after 10 s — place structure broken", 0)

local Boot      = require(SharedModules:WaitForChild("PlaceBootstrap"))
local Lifecycle = require(SharedModules:WaitForChild("PlaceLifecycle"))
local ctx       = Boot.MakeContext("SocialPlaza")
local IsAdmin   = ctx.IsAdmin

-- ───────────────────────────────────────────────────────────
-- CONFIG (pure data, no Init)
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "PlayerDataConfig")
ctx.Load(SharedModules, "WeaponConfig")
ctx.Load(SharedModules, "ArmorConfig")
ctx.Load(SharedModules, "GearUpgradeConfig")  -- §CFG-D1: shared upgrade tables
ctx.Load(SharedModules, "ClassConfig")
ctx.Load(SharedModules, "CharacterConfig")
ctx.Load(SharedModules, "GameModeConfig")
ctx.Load(SharedModules, "AnimationConfig")
ctx.Load(SharedModules, "CosmeticConfig")

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
-- REGISTRIES (no SkillRegistry — §PB-D2)
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "WeaponRegistry")
ctx.Load(SharedModules, "ArmorRegistry")

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

-- ───────────────────────────────────────────────────────────
-- CLASS, EQUIPMENT, COSMETICS  (the headline systems for this place)
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "ClassManager")
ctx.Load(SharedModules, "WeaponManager")
ctx.Load(SharedModules, "ArmorManager")
ctx.Load(SharedModules, "VisualEquipmentManager")
ctx.Load(SharedModules, "CosmeticManager")

-- ───────────────────────────────────────────────────────────
-- ACHIEVEMENTS / DAILY LOGIN / SHOP / LEADERBOARD
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "AchievementManager")
ctx.Load(SharedModules, "EquipmentHandler")
ctx.Load(SharedModules, "InventoryManager")
ctx.Load(SharedModules, "DailyLoginManager")
ctx.Load(SharedModules, "ShopManager")
ctx.Load(SharedModules, "LeaderboardManager")

-- ───────────────────────────────────────────────────────────
-- RESOURCE (HUD resource bar even without combat)
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "ResourceManager")

-- ───────────────────────────────────────────────────────────
-- MONITORING + SHARED HANDLERS + BONUS XP + ADMIN
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "MonitoringSystem")
ctx.Load(SharedModules, "SharedEventHandlers")
ctx.Load(SharedModules, "BonusExpSystem")
ctx.Load(SharedModules, "AdminTesting")

-- §AGX/UI-P3: D15 exit from the Plaza (shell-spec F4/B9). The menu's
-- `leave` entry fires RequestReturnToLobby; only NetworkManager and
-- TeleportService are needed, and the handler has no state gate.
ctx.Load(SharedModules, "ReturnTeleporter")

-- ───────────────────────────────────────────────────────────
-- VALIDATE CRITICAL MODULES
-- ───────────────────────────────────────────────────────────
ctx.RequireLoaded("PlayerDataConfig")
ctx.RequireLoaded("PlayerDataManager")
ctx.RequireLoaded("NetworkManager")
ctx.RequireLoaded("ReadyGate")
ctx.RequireLoaded("StatsManager")
ctx.RequireLoaded("CurrencyManager")
ctx.RequireLoaded("CosmeticManager")
ctx.RequireLoaded("SharedEventHandlers")

-- ───────────────────────────────────────────────────────────
-- SHARED EVENT HANDLERS
-- ───────────────────────────────────────────────────────────
local NetworkManager  = ctx.loaded["NetworkManager"]
local DataManager     = ctx.loaded["PlayerDataManager"]
local Config          = ctx.loaded["PlayerDataConfig"]
local ResourceManager = ctx.loaded["ResourceManager"]

ctx.loaded["SharedEventHandlers"].Register({
    NetworkManager  = NetworkManager,
    DataManager     = DataManager,
    Config          = Config,
    ResourceManager = ResourceManager,
    IsAdmin         = IsAdmin,
})

-- ───────────────────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ───────────────────────────────────────────────────────────
-- §T0-FOLLOWUP/L4: PlayerDataManager.Init already binds RemovePlayer to
-- PlayerRemoving. A second binding here used to fire after the first
-- cleared playerDataStore[player], which surfaced as a noisy
-- "in-memory data is nil" warn on every disconnect.
Lifecycle.WireOnPlayerReady(ctx)

print(string.format("[SocialPlaza] Place ready — %d modules loaded", (function()
    local n = 0
    for _ in pairs(ctx.loaded) do n = n + 1 end
    return n
end)()))
