-- ServerScriptService/Modules/EquipmentRefinement
--[[
    Shared refinement system factory for armor and weapons.
    Takes a config and equipment type, returns a refinement system module.
]]

local function CreateRefinementSystem(Config, equipmentType)
    local System = {}

    local Modules         = script.Parent
    local CurrencyManager = require(Modules:WaitForChild("CurrencyManager"))
    local NetworkManager  = require(Modules:WaitForChild("NetworkManager"))
    local ChapterConfig   = require(Modules:WaitForChild("ChapterConfig"))
    local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))

    -- Will be set by the manager
    System.Manager = nil

    -- §ER2 fix: per-player attempt lock so two concurrent Attempt() calls
    -- can't both pass the cost check, both call SpendMerits/SpendEssence,
    -- and both apply rolls. Weak keys so disconnecting players are GC'd.
    local attemptLock = setmetatable({}, { __mode = "k" })

    -- Determine naming conventions based on equipment type
    local getEquippedMethod
    local eventName
    local instanceProperty
    local logPrefix
    local refreshMethod

    if equipmentType == "armor" then
        getEquippedMethod = "GetEquippedArmor"
        eventName = "ArmorRefinementResult"
        instanceProperty = "armorInstance"
        logPrefix = "[ArmorRefinement]"
        refreshMethod = "RefreshArmorStats"
    elseif equipmentType == "weapon" then
        getEquippedMethod = "GetEquippedWeapon"
        eventName = "WeaponRefinementResult"
        instanceProperty = "weaponInstance"
        logPrefix = "[WeaponRefinement]"
        refreshMethod = "RefreshWeaponStats"
    else
        error("Unknown equipment type: " .. equipmentType)
    end

    --============================================
    -- INITIALIZATION
    --============================================
    function System.Init()
        NetworkManager.GetEvent(eventName)
    end

    --============================================
    -- ATTEMPT REFINEMENT
    --============================================
    function System.Attempt(player)
        -- §ER2: reentrancy guard — must run BEFORE re-reading state.
        if attemptLock[player] then
            return false, 0, "Refinement already in progress"
        end

        local instance = System.Manager[getEquippedMethod](player)
        if not instance then
            return false, 0, "No " .. equipmentType .. " equipped"
        end

        local currentRefinement = instance.refinement

        if currentRefinement >= Config.REFINEMENT_MAX then
            return false, currentRefinement, "Already at max refinement"
        end

        -- Chapter-based refine cap (§13)
        local playerLevel = PlayerDataManager.GetAccountData(player, "Level") or 1
        local chapterMax = ChapterConfig.GetMaxRefine(playerLevel)
        if currentRefinement >= chapterMax then
            return false, currentRefinement, "Refinement capped at +" .. chapterMax .. " for your chapter"
        end

        -- Cost check
        local cost     = Config.GetRefinementCost(currentRefinement)
        local currency = Config.REFINEMENT_CURRENCY

        -- §ER1 fix: SpendMerits / SpendEssence can return false (race lost,
        -- balance changed since CanAfford). Was being ignored — would let
        -- the player roll the refinement for free.
        attemptLock[player] = true
        if cost > 0 then
            local canAfford
            if currency == "Merits" then
                canAfford = CurrencyManager.CanAffordMerits(player, cost)
            else
                canAfford = CurrencyManager.CanAffordEssence(player, cost)
            end
            if not canAfford then
                attemptLock[player] = nil
                return false, currentRefinement, "Not enough " .. currency
            end
            local spendOk
            if currency == "Merits" then
                spendOk = CurrencyManager.SpendMerits(player, cost)
            else
                spendOk = CurrencyManager.SpendEssence(player, cost)
            end
            if not spendOk then
                attemptLock[player] = nil
                return false, currentRefinement, "Not enough " .. currency
            end
        end

        local successChance = Config.REFINEMENT_SUCCESS[currentRefinement] or 0.01
        local roll    = math.random()
        local success = roll <= successChance

        -- Determine position in refinement band for failure logic (§13/§14)
        local floor = Config.GetCeilingBelow(currentRefinement + 1)
        if Config.IsCeiling(currentRefinement) then
            floor = currentRefinement
        end
        local step = currentRefinement - floor + 1

        if success then
            instance.refinement = currentRefinement + 1

            -- Reset temper if we reached a new floor
            if Config.IsCeiling(instance.refinement) then
                instance.temper = 0
            end

            NetworkManager.FireClient(player, eventName, {
                success        = true,
                oldRefinement  = currentRefinement,
                newRefinement  = instance.refinement,
                temper         = instance.temper or 0,
                stats          = System.Manager.GetCalculatedStats(player),
            })

            PlayerDataManager[refreshMethod](player)
            print(logPrefix, player.Name, "SUCCESS: +" .. currentRefinement, "→ +" .. instance.refinement)
            attemptLock[player] = nil
            return true, instance.refinement, "Success!"
        else
            local newRefinement = currentRefinement
            local downgraded    = false

            -- Step 1 or 2 above floor: no loss
            -- Step 3 above floor: lose 1 level (never below floor)
            if step >= 3 then
                newRefinement = math.max(floor, currentRefinement - 1)
                if newRefinement < currentRefinement then
                    downgraded = true
                end
            end

            -- Temper pity system per §14 — per-band thresholds
            local temperGainByStep = Config.TEMPER_GAIN_BY_STEP
            local temperThreshold = Config.TEMPER_THRESHOLDS[floor] or 10
            instance.temper = (instance.temper or 0) + (temperGainByStep[step] or 1)

            local pitied = false
            if instance.temper >= temperThreshold then
                -- §AGX/X9: pity jump respects the chapter cap too (the
                -- cap check above only guarded the normal +1 path, so pity
                -- could land +9/+12/+15 past a +8/+11/+13 cap). When the cap
                -- cuts the jump short, the player lands ON the cap (no more
                -- attempts possible there, so no drop-back) and keeps the
                -- temper bar for the next chapter instead of burning it.
                local capped = floor + 3 > chapterMax
                local nextFloor = math.min(floor + 3, chapterMax)
                if nextFloor <= Config.REFINEMENT_MAX and nextFloor > currentRefinement then
                    instance.refinement = nextFloor
                    if not capped then
                        instance.temper = 0
                    end
                    pitied = true

                    NetworkManager.FireClient(player, eventName, {
                        success       = true,
                        pitied        = true,
                        oldRefinement = currentRefinement,
                        newRefinement = instance.refinement,
                        temper        = instance.temper or 0,
                        stats         = System.Manager.GetCalculatedStats(player),
                    })

                    print(logPrefix, player.Name, "TEMPER PITY: +" .. currentRefinement, "→ +" .. instance.refinement)
                    PlayerDataManager[refreshMethod](player)
                    attemptLock[player] = nil
                    return true, instance.refinement, "Temper pity!"
                end
            end

            if not pitied then
                instance.refinement = newRefinement

                NetworkManager.FireClient(player, eventName, {
                    success       = false,
                    downgraded    = downgraded,
                    oldRefinement = currentRefinement,
                    newRefinement = newRefinement,
                    temper        = instance.temper,
                    stats         = System.Manager.GetCalculatedStats(player),
                })

                if downgraded then
                    print(logPrefix, player.Name, "FAIL+DOWN: +" .. currentRefinement, "→ +" .. newRefinement)
                    PlayerDataManager[refreshMethod](player)
                    attemptLock[player] = nil
                    return false, newRefinement, "Failed and downgraded!"
                else
                    print(logPrefix, player.Name, "FAIL: +" .. currentRefinement, "stays")
                    attemptLock[player] = nil
                    return false, newRefinement, "Failed but held!"
                end
            end
        end

        -- Defensive: if we somehow fall through without returning, release lock.
        attemptLock[player] = nil
    end

    --============================================
    -- REFINEMENT INFO
    --============================================
    function System.GetInfo(player)
        local instance = System.Manager[getEquippedMethod](player)
        if not instance then
            return { refinement = 0, successChance = 100, isMax = false, isCeiling = true }
        end

        local refinement    = instance.refinement
        local successChance = Config.REFINEMENT_SUCCESS[refinement] or 0
        local isCeiling     = Config.IsCeiling(refinement)

        return {
            refinement      = refinement,
            successChance   = math.floor(successChance * 100),
            downgradeChance = 0, -- deterministic step-based loss replaces random downgrade (§13)
            isMax           = refinement >= Config.REFINEMENT_MAX,
            isCeiling       = isCeiling,
            ceilingBelow    = Config.GetCeilingBelow(refinement),
            cost            = Config.GetRefinementCost(refinement),
            currency        = Config.REFINEMENT_CURRENCY,
        }
    end

    return System
end

return CreateRefinementSystem
