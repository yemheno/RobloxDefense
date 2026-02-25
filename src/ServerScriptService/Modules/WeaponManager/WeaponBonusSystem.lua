-- ServerScriptService/Modules/WeaponManager/WeaponBonusSystem

local WeaponBonusSystem = {}

local Modules = script.Parent.Parent
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry"))
local CurrencyManager = require(Modules:WaitForChild("CurrencyManager"))
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- Set by WeaponManager
WeaponBonusSystem.WeaponManager = nil

--============================================
-- INITIALIZATION
--============================================
function WeaponBonusSystem.Init()
	NetworkManager.GetEvent("WeaponRerollResult")

	print("[WeaponBonusSystem] Initialized")
end

--============================================
-- ROLL BONUSES
--============================================
function WeaponBonusSystem.RollBonuses(weaponId, tier)
	local availablePool = WeaponRegistry.GetAvailableBonusPool(weaponId, tier)
	local slotCount = WeaponConfig.TIER_BONUS_SLOTS[tier] or 2

	local bonuses = {}
	local usedStats = {}

	for i = 1, slotCount do
		local bonus = WeaponBonusSystem.RollSingleBonus(availablePool, usedStats, tier)
		if bonus then
			table.insert(bonuses, bonus)
			usedStats[bonus.stat] = true
		end
	end

	return bonuses
end

--============================================
-- ROLL SINGLE BONUS
--============================================
function WeaponBonusSystem.RollSingleBonus(availablePool, usedStats, tier)
	-- Filter out used stats
	local validOptions = {}
	for _, poolEntry in ipairs(availablePool) do
		if not usedStats[poolEntry.stat] then
			table.insert(validOptions, poolEntry)
		end
	end

	if #validOptions == 0 then
		return nil
	end

	-- Pick random
	local chosen = validOptions[math.random(#validOptions)]

	-- Roll value with tier multiplier
	local valueMultiplier = WeaponConfig.TIER_VALUE_MULTIPLIER[tier] or 1.0
	local minVal = math.floor(chosen.min * valueMultiplier)
	local maxVal = math.floor(chosen.max * valueMultiplier)
	local value = math.random(minVal, maxVal)

	return {
		stat = chosen.stat,
		value = value,
	}
end

--============================================
-- REROLL BONUSES
--============================================
function WeaponBonusSystem.Reroll(player)
	local weaponInstance = WeaponBonusSystem.WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then
		return false, "No weapon equipped"
	end

	local tier = weaponInstance.tier
	local cost = WeaponConfig.GetRerollCost(tier)

	-- Check currency
	local currentMerits = CurrencyManager.GetCurrency(player, "Merits")
	if currentMerits < cost then
		return false, "Not enough Merits (need " .. cost .. ")"
	end

	-- Deduct cost
	local success = CurrencyManager.RemoveCurrency(player, "Merits", cost)
	if not success then
		return false, "Failed to deduct Merits"
	end

	-- Roll new bonuses
	local oldBonuses = weaponInstance.bonuses
	local newBonuses = WeaponBonusSystem.RollBonuses(weaponInstance.weaponId, tier)
	weaponInstance.bonuses = newBonuses

	NetworkManager.FireClient(player, "WeaponRerollResult", {
		success = true,
		cost = cost,
		oldBonuses = oldBonuses,
		newBonuses = newBonuses,
		stats = WeaponBonusSystem.WeaponManager.GetCalculatedStats(player),
	})

	print("[WeaponBonusSystem]", player.Name, "rerolled for", cost, "Merits")
	return true, "Bonuses rerolled!"
end

--============================================
-- REROLL INFO
--============================================
function WeaponBonusSystem.GetRerollInfo(player)
	local weaponInstance = WeaponBonusSystem.WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then
		return { cost = 100, canAfford = false }
	end

	local tier = weaponInstance.tier
	local cost = WeaponConfig.GetRerollCost(tier)
	local currentMerits = CurrencyManager.GetCurrency(player, "Merits")

	return {
		cost = cost,
		currency = "Merits",
		canAfford = currentMerits >= cost,
		currentBonuses = weaponInstance.bonuses,
	}
end

return WeaponBonusSystem