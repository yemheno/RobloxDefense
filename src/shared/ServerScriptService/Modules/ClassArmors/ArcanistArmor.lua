-- ServerScriptService/Modules/ClassArmors/ArcanistArmor
--[[
    Armor definitions for the Arcanist class.
    Two armors: SilkRobe (starter), ArcaneVestment (unlock via achievement).
]]

local ArcanistArmor = {}

ArcanistArmor.CLASS = "Arcanist"

ArcanistArmor.Armors = {
	--============================================
	-- SILK ROBE (Starter Armor)
	-- Light defense with magical affinity
	--============================================
	["SilkRobe"] = {
		id          = "SilkRobe",
		name        = "Silk Robe",
		class       = "Arcanist",
		description = "A lightweight enchanted robe. Low physical protection but enhances magical abilities.",
		modelId     = "DefaultArmor",

		baseDefense = 6,
		baseHealth  = 30,

		refinementDefenseBonus = 1,

		bonusPool = {
			-- Tier I (basic caster)
			{ stat = "cooldownReduction", min = 2, max = 10 },
			{ stat = "skillDamage",       min = 3, max = 12 },
			{ stat = "bonusHealth",       min = 15, max = 60 },

			-- Tier II
			{ stat = "statusResistance",  min = 3, max = 12 },

			-- Tier III
			{ stat = "critChance",        min = 2, max = 10 },

			-- Tier IV
			{ stat = "critDamage",        min = 5, max = 20 },

			-- Tier V
			{ stat = "damageReduction",   min = 1, max = 5 },

			-- Tier VI
			{ stat = "movementSpeed",     min = 2, max = 8 },

			-- Tier VII
			{ stat = "flatAttack",        min = 3, max = 12 },

			-- Tier VIII
			{ stat = "mana",              min = 3, max = 10 },  -- §AGX/D-FIX2: class resource (max Aether), not Aegis-only determination

			-- Tier IX
			{ stat = "aoeSize",           min = 3, max = 12 },

			-- Tier X
			{ stat = "lifesteal",         min = 1, max = 4 },

			-- Tier XI
			{ stat = "thorns",            min = 2, max = 8 },

			-- Tier XII
			{ stat = "attackSpeed",       min = 1, max = 5 },
		},

		modelName = "SilkRobe",
	},

	--============================================
	-- ARCANE VESTMENT (Unlock via Achievement)
	-- Enhanced magical protection and power
	--============================================
	["ArcaneVestment"] = {
		id          = "ArcaneVestment",
		name        = "Arcane Vestment",
		class       = "Arcanist",
		description = "Robes woven with arcane threads. Superior magical enhancement and moderate defense.",
		modelId     = "DefaultArmor",

		baseDefense = 9,
		baseHealth  = 45,

		refinementDefenseBonus = 2,

		bonusPool = {
			-- Tier I (enhanced caster)
			{ stat = "skillDamage",       min = 5, max = 18 },
			{ stat = "cooldownReduction", min = 3, max = 14 },
			{ stat = "critDamage",        min = 8, max = 25 },

			-- Tier II
			{ stat = "critChance",        min = 3, max = 12 },

			-- Tier III
			{ stat = "statusResistance",  min = 4, max = 15 },

			-- Tier IV
			{ stat = "bonusHealth",       min = 25, max = 80 },

			-- Tier V
			{ stat = "aoeSize",           min = 5, max = 15 },

			-- Tier VI
			{ stat = "damageReduction",   min = 2, max = 8 },

			-- Tier VII
			{ stat = "movementSpeed",     min = 2, max = 7 },

			-- Tier VIII
			{ stat = "flatAttack",        min = 4, max = 15 },

			-- Tier IX
			{ stat = "lifesteal",         min = 2, max = 6 },

			-- Tier X
			{ stat = "mana",              min = 4, max = 12 },  -- §AGX/D-FIX2: class resource (max Aether)

			-- Tier XI
			{ stat = "thorns",            min = 2, max = 8 },

			-- Tier XII
			{ stat = "attackSpeed",       min = 1, max = 4 },
		},

		modelName = "ArcaneVestment",
	},
}

return ArcanistArmor
