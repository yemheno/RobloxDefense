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

-- ── Dependencies (set in Init) ─────────────────────────────
local NetworkManager = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════
function TeleportDataReader.Init(modeId)
	matchModeId = modeId or matchModeId
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
	print("[TeleportDataReader] Initialized (" .. matchModeId .. ")")
end

-- ═══════════════════════════════════════════════════════════
-- PROCESS ARRIVING PLAYER
-- ═══════════════════════════════════════════════════════════
function TeleportDataReader.ProcessPlayer(player)
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData

	if teleportData and type(teleportData) == "table" then
		arrivedPlayers[player.UserId] = teleportData

		if teleportData.difficulty then
			matchDifficulty = teleportData.difficulty
		end
		if teleportData.modeId then
			matchModeId = teleportData.modeId
		end
		if teleportData.partyData and #teleportData.partyData > 0 then
			matchPartyData = teleportData.partyData
		end

		TeleportDataReader.ApplyPlayerData(player, teleportData)
	else
		warn("[TeleportDataReader] Player", player.Name, "has NO teleport data — using defaults")
		local playerLevel = player:GetAttribute("Level") or 1
		local DifficultyConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("DifficultyConfig"))
		local autoDifficulty = DifficultyConfig.AutoSelect({ playerLevel })
		arrivedPlayers[player.UserId] = {
			modeId     = matchModeId,
			difficulty = autoDifficulty,
			partyData  = {
				{ name = player.Name, class = player:GetAttribute("ActiveClass") or "Aegis", level = playerLevel },
			},
		}
		matchDifficulty = autoDifficulty
		matchPartyData = arrivedPlayers[player.UserId].partyData
	end
end

-- ═══════════════════════════════════════════════════════════
-- APPLY PLAYER DATA
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
