-- ServerScriptService/Modules/MatchmakingManager
--[[
    Handles queuing parties for game modes and launching matches.
    
    Flow:
      1. Party leader clicks "Play" on a game mode in the menu.
      2. Client fires MatchmakingRequest { action = "Queue", mode = "Defense" }.
      3. Server validates (party exists, mode available, correct size, all in village).
      4. Party enters the queue for that mode.
      5. The queue check runs: if enough players → form match → 5 s countdown → transition.
      6. During countdown, players can cancel. If anyone cancels, match is voided.
    
    For Defense mode (soloAllowed, min 1): match starts immediately on queue.
    For future modes with minPlayers > partySize: parties wait in queue
    until enough players/parties are available to fill a match.
    
    Network events:
      MatchmakingRequest   (client → server)  { action, mode }
      MatchmakingUpdate    (server → client)  { status, countdown, mode, ... }
]]

local MatchmakingManager = {}

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

local SharedModules = SSS:WaitForChild("Modules")
local LobbyModules  = script.Parent
local NetworkManager = nil
local PartyManager   = nil
local SceneManager   = nil
local GameModeConfig = nil
local DifficultyConfig = nil
local PlayerDataManager = nil
local TeleportManager = nil

-- ── Queue state ───────────────────────────────────────────
-- { [queueId] = { partyId, modeId, players = {}, queuedAt } }
local queue = {}
local nextQueueId = 1

-- Active matches in countdown
-- { [matchId] = { players = {}, modeId, countdownEnd, cancelled } }
local activeCountdowns = {}
local nextMatchId = 1

local COUNTDOWN_SECONDS = 5

-- §AGX/X14: players whose match has launched but whose teleport hasn't
-- resolved yet. A party is in here from LaunchMatch until it leaves the
-- server (success), TeleportManager reports a failure, or the TTL lapses
-- (TeleportInitFailed is not guaranteed to fire). IsQueued treats these
-- players as busy so the leader can't double-queue during retry backoff.
-- [player] = expiresAt (os.clock)
local launching = {}
local LAUNCH_CALL_TTL   = 60  -- covers TeleportManager's synchronous G4 retries
local LAUNCH_SETTLE_TTL = 15  -- after TeleportAsync returns; < MatchmakingUI's 20 s client timeout

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function MatchmakingManager.Init()
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
	PartyManager   = require(LobbyModules:WaitForChild("PartyManager"))
	SceneManager   = require(LobbyModules:WaitForChild("SceneManager"))
	GameModeConfig = require(SharedModules:WaitForChild("GameModeConfig"))
	DifficultyConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("DifficultyConfig"))
	PlayerDataManager = require(SharedModules:WaitForChild("PlayerDataManager"))
	TeleportManager = require(LobbyModules:WaitForChild("TeleportManager"))

	NetworkManager.GetEvent("MatchmakingRequest")
	NetworkManager.GetEvent("MatchmakingUpdate")

	NetworkManager.OnClientEvent("MatchmakingRequest", function(player, data)
		if not data or not data.action then return end
		MatchmakingManager.HandleRequest(player, data)
	end)

	Players.PlayerRemoving:Connect(function(player)
		MatchmakingManager.HandlePlayerLeaving(player)
	end)

end

-- ═══════════════════════════════════════════════════════════
-- REQUEST ROUTER
-- ═══════════════════════════════════════════════════════════

function MatchmakingManager.HandleRequest(player, data)
	local action = data.action

	if action == "Queue" then
		MatchmakingManager.QueueForMode(player, data.mode, data.difficulty)
	elseif action == "Cancel" then
		MatchmakingManager.CancelQueue(player)
	else
		warn("[MatchmakingManager] Unknown action:", action)
	end
end

-- ═══════════════════════════════════════════════════════════
-- QUEUE
-- ═══════════════════════════════════════════════════════════

