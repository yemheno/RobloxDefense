-- ServerScriptService/Modules/CosmeticConfig.lua
--[[
    CosmeticConfig
    ==============
    Central data definitions for the cosmetic system.

    Slot types:
      • headgear — accessories / color changes on the Head part.
      • outfit   — full body replacement (Torso + Arms + Legs color/material/model).

    Each cosmetic entry can specify:
      classRestriction  nil = universal, "Aegis"/"Hunter"/... = class-locked.
      rarity            Common / Uncommon / Rare / Epic / Legendary (UI colouring).
      visual.type       "color"  = recolor R6 parts (placeholder system).
                        "model"  = attach/replace with an .rbxmx template (future).

    Head presets are used during character creation. They define the skin
    colour and optional face decal / accessories for the R6 Head.

    Mob variants define body colour / material overrides applied after the
    mob template is cloned, giving visual variety without extra model files.

    Adding new cosmetics:
      1. Add an entry in the appropriate catalog (Headgear / Outfits).
      2. Optionally add it to StarterWardrobe so all players get it free.
      3. Or set up an unlock source (shop, drop, quest) elsewhere.
]]

local CosmeticConfig = {}

-- ═══════════════════════════════════════════════════════════
-- SLOT TYPES
-- ═══════════════════════════════════════════════════════════

CosmeticConfig.Slots = {
	HEADGEAR = "headgear",
	OUTFIT   = "outfit",
}

-- ═══════════════════════════════════════════════════════════
-- HEADGEAR CATALOG
-- ═══════════════════════════════════════════════════════════

CosmeticConfig.Headgear = {
	none = {
		id               = "none",
		name             = "None",
		description      = "No headgear.",
		rarity           = "Common",
		classRestriction = nil,
		visual           = nil,  -- no change
	},

	hood_basic = {
		id               = "hood_basic",
		name             = "Traveler's Hood",
		description      = "A simple cloth hood.",
		rarity           = "Common",
		classRestriction = nil,
		visual = {
			type         = "color",
			headColor    = Color3.fromRGB(80, 60, 40),
			headMaterial = Enum.Material.Fabric,
		},
	},

	helm_aegis = {
		id               = "helm_aegis",
		name             = "Aegis Helm",
		description      = "A sturdy steel helmet.",
		rarity           = "Uncommon",
		classRestriction = "Aegis",
		visual = {
			type         = "color",
			headColor    = Color3.fromRGB(140, 140, 155),
			headMaterial = Enum.Material.Metal,
		},
	},

	circlet_arcanist = {
		id               = "circlet_arcanist",
		name             = "Arcane Circlet",
		description      = "Glows with faint magical energy.",
		rarity           = "Uncommon",
		classRestriction = "Arcanist",
		visual = {
			type         = "color",
			headColor    = Color3.fromRGB(100, 60, 180),
			headMaterial = Enum.Material.Neon,
		},
	},

	mask_hunter = {
		id               = "mask_hunter",
		name             = "Hunter's Mask",
		description      = "Sharpens the senses.",
		rarity           = "Uncommon",
		classRestriction = "Hunter",
		visual = {
			type         = "color",
			headColor    = Color3.fromRGB(60, 90, 50),
			headMaterial = Enum.Material.Fabric,
		},
	},
}

-- ═══════════════════════════════════════════════════════════
-- OUTFIT CATALOG
-- ═══════════════════════════════════════════════════════════

