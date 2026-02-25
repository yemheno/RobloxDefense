-- ServerScriptService/Modules/ClassConfig
-- Base game classes: Aegis (melee), Arcanist (AoE ranged), Hunter (pierce ranged)

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

-- Default Roblox Animation IDs (R15)
local ANIM = {
	Slash = "rbxassetid://522635514",      -- Sword slash
	Punch = "rbxassetid://507777826",      -- Punch
	Stomp = "rbxassetid://507771019",      -- Jump land
	Lunge = "rbxassetid://522638767",      -- Lunge forward
	Cheer = "rbxassetid://507770677",      -- Arms up
}

ClassConfig.Classes = {

	-- ═══════════════════════════════════════════════════════
	-- MELEE CLASSES
	-- ═══════════════════════════════════════════════════════

	Aegis = {
		name = "Aegis",
		description = "A sturdy frontline fighter with high health and defense.",

		-- Attack Type
		ranged = false,
		attackShape = "Cone",
		shapeParams = {
			range = 10,
			angle = 120,
		},

		-- Attack Timing (weapon will override when equipped)
		baseAttackSpeed = 1.5,  -- attacks per second (cooldown = 0.67s)

		-- Animations
		animations = {
			basicAttack = ANIM.Slash,
		},

		-- Innate Bonuses
		innateBonuses = {
			HealthPercent = 10,
			DamageReduction = 5,
		},

		-- Primary stat → derived stat derivation
		-- formula: derived = DerivedBase + sum((PrimaryBase + allocated) * coeff) + flatBonus
		statDerivation = {
			Health            = { VIT = 15 },
			Damage            = { MIG = 3.0 },
			Armor             = { MIG = 1.0 },
			Penetration       = { MIG = 0.3 },
			CritChance        = { PRE = 0.4 },
			CritDamage        = { PRE = 0.008 },
			CooldownReduction = { RSV = 0.5 },
			StatusResistance  = { RSV = 1.0 },
			ResourceMax       = { RSV = 2.0 },
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

		-- Attack Type
		ranged = true,
		projectile = {
			type = "AoE",
			shape = "Circle",
			shapeParams = {
				range = 8,  -- AoE radius (weapon can modify)
			},
			primaryMultiplier = 1.5,  -- Direct hit gets 150% damage
			speed = 40,
			lifetime = 4,
		},

		-- Attack Timing (weapon will override when equipped)
		baseAttackSpeed = 1.0,  -- attacks per second (cooldown = 1.0s) - slower but powerful

		-- Animations
		animations = {
			basicAttack = ANIM.Lunge,  -- Casting motion
		},

		-- Innate Bonuses
		innateBonuses = {
			BonusDamage = 10,
			DamagePercent = 15,
		},

		-- Primary stat → derived stat derivation
		statDerivation = {
			Health            = { VIT = 10 },
			Damage            = { MAG = 4.0 },          -- Mage scales damage via MAG
			Armor             = { MIG = 0.3 },
			Penetration       = { MAG = 0.5 },          -- Magic penetration via MAG
			CritChance        = { PRE = 0.3 },
			CritDamage        = { PRE = 0.006, MAG = 0.004 },
			CastTimeReduction = { PRE = 0.4 },          -- PRE reduces cast time for Mage
			CooldownReduction = { RSV = 0.6 },
			StatusResistance  = { RSV = 0.8 },
			ResourceMax       = { MAG = 3.0, RSV = 1.0 },
		},

		-- Future
		resource = "Mana",
	},

	Hunter = {
		name = "Hunter",
		gendered = true,  -- display name uses CharacterConfig.ClassTitles (Hunter / Huntress)
		description = "A deadly marksman who fells enemies with precision and speed.",

		-- Attack Type
		ranged = true,
		projectile = {
			type = "Pierce",
			maxHits = 1,        
			damageReduction = 0,
			speed = 60,
			lifetime = 3,
		},

		-- Attack Timing (weapon will override when equipped)
		baseAttackSpeed = 2.5,  -- attacks per second (cooldown = 0.4s) - rapid fire!

		-- Animations
		animations = {
			basicAttack = ANIM.Lunge,  -- Drawing bow motion
		},

		-- Innate Bonuses
		innateBonuses = {
			CritChance = 15,
			CritDamage = 0.5,
			MovementSpeed = 10,
		},

		-- Primary stat → derived stat derivation
		statDerivation = {
			Health            = { VIT = 10 },
			Damage            = { MIG = 1.5, PRE = 2.0 }, -- Split physical + precision scaling
			Armor             = { MIG = 0.5 },
			Penetration       = { PRE = 0.5 },
			CritChance        = { PRE = 1.2 },           -- Best crit scaling
			CritDamage        = { PRE = 0.018 },         -- Best crit damage scaling
			CooldownReduction = { RSV = 0.5 },
			StatusResistance  = { RSV = 0.7 },
			ResourceMax       = { RSV = 2.0 },
		},

		-- Future
		resource = "Focus",
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