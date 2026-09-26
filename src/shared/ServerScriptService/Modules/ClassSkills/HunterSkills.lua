-- ServerScriptService/Modules/ClassSkills/HunterSkills
--[[
    Hunter Skill Layout
    ════════════════════
    Slot 1 — Swift Arrow    Instant piercing shot (up to 3 targets)
    Slot 2 — Barrage        5 rapid arrows, successive-hit scaling
    Slot 3 — Rain of Arrows Mouse-targeted rectangle volley (2 waves)
    Slot 4 — Eagle Eye ★ULT Crit-chance buff (scales with Focus),
                            attack-speed penalty, lasts 6 s.
                            Uses ALL Killer Instinct (min 100).
]]

local HunterSkills = {}

local BaseSkills = require(script.Parent:WaitForChild("BaseSkills"))
local Base    = nil
local Effects = nil

-- ═══════════════════════════════════════════════════════════
-- CLASS IDENTIFIER
-- ═══════════════════════════════════════════════════════════

HunterSkills.CLASS = "Hunter"

-- ═══════════════════════════════════════════════════════════
-- ANIMATIONS
-- ═══════════════════════════════════════════════════════════

-- R6 Animate-script IDs (guaranteed visible on R6 rigs).
local ANIM = {
	Draw  = "rbxassetid://128853357",  -- R6 Point (arm extend = drawing bow)
	Roll  = "rbxassetid://128777973",  -- R6 Wave  (arm swing = rapid fire)
	Cheer = "rbxassetid://128777973",  -- R6 Wave  (eagle eye flourish)
	Jump  = "rbxassetid://125750702",  -- R6 Jump  (volley leap stance)
}

-- ═══════════════════════════════════════════════════════════
-- SKILL DEFINITIONS (Slots 1-4)
-- ═══════════════════════════════════════════════════════════

