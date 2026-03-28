-- ReplicatedStorage/Shared/DifficultyConfig
--[[
    Defines difficulty tiers for wave-based defense missions.

    Each tier has multipliers applied to:
      • Mob stats (health, damage, armor) — post-multiplied after level scaling
      • Mob speed — flat bonus added to base speed
      • Wave composition (mob count, spawn interval) — affects wave scaling
      • Reward scaling — bonus XP/Merits/Essence

    Usage:
      local DifficultyConfig = require(Shared:WaitForChild("DifficultyConfig"))
      local diff = DifficultyConfig.GetDifficulty("Hard")
      local effectiveHP = scaledHP * diff.hpMult

    The active difficulty is stored per-session in MobSpawner (not persisted to
    player data, since it's a group/lobby setting).
]]

local DifficultyConfig = {}

-- ═══════════════════════════════════════════════════════════
-- DIFFICULTY TIERS
-- ═══════════════════════════════════════════════════════════

local TIERS = {
    Normal = {
        label       = "Normal",
        description = "Standard difficulty. Balanced for your level.",
        order       = 1,
        requiredLevel = 1,     -- minimum account level to queue

        -- Mob stat multipliers (post-level-scaling)
        hpMult      = 1.0,
        damageMult  = 1.0,
        armorMult   = 1.0,
        speedBonus  = 0,       -- flat addition to base speed

        -- Wave composition multipliers
        countMult   = 1.0,     -- multiplied against mob count
        intervalMult = 1.0,    -- multiplied against spawn interval (lower = faster)

        -- Reward multipliers
        meritMult   = 1.0,
        essenceMult = 1.0,
        xpMult      = 1.0,
    },

    Hard = {
        label       = "Hard",
        description = "Tougher enemies, better rewards.",
        order       = 2,
        requiredLevel = 30,

        hpMult      = 1.45,
        damageMult  = 1.25,
        armorMult   = 1.15,
        speedBonus  = 1,

        -- Tighter multipliers keep the 12-wave run inside the 9–10 min band
        countMult   = 1.10,
        intervalMult = 0.95,

        meritMult   = 1.25,
        essenceMult = 1.25,
        xpMult      = 1.25,
    },

    Nightmare = {
        label       = "Nightmare",
        description = "Relentless hordes. Only the strongest survive.",
        order       = 3,
        requiredLevel = 80,

        hpMult      = 2.15,
        damageMult  = 1.60,
        armorMult   = 1.35,
        speedBonus  = 2,

        -- Moderate composition increase — difficulty comes from stats, not body flood
        countMult   = 1.20,
        intervalMult = 0.90,

        meritMult   = 1.75,
        essenceMult = 2.0,
        xpMult      = 1.5,
    },
}

-- ═══════════════════════════════════════════════════════════
-- DEFAULTS
-- ═══════════════════════════════════════════════════════════

local DEFAULT_TIER = "Normal"

-- Sentinel "no-op" multiplier set returned when a bad key is queried so callers
-- never have to nil-check every field.
local IDENTITY = {
    label = "Normal", description = "", order = 0,
    hpMult = 1, damageMult = 1, armorMult = 1, speedBonus = 0,
    countMult = 1, intervalMult = 1,
    meritMult = 1, essenceMult = 1, xpMult = 1,
}

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════

--- Get the multiplier table for a difficulty tier.
--- Returns the IDENTITY set if the tier name is invalid.
function DifficultyConfig.GetDifficulty(tierName)
    return TIERS[tierName] or IDENTITY
end

--- Get the default difficulty tier name.
function DifficultyConfig.GetDefault()
    return DEFAULT_TIER
end

--- Get all tier names in order.
function DifficultyConfig.GetTierNames()
    local names = {}
    for name, _ in pairs(TIERS) do
        table.insert(names, name)
    end
    table.sort(names, function(a, b)
        return TIERS[a].order < TIERS[b].order
    end)
    return names
end

--- Check if a tier name is valid.
function DifficultyConfig.IsValid(tierName)
    return TIERS[tierName] ~= nil
end

--- Auto-select the highest difficulty tier that ALL provided levels qualify for.
--- @param levels {number} array of account levels (one per party member)
--- @return string tier name
function DifficultyConfig.AutoSelect(levels)
    local minLevel = math.huge
    for _, lvl in ipairs(levels) do
        if lvl < minLevel then minLevel = lvl end
    end

    local best = DEFAULT_TIER
    local bestOrder = 0
    for name, tier in pairs(TIERS) do
        if minLevel >= (tier.requiredLevel or 1) and tier.order > bestOrder then
            best = name
            bestOrder = tier.order
        end
    end
    return best
end

return DifficultyConfig
