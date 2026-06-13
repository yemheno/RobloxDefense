-- ServerScriptService/Modules/PlayerDataManager/PlayerLevelSystem

local PlayerLevelSystem = {}

local Modules = script.Parent.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))
local ChapterConfig = require(Modules:WaitForChild("ChapterConfig"))
-- §T0P2/X21: ClassMasteryConfig require removed with AddClassMasteryXP.

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

	-- Chapter level cap (§4): cannot pass cap until chapter boss is defeated.
	-- §PDM-D5: at hard cap, the player simply STOPS gaining XP. Other
	-- progression channels (weapon XP, achievements, talents) still flow
	-- through their own systems. Class Mastery XP has its own dedicated
	-- earn path — see TODO §3 ("Class Mastery XP source").
	local currentLevel = data.Account.Level
	local chapterCap = ChapterConfig.GetChapterLevelCap(ChapterConfig.GetChapter(currentLevel))
	if currentLevel >= chapterCap then
		return  -- at cap, XP is lost; player must defeat the chapter boss
	end

	data.Account.Experience = data.Account.Experience + actualAmount

	-- Check for level up
	local requiredXP = Config.GetXPForLevel(currentLevel)

	while data.Account.Experience >= requiredXP do
		-- Don't exceed the chapter cap. Clamp XP at cap-1 so the bar shows
		-- "full" without overflowing into the next level until the cap is
		-- raised (chapter boss defeat).
		if data.Account.Level >= chapterCap then
			data.Account.Experience = requiredXP - 1
			break
		end

		data.Account.Experience = data.Account.Experience - requiredXP

		-- §T0P2/X4: route the level write through SetAccountData — the
		-- SINGLE write path that also syncs the leaderstat, the Level
		-- player Attribute (read by TeleportDataReader's fallback), and
		-- RefreshPowerScore. The old direct write + manual leaderstat
		-- update left the attribute and Power score stale after every
		-- natural level-up (admin SetLevel was unaffected, which is why
		-- live tests never caught it).
		local PDM = PlayerLevelSystem.PlayerDataManager
		if PDM and PDM.SetAccountData then
			PDM.SetAccountData(player, "Level", data.Account.Level + 1)
		else
			data.Account.Level = data.Account.Level + 1
		end

		print("[PlayerLevelSystem]", player.Name, "leveled up to", data.Account.Level)

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

-- §T0P2/X21: AddClassMasteryXP DELETED. Class XP was superseded by
-- weapon/gear XP (WeaponXPSystem); the function had zero callers and
-- would still have granted BoundTokens if ever invoked. The schema
-- fields (Classes.*.MasteryXP / MasteryMilestones) and
-- ClassMasteryConfig remain — full sweep parked in docs/TODO.md
-- (§T0P2-MASTERY).

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