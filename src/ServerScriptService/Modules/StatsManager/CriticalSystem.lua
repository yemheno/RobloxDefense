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
-- APPLY CRIT (Multi-Crit Enabled)
-- 150% crit = 1 guaranteed + 50% chance for another
-- Returns: finalDamage, wasCrit, critProcs
-- ═══════════════════════════════════════════════════════════
function CriticalSystem.ApplyCrit(player, baseDamage)
	local critChance = CriticalSystem.GetCritChance(player)
	local critMultiplier = CriticalSystem.GetCritDamage(player)

	local finalDamage = baseDamage
	local critProcs = 0

	-- Loop for multi-crit
	local remainingChance = critChance
	while remainingChance > 0 do
		if remainingChance >= 100 then
			-- Guaranteed crit
			critProcs = critProcs + 1
			remainingChance = remainingChance - 100
		else
			-- Roll for crit
			if math.random(100) <= remainingChance then
				critProcs = critProcs + 1
			end
			break
		end
	end

	-- Apply multiplier for each crit proc
	if critProcs > 0 then
		for i = 1, critProcs do
			finalDamage = finalDamage * critMultiplier
		end
	end

	local wasCrit = critProcs > 0

	return finalDamage, wasCrit, critProcs
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════
function CriticalSystem.GetDebugInfo(player)
	return {
		CritChance = CriticalSystem.GetCritChance(player),
		CritDamage = CriticalSystem.GetCritDamage(player),
	}
end

return CriticalSystem