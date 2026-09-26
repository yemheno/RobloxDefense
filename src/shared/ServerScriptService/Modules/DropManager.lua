-- ServerScriptService/Modules/DropManager
--[[
    Rolls drop tables when mobs are killed and grants rewards.

    API
    ═══
        DropManager.Init()
            – Must be called after CurrencyManager & NetworkManager are loaded.

        DropManager.ProcessKill(player, mobId, mobTier, worldPosition, mobLevel, playerLevel, scaleLevel)
            – Roll the drop table for ONE recipient and queue the result.
              §AGX/X44: called once per eligible party member per kill
              (KillRewardManager), each with an independent roll.

    §AGX/X44 batching: grants and the "LootDrop" notification are
    accumulated per player and flushed every FLUSH_WINDOW seconds — one
    AddMerits + one AddEssence + one LootDrop per player per window,
    instead of per kill per recipient (each AddMerits fires CurrencyUpdate,
    writes a leaderstat and prints). Drops are a direct grant; there are
    no physical drop Instances.

    LootDrop payload (batched):  { drops = { {type, amount}, ... }, kills = n }
      – one entry per currency type, summed over the window. Merits are
        post-meritScalar, pre-MeritBonus (MeritBonus is applied inside
        CurrencyManager.AddMerits, as before).

    Called from KillRewardManager.ProcessKill (via DamageHandler.HandleMobDeath).
]]

local Players = game:GetService("Players")

local DropManager = {}

local Modules = script.Parent

local DropTableConfig = require(Modules:WaitForChild("DropTableConfig"))
local GameModeConfig  = require(Modules:WaitForChild("GameModeConfig"))
local CurrencyManager = nil
local NetworkManager  = nil

-- RunModifiers (lazy-loaded for meritScalar / BountyBoard)
local RunModifiers      = nil
local runModifiersLoaded = false

local function getRunModifiers()
	if not runModifiersLoaded then
		runModifiersLoaded = true
		local rm = Modules:FindFirstChild("RunModifiers")
		if rm then RunModifiers = require(rm) end
	end
	return RunModifiers
end

local RNG = Random.new()

-- Cached difficulty reward multipliers (resolved once from TeleportDataReader + DifficultyConfig)
local cachedDiffMults = nil

local function getDiffMults()
	if cachedDiffMults ~= nil then return cachedDiffMults end
	local tdrModule = Modules:FindFirstChild("TeleportDataReader")
	if tdrModule then
		local ok, TeleportDataReader = pcall(require, tdrModule)
		if ok and TeleportDataReader and TeleportDataReader.GetDifficulty then
			local tierName = TeleportDataReader.GetDifficulty()
			if tierName then
				local dcOk, DifficultyConfig = pcall(function()
					return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("DifficultyConfig"))
				end)
				if dcOk and DifficultyConfig then
					cachedDiffMults = DifficultyConfig.GetDifficulty(tierName)
					return cachedDiffMults
				end
			end
		end
	end
	-- Load failed — return default multipliers (1.0) but don't cache
	-- This allows retry on next call
	return nil
end

-- Cached mode reward multipliers (resolved once from TeleportDataReader)
local cachedModeMults = nil

local function getModeMults()
	if cachedModeMults ~= nil then return cachedModeMults end
	local tdrModule = Modules:FindFirstChild("TeleportDataReader")
	if tdrModule then
		local ok, TeleportDataReader = pcall(require, tdrModule)
		if ok and TeleportDataReader and TeleportDataReader.GetModeId then
			local modeId = TeleportDataReader.GetModeId()
			if modeId then
				local mode = GameModeConfig.GetMode(modeId)
				if mode and mode.rewardMultipliers then
					cachedModeMults = mode.rewardMultipliers
					return cachedModeMults
				end
			end
		end
	end
	-- Load failed — return default multipliers (1.0) but don't cache
	-- This allows retry on next call
	return nil
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DropManager.Init()
	CurrencyManager = require(Modules:WaitForChild("CurrencyManager"))
	NetworkManager  = require(Modules:WaitForChild("NetworkManager"))

	-- Event the client listens to for floating loot text / pickups
	NetworkManager.GetEvent("LootDrop")

	-- §AGX/X44: a leaver's queued window is granted before the data unloads
	-- (best effort — PlayerDataManager's leave-save may already be in flight;
	-- at most FLUSH_WINDOW seconds of drops are at stake).
	Players.PlayerRemoving:Connect(function(player)
		DropManager.FlushPlayer(player)
	end)
end

-- ═══════════════════════════════════════════════════════════
-- DELTA-BASED REWARD MULTIPLIERS (§6)
-- Merits: same curve as XP but never below 50%
-- Essence: softer penalty
-- ═══════════════════════════════════════════════════════════

