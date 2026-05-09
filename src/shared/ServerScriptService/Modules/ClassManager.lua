-- ServerScriptService/Modules/ClassManager

local ClassManager = {}

local Modules = script.Parent
local ClassConfig = require(Modules:WaitForChild("ClassConfig"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))

-- WeaponManager loaded after init (circular dependency prevention)
local WeaponManager = nil

-- ArmorManager loaded lazily (same pattern as WeaponManager)
local ArmorManager = nil

-- ResourceManager loaded lazily to notify on class change
local ResourceManager = nil

-- VisualEquipmentManager loaded lazily for visual re-equip on class switch
local VisualEquipmentManager = nil

-- CosmeticManager loaded lazily for outfit swap on class switch
local CosmeticManager = nil

-- GameStateManager loaded lazily to guard class switches during combat
local GameStateManager = nil

-- BonusManager loaded lazily for innate bonus application
local BonusManager = nil
local function getBonusManager()
	if not BonusManager then
		local bmMod = Modules:FindFirstChild("BonusManager")
		if bmMod then BonusManager = require(bmMod) end
	end
	return BonusManager
end

--============================================
-- INITIALIZATION
--============================================
function ClassManager.Init()
	-- Delayed WeaponManager require (it requires us, we require it)
	task.spawn(function()
		WeaponManager = require(Modules:WaitForChild("WeaponManager"))
	end)

	-- Delayed ArmorManager require (same circular-dep pattern)
	task.spawn(function()
		ArmorManager = require(Modules:WaitForChild("ArmorManager"))
	end)

	-- Delayed VisualEquipmentManager require
	task.spawn(function()
		VisualEquipmentManager = require(Modules:WaitForChild("VisualEquipmentManager"))
	end)

	-- Delayed CosmeticManager require
	task.spawn(function()
		local cm = Modules:FindFirstChild("CosmeticManager")
		if cm then
			CosmeticManager = require(cm)
		end
	end)

	-- Lazy load GameStateManager (may not exist in all places)
	task.spawn(function()
		local gsm = Modules:FindFirstChild("GameStateManager")
		if gsm then
			GameStateManager = require(gsm)
		end
	end)

	-- Lazy load ResourceManager
	task.spawn(function()
		local rm = Modules:FindFirstChild("ResourceManager")
		if rm then
			ResourceManager = require(rm)
		end
	end)

	-- Apply innate class passives automatically when any player's data loads.
	-- This replaces the per-game-mode calls scattered in Main scripts and
	-- ensures innate bonuses are always present regardless of boot order.
	PlayerDataManager.OnPlayerDataReady(function(player)
		ClassManager.ApplyInnateBonus(player)
	end)

	-- Remote: client asks to switch to a class they've already unlocked
	local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

	-- Pre-create ClassSwitchResult so the client's WaitForChild resolves immediately on mount
	NetworkManager.GetEvent("ClassSwitchResult")

	NetworkManager.OnClientEvent("RequestClassSwitch", function(player, className)
		if not ClassConfig.Classes[className] then
			NetworkManager.FireClient(player, "ClassSwitchResult", false, "Unknown class: " .. tostring(className))
			return
		end

		-- Block class switching during active combat (Preparing / Defending)
		if GameStateManager and GameStateManager.IsInGame() then
			NetworkManager.FireClient(player, "ClassSwitchResult", false, "Cannot switch class during combat")
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
-- ANIMATIONS
--============================================
function ClassManager.GetBasicAttackAnimation(player)
	local classData = ClassManager.GetClassData(player)
	if not classData then return nil end
	return classData.animations and classData.animations.basicAttack or nil
end

--============================================
-- INNATE BONUS APPLICATION
--============================================
--- Reads the active (or given) class's innateBonuses and writes them
--- into BonusManager's "innate" source, replacing any old class's passives.
function ClassManager.ApplyInnateBonus(player, className)
	local bm = getBonusManager()
	if not bm then return end
	local cn = className or PlayerDataManager.GetActiveClass(player)
	local classConfig = ClassConfig.Classes[cn]
	bm.SetSourceBonuses(player, "innate", (classConfig and classConfig.innateBonuses) or {})
end

--============================================
-- CLASS SWITCHING
--============================================
function ClassManager.SetClass(player, className)
	if not ClassConfig.Classes[className] then
		return false, "Invalid class"
	end

	local oldClassName = PlayerDataManager.GetActiveClass(player)

	local success, err = PlayerDataManager.SetActiveClass(player, className)
	if not success then
		return false, err
	end

	-- Notify ResourceManager so it resets the resource bar for the new class
	if ResourceManager and ResourceManager.OnClassChanged then
		ResourceManager.OnClassChanged(player, className, oldClassName)
	end

	-- Ensure starter equipment for the new class
	if WeaponManager then
		WeaponManager.EnsureStarterWeapon(player)
		PlayerDataManager.RefreshWeaponStats(player)
	end

	if ArmorManager then
		ArmorManager.EnsureStarterArmor(player)
	end

	-- Re-attach weapon visual for the new class
	if VisualEquipmentManager then
		local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry"))

		local wInst = WeaponManager and WeaponManager.GetEquippedWeapon(player)
		if wInst then
			local wDef = WeaponRegistry.GetWeapon(wInst.weaponId)
			if wDef and wDef.weaponSlot then
				VisualEquipmentManager.AttachClassWeapon(player, className, wDef.weaponSlot)
			end
		end
	end

	-- Swap cosmetics (outfit, headgear) to match new class defaults/restrictions
	if CosmeticManager then
		CosmeticManager.OnClassSwitched(player, className)
	end

	-- Apply innate class passives via BonusManager
	ClassManager.ApplyInnateBonus(player, className)

	return true
end

return ClassManager