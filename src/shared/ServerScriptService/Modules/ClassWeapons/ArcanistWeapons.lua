-- ServerScriptService/Modules/ClassWeapons/ArcanistWeapons

local ArcanistWeapons = {}

ArcanistWeapons.CLASS = "Arcanist"

ArcanistWeapons.Weapons = {
	--============================================
	-- APPRENTICE WAND (Starter Weapon)
	-- Moderate AoE, decent cast speed, low damage
	--============================================
	["ApprenticeWand"] = {
		id    = "ApprenticeWand",
		name  = "Apprentice Wand",
		class = "Arcanist",
		description = "A modest arcane focus etched with basic runic sigils. Reliable for newly awakened Arcanists.",
		modelId = "DefaultSword",
		weaponSlot = 1,

		-- Element for basic attacks
		element = "None",

		-- Base Stats
		baseAttack      = 15,
		baseAttackSpeed = 1.0,  -- Fits the Arcanist's deliberate cadence

		-- AoE override
		explosionRange = 6,     -- Radius of basic attack explosion

		-- Refinement: +2.0 ATK per level
		refinementAttackBonus = 2.0,

		-- Random Bonus Pool
		bonusPool = {
			-- Tier I
			{ stat = "critChance",  min = 1,  max = 8   },
			{ stat = "critDamage",  min = 5,  max = 20  },
			{ stat = "flatAttack",  min = 4,  max = 14  },

			-- Tier II
			{ stat = "skillDamage", min = 2, max = 10 },

			-- Tier III
			{ stat = "mana",        min = 5, max = 15 },  -- Bonus Mana

			-- Tier IV
			{ stat = "cooldownReduction", min = 1, max = 5 },

			-- Tier V
			{ stat = "damageReduction",   min = 1, max = 5 },

			-- Tier VI
			{ stat = "lifesteal",         min = 1, max = 3 },

			-- Tier VII
			{ stat = "aoeSize",           min = 5, max = 20 },  -- Larger explosions
		},
	},

	--============================================
	-- ARCANE FOCUS (Achievement Unlock)
	-- Larger AoE, higher base attack, more mana synergy
	--============================================
	["ArcaneFocus"] = {
		id    = "ArcaneFocus",
		name  = "Arcane Focus",
		class = "Arcanist",
		description = "A polished crystalline orb resonating with intense magical energy. AoE blasts cover far greater areas.",
		modelId = "DefaultSword",
		weaponSlot = 2,

		-- Element for basic attacks
		element = "None",

		-- Base Stats
		baseAttack      = 26,
		baseAttackSpeed = 0.9,   -- Slightly slower but more impactful

		-- AoE override (bigger explosions)
		explosionRange = 10,

		-- Refinement: +3.5 ATK per level
		refinementAttackBonus = 4,

		-- Unlock requirement
		unlockRequirement = { classLevel = 15 },

		-- Random Bonus Pool
		bonusPool = {
			-- Tier I
			{ stat = "critChance",  min = 2,  max = 12  },
			{ stat = "critDamage",  min = 8,  max = 35  },
			{ stat = "flatAttack",  min = 8,  max = 22  },

			-- Tier II
			{ stat = "skillDamage", min = 4, max = 16 },

			-- Tier III
			{ stat = "mana",        min = 8, max = 25 },

			-- Tier IV
			{ stat = "cooldownReduction", min = 2, max = 8 },

			-- Tier V
			{ stat = "damageReduction",   min = 2, max = 7 },

			-- Tier VI
			{ stat = "lifesteal",         min = 1, max = 5 },

			-- Tier VII
			{ stat = "aoeSize",           min = 10, max = 30 },
		},
	},
}

return ArcanistWeapons
