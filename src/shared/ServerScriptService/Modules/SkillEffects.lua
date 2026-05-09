-- ServerScriptService/Modules/SkillEffects
--[[
    Handles application of all status effects from skills.
    
    Supported effect types:
        PLAYER BUFFS          MOB DEBUFFS / CC
        ─────────────         ────────────────
        DamageReduction       Slow
        CritChanceUp          Knockback
        AttackSpeedDown       Pull
        HealingPowerUp        Taunt
                              Stun
        HEALING               Immobilize
        ───────               ArmorReduction
        Heal                  Vulnerability
        HealOverTime

        MOB OVER TIME
        ─────────────
        DamagePerSecond
]]

local SkillEffects = {}

local TweenService = game:GetService("TweenService")

-- Dependencies (set by SkillManager.Init)
SkillEffects.AttackShapes   = nil
SkillEffects.NetworkManager = nil
SkillEffects.MobAI          = nil
SkillEffects.SkillManager   = nil
SkillEffects.StatsManager   = nil
-- Set by place bootstrap after WeaponManager loads.
-- Used to grant weapon XP to healer/support classes on healing, buff, and revive events.
SkillEffects.WeaponManager  = nil

-- Lazy-loaded for achievement tracking; no circular dep risk.
local _AchievementManager = nil
local function getAM()
    if not _AchievementManager then
        local mod = script.Parent:FindFirstChild("AchievementManager")
        if mod then
            local ok, am = pcall(require, mod)
            if ok then _AchievementManager = am end
        end
    end
    return _AchievementManager
end

local initialized = false

-- Active mob effects tracking
-- { [mob] = { [effectKey] = { stacks, endTime, tickNext, ... } } }
local activeMobEffects = {}

-- Active player effects tracking (HealOverTime, etc.)
-- { [player] = { [effectKey] = { stacks, endTime, tickNext, ... } } }
local activePlayerEffects = {}

-- Per-mob base speed tracking. Stores the mob's unmodified WalkSpeed
-- (captured once on first speed-affecting effect). This prevents
-- Slow → Stun → remove Stun from restoring a slow-modified speed.
local mobBaseSpeeds = {}

