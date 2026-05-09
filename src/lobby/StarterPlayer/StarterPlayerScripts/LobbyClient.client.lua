-- lobby/StarterPlayerScripts/LobbyClient.client.lua
--[[
    Lobby client bootstrap.
    Loads shared client modules + lobby-specific modules.
    Combat modules (SkillInput, PlayerAttack, DamageNumbers, etc.)
    are loaded but will self-gate via player attributes.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local SharedModules = PlayerScripts:WaitForChild("Modules")
local LobbyModules  = PlayerScripts:WaitForChild("Lobby"):WaitForChild("Modules")

-- ───────────────────────────────────────────────────────────
-- MODULE LOADER
-- ───────────────────────────────────────────────────────────
local loadedModules = {}

local function Load(parent, name)
	local mod = parent:FindFirstChild(name)
	if not mod then
		warn("[LobbyClient] Module not found:", name)
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[LobbyClient] Failed to load", name, ":", result)
		return nil
	end
	loadedModules[name] = result
	if type(result.Init) == "function" then
		result.Init()
	end
	return result
end

-- ───────────────────────────────────────────────────────────
-- SHARED CLIENT MODULES
-- Lobby uses default Roblox camera and movement — CameraSystem
-- and MovementSystem are available but not configured here.
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "NetworkManager")
Load(SharedModules, "ResourceCache")   -- early listener prevents ResourceUpdate queue exhaustion
Load(SharedModules, "AnimationSystem")  -- centralized animation controller
Load(SharedModules, "CosmeticClient")   -- cosmetic cache + wardrobe requests
Load(SharedModules, "AchievementClient") -- achievement cache + toast events
Load(SharedModules, "InputSystem")      -- centralized input dispatcher (BEFORE lobby modules)
Load(SharedModules, "TalentClient")
Load(SharedModules, "Locale")
Load(SharedModules, "SoundManager")

-- ───────────────────────────────────────────────────────────
-- LOBBY CLIENT MODULES
-- ───────────────────────────────────────────────────────────
Load(LobbyModules, "SceneController")
Load(LobbyModules, "NPCInteraction")

-- Listen for server ready
local NetworkManager = loadedModules["NetworkManager"]
if NetworkManager then
	NetworkManager.OnServerEvent("ServerReady", function()
	end)
end
