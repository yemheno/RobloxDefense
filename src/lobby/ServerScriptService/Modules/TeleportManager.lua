-- lobby/ServerScriptService/Modules/TeleportManager.lua
--[[
    Lobby → Game Mode teleport module.
    
    Called by MatchmakingManager when a match is ready.
    Uses TeleportService:TeleportAsync to send a party to the
    target place, passing party composition, difficulty,
    and mode via TeleportOptions:SetTeleportData().
    
    The target place reads this data via TeleportDataReader.
]]

local TeleportManager = {}

local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")
local SSS             = game:GetService("ServerScriptService")

local SharedModules = SSS:WaitForChild("Modules")
local LobbyModules  = script.Parent

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

-- §L10: lazy-load PlayerDataManager so we can read authoritative Level
-- (Player attribute may not have replicated yet).
local _PlayerDataManager = nil
local function getPDM()
	if not _PlayerDataManager then
		local mod = SharedModules:FindFirstChild("PlayerDataManager")
		if mod then
			local ok, result = pcall(require, mod)
			if ok then _PlayerDataManager = result end
		end
	end
	return _PlayerDataManager
end

-- §L9: lazy-load MatchmakingManager so a teleport failure can cancel
-- the queue state. We avoid an Init-time require to dodge circular load.
local _MatchmakingManager = nil
local function getMatchmaking()
	if not _MatchmakingManager then
		local mod = LobbyModules:FindFirstChild("MatchmakingManager")
		if mod then
			local ok, result = pcall(require, mod)
			if ok then _MatchmakingManager = result end
		end
	end
	return _MatchmakingManager
end

-- ── Config ────────────────────────────────────────────────
local PLACE_IDS = {
	Defense     = Shared.PlaceIds.LaneDefense,
	CentralBoss = Shared.PlaceIds.CentralBoss,
	HordeMode   = Shared.PlaceIds.HordeMode,
}
local LANE_DEFENSE_PLACE_ID = Shared.PlaceIds.LaneDefense

-- §DISC/D6: party rules live in the shared PartyRequirements module
-- (same functions PartyManager uses at invite-time).
local PartyRequirements = require(SharedModules:WaitForChild("PartyRequirements"))

-- ── Dependencies (set in Init) ────────────────────────────
local NetworkManager = nil

-- §AGX/X14: per-player context for teleports that were ACCEPTED by
-- TeleportAsync but can still fail later (TeleportInitFailed fires after
-- the call returns). Holds what a one-shot retry needs to land the player
-- in the SAME reserved server as the rest of the party.
-- [player] = { placeId, teleportData, accessCode, modeId, difficulty, retried }
local pendingLaunches = {}
local INIT_FAIL_RETRY_DELAY = 2
local TRANSIENT_TELEPORT_RESULTS = {
	[Enum.TeleportResult.Failure] = true,
	[Enum.TeleportResult.Flooded] = true,
}

-- §AGX/X14: final failure for one player — drop the launch context, clear
-- MatchmakingManager's `launching` flag and tell the client so the UI
-- leaves "Launching".
local function failLaunch(player, reason)
	local pending = pendingLaunches[player]
	pendingLaunches[player] = nil
	warn("[TeleportManager] Launch failed for", player.Name, ":", tostring(reason))
	local mm = getMatchmaking()
	if mm and mm.ClearLaunching then
		mm.ClearLaunching({ player })
	end
	if player.Parent and NetworkManager then
		NetworkManager.FireClient(player, "MatchmakingUpdate", {
			status     = "Error",
			message    = "Teleport failed. Please try again.",
			mode       = pending and pending.modeId or nil,
			difficulty = pending and pending.difficulty or nil,
		})
	end
end

