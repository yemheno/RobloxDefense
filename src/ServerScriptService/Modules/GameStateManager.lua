-- ServerScriptService/Modules/GameStateManager

local GameStateManager = {}

local Players = game:GetService("Players")

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- ═══════════════════════════════════════════════════════════
-- GAME STATES
-- ═══════════════════════════════════════════════════════════
--[[
    "Lobby"      - In NPC village, waiting for players
    "Preparing"  - Countdown before wave starts (optional)
    "Defending"  - Waves are active
    "Victory"    - All waves completed
    "Defeat"     - Defense line destroyed / all players dead
]]

local STATES = {
	LOBBY = "Lobby",
	PREPARING = "Preparing",
	DEFENDING = "Defending",
	VICTORY = "Victory",
	DEFEAT = "Defeat",
}

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

local CONFIG = {
	PrepareTime = 3,              -- Seconds of countdown before waves start
	EnablePrepareCountdown = true, -- Set false to skip countdown
	MinPlayersToStart = 1,        -- Minimum players to allow start
	ReturnToLobbyDelay = 10,      -- Seconds before returning to lobby after victory/defeat
}

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local currentState = STATES.LOBBY
local stateStartTime = 0
local MobSpawner = nil  -- Lazy loaded

-- Server-side callbacks
local stateChangedCallbacks = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function GameStateManager.Init()
	-- Create network events
	NetworkManager.GetEvent("GameStateChanged")
	NetworkManager.GetEvent("RequestStartGame")
	NetworkManager.GetEvent("CountdownUpdate")

	-- Listen for start requests from clients
	NetworkManager.OnClientEvent("RequestStartGame", function(player)
		GameStateManager.RequestStart(player)
	end)

	print("[GameStateManager] Initialized - State:", currentState)
end

-- Late init (called after MobSpawner is loaded)
function GameStateManager.LateInit()
	MobSpawner = require(Modules:WaitForChild("MobSpawner"))

	-- Disable MobSpawner auto-advance (we control it now)
	MobSpawner.SetAutoAdvance(true)  -- Still auto-advance between waves

	-- Listen for wave completion
	MobSpawner.OnAllWavesCompleted(function(finalWave)
		GameStateManager.SetState(STATES.VICTORY)
	end)

	print("[GameStateManager] Late init complete - MobSpawner connected")
end

-- ═══════════════════════════════════════════════════════════
-- STATE MANAGEMENT
-- ═══════════════════════════════════════════════════════════

function GameStateManager.GetState()
	return currentState
end

function GameStateManager.GetStates()
	return STATES
end

function GameStateManager.SetState(newState)
	if currentState == newState then return end

	local oldState = currentState
	currentState = newState
	stateStartTime = tick()

	print("[GameStateManager] ═══════════════════════════════════")
	print("[GameStateManager] State changed:", oldState, "→", newState)
	print("[GameStateManager] ═══════════════════════════════════")

	-- Notify all clients
	NetworkManager.FireAllClients("GameStateChanged", {
		oldState = oldState,
		newState = newState,
		timestamp = stateStartTime,
	})

	-- Fire server callbacks
	for _, callback in ipairs(stateChangedCallbacks) do
		task.spawn(callback, newState, oldState)
	end

	-- Handle state-specific logic
	GameStateManager.OnStateEnter(newState, oldState)
end

function GameStateManager.OnStateEnter(newState, oldState)
	if newState == STATES.PREPARING then
		-- Start countdown
		if CONFIG.EnablePrepareCountdown then
			GameStateManager.StartCountdown()
		else
			-- Skip directly to defending
			GameStateManager.SetState(STATES.DEFENDING)
		end

	elseif newState == STATES.DEFENDING then
		-- Start first wave
		if MobSpawner then
			MobSpawner.StartWave(1)
		end

	elseif newState == STATES.VICTORY then
		print("[GameStateManager] 🎉 VICTORY! All waves completed!")
		-- Optional: Return to lobby after delay
		if CONFIG.ReturnToLobbyDelay > 0 then
			task.delay(CONFIG.ReturnToLobbyDelay, function()
				if currentState == STATES.VICTORY then
					GameStateManager.ReturnToLobby()
				end
			end)
		end

	elseif newState == STATES.DEFEAT then
		print("[GameStateManager] 💀 DEFEAT!")
		-- Optional: Return to lobby after delay
		if CONFIG.ReturnToLobbyDelay > 0 then
			task.delay(CONFIG.ReturnToLobbyDelay, function()
				if currentState == STATES.DEFEAT then
					GameStateManager.ReturnToLobby()
				end
			end)
		end

	elseif newState == STATES.LOBBY then
		-- Reset everything for next game
		GameStateManager.ResetGame()
	end
