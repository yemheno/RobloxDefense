-- ServerScriptService/Modules/DefenseLine/DefenseConfig

local ChapterConfig = require(script.Parent.Parent:WaitForChild("ChapterConfig"))

local DefenseConfig = {}

-- §47.1: Chapter-based defense line max health
local CHAPTER_MAX_HEALTH = {
	[1] = 1500,
	[2] = 3500,
	[3] = 7000,
	[4] = 12000,
}

function DefenseConfig.GetMaxHealth(chapterLevel)
	local chapter = ChapterConfig.GetChapter(chapterLevel or 1)
	return CHAPTER_MAX_HEALTH[chapter] or CHAPTER_MAX_HEALTH[1]
end

-- Legacy static value (default chapter 1); systems should prefer GetMaxHealth()
DefenseConfig.MaxHealth = 1500

-- §47.2: Percentage-based breach damage
-- BreachDamage = round(MaxHP × BasePct × RemainingHpFactor)
-- RemainingHpFactor = 0.5 + 0.5 × currentHpPercent
DefenseConfig.BreachBasePct = {
	normal   = 0.04,
	elite    = 0.08,
	miniboss = 0.14,
	boss     = 0.24,
}

-- ═══════════════════════════════════════════════════════════
-- DAMAGE FORMULA
-- Formula: (BaseDamage + HP*HPFactor + Attack*AttackFactor) * TierMult * GlobalMult * ComboMult
-- ═══════════════════════════════════════════════════════════

-- §47.2: unused; breach damage is percentage-based (BreachBasePct).
-- This table is kept as reference only.
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

-- §47.3: Defense combo rework
DefenseConfig.Combo = {
	Enabled = true,
	Window = 3.0,              -- Seconds
	Factor = 1.20,             -- Each combo level multiplies damage by 1.20x
	MaxLevel = 5,              -- Cap at 5
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