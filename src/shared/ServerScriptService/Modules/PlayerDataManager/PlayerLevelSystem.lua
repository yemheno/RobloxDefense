-- ServerScriptService/Modules/PlayerDataManager/PlayerLevelSystem

local PlayerLevelSystem = {}

local Modules = script.Parent.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))
local ChapterConfig = require(Modules:WaitForChild("ChapterConfig"))
local ClassMasteryConfig = require(Modules:WaitForChild("ClassMasteryConfig"))

-- Set by PlayerDataManager
PlayerLevelSystem.PlayerDataManager = nil
PlayerLevelSystem.GetDataStore = nil

-- Lazy-loaded (only exists when the server has loaded BonusExpSystem)
local BonusExpSystem = nil

--============================================
-- INITIALIZATION
--============================================
function PlayerLevelSystem.Init()
	-- BonusExpSystem lives in the same Modules folder; load it if present.
	local bonusMod = Modules:FindFirstChild("BonusExpSystem")
	if bonusMod then
		BonusExpSystem = require(bonusMod)
	end
	print("[PlayerLevelSystem] Initialized")
end

--============================================
-- EXPERIENCE & LEVELING
--============================================
function PlayerLevelSystem.AddExperience(player, amount)
	local playerDataStore = PlayerLevelSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return end

	-- Combine permanent XP bonus (from equipment/stats) with dynamic bonuses
	-- (party, events, etc.) tracked by BonusExpSystem.
	local staticBonus    = data.Bonus.XPBonus or 0            -- percent integer, e.g. 10 = +10%
	local dynamicMult    = BonusExpSystem and BonusExpSystem.GetMultiplier(player) or 1.0
	local staticMult     = 1 + (staticBonus / 100)
	local actualAmount   = amount * staticMult * dynamicMult

	-- Chapter level cap (§4): cannot pass cap until chapter boss is defeated
	local currentLevel = data.Account.Level
	local chapterCap = ChapterConfig.GetChapterLevelCap(ChapterConfig.GetChapter(currentLevel))
	local atCap = currentLevel >= chapterCap

	if atCap then
		-- §5: At chapter cap, 100% of earned XP → Class Mastery XP
		PlayerLevelSystem.AddClassMasteryXP(data, actualAmount)
		return
	end

	data.Account.Experience = data.Account.Experience + actualAmount

	-- Check for level up
	local requiredXP = Config.GetXPForLevel(currentLevel)

	while data.Account.Experience >= requiredXP do
		-- Don't exceed the chapter cap
		if data.Account.Level >= chapterCap then
			data.Account.Experience = requiredXP - 1 -- clamp XP, no overflow
			break
		end

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

--============================================
-- CLASS MASTERY XP (§5)
-- While capped, 100% of earned XP → active class mastery
--============================================
function PlayerLevelSystem.AddClassMasteryXP(data, amount)
	local className = data.ActiveClass
	local classData = data.Classes[className]
	if not classData then return end

	classData.MasteryXP = (classData.MasteryXP or 0) + amount

	-- Auto-unlock milestones and grant rewards
	if not classData.MasteryMilestones then
		classData.MasteryMilestones = {}
	end
	local pending = ClassMasteryConfig.GetPendingMilestones(classData.MasteryXP, classData.MasteryMilestones)
	for _, milestone in ipairs(pending) do
		classData.MasteryMilestones[milestone.id] = true

		-- Grant bound tokens (role seals, etc.)
		if milestone.rewards and milestone.rewards.boundToken then
			local sealPrefix = ClassMasteryConfig.RoleSealMap[className]
			local tokenId = sealPrefix and (sealPrefix .. "_" .. milestone.id) or milestone.rewards.boundToken
			if not data.Account.BoundTokens then
				data.Account.BoundTokens = {}
			end
			data.Account.BoundTokens[tokenId] = (data.Account.BoundTokens[tokenId] or 0) + 1
		end

		print("[ClassMastery]", className, "unlocked milestone:", milestone.id)
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