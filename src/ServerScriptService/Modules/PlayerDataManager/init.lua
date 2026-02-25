-- ServerScriptService/Modules/PlayerDataManager

local PlayerDataManager = {}

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local DATA_STORE_KEY = "PlayerData_v1"
local AUTO_SAVE_INTERVAL = 300  -- seconds between auto-saves

local LOCAL_DATASTORE = DataStoreService:GetDataStore(DATA_STORE_KEY)

local Modules = script.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))

-- Child systems (loaded in Init)
local ClassSystem
local StatSystem
local BonusSystem
local LevelSystem

-- Internal storage (shared with children via getter)
local playerDataStore = {}

--============================================
-- INITIALIZATION
--============================================
function PlayerDataManager.Init()
	-- Load child systems
	ClassSystem = require(script:WaitForChild("PlayerClassSystem"))
	StatSystem = require(script:WaitForChild("PlayerStatSystem"))
	BonusSystem = require(script:WaitForChild("PlayerBonusSystem"))
	LevelSystem = require(script:WaitForChild("PlayerLevelSystem"))

	-- Give children access to parent and data store
	ClassSystem.PlayerDataManager = PlayerDataManager
	StatSystem.PlayerDataManager = PlayerDataManager
	BonusSystem.PlayerDataManager = PlayerDataManager
	LevelSystem.PlayerDataManager = PlayerDataManager

	ClassSystem.GetDataStore = function() return playerDataStore end
	StatSystem.GetDataStore = function() return playerDataStore end
	BonusSystem.GetDataStore = function() return playerDataStore end
	LevelSystem.GetDataStore = function() return playerDataStore end

	-- Initialize children
	ClassSystem.Init()
	StatSystem.Init()
	BonusSystem.Init()
	LevelSystem.Init()

	-- Player connections
	Players.PlayerAdded:Connect(PlayerDataManager.SetupPlayer)
	Players.PlayerRemoving:Connect(PlayerDataManager.RemovePlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		PlayerDataManager.SetupPlayer(player)
	end

	-- Auto-save loop
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				PlayerDataManager.SavePlayer(player)
			end
		end
	end)

	-- Save all on server shutdown
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			PlayerDataManager.SavePlayer(player)
		end
	end)

	print("[PlayerDataManager] Initialized")
end

--============================================
-- DEFAULT DATA CREATION
--============================================

-- Deep-merge: add any missing keys from 'defaults' into 'target' without overwriting.
local function DeepMerge(target, defaults)
	for key, defaultValue in pairs(defaults) do
		if target[key] == nil then
			if type(defaultValue) == "table" then
				target[key] = {}
				DeepMerge(target[key], defaultValue)
			else
				target[key] = defaultValue
			end
		elseif type(target[key]) == "table" and type(defaultValue) == "table" then
			DeepMerge(target[key], defaultValue)
		end
	end
end

-- Load raw data from DataStore; returns nil on first visit or error.
local function LoadRawData(userId)
	local ok, result = pcall(function()
		return LOCAL_DATASTORE:GetAsync(tostring(userId))
	end)
	if not ok then
		warn("[PlayerDataManager] DataStore load error for userId", userId, ":", result)
		return nil
	end
	return result
end
local function CreateDefaultData()
	local data = {
		Account = {},
		Classes = {},
		ActiveClass = "Aegis",
		LastClassSwitch = 0,
		Bonus = {},
	}

	-- Copy account defaults
	for key, value in pairs(Config.AccountDefaults) do
		if type(value) == "table" then
			data.Account[key] = {}
			for k, v in pairs(value) do
				data.Account[key][k] = v
			end
		else
			data.Account[key] = value
		end
	end

	-- CharacterData needs a fresh copy (avoid shared skins table between players)
	data.Account.CharacterData = {
		isCreated    = false,
		gender       = nil,
		preset       = nil,
		skins        = {},
		equippedSkin = nil,
	}

	-- Create class data for unlocked classes
	for _, className in ipairs(data.Account.UnlockedClasses) do
		data.Classes[className] = Config.CreateClassData()
	end

	-- Bonus stats (flat modifiers on top of primary-derived values)
	for key, value in pairs(Config.BonusStats) do
		data.Bonus[key] = value
	end

	return data
end

