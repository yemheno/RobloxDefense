-- ServerScriptService/Modules/ElementalSystem
--[[
    Elemental System
    ================
    Four elements form a one-directional advantage cycle:
        Wood → Earth → Water → Fire → Wood

    "A beats B" means:
        attacking with A against a B-element defender  →  2x damage
        attacking with B against an A-element defender →  0.5x damage
        same element vs same element                   →  1x damage
        either side is None (physical / untyped)       →  1x damage

    Multipliers: 2.0 / 1.0 / 0.5
]]

local ElementalSystem = {}

-- ═══════════════════════════════════════════════════════════
-- ELEMENT CONSTANTS
-- ═══════════════════════════════════════════════════════════

ElementalSystem.Elements = {
	Wood  = "Wood",
	Earth = "Earth",
	Water = "Water",
	Fire  = "Fire",
	None  = "None",   -- Physical / untyped — always neutral
}

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
        2.0  →  attackElement beats defenderElement  (Strong)
        0.5  →  defenderElement beats attackElement  (Weak)
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
		return 2.0
	end

	-- Defender beats attacker → Weak
	if STRONG_AGAINST[defenderElement] == attackElement then
		return 0.5
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

-- Get the element from a skill definition table
function ElementalSystem.GetSkillElement(skillDef)
	return (skillDef and skillDef.element) or "None"
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function ElementalSystem.PrintTable()
	print("-- Elemental Interaction Table --")
	local elements = { "Wood", "Earth", "Water", "Fire", "None" }
	for _, atk in ipairs(elements) do
		for _, def in ipairs(elements) do
			local mult = ElementalSystem.GetMultiplier(atk, def)
			if mult ~= 1.0 then
				print(string.format("  %s vs %s → %.1fx", atk, def, mult))
			end
		end
	end
	print("---------------------------------")
end

return ElementalSystem
