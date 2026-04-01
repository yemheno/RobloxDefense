-- ReplicatedStorage/Shared/GearRating.lua
--[[
    Power Rating System — single composite number summarizing player strength.

    CombatPower  = 150
                 + 900  × L   (account level)
                 + 2400 × W   (weapon composite)
                 + 1700 × A   (armor composite)
                 + 700  × X   (accessory score)
                 + 800  × T   (weighted talent score)
                 + 550  × M   (mastery progress)

    Where each sub-score is normalized to [0, 1]:
      L = (Level − 1) / 199
      W = 0.20×(WepLevel−1)/199 + 0.45×(WepTier−1)/11 + 0.35×(WepRef/15)
      A = 0.20×(ArmorLevel−1)/199 + 0.40×(ArmorTier−1)/11 + 0.40×(ArmorRef/15)
      X = AccessoryScore / 300
      T = WeightedTalents / 420  (small=1, notable=2, keystone=4; max = 300 player-chosen nodes)
      M = min(MasteryXP, 120000) / 120000

    DisplayPower = CombatPower × (1 + 0.10 × P)
    P = 0.70 × (AchievementTiers / 70) + 0.30 × (min(HighestWave, 100) / 100)

    Public API:
      GearRating.GetDisplayPower(data) → number  (DisplayPower, integer)  ← single source of truth
      GearRating.GetBreakdown(data)    → table   (all component scores + displayPower)
]]

local GearRating = {}

-- ═══════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════

local LEVEL_CAP      = 200
local TIER_MAX       = 12
local REFINEMENT_MAX = 15
local ACCESSORY_MAX  = 300   -- 3 legendary slots × 100 each
local TALENT_MAX_W   = 420   -- 210 small×1 + 75 notable×2 + 15 keystone×4  (300 player-chosen nodes across 15 sectors)
local MASTERY_MAX    = 120000

local TALENT_WEIGHTS = { small = 1, notable = 2, keystone = 4 }

-- Component weights
local W_BASE    = 150
local W_LEVEL   = 900
local W_WEAPON  = 2400
local W_ARMOR   = 1700
local W_ACC     = 700
local W_TALENT  = 800
local W_MASTERY = 550

-- Prestige multiplier cap
local PRESTIGE_MULT = 0.10
local ACH_TIER_MAX  = 70
local HIGHEST_WAVE_CAP = 100

-- ═══════════════════════════════════════════════════════════
-- LAZY REQUIRES
-- ═══════════════════════════════════════════════════════════

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccessoryConfig = nil
local TalentTreeConfig = nil

local function getAccessoryConfig()
    if AccessoryConfig then return AccessoryConfig end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AccessoryConfig"))
    end)
    if ok then AccessoryConfig = mod end
    return AccessoryConfig
end

local function getTalentTreeConfig()
    if TalentTreeConfig then return TalentTreeConfig end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TalentTreeConfig"))
    end)
    if ok then TalentTreeConfig = mod end
    return TalentTreeConfig
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

local function clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

local function getWeaponData(data)
    local activeClass = data.ActiveClass or "Aegis"
    local classData   = data.Classes and data.Classes[activeClass]
    if not classData then return 1, 1, 0 end

    local weapon = classData.EquippedWeapon
    if not weapon then return 1, 1, 0 end
    return data.Account and data.Account.Level or 1,
           weapon.tier or 1,
           weapon.refinement or 0
end

local function getArmorData(data)
    local activeClass = data.ActiveClass or "Aegis"
    local classData   = data.Classes and data.Classes[activeClass]
    if not classData then return 1, 1, 0 end

    local armorInst = classData.EquippedArmor
    if not armorInst then return 1, 1, 0 end
    return data.Account and data.Account.Level or 1,
           armorInst.tier or 1,
           armorInst.refinement or 0
end

local function getWeightedTalents(data)
    local talents = data.Account and data.Account.AllocatedTalents
    if not talents then return 0 end

    local ttc = getTalentTreeConfig()
    if not ttc or not ttc.Nodes then
        -- Fallback: count allocated = 1 each
        local count = 0
        for _, v in pairs(talents) do
            if v then count = count + 1 end
        end
        return count
    end

    -- Build id → type lookup
    local nodeTypes = {}
    for _, node in ipairs(ttc.Nodes) do
        nodeTypes[node.id] = node.type
    end

    local total = 0
    for nodeId, allocated in pairs(talents) do
        if allocated then
            local nodeType = nodeTypes[nodeId]
            total = total + (TALENT_WEIGHTS[nodeType] or 1)
        end
    end
    return total
