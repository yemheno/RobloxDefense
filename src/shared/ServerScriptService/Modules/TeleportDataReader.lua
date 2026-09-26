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

local Players    = game:GetService("Players")
local SSS        = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local SharedModules = SSS:WaitForChild("Modules")

-- §AGX/X4: combat places only accept arrivals on the reserved server the
-- lobby created for the match. A public server here means someone joined
-- the place directly (or via an old public-server teleport) — bounce them.
-- Studio (solo play and Team Test) is exempt so playtesting still works.
local PUBLIC_SERVER_REASON = "Matches run on private servers — returning you to the lobby."
local function isRejectedPublicServer()
	-- §AGX/X4: VIP servers also have a PrivateServerId; only reserved
	-- servers (PrivateServerOwnerId == 0) count as a proper match server.
	return (game.PrivateServerId == "" or game.PrivateServerOwnerId ~= 0) and not RunService:IsStudio()
end

-- §AGX/X4: lazy getter (§5.3) — ReturnTeleporter requires this module in
-- its own Init, so no eager require here.
local _ReturnTeleporter
local function getReturnTeleporter()
	if _ReturnTeleporter ~= nil then
		return _ReturnTeleporter or nil
	end
	local mod = SharedModules:FindFirstChild("ReturnTeleporter")
	if not mod then
		_ReturnTeleporter = false
		warn("[TeleportDataReader] ReturnTeleporter not loaded.")
		return nil
	end
	local ok, result = pcall(require, mod)
	_ReturnTeleporter = ok and result or false
	return _ReturnTeleporter or nil
end

-- §AGX/X6: lazy getter for the player's LOADED level (server truth), used
-- to re-check the difficulty's requiredLevel on arrival.
local _PlayerDataManager
-- §AGX/WC: split out of getLoadedLevel so ApplyPlayerData can read the
-- server-truth active class too.
local function getPlayerDataManager()
	if _PlayerDataManager == nil then
		local mod = SharedModules:FindFirstChild("PlayerDataManager")
		local ok, result = false, nil
		if mod then ok, result = pcall(require, mod) end
		_PlayerDataManager = ok and result or false
	end
	return _PlayerDataManager or nil
end
local function getLoadedLevel(player)
	local pdm = getPlayerDataManager()
	if not pdm or not pdm.GetAccountData then return nil end
	return pdm.GetAccountData(player, "Level")
end

-- §AGX/WC: §T0P2-TPCLASS — lazy ClassManager (it validates + applies the
-- TeleportClass through the normal class-change path).
local _ClassManager
local function getClassManager()
	if _ClassManager == nil then
		local mod = SharedModules:FindFirstChild("ClassManager")
		local ok, result = false, nil
		if mod then ok, result = pcall(require, mod) end
		_ClassManager = ok and result or false
	end
	return _ClassManager or nil
end

-- §AGX/WC: §PB-D3 — bound on the roster names we accept from a payload
-- (lobby parties cap at 5; slack for matchmaking merges). The payload
-- transits the client, so a padded roster can only stretch the start
-- gate up to its hard timeout, never block it.
local MAX_ROSTER_NAMES = 10

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

-- §AGX/X6: requiredLevel re-check at resolution time. The payload's tier
-- transits the client, and the lobby check can be stale, so clamp against
-- the LOADED levels of everyone whose data is ready when the (once-only)
-- resolution happens — normally the first arrival(s). Choice: we do NOT
-- delay resolution to wait for the whole party (that would stall wave
-- spawns and the OnDifficultyResolved consumers); an under-level player
-- whose data loads after resolution is only logged, see ProcessPlayer.
local function clampDifficultyToLevels(requested)
	local tier = DifficultyConfig.GetDifficulty(requested)
	local levels = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local lvl = getLoadedLevel(p)
		if lvl then table.insert(levels, lvl) end
	end
	if #levels == 0 then return requested end
	local minLevel = math.huge
	for _, lvl in ipairs(levels) do
		minLevel = math.min(minLevel, lvl)
	end
	if minLevel >= (tier.requiredLevel or 1) then return requested end
	-- AutoSelect = highest tier every provided level qualifies for, which
	-- is necessarily below the requested one here.
	local clamped = DifficultyConfig.AutoSelect(levels)
	warn(string.format(
		"[TeleportDataReader] Difficulty %s requires level %d but lowest arrived level is %d — clamped to %s",
		tostring(requested), tier.requiredLevel or 1, minLevel, tostring(clamped)))
	return clamped
end

-- ── Dependencies (set in Init) ─────────────────────────────
local NetworkManager = nil

-- §AGX/X4: send a public-server arrival back to the lobby.
local function rejectPublicArrival(player)
	warn("[TeleportDataReader] Rejecting", player.Name, "— public server (PrivateServerId is empty)")
	local rt = getReturnTeleporter()
	local ok = rt and rt.TeleportPlayerToLobby
		and rt.TeleportPlayerToLobby(player, PUBLIC_SERVER_REASON)
	if not ok and player.Parent then
		-- Teleport unavailable — a kick still gets them out with the reason.
		player:Kick(PUBLIC_SERVER_REASON)
	end
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════
function TeleportDataReader.Init(modeId)
	-- §AGX/X6: the place's own mode is authoritative; the payload's
	-- modeId is never applied (it only gets logged on mismatch).
	matchModeId = modeId or matchModeId
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

	-- §AGX/X4: every combat place calls Init, so the reserved-server gate
	-- lives here once instead of in the three Mains.
	if isRejectedPublicServer() then
		warn("[TeleportDataReader] Public server outside Studio — all arrivals will be returned to the lobby")
		Players.PlayerAdded:Connect(function(player)
			task.spawn(rejectPublicArrival, player)
		end)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(rejectPublicArrival, player)
		end
	end
