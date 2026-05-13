-- ServerScriptService/Modules/StatsManager/CriticalSystem
--[[
    CriticalSystem
    ==============
    Shared crit-roll pipeline used by both DamageSystem and HealingSystem.

    Returns: finalValue, wasCrit, critProcs

    Caps  (§T1.3/B3+B4+B5)
    ───────────────────────
    Both the CritChance cap and the CritDamage cap live in
    PlayerDataConfig.StatCaps. CriticalSystem reads from there — there
    are no magic numbers inside this file. The balance audit can tune
    both caps in one place.

    Multi-crit pipeline  (§40)
    ──────────────────────────
    Geometric procs: a 150% crit chance = 1 guaranteed proc + 50%
    chance for a second proc. Procs capped at 2 max (so 200% CritChance
    × 1.80× CritDamage = 1.80 × 1.80 = 3.24× max multiplier).
    Heals and damage share this pipeline exactly; balance tuning is
    done per-skill via the action / heal multipliers, not by branching
    here.
]]

local CriticalSystem = {}

local Modules = script.Parent.Parent
local DataManager = require(Modules:WaitForChild("PlayerDataManager"))
local Config      = require(Modules:WaitForChild("PlayerDataConfig"))

-- ═══════════════════════════════════════════════════════════
-- CAPS
-- ═══════════════════════════════════════════════════════════

local function getCritChanceCap()
    local caps = Config.StatCaps and Config.StatCaps.CritChance
    return (caps and caps.max) or 200
end

local function getCritDamageCap()
    local caps = Config.StatCaps and Config.StatCaps.CritDamage
    return (caps and caps.max) or 1.80
end

-- ═══════════════════════════════════════════════════════════
-- GET CRIT STATS
-- ═══════════════════════════════════════════════════════════
function CriticalSystem.GetCritChance(player)
    return DataManager.GetTotalStat(player, "CritChance") or 0
end

function CriticalSystem.GetCritDamage(player)
    return DataManager.GetTotalStat(player, "CritDamage") or 1.5
end

-- ═══════════════════════════════════════════════════════════
-- APPLY CRIT  (Multi-Crit per §40)
-- Geometric procs; CritChance & CritDamage caps come from StatCaps.
-- ═══════════════════════════════════════════════════════════
function CriticalSystem.ApplyCrit(player, baseValue)
    local critChance     = CriticalSystem.GetCritChance(player)
    local critMultiplier = CriticalSystem.GetCritDamage(player)

    local clampedCritChance = math.min(critChance,     getCritChanceCap())
    critMultiplier          = math.min(critMultiplier, getCritDamageCap())

    -- Geometric multi-crit per §40.2
    local guaranteedProcs = math.floor(clampedCritChance / 100)
    local overflowChance  = (clampedCritChance % 100) / 100
    local extraProc       = (math.random() < overflowChance) and 1 or 0
    local critProcs       = math.min(guaranteedProcs + extraProc, 2)

    local finalValue = baseValue
    if critProcs > 0 then
        local finalMultiplier = 1.0
        for _ = 1, critProcs do
            finalMultiplier = finalMultiplier * critMultiplier
        end
        finalValue = baseValue * finalMultiplier
    end

    return finalValue, critProcs > 0, critProcs
end

return CriticalSystem
