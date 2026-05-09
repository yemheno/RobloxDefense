-- ServerScriptService/Modules/DropManager
--[[
    Rolls drop tables when mobs are killed and grants rewards.

    API
    ═══
        DropManager.Init()
            – Must be called after CurrencyManager & NetworkManager are loaded.

        DropManager.ProcessKill(player, mobId, mobTier, worldPosition)
            – Roll the drop table, grant currencies, fire "LootDrop" to killer.

    Called from DamageHandler.HandleMobDeath.
]]

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

	print("[DropManager] Initialized")
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
			local modeMults = getModeMults()
			if modeMults then
				if entry.type == "Merits" and modeMults.meritsMult then
					mult = mult * modeMults.meritsMult
				elseif entry.type == "Essence" and modeMults.essenceMult then
					mult = mult * modeMults.essenceMult
				end
			end
			-- Apply difficulty-tier reward multiplier (Hard/Nightmare)
			local diffMults = getDiffMults()
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

--- Grant a single drop result to the player.
function DropManager.GrantDrop(player, drop)
	if not CurrencyManager then
		warn("[DropManager] GrantDrop called before Init — drop lost:", drop.type)
		return
	end
	if drop.type == "Merits" then
		local amount = drop.amount
		-- Apply meritScalar from RunModifiers (e.g. BountyBoard 2×)
		local rm = getRunModifiers()
		if rm then
			local scalar = rm.GetModifier("meritScalar")
			if scalar and scalar > 0 then
				amount = math.floor(amount * (1 + scalar) + 0.5)
			end
		end
		CurrencyManager.AddMerits(player, amount)
	elseif drop.type == "Essence" then
		CurrencyManager.AddEssence(player, drop.amount)
	else
		-- Future: item drops, materials, etc.
		warn("[DropManager] Unknown drop type:", drop.type)
	end
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC: PROCESS KILL
-- ═══════════════════════════════════════════════════════════

--- Called once per mob death.  Rolls the table, grants rewards, notifies client.
---@param player     Player   – the killer
---@param mobId      string   – e.g. "Zombie", "Ogre"
---@param mobTier    string   – "normal" | "miniboss" | "boss"
---@param worldPos   Vector3  – where the mob died (for floating text)
---@param mobLevel   number?  – mob / wave level for scaling (default 1)
---@param playerLevel number? – killer's account level (for §6 delta window)
function DropManager.ProcessKill(player, mobId, mobTier, worldPos, mobLevel, playerLevel)
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

	local drops = DropManager.RollDrops(dropTable, mobLevel, delta)
	if #drops == 0 then return end

	-- Grant every drop
	for _, drop in ipairs(drops) do
		DropManager.GrantDrop(player, drop)
	end

	-- Notify the killer's client so it can show floating loot text
	NetworkManager.FireClient(player, "LootDrop", {
		mobId    = mobId,
		mobTier  = mobTier,
		position = worldPos,
		drops    = drops,   -- array of { type, amount }
	})
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
