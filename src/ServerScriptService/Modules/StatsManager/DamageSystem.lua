-- DamageSystem

local DamageSystem = {}

local Modules = script.Parent.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))
local DataManager = require(Modules:WaitForChild("PlayerDataManager"))
local ElementalSystem = require(Modules:WaitForChild("ElementalSystem"))

-- SUB-SYSTEM REFERENCES (set by StatsManager)
DamageSystem.ArmorSystem = nil
DamageSystem.CriticalSystem = nil

-- ═══════════════════════════════════════════════════════════
-- BASE DAMAGE CALCULATION
-- ═══════════════════════════════════════════════════════════
--[[
    Damage formula:
    1. Player Damage: Base + (Allocated * PointValue) + BonusDamage, then * (1 + DamagePercent/100)
    2. Weapon Attack: From equipped weapon (level, refinement, tier scaled)
    3. Flat Attack: Bonus from weapon random bonuses
    
    Final = PlayerDamage + WeaponAttack + FlatAttack
]]
function DamageSystem.GetBaseDamage(player)
	-- Player's stat-based damage
	local playerDamage = DataManager.GetTotalStat(player, "Damage")

	-- Weapon attack (NEW!)
	local weaponAttack = 0
	local WeaponManagerModule = Modules:FindFirstChild("WeaponManager")
	if WeaponManagerModule then
		local WeaponManager = require(WeaponManagerModule)
		weaponAttack = WeaponManager.GetWeaponAttack(player) or 0
	end

	-- Flat attack bonus from weapon bonuses (already applied via RefreshWeaponStats)
	local flatAttack = DataManager.GetBonus(player, "FlatAttack") or 0

	return playerDamage + weaponAttack + flatAttack
end

-- ═══════════════════════════════════════════════════════════
-- OUTGOING DAMAGE (Player → Mob)
-- ═══════════════════════════════════════════════════════════
--[[  options (optional table):
        attackElement  (string)  — element of the hit (from weapon or skill)
                                   defaults to "None" if omitted
]]
function DamageSystem.CalculateOutgoingDamage(player, targetMob, options)
	options = options or {}

	local damage = DamageSystem.GetBaseDamage(player)
	local wasCrit = false
	local critProcs = 0
	local isPenetrating = false

	-- Step 1: Critical Hit
	if DamageSystem.CriticalSystem then
		damage, wasCrit, critProcs = DamageSystem.CriticalSystem.ApplyCrit(player, damage)
	end

	-- Step 2: Penetration check
	if DamageSystem.ArmorSystem then
		isPenetrating = DamageSystem.ArmorSystem.GetPenetration(player) > 0
	end

	-- Step 3: Elemental Multiplier
	local attackElement   = options.attackElement or "None"
	local defenderElement = ElementalSystem.GetMobElement(targetMob)
	local elementMult     = ElementalSystem.GetMultiplier(attackElement, defenderElement)
	local elementLabel    = ElementalSystem.GetInteractionLabel(attackElement, defenderElement)
	damage = damage * elementMult

	return {
		damage = damage,
		wasCrit = wasCrit,
		critProcs = critProcs or 0,
		isPenetrating = isPenetrating,
		-- Elemental info (for damage numbers / logs)
		attackElement   = attackElement,
		defenderElement = defenderElement,
		elementMult     = elementMult,
		elementLabel    = elementLabel,
	}
end

-- ═══════════════════════════════════════════════════════════
-- INCOMING DAMAGE (Mob → Player)
-- ═══════════════════════════════════════════════════════════
function DamageSystem.CalculateIncomingDamage(player, incomingDamage, attackerPenetration)
	local finalDamage = incomingDamage
	attackerPenetration = attackerPenetration or 0

	-- Step 1: Armor Reduction
	if DamageSystem.ArmorSystem then
		finalDamage = DamageSystem.ArmorSystem.ApplyArmor(player, finalDamage, attackerPenetration)
	end

	-- Step 2: Damage Reduction (percentage)
	local damageReduction = DataManager.GetBonus(player, "DamageReduction") or 0

	-- Apply cap if defined
	local caps = Config.StatCaps.DamageReduction
	if caps then
		damageReduction = math.clamp(damageReduction, caps.min, caps.max)
	end

	finalDamage = finalDamage * (1 - damageReduction / 100)

	-- Minimum 1 damage
	return math.max(1, finalDamage)
end

return DamageSystem