local function onTeleportInitFailed(player, teleportResult, errorMessage, _placeId, _options)
	local pending = pendingLaunches[player]
	if not pending then return end  -- not a matchmaking launch
	-- A duplicate request while the first is still in flight — not a failure.
	if teleportResult == Enum.TeleportResult.IsTeleporting then return end

	warn(string.format("[TeleportManager] TeleportInitFailed for %s: %s (%s)",
		player.Name, tostring(teleportResult), tostring(errorMessage)))

	-- §AGX/X14: retry ONCE for transient results, into the same reserved
	-- server via its access code. Without an access code a retry would
	-- reserve a fresh server and split the party, so we fail instead.
	if TRANSIENT_TELEPORT_RESULTS[teleportResult] and not pending.retried and pending.accessCode then
		pending.retried = true
		local mm = getMatchmaking()
		if mm and mm.MarkLaunching then
			-- keep the player "busy" through the backoff + second attempt
			mm.MarkLaunching({ player })
		end
		task.delay(INIT_FAIL_RETRY_DELAY, function()
			if not player.Parent or pendingLaunches[player] ~= pending then return end
			local retryOptions = Instance.new("TeleportOptions")
			retryOptions.ReservedServerAccessCode = pending.accessCode
			retryOptions:SetTeleportData(pending.teleportData)
			local ok, err = pcall(function()
				TeleportService:TeleportAsync(pending.placeId, { player }, retryOptions)
			end)
			if not ok then
				failLaunch(player, err)
			end
		end)
		return
	end

	failLaunch(player, errorMessage)
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════
function TeleportManager.Init()
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

	-- §AGX/X14: failures AFTER TeleportAsync returns only surface here.
	TeleportService.TeleportInitFailed:Connect(onTeleportInitFailed)
	Players.PlayerRemoving:Connect(function(player)
		pendingLaunches[player] = nil
	end)
end

