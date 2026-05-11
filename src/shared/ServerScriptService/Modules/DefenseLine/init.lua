-- ServerScriptService/Modules/DefenseLine

local DefenseLine = {}

local RunService = game:GetService("RunService")

local Modules = script.Parent

-- Lazy loaded external modules
local NetworkManager   = nil
local GameStateManager = nil
local MobAI            = nil

-- Child modules
local DefenseConfig = require(script:WaitForChild("DefenseConfig"))
local DefenseHealth = require(script:WaitForChild("DefenseHealth"))
local DefenseCombo = require(script:WaitForChild("DefenseCombo"))
local DefenseDetection = require(script:WaitForChild("DefenseDetection"))
local DefenseAnimation = require(script:WaitForChild("DefenseAnimation"))

-- State
local defenseLinePart = nil
local isInitialized = false

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DefenseLine.Init()
	-- Load external modules
	NetworkManager = require(Modules:WaitForChild("NetworkManager"))
	MobAI = require(Modules:WaitForChild("MobAI"))

	-- Get defense line part
	defenseLinePart = workspace:WaitForChild("DefenseLine", 10)
	if not defenseLinePart then
		warn("[DefenseLine] DefenseLine part not found in workspace!")
		return
	end

	-- Setup child modules with references
	DefenseHealth.Config = DefenseConfig
	DefenseHealth.NetworkManager = NetworkManager
	DefenseHealth.DefensePart = defenseLinePart
	DefenseHealth.Init()

	DefenseCombo.Config = DefenseConfig
	DefenseCombo.NetworkManager = NetworkManager
	DefenseCombo.Init()

	DefenseDetection.Config = DefenseConfig
	DefenseDetection.DefensePart = defenseLinePart
	DefenseDetection.OnMobReached = DefenseLine.OnMobReachedLine
	DefenseDetection.Init()

	DefenseAnimation.Config = DefenseConfig
	DefenseAnimation.Init()

	-- Create network events
	NetworkManager.GetEvent("DefenseLineUpdate")
	NetworkManager.GetEvent("DefenseLineDamaged")
	NetworkManager.GetEvent("DefenseLineDestroyed")
	NetworkManager.GetEvent("DefenseLineCombo")

	-- Start update loop
	RunService.Heartbeat:Connect(function(dt)
		DefenseLine.Update(dt)
	end)

	isInitialized = true

	print("  Health:", DefenseHealth.GetHealth(), "/", DefenseHealth.GetMaxHealth())
	print("  Combo:", DefenseConfig.Combo.Enabled and "ON" or "OFF")

	task.defer(function()
		DefenseLine.LateInit()
	end)
end

-- §D2 fix: LateInit idempotency. Init() task.defers LateInit once, but
-- the place bootstrap (LaneDefenseMain) ALSO calls LateInit explicitly,
-- which used to log + re-require twice. Guard so the second call is a
-- silent no-op.
local _lateInitDone = false

function DefenseLine.LateInit()
	if _lateInitDone then return end
	_lateInitDone = true

	-- Get modules that load after DefenseLine
	local GSM = Modules:FindFirstChild("GameStateManager")
	if GSM then
		GameStateManager = require(GSM)
	end

	local MAI = Modules:FindFirstChild("MobAI")
	if MAI then
		MobAI = require(MAI)
		DefenseDetection.MobAI = MobAI
	end

	print("[DefenseLine] Late init complete")
end

-- ═══════════════════════════════════════════════════════════
-- UPDATE LOOP
-- ═══════════════════════════════════════════════════════════

function DefenseLine.Update(dt)
	if DefenseHealth.IsDestroyed() then return end

	-- Only update when game is active
	if GameStateManager and not GameStateManager.IsDefending() then
		return
	end

	-- Update subsystems
	DefenseCombo.Update(dt)
	DefenseDetection.Update(dt)
	DefenseHealth.UpdateRegen(dt)
end

-- ═══════════════════════════════════════════════════════════
-- MOB REACHES LINE (Called by DefenseDetection)
-- ═══════════════════════════════════════════════════════════

