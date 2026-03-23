-- ServerScriptService/Modules/StatusEffectTypes
--[[
    ═══════════════════════════════════════════════════════════
    STATUS EFFECT TYPE DEFINITIONS
    ═══════════════════════════════════════════════════════════

    Central reference for every status effect category used
    by skills, weapons, mobs, and environment hazards.

    CATEGORIES
    ──────────
    Buff            Positive timed effect on a PLAYER (stat increase).
    Debuff          Negative timed effect on a MOB (stat decrease).
    DamageOverTime  Periodic damage to a MOB over time (ticks).
    AbnormalStatus  Hard crowd-control on a MOB (Stun, Immobilize, Silence).

    STACKING RULES
    ──────────────
    Each effect definition may specify:
        stackable        (bool)   Can multiple instances coexist?
        maxStacks        (number) Cap on simultaneous stacks.
        refreshDuration  (bool)   Reapplying refreshes all stacks' timers?
        independent      (bool)   Each source tracks its own stack table?

    SCALING MODES
    ─────────────
    "Flat"       → value is used as-is (e.g. +50 CritChance).
    "Percent"    → value is a percentage modifier (e.g. -5% Armor).
    "PerResource"→ value = coefficient × resource spent (e.g. Ultimate skills).

    ═══════════════════════════════════════════════════════════
]]

local StatusEffectTypes = {}

-- ═══════════════════════════════════════════════════════════
-- ENUM-LIKE CONSTANTS
-- ═══════════════════════════════════════════════════════════

StatusEffectTypes.Category = {
	Buff           = "Buff",
	Debuff         = "Debuff",
	DamageOverTime = "DamageOverTime",
	AbnormalStatus = "AbnormalStatus",
}

StatusEffectTypes.ScalingMode = {
	Flat        = "Flat",
	Percent     = "Percent",
	PerResource = "PerResource",
}

-- ═══════════════════════════════════════════════════════════
-- BUFF DEFINITIONS  (positive effects on PLAYERS)
-- ═══════════════════════════════════════════════════════════

StatusEffectTypes.Buffs = {

	DamageReduction = {
		id           = "DamageReduction",
		category     = "Buff",
		stat         = "DamageReduction",       -- StatsManager bonus name
		scalingMode  = "Flat",                   -- amount = flat DR%
		stackable    = false,
		description  = "Reduces incoming damage by a percentage.",
	},

	CritChanceUp = {
		id           = "CritChanceUp",
		category     = "Buff",
		stat         = "CritChance",
		scalingMode  = "Flat",
		stackable    = false,
		description  = "Increases critical hit chance.",
	},

}

-- ═══════════════════════════════════════════════════════════
-- DEBUFF DEFINITIONS  (negative effects on MOBS)
-- ═══════════════════════════════════════════════════════════

StatusEffectTypes.Debuffs = {

	ArmorReduction = {
		id              = "ArmorReduction",
		category        = "Debuff",
		stat            = "Armor",
		scalingMode     = "Percent",             -- -5% per stack
		stackable       = true,
		maxStacks       = 5,
		refreshDuration = true,
		description     = "Reduces target's armor by a percentage per stack.",
	},

	Vulnerability = {
		id              = "Vulnerability",
		category        = "Debuff",
		stat            = "DamageTaken",
		scalingMode     = "Flat",                -- multiplier on incoming damage
		stackable       = false,
		description     = "Target takes increased damage from all sources.",
	},

	Slow = {
		id              = "Slow",
		category        = "Debuff",
		stat            = "MoveSpeed",
		scalingMode     = "Percent",
		stackable       = false,                 -- strongest slow wins
		description     = "Reduces target's movement speed.",
	},

	AttackSpeedDown = {
		id           = "AttackSpeedDown",
		category     = "Debuff",                  -- self-debuff on player (trade-off for powerful buffs)
		stat         = "AttackSpeed",
		scalingMode  = "Percent",
		stackable    = false,
		description  = "Reduces attack speed (trade-off for powerful buffs).",
	},
}

