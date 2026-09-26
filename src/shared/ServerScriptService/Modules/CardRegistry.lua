-- ServerScriptService/Modules/CardRegistry
--[[
    Defines every card the vote system can present.

    Card types:
      "supply"   — personal reward, no shared pressure change  (Horde)
      "threat"   — shared difficulty modifier + danger bonus    (Horde)
      "tactical" — current/next-wave modifier                   (Lane)

    Threat cards belong to one of three lanes:
      "greed"   — harder mobs, bigger danger bonus
      "control" — trade-off, moderate bonus
      "relief"  — easier mobs, negative danger bonus

    Every card table has:
      id            string   unique key
      name          string   display name
      description   string   1-line player-facing text
      cardType      string   "supply" | "threat" | "tactical"
      lane          string?  "greed" | "control" | "relief" (threat only)
      cooldownKey   string?  if set, blocks re-selection within cooldownSec
      cooldownSec   number?  seconds before the same cooldownKey can win again
      eligible      fn?      (runState) → bool; extra gating (e.g. wave ≥ 4)
      apply         fn       (deps) → nil; server-side effect execution
      --
      -- deps passed to apply():
      --   players       {Player}   active players
      --   runModifiers  RunModifiers module
      --   mobSpawner    MobSpawner / HordeModeSpawner
      --   dataManager   PlayerDataManager
      --   networkMgr    NetworkManager
      --   difficulty    string current tier
      --   elapsed       number seconds since run start
      --   waveNumber    number? (Lane only)
]]

local CardRegistry = {}

-- ─────────────────────────────────────────────────────────────────────
-- LAZY MODULE CACHES
-- ─────────────────────────────────────────────────────────────────────
-- §VM4 fix: cache InventoryManager at module scope. Card apply functions
-- run on the hot vote-resolution path; without this cache, the Respec
-- Fragment card was calling WaitForChild + require on every invocation.
local _InventoryManager = nil
local function getInventoryManager()
    if _InventoryManager then return _InventoryManager end
    local mod = script.Parent:FindFirstChild("InventoryManager")
    if not mod then
        warn("[CardRegistry] InventoryManager not found in script.Parent")
        return nil
    end
    local ok, result = pcall(require, mod)
    if not ok then
        warn("[CardRegistry] Failed to require InventoryManager:", result)
        return nil
    end
    _InventoryManager = result
    return _InventoryManager
end

-- ─────────────────────────────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────────────────────────────

--- Random integer in [lo, hi] stepped by `step` (default 1).
local function randRange(lo, hi, step)
    step = step or 1
    local steps = math.floor((hi - lo) / step)
    return lo + math.random(0, steps) * step
end

--- Random float in [lo, hi], rounded to 2 decimals.
local function randFloat(lo, hi)
    return math.floor((lo + math.random() * (hi - lo)) * 100 + 0.5) / 100
end

-- §AGX/X41: Essence card base amounts per difficulty (Normal / Hard /
-- Nightmare ≈ 1.0 / 1.25 / 2.0, the same ratio as DifficultyConfig's
-- essenceMult, which is NOT applied again on top). Shared by Scavenge (Lane)
-- and EssenceDrop (Horde, which then takes the Horde ×0.6 below).
-- Was 15–25 / 20–30 / 25–35(40): ≈70 Essence/run from Scavenge alone vs
-- ≈3.6 from Lane drops (19×). Now ≈12/run (≈3× drops); see BALANCE_NUMBERS §29.
local ESSENCE_CARD_RANGE = { Normal = {8,12}, Hard = {10,15}, Nightmare = {16,24} }

-- §AGX/X41: Horde reward multiplier for card Essence, read from
-- GameModeConfig so it can't drift from the ×0.6 DropManager applies to
-- every Horde Essence drop. Supply cards only exist in Horde, so the card
-- type identifies the mode (VoteManager deps carry no modeId).
local _hordeEssenceMult = nil
local function getHordeEssenceMult()
    if _hordeEssenceMult then return _hordeEssenceMult end
    local mult = 1
    local mod = script.Parent:FindFirstChild("GameModeConfig")
    if mod then
        local ok, gmc = pcall(require, mod)
        local mode = ok and gmc and gmc.GetMode and gmc.GetMode("HordeMode")
        local rm = mode and mode.rewardMultipliers
        if rm and type(rm.essenceMult) == "number" then
            mult = rm.essenceMult
        end
    end
    _hordeEssenceMult = mult
    return mult
