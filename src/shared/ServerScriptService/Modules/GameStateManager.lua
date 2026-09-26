-- ServerScriptService/Modules/GameStateManager

local GameStateManager = {}

local Players = game:GetService("Players")

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- ═══════════════════════════════════════════════════════════
-- GAME STATES  (canonical source: ReplicatedStorage.Shared.GameStates)
-- ═══════════════════════════════════════════════════════════
--[[
    "Idle"       - Pre-game waiting state (inside the defense place)
    "Preparing"  - Countdown before wave starts (optional)
    "Defending"  - Waves are active
    "Victory"    - All waves completed
    "Defeat"     - Defense line destroyed / all players dead

    NOTE: Using the shared table instead of a local copy so that server and
    client always compare against the same string constants. If you need to
    add a new state, add it to ReplicatedStorage/Shared/init.lua ONLY.
]]

local _RS = game:GetService("ReplicatedStorage")
local STATES = require(_RS:WaitForChild("Shared")).GameStates

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

local currentState = STATES.IDLE
local stateStartTime = 0
local MobSpawner = nil  -- Lazy loaded
local countdownThread = nil  -- Thread spawned by StartCountdown
-- §AGX/UX-02: flags the HUD can't rebuild from transitions alone; sent in
-- the RequestGameState snapshot so a (re)mounted HUD shows the right buttons.
local runEnded = false       -- true after Defeat/Victory until the next run starts
local betweenWaves = false   -- true after WaveCompleted until the next WaveStarted

-- When true, entering DEFENDING state will NOT call MobSpawner.StartWave(1).
-- Used by HordeMode which manages spawning via HordeModeSpawner.
GameStateManager.suppressWaveStart = false

-- Server-side callbacks
local stateChangedCallbacks = {}
local returnToLobbyCallbacks = {}

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

	-- §AGX/UX-02: per-player state snapshot. GameStateChanged is otherwise
	-- only broadcast on transitions, so a HUD mounted mid-run defaulted to
	-- "Idle" and offered Start Game. Same payload shape as a transition
	-- (oldState == newState), plus the optional run flags.
	NetworkManager.GetEvent("RequestGameState")
	NetworkManager.OnClientEvent("RequestGameState", function(player)
		-- nil when MobSpawner doesn't drive waves (e.g. HordeMode): the HUD
		-- then keeps whatever its own WaveStarted/WaveCompleted said.
		local waveFlag = nil
		if MobSpawner and not GameStateManager.suppressWaveStart then
			waveFlag = betweenWaves
		end
		NetworkManager.FireClient(player, "GameStateChanged", {
			oldState     = currentState,
			newState     = currentState,
			timestamp    = stateStartTime,
			runEnded     = runEnded,
			betweenWaves = waveFlag,
		})
	end)

end

-- Late init (called after MobSpawner is loaded)
function GameStateManager.LateInit()
	MobSpawner = require(Modules:WaitForChild("MobSpawner"))

	-- §AGX/UX-02: mirror the between-waves flag for RequestGameState.
	-- (Public MobSpawner callbacks only; MobSpawner itself is unchanged.)
	MobSpawner.OnWaveStarted(function() betweenWaves = false end)
	MobSpawner.OnWaveCompleted(function() betweenWaves = true end)

	-- Listen for wave completion
	MobSpawner.OnAllWavesCompleted(function(finalWave)
		-- §AGX/X5: via TriggerVictory so it only fires from DEFENDING
		-- (was SetState from any state).
		GameStateManager.TriggerVictory()
	end)

	print("[GameStateManager] Late init complete - MobSpawner connected")
end

-- ═══════════════════════════════════════════════════════════
-- STATE MANAGEMENT
-- ═══════════════════════════════════════════════════════════

function GameStateManager.GetState()
	return currentState
end

function GameStateManager.SetState(newState)
	if currentState == newState then return end

	local oldState = currentState
	currentState = newState
	stateStartTime = os.clock()

	-- §AGX/UX-02: same rules the HUD applies to transitions (§AGX/X14).
	if newState == STATES.DEFEAT or newState == STATES.VICTORY then
		runEnded = true
	elseif newState == STATES.PREPARING or newState == STATES.DEFENDING then
		runEnded = false
	end
	if newState ~= STATES.DEFENDING then
		betweenWaves = false
	end

	-- Cancel any pending countdown when state changes
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end

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
		-- Start first wave (unless suppressed, e.g. HordeMode manages its own spawner)
		if MobSpawner and not GameStateManager.suppressWaveStart then
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

	elseif newState == STATES.IDLE then
		-- Reset everything for next game
		GameStateManager.ResetGame()
	end
