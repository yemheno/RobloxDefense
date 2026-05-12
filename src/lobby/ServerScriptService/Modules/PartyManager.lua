-- ServerScriptService/Modules/PartyManager
--[[
    Standard party system.
    
    Features:
      • Create / disband party
      • Invite with timeout (30 s)
      • Accept / decline invite
      • Leave party
      • Kick member (leader only)
      • Promote new leader (leader only)
      • Auto-disband when last member leaves
      • Auto-transfer leadership when leader leaves
      • Solo players are NOT in a party by default;
        they auto-create a party of 1 when they queue for matchmaking.
    
    Network events  (all prefixed "Party"):
      PartyRequest   (client → server)  { action, ... }
      PartyUpdate    (server → client)  full party snapshot
      PartyInvite    (server → client)  incoming invite popup
      PartyError     (server → client)  { message }
]]

local PartyManager = {}

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

local SharedModules = SSS:WaitForChild("Modules")
local NetworkManager   = nil  -- lazy
local BonusExpSystem   = nil  -- lazy

-- ── Data ──────────────────────────────────────────────────
local nextPartyId = 1

local parties        = {}   -- [partyId] = { id, leader, members={}, maxSize }
local playerParty    = {}   -- [player]  = partyId
local pendingInvites = {}   -- [player]  = { partyId, from, expiresAt }

local MAX_PARTY_SIZE = 5
local INVITE_TIMEOUT = 30  -- seconds
-- §L11: read MaxLevelGap from PlayerDataConfig so PartyManager and
-- TeleportManager can't drift apart. Late-load with a sane fallback so
-- a missing config doesn't crash the lobby — just warns.
local MAX_LEVEL_GAP  = 10
do
	local ok, cfg = pcall(function()
		return require(SharedModules:WaitForChild("PlayerDataConfig"))
	end)
	if ok and cfg and cfg.Matchmaking and cfg.Matchmaking.MaxLevelGap then
		MAX_LEVEL_GAP = cfg.Matchmaking.MaxLevelGap
	else
		warn("[PartyManager] PlayerDataConfig.Matchmaking.MaxLevelGap missing — defaulting to 10")
	end
end

-- Lazy-loaded PlayerDataManager for level checks
local PlayerDataManager = nil

local function getPlayerLevel(player)
	if not PlayerDataManager then
		local pdm = SharedModules:FindFirstChild("PlayerDataManager")
		if pdm then PlayerDataManager = require(pdm) end
	end
	if not PlayerDataManager then return 1 end
	local account = PlayerDataManager.GetAccountData(player)
	return account and account.Level or 1
end

-- Expose constants for UI modules that want to mirror server timings.
PartyManager.INVITE_TIMEOUT = INVITE_TIMEOUT

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function PartyManager.Init()
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
	BonusExpSystem = require(SharedModules:WaitForChild("BonusExpSystem"))

	-- Network events
	NetworkManager.GetEvent("PartyRequest")
	NetworkManager.GetEvent("PartyUpdate")
	NetworkManager.GetEvent("PartyInvite")
	NetworkManager.GetEvent("PartyError")
	NetworkManager.GetEvent("PlayerListUpdate")

	-- Route all party actions through one event
	NetworkManager.OnClientEvent("PartyRequest", function(player, data)
		if not data or not data.action then return end
		PartyManager.HandleRequest(player, data)
	end)

	-- Player list refresh on request
	NetworkManager.OnClientEvent("PlayerListRequest", function(player)
		PartyManager.SendPlayerList(player)
	end)

	-- Broadcast player list when roster changes
	Players.PlayerAdded:Connect(function()
		task.wait(1)  -- let data load first
		PartyManager.BroadcastPlayerList()
	end)

	Players.PlayerRemoving:Connect(function(player)
		PartyManager.HandlePlayerLeaving(player)
		task.defer(PartyManager.BroadcastPlayerList)
	end)

end

-- ═══════════════════════════════════════════════════════════
-- REQUEST ROUTER
-- ═══════════════════════════════════════════════════════════

