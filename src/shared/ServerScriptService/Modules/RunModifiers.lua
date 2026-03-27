-- ServerScriptService/Modules/RunModifiers
--[[
    Tracks shared pressure modifiers and danger bonus across a run.

    Modifiers represent additive deltas to the baseline:
      hpScalar             +N%  mob HP
      damageScalar         +N%  mob damage
      armorFlatBonus       +N   flat armor
      speedScalar          +N%  mob speed
      spawnIntervalScalar  +N%  spawn interval (negative = faster)
      normalMobCountScalar +N%  normal-mob count
      eliteDamageVuln      +N%  extra damage taken by elites
      eliteSpeedScalar     +N%  elite speed
      eliteAttackScalar    +N%  elite attack rate

    DangerBonusPercent:
      Accumulated across Threat/Tactical card picks.
      Horde: cashed out at run end.
      Lane:  waveDangerBonus resets per wave; run danger persists.

    Guardrails (hard caps from design doc):
      totalDangerBonus       : [-25%, +45%]
      spawnIntervalScalar    : [-18%, +∞]  (can't accelerate more than 18%)
      speedScalar (relief)   : max -30%
      extraMiniboss avg      : ≤ 1 per 90s
]]

local RunModifiers = {}

-- ─────────────────────────────────────────────────────────────────────
-- CAPS
-- ─────────────────────────────────────────────────────────────────────
local CAPS = {
    dangerBonusMax      =  0.45,
    dangerBonusMin      = -0.25,
    spawnAccelMax       = -0.18,  -- interval scalar floor (negative = faster)
    speedReductionMax   = -0.30,
    waveDangerMax       =  0.12,
    waveDangerMin       = -0.12,
}

-- ─────────────────────────────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────────────────────────────
local dangerBonusPercent     = 0
local waveDangerBonusPercent = 0   -- per-wave; reset by ResetWaveDanger()

-- Active timed modifiers: { { key, delta, expiresAt } }
local timedModifiers = {}

-- Extra miniboss charges for current spawn window
local extraMinibossCharges = 0

-- ─────────────────────────────────────────────────────────────────────
-- DANGER BONUS
-- ─────────────────────────────────────────────────────────────────────

function RunModifiers.AddDangerBonus(delta)
    dangerBonusPercent = math.clamp(
        dangerBonusPercent + delta,
        CAPS.dangerBonusMin,
        CAPS.dangerBonusMax
    )
end

function RunModifiers.GetDangerBonus()
    return dangerBonusPercent
end

--- Per-wave danger bonus (Lane mode). Resets each wave.
function RunModifiers.AddWaveDangerBonus(delta)
    waveDangerBonusPercent = math.clamp(
        waveDangerBonusPercent + delta,
        CAPS.waveDangerMin,
        CAPS.waveDangerMax
    )
end

function RunModifiers.GetWaveDangerBonus()
    return waveDangerBonusPercent
end

function RunModifiers.ResetWaveDanger()
    waveDangerBonusPercent = 0
end

--- Total combined danger (run + wave).
function RunModifiers.GetTotalDangerBonus()
    return math.clamp(
        dangerBonusPercent + waveDangerBonusPercent,
        CAPS.dangerBonusMin,
        CAPS.dangerBonusMax
    )
end

-- ─────────────────────────────────────────────────────────────────────
-- TIMED MODIFIERS
-- ─────────────────────────────────────────────────────────────────────

--- Apply a delta to a modifier key for `durationSec`.
function RunModifiers.ApplyTimedModifier(key, delta, durationSec)
    table.insert(timedModifiers, {
        key       = key,
        delta     = delta,
        expiresAt = os.clock() + durationSec,
    })
end

--- Prune expired entries and return the net value for `key`.
function RunModifiers.GetModifier(key)
    local now = os.clock()
    local net = 0
    local i   = 1
    while i <= #timedModifiers do
        local m = timedModifiers[i]
        if m.expiresAt <= now then
            table.remove(timedModifiers, i)
        else
            if m.key == key then
                net = net + m.delta
            end
            i = i + 1
        end
    end
    -- Apply caps for specific keys
    if key == "spawnIntervalScalar" then
        net = math.max(CAPS.spawnAccelMax, net)
    elseif key == "speedScalar" then
        net = math.max(CAPS.speedReductionMax, net)
    end
    return net
end

--- Get ALL active modifiers as a flat table { key = netValue }.
function RunModifiers.GetAllModifiers()
    local now = os.clock()
    local result = {}
    local i = 1
    while i <= #timedModifiers do
        local m = timedModifiers[i]
        if m.expiresAt <= now then
            table.remove(timedModifiers, i)
        else
            result[m.key] = (result[m.key] or 0) + m.delta
            i = i + 1
        end
    end
    -- Apply caps
    if result.spawnIntervalScalar then
        result.spawnIntervalScalar = math.max(CAPS.spawnAccelMax, result.spawnIntervalScalar)
    end
    if result.speedScalar then
        result.speedScalar = math.max(CAPS.speedReductionMax, result.speedScalar)
    end
    return result
end

-- ─────────────────────────────────────────────────────────────────────
-- EXTRA MINIBOSS
-- ─────────────────────────────────────────────────────────────────────

function RunModifiers.AddExtraMiniboss(count)
    extraMinibossCharges = extraMinibossCharges + (count or 1)
end

--- Consume one extra-miniboss charge. Returns true if a charge was available.
function RunModifiers.ConsumeMinibossCharge()
    if extraMinibossCharges > 0 then
        extraMinibossCharges = extraMinibossCharges - 1
        return true
    end
    return false
end

function RunModifiers.GetMinibossCharges()
    return extraMinibossCharges
end

-- ─────────────────────────────────────────────────────────────────────
-- RESET
-- ─────────────────────────────────────────────────────────────────────

function RunModifiers.Reset()
    dangerBonusPercent     = 0
    waveDangerBonusPercent = 0
    timedModifiers         = {}
    extraMinibossCharges   = 0
end

return RunModifiers