end

-- ═══════════════════════════════════════════════════════════
-- GAME FLOW
-- ═══════════════════════════════════════════════════════════

function GameStateManager.RequestStart(player)
	-- Validate state
	if currentState ~= STATES.IDLE then
		warn("[GameStateManager] Cannot start - not in Idle state (current:", currentState .. ")")
		-- §AGX/UI-P4 (§DISC/D8): tell the player, not just the server log.
		local ns = Modules:FindFirstChild("NotifyService")
		if ns and player then pcall(function() require(ns).Toast(player, "warning", "Game already in progress") end) end
		return false, "Game already in progress"
	end

	-- Validate player count
	local playerCount = #Players:GetPlayers()
	if playerCount < CONFIG.MinPlayersToStart then
		warn("[GameStateManager] Cannot start - not enough players:", playerCount, "/", CONFIG.MinPlayersToStart)
		local ns = Modules:FindFirstChild("NotifyService")
		if ns and player then pcall(function() require(ns).Toast(player, "warning", "Not enough players") end) end
		return false, "Not enough players"
	end

	print("[GameStateManager]", player.Name, "started the game!")

	-- Transition to preparing (or defending if countdown disabled)
	GameStateManager.SetState(STATES.PREPARING)

	return true
end

function GameStateManager.StartCountdown()
	-- Cancel any existing countdown thread
	if countdownThread then
		task.cancel(countdownThread)
	end

	-- Spawn new countdown thread and store reference
	countdownThread = task.spawn(function()
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

			-- Nil out BEFORE SetState so SetState doesn't try to cancel this thread
			countdownThread = nil
			GameStateManager.SetState(STATES.DEFENDING)
		else
			-- Clear thread reference when done without transitioning
			countdownThread = nil
		end
	end)
end

-- §G2 fix: idempotency guard. Both the auto-return delays (Victory and
-- Defeat) and any manual ReturnToLobby caller could otherwise queue
-- multiple teleport sweeps and double-reset the run state.
local _returnInFlight = false

function GameStateManager.ReturnToLobby()
	if _returnInFlight then
		warn("[GameStateManager] ReturnToLobby ignored — already in flight.")
		return
	end
	_returnInFlight = true

	print("[GameStateManager] Returning to lobby...")

	-- Fire return-to-lobby callbacks (teleport, cleanup, etc.)
	for _, cb in ipairs(returnToLobbyCallbacks) do
		task.spawn(cb)
	end

	GameStateManager.SetState(STATES.IDLE)
	-- Allow a future run to ReturnToLobby once the IDLE transition settles.
	-- The delay matters in case a Victory→Defeat double-trigger happens within
	-- the same frame (we ignore the second; this clears the latch for next run).
	task.delay(2, function() _returnInFlight = false end)
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

function GameStateManager.TriggerVictory()
	if currentState == STATES.DEFENDING then
		GameStateManager.SetState(STATES.VICTORY)
	end
end

-- ═══════════════════════════════════════════════════════════
-- CALLBACKS
-- ═══════════════════════════════════════════════════════════

function GameStateManager.OnStateChanged(callback)
	table.insert(stateChangedCallbacks, callback)
end

function GameStateManager.OnReturnToLobby(callback)
	table.insert(returnToLobbyCallbacks, callback)
end

-- ═══════════════════════════════════════════════════════════
-- §AGX/X27: HIGHEST WAVE RECORD
-- ═══════════════════════════════════════════════════════════
-- Account.HighestWaveReached was never written, so the HighestWave board
-- and the wave part of Power's prestige bonus (GearRating) were always 0.
-- The mode Mains call this on each wave/level completion (Lane: MobSpawner
-- OnWaveCompleted; Horde: its level watcher) — no MobSpawner edit needed.
-- Stores max(current, wave) for every player in the server. In-memory only;
-- it rides the normal PlayerDataManager saves, and LeaderboardManager
-- persists it on leave.
function GameStateManager.RecordWaveReached(wave)
	wave = tonumber(wave)
	if not wave or wave <= 0 then return end
	wave = math.floor(wave)
	local DataManager = require(Modules:WaitForChild("PlayerDataManager"))
	for _, player in ipairs(Players:GetPlayers()) do
		local account = DataManager.GetAccountData(player)
		if account and wave > (tonumber(account.HighestWaveReached) or 0) then
			account.HighestWaveReached = wave
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function GameStateManager.IsInGame()
	return currentState == STATES.PREPARING or currentState == STATES.DEFENDING
end

function GameStateManager.IsDefending()
	return currentState == STATES.DEFENDING
end

return GameStateManager