CosmeticConfig.Outfits = {
	-- ── Class defaults ────────────────────────────────────

	default_aegis = {
		id               = "default_aegis",
		name             = "Aegis Plate",
		description      = "Standard Aegis iron armor.",
		rarity           = "Common",
		classRestriction = "Aegis",
		visual = {
			type  = "color",
			parts = {
				Torso        = { color = Color3.fromRGB(140, 140, 155), material = Enum.Material.Metal },
				["Left Arm"]  = { color = Color3.fromRGB(150, 150, 165), material = Enum.Material.Metal },
				["Right Arm"] = { color = Color3.fromRGB(150, 150, 165), material = Enum.Material.Metal },
				["Left Leg"]  = { color = Color3.fromRGB(90, 90, 100),   material = Enum.Material.Metal },
				["Right Leg"] = { color = Color3.fromRGB(90, 90, 100),   material = Enum.Material.Metal },
			},
		},
	},

	default_arcanist = {
		id               = "default_arcanist",
		name             = "Arcanist Robes",
		description      = "Flowing magical robes.",
		rarity           = "Common",
		classRestriction = "Arcanist",
		visual = {
			type  = "color",
			parts = {
				Torso        = { color = Color3.fromRGB(60, 40, 120),  material = Enum.Material.Fabric },
				["Left Arm"]  = { color = Color3.fromRGB(70, 50, 130),  material = Enum.Material.Fabric },
				["Right Arm"] = { color = Color3.fromRGB(70, 50, 130),  material = Enum.Material.Fabric },
				["Left Leg"]  = { color = Color3.fromRGB(40, 25, 80),   material = Enum.Material.Fabric },
				["Right Leg"] = { color = Color3.fromRGB(40, 25, 80),   material = Enum.Material.Fabric },
			},
		},
	},

	default_hunter = {
		id               = "default_hunter",
		name             = "Hunter's Garb",
		description      = "Light leather for swift movement.",
		rarity           = "Common",
		classRestriction = "Hunter",
		visual = {
			type  = "color",
			parts = {
				Torso        = { color = Color3.fromRGB(80, 100, 60),  material = Enum.Material.Fabric },
				["Left Arm"]  = { color = Color3.fromRGB(90, 110, 70),  material = Enum.Material.Fabric },
				["Right Arm"] = { color = Color3.fromRGB(90, 110, 70),  material = Enum.Material.Fabric },
				["Left Leg"]  = { color = Color3.fromRGB(70, 60, 45),   material = Enum.Material.SmoothPlastic },
				["Right Leg"] = { color = Color3.fromRGB(70, 60, 45),   material = Enum.Material.SmoothPlastic },
			},
		},
	},

	default_lifesteward = {
		id               = "default_lifesteward",
		name             = "Steward's Vestments",
		description      = "Light cloth infused with restorative energy.",
		rarity           = "Common",
		classRestriction = "LifeSteward",
		visual = {
			type  = "color",
			parts = {
				Torso        = { color = Color3.fromRGB(220, 220, 200), material = Enum.Material.Fabric },
				["Left Arm"]  = { color = Color3.fromRGB(200, 210, 190), material = Enum.Material.Fabric },
				["Right Arm"] = { color = Color3.fromRGB(200, 210, 190), material = Enum.Material.Fabric },
				["Left Leg"]  = { color = Color3.fromRGB(180, 180, 165), material = Enum.Material.Fabric },
				["Right Leg"] = { color = Color3.fromRGB(180, 180, 165), material = Enum.Material.Fabric },
			},
		},
	},

	-- ── Universal outfits ─────────────────────────────────

	peasant_garb = {
		id               = "peasant_garb",
		name             = "Peasant's Garb",
		description      = "Simple village clothing.",
		rarity           = "Common",
		classRestriction = nil,
		visual = {
			type  = "color",
			parts = {
				Torso        = { color = Color3.fromRGB(160, 140, 110), material = Enum.Material.Fabric },
				["Left Arm"]  = { color = Color3.fromRGB(170, 150, 120), material = Enum.Material.Fabric },
				["Right Arm"] = { color = Color3.fromRGB(170, 150, 120), material = Enum.Material.Fabric },
				["Left Leg"]  = { color = Color3.fromRGB(100, 85, 65),   material = Enum.Material.Fabric },
				["Right Leg"] = { color = Color3.fromRGB(100, 85, 65),   material = Enum.Material.Fabric },
			},
		},
	},

	dark_knight = {
		id               = "dark_knight",
		name             = "Dark Knight Armor",
		description      = "Formidable black iron plate.",
		rarity           = "Rare",
		classRestriction = "Aegis",
		visual = {
			type  = "color",
			parts = {
				Torso        = { color = Color3.fromRGB(30, 30, 35),   material = Enum.Material.Metal },
				["Left Arm"]  = { color = Color3.fromRGB(35, 35, 40),   material = Enum.Material.Metal },
				["Right Arm"] = { color = Color3.fromRGB(35, 35, 40),   material = Enum.Material.Metal },
				["Left Leg"]  = { color = Color3.fromRGB(25, 25, 30),   material = Enum.Material.Metal },
				["Right Leg"] = { color = Color3.fromRGB(25, 25, 30),   material = Enum.Material.Metal },
			},
		},
	},

	shadow_robes = {
		id               = "shadow_robes",
		name             = "Shadow Weave Robes",
		description      = "Woven from threads of pure darkness.",
		rarity           = "Rare",
		classRestriction = "Arcanist",
		visual = {
			type  = "color",
			parts = {
				Torso        = { color = Color3.fromRGB(20, 10, 40),   material = Enum.Material.Fabric },
				["Left Arm"]  = { color = Color3.fromRGB(25, 15, 50),   material = Enum.Material.Fabric },
				["Right Arm"] = { color = Color3.fromRGB(25, 15, 50),   material = Enum.Material.Fabric },
				["Left Leg"]  = { color = Color3.fromRGB(15, 8, 30),    material = Enum.Material.Fabric },
				["Right Leg"] = { color = Color3.fromRGB(15, 8, 30),    material = Enum.Material.Fabric },
			},
		},
	},

	forest_ranger = {
		id               = "forest_ranger",
		name             = "Forest Ranger Suit",
		description      = "Camouflage for deep woodland hunting.",
		rarity           = "Rare",
		classRestriction = "Hunter",
		visual = {
			type  = "color",
			parts = {
				Torso        = { color = Color3.fromRGB(50, 70, 35),   material = Enum.Material.Fabric },
				["Left Arm"]  = { color = Color3.fromRGB(55, 75, 40),   material = Enum.Material.Fabric },
				["Right Arm"] = { color = Color3.fromRGB(55, 75, 40),   material = Enum.Material.Fabric },
				["Left Leg"]  = { color = Color3.fromRGB(40, 55, 28),   material = Enum.Material.Fabric },
				["Right Leg"] = { color = Color3.fromRGB(40, 55, 28),   material = Enum.Material.Fabric },
			},
		},
	},

}

