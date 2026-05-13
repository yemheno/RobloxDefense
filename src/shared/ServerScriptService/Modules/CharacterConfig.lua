-- ServerScriptService/Modules/CharacterConfig
--[[
    CharacterConfig
    ===============
    Central configuration for character appearance:
      • Gender labels and gendered class titles
      • Skin color palette (natural + exotic)
      • Body / head / hair model slot seams (3 of each per gender, planned)
      • Template-name resolution for CharacterManager.ApplyTemplate

    Template models live in ServerStorage/CharacterTemplates/<Name>.
    Each contains CharacterMesh instances (shape) and the Humanoid +
    HumanoidDescription used by CharacterManager. CharacterMesh items
    are cloned onto the player's default R6 rig at runtime; BodyColors
    is applied from the chosen skin color.

    Cosmetic items (hats, outfits, hair, weapons, armor) are handled by
    CosmeticManager / InventoryManager / VisualEquipmentManager as
    accessories welded onto the base rig — NOT by part replacement.
]]

local CharacterConfig = {}

-- ═══════════════════════════════════════════════════════════
-- GENDER
-- ═══════════════════════════════════════════════════════════

CharacterConfig.Genders = { "Male", "Female" }

function CharacterConfig.IsValidGender(gender)
    return gender == "Male" or gender == "Female"
end

-- ═══════════════════════════════════════════════════════════
-- BODY / HEAD / HAIR MODEL SLOTS  (planned)
--
-- The character creation flow will eventually offer 3 body shapes, 3
-- head/face models, and 3 hair models per gender. Until those assets
-- ship there is only the default (index 1). The validators accept any
-- positive integer so the persistence layer never silently drops a
-- value that a future asset pack adds.
-- ═══════════════════════════════════════════════════════════

CharacterConfig.BodyModelCount = 1
CharacterConfig.HeadModelCount = 1
CharacterConfig.HairModelCount = 1

local function isPositiveInt(v)
    return type(v) == "number" and v == math.floor(v) and v >= 1
end

function CharacterConfig.IsValidBodyModel(v) return isPositiveInt(v) end
function CharacterConfig.IsValidHeadModel(v) return isPositiveInt(v) end
function CharacterConfig.IsValidHairModel(v) return isPositiveInt(v) end

-- §CC-LEGACY: `preset` was the v0.5 field name for what is now
-- `bodyModel`. Saves migrate forward (PlayerDataConfig.AccountDefaults)
-- but legacy callers still hit IsValidPreset. Keep the helper.
function CharacterConfig.IsValidPreset(preset)
    return preset == nil or isPositiveInt(preset)
end

-- ═══════════════════════════════════════════════════════════
-- SKIN COLOR PALETTE
-- Ordered list of selectable skin tones. Each entry sets all six
-- BodyColors slots uniformly.
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
-- HAIR + CLOTHING COLOR PALETTES  (seams for future UI)
--
-- Empty today by design — the planned hair models include a no-color
-- "occlusion only" variant that can be painted with any Color3. When
-- those models ship, populate this palette and CharacterCreation.lua
-- will pick it up automatically via the same get/validate helpers
-- used for skin color.
-- ═══════════════════════════════════════════════════════════

CharacterConfig.HairColors     = {}
CharacterConfig.ClothingColors = {}

-- ═══════════════════════════════════════════════════════════
-- GENDERED CLASS TITLES
--
-- Some titles are genderless (Aegis is Aegis). UI renders the gendered
-- form via CharacterManager.GetClassTitle so we never duplicate the
-- decision elsewhere.
-- ═══════════════════════════════════════════════════════════

CharacterConfig.ClassTitles = {
    Aegis       = { Male = "Aegis",        Female = "Aegis"           },
    Hunter      = { Male = "Hunter",       Female = "Huntress"        },
    Arcanist    = { Male = "Arcanist",     Female = "Arcaness"        },
    LifeSteward = { Male = "Life Steward", Female = "Life Stewardess" },
}

-- ═══════════════════════════════════════════════════════════
-- LOOKUP HELPERS
-- ═══════════════════════════════════════════════════════════

function CharacterConfig.GetClassTitle(className, gender)
    local titles = CharacterConfig.ClassTitles[className]
    if not titles then return className end
    local g = (gender == "Female") and "Female" or "Male"
    return titles[g]
end

--- Returns the base body template model name. With current assets this
--- is always "Male" or "Female" (one template per gender). Once 3 body
--- shapes ship per gender, this will fan out to "Male1/Male2/Male3" etc.
function CharacterConfig.GetTemplateName(_preset, gender)
    local g = (gender == "Female") and "Female" or "Male"
    return g
end

local function paletteLookup(list, id)
    for _, entry in ipairs(list) do
        if entry.id == id then return entry end
    end
    return nil
end

function CharacterConfig.GetSkinColor(id)
    return paletteLookup(CharacterConfig.SkinColors, id)
end
function CharacterConfig.IsValidSkinColor(id)
    return CharacterConfig.GetSkinColor(id) ~= nil
end

function CharacterConfig.GetHairColor(id)
    return paletteLookup(CharacterConfig.HairColors, id)
end
function CharacterConfig.IsValidHairColor(id)
    -- Empty palette today: accept nil (default) and reject everything else.
    if id == nil then return true end
    return CharacterConfig.GetHairColor(id) ~= nil
end

function CharacterConfig.GetClothingColor(id)
    return paletteLookup(CharacterConfig.ClothingColors, id)
end
function CharacterConfig.IsValidClothingColor(id)
    if id == nil then return true end
    return CharacterConfig.GetClothingColor(id) ~= nil
end

return CharacterConfig
