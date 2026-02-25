-- ServerScriptService/Modules/MobBehaviors/Enrage
--[[
    Enrage behavior:
    When the mob's HP falls below `hpThreshold` (0.0–1.0 fraction of max HP),
    it gains a permanent speed and damage boost for the rest of its life.

    Config fields (set in the mob's `behaviors` table):
        hpThreshold  number  0.3     Fraction of max HP that triggers enrage.
        speedBonus   number  4       Added directly to WalkSpeed.
        damageBonus  number  1.5     Multiplied onto mobData.damageMultiplier.
]]

local Enrage = {}

function Enrage.Init(mobData, config)
	-- Store config and initial state on mobData under a namespaced key
	-- to avoid collisions with other fields.
	mobData._enrage = {
		config     = config,
		triggered  = false,
	}
end

function Enrage.Update(mobData, now)
	local state = mobData._enrage
	if not state or state.triggered then return end

	local config    = state.config
	local threshold = config.hpThreshold or 0.3

	local hpFraction = mobData.humanoid.Health / mobData.humanoid.MaxHealth
	if hpFraction > threshold then return end

	-- Trigger enrage
	state.triggered = true

	local speedBonus  = config.speedBonus  or 4
	local damageBonus = config.damageBonus or 1.5

	mobData.humanoid.WalkSpeed    = mobData.config.speed + speedBonus
	mobData.damageMultiplier      = (mobData.damageMultiplier or 1.0) * damageBonus

	local tierText = mobData.mobTier ~= "normal" and " [" .. mobData.mobTier:upper() .. "]" or ""
	print(string.format(
		"[MobAI/Enrage] %s%s enraged! Speed: %.1f  DMG mult: %.2f",
		mobData.mobId, tierText,
		mobData.humanoid.WalkSpeed,
		mobData.damageMultiplier
	))
end

return Enrage
