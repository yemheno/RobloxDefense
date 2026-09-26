-- ServerScriptService/Modules/ClassWeapons/HunterWeapons

local HunterWeapons = {}

HunterWeapons.CLASS = "Hunter"

HunterWeapons.Weapons = {
	--============================================
	-- SHORT BOW (Starter Weapon)
	-- Fast attack speed, moderate damage, low pierce count
	--============================================
	["ShortBow"] = {
		id    = "ShortBow",
		name  = "Short Bow",
		class = "Hunter",
		description = "A lightweight ranged weapon favoured by novice hunters. Rapid fire, reliable aim.",
		modelId = "DefaultSword",
		weaponSlot = 1,

		-- Element for basic attacks (skill attacks use their own skill.element)
		element = "None",

		-- Base Stats
		baseAttack      = 10,
		baseAttackSpeed = 2.2,  -- Fastest attack speed of any starter weapon

		-- Projectile override (Pierce)
		maxHits         = 1,    -- Starter: single-target pierce
		damageReduction = 0,

		-- Refinement: +1.6 ATK per level
		refinementAttackBonus = 1.6,

		-- Random Bonus Pool
		bonusPool = {
			-- Tier I
			{ stat = "critChance", min = 2,  max = 12  },
			{ stat = "critDamage", min = 8,  max = 30  },
			{ stat = "flatAttack", min = 3,  max = 12  },

			-- Tier II
			{ stat = "attackSpeed",  min = 2, max = 10 },

			-- Tier III
			{ stat = "focus", min = 3, max = 10 },  -- Bonus max Killer Instinct (PlayerBonusSystem maps focus)

			-- Tier IV
			{ stat = "skillDamage", min = 2, max = 10 },

			-- Tier V
			{ stat = "movementSpeed", min = 2, max = 8 },

			-- Tier VI
			{ stat = "lifesteal", min = 1, max = 4 },

			-- Tier VII
			{ stat = "damageReduction", min = 1, max = 5 },
		},
	},

	--============================================
	-- HUNTING BOW (Achievement Unlock)
	-- Slower but harder-hitting; base multi-pierce
	--============================================
	["HuntingBow"] = {
		id    = "HuntingBow",
		name  = "Hunting Bow",
		class = "Hunter",
		description = "A heavier draw bow used by seasoned trackers. Each arrow punches through multiple foes.",
		modelId = "DefaultSword",
		weaponSlot = 2,

		-- Element for basic attacks
		element = "None",

		-- Base Stats
		baseAttack      = 22,
		baseAttackSpeed = 1.8,

		-- Projectile override (Pierce — inherits class defaults but can override)
		maxHits         = 3,    -- Pierce up to 3 targets on basic attack
		damageReduction = 0.15, -- -15% per additional target

		-- Refinement: +3 ATK per level
		refinementAttackBonus = 3,

		-- Unlock requirement (example — plugged in by WeaponManager future unlock system)
		unlockRequirement = { classLevel = 15 },

		-- Random Bonus Pool
		bonusPool = {
			-- Tier I
			{ stat = "critChance",  min = 4,  max = 18  },
			{ stat = "critDamage",  min = 10, max = 40  },
			{ stat = "flatAttack",  min = 6,  max = 20  },

			-- Tier II
			{ stat = "attackSpeed",  min = 1, max = 6 },

			-- Tier III
			{ stat = "focus",        min = 5, max = 15 },

			-- Tier IV
			{ stat = "skillDamage",  min = 4, max = 14 },

			-- Tier V
			{ stat = "movementSpeed", min = 3, max = 10 },

			-- Tier VI
			{ stat = "lifesteal",    min = 2, max = 6  },

			-- Tier VII
			{ stat = "damageReduction", min = 2, max = 7 },
		},
	},
}

return HunterWeapons