--============================================
-- PLAYER SETUP / REMOVAL
--============================================
function PlayerDataManager.SetupPlayer(player)
	-- Try loading persisted data; fall back to fresh defaults.
	local rawSaved = LoadRawData(player.UserId)
	local data = CreateDefaultData()

	if rawSaved and type(rawSaved) == "table" then
		-- Merge saved data onto defaults so new keys added in updates are present.
		DeepMerge(rawSaved, data)
		data = rawSaved
		print("[PlayerDataManager] Loaded saved data for", player.Name)
	else
		print("[PlayerDataManager] First visit — using default data for", player.Name)
	end

	playerDataStore[player] = data

	-- Auto-unlock any classes this player now qualifies for (handles both
	-- returning players and future live updates to unlock requirements).
	task.defer(function()
		if ClassSystem then
			ClassSystem.CheckAndUnlockEligibleClasses(player)
		end
	end)

	-- Create leaderstats
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local meritsValue = Instance.new("IntValue")
	meritsValue.Name = "Merits"
	meritsValue.Value = data.Account.Merits
	meritsValue.Parent = leaderstats

	local levelValue = Instance.new("IntValue")
	levelValue.Name = "Level"
	levelValue.Value = data.Account.Level
	levelValue.Parent = leaderstats

	-- Apply health on spawn
	player.CharacterAdded:Connect(function(character)
		StatSystem.ApplyHealthToCharacter(player, character)
	end)

	if player.Character then
		StatSystem.ApplyHealthToCharacter(player, player.Character)
	end
end

function PlayerDataManager.RemovePlayer(player)
	PlayerDataManager.SavePlayer(player)
	playerDataStore[player] = nil
end

function PlayerDataManager.SavePlayer(player)
	local data = playerDataStore[player]
	if not data then return end

	local ok, err = pcall(function()
		LOCAL_DATASTORE:SetAsync(tostring(player.UserId), data)
	end)

	if not ok then
		warn("[PlayerDataManager] Failed to save data for", player.Name, ":", err)
	else
		print("[PlayerDataManager] Saved data for", player.Name)
	end
end

--============================================
-- RAW DATA ACCESS
--============================================
function PlayerDataManager.GetData(player)
	return playerDataStore[player]
end

function PlayerDataManager.GetDataStore()
	return playerDataStore
end

function PlayerDataManager.GetLeaderstats(player)
	return player:FindFirstChild("leaderstats")
end

--============================================
-- ACCOUNT DATA ACCESS
--============================================
function PlayerDataManager.GetAccountData(player, key)
	local data = playerDataStore[player]
	if not data then return nil end

	if key then
		return data.Account[key]
	end
	return data.Account
end

function PlayerDataManager.SetAccountData(player, key, value)
	local data = playerDataStore[player]
	if not data then return false end

	data.Account[key] = value

	-- Update leaderstats if applicable
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local stat = leaderstats:FindFirstChild(key)
		if stat then
			stat.Value = value
		end
	end

	return true
end

--============================================
-- CLASS DATA ACCESS (basic getters)
--============================================
function PlayerDataManager.GetActiveClass(player)
	local data = playerDataStore[player]
	return data and data.ActiveClass or "Aegis"
end

function PlayerDataManager.GetActiveClassData(player)
	local data = playerDataStore[player]
	if not data then return nil end

	return data.Classes[data.ActiveClass]
end

function PlayerDataManager.GetClassData(player, className)
	local data = playerDataStore[player]
	if not data then return nil end

	return data.Classes[className]
end

function PlayerDataManager.SetClassData(player, className, key, value)
	local data = playerDataStore[player]
	if not data or not data.Classes[className] then return false end

	data.Classes[className][key] = value
	return true
end

function PlayerDataManager.HasClassData(player, className)
	local data = playerDataStore[player]
	return data and data.Classes[className] ~= nil
end

