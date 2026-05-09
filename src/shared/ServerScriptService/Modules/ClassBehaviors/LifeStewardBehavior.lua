-- ServerScriptService/Modules/ClassBehaviors/LifeStewardBehavior
--[[
    Life Steward resource: Life Energy
    ══════════════════════════════════
    • Natural regen similar to Arcanist's Aether.
    • Regen INCREASES when nearby allies are below 40 % HP.
      Each wounded ally in range adds +ProximityBonus/s (stacks).
    • Killing enemies refunds a small amount.
    • Taking damage causes a small loss.
]]

local Players = game:GetService("Players")

local LifeStewardBehavior = {}

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

LifeStewardBehavior.CONFIG = {
	-- Resource Identity
	ResourceName = "Life Energy",
	MaxResource = 100,
	StartingResource = 30,

	-- Passive regen
	BaseRegen = 4,                  -- Out-of-combat; in-combat = 4 × 0.5 = 2.0/s (§29.1)

	-- Combat regen modifier
	InCombatRegenMultiplier = 0.5,  -- §29.1: 2.0/s in combat
	CombatTimeout = 3,              -- Seconds since last action

	-- Proximity regen boost (§29.1)
	ProximityRange  = 35,           -- §29.1: 35 studs
	ProximityThreshold = 0.60,      -- §29.1: 60% HP threshold
	ProximityBonusPerAlly = 2,      -- §29.1: +2/s per wounded ally
	MaxProximityAllies = 3,         -- §29.1: max contributing allies = 3

	-- On hit dealt
	GainPerHitDealt = 0,
	CostPerHit = 0,

	-- On kill
	GainPerKill = 2,                -- §29.1: +2 on kill
	MinibossKillBonus = 6,          -- §29.1: +6 on miniboss kill
	BossKillBonus = 15,             -- §29.1: +15 on boss kill

	-- On hit received
	LossPerHitReceived = 0,         -- §29.1: no loss on hit received for LifeSteward
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function LifeStewardBehavior.Init()
	print("[LifeStewardBehavior] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- RESOURCE RATE
-- ═══════════════════════════════════════════════════════════

function LifeStewardBehavior.GetResourceRate(player, resourceData)
	local config = LifeStewardBehavior.CONFIG
	local regen = config.BaseRegen

	-- Slower regen in combat
	local inCombat = math.min(resourceData.timeSinceHitDealt, resourceData.timeSinceHitReceived) < config.CombatTimeout
	if inCombat then
		regen = regen * config.InCombatRegenMultiplier
	end

	-- Proximity boost: regen faster when nearby allies are low HP
	local bonus = LifeStewardBehavior.CalculateProximityBonus(player)
	regen = regen + bonus

	return regen
end

-- ═══════════════════════════════════════════════════════════
-- PROXIMITY BONUS CALCULATION
--
-- Returns additional regen/s based on how many nearby allies
-- are at or below the HP threshold.
-- ═══════════════════════════════════════════════════════════

function LifeStewardBehavior.CalculateProximityBonus(player)
	local config = LifeStewardBehavior.CONFIG
	local char = player.Character
	if not char then return 0 end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return 0 end

	local origin = root.Position
	local woundedCount = 0
	local maxAllies = config.MaxProximityAllies or 3

	for _, p in ipairs(Players:GetPlayers()) do
		if p == player then continue end
		if woundedCount >= maxAllies then break end
		local pChar = p.Character
		if not pChar then continue end
		local hum = pChar:FindFirstChild("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local pRoot = pChar:FindFirstChild("HumanoidRootPart")
		if not pRoot then continue end

		local dist = (pRoot.Position - origin).Magnitude
		if dist > config.ProximityRange then continue end

		local pct = hum.Health / math.max(hum.MaxHealth, 1)
		if pct <= config.ProximityThreshold then
			woundedCount = woundedCount + 1
		end
	end

	return woundedCount * config.ProximityBonusPerAlly
end

-- ═══════════════════════════════════════════════════════════
-- ON HIT DEALT
-- ═══════════════════════════════════════════════════════════

function LifeStewardBehavior.OnHitDealt(player, hitData, resourceData)
	local config = LifeStewardBehavior.CONFIG
	local gain = config.GainPerHitDealt

	if hitData.isKill then
		if hitData.mobTier == "boss" then
			gain = gain + config.BossKillBonus
		elseif hitData.mobTier == "miniboss" then
			gain = gain + config.MinibossKillBonus
		else
			gain = gain + config.GainPerKill
		end
	end

	return gain
end

-- ═══════════════════════════════════════════════════════════
-- ON HIT RECEIVED
-- ═══════════════════════════════════════════════════════════

function LifeStewardBehavior.OnHitReceived(player, hitData, resourceData)
	local config = LifeStewardBehavior.CONFIG
	return -config.LossPerHitReceived
end

-- ═══════════════════════════════════════════════════════════
-- CALLBACKS
-- ═══════════════════════════════════════════════════════════

function LifeStewardBehavior.OnResourceFull(player)
	-- Life Energy full — ready for ultimate
end

function LifeStewardBehavior.OnResourceEmpty(player)
	print("[LifeStewardBehavior]", player.Name, "is OUT OF LIFE ENERGY!")
end

return LifeStewardBehavior
