-- ServerScriptService/Modules/ClassBehaviors/ArcanistBehavior

local ArcanistBehavior = {}

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION (Tune these for balance!)
-- ═══════════════════════════════════════════════════════════

ArcanistBehavior.CONFIG = {
	-- Passive regen
	BaseRegen = 5,                  -- Per second (Arcanists regen fast)

	-- Combat regen modifier
	InCombatRegenMultiplier = 0.5,  -- Regen slower in combat
	CombatTimeout = 3,              -- Seconds since last action = "out of combat"

	-- On hit dealt
	GainPerHitDealt = 0,            -- Arcanists don't gain from hits
	CostPerHit = 0,                 -- Could cost mana per attack (future)

	-- On kill
	GainPerKill = 5,                -- Mana refund on kill
	MinibossKillBonus = 10,
	BossKillBonus = 25,

	-- On hit received (Arcanists are punished for taking damage)
	LossPerHitReceived = 2,         -- Lose mana when hit
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
