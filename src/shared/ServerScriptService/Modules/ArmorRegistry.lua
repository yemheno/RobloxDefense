-- ServerScriptService/Modules/ArmorRegistry
--[[
    Auto-loads armor definitions from the ClassArmors/ folder.
    Mirrors WeaponRegistry structure for defensive gear.
]]

local ArmorRegistry = {}

local Modules     = script.Parent
local ArmorConfig = require(Modules:WaitForChild("ArmorConfig"))

-- Storage
local armors        = {}   -- [armorId] = armorData
local armorsByClass = {}   -- [className] = { armorId, armorId, ... }

--============================================
-- AUTO-LOAD FROM ClassArmors FOLDER
--============================================
local function LoadClassArmors()
	local classArmorsFolder = Modules:FindFirstChild("ClassArmors")
	if not classArmorsFolder then
		warn("[ArmorRegistry] ClassArmors folder not found!")
		return
	end

	for _, moduleScript in ipairs(classArmorsFolder:GetChildren()) do
		if moduleScript:IsA("ModuleScript") then
			local success, classModule = pcall(require, moduleScript)

			if success and classModule then
				local className = classModule.CLASS

				if not className then
					warn("[ArmorRegistry] Module missing CLASS:", moduleScript.Name)
					continue
				end

				if not classModule.Armors then
					warn("[ArmorRegistry] Module missing Armors table:", moduleScript.Name)
					continue
				end

				armorsByClass[className] = armorsByClass[className] or {}

				local count = 0
				for armorId, armorData in pairs(classModule.Armors) do
					if not armorData.id then
						armorData.id = armorId
					end
					if not armorData.class then
						armorData.class = className
					end

					armors[armorId] = armorData
					table.insert(armorsByClass[className], armorId)
					count = count + 1
				end

				print("[ArmorRegistry] Loaded", count, "armors for", className)
			else
				warn("[ArmorRegistry] Failed to load:", moduleScript.Name, classModule)
			end
		end
	end
end

--============================================
-- INITIALIZATION
--============================================
function ArmorRegistry.Init()
	LoadClassArmors()

	local totalArmors = 0
	for _ in pairs(armors) do
		totalArmors = totalArmors + 1
	end

	print("[ArmorRegistry] Initialized with", totalArmors, "total armors")
end

--============================================
-- ARMOR LOOKUP
--============================================
function ArmorRegistry.GetArmor(armorId)
	return armors[armorId]
end

function ArmorRegistry.GetArmorsByClass(className)
	local armorIds = armorsByClass[className]
	if not armorIds then return {} end

	local result = {}
	for _, armorId in ipairs(armorIds) do
		result[armorId] = armors[armorId]
	end
	return result
end

function ArmorRegistry.GetArmorIdsForClass(className)
	return armorsByClass[className] or {}
end

function ArmorRegistry.IsArmorForClass(armorId, className)
	local armor = armors[armorId]
	return armor and armor.class == className
end

--============================================
-- STARTER ARMOR
--============================================
function ArmorRegistry.GetStarterArmorId(className)
	return ArmorConfig.STARTER_ARMORS[className]
end

--============================================
-- CALCULATED STATS
--============================================
function ArmorRegistry.CalculateDefense(armorId, level, refinement, tier)
	local armor = armors[armorId]
	if not armor then return 0 end

	level      = level or 1
	refinement = refinement or 0
	tier       = tier or 1

	local baseDefense = armor.baseDefense or 5

	-- Level scaling: same formula as weapons
	local levelMultiplier = (1 + ArmorConfig.LEVEL_SCALE_PERCENT) ^ math.floor(level / 10)
	local leveledDefense  = baseDefense * levelMultiplier

	-- Refinement bonus (flat)
	local refinementBonus = (armor.refinementDefenseBonus or 0) * refinement

	-- Tier bonus (percentage)
	local tierBonus = ArmorConfig.TIER_DEF_BONUS[tier] or 0

	local finalDefense = (leveledDefense + refinementBonus) * (1 + tierBonus)
	return math.floor(finalDefense)
end

function ArmorRegistry.CalculateBonusHealth(armorId, level, tier)
	local armor = armors[armorId]
	if not armor then return 0 end

	level = level or 1
	tier  = tier or 1

	local baseHealth = armor.baseHealth or 0

	-- Level scaling
	local levelMultiplier = (1 + ArmorConfig.LEVEL_SCALE_PERCENT) ^ math.floor(level / 10)
	local leveledHealth   = baseHealth * levelMultiplier

	-- Tier bonus (same percentage as defense)
	local tierBonus = ArmorConfig.TIER_DEF_BONUS[tier] or 0
	local finalHealth = leveledHealth * (1 + tierBonus)

	return math.floor(finalHealth)
end

--============================================
-- BONUS POOL
--============================================
function ArmorRegistry.GetAvailableBonusPool(armorId, tier)
	local armor = armors[armorId]
	if not armor or not armor.bonusPool then
		return {}
	end

	tier = tier or 1
	local maxIndex = ArmorConfig.TIER_POOL_UNLOCKS[tier] or 3

	local available = {}
	for i, bonus in ipairs(armor.bonusPool) do
		if i <= maxIndex then
			table.insert(available, {
				index = i,
				stat  = bonus.stat,
				min   = bonus.min,
				max   = bonus.max,
			})
		end
	end

	return available
end

function ArmorRegistry.GetBonusSlotCount(tier)
	return ArmorConfig.TIER_BONUS_SLOTS[tier] or 2
end

function ArmorRegistry.GetTierValueMultiplier(tier)
	return ArmorConfig.TIER_VALUE_MULTIPLIER[tier] or 1.0
end

return ArmorRegistry
