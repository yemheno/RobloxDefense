-- ServerScriptService/Modules/WeaponRegistry

local WeaponRegistry = {}

local Modules = script.Parent
local WeaponConfig      = require(Modules:WaitForChild("WeaponConfig"))
-- §CFG-D1: shared upgrade tables (level scaling, tier slots/pool/multiplier) live here.
local GearUpgradeConfig = require(Modules:WaitForChild("GearUpgradeConfig"))

-- Storage for all weapons
local weapons = {}           -- [weaponId] = weaponData
local weaponsByClass = {}    -- [className] = { weaponId, weaponId, ... }

--============================================
-- AUTO-LOAD FROM ClassWeapons FOLDER
--============================================
local function LoadClassWeapons()
	local classWeaponsFolder = Modules:FindFirstChild("ClassWeapons")
	if not classWeaponsFolder then
		warn("[WeaponRegistry] ClassWeapons folder not found!")
		return
	end

	for _, moduleScript in ipairs(classWeaponsFolder:GetChildren()) do
		if moduleScript:IsA("ModuleScript") then
			local success, classModule = pcall(require, moduleScript)

			if success and classModule then
				local className = classModule.CLASS

				if not className then
					warn("[WeaponRegistry] Module missing CLASS identifier:", moduleScript.Name)
					continue
				end

				if not classModule.Weapons then
					warn("[WeaponRegistry] Module missing Weapons table:", moduleScript.Name)
					continue
				end

				-- Initialize class weapon list
				weaponsByClass[className] = weaponsByClass[className] or {}

				-- Register each weapon
				local count = 0
				for weaponId, weaponData in pairs(classModule.Weapons) do
					-- Validate required fields
					if not weaponData.id then
						weaponData.id = weaponId
					end

					if not weaponData.class then
						weaponData.class = className
					end

					-- Store weapon
					weapons[weaponId] = weaponData
					table.insert(weaponsByClass[className], weaponId)
					count = count + 1
				end

				print("[WeaponRegistry] Loaded", count, "weapons for", className)
			else
				warn("[WeaponRegistry] Failed to load:", moduleScript.Name, classModule)
			end
		end
	end
end

--============================================
-- INITIALIZATION
--============================================
function WeaponRegistry.Init()
	LoadClassWeapons()

	local totalWeapons = 0
	for _ in pairs(weapons) do
		totalWeapons = totalWeapons + 1
	end

end

--============================================
-- WEAPON LOOKUP
--============================================

-- Get weapon definition by ID
function WeaponRegistry.GetWeapon(weaponId)
	return weapons[weaponId]
end

-- Get all weapons for a class
function WeaponRegistry.GetWeaponsByClass(className)
	local weaponIds = weaponsByClass[className]
	if not weaponIds then
		return {}
	end

	local result = {}
	for _, weaponId in ipairs(weaponIds) do
		result[weaponId] = weapons[weaponId]
	end
	return result
end

-- Get list of weapon IDs for a class
function WeaponRegistry.GetWeaponIdsForClass(className)
	return weaponsByClass[className] or {}
end

-- Check if weapon belongs to class
function WeaponRegistry.IsWeaponForClass(weaponId, className)
	local weapon = weapons[weaponId]
	return weapon and weapon.class == className
end

--============================================
-- STARTER WEAPON
--============================================
function WeaponRegistry.GetStarterWeaponId(className)
	return WeaponConfig.STARTER_WEAPONS[className]
end

--============================================
-- CALCULATED STATS
-- These calculate final stats based on weapon instance data
--============================================

-- Calculate scaled attack for a weapon instance
-- Parameters: weaponId, level, refinement, tier
function WeaponRegistry.CalculateAttack(weaponId, level, refinement, tier)
	local weapon = weapons[weaponId]
	if not weapon then return 0 end

	level = level or 1
	refinement = refinement or 0
	tier = tier or 1

	-- Base attack
	local baseAttack = weapon.baseAttack or 10

	-- Level scaling: baseAttack * (1 + SCALE%) ^ floor(level/10)
	local levelMultiplier = (1 + GearUpgradeConfig.LEVEL_SCALE_PERCENT) ^ math.floor(level / 10)
	local leveledAttack = baseAttack * levelMultiplier

	-- Refinement bonus (flat, added to base before tier)
	local refinementBonus = (weapon.refinementAttackBonus or 0) * refinement

	-- Tier bonus (percentage)
	local tierBonus = WeaponConfig.TIER_ATK_BONUS[tier] or 0

	-- Final calculation
	local finalAttack = (leveledAttack + refinementBonus) * (1 + tierBonus)

	return math.floor(finalAttack)
end

-- Calculate attack speed for a weapon instance
function WeaponRegistry.CalculateAttackSpeed(weaponId, tier)
	local weapon = weapons[weaponId]
	if not weapon then return 1.0 end

	tier = tier or 1

	-- Base attack speed
	local baseSpeed = weapon.baseAttackSpeed or 1.0

	-- Tier doesn't affect attack speed (yet).
	return baseSpeed
end

-- Get attack shape for a weapon
function WeaponRegistry.GetAttackShape(weaponId)
	local weapon = weapons[weaponId]
	if not weapon then return nil, nil end

	return weapon.attackShape, weapon.shapeParams
end

-- Get shape params with tier scaling (future: range increase per tier)
function WeaponRegistry.GetScaledShapeParams(weaponId, tier)
	local weapon = weapons[weaponId]
	if not weapon then return nil end

	tier = tier or 1

	-- Copy base params
	local params = {}
	for k, v in pairs(weapon.shapeParams or {}) do
		params[k] = v
	end

	-- Tier doesn't scale range (yet); `tier` is accepted for that seam.

	return params
end

--============================================
-- BONUS POOL
--============================================

-- Get available bonus pool for a weapon at a given tier
function WeaponRegistry.GetAvailableBonusPool(weaponId, tier)
	local weapon = weapons[weaponId]
	if not weapon or not weapon.bonusPool then
		return {}
	end

	tier = tier or 1
	local maxIndex = GearUpgradeConfig.TIER_POOL_UNLOCKS[tier] or 3

	local available = {}
	for i, bonus in ipairs(weapon.bonusPool) do
		if i <= maxIndex then
			table.insert(available, {
				index = i,
				stat = bonus.stat,
				min = bonus.min,
				max = bonus.max,
			})
		end
	end

	return available
end

-- Get bonus slot count for a tier
function WeaponRegistry.GetBonusSlotCount(tier)
	return GearUpgradeConfig.TIER_BONUS_SLOTS[tier] or 2
end

-- Get value multiplier for a tier
function WeaponRegistry.GetTierValueMultiplier(tier)
	return GearUpgradeConfig.TIER_VALUE_MULTIPLIER[tier] or 1.0
end

return WeaponRegistry