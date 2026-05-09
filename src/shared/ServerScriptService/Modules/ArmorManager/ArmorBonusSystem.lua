-- ServerScriptService/Modules/ArmorManager/ArmorBonusSystem
--[[
    Random bonus rolling and rerolling for armors.
    Mirrors WeaponBonusSystem but uses ArmorConfig / ArmorRegistry.
]]

local ArmorBonusSystem = {}

local Modules         = script.Parent.Parent
local ArmorConfig     = require(Modules:WaitForChild("ArmorConfig"))
local ArmorRegistry   = require(Modules:WaitForChild("ArmorRegistry"))
local CurrencyManager = require(Modules:WaitForChild("CurrencyManager"))
local NetworkManager  = require(Modules:WaitForChild("NetworkManager"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))

ArmorBonusSystem.ArmorManager = nil

-- §AB1 fix: per-player reroll lock (mirrors WeaponBonusSystem §WB1).
local rerollLock = setmetatable({}, { __mode = "k" })

--============================================
-- INITIALIZATION
--============================================
function ArmorBonusSystem.Init()
	NetworkManager.GetEvent("ArmorRerollResult")
	print("[ArmorBonusSystem] Initialized")
end

--============================================
-- ROLL BONUSES
--============================================
function ArmorBonusSystem.RollBonuses(armorId, tier)
	local availablePool = ArmorRegistry.GetAvailableBonusPool(armorId, tier)
	local slotCount     = ArmorConfig.TIER_BONUS_SLOTS[tier] or 2

	local bonuses   = {}
	local usedStats = {}

	for _i = 1, slotCount do
		local bonus = ArmorBonusSystem.RollSingleBonus(availablePool, usedStats, tier)
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
function ArmorBonusSystem.RollSingleBonus(availablePool, usedStats, tier)
	local validOptions = {}
	for _, poolEntry in ipairs(availablePool) do
		if not usedStats[poolEntry.stat] then
			table.insert(validOptions, poolEntry)
		end
	end

	if #validOptions == 0 then return nil end

	local chosen = validOptions[math.random(#validOptions)]

	local valueMultiplier = ArmorConfig.TIER_VALUE_MULTIPLIER[tier] or 1.0
	local minVal = math.floor(chosen.min * valueMultiplier)
	local maxVal = math.floor(chosen.max * valueMultiplier)
	local value  = math.random(minVal, maxVal)

	return {
		stat  = chosen.stat,
		value = value,
	}
end

--============================================
-- REROLL BONUSES
--============================================
function ArmorBonusSystem.Reroll(player)
	-- §AB1: reentrancy guard before any state-touching work.
	if rerollLock[player] then
		return false, "Reroll already in progress"
	end

	local armorInstance = ArmorBonusSystem.ArmorManager.GetEquippedArmor(player)
	if not armorInstance then
		return false, "No armor equipped"
	end

	local tier = armorInstance.tier
	local cost = ArmorConfig.GetRerollCost(tier)

	if cost > 0 and not CurrencyManager.CanAffordMerits(player, cost) then
		return false, "Not enough Merits (need " .. cost .. ")"
	end

	rerollLock[player] = true

	if cost > 0 then
		local success = CurrencyManager.SpendMerits(player, cost)
		if not success then
			rerollLock[player] = nil
			return false, "Failed to deduct Merits"
		end
	end

	local oldBonuses = armorInstance.bonuses
	local newBonuses = ArmorBonusSystem.RollBonuses(armorInstance.armorId, tier)
	armorInstance.bonuses = newBonuses

	PlayerDataManager.RefreshArmorStats(player)

	NetworkManager.FireClient(player, "ArmorRerollResult", {
		success    = true,
		cost       = cost,
		oldBonuses = oldBonuses,
		newBonuses = newBonuses,
		stats      = ArmorBonusSystem.ArmorManager.GetCalculatedStats(player),
	})

	print("[ArmorBonusSystem]", player.Name, "rerolled armor for", cost, "Merits")
	rerollLock[player] = nil
	return true, "Bonuses rerolled!"
end

--============================================
-- REROLL INFO
--============================================
function ArmorBonusSystem.GetRerollInfo(player)
	local armorInstance = ArmorBonusSystem.ArmorManager.GetEquippedArmor(player)
	if not armorInstance then
		return { cost = 100, canAfford = false }
	end

	local tier = armorInstance.tier
	local cost = ArmorConfig.GetRerollCost(tier)

	return {
		cost           = cost,
		currency       = "Merits",
		canAfford      = cost == 0 or CurrencyManager.CanAffordMerits(player, cost),
		currentBonuses = armorInstance.bonuses,
	}
end

return ArmorBonusSystem
