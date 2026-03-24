-- ServerScriptService/Modules/ElementalSystem
--[[
    Elemental System
    ================
    Four elements form a one-directional advantage cycle:
        Wood → Earth → Water → Fire → Wood

    "A beats B" means:
        attacking with A against a B-element defender  →  1.25x damage
        attacking with B against an A-element defender →  0.85x damage
        same element vs same element                   →  1x damage
        either side is None (physical / untyped)       →  1x damage

    Multipliers: 1.25 / 1.0 / 0.85
]]

local ElementalSystem = {}

-- ═══════════════════════════════════════════════════════════
-- ADVANTAGE TABLE
-- STRONG_AGAINST[attacker] = the element it beats
-- ═══════════════════════════════════════════════════════════

local STRONG_AGAINST = {
	Wood  = "Earth",
	Earth = "Water",
	Water = "Fire",
	Fire  = "Wood",
}

-- ═══════════════════════════════════════════════════════════
-- MULTIPLIER LOOKUP
-- ═══════════════════════════════════════════════════════════

--[[
    GetMultiplier(attackElement, defenderElement)
    Returns the damage multiplier to apply to the attack.
        1.25 →  attackElement beats defenderElement  (Strong)
        0.85 →  defenderElement beats attackElement  (Weak)
        1.0  →  neutral (same, untyped, or unrelated pair)
]]
function ElementalSystem.GetMultiplier(attackElement, defenderElement)
	-- Untyped attacks/defenders are always neutral
	if not attackElement  or attackElement  == "None" then return 1.0 end
	if not defenderElement or defenderElement == "None" then return 1.0 end

	-- Same element — neutral
	if attackElement == defenderElement then return 1.0 end

	-- Attacker beats defender → Strong
	if STRONG_AGAINST[attackElement] == defenderElement then
		return 1.25
	end

	-- Defender beats attacker → Weak
	if STRONG_AGAINST[defenderElement] == attackElement then
		return 0.85
	end

	-- Unrelated pair (e.g. Wood vs Water) — neutral
	return 1.0
end

-- ═══════════════════════════════════════════════════════════
-- INTERACTION LABEL  (used for damage number display)
-- ═══════════════════════════════════════════════════════════

--[[
    Returns "Strong", "Weak", or "Neutral".
    Useful for showing elemental feedback on the client.
]]
function ElementalSystem.GetInteractionLabel(attackElement, defenderElement)
	local mult = ElementalSystem.GetMultiplier(attackElement, defenderElement)
	if mult > 1.0 then
		return "Strong"
	elseif mult < 1.0 then
		return "Weak"
	else
		return "Neutral"
	end
end

-- ═══════════════════════════════════════════════════════════
-- ELEMENT READERS (read from live instances / data tables)
-- ═══════════════════════════════════════════════════════════

-- Get the element of a mob model (set as a Roblox Attribute at spawn time)
function ElementalSystem.GetMobElement(mob)
	if not mob then return "None" end
	return mob:GetAttribute("MobElement") or "None"
end

-- Get the element from a weapon definition table (from WeaponRegistry)
function ElementalSystem.GetWeaponElement(weaponDef)
	return (weaponDef and weaponDef.element) or "None"
end

return ElementalSystem
