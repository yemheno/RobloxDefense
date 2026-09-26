-- ServerScriptService/Modules/StatsManager/PartyAura
--[[
    §AGX/X11: party auras for the Patron Saint and Fortune Favors keystones.

    Once per second, each keystone OWNER shares 50% of their TALENT-sourced
    bonuses with every party member who is:
      • in the same party (see "Party membership" below), not the owner,
      • alive (DeathState "Alive", or unset in places without a death system),
      • within 30 studs of the owner (squared distance, 3D),
    while the owner is alive too.

      Rule            Shared stats (50% of the owner's talent total)
      ──────────────  ──────────────────────────────────────────────────
      PatronSaint     HealingPower, HealingPercent, XPBonus, MeritBonus
      FortuneFavors   XPBonus, MeritBonus

    One owner holding both shares each stat once. Auras from DIFFERENT
    owners don't stack: per member and stat, the strongest share wins (ties:
    the first owner found keeps it).

    Writes go to BonusManager source "aura_<ownerUserId>" on the MEMBER,
    via SetSourceBonuses / ClearSource, and only when a value changes. A
    source holds exactly the stats that owner currently wins. Leaving
    range, death, unallocating the keystone (respec) or the owner leaving
    all clear it on the next tick; the owner leaving also clears it at once
    (PlayerRemoving). Amounts come from TalentEffectAggregator.GetTalentBonus
    (the talent source only), so auras never chain through other auras.

    Dynamic source keys follow the "timed_<tag>" precedent: BonusManager
    creates a missing source table on first write; the key family is
    documented in BonusManager's header (see the X11 hand-off note).

    Party membership (first match wins):
      1. Combat places: TeleportDataReader.GetPartyData() roster (the
         reserved server's party, by player name — same source
         KillRewardManager uses for XP sharing).
      2. Lobby: PartyManager.GetPartyId(player) (nil = solo, no aura).
      3. Studio with neither: everyone on the server is one party, so a
         Team Test can exercise the aura. Never true on a live server.

    Cost: O(players²) per second with no steady-state allocations — the
    player list, owner list and scratch arrays are reused; tables are only
    built when an aura actually changes.
]]

local PartyAura = {}

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = script.Parent.Parent

-- ═══════════════════════════════════════════════════════════
-- TUNING  (keystone descriptions + delegated balance call)
-- ═══════════════════════════════════════════════════════════

local TICK          = 1      -- s
local RANGE         = 30     -- studs
local RANGE_SQ      = RANGE * RANGE
local SHARE         = 0.5    -- fraction of the owner's talent bonus
local SOURCE_PREFIX = "aura_"

-- Stat slots, and which slots each rule shares.
local STATS  = { "HealingPower", "HealingPercent", "XPBonus", "MeritBonus" }
local NSTATS = #STATS
local RULE_NAMES = { "PatronSaint", "FortuneFavors" }
local RULE_SLOTS = {
	PatronSaint   = { true,  true,  true, true },
	FortuneFavors = { false, false, true, true },
}

-- ═══════════════════════════════════════════════════════════
-- LAZY REFERENCES  (Audit_4.7 §5.3 / §5.4)
-- ═══════════════════════════════════════════════════════════

local _hasRule, _getTalentBonus = nil, nil
local function resolveTalents()
	if _hasRule then return true end
	local mod = Modules:FindFirstChild("TalentEffectAggregator")
	if not mod then return false end
	local ok, tea = pcall(require, mod)
	if ok and tea and type(tea.HasRule) == "function" and type(tea.GetTalentBonus) == "function" then
		_hasRule, _getTalentBonus = tea.HasRule, tea.GetTalentBonus
		return true
	end
	return false
end

local _BonusManager = nil
local function getBonusManager()
	if _BonusManager then return _BonusManager end
	local mod = Modules:FindFirstChild("BonusManager")
	if not mod then return nil end
	local ok, bm = pcall(require, mod)
	if ok and bm and bm.SetSourceBonuses and bm.ClearSource then _BonusManager = bm end
	return _BonusManager
end

-- Not cached as missing: TeleportDataReader exists in combat places only,
-- PartyManager in the Lobby only.
local _TeleportDataReader = nil
local function getTeleportDataReader()
	if _TeleportDataReader then return _TeleportDataReader end
	local mod = Modules:FindFirstChild("TeleportDataReader")
	if not mod then return nil end
	local ok, tdr = pcall(require, mod)
	if ok and tdr then _TeleportDataReader = tdr end
	return _TeleportDataReader