end

local function getAccessoryScore(data)
    local cfg = getAccessoryConfig()
    if not cfg then return 0 end
    local account = data.Account
    if not account then return 0 end

    local total = 0
    if account.TrinketId then
        total = total + (cfg.GetAccessoryScore(account.TrinketId) or 0)
    end
    if account.Ring1Id then
        total = total + (cfg.GetAccessoryScore(account.Ring1Id) or 0)
    end
    if account.Ring2Id then
        total = total + (cfg.GetAccessoryScore(account.Ring2Id) or 0)
    end
    return total
end

local function getMasteryXP(data)
    local activeClass = data.ActiveClass or "Aegis"
    local classData   = data.Classes and data.Classes[activeClass]
    if not classData then return 0 end
    return classData.MasteryXP or 0
end

local function getAchievementTierSum(data)
    local ach = data.Account and data.Account.Achievements
    if not ach or not ach.unlocked then return 0 end
    local total = 0
    for _, tier in pairs(ach.unlocked) do
        total = total + (tier or 0)
    end
    return total
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════

--- Returns a breakdown of all component scores.
--- @param data  Player data table
--- @return table
function GearRating.GetBreakdown(data)
    if not data or not data.Account then
        return {
            level = 0, weapon = 0, armor = 0, accessories = 0,
            talents = 0, mastery = 0, prestige = 0,
            combatPower = 0, displayPower = 0, total = 0,
        }
    end

    local level = data.Account.Level or 1
    local L = clamp01((level - 1) / (LEVEL_CAP - 1))

    local _, wTier, wRef = getWeaponData(data)
    local W = 0.20 * clamp01((level - 1) / (LEVEL_CAP - 1))
            + 0.45 * clamp01((wTier - 1) / (TIER_MAX - 1))
            + 0.35 * clamp01(wRef / REFINEMENT_MAX)

    local _, aTier, aRef = getArmorData(data)
    local A = 0.20 * clamp01((level - 1) / (LEVEL_CAP - 1))
            + 0.40 * clamp01((aTier - 1) / (TIER_MAX - 1))
            + 0.40 * clamp01(aRef / REFINEMENT_MAX)

    local accScore = getAccessoryScore(data)
    local X = clamp01(accScore / ACCESSORY_MAX)

    local weightedTalents = getWeightedTalents(data)
    local T = clamp01(weightedTalents / TALENT_MAX_W)

    local masteryXP = getMasteryXP(data)
    local M = clamp01(math.min(masteryXP, MASTERY_MAX) / MASTERY_MAX)

    local levelScore   = math.floor(W_LEVEL   * L + 0.5)
    local weaponScore  = math.floor(W_WEAPON  * W + 0.5)
    local armorScore   = math.floor(W_ARMOR   * A + 0.5)
    local accScoreComp = math.floor(W_ACC     * X + 0.5)
    local talentScore  = math.floor(W_TALENT  * T + 0.5)
    local masteryScore = math.floor(W_MASTERY * M + 0.5)

    local combatPower = W_BASE + levelScore + weaponScore + armorScore + accScoreComp + talentScore + masteryScore

    -- Prestige modifier
    local achTierSum   = getAchievementTierSum(data)
    local highestWave  = data.Account.HighestWaveReached or 0
    local P = 0.70 * clamp01(achTierSum / ACH_TIER_MAX)
            + 0.30 * clamp01(math.min(highestWave, HIGHEST_WAVE_CAP) / HIGHEST_WAVE_CAP)
    local displayPower = math.floor(combatPower * (1 + PRESTIGE_MULT * P) + 0.5)

    return {
        level        = levelScore,
        weapon       = weaponScore,
        armor        = armorScore,
        accessories  = accScoreComp,
        talents      = talentScore,
        mastery      = masteryScore,
        prestige     = math.floor(combatPower * PRESTIGE_MULT * P + 0.5),
        combatPower  = combatPower,
        displayPower = displayPower,
        total        = displayPower,  -- backwards-compatible with old GearRating.GetBreakdown().total
    }
end

--- Single source of truth for the player's power number (Combat × Prestige).
--- @param data  Player data table (from PlayerDataManager.GetData)
--- @return number  DisplayPower (integer)
function GearRating.GetDisplayPower(data)
    local breakdown = GearRating.GetBreakdown(data)
    return breakdown.displayPower
end

-- Backward-compat alias — redirects old Calculate() calls to the unified formula.
GearRating.Calculate = GearRating.GetDisplayPower

return GearRating
