-- centralboss/StarterPlayerScripts/CentralBossClient.client.lua
--[[
    CentralBoss client bootstrap.
    Loads shared client modules + combat-specific modules (identical set to
    LaneDefense), then configures camera and movement for a boss encounter:

      Camera  : FixedIsometric  — standard isometric offset following the player.
      Movement: FacePoint        — character always rotates to face the BossPoint,
                                  jump disabled.

    Everything else (combat, skills, cosmetics, etc.) is identical to LaneDefense.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local SharedModules = PlayerScripts:WaitForChild("Modules")

-- §PERF/BP: client boot timeline (see BootProfiler for the dump contract)
local BootProfiler = require(game:GetService("ReplicatedStorage")
	:WaitForChild("Shared"):WaitForChild("BootProfiler"))
BootProfiler.SetContext("CentralBossClient")

-- ───────────────────────────────────────────────────────────
-- MODULE LOADER
-- ───────────────────────────────────────────────────────────
local loadedModules = {}

local function Load(parent, name)
	local mod = parent:FindFirstChild(name)
	if not mod then
		warn("[CentralBossClient] Module not found:", name)
		return nil
	end
	local doneRequire = BootProfiler.Begin("require " .. name)
	local ok, result = pcall(require, mod)
	doneRequire()
	if not ok then
		warn("[CentralBossClient] Failed to load", name, ":", result)
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
Load(SharedModules, "LoadingScreen")    -- §T10/U1: overlay up FIRST, dismissed on ServerReady
Load(SharedModules, "NetworkManager")
Load(SharedModules, "ResourceCache")    -- early listener
Load(SharedModules, "AnimationSystem")
Load(SharedModules, "CosmeticClient")
Load(SharedModules, "AchievementClient")
Load(SharedModules, "InputSystem")
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
-- CONFIGURE INPUT, CAMERA & MOVEMENT FOR CENTRAL BOSS
-- ───────────────────────────────────────────────────────────
local InputSystem    = loadedModules["InputSystem"]
local CameraSystem   = loadedModules["CameraSystem"]
local MovementSystem = loadedModules["MovementSystem"]

-- Boss mode is always in combat context
if InputSystem then
	InputSystem.SetContext("Combat")
end

-- FixedBossView: 3rd-person camera that follows the player and rotates with them.
-- Camera stays behind the player as they turn (true 3rd-person behavior).
if CameraSystem then
	CameraSystem.SetMode("FixedBossView", {
		offset = Vector3.new(0, 8, 12),
	})
end

-- NoJump + FacePoint: players cannot jump and always face the boss
if MovementSystem then
	MovementSystem.Enable("NoJump")
	MovementSystem.Enable("FacePoint", {
		-- bossPoint can be omitted; FacePoint auto-reads workspace.BossPoint
	})
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
