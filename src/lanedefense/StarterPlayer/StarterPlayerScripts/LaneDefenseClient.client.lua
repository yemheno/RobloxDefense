-- lanedefense/StarterPlayerScripts/LaneDefenseClient.client.lua
--[[
    LaneDefense client bootstrap.
    Loads shared client modules + combat-specific modules.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local SharedModules = PlayerScripts:WaitForChild("Modules")

-- §PERF/BP: client boot timeline (see BootProfiler for the dump contract)
local BootProfiler = require(game:GetService("ReplicatedStorage")
	:WaitForChild("Shared"):WaitForChild("BootProfiler"))
BootProfiler.SetContext("LaneDefenseClient")

-- ───────────────────────────────────────────────────────────
-- MODULE LOADER
-- ───────────────────────────────────────────────────────────
local loadedModules = {}

local function Load(parent, name)
	local mod = parent:FindFirstChild(name)
	if not mod then
		warn("[LaneDefenseClient] Module not found:", name)
		return nil
	end
	local doneRequire = BootProfiler.Begin("require " .. name)
	local ok, result = pcall(require, mod)
	doneRequire()
	if not ok then
		warn("[LaneDefenseClient] Failed to load", name, ":", result)
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
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "LoadingScreen")   -- §T10/U1: overlay up FIRST, dismissed on ServerReady
Load(SharedModules, "NetworkManager")
Load(SharedModules, "ResourceCache")   -- early listener prevents ResourceUpdate queue exhaustion
Load(SharedModules, "AnimationSystem")  -- centralized animation controller (BEFORE PlayerAttack)
Load(SharedModules, "CosmeticClient")   -- cosmetic cache + wardrobe requests
Load(SharedModules, "AchievementClient") -- achievement cache + toast events
Load(SharedModules, "InputSystem")      -- centralized input dispatcher (BEFORE combat modules)
Load(SharedModules, "CameraSystem")
Load(SharedModules, "MovementSystem")
Load(SharedModules, "PlayerAttack")
Load(SharedModules, "SkillInput")
Load(SharedModules, "SkillVisuals")
Load(SharedModules, "MobVisuals")
Load(SharedModules, "DamageNumbers")
Load(SharedModules, "LootNotification")
Load(SharedModules, "TalentClient")
Load(SharedModules, "Locale")
Load(SharedModules, "SoundManager")

-- ───────────────────────────────────────────────────────────
-- CONFIGURE INPUT, CAMERA & MOVEMENT FOR LANE DEFENSE
-- ───────────────────────────────────────────────────────────────
local InputSystem    = loadedModules["InputSystem"]
local CameraSystem   = loadedModules["CameraSystem"]
local MovementSystem = loadedModules["MovementSystem"]

-- Lane defense is always in combat context
if InputSystem then
	InputSystem.SetContext("Combat")
end

if CameraSystem then
	CameraSystem.SetMode("FixedIsometric", {
		offset    = Vector3.new(-12, 8, 0),
		lookAhead = 20,
	})
end

if MovementSystem then
	MovementSystem.Enable("NoJump")
	MovementSystem.Enable("FaceDirection", { direction = Vector3.new(1, 0, 0) })
end

-- Listen for server ready
-- §T0P2/X25: intentionally empty — reserved loading-screen hook.
-- ServerReady is ReadyGate-routed (§T0P2/X9).
local NetworkManager = loadedModules["NetworkManager"]
if NetworkManager then
	NetworkManager.OnServerEvent("ServerReady", function()
		BootProfiler.Mark("ServerReady received")  -- §PERF/BP
		-- §T10/U1: dismiss the loading screen.
		local ls = loadedModules["LoadingScreen"]
		if ls then ls.Dismiss() end
		BootProfiler.Mark("LoadingScreen dismissed")
	end)
end