local MERIT_DELTA_TABLE = {
	{ -math.huge, -11, 0.50 },
	{ -10,  -7,  0.50 },
	{ -6,   -4,  0.75 },
	{ -3,    5,  1.00 },
	{ 6,     8,  0.90 },
	{ 9,    12,  0.65 },
	{ 13,   15,  0.50 },
	{ 16, math.huge, 0.50 },
}

local ESSENCE_DELTA_TABLE = {
	{ -math.huge, -11, 0.30 },
	{ -10,  -7,  0.60 },
	{ -6,   -4,  0.85 },
	{ -3,    5,  1.00 },
	{ 6,     8,  0.95 },
	{ 9,    12,  0.80 },
	{ 13,   15,  0.60 },
	{ 16, math.huge, 0.40 },
}

local function getDeltaMultiplier(delta, table_)
	for _, entry in ipairs(table_) do
		if delta >= entry[1] and delta <= entry[2] then
			return entry[3]
		end
	end
	return 0.50
end

-- ═══════════════════════════════════════════════════════════
-- CORE: ROLL + GRANT
-- ═══════════════════════════════════════════════════════════

--- Roll each entry in the table independently.
--- Amounts scale with mobLevel (+10% per level above 1) UNLESS the entry has noScale=true.
--- `delta` = mobLevel - playerLevel (for §6 reward window).
--- Returns an array of { type, amount } for every successful roll.
function DropManager.RollDrops(dropTable, mobLevel, delta)
	local results = {}
	local levelMultiplier = 1 + ((mobLevel or 1) - 1) * 0.1
	-- §AGX/X44: resolved once per roll instead of per entry — RollDrops
	-- runs once per party member per kill, and an unresolved lookup retries
	-- a pcall(require) each call.
	local modeMults = getModeMults()
	local diffMults = getDiffMults()

	for _, entry in ipairs(dropTable) do
		if RNG:NextNumber() <= entry.chance then
			local baseAmount = RNG:NextInteger(entry.min, entry.max)
			-- noScale=true entries (e.g. Essence) give flat amounts regardless of mob level
			local mult = entry.noScale and 1 or levelMultiplier

			-- Apply delta-based reward window (§6)
			if delta then
				if entry.type == "Merits" then
					mult = mult * getDeltaMultiplier(delta, MERIT_DELTA_TABLE)
				elseif entry.type == "Essence" then
					mult = mult * getDeltaMultiplier(delta, ESSENCE_DELTA_TABLE)
				end
			end

			-- §36: Apply mode-specific reward multiplier (e.g. HordeMode)
			if modeMults then
				if entry.type == "Merits" and modeMults.meritsMult then
					mult = mult * modeMults.meritsMult
				elseif entry.type == "Essence" and modeMults.essenceMult then
					mult = mult * modeMults.essenceMult
				end
			end
			-- Apply difficulty-tier reward multiplier (Hard/Nightmare)
			if diffMults then
				if entry.type == "Merits" and diffMults.meritMult then
					mult = mult * diffMults.meritMult
				elseif entry.type == "Essence" and diffMults.essenceMult then
					mult = mult * diffMults.essenceMult
				end
			end
			local amount = math.max(1, math.floor(baseAmount * mult + 0.5))
			if amount > 0 then
				table.insert(results, {
					type   = entry.type,
					amount = amount,
				})
			end
		end
	end

	return results
end

--- §AGX/X44: meritScalar (BountyBoard) for one Merits drop. Split out of
--- GrantDrop so the batched path applies it exactly once per drop too.
local function applyMeritScalar(amount)
	local rm = getRunModifiers()
	if rm then
		local scalar = rm.GetModifier("meritScalar")
		if scalar and scalar > 0 then
			amount = math.floor(amount * (1 + scalar) + 0.5)
		end
	end
	return amount
end

--- Grant a single drop result to the player immediately (unbatched).
--- ProcessKill no longer uses this (§AGX/X44 queues instead); kept for
--- any direct caller.
function DropManager.GrantDrop(player, drop)
	if not CurrencyManager then
		warn("[DropManager] GrantDrop called before Init — drop lost:", drop.type)
		return
	end
	if drop.type == "Merits" then
		-- Apply meritScalar from RunModifiers (e.g. BountyBoard 2×)
		CurrencyManager.AddMerits(player, applyMeritScalar(drop.amount))
	elseif drop.type == "Essence" then
		CurrencyManager.AddEssence(player, drop.amount)
	else
		-- Future: item drops, materials, etc.
		warn("[DropManager] Unknown drop type:", drop.type)
	end
end

