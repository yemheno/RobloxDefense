-- ServerScriptService/Modules/DefenseLine

local DefenseLine = {}

local RunService = game:GetService("RunService")

local Modules = script.Parent

-- Lazy loaded external modules
local NetworkManager = nil
local MobConfig = nil
local GameStateManager = nil
local MobAI = nil

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

	print("[DefenseLine] Initialized")
	print("  Health:", DefenseHealth.GetHealth(), "/", DefenseHealth.GetMaxHealth())
	print("  Combo:", DefenseConfig.Combo.Enabled and "ON" or "OFF")
end

function DefenseLine.LateInit()
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

	-- Get mob stats
	local humanoid = mob:FindFirstChild("Humanoid")
	local remainingHP = humanoid and humanoid.Health or 0
	local mobConfig = mobData.config
	local mobTier = mobData.mobTier or "normal"
	local mobAttack = mobConfig.damage or 10
	local mobTypeName = mobData.mobTypeName or "Unknown"

	-- Get combo multiplier (increments combo)
	local comboMultiplier = DefenseCombo.IncrementCombo()
	local comboLevel = DefenseCombo.GetLevel()

	-- Calculate damage
	local baseDamage = DefenseLine.CalculateBaseDamage({
		remainingHP = remainingHP,
		attack = mobAttack,
		tier = mobTier,
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
-- DAMAGE CALCULATION
-- ═══════════════════════════════════════════════════════════

function DefenseLine.CalculateBaseDamage(params)
	local config = DefenseConfig.Damage

	local remainingHP = params.remainingHP or 0
	local attack = params.attack or 10
	local tier = params.tier or "normal"

	local basePart = config.BaseDamage
	local hpPart = remainingHP * config.HPFactor
	local attackPart = attack * config.AttackFactor

	local rawDamage = basePart + hpPart + attackPart

	local tierMultiplier = config.TierMultipliers[tier] or 1.0
	rawDamage = rawDamage * tierMultiplier
	rawDamage = rawDamage * config.GlobalMultiplier

	return math.max(1, rawDamage)
end

function DefenseLine.CalculateDamage(params)
	local baseDamage = DefenseLine.CalculateBaseDamage(params)
	local comboMultiplier = DefenseCombo.GetMultiplier()
	return baseDamage * comboMultiplier
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

function DefenseLine.GetHealth()
	return DefenseHealth.GetHealth()
end

function DefenseLine.GetMaxHealth()
	return DefenseHealth.GetMaxHealth()
end

function DefenseLine.GetHealthPercent()
	return DefenseHealth.GetHealthPercent()
end

function DefenseLine.IsDestroyed()
	return DefenseHealth.IsDestroyed()
end

function DefenseLine.TakeDamage(amount, source)
	return DefenseHealth.TakeDamage(amount, source)
end

function DefenseLine.Heal(amount)
	return DefenseHealth.Heal(amount)
end

function DefenseLine.SetHealth(value)
	DefenseHealth.SetHealth(value)
end

function DefenseLine.SetMaxHealth(value)
	DefenseHealth.SetMaxHealth(value)
end

function DefenseLine.SendStateToPlayer(player)
	DefenseHealth.SendStateToPlayer(player)
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API: Combo
-- ═══════════════════════════════════════════════════════════

function DefenseLine.GetComboLevel()
	return DefenseCombo.GetLevel()
end

function DefenseLine.GetComboMultiplier()
	return DefenseCombo.GetMultiplier()
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API: Callbacks
-- ═══════════════════════════════════════════════════════════

function DefenseLine.OnDamaged(callback)
	DefenseHealth.OnDamaged(callback)
end

function DefenseLine.OnDestroyedCallback(callback)
	DefenseHealth.OnDestroyed(callback)
end

function DefenseLine.OnHealed(callback)
	DefenseHealth.OnHealed(callback)
end

function DefenseLine.OnComboChanged(callback)
	DefenseCombo.OnChanged(callback)
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API: Configuration
-- ═══════════════════════════════════════════════════════════

function DefenseLine.GetConfig()
	return DefenseConfig
end

-- Damage config
function DefenseLine.SetBaseDamage(value)
	DefenseConfig.Damage.BaseDamage = value
end

function DefenseLine.SetHPFactor(value)
	DefenseConfig.Damage.HPFactor = value
end

function DefenseLine.SetAttackFactor(value)
	DefenseConfig.Damage.AttackFactor = value
end

function DefenseLine.SetGlobalMultiplier(value)
	DefenseConfig.Damage.GlobalMultiplier = value
end

function DefenseLine.SetTierMultiplier(tier, value)
	DefenseConfig.Damage.TierMultipliers[tier] = value
end

-- Combo config
function DefenseLine.SetComboEnabled(enabled)
	DefenseConfig.Combo.Enabled = enabled
	print("[DefenseLine] Combo:", enabled and "ON" or "OFF")
end

function DefenseLine.SetComboWindow(seconds)
	DefenseConfig.Combo.Window = seconds
end

function DefenseLine.SetComboFactor(factor)
	DefenseConfig.Combo.Factor = factor
end

function DefenseLine.SetComboMaxLevel(level)
	DefenseConfig.Combo.MaxLevel = level
end

-- Detection config
function DefenseLine.SetDetectionRange(value)
	DefenseConfig.Detection.Range = value
end

-- Regen config
function DefenseLine.SetRegen(enabled, perSecond, delay)
	DefenseConfig.Regen.Enabled = enabled
	if perSecond then DefenseConfig.Regen.PerSecond = perSecond end
	if delay then DefenseConfig.Regen.Delay = delay end
end

-- Animation config
function DefenseLine.SetAnimationEnabled(enabled)
	DefenseConfig.Animation.Enabled = enabled
end

function DefenseLine.SetAnimationStyle(style)
	DefenseConfig.Animation.Style = style
end

function DefenseLine.SetAnimationDuration(duration)
	DefenseConfig.Animation.Duration = duration
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API: Part
-- ═══════════════════════════════════════════════════════════

function DefenseLine.GetPart()
	return defenseLinePart
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function DefenseLine.GetDebugInfo()
	return {
		health = {
			current = DefenseHealth.GetHealth(),
			max = DefenseHealth.GetMaxHealth(),
			percent = DefenseHealth.GetHealthPercent(),
			destroyed = DefenseHealth.IsDestroyed(),
		},
		combo = DefenseCombo.GetDebugInfo(),
		detection = DefenseDetection.GetDebugInfo(),
		config = DefenseConfig,
	}
end

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