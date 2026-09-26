-- ServerScriptService/Modules/ClassArmors/HunterArmor
--[[
    Armor definitions for the Hunter class.
    Two armors: LeatherArmor (starter), ShadowCloak (unlock via achievement).
]]

local HunterArmor = {}

HunterArmor.CLASS = "Hunter"

HunterArmor.Armors = {
	--============================================
	-- LEATHER ARMOR (Starter Armor)
	-- Light and agile, favors mobility and crits
	--============================================
	["LeatherArmor"] = {
		id          = "LeatherArmor",
		name        = "Leather Armor",
		class       = "Hunter",
		description = "Supple leather gear built for speed. Light protection but maximum agility.",
		modelId     = "DefaultArmor",

		baseDefense = 8,
		baseHealth  = 35,

		refinementDefenseBonus = 1,

		bonusPool = {
			-- Tier I (basic agility)
			{ stat = "critChance",       min = 3, max = 12 },
			{ stat = "movementSpeed",    min = 2, max = 8 },
			{ stat = "critDamage",       min = 5, max = 20 },

			-- Tier II
			{ stat = "attackSpeed",      min = 1, max = 6 },

			-- Tier III
			{ stat = "bonusHealth",      min = 15, max = 50 },

			-- Tier IV
			{ stat = "statusResistance", min = 2, max = 10 },

			-- Tier V
			{ stat = "damageReduction",  min = 1, max = 5 },

			-- Tier VI
			{ stat = "skillDamage",      min = 3, max = 12 },

			-- Tier VII
			{ stat = "flatAttack",       min = 3, max = 12 },

			-- Tier VIII
			{ stat = "cooldownReduction", min = 2, max = 8 },

			-- Tier IX
			{ stat = "lifesteal",        min = 1, max = 4 },

			-- Tier X
			{ stat = "focus",            min = 3, max = 10 },  -- §AGX/D-FIX2: was determination (Aegis-only resource; dead on Hunter)

			-- Tier XI
			{ stat = "aoeSize",          min = 2, max = 8 },

			-- Tier XII
			{ stat = "thorns",           min = 1, max = 5 },
		},

		modelName = "LeatherArmor",
	},

	--============================================
	-- SHADOW CLOAK (Unlock via Achievement)
	-- Maximum agility and crit focus
	--============================================
	["ShadowCloak"] = {
		id          = "ShadowCloak",
		name        = "Shadow Cloak",
		class       = "Hunter",
		description = "A cloak woven from shadow threads. Near-invisible and deadly.",
		modelId     = "DefaultArmor",

		baseDefense = 5,
		baseHealth  = 25,

		refinementDefenseBonus = 1,

		bonusPool = {
			-- Tier I (assassin focus)
			{ stat = "critChance",       min = 5, max = 15 },
			{ stat = "critDamage",       min = 8, max = 30 },
			{ stat = "movementSpeed",    min = 3, max = 10 },

			-- Tier II
			{ stat = "attackSpeed",      min = 2, max = 8 },

			-- Tier III
			{ stat = "skillDamage",      min = 4, max = 15 },

			-- Tier IV
			{ stat = "flatAttack",       min = 5, max = 18 },

			-- Tier V
			{ stat = "lifesteal",        min = 2, max = 6 },

			-- Tier VI
			{ stat = "cooldownReduction", min = 3, max = 12 },

			-- Tier VII
			{ stat = "statusResistance", min = 2, max = 8 },

			-- Tier VIII
			{ stat = "bonusHealth",      min = 10, max = 40 },

			-- Tier IX
			{ stat = "damageReduction",  min = 1, max = 4 },

			-- Tier X
			{ stat = "focus",            min = 2, max = 8 },   -- §AGX/D-FIX2: was determination

			-- Tier XI
			{ stat = "aoeSize",          min = 2, max = 8 },

			-- Tier XII
			{ stat = "thorns",           min = 1, max = 4 },
		},

		modelName = "ShadowCloak",
	},
}

return HunterArmor
