-- ServerScriptService/Modules/ClassBehaviors/ArcanistBehavior

local ArcanistBehavior = {}

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION (Tune these for balance!)
-- ═══════════════════════════════════════════════════════════

ArcanistBehavior.CONFIG = {
	-- Resource Identity
	ResourceName = "Aether",
	MaxResource = 100,
	StartingResource = 35,          -- §29.1

	-- Passive regen
	BaseRegen = 4,                  -- Out-of-combat; in-combat = 4 × 0.5 = 2.0/s (§29.1)

	-- Combat regen modifier
	InCombatRegenMultiplier = 0.5,  -- §29.1: 2.0/s in combat
	CombatTimeout = 3,              -- Seconds since last action = "out of combat"

	-- On hit dealt
	GainPerHitDealt = 0,            -- §29.1: no hit gain
	CostPerHit = 0,

	-- On kill
	GainPerKill = 6,                -- §29.1: +6 on kill
	MinibossKillBonus = 15,         -- §29.1: +15 on miniboss kill
	BossKillBonus = 30,             -- §29.1: +30 on boss kill

	-- On hit received (Arcanists are punished for taking damage)
	LossPerHitReceived = 3,         -- §29.1: -3 on hit received
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function ArcanistBehavior.Init()
	print("[ArcanistBehavior] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- RESOURCE RATE
-- ═══════════════════════════════════════════════════════════

function ArcanistBehavior.GetResourceRate(player, resourceData)
	local config = ArcanistBehavior.CONFIG
	local regen = config.BaseRegen

	-- Slower regen in combat
	local inCombat = math.min(resourceData.timeSinceHitDealt, resourceData.timeSinceHitReceived) < config.CombatTimeout

	if inCombat then
		regen = regen * config.InCombatRegenMultiplier
	end

	return regen
end

-- ═══════════════════════════════════════════════════════════
-- ON HIT DEALT
-- ═══════════════════════════════════════════════════════════

function ArcanistBehavior.OnHitDealt(player, hitData, resourceData)
	local config = ArcanistBehavior.CONFIG
	local gain = config.GainPerHitDealt

	-- Kill bonus (mana refund)
	if hitData.isKill then
		if hitData.mobTier == "boss" then
			gain = gain + config.BossKillBonus
		elseif hitData.mobTier == "miniboss" then
			gain = gain + config.MinibossKillBonus
		else
			gain = gain + config.GainPerKill
		end
	end

	return gain
end

-- ═══════════════════════════════════════════════════════════
-- ON HIT RECEIVED
-- ═══════════════════════════════════════════════════════════

function ArcanistBehavior.OnHitReceived(player, hitData, resourceData)
	local config = ArcanistBehavior.CONFIG

	-- Mages LOSE mana when hit (punishes bad positioning)
	return -config.LossPerHitReceived
end

-- ═══════════════════════════════════════════════════════════
-- CALLBACKS
-- ═══════════════════════════════════════════════════════════

function ArcanistBehavior.OnResourceFull(player)
	-- Mana full
end

function ArcanistBehavior.OnResourceEmpty(player)
	-- Out of mana! Could disable abilities
	print("[ArcanistBehavior]", player.Name, "is OUT OF MANA!")
end

return ArcanistBehavior
