-- shared/ServerScriptService/Modules/ReturnTeleporter.lua
--[[
    Teleports players back to the lobby place.

    Reads the lobby PlaceId from TeleportDataReader (sent by TeleportManager
    inside the TeleportData payload). Falls back to FALLBACK_LOBBY_PLACE_ID
    for Studio testing.

    Used by LaneDefense, CentralBoss, and HordeMode.
]]

local ReturnTeleporter = {}

local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local SSS             = game:GetService("ServerScriptService")

local SharedModules = SSS:WaitForChild("Modules")

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

-- Dependencies (set in Init)
local TeleportDataReader = nil
local NetworkManager     = nil

-- Fallback lobby PlaceId for Studio testing
local FALLBACK_LOBBY_PLACE_ID = Shared.PlaceIds.Lobby

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════
function ReturnTeleporter.Init()
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

	local tdModule = SharedModules:FindFirstChild("TeleportDataReader")
	if tdModule then
		TeleportDataReader = require(tdModule)
	end

	NetworkManager.GetEvent("RequestReturnToLobby")
	NetworkManager.OnClientEvent("RequestReturnToLobby", function(player)
		ReturnTeleporter.TeleportPlayerToLobby(player)
	end)

	print("[ReturnTeleporter] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- LOBBY PLACE ID
-- ═══════════════════════════════════════════════════════════
function ReturnTeleporter.GetLobbyPlaceId()
	if TeleportDataReader then
		for _, player in ipairs(Players:GetPlayers()) do
			local data = TeleportDataReader.GetPlayerTeleportData(player)
			if data and data.lobbyPlaceId and data.lobbyPlaceId ~= 0 then
				return data.lobbyPlaceId
			end
		end
	end
	return FALLBACK_LOBBY_PLACE_ID
end

-- ═══════════════════════════════════════════════════════════
-- TELEPORT
-- ═══════════════════════════════════════════════════════════
function ReturnTeleporter.TeleportPlayerToLobby(player)
	local lobbyId = ReturnTeleporter.GetLobbyPlaceId()

	if lobbyId == 0 then
		if RunService:IsStudio() then
			warn("[ReturnTeleporter] Studio mode — skipping teleport for", player.Name)
		else
			warn("[ReturnTeleporter] No lobby PlaceId available — cannot teleport", player.Name)
		end
		return false
	end

	local ok, err = pcall(function()
		TeleportService:Teleport(lobbyId, player)
	end)

	if ok then
		-- success
	else
		warn("[ReturnTeleporter] Failed to teleport", player.Name, ":", err)
	end

	return ok
end

function ReturnTeleporter.TeleportAllToLobby()
	local lobbyId = ReturnTeleporter.GetLobbyPlaceId()

	if lobbyId == 0 then
		if RunService:IsStudio() then
			warn("[ReturnTeleporter] Studio mode — skipping teleport for all players")
		else
			warn("[ReturnTeleporter] No lobby PlaceId available — cannot teleport")
		end
		return false
	end

	local players = Players:GetPlayers()
	if #players == 0 then return true end

	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions.ShouldReserveServer = false

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(lobbyId, players, teleportOptions)
	end)

	if ok then
		-- all teleported
	else
		warn("[ReturnTeleporter] Group teleport failed:", err, "— falling back to individual teleports")
		for _, player in ipairs(players) do
			task.spawn(ReturnTeleporter.TeleportPlayerToLobby, player)
		end
	end

	return ok
end

return ReturnTeleporter
