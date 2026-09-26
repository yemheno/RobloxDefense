-- ServerScriptService/Modules/ClassWeapons/AegisWeapon

local AegisWeapons = {}

AegisWeapons.CLASS = "Aegis"

AegisWeapons.Weapons = {
	--============================================
	-- SWORD AND SHIELD (Starter Weapon)
	-- Balanced offense/defense, cone attack
	--============================================
	["SwordAndShield"] = {
		id = "SwordAndShield",
		name = "Sword & Shield",
		class = "Aegis",
		description = "A balanced weapon for frontline defenders. Wide cone attacks.",
		modelId = "DefaultSword",
		weaponSlot = 1,

		-- Element for basic attacks (skill attacks use their own skill.element)
		-- "None" = physical / untyped — always neutral
		element = "None",

		-- Base Stats (level 1, +0 refinement, Tier I)
		baseAttack = 14,
		baseAttackSpeed = 1.4,  -- attacks per second

		-- Attack Shape
		attackShape = "Cone",
		shapeParams = {
			range = 8,
			angle = 120,
		},

		-- Refinement: +1.8 ATK per level
		refinementAttackBonus = 1.8,

		-- Random Bonus Pool (ordered by tier unlock)
		-- Tier I: indices 1-3
		-- Tier II: index 4
		-- Tier III: index 5
		-- etc.
		bonusPool = {
			-- Tier I (basic)
			{ stat = "critChance", min = 1, max = 10 },
			{ stat = "critDamage", min = 5, max = 25 },
			{ stat = "flatAttack", min = 5, max = 20 },

			-- Tier II
			{ stat = "attackSpeed", min = 1, max = 8 },

			-- Tier III
			{ stat = "determination", min = 5, max = 15 },

			-- Tier IV
			{ stat = "damageReduction", min = 2, max = 8 },

			-- Tier V
			{ stat = "skillDamage", min = 3, max = 12 },

			-- Tier VI
			{ stat = "tauntDuration", min = 5, max = 20 },

			-- Tier VII
			{ stat = "lifesteal", min = 1, max = 5 },

			-- Tier VIII
			{ stat = "aoeSize", min = 3, max = 10 },

			-- Tier IX
			{ stat = "movementSpeed", min = 2, max = 8 },

			-- Tier X
			{ stat = "cooldownReduction", min = 2, max = 10 },

			-- Tier XI
			{ stat = "bonusHealth", min = 50, max = 200 },

			-- Tier XII (all unlocked)
			{ stat = "thorns", min = 5, max = 15 },
		},

		-- Visual (references ReplicatedStorage.Weapons.SwordAndShield)
		modelName = "SwordAndShield",
	},

	--============================================
	-- TOWER SHIELD (Unlock via Achievement)
	-- Defensive focus, wide rectangle attack
	--============================================
	["TowerShield"] = {
		id = "TowerShield",
		name = "Tower Shield",
		class = "Aegis",
		description = "A massive shield for maximum protection. Wide sweeping attacks.",
		modelId = "DefaultSword",
		weaponSlot = 2,

		-- Element for basic attacks (skill attacks use their own skill.element)
		element = "None",

		-- Base Stats (lower ATK, lower speed, but wider area)
		baseAttack = 12,
		baseAttackSpeed = 1.2,

		-- Attack Shape (wide rectangle)
		attackShape = "Rectangle",
		shapeParams = {
			range = 10,
			width = 12,
		},

		-- Refinement: +1 ATK per level (defensive weapon)
		refinementAttackBonus = 1,

		-- Random Bonus Pool (more defensive options)
		bonusPool = {
			-- Tier I (basic defensive)
			{ stat = "damageReduction", min = 2, max = 10 },
			{ stat = "bonusHealth", min = 30, max = 100 },
			{ stat = "flatAttack", min = 3, max = 15 },

			-- Tier II
			{ stat = "determination", min = 8, max = 20 },

			-- Tier III
			{ stat = "thorns", min = 3, max = 12 },

			-- Tier IV
			{ stat = "tauntDuration", min = 8, max = 25 },

			-- Tier V
			{ stat = "lifesteal", min = 1, max = 4 },

			-- Tier VI
			{ stat = "critChance", min = 1, max = 8 },

			-- Tier VII
			{ stat = "aoeSize", min = 5, max = 15 },

			-- Tier VIII
			{ stat = "skillDamage", min = 2, max = 8 },

			-- Tier IX
			{ stat = "cooldownReduction", min = 3, max = 12 },

			-- Tier X
			{ stat = "critDamage", min = 5, max = 20 },

			-- Tier XI
			{ stat = "movementSpeed", min = 1, max = 5 },

			-- Tier XII
			{ stat = "attackSpeed", min = 1, max = 5 },
		},

		-- Visual
		modelName = "TowerShield",
	},
}

return AegisWeapons