end

--- §AGX/X4: true on a public live server (arrivals are being bounced).
function TeleportDataReader.IsRejectedPublicServer()
	return isRejectedPublicServer()
end

-- ═══════════════════════════════════════════════════════════
-- PROCESS ARRIVING PLAYER
-- ═══════════════════════════════════════════════════════════
function TeleportDataReader.ProcessPlayer(player)
	-- §AGX/X4: a player being bounced off a public server must not resolve
	-- this server's difficulty or party data.
	if isRejectedPublicServer() then return end

	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData

	if teleportData and type(teleportData) == "table" then
		-- §AGX/X6: store a sanitised copy — the payload's modeId and
		-- lobbyPlaceId are never trusted downstream.
		teleportData = table.clone(teleportData)
		if teleportData.modeId ~= nil and teleportData.modeId ~= matchModeId then
			warn("[TeleportDataReader] Teleport data modeId mismatch from", player.Name, ":",
				tostring(teleportData.modeId), "≠ place mode", matchModeId, "— ignoring payload")
		end
		teleportData.modeId = matchModeId
		teleportData.lobbyPlaceId = nil
		-- §AGX/D-FIX: N3 — a non-table partyData (spoofed number/bool/string) is dropped before it's stored or #-indexed.
		if teleportData.partyData ~= nil and type(teleportData.partyData) ~= "table" then
			warn("[TeleportDataReader] Non-table partyData from", player.Name, "— ignoring")
			teleportData.partyData = nil
		end
		arrivedPlayers[player.UserId] = teleportData

		-- §T0P2/X2: validate against DifficultyConfig (teleport data
		-- transits the client and is spoofable) and resolve ONCE.
		if teleportData.difficulty then
			if DifficultyConfig.IsValid(teleportData.difficulty) then
				if not difficultyResolved then
					-- §AGX/X6: clamp to what the arrived players' loaded levels allow.
					resolveDifficulty(clampDifficultyToLevels(teleportData.difficulty))
				else
					-- §AGX/X6: resolved already (once-per-server); just log an
					-- under-level late arrival — see clampDifficultyToLevels.
					local lvl = getLoadedLevel(player)
					local req = DifficultyConfig.GetDifficulty(matchDifficulty).requiredLevel or 1
					if lvl and lvl < req then
						warn(string.format(
							"[TeleportDataReader] %s (level %d) arrived under %s's requiredLevel %d after resolution — not re-clamped",
							player.Name, lvl, tostring(matchDifficulty), req))
					end
				end
			else
				warn("[TeleportDataReader] Invalid difficulty in teleport data from",
					player.Name, ":", tostring(teleportData.difficulty), "— ignoring")
			end
		end
		if type(teleportData.partyData) == "table" and #teleportData.partyData > 0 then  -- §AGX/D-FIX: N3
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
-- §AGX/WC: §T0P2-TPCLASS — consumed right here via
-- ClassManager.ApplyTeleportClass, which validates the class exists AND
-- is unlocked for this player (the payload is client-influenced) before
-- switching through ClassManager.SetClass; otherwise it warns and ignores.
-- ProcessPlayer runs from the combat places' data-ready extras only, so
-- this never fires in the Lobby / Plaza.
-- ═══════════════════════════════════════════════════════════
function TeleportDataReader.ApplyPlayerData(player, teleportData)
	local partyData = teleportData.partyData or {}
	if type(partyData) ~= "table" then return end  -- §AGX/WC: payload is client-influenced
	for _, member in ipairs(partyData) do
		if type(member) == "table" and member.name == player.Name then
			if type(member.class) == "string" and member.class ~= "" then
				-- §AGX/WC: compare against server truth (loaded data). The
				-- ActiveClass attribute was never written server-side, so
				-- the old attribute compare always differed.
				local pdm = getPlayerDataManager()
				local currentClass = (pdm and pdm.GetActiveClass and pdm.GetActiveClass(player))
					or player:GetAttribute("ActiveClass")
				if currentClass ~= member.class then
					player:SetAttribute("TeleportClass", member.class)
				end
			end
			break
		end
	end

	-- §AGX/WC: §T0P2-TPCLASS consumer (no-op when no TeleportClass is set).
	if player:GetAttribute("TeleportClass") ~= nil then
		local cm = getClassManager()
		if cm and cm.ApplyTeleportClass then
			local ok, err = pcall(cm.ApplyTeleportClass, player)
			if not ok then
				warn("[TeleportDataReader] ApplyTeleportClass errored for", player.Name, ":", tostring(err))
			end
		else
			warn("[TeleportDataReader] ClassManager.ApplyTeleportClass unavailable — TeleportClass ignored for", player.Name)
		end
	end
end

--- §AGX/WC: §PB-D3 — the party roster (player names) this player's
--- TeleportData says is coming to this server. Read straight from join
--- data so the start gate knows the roster at PlayerAdded, before
--- ProcessPlayer (which waits for the DataStore load). Returns {} on a
--- direct join / Studio test / public-server bounce. Sanitised: strings
--- only, de-duplicated, capped at MAX_ROSTER_NAMES.
function TeleportDataReader.PeekPartyRoster(player)
	local names = {}
	if isRejectedPublicServer() then return names end
	local ok, joinData = pcall(function() return player:GetJoinData() end)
	local td = ok and type(joinData) == "table" and joinData.TeleportData
	local party = type(td) == "table" and td.partyData
	if type(party) ~= "table" then return names end
	local seen = {}
	for _, member in ipairs(party) do
		local name = type(member) == "table" and member.name
		if type(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(names, name)
			if #names >= MAX_ROSTER_NAMES then break end
		end
	end
	return names
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
