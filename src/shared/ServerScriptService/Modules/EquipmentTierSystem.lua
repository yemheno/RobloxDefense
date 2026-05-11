-- ServerScriptService/Modules/EquipmentTierSystem
--[[
    Shared tier upgrade system factory for armor and weapons.
    Takes a config and equipment type, returns a tier system module.
]]

-- BonusSystemModule: the ModuleScript for WeaponBonusSystem / ArmorBonusSystem.
-- Passed in by the caller because the bonus systems live in subfolders
-- (WeaponManager/, ArmorManager/) that EquipmentTierSystem cannot see from Modules/.
local function CreateTierSystem(Config, RegistryModule, BonusSystemModule, equipmentType)
    local System = {}

    local Modules         = script.Parent
    local CurrencyManager = require(Modules:WaitForChild("CurrencyManager"))
    local NetworkManager  = require(Modules:WaitForChild("NetworkManager"))
    local ChapterConfig   = require(Modules:WaitForChild("ChapterConfig"))
    local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
    local Registry        = require(RegistryModule)

    -- Will be set by the manager
    System.Manager = nil

    local BonusSystem = nil  -- filled in Init

    -- §ET2 fix: per-player tier-upgrade lock (same shape as EquipmentRefinement).
    local upgradeLock = setmetatable({}, { __mode = "k" })

    -- Determine naming conventions based on equipment type
    local getEquippedMethod
    local eventName
    local bonusSystemName
    local logPrefix
    local refreshMethod
    local bonusStatField
    local equipmentIdField

    if equipmentType == "armor" then
        getEquippedMethod = "GetEquippedArmor"
        eventName = "ArmorTierUp"
        bonusSystemName = "ArmorBonusSystem"
        logPrefix = "[ArmorTierSystem]"
        refreshMethod = "RefreshArmorStats"
        bonusStatField = "defBonus"
        equipmentIdField = "armorId"
    elseif equipmentType == "weapon" then
        getEquippedMethod = "GetEquippedWeapon"
        eventName = "WeaponTierUp"
        bonusSystemName = "WeaponBonusSystem"
        logPrefix = "[WeaponTierSystem]"
        refreshMethod = "RefreshWeaponStats"
        bonusStatField = "atkBonus"
        equipmentIdField = "weaponId"
    else
        error("Unknown equipment type: " .. equipmentType)
    end

    --============================================
    -- INITIALIZATION
    --============================================
    function System.Init()
        BonusSystem = require(BonusSystemModule)
        NetworkManager.GetEvent(eventName)
    end

    --============================================
    -- UPGRADE TIER
    --============================================
    function System.Upgrade(player)
        -- §ET2: reentrancy guard — must run BEFORE re-reading state.
        if upgradeLock[player] then
            return false, "Tier upgrade already in progress"
        end

        local instance = System.Manager[getEquippedMethod](player)
        if not instance then
            return false, "No " .. equipmentType .. " equipped"
        end

        local currentTier = instance.tier
        if currentTier >= Config.TIER_MAX then
            return false, "Already at max tier"
        end

        -- Chapter-based tier cap (§12)
        local playerLevel = PlayerDataManager.GetAccountData(player, "Level") or 1
        local chapterMaxTier = ChapterConfig.GetMaxTier(playerLevel)
        if currentTier >= chapterMaxTier then
            return false, "Tier capped at " .. chapterMaxTier .. " for your chapter"
        end

        -- Check minimum refinement requirement (§12)
        local minRefine = Config.TIER_MIN_REFINE and Config.TIER_MIN_REFINE[currentTier]
        if minRefine and (instance.refinement or 0) < minRefine then
            return false, equipmentType:sub(1, 1):upper() .. equipmentType:sub(2) .. " must be +" .. minRefine .. " refinement to tier up"
        end

        -- Cost check.
        -- §ET1 fix: was ignoring SpendMerits/SpendEssence return value, so a
        -- losing race could grant the upgrade for free. Now we abort if the
        -- spend fails after CanAfford passed.
        upgradeLock[player] = true
        local cost     = Config.GetTierCost(currentTier)
        local currency = Config.TIER_CURRENCY
        if cost > 0 then
            local canAfford
            if currency == "Merits" then
                canAfford = CurrencyManager.CanAffordMerits(player, cost)
            else
                canAfford = CurrencyManager.CanAffordEssence(player, cost)
            end
            if not canAfford then
                upgradeLock[player] = nil
                return false, "Not enough " .. currency
            end
            local spendOk
            if currency == "Merits" then
                spendOk = CurrencyManager.SpendMerits(player, cost)
            else
                spendOk = CurrencyManager.SpendEssence(player, cost)
            end
            if not spendOk then
                upgradeLock[player] = nil
                return false, "Not enough " .. currency
            end
        end

        local newTier = currentTier + 1
        instance.tier = newTier

        -- Reset refinement and temper on tier up (progression restarts each tier)
        local oldRefinement = instance.refinement or 0
        instance.refinement = 0
        instance.temper = 0

        -- Check for new bonus slots
        local oldSlots = Config.TIER_BONUS_SLOTS[currentTier] or 2
        local newSlots = Config.TIER_BONUS_SLOTS[newTier] or 2

        if newSlots > oldSlots then
            local additionalSlots = newSlots - #instance.bonuses
            if additionalSlots > 0 then
                local availablePool = Registry.GetAvailableBonusPool(instance[equipmentIdField], newTier)
                local usedStats = {}
                for _, bonus in ipairs(instance.bonuses) do
                    usedStats[bonus.stat] = true
                end
                for _i = 1, additionalSlots do
                    local newBonus = BonusSystem.RollSingleBonus(availablePool, usedStats, newTier)
                    if newBonus then
                        table.insert(instance.bonuses, newBonus)
                        usedStats[newBonus.stat] = true
                    end
                end
            end
        end

        NetworkManager.FireClient(player, eventName, {
            oldTier      = currentTier,
            newTier      = newTier,
            oldRefinement = oldRefinement,
            newRefinement = 0,
            newBonusSlots = newSlots,
            bonuses      = instance.bonuses,
            stats        = System.Manager.GetCalculatedStats(player),
        })

        PlayerDataManager[refreshMethod](player)
        print(logPrefix, player.Name, "tier up: Tier", currentTier, "→ Tier", newTier)
        upgradeLock[player] = nil
        return true, "Tier upgraded!"
    end

    --============================================
    -- TIER INFO
    --============================================
    function System.GetInfo(player)
        local instance = System.Manager[getEquippedMethod](player)
        if not instance then
            return { tier = 1, bonusSlots = 2, [bonusStatField] = 0, isMax = false }
        end

        local tier = instance.tier
        local info = {
            tier            = tier,
            bonusSlots      = Config.TIER_BONUS_SLOTS[tier] or 2,
            valueMultiplier = Config.TIER_VALUE_MULTIPLIER[tier] or 1.0,
            poolUnlocks     = Config.TIER_POOL_UNLOCKS[tier] or 3,
            isMax           = tier >= Config.TIER_MAX,
            cost            = Config.GetTierCost(tier),
            currency        = Config.TIER_CURRENCY,
        }

        -- Add equipment-specific bonus stat field
        local bonusTableKey = bonusStatField == "defBonus" and "TIER_DEF_BONUS" or "TIER_ATK_BONUS"
        info[bonusStatField] = math.floor((Config[bonusTableKey][tier] or 0) * 100)

        return info
    end

    return System
end

return CreateTierSystem
