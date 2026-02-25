-- ServerScriptService/Modules/DefenseLine/DefenseConfig

local DefenseConfig = {}

-- ═══════════════════════════════════════════════════════════
-- HEALTH
-- ═══════════════════════════════════════════════════════════

DefenseConfig.MaxHealth = 1000

-- ═══════════════════════════════════════════════════════════
-- DAMAGE FORMULA
-- Formula: (BaseDamage + HP*HPFactor + Attack*AttackFactor) * TierMult * GlobalMult * ComboMult
-- ═══════════════════════════════════════════════════════════

DefenseConfig.Damage = {
	BaseDamage = 10,
	HPFactor = 0.5,
	AttackFactor = 1.0,
	GlobalMultiplier = 1.0,

	TierMultipliers = {
		normal = 1.0,
		miniboss = 2.0,
		boss = 5.0,
	},
}

-- ═══════════════════════════════════════════════════════════
-- COMBO SYSTEM
-- ═══════════════════════════════════════════════════════════

DefenseConfig.Combo = {
	Enabled = true,
	Window = 3.0,              -- Seconds - hits within this window stack
	Factor = 1.5,              -- Each combo level multiplies damage by this
	MaxLevel = 10,             -- Cap combo level
	DecayRate = 1,             -- Combo levels lost per second after window
}

-- ═══════════════════════════════════════════════════════════
-- DETECTION
-- ═══════════════════════════════════════════════════════════

DefenseConfig.Detection = {
	Range = 5,                 -- How close mob must be to defense line
	CheckInterval = 0.2,       -- How often to check for mobs
}

-- ═══════════════════════════════════════════════════════════
-- ANIMATION
-- ═══════════════════════════════════════════════════════════

DefenseConfig.Animation = {
	Enabled = true,
	Duration = 0.5,            -- Seconds before mob is destroyed
	Style = "Dissolve",        -- "Dissolve", "Explode", "Shrink", "Fade"
}

-- ═══════════════════════════════════════════════════════════
-- VISUAL FEEDBACK
-- ═══════════════════════════════════════════════════════════

DefenseConfig.Visuals = {
	Enabled = true,
	HealthyColor = Color3.fromRGB(0, 170, 0),
	DamagedColor = Color3.fromRGB(170, 170, 0),
	CriticalColor = Color3.fromRGB(170, 0, 0),
	CriticalThreshold = 0.25,  -- 25% HP
	DamagedThreshold = 0.50,   -- 50% HP

	-- Flash on hit
	FlashEnabled = true,
	FlashColor = Color3.fromRGB(255, 0, 0),
	FlashDuration = 0.15,
}

-- ═══════════════════════════════════════════════════════════
-- REGEN
-- ═══════════════════════════════════════════════════════════

DefenseConfig.Regen = {
	Enabled = false,
	PerSecond = 0,
	Delay = 5,                 -- Seconds after last damage before regen
}

-- ═══════════════════════════════════════════════════════════
-- HELPER: Deep copy for modification
-- ═══════════════════════════════════════════════════════════

function DefenseConfig.Get(section)
	if section then
		return DefenseConfig[section]
	end
	return DefenseConfig
end

return DefenseConfig