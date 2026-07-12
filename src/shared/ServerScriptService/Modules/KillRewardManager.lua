-- ServerScriptService/Modules/KillRewardManager
--[[
    Centralised kill-reward module.

    Every reward that fires when a mob dies is funnelled through this single
    module so that the order/conditions are explicit and no duplicate paths
    exist.

    Reward pipeline (in order):
      1. Player XP  (shared across nearby party members via BonusExpSystem)
      2. Weapon XP  (killer only)
      3. Armor XP   (killer only)
      4. Loot drops  (DropManager — merits, essence, items)
      5. Kill callbacks (AchievementManager and any other subscribers)
      6. Client notification (MobDeath)

    XP flows exclusively through PlayerDataManager.AddExperience →
    PlayerLevelSystem.AddExperience, which applies XPBonus + BonusExpSystem
    multipliers.  No other XP path should be used.
]]

local KillRewardManager = {}

local Players            = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = script.Parent

-- Eagerly loaded
local NetworkManager    = require(Modules:WaitForChild("NetworkManager"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
local Config            = require(Modules:WaitForChild("PlayerDataConfig"))
local GameModeConfig    = require(Modules:WaitForChild("GameModeConfig"))

-- §PB-D5: WeaponManager is now lazy-loaded instead of injected by the
-- place bootstrap. KillRewardManager is a leaf module; WeaponManager
-- doesn't require it, so there's no cycle. Used to grant weapon XP to
-- DPS classes on mob kills.
local _WeaponManager = nil
local function getWeaponManager()
    if _WeaponManager ~= nil then return _WeaponManager end
    local ok, mod = pcall(function()
        return require(Modules:WaitForChild("WeaponManager"))
    end)
    if ok and mod then _WeaponManager = mod else _WeaponManager = false end
    return _WeaponManager or nil
end

-- Lazily loaded (avoid circular deps / optional systems)
local DropManager        = nil
local dropManagerLoaded  = false
local RunModifiers       = nil
local runModifiersLoaded = false

-- DifficultyConfig lives in ReplicatedStorage (shared read)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DifficultyConfig  = nil

-- Cached mode data (set once at init or first use)
local cachedModeId        = nil
local cachedRewardMults   = nil  -- { xpMult, meritsMult, essenceMult } or nil

local function getModeRewardMultipliers()
	if cachedRewardMults ~= nil then return cachedRewardMults end
	-- Resolve mode ID from TeleportDataReader
	local tdrModule = Modules:FindFirstChild("TeleportDataReader")
	if tdrModule then
		local ok, TeleportDataReader = pcall(require, tdrModule)
		if ok and TeleportDataReader and TeleportDataReader.GetModeId then
			cachedModeId = TeleportDataReader.GetModeId()
		end
	end
	if cachedModeId then
		local mode = GameModeConfig.GetMode(cachedModeId)
		if mode and mode.rewardMultipliers then
			cachedRewardMults = mode.rewardMultipliers
			return cachedRewardMults
		end
	end
	cachedRewardMults = false  -- false = no multipliers, don't re-check
	return nil
end

--- Lazy-load DifficultyConfig from ReplicatedStorage and return the xpMult
--- for the active difficulty tier (Normal=1.0, Hard=1.25, Nightmare=1.5).
local function getDifficultyXPMult()
	if not DifficultyConfig then
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local mod = shared and shared:FindFirstChild("DifficultyConfig")
		if mod then
			local ok, result = pcall(require, mod)
			if ok then DifficultyConfig = result end
		end
	end
	if not DifficultyConfig then return 1 end
	-- Resolve tier each time via TeleportDataReader (don't cache)
	local tdrModule = Modules:FindFirstChild("TeleportDataReader")
	local diffTier = "Normal"
	if tdrModule then
		local ok, TeleportDataReader = pcall(require, tdrModule)
		if ok and TeleportDataReader and TeleportDataReader.GetDifficulty then
			diffTier = TeleportDataReader.GetDifficulty() or "Normal"
		end
	end
	local tier = DifficultyConfig.GetDifficulty(diffTier)
	return tier.xpMult or 1
end

-- ═══════════════════════════════════════════════════════════
-- PARTY XP SHARING
-- ═══════════════════════════════════════════════════════════

local XP_SHARE_RANGE_STUDS = 200

local function getRootPosition(player)
	local character = player and player.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function isWithinRange(player, position, range)
	local p = getRootPosition(player)
	if not p then return false end
	return (p - position).Magnitude <= range
end

local function getPartyMembersFromTeleportData()
	local modules = ServerScriptService:FindFirstChild("Modules")
	if not modules then return nil end

	local tdrModule = modules:FindFirstChild("TeleportDataReader")
	if not tdrModule then return nil end

	local ok, TeleportDataReader = pcall(require, tdrModule)
	if not ok or not TeleportDataReader then return nil end
	if not TeleportDataReader.GetPartyData then return nil end

	local partyData = TeleportDataReader.GetPartyData()
	if type(partyData) ~= "table" or #partyData == 0 then return nil end

	local members = {}
	for _, entry in ipairs(partyData) do
		local name = entry and entry.name
		if type(name) == "string" then
			local p = Players:FindFirstChild(name)
			if p then table.insert(members, p) end
		end
	end
	return members
end

local function getPartyMembersFromPartyManager(player)
	local modules = ServerScriptService:FindFirstChild("Modules")
	if not modules then return nil end

	local pmModule = modules:FindFirstChild("PartyManager")
	if not pmModule then return nil end

	local ok, PartyManager = pcall(require, pmModule)
	if not ok or not PartyManager then return nil end
	if not PartyManager.GetPartyMembers then return nil end

	local members = PartyManager.GetPartyMembers(player)
	if type(members) ~= "table" or #members == 0 then return nil end
	return members
end

local function getEligibleXPRecipients(killer, mobPosition)
	local partyMembers = getPartyMembersFromTeleportData()
	if not partyMembers then
		partyMembers = getPartyMembersFromPartyManager(killer)
	end
	if not partyMembers then
		return { killer }
	end

	local recipients = {}
	for _, member in ipairs(partyMembers) do
		-- §T2/Z2 (DQ-T2A): DEAD players earn nothing — anti AFK-carry.
		-- KnockedDown still earns: it's a seconds-long combat state the
		-- player fought their way into, not AFK leeching.
		if member and member.Parent
			and member:GetAttribute("DeathState") ~= "Dead"
			and isWithinRange(member, mobPosition, XP_SHARE_RANGE_STUDS) then
			table.insert(recipients, member)
		end
	end

	if #recipients == 0 then
		return { killer }
	end
	return recipients
end

-- ═══════════════════════════════════════════════════════════
-- XP REWARD FORMULA (§6 — Personal XP Reward Window)
-- ═══════════════════════════════════════════════════════════

-- Delta-based XP multiplier table — symmetric ±5 full / 20% decay / 0 at ±10
local XP_DELTA_TABLE = {
	-- { minDelta, maxDelta, multiplier }
	{ -math.huge, -10, 0.00 },
	{ -9,  -9,  0.20 },
	{ -8,  -8,  0.40 },
	{ -7,  -7,  0.60 },
	{ -6,  -6,  0.80 },
	{ -5,   5,  1.00 },
	{ 6,    6,  0.80 },
	{ 7,    7,  0.60 },
	{ 8,    8,  0.40 },
	{ 9,    9,  0.20 },
	{ 10, math.huge, 0.00 },
}

local function getXPDeltaMultiplier(delta)
	for _, entry in ipairs(XP_DELTA_TABLE) do
		if delta >= entry[1] and delta <= entry[2] then
			return entry[3]
		end
	end
	return 0.10
end

function KillRewardManager.GetXPReward(player, mobLevel, mobTier)
	local playerLevel = PlayerDataManager.GetAccountData(player, "Level") or 1
	mobLevel = math.max(1, mobLevel or 1)

	local xpNeeded = Config.GetXPForLevel(playerLevel)
	-- ~33 kills to reach next level at any level (wave bonuses push first level-up to wave 3)
	local baseFraction = 0.03

	local tierMult = ({
		normal   = 1,
		miniboss = 8,
		boss     = 25,
	})[mobTier] or 1

	-- §6: Personal XP reward window (delta-based)
	local delta = mobLevel - playerLevel
	local deltaMult = getXPDeltaMultiplier(delta)

	local baseXP = math.max(1, math.ceil(xpNeeded * baseFraction))
	local xp = math.floor(baseXP * tierMult * deltaMult)

	-- §36: Apply mode-specific XP multiplier (e.g. HordeMode ×0.45)
	local mults = getModeRewardMultipliers()
	if mults and mults.xpMult then
		xp = math.floor(xp * mults.xpMult)
	end

	-- Apply difficulty tier XP multiplier (Hard ×1.25, Nightmare ×1.5)
	local diffMult = getDifficultyXPMult()
	if diffMult ~= 1 then
		xp = math.floor(xp * diffMult)
	end

	-- §DangerBonus: accumulated danger bonus scales kill XP
	-- (positive danger = more XP, negative = less; capped by RunModifiers)
	if not runModifiersLoaded then
		runModifiersLoaded = true
		local rm = Modules:FindFirstChild("RunModifiers")
		if rm then RunModifiers = require(rm) end
	end
	if RunModifiers then
		local danger = RunModifiers.GetTotalDangerBonus()
		if danger ~= 0 then
			xp = math.max(0, math.floor(xp * (1 + danger)))
		end
	end

	return xp
end

-- ═══════════════════════════════════════════════════════════
-- KILL REWARD CALLBACKS
-- ═══════════════════════════════════════════════════════════

local killCallbacks = {}

--- Subscribe to kill events (used by AchievementManager, etc.)
function KillRewardManager.OnMobKilled(callback)
	table.insert(killCallbacks, callback)
end

-- ═══════════════════════════════════════════════════════════
-- MAIN ENTRY POINT — called by DamageHandler.HandleMobDeath
-- ═══════════════════════════════════════════════════════════

function KillRewardManager.ProcessKill(player, mob, damageResult)
	-- RewardLevel is frozen at run start; falls back to Level if not set.
	local mobLevel = mob and (mob:GetAttribute("RewardLevel") or mob:GetAttribute("Level")) or 1
	local mobId    = damageResult.mobId   or "Unknown"
	local mobTier  = damageResult.mobTier or "normal"
	local mobPosition = mob and mob:GetPivot().Position or nil

	-- ── 1. Player XP (shared across nearby party members) ──────────────
	local recipients = mobPosition and getEligibleXPRecipients(player, mobPosition) or { player }
	local partySize  = math.max(1, #recipients)

	for _, member in ipairs(recipients) do
		-- Compute XP per-recipient using their own level for the delta calculation
		local memberXP = KillRewardManager.GetXPReward(member, mobLevel, mobTier)
		local perPlayer = memberXP / partySize
		if perPlayer > 0 then
			-- Single canonical XP path: PlayerDataManager → PlayerLevelSystem
			-- PlayerDataManager.AddExperience now fires PlayerInfoUpdate automatically.
			PlayerDataManager.AddExperience(member, perPlayer)
		end
	end

	-- ── 2. Weapon XP — DPS role classes only; gated inside WeaponManager ──
	--    Role check is in WeaponXPSystem.AddKillXP (tank/healer classes get 0).
	do
		local mobType = mobTier == "miniboss" and "Mini"
			or mobTier == "boss" and "Boss"
			or "Normal"
		local wm = getWeaponManager()
		if wm then
			wm.GrantKillXP(player, mobLevel, mobType)
		end
	end

	-- ── 3. Loot drops (merits, essence, items via DropManager) ─────────
	-- (Armor XP was removed — only weapons level up.)
	if not dropManagerLoaded then
		dropManagerLoaded = true
		local dm = Modules:FindFirstChild("DropManager")
		if dm then DropManager = require(dm) end
	end
	if DropManager then
		local playerLevel = PlayerDataManager.GetAccountData(player, "Level") or 1
		DropManager.ProcessKill(player, mobId, mobTier, mobPosition, mobLevel, playerLevel)
	end

	-- ── 4b. Merit scalar bonus (BountyBoard) ──────────────────────────
	-- meritScalar is now consumed directly inside DropManager.GrantDrop,
	-- which applies the multiplier to actual drop amounts for a true 2×.
	-- No additional flat bonus needed here.

	-- ── 5. Kill callbacks (AchievementManager, etc.) ───────────────────
	for _, cb in ipairs(killCallbacks) do
		task.spawn(cb, player, {
			mobId    = mobId,
			mobTier  = mobTier,
			mobLevel = mobLevel,
		})
	end

	-- ── 6. Client notification ─────────────────────────────────────────
	if mobPosition then
		NetworkManager.FireAllClients("MobDeath", {
			mobId      = mobId,
			mobTier    = mobTier,
			killerName = player.Name,
			position   = mobPosition,
		})
	end
end

return KillRewardManager