-- ═══════════════════════════════════════════════════════════
-- DAMAGE-OVER-TIME DEFINITIONS
-- ═══════════════════════════════════════════════════════════

StatusEffectTypes.DamageOverTime = {}

-- ═══════════════════════════════════════════════════════════
-- HEALING DEFINITIONS
-- ═══════════════════════════════════════════════════════════

StatusEffectTypes.Healing = {

	Heal = {
		id          = "Heal",
		category    = "Healing",
		scalingMode = "Flat",
		stackable   = false,
		description = "Restores health to the target instantly.",
	},

	HealOverTime = {
		id              = "HealOverTime",
		category        = "Healing",
		scalingMode     = "Flat",
		stackable       = true,
		maxStacks       = 3,
		refreshDuration = true,
		description     = "Restores health periodically over a duration.",
	},

	HealingPowerUp = {
		id           = "HealingPowerUp",
		category     = "Buff",
		stat         = "HealingPercent",
		scalingMode  = "Flat",
		stackable    = false,
		description  = "Increases healing output by a percentage.",
	},
}

-- ═══════════════════════════════════════════════════════════
-- ABNORMAL STATUS DEFINITIONS  (hard CC on MOBS)
-- ═══════════════════════════════════════════════════════════

StatusEffectTypes.AbnormalStatus = {

	Stun = {
		id          = "Stun",
		category    = "AbnormalStatus",
		blocksMove  = true,
		blocksAttack = true,
		blocksSkills = true,
		stackable   = false,                     -- refreshes instead
		description = "Target cannot move, attack, or use skills.",
	},

	Immobilize = {
		id          = "Immobilize",
		category    = "AbnormalStatus",
		blocksMove  = true,
		blocksAttack = false,
		blocksSkills = false,
		stackable   = false,
		description = "Target cannot move but can still attack and use skills.",
	},

	Knockback = {
		id           = "Knockback",
		category     = "AbnormalStatus",
		blocksMove   = true,
		blocksAttack = false,
		blocksSkills = false,
		stackable    = false,
		defaultMode  = "Impulse",                -- ApplyImpulse (mass-dependent); "Flat" via talent override
		description  = "Target is knocked away by a physics impulse. Heavier enemies are displaced less.",
	},

	Pull = {
		id           = "Pull",
		category     = "AbnormalStatus",
		blocksMove   = true,
		blocksAttack = false,
		blocksSkills = false,
		stackable    = false,
		defaultMode  = "Impulse",
		description  = "Target is pulled toward the origin by a physics impulse. Heavier enemies resist more.",
	},

	Taunt = {
		id           = "Taunt",
		category     = "AbnormalStatus",
		blocksMove   = false,
		blocksAttack = false,
		blocksSkills = false,
		overrideBehaviour = true,
		stackable    = false,
		description  = "Target is forced to focus the taunter, ignoring other threats.",
	},
}

-- ═══════════════════════════════════════════════════════════
-- LOOKUP HELPERS
-- ═══════════════════════════════════════════════════════════

-- Lookup tables (built lazily)
local allEffectsById = nil

local function BuildLookup()
	allEffectsById = {}
	for _, group in pairs({
		StatusEffectTypes.Buffs,
		StatusEffectTypes.Debuffs,
		StatusEffectTypes.DamageOverTime,
		StatusEffectTypes.Healing,
		StatusEffectTypes.AbnormalStatus,
	}) do
		for _, def in pairs(group) do
			allEffectsById[def.id] = def
		end
	end
end

function StatusEffectTypes.GetDefinition(effectId)
	if not allEffectsById then BuildLookup() end
	return allEffectsById[effectId]
end

function StatusEffectTypes.IsStackable(effectId)
	local def = StatusEffectTypes.GetDefinition(effectId)
	return def and def.stackable or false
end

function StatusEffectTypes.GetMaxStacks(effectId)
	local def = StatusEffectTypes.GetDefinition(effectId)
	return def and def.maxStacks or 1
end

function StatusEffectTypes.GetCategory(effectId)
	local def = StatusEffectTypes.GetDefinition(effectId)
	return def and def.category or nil
end

return StatusEffectTypes
