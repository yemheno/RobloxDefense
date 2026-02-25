-- ServerScriptService/Modules/WeaponManager/WeaponXPSystem

local WeaponXPSystem = {}

local Modules = script.Parent.Parent
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- Set by WeaponManager
WeaponXPSystem.WeaponManager = nil

--============================================
-- INITIALIZATION
--============================================
function WeaponXPSystem.Init()
	NetworkManager.GetEvent("WeaponLevelUp")
	NetworkManager.GetEvent("WeaponXPGained")

	print("[WeaponXPSystem] Initialized")
end

--============================================
-- XP RANGE CHECK
--============================================
function WeaponXPSystem.IsMobInRange(player, mobLevel)
	local weaponInstance = WeaponXPSystem.WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then return false end

	local weaponLevel = weaponInstance.level
	local range = WeaponConfig.XP_LEVEL_RANGE

	local minLevel = math.max(1, weaponLevel - range)
	local maxLevel = weaponLevel + range

	return mobLevel >= minLevel and mobLevel <= maxLevel
end

--============================================
-- XP CALCULATION
--============================================
function WeaponXPSystem.CalculateMobXP(weaponLevel, mobLevel, mobType)
	local baseXP = WeaponConfig.XP_BASE
	local typeMultiplier = WeaponConfig.XP_MOB_MULTIPLIER[mobType] or 1

	-- Level difference bonus
	local levelDiff = mobLevel - weaponLevel
	local levelMultiplier = math.max(0.1, 1 + levelDiff * 0.1)

	return math.floor(baseXP * typeMultiplier * levelMultiplier)
end

--============================================
-- ADD XP FROM MOB KILL
--============================================
function WeaponXPSystem.AddMobKillXP(player, mobLevel, mobType)
	local weaponInstance = WeaponXPSystem.WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then return end

	-- Check range
	if not WeaponXPSystem.IsMobInRange(player, mobLevel) then
		return
	end

	-- Check if can level
	if not WeaponXPSystem.WeaponManager.CanWeaponLevelUp(player) then
		return
	end

	-- Calculate XP
	local xpGained = WeaponXPSystem.CalculateMobXP(weaponInstance.level, mobLevel, mobType)

	-- Apply player XP bonus
	local xpBonus = PlayerDataManager.GetBonus(player, "XPBonus") or 0
	xpGained = math.floor(xpGained * (1 + xpBonus / 100))

	-- Add XP
	weaponInstance.xp = weaponInstance.xp + xpGained

	-- Check for level ups
	local levelsGained = 0
	local maxLevel = WeaponXPSystem.WeaponManager.GetMaxWeaponLevel(player)

	while weaponInstance.level < maxLevel do
		local requiredXP = WeaponConfig.GetXPRequired(weaponInstance.level)

		if weaponInstance.xp >= requiredXP then
			weaponInstance.xp = weaponInstance.xp - requiredXP
			weaponInstance.level = weaponInstance.level + 1
			levelsGained = levelsGained + 1
		else
			break
		end
	end

	-- Cap XP at max level
	if weaponInstance.level >= maxLevel then
		weaponInstance.xp = 0
	end

	-- Notify client
	if levelsGained > 0 then
		NetworkManager.FireClient(player, "WeaponLevelUp", {
			newLevel = weaponInstance.level,
			levelsGained = levelsGained,
			stats = WeaponXPSystem.WeaponManager.GetCalculatedStats(player),
		})
		print("[WeaponXPSystem]", player.Name, "leveled up to", weaponInstance.level)
	else
		NetworkManager.FireClient(player, "WeaponXPGained", {
			xpGained = xpGained,
			currentXP = weaponInstance.xp,
			requiredXP = WeaponConfig.GetXPRequired(weaponInstance.level),
			level = weaponInstance.level,
		})
	end
end

--============================================
-- XP PROGRESS INFO
--============================================
function WeaponXPSystem.GetXPProgress(player)
	local weaponInstance = WeaponXPSystem.WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then
		return { level = 1, xp = 0, required = 100, percent = 0, maxLevel = 1 }
	end

	local required = WeaponConfig.GetXPRequired(weaponInstance.level)
	local percent = math.floor((weaponInstance.xp / required) * 100)

	return {
		level = weaponInstance.level,
		xp = weaponInstance.xp,
		required = required,
		percent = percent,
		maxLevel = WeaponXPSystem.WeaponManager.GetMaxWeaponLevel(player),
	}
end

return WeaponXPSystem