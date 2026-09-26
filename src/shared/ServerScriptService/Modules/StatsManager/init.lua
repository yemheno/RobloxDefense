-- StatsManager

local StatsManager = {}

local Modules = script.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))
local DataManager = require(Modules:WaitForChild("PlayerDataManager"))

--============================================
-- LOAD SUB-SYSTEMS
--============================================
local DamageSystem = require(script:WaitForChild("DamageSystem"))
local ArmorSystem   = require(script:WaitForChild("ArmorSystem"))
local CriticalSystem = require(script:WaitForChild("CriticalSystem"))
local HealingSystem  = require(script:WaitForChild("HealingSystem"))
-- §AGX/X11: keystone rule hooks (DamageSystem / CriticalSystem call into it).
local KeystoneRules  = require(script:WaitForChild("KeystoneRules"))

-- Wire sub-systems together
DamageSystem.ArmorSystem    = ArmorSystem
DamageSystem.CriticalSystem = CriticalSystem
HealingSystem.CriticalSystem = CriticalSystem
-- §AGX/X11: keystone hooks. Exposed on StatsManager too so DamageHandler,
-- SkillEffects and the class skill modules reach it without a new require.
DamageSystem.KeystoneRules   = KeystoneRules
CriticalSystem.KeystoneRules = KeystoneRules
StatsManager.KeystoneRules   = KeystoneRules
KeystoneRules.Start()

-- §2.3b: hard-assert that every sub-system is actually wired. A nil
-- CriticalSystem silently disables crits everywhere and is very hard to
-- notice in gameplay — fail fast at boot instead.
assert(DamageSystem.ArmorSystem,     "[StatsManager] DamageSystem.ArmorSystem failed to wire")
assert(DamageSystem.CriticalSystem,  "[StatsManager] DamageSystem.CriticalSystem failed to wire")
assert(HealingSystem.CriticalSystem, "[StatsManager] HealingSystem.CriticalSystem failed to wire")

print("[StatsManager] ArmorSystem loaded")
print("[StatsManager] CriticalSystem loaded")
print("[StatsManager] HealingSystem loaded")

--============================================
-- STAT ACCESS (routes through PlayerDataManager)
--============================================

function StatsManager.GetBonus(player, bonusName)
	return DataManager.GetBonus(player, bonusName)
end

function StatsManager.SetBonus(player, bonusName, value)
	return DataManager.SetBonus(player, bonusName, value)
end

--============================================
-- TOTAL STAT GETTERS
--============================================
function StatsManager.GetTotalHealth(player)
	return DataManager.GetTotalStat(player, "Health")
end

function StatsManager.GetTotalDamage(player)
	return DataManager.GetTotalStat(player, "Damage")
end

--============================================
-- DAMAGE CALCULATIONS
--============================================
function StatsManager.CalculateDamage(player, targetMob, options)
	return DamageSystem.CalculateOutgoingDamage(player, targetMob, options)
end

function StatsManager.CalculateDamageTaken(player, incomingDamage, attackerPenetration)
	return DamageSystem.CalculateIncomingDamage(player, incomingDamage, attackerPenetration)
end

--============================================
-- HEALING CALCULATIONS
--============================================
function StatsManager.CalculateHeal(healer, options)
	return HealingSystem.CalculateHeal(healer, options)
end

return StatsManager