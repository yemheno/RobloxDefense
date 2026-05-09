-- CriticalSystem

local CriticalSystem = {}

local Modules = script.Parent.Parent
local DataManager = require(Modules:WaitForChild("PlayerDataManager"))

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
-- APPLY CRIT (Multi-Crit with Caps per §40)
-- CritChance capped at 200%, CritDamage capped at 1.80x
-- 150% crit = 1 guaranteed + 50% chance for another
-- Returns: finalDamage, wasCrit, critProcs
-- ═══════════════════════════════════════════════════════════
function CriticalSystem.ApplyCrit(player, baseDamage)
	local critChance = CriticalSystem.GetCritChance(player)
	local critMultiplier = CriticalSystem.GetCritDamage(player)

	-- Apply caps per §40.1
	local clampedCritChance = math.min(critChance, 200)
	critMultiplier = math.min(critMultiplier, 1.80)

	local finalDamage = baseDamage
	local critProcs = 0

	-- Geometric multi-crit per §40.2
	local guaranteedProcs = math.floor(clampedCritChance / 100)
	local overflowChance = (clampedCritChance % 100) / 100
	local extraProc = (math.random() < overflowChance) and 1 or 0
	critProcs = guaranteedProcs + extraProc
	critProcs = math.min(critProcs, 2)  -- Cap at 2 procs max (200% crit = 1.8x1.8)

	-- Apply multiplier for each crit proc (geometric)
	if critProcs > 0 then
		local finalMultiplier = 1.0
		for _ = 1, critProcs do
			finalMultiplier = finalMultiplier * critMultiplier
		end
		finalDamage = finalDamage * finalMultiplier
	end

	local wasCrit = critProcs > 0

	return finalDamage, wasCrit, critProcs
end

return CriticalSystem