-- ═══════════════════════════════════════════════════════════
-- CLASS DEFAULTS  (equipped when creating character / switching class)
-- ═══════════════════════════════════════════════════════════

CosmeticConfig.ClassDefaults = {
	Aegis        = { headgear = "none", outfit = "default_aegis" },
	Arcanist     = { headgear = "none", outfit = "default_arcanist" },
	Hunter       = { headgear = "none", outfit = "default_hunter" },
	LifeSteward  = { headgear = "none", outfit = "default_lifesteward" },
}

-- ═══════════════════════════════════════════════════════════
-- STARTER WARDROBE  (given to all new players automatically)
-- ═══════════════════════════════════════════════════════════

CosmeticConfig.StarterWardrobe = {
	"none",
	"hood_basic",
	"peasant_garb",
	"default_aegis",
	"default_arcanist",
	"default_hunter",
	"default_lifesteward",
}



-- ═══════════════════════════════════════════════════════════
-- MOB VISUAL VARIANTS
-- Each mob type can have named variants that modify color / material.
-- MobSpawner passes a variant name; MobCosmeticManager applies it.
-- ═══════════════════════════════════════════════════════════

CosmeticConfig.MobVariants = {
	Zombie = {
		default = {
			bodyColor = Color3.fromRGB(100, 140, 90),
			material  = Enum.Material.SmoothPlastic,
			features  = {},
		},
		decayed = {
			bodyColor = Color3.fromRGB(70, 95, 60),
			material  = Enum.Material.Slate,
			features  = {},
		},
		frozen = {
			bodyColor = Color3.fromRGB(120, 160, 200),
			material  = Enum.Material.Ice,
			features  = { glow = true, glowColor = Color3.fromRGB(150, 200, 255) },
		},
		burning = {
			bodyColor = Color3.fromRGB(180, 60, 30),
			material  = Enum.Material.Neon,
			features  = { glow = true, glowColor = Color3.fromRGB(255, 120, 30) },
		},
	},

	Ogre = {
		default = {
			bodyColor = Color3.fromRGB(140, 120, 90),
			material  = Enum.Material.SmoothPlastic,
			features  = {},
		},
		armored = {
			bodyColor = Color3.fromRGB(100, 100, 110),
			material  = Enum.Material.Metal,
			features  = {},
		},
		enraged = {
			bodyColor = Color3.fromRGB(180, 70, 50),
			material  = Enum.Material.SmoothPlastic,
			features  = { glow = true, glowColor = Color3.fromRGB(255, 80, 40) },
		},
	},

	Troll = {
		default = {
			bodyColor = Color3.fromRGB(90, 130, 90),
			material  = Enum.Material.Granite,
			features  = {},
		},
		elite = {
			bodyColor = Color3.fromRGB(130, 50, 50),
			material  = Enum.Material.Granite,
			features  = { glow = true, glowColor = Color3.fromRGB(255, 80, 80) },
		},
		moss = {
			bodyColor = Color3.fromRGB(60, 100, 55),
			material  = Enum.Material.Grass,
			features  = {},
		},
	},
}