end

local _PartyManager = nil
local function getPartyManager()
	if _PartyManager then return _PartyManager end
	-- §AGX/D-FIX2: PartyManager lives in ServerScriptService.Lobby.Modules
	-- (lobby.project.json / LobbyMain), not the shared Modules folder, so
	-- the old lookup never found it and the Lobby branch was dead.
	local lobby = game:GetService("ServerScriptService"):FindFirstChild("Lobby")
	local lobbyModules = lobby and lobby:FindFirstChild("Modules")
	local mod = lobbyModules and lobbyModules:FindFirstChild("PartyManager")
	if not mod then return nil end
	local ok, pm = pcall(require, mod)
	if ok and pm and pm.GetPartyId then _PartyManager = pm end
	return _PartyManager
end

-- ═══════════════════════════════════════════════════════════
-- STATE  (all reused across ticks)
-- ═══════════════════════════════════════════════════════════

local playerList   = {}                                   -- array of Player
local posOf        = setmetatable({}, { __mode = "k" })   -- [player] = Vector3 | nil (nil = not eligible)
local partyKey     = setmetatable({}, { __mode = "k" })   -- [player] = any | nil
local ownerShare   = setmetatable({}, { __mode = "k" })   -- [owner] = { [slot] = number }
local owners       = {}                                   -- array of Player (this tick)
local bestOwner    = table.create(NSTATS, false)          -- [slot] = Player | false
local bestVal      = table.create(NSTATS, 0)              -- [slot] = number
local dirtyOwners  = {}                                   -- array of UserId
local appliedOwner = {}  -- [member] = { [slot] = ownerUserId | false }
local appliedVal   = {}  -- [member] = { [slot] = number }
local sourceNames  = {}  -- [ownerUserId] = "aura_<id>"

local rosterSource, rosterSet = nil, nil

local function sourceName(ownerId)
	local s = sourceNames[ownerId]
	if not s then
		s = SOURCE_PREFIX .. tostring(ownerId)
		sourceNames[ownerId] = s
	end
	return s
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

--- Root position of an alive player, else nil.
local function alivePosition(player)
	local ds = player:GetAttribute("DeathState")
	if ds ~= nil and ds ~= "Alive" then return nil end
	local char = player.Character
	if not char or not char.Parent then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

--- Which membership source applies this tick: "roster" | "manager" | "studio" | nil.
local function partyMode()
	local tdr = getTeleportDataReader()
	local pd = tdr and tdr.GetPartyData and tdr.GetPartyData()
	if type(pd) == "table" and #pd > 0 then
		if pd ~= rosterSource then
			-- Rebuilt only when TeleportDataReader adopts a new table.
			rosterSource = pd
			rosterSet = {}
			for _, entry in ipairs(pd) do
				local name = type(entry) == "table" and entry.name
				if type(name) == "string" then rosterSet[name] = true end
			end
		end
		return "roster"
	end
	if getPartyManager() then return "manager" end
	if RunService:IsStudio() then return "studio" end
	return nil
end

local function computePartyKey(player, mode)
	if mode == "roster" then
		return rosterSet[player.Name] and 1 or nil
	elseif mode == "manager" then
		return _PartyManager.GetPartyId(player)
	elseif mode == "studio" then
		return 1
	end
	return nil
end

--- Fill ownerShare[owner]; true when the owner shares anything positive.
local function fillOwnerShare(owner)
	local share = ownerShare[owner]
	if not share then
		share = table.create(NSTATS, 0)
		ownerShare[owner] = share
	end
	for slot = 1, NSTATS do share[slot] = 0 end
	local any = false
	for r = 1, #RULE_NAMES do
		local rule = RULE_NAMES[r]
		if _hasRule(owner, rule) then
			local slots = RULE_SLOTS[rule]
			for slot = 1, NSTATS do
				if slots[slot] then
					local v = SHARE * (_getTalentBonus(owner, STATS[slot]) or 0)
					if v > share[slot] then
						share[slot] = v
						any = true
					end
				end
			end
		end
	end
	return any
end

local function markDirty(ownerId, n)
	for k = 1, n do
		if dirtyOwners[k] == ownerId then return n end
	end
	dirtyOwners[n + 1] = ownerId
	return n + 1
end

