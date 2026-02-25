-- ArmorSystem

local ArmorSystem = {}

local Modules = script.Parent.Parent
local DataManager = require(Modules:WaitForChild("PlayerDataManager"))

-- ═══════════════════════════════════════════════════════════
-- GET ARMOR VALUE
-- ═══════════════════════════════════════════════════════════
function ArmorSystem.GetArmor(player)
	return DataManager.GetTotalStat(player, "Armor") or 0
end

-- ═══════════════════════════════════════════════════════════
-- GET PENETRATION VALUE
-- ═══════════════════════════════════════════════════════════
function ArmorSystem.GetPenetration(player)
	return DataManager.GetTotalStat(player, "Penetration") or 0
end

-- ═══════════════════════════════════════════════════════════
-- APPLY ARMOR REDUCTION
-- Reduces incoming damage by armor, minus attacker penetration
-- ═══════════════════════════════════════════════════════════
function ArmorSystem.ApplyArmor(player, incomingDamage, attackerPenetration)
	attackerPenetration = attackerPenetration or 0

	local armor = ArmorSystem.GetArmor(player)
	local effectiveArmor = math.max(0, armor - attackerPenetration)
	local reducedDamage = math.max(1, incomingDamage - effectiveArmor)

	return reducedDamage
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════
function ArmorSystem.GetDebugInfo(player)
	return {
		Armor = ArmorSystem.GetArmor(player),
		Penetration = ArmorSystem.GetPenetration(player),
	}
end

return ArmorSystem