-- ═══════════════════════════════════════════════════════════
-- §AGX/X44: PER-PLAYER BATCH (§SCALE/S5 dirty-flag pattern)
-- ═══════════════════════════════════════════════════════════

local FLUSH_WINDOW = 0.25
local pendingByPlayer = {}  -- [player] = { totals = { [type] = n }, order = { type, ... }, kills = n }
local flushScheduled = false

local function flushEntry(player, entry)
	if not player.Parent then return end
	if CurrencyManager then
		for dropType, amount in pairs(entry.totals) do
			if dropType == "Merits" then
				CurrencyManager.AddMerits(player, amount)
			elseif dropType == "Essence" then
				CurrencyManager.AddEssence(player, amount)
			else
				-- Future: item drops, materials, etc.
				warn("[DropManager] Unknown drop type:", dropType)
			end
		end
	else
		warn("[DropManager] flush before Init — drops lost for", player.Name)
		return
	end
	if NetworkManager then
		local drops = table.create(#entry.order)
		for i, dropType in ipairs(entry.order) do
			drops[i] = { type = dropType, amount = entry.totals[dropType] }
		end
		NetworkManager.FireClient(player, "LootDrop", {
			drops = drops,       -- array of { type, amount }, summed per type
			kills = entry.kills, -- kills that contributed to this window
		})
	end
end

local function flushAll()
	flushScheduled = false
	-- Swap first so grants that re-enter (callbacks) queue into a fresh window.
	local batch = pendingByPlayer
	pendingByPlayer = {}
	for player, entry in pairs(batch) do
		-- One bad grant must not drop everyone else's window.
		local ok, err = pcall(flushEntry, player, entry)
		if not ok then
			warn("[DropManager] flush failed for", player.Name, err)
		end
	end
end

--- §AGX/X44: grant + notify one player's queued window right now.
function DropManager.FlushPlayer(player)
	local entry = pendingByPlayer[player]
	if not entry then return end
	pendingByPlayer[player] = nil
	flushEntry(player, entry)
end

local function queueDrops(player, drops)
	local entry = pendingByPlayer[player]
	if not entry then
		entry = { totals = {}, order = {}, kills = 0 }
		pendingByPlayer[player] = entry
	end
	entry.kills = entry.kills + 1
	for _, drop in ipairs(drops) do
		local amount = drop.amount
		if drop.type == "Merits" then
			amount = applyMeritScalar(amount)  -- once per drop, as GrantDrop did
		end
		if entry.totals[drop.type] == nil then
			entry.totals[drop.type] = 0
			table.insert(entry.order, drop.type)
		end
		entry.totals[drop.type] = entry.totals[drop.type] + amount
	end

	if not flushScheduled then
		flushScheduled = true
		task.delay(FLUSH_WINDOW, flushAll)
	end
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC: PROCESS KILL
-- ═══════════════════════════════════════════════════════════

--- Called once per mob death PER RECIPIENT (§AGX/X44). Rolls the table and
--- queues the result for the batched grant + LootDrop flush.
---@param player     Player   – the recipient (killer or eligible party member)
---@param mobId      string   – e.g. "Zombie", "Ogre"
---@param mobTier    string   – "normal" | "miniboss" | "boss"
---@param worldPos   Vector3  – where the mob died (unused since the batch; kept for API compat)
---@param mobLevel   number?  – mob RewardLevel (for the §6 delta window)
---@param playerLevel number? – recipient's account level (for §6 delta window)
---@param scaleLevel number?  – §AGX/X44: level for the +10%/level amount
---                             scaling; the recipient's own reward level.
---                             Defaults to mobLevel.
function DropManager.ProcessKill(player, mobId, mobTier, worldPos, mobLevel, playerLevel, scaleLevel)
	-- §Dr1: bail if the killer disconnected between the killing-blow
	-- damage event and this drop-processing call. Without this, FireClient
	-- on a leaving player produces console warns and AddMerits/Essence run
	-- on a stale Player object.
	if not player or not player.Parent then return end

	local dropTable = DropTableConfig.GetDropTable(mobId, mobTier)
	if not dropTable or #dropTable == 0 then return end

	local delta = nil
	if mobLevel and playerLevel then
		delta = mobLevel - playerLevel
	end

	-- §AGX/X44: amounts scale with the recipient's own level (scaleLevel),
	-- not the party's highest, so a carried low-level player earns like a solo one.
	local drops = DropManager.RollDrops(dropTable, scaleLevel or mobLevel, delta)
	if #drops == 0 then return end

	-- §AGX/X44: queued; granted + notified on the next FLUSH_WINDOW tick.
	queueDrops(player, drops)
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function DropManager.GetDebugInfo()
	return {
		tierCount      = 3,
		overrideCount  = 0,
	}
end

return DropManager
