-- ServerScriptService/Modules/PlayerDataManager/PlayerStatSystem

local PlayerStatSystem = {}

local Modules = script.Parent.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))
local ClassConfig = require(Modules:WaitForChild("ClassConfig"))

-- Set by PlayerDataManager
PlayerStatSystem.PlayerDataManager = nil
PlayerStatSystem.GetDataStore = nil

--============================================
-- INITIALIZATION
--============================================
function PlayerStatSystem.Init()
	print("[PlayerStatSystem] Initialized")
end

--============================================
-- HEALTH APPLICATION
--============================================
function PlayerStatSystem.ApplyHealthToCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	local totalHealth = math.floor(PlayerStatSystem.GetTotalStat(player, "Health"))

	-- Scale current HP proportionally so stat changes don't full-heal.
	-- First spawn (MaxHealth == 100, the Roblox default) is treated as a full heal.
	-- IMPORTANT: Read Health before setting MaxHealth, because Roblox auto-clamps
	-- Health to MaxHealth when MaxHealth is reduced.
	local oldMax = humanoid.MaxHealth
	local oldHealth = humanoid.Health
	humanoid.MaxHealth = totalHealth

	if oldMax > 0 and oldMax ~= 100 then
		-- Preserve HP percentage (using pre-clamp oldHealth)
		local ratio = math.clamp(oldHealth / oldMax, 0, 1)
		humanoid.Health = math.max(1, math.floor(totalHealth * ratio))
	else
		-- First application: start at full health
		humanoid.Health = totalHealth
	end
end

function PlayerStatSystem.ResetHealth(player)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local totalHealth = math.floor(PlayerStatSystem.GetTotalStat(player, "Health"))
	humanoid.MaxHealth = totalHealth
	humanoid.Health = totalHealth

	print("[PlayerStatSystem] Reset health for", player.Name)
end

--============================================
-- POINT MANAGEMENT
--============================================
function PlayerStatSystem.GetAvailablePoints(player)
	local playerDataStore = PlayerStatSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return 0 end

	return Config.GetAvailablePoints(data.Account.Level)
end

function PlayerStatSystem.GetSpentPoints(player, className)
	local playerDataStore = PlayerStatSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return 0 end

	className = className or data.ActiveClass
	local classData = data.Classes[className]
	if not classData then return 0 end

	-- Only count known PrimaryStats keys — orphaned keys from renamed stats must
	-- not be counted or they silently inflate the spent total, draining the
	-- unallocated budget and showing 0 points available in the UI.
	local spent = 0
	for _, statName in ipairs(Config.PrimaryStats) do
		spent = spent + (classData.Allocated[statName] or 0)
	end

	return spent
end

function PlayerStatSystem.GetUnallocatedPoints(player, className)
	local available = PlayerStatSystem.GetAvailablePoints(player)
	local spent = PlayerStatSystem.GetSpentPoints(player, className)

	return available - spent
end

--============================================
-- STAT ALLOCATION
--============================================
function PlayerStatSystem.GetAllocatedStat(player, statName, className)
	local playerDataStore = PlayerStatSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return 0 end

	className = className or data.ActiveClass
	local classData = data.Classes[className]
	if not classData then return 0 end

	return classData.Allocated[statName] or 0
end

function PlayerStatSystem.AllocateStat(player, statName, points)
	local playerDataStore = PlayerStatSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return false, "No player data" end

	-- Validate stat is a primary stat
	local isAllocatable = false
	for _, name in ipairs(Config.PrimaryStats) do
		if name == statName then
			isAllocatable = true
			break
		end
	end

	if not isAllocatable then
		return false, "Not a primary stat: " .. tostring(statName)
	end

	-- Check available points
	local unallocated = PlayerStatSystem.GetUnallocatedPoints(player)
	if points > unallocated then
		return false, "Not enough points"
	end

	if points < 0 then
		return false, "Cannot allocate negative points"
	end

	-- Apply allocation
	local classData = data.Classes[data.ActiveClass]
	classData.Allocated[statName] = (classData.Allocated[statName] or 0) + points

	-- Refresh character health if a health-affecting primary was changed
	if (statName == "VIT" or statName == "MIG") and player.Character then
		PlayerStatSystem.ApplyHealthToCharacter(player, player.Character)
	end

	return true
end

