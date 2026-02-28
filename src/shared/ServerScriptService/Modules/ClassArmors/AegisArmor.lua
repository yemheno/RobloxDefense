-- ServerScriptService/Modules/ClassArmors/AegisArmor
--[[
    Armor definitions for the Aegis class.
    Two armors: PlateArmor (starter), FortressArmor (unlock via achievement).
]]

local AegisArmor = {}

AegisArmor.CLASS = "Aegis"

AegisArmor.Armors = {
	--============================================
	-- PLATE ARMOR (Starter Armor)
	-- Balanced defense, solid HP bonus
	--============================================
	["PlateArmor"] = {
		id          = "PlateArmor",
		name        = "Plate Armor",
		class       = "Aegis",
		description = "Standard-issue plate armor for the frontline. Sturdy and reliable.",
		modelId     = "DefaultArmor",

		-- Base Stats (level 1, +0 refinement, Tier I)
		baseDefense = 12,
		baseHealth  = 50,

		-- Refinement: +2 DEF per refinement level
		refinementDefenseBonus = 2,

		-- Random Bonus Pool (ordered by tier unlock)
		bonusPool = {
			-- Tier I (basic)
			{ stat = "damageReduction", min = 2, max = 8 },
			{ stat = "bonusHealth",     min = 20, max = 80 },
			{ stat = "determination",   min = 3, max = 12 },

			-- Tier II
			{ stat = "thorns",           min = 2, max = 10 },

			-- Tier III
			{ stat = "statusResistance", min = 3, max = 12 },

			-- Tier IV
			{ stat = "lifesteal",        min = 1, max = 4 },

			-- Tier V
			{ stat = "cooldownReduction", min = 2, max = 8 },

			-- Tier VI
			{ stat = "movementSpeed",    min = 1, max = 5 },

			-- Tier VII
			{ stat = "critChance",       min = 1, max = 6 },

			-- Tier VIII
			{ stat = "flatAttack",       min = 3, max = 12 },

			-- Tier IX
			{ stat = "tauntDuration",    min = 5, max = 15 },

			-- Tier X
			{ stat = "skillDamage",      min = 2, max = 8 },

			-- Tier XI
			{ stat = "aoeSize",          min = 3, max = 10 },

			-- Tier XII (all unlocked)
			{ stat = "critDamage",       min = 5, max = 15 },
		},

		modelName = "PlateArmor",
	},

	--============================================
	-- FORTRESS ARMOR (Unlock via Achievement)
	-- Maximum defense, lower mobility
	--============================================
	["FortressArmor"] = {
		id          = "FortressArmor",
		name        = "Fortress Armor",
		class       = "Aegis",
		description = "An impenetrable fortress of steel. Maximum protection at the cost of agility.",
		modelId     = "DefaultArmor",

		baseDefense = 18,
		baseHealth  = 80,

		refinementDefenseBonus = 3,

		bonusPool = {
			-- Tier I (heavy defense)
			{ stat = "damageReduction",  min = 4, max = 12 },
			{ stat = "bonusHealth",      min = 40, max = 120 },
			{ stat = "thorns",           min = 3, max = 12 },

			-- Tier II
			{ stat = "determination",    min = 5, max = 18 },

			-- Tier III
			{ stat = "statusResistance", min = 4, max = 15 },

			-- Tier IV
			{ stat = "tauntDuration",    min = 8, max = 25 },

			-- Tier V
			{ stat = "lifesteal",        min = 1, max = 5 },

			-- Tier VI
			{ stat = "cooldownReduction", min = 2, max = 10 },

			-- Tier VII
			{ stat = "critChance",       min = 1, max = 5 },

			-- Tier VIII
			{ stat = "aoeSize",          min = 3, max = 12 },

			-- Tier IX
			{ stat = "flatAttack",       min = 2, max = 8 },

			-- Tier X
			{ stat = "skillDamage",      min = 1, max = 6 },

			-- Tier XI
			{ stat = "movementSpeed",    min = 1, max = 3 },

			-- Tier XII
			{ stat = "critDamage",       min = 3, max = 10 },
		},

		modelName = "FortressArmor",
	},
}

return AegisArmor
