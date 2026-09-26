-- ServerScriptService/Modules/ArmorManager/ArmorBonusSystem
--[[
    Random bonus rolling and rerolling for armors.
    Mirrors WeaponBonusSystem but uses ArmorConfig / ArmorRegistry.
]]

local ArmorBonusSystem = {}

local Modules         = script.Parent.Parent
-- §CFG-D1: tier slot/value tables + reroll cost are shared with weapons —
-- read them from GearUpgradeConfig. ArmorConfig retained for any
-- armor-specific reads added later.
local GearUpgradeConfig = require(Modules:WaitForChild("GearUpgradeConfig"))
local ArmorRegistry   = require(Modules:WaitForChild("ArmorRegistry"))
local CurrencyManager = require(Modules:WaitForChild("CurrencyManager"))
local NetworkManager  = require(Modules:WaitForChild("NetworkManager"))
-- §AGX/UI-P4: player-facing rejections used to be silent (return value
-- dropped by the caller / warn only). NotifyService pushes a toast; it
-- never throws, and a missing module is skipped, so logic is unchanged.
local NotifyService = nil
local function notifyReject(player, text)
	if not NotifyService then
		local mod = Modules:FindFirstChild("NotifyService")
		if mod then
			local ok, svc = pcall(require, mod)
			if ok then NotifyService = svc end
		end
	end
	if NotifyService then NotifyService.Toast(player, "error", text) end
end
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))

ArmorBonusSystem.ArmorManager = nil

-- §AB1 fix: per-player reroll lock (mirrors WeaponBonusSystem §WB1).
local rerollLock = setmetatable({}, { __mode = "k" })

--============================================
-- INITIALIZATION
--============================================
function ArmorBonusSystem.Init()
	NetworkManager.GetEvent("ArmorRerollResult")
end

--============================================
-- ROLL BONUSES
--============================================
function ArmorBonusSystem.RollBonuses(armorId, tier)
	local availablePool = ArmorRegistry.GetAvailableBonusPool(armorId, tier)
	local slotCount     = GearUpgradeConfig.TIER_BONUS_SLOTS[tier] or 2

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

	local valueMultiplier = GearUpgradeConfig.TIER_VALUE_MULTIPLIER[tier] or 1.0
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
-- §AGX/WC: body split out so the public Reroll can guarantee lock release
-- even if something throws midway (mirrors EquipmentRefinement.attemptLock).
-- §AGX/D-FIX: S4 — txn records what was spent / whether the item changed, so an error can be refunded exactly.
local function rerollBody(player, txn)
	local armorInstance = ArmorBonusSystem.ArmorManager.GetEquippedArmor(player)
	if not armorInstance then
		notifyReject(player, "No armor equipped")  -- §AGX/UI-P4
		return false, "No armor equipped"
	end

	local tier = armorInstance.tier
	local cost = GearUpgradeConfig.GetRerollCost(tier)

	if cost > 0 and not CurrencyManager.CanAffordMerits(player, cost) then
		notifyReject(player, "Not enough Merits (need " .. cost .. ")")  -- §AGX/UI-P4
		return false, "Not enough Merits (need " .. cost .. ")"
	end

	if cost > 0 then
		local success = CurrencyManager.SpendMerits(player, cost)
		if not success then
			notifyReject(player, "Not enough Merits")  -- §AGX/UI-P4
		return false, "Failed to deduct Merits"
		end
		txn.spentMerits = cost  -- §AGX/D-FIX: S4
	end

	local oldBonuses = armorInstance.bonuses
	local newBonuses = ArmorBonusSystem.RollBonuses(armorInstance.armorId, tier)
	armorInstance.bonuses = newBonuses
	txn.mutated = true  -- §AGX/D-FIX: S4 — item changed; an error past here is not refunded

	PlayerDataManager.RefreshArmorStats(player)

	NetworkManager.FireClient(player, "ArmorRerollResult", {
		success    = true,
		cost       = cost,
		oldBonuses = oldBonuses,
		newBonuses = newBonuses,
		stats      = ArmorBonusSystem.ArmorManager.GetCalculatedStats(player),
	})

	print("[ArmorBonusSystem]", player.Name, "rerolled armor for", cost, "Merits")
	return true, "Bonuses rerolled!"
end

function ArmorBonusSystem.Reroll(player)
	-- §AB1: reentrancy guard before any state-touching work.
	if rerollLock[player] then
		return false, "Reroll already in progress"
	end
	-- §AGX/WC: lock held only for the pcall'd body; released on every path, including errors.
	rerollLock[player] = true
	local txn = { spentMerits = 0, mutated = false }  -- §AGX/D-FIX: S4
	local ok, success, msg = pcall(rerollBody, player, txn)
	rerollLock[player] = nil
	if not ok then
		warn("[ArmorBonusSystem] Reroll errored for", player.Name, ":", success)
		-- §AGX/D-FIX: S4 — refund exactly what was spent if the item is untouched (raw: no MeritBonus); always tell the player.
		if txn.mutated then
			warn("[ArmorBonusSystem] !!! Reroll errored AFTER bonuses changed for", player.Name,
				"— NOT refunded (spent", txn.spentMerits, "Merits)")
			pcall(notifyReject, player, "Something went wrong — reroll applied, reopen the menu.")
		else
			if txn.spentMerits > 0 then
				local rOk, rErr = pcall(CurrencyManager.AddMerits, player, txn.spentMerits, { raw = true })
				if not rOk then warn("[ArmorBonusSystem] !!! Refund FAILED for", player.Name, ":", rErr) end
			end
			pcall(notifyReject, player, "Something went wrong — refunded.")
		end
		return false, "Reroll failed"
	end
	return success, msg
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
	local cost = GearUpgradeConfig.GetRerollCost(tier)

	return {
		cost           = cost,
		currency       = "Merits",
		canAfford      = cost == 0 or CurrencyManager.CanAffordMerits(player, cost),
		currentBonuses = armorInstance.bonuses,
	}
end

return ArmorBonusSystem
