-- StatsManager

local StatsManager = {}

local Modules = script.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))
local DataManager = require(Modules:WaitForChild("PlayerDataManager"))

--============================================
-- LOAD SUB-SYSTEMS
--============================================
local DamageSystem = require(script:WaitForChild("DamageSystem"))
local ArmorSystem   = require(script:WaitForChild("ArmorSystem"))
local CriticalSystem = require(script:WaitForChild("CriticalSystem"))

-- Wire sub-systems together
DamageSystem.ArmorSystem    = ArmorSystem
DamageSystem.CriticalSystem = CriticalSystem

print("[StatsManager] ArmorSystem loaded")
print("[StatsManager] CriticalSystem loaded")

-- Expose sub-systems
StatsManager.Damage = DamageSystem
StatsManager.Armor = ArmorSystem
StatsManager.Critical = CriticalSystem

--============================================
-- STAT GETTERS (Now routes through PlayerDataManager)
--============================================

-- Get system stat (Armor, Crit, Penetration, etc.)
function StatsManager.GetStat(player, statName)
	return DataManager.GetSystemStat(player, statName)
end

-- Set system stat
function StatsManager.SetStat(player, statName, value)
	return DataManager.SetSystemStat(player, statName, value)
end

-- Get bonus stat
function StatsManager.GetBonus(player, bonusName)
	return DataManager.GetBonus(player, bonusName)
end

-- Set bonus stat
function StatsManager.SetBonus(player, bonusName, value)
	return DataManager.SetBonus(player, bonusName, value)
end

-- Modify bonus stat
function StatsManager.ModifyBonus(player, bonusName, delta)
	return DataManager.ModifyBonus(player, bonusName, delta)
end

--============================================
-- TOTAL STAT GETTERS (Base + Allocated + Bonuses)
--============================================
function StatsManager.GetTotalHealth(player)
	return DataManager.GetTotalStat(player, "Health")
end

function StatsManager.GetTotalDamage(player)
	return DataManager.GetTotalStat(player, "Damage")
end

-- Generic total stat getter
function StatsManager.GetTotalStat(player, statName)
	return DataManager.GetTotalStat(player, statName)
end

--============================================
-- ALLOCATION SHORTCUTS
--============================================
function StatsManager.GetAllocatedStat(player, statName)
	return DataManager.GetAllocatedStat(player, statName)
end

function StatsManager.GetAvailablePoints(player)
	return DataManager.GetAvailablePoints(player)
end

function StatsManager.GetUnallocatedPoints(player)
	return DataManager.GetUnallocatedPoints(player)
end

--============================================
-- DAMAGE CALCULATIONS
--============================================
function StatsManager.CalculateDamage(player, targetMob, options)
	return DamageSystem.CalculateOutgoingDamage(player, targetMob, options)
end

function StatsManager.CalculateDamageTaken(player, incomingDamage, attackerPenetration)
	return DamageSystem.CalculateIncomingDamage(player, incomingDamage, attackerPenetration)
end

--============================================
-- DEBUG
--============================================
function StatsManager.GetDebugInfo(player)
	local lines = {
		"=== StatsManager Debug ===",
		"Total Health: " .. StatsManager.GetTotalHealth(player),
		"Total Damage: " .. StatsManager.GetTotalDamage(player),
		"Available Points: " .. StatsManager.GetAvailablePoints(player),
		"Unallocated Points: " .. StatsManager.GetUnallocatedPoints(player),
	}

	if ArmorSystem then
		table.insert(lines, "Armor: " .. (StatsManager.GetStat(player, "Armor") or 0))
		table.insert(lines, "Penetration: " .. (StatsManager.GetStat(player, "Penetration") or 0))
	end

	if CriticalSystem then
		table.insert(lines, "CritChance: " .. (StatsManager.GetStat(player, "CritChance") or 0))
		table.insert(lines, "CritDamage: " .. (StatsManager.GetStat(player, "CritDamage") or 0))
	end

	return table.concat(lines, "\n")
end

return StatsManager