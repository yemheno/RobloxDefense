# RobloxDefense Content Creation Guide

This guide explains how to add new classes, class skills, mob skills, mobs, and wave usage with the current auto-loading architecture.

## Quick architecture map

- Class definitions: `src/ServerScriptService/Modules/ClassConfig.lua`
- Class resources/passives: `src/ServerScriptService/Modules/ClassBehaviors/*Behavior.lua`
- Class skills: `src/ServerScriptService/Modules/ClassSkills/*.lua`
- Weapon definitions by class: `src/ServerScriptService/Modules/ClassWeapons/*.lua`
- Mob definitions: `src/ServerScriptService/Modules/Mobs/*.lua`
- Mob skills: `src/ServerScriptService/Modules/MobSkills/*.lua`
- Wave composition: `src/ServerScriptService/Modules/WaveConfig.lua`

Auto-loaded systems:
- `SkillRegistry` auto-loads all class skill modules (except `BaseSkills`).
- `MobSkillRegistry` auto-loads all mob skills.
- `MobRegistry` auto-loads all mobs and validates referenced mob skills.
- `WeaponRegistry` auto-loads all class weapon modules.

---

## 1) Add a new class

### Step A: Define class in `ClassConfig`
Add a new entry under `ClassConfig.Classes`.

Minimum fields used by current systems:
- `name`
- `description`
- `ranged` (boolean)
- Melee: `attackShape`, `shapeParams`
- Ranged: `projectile` table
- `baseAttackSpeed`
- `animations.basicAttack`
- `innateBonuses`
- `statDerivation`
- `resource` (string)

Example:
```luau
Sentinel = {
    name = "Sentinel",
    description = "A tactical spear user.",
    ranged = false,
    attackShape = "Cone",
    shapeParams = { range = 11, angle = 100 },
    baseAttackSpeed = 1.8,
    animations = { basicAttack = "rbxassetid://522635514" },
    innateBonuses = { HealthPercent = 8, Penetration = 5 },
    statDerivation = {
        Health = { VIT = 14 },
        Damage = { MIG = 3.2 },
        Armor = { MIG = 0.8 },
        Penetration = { PRE = 0.6 },
        CritChance = { PRE = 0.5 },
        CritDamage = { PRE = 0.01 },
        CooldownReduction = { RSV = 0.5 },
        StatusResistance = { RSV = 0.7 },
        ResourceMax = { RSV = 1.8 },
    },
    resource = "Focus",
}
```

### Step B: Add resource behavior file
Create `src/ServerScriptService/Modules/ClassBehaviors/SentinelBehavior.lua`.

Important:
- The filename drives class binding in `ResourceManager`.
- Must be exactly `<ClassName>Behavior.lua`.

Template:
```luau
local SentinelBehavior = {}

SentinelBehavior.CONFIG = {
    ResourceName = "Focus",
    MaxResource = 100,
    StartingResource = 20,
    BaseRegen = 4,
    GainPerHitDealt = 1,
    GainPerHitReceived = 0,
}

function SentinelBehavior.Init() end

function SentinelBehavior.GetResourceRate(player, resourceData)
    return SentinelBehavior.CONFIG.BaseRegen
end

function SentinelBehavior.OnHitDealt(player, hitData, resourceData)
    return SentinelBehavior.CONFIG.GainPerHitDealt
end

function SentinelBehavior.OnHitReceived(player, hitData, resourceData)
    return SentinelBehavior.CONFIG.GainPerHitReceived
end

function SentinelBehavior.OnResourceFull(player) end
function SentinelBehavior.OnResourceEmpty(player) end

return SentinelBehavior
```

### Step C: Make class selectable and armed
Update:
- `PlayerDataConfig` unlock/default logic (if needed)
- `WeaponConfig.STARTER_WEAPONS` with a starter weapon id
- Add matching class weapon module in `ClassWeapons`

If class switching is used in your gameplay flow, ensure resource refresh is triggered for switched classes.

---

## 2) Add class skills (player skills)

Create a new file in `ClassSkills`, e.g. `SentinelSkills.lua`.

Required module contract:
- `CLASS = "Sentinel"`
- `Skills` table indexed by slot `[1]..[4]` (or however many you use)
- `Init(baseSkills, skillEffects)`
- `GetAllSkills()`
- `GetSkillBySlot(slot)`
- `GetSkillCount()`
- `Execute(player, skill, inputData)`

