-- DamageSystem

local DamageSystem = {}

local Modules = script.Parent.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))
local DataManager = require(Modules:WaitForChild("PlayerDataManager"))
local ElementalSystem = require(Modules:WaitForChild("ElementalSystem"))

-- SUB-SYSTEM REFERENCES (set by StatsManager)
DamageSystem.ArmorSystem    = nil
DamageSystem.CriticalSystem = nil
DamageSystem.KeystoneRules  = nil  -- §AGX/X11: keystone hooks (set by StatsManager)

-- §AGX/BAL: combat guard caps, resolved once. Penetration (60) was declared in
-- StatCaps but never enforced; the other two answer TODO §1 [??] items.
local PENETRATION_CAP      = (Config.StatCaps.Penetration and Config.StatCaps.Penetration.max) or 60
-- Vulnerability never stacks (strongest application wins, §T2/Z9); the
-- strongest source is Meteorite at 1.25×. 2.0 leaves 60% headroom for
-- talents/new skills and bounds the worst hit at 3.24 (crit) × 1.25
-- (element) × 2.0 = 8.1× instead of 12.2× at the interim 3.0.
local VULNERABILITY_CAP    = 2.0
-- ArmorReduction peaks at 25% today (Sundering 5 stacks × 5%). Capping at
-- 50% (2× headroom) means shred alone can never zero a mob's armor;
-- Penetration (capped at 60) is the stat that strips the rest.
local ARMOR_REDUCTION_CAP  = 50

-- §T1.3/B10: single lazy getter. Same shape as ClassManager's per-module
-- lazy getters; replaces the two divergent inline implementations that
-- previously lived in GetBaseDamage and CalculateIncomingDamage.
-- A pcall on the initial require so a deep WeaponManager load-error
-- surfaces once and then we proceed with weapon-attack = 0.
local _WeaponManager
local _weaponManagerWarned = false
local function getWeaponManager()
	if _WeaponManager ~= nil then
		return _WeaponManager or nil
	end
	local mod = Modules:FindFirstChild("WeaponManager")
	if not mod then
		if not _weaponManagerWarned then
			_weaponManagerWarned = true
			warn("[DamageSystem] WeaponManager module not found under StatsManager's " ..
				"parent folder — weapon attack will be treated as 0 for all players.")
		end
		_WeaponManager = false
		return nil
	end
	local ok, result = pcall(require, mod)
	if ok then
		_WeaponManager = result
		return result
	end
	if not _weaponManagerWarned then
		_weaponManagerWarned = true
		warn("[DamageSystem] Lazy require of WeaponManager failed: " ..
			tostring(result) .. " — weapon attack will be treated as 0.")
	end
	_WeaponManager = false
	return nil
end

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

	-- Weapon attack
	local weaponAttack = 0
	local wm = getWeaponManager()
	if wm then
		weaponAttack = wm.GetWeaponAttack(player) or 0
	end

	-- Flat attack bonus from weapon bonuses (already applied via RefreshWeaponStats)
	local flatAttack = DataManager.GetBonus(player, "FlatAttack") or 0

	return playerDamage + weaponAttack + flatAttack
end