end

-- ─────────────────────────────────────────────────────────────────────
-- CARD DEFINITIONS
-- ─────────────────────────────────────────────────────────────────────

local CARDS = {}

-- ═══════════════════════════════════════════════════════════
-- HORDE SUPPLY CARDS  (personal rewards, no shared pressure)
-- ═══════════════════════════════════════════════════════════

CARDS.MeritCache = {
    id          = "MeritCache",
    name        = "Merit Cache",
    cardType    = "supply",
    description = "Each player receives a cache of merits.",
    apply = function(deps)
        -- Difficulty-scaled merit payout
        local base = { Normal = {60,90}, Hard = {70,105}, Nightmare = {80,120} }
        local range = base[deps.difficulty] or base.Normal
        for _, player in ipairs(deps.players) do
            local amount = randRange(range[1], range[2], 5)
            if deps.currencyManager then
                deps.currencyManager.AddMerits(player, amount)
            end
            deps.networkMgr.FireClient(player, "VoteRewardGranted", {
                cardId = "MeritCache", text = "+" .. amount .. " Merits",
            })
        end
    end,
}

CARDS.ClassBattery = {
    id          = "ClassBattery",
    name        = "Class Battery",
    cardType    = "supply",
    description = "Restore 20–35% of your class resource.",
    apply = function(deps)
        for _, player in ipairs(deps.players) do
            local pct = randFloat(0.20, 0.35)
            -- ResourceManager restores by percentage if available
            if deps.resourceManager and deps.resourceManager.RestorePercent then
                deps.resourceManager.RestorePercent(player, pct)
            end
            deps.networkMgr.FireClient(player, "VoteRewardGranted", {
                cardId = "ClassBattery",
                text = "+" .. math.floor(pct * 100) .. "% class resource",
            })
        end
    end,
}