end

-- ═══════════════════════════════════════════════════════════
-- GAME FLOW
-- ═══════════════════════════════════════════════════════════

function GameStateManager.RequestStart(player)
	-- Validate state
	if currentState ~= STATES.LOBBY then
		warn("[GameStateManager] Cannot start - not in Lobby state (current:", currentState .. ")")
		return false, "Game already in progress"
	end

	-- Validate player count
	local playerCount = #Players:GetPlayers()
	if playerCount < CONFIG.MinPlayersToStart then
		warn("[GameStateManager] Cannot start - not enough players:", playerCount, "/", CONFIG.MinPlayersToStart)
		return false, "Not enough players"
	end

	print("[GameStateManager]", player.Name, "started the game!")

	-- Transition to preparing (or defending if countdown disabled)
	GameStateManager.SetState(STATES.PREPARING)

	return true
end

function GameStateManager.StartCountdown()
	task.spawn(function()
		local remaining = CONFIG.PrepareTime

		while remaining > 0 and currentState == STATES.PREPARING do
			-- Notify clients of countdown
			NetworkManager.FireAllClients("CountdownUpdate", {
				remaining = remaining,
				total = CONFIG.PrepareTime,
			})

			print("[GameStateManager] Starting in", remaining, "...")

			task.wait(1)
			remaining = remaining - 1
		end

		-- Only transition if still in PREPARING state
		if currentState == STATES.PREPARING then
			NetworkManager.FireAllClients("CountdownUpdate", {
				remaining = 0,
				total = CONFIG.PrepareTime,
			})

			GameStateManager.SetState(STATES.DEFENDING)
		end
	end)
end

function GameStateManager.ReturnToLobby()
	print("[GameStateManager] Returning to lobby...")
	GameStateManager.SetState(STATES.LOBBY)
end

-- Add to GameStateManager.ResetGame()

function GameStateManager.ResetGame()
	-- Reset MobSpawner
	if MobSpawner and MobSpawner.Reset then
		MobSpawner.Reset()
	end

	-- Reset DefenseLine
	local DefenseLine = Modules:FindFirstChild("DefenseLine")
	if DefenseLine then
		local dl = require(DefenseLine)
		if dl.Reset then
			dl.Reset()
		end
	end

	-- Reset HitTracker sessions
	local HitTracker = Modules:FindFirstChild("HitTracker")
	if HitTracker then
		local ht = require(HitTracker)
		if ht.ResetAllSessions then
			ht.ResetAllSessions()
		end
	end

	-- Heal all players
	for _, player in ipairs(Players:GetPlayers()) do
		local DataManager = require(Modules:WaitForChild("PlayerDataManager"))
		DataManager.ResetHealth(player)
	end

	print("[GameStateManager] Game reset complete")
end

function GameStateManager.TriggerDefeat()
	if currentState == STATES.DEFENDING then
		GameStateManager.SetState(STATES.DEFEAT)
	end
end

-- ═══════════════════════════════════════════════════════════
-- CALLBACKS
-- ═══════════════════════════════════════════════════════════

function GameStateManager.OnStateChanged(callback)
	table.insert(stateChangedCallbacks, callback)
end

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

function GameStateManager.SetPrepareTime(seconds)
	CONFIG.PrepareTime = seconds
end

function GameStateManager.SetMinPlayers(count)
	CONFIG.MinPlayersToStart = count
end

function GameStateManager.SetEnableCountdown(enabled)
	CONFIG.EnablePrepareCountdown = enabled
end

function GameStateManager.GetConfig()
	return CONFIG
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function GameStateManager.IsInGame()
	return currentState == STATES.PREPARING or currentState == STATES.DEFENDING
end

function GameStateManager.IsInLobby()
	return currentState == STATES.LOBBY
end

function GameStateManager.IsDefending()
	return currentState == STATES.DEFENDING
end

function GameStateManager.GetTimeSinceStateChange()
	return tick() - stateStartTime
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function GameStateManager.GetDebugInfo()
	return {
		state = currentState,
		timeSinceChange = GameStateManager.GetTimeSinceStateChange(),
		playerCount = #Players:GetPlayers(),
		minPlayers = CONFIG.MinPlayersToStart,
		prepareTime = CONFIG.PrepareTime,
	}
end

return GameStateManager