Minimal template:
```luau
local SentinelSkills = {}

local Base = nil
local Effects = nil

SentinelSkills.CLASS = "Sentinel"

SentinelSkills.Skills = {
    [1] = {
        id = "PiercingThrust",
        name = "Piercing Thrust",
        description = "Strike enemies in a line.",
        icon = "rbxassetid://0",
        slot = 1,
        resourceCost = 10,
        cooldown = 3,
        skillType = "AreaEffect",
        element = "None",
        castTime = 0,
        lockMovement = false,
        lockSkills = false,
        lockAttack = false,
        canBeInterrupted = false,
        damageMultiplier = 1.5,
        shape = "Rectangle",
        shapeParams = { range = 14, width = 4 },
        animation = "rbxassetid://522638767",
        animationDuration = 0.4,
        debugColor = Color3.fromRGB(200, 200, 255),
        effects = {},
    },
}

function SentinelSkills.Init(baseSkills, skillEffects)
    Base = baseSkills
    Effects = skillEffects
end

function SentinelSkills.GetSkillBySlot(slot)
    return SentinelSkills.Skills[slot]
end

function SentinelSkills.GetAllSkills()
    return SentinelSkills.Skills
end

function SentinelSkills.GetSkillCount()
    local count = 0
    for _ in pairs(SentinelSkills.Skills) do count += 1 end
    return count
end

function SentinelSkills.Execute(player, skill, inputData)
    if skill.id == "PiercingThrust" then
        return Base.ExecuteSimpleDamage(player, skill, inputData)
    end
    return false
end

return SentinelSkills
```

Notes:
- Skill execution is routed by `SkillRegistry` -> class module `Execute`.
- Use `BaseSkills` helpers for targeting/damage/visual dispatch.
- If you add new effect types, implement them in `SkillEffects.ApplyEffect`.

---

## 3) Add a new mob skill

Create `src/ServerScriptService/Modules/MobSkills/<SkillName>.lua`.

Required/common fields:
- `id`, `name`, `skillType`
- `cooldown`, `startOnCooldown`
- `targeting` (`minRange`, `maxRange`, optional `healthThreshold`)
- `animation`, `animationDuration`
- `damageDelay`, `damageWindow`
- `damageMultiplier`
- `shape`, `shapeParams`
- `effects` (optional)
- `visual` (optional but recommended)

Template:
```luau
return {
    id = "ThrowRock",
    name = "Throw Rock",
    skillType = "Projectile",
    cooldown = 8,
    startOnCooldown = true,
    targeting = { minRange = 8, maxRange = 30, healthThreshold = nil },
    animation = "rbxassetid://507770677",
    animationDuration = 0.9,
    damageDelay = 0.5,
    damageWindow = 0.3,
    damageMultiplier = 1.4,
    shape = "Circle",
    shapeParams = { range = 5 },
    effects = {},
    visual = {
        type = "GroundSlam",
        warningDuration = 0.5,
        impactDuration = 0.3,
        color = Color3.fromRGB(130, 110, 90),
        warningColor = Color3.fromRGB(255, 140, 120),
    },
}
```

---

## 4) Add a new mob

Create `src/ServerScriptService/Modules/Mobs/<MobName>.lua`.

Required/common fields:
- `id`, `name`, `description`
- `mobTier` (`normal`, `miniboss`, `boss`)
- `template` (existing model name in `ReplicatedStorage/Mobs`)
- `element`
- `health`, `damage`
- `speed`, `attackRange`, `attackCooldown`, `perceptionRange`
- `animations.attack`, `attackDuration`, `damageDelay`
- `skills` and `skillPriority` (optional)

Template:
```luau
return {
    id = "Bandit",
    name = "Bandit",
    description = "A fast melee skirmisher.",
    mobTier = "normal",
    template = "MobTemplate",
    element = "None",
    health = 140,
    damage = 18,
    speed = 6,
    attackRange = 4,
    attackCooldown = 1.2,
    perceptionRange = 28,
    animations = { attack = "rbxassetid://507768375" },
    attackDuration = 0.45,
    damageDelay = 0.2,
    skills = nil,
    skillPriority = nil,
}
```

Notes:
- Mob stats are level-scaled by `MobRegistry` for `health` and `damage`.
- `MobSpawner` requires template availability in `ReplicatedStorage/Mobs`.

---

## 5) Put mobs into waves

Edit `WaveConfig.lua`:
- For fixed waves: update `WAVE_DEFINITIONS[n].spawnWeights` and `guaranteed`.
- For procedural waves: update `PROCEDURAL_CONFIG.availableMobs` and `availableMinibosses`.

Example:
```luau
spawnWeights = { Zombie = 3, Bandit = 2 }
guaranteed = { "Ogre" }
```

---

## 6) Validation checklist (after adding content)

1. Start server and confirm loader logs show your module loaded.
2. Verify no warnings for missing skills or templates.
3. Trigger combat and confirm:
   - class basic attack works,
   - resource updates appear,
   - skills execute and cooldowns update,
   - mob skills cast and hit feedback appears.
4. Confirm new content appears in waves as configured.

---

## Common pitfalls

- Behavior filename/class mismatch breaks class resource behavior binding.
- Referencing a mob skill id that has no module file causes silent capability loss (warning + partial kit).
- Adding a class without starter weapon mapping leaves players with fallback weapon stats.
- Adding a class without class skill module means slot requests fail for that class.