-- ═══════════════════════════════════════════════════════════
-- RARITY COLOURS  (for UI borders / text)
-- ═══════════════════════════════════════════════════════════

CosmeticConfig.RarityColors = {
	Common    = Color3.fromRGB(180, 180, 180),
	Uncommon  = Color3.fromRGB(80, 200, 120),
	Rare      = Color3.fromRGB(80, 140, 230),
	Epic      = Color3.fromRGB(160, 80, 220),
	Legendary = Color3.fromRGB(255, 180, 40),
}

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function CosmeticConfig.GetHeadgear(id)
	return CosmeticConfig.Headgear[id]
end

function CosmeticConfig.GetOutfit(id)
	return CosmeticConfig.Outfits[id]
end

--- Lookup a cosmetic in either catalog.
function CosmeticConfig.GetCosmetic(id)
	return CosmeticConfig.Headgear[id] or CosmeticConfig.Outfits[id]
end

--- Determine which slot a cosmetic belongs to.
function CosmeticConfig.GetSlotForCosmetic(id)
	if CosmeticConfig.Headgear[id] then return CosmeticConfig.Slots.HEADGEAR end
	if CosmeticConfig.Outfits[id]  then return CosmeticConfig.Slots.OUTFIT end
	return nil
end

--- Check if a class is allowed to wear a cosmetic.
function CosmeticConfig.CanClassWear(cosmeticId, className)
	local cosmetic = CosmeticConfig.GetCosmetic(cosmeticId)
	if not cosmetic then return false end
	if cosmetic.classRestriction == nil then return true end
	return cosmetic.classRestriction == className
end

--- Get mob variant data (falls back to "default").
function CosmeticConfig.GetMobVariant(mobId, variantName)
	local mobVariants = CosmeticConfig.MobVariants[mobId]
	if not mobVariants then return nil end
	return mobVariants[variantName or "default"] or mobVariants["default"]
end

--- Get the class default cosmetics table.
function CosmeticConfig.GetClassDefault(className)
	return CosmeticConfig.ClassDefaults[className]
end

--- Get all cosmetics for a slot, filtered by class compatibility.
function CosmeticConfig.GetCosmeticsForSlot(slot, className)
	local catalog = (slot == CosmeticConfig.Slots.HEADGEAR) and CosmeticConfig.Headgear or CosmeticConfig.Outfits
	local result = {}
	for id, entry in pairs(catalog) do
		if entry.classRestriction == nil or entry.classRestriction == className then
			table.insert(result, entry)
		end
	end
	table.sort(result, function(a, b) return a.name < b.name end)
	return result
end

return CosmeticConfig
