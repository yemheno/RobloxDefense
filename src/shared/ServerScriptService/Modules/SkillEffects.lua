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
SkillEffects.DamageHandler  = nil  -- §AGX/X12: DoT kills route through ApplyRawDamage

-- §PB-D5: WeaponManager is lazy-loaded, not injected by the
-- place bootstrap. SkillEffects is a "leaf" module (nothing else
-- requires it), and WeaponManager doesn't require SkillEffects, so
-- there's no cycle. Used to grant weapon XP to healer/support classes
-- on healing, buff, and revive events.
local _WeaponManager = nil
local function getWeaponManager()
    if _WeaponManager ~= nil then return _WeaponManager end
    local ok, mod = pcall(function()
        return require(script.Parent:WaitForChild("WeaponManager"))
    end)
    if ok and mod then _WeaponManager = mod else _WeaponManager = false end
    return _WeaponManager or nil
end

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
-- §MEM/M11: weak keys — the 0.5s sweep already prunes dead mobs, but a
-- weak key guarantees GC can reclaim an entry even if a sweep is missed
-- (destroyed Instance keys otherwise pin the table entry).
local activeMobEffects = setmetatable({}, { __mode = "k" })

-- Active player effects tracking (HealOverTime, etc.)
-- { [player] = { [effectKey] = { stacks, endTime, tickNext, ... } } }
local activePlayerEffects = {}

-- Per-mob base speed tracking. Stores the mob's unmodified WalkSpeed
-- (captured once on first speed-affecting effect). This prevents
-- Slow → Stun → remove Stun from restoring a slow-modified speed.
local mobBaseSpeeds = setmetatable({}, { __mode = "k" })  -- §MEM/M11

-- §SCALE/S5, §PERF/F5: DoT/HoT/heal numbers are batched too (one event
-- per tick PER TARGET would be 30 events/s for one player DoT-ing 30 horde
-- mobs). Queue + flush on NUMBER_FLUSH_WINDOW — coarser than combat's
-- window is fine at 1-2 Hz tick rates.
local NUMBER_FLUSH_WINDOW = 0.25
local pendingDamageNumbers = {}  -- [player] = { entry, ... }
local pendingHealNumbers   = {}  -- [player] = { entry, ... }
local numberFlushScheduled = false

local function queueNumber(map, plr, entry)
	local list = map[plr]
	if not list then
		list = {}
		map[plr] = list
	end
	table.insert(list, entry)

	if not numberFlushScheduled then
		numberFlushScheduled = true
		task.delay(NUMBER_FLUSH_WINDOW, function()
			numberFlushScheduled = false
			local nm = SkillEffects.NetworkManager
			if nm then
				for p, entries in pairs(pendingDamageNumbers) do
					if p.Parent then nm.FireClient(p, "DamageNumberBatch", entries) end
				end
				for p, entries in pairs(pendingHealNumbers) do
					if p.Parent then nm.FireClient(p, "HealNumberBatch", entries) end
				end
			end
			table.clear(pendingDamageNumbers)
			table.clear(pendingHealNumbers)
		end)
	end
