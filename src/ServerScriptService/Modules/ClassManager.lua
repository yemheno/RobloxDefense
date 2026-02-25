-- ServerScriptService/Modules/ClassManager

local ClassManager = {}

local Modules = script.Parent
local ClassConfig = require(Modules:WaitForChild("ClassConfig"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))

-- WeaponManager loaded after init (circular dependency prevention)
local WeaponManager = nil

--============================================
-- INITIALIZATION
--============================================
function ClassManager.Init()
	-- Delayed WeaponManager require (it requires us, we require it)
	task.spawn(function()
		WeaponManager = require(Modules:WaitForChild("WeaponManager"))
	end)

	-- Remote: client asks to switch to a class they've already unlocked
	local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
	NetworkManager.OnClientEvent("RequestClassSwitch", function(player, className)
		if not ClassConfig.Classes[className] then
			NetworkManager.FireClient(player, "ClassSwitchResult", false, "Unknown class: " .. tostring(className))
			return
		end

		local canSwitch, reason = PlayerDataManager.CanSwitchClass(player)
		if not canSwitch then
			NetworkManager.FireClient(player, "ClassSwitchResult", false, "Cooldown: " .. tostring(math.ceil(reason)) .. "s remaining")
			return
		end

		local ok, err = ClassManager.SetClass(player, className)
		NetworkManager.FireClient(player, "ClassSwitchResult", ok, err or className)
	end)

	print("[ClassManager] Initialized")
end

--============================================
-- CLASS INFO
--============================================
function ClassManager.GetClassName(player)
	return PlayerDataManager.GetActiveClass(player)
end

function ClassManager.GetClassData(player)
	local className = ClassManager.GetClassName(player)
	return ClassConfig.Classes[className]
end

function ClassManager.GetClassConfig(className)
	return ClassConfig.Classes[className]
end

--============================================
-- ATTACK TYPE (Class determines melee vs ranged)
--============================================
function ClassManager.IsRanged(player)
	local classData = ClassManager.GetClassData(player)
	return classData and classData.ranged == true
end

function ClassManager.IsMelee(player)
	return not ClassManager.IsRanged(player)
end

--============================================
-- ATTACK SHAPE (Now from WEAPON, not class!)
--============================================
function ClassManager.GetAttackShape(player)
	-- Try to get from weapon first
	if WeaponManager then
		local shape, params = WeaponManager.GetAttackShape(player)
		if shape then
			return shape
		end
	end

	-- Fallback to class default
	local classData = ClassManager.GetClassData(player)
	return classData and classData.attackShape or "Circle"
end

function ClassManager.GetShapeParams(player)
	-- Try to get from weapon first
	if WeaponManager then
		local shape, params = WeaponManager.GetAttackShape(player)
		if params then
			return params
		end
	end

	-- Fallback to class default
	local classData = ClassManager.GetClassData(player)
	return classData and classData.shapeParams or { radius = 5 }
end

--============================================
-- ATTACK SPEED (Now from WEAPON, not class!)
--============================================
function ClassManager.GetAttackSpeed(player)
	-- Try to get from weapon first
	if WeaponManager then
		local speed = WeaponManager.GetAttackSpeed(player)
		if speed then
			return speed
		end
	end

	-- Fallback to class default
	local classData = ClassManager.GetClassData(player)
	return classData and classData.baseAttackSpeed or 1.0
end

function ClassManager.GetAttackCooldown(player)
	local speed = ClassManager.GetAttackSpeed(player)
	return 1 / speed
end

--============================================
-- WEAPON ATTACK VALUE
--============================================
function ClassManager.GetWeaponAttack(player)
	if WeaponManager then
		return WeaponManager.GetWeaponAttack(player)
	end
	return 10  -- Fallback
end

--============================================
-- PROJECTILE CONFIG (Ranged classes only)
--============================================
function ClassManager.GetProjectileConfig(player)
	local classData = ClassManager.GetClassData(player)
	return classData and classData.projectile or nil
end

--============================================
-- RESOURCE
--============================================
function ClassManager.GetResourceType(player)
	local classData = ClassManager.GetClassData(player)
	return classData and classData.resource or "None"
end

--============================================
-- ANIMATIONS
--============================================
function ClassManager.GetBasicAttackAnimation(player)
	local classData = ClassManager.GetClassData(player)
	if not classData then return nil end
	return classData.animations and classData.animations.basicAttack or nil
end

--============================================
-- CLASS SWITCHING
--============================================
function ClassManager.SetClass(player, className)
	if not ClassConfig.Classes[className] then
		return false, "Invalid class"
	end

	local success, err = PlayerDataManager.SetActiveClass(player, className)
	if not success then
		return false, err
	end

	-- Refresh weapon stats for new class
	if WeaponManager then
		WeaponManager.EnsureStarterWeapon(player)
		PlayerDataManager.RefreshWeaponStats(player)
	end

	return true
end

--============================================
-- DEBUG
--============================================
function ClassManager.GetDebugInfo(player)
	local className = ClassManager.GetClassName(player)
	local shape = ClassManager.GetAttackShape(player)
	local params = ClassManager.GetShapeParams(player)
	local speed = ClassManager.GetAttackSpeed(player)
	local attack = ClassManager.GetWeaponAttack(player)

	local paramStr = ""
	for k, v in pairs(params) do
		paramStr = paramStr .. k .. "=" .. tostring(v) .. " "
	end

	return string.format(
		"Class: %s | Shape: %s (%s) | Speed: %.2f | ATK: %d",
		className, shape, paramStr, speed, attack
	)
end

return ClassManager