-- shared/ServerScriptService/Modules/TeleportDataReader.lua
--[[
    Reads TeleportData sent by the Lobby place's TeleportManager.

    When a player arrives in a combat place, ProcessPlayer() extracts
    the party composition, mode, and difficulty from
    Player:GetJoinData().TeleportData and applies them.

    If the player joined without teleport data (e.g. Studio test),
    defaults are applied so the game can still run.

    Used by LaneDefense, CentralBoss, and HordeMode.
    Call Init(modeId) with the place's mode identifier string.
]]

local TeleportDataReader = {}

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

local SharedModules = SSS:WaitForChild("Modules")

-- ── State ──────────────────────────────────────────────────
local arrivedPlayers  = {}
local matchDifficulty = "Normal"
local matchModeId     = "Defense"
local matchPartyData  = {}

-- §T0P2/X2 (DQ-B): difficulty is OWNED BY THE LOBBY — it arrives in the
-- teleport payload and is resolved exactly ONCE, by the first player
-- whose data is processed. Later arrivals cannot change it (the old
-- code let every arrival overwrite matchDifficulty — last-arriver-wins,
-- spoofable, and never re-pushed to the spawner anyway).
-- Consumers register OnDifficultyResolved to receive the validated
-- value; callbacks registered after resolution fire immediately.
local difficultyResolved   = false
local difficultyCallbacks  = {}

local DifficultyConfig = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("DifficultyConfig"))

local function resolveDifficulty(difficulty)
	if difficultyResolved then return end
	difficultyResolved = true
	matchDifficulty = difficulty
	for _, cb in ipairs(difficultyCallbacks) do
		task.spawn(cb, difficulty)
	end
end

-- ── Dependencies (set in Init) ─────────────────────────────
local NetworkManager = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════
function TeleportDataReader.Init(modeId)
	matchModeId = modeId or matchModeId
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
end

-- ═══════════════════════════════════════════════════════════
-- PROCESS ARRIVING PLAYER
-- ═══════════════════════════════════════════════════════════
function TeleportDataReader.ProcessPlayer(player)
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData

	if teleportData and type(teleportData) == "table" then
		arrivedPlayers[player.UserId] = teleportData

		-- §T0P2/X2: validate against DifficultyConfig (teleport data
		-- transits the client and is spoofable) and resolve ONCE.
		if teleportData.difficulty then
			if DifficultyConfig.IsValid(teleportData.difficulty) then
				resolveDifficulty(teleportData.difficulty)
			else
				warn("[TeleportDataReader] Invalid difficulty in teleport data from",
					player.Name, ":", tostring(teleportData.difficulty), "— ignoring")
			end
		end
		if teleportData.modeId then
			matchModeId = teleportData.modeId
		end
		if teleportData.partyData and #teleportData.partyData > 0 then
			matchPartyData = teleportData.partyData
		end

		TeleportDataReader.ApplyPlayerData(player, teleportData)
	else
		-- No teleport data = direct join / Studio test. Auto-select from
		-- the player's level (the Level attribute is set before data-ready
		-- callbacks fire — §T0P2/X7).
		warn("[TeleportDataReader] Player", player.Name, "has NO teleport data — using defaults")
		local playerLevel = player:GetAttribute("Level") or 1
		local autoDifficulty = DifficultyConfig.AutoSelect({ playerLevel })
		arrivedPlayers[player.UserId] = {
			modeId     = matchModeId,
			difficulty = autoDifficulty,
			partyData  = {
				{ name = player.Name, class = player:GetAttribute("ActiveClass") or "Aegis", level = playerLevel },
			},
		}
		resolveDifficulty(autoDifficulty)
		matchPartyData = arrivedPlayers[player.UserId].partyData
	end
end

--- §T0P2/X2: register a callback for the once-only difficulty
--- resolution. Fires immediately (spawned) if already resolved.
function TeleportDataReader.OnDifficultyResolved(callback)
	if difficultyResolved then
		task.spawn(callback, matchDifficulty)
		return
	end
	table.insert(difficultyCallbacks, callback)
end

-- ═══════════════════════════════════════════════════════════
-- APPLY PLAYER DATA
-- §T0P2/X20: sets the "TeleportClass" attribute for the player when the
-- party payload carries a class different from their current one.
-- NOTE: nothing reads this attribute yet — the intended consumer is the
-- new map's spawn flow (apply the party-selected class on arrival).
-- Tracked in docs/TODO.md (§T0P2-TPCLASS). Any consumer MUST validate
-- the class is actually unlocked for the player before applying it.
-- ═══════════════════════════════════════════════════════════
function TeleportDataReader.ApplyPlayerData(player, teleportData)
	local partyData = teleportData.partyData or {}
	for _, member in ipairs(partyData) do
		if member.name == player.Name then
			if member.class and member.class ~= "" then
				local currentClass = player:GetAttribute("ActiveClass")
				if currentClass ~= member.class then
					player:SetAttribute("TeleportClass", member.class)
				end
			end
			break
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS
-- ═══════════════════════════════════════════════════════════
function TeleportDataReader.GetDifficulty()
	return matchDifficulty
end

function TeleportDataReader.GetModeId()
	return matchModeId
end

function TeleportDataReader.GetPartyData()
	return matchPartyData
end

function TeleportDataReader.GetPlayerTeleportData(player)
	return arrivedPlayers[player.UserId]
end

function TeleportDataReader.GetAllArrivedPlayers()
	return arrivedPlayers
end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════
function TeleportDataReader.OnPlayerRemoving(player)
	arrivedPlayers[player.UserId] = nil
end

return TeleportDataReader
