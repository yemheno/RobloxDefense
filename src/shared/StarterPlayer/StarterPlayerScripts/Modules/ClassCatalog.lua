-- StarterPlayerScripts/Modules/ClassCatalog
--
-- Client-side presentation config for the class selection menu.
-- Contains ONLY display data: categories, class identifiers, unlock levels,
-- and locale key prefixes.  No server stats or damage formulae here.
--
-- To add a new class: append an entry to the relevant category's `classes` table.
-- To add a new category: append to ClassCatalog.Categories.

local ClassCatalog = {}

-- Number of class slots rendered per column (real classes + gray placeholders).
ClassCatalog.SlotsPerColumn = 4

--[[
    Category structure:
        id         – internal identifier (used as React child key)
        headerKey  – Locale key for the column header text
        classes    – ordered list of classes belonging to this category

    Class entry structure:
        id            – class name as registered on the server (e.g. "Aegis")
        localeKey     – prefix used to build locale keys:
                          <localeKey>_name  → display name
                          <localeKey>_desc  → short description
        requiredLevel – minimum player level to unlock this class
                        (must stay in sync with PlayerDataConfig.ClassUnlockRequirements)
]]
ClassCatalog.Categories = {

	{
		id        = "vanguard",
		headerKey = "cat_vanguard",   -- "Vanguard"
		classes   = {
			{ id = "Aegis",    localeKey = "class_Aegis",    requiredLevel = 1  },
			-- future melee classes go here
		},
	},

	{
		id        = "ranger",
		headerKey = "cat_ranger",     -- "Ranger"
		classes   = {
			{ id = "Hunter",   localeKey = "class_Hunter",   requiredLevel = 1 },
			-- future ranged classes go here
		},
	},

	{
		id        = "mage",
		headerKey = "cat_mage",       -- "Arcanist"
		classes   = {
			{ id = "Arcanist", localeKey = "class_Arcanist", requiredLevel = 1 },
			-- future magical classes go here
		},
	},

	{
		id        = "support",
		headerKey = "cat_support",    -- "Warden"
		classes   = {
			{ id = "LifeSteward", localeKey = "class_LifeSteward", requiredLevel = 1 },
		},
	},
}

return ClassCatalog
