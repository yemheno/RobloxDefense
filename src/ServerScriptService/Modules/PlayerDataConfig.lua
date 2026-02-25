-- PlayerDataConfig

local PlayerDataConfig = {}

--============================================
-- PRIMARY STATS (players spend points on these)
--============================================
--[[
	MIG  Might               Raw muscular force, forged through battle
	                         → Physical Damage, Armor
	VIT  Vitality            The endurance to weather any storm
	                         → Max Health
	PRE  Precision           Fine motor mastery that turns near-hits into perfect strikes
	                         → Critical Chance; Mages: faster casting
	MAG  Magical Attunement  Resonance with arcane forces beyond mortal understanding
	                         → Magic Damage, Healing Power, Resource Depth
	RSV  Resolve             Unbreakable will that pushes through pain and fear
	                         → Cooldown Reduction, Status Resistance, Resource Max
]]
PlayerDataConfig.PrimaryStats = { "MIG", "VIT", "PRE", "MAG", "RSV" }

-- Starting value for each primary before any allocation
PlayerDataConfig.PrimaryBase = {
	MIG = 5,
	VIT = 5,
	PRE = 5,
	MAG = 5,
	RSV = 5,
}

--============================================
-- DERIVED STAT BASES
-- Flat baseline before primary contributions.
-- Each class's statDerivation adds on top.
--============================================
PlayerDataConfig.DerivedBase = {
	Health            = 100,
	Damage            = 10,
	Armor             = 0,
	Penetration       = 0,
	CritChance        = 5,    -- 5% base crit for every class
	CritDamage        = 1.5,  -- 1.5x base crit damage for every class
	CastTimeReduction = 0,    -- % cast time reduction (PRE → Mage)
	CooldownReduction = 0,    -- % cooldown reduction (RSV → all)
	StatusResistance  = 0,    -- % status effect resistance (RSV → all)
	ResourceMax       = 0,    -- Flat resource cap bonus (RSV/MAG → all)
}

--============================================
-- BONUS STATS (from innate, equipment, skills - NOT allocated)
--============================================
PlayerDataConfig.BonusStats = {
	-- Offensive
	BonusDamage = 0,
	DamagePercent = 0,

	-- Defensive
	BonusHealth = 0,
	HealthPercent = 0,
	DamageReduction = 0,

	-- Flat bonuses on top of primary-derived stats (from weapons / buffs / skills)
	CritChance  = 0,
	CritDamage  = 0,
	Armor       = 0,
	Penetration = 0,

	-- Utility
	AoESize = 0,
	MovementSpeed = 0,
	MeritBonus = 0,
	XPBonus = 0,

	-- Weapon bonus stats (applied from weapon bonuses)
	FlatAttack = 0,
	AttackSpeed = 0,
	SkillDamage = 0,
	Thorns = 0,
	Lifesteal = 0,
	CooldownReduction = 0,

	-- Class-specific from weapons
	Determination = 0,      -- Aegis resource
	Mana = 0,               -- Arcanist resource
	Focus = 0,              -- Hunter resource
	TauntDuration = 0,      -- Aegis utility
}

--============================================
-- STAT CAPS
--============================================
PlayerDataConfig.StatCaps = {
	CritChance = { min = 0, max = 500 },
	DamageReduction = { min = 0, max = 75 },
	CooldownReduction = { min = 0, max = 50 },
	Lifesteal = { min = 0, max = 30 },
	AttackSpeed = { min = -50, max = 100 },  -- Can't go below 50% base speed
}

--============================================
-- ACCOUNT DEFAULTS (shared across all classes)
--============================================
PlayerDataConfig.AccountDefaults = {
	-- Currencies
	Merits = 0,
	Essence = 0,

	-- Character progression
	Level = 1,
	Experience = 0,

	-- Classes unlocked from start
	-- Aegis is the starter class. Hunter (lv10) and Arcanist (lv20) unlock via progression.
	UnlockedClasses = { "Aegis" },

	-- Universal equipment (future)
	TrinketId = nil,
	Ring1Id = nil,
	Ring2Id = nil,

	-- Meta tracking
	HighestWaveReached = 0,
	TotalPlayTime = 0,

	-- Character appearance (set once during character creation on first login)
	CharacterData = {
		isCreated = false,    -- false until the player completes character creation
		gender   = nil,       -- "Male" or "Female"
		preset   = nil,       -- 1, 2, or 3  (body type)
		skins    = {},        -- { [skinId] = true }  owned skin IDs
		equippedSkin = nil,   -- currently worn skin ID (nil = class default)
	},
}

--============================================
-- CLASS DATA TEMPLATE (created per class)
--============================================
PlayerDataConfig.ClassDataTemplate = {
	-- Points allocated per primary stat (MIG/VIT/PRE/MAG/RSV)
	Allocated = {},   -- { MIG=0, VIT=0, PRE=0, MAG=0, RSV=0 }

	-- Class-specific equipment
	ArmorId = nil,

	-- NEW: Weapon System
	EquippedWeapon = nil,  -- { weaponId, level, xp, refinement, tier, bonuses }
	OwnedWeapons = {},     -- { [weaponId] = weaponInstance, ... }

	-- Class achievements (future - separate from account XP)
	ClassAchievements = {},
}

-- Helper to create fresh class data
function PlayerDataConfig.CreateClassData()
	local data = {
		Allocated = {},   -- { MIG=0, VIT=0, PRE=0, MAG=0, RSV=0 }
		ArmorId = nil,
		EquippedWeapon = nil,
		OwnedWeapons = {},
		ClassAchievements = {},
	}

	-- Initialize all primary stat allocations to 0
	for _, primaryStat in ipairs(PlayerDataConfig.PrimaryStats) do
		data.Allocated[primaryStat] = 0
	end

	return data
end

--============================================
-- WEAPON INSTANCE TEMPLATE
-- Reference for what EquippedWeapon contains
--============================================
--[[
WeaponInstance = {
	weaponId = "SwordAndShield",  -- References WeaponRegistry
	level = 1,                    -- 1 to maxLevel (floor(playerLevel/10)*10)
	xp = 0,                       -- Current XP toward next level
	refinement = 0,               -- +0 to +15
	tier = 1,                     -- Tier I to XII
	bonuses = {                   -- Rolled random bonuses
		{ stat = "critChance", value = 7 },
		{ stat = "flatAttack", value = 15 },
	},
}
]]

--============================================
-- PROGRESSION
--============================================
PlayerDataConfig.PointsPerLevel = 1  -- Each level grants 1 stat point

function PlayerDataConfig.GetXPForLevel(level)
	return level * 100
end

function PlayerDataConfig.GetAvailablePoints(level)
	return (level - 1) * PlayerDataConfig.PointsPerLevel
end

--============================================
-- CLASS SWITCHING
--============================================
PlayerDataConfig.ClassSwitchCooldown = 30  -- Seconds

--============================================
-- CLASS UNLOCK REQUIREMENTS (future)
-- nil = free from start
--============================================
PlayerDataConfig.ClassUnlockRequirements = {
	Aegis    = nil,                          -- starter class, always unlocked
	Hunter   = { requiredLevel = 10 },
	Arcanist = { requiredLevel = 20 },
	-- Future examples:
	-- Hunter = { requiredClasses = { Aegis = 10 } },
	-- Arcanist = { requiredClasses = { Hunter = 20 } },
	-- Sage = { requiredClasses = { Mage = 20 } },
	-- Shaman = { requiredClasses = { Sage = 40, Mage = 40 } },
}

return PlayerDataConfig