function PartyManager.HandleRequest(player, data)
	local action = data.action

	if action == "Create" then
		PartyManager.CreateParty(player)

	elseif action == "Invite" then
		local targetName = data.targetName
		local target = Players:FindFirstChild(targetName)
		if target then
			PartyManager.InvitePlayer(player, target)
		else
			PartyManager.SendError(player, "Player not found.")
		end

	elseif action == "InviteById" then
		-- Invite by UserId (used by the Social panel player browser)
		local userId = data.userId
		local target
		for _, p in ipairs(Players:GetPlayers()) do
			if p.UserId == userId then target = p break end
		end
		if target then
			PartyManager.InvitePlayer(player, target)
		else
			PartyManager.SendError(player, "Player not found.")
		end

	elseif action == "AcceptInvite" then
		PartyManager.AcceptInvite(player)

	elseif action == "DeclineInvite" then
		PartyManager.DeclineInvite(player)

	elseif action == "Leave" then
		PartyManager.LeaveParty(player)

	elseif action == "Kick" then
		local targetName = data.targetName
		local target = Players:FindFirstChild(targetName)
		if target then
			PartyManager.KickPlayer(player, target)
		end

	elseif action == "KickMember" then
		-- UserId-based kick (used by Social panel)
		local target
		for _, p in ipairs(Players:GetPlayers()) do
			if p.UserId == data.userId then target = p break end
		end
		if target then PartyManager.KickPlayer(player, target) end

	elseif action == "Promote" then
		local targetName = data.targetName
		local target = Players:FindFirstChild(targetName)
		if target then
			PartyManager.PromoteLeader(player, target)
		end

	elseif action == "PromoteMember" then
		-- UserId-based promote (used by Social panel)
		local target
		for _, p in ipairs(Players:GetPlayers()) do
			if p.UserId == data.userId then target = p break end
		end
		if target then PartyManager.PromoteLeader(player, target) end

	elseif action == "Disband" then
		PartyManager.DisbandParty(player)

	else
		warn("[PartyManager] Unknown action:", action)
	end
end

-- ═══════════════════════════════════════════════════════════
-- PLAYER LIST  (for Social panel player browser)
-- ═══════════════════════════════════════════════════════════

--- Returns a payload array of all players currently in the server.
function PartyManager.BuildPlayerListPayload()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(list, { userId = p.UserId, name = p.Name })
	end
	return list
end

--- Send the current player list to a specific client.
function PartyManager.SendPlayerList(player)
	NetworkManager.FireClient(player, "PlayerListUpdate", PartyManager.BuildPlayerListPayload())
end

--- Broadcast the player list to all clients.
function PartyManager.BroadcastPlayerList()
	local payload = PartyManager.BuildPlayerListPayload()
	for _, p in ipairs(Players:GetPlayers()) do
		NetworkManager.FireClient(p, "PlayerListUpdate", payload)
	end
end

-- ═══════════════════════════════════════════════════════════
-- PARTY XP BONUS
-- ═══════════════════════════════════════════════════════════