end

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
	SkillEffects.DamageHandler  = dependencies.DamageHandler  -- §AGX/X12

	-- Start the mob-effect tick loop
	task.spawn(function()
		while true do
			task.wait(0.5)
			SkillEffects.TickMobEffects()
			SkillEffects.TickPlayerEffects()
		end
	end)

	initialized = true
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
		-- §T2/Z9 (§T1P2-STACKS rule, Pablo): below max stacks, adding a
		-- stack refreshes normally. AT max stacks, a new application
		-- refreshes the timer ONLY if it would extend it — a weaker/
		-- shorter re-application can never cut an existing effect short.
		if existing.stacks < maxStacks then
			existing.stacks = existing.stacks + 1
			if effect.refreshDuration then
				existing.endTime = os.clock() + (effect.duration or 6)
			end
		elseif effect.refreshDuration then
			local newEnd = os.clock() + (effect.duration or 6)
			if newEnd > existing.endTime then
				existing.endTime = newEnd
			end
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
	-- §AGX/X12: capture the number position BEFORE damage — a killing tick
	-- Destroy()s the mob, after which its parts are gone.
	local rootPart = mob:FindFirstChild("HumanoidRootPart") or mob.PrimaryPart
	local pos = rootPart and rootPart.Position or mob:GetPivot().Position
	-- §AGX/X12: route through DamageHandler so a DoT kill runs the normal
	-- death path (rewards to the DoT owner + corpse Destroy). Was a bare
	-- humanoid:TakeDamage, which left the corpse and paid nothing.
	local dh = SkillEffects.DamageHandler
	if dh and dh.ApplyRawDamage then
		dh.ApplyRawDamage(mob, tickDamage, player)
	else
		humanoid:TakeDamage(tickDamage)
	end

	-- Fire DoT damage number to the player (small, side-positioned)
	-- §SCALE/S5: batched, not one RemoteEvent per DoT tick per mob.
	if player and SkillEffects.NetworkManager then
		queueNumber(pendingDamageNumbers, player, {
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
	local key = "Vulnerability_direct"
	if not activeMobEffects[mob] then activeMobEffects[mob] = {} end

	-- §T2/Z9 (§T1P2-STACKS rule): non-stacking debuff — a re-application
	-- keeps the STRONGER multiplier and the LONGER remaining duration;
	-- it can never weaken or shorten what's already on the mob (e.g. a
	-- weaker cast from another player).
	local newEnd = os.clock() + (effect.duration or 3)
	local existing = activeMobEffects[mob][key]
	if existing then
		mult = math.max(mult, existing.appliedMult or 0)
		newEnd = math.max(newEnd, existing.endTime)
	end

	mob:SetAttribute("Vulnerability", mult)
	activeMobEffects[mob][key] = {
		type        = "Vulnerability",
		stacks      = 1,
		endTime     = newEnd,
		effectData  = effect,
		appliedMult = mult,  -- §T2/Z9: the winning value, for the next comparison
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
	if not isNegative and getWeaponManager() then
		getWeaponManager().GrantBuffXP(player)
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
	-- §AGX/X11: Clarity Surge (a crit heal restores Life Energy).
	local KR = SkillEffects.StatsManager.KeystoneRules
	if KR then KR.OnHealCast(healer, healResult) end

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

	-- §AGX/X11: Shared Grace — part of the overheal returns as a HoT.
	-- Checked before the early-out so a heal on a full-HP ally counts.
	if healer and amount > actualHeal then
		local sm = SkillEffects.StatsManager
		local KR = sm and sm.KeystoneRules
		if KR then KR.OnOverheal(healer, target, amount - math.max(actualHeal, 0)) end
	end

	if actualHeal <= 0 then return end

	humanoid.Health = humanoid.Health + actualHeal

	-- Grant weapon XP to healer/support for effective healing (overheal excluded).
	if healer and getWeaponManager() and actualHeal > 0 then
		getWeaponManager().GrantHealXP(healer, actualHeal)
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

	-- §SCALE/S5: batched — otherwise an AoE heal costs two immediate
	-- RemoteEvents per ally (target + healer echo).
	queueNumber(pendingHealNumbers, target, healData)
	if healer and healer ~= target then
		queueNumber(pendingHealNumbers, healer, healData)
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

--- §AGX/X11: HoT that restores a FIXED total (not a Damage coefficient),
--- evenly over `duration` seconds at 1 tick/s. Used by Shared Grace. A
--- re-application adds its total to what is still pending and restarts the
--- window, so rapid overheals pool instead of overwriting each other. Its
--- ticks never trigger Shared Grace again (TickHoT doesn't call HealPlayer).
function SkillEffects.ApplyFlatHoT(healer, target, total, duration, id)
	if not target or not target.Parent or total <= 0 then return end
	duration = math.max(1, math.floor(duration or 4))
	local key = "HealOverTime_" .. (id or "flat")
	local effects = activePlayerEffects[target]
	if not effects then
		effects = {}
		activePlayerEffects[target] = effects
	end
	local now = os.clock()
	local entry = effects[key]
	if entry and entry.flatRemaining then
		entry.flatRemaining = entry.flatRemaining + total
		entry.flatTicksLeft = duration
		entry.endTime       = now + duration * 2 + 1
		entry.healer        = healer
	else
		effects[key] = {
			type          = "HealOverTime",
			stacks        = 1,
			maxStacks     = 1,
			-- Generous: ticks drift up to 0.5 s each on the 0.5 s loop; the
			-- entry ends itself after its last tick (flatTicksLeft → 0).
			endTime       = now + duration * 2 + 1,
			healer        = healer,
			effectData    = { tickInterval = 1 },
			tickNext      = now + 1,
			flatRemaining = total,
			flatTicksLeft = duration,
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

	local tickHeal
	if entry.flatRemaining then
		-- §AGX/X11: fixed-total HoT (Shared Grace).
		local ticksLeft = math.max(entry.flatTicksLeft or 1, 1)
		tickHeal = entry.flatRemaining / ticksLeft
		entry.flatRemaining = entry.flatRemaining - tickHeal
		entry.flatTicksLeft = ticksLeft - 1
		if entry.flatTicksLeft <= 0 then entry.endTime = 0 end
		tickHeal = math.floor(tickHeal + 0.5)
	elseif healer and SkillEffects.StatsManager and SkillEffects.StatsManager.CalculateHeal then
		-- §AGX/BAL (§T1.3-BAL1): HoT ticks go through the heal pipeline
		-- (Damage + flat HealingPower, × HealingPercent) like every other
		-- heal, so innate HealingPercent and HealingPower gear apply to
		-- HoTs. No crit on ticks.
		local r = SkillEffects.StatsManager.CalculateHeal(healer, {
			healMultiplier = healCoef,
			canCrit        = false,
		})
		tickHeal = math.floor((r and r.heal or 0) * stacks)
	else
		-- Scale from healer's damage (mirrors DoT scaling) — fallback
		local baseHeal = 10
		if healer and SkillEffects.StatsManager then
			baseHeal = SkillEffects.StatsManager.GetTotalDamage(healer) or 10
		end
		tickHeal = math.floor(baseHeal * healCoef * stacks)
	end
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
		-- §SCALE/S5: batched HoT ticks.
		queueNumber(pendingHealNumbers, target, healData)
		if healer and healer ~= target then
			queueNumber(pendingHealNumbers, healer, healData)
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
