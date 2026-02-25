-- ServerScriptService/Modules/ClassBehaviors/HunterBehavior

local HunterBehavior = {}

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION (Tune these for balance!)
-- ═══════════════════════════════════════════════════════════

HunterBehavior.CONFIG = {
	-- Passive regen
	BaseRegen = 8,                  -- Per second (Hunters regen fastest)

	-- On hit dealt
	GainPerHitDealt = 1,            -- Small gain per hit

	-- Crit bonus (Hunters are crit-focused!)
	GainPerCrit = 3,                -- Good bonus per crit proc
	MultiCritBonus = 2,             -- Extra per crit after first (multi-crit reward)

	-- On kill
	GainPerKill = 2,

	-- On hit received
	LossPerHitReceived = 1,         -- Small penalty for getting hit
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function HunterBehavior.Init()
	print("[HunterBehavior] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- RESOURCE RATE
-- ═══════════════════════════════════════════════════════════

function HunterBehavior.GetResourceRate(player, resourceData)
	local config = HunterBehavior.CONFIG

	-- Fast constant regen
	return config.BaseRegen
end

-- ═══════════════════════════════════════════════════════════
-- ON HIT DEALT
-- ═══════════════════════════════════════════════════════════

function HunterBehavior.OnHitDealt(player, hitData, resourceData)
	local config = HunterBehavior.CONFIG
	local gain = config.GainPerHitDealt

	-- Crit bonus (Hunter specialty!)
	if hitData.isCrit and hitData.critProcs then
		gain = gain + config.GainPerCrit

		-- Multi-crit bonus
		if hitData.critProcs > 1 then
			gain = gain + (config.MultiCritBonus * (hitData.critProcs - 1))
		end
	end

	-- Kill bonus
	if hitData.isKill then
		gain = gain + config.GainPerKill
	end

	return gain
end

-- ═══════════════════════════════════════════════════════════
-- ON HIT RECEIVED
-- ═══════════════════════════════════════════════════════════

function HunterBehavior.OnHitReceived(player, hitData, resourceData)
	local config = HunterBehavior.CONFIG

	-- Small penalty for getting hit (encourages kiting/positioning)
	return -config.LossPerHitReceived
end

-- ═══════════════════════════════════════════════════════════
-- CALLBACKS
-- ═══════════════════════════════════════════════════════════

function HunterBehavior.OnResourceFull(player)
	-- Focus full
end

function HunterBehavior.OnResourceEmpty(player)
	-- Low focus
end

return HunterBehavior
