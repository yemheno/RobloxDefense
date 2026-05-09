-- ServerScriptService/Modules/WeaponManager/WeaponBonusSystem

local WeaponBonusSystem = {}

local Modules = script.Parent.Parent
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry"))
local CurrencyManager = require(Modules:WaitForChild("CurrencyManager"))
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- Set by WeaponManager
WeaponBonusSystem.WeaponManager = nil

-- §WB1 fix: per-player reroll lock so two simultaneous Reroll requests can't
-- both pass CanAfford, both call SpendMerits, and both apply rolls.
local rerollLock = setmetatable({}, { __mode = "k" })

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
	-- §WB1: reentrancy guard before any state-touching work.
	if rerollLock[player] then
		return false, "Reroll already in progress"
	end

	local weaponInstance = WeaponBonusSystem.WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then
		return false, "No weapon equipped"
	end

	local tier = weaponInstance.tier
	local cost = WeaponConfig.GetRerollCost(tier)

	-- Check currency
	if not CurrencyManager.CanAffordMerits(player, cost) then
		return false, "Not enough Merits (need " .. cost .. ")"
	end

	rerollLock[player] = true

	-- Deduct cost
	local success = CurrencyManager.SpendMerits(player, cost)
	if not success then
		rerollLock[player] = nil
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
	rerollLock[player] = nil
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

	return {
		cost = cost,
		currency = "Merits",
		canAfford = CurrencyManager.CanAffordMerits(player, cost),
		currentBonuses = weaponInstance.bonuses,
	}
end

return WeaponBonusSystem