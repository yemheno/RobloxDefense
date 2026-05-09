-- ServerScriptService/Modules/ClassConfig
-- Base game classes: Aegis (melee), Arcanist (AoE ranged), Hunter (pierce ranged), Life Steward (healer)

local ClassConfig = {}

--[[
    ═══════════════════════════════════════════════════════════
    CLASS DEFINITIONS
    ═══════════════════════════════════════════════════════════

    Attack Types are CLASS-LOCKED:
    - Aegis:    Melee (uses attackShape)
    - Arcanist: AoE Projectile (fireball explodes)
    - Hunter:   Pierce Projectile (arrow goes through)
    
    Weapons (future) modify STATS, not attack type.
    Weapons will override baseAttackSpeed when equipped.
    
    ═══════════════════════════════════════════════════════════
    PROJECTILE TYPES:
    
    "Pierce" - Goes through targets
        maxHits: number (1 = single target)
        damageReduction: number (0-1, reduction per hit)
    
    "AoE" - Explodes on impact using AttackShapes
        shape: "Circle", "Cone", "Ring", "Rectangle"
        shapeParams: { range, angle, width, innerRadius }
        primaryMultiplier: number (bonus for direct hit)
    
    ═══════════════════════════════════════════════════════════
]]

-- Animation IDs are centralised in AnimationConfig (single source of truth).
-- Lazily resolved at first access to avoid circular-require at load time.
local _AnimationConfig = nil
local function getAnim(className)
	if not _AnimationConfig then
		_AnimationConfig = require(script.Parent:WaitForChild("AnimationConfig"))
	end
	local classAnims = _AnimationConfig.Player.Classes[className]
	return classAnims and classAnims.basicAttack
end

