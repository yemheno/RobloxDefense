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

-- §L11: read MaxLevelGap from PlayerDataConfig (single source of truth).
local MAX_LEVEL_GAP = 10
do
	local ok, cfg = pcall(function()
		return require(SharedModules:WaitForChild("PlayerDataConfig"))
	end)
	if ok and cfg and cfg.Matchmaking and cfg.Matchmaking.MaxLevelGap then
		MAX_LEVEL_GAP = cfg.Matchmaking.MaxLevelGap
	else
		warn("[TeleportManager] PlayerDataConfig.Matchmaking.MaxLevelGap missing — defaulting to 10")
	end
end

-- ── Dependencies (set in Init) ────────────────────────────
local NetworkManager = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════
function TeleportManager.Init()
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
	print("[TeleportManager] Initialized — target PlaceId:", LANE_DEFENSE_PLACE_ID)
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
	teleportOptions:SetTeleportData(teleportData)

	-- Attempt teleport
	local success, errorMsg = pcall(function()
		TeleportService:TeleportAsync(
			placeId,
			players,
			teleportOptions
		)
	end)

	if success then
		print("[TeleportManager] Teleported", #players, "to", modeId, "(difficulty:", teleportData.difficulty, ")")
	else
		warn("[TeleportManager] Teleport failed:", errorMsg)
		-- §L9 fix: notify clients of the error AND cancel their queue
		-- state. Without the cancel, MatchmakingManager still believes
		-- they're "Launching" and they have no path back to the queue UI.
		local mm = getMatchmaking()
		for _, player in ipairs(players) do
			if player and player.Parent then
				NetworkManager.FireClient(player, "MatchmakingUpdate", {
					status  = "Error",
					message = "Teleport failed. Please try again.",
				})
				if mm and mm.CancelQueue then
					mm.CancelQueue(player)
				end
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

	-- Find min/max level in the party
	local minLevel, maxLevel = math.huge, 0
	for _, member in ipairs(partyData) do
		local lvl = member.level or 1
		if lvl < minLevel then minLevel = lvl end
		if lvl > maxLevel then maxLevel = lvl end
	end

	-- Anti-carry: reject if level gap exceeds threshold
	if maxLevel - minLevel > MAX_LEVEL_GAP then
		return false, "Party level gap too large (max " .. MAX_LEVEL_GAP .. "). Highest: " .. maxLevel .. ", Lowest: " .. minLevel .. "."
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
