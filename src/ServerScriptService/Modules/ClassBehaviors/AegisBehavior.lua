-- ServerScriptService/Modules/ClassBehaviors/AegisBehavior

local AegisBehavior = {}

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

AegisBehavior.CONFIG = {
	-- Resource Identity
	ResourceName = "Determination",
	MaxResource = 100,
	StartingResource = 50,

	-- Passive regen
	BaseRegen = 2,                  -- Per second (always)

	-- (rest stays the same)
	GainPerHitDealt = 0.5,
	GainPerKill = 2,
	MinibossHitMultiplier = 1.5,
	BossHitMultiplier = 2.0,
	GainPerHitReceived = 1,
	MinibossReceivedMultiplier = 1.5,
	BossReceivedMultiplier = 2.0,
	GainPerCrit = 0.5,
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function AegisBehavior.Init()
	print("[AegisBehavior] Initialized")
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