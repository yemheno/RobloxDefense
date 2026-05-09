-- ServerScriptService/Modules/SceneManager
--[[
    Manages which "scene" each player is in within the single place.
    
    Scenes:
      Village   — The hub / lobby. Free camera, no combat, NPCs.
      Defense   — The defense game mode. Fixed camera, combat on.
      (future)  — Arena, Raid, Exploration, etc.
    
    Transitioning a player between scenes:
      1. Move their character to the scene's spawn point.
      2. Notify the client to swap camera mode + enable/disable systems.
      3. Update server-side tracking so other modules can query scene.
    
    All players start in Village.
]]

local SceneManager = {}

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

local SharedModules = SSS:WaitForChild("Modules")
local NetworkManager  = nil  -- lazy
local GameModeConfig  = nil  -- lazy

-- ── Per-player scene tracking ─────────────────────────────
local playerScene = {}   -- [player] = sceneName (string)

-- ── Callbacks ─────────────────────────────────────────────
local sceneChangedCallbacks = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function SceneManager.Init()
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
	GameModeConfig = require(SharedModules:WaitForChild("GameModeConfig"))

	-- Network events
	NetworkManager.GetEvent("SceneChanged")       -- server → client
	NetworkManager.GetEvent("RequestSceneInfo")    -- client → server (initial query)

	NetworkManager.OnClientEvent("RequestSceneInfo", function(player)
		SceneManager.SendSceneInfo(player)
	end)

	-- Player lifecycle
	Players.PlayerAdded:Connect(function(player)
		SceneManager.SetupPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		playerScene[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		SceneManager.SetupPlayer(player)
	end

	print("[SceneManager] Initialized — default scene: Village")
end

function SceneManager.SetupPlayer(player)
	-- Everyone starts in the village
	playerScene[player] = "Village"

	-- Wait for character, then move to village spawn
	if player.Character then
		SceneManager.MoveToSpawn(player, "Village")
	end
	player.CharacterAdded:Connect(function()
		task.wait(0.2) -- let character load
		local scene = playerScene[player] or "Village"
		SceneManager.MoveToSpawn(player, scene)
	end)
end

-- ═══════════════════════════════════════════════════════════
-- SCENE QUERIES
-- ═══════════════════════════════════════════════════════════

function SceneManager.GetScene(player)
	return playerScene[player] or "Village"
end

function SceneManager.IsInVillage(player)
	return SceneManager.GetScene(player) == "Village"
end

function SceneManager.IsInGameMode(player)
	return SceneManager.GetScene(player) ~= "Village"
end

function SceneManager.GetPlayersInScene(sceneName)
	local list = {}
	for player, scene in pairs(playerScene) do
		if scene == sceneName then
			table.insert(list, player)
		end
	end
	return list
end

-- ═══════════════════════════════════════════════════════════
-- SCENE TRANSITIONS
-- ═══════════════════════════════════════════════════════════

--- Transition a list of players to a game mode scene.
function SceneManager.TransitionToMode(players, modeId)
	local mode = GameModeConfig.GetMode(modeId)
	if not mode then
		warn("[SceneManager] Unknown mode:", modeId)
		return false
	end

	for _, player in ipairs(players) do
		SceneManager.SetScene(player, mode.sceneName, mode.features)
		SceneManager.MoveToSpawn(player, mode.sceneName)
	end

	print("[SceneManager] Transitioned", #players, "players to", mode.sceneName)
	return true
end

--- Return a list of players to the village.
function SceneManager.ReturnToVillage(players)
	local features = GameModeConfig.Village.features

	for _, player in ipairs(players) do
		SceneManager.SetScene(player, "Village", features)
		SceneManager.MoveToSpawn(player, "Village")
	end

	print("[SceneManager] Returned", #players, "players to Village")
end

--- Internal: set scene and notify client + callbacks.
function SceneManager.SetScene(player, sceneName, features)
	local oldScene = playerScene[player]
	playerScene[player] = sceneName

	-- Determine features if not provided
	if not features then
		if sceneName == "Village" then
			features = GameModeConfig.Village.features
		else
			local mode = GameModeConfig.GetMode(sceneName)
			features = mode and mode.features or {}
		end
	end

	-- Notify client
	NetworkManager.FireClient(player, "SceneChanged", {
		scene    = sceneName,
		features = features,
	})

	-- Fire server-side callbacks
	for _, cb in ipairs(sceneChangedCallbacks) do
		task.spawn(cb, player, sceneName, oldScene)
	end
end

-- ═══════════════════════════════════════════════════════════
-- SPAWN MANAGEMENT
-- ═══════════════════════════════════════════════════════════

--- Move the player's character to the named spawn point.
--- Looks for a Part/SpawnLocation named after the scene under workspace.Spawns.
function SceneManager.MoveToSpawn(player, sceneName)
	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local spawnName
	if sceneName == "Village" then
		spawnName = GameModeConfig.Village.spawnPoint
	else
		local mode = GameModeConfig.GetMode(sceneName)
		spawnName = mode and mode.spawnPoint or (sceneName .. "Spawn")
	end

	-- Look for the spawn in workspace
	local spawnsFolder = workspace:FindFirstChild("Spawns")
	local spawnPart = spawnsFolder and spawnsFolder:FindFirstChild(spawnName)

	if spawnPart then
		rootPart.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
	else
		-- Fallback: just don't move; the spawn may not exist in Studio yet
		warn("[SceneManager] Spawn point not found:", spawnName, "- player stays in place")
	end
end

-- ═══════════════════════════════════════════════════════════
-- INFO
-- ═══════════════════════════════════════════════════════════

function SceneManager.SendSceneInfo(player)
	local sceneName = playerScene[player] or "Village"
	local features
	if sceneName == "Village" then
		features = GameModeConfig.Village.features
	else
		local mode = GameModeConfig.GetMode(sceneName)
		features = mode and mode.features or {}
	end

	NetworkManager.FireClient(player, "SceneChanged", {
		scene    = sceneName,
		features = features,
	})
end

-- ═══════════════════════════════════════════════════════════
-- CALLBACKS
-- ═══════════════════════════════════════════════════════════

function SceneManager.OnSceneChanged(callback)
	table.insert(sceneChangedCallbacks, callback)
end

return SceneManager
