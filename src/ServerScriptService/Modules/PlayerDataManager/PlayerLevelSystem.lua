-- ServerScriptService/Modules/PlayerDataManager/PlayerLevelSystem

local PlayerLevelSystem = {}

local Modules = script.Parent.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))

-- Set by PlayerDataManager
PlayerLevelSystem.PlayerDataManager = nil
PlayerLevelSystem.GetDataStore = nil

--============================================
-- INITIALIZATION
--============================================
function PlayerLevelSystem.Init()
	print("[PlayerLevelSystem] Initialized")
end

--============================================
-- EXPERIENCE & LEVELING
--============================================
function PlayerLevelSystem.AddExperience(player, amount)
	local playerDataStore = PlayerLevelSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return end

	-- Apply XP bonus
	local xpBonus = data.Bonus.XPBonus or 0
	local actualAmount = amount * (1 + xpBonus / 100)

	data.Account.Experience = data.Account.Experience + actualAmount

	-- Check for level up
	local currentLevel = data.Account.Level
	local requiredXP = Config.GetXPForLevel(currentLevel)

	while data.Account.Experience >= requiredXP do
		data.Account.Experience = data.Account.Experience - requiredXP
		data.Account.Level = data.Account.Level + 1

		print("[PlayerLevelSystem]", player.Name, "leveled up to", data.Account.Level)

		-- Update leaderstats
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local levelStat = leaderstats:FindFirstChild("Level")
			if levelStat then
				levelStat.Value = data.Account.Level
			end
		end

		-- Auto-unlock classes that require the newly reached level
		local ClassSys = PlayerLevelSystem.PlayerDataManager
			and PlayerLevelSystem.PlayerDataManager.GetSystems
			and PlayerLevelSystem.PlayerDataManager.GetSystems().Class
		if ClassSys and ClassSys.CheckAndUnlockEligibleClasses then
			local newClasses = ClassSys.CheckAndUnlockEligibleClasses(player)
			for _, className in ipairs(newClasses) do
				print("[PlayerLevelSystem]", player.Name, "auto-unlocked:", className)
			end
		end

		requiredXP = Config.GetXPForLevel(data.Account.Level)
	end
end

function PlayerLevelSystem.GetLevel(player)
	local playerDataStore = PlayerLevelSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return 1 end

	return data.Account.Level
end

function PlayerLevelSystem.GetExperience(player)
	local playerDataStore = PlayerLevelSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return 0 end

	return data.Account.Experience
end

function PlayerLevelSystem.GetXPProgress(player)
	local playerDataStore = PlayerLevelSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then
		return { level = 1, xp = 0, required = 100, percent = 0 }
	end

	local level = data.Account.Level
	local xp = data.Account.Experience
	local required = Config.GetXPForLevel(level)
	local percent = math.floor((xp / required) * 100)

	return {
		level = level,
		xp = xp,
		required = required,
		percent = percent,
	}
end

return PlayerLevelSystem