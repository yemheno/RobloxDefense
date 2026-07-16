-- StarterPlayerScripts/Modules/SceneController
--[[
    Client-side scene management.
    
    Listens for "SceneChanged" from the server and toggles:
      • Camera mode (free in Village, fixed in Defense)
      • Skill input (disabled in Village)
      • Attack input (disabled in Village)
      • NPC interaction prompts (enabled in Village)
    
    Other client modules can query SceneController to check the current scene.
]]

local SceneController = {}

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")

local player = Players.LocalPlayer

local SharedModules    = player:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local NetworkManager   = nil  -- lazy
local CameraSystem     = nil  -- lazy
local InputSystem      = nil  -- lazy

-- ── State ─────────────────────────────────────────────────
local currentScene    = "Village"
local currentFeatures = {
	fixedCamera   = false,
	skillsEnabled = false,
	attackEnabled = false,
	pvpEnabled    = false,
}

-- Callbacks for other modules to react to scene changes
local sceneChangedCallbacks = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function SceneController.Init()
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

	-- Grab the centralized input system so we can switch contexts
	local inputMod = SharedModules:FindFirstChild("InputSystem")
	if inputMod then
		InputSystem = require(inputMod)
	end

	-- Init CameraSystem eagerly so modes are registered before any scene event fires
	local camModule = SharedModules:FindFirstChild("CameraSystem")
	if camModule then
		CameraSystem = require(camModule)
		CameraSystem.Init()
	end

	-- Listen for scene changes from server
	NetworkManager.OnServerEvent("SceneChanged", function(data)
		SceneController.OnSceneChanged(data)
	end)

	-- Request current scene info from server
	NetworkManager.FireServer("RequestSceneInfo")

end

-- ═══════════════════════════════════════════════════════════
-- SCENE CHANGE HANDLER
-- ═══════════════════════════════════════════════════════════

function SceneController.OnSceneChanged(data)
	local oldScene = currentScene
	currentScene = data.scene or "Village"
	currentFeatures = data.features or {}

	print("[SceneController] Scene changed:", oldScene, "→", currentScene)

	-- Apply features
	SceneController.ApplyFeatures()

	-- Fire callbacks
	for _, cb in ipairs(sceneChangedCallbacks) do
		task.spawn(cb, currentScene, oldScene, currentFeatures)
	end
end

function SceneController.ApplyFeatures()
	-- Input context — Combat when combat features active, Lobby otherwise
	if InputSystem then
		if currentFeatures.skillsEnabled or currentFeatures.attackEnabled then
			InputSystem.SetContext("Combat")
		else
			InputSystem.SetContext("Lobby")
		end
	end

	-- Camera mode
	if CameraSystem then
		if currentFeatures.fixedCamera then
			CameraSystem.SetMode("FixedIsometric")
		else
			CameraSystem.SetMode("Free")
		end
	end

	-- Player attributes so other local scripts can query
	player:SetAttribute("SkillsEnabled", currentFeatures.skillsEnabled ~= false)
	player:SetAttribute("AttackEnabled", currentFeatures.attackEnabled ~= false)
	player:SetAttribute("CurrentScene", currentScene)
end

-- ═══════════════════════════════════════════════════════════
-- QUERIES
-- ═══════════════════════════════════════════════════════════

function SceneController.GetScene()
	return currentScene
end

function SceneController.GetFeatures()
	return currentFeatures
end

function SceneController.IsInVillage()
	return currentScene == "Village"
end

function SceneController.IsInGameMode()
	return currentScene ~= "Village"
end

function SceneController.AreSkillsEnabled()
	return currentFeatures.skillsEnabled == true
end

function SceneController.IsAttackEnabled()
	return currentFeatures.attackEnabled == true
end

-- ═══════════════════════════════════════════════════════════
-- CALLBACKS
-- ═══════════════════════════════════════════════════════════

function SceneController.OnSceneChangedCallback(callback)
	table.insert(sceneChangedCallbacks, callback)
	-- §MEM/M10: return an unsubscribe (like ResourceCache.Subscribe) so a
	-- React useEffect can clean up — without it every remount would leak
	-- one callback forever. No callers yet; closing the trap early.
	return function()
		local idx = table.find(sceneChangedCallbacks, callback)
		if idx then table.remove(sceneChangedCallbacks, idx) end
	end
end

return SceneController
