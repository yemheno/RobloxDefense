-- ServerScriptService/Modules/PlayerDataManager/PlayerClassSystem

local PlayerClassSystem = {}

local Modules = script.Parent.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))

-- §AGX/T11-JAN: lazy ReadyGate getter (Audit_4.7 §5.3; false = looked, not found).
local _ReadyGate = nil
local function getReadyGate()
	if _ReadyGate ~= nil then
		return _ReadyGate or nil
	end
	local mod = Modules:FindFirstChild("ReadyGate")
	if not mod then
		_ReadyGate = false
		return nil
	end
	local ok, result = pcall(require, mod)
	_ReadyGate = ok and result or false
	return _ReadyGate or nil
end

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
	-- §AGX/WC: mirror server truth into the ActiveClass attribute. The lobby's
	-- TeleportManager stamps partyData.class from it (it was never written,
	-- so every party member travelled as "Aegis").
	player:SetAttribute("ActiveClass", className)

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

	-- §EASY/E6: class-unlock toast — rides the existing AchievementUnlocked
	-- pipeline (AchievementClient → toast queue), no new client code.
	-- §AGX/T11-JAN: routed through ReadyGate (Audit_4.7 §5.5). The login
	-- auto-unlock (CheckAndUnlockEligibleClasses from SetupPlayer) fires
	-- before ClientReady, so a raw FireClient dropped the toast. ReadyGate
	-- queues until the handshake and sends immediately once ready. No
	-- task.spawn needed: ReadyGate.FireClient never yields.
	local payload = {
		id   = "class_unlock_" .. className,
		name = "Class Unlocked!",
		desc = className .. " is now available in the Class menu.",
		icon = "🗡",
	}
	local rg = getReadyGate()
	if rg then
		rg.FireClient(player, "AchievementUnlocked", payload)
	else
		local nmMod = Modules:FindFirstChild("NetworkManager")
		local ok, nm = nmMod and pcall(require, nmMod)
		if ok and nm and nm.FireClient then
			nm.FireClient(player, "AchievementUnlocked", payload)
		end
	end
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