ClassConfig.Classes = {

	-- ═══════════════════════════════════════════════════════
	-- MELEE CLASSES
	-- ═══════════════════════════════════════════════════════

	Aegis = {
		name = "Aegis",
		description = "A sturdy frontline fighter with high health and defense.",

		-- Weapon XP role: determines which combat actions grant weapon XP.
		--   "tank"    → XP from incoming damage (pre-DR)
		--   "healer"  → XP from HP healed + revives + buffs
		--   "support" → XP from buffs + revives (+ partial healing)
		--   "dps"     → XP from mob kills (default for offensive classes)
		weaponXPRole = "tank",

		-- Attack Type
		ranged = false,
		attackShape = "Cone",
		shapeParams = {
			range = 10,
			angle = 120,
		},

		-- Attack Timing (weapon will override when equipped)
		baseAttackSpeed = 1.4,  -- attacks per second (cooldown = 0.71s)

		-- Animations (resolved from AnimationConfig)
		animations = {
			basicAttack = getAnim("Aegis"),
		},

		-- Innate Bonuses
		innateBonuses = {
			HealthPercent = 10,
			DamageReduction = 5,
		},

		-- Primary stat → derived stat derivation
		-- formula: derived = DerivedBase + sum((PrimaryBase + allocated) * coeff) + flatBonus
		statDerivation = {
			Health            = { VIT = 15.0 },
			Damage            = { MIG = 3.0 },
			Armor             = { MIG = 1.0 },
			Penetration       = { MIG = 0.25 },
			CritChance        = { PRE = 0.22 },
			CritDamage        = {},          -- PRE removed; crit damage uses class base only
			CooldownReduction = { RSV = 0.45 },
			StatusResistance  = { RSV = 1.0 },
			ResourceMax       = { RSV = 1.5 },
		},

		-- Future
		resource = "Determination",
	},

	-- ═══════════════════════════════════════════════════════
	-- RANGED CLASSES
	-- ═══════════════════════════════════════════════════════

	Arcanist = {
		name = "Arcanist",
		gendered = true,  -- display name uses CharacterConfig.ClassTitles (Arcanist / Arcaness)
		description = "A powerful spellcaster who bends elemental forces to obliterate foes.",

		weaponXPRole = "dps",

		-- Attack Type
		ranged = true,
		projectile = {
			type = "AoE",
			shape = "Circle",
			shapeParams = {
				range = 6.5,
			},
			primaryMultiplier = 1.2,
			splashMultiplier = 0.8,
			speed = 45,
			lifetime = 4,
		},

		-- Attack Timing (weapon will override when equipped)
		baseAttackSpeed = 1.0,  -- attacks per second (cooldown = 1.0s) - slower but powerful

		-- Animations
		animations = {
			basicAttack = getAnim("Arcanist"),
		},

		-- Innate Bonuses
		innateBonuses = {
			BonusDamage = 10,
			DamagePercent = 15,
		},

		-- Primary stat → derived stat derivation
		statDerivation = {
			Health            = { VIT = 10.0 },
			Damage            = { MAG = 4.0 },
			Armor             = { MIG = 0.3 },
			Penetration       = { MAG = 0.45 },
			CritChance        = { PRE = 0.18 },
			CritDamage        = { MAG = 0.001 }, -- PRE removed; only MAG scales crit damage
			CastTimeReduction = { PRE = 0.35 },
			CooldownReduction = { RSV = 0.55 },
			StatusResistance  = { RSV = 0.8 },
			ResourceMax       = { MAG = 2.5, RSV = 1.0 },
		},

		-- Future
		resource = "Aether",
	},

	Hunter = {
		name = "Hunter",
		gendered = true,  -- display name uses CharacterConfig.ClassTitles (Hunter / Huntress)
		description = "A deadly marksman who fells enemies with precision and speed.",

		weaponXPRole = "dps",

		-- Attack Type
		ranged = true,
		projectile = {
			type = "Pierce",
			maxHits = 3,
			damageReduction = 0.15,
			minDamageFraction = 0.70,
			speed = 70,
			lifetime = 3,
		},

		-- Attack Timing (weapon will override when equipped)
		baseAttackSpeed = 2.2,  -- attacks per second (cooldown = 0.4s) - rapid fire!

		-- Animations
		animations = {
			basicAttack = getAnim("Hunter"),
		},

		-- Innate Bonuses
		innateBonuses = {
			CritChance = 10,
			CritDamage = 0.15,
			MovementSpeed = 8,
		},

		-- Primary stat → derived stat derivation
		statDerivation = {
			Health            = { VIT = 10.0 },
			Damage            = { MIG = 1.5, PRE = 2.0 },
			Armor             = { MIG = 0.5 },
			Penetration       = { PRE = 0.4 },
			CritChance        = { PRE = 0.65 },
			CritDamage        = {},          -- PRE removed; crit damage uses class base only
			CooldownReduction = { RSV = 0.45 },
			StatusResistance  = { RSV = 0.7 },
			ResourceMax       = { RSV = 1.5 },
		},

		-- Future
		resource = "Killer Instinct",
	},

	-- ═══════════════════════════════════════════════════════
	-- SUPPORT CLASSES
	-- ═══════════════════════════════════════════════════════

	LifeSteward = {
		name = "Life Steward",
		gendered = true,   -- "Life Steward" / "Life Stewardess"
		description = "A devoted healer who channels the power of nature to mend allies and cleanse afflictions.",

		weaponXPRole = "healer",

		-- Attack Type — ranged nature bolt (small single-target projectile)
		ranged = true,
		projectile = {
			type = "Pierce",
			maxHits = 1,
			damageReduction = 0,
			speed = 35,
			lifetime = 3,
		},

		-- Attack Timing — slow auto-attack (healer, not a DPS)
		baseAttackSpeed = 0.85,

		-- Animations
		animations = {
			basicAttack = getAnim("LifeSteward"),
		},

		-- Innate Bonuses — healing and survivability focus
		innateBonuses = {
			HealingPercent = 15,
			HealthPercent  = 10,
		},

		-- Primary stat → derived stat derivation
		-- MAG drives healing power; VIT for survivability; RSV for CDR + resources
		statDerivation = {
			Health            = { VIT = 12.0 },
			Damage            = { MAG = 2.5 },
			Armor             = { MIG = 0.5 },
			Penetration       = { MAG = 0.25 },
			CritChance        = { PRE = 0.18 },
			CritDamage        = {},          -- PRE removed; crit damage uses class base only
			CastTimeReduction = { PRE = 0.25 },
			CooldownReduction = { RSV = 0.65 },
			StatusResistance  = { RSV = 1.0 },
			ResourceMax       = { MAG = 1.5, RSV = 1.5 },
		},

		resource = "Life Energy",
	},
}

-- Default class for new players
ClassConfig.DefaultClass = "Aegis"

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

--[[
    GetClassTitle(className, gender)
    Returns the display name for a class, respecting gender where applicable.
    Falls back to class name for non-gendered classes.
    Requires CharacterConfig if you want gendered names.
]]
function ClassConfig.GetClassTitle(className, gender)
	local classData = ClassConfig.Classes[className]
	if not classData then return className end
	if not classData.gendered then return classData.name end

	-- Delegate to CharacterConfig if available
	local Modules = script.Parent
	local charConfigModule = Modules:FindFirstChild("CharacterConfig")
	if charConfigModule then
		local CharacterConfig = require(charConfigModule)
		return CharacterConfig.GetClassTitle(className, gender)
	end

	-- Fallback: masculine name
	return classData.name
end

function ClassConfig.GetClassNames()
	local names = {}
	for className, _ in pairs(ClassConfig.Classes) do
		table.insert(names, className)
	end
	table.sort(names)
	return names
end

function ClassConfig.IsValidClass(className)
	return ClassConfig.Classes[className] ~= nil
end

function ClassConfig.GetClass(className)
	return ClassConfig.Classes[className]
end

return ClassConfig