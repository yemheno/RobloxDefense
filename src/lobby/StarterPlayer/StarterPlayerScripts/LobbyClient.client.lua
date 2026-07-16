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

-- §PERF/BP: client boot timeline (see BootProfiler for the dump contract)
local BootProfiler = require(game:GetService("ReplicatedStorage")
	:WaitForChild("Shared"):WaitForChild("BootProfiler"))
BootProfiler.SetContext("LobbyClient")

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
	local doneRequire = BootProfiler.Begin("require " .. name)
	local ok, result = pcall(require, mod)
	doneRequire()
	if not ok then
		warn("[LobbyClient] Failed to load", name, ":", result)
		return nil
	end
	loadedModules[name] = result
	if type(result.Init) == "function" then
		local doneInit = BootProfiler.Begin(name .. ".Init")
		result.Init()
		doneInit()
	end
	return result
end

-- ───────────────────────────────────────────────────────────
-- SHARED CLIENT MODULES
-- Lobby uses default Roblox camera and movement — CameraSystem
-- and MovementSystem are available but not configured here.
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "LoadingScreen")   -- §T10/U1: overlay up FIRST, dismissed on ServerReady
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
-- §T10/U1: the loading-screen dismiss hook (the seam §T0P2/X25 reserved).
-- ServerReady is ReadyGate-routed (§T0P2/X9), so it reliably arrives
-- after this client's ClientReady handshake — i.e. after every queued
-- boot payload has been drained.
local NetworkManager = loadedModules["NetworkManager"]
if NetworkManager then
	NetworkManager.OnServerEvent("ServerReady", function()
		BootProfiler.Mark("ServerReady received")  -- §PERF/BP
		local ls = loadedModules["LoadingScreen"]
		if ls then ls.Dismiss() end
		BootProfiler.Mark("LoadingScreen dismissed")
	end)
end
