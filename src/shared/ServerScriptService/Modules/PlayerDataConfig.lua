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
-- DERIVED STATS CATALOG  (§T1.2/D6)
-- One entry per derived stat that participates in class scaling.
-- `required = true`  → every class's statDerivation must declare this
--                      key (empty table {} is fine — means class scales
--                      it from base only). ClassConfig.Validate warns
--                      at boot if a class omits a required stat.
-- `required = false` → optional, class-specific scaling. Caster-only
--                      stats like CastTimeReduction live here.
-- Stats that participate ONLY via DerivedBase + Bonus (never per-class
-- primary-scaled) are still listed so ClassConfig.Validate doesn't flag
-- a future class that wants to opt in.
--============================================
PlayerDataConfig.DerivedStats = {
	Health            = { required = true  },
	Damage            = { required = true  },
	Armor             = { required = true  },
	Penetration       = { required = true  },
	CritChance        = { required = true  },
	CritDamage        = { required = true  },  -- empty table = uses class-base CritDamage only
	CooldownReduction = { required = true  },
	StatusResistance  = { required = true  },
	ResourceMax       = { required = true  },
	CastTimeReduction = { required = false },  -- caster-only (Arcanist, LifeSteward); §T1.2/DQ1
	HpRegen           = { required = false },  -- base-only today; classes may opt in
	FlatHpRegen       = { required = false },  -- base-only today; classes may opt in
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
	-- §T10/LIVE1: CastTimeReduction + StatusResistance were missing here,
	-- so BonusManager warn-rejected every talent node granting them — 23
	-- nodes were silently VOID in play (surfaced by the §S5 validator).
	-- Both are real derived stats (DerivedBase + caster statDerivation);
	-- GetTotalStat folds data.Bonus[stat] into them like any flat bonus.
	CastTimeReduction = 0,
	StatusResistance = 0,

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

	-- §T1.2/D5: Classes unlocked at first spawn are now derived from
	-- ClassConfig.Classes[name].default. The literal list below is filled
	-- in at the bottom of this file via ClassConfig.GetDefaultUnlockedClasses().
	-- Authoring a new class is a one-file change in ClassConfig.
	UnlockedClasses = nil,   -- populated below

	-- Equipped accessory slots. Live in production: InventoryManager reads
	-- and writes these; GearRating consumes them for the accessory score.
	-- The accessories themselves live in `Inventory` below (one item per
	-- `itemId` matching AccessoryConfig). These three fields are just the
	-- equipped pointers per slot.
	TrinketId = nil,
	Ring1Id   = nil,
	Ring2Id   = nil,

	-- Meta tracking
	HighestWaveReached = 0,
	TotalPlayTime = 0,

	-- Character appearance (set once during character creation on first login;
	-- editable later through the testing UI / appearance menu).
	--
	-- The cosmetic SYSTEM (accessories, weapons, armor visuals) lives in
	-- Wardrobe + Inventory below. CharacterData holds only the things that
	-- define the underlying avatar: gender, body/head/hair model choice,
	-- and the three color slots applied to that avatar.
	CharacterData = {
		isCreated     = false,    -- true once the player completes character creation
		gender        = nil,      -- "Male" | "Female"

		-- Model slots — 1..N per gender. nil = default (index 1).
		-- Planned: 3 body shapes, 3 head/face models, 3 hair models per gender.
		-- See CharacterConfig.{Body,Head,Hair}ModelCount for current limits.
		bodyModel     = nil,
		headModel     = nil,
		hairModel     = nil,

		-- Colors — palette id from CharacterConfig.<Skin|Hair|Clothing>Colors.
		-- nil = default (first entry of the palette, or the original avatar
		-- color when the palette is empty).
		skinColor     = nil,
		hairColor     = nil,
		clothingColor = nil,

		-- §CC-LEGACY: `preset` was the v0.5 field name for the body slot.
		-- Kept so legacy saves DeepMerge cleanly. New code uses `bodyModel`.
		-- Drop this field in v0.7 once all live saves are touched.
		preset        = nil,
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
-- §AGX/X42: flat 25 Essence at every level (or 1 respec_scroll, which the
-- shop also sells for 25 Essence). Free respec on each ascension boss clear.
--   • The Merit option (20,000 / 50,000) was never read by either respec
--     path, so it is removed rather than wired: Merit income grows ~10×
--     from level 10 to 200, so a Merit price is either a wall early or
--     free late, and it would drain the Essence sink respec exists for.
--   • HIGH was 40: Essence income is flat (not level-scaled), so a level
--     step made respec pricier for no economic reason, and it made the
--     scroll price incoherent (a 25 E scroll would undercut it).
--   • 25 E ≈ 6,250 Merits at the 250:1 anchor (BALANCE_NUMBERS §33), the
--     same as the wipe-revive price.
-- LOW/HIGH are kept so GetRespecCost callers (.essence) keep working.
--============================================
PlayerDataConfig.RESPEC_COSTS = {
	LOW  = { essence = 25 },
	HIGH = { essence = 25 },
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
-- CLASS UNLOCK REQUIREMENTS  (§T1.2/D5)
-- Derived from ClassConfig.Classes[name].unlockRequirements at the
-- bottom of this file. Authoring a new class with a level gate is
-- a one-file change in ClassConfig.
--============================================
PlayerDataConfig.ClassUnlockRequirements = nil  -- populated below

--============================================
-- ADMIN ALLOWLIST
-- Read by PlaceBootstrap.IsAdmin (the single admin check, §AGX/SEC), which
-- only grants admin inside Studio: allowlisted UserIds, the owner of a
-- user-owned game, or Studio test accounts. Live servers have no admin
-- surface at all. Add / remove developer UserIds here.
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

--============================================
-- DERIVED FROM ClassConfig  (§T1.2/D5)
--
-- ClassConfig.Classes is the single source of truth for class identity,
-- including which classes are granted by default and which carry unlock
-- gates. We pull both lists out here so the rest of the codebase keeps
-- reading PlayerDataConfig.UnlockedClasses / .ClassUnlockRequirements
-- exactly as before — only the source of those values has moved.
--
-- Boot-order note: this require happens AFTER all of PlayerDataConfig's
-- own fields are populated, so a ClassConfig that pcall-requires
-- PlayerDataConfig (e.g. its Validate task) sees a fully-populated
-- table.
--============================================
local ClassConfig = require(script.Parent:WaitForChild("ClassConfig"))
PlayerDataConfig.AccountDefaults.UnlockedClasses = ClassConfig.GetDefaultUnlockedClasses()
PlayerDataConfig.ClassUnlockRequirements        = ClassConfig.GetUnlockRequirementsMap()

return PlayerDataConfig