function MatchmakingManager.QueueForMode(player, modeId, difficulty)
	-- Validate mode
	if not GameModeConfig.IsModeAvailable(modeId) then
		MatchmakingManager.SendUpdate(player, { status = "Error", message = "Mode not available." })
		return false
	end

	-- Validate difficulty (server-authoritative — default to Normal if invalid)
	-- "Auto" or nil → pick the highest tier all party members qualify for
	local partyLevels = {}
	do
		local members = PartyManager.GetPartyMembers(player)
		for _, m in ipairs(members) do
			local acct = PlayerDataManager.GetAccountData(m)
			table.insert(partyLevels, acct and acct.Level or 1)
		end
	end
	if difficulty == "Auto" or type(difficulty) ~= "string" or not DifficultyConfig.IsValid(difficulty) then
		difficulty = DifficultyConfig.AutoSelect(partyLevels)
	else
		-- §T5-T9/S3: enforce requiredLevel on EXPLICIT picks too. A valid
		-- tier name ("Nightmare") used to skip the auto-select branch —
		-- and requiredLevel was only enforced inside AutoSelect — so a
		-- level-1 party could queue Nightmare with a hand-crafted packet.
		local tier = DifficultyConfig.GetDifficulty(difficulty)
		local minLevel = math.huge
		for _, lvl in ipairs(partyLevels) do
			minLevel = math.min(minLevel, lvl)
		end
		if minLevel < (tier.requiredLevel or 1) then
			MatchmakingManager.SendUpdate(player, {
				status = "Error",
				message = difficulty .. " requires level " .. (tier.requiredLevel or 1)
					.. " (party lowest: " .. (minLevel == math.huge and 1 or minLevel) .. ").",
			})
			return false
		end
	end

	local mode = GameModeConfig.GetMode(modeId)

	-- Must be in village
	if not SceneManager.IsInVillage(player) then
		MatchmakingManager.SendUpdate(player, { status = "Error", message = "Must be in village to queue." })
		return false
	end

	-- Ensure player has a party (auto-create solo party if needed)
	local partyId = PartyManager.EnsureParty(player)
	if not partyId then
		MatchmakingManager.SendUpdate(player, { status = "Error", message = "Could not create party." })
		return false
	end

	-- Only leader can queue
	if not PartyManager.IsPartyLeader(player) then
		MatchmakingManager.SendUpdate(player, { status = "Error", message = "Only the party leader can queue." })
		return false
	end

	-- Check party size against mode constraints
	local partySize = PartyManager.GetPartySize(player)
	if not mode.soloAllowed and partySize < mode.minPlayers then
		MatchmakingManager.SendUpdate(player, {
			status  = "Error",
			message = "Need at least " .. mode.minPlayers .. " players.",
		})
		return false
	end

	if partySize > mode.maxPlayers then
		MatchmakingManager.SendUpdate(player, {
			status  = "Error",
			message = "Party too large (max " .. mode.maxPlayers .. ").",
		})
		return false
	end

	-- Check all party members are in village
	local members = PartyManager.GetPartyMembers(player)
	for _, member in ipairs(members) do
		if not SceneManager.IsInVillage(member) then
			MatchmakingManager.SendUpdate(player, {
				status  = "Error",
				message = member.Name .. " is not in the village.",
			})
			return false
		end
	end

	-- §L6 fix: check IsQueued for EVERY party member, not just the leader.
	-- A member could already be in a queue from a prior solo-queue attempt
	-- whose CancelQueue was lost, or from a malicious / replayed packet.
	-- Without this, two queue entries can co-exist for the same player and
	-- both eventually try to teleport them.
	if MatchmakingManager.IsQueued(player) then
		MatchmakingManager.SendUpdate(player, { status = "Error", message = "Already in queue." })
		return false
	end
	for _, member in ipairs(members) do
		if member ~= player and MatchmakingManager.IsQueued(member) then
			MatchmakingManager.SendUpdate(player, {
				status = "Error",
				message = member.Name .. " is already in another queue.",
			})
			return false
		end
	end

	-- §L8 fix: clone the members array so the queue snapshot doesn't
	-- alias PartyManager's live members list. Without this, joining or
	-- leaving the party while queued would silently mutate the queued
	-- list — the players who eventually teleport may not match the ones
	-- the leader expected to bring.
	local membersSnapshot = table.clone(members)

	-- Add to queue
	local queueId = nextQueueId
	nextQueueId = nextQueueId + 1

	queue[queueId] = {
		queueId    = queueId,
		partyId    = partyId,
		modeId     = modeId,
		difficulty = difficulty or 1,
		players    = membersSnapshot,
		queuedAt   = os.clock(),
	}

	-- Notify all party members
	for _, member in ipairs(members) do
		MatchmakingManager.SendUpdate(member, {
			status = "Queued",
			mode   = modeId,
		})
	end

	-- Try to form a match immediately
	MatchmakingManager.TryFormMatch(modeId)

	return true