--============================================
-- WEAPON DATA ACCESS
--============================================
function PlayerDataManager.GetEquippedWeapon(player, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return nil end
	return classData.EquippedWeapon
end

function PlayerDataManager.SetEquippedWeapon(player, weaponInstance, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return false end
	classData.EquippedWeapon = weaponInstance
	return true
end

function PlayerDataManager.GetOwnedWeapons(player, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return {} end
	return classData.OwnedWeapons or {}
end

function PlayerDataManager.AddOwnedWeapon(player, weaponId, weaponInstance, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return false end

	classData.OwnedWeapons = classData.OwnedWeapons or {}

	if classData.OwnedWeapons[weaponId] then
		return false
	end

	classData.OwnedWeapons[weaponId] = weaponInstance
	return true
end

function PlayerDataManager.GetOwnedWeapon(player, weaponId, className)
	local ownedWeapons = PlayerDataManager.GetOwnedWeapons(player, className)
	return ownedWeapons[weaponId]
end

function PlayerDataManager.HasWeapon(player, weaponId, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return false end

	if classData.EquippedWeapon and classData.EquippedWeapon.weaponId == weaponId then
		return true
	end

	if classData.OwnedWeapons and classData.OwnedWeapons[weaponId] then
		return true
	end

	return false
end

--============================================
-- EXPOSE CHILD SYSTEMS
--============================================
function PlayerDataManager.GetSystems()
	return {
		Class = ClassSystem,
		Stat = StatSystem,
		Bonus = BonusSystem,
		Level = LevelSystem,
	}
end

function PlayerDataManager.CheckUnlockEligibleClasses(player)
	return ClassSystem.CheckAndUnlockEligibleClasses(player)
end

-- Convenience pass-through functions (so existing code doesn't break)

-- Class System
function PlayerDataManager.SetActiveClass(player, className)
	return ClassSystem.SetActiveClass(player, className)
end

function PlayerDataManager.CanSwitchClass(player)
	return ClassSystem.CanSwitchClass(player)
end

function PlayerDataManager.GetSwitchCooldownRemaining(player)
	return ClassSystem.GetSwitchCooldownRemaining(player)
end

function PlayerDataManager.IsClassUnlocked(player, className)
	return ClassSystem.IsClassUnlocked(player, className)
end

function PlayerDataManager.UnlockClass(player, className)
	return ClassSystem.UnlockClass(player, className)
end

function PlayerDataManager.CreateClassData(player, className)
	return ClassSystem.CreateClassData(player, className)
end

-- Stat System
function PlayerDataManager.GetAvailablePoints(player)
	return StatSystem.GetAvailablePoints(player)
end

function PlayerDataManager.GetSpentPoints(player, className)
	return StatSystem.GetSpentPoints(player, className)
end

function PlayerDataManager.GetUnallocatedPoints(player, className)
	return StatSystem.GetUnallocatedPoints(player, className)
end

function PlayerDataManager.GetAllocatedStat(player, statName, className)
	return StatSystem.GetAllocatedStat(player, statName, className)
end

function PlayerDataManager.AllocateStat(player, statName, points)
	return StatSystem.AllocateStat(player, statName, points)
end

function PlayerDataManager.DeallocateStat(player, statName, points)
	return StatSystem.DeallocateStat(player, statName, points)
end

function PlayerDataManager.ResetAllocation(player, className)
	return StatSystem.ResetAllocation(player, className)
end

function PlayerDataManager.GetTotalStat(player, statName)
	return StatSystem.GetTotalStat(player, statName)
end

function PlayerDataManager.ApplyHealthToCharacter(player, character)
	return StatSystem.ApplyHealthToCharacter(player, character)
end

function PlayerDataManager.ResetHealth(player)
	return StatSystem.ResetHealth(player)
end

-- Bonus System
function PlayerDataManager.GetBonus(player, bonusName)
	return BonusSystem.GetBonus(player, bonusName)
end

function PlayerDataManager.SetBonus(player, bonusName, value)
	return BonusSystem.SetBonus(player, bonusName, value)
end

function PlayerDataManager.ModifyBonus(player, bonusName, delta)
	return BonusSystem.ModifyBonus(player, bonusName, delta)
end

function PlayerDataManager.GetSystemStat(player, statName)
	return BonusSystem.GetSystemStat(player, statName)
end

function PlayerDataManager.SetSystemStat(player, statName, value)
	return BonusSystem.SetSystemStat(player, statName, value)
end

function PlayerDataManager.ApplyWeaponBonuses(player)
	return BonusSystem.ApplyWeaponBonuses(player)
end

function PlayerDataManager.RefreshWeaponStats(player)
	return BonusSystem.RefreshWeaponStats(player)
end

-- Level System
function PlayerDataManager.AddExperience(player, amount)
	return LevelSystem.AddExperience(player, amount)
end

--============================================
-- DEBUG
--============================================
function PlayerDataManager.GetDebugInfo(player)
	local data = playerDataStore[player]
	if not data then return "No data" end

	local activeClass = data.ActiveClass
	local classData = data.Classes[activeClass]

	local info = {
		"=== PlayerDataManager Debug ===",
		"Account Level: " .. data.Account.Level,
		"Active Class: " .. activeClass,
	}

	-- Stat info
	local statInfo = StatSystem.GetDebugInfo(player)
	if statInfo then
		table.insert(info, statInfo)
	end

	-- Weapon info
	table.insert(info, "--- Weapon ---")
	local weapon = classData.EquippedWeapon
	if weapon then
		table.insert(info, "ID: " .. weapon.weaponId)
		table.insert(info, "Level: " .. weapon.level .. " | +: " .. weapon.refinement .. " | Tier: " .. weapon.tier)
		if weapon.bonuses then
			for i, bonus in ipairs(weapon.bonuses) do
				table.insert(info, "  " .. i .. ". " .. bonus.stat .. ": +" .. bonus.value)
			end
		end
	else
		table.insert(info, "No weapon equipped")
	end

	return table.concat(info, "\n")
end

return PlayerDataManager