--- Rewrite member's "aura_<ownerId>" source from the applied state.
local function writeSource(bm, member, ownerId)
	local aOwner, aVal = appliedOwner[member], appliedVal[member]
	local tbl = nil
	if aOwner then
		for slot = 1, NSTATS do
			if aOwner[slot] == ownerId then
				tbl = tbl or {}
				tbl[STATS[slot]] = aVal[slot]
			end
		end
	end
	if tbl then
		bm.SetSourceBonuses(member, sourceName(ownerId), tbl)
	else
		bm.ClearSource(member, sourceName(ownerId))
	end
end

--- Diff bestOwner/bestVal against what member has applied; write changes.
local function applyMember(bm, member)
	local aOwner, aVal = appliedOwner[member], appliedVal[member]
	local nDirty = 0
	for slot = 1, NSTATS do
		local o = bestOwner[slot]
		local newId = o and o.UserId or false
		local newV  = newId and bestVal[slot] or 0
		local oldId = aOwner and aOwner[slot] or false
		local oldV  = aVal and aVal[slot] or 0
		if newId ~= oldId or newV ~= oldV then
			if not aOwner then
				aOwner = table.create(NSTATS, false)
				aVal   = table.create(NSTATS, 0)
				appliedOwner[member] = aOwner
				appliedVal[member]   = aVal
			end
			aOwner[slot], aVal[slot] = newId, newV
			if oldId then nDirty = markDirty(oldId, nDirty) end
			if newId then nDirty = markDirty(newId, nDirty) end
		end
	end
	for k = 1, nDirty do
		writeSource(bm, member, dirtyOwners[k])
		dirtyOwners[k] = nil
	end
end

-- ═══════════════════════════════════════════════════════════
-- TICK
-- ═══════════════════════════════════════════════════════════

local function tick()
	if not resolveTalents() then return end
	local bm = getBonusManager()
	if not bm then return end
	local mode = partyMode()

	-- Pass 1: positions, party keys, owners.
	local ownerCount = 0
	for i = 1, #playerList do
		local p = playerList[i]
		local pos = alivePosition(p)
		local key = (pos and mode) and computePartyKey(p, mode) or nil
		posOf[p], partyKey[p] = pos, key
		if key ~= nil and fillOwnerShare(p) then
			ownerCount += 1
			owners[ownerCount] = p
		end
	end
	for i = ownerCount + 1, #owners do owners[i] = nil end

	-- Pass 2: strongest in-range owner per member and stat.
	for i = 1, #playerList do
		local m = playerList[i]
		for slot = 1, NSTATS do
			bestOwner[slot], bestVal[slot] = false, 0
		end
		local mPos, mKey = posOf[m], partyKey[m]
		if mPos and mKey ~= nil then
			for o = 1, ownerCount do
				local owner = owners[o]
				if owner ~= m and partyKey[owner] == mKey then
					local d = posOf[owner] - mPos
					if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= RANGE_SQ then
						local share = ownerShare[owner]
						for slot = 1, NSTATS do
							if share[slot] > bestVal[slot] then
								bestVal[slot], bestOwner[slot] = share[slot], owner
							end
						end
					end
				end
			end
		end
		applyMember(bm, m)
	end
end

-- ═══════════════════════════════════════════════════════════
-- LIFECYCLE
-- ═══════════════════════════════════════════════════════════

local function onPlayerAdded(player)
	if table.find(playerList, player) then return end
	table.insert(playerList, player)
end

local function onPlayerRemoving(player)
	local idx = table.find(playerList, player)
	if idx then table.remove(playerList, idx) end
	-- As a member: BonusManager drops the leaver's sources itself; never
	-- write to a leaving player (it would re-create their BonusManager entry).
	appliedOwner[player], appliedVal[player] = nil, nil
	ownerShare[player] = nil
	-- As an owner: clear their aura on everyone right away.
	local ownerId = player.UserId
	local bm = getBonusManager()
	for member, aOwner in pairs(appliedOwner) do
		local hit = false
		for slot = 1, NSTATS do
			if aOwner[slot] == ownerId then
				aOwner[slot] = false
				appliedVal[member][slot] = 0
				hit = true
			end
		end
		if hit and bm and member.Parent then
			bm.ClearSource(member, sourceName(ownerId))
		end
	end
end

local started = false
function PartyAura.Start()
	if started then return end
	started = true
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do onPlayerAdded(p) end
	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn("[PartyAura] tick failed:", err)
			end
		end
	end)
end

return PartyAura
