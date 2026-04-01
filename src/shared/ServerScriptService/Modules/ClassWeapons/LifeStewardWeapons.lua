-- ServerScriptService/Modules/ClassWeapons/LifeStewardWeapons
--[[
    Weapon definitions for the Life Steward class.
    Two weapons: Life Totem (starter), Reincarnation Totem (unlock via achievement).
    Both are healing-focused with Wood element output.
]]

local LifeStewardWeapons = {}

LifeStewardWeapons.CLASS = "LifeSteward"

LifeStewardWeapons.Weapons = {
	--============================================
	-- LIFE TOTEM (Starter Weapon)
	-- Healing-focused, low ATK, Wood element
	--============================================
	["LifeTotem"] = {
		id = "LifeTotem",
		name = "Life Totem",
		class = "LifeSteward",
		description = "A totem carved from an ancient living tree. Channels nature's healing energy.",
		modelId = "DefaultSword",
		weaponSlot = 1,

		-- Wood element on basic attacks
		element = "Wood",

		-- Base Stats (low ATK — healer, not a DPS)
		baseAttack = 9,
		baseAttackSpeed = 0.85,

		-- Ranged projectile (matches ClassConfig)
		attackShape = nil,  -- uses ClassConfig projectile

		-- Refinement: +1.2 ATK per level
		refinementAttackBonus = 1.2,

		-- Random Bonus Pool (healing-focused)
		bonusPool = {
			-- Tier I (basic healer)
			{ stat = "healingPower",      min = 5, max = 20 },
			{ stat = "healingPercent",    min = 3, max = 12 },
			{ stat = "cooldownReduction", min = 2, max = 10 },

			-- Tier II
			{ stat = "bonusHealth", min = 20, max = 80 },

			-- Tier III
			{ stat = "lifeEnergy", min = 5, max = 15 },

			-- Tier IV
			{ stat = "statusResistance", min = 3, max = 12 },

			-- Tier V
			{ stat = "critChance", min = 1, max = 8 },

			-- Tier VI
			{ stat = "critDamage", min = 3, max = 15 },

			-- Tier VII
			{ stat = "skillDamage", min = 2, max = 8 },

			-- Tier VIII
			{ stat = "damageReduction", min = 1, max = 5 },

			-- Tier IX
			{ stat = "movementSpeed", min = 2, max = 8 },

			-- Tier X
			{ stat = "flatAttack", min = 3, max = 12 },

			-- Tier XI
			{ stat = "aoeSize", min = 3, max = 10 },

			-- Tier XII
			{ stat = "lifesteal", min = 1, max = 4 },
		},

		-- Visual
		modelName = "LifeTotem",
	},

	--============================================
	-- REINCARNATION TOTEM (Unlock via Achievement)
	-- Enhanced healing, stronger self-sustain
	--============================================
	["ReincarnationTotem"] = {
		id = "ReincarnationTotem",
		name = "Reincarnation Totem",
		class = "LifeSteward",
		description = "An ancient relic pulsing with the cycle of life and death. Empowers resurrection and restoration.",
		modelId = "DefaultSword",
		weaponSlot = 2,

		-- Wood element on basic attacks
		element = "Wood",

		-- Base Stats (slightly more ATK, same speed)
		baseAttack = 10,
		baseAttackSpeed = 0.8,

		-- Ranged projectile
		attackShape = nil,

		-- Refinement: +1.5 ATK per level
		refinementAttackBonus = 1.5,

		-- Random Bonus Pool (enhanced healer)
		bonusPool = {
			-- Tier I (enhanced healer)
			{ stat = "healingPower",      min = 8, max = 30 },
			{ stat = "healingPercent",    min = 5, max = 18 },
			{ stat = "cooldownReduction", min = 3, max = 14 },

			-- Tier II
			{ stat = "lifeEnergy", min = 8, max = 20 },

			-- Tier III
			{ stat = "bonusHealth", min = 30, max = 100 },

			-- Tier IV
			{ stat = "critChance", min = 2, max = 10 },

			-- Tier V
			{ stat = "critDamage", min = 5, max = 20 },

			-- Tier VI
			{ stat = "statusResistance", min = 4, max = 15 },

			-- Tier VII
			{ stat = "damageReduction", min = 2, max = 8 },

			-- Tier VIII
			{ stat = "skillDamage", min = 3, max = 12 },

			-- Tier IX
			{ stat = "lifesteal", min = 1, max = 5 },

			-- Tier X
			{ stat = "flatAttack", min = 5, max = 18 },

			-- Tier XI
			{ stat = "movementSpeed", min = 2, max = 8 },

			-- Tier XII
			{ stat = "aoeSize", min = 4, max = 12 },
		},

		-- Visual
		modelName = "ReincarnationTotem",
	},
}

return LifeStewardWeapons
