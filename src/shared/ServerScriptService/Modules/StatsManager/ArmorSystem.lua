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
-- APPLY ARMOR REDUCTION (Division-based mitigation)
-- armorMultiplier = 100 / (100 + effectiveArmor)
--
-- §T1.3/B6: no inner min-1 clamp. The single floor lives in
-- DamageSystem.CalculateIncomingDamage (the only caller), so intermediate
-- values (legitimately < 1 if armor is enormous) don't round up early.
-- ═══════════════════════════════════════════════════════════
function ArmorSystem.ApplyArmor(player, incomingDamage, attackerPenetration)
	attackerPenetration = attackerPenetration or 0

	local armor = ArmorSystem.GetArmor(player)
	local effectiveArmor = math.max(0, armor - attackerPenetration)
	local armorMultiplier = 100 / (100 + effectiveArmor)
	return incomingDamage * armorMultiplier
end

return ArmorSystem