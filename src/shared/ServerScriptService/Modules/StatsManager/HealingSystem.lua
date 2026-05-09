-- HealingSystem
--[[
    Mirrors DamageSystem for healing output.

    Healing formula:
    1. Base healing   = MAG-derived HealingPower + flat bonuses
    2. Skill coeff    = skill.healMultiplier (e.g. 1.0 = 100% of HealingPower)
    3. Critical heal  = same multi-crit system as damage
    4. Buff modifiers = HealingPowerUp bonus (additive %)

    Result table matches the DamageSystem shape so the network
    payload and client rendering can share code.
]]

local HealingSystem = {}

local Modules = script.Parent.Parent
local DataManager = require(Modules:WaitForChild("PlayerDataManager"))

-- Sub-system references (set by StatsManager wiring)
HealingSystem.CriticalSystem = nil

-- ═══════════════════════════════════════════════════════════
-- BASE HEALING POWER
-- ═══════════════════════════════════════════════════════════

function HealingSystem.GetBaseHealing(healer)
	-- MAG-derived healing power from the stat derivation system
	local healingPower = DataManager.GetTotalStat(healer, "Damage") or 10

	-- Flat bonus (from gear, talents, etc.)
	local flatBonus = DataManager.GetBonus(healer, "HealingPower") or 0

	return healingPower + flatBonus
end

-- ═══════════════════════════════════════════════════════════
-- CALCULATE OUTGOING HEAL
-- ═══════════════════════════════════════════════════════════
--[[  options (optional table):
        healMultiplier (number) — skill coefficient (default 1.0)
        canCrit        (bool)   — whether the heal can crit (default true)
]]
function HealingSystem.CalculateHeal(healer, options)
	options = options or {}

	local baseHeal = HealingSystem.GetBaseHealing(healer)
	local healMultiplier = options.healMultiplier or 1.0

	local heal = baseHeal * healMultiplier

	-- Healing buff modifier (additive %)
	local healBonus = DataManager.GetBonus(healer, "HealingPercent") or 0
	if healBonus ~= 0 then
		heal = heal * (1 + healBonus / 100)
	end

	-- Critical heal per §40.3: ignore overflow above 100%, cap mult at 1.50x
	local wasCrit = false
	local critProcs = 0
	if options.canCrit ~= false and HealingSystem.CriticalSystem then
		local critChance = HealingSystem.CriticalSystem.GetCritChance(healer)
		local clampedChance = math.min(critChance, 100) -- no multi-crit for heals
		if math.random(100) <= clampedChance then
			local critDamage = HealingSystem.CriticalSystem.GetCritDamage(healer)
			local healCritMult = math.min(critDamage, 1.50)
			heal = heal * healCritMult
			wasCrit = true
			critProcs = 1
		end
	end

	return {
		heal      = math.floor(heal),
		wasCrit   = wasCrit,
		critProcs = critProcs,
	}
end

return HealingSystem
