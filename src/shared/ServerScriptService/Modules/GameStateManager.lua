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
-- §AGX/T11-JAN: bumped on every SetState. The Victory/Defeat auto-return
-- delay only re-checked the state NAME, so Victory → Idle → new run →
-- Victory inside ReturnToLobbyDelay let the first run's timer fire early.
local stateEpoch = 0
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
-- §AGX/WC: §PB-D3 "ALL PLAYERS READY" START GATE
-- ═══════════════════════════════════════════════════════════
--[[
    One gate shared by the three combat places. Combat can start only once
    every party member expected in this server has sent ClientReady (the
    existing ReadyGate handshake — no new handshake):

      expected = party roster names from TeleportData (PeekPartyRoster, read
                 at PlayerAdded) ∪ players currently in the server
                 − members dropped from the wait (left the server, or still
                 not ready when the hard timeout fires)
      open     = at least one player ready AND every expected name is an
                 in-server player that is ready
      timeout  = START_GATE_TIMEOUT s after the FIRST ready player: opens
                 anyway and drops whoever is still missing (a stuck or
                 never-arriving client can't block the party)

    Studio solo: no TeleportData → expected = {you} → opens on your
    ClientReady, no delay. The roster transits the client, so a padded
    roster can only delay the start up to the timeout.

    Places call EnableStartGate({ autoStart = bool }) once at boot:
      autoStart = true   (Horde) the gate opening enters Defending directly
      autoStart = false  (Lane / CentralBoss) RequestStart is refused until
                         the gate opens; the Start button does the rest.
    Places that never call it (none today) keep the old ungated behaviour.
    The gate opens once per server and stays open (post-run restarts in
    Lane aren't re-gated).
]]
local START_GATE_TIMEOUT = 20

local gate = {
	enabled   = false,
	autoStart = false,
	open      = false,
	roster    = {},   -- [name] = true (from TeleportData)
	dropped   = {},   -- [name] = true (no longer waited for)
	timeoutArmed = false,
	callbacks = {},
}

local _ReadyGate
local function getReadyGate()
	if _ReadyGate == nil then
		local mod = Modules:FindFirstChild("ReadyGate")
		local ok, result = false, nil
		if mod then ok, result = pcall(require, mod) end
		_ReadyGate = ok and result or false
	end
	return _ReadyGate or nil
end

local _TeleportDataReader
local function getTeleportDataReader()
	if _TeleportDataReader == nil then
		local mod = Modules:FindFirstChild("TeleportDataReader")
		local ok, result = false, nil
		if mod then ok, result = pcall(require, mod) end
		_TeleportDataReader = ok and result or false
	end
	return _TeleportDataReader or nil
end

--- (readyCount, expectedCount, missingNames) for the current gate inputs.
local function gateCounts()
	local rg = getReadyGate()
	local expected = {}
	for name in pairs(gate.roster) do
		if not gate.dropped[name] then expected[name] = true end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if not gate.dropped[p.Name] then expected[p.Name] = true end
	end
	local ready, total, missing = 0, 0, {}
	for name in pairs(expected) do
		total += 1
		local p = Players:FindFirstChild(name)
		if p and p:IsA("Player") and rg and rg.IsReady(p) then
			ready += 1
		else
			table.insert(missing, name)
		end
	end
	return ready, total, missing
end

local function gateSnapshot()
	if not gate.enabled then return nil end
	local ready, total = gateCounts()
	return {
		open      = gate.open,
		ready     = ready,
		expected  = total,
		autoStart = gate.autoStart,
	}
end

local function broadcastGate()
	local snap = gateSnapshot()
	if snap then
		NetworkManager.FireAllClients("StartGateUpdate", snap)
	end
end

local function openGate(reason)
	if gate.open then return end
	gate.open = true
	print("[GameStateManager] §PB-D3 start gate OPEN (" .. reason .. ")")
	-- §AGX/D-FIX: N2 — autoStart enters Defending BEFORE the {open=true} broadcast, so no client sees open-while-Idle (Start button flash).
	if gate.autoStart and currentState == STATES.IDLE then
		GameStateManager.SetState(STATES.DEFENDING)
	end
	broadcastGate()
	for _, cb in ipairs(gate.callbacks) do
		task.spawn(cb)
	end
end

local evaluateGate  -- forward-declared: the timeout closure calls it

-- §AGX/D-FIX: S2 — true if any in-server player has loaded data (lazy require: PlayerDataManager is required lazily elsewhere in this file too).
local function anyPresentPlayerDataReady()
	local mod = Modules:FindFirstChild("PlayerDataManager")
	if not mod then return false end
	local ok, pdm = pcall(require, mod)
	if not ok or not pdm or not pdm.GetAccountData then return false end
	for _, p in ipairs(Players:GetPlayers()) do
		if pdm.GetAccountData(p) ~= nil then return true end
	end
	return false
end

evaluateGate = function()
	if not gate.enabled or gate.open then return end
	local ready, total, missing = gateCounts()
	if ready >= 1 and ready >= total then
		openGate(string.format("%d/%d ready", ready, total))
		return
	end
	-- §AGX/D-FIX: S2 — arm on the first PRESENT player too, not only the first ClientReady: one lost handshake must not strand the gate shut.
	if (ready >= 1 or #Players:GetPlayers() >= 1) and not gate.timeoutArmed then
		gate.timeoutArmed = true
		task.delay(START_GATE_TIMEOUT, function()
			if gate.open then return end
			local readyNow, _, stillMissing = gateCounts()
			-- §AGX/D-FIX: S2 — nobody ready: open only for a present, data-ready player; otherwise re-arm (never open on an empty server).
			if readyNow == 0 and not anyPresentPlayerDataReady() then
				gate.timeoutArmed = false
				warn("[GameStateManager] §PB-D3 start gate timeout with no ready/data-ready player — re-arming")
				evaluateGate()  -- re-arms now if someone is present, else on the next PlayerAdded
				return
			end
			for _, name in ipairs(stillMissing) do
				gate.dropped[name] = true
			end
			if #stillMissing > 0 then
				warn("[GameStateManager] §PB-D3 start gate timed out after "
					.. START_GATE_TIMEOUT .. " s — dropped from the wait: "
					.. table.concat(stillMissing, ", "))
			end
			openGate("timeout")
		end)
	end
	if #missing > 0 then
		print(string.format("[GameStateManager] §PB-D3 waiting for party (%d/%d) — missing: %s",
			ready, total, table.concat(missing, ", ")))
	end
	broadcastGate()
end

local function addRosterFrom(player)
	local tdr = getTeleportDataReader()
	if not tdr or not tdr.PeekPartyRoster then return end
	for _, name in ipairs(tdr.PeekPartyRoster(player)) do
		gate.roster[name] = true
	end
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function GameStateManager.Init()
	-- Create network events
	NetworkManager.GetEvent("GameStateChanged")
	NetworkManager.GetEvent("RequestStartGame")
	NetworkManager.GetEvent("CountdownUpdate")
	NetworkManager.GetEvent("StartGateUpdate")  -- §AGX/WC: §PB-D3

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
			startGate    = gateSnapshot(),  -- §AGX/WC: §PB-D3 (nil when ungated)
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
	stateEpoch += 1  -- §AGX/T11-JAN
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
			local epoch = stateEpoch  -- §AGX/T11-JAN
			task.delay(CONFIG.ReturnToLobbyDelay, function()
				if currentState == STATES.VICTORY and stateEpoch == epoch then
					GameStateManager.ReturnToLobby()
				end
			end)
		end

	elseif newState == STATES.DEFEAT then
		print("[GameStateManager] 💀 DEFEAT!")
		-- Optional: Return to lobby after delay
		if CONFIG.ReturnToLobbyDelay > 0 then
			local epoch = stateEpoch  -- §AGX/T11-JAN
			task.delay(CONFIG.ReturnToLobbyDelay, function()
				if currentState == STATES.DEFEAT and stateEpoch == epoch then
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

	-- §AGX/WC: §PB-D3 — no start until the whole party is ready (or the
	-- gate's timeout dropped the stragglers). Auto-start places never
	-- accept a manual start.
	if gate.enabled then
		local ns = Modules:FindFirstChild("NotifyService")
		if gate.autoStart then
			-- §AGX/D-FIX: N2 — was a silent refusal; closed gate gets the same "Waiting for party" toast as manual-start places.
			if not gate.open then
				local ready, total = gateCounts()
				local msg = string.format("Waiting for party (%d/%d)…", ready, total)
				if ns and player then pcall(function() require(ns).Toast(player, "warning", msg) end) end
			end
			return false, "This mode starts automatically"
		end
		if not gate.open then
			local ready, total = gateCounts()
			local msg = string.format("Waiting for party (%d/%d)…", ready, total)
			if ns and player then pcall(function() require(ns).Toast(player, "warning", msg) end) end
			return false, msg
		end
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
-- §AGX/WC: §PB-D3 START GATE API
-- ═══════════════════════════════════════════════════════════

--- Arm the all-players-ready gate for this place (call once at boot,
--- after ReadyGate / TeleportDataReader are loaded). opts.autoStart:
--- true → the gate opening enters Defending (Horde); false → it only
--- unlocks RequestStart (Lane / CentralBoss).
function GameStateManager.EnableStartGate(opts)
	if gate.enabled then return end
	opts = opts or {}
	gate.enabled   = true
	gate.autoStart = opts.autoStart == true

	local rg = getReadyGate()
	if not rg then
		warn("[GameStateManager] §PB-D3 ReadyGate missing — start gate opens immediately")
		openGate("no ReadyGate")
		return
	end

	Players.PlayerAdded:Connect(function(player)
		if not gate.open then gate.dropped[player.Name] = nil end  -- rejoined: wait for them again
		addRosterFrom(player)
		evaluateGate()
	end)
	Players.PlayerRemoving:Connect(function(player)
		if gate.open then return end
		gate.dropped[player.Name] = true  -- left before the start: stop waiting
		task.defer(evaluateGate)          -- after ReadyGate clears its entry
	end)
	rg.OnReady(function()
		evaluateGate()
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		addRosterFrom(player)
	end
	evaluateGate()
end

function GameStateManager.IsStartGateOpen()
	return (not gate.enabled) or gate.open
end

--- callback() once when the gate opens (fires immediately, spawned, if
--- it's already open or the place never enabled a gate).
function GameStateManager.OnStartGateOpen(callback)
	if GameStateManager.IsStartGateOpen() then
		task.spawn(callback)
		return
	end
	table.insert(gate.callbacks, callback)
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
-- `wave` is the highest wave/level COMPLETED (not merely reached; §AGX/SEC).
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