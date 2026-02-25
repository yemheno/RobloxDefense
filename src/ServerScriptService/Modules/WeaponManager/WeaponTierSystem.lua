-- ServerScriptService/Modules/WeaponManager/WeaponTierSystem

local WeaponTierSystem = {}

local Modules = script.Parent.Parent
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry"))
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- Set by WeaponManager
WeaponTierSystem.WeaponManager = nil

-- Reference to BonusSystem (set after init)
local BonusSystem = nil

--============================================
-- INITIALIZATION
--============================================
function WeaponTierSystem.Init()
	BonusSystem = require(script.Parent:WaitForChild("WeaponBonusSystem"))

	NetworkManager.GetEvent("WeaponTierUp")

	print("[WeaponTierSystem] Initialized")
end

--============================================
-- UPGRADE TIER
--============================================
function WeaponTierSystem.Upgrade(player)
	local weaponInstance = WeaponTierSystem.WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then
		return false, "No weapon equipped"
	end

	local currentTier = weaponInstance.tier

	-- Check max
	if currentTier >= WeaponConfig.TIER_MAX then
		return false, "Already at max tier"
	end

	-- Upgrade
	local newTier = currentTier + 1
	weaponInstance.tier = newTier

	-- Check for new bonus slots
	local oldSlots = WeaponConfig.TIER_BONUS_SLOTS[currentTier] or 2
	local newSlots = WeaponConfig.TIER_BONUS_SLOTS[newTier] or 2

	if newSlots > oldSlots then
		local additionalSlots = newSlots - #weaponInstance.bonuses

		if additionalSlots > 0 then
			local availablePool = WeaponRegistry.GetAvailableBonusPool(weaponInstance.weaponId, newTier)

			-- Get used stats
			local usedStats = {}
			for _, bonus in ipairs(weaponInstance.bonuses) do
				usedStats[bonus.stat] = true
			end

			-- Add new bonuses
			for i = 1, additionalSlots do
				local newBonus = BonusSystem.RollSingleBonus(availablePool, usedStats, newTier)
				if newBonus then
					table.insert(weaponInstance.bonuses, newBonus)
					usedStats[newBonus.stat] = true
				end
			end
		end
	end

	NetworkManager.FireClient(player, "WeaponTierUp", {
		oldTier = currentTier,
		newTier = newTier,
		newBonusSlots = newSlots,
		bonuses = weaponInstance.bonuses,
		stats = WeaponTierSystem.WeaponManager.GetCalculatedStats(player),
	})

	print("[WeaponTierSystem]", player.Name, "tier up: Tier", currentTier, "→ Tier", newTier)
	return true, "Tier upgraded!"
end

--============================================
-- TIER INFO
--============================================
function WeaponTierSystem.GetInfo(player)
	local weaponInstance = WeaponTierSystem.WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then
		return { tier = 1, bonusSlots = 2, atkBonus = 0, isMax = false }
	end

	local tier = weaponInstance.tier

	return {
		tier = tier,
		bonusSlots = WeaponConfig.TIER_BONUS_SLOTS[tier] or 2,
		atkBonus = math.floor((WeaponConfig.TIER_ATK_BONUS[tier] or 0) * 100),
		valueMultiplier = WeaponConfig.TIER_VALUE_MULTIPLIER[tier] or 1.0,
		poolUnlocks = WeaponConfig.TIER_POOL_UNLOCKS[tier] or 3,
		isMax = tier >= WeaponConfig.TIER_MAX,
	}
end

return WeaponTierSystem