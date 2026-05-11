-- ServerScriptService/Modules/DefenseLine/DefenseCombo

local DefenseCombo = {}

-- References (set by parent)
DefenseCombo.Config = nil
DefenseCombo.NetworkManager = nil

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local comboLevel = 0
local lastHitTime = 0
local hitCount = 0

-- Callbacks
local onComboChangedCallbacks = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DefenseCombo.Init()
	DefenseCombo.Reset()
end

-- ═══════════════════════════════════════════════════════════
-- COMBO TRACKING
-- ═══════════════════════════════════════════════════════════

--[[
    Call this when a mob hits the defense line.
    Returns the multiplier to apply to damage.
]]
function DefenseCombo.IncrementCombo()
	local config = DefenseCombo.Config.Combo

	if not config.Enabled then
		return 1
	end

	local now = os.clock()
	local timeSinceHit = now - lastHitTime

	-- FIX: Check if there WAS a previous hit (lastHitTime > 0), not if combo is already building
	if lastHitTime > 0 and timeSinceHit <= config.Window then
		-- Within combo window - increment!
		comboLevel = math.min(comboLevel + 1, config.MaxLevel)
	else
		-- First hit ever OR outside window - start fresh at level 0
		comboLevel = 0
	end

	lastHitTime = now
	hitCount = hitCount + 1

	-- Calculate multiplier for THIS hit
	local multiplier = config.Factor ^ comboLevel

	-- Always notify so UI updates (even at level 0)
	DefenseCombo.OnComboChanged()

	return multiplier
end

--[[
    Call this every frame to handle combo decay.
]]
function DefenseCombo.Update(dt)
	if not DefenseCombo.Config then return end

	local config = DefenseCombo.Config.Combo
	if not config or not config.Enabled then return end
	if comboLevel <= 0 and hitCount == 0 then return end

	local now = os.clock()
	local timeSinceHit = now - lastHitTime

	-- Decay after window expires
	if lastHitTime > 0 and timeSinceHit > config.Window then
		if comboLevel > 0 then
			local decayAmount = config.DecayRate * dt
			local oldLevel = comboLevel
			comboLevel = math.max(0, comboLevel - decayAmount)

			-- Notify if level changed significantly
			if math.floor(oldLevel) ~= math.floor(comboLevel) then
				DefenseCombo.OnComboChanged()
			end

			if comboLevel <= 0 then
				DefenseCombo.OnComboEnded()
			end
		elseif hitCount > 0 and timeSinceHit > config.Window * 2 then
			-- Reset hit count after extended idle
			DefenseCombo.OnComboEnded()
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- EVENTS
-- ═══════════════════════════════════════════════════════════

function DefenseCombo.OnComboChanged()
	if not DefenseCombo.Config then return end

	local config = DefenseCombo.Config.Combo
	if not config then return end

	local multiplier = config.Factor ^ comboLevel

	-- Notify clients
	if DefenseCombo.NetworkManager then
		DefenseCombo.NetworkManager.FireAllClients("DefenseLineCombo", {
			level = comboLevel,
			multiplier = multiplier,
			hitCount = hitCount,
			maxLevel = config.MaxLevel,
			window = config.Window,
		})
	end

	-- Fire callbacks
	for _, callback in ipairs(onComboChangedCallbacks) do
		task.spawn(callback, comboLevel, hitCount, multiplier)
	end

	-- Warning at high combo
	if comboLevel >= 3 then
		print("[DefenseCombo] ⚠️ COMBO x" .. math.floor(comboLevel) .. "! Multiplier:", string.format("%.2f", multiplier) .. "x")
	end
end

function DefenseCombo.OnComboEnded()
	local oldHitCount = hitCount

	if oldHitCount > 1 then
		print("[DefenseCombo] Combo ended - Total hits:", oldHitCount)
	end

	comboLevel = 0
	hitCount = 0
	lastHitTime = 0

	if DefenseCombo.NetworkManager and DefenseCombo.Config then
		local config = DefenseCombo.Config.Combo
		DefenseCombo.NetworkManager.FireAllClients("DefenseLineCombo", {
			level = 0,
			multiplier = 1,
			hitCount = 0,
			maxLevel = config and config.MaxLevel or 10,
			ended = true,
			totalHits = oldHitCount,
		})
	end
end

-- ═══════════════════════════════════════════════════════════
-- CALLBACKS
-- ═══════════════════════════════════════════════════════════

function DefenseCombo.OnChanged(callback)
	table.insert(onComboChangedCallbacks, callback)
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS
-- ═══════════════════════════════════════════════════════════

function DefenseCombo.GetLevel()
	return comboLevel
end

-- ═══════════════════════════════════════════════════════════
-- RESET
-- ═══════════════════════════════════════════════════════════

function DefenseCombo.Reset()
	comboLevel = 0
	lastHitTime = 0
	hitCount = 0
end

return DefenseCombo