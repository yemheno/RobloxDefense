-- ServerScriptService/Modules/ClassConfig
--[[
    ClassConfig
    ===========
    Authoritative definitions for every playable class.

    What lives here:
      • Identity:    name, description, gendered display, default flag,
                     unlockRequirements.
      • Combat ID:   ranged (melee | ranged), weaponXPRole, projectile
                     spec (ranged only), basic-attack animation reference,
                     innateBonuses (BonusManager source = "innate").
      • Scaling:     statDerivation table — { derivedStat = { PRIMARY = coeff, … } }.

    What does NOT live here:
      • attackShape / shapeParams / baseAttackSpeed
            (§T1.2/D7 — owned by WeaponManager; the class no longer
             carries pre-weapon stand-in values.)
      • Resource name / max / regen rules
            (§T1.2/DQ5 — owned by ClassBehaviors/<Class>Behavior.lua.
             That module's CONFIG.ResourceName is canonical.)
      • Default-unlocked list
            (§T1.2/D5 — derived at module load from each class's
             `default = true` flag below; PlayerDataConfig consumes
             the derived list.)
      • ClassUnlockRequirements table
            (§T1.2/D5 — derived from each class's `unlockRequirements`
             field below.)

    Adding a new class — one place to author:
      1. Append an entry to ClassConfig.Classes with all fields below.
      2. Author ClassBehaviors/<Name>Behavior.lua for resource mechanics.
      3. Author ClassSkills/<Name>Skills.lua for skills.
      4. Author ClassWeapons/<Name>Weapons.lua for starter weapon binding.
      No edits to PlayerDataConfig.UnlockedClasses or
      PlayerDataConfig.ClassUnlockRequirements are needed — both are
      derived from this file.
]]

local ClassConfig = {}

-- Animation IDs are centralised in AnimationConfig (single source of truth).
-- Lazily resolved at first access to avoid circular-require at load time.
local _AnimationConfig = nil
local function getAnim(className)
    if not _AnimationConfig then
        _AnimationConfig = require(script.Parent:WaitForChild("AnimationConfig"))
    end
    local classAnims = _AnimationConfig.Player.Classes[className]
    return classAnims and classAnims.basicAttack
end

-- ═══════════════════════════════════════════════════════════
-- CLASS DEFINITIONS
-- ═══════════════════════════════════════════════════════════
--[[
    Field reference:
      name              string   — internal id (also used as table key)
      gendered          bool?    — display name via CharacterConfig.ClassTitles
      description       string
      default           bool     — true → granted to new players at first spawn
      unlockRequirements table   — {} = no gate; { requiredLevel = N } supported
      weaponXPRole      string   — "tank" | "healer" | "support" | "dps"
      ranged            bool     — false = melee (uses weapon attackShape),
                                   true  = ranged (uses .projectile below)
      projectile        table?   — only for ranged classes (see comment block)
      animations        table    — { basicAttack = AnimationConfig.Player.Classes[name].basicAttack }
      innateBonuses     table    — flat BonusManager entries applied at class-active
      statDerivation    table    — derived = base + Σ((PrimaryBase+allocated) × coeff)

    §AGX/BAL (§T1.2-BAL1) — CritDamage rule: NO class scales CritDamage from a
    primary stat. The base→cap headroom is small and gear, accessories,
    talents and Hunter's innate already fill it by mid-game, so primary-stat
    scaling would only double-dip the stat that already drives Damage or
    CritChance. Class crit identity lives in CritChance coefficients +
    innateBonuses. Numbers: BALANCE_NUMBERS.md#crit-damage-no-class-scaling.

    Projectile shapes — for `ranged = true` classes:
      type = "Pierce"  goes through targets
         maxHits, damageReduction, minDamageFraction, speed, lifetime
      type = "AoE"     explodes on impact, uses AttackShapes radius/cone/etc.
         shape, shapeParams, primaryMultiplier, splashMultiplier, speed, lifetime
]]
ClassConfig.Classes = {

    -- ═══════════════════════════════════════════════════════
    -- MELEE CLASSES
    -- ═══════════════════════════════════════════════════════

    Aegis = {
        name        = "Aegis",
        description = "A sturdy frontline fighter with high health and defense.",

        default            = true,
        unlockRequirements = {},

        weaponXPRole = "tank",
        ranged       = false,

        animations = {
            basicAttack = getAnim("Aegis"),
        },

        innateBonuses = {
            HealthPercent   = 10,
            DamageReduction = 5,
        },

        statDerivation = {
            Health            = { VIT = 15.0 },
            Damage            = { MIG = 3.0  },
            Armor             = { MIG = 1.0  },
            Penetration       = { MIG = 0.25 },
            CritChance        = { PRE = 0.22 },
            CritDamage        = {},                       -- §AGX/BAL: none for every class (T1.2-BAL1, see header)
            CooldownReduction = { RSV = 0.45 },
            StatusResistance  = { RSV = 1.0  },
            ResourceMax       = { RSV = 1.5  },
        },
    },

    -- ═══════════════════════════════════════════════════════
    -- RANGED CLASSES
    -- ═══════════════════════════════════════════════════════

    Arcanist = {
        name        = "Arcanist",
        gendered    = true,
        description = "A powerful spellcaster who bends elemental forces to obliterate foes.",

        default            = true,
        unlockRequirements = {},

        weaponXPRole = "dps",
        ranged       = true,
        projectile = {
            type        = "AoE",
            shape       = "Circle",
            shapeParams = {
                range = 6.5,
            },
            primaryMultiplier = 1.2,
            splashMultiplier  = 0.8,
            speed             = 45,
            lifetime          = 4,
        },

        animations = {
            basicAttack = getAnim("Arcanist"),
        },

        innateBonuses = {
            BonusDamage   = 10,
            DamagePercent = 15,
        },

        statDerivation = {
            Health            = { VIT = 10.0 },
            Damage            = { MAG = 4.0  },
            Armor             = { MIG = 0.3  },
            Penetration       = { MAG = 0.45 },
            CritChance        = { PRE = 0.18 },
            CritDamage        = {},                       -- §AGX/BAL, §T1.2-BAL1: no class scales CritDamage (see header)
            CastTimeReduction = { PRE = 0.35 },           -- §T1.2/DQ1 — caster-only, by design (optional in DerivedStats)
            CooldownReduction = { RSV = 0.55 },
            StatusResistance  = { RSV = 0.8  },
            ResourceMax       = { MAG = 2.5, RSV = 1.0 },
        },
    },

    Hunter = {
        name        = "Hunter",
        gendered    = true,
        description = "A deadly marksman who fells enemies with precision and speed.",

        default            = true,
        unlockRequirements = {},

        weaponXPRole = "dps",
        ranged       = true,
        projectile = {
            type              = "Pierce",
            maxHits           = 3,
            damageReduction   = 0.15,
            minDamageFraction = 0.70,
            speed             = 70,
            lifetime          = 3,
        },

        animations = {
            basicAttack = getAnim("Hunter"),
        },

        innateBonuses = {
            CritChance    = 10,
            CritDamage    = 0.15,
            MovementSpeed = 8,
        },

        statDerivation = {
            Health            = { VIT = 10.0 },
            Damage            = { MIG = 1.5, PRE = 2.0 },
            Armor             = { MIG = 0.5  },
            Penetration       = { PRE = 0.4  },
            CritChance        = { PRE = 0.65 },
            CritDamage        = {},                       -- §AGX/BAL: none for every class (T1.2-BAL1, see header)
            CooldownReduction = { RSV = 0.45 },
            StatusResistance  = { RSV = 0.7  },
            ResourceMax       = { RSV = 1.5  },
        },
    },

    -- ═══════════════════════════════════════════════════════
    -- SUPPORT CLASSES
    -- ═══════════════════════════════════════════════════════

    LifeSteward = {
        name        = "Life Steward",
        gendered    = true,   -- "Life Steward" / "Life Stewardess"
        description = "A devoted healer who channels the power of nature to mend allies and cleanse afflictions.",

        default            = true,
        unlockRequirements = {},

        weaponXPRole = "healer",
        ranged       = true,
        projectile = {
            type            = "Pierce",
            maxHits         = 1,
            damageReduction = 0,
            speed           = 35,
            lifetime        = 3,
        },

        animations = {
            basicAttack = getAnim("LifeSteward"),
        },

        innateBonuses = {
            HealingPercent = 15,
            HealthPercent  = 10,
        },

        statDerivation = {
            -- MAG drives healing power; VIT for survivability; RSV for CDR + resources
            Health            = { VIT = 12.0 },
            Damage            = { MAG = 2.5  },
            Armor             = { MIG = 0.5  },
            Penetration       = { MAG = 0.25 },
            CritChance        = { PRE = 0.18 },
            CritDamage        = {},                       -- §AGX/BAL: none for every class (T1.2-BAL1, see header)
            CastTimeReduction = { PRE = 0.25 },           -- §T1.2/DQ1 — caster-only (LifeSteward casts heals/cleanses)
            CooldownReduction = { RSV = 0.65 },
            StatusResistance  = { RSV = 1.0  },
            ResourceMax       = { MAG = 1.5, RSV = 1.5 },
        },
    },
}

-- Default class for new players (first one selected on creation).
ClassConfig.DefaultClass = "Aegis"

-- ═══════════════════════════════════════════════════════════
-- DERIVED CONFIG  (§T1.2/D5 — single source of truth)
-- Derives the default-unlocked list and the unlock-requirements map
-- from ClassConfig.Classes, so adding a class is a one-file change.
-- ═══════════════════════════════════════════════════════════

--- Ordered list of class names that should be unlocked for every new
--- player at first spawn.
function ClassConfig.GetDefaultUnlockedClasses()
    local result = {}
    for className, classDef in pairs(ClassConfig.Classes) do
        if classDef.default == true then
            table.insert(result, className)
        end
    end
    table.sort(result)
    return result
end

--- Map of className → unlockRequirements table. Every entry in
--- ClassConfig.Classes contributes — `{}` means "no gating, free to
--- claim once it's unlocked at first spawn or via UnlockClass."
function ClassConfig.GetUnlockRequirementsMap()
    local result = {}
    for className, classDef in pairs(ClassConfig.Classes) do
        result[className] = classDef.unlockRequirements or {}
    end
    return result
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

--- Return the display name for a class, respecting gender where applicable.
--- Falls back to the canonical name for non-gendered classes.
function ClassConfig.GetClassTitle(className, gender)
    local classData = ClassConfig.Classes[className]
    if not classData then return className end
    if not classData.gendered then return classData.name end

    local Modules = script.Parent
    local charConfigModule = Modules:FindFirstChild("CharacterConfig")
    if charConfigModule then
        local CharacterConfig = require(charConfigModule)
        return CharacterConfig.GetClassTitle(className, gender)
    end

    return classData.name  -- masculine fallback if CharacterConfig is unavailable
end

function ClassConfig.GetClassNames()
    local names = {}
    for className, _ in pairs(ClassConfig.Classes) do
        table.insert(names, className)
    end
    table.sort(names)
    return names
end

function ClassConfig.IsValidClass(className)
    return ClassConfig.Classes[className] ~= nil
end

function ClassConfig.GetClass(className)
    return ClassConfig.Classes[className]
end

-- ═══════════════════════════════════════════════════════════
-- VALIDATE  (§T1.2/D6)
-- Boot-time sanity check on every class's statDerivation table.
-- Reads PlayerDataConfig.DerivedStats as the catalog of which stats
-- are required-for-all-classes vs optional. Loud-warn on:
--   • required stat missing from a class's statDerivation
--   • unknown stat name in a class's statDerivation
-- The validator runs once at module load; if PlayerDataConfig isn't
-- loadable for any reason we skip silently (boot-order safe).
-- ═══════════════════════════════════════════════════════════

local function validate()
    local ok, PlayerDataConfig = pcall(require, script.Parent:WaitForChild("PlayerDataConfig"))
    if not ok or type(PlayerDataConfig) ~= "table" then return end
    local catalog = PlayerDataConfig.DerivedStats
    if type(catalog) ~= "table" then return end

    for className, classDef in pairs(ClassConfig.Classes) do
        local sd = classDef.statDerivation or {}

        -- Missing-required check
        for statName, meta in pairs(catalog) do
            if meta.required and sd[statName] == nil then
                warn(string.format(
                    "[ClassConfig] %s.statDerivation is missing required derived stat: %s",
                    className, statName))
            end
        end

        -- Unknown-stat check
        for statName, _ in pairs(sd) do
            if not catalog[statName] then
                warn(string.format(
                    "[ClassConfig] %s.statDerivation has unknown derived stat: %s " ..
                    "(add it to PlayerDataConfig.DerivedStats or remove it from the class)",
                    className, statName))
            end
        end
    end
end

-- Run validation once at module load.
task.spawn(validate)

return ClassConfig