HunterSkills.Skills = {

	-- ═══════════════════════════════════════════════════════
	-- SLOT 1: Swift Arrow (Instant piercing shot)
	-- ═══════════════════════════════════════════════════════
	[1] = {
		id   = "SwiftArrow",
		name = "Swift Arrow",
		description = "Fire a piercing arrow in an instant. Crits reward extra Focus.",
		icon = "rbxassetid://0",
		slot = 1,

		resourceCost = 8,
		cooldown     = 3,

		skillType = "Projectile_Pierce",
		element   = "None",

		-- Instant
		castTime         = 0,
		lockMovement     = false,
		lockSkills       = false,
		lockAttack       = false,
		canBeInterrupted = false,

		-- Damage
		damageMultiplier = 1.2,

		-- Pierce
		maxHits         = 3,
		damageReduction = 0.20,   -- −20 % per additional target

		-- Animation
		animation         = ANIM.Draw,
		animationDuration = 0.35,

		-- Visual
		debugColor = Color3.fromRGB(180, 230, 100),

		effects = {},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 2: Barrage (5 rapid arrows, successive-hit scaling)
	--
	--   Fires 5 arrows forward in rapid succession.
	--   Base damage is the same per arrow.
	--   If the same mob is hit by successive arrows, each earlier hit
	--   on that mob adds +successiveHitScaling× (linear, 0.25 below):
	--       Hit 1 = 1.0×  |  Hit 2 = 1.25×  |  Hit 3 = 1.5×
	--       Hit 4 = 1.75× |  Hit 5 = 2.0×
	-- ═══════════════════════════════════════════════════════
	[2] = {
		id   = "Barrage",
		name = "Barrage",
		description = "Unleash a rapid volley of five arrows. Each successive hit on the same target deals escalating damage.",
		icon = "rbxassetid://0",
		slot = 2,

		resourceCost = 16,          -- §30.3
		cooldown     = 8,

		skillType = "Projectile_Burst",
		element   = "None",

		-- Instant start
		castTime         = 0,
		lockMovement     = false,
		lockSkills       = true,       -- can't use other skills mid-burst
		lockAttack       = true,
		canBeInterrupted = false,

		-- Per-arrow damage (before successive-hit scaling)
		damageMultiplier = 0.5,

		-- Burst config
		arrowCount            = 5,
		arrowDelay            = 0.12,          -- seconds between arrows
		successiveHitScaling  = 0.25,          -- §31: cap same-target at ~2.0x

		-- Each arrow uses a narrow rectangle for hit detection
		shape      = "Rectangle",
		shapeParams = {
			range = 50,
			width = 3,
		},

		-- Animation
		animation         = ANIM.Draw,
		animationDuration = 0.6,   -- covers full burst duration

		-- Visual
		debugColor = Color3.fromRGB(255, 180, 50),

		effects = {},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 3: Rain of Arrows (forward-cast rectangle, 2 waves)
	-- ═══════════════════════════════════════════════════════
	[3] = {
		id   = "RainOfArrows",
		name = "Rain of Arrows",
		description = "Lock on to a target area and unleash a volley of arrows that fall over a wide zone.",
		icon = "rbxassetid://0",
		slot = 3,

		resourceCost = 22,          -- §30.3
		cooldown     = 14,

		skillType    = "AreaEffect",
		element      = "Wood",             -- Rain of Arrows channels natural energy
		-- §LD-SK1: forward cast (see Arcanist FrostBind comment).
		targetMode   = "Forward",
		maxRange     = 50,
		castDistance = 26,

		-- Channel
		castTime         = 1.2,
		lockMovement     = true,
		lockSkills       = true,
		lockAttack       = true,
		canBeInterrupted = false,

		-- Per-wave damage
		damageMultiplier = 0.8,
		hitWaves         = 2,
		waveDelay        = 0.25,

		-- Shape (rectangle centred on target position)
		shape      = "Rectangle",
		shapeParams = {
			range = 30,
			width = 12,
		},

		-- Animation
		animation         = ANIM.Draw,
		animationDuration = 1.2,

		-- Visual
		debugColor = Color3.fromRGB(100, 200, 50),

		effects = {},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 4 ★ ULTIMATE: Eagle Eye
	--
	--   Consumes ALL Killer Instinct (min 100).
	--   Buff for 6 seconds:
	--       • +CritChance  = resourceUsed × critPerResource
	--       • −AttackSpeed  = attackSpeedPenalty %
	--
	--   Configurable constants for tuning:
	--       critPerResource      0.5  (100 Killer Instinct → +50 % crit)
	--       attackSpeedPenalty   30   (−30 % attack speed)
	--       buffDuration         default 6 s
	-- ═══════════════════════════════════════════════════════
	[4] = {
		id   = "EagleEye",
		name = "Eagle Eye",
		description = "Enter a hyper-focused state. Your critical hits become devastating, but your attack speed is reduced.",
		icon = "rbxassetid://0",
		slot = 4,

		-- Ultimate resource rules
		usesAllResource = true,
		minimumResource = 100,      -- §30.3: all, min 100
		resourceCost    = 0,
		cooldown        = 75,       -- §30.3

		-- Ultimate flags
		isUltimate  = true,
		unlockLevel = 30,

		skillType = "Buff",
		element   = "None",

		-- Instant activation
		castTime         = 0,
		lockMovement     = false,
		lockSkills       = false,
		lockAttack       = false,
		canBeInterrupted = false,

		-- No damage
		damageMultiplier = 0,

		-- Scaling constants (tune these for balance)
		critPerResource     = 0.5,         -- CritChance bonus = resource × this
		attackSpeedPenalty   = 30,          -- §31: reduce to -30%
		buffDuration         = 6,

		-- Animation
		animation         = ANIM.Cheer,
		animationDuration = 0.5,

		-- Visual
		debugColor = Color3.fromRGB(255, 215, 0),

		effects = {},   -- built dynamically
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 5: Fast Steps (Dash)
	-- ═══════════════════════════════════════════════════════
	[5] = {
		id = "FastSteps",
		name = "Fast Steps",
		description = "Dart forward with blinding speed, the shortest cooldown of all dashes.",
		skillType = "Dash",
		slot = 5,
		cooldown = 5,           -- §30.3
		resourceCost = 8,
		castTime = 0,
		dashDistance = 22,
		dashDuration = 0.2,
		unstoppable = false,
		fallbackDirection = Vector3.new(0, 0, -1),
		debugColor = Color3.fromRGB(80, 200, 80),
		visualId = "Dash",
	},
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function HunterSkills.Init(baseSkills, skillEffects)
	Base    = baseSkills
	Effects = skillEffects
	baseSkills.InjectGetters(HunterSkills)
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 5: FAST STEPS (Dash)
-- ═══════════════════════════════════════════════════════════

function HunterSkills.FastStepsExec(player, skill, inputData)
	return BaseSkills.ExecuteDash(player, skill, inputData)
end

-- ═══════════════════════════════════════════════════════════
-- MAIN EXECUTE
-- ═══════════════════════════════════════════════════════════

function HunterSkills.Execute(player, skill, inputData)
	local id = skill.id

	if id == "SwiftArrow" then
		return HunterSkills.SwiftArrowExec(player, skill, inputData)

	elseif id == "Barrage" then
		return HunterSkills.BarrageExec(player, skill, inputData)

	elseif id == "RainOfArrows" then
		return HunterSkills.RainOfArrowsExec(player, skill, inputData)

	elseif id == "EagleEye" then
		return HunterSkills.EagleEyeExec(player, skill, inputData)

	elseif id == "FastSteps" then
		return HunterSkills.FastStepsExec(player, skill, inputData)

	else
		warn("[HunterSkills] Unknown skill:", id)
		return false
	end
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 1: SWIFT ARROW
-- ═══════════════════════════════════════════════════════════

function HunterSkills.SwiftArrowExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position

	-- Prefer client's authoritative look direction (already flat/normalised by SkillInput)
	-- Falls back to server rootPart LookVector if not provided
	-- §T2/Z3: client-look preferred, server fallback, NaN-proof.
	local direction = Base.GetCastDirection(rootPart, inputData)

	-- Visual
	Base.SendVisualToAll("Projectile", {
		skillId   = skill.id,
		playerId  = player.UserId,
		startPos  = origin,
		direction = direction,
		speed     = 60,
		lifetime  = 3,
		color     = skill.debugColor,
	})

	-- Narrow rectangle for pierce hit detection
	local targets = Base.GetTargetsInShape(origin, direction, {
		shape      = "Rectangle",
		shapeParams = { range = 60, width = 2 },
	})

	local maxHits   = skill.maxHits or 1
	local reduction = skill.damageReduction or 0
	local hitCount  = 0

	for _, mob in ipairs(targets) do
		if hitCount >= maxHits then break end
		local mult = skill.damageMultiplier * ((1 - reduction) ^ hitCount)
		Base.DamageMob(mob, player, mult, skill.id, skill.element)
		hitCount = hitCount + 1
	end

	-- §T2/Z6: no telemetry print (log spam).
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 2: BARRAGE  (5 rapid arrows, successive-hit scaling)
-- ═══════════════════════════════════════════════════════════

function HunterSkills.BarrageExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position

	-- Prefer client's authoritative look direction
	-- §T2/Z3: client-look preferred, server fallback, NaN-proof.
	local direction = Base.GetCastDirection(rootPart, inputData)

	local arrowCount = skill.arrowCount or 5
	local arrowDelay = skill.arrowDelay or 0.12
	local scaling    = skill.successiveHitScaling or 0.3

	-- Track how many times each mob has been hit (for scaling)
	local hitTracker = {}   -- { [mob] = hitsSoFar }

	-- Visual (burst)
	Base.SendVisualToAll("Barrage", {
		skillId    = skill.id,
		playerId   = player.UserId,
		origin     = origin,
		direction  = direction,
		arrowCount = arrowCount,
		arrowDelay = arrowDelay,
		color      = skill.debugColor,
	})

	for i = 1, arrowCount do
		task.delay((i - 1) * arrowDelay, function()
			local rp = Base.GetPlayerRootPart(player)
			if not rp then return end

			local arrowOrigin = rp.Position

			-- Find targets in narrow lane
			local targets = Base.GetTargetsInShape(arrowOrigin, direction, skill)

			-- Hit first target in line (single target per arrow)
			if #targets > 0 then
				local mob = targets[1]
				local prevHits = hitTracker[mob] or 0
				local mult     = skill.damageMultiplier * (1 + prevHits * scaling)

				Base.DamageMob(mob, player, mult, skill.id, skill.element)
				hitTracker[mob] = prevHits + 1
			end
		end)
	end

	-- Unlock skills/attack after burst completes
	task.delay(arrowCount * arrowDelay + 0.1, function()
		player:SetAttribute("CastingLockSkills", false)
		player:SetAttribute("CastingLockAttack", false)
	end)

	-- §T2/Z6: no telemetry print (log spam).
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 3: RAIN OF ARROWS  (forward-cast, 2 waves)
-- ═══════════════════════════════════════════════════════════

function HunterSkills.RainOfArrowsExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local playerPos = rootPart.Position

	-- §LD-SK1: deterministic forward cast (see BaseSkills.GetForwardCastPosition).
	local targetPos = Base.GetForwardCastPosition(player, skill, inputData)

	-- Capture player facing at cast time for shape orientation
	-- §T2/Z3: server-look on purpose (shape orientation, not aim).
	local direction = Base.GetCastDirection(rootPart)

	-- Visual
	Base.SendVisualToAll("RainOfArrows", {
		skillId  = skill.id,
		playerId = player.UserId,
		origin   = targetPos,
		range    = skill.shapeParams.range,
		width    = skill.shapeParams.width,
		waves    = skill.hitWaves,
		color    = skill.debugColor,
	})

	local waves = skill.hitWaves or 2
	for wave = 1, waves do
		task.delay((wave - 1) * (skill.waveDelay or 0.25), function()
			-- Hit targets at the target position (not player position)
			local targets = Base.GetTargetsInShape(targetPos, direction, skill)
			local hits    = Base.DamageTargets(targets, player, skill.damageMultiplier, skill.id, skill.element)
			-- §T2/Z6: no telemetry print (log spam).
		end)
	end

	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 4 ★ ULTIMATE: EAGLE EYE
-- ═══════════════════════════════════════════════════════════

function HunterSkills.EagleEyeExec(player, skill, inputData)
	-- Resource consumed
	local resourceUsed = (inputData and inputData.resourceUsed) or skill.minimumResource

	local critBonus    = resourceUsed * (skill.critPerResource or 0.5)
	local atkPenalty   = skill.attackSpeedPenalty or 40
	local dur          = skill.buffDuration or 6

	-- §T2/Z6: no telemetry print (log spam).

	-- Apply Crit Chance buff
	Effects.ApplyEffect(player, {
		type     = "CritChanceUp",
		target   = "Self",
		amount   = critBonus,
		duration = dur,
	}, Vector3.zero)

	-- Apply Attack Speed penalty
	Effects.ApplyEffect(player, {
		type     = "AttackSpeedDown",
		target   = "Self",
		amount   = atkPenalty,
		duration = dur,
	}, Vector3.zero)

	-- Visual
	Base.SendVisualToAll("EagleEye", {
		skillId      = skill.id,
		playerId     = player.UserId,
		critBonus    = critBonus,
		atkPenalty   = atkPenalty,
		duration     = dur,
		resourceUsed = resourceUsed,
		color        = skill.debugColor,
	})

	return true
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function HunterSkills.GetDebugInfo()
	local ids = {}
	for _, skill in pairs(HunterSkills.Skills) do
		table.insert(ids, skill.id)
	end
	return { class = HunterSkills.CLASS, skillCount = HunterSkills.GetSkillCount(), skills = ids }
end

return HunterSkills