function PlayerStatSystem.DeallocateStat(player, statName, points)
	local playerDataStore = PlayerStatSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return false, "No player data" end

	local classData = data.Classes[data.ActiveClass]
	local currentAllocation = classData.Allocated[statName] or 0

	if points > currentAllocation then
		return false, "Cannot deallocate more than allocated"
	end

	classData.Allocated[statName] = currentAllocation - points

	if (statName == "VIT" or statName == "MIG") and player.Character then
		PlayerStatSystem.ApplyHealthToCharacter(player, player.Character)
	end

	return true
end

function PlayerStatSystem.ResetAllocation(player, className)
	local playerDataStore = PlayerStatSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return false end

	className = className or data.ActiveClass
	local classData = data.Classes[className]
	if not classData then return false end

	-- Rebuild Allocated with only current PrimaryStats set to 0.
	-- Using pairs() and zeroing preserves orphaned keys; we replace the table
	-- outright so deleted/renamed stats are fully removed.
	local fresh = {}
	for _, statName in ipairs(Config.PrimaryStats) do
		fresh[statName] = 0
	end
	classData.Allocated = fresh

	if className == data.ActiveClass and player.Character then
		PlayerStatSystem.ApplyHealthToCharacter(player, player.Character)
	end

	return true
end

--============================================
-- TOTAL STAT CALCULATION
-- Returns the full value of a derived stat for a player.
--
-- Formula:
--   total = DerivedBase
--         + sum over class.statDerivation[stat]:
--               (PrimaryBase[primary] + allocatedPoints) * coefficient
--         + data.Bonus[stat]                    (flat bonus from weapons/buffs)
--         ) * (1 + data.Bonus[stat.."Percent"] / 100)
--============================================
function PlayerStatSystem.GetTotalStat(player, derivedStatName)
	local playerDataStore = PlayerStatSystem.GetDataStore()
	local data = playerDataStore[player]

	-- 1. Derived base value (everyone starts here)
	local base = Config.DerivedBase[derivedStatName] or 0
	if not data then return base end

	-- 2. Primary stat contributions via class derivation formula
	local className = data.ActiveClass
	local classConfig = ClassConfig.Classes[className]
	local derivation = classConfig
		and classConfig.statDerivation
		and classConfig.statDerivation[derivedStatName]

	local primaryContribution = 0
	if derivation then
		local allocated = data.Classes[className] and data.Classes[className].Allocated or {}
		for primaryStat, coefficient in pairs(derivation) do
			local primaryBase     = Config.PrimaryBase[primaryStat] or 0
			local allocatedPoints = allocated[primaryStat] or 0
			-- BonusMIG / BonusVIT / etc. come from talent nodes (and future items).
			-- They are treated as extra allocated points so they scale through the
			-- same class derivation coefficients as normal stat investment.
			local talentBonus     = data.Bonus["Bonus" .. primaryStat] or 0
			primaryContribution   = primaryContribution + (primaryBase + allocatedPoints + talentBonus) * coefficient
		end
	end

	-- 3. Flat bonus (weapons, buffs, skill effects — stored in data.Bonus)
	local flatBonus = data.Bonus[derivedStatName] or 0
	-- BonusHealth is a separate key that feeds into the Health stat
	if derivedStatName == "Health" then
		flatBonus = flatBonus + (data.Bonus["BonusHealth"] or 0)
	end

	-- 4. Percent modifier (e.g. HealthPercent from innate or equipment)
	local percentBonus = data.Bonus[derivedStatName .. "Percent"] or 0

	local rawTotal = base + primaryContribution + flatBonus
	-- Clamp to zero — no derived stat should ever go negative
	return math.max(0, rawTotal * (1 + percentBonus / 100))
end

--============================================
-- DEBUG
--============================================
function PlayerStatSystem.GetDebugInfo(player)
	local playerDataStore = PlayerStatSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return nil end

	local classData = data.Classes[data.ActiveClass]
	if not classData then return nil end

	local lines = {
		"--- Stats ---",
		"Available: " .. PlayerStatSystem.GetAvailablePoints(player),
		"Unallocated: " .. PlayerStatSystem.GetUnallocatedPoints(player),
	}

	for statName, points in pairs(classData.Allocated) do
		local total = PlayerStatSystem.GetTotalStat(player, statName)
		table.insert(lines, statName .. ": " .. points .. " pts → " .. total .. " total")
	end

	return table.concat(lines, "\n")
end

return PlayerStatSystem