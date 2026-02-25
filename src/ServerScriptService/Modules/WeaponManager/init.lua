-- ServerScriptService/Modules/WeaponManager

local WeaponManager = {}

local Players = game:GetService("Players")

local Modules = script.Parent
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- Child systems (loaded in Init)
local XPSystem
local Refinement
local TierSystem
local BonusSystem

--============================================
-- INITIALIZATION
--============================================
function WeaponManager.Init()
	-- Load child systems
	XPSystem = require(script:WaitForChild("WeaponXPSystem"))
	Refinement = require(script:WaitForChild("WeaponRefinement"))
	TierSystem = require(script:WaitForChild("WeaponTierSystem"))
	BonusSystem = require(script:WaitForChild("WeaponBonusSystem"))

	-- Give children access to parent
	XPSystem.WeaponManager = WeaponManager
	Refinement.WeaponManager = WeaponManager
	TierSystem.WeaponManager = WeaponManager
	BonusSystem.WeaponManager = WeaponManager

	-- Initialize children
	BonusSystem.Init()  -- First, others may need it
	XPSystem.Init()
	Refinement.Init()
	TierSystem.Init()

	-- Create network events
	NetworkManager.GetEvent("WeaponEquipped")

	-- Setup starter weapons for players
	Players.PlayerAdded:Connect(function(player)
		task.wait(0.1)  -- Ensure PlayerDataManager is ready
		WeaponManager.EnsureStarterWeapon(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			WeaponManager.EnsureStarterWeapon(player)
		end)
	end

	print("[WeaponManager] Initialized")
end

--============================================
-- WEAPON INSTANCE CREATION
--============================================
function WeaponManager.CreateWeaponInstance(weaponId)
	local weaponDef = WeaponRegistry.GetWeapon(weaponId)
	if not weaponDef then
		warn("[WeaponManager] Weapon not found:", weaponId)
		return nil
	end

	local initialBonuses = BonusSystem.RollBonuses(weaponId, 1)

	return {
		weaponId = weaponId,
		level = 1,
		xp = 0,
		refinement = 0,
		tier = 1,
		bonuses = initialBonuses,
	}
end

--============================================
-- STARTER WEAPON
--============================================
function WeaponManager.EnsureStarterWeapon(player)
	local activeClass = PlayerDataManager.GetActiveClass(player)
	local classData = PlayerDataManager.GetActiveClassData(player)

	if not classData then
		warn("[WeaponManager] No class data for", player.Name)
		return
	end

	if classData.EquippedWeapon and classData.EquippedWeapon.weaponId then
		return  -- Already has weapon
	end

	local starterWeaponId = WeaponRegistry.GetStarterWeaponId(activeClass)
	if not starterWeaponId then
		warn("[WeaponManager] No starter weapon for class:", activeClass)
		return
	end

	local weaponInstance = WeaponManager.CreateWeaponInstance(starterWeaponId)
	if weaponInstance then
		classData.EquippedWeapon = weaponInstance
		print("[WeaponManager] Gave starter weapon to", player.Name, ":", starterWeaponId)

		NetworkManager.FireClient(player, "WeaponEquipped", {
			weaponId = starterWeaponId,
			weaponData = weaponInstance,
			stats = WeaponManager.GetCalculatedStats(player),
		})
	end
end

--============================================
-- WEAPON ACCESS
--============================================
function WeaponManager.GetEquippedWeapon(player, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return nil end
	return classData.EquippedWeapon
end

function WeaponManager.GetEquippedWeaponDef(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then return nil end

	return WeaponRegistry.GetWeapon(weaponInstance.weaponId)
end

function WeaponManager.GetCalculatedStats(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then
		return {
			attack = 10,
			attackSpeed = 1.0,
			attackShape = "Circle",
			shapeParams = { radius = 5 },
		}
	end

	local weaponId = weaponInstance.weaponId
	local level = weaponInstance.level
	local refinement = weaponInstance.refinement
	local tier = weaponInstance.tier

	return {
		attack = WeaponRegistry.CalculateAttack(weaponId, level, refinement, tier),
		attackSpeed = WeaponRegistry.CalculateAttackSpeed(weaponId, tier),
		attackShape = WeaponRegistry.GetAttackShape(weaponId),
		shapeParams = WeaponRegistry.GetScaledShapeParams(weaponId, tier),
		bonuses = weaponInstance.bonuses,
	}
end

function WeaponManager.GetAttackShape(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then
		return "Circle", { radius = 5 }
	end

	local shape, params = WeaponRegistry.GetAttackShape(weaponInstance.weaponId)
	local scaledParams = WeaponRegistry.GetScaledShapeParams(weaponInstance.weaponId, weaponInstance.tier)

	return shape or "Circle", scaledParams or params or { radius = 5 }
end

function WeaponManager.GetAttackSpeed(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then return 1.0 end

	return WeaponRegistry.CalculateAttackSpeed(weaponInstance.weaponId, weaponInstance.tier)
end

function WeaponManager.GetAttackCooldown(player)
	return 1 / WeaponManager.GetAttackSpeed(player)
end

function WeaponManager.GetWeaponAttack(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then return 10 end

	return WeaponRegistry.CalculateAttack(
		weaponInstance.weaponId,
		weaponInstance.level,
		weaponInstance.refinement,
		weaponInstance.tier
	)
end

--============================================
-- MAX WEAPON LEVEL
--============================================
function WeaponManager.GetMaxWeaponLevel(player)
	local playerLevel = PlayerDataManager.GetAccountData(player, "Level") or 1
	local maxLevel = math.floor(playerLevel / 10) * 10
	return math.max(1, maxLevel)  -- Minimum level 1
end

function WeaponManager.CanWeaponLevelUp(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then return false end

	return weaponInstance.level < WeaponManager.GetMaxWeaponLevel(player)
end

--============================================
-- WEAPON SWITCHING & UNLOCKING
--============================================
function WeaponManager.SwitchWeapon(player, weaponId)
	local activeClass = PlayerDataManager.GetActiveClass(player)

	if not WeaponRegistry.IsWeaponForClass(weaponId, activeClass) then
		return false, "Weapon not available for your class"
	end

	local classData = PlayerDataManager.GetActiveClassData(player)
	if not classData then return false, "No class data" end

	local ownedWeapons = classData.OwnedWeapons or {}
	local weaponInstance = ownedWeapons[weaponId]

	if not weaponInstance then
		return false, "You don't own this weapon"
	end

	-- Store current weapon
	if classData.EquippedWeapon then
		local currentId = classData.EquippedWeapon.weaponId
		ownedWeapons[currentId] = classData.EquippedWeapon
	end

	-- Equip new weapon
	classData.EquippedWeapon = weaponInstance
	classData.OwnedWeapons = ownedWeapons

	NetworkManager.FireClient(player, "WeaponEquipped", {
		weaponId = weaponId,
		weaponData = weaponInstance,
		stats = WeaponManager.GetCalculatedStats(player),
	})

	print("[WeaponManager]", player.Name, "switched to:", weaponId)
	return true, "Weapon equipped!"
end

function WeaponManager.UnlockWeapon(player, weaponId)
	local activeClass = PlayerDataManager.GetActiveClass(player)

	if not WeaponRegistry.IsWeaponForClass(weaponId, activeClass) then
		return false, "Weapon not available for your class"
	end

	local classData = PlayerDataManager.GetActiveClassData(player)
	if not classData then return false, "No class data" end

	classData.OwnedWeapons = classData.OwnedWeapons or {}

	if classData.OwnedWeapons[weaponId] then
		return false, "Weapon already owned"
	end

	local weaponInstance = WeaponManager.CreateWeaponInstance(weaponId)
	if not weaponInstance then return false, "Failed to create weapon" end

	classData.OwnedWeapons[weaponId] = weaponInstance
	print("[WeaponManager]", player.Name, "unlocked:", weaponId)

	return true, "Weapon unlocked!"
end

function WeaponManager.GetOwnedWeapons(player)
	local classData = PlayerDataManager.GetActiveClassData(player)
	if not classData then return {} end

	local result = {}

	if classData.EquippedWeapon then
		local weaponId = classData.EquippedWeapon.weaponId
		result[weaponId] = {
			instance = classData.EquippedWeapon,
			equipped = true,
			definition = WeaponRegistry.GetWeapon(weaponId),
		}
	end

	for weaponId, instance in pairs(classData.OwnedWeapons or {}) do
		if not result[weaponId] then
			result[weaponId] = {
				instance = instance,
				equipped = false,
				definition = WeaponRegistry.GetWeapon(weaponId),
			}
		end
	end

	return result
end

--============================================
-- EXPOSE CHILD SYSTEMS
--============================================
function WeaponManager.GetSystems()
	return {
		XP = XPSystem,
		Refinement = Refinement,
		Tier = TierSystem,
		Bonus = BonusSystem,
	}
end

--============================================
-- DEBUG
--============================================
function WeaponManager.GetDebugInfo(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then return "No weapon equipped" end

	local stats = WeaponManager.GetCalculatedStats(player)
	local xpInfo = XPSystem.GetXPProgress(player)
	local refInfo = Refinement.GetInfo(player)
	local tierInfo = TierSystem.GetInfo(player)

	local info = {
		"=== WeaponManager Debug ===",
		"Weapon: " .. weaponInstance.weaponId,
		"Level: " .. weaponInstance.level .. " / " .. xpInfo.maxLevel,
		"XP: " .. xpInfo.xp .. " / " .. xpInfo.required .. " (" .. xpInfo.percent .. "%)",
		"Refinement: +" .. refInfo.refinement .. " (Success: " .. refInfo.successChance .. "%)",
		"Tier: " .. tierInfo.tier .. " (ATK Bonus: +" .. tierInfo.atkBonus .. "%)",
		"--- Stats ---",
		"Attack: " .. stats.attack,
		"Speed: " .. stats.attackSpeed,
		"Shape: " .. tostring(stats.attackShape),
		"--- Bonuses ---",
	}

	for i, bonus in ipairs(weaponInstance.bonuses or {}) do
		table.insert(info, "  " .. i .. ". " .. bonus.stat .. ": +" .. bonus.value)
	end

	return table.concat(info, "\n")
end

return WeaponManager