function DefenseLine.OnMobReachedLine(mob, mobData)
	if DefenseHealth.IsDestroyed() then return end

	-- Immediately unregister from MobAI so it stops processing this mob
	if MobAI then
		MobAI.UnregisterMob(mob)
	end

	-- Get mob stats
	local humanoid = mob:FindFirstChild("Humanoid")
	local remainingHP = humanoid and humanoid.Health or 0
	local maxMobHP = humanoid and humanoid.MaxHealth or 1
	local mobHpPercent = math.clamp(remainingHP / math.max(1, maxMobHP), 0, 1)
	local mobConfig = mobData.config or {}   -- guard: registry miss produces no .config
	local mobTier = mobData.mobTier or "normal"
	local mobTypeName = mobData.mobTypeName or "Unknown"

	-- Get combo multiplier (increments combo)
	local comboMultiplier = DefenseCombo.IncrementCombo()
	local comboLevel = DefenseCombo.GetLevel()

	-- Calculate damage (§47.2)
	local baseDamage = DefenseLine.CalculateBaseDamage({
		tier = mobTier,
		mobHpPercent = mobHpPercent,
	})
	local finalDamage = baseDamage * comboMultiplier

	-- Play animation, then apply damage
	DefenseAnimation.PlayHitAnimation(mob, function()
		-- Apply damage
		DefenseHealth.TakeDamage(finalDamage, {
			source = "mob",
			mobTypeName = mobTypeName,
			mobTier = mobTier,
			comboLevel = comboLevel,
			comboMultiplier = comboMultiplier,
			baseDamage = baseDamage,
		})

		-- Log
		local comboText = comboMultiplier > 1 and " [COMBO x" .. math.floor(comboLevel) .. "]" or ""
		print("[DefenseLine] 💥", mobTypeName, "[" .. mobTier .. "]", math.floor(finalDamage), "dmg" .. comboText)

		-- Destroy mob
		DefenseDetection.ClearMob(mob)
		if mob and mob.Parent then
			mob:Destroy()
		end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- DAMAGE CALCULATION (§47.2 — percentage-based breach damage)
-- BreachDamage = round(MaxHP × BasePct × RemainingHpFactor)
-- RemainingHpFactor = 0.5 + 0.5 × currentHpPercent
-- ═══════════════════════════════════════════════════════════

function DefenseLine.CalculateBaseDamage(params)
	local tier = params.tier or "normal"
	local basePct = DefenseConfig.BreachBasePct[tier] or DefenseConfig.BreachBasePct.normal
	local maxHP = DefenseHealth.GetMaxHealth()

	-- currentHpPercent of the MOB at time of breach (rewards softening mobs)
	local mobHpPercent = params.mobHpPercent or 1.0
	local remainingHpFactor = 0.5 + 0.5 * mobHpPercent

	return math.max(1, math.floor(maxHP * basePct * remainingHpFactor + 0.5))
end

-- ═══════════════════════════════════════════════════════════
-- RESET
-- ═══════════════════════════════════════════════════════════

function DefenseLine.Reset()
	DefenseHealth.Reset()
	DefenseCombo.Reset()
	DefenseDetection.Reset()
	print("[DefenseLine] Reset complete")
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API: Health
-- ═══════════════════════════════════════════════════════════

function DefenseLine.GetMaxHealth()
	return DefenseHealth.GetMaxHealth()
end

function DefenseLine.SetChapterLevel(level)
	DefenseHealth.SetChapterLevel(level)
end

function DefenseLine.Heal(amount)
	return DefenseHealth.Heal(amount)
end

--- Heal by a fraction of max HP (e.g. 0.10 = 10%).
--- Called by the card/vote system (RepairWindow).
function DefenseLine.HealPercent(fraction)
	local maxHP = DefenseHealth.GetMaxHealth()
	local amount = math.floor(maxHP * fraction + 0.5)
	return DefenseHealth.Heal(amount)
end

--- Add a temporary shield as a flat heal equal to a fraction of max HP.
--- Full shield mechanics (overheal buffer) can be added later; for now
--- this is equivalent to a heal that can over-cap up to 100%.
--- Called by the card/vote system (Fortify).
function DefenseLine.AddShieldPercent(fraction)
	local maxHP = DefenseHealth.GetMaxHealth()
	local amount = math.floor(maxHP * fraction + 0.5)
	return DefenseHealth.Heal(amount)
end

function DefenseLine.SetHealth(value)
	DefenseHealth.SetHealth(value)
end

function DefenseLine.SendStateToPlayer(player)
	DefenseHealth.SendStateToPlayer(player)
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API: Callbacks
-- ═══════════════════════════════════════════════════════════

function DefenseLine.OnDestroyedCallback(callback)
	DefenseHealth.OnDestroyed(callback)
end

function DefenseLine.OnComboChanged(callback)
	DefenseCombo.OnChanged(callback)
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function DefenseLine.TestDamage(mobTier, remainingHP, attack)
	mobTier = mobTier or "normal"
	remainingHP = remainingHP or 50
	attack = attack or 10

	local comboMult = DefenseCombo.IncrementCombo()
	local baseDamage = DefenseLine.CalculateBaseDamage({
		remainingHP = remainingHP,
		attack = attack,
		tier = mobTier,
	})
	local finalDamage = baseDamage * comboMult

	print("[DefenseLine] TEST")
	print("  Tier:", mobTier, "| HP:", remainingHP, "| Attack:", attack)
	print("  Base:", math.floor(baseDamage), "| Combo:", DefenseCombo.GetLevel(), "(" .. string.format("%.2f", comboMult) .. "x)")
	print("  Final:", math.floor(finalDamage))

	DefenseHealth.TakeDamage(finalDamage, { source = "test", mobTier = mobTier })

	return finalDamage
end

return DefenseLine