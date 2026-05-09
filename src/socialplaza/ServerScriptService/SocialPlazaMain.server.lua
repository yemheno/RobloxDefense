-- socialplaza/ServerScriptService/SocialPlazaMain.server.lua
--[[
    Social Plaza place bootstrap.

    Loads only the systems relevant to appearance and social features:
      • Shared core  (player data, character, network)
      • Cosmetic & animation config / manager
      • Currency     (for wardrobe purchases and shop)
      • NO combat, NO enemy AI, NO wave/defense systems.

    This place is the dedicated development environment for:
      • Costume and outfit system  (CosmeticManager / PlayerCosmeticManager)
      • Animation and emote system (AnimationSystem / AnimationConfig)
      • Character appearance       (CharacterCreation / CharacterManager)
      • Social features            (emote wheel, avatar preview, future parades)
]]

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

local SharedModules = SSS:WaitForChild("Modules")

-- ───────────────────────────────────────────────────────────
-- ADMIN GUARD
-- ───────────────────────────────────────────────────────────
local _AdminCfg = require(SharedModules:WaitForChild("PlayerDataConfig"))
local function IsAdmin(player)
	if player.UserId == game.CreatorId then return true end
	return _AdminCfg.AdminUserIds and _AdminCfg.AdminUserIds[player.UserId] == true
end

-- ───────────────────────────────────────────────────────────
-- MODULE LOADER HELPER
-- ───────────────────────────────────────────────────────────
local loaded = {}

local function Load(parent, name)
	local mod = parent:FindFirstChild(name)
	if not mod then
		warn("[SocialPlazaMain] Module not found:", name)
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[SocialPlazaMain] Failed to load", name, ":", result)
		return nil
	end
	loaded[name] = result
	if type(result.Init) == "function" then
		result.Init()
	end
	return result
end

-- Plaza-specific modules in SSS.SocialPlaza.Modules
local SocialPlaza  = SSS:WaitForChild("SocialPlaza")
local PlazaModules = SocialPlaza:WaitForChild("Modules")

-- ───────────────────────────────────────────────────────────
-- CONFIG  (pure data, no Init)
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "PlayerDataConfig")
Load(SharedModules, "CharacterConfig")
Load(SharedModules, "CosmeticConfig")
Load(SharedModules, "AnimationConfig")

-- ───────────────────────────────────────────────────────────
-- NETWORK
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "NetworkManager")

-- ───────────────────────────────────────────────────────────
-- PLAYER DATA & CHARACTER
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "PlayerDataManager")
Load(SharedModules, "CharacterManager")

-- ───────────────────────────────────────────────────────────
-- ECONOMY  (wardrobe purchases reference currency balance)
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "StatsManager")
Load(SharedModules, "CurrencyManager")

-- ───────────────────────────────────────────────────────────
-- APPEARANCE SYSTEMS
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "CosmeticManager")        -- wardrobe equip/unequip, visual application

-- ───────────────────────────────────────────────────────────
-- SHOP  (buy cosmetics directly in the plaza)
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "ShopManager")

-- ───────────────────────────────────────────────────────────
-- DAILY LOGIN  (run here so players earn rewards on arrival)
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "DailyLoginManager")

-- ───────────────────────────────────────────────────────────
-- MONITORING  (error telemetry; lightweight in dev)
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "MonitoringSystem")



-- ───────────────────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ───────────────────────────────────────────────────────────
local function onPlayerAdded(player)
	-- PlayerDataManager initialises data; CosmeticManager handles wardrobe;
	-- CharacterManager applies the correct R6 appearance on character spawn.
	-- No additional wiring needed at the plaza level for now.
end

local function onPlayerRemoving(player)
	-- PlayerDataManager handles auto-save on remove.
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Handle players who joined before this script ran
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- Signal clients that server initialisation is complete
local NetworkManager = loaded["NetworkManager"]
if NetworkManager then
	NetworkManager.FireAllClients("ServerReady")
end
