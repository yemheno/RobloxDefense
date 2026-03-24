-- ServerScriptService/Modules/ClassArmors/LifeStewardArmor
--[[
    Armor definitions for the Life Steward class.
    Two armors: BarkweaveVest (starter), VerdantRegalia (unlock via achievement).
    Both focus on survivability and healing enhancement.
]]

local LifeStewardArmor = {}

LifeStewardArmor.CLASS = "LifeSteward"

LifeStewardArmor.Armors = {
	--============================================
	-- BARKWEAVE VEST (Starter Armor)
	-- Nature-woven defense with healing amplification
	--============================================
	["BarkweaveVest"] = {
		id          = "BarkweaveVest",
		name        = "Barkweave Vest",
		class       = "LifeSteward",
		description = "Armor woven from living bark. Offers moderate protection and enhances natural healing.",
		modelId     = "DefaultArmor",

		baseDefense = 8,
		baseHealth  = 40,

		refinementDefenseBonus = 1,

		bonusPool = {
			-- Tier I (basic healer defense)
			{ stat = "healingPower",      min = 5, max = 18 },
			{ stat = "bonusHealth",       min = 20, max = 80 },
			{ stat = "cooldownReduction", min = 2, max = 10 },

			-- Tier II
			{ stat = "statusResistance",  min = 3, max = 12 },

			-- Tier III
			{ stat = "healingPercent",    min = 3, max = 10 },

			-- Tier IV
			{ stat = "damageReduction",   min = 2, max = 8 },

			-- Tier V
			{ stat = "lifeEnergy",        min = 5, max = 15 },

			-- Tier VI
			{ stat = "critChance",        min = 1, max = 8 },

			-- Tier VII
			{ stat = "movementSpeed",     min = 2, max = 8 },

			-- Tier VIII
			{ stat = "critDamage",        min = 3, max = 12 },

			-- Tier IX
			{ stat = "flatAttack",        min = 2, max = 10 },

			-- Tier X
			{ stat = "skillDamage",       min = 2, max = 8 },

			-- Tier XI
			{ stat = "aoeSize",           min = 3, max = 10 },

			-- Tier XII
			{ stat = "lifesteal",         min = 1, max = 4 },
		},

		modelName = "BarkweaveVest",
	},

	--============================================
	-- VERDANT REGALIA (Unlock via Achievement)
	-- Enhanced nature armor with superior healing amplification
	--============================================
	["VerdantRegalia"] = {
		id          = "VerdantRegalia",
		name        = "Verdant Regalia",
		class       = "LifeSteward",
		description = "Ancient armor blessed by the forest itself. Vastly empowers restoration and grants strong protection.",
		modelId     = "DefaultArmor",

		baseDefense = 11,
		baseHealth  = 55,

		refinementDefenseBonus = 2,

		bonusPool = {
			-- Tier I (enhanced healer)
			{ stat = "healingPower",      min = 8, max = 28 },
			{ stat = "healingPercent",    min = 5, max = 16 },
			{ stat = "bonusHealth",       min = 30, max = 100 },

			-- Tier II
			{ stat = "cooldownReduction", min = 3, max = 14 },

			-- Tier III
			{ stat = "lifeEnergy",        min = 8, max = 20 },

			-- Tier IV
			{ stat = "statusResistance",  min = 4, max = 15 },

			-- Tier V
			{ stat = "damageReduction",   min = 3, max = 10 },

			-- Tier VI
			{ stat = "critChance",        min = 2, max = 10 },

			-- Tier VII
			{ stat = "critDamage",        min = 5, max = 18 },

			-- Tier VIII
			{ stat = "movementSpeed",     min = 3, max = 10 },

			-- Tier IX
			{ stat = "skillDamage",       min = 3, max = 12 },

			-- Tier X
			{ stat = "flatAttack",        min = 3, max = 14 },

			-- Tier XI
			{ stat = "lifesteal",         min = 2, max = 6 },

			-- Tier XII
			{ stat = "aoeSize",           min = 4, max = 12 },
		},

		modelName = "VerdantRegalia",
	},
}

return LifeStewardArmor
