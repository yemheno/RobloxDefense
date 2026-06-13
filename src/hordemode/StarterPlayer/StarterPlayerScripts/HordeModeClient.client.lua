-- hordemode/StarterPlayerScripts/HordeModeClient.client.lua
--[[
    HordeMode client bootstrap.
    Loads shared client modules + combat-specific modules (identical set to
    CentralBoss), then configures camera and movement for a horde encounter:

      Camera  : TopDown          — top-down view following the player from above.
                                   Configurable offset (default: RBXMX arcade style).
      Movement: FaceMouse (PC)   — character rotates to face mouse cursor.
                JoystickAim (mobile) — virtual joystick for aiming on touch devices.
                NoJump           — jumping disabled.

    Everything else (combat, skills, cosmetics, etc.) is identical to CentralBoss.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local SharedModules = PlayerScripts:WaitForChild("Modules")

-- ───────────────────────────────────────────────────────────
-- MODULE LOADER
-- ───────────────────────────────────────────────────────────
local loadedModules = {}

local function Load(parent, name)
	local mod = parent:FindFirstChild(name)
	if not mod then
		warn("[HordeModeClient] Module not found:", name)
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[HordeModeClient] Failed to load", name, ":", result)
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
-- ───────────────────────────────────────────────────────────
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
-- CONFIGURE INPUT, CAMERA & MOVEMENT FOR HORDE MODE
-- ───────────────────────────────────────────────────────────
local InputSystem    = loadedModules["InputSystem"]
local CameraSystem   = loadedModules["CameraSystem"]
local MovementSystem = loadedModules["MovementSystem"]

-- Horde mode is always in combat context
if InputSystem then
	InputSystem.SetContext("Combat")
end

-- TopDown camera: arcade-style overhead view
-- Defaults match the RBXMX reference (offset 20,40,0 with +5X shift)
if CameraSystem then
	CameraSystem.SetMode("TopDown", {
		heightOffset = 35,
		sideOffset   = Vector3.new(0, 0, 0),
		cameraShift  = Vector3.new(20, 0, 0),
		fov          = 45,
	})
end

-- NoJump + FaceMouse (PC) / JoystickAim (mobile)
if MovementSystem then
	MovementSystem.Enable("NoJump")
	MovementSystem.Enable("FaceMouse")     -- no-op on mobile
	MovementSystem.Enable("JoystickAim")   -- no-op on PC
end

-- Listen for server ready
-- §T0P2/X25: intentionally empty — reserved loading-screen hook.
-- ServerReady is ReadyGate-routed (§T0P2/X9).
local NetworkManager = loadedModules["NetworkManager"]
if NetworkManager then
	NetworkManager.OnServerEvent("ServerReady", function()
	end)

	-- ── Pause/resume ──────────────────────────────────────────
	-- When the server fires HordePaused(true), block all combat input
	-- and freeze the local character.  HordePaused(false) restores both.
	local savedWalkSpeed = nil
	NetworkManager.OnServerEvent("HordePaused", function(isPaused)
		local localPlayer = game.Players.LocalPlayer

		if isPaused then
			-- Block attacks / skills by switching away from Combat context
			if InputSystem then
				InputSystem.SetContext("UI")
			end
			-- Freeze character movement (re-resolve humanoid each time
			-- in case the character respawned since the last call)
			local char = localPlayer.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				-- Guard against saving 0: a lockMovement skill cast may have already
				-- set WalkSpeed to 0 on the server; saving 0 is falsy and would
				-- skip the restore block, leaving the player permanently frozen.
				savedWalkSpeed = humanoid.WalkSpeed > 0 and humanoid.WalkSpeed or 16
				humanoid.WalkSpeed = 0
			end
		else
			-- Restore combat input
			if InputSystem then
				InputSystem.SetContext("Combat")
			end
			-- Restore movement speed (re-resolve humanoid for same reason)
			local char = localPlayer.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid and savedWalkSpeed then
				humanoid.WalkSpeed = savedWalkSpeed
				savedWalkSpeed = nil
			end
		end
	end)
end
