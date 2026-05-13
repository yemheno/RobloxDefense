-- ServerScriptService/Modules/StatsManager/HealingSystem
--[[
    HealingSystem
    =============
    Outgoing-heal pipeline. Mirrors DamageSystem so the network payload
    and client renderer can share code.

    Healing formula
    ───────────────
      1. Base healing  = HealingPower (MAG-derived via the Damage stat)
                         + flat HealingPower bonus
      2. Skill coeff   = skill.healMultiplier (e.g. 1.0 = 100% baseHeal)
      3. % modifier    = HealingPercent bonus (additive percent)
      4. Critical heal = CriticalSystem.ApplyCrit  (§T1.3/B14)
      5. Floor + zero-clamp

    Healing scales with MAG  (§T1.3/B2)
    ──────────────────────────────────────
    We deliberately read the player's Damage stat as the healing-power
    base. Healing was designed to ride the SAME stat pipeline as damage
    so:
      • LifeSteward's statDerivation has Damage scaling from MAG; that
        same MAG-driven Damage value is the heal scaling input.
      • A dedicated `HealingPower` derived stat could be split out later
        (see TODO §T1.3-DQ2) — useful when PvP arrives and we want
        damage-vs-heal scaling to diverge. The override hook (the
        `options` table) is the seam where that split lives.

    Critical heals  (§T1.3/B14)
    ───────────────────────────
    Heals use the same multi-crit pipeline as damage via
    CriticalSystem.ApplyCrit. CritChance + CritDamage caps come from
    PlayerDataConfig.StatCaps — heals and damage cap together. Balance
    is done per-skill via healMultiplier (not by capping heals
    separately).
]]

local HealingSystem = {}

local Modules = script.Parent.Parent
local DataManager = require(Modules:WaitForChild("PlayerDataManager"))

-- Sub-system reference (set by StatsManager wiring at init time).
HealingSystem.CriticalSystem = nil

-- ═══════════════════════════════════════════════════════════
-- BASE HEALING POWER
-- ═══════════════════════════════════════════════════════════

function HealingSystem.GetBaseHealing(healer)
    -- §T1.3/B2: Damage stat IS the magic-power input for heals. See
    -- header comment for the rationale + future-split hook.
    local healingPower = DataManager.GetTotalStat(healer, "Damage") or 10
    local flatBonus    = DataManager.GetBonus(healer, "HealingPower") or 0
    return healingPower + flatBonus
end

-- ═══════════════════════════════════════════════════════════
-- CALCULATE OUTGOING HEAL
-- ═══════════════════════════════════════════════════════════
--[[  options (optional table):
        healMultiplier  (number)  — skill coefficient (default 1.0)
        canCrit         (bool)    — disable crits for this heal (default true)
]]
function HealingSystem.CalculateHeal(healer, options)
    options = options or {}

    local baseHeal       = HealingSystem.GetBaseHealing(healer)
    local healMultiplier = options.healMultiplier or 1.0
    local heal           = baseHeal * healMultiplier

    -- HealingPercent buff (additive %)
    local healBonus = DataManager.GetBonus(healer, "HealingPercent") or 0
    if healBonus ~= 0 then
        heal = heal * (1 + healBonus / 100)
    end

    -- §T1.3/B14: same crit pipeline as damage. Multi-crit, geometric,
    -- StatCaps-driven. Skill-side balance is in healMultiplier.
    local wasCrit, critProcs = false, 0
    if options.canCrit ~= false and HealingSystem.CriticalSystem then
        heal, wasCrit, critProcs = HealingSystem.CriticalSystem.ApplyCrit(healer, heal)
    end

    -- §T1.3/B7: zero-clamp the final value. No upstream guard exists
    -- below GetTotalStat's own clamp once flat bonuses + multipliers
    -- enter the chain, so a perverse stack of negative bonuses won't
    -- produce a "negative heal" (= effectively damage) here.
    return {
        heal      = math.max(0, math.floor(heal)),
        wasCrit   = wasCrit,
        critProcs = critProcs,
    }
end

return HealingSystem