-- Skill "strength" is a game-design value; multiply by this scale
-- to produce a physics impulse (N·s).  Heavy mobs resist knockback
-- naturally through their higher AssemblyMass.
local KNOCKBACK_IMPULSE_SCALE = 10

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function SkillEffects.Init(dependencies)
	if not dependencies then
		print("[SkillEffects] Waiting for SkillManager to initialize with dependencies...")
		return
	end

	if initialized then return end

	SkillEffects.AttackShapes   = dependencies.AttackShapes
	SkillEffects.NetworkManager = dependencies.NetworkManager
	SkillEffects.MobAI          = dependencies.MobAI
	SkillEffects.SkillManager   = dependencies.SkillManager
	SkillEffects.StatsManager   = dependencies.StatsManager

	-- Start the mob-effect tick loop
	task.spawn(function()
		while true do
			task.wait(0.5)
			SkillEffects.TickMobEffects()
			SkillEffects.TickPlayerEffects()
		end
	end)

	initialized = true
	print("[SkillEffects] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- MOB BASE SPEED HELPER
-- Returns the mob's true unmodified WalkSpeed.  The value is
-- captured once (before the first Slow/Stun/Immobilize) and
-- reused for all subsequent speed-modifying effects.
-- ═══════════════════════════════════════════════════════════

function SkillEffects.GetMobBaseSpeed(mob, humanoid)
	if mobBaseSpeeds[mob] then
		return mobBaseSpeeds[mob]
	end
	-- First speed-affecting effect: store current (unmodified) speed.
	-- If the mob is currently paused by MobAI (WalkSpeed already 0), fall back
	-- to the AI config speed so that RestoreMobSpeed can return to the right value.
	local speed = humanoid.WalkSpeed
	if speed <= 0 and SkillEffects.MobAI then
		local mobData = SkillEffects.MobAI.GetMobData(mob)
		if mobData and mobData.config then
			speed = mobData.config.speed or 16
		end
	end
	if speed <= 0 then speed = 16 end
	mobBaseSpeeds[mob] = speed
	return speed
end

-- ═══════════════════════════════════════════════════════════
-- APPLY EFFECTS FROM SKILL CONFIG  (player-origin effects)
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyEffects(player, effects, origin)
	for _, effect in ipairs(effects or {}) do
		SkillEffects.ApplyEffect(player, effect, origin)
	end
end

function SkillEffects.ApplyEffect(player, effect, origin)
	local t = effect.type

	if t == "Pull" then
		SkillEffects.ApplyPull(player, effect, origin)

	elseif t == "Taunt" then
		SkillEffects.ApplyTaunt(player, effect, origin)

	elseif t == "Stun" then
		SkillEffects.ApplyStun(player, effect, origin)

	elseif t == "Immobilize" then
		SkillEffects.ApplyImmobilize(player, effect, origin)

	elseif t == "DamageReduction" then
		SkillEffects.ApplyDamageReduction(player, effect, origin)

	elseif t == "CritChanceUp" then
		SkillEffects.ApplyPlayerBuff(player, effect, "CritChance")

	elseif t == "AttackSpeedDown" then
		SkillEffects.ApplyPlayerBuff(player, effect, "AttackSpeed", true)

	elseif t == "Slow" then
		SkillEffects.ApplySlow(player, effect, origin)

	elseif t == "Knockback" then
		SkillEffects.ApplyKnockback(player, effect, origin)

	-- Healing
	elseif t == "Heal" then
		SkillEffects.ApplyHeal(player, effect, origin)

	elseif t == "HealOverTime" then
		SkillEffects.ApplyHealOverTime(player, effect, origin)

	elseif t == "HealingPowerUp" then
		SkillEffects.ApplyPlayerBuff(player, effect, "HealingPercent")

	else
		warn("[SkillEffects] Unknown effect type:", t)
	end
end

-- ═══════════════════════════════════════════════════════════
-- APPLY EFFECTS DIRECTLY TO MOB LIST
-- Used by mouse-targeted / area skills that already have targets.
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyEffectsToMobs(player, effects, mobs)
	for _, effect in ipairs(effects or {}) do
		for _, mob in ipairs(mobs) do
			SkillEffects.ApplyMobEffect(player, effect, mob)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- APPLY STACKING EFFECTS TO MOB LIST
-- Used by Sundering Strikes: adds 1 stack per call.
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyStackingEffects(player, effects, mobs)
	for _, effect in ipairs(effects or {}) do
		for _, mob in ipairs(mobs) do
			SkillEffects.ApplyStackingMobEffect(player, effect, mob)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- SINGLE MOB EFFECT APPLICATION
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyMobEffect(player, effect, mob)
	local t = effect.type

	if t == "Slow" then
		SkillEffects.ApplySlowToMob(mob, effect)

	elseif t == "DamagePerSecond" then
		SkillEffects.ApplyDoTToMob(player, mob, effect)

	elseif t == "ArmorReduction" then
		SkillEffects.ApplyArmorReductionToMob(mob, effect)

	elseif t == "Vulnerability" then
		SkillEffects.ApplyVulnerabilityToMob(mob, effect)

	elseif t == "Stun" then
		SkillEffects.ApplyStunToMob(mob, effect)

	elseif t == "Immobilize" then
		SkillEffects.ApplyImmobilizeToMob(mob, effect)

	elseif t == "Knockback" or t == "Pull" then
		local char = player and player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local origin = root.Position
			if t == "Knockback" then
				SkillEffects.ApplyKnockbackToMob(mob, effect, origin)
			else
				SkillEffects.ApplyPullToMob(mob, effect, origin)
			end
		end

	else
		warn("[SkillEffects] Unknown mob effect type:", t)
	end
end

-- ═══════════════════════════════════════════════════════════
-- STACKING MOB EFFECT (adds 1 stack, up to maxStacks)
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyStackingMobEffect(player, effect, mob)
	if not mob or not mob.Parent then return end

	local key = effect.type .. "_" .. (effect.id or effect.type)
	if not activeMobEffects[mob] then
		activeMobEffects[mob] = {}
	end

	local existing = activeMobEffects[mob][key]
	local maxStacks = effect.maxStacks or 1

	if existing then
		-- Add stack (up to max)
		if existing.stacks < maxStacks then
			existing.stacks = existing.stacks + 1
		end
		-- Refresh duration
		if effect.refreshDuration then
			existing.endTime = os.clock() + (effect.duration or 6)
		end
		existing.player = player
	else
		-- New entry
		activeMobEffects[mob][key] = {
			type         = effect.type,
			stacks       = 1,
			maxStacks    = maxStacks,
			endTime      = os.clock() + (effect.duration or 6),
			player       = player,
			effectData   = effect,
			tickNext     = effect.tickInterval and (os.clock() + effect.tickInterval) or nil,
		}
	end

	-- Apply immediate stat change for ArmorReduction
	if effect.type == "ArmorReduction" then
		local entry = activeMobEffects[mob][key]
		local totalReduction = (effect.amountPerStack or 5) * entry.stacks
		mob:SetAttribute("ArmorReduction", totalReduction)
	end

	local entry = activeMobEffects[mob][key]
	mob:SetAttribute(effect.type .. "_Stacks", entry.stacks)

end

-- ═══════════════════════════════════════════════════════════
-- MOB EFFECT TICK LOOP
-- ═══════════════════════════════════════════════════════════

function SkillEffects.TickMobEffects()
	local now = os.clock()

	-- Collect dead mobs first to avoid mutating outer table during iteration
	local deadMobs = {}
	for mob in pairs(activeMobEffects) do
		if not mob or not mob.Parent then
			table.insert(deadMobs, mob)
		end
	end
	for _, mob in ipairs(deadMobs) do
		activeMobEffects[mob] = nil
		mobBaseSpeeds[mob] = nil
	end

	for mob, effects in pairs(activeMobEffects) do
		-- Collect expired keys first to avoid mutating inner table during iteration
		local expired = {}
		for key, entry in pairs(effects) do
			if now >= entry.endTime then
				table.insert(expired, { key = key, entry = entry })
			else
				-- DoT tick?
				if entry.type == "DamagePerSecond" and entry.tickNext and now >= entry.tickNext then
					SkillEffects.TickDoT(mob, entry)
					entry.tickNext = now + (entry.effectData.tickInterval or 1)
				end
			end
		end

		for _, info in ipairs(expired) do
			-- Nil the entry BEFORE calling RemoveMobEffect so that
			-- RestoreMobSpeed's "is any speed effect still active?" scan
			-- does not find this expiring entry and incorrectly keep WalkSpeed=0.
			effects[info.key] = nil
			SkillEffects.RemoveMobEffect(mob, info.key, info.entry)
		end

		-- Clean up empty tables
		local hasEffects = false
		for _ in pairs(effects) do hasEffects = true; break end
		if not hasEffects then
			activeMobEffects[mob] = nil
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- DOT TICK
-- ═══════════════════════════════════════════════════════════

function SkillEffects.TickDoT(mob, entry)
	local humanoid = mob:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local player     = entry.player
	local damageCoef = entry.effectData.damagePerTick or 0.1
	local stacks     = entry.stacks or 1

	-- Get player's total damage for scaling
	local baseDamage = 10   -- fallback
	if player and SkillEffects.StatsManager then
		baseDamage = SkillEffects.StatsManager.GetTotalDamage(player) or 10
	end

	local tickDamage = baseDamage * damageCoef * stacks
	humanoid:TakeDamage(tickDamage)

	-- Fire DoT damage number to the player (small, side-positioned)
	if player and SkillEffects.NetworkManager then
		local rootPart = mob:FindFirstChild("HumanoidRootPart") or mob.PrimaryPart
		local pos = rootPart and rootPart.Position or mob:GetPivot().Position

		SkillEffects.NetworkManager.FireClient(player, "DamageNumber", {
			position      = pos,
			damage        = tickDamage,
			wasCrit       = false,
			critProcs     = 0,
			attackerName  = player.Name,
			attackerUserId = player.UserId,
			attackElement = entry.effectData.element or "None",
			isDoT         = true,
		})
	end

end

-- ═══════════════════════════════════════════════════════════
-- REMOVE MOB EFFECT (cleanup)
-- ═══════════════════════════════════════════════════════════

function SkillEffects.RemoveMobEffect(mob, key, entry)
	if not mob or not mob.Parent then return end

	if entry.type == "ArmorReduction" then
		mob:SetAttribute("ArmorReduction", 0)
	elseif entry.type == "Vulnerability" then
		mob:SetAttribute("Vulnerability", nil)
	elseif entry.type == "Slow" then
		mob:SetAttribute("IsSlowed", false)
		SkillEffects.RestoreMobSpeed(mob)
	elseif entry.type == "Stun" then
		mob:SetAttribute("IsStunned", false)
		SkillEffects.RestoreMobSpeed(mob)
	elseif entry.type == "Immobilize" then
		mob:SetAttribute("IsImmobilized", false)
		SkillEffects.RestoreMobSpeed(mob)
	elseif entry.type == "Knockback" then
		mob:SetAttribute("IsKnockedBack", false)
		SkillEffects.RestoreMobSpeed(mob)
	end

	mob:SetAttribute(entry.type .. "_Stacks", nil)
end

-- Restore a mob's WalkSpeed after a speed-affecting effect expires.
-- If other speed-affecting effects are still active on this mob,
-- re-apply the strongest remaining modification. Otherwise restore
-- the original base speed and clean up the cache.
function SkillEffects.RestoreMobSpeed(mob)
	local humanoid = mob:FindFirstChild("Humanoid")
	if not humanoid then return end

	local baseSpeed = mobBaseSpeeds[mob]
	if not baseSpeed then return end

	local effects = activeMobEffects[mob]
	if effects then
		-- Priority 1: Any hard-CC (stun/immobilize/knockback) → speed 0
		for _, entry in pairs(effects) do
			if entry.type == "Stun" or entry.type == "Immobilize" or entry.type == "Knockback" then
				humanoid.WalkSpeed = 0
				return
			end
		end
		-- Priority 2: Apply the strongest slow (highest slow %)
		local strongestSlow = 0
		for _, entry in pairs(effects) do
			if entry.type == "Slow" then
				local amount = entry.effectData and entry.effectData.amount or 50
				if amount > strongestSlow then
					strongestSlow = amount
				end
			end
		end
		if strongestSlow > 0 then
			humanoid.WalkSpeed = baseSpeed * (1 - strongestSlow / 100)
			return
		end
	end
	-- No remaining speed effects — full restore
	humanoid.WalkSpeed = baseSpeed
	mobBaseSpeeds[mob] = nil
end

-- ═══════════════════════════════════════════════════════════
-- INDIVIDUAL MOB EFFECT APPLIERS
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplySlowToMob(mob, effect)
	if not mob or not mob.Parent then return end
	local humanoid = mob:FindFirstChild("Humanoid")
	if not humanoid then return end

	local key = "Slow_direct"
	if not activeMobEffects[mob] then activeMobEffects[mob] = {} end

	-- Preserve the base speed from before any speed-modifying effects
	local baseSpeed = SkillEffects.GetMobBaseSpeed(mob, humanoid)

	humanoid.WalkSpeed = baseSpeed * (1 - (effect.amount or 50) / 100)
	mob:SetAttribute("IsSlowed", true)

	activeMobEffects[mob][key] = {
		type          = "Slow",
		stacks        = 1,
		endTime       = os.clock() + (effect.duration or 3),
		effectData    = effect,
	}
end

function SkillEffects.ApplyDoTToMob(player, mob, effect)
	if not mob or not mob.Parent then return end

	local key = "DamagePerSecond_direct"
	if not activeMobEffects[mob] then activeMobEffects[mob] = {} end

	activeMobEffects[mob][key] = {
		type       = "DamagePerSecond",
		stacks     = 1,
		endTime    = os.clock() + (effect.duration or 3),
		player     = player,
		effectData = effect,
		tickNext   = os.clock() + (effect.tickInterval or 1),
	}
end

function SkillEffects.ApplyArmorReductionToMob(mob, effect)
	if not mob or not mob.Parent then return end

	local key = "ArmorReduction_direct"
	if not activeMobEffects[mob] then activeMobEffects[mob] = {} end

	local amount = effect.amountPerStack or effect.amount or 5
	mob:SetAttribute("ArmorReduction", amount)

	activeMobEffects[mob][key] = {
		type       = "ArmorReduction",
		stacks     = 1,
		endTime    = os.clock() + (effect.duration or 6),
		effectData = effect,
	}
end

function SkillEffects.ApplyVulnerabilityToMob(mob, effect)
	if not mob or not mob.Parent then return end

	local mult = effect.damageMultiplier or 1.5
	mob:SetAttribute("Vulnerability", mult)

	local key = "Vulnerability_direct"
	if not activeMobEffects[mob] then activeMobEffects[mob] = {} end

	activeMobEffects[mob][key] = {
		type       = "Vulnerability",
		stacks     = 1,
		endTime    = os.clock() + (effect.duration or 3),
		effectData = effect,
	}

end

function SkillEffects.ApplyStunToMob(mob, effect)
	if not mob or not mob.Parent then return end
	local humanoid = mob:FindFirstChild("Humanoid")
	if not humanoid then return end

	local key = "Stun_direct"
	if not activeMobEffects[mob] then activeMobEffects[mob] = {} end

	-- Preserve the base speed from before any speed-modifying effects
	local baseSpeed = SkillEffects.GetMobBaseSpeed(mob, humanoid)
	humanoid.WalkSpeed = 0
	mob:SetAttribute("IsStunned", true)

	activeMobEffects[mob][key] = {
		type          = "Stun",
		stacks        = 1,
		endTime       = os.clock() + (effect.duration or 2),
		effectData    = effect,
	}
end

function SkillEffects.ApplyImmobilizeToMob(mob, effect)
	if not mob or not mob.Parent then return end
	local humanoid = mob:FindFirstChild("Humanoid")
	if not humanoid then return end

	local key = "Immobilize_direct"
	if not activeMobEffects[mob] then activeMobEffects[mob] = {} end

	-- Preserve the base speed from before any speed-modifying effects
	local baseSpeed = SkillEffects.GetMobBaseSpeed(mob, humanoid)
	humanoid.WalkSpeed = 0
	mob:SetAttribute("IsImmobilized", true)

	activeMobEffects[mob][key] = {
		type          = "Immobilize",
		stacks        = 1,
		endTime       = os.clock() + (effect.duration or 3),
		effectData    = effect,
	}
end

-- ═══════════════════════════════════════════════════════════
-- PLAYER BUFF (generic stat modification with auto-revert)
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyPlayerBuff(player, effect, statName, isNegative)
	if not SkillEffects.SkillManager then return end

	local amount = effect.amount or 0
	if isNegative then amount = -amount end

	local buffId = statName .. "_buff"

	SkillEffects.SkillManager.ApplyBuff(player, buffId, {
		type     = statName,           -- maps to StatsManager bonus name
		amount   = amount,
		duration = effect.duration or 6,
	})

	-- Grant weapon XP to healer/support for applying beneficial buffs.
	-- `player` here is the caster (the buff targets may differ, but XP belongs to the caster).
	if not isNegative and SkillEffects.WeaponManager then
		SkillEffects.WeaponManager.GrantBuffXP(player)
	end

end

-- ═══════════════════════════════════════════════════════════
-- PULL EFFECT
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyPull(player, effect, origin)
	local mobsInRange = SkillEffects.AttackShapes.GetTargetsInCircle(origin, effect.range or 10, "IsMob")

	for _, mob in ipairs(mobsInRange) do
		SkillEffects.ApplyPullToMob(mob, effect, origin)
	end

end

function SkillEffects.ApplyPullToMob(mob, effect, origin)
	if not mob or not mob.Parent then return end
	local rootPart = mob:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local resist = mob:GetAttribute("KnockbackResist") or 0
	if resist >= 1 then return end

	local toOrigin = (origin - rootPart.Position)
	local pullDir = Vector3.new(toOrigin.X, 0, toOrigin.Z)
	if pullDir.Magnitude < 0.001 then return end
	local dist = pullDir.Magnitude   -- horizontal distance to caster
	pullDir = pullDir.Unit

	local strength = (effect.strength or 20) * KNOCKBACK_IMPULSE_SCALE * (1 - resist)

	if effect.flatStrength then
		-- Cap velocity so the mob cannot overshoot the caster.
		-- A mob very close to the caster would launch past it without this cap.
		local duration    = effect.duration or 0.3
		local maxVelocity = dist / duration
		local velocity    = math.min(effect.flatStrength, maxVelocity) * (1 - resist)
		rootPart.AssemblyLinearVelocity = pullDir * velocity
	else
		rootPart:ApplyImpulse(pullDir * strength)
	end

	-- Brief immobilize so AI doesn't fight the displacement
	local duration = effect.duration or 0.3
	local humanoid = mob:FindFirstChild("Humanoid")
	if humanoid then
		SkillEffects.GetMobBaseSpeed(mob, humanoid)
		humanoid.WalkSpeed = 0
	end

	local key = "Pull_direct"
	if not activeMobEffects[mob] then activeMobEffects[mob] = {} end
	activeMobEffects[mob][key] = {
		type = "Knockback",
		stacks = 1,
		endTime = os.clock() + duration,
		effectData = effect,
	}
	mob:SetAttribute("IsKnockedBack", true)
end

-- ═══════════════════════════════════════════════════════════
-- TAUNT EFFECT
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyTaunt(player, effect, origin)
	if not SkillEffects.MobAI then
		warn("[SkillEffects] MobAI not loaded")
		return
	end

	player:SetAttribute("IsTaunting", true)

	local mobsInRange = SkillEffects.AttackShapes.GetTargetsInCircle(origin, effect.range, "IsMob")

	for _, mob in ipairs(mobsInRange) do
		local mobData = SkillEffects.MobAI.GetMobData(mob)
		if mobData then
			mobData.forcedTarget = player
			mobData.tauntEndTime = os.clock() + effect.duration
		end
	end

	task.delay(effect.duration, function()
		if player and player:GetAttribute("IsTaunting") then
			player:SetAttribute("IsTaunting", false)
		end
	end)

end

-- ═══════════════════════════════════════════════════════════
-- STUN EFFECT  (area-based, uses origin)
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyStun(player, effect, origin)
	local mobsInRange = SkillEffects.AttackShapes.GetTargetsInCircle(origin, effect.range or 10, "IsMob")

	for _, mob in ipairs(mobsInRange) do
		SkillEffects.ApplyStunToMob(mob, effect)
	end

end

-- ═══════════════════════════════════════════════════════════
-- IMMOBILIZE EFFECT  (area-based, uses origin)
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyImmobilize(player, effect, origin)
	local mobsInRange = SkillEffects.AttackShapes.GetTargetsInCircle(origin, effect.range or 10, "IsMob")

	for _, mob in ipairs(mobsInRange) do
		SkillEffects.ApplyImmobilizeToMob(mob, effect)
	end

end

-- ═══════════════════════════════════════════════════════════
-- DAMAGE REDUCTION (Buff on player)
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyDamageReduction(player, effect, origin)
	if not SkillEffects.SkillManager then return end

	local buffId = "DamageReduction_" .. player.UserId
	SkillEffects.SkillManager.ApplyBuff(player, buffId, effect)
end

-- ═══════════════════════════════════════════════════════════
-- SLOW EFFECT  (area-based, uses origin)
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplySlow(player, effect, origin)
	local mobsInRange = SkillEffects.AttackShapes.GetTargetsInCircle(origin, effect.range or 10, "IsMob")

	for _, mob in ipairs(mobsInRange) do
		SkillEffects.ApplySlowToMob(mob, effect)
	end

end

-- ═══════════════════════════════════════════════════════════
-- KNOCKBACK EFFECT
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyKnockback(player, effect, origin)
	local mobsInRange = SkillEffects.AttackShapes.GetTargetsInCircle(origin, effect.range or 10, "IsMob")

	for _, mob in ipairs(mobsInRange) do
		SkillEffects.ApplyKnockbackToMob(mob, effect, origin)
	end

end

function SkillEffects.ApplyKnockbackToMob(mob, effect, origin)
	if not mob or not mob.Parent then return end
	local rootPart = mob:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local resist = mob:GetAttribute("KnockbackResist") or 0
	if resist >= 1 then return end

	local awayDir = (rootPart.Position - origin)
	local knockDir = Vector3.new(awayDir.X, 0, awayDir.Z)
	if knockDir.Magnitude < 0.001 then return end
	knockDir = knockDir.Unit

	local strength = (effect.strength or 30) * KNOCKBACK_IMPULSE_SCALE * (1 - resist)

	if effect.flatStrength then
		-- Talent-granted flat velocity: ignores mass entirely
		rootPart.AssemblyLinearVelocity = knockDir * effect.flatStrength * (1 - resist)
	else
		-- Default: mass-dependent impulse (heavy mobs barely budge)
		rootPart:ApplyImpulse(knockDir * strength)
	end

	-- Brief immobilize so AI doesn't fight the displacement
	local duration = effect.duration or 0.3
	local humanoid = mob:FindFirstChild("Humanoid")
	if humanoid then
		SkillEffects.GetMobBaseSpeed(mob, humanoid)
		humanoid.WalkSpeed = 0
	end

	local key = "Knockback_direct"
	if not activeMobEffects[mob] then activeMobEffects[mob] = {} end
	activeMobEffects[mob][key] = {
		type = "Knockback",
		stacks = 1,
		endTime = os.clock() + duration,
		effectData = effect,
	}
	mob:SetAttribute("IsKnockedBack", true)
end

-- ═══════════════════════════════════════════════════════════
-- HEALING: INSTANT HEAL
-- Heals allied players in range around origin.
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")

function SkillEffects.GetAlliesInRange(origin, range, healer)
	local allies = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if not char then continue end
		local hum = char:FindFirstChild("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then continue end
		if (root.Position - origin).Magnitude <= range then
			table.insert(allies, p)
		end
	end
	return allies
end

function SkillEffects.ApplyHeal(healer, effect, origin)
	if not SkillEffects.StatsManager then return end

	local range = effect.range or 15
	local allies = SkillEffects.GetAlliesInRange(origin, range, healer)

	local healResult = SkillEffects.StatsManager.CalculateHeal(healer, {
		healMultiplier = effect.healMultiplier or 1.0,
		canCrit = effect.canCrit ~= false,
	})

	for _, target in ipairs(allies) do
		SkillEffects.HealPlayer(target, healResult.heal, healer, healResult.wasCrit, healResult.critProcs)
	end

end

function SkillEffects.HealPlayer(target, amount, healer, wasCrit, critProcs)
	local char = target.Character
	if not char then return end
	local humanoid = char:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local actualHeal = math.min(amount, humanoid.MaxHealth - humanoid.Health)
	if actualHeal <= 0 then return end

	humanoid.Health = humanoid.Health + actualHeal

	-- Grant weapon XP to healer/support for effective healing (overheal excluded).
	if healer and SkillEffects.WeaponManager and actualHeal > 0 then
		SkillEffects.WeaponManager.GrantHealXP(healer, actualHeal)
	end

	-- Track healing done for achievements.
	if healer then
		local am = getAM()
		if am then am.OnHealingDone(healer, actualHeal) end
	end

	SkillEffects.SendHealNumber(target, actualHeal, healer, wasCrit, critProcs)
end

function SkillEffects.SendHealNumber(target, amount, healer, wasCrit, critProcs)
	if not SkillEffects.NetworkManager then return end

	local char = target.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local healData = {
		position   = rootPart.Position,
		amount     = amount,
		wasCrit    = wasCrit or false,
		critProcs  = critProcs or 0,
		healerName = healer and healer.Name or "?",
		healerUserId = healer and healer.UserId or 0,
		isHoT      = false,
	}

	-- Send to the healed player
	SkillEffects.NetworkManager.FireClient(target, "HealNumber", healData)

	-- Also send to the healer (if different) so they see their own heal output
	if healer and healer ~= target then
		SkillEffects.NetworkManager.FireClient(healer, "HealNumber", healData)
	end
end

-- ═══════════════════════════════════════════════════════════
-- HEALING: HEAL OVER TIME (HoT)
-- Tracked per-player, mirrors DoT for mobs.
-- ═══════════════════════════════════════════════════════════

function SkillEffects.ApplyHealOverTime(healer, effect, origin)
	if not SkillEffects.StatsManager then return end

	local range = effect.range or 15
	local allies = SkillEffects.GetAlliesInRange(origin, range, healer)

	for _, target in ipairs(allies) do
		SkillEffects.ApplyHoTToPlayer(healer, target, effect)
	end

end

function SkillEffects.ApplyHoTToPlayer(healer, target, effect)
	local key = "HealOverTime_" .. (effect.id or "direct")
	if not activePlayerEffects[target] then
		activePlayerEffects[target] = {}
	end

	local existing = activePlayerEffects[target][key]
	local maxStacks = effect.maxStacks or 1

	if existing then
		if existing.stacks < maxStacks then
			existing.stacks = existing.stacks + 1
		end
		if effect.refreshDuration ~= false then
			existing.endTime = os.clock() + (effect.duration or 6)
		end
		existing.healer = healer
	else
		activePlayerEffects[target][key] = {
			type       = "HealOverTime",
			stacks     = 1,
			maxStacks  = maxStacks,
			endTime    = os.clock() + (effect.duration or 6),
			healer     = healer,
			effectData = effect,
			tickNext   = os.clock() + (effect.tickInterval or 1),
		}
	end
end

-- ═══════════════════════════════════════════════════════════
-- PLAYER EFFECT TICK LOOP (HoT, etc.)
-- ═══════════════════════════════════════════════════════════

function SkillEffects.TickPlayerEffects()
	local now = os.clock()

	-- Remove disconnected players
	local gone = {}
	for p in pairs(activePlayerEffects) do
		if not p or not p.Parent then
			table.insert(gone, p)
		end
	end
	for _, p in ipairs(gone) do
		activePlayerEffects[p] = nil
	end

	for target, effects in pairs(activePlayerEffects) do
		local expired = {}
		for key, entry in pairs(effects) do
			if now >= entry.endTime then
				table.insert(expired, key)
			else
				-- HoT tick
				if entry.type == "HealOverTime" and entry.tickNext and now >= entry.tickNext then
					SkillEffects.TickHoT(target, entry)
					entry.tickNext = now + (entry.effectData.tickInterval or 1)
				end
			end
		end

		for _, key in ipairs(expired) do
			effects[key] = nil
		end

		-- Clean empty tables
		local hasEffects = false
		for _ in pairs(effects) do hasEffects = true; break end
		if not hasEffects then
			activePlayerEffects[target] = nil
		end
	end
end

function SkillEffects.TickHoT(target, entry)
	local char = target.Character
	if not char then return end
	local humanoid = char:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local healer    = entry.healer
	local healCoef  = entry.effectData.healPerTick or 0.1
	local stacks    = entry.stacks or 1

	-- Scale from healer's damage (mirrors DoT scaling)
	local baseHeal = 10
	if healer and SkillEffects.StatsManager then
		baseHeal = SkillEffects.StatsManager.GetTotalDamage(healer) or 10
	end

	local tickHeal = math.floor(baseHeal * healCoef * stacks)
	local actualHeal = math.min(tickHeal, humanoid.MaxHealth - humanoid.Health)
	if actualHeal <= 0 then return end

	humanoid.Health = humanoid.Health + actualHeal

	-- Send HoT number
	if SkillEffects.NetworkManager then
		local rootPart = char:FindFirstChild("HumanoidRootPart")
		local pos = rootPart and rootPart.Position or char:GetPivot().Position

		local healData = {
			position     = pos,
			amount       = actualHeal,
			wasCrit      = false,
			critProcs    = 0,
			healerName   = healer and healer.Name or "?",
			healerUserId = healer and healer.UserId or 0,
			isHoT        = true,
		}
		SkillEffects.NetworkManager.FireClient(target, "HealNumber", healData)
		if healer and healer ~= target then
			SkillEffects.NetworkManager.FireClient(healer, "HealNumber", healData)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- CLEANSE: Remove one debuff from a player
-- Delegates to SkillManager for stat-based debuffs.
-- Returns true if a debuff was removed.
-- ═══════════════════════════════════════════════════════════

function SkillEffects.CleansePlayerDebuff(target)
	if SkillEffects.SkillManager and SkillEffects.SkillManager.CleanseOneDebuff then
		local removed, buffId = SkillEffects.SkillManager.CleanseOneDebuff(target)
		if removed then
			return true
		end
	end
	return false
end

return SkillEffects
