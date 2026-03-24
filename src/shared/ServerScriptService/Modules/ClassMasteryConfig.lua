-- ServerScriptService/Modules/ClassMasteryConfig
--[[
    §5 / §21: Class Mastery Milestones

    Mastery XP accumulates while the player is at a chapter level cap.
    Milestones grant rewards: titles, cosmetics, role seals, and weapon path unlocks.

    Second weapon unlock (§5):
      - Account level 60+
      - Class Mastery milestone "second_weapon" on that class
]]

local ClassMasteryConfig = {}

-- ═══════════════════════════════════════════════════════════
-- MASTERY MILESTONES (shared across all classes)
-- Each milestone requires a total accumulated MasteryXP threshold.
-- ═══════════════════════════════════════════════════════════

ClassMasteryConfig.Milestones = {
	-- id, xpRequired, rewards table
	{ id = "mastery_1",       xpRequired = 2000,    rewards = { title = "Initiate" } },
	{ id = "mastery_2",       xpRequired = 6000,    rewards = { title = "Adept" } },
	{ id = "role_seal_1",     xpRequired = 12000,   rewards = { boundToken = "RoleSeal_1" } },
	{ id = "mastery_3",       xpRequired = 20000,   rewards = { title = "Veteran" } },
	{ id = "second_weapon",   xpRequired = 30000,   rewards = { unlock = "SecondWeaponPath" } },
	{ id = "role_seal_2",     xpRequired = 45000,   rewards = { boundToken = "RoleSeal_2" } },
	{ id = "mastery_4",       xpRequired = 65000,   rewards = { title = "Master" } },
	{ id = "role_seal_3",     xpRequired = 90000,   rewards = { boundToken = "RoleSeal_3" } },
	{ id = "mastery_5",       xpRequired = 120000,  rewards = { title = "Grandmaster" } },
}

-- ═══════════════════════════════════════════════════════════
-- SECOND WEAPON UNLOCK REQUIREMENTS (§5)
-- ═══════════════════════════════════════════════════════════

ClassMasteryConfig.SecondWeaponGate = {
	minAccountLevel = 60,
	requiredMilestone = "second_weapon",
}

-- ═══════════════════════════════════════════════════════════
-- ROLE-SPECIFIC SEAL MAP (§21)
-- Maps class names to the bound token IDs their seals produce.
-- ═══════════════════════════════════════════════════════════

ClassMasteryConfig.RoleSealMap = {
	Aegis        = "TankSeal",
	Hunter       = "DPSSeal",
	LifeSteward  = "HealerSeal",
	Arcanist     = "SupportSeal",
}

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

--- Get all milestones a class has unlocked given its current MasteryXP.
function ClassMasteryConfig.GetUnlockedMilestones(masteryXP)
	local unlocked = {}
	for _, milestone in ipairs(ClassMasteryConfig.Milestones) do
		if masteryXP >= milestone.xpRequired then
			table.insert(unlocked, milestone)
		end
	end
	return unlocked
end

--- Get newly-unlockable milestones (not yet in the player's MasteryMilestones table).
function ClassMasteryConfig.GetPendingMilestones(masteryXP, existingMilestones)
	local pending = {}
	for _, milestone in ipairs(ClassMasteryConfig.Milestones) do
		if masteryXP >= milestone.xpRequired and not existingMilestones[milestone.id] then
			table.insert(pending, milestone)
		end
	end
	return pending
end

--- Check whether the player can unlock a second weapon path for a given class.
function ClassMasteryConfig.CanUnlockSecondWeapon(accountLevel, classMilestones)
	local gate = ClassMasteryConfig.SecondWeaponGate
	if accountLevel < gate.minAccountLevel then
		return false
	end
	return classMilestones[gate.requiredMilestone] == true
end

return ClassMasteryConfig
