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
-- DamageSystem.CalculateIncomingDamage which is the only caller and
-- already enforces math.max(1, math.floor(finalDamage)). Stacking
-- two clamps obscured the pipeline and let intermediate values
-- (which can legitimately be < 1 if armor is enormous) round up
-- prematurely.
-- ═══════════════════════════════════════════════════════════
function ArmorSystem.ApplyArmor(player, incomingDamage, attackerPenetration)
	attackerPenetration = attackerPenetration or 0

	local armor = ArmorSystem.GetArmor(player)
	local effectiveArmor = math.max(0, armor - attackerPenetration)
	local armorMultiplier = 100 / (100 + effectiveArmor)
	return incomingDamage * armorMultiplier
end

return ArmorSystem