end

-- §AGX/X15: optional `reason` (e.g. "Party changed — queue cancelled.")
-- so PartyManager can reuse this path when membership changes.
function MatchmakingManager.CancelQueue(player, reason)
	for queueId, entry in pairs(queue) do
		for _, member in ipairs(entry.players) do
			if member == player then
				-- Remove the whole party entry from queue
				for _, m in ipairs(entry.players) do
					MatchmakingManager.SendUpdate(m, { status = "Cancelled", message = reason })
				end
				queue[queueId] = nil
				return
			end
		end
	end

	-- Also cancel active countdown
	for matchId, match in pairs(activeCountdowns) do
		for _, member in ipairs(match.players) do
			if member == player then
				match.cancelled = true
				for _, m in ipairs(match.players) do
					MatchmakingManager.SendUpdate(m, {
						status  = "Cancelled",
						message = reason or (player.Name .. " cancelled."),  -- §AGX/X15
					})
				end
				activeCountdowns[matchId] = nil
				return
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- MATCH FORMATION
-- ═══════════════════════════════════════════════════════════

function MatchmakingManager.TryFormMatch(modeId)
	local mode = GameModeConfig.GetMode(modeId)
	if not mode then return end

	-- Collect all queue entries for this mode
	local modeEntries = {}
	for queueId, entry in pairs(queue) do
		if entry.modeId == modeId then
			table.insert(modeEntries, entry)
		end
	end

	if #modeEntries == 0 then return end

	-- Simple strategy: for now, each party entry is its own match
	-- (future: merge multiple small parties to fill a match)
	for _, entry in ipairs(modeEntries) do
		local totalPlayers = #entry.players

		-- Enough to start?
		if totalPlayers >= mode.minPlayers then
			-- Remove from queue
			queue[entry.queueId] = nil

			-- Start countdown
			MatchmakingManager.StartCountdown(entry.players, modeId, entry.difficulty)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- COUNTDOWN
-- ═══════════════════════════════════════════════════════════

function MatchmakingManager.StartCountdown(players, modeId, difficulty)
	local matchId = nextMatchId
	nextMatchId = nextMatchId + 1

	activeCountdowns[matchId] = {
		matchId      = matchId,
		players      = players,
		modeId       = modeId,
		difficulty   = difficulty or 1,
		countdownEnd = os.clock() + COUNTDOWN_SECONDS,
		cancelled    = false,
	}

	-- Notify all players
	for _, player in ipairs(players) do
		MatchmakingManager.SendUpdate(player, {
			status    = "Countdown",
			mode      = modeId,
			countdown = COUNTDOWN_SECONDS,
		})
	end

	print("[MatchmakingManager] Match", matchId, "countdown started — ", modeId)

	-- Run countdown
	task.spawn(function()
		local remaining = COUNTDOWN_SECONDS

		while remaining > 0 do
			task.wait(1)
			remaining = remaining - 1

			local match = activeCountdowns[matchId]
			if not match or match.cancelled then
				return  -- cancelled
			end

			-- Send tick updates
			for _, player in ipairs(players) do
				if player.Parent then
					MatchmakingManager.SendUpdate(player, {
						status    = "Countdown",
						mode      = modeId,
						countdown = remaining,
					})
				end
			end
		end

		-- Check if still active
		local match = activeCountdowns[matchId]
		if not match or match.cancelled then return end

		-- Launch!
		activeCountdowns[matchId] = nil
		MatchmakingManager.LaunchMatch(players, modeId, difficulty)
	end)
end

-- ═══════════════════════════════════════════════════════════
-- LAUNCH
-- ═══════════════════════════════════════════════════════════

