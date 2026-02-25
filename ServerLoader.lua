-- ServerScriptService/ServerLoader

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Modules = script.Parent:WaitForChild("Modules")

-- -----------------------------------------------------------
-- LOAD ORDER
-- -----------------------------------------------------------

local LOAD_ORDER = {
	-- Config
	"PlayerDataConfig",
	"WeaponConfig",
	"ClassConfig",

	-- Network 
	"NetworkManager",

	-- Player Data 
	"PlayerDataManager",

	-- Registries
	"WeaponRegistry",
	"SkillRegistry",
	"MobSkillRegistry",
	"MobRegistry",

	-- Stats & Currency
	"StatsManager",
	"CurrencyManager",

	-- Class & Weapon 
	"ClassManager",
	"WeaponManager",

	-- Combat Support
	"HitTracker",
	"ResourceManager",
	"AttackShapes",

	-- Monitoring
	"MonitoringSystem",

	-- Mob Systems
	"MobAI",
	"WaveConfig",
	"MobSpawner",

	-- Defense
	"DefenseLine",

	-- Combat
	"AttackHandler",
	"SkillEffects",
	"SkillManager",

	-- Game State
	"GameStateManager",
}

local loadedModules = {}
local serverReady = false

-- -----------------------------------------------------------
-- LOAD MODULES
-- -----------------------------------------------------------

print("========== SERVER LOADING ==========")
for _, moduleName in ipairs(LOAD_ORDER) do
	local moduleScript = Modules:FindFirstChild(moduleName)
	if moduleScript then
		local success, result = pcall(function()
			return require(moduleScript)
		end)

		if success then
			loadedModules[moduleName] = result

			if type(result.Init) == "function" then
				result.Init()
			end

			print("[ServerLoader] ? Loaded:", moduleName)
		else
			warn("[ServerLoader] ? Failed to load", moduleName, ":", result)
		end
	else
		warn("[ServerLoader] ? Module not found:", moduleName)
	end
end

-- Late init for modules that need other modules
if loadedModules["GameStateManager"] then
	loadedModules["GameStateManager"].LateInit()
end

if loadedModules["DefenseLine"] then
	loadedModules["DefenseLine"].LateInit()
end

serverReady = true
print("========== SERVER READY ==========")

-- -----------------------------------------------------------
-- GET MANAGER REFERENCES
-- -----------------------------------------------------------

local Config = loadedModules["PlayerDataConfig"]
local NetworkManager = loadedModules["NetworkManager"]
local DataManager = loadedModules["PlayerDataManager"]
local StatsManager = loadedModules["StatsManager"]
local ClassManager = loadedModules["ClassManager"]
local MobSpawner = loadedModules["MobSpawner"]
local HitTracker = loadedModules["HitTracker"]
local ResourceManager = loadedModules["ResourceManager"]
local GameStateManager = loadedModules["GameStateManager"]
local DefenseLine = loadedModules["DefenseLine"]

-- -----------------------------------------------------------
-- PRINT ENABLED SYSTEMS
-- -----------------------------------------------------------

if Config then
	print("")
	print("===== STAT SYSTEMS STATUS =====")
	for systemName, enabled in pairs(Config.StatGroups) do
		local status = enabled and "? ENABLED" or "? DISABLED"
		print("  " .. systemName .. ": " .. status)
	end
	print("================================")
end

if DefenseLine then
	print("")
	print("===== DEFENSE LINE =====")
	print("  Health:", DefenseLine.GetHealth(), "/", DefenseLine.GetMaxHealth())
	local config = DefenseLine.GetConfig()
	local dmg = config.Damage
	print("  Damage Formula: (" .. dmg.BaseDamage .. " + HP*" .. dmg.HPFactor .. " + Atk*" .. dmg.AttackFactor .. ") * TierMult * " .. dmg.GlobalMultiplier)
	print("  Combo:", config.Combo.Enabled and ("ON - " .. config.Combo.Factor .. "x per level") or "OFF")
	print("========================")
end

if GameStateManager then
	print("")
	print("===== GAME STATE =====")
	print("  Current State:", GameStateManager.GetState())
	print("  Waiting for 'Start' button...")
	print("======================")
	print("")
end

-- -----------------------------------------------------------
-- DEBUG: Print player stats when they join
-- -----------------------------------------------------------

local function DebugPrintPlayerStats(player)
	task.wait(1)

	local data = DataManager.GetData(player)
	if not data then
		warn("[Debug] No data for player:", player.Name)
		return
	end

	print("")
	print("===== PLAYER JOINED: " .. player.Name .. " =====")

	local account = DataManager.GetAccountData(player)
	print("  Level: " .. (account.Level or 1) .. " | Points: " .. DataManager.GetUnallocatedPoints(player) .. " unallocated")
	print("  Class: " .. DataManager.GetActiveClass(player))
	print("  Health: " .. StatsManager.GetTotalHealth(player) .. " | Damage: " .. StatsManager.GetTotalDamage(player))

	if ResourceManager and ResourceManager.GetResource then
		print("  Resource: " .. string.format("%.0f", ResourceManager.GetResource(player)) .. "/" .. ResourceManager.GetMaxResource(player) .. " " .. ResourceManager.GetResourceName(player))
	end

	print("==========================================")
	print("")

	-- Send defense line state to new player
	if DefenseLine then
		DefenseLine.SendStateToPlayer(player)
	end
