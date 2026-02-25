-- ServerScriptService/Modules/CharacterConfig
--[[
    CharacterConfig
    ===============
    Central configuration for the character appearance system:
      • Body presets  (3 silhouette options, shared by both genders)
      • Gendered class titles  (Hunter/Huntress, Arcanist/Arcaness)
      • Template naming convention used by CharacterManager when
        loading character models from ReplicatedStorage

    Template models live in:
        ReplicatedStorage/CharacterTemplates/<Preset>_<Gender>
    e.g.: Athletic_Male, Athletic_Female, Balanced_Male, …

    If a template model is not found the system falls back silently
    to the default Roblox avatar so missing assets never block play.
]]

local CharacterConfig = {}

-- ═══════════════════════════════════════════════════════════
-- BODY PRESETS
-- ═══════════════════════════════════════════════════════════

CharacterConfig.Presets = {
	[1] = {
		id          = 1,
		name        = "Athletic",
		description = "Lean and agile — built for speed.",
	},
	[2] = {
		id          = 2,
		name        = "Balanced",
		description = "Average proportions — a reliable all-rounder.",
	},
	[3] = {
		id          = 3,
		name        = "Brawny",
		description = "Stocky and powerful — built to endure.",
	},
}

-- Total number of presets (used for validation)
CharacterConfig.PresetCount = 3

-- Gender labels shown in the creation UI
CharacterConfig.Genders = { "Male", "Female" }

-- ═══════════════════════════════════════════════════════════
-- GENDERED CLASS TITLES
-- Aegis is non-gendered; Hunter and Arcanist have gender-specific titles.
-- ═══════════════════════════════════════════════════════════

CharacterConfig.ClassTitles = {
	Aegis    = { Male = "Aegis",    Female = "Aegis"    },
	Hunter   = { Male = "Hunter",   Female = "Huntress" },
	Arcanist = { Male = "Arcanist", Female = "Arcaness" },
}

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

--[[
    GetClassTitle(className, gender)
    Returns the display title for a player's class.
    gender: "Male" or "Female" (defaults to "Male" if nil/unknown)
]]
function CharacterConfig.GetClassTitle(className, gender)
	local titles = CharacterConfig.ClassTitles[className]
	if not titles then
		return className  -- unknown class → return raw name
	end

	local g = (gender == "Female") and "Female" or "Male"
	return titles[g]
end

--[[
    GetTemplateName(preset, gender)
    Returns the ReplicatedStorage model name for the given preset+gender.
    e.g. GetTemplateName(1, "Female") → "Athletic_Female"
]]
function CharacterConfig.GetTemplateName(preset, gender)
	local presetData = CharacterConfig.Presets[preset]
	if not presetData then
		presetData = CharacterConfig.Presets[2]  -- default: Balanced
	end
	local g = (gender == "Female") and "Female" or "Male"
	return presetData.name .. "_" .. g
end

--[[
    IsValidPreset(preset)
    Returns true if the preset number is valid.
]]
function CharacterConfig.IsValidPreset(preset)
	return preset ~= nil
		and type(preset) == "number"
		and CharacterConfig.Presets[preset] ~= nil
end

--[[
    IsValidGender(gender)
    Returns true if the gender string is valid.
]]
function CharacterConfig.IsValidGender(gender)
	return gender == "Male" or gender == "Female"
end

return CharacterConfig