-- ═══════════════════════════════════════════════════════════
-- OUTGOING DAMAGE (Player → Mob)
-- ═══════════════════════════════════════════════════════════
--[[  options (optional table):
        attackElement     (string)  — element of the hit (from weapon or skill)
        actionMultiplier  (number)  — skill damage coefficient (default 1.0)
]]
function DamageSystem.CalculateOutgoingDamage(player, targetMob, options)
	options = options or {}

	-- Pipeline per §42.1:
	-- BaseAttack → ActionMultiplier → PercentDmg → Armor (division) → Crit → Element → Vulnerability → floor

	-- §AGX/X11: keystone modifiers for this hit (Overwhelm, Cull the Weak,
	-- Second Heart, Relentless Quarry). One call; zeros when none apply.
	local ksDmgPct, ksPen, ksCrit, ksLifesteal = 0, 0, 0, 0
	local KR = DamageSystem.KeystoneRules
	if KR then
		ksDmgPct, ksPen, ksCrit, ksLifesteal = KR.OutgoingHit(player, targetMob, options) -- §AGX/X11: Spell Rhythm needs options
	end

	-- Step 1: Base Attack
	local baseAttack = DamageSystem.GetBaseDamage(player)

	-- Step 2: Action Multiplier (skill coefficient)
	local actionMultiplier = options.actionMultiplier or 1.0
	-- SkillDamage bonus amplifies skill hits (only when an explicit multiplier is provided)
	if options.actionMultiplier then
		local skillDamageBonus = DataManager.GetBonus(player, "SkillDamage") or 0
		actionMultiplier = actionMultiplier * (1 + skillDamageBonus / 100)
	end
	local damage = baseAttack * actionMultiplier

	-- Step 3: Percent Damage bonus
	local percentDamage = (DataManager.GetBonus(player, "DamagePercent") or 0) + ksDmgPct  -- §AGX/X11
	damage = damage * math.max(0, 1 + percentDamage / 100)

	-- Step 4: Armor Mitigation (division-based)
	local playerPenetration = 0
	local isPenetrating = false
	if DamageSystem.ArmorSystem then
		-- §AGX/BAL: StatCaps.Penetration enforced (keystone bonus included).
		playerPenetration = math.min(DamageSystem.ArmorSystem.GetPenetration(player) + ksPen, PENETRATION_CAP)
		isPenetrating = playerPenetration > 0
	end

	local mobArmor = 0
	if targetMob then
		mobArmor = targetMob:GetAttribute("Armor") or 0
	end

	-- ArmorReduction is now percentage-based (e.g. 30 = 30% reduction)
	local armorReductionPct = 0
	if targetMob then
		-- §AGX/BAL: TODO §1 [??] ArmorReduction floor → capped (see top).
		armorReductionPct = math.clamp(targetMob:GetAttribute("ArmorReduction") or 0, 0, ARMOR_REDUCTION_CAP)
	end

	local effectiveMobArmor = math.max(0, mobArmor * (1 - armorReductionPct / 100) - playerPenetration)
	local armorMultiplier = 100 / (100 + effectiveMobArmor)
	damage = damage * armorMultiplier

	-- Step 5: Critical Hit (after armor)
	local wasCrit = false
	local critProcs = 0
	if DamageSystem.CriticalSystem then
		damage, wasCrit, critProcs = DamageSystem.CriticalSystem.ApplyCrit(player, damage, ksCrit)  -- §AGX/X11
	end

	-- Step 6: Elemental Multiplier
	-- §2.3a: nil-fallback. If either element is missing or the matchup
	-- table has no entry, GetMultiplier may return nil; treat that as a
	-- neutral 1.0× instead of blowing up the arithmetic.
	local attackElement   = options.attackElement or "None"
	local defenderElement = ElementalSystem.GetMobElement(targetMob) or "None"
	local elementMult     = ElementalSystem.GetMultiplier(attackElement, defenderElement) or 1
	local elementLabel    = ElementalSystem.GetInteractionLabel(attackElement, defenderElement)
	damage = damage * elementMult

	-- Step 7: Vulnerability multiplier (applied by skill debuffs, e.g. Meteorite)
	-- §T1P2/Y2: runaway clamp. §AGX/BAL: 3.0 → VULNERABILITY_CAP (2.0),
	-- answering TODO §1 [??] "Vulnerability stacking cap" (see top).
	if targetMob then
		local vulnerability = targetMob:GetAttribute("Vulnerability") or 0
		if vulnerability > 0 then
			damage = damage * math.min(vulnerability, VULNERABILITY_CAP)
		end
	end

	-- Floor and minimum 1
	damage = math.max(1, math.floor(damage))

	return {
		damage = damage,
		wasCrit = wasCrit,
		critProcs = critProcs or 0,
		isPenetrating = isPenetrating,
		attackElement   = attackElement,
		defenderElement = defenderElement,
		elementMult     = elementMult,
		elementLabel    = elementLabel,
		bonusLifesteal  = ksLifesteal,  -- §AGX/X11: Cull the Weak (read by DamageHandler)
	}
end

-- ═══════════════════════════════════════════════════════════
-- INCOMING DAMAGE (Mob → Player)
-- ═══════════════════════════════════════════════════════════
function DamageSystem.CalculateIncomingDamage(player, incomingDamage, attackerPenetration)
	local finalDamage = incomingDamage
	attackerPenetration = attackerPenetration or 0

	-- ── Tank weapon XP: grant XP BEFORE any reduction, rewarding the act
	--    of being in danger regardless of how much armor/DR the tank has.
	if incomingDamage > 0 then
		local wm = getWeaponManager()
		if wm then
			wm.GrantDamageTakenXP(player, incomingDamage)
		end
	end

	-- Step 1: Armor Reduction
	if DamageSystem.ArmorSystem then
		finalDamage = DamageSystem.ArmorSystem.ApplyArmor(player, finalDamage, attackerPenetration)
	end

	-- Step 2: Damage Reduction (percentage)
	-- Path A: regular DR — capped by StatCaps (max 75%)
	local damageReduction = DataManager.GetBonus(player, "DamageReduction") or 0
	-- §AGX/X11: Unyielding Advance / Last Bastion add regular (capped) DR.
	local KR = DamageSystem.KeystoneRules
	if KR then
		damageReduction = damageReduction + KR.IncomingDR(player)
	end
	local caps = Config.StatCaps.DamageReduction
	if caps then
		damageReduction = math.clamp(damageReduction, caps.min, caps.max)
	end

	-- Path B: uncapped DR — from ultimates (e.g. Aegis Battle Beast); bypasses the stat cap.
	-- Clamped only to [0, 100] so it can never invert damage.
	local uncappedDR = math.clamp(DataManager.GetBonus(player, "UncappedDamageReduction") or 0, 0, 100)

	-- Use whichever path grants more protection
	local effectiveDR = math.max(damageReduction, uncappedDR)

	finalDamage = finalDamage * (1 - effectiveDR / 100)

	-- Minimum 1 damage, floored
	finalDamage = math.max(1, math.floor(finalDamage))

	-- §AGX/X11: Second Heart watches the HP this hit leaves behind.
	if KR then
		KR.AfterIncomingDamage(player, finalDamage)
	end
	return finalDamage
end

return DamageSystem