end

-- -----------------------------------------------------------
-- PLAYER CONNECTIONS
-- -----------------------------------------------------------

for _, player in ipairs(Players:GetPlayers()) do
	NetworkManager.FireClient(player, "ServerReady")
	DebugPrintPlayerStats(player)
end

Players.PlayerAdded:Connect(function(player)
	if serverReady then
		task.wait(0.5)
		NetworkManager.FireClient(player, "ServerReady")
		DebugPrintPlayerStats(player)
	end
end)

-- -----------------------------------------------------------
-- TEST EVENTS
-- -----------------------------------------------------------

-- Allocate stat points
NetworkManager.GetEvent("AllocateStat")
NetworkManager.OnClientEvent("AllocateStat", function(player, statName, points)
	if points > 0 then
		local success, err = DataManager.AllocateStat(player, statName, points)
		if success then
			print("[StatTest]", player.Name, "allocated", points, "to", statName, "? Total:", DataManager.GetTotalStat(player, statName))
		else
			warn("[StatTest] Failed to allocate:", err)
		end
	elseif points < 0 then
		local success, err = DataManager.DeallocateStat(player, statName, math.abs(points))
		if success then
			print("[StatTest]", player.Name, "deallocated", math.abs(points), "from", statName)
		else
			warn("[StatTest] Failed to deallocate:", err)
		end
	end
end)

-- Modify system stats
NetworkManager.GetEvent("ModifySystemStat")
NetworkManager.OnClientEvent("ModifySystemStat", function(player, statName, delta)
	local currentValue = DataManager.GetSystemStat(player, statName)
	if currentValue ~= nil then
		local newValue = currentValue + delta
		if statName == "CritDamage" then
			newValue = math.max(0.5, newValue)
		elseif statName == "CritChance" then
			newValue = math.max(0, newValue)
		end
		DataManager.SetSystemStat(player, statName, newValue)
		print("[StatTest]", player.Name, statName, ":", currentValue, "?", newValue)
	end
end)

-- -----------------------------------------------------------
-- GAME STATE EVENTS
-- -----------------------------------------------------------

GameStateManager.OnStateChanged(function(newState, oldState)
	print("[ServerLoader] Game state:", oldState, "?", newState)
end)

MobSpawner.OnWaveStarted(function(waveNumber, mobCount)
	print("[ServerLoader] ?? Wave", waveNumber, "-", mobCount, "mobs")
end)

MobSpawner.OnWaveCompleted(function(waveNumber)
	print("[ServerLoader] ? Wave", waveNumber, "completed!")
end)

-- -----------------------------------------------------------
-- DEFENSE LINE EVENTS
-- -----------------------------------------------------------

DefenseLine.OnDamaged(function(damage, currentHealth, source)
	local percent = DefenseLine.GetHealthPercent()
	local comboText = ""

	if source and source.comboLevel and source.comboLevel > 0 then
		comboText = " [COMBO x" .. source.comboLevel .. "]"
	end

	print("[ServerLoader] ?? Defense Line:" .. comboText, math.floor(damage), "dmg -", 
		math.floor(currentHealth), "HP (" .. math.floor(percent) .. "%)")
end)

DefenseLine.OnComboChanged(function(level, hitCount)
	if level >= 3 then
		warn("[ServerLoader] ?? DEFENSE COMBO x" .. level .. "! (" .. hitCount .. " hits)")
	end
end)

DefenseLine.OnDestroyedCallback(function()
	print("[ServerLoader] ?? DEFENSE LINE DESTROYED - GAME OVER!")
end)

-- -----------------------------------------------------------
-- DEBUG COMMANDS (Optional - for testing)
-- -----------------------------------------------------------

NetworkManager.GetEvent("DebugCommand")
NetworkManager.OnClientEvent("DebugCommand", function(player, command, ...)
	local args = {...}

	if command == "testDamage" then
		-- Test defense line damage
		local tier = args[1] or "normal"
		local hp = args[2] or 50
		local atk = args[3] or 10
		DefenseLine.TestDamage(tier, hp, atk)

	elseif command == "healLine" then
		-- Heal defense line
		local amount = args[1] or 100
		DefenseLine.Heal(amount)
		print("[Debug] Healed defense line by", amount)

	elseif command == "setLineHP" then
		-- Set defense line HP
		local hp = args[1] or DefenseLine.GetMaxHealth()
		DefenseLine.SetHealth(hp)
		print("[Debug] Set defense line HP to", hp)

	elseif command == "skipWave" then
		MobSpawner.ForceCompleteWave()

	elseif command == "addXP" then
		local amount = args[1] or 100
		DataManager.AddExperience(player, amount)
		print("[Debug]", player.Name, "+", amount, "XP")
	end
end)

print("")
print("+-------------------------------------------+")
print("¦  Game waiting in LOBBY state              ¦")
print("¦  Click 'Start' button to begin waves     ¦")
print("+-------------------------------------------+")
print("")