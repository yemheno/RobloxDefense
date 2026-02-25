-- ServerScriptService/Modules/ProjectileConfig

local ProjectileConfig = {}

--[[
    ═══════════════════════════════════════════════════════════
    PROJECTILE DEFINITIONS
    ═══════════════════════════════════════════════════════════
    
    Each projectile defines:
    - template: Name of Part in ReplicatedStorage.Projectiles
    - speed: How fast it travels
    - lifetime: Max seconds before despawn
    - hitType: What happens on impact
    - hitParams: Parameters for hit behavior
    
    ═══════════════════════════════════════════════════════════
    HIT TYPES:
    
    "Single"  - Damages one target, projectile destroyed
    "Pierce"  - Damages target, continues through (limited hits)
    "Circle"  - AoE circle damage on impact point
    "Cone"    - AoE cone damage on impact point
    
    ═══════════════════════════════════════════════════════════
]]

ProjectileConfig.Projectiles = {

	-- Basic arrow (Archer default)
	Arrow = {
		template = "BasicProjectile",
		speed = 60,
		lifetime = 3,
		hitType = "Single",
		hitParams = {},
	},

	-- Fireball (Mage default) - Explodes on impact!
	Fireball = {
		template = "BasicProjectile",  -- TODO: Create FireballProjectile
		speed = 40,
		lifetime = 4,
		hitType = "Circle",
		hitParams = {
			radius = 8,
			damageMultiplier = 0.75,  -- 75% damage to AoE targets
		},
	},

	-- Piercing arrow (Archer ability)
	PiercingArrow = {
		template = "BasicProjectile",
		speed = 70,
		lifetime = 3,
		hitType = "Pierce",
		hitParams = {
			maxHits = 3,
			damageReduction = 0.2,  -- Each hit does 20% less
		},
	},

	-- Frost bolt (Mage ability) - Single target
	FrostBolt = {
		template = "BasicProjectile",
		speed = 50,
		lifetime = 3,
		hitType = "Single",
		hitParams = {
			damageMultiplier = 1.5,  -- 150% damage
			-- Future: slowEffect = 0.5, slowDuration = 2
		},
	},

	-- Explosive shot (cone on impact)
	ExplosiveShot = {
		template = "BasicProjectile",
		speed = 45,
		lifetime = 3,
		hitType = "Cone",
		hitParams = {
			range = 10,
			angle = 60,
			damageMultiplier = 0.6,
		},
	},
}

-- Default projectile per class
ProjectileConfig.ClassDefaults = {
	Mage = "Fireball",
	Archer = "Arrow",
}

-- Fallback if class not defined
ProjectileConfig.DefaultProjectile = "Arrow"

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function ProjectileConfig.GetProjectile(projectileName)
	return ProjectileConfig.Projectiles[projectileName]
end

function ProjectileConfig.GetClassProjectile(className)
	local projectileName = ProjectileConfig.ClassDefaults[className] 
		or ProjectileConfig.DefaultProjectile
	return projectileName, ProjectileConfig.Projectiles[projectileName]
end

function ProjectileConfig.IsValidProjectile(projectileName)
	return ProjectileConfig.Projectiles[projectileName] ~= nil
end

return ProjectileConfig