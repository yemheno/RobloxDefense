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

--[[
    PRECEDENCE ORDER (highest to lowest):
    1. ClassWeapons/<Class>Weapons.lua  — weapon-specific overrides
    2. ClassConfig.lua                  — class-level defaults (.projectile table)
    3. ProjectileConfig.lua (this file) — global fallback templates

    ClassManager.GetProjectileConfig() resolves in this order:
    it tries the equipped weapon first, then the class default, then
    falls back to ProjectileConfig.ClassDefaults[className].
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
		template = "BasicProjectile",  -- FUTURE: swap for a dedicated FireballProjectile model when art is ready
		speed = 40,
		lifetime = 4,
		hitType = "Circle",
		hitParams = {
			radius = 8,
			damageMultiplier = 0.75,  -- 75% damage to AoE targets
		},
	},

	-- §T2/Z8: PiercingArrow / FrostBolt / ExplosiveShot below are
	-- FUTURE-CONTENT templates — no class or skill references them yet.
	-- Kept deliberately as authoring examples for new ranged content.

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
-- §T2/Z8: Aegis and LifeSteward are INTENTIONALLY absent — melee /
-- support classes have no basic-attack projectile. Don't re-flag this
-- in future audits.
ProjectileConfig.ClassDefaults = {
	Arcanist = "Fireball",
	Hunter = "Arrow",
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