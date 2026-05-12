-- ServerScriptService/Modules/ClassBehaviors/HunterBehavior

local HunterBehavior = {}

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION (Tune these for balance!)
-- ═══════════════════════════════════════════════════════════

HunterBehavior.CONFIG = {
	-- Resource Identity
	ResourceName = "Killer Instinct",
	MaxResource = 100,
	StartingResource = 15,          -- §29.1

	-- Passive regen
	BaseRegen = 3,                  -- §29.1: 3.0/s in-combat passive gain

	-- On hit dealt
	GainPerHitDealt = 0.6,          -- §29.1: +0.6 on hit dealt

	-- Crit bonus (Hunters are crit-focused!)
	GainPerCrit = 2,                -- §29.1: +2 on crit
	MultiCritBonus = 0,             -- §29.1: no multi-crit bonus specified

	-- On kill
	GainPerKill = 3,                -- §29.1: +3 on kill

	-- On hit received
	LossPerHitReceived = 2,         -- §29.1: -2 on hit received
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function HunterBehavior.Init()
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
