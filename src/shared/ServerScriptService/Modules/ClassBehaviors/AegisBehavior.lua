-- ServerScriptService/Modules/ClassBehaviors/AegisBehavior

local AegisBehavior = {}

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

AegisBehavior.CONFIG = {
	-- Resource Identity
	ResourceName = "Determination",
	MaxResource = 100,
	StartingResource = 25,          -- §29.1

	-- Passive regen
	BaseRegen = 1.0,                -- §29.1: 1.0/s in-combat passive gain

	-- (rest stays the same)
	GainPerHitDealt = 1,            -- §29.1: +1 on hit dealt
	GainPerKill = 3,                -- §29.1: +3 on kill
	MinibossHitMultiplier = 1.5,
	BossHitMultiplier = 2.0,
	GainPerHitReceived = 2,         -- §29.1: +2 on hit received
	MinibossReceivedMultiplier = 1.5,
	BossReceivedMultiplier = 2.0,
	GainPerCrit = 0.5,              -- §29.1: +0.5 on crit
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function AegisBehavior.Init()
end

-- ═══════════════════════════════════════════════════════════
-- RESOURCE RATE (Called every update tick)
-- Returns: resource per second (can be negative)
-- ═══════════════════════════════════════════════════════════

function AegisBehavior.GetResourceRate(player, resourceData)
	local config = AegisBehavior.CONFIG
	return config.BaseRegen
end

-- ═══════════════════════════════════════════════════════════
-- ON HIT DEALT
-- Returns: resource change amount
-- ═══════════════════════════════════════════════════════════

function AegisBehavior.OnHitDealt(player, hitData, resourceData)
	local config = AegisBehavior.CONFIG
	local gain = config.GainPerHitDealt

	-- Tier multiplier
	if hitData.mobTier == "miniboss" then
		gain = gain * config.MinibossHitMultiplier
	elseif hitData.mobTier == "boss" then
		gain = gain * config.BossHitMultiplier
	end

	-- Kill bonus
	if hitData.isKill then
		gain = gain + config.GainPerKill
	end

	-- Crit bonus
	if hitData.isCrit and hitData.critProcs then
		gain = gain + (config.GainPerCrit * hitData.critProcs)
	end

	return gain
end

-- ═══════════════════════════════════════════════════════════
-- ON HIT RECEIVED
-- Returns: resource change amount
-- ═══════════════════════════════════════════════════════════

function AegisBehavior.OnHitReceived(player, hitData, resourceData)
	local config = AegisBehavior.CONFIG
	local gain = config.GainPerHitReceived

	-- Tier multiplier
	if hitData.mobTier == "miniboss" then
		gain = gain * config.MinibossReceivedMultiplier
	elseif hitData.mobTier == "boss" then
		gain = gain * config.BossReceivedMultiplier
	end

	return gain
end

-- ═══════════════════════════════════════════════════════════
-- CALLBACKS
-- ═══════════════════════════════════════════════════════════

function AegisBehavior.OnResourceFull(player)
	print("[AegisBehavior]", player.Name, "Determination is FULL!")
end

function AegisBehavior.OnResourceEmpty(player)
	-- Could prevent skill usage, etc.
end

return AegisBehavior