-- ServerScriptService/Modules/CharacterConfig
--[[
    CharacterConfig
    ===============
    Central configuration for the character appearance system:
      • Body presets  (wired for future expansion; currently one per gender)
      • Skin color palette  (natural + exotic tones)
      • Gendered class titles  (Hunter/Huntress, Arcanist/Arcaness)
      • Template naming convention used by CharacterManager

    Template models live in ServerStorage/CharacterTemplates/<Gender>.
    Each template contains CharacterMesh instances (shape) and BodyColors.
    CharacterManager clones the CharacterMesh items onto the player's
    default R6 rig and applies BodyColors from the chosen skin color.
]]

local CharacterConfig = {}

-- ═══════════════════════════════════════════════════════════
-- BODY PRESETS
-- Currently one option per gender (all point to the same model).
-- Add new entries here when additional body shapes become available.
-- ═══════════════════════════════════════════════════════════

CharacterConfig.Presets = {
	[1] = {
		id          = 1,
		name        = "Default",
		description = "Standard proportions.",
	},
}

CharacterConfig.PresetCount = 1

-- Gender labels shown in the creation UI
CharacterConfig.Genders = { "Male", "Female" }

-- ═══════════════════════════════════════════════════════════
-- SKINS
-- Each entry defines a cosmetic skin that can be applied over
-- the base body.  Two skin types exist:
--
--   "CharacterMesh" – only CharacterMesh instances inside the
--       template are applied; the template must be a full R6
--       character model with the correct Motor6D values baked in.
--       `template` is the model name in CharacterTemplates.
--       When `template` is nil, the gender name ("Male"/"Female")
--       is used — this is the default body skin.
--
--   "Armor" – the template contains armor Parts connected by Welds.
--       Each Part is named after a character body part
--       ("Torso", "Left Arm", etc.).  ApplyTemplate welds each
--       armor Part onto the matching character body part at runtime.
--       The base body (CharacterMesh) is still applied first.
--
-- `id`        unique string key saved in PlayerData
-- `name`      display name shown in the UI
-- `type`      "CharacterMesh" | "Armor"
-- `template`  name in ServerStorage/CharacterTemplates (nil → gender default)
-- ═══════════════════════════════════════════════════════════

CharacterConfig.Skins = {
	{
		id       = "default",
		name     = "Default",
		type     = "CharacterMesh",
		template = nil,   -- resolved to "Male" or "Female" at runtime
	},
	{
		id       = "rune_armor",
		name     = "Rune Armor",
		type     = "Armor",
		template = "RuneArmor",
	},
}

-- Lookup helpers
local _skinById = {}
for _, s in ipairs(CharacterConfig.Skins) do
	_skinById[s.id] = s
end

function CharacterConfig.GetSkin(skinId)
	return _skinById[skinId] or _skinById["default"]
end

-- ═══════════════════════════════════════════════════════════
-- SKIN COLOR PALETTE
-- Ordered list of selectable skin tones. Each entry sets all six
-- BodyColors slots uniformly. Includes natural + tasteful exotic tones.
-- ═══════════════════════════════════════════════════════════

CharacterConfig.SkinColors = {
	-- Natural tones
	{ id = "skin_fair",      name = "Fair",      color = Color3.fromRGB(234, 184, 146) },
	{ id = "skin_pale",      name = "Pale",      color = Color3.fromRGB(255, 220, 200) },
	{ id = "skin_tan",       name = "Tan",       color = Color3.fromRGB(210, 160, 110) },
	{ id = "skin_brown",     name = "Brown",     color = Color3.fromRGB(160, 105,  70) },
	{ id = "skin_dark",      name = "Dark",      color = Color3.fromRGB(100,  65,  45) },
	-- Exotic tones (muted / pastel — readable on R6)
	{ id = "skin_lavender",  name = "Lavender",  color = Color3.fromRGB(180, 155, 210) },
	{ id = "skin_violet",    name = "Violet",    color = Color3.fromRGB(145, 110, 185) },
	{ id = "skin_cyan",      name = "Cyan",      color = Color3.fromRGB(130, 200, 210) },
	{ id = "skin_mint",      name = "Mint",      color = Color3.fromRGB(150, 210, 175) },
	{ id = "skin_rose",      name = "Rose",      color = Color3.fromRGB(210, 150, 160) },
	{ id = "skin_ash",       name = "Ash",       color = Color3.fromRGB(155, 155, 165) },
	{ id = "skin_gold",      name = "Gold",      color = Color3.fromRGB(210, 185, 130) },
}

-- ═══════════════════════════════════════════════════════════
-- GENDERED CLASS TITLES
-- ═══════════════════════════════════════════════════════════

CharacterConfig.ClassTitles = {
	Aegis       = { Male = "Aegis",        Female = "Aegis"          },
	Hunter      = { Male = "Hunter",       Female = "Huntress"       },
	Arcanist    = { Male = "Arcanist",     Female = "Arcaness"       },
	LifeSteward = { Male = "Life Steward", Female = "Life Stewardess" },
}

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function CharacterConfig.GetClassTitle(className, gender)
	local titles = CharacterConfig.ClassTitles[className]
	if not titles then return className end
	local g = (gender == "Female") and "Female" or "Male"
	return titles[g]
end

--- Returns the base body template model name (always "Male" or "Female").
--- Armor skins are applied on top; use GetSkin() for those.
function CharacterConfig.GetTemplateName(preset, gender)
	local g = (gender == "Female") and "Female" or "Male"
	return g
end

function CharacterConfig.IsValidPreset(preset)
	return preset ~= nil
		and type(preset) == "number"
		and CharacterConfig.Presets[preset] ~= nil
end

function CharacterConfig.IsValidGender(gender)
	return gender == "Male" or gender == "Female"
end

--- Look up a skin color entry by id. Returns { id, name, color } or nil.
function CharacterConfig.GetSkinColor(skinId)
	for _, entry in ipairs(CharacterConfig.SkinColors) do
		if entry.id == skinId then
			return entry
		end
	end
	return nil
end

--- Validate a skin color id.
function CharacterConfig.IsValidSkinColor(skinId)
	return CharacterConfig.GetSkinColor(skinId) ~= nil
end

return CharacterConfig
