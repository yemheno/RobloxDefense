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
	HpRegen           = 0.5,  -- % of max HP regenerated per second (base: 0.5 %/s)
	FlatHpRegen       = 0,    -- flat HP regenerated per second
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
	UncappedDamageReduction = 0,  -- DR from ultimates (e.g. Aegis Battle Beast); bypasses StatCap

	-- Flat bonuses on top of primary-derived stats (from weapons / buffs / skills)
	CritChance  = 0,
	CritDamage  = 0,
	Armor       = 0,
	Penetration = 0,

	-- Primary stat bonuses from talents / items (applied before class stat derivation)
	BonusMIG = 0,
	BonusVIT = 0,
	BonusPRE = 0,
	BonusMAG = 0,
	BonusRSV = 0,

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

	-- Healing
	HealingPower = 0,       -- Flat bonus healing
	HealingPercent = 0,     -- % healing output modifier
	HpRegen = 0,            -- bonus % HP regen per second (stacks with DerivedBase)
	FlatHpRegen = 0,        -- bonus flat HP regen per second

	-- Class-specific from weapons
	Determination = 0,      -- Aegis resource
	Aether = 0,             -- Arcanist resource
	KillerInstinct = 0,     -- Hunter resource
	LifeEnergy = 0,         -- LifeSteward resource
	TauntDuration = 0,      -- Aegis utility
}

--============================================
-- STAT CAPS
--============================================
PlayerDataConfig.StatCaps = {
	CritChance = { min = 0, max = 200 },
	CritDamage = { min = 1.0, max = 1.80 },
	DamageReduction = { min = 0, max = 75 },  -- cap raised from 60 → 75 (§DR-2)
	Penetration = { min = 0, max = 60 },
	CooldownReduction = { min = 0, max = 40 },
	CastTimeReduction = { min = 0, max = 40 },
	Lifesteal = { min = 0, max = 25 },
	AttackSpeed = { min = -50, max = 75 },
	StatusResistance = { min = 0, max = 60 },
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

	-- Bonus talent points granted outside of levelling (e.g. admin grants, future quests)
	BonusTalentPoints = 0,

	-- Talent tree (allocated node ids stored as { [nodeId] = true })
	AllocatedTalents = {},

	-- Classes unlocked from start
	-- All currently available classes are playable from day one.
	-- Future classes added later will carry their own level requirements.
	UnlockedClasses = { "Aegis", "Hunter", "Arcanist", "LifeSteward" },

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
		gender    = nil,       -- "Male" or "Female"
		preset    = nil,       -- body-type index (currently always 1)
		skinColor = nil,       -- skin color id from CharacterConfig.SkinColors (e.g. "skin_fair")
		skins    = {},        -- { [skinId] = true }  owned skin IDs
		equippedSkin = nil,   -- currently worn skin ID (nil = class default)
	},

	-- Wardrobe: cosmetic ownership + equipped slots (managed by CosmeticManager)
	Wardrobe = {
		owned = {},               -- { [cosmeticId] = true }
		equipped = {              -- one item per slot
			headgear = "none",    -- headgear cosmetic id
			outfit   = nil,       -- outfit cosmetic id (nil = class default)
		},
	},

	-- Achievements: unlock history + lifetime stats (managed by AchievementManager)
	-- stats fields: totalKills, killsByMobId, killsByTier, hitsDelivered, hitsReceived,
	--               meritsCollected, wavesSurvived, highestWave, totalDamageDealt,
	--               totalDamageTaken, criticalHits, bestCombo
	Achievements = {
		unlocked = {},            -- { [achievementId] = unixTimestamp }
		stats    = {},            -- see AchievementManager.DefaultStats() for all fields
	},

	-- §11: Bound Chapter Tokens (never tradable — used for ascension, tier gates, role validation)
	BoundTokens = {},             -- { [tokenId] = quantity } e.g. { AscensionCrest_50 = 1, TankSeal_1 = 2 }

	-- Inventory: accessories, consumables, tokens
	Inventory = {},               -- { { itemId, quantity, metadata? }, ... }
	-- §4.3: RespecTokens counter removed — respecs now consume the
	-- `respec_scroll` inventory item. Legacy saves still carrying
	-- Account.RespecTokens are cleaned up by the deprecated-key sweep
	-- in PlayerDataManager/init.lua.

	-- Daily login tracking
	DailyLogin = {
		lastClaimDate = 0,        -- os.time() of last daily claim
		streak        = 0,        -- consecutive-day streak
		totalDays     = 0,        -- lifetime days claimed
	},

	-- Quest state (persistent across sessions)
	Quests = {
		active    = {},           -- { [questId] = { progress = N, ... } }
		completed = {},           -- { [questId] = true }
	},

	-- Leaderboard tracking
	Leaderboard = {
		EssenceSpent  = 0,
		RobuxSpent    = 0,
		GearScore     = 0,
	},

	-- Player keybind overrides (serialized EnumItem names; empty = use defaults)
	Keybindings = {},
}