function MatchmakingManager.LaunchMatch(players, modeId, difficulty)
	-- Filter out disconnected players
	local validPlayers = {}
	for _, player in ipairs(players) do
		if player.Parent then
			table.insert(validPlayers, player)
		end
	end

	if #validPlayers == 0 then
		warn("[MatchmakingManager] No valid players for match")
		return
	end

	-- §L7 fix: re-check minPlayers AFTER disconnect-filter. If a 5-player
	-- party where 4 disconnected during the 5s countdown reaches here,
	-- only 1 remains — teleporting them solo into a 5-player mode would
	-- be a guaranteed loss. Cancel the launch instead and let the
	-- remaining players re-queue.
	local mode = GameModeConfig.GetMode(modeId)
	if mode and not mode.soloAllowed and #validPlayers < (mode.minPlayers or 1) then
		warn(string.format(
			"[MatchmakingManager] Match cancelled — only %d/%d required players remain after disconnects.",
			#validPlayers, mode.minPlayers))
		for _, player in ipairs(validPlayers) do
			MatchmakingManager.SendUpdate(player, {
				status  = "Cancelled",
				message = "Match cancelled — too many players disconnected.",
			})
		end
		return
	end

	-- §AGX/X14: mark the party busy for the whole launch window.
	MatchmakingManager.MarkLaunching(validPlayers, LAUNCH_CALL_TTL)

	-- Notify
	for _, player in ipairs(validPlayers) do
		MatchmakingManager.SendUpdate(player, {
			status     = "Launching",
			mode       = modeId,
			difficulty = difficulty,  -- §AGX/X14: lets the client re-queue the same tier after a timeout
		})
	end

	-- Teleport party to target place via TeleportManager
	if not TeleportManager then
		warn("[MatchmakingManager] TeleportManager not available")
		-- §AGX/X14: don't leave the party stuck in "Launching".
		MatchmakingManager.ClearLaunching(validPlayers)
		for _, player in ipairs(validPlayers) do
			MatchmakingManager.SendUpdate(player, { status = "Error", message = "Teleport unavailable." })
		end
		return
	end
	local launched = TeleportManager.TeleportToGameMode(validPlayers, {
		modeId     = modeId,
		difficulty = difficulty or 1,
	})
	-- §AGX/X14: synchronous failure → TeleportManager already sent the
	-- Error; free the players. Accepted → keep them busy only for the
	-- settle window (TeleportInitFailed / PlayerRemoving usually end it sooner).
	if launched then
		MatchmakingManager.MarkLaunching(validPlayers, LAUNCH_SETTLE_TTL)
	else
		MatchmakingManager.ClearLaunching(validPlayers)
		return
	end

	print("[MatchmakingManager] Match launched —", modeId, "with", #validPlayers, "players")
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

-- §AGX/X14: launching-set helpers (TeleportManager calls these via its
-- lazy getter; see the `launching` comment at the top of the file).
function MatchmakingManager.MarkLaunching(players, ttl)
	local expiresAt = os.clock() + (ttl or LAUNCH_SETTLE_TTL)
	for _, player in ipairs(players) do
		launching[player] = expiresAt
	end
end

function MatchmakingManager.ClearLaunching(players)
	for _, player in ipairs(players) do
		launching[player] = nil
	end
end

function MatchmakingManager.IsLaunching(player)
	local expiresAt = launching[player]
	if not expiresAt then return false end
	if os.clock() >= expiresAt then
		launching[player] = nil
		return false
	end
	return true
end

function MatchmakingManager.IsQueued(player)
	-- §AGX/X14: a launch in flight counts as busy.
	if MatchmakingManager.IsLaunching(player) then return true end
	for _, entry in pairs(queue) do
		for _, member in ipairs(entry.players) do
			if member == player then return true end
		end
	end
	for _, match in pairs(activeCountdowns) do
		for _, member in ipairs(match.players) do
			if member == player then return true end
		end
	end
	return false
end

function MatchmakingManager.HandlePlayerLeaving(player)
	-- Auto-cancel any queue / countdown they are in
	MatchmakingManager.CancelQueue(player)
	-- §AGX/X14: leaving mid-launch is the normal teleport-success path.
	launching[player] = nil
end

function MatchmakingManager.SendUpdate(player, payload)
	if player and player.Parent then
		NetworkManager.FireClient(player, "MatchmakingUpdate", payload)
	end
end

return MatchmakingManager
