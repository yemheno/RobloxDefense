-- lobby/ServerScriptService/LobbyMain.server.lua
--[[
    Lobby place bootstrap.

    Loads ONLY the modules relevant to the lobby:
      • Shared core (data, classes, stats, currency, weapons, network)
      • Lobby-specific (party, matchmaking, scene, NPC, teleport)

    Combat systems (mobs, waves, defense line, attack handler, skills) are
    NOT loaded — they belong to the combat places.

    Helpers (Load, RequireLoaded, IsAdmin) live in PlaceBootstrap.
    Common per-player lifecycle (OnPlayerReady) lives in PlaceLifecycle.
]]

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

-- §T0P2/G3: bounded waits + loud error. The old no-timeout WaitForChild
-- hung the server forever, silently, if the place structure was broken.
local SharedModules = SSS:WaitForChild("Modules", 10)
    or error("[LobbyMain] ServerScriptService.Modules missing after 10 s — place structure broken", 0)
local LobbyFolder   = SSS:WaitForChild("Lobby", 10)
    or error("[LobbyMain] ServerScriptService.Lobby missing after 10 s — place structure broken", 0)
local LobbyModules  = LobbyFolder:WaitForChild("Modules", 10)
    or error("[LobbyMain] ServerScriptService.Lobby.Modules missing after 10 s — place structure broken", 0)

local Boot      = require(SharedModules:WaitForChild("PlaceBootstrap"))
local Lifecycle = require(SharedModules:WaitForChild("PlaceLifecycle"))
local ctx       = Boot.MakeContext("Lobby")
local IsAdmin   = ctx.IsAdmin

-- §T0P2/X19: _G.LobbyMainRequireLoaded removed — write-only global,
-- zero consumers anywhere in src/.

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
-- §PB-D2: SkillRegistry intentionally NOT loaded — the lobby doesn't
-- run any skills. Loading it would pull in the entire ClassSkills/*
-- graph for no consumer.
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

-- Talents (must load after BonusManager)
ctx.Load(SharedModules, "TalentEffectAggregator")
ctx.Load(SharedModules, "TalentManager")

-- ───────────────────────────────────────────────────────────
-- CLASS, WEAPON, COSMETIC
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "ClassManager")
ctx.Load(SharedModules, "WeaponManager")
ctx.Load(SharedModules, "ArmorManager")
ctx.Load(SharedModules, "VisualEquipmentManager")

ctx.Load(SharedModules, "AnimationConfig")
ctx.Load(SharedModules, "CosmeticConfig")
ctx.Load(SharedModules, "CosmeticManager")

-- ───────────────────────────────────────────────────────────
-- ACHIEVEMENT, EQUIPMENT, INVENTORY
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "AchievementManager")
ctx.Load(SharedModules, "EquipmentHandler")
ctx.Load(SharedModules, "InventoryManager")

-- ───────────────────────────────────────────────────────────
-- DAILY LOGIN, SHOP, LEADERBOARD
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "DailyLoginManager")
ctx.Load(SharedModules, "ShopManager")
ctx.Load(SharedModules, "LeaderboardManager")

-- ───────────────────────────────────────────────────────────
-- RESOURCE (so HUD can show resource bar in lobby)
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "ResourceManager")

-- ───────────────────────────────────────────────────────────
-- MONITORING + SHARED HANDLERS + BONUS XP
-- ───────────────────────────────────────────────────────────
ctx.Load(SharedModules, "MonitoringSystem")
ctx.Load(SharedModules, "SharedEventHandlers")
ctx.Load(SharedModules, "BonusExpSystem")

-- ───────────────────────────────────────────────────────────
-- LOBBY-SPECIFIC MODULES
-- ───────────────────────────────────────────────────────────
ctx.Load(LobbyModules, "SceneManager")
ctx.Load(LobbyModules, "PartyManager")
ctx.Load(LobbyModules, "MatchmakingManager")
ctx.Load(LobbyModules, "TeleportManager")

-- NPCManager has injected deps; load manually so we can inject the
-- place-specific NPC registry + SceneManager + MatchmakingManager refs.
do
    local mod = SharedModules:FindFirstChild("NPCManager")
    if mod then
        local ok, npcMgr = pcall(require, mod)
        if ok then
            ctx.loaded["NPCManager"] = npcMgr

            local lobbyNpcs = {}
            local npcRegMod = LobbyModules:FindFirstChild("LobbyNPCRegistry")
            if npcRegMod then
                local rok, defs = pcall(require, npcRegMod)
                if rok then
                    lobbyNpcs = defs
                else
                    warn("[LobbyMain] Failed to load LobbyNPCRegistry: " .. tostring(defs))
                end
            else
                warn("[LobbyMain] LobbyNPCRegistry not found — no lobby NPCs will spawn")
            end

            npcMgr.Init({
                SceneManager       = ctx.loaded["SceneManager"],
                MatchmakingManager = ctx.loaded["MatchmakingManager"],
                npcs               = lobbyNpcs,
            })
        else
            warn("[LobbyMain] Failed to load NPCManager: " .. tostring(npcMgr))
        end
    else
        warn("[LobbyMain] Module not found: NPCManager")
    end
end

-- §AGX/SEC: §T0P2-ADMIN — admin panel backend is Studio-only.
if ctx.IsStudio then ctx.Load(SharedModules, "AdminTesting") end

-- ───────────────────────────────────────────────────────────
-- VALIDATE CRITICAL MODULES
-- ───────────────────────────────────────────────────────────
ctx.RequireLoaded("PlayerDataConfig")
ctx.RequireLoaded("PlayerDataManager")
ctx.RequireLoaded("NetworkManager")
ctx.RequireLoaded("ReadyGate")
ctx.RequireLoaded("StatsManager")
ctx.RequireLoaded("CurrencyManager")
ctx.RequireLoaded("SharedEventHandlers")
ctx.RequireLoaded("PartyManager")
ctx.RequireLoaded("MatchmakingManager")
ctx.RequireLoaded("TeleportManager")
ctx.RequireLoaded("SceneManager")

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

-- Lobby-specific request: send party state on demand.
NetworkManager.OnClientEvent("GetPartyState", function(player)
    local pm = ctx.loaded["PartyManager"]
    if pm and pm.SendPartyState then
        pm.SendPartyState(player)
    end
end)

-- ───────────────────────────────────────────────────────────
-- ADMIN DEBUG COMMANDS (lobby has only addXP for now)
-- ───────────────────────────────────────────────────────────
-- §AGX/SEC: §T0P2-ADMIN — the DebugCommand remote exists only in Studio
-- (NetworkManager studioOnly); outside Studio nothing is wired here.
if ctx.IsStudio then
    NetworkManager.OnClientEvent("DebugCommand", function(player, command, ...)
        if not IsAdmin(player) then
            warn("[Security] DebugCommand blocked for " .. player.Name)
            return
        end
        local args = {...}
        if command == "addXP" then
            local amount = tonumber(args[1]) or 100  -- §AGX/SEC: type-check client arg
            DataManager.AddExperience(player, amount)
        end
    end)
end

-- ───────────────────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ───────────────────────────────────────────────────────────
-- §T0-FOLLOWUP/L4: PlayerDataManager.Init already binds RemovePlayer to
-- PlayerRemoving. A second binding here used to fire after the first
-- cleared playerDataStore[player], which surfaced as a noisy
-- "in-memory data is nil" warn on every disconnect.
Lifecycle.WireOnPlayerReady(ctx)

print(string.format("[Lobby] Place ready — %d modules loaded", (function()
    local n = 0
    for _ in pairs(ctx.loaded) do n = n + 1 end
    return n
end)()))