--============================================
-- CLASS DATA TEMPLATE (created per class)
--============================================
PlayerDataConfig.ClassDataTemplate = {
	-- Points allocated per primary stat (MIG/VIT/PRE/MAG/RSV)
	Allocated = {},   -- { MIG=0, VIT=0, PRE=0, MAG=0, RSV=0 }

	-- Armor System (managed by ArmorManager)
	EquippedArmor = nil,    -- { armorId, level, xp, refinement, tier, bonuses }
	OwnedArmors = {},       -- { [armorId] = armorInstance, ... }

	-- NEW: Weapon System
	EquippedWeapon = nil,  -- { weaponId, level, xp, refinement, tier, bonuses }
	OwnedWeapons = {},     -- { [weaponId] = weaponInstance, ... }

	-- §5: Class Mastery (accumulated while at chapter cap)
	MasteryXP = 0,
	MasteryMilestones = {},  -- { [milestoneId] = true } — unlocked milestones

	-- Class achievements (future - separate from account XP)
	ClassAchievements = {},
}

-- Helper to create fresh class data
function PlayerDataConfig.CreateClassData()
	local data = {
		Allocated = {},   -- { MIG=0, VIT=0, PRE=0, MAG=0, RSV=0 }
		EquippedArmor = nil,
		OwnedArmors = {},
		EquippedWeapon = nil,
		OwnedWeapons = {},
		MasteryXP = 0,
		MasteryMilestones = {},
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
	temper = 0,                   -- Temper pity counter (§14), resets on floor reached
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

-- XP CURVE (§4 — Chapter-based XP formula)
-- b = floor((Level - 1) / 50)   — chapter index (0-based)
-- p = (Level - 1) % 50          — position within chapter
-- XPReq(Level) = round(120 × 3.2^b × (1 + 0.05p)^1.9)
-- Resets perceived steepness at 51, 101, 151 intentionally.

function PlayerDataConfig.GetXPForLevel(level)
	level = math.max(1, level or 1)
	local b = math.floor((level - 1) / 50)
	local p = (level - 1) % 50
	return math.floor(120 * (3.2 ^ b) * ((1 + 0.05 * p) ^ 1.9) + 0.5)
end

function PlayerDataConfig.GetAvailablePoints(level)
	return (level - 1) * PlayerDataConfig.PointsPerLevel
end

--============================================
-- RESPEC COST (§18)
-- Before level 100: 25 Essence or 20,000 Merits
-- Level 100+: 40 Essence or 50,000 Merits
-- Free respec on each ascension boss clear
--============================================
PlayerDataConfig.RESPEC_COSTS = {
	LOW  = { essence = 25, merits = 20000 },
	HIGH = { essence = 40, merits = 50000 },
}

function PlayerDataConfig.GetRespecCost(level)
	if (level or 1) >= 100 then
		return PlayerDataConfig.RESPEC_COSTS.HIGH
	end
	return PlayerDataConfig.RESPEC_COSTS.LOW
end

--============================================
-- CLASS SWITCHING
--============================================
PlayerDataConfig.ClassSwitchCooldown = 30  -- Seconds (production value)

--============================================
-- CLASS UNLOCK REQUIREMENTS
-- {} = known class, available from day one
-- { requiredLevel = N } = locks behind a player level
-- Classes absent from this table are treated as unknown by UnlockClass.
--============================================
PlayerDataConfig.ClassUnlockRequirements = {
	-- Current classes: available immediately (no requirements)
	Aegis       = {},
	Hunter      = {},
	Arcanist    = {},
	LifeSteward = {},
	-- Future classes added below with their requirements, e.g.:
	-- Warden  = { requiredLevel = 30 },
}

--============================================
-- ADMIN ALLOWLIST
-- Server-side guard: player.UserId must match one of these OR game.CreatorId.
-- Add / remove developer UserIds here. This is the SINGLE SOURCE OF TRUTH used
-- by LaneDefenseMain, LobbyMain, and AdminTesting. Do NOT maintain a separate
-- copy in any other file.
--============================================
PlayerDataConfig.AdminUserIds = {
	[4700259512] = true,  -- AstralitoCL (developer)
	-- Add more developer UserIds below:
	-- [XXX] = true,
}

--============================================
-- MATCHMAKING / PARTY CONSTANTS
--
-- §L11: SINGLE source of truth for level-gap rules. Both
-- PartyManager (invite-time level check) and TeleportManager
-- (pre-launch validation) MUST read from here so they can't drift.
--============================================
PlayerDataConfig.Matchmaking = {
	MaxLevelGap = 10,   -- max level difference between any two party members
}

return PlayerDataConfig