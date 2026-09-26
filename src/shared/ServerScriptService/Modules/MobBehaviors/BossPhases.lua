-- ServerScriptService/Modules/MobBehaviors/BossPhases
--[[
    §AGX/X28: HP-threshold phases for boss-tier mobs.

    Reads the phase list from the mob definition (`mobData.config.phases`,
    see Mobs/IronWarden.lua for the field reference) so designers tune one
    table. On each phase entry it rewrites, on THIS mob only:
        • mobData.skillPriority        — which skills are active
        • mobData.resolvedSkills[id]   — per-phase tuned COPIES (the
                                         registry tables are shared by every
                                         mob and are never mutated)
        • mobData.config.attackCooldown — config is a per-mob deep copy
        • mobData.baseSpeed / WalkSpeed
        • mobData.damageMultiplier     — set, not compounded (don't combine
                                         with the Enrage behavior)
    and publishes the phase index as the "BossPhase" attribute on the mob
    model. BossEncounter listens to that attribute for announcements and
    adds, so this behavior stays free of networking and spawning.

    Declared as:
        behaviors = { { type = "BossPhases" } }
]]

local BossPhases = {}

local DEFAULT_FIRST_CAST_DELAY = 2

local function applyPhase(mobData, index, now)
	local state = mobData._bossPhases
	local phase = state.phases[index]
	if not phase then return end
	state.index = index

	-- Skills: active list + tuned copies.
	local priority = {}
	for _, skillId in ipairs(phase.skills or {}) do
		local base = state.baseSkills[skillId]
		if base then
			local tuning = phase.skillTuning and phase.skillTuning[skillId]
			local skill = base
			if tuning then
				skill = table.clone(base)
				for key, value in pairs(tuning) do
					skill[key] = value
				end
			end
			mobData.resolvedSkills[skillId] = skill
			table.insert(priority, skillId)

			-- A skill unlocked by a LATER phase gets a short fuse so the
			-- phase change is felt; phase-1 skills keep MobAI's own
			-- startOnCooldown timers.
			if not state.unlocked[skillId] then
				state.unlocked[skillId] = true
				if index > 1 then
					mobData.skillCooldowns[skillId] = now + (phase.firstCastDelay or DEFAULT_FIRST_CAST_DELAY)
				end
			end
		else
			warn(string.format(
				"[BossPhases] %s phase %d lists skill %s, which is not in the mob's `skills` list — ignored.",
				tostring(mobData.mobId), index, tostring(skillId)))
		end
	end
	mobData.skillPriority = priority

	-- Cadence / speed / damage.
	mobData.config.attackCooldown = state.baseCooldown * (phase.attackCooldownMult or 1)
	local speed = state.baseSpeed + (phase.speedBonus or 0)
	mobData.baseSpeed = speed
	if mobData.humanoid then
		mobData.humanoid.WalkSpeed = speed
	end
	mobData.damageMultiplier = phase.damageMult or 1

	if mobData.mob then
		mobData.mob:SetAttribute("BossPhase", index)
		mobData.mob:SetAttribute("BossPhaseName", phase.name or ("Phase " .. index))
	end
end

function BossPhases.Init(mobData, _config)
	local phases = mobData.config and mobData.config.phases
	if type(phases) ~= "table" or #phases == 0 then
		warn("[BossPhases] mob", tostring(mobData.mobId), "declares BossPhases but has no `phases` table.")
		return
	end

	local baseSkills = {}
	for skillId, skill in pairs(mobData.resolvedSkills or {}) do
		baseSkills[skillId] = skill
	end

	mobData._bossPhases = {
		phases       = phases,
		index        = 0,
		baseSkills   = baseSkills,
		unlocked     = {},
		baseCooldown = mobData.config.attackCooldown or 2,
		baseSpeed    = mobData.config.speed or 0,
	}

	-- §FRENZY1 opt-out: MobAI only ramps speed when spawnTime is set.
	local bossCfg = mobData.config.boss
	if bossCfg and bossCfg.disableFrenzy then
		mobData.spawnTime = nil
	end

	applyPhase(mobData, 1, os.clock())
end

function BossPhases.Update(mobData, now)
	local state = mobData._bossPhases
	if not state then return end
	local humanoid = mobData.humanoid
	if not humanoid or humanoid.MaxHealth <= 0 then return end

	local hpFraction = humanoid.Health / humanoid.MaxHealth
	local target = state.index
	for i = state.index + 1, #state.phases do
		if hpFraction <= (state.phases[i].enterAtHp or 0) then
			target = i
		end
	end
	if target > state.index then
		applyPhase(mobData, target, now)
	end
end

--- Current phase index for a registered boss (0 if not a phased mob).
function BossPhases.GetPhase(mobData)
	local state = mobData and mobData._bossPhases
	return state and state.index or 0
end

return BossPhases