-- ═══════════════════════════════════════════════════════════
-- TELEPORT TO GAME MODE
-- ═══════════════════════════════════════════════════════════
--[[
    TeleportToGameMode(players, options)
    
    players : { Player }
    options : {
        modeId       : string   — e.g. "Defense"
        difficulty   : number   — integer level for defense difficulty
        partyData    : {        — party composition snapshot
            { name: string, class: string, level: number }
        }
    }
]]
function TeleportManager.TeleportToGameMode(players, options)
	options = options or {}

	local modeId = options.modeId or "Defense"

	-- Build teleport data payload
	local teleportData = {
		modeId        = modeId,
		difficulty    = options.difficulty  or 1,
		partyData     = options.partyData  or {},
		lobbyPlaceId  = game.PlaceId,
		timestamp     = os.time(),
	}

	-- Build per-player data (class, level snapshot)
	-- §L10: read Level from PlayerDataManager.GetAccountData when
	-- available. Player attributes may not have replicated by the time
	-- TeleportToGameMode runs, which would mis-stamp a high-level player
	-- as level 1 and silently bypass the level-gap validation.
	if #teleportData.partyData == 0 then
		local pdm = getPDM()
		for _, player in ipairs(players) do
			local authoritativeLevel
			if pdm and pdm.GetAccountData then
				authoritativeLevel = pdm.GetAccountData(player, "Level")
			end
			table.insert(teleportData.partyData, {
				name  = player.Name,
				class = player:GetAttribute("ActiveClass") or "Aegis",
				level = authoritativeLevel or player:GetAttribute("Level") or 1,
			})
		end
	end

	-- Validate party (level gap, etc.)
	local valid, reason = TeleportManager.ValidateParty(teleportData)
	if not valid then
		for _, player in ipairs(players) do
			NetworkManager.FireClient(player, "MatchmakingUpdate", {
				status  = "Error",
				message = reason,
			})
		end
		return false, reason
	end

	-- Resolve target place from mode
	local placeId = PLACE_IDS[modeId] or LANE_DEFENSE_PLACE_ID

	-- Create teleport options
	local teleportOptions = Instance.new("TeleportOptions")
	-- §AGX/X4: one reserved server per match. Public servers let a second
	-- party land in a run already in progress (or a finished one).
	teleportOptions.ShouldReserveServer = true
	teleportOptions:SetTeleportData(teleportData)

	-- Attempt teleport.
	-- §T7/G4: retry with backoff, so a transient TeleportService hiccup
	-- can't strand the matched party in "Launching" after one failed pcall.
	local success, errorMsg = false, nil
	local teleportResult = nil
	local RETRIES, delaySec = 3, 1
	for attempt = 1, RETRIES do
		-- §AGX/X14: keep the TeleportAsyncResult — its access code lets a
		-- TeleportInitFailed retry rejoin the same reserved server.
		success, errorMsg = pcall(function()
			teleportResult = TeleportService:TeleportAsync(placeId, players, teleportOptions)
		end)
		if success then break end
		warn(string.format("[TeleportManager] Teleport attempt %d/%d failed: %s",
			attempt, RETRIES, tostring(errorMsg)))
		if attempt < RETRIES then
			task.wait(delaySec)
			delaySec = delaySec * 2
			-- Players may have left while we waited; drop them from the batch.
			for i = #players, 1, -1 do
				if not players[i] or not players[i].Parent then
					table.remove(players, i)
				end
			end
			if #players == 0 then
				errorMsg = "all players left during teleport retries"
				break
			end
		end
	end

	if success then
		print("[TeleportManager] Teleported", #players, "to", modeId, "(difficulty:", teleportData.difficulty, ")")
		-- §AGX/X14: remember the launch so a later TeleportInitFailed can
		-- retry / report it. Cleared on PlayerRemoving (= success) or failure.
		local accessCode = teleportResult and teleportResult.ReservedServerAccessCode or nil
		for _, player in ipairs(players) do
			pendingLaunches[player] = {
				placeId      = placeId,
				teleportData = teleportData,
				accessCode   = accessCode,
				modeId       = modeId,
				difficulty   = teleportData.difficulty,
				retried      = false,
			}
		end
	else
		warn("[TeleportManager] Teleport failed after retries:", errorMsg)
		-- §L9, §AGX/X14: notify clients of the error AND clear their matchmaking
		-- state so they have a path back to the queue UI. CancelQueue would be a
		-- no-op here (the queue entry and countdown are already gone by launch
		-- time), so clear the `launching` flag instead.
		local mm = getMatchmaking()
		if mm and mm.ClearLaunching then
			mm.ClearLaunching(players)
		end
		for _, player in ipairs(players) do
			if player and player.Parent then
				NetworkManager.FireClient(player, "MatchmakingUpdate", {
					status     = "Error",
					message    = "Teleport failed. Please try again.",
					mode       = modeId,
					difficulty = teleportData.difficulty,
				})
			end
		end
	end

	return success, errorMsg
end

-- ═══════════════════════════════════════════════════════════
-- VALIDATION (stubs — extend for level/class requirements)
-- ═══════════════════════════════════════════════════════════

--[[
    ValidateParty(teleportData) → bool, string?
    
    Checks if the party meets the minimum requirements for
    the selected mode and difficulty. Extend this later with
    level thresholds, required classes, etc.
]]
function TeleportManager.ValidateParty(teleportData)
	local partyData = teleportData.partyData
	if not partyData or #partyData == 0 then return true, nil end

	-- §DISC/D6: shared rule. Future launch gates (achievement locks,
	-- class composition) also fold into PartyRequirements.
	local levels = {}
	for _, member in ipairs(partyData) do
		table.insert(levels, member.level or 1)
	end
	local ok, minLevel, maxLevel = PartyRequirements.CheckLevels(levels)
	if not ok then
		return false, "Party level gap too large (max " .. PartyRequirements.MaxLevelGap()
			.. "). Highest: " .. maxLevel .. ", Lowest: " .. minLevel .. "."
	end

	return true, nil
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS
-- ═══════════════════════════════════════════════════════════
function TeleportManager.GetPlaceId()
	return LANE_DEFENSE_PLACE_ID
end

return TeleportManager