--- Recalculate and apply the party XP bonus for every member.
--- Runs async to avoid blocking on IsFriendsWith calls.
function PartyManager.UpdatePartyBonuses(partyId)
	if not BonusExpSystem then return end
	local party = parties[partyId]
	if not party then return end

	task.spawn(function()
		for _, member in ipairs(party.members) do
			if playerParty[member] ~= partyId then continue end  -- guard race

			local addend = 0
			for _, other in ipairs(party.members) do
				if other == member then continue end
				local ok, isFriend = pcall(function()
					return member:IsFriendsWith(other.UserId)
				end)
				if ok and isFriend then
					addend = addend + 0.05   -- +5% per friend
				else
					addend = addend + 0.025  -- +2.5% per non-friend
				end
			end

			BonusExpSystem.SetBonus(member, "party", addend)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- PARTY CREATION
-- ═══════════════════════════════════════════════════════════

function PartyManager.CreateParty(leader)
	if playerParty[leader] then
		PartyManager.SendError(leader, "You are already in a party.")
		return nil
	end

	local partyId = nextPartyId
	nextPartyId = nextPartyId + 1

	parties[partyId] = {
		id        = partyId,
		leader    = leader,
		members   = { leader },
		maxSize   = MAX_PARTY_SIZE,
		createdAt = os.clock(),
	}

	playerParty[leader] = partyId
	PartyManager.BroadcastUpdate(partyId)

	return partyId
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC QUERIES (for other systems)
-- ═══════════════════════════════════════════════════════════

--- Returns an array of Player instances in the caller's party.
--- If not in a party, returns { player }.
function PartyManager.GetPartyMembers(player)
	local partyId = playerParty[player]
	if not partyId then
		return { player }
	end
	local party = parties[partyId]
	if not party or type(party.members) ~= "table" or #party.members == 0 then
		return { player }
	end
	return party.members
end

--- Creates a solo party silently (for matchmaking). Returns partyId.
function PartyManager.EnsureParty(player)
	local existing = playerParty[player]
	if existing then return existing end
	return PartyManager.CreateParty(player)
end

-- ═══════════════════════════════════════════════════════════
-- INVITES
-- ═══════════════════════════════════════════════════════════

function PartyManager.InvitePlayer(leader, target)
	-- §L3 fix: reject self-invite. Without this, a leader inviting
	-- themselves overwrites their own pendingInvites slot and produces
	-- inconsistent UI state.
	if target == leader then
		PartyManager.SendError(leader, "You cannot invite yourself.")
		return false
	end

	-- Validations
	local partyId = playerParty[leader]
	if not partyId then
		PartyManager.SendError(leader, "Create a party first.")
		return false
	end

	local party = parties[partyId]
	if not party then return false end

	if party.leader ~= leader then
		PartyManager.SendError(leader, "Only the party leader can invite.")
		return false
	end

	if #party.members >= party.maxSize then
		PartyManager.SendError(leader, "Party is full.")
		return false
	end

	if playerParty[target] then
		PartyManager.SendError(leader, target.Name .. " is already in a party.")
		return false
	end

	if pendingInvites[target] then
		PartyManager.SendError(leader, target.Name .. " already has a pending invite.")
		return false
	end

	-- Send invite
	pendingInvites[target] = {
		partyId   = partyId,
		from      = leader,
		expiresAt = os.clock() + INVITE_TIMEOUT,
	}

	NetworkManager.FireClient(target, "PartyInvite", {
		from      = leader.Name,
		partyId   = partyId,
		timeout   = INVITE_TIMEOUT,
	})

	-- Auto-expire
	task.delay(INVITE_TIMEOUT, function()
		if pendingInvites[target] and pendingInvites[target].partyId == partyId then
			pendingInvites[target] = nil
			PartyManager.SendError(target, "Party invite expired.")
		end
	end)

	return true
end

function PartyManager.AcceptInvite(player)
	local invite = pendingInvites[player]
	if not invite then
		PartyManager.SendError(player, "No pending invite.")
		return false
	end

	if os.clock() > invite.expiresAt then
		pendingInvites[player] = nil
		PartyManager.SendError(player, "Invite expired.")
		return false
	end

	local party = parties[invite.partyId]
	if not party then
		pendingInvites[player] = nil
		PartyManager.SendError(player, "Party no longer exists.")
		return false
	end

	if #party.members >= party.maxSize then
		pendingInvites[player] = nil
		PartyManager.SendError(player, "Party is full.")
		return false
	end

	-- Level gap check: no two members may differ by more than MAX_LEVEL_GAP
	local joinerLevel = getPlayerLevel(player)
	for _, member in ipairs(party.members) do
		local memberLevel = getPlayerLevel(member)
		if math.abs(joinerLevel - memberLevel) > MAX_LEVEL_GAP then
			pendingInvites[player] = nil
			PartyManager.SendError(player,
				"Level gap too large (max " .. MAX_LEVEL_GAP .. "). "
				.. member.Name .. " is level " .. memberLevel .. ".")
			return false
		end
	end

	-- §L4 fix: re-check size and party-membership IMMEDIATELY before
	-- insert. The earlier checks (line 369, line 364) happened before the
	-- level-gap loop — a second concurrent AcceptInvite could pass those
	-- earlier checks, run its own level-gap loop, and arrive here
	-- interleaved. Without this guard both inserts succeed and the party
	-- ends up at maxSize+1 (or more under heavy concurrency). We also
	-- re-check playerParty[player] in case a duplicate client packet
	-- already inserted them.
	if #party.members >= party.maxSize then
		pendingInvites[player] = nil
		PartyManager.SendError(player, "Party is full.")
		return false
	end
	if playerParty[player] then
		pendingInvites[player] = nil
		PartyManager.SendError(player, "You are already in a party.")
		return false
	end

	-- Join
	pendingInvites[player] = nil
	table.insert(party.members, player)
	playerParty[player] = party.id

	PartyManager.BroadcastUpdate(party.id)

	return true
end

function PartyManager.DeclineInvite(player)
	local invite = pendingInvites[player]
	if not invite then return end

	pendingInvites[player] = nil

	-- Notify the inviter
	if invite.from and invite.from.Parent then
		PartyManager.SendError(invite.from, player.Name .. " declined the invite.")
	end
end

-- ═══════════════════════════════════════════════════════════
-- LEAVE / KICK / DISBAND
-- ═══════════════════════════════════════════════════════════

function PartyManager.LeaveParty(player)
	local partyId = playerParty[player]
	if not partyId then
		PartyManager.SendError(player, "You are not in a party.")
		return
	end

	local party = parties[partyId]
	if not party then
		playerParty[player] = nil
		return
	end

	PartyManager.RemoveMember(party, player)
end

function PartyManager.KickPlayer(leader, target)
	local partyId = playerParty[leader]
	if not partyId then return end

	local party = parties[partyId]
	if not party or party.leader ~= leader then
		PartyManager.SendError(leader, "Only the leader can kick.")
		return
	end

	if target == leader then
		PartyManager.SendError(leader, "You cannot kick yourself.")
		return
	end

	if playerParty[target] ~= partyId then
		PartyManager.SendError(leader, target.Name .. " is not in your party.")
		return
	end

	PartyManager.RemoveMember(party, target)
	PartyManager.SendError(target, "You have been kicked from the party.")
end

function PartyManager.DisbandParty(player)
	local partyId = playerParty[player]
	if not partyId then return end

	local party = parties[partyId]
	if not party then
		playerParty[player] = nil
		return
	end

	if party.leader ~= player then
		PartyManager.SendError(player, "Only the leader can disband.")
		return
	end

	-- Notify all members and clear their bonuses
	for _, member in ipairs(party.members) do
		playerParty[member] = nil
		if BonusExpSystem then
			BonusExpSystem.RemoveBonus(member, "party")
		end
		NetworkManager.FireClient(member, "PartyUpdate", { disbanded = true })
	end

	parties[partyId] = nil
end

function PartyManager.PromoteLeader(leader, target)
	-- §L5 fix: reject self-promote with a clear error.
	if target == leader then
		PartyManager.SendError(leader, "You are already the leader.")
		return
	end

	local partyId = playerParty[leader]
	if not partyId then return end

	local party = parties[partyId]
	if not party or party.leader ~= leader then
		PartyManager.SendError(leader, "Only the leader can promote.")
		return
	end

	if playerParty[target] ~= partyId then
		PartyManager.SendError(leader, target.Name .. " is not in your party.")
		return
	end

	party.leader = target
	PartyManager.BroadcastUpdate(partyId)
end

-- ═══════════════════════════════════════════════════════════
-- INTERNAL HELPERS
-- ═══════════════════════════════════════════════════════════

function PartyManager.RemoveMember(party, player)
	-- Remove from list
	for i, member in ipairs(party.members) do
		if member == player then
			table.remove(party.members, i)
			break
		end
	end

	playerParty[player] = nil

	-- Clear this player's party XP bonus
	if BonusExpSystem then
		BonusExpSystem.RemoveBonus(player, "party")
	end

	-- Notify the removed player
	NetworkManager.FireClient(player, "PartyUpdate", { disbanded = true })

	-- Is the party now empty?
	if #party.members == 0 then
		parties[party.id] = nil
		return
	end

	-- Transfer leadership if the leader left
	if party.leader == player then
		party.leader = party.members[1]
	end

	-- Broadcast update to remaining members
	PartyManager.BroadcastUpdate(party.id)
end

function PartyManager.HandlePlayerLeaving(player)
	-- Clear pending invites
	pendingInvites[player] = nil

	-- Leave party
	local partyId = playerParty[player]
	if partyId and parties[partyId] then
		PartyManager.RemoveMember(parties[partyId], player)
	end
	playerParty[player] = nil
end

-- ═══════════════════════════════════════════════════════════
-- BROADCAST
-- ═══════════════════════════════════════════════════════════

function PartyManager.BroadcastUpdate(partyId)
	local party = parties[partyId]
	if not party then return end

	local memberList = {}
	for _, member in ipairs(party.members) do
		table.insert(memberList, { userId = member.UserId, name = member.Name })
	end

	local payload = {
		id          = party.id,
		leaderId    = party.leader.UserId,
		members     = memberList,
		maxSize     = party.maxSize,
		disbanded   = false,
	}

	for _, member in ipairs(party.members) do
		NetworkManager.FireClient(member, "PartyUpdate", payload)
	end

	-- Recalculate XP bonuses asynchronously after roster changes
	PartyManager.UpdatePartyBonuses(partyId)
end

function PartyManager.SendError(player, message)
	NetworkManager.FireClient(player, "PartyError", { message = message })
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC QUERIES (for other server modules)
-- ═══════════════════════════════════════════════════════════

function PartyManager.IsInParty(player)
	return playerParty[player] ~= nil
end

function PartyManager.IsPartyLeader(player)
	local partyId = playerParty[player]
	if not partyId then return false end
	local party = parties[partyId]
	return party and party.leader == player
end

function PartyManager.GetParty(player)
	local partyId = playerParty[player]
	return partyId and parties[partyId] or nil
end

function PartyManager.GetPartySize(player)
	local party = PartyManager.GetParty(player)
	return party and #party.members or 1
end

function PartyManager.GetPartyId(player)
	return playerParty[player]
end

-- Send the requesting player's current party state (used on SocialPanel open).
function PartyManager.SendPartyState(player)
	local partyId = playerParty[player]
	if partyId and parties[partyId] then
		local party = parties[partyId]
		local memberList = {}
		for _, m in ipairs(party.members) do
			table.insert(memberList, { userId = m.UserId, name = m.Name })
		end
		NetworkManager.FireClient(player, "PartyUpdate", {
			id        = party.id,
			leaderId  = party.leader.UserId,
			members   = memberList,
			maxSize   = party.maxSize,
			disbanded = false,
		})
	else
		NetworkManager.FireClient(player, "PartyUpdate", { disbanded = true })
	end
end

return PartyManager
