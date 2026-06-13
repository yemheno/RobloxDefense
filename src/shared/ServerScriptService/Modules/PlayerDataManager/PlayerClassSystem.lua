-- ServerScriptService/Modules/PlayerDataManager/PlayerClassSystem

local PlayerClassSystem = {}

local Modules = script.Parent.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))

-- Set by PlayerDataManager
PlayerClassSystem.PlayerDataManager = nil
PlayerClassSystem.GetDataStore = nil

--============================================
-- INITIALIZATION
--============================================
function PlayerClassSystem.Init()
end

--============================================
-- CLASS SWITCHING
--============================================
function PlayerClassSystem.SetActiveClass(player, className)
	local playerDataStore = PlayerClassSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return false, "No player data" end

	-- Check if class is unlocked
	if not data.Classes[className] then
		local isUnlocked = false
		for _, unlockedClass in ipairs(data.Account.UnlockedClasses) do
			if unlockedClass == className then
				isUnlocked = true
				break
			end
		end

		if isUnlocked then
			data.Classes[className] = Config.CreateClassData()
		else
			return false, "Class not unlocked"
		end
	end

	data.ActiveClass = className
	data.LastClassSwitch = os.time()

	return true
end

function PlayerClassSystem.CanSwitchClass(player)
	local playerDataStore = PlayerClassSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return false, "No player data" end

	local elapsed = os.time() - data.LastClassSwitch
	local remaining = Config.ClassSwitchCooldown - elapsed

	if remaining > 0 then
		return false, remaining
	end

	return true
end

function PlayerClassSystem.GetSwitchCooldownRemaining(player)
	local playerDataStore = PlayerClassSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return 0 end

	local elapsed = os.time() - data.LastClassSwitch
	local remaining = Config.ClassSwitchCooldown - elapsed

	return math.max(0, remaining)
end

--============================================
-- CLASS UNLOCKING
--============================================

--- Returns true if the player meets all requirements for a class,
--- or (false, reason) if not. Returns true for classes with no requirements.
function PlayerClassSystem.CheckUnlockRequirements(player, className)
	local reqs = Config.ClassUnlockRequirements[className]
	if not reqs then return true end  -- No requirements — free class

	local playerDataStore = PlayerClassSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return false, "No player data" end

	if reqs.requiredLevel then
		local level = data.Account.Level
		if level < reqs.requiredLevel then
			return false, "Requires level " .. reqs.requiredLevel .. " (you are " .. level .. ")"
		end
	end

	return true
end

function PlayerClassSystem.IsClassUnlocked(player, className)
	local playerDataStore = PlayerClassSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return false end

	for _, unlockedClass in ipairs(data.Account.UnlockedClasses) do
		if unlockedClass == className then
			return true
		end
	end

	return false
end

--- Unlock a class for the player, respecting level/progression requirements.
function PlayerClassSystem.UnlockClass(player, className)
	local playerDataStore = PlayerClassSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return false, "No player data" end

	-- §T1.2/D4: hardcoded Aegis exception removed. Every known class has
	-- an entry in ClassUnlockRequirements (derived from ClassConfig); an
	-- absent entry means the class is genuinely unknown.
	if Config.ClassUnlockRequirements[className] == nil then
		return false, "Unknown class: " .. className
	end

	if PlayerClassSystem.IsClassUnlocked(player, className) then
		return false, "Already unlocked"
	end

	local canUnlock, reason = PlayerClassSystem.CheckUnlockRequirements(player, className)
	if not canUnlock then
		return false, reason
	end

	table.insert(data.Account.UnlockedClasses, className)
	data.Classes[className] = Config.CreateClassData()

	print("[PlayerClassSystem]", player.Name, "unlocked class:", className)
	return true
end

--- Scan all classes and auto-unlock any for which the player now qualifies.
--- Called on login and after every level-up.
function PlayerClassSystem.CheckAndUnlockEligibleClasses(player)
	local unlocked = {}
	for className, _ in pairs(Config.ClassUnlockRequirements) do
		if not PlayerClassSystem.IsClassUnlocked(player, className) then
			local ok = PlayerClassSystem.CheckUnlockRequirements(player, className)
			if ok then
				PlayerClassSystem.UnlockClass(player, className)
				table.insert(unlocked, className)
			end
		end
	end
	return unlocked
end

--============================================
-- CLASS INFO
--============================================
function PlayerClassSystem.GetUnlockedClasses(player)
	local playerDataStore = PlayerClassSystem.GetDataStore()
	local data = playerDataStore[player]
	if not data then return {} end

	return data.Account.UnlockedClasses or {}
end

return PlayerClassSystem