CARDS.PowerSurge = {
    id          = "PowerSurge",
    name        = "Power Surge",
    cardType    = "supply",
    description = "Short combat buff for all players.",
    apply = function(deps)
        -- Pick a random buff template
        local templates = {
            { stat = "DamagePercent", lo = 8, hi = 12, dur = {20, 25}, label = "damage" },
            { stat = "CritChance",   lo = 6, hi = 10, dur = {18, 22}, label = "crit chance" },
            { stat = "AttackSpeed",  lo = 10, hi = 14, dur = {15, 18}, label = "attack speed" },
        }
        local t = templates[math.random(#templates)]
        local value = randRange(t.lo, t.hi)
        local duration = randRange(t.dur[1], t.dur[2])
        for _, player in ipairs(deps.players) do
            -- Apply via BonusManager if available (timed buff)
            if deps.bonusManager and deps.bonusManager.AddTimedBonus then
                deps.bonusManager.AddTimedBonus(player, "CardBuff_" .. t.stat, t.stat, value, duration)
            end
            deps.networkMgr.FireClient(player, "VoteRewardGranted", {
                cardId = "PowerSurge",
                text = "+" .. value .. "% " .. t.label .. " for " .. duration .. "s",
            })
        end
    end,
}

CARDS.EmergencyPulse = {
    id          = "EmergencyPulse",
    name        = "Emergency Pulse",
    cardType    = "supply",
    description = "Instant heal for 12–18% max HP.",
    apply = function(deps)
        local pct = randFloat(0.12, 0.18)
        for _, player in ipairs(deps.players) do
            local char = player.Character
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                local heal = math.floor(hum.MaxHealth * pct)
                hum.Health = math.min(hum.Health + heal, hum.MaxHealth)
            end
            deps.networkMgr.FireClient(player, "VoteRewardGranted", {
                cardId = "EmergencyPulse",
                text = "Healed " .. math.floor(pct * 100) .. "% HP",
            })
        end
    end,
}

CARDS.EssenceDrop = {
    id          = "EssenceDrop",
    name        = "Essence Drop",
    cardType    = "supply",
    description = "Each player receives a small essence cache.",
    -- §AGX/X41: personal cooldown so it can win at most every other supply
    -- vote (supply votes are ~95–120 s apart on the wall clock), i.e. ≤4 of
    -- the 7 per run. Was offered 7 × 3/8 ≈ 2.6 times/run with no limit.
    cooldownKey = "EssenceDrop",
    cooldownSec = 150,
    apply = function(deps)
        -- §AGX/X41: shared base table × Horde essenceMult (0.6), like every
        -- other Horde Essence reward. Normal 8–12 → 5–7.
        local range = ESSENCE_CARD_RANGE[deps.difficulty] or ESSENCE_CARD_RANGE.Normal
        local modeMult = getHordeEssenceMult()
        for _, player in ipairs(deps.players) do
            local amount = math.max(1, math.floor(randRange(range[1], range[2]) * modeMult + 0.5))
            if deps.currencyManager then
                deps.currencyManager.AddEssence(player, amount)
            end
            deps.networkMgr.FireClient(player, "VoteRewardGranted", {
                cardId = "EssenceDrop", text = "+" .. amount .. " Essence",
            })
        end
    end,
}

-- ═══════════════════════════════════════════════════════════
-- HORDE THREAT CARDS  (shared pressure + danger bonus)
-- ═══════════════════════════════════════════════════════════

-- GREED --

CARDS.BloodMoon = {
    id          = "BloodMoon",
    name        = "Blood Moon",
    cardType    = "threat",
    lane        = "greed",
    description = "Spawn 4–6% faster, +4–6% danger bonus for 60s.",
    apply = function(deps)
        local spawnAccel = randFloat(0.04, 0.06)
        local dangerBonus = randFloat(0.04, 0.06)
        deps.runModifiers.ApplyTimedModifier("spawnIntervalScalar", -spawnAccel, 60)
        deps.runModifiers.AddDangerBonus(dangerBonus)
    end,
}

CARDS.HuntingHorn = {
    id          = "HuntingHorn",
    name        = "Hunting Horn",
    cardType    = "threat",
    lane        = "greed",
    cooldownKey = "HuntingHorn",
    cooldownSec = 90,
    description = "Summon 1 elite, +6–9% danger bonus.",
    apply = function(deps)
        local dangerBonus = randFloat(0.06, 0.09)
        deps.runModifiers.AddExtraMiniboss(1)
        deps.runModifiers.AddDangerBonus(dangerBonus)
    end,
}

CARDS.ThickSkins = {
    id          = "ThickSkins",
    name        = "Thick Skins",
    cardType    = "threat",
    lane        = "greed",
    description = "Mob HP +8–12%, armor +2–4, +5–7% danger bonus for 60s.",
    apply = function(deps)
        local hpBoost = randFloat(0.08, 0.12)
        local armorFlat = randRange(2, 4)
        local dangerBonus = randFloat(0.05, 0.07)
        deps.runModifiers.ApplyTimedModifier("hpScalar", hpBoost, 60)
        deps.runModifiers.ApplyTimedModifier("armorFlatBonus", armorFlat, 60)
        deps.runModifiers.AddDangerBonus(dangerBonus)
    end,
}

-- CONTROL --

CARDS.SplitPack = {
    id          = "SplitPack",
    name        = "Split Pack",
    cardType    = "threat",
    lane        = "control",
    description = "More normal mobs, fewer elites, +2–4% danger for 60s.",
    apply = function(deps)
        local extraCount = randFloat(0.08, 0.12)
        local dangerBonus = randFloat(0.02, 0.04)
        deps.runModifiers.ApplyTimedModifier("normalMobCountScalar", extraCount, 60)
        deps.runModifiers.AddDangerBonus(dangerBonus)
    end,
}

CARDS.MarkedTargets = {
    id          = "MarkedTargets",
    name        = "Marked Targets",
    cardType    = "threat",
    lane        = "control",
    description = "Elites take +8–12% damage but move faster, +2–4% danger for 60s.",
    apply = function(deps)
        local dangerBonus = randFloat(0.02, 0.04)
        -- Mark effect: tracked as modifier, applied by MobAI at damage time
        deps.runModifiers.ApplyTimedModifier("eliteDamageVuln", randFloat(0.08, 0.12), 60)
        deps.runModifiers.ApplyTimedModifier("eliteSpeedScalar", randFloat(0.04, 0.06), 60)
        deps.runModifiers.AddDangerBonus(dangerBonus)
    end,
}

-- RELIEF --

CARDS.HeavyAir = {
    id          = "HeavyAir",
    name        = "Heavy Air",
    cardType    = "threat",
    lane        = "relief",
    description = "Mob speed −6–9%, danger bonus −3–5% for 60s.",
    apply = function(deps)
        local speedReduction = -randFloat(0.06, 0.09)
        local dangerPenalty = -randFloat(0.03, 0.05)
        deps.runModifiers.ApplyTimedModifier("speedScalar", speedReduction, 60)
        deps.runModifiers.AddDangerBonus(dangerPenalty)
    end,
}

CARDS.ThinRanks = {
    id          = "ThinRanks",
    name        = "Thin Ranks",
    cardType    = "threat",
    lane        = "relief",
    description = "Spawns 6–9% slower, danger bonus −4–6% for 60s.",
    apply = function(deps)
        local spawnSlow = randFloat(0.06, 0.09)
        local dangerPenalty = -randFloat(0.04, 0.06)
        deps.runModifiers.ApplyTimedModifier("spawnIntervalScalar", spawnSlow, 60)
        deps.runModifiers.AddDangerBonus(dangerPenalty)
    end,
}

CARDS.FrozenBlood = {
    id          = "FrozenBlood",
    name        = "Frozen Blood",
    cardType    = "threat",
    lane        = "relief",
    description = "Elite attack −8–12%, speed −4–6%, danger −3–4% for 60s.",
    apply = function(deps)
        deps.runModifiers.ApplyTimedModifier("eliteAttackScalar", -randFloat(0.08, 0.12), 60)
        deps.runModifiers.ApplyTimedModifier("eliteSpeedScalar", -randFloat(0.04, 0.06), 60)
        deps.runModifiers.AddDangerBonus(-randFloat(0.03, 0.04))
    end,
}

-- ═══════════════════════════════════════════════════════════
-- LANE TACTICAL CARDS (current/next-wave modifiers)
-- ═══════════════════════════════════════════════════════════

CARDS.SupplyCart = {
    id          = "SupplyCart",
    name        = "Supply Cart",
    cardType    = "tactical",
    description = "Each player receives 40–70 merits.",
    apply = function(deps)
        for _, player in ipairs(deps.players) do
            local amount = randRange(40, 70, 5)
            if deps.currencyManager then
                deps.currencyManager.AddMerits(player, amount)
            end
            deps.networkMgr.FireClient(player, "VoteRewardGranted", {
                cardId = "SupplyCart", text = "+" .. amount .. " Merits",
            })
        end
    end,
}

CARDS.Fortify = {
    id          = "Fortify",
    name        = "Fortify",
    cardType    = "tactical",
    description = "Defense line gains 8–12% shield, danger −4–6%.",
    apply = function(deps)
        local pct = randFloat(0.08, 0.12)
        if deps.defenseLine and deps.defenseLine.AddShieldPercent then
            deps.defenseLine.AddShieldPercent(pct)
        end
        deps.runModifiers.AddWaveDangerBonus(-randFloat(0.04, 0.06))
    end,
}

CARDS.Sharpsight = {
    id          = "Sharpsight",
    name        = "Sharpsight",
    cardType    = "tactical",
    description = "Team gains +6–10% crit chance this wave.",
    apply = function(deps)
        local value = randRange(6, 10)
        for _, player in ipairs(deps.players) do
            if deps.bonusManager and deps.bonusManager.AddTimedBonus then
                -- Duration of 180s covers any single wave
                deps.bonusManager.AddTimedBonus(player, "CardBuff_Sharpsight", "CritChance", value, 180)
            end
        end
        deps.runModifiers.AddWaveDangerBonus(randFloat(0.00, 0.02))
    end,
}

CARDS.EliteBounty = {
    id          = "EliteBounty",
    name        = "Elite Bounty",
    cardType    = "tactical",
    description = "Add 1 miniboss this wave. Danger +8–11%.",
    eligible = function(runState)
        local eligible = { [4]=true, [7]=true, [10]=true, [12]=true }
        return eligible[runState.waveNumber] == true
    end,
    apply = function(deps)
        deps.runModifiers.AddExtraMiniboss(1)
        deps.runModifiers.AddWaveDangerBonus(randFloat(0.08, 0.11))
    end,
}

CARDS.SlowMarch = {
    id          = "SlowMarch",
    name        = "Slow March",
    cardType    = "tactical",
    description = "Enemy speed −6–10% this wave. Danger −4–6%.",
    apply = function(deps)
        deps.runModifiers.ApplyTimedModifier("speedScalar", -randFloat(0.06, 0.10), 180)
        deps.runModifiers.AddWaveDangerBonus(-randFloat(0.04, 0.06))
    end,
}

CARDS.DensePack = {
    id          = "DensePack",
    name        = "Dense Pack",
    cardType    = "tactical",
    description = "Normal mob count +6–10% this wave. Danger +4–7%.",
    apply = function(deps)
        deps.runModifiers.ApplyTimedModifier("normalMobCountScalar", randFloat(0.06, 0.10), 180)
        deps.runModifiers.AddWaveDangerBonus(randFloat(0.04, 0.07))
    end,
}

CARDS.RepairWindow = {
    id          = "RepairWindow",
    name        = "Repair Window",
    cardType    = "tactical",
    description = "Restore 6–10% defense-line HP. Danger −5–7%.",
    apply = function(deps)
        local pct = randFloat(0.06, 0.10)
        if deps.defenseLine and deps.defenseLine.HealPercent then
            deps.defenseLine.HealPercent(pct)
        end
        deps.runModifiers.AddWaveDangerBonus(-randFloat(0.05, 0.07))
    end,
}

CARDS.FrenzyBanner = {
    id          = "FrenzyBanner",
    name        = "Frenzy Banner",
    cardType    = "tactical",
    description = "Team gains +8–12% attack speed this wave.",
    apply = function(deps)
        local value = randRange(8, 12)
        for _, player in ipairs(deps.players) do
            if deps.bonusManager and deps.bonusManager.AddTimedBonus then
                deps.bonusManager.AddTimedBonus(player, "CardBuff_Frenzy", "AttackSpeed", value, 180)
            end
        end
        deps.runModifiers.AddWaveDangerBonus(randFloat(0.00, 0.02))
    end,
}

-- ═══════════════════════════════════════════════════════════
-- ADDITIONAL SUPPLY CARDS
-- ═══════════════════════════════════════════════════════════

CARDS.SecondWind = {
    id          = "SecondWind",
    name        = "Second Wind",
    cardType    = "supply",
    description = "All players gain +6–10% max HP for 45s.",
    apply = function(deps)
        local value = randRange(6, 10)
        for _, player in ipairs(deps.players) do
            if deps.bonusManager and deps.bonusManager.AddTimedBonus then
                deps.bonusManager.AddTimedBonus(player, "CardBuff_SecondWind", "HealthPercent", value, 45)
            end
            deps.networkMgr.FireClient(player, "VoteRewardGranted", {
                cardId = "SecondWind",
                text = "+" .. value .. "% max HP for 45s",
            })
        end
    end,
}

CARDS.WeaponOil = {
    id          = "WeaponOil",
    name        = "Weapon Oil",
    cardType    = "supply",
    description = "All players gain +5–8% flat damage for 30s.",
    apply = function(deps)
        local value = randRange(5, 8)
        for _, player in ipairs(deps.players) do
            if deps.bonusManager and deps.bonusManager.AddTimedBonus then
                deps.bonusManager.AddTimedBonus(player, "CardBuff_WeaponOil", "DamagePercent", value, 30)
            end
            deps.networkMgr.FireClient(player, "VoteRewardGranted", {
                cardId = "WeaponOil",
                text = "+" .. value .. "% damage for 30s",
            })
        end
    end,
}

CARDS.BountyBoard = {
    id          = "BountyBoard",
    name        = "Bounty Board",
    cardType    = "supply",
    cooldownKey = "BountyBoard",
    cooldownSec = 120,
    description = "Double merits from kills for 30s.",
    apply = function(deps)
        -- Track via RunModifiers as a timed scalar; KillRewardManager reads it
        deps.runModifiers.ApplyTimedModifier("meritScalar", 1.0, 30)
        for _, player in ipairs(deps.players) do
            deps.networkMgr.FireClient(player, "VoteRewardGranted", {
                cardId = "BountyBoard",
                text = "2× merits for 30s!",
            })
        end
    end,
}

-- ═══════════════════════════════════════════════════════════
-- RESPEC FRAGMENT  (personal-only, gated entirely by VoteManager)
-- ═══════════════════════════════════════════════════════════
-- This card is NEVER surfaced by the normal supply pool — VoteManager
-- does a 10 % per-player-per-supply-vote roll (capped at one roll per
-- player per run) and swaps it in at that point.  CardRegistry's pool
-- pickers (pickCards / pickCardsPersonal) explicitly filter it out.
-- Four fragments auto-combine into a respec_scroll inside InventoryManager.

CARDS.RespecFragment = {
    id          = "RespecFragment",
    name        = "Respec Fragment",
    cardType    = "supply",
    description = "A shard of reflection. Collect 4 to reshape your talents.",
    -- No cooldownKey, no eligible() — gating lives in VoteManager.
    apply = function(deps)
        -- §VM4: use the module-scoped lazy cache instead of WaitForChild
        -- on every invocation. Same lookup, only resolved once per server.
        local InventoryManager = getInventoryManager()
        if not InventoryManager then
            warn("[CardRegistry] RespecFragment.apply: InventoryManager unavailable")
            return
        end
        for _, player in ipairs(deps.players) do
            InventoryManager.AddItem(player, "respec_fragment", 1)
            if deps.networkMgr then
                deps.networkMgr.FireClient(player, "VoteRewardGranted", {
                    cardId = "RespecFragment",
                    text   = "+1 Respec Fragment",
                })
            end
        end
    end,
}

-- ═══════════════════════════════════════════════════════════
-- ADDITIONAL THREAT CARDS
-- ═══════════════════════════════════════════════════════════

CARDS.CorruptedGround = {
    id          = "CorruptedGround",
    name        = "Corrupted Ground",
    cardType    = "threat",
    lane        = "greed",
    description = "Mob damage +10–15%, danger +6–8% for 60s.",
    apply = function(deps)
        local dmgBoost = randFloat(0.10, 0.15)
        local dangerBonus = randFloat(0.06, 0.08)
        deps.runModifiers.ApplyTimedModifier("damageScalar", dmgBoost, 60)
        deps.runModifiers.AddDangerBonus(dangerBonus)
    end,
}

CARDS.Reinforcements = {
    id          = "Reinforcements",
    name        = "Reinforcements",
    cardType    = "threat",
    lane        = "control",
    description = "Spawn rate +5–8%, mob speed −3–5%, danger +2–4% for 60s.",
    apply = function(deps)
        deps.runModifiers.ApplyTimedModifier("spawnIntervalScalar", -randFloat(0.05, 0.08), 60)
        deps.runModifiers.ApplyTimedModifier("speedScalar", -randFloat(0.03, 0.05), 60)
        deps.runModifiers.AddDangerBonus(randFloat(0.02, 0.04))
    end,
}

CARDS.WeakSpot = {
    id          = "WeakSpot",
    name        = "Weak Spot",
    cardType    = "threat",
    lane        = "relief",
    description = "Mob HP −8–12%, but damage +4–6%, danger −2–4% for 60s.",
    apply = function(deps)
        deps.runModifiers.ApplyTimedModifier("hpScalar", -randFloat(0.08, 0.12), 60)
        deps.runModifiers.ApplyTimedModifier("damageScalar", randFloat(0.04, 0.06), 60)
        deps.runModifiers.AddDangerBonus(-randFloat(0.02, 0.04))
    end,
}

-- ═══════════════════════════════════════════════════════════
-- ADDITIONAL TACTICAL CARDS
-- ═══════════════════════════════════════════════════════════

CARDS.IronWall = {
    id          = "IronWall",
    name        = "Iron Wall",
    cardType    = "tactical",
    description = "Team gains +4–7% armor this wave. Danger −2–4%.",
    apply = function(deps)
        local value = randRange(4, 7)
        for _, player in ipairs(deps.players) do
            if deps.bonusManager and deps.bonusManager.AddTimedBonus then
                deps.bonusManager.AddTimedBonus(player, "CardBuff_IronWall", "Armor", value, 180)
            end
        end
        deps.runModifiers.AddWaveDangerBonus(-randFloat(0.02, 0.04))
    end,
}

CARDS.RallyingCry = {
    id          = "RallyingCry",
    name        = "Rallying Cry",
    cardType    = "tactical",
    description = "Team gains +5–8% damage and +3–5% crit this wave.",
    apply = function(deps)
        local dmg = randRange(5, 8)
        local crit = randRange(3, 5)
        for _, player in ipairs(deps.players) do
            if deps.bonusManager and deps.bonusManager.AddTimedBonus then
                deps.bonusManager.AddTimedBonus(player, "CardBuff_RallyDmg", "DamagePercent", dmg, 180)
                deps.bonusManager.AddTimedBonus(player, "CardBuff_RallyCrit", "CritChance", crit, 180)
            end
        end
        deps.runModifiers.AddWaveDangerBonus(randFloat(0.02, 0.04))
    end,
}

CARDS.Scavenge = {
    id          = "Scavenge",
    name        = "Scavenge",
    cardType    = "tactical",
    -- §AGX/X41: description matches the code (was "15–30", code 15–35).
    description = "Each player receives 8–12 essence (more on Hard/Nightmare). Danger +1–3%.",
    -- §AGX/X41: only offered every third wave (3/6/9/12), so ≈1.2 offers per
    -- run instead of ≈3.5. EliteBounty uses the same eligible() pattern.
    eligible = function(runState)
        local w = runState.waveNumber
        return type(w) == "number" and w % 3 == 0
    end,
    apply = function(deps)
        local range = ESSENCE_CARD_RANGE[deps.difficulty] or ESSENCE_CARD_RANGE.Normal
        for _, player in ipairs(deps.players) do
            local amount = randRange(range[1], range[2])
            if deps.currencyManager then
                deps.currencyManager.AddEssence(player, amount)
            end
            deps.networkMgr.FireClient(player, "VoteRewardGranted", {
                cardId = "Scavenge", text = "+" .. amount .. " Essence",
            })
        end
        deps.runModifiers.AddWaveDangerBonus(randFloat(0.01, 0.03))
    end,
}

-- ─────────────────────────────────────────────────────────────────────
-- POOL ACCESSORS
-- ─────────────────────────────────────────────────────────────────────

--- Get a card definition by id.
function CardRegistry.GetCard(cardId)
    return CARDS[cardId]
end

--- Return all card ids of a given type.
function CardRegistry.GetPool(cardType)
    local pool = {}
    for id, card in pairs(CARDS) do
        if card.cardType == cardType then
            table.insert(pool, id)
        end
    end
    table.sort(pool)
    return pool
end

--- Return all card ids in a threat lane.
function CardRegistry.GetThreatLane(lane)
    local pool = {}
    for id, card in pairs(CARDS) do
        if card.cardType == "threat" and card.lane == lane then
            table.insert(pool, id)
        end
    end
    table.sort(pool)
    return pool
end

return CardRegistry
