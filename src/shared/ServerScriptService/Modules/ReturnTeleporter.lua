-- shared/ServerScriptService/Modules/ReturnTeleporter.lua
--[[
    Teleports players back to the lobby place.

    §AGX/X6: always targets Shared.PlaceIds.Lobby. The payload's
    lobbyPlaceId transits the client and is no longer read.

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
-- §AGX/X6: no TeleportDataReader dependency — the payload lobbyPlaceId
-- is not trusted.
local NetworkManager     = nil

-- §AGX/X6: the one lobby PlaceId.
local LOBBY_PLACE_ID = Shared.PlaceIds.Lobby

-- §AGX/X14: one retry for a failed return teleport, both for synchronous
-- pcall failures and for TeleportInitFailed after the call returned.
local RETURN_RETRY_DELAY = 2
local initFailRetried = {}   -- [player] = true once the async retry was used
local pendingReasons  = {}   -- [player] = reason string (X4 bounce) for the retry

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════
function ReturnTeleporter.Init()
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

	NetworkManager.GetEvent("RequestReturnToLobby")
	NetworkManager.OnClientEvent("RequestReturnToLobby", function(player)
		-- §AGX/X14: a manual press (HUD Return button) earns a fresh retry.
		initFailRetried[player] = nil
		ReturnTeleporter.TeleportPlayerToLobby(player)
	end)

	-- §AGX/X14: failures after TeleportAsync returned. Retry once; after
	-- that the HUD keeps the Return button up in post-run Idle so the
	-- player can try again. X4 bounces that still fail are kicked.
	TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
		if teleportResult == Enum.TeleportResult.IsTeleporting then return end
		warn("[ReturnTeleporter] TeleportInitFailed for", player.Name, ":",
			tostring(teleportResult), tostring(errorMessage))
		if not initFailRetried[player] then
			initFailRetried[player] = true
			task.delay(RETURN_RETRY_DELAY, function()
				if player.Parent then
					ReturnTeleporter.TeleportPlayerToLobby(player, pendingReasons[player])
				end
			end)
		elseif pendingReasons[player] and player.Parent then
			player:Kick(pendingReasons[player])
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		initFailRetried[player] = nil
		pendingReasons[player] = nil
	end)

end

-- ═══════════════════════════════════════════════════════════
-- LOBBY PLACE ID
-- ═══════════════════════════════════════════════════════════
function ReturnTeleporter.GetLobbyPlaceId()
	-- §AGX/X6: never read the payload's lobbyPlaceId (spoofable).
	return LOBBY_PLACE_ID
end

-- ═══════════════════════════════════════════════════════════
-- TELEPORT
-- ═══════════════════════════════════════════════════════════
-- §AGX/X4: optional `reason` rides along in TeleportData (returnReason)
-- for a future lobby-side toast; nothing in the lobby reads it yet.
function ReturnTeleporter.TeleportPlayerToLobby(player, reason)
	local lobbyId = ReturnTeleporter.GetLobbyPlaceId()
	pendingReasons[player] = reason

	if lobbyId == 0 then
		if RunService:IsStudio() then
			warn("[ReturnTeleporter] Studio mode — skipping teleport for", player.Name)
		else
			warn("[ReturnTeleporter] No lobby PlaceId available — cannot teleport", player.Name)
		end
		return false
	end

	-- §AGX/X4/X14: TeleportAsync (so a reason can travel) with one retry.
	local teleportOptions = Instance.new("TeleportOptions")
	if reason then
		teleportOptions:SetTeleportData({ returnReason = reason })
	end
	local ok, err
	for attempt = 1, 2 do
		ok, err = pcall(function()
			TeleportService:TeleportAsync(lobbyId, { player }, teleportOptions)
		end)
		if ok or not player.Parent then break end
		warn(string.format("[ReturnTeleporter] Teleport attempt %d/2 failed for %s: %s",
			attempt, player.Name, tostring(err)))
		if attempt < 2 then task.wait(RETURN_RETRY_DELAY) end
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
