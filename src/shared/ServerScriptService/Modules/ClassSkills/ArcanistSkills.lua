-- ServerScriptService/Modules/ClassSkills/ArcanistSkills
--[[
    Arcanist Skill Layout
    ═════════════════════
    Slot 1 — Arcane Beam       Line / laser instant damage
    Slot 2 — Frost Bind        Mouse-targeted AoE: Slow + DpS
    Slot 3 — Arcane Surge      Channelled massive cone blast + knockback
    Slot 4 — Meteorite    ★ULT Two-element strike (Fire + Earth),
                                vulnerability debuff, resource-scaled damage.
                                Uses ALL Aether (min 100).
]]

local ArcanistSkills = {}

local BaseSkills = require(script.Parent:WaitForChild("BaseSkills"))
local Base    = nil
local Effects = nil

-- ═══════════════════════════════════════════════════════════
-- CLASS IDENTIFIER
-- ═══════════════════════════════════════════════════════════

ArcanistSkills.CLASS = "Arcanist"

-- ═══════════════════════════════════════════════════════════
-- ANIMATIONS
-- ═══════════════════════════════════════════════════════════

-- R6 Animate-script IDs (guaranteed visible on R6 rigs).
local ANIM = {
	Cast    = "rbxassetid://128853357",  -- R6 Point (arm extend = casting)
	Channel = "rbxassetid://128777973",  -- R6 Wave  (arm motion = channeling)
	Stomp   = "rbxassetid://125750702",  -- R6 Jump  (body slam = frost slam)
	Slash   = "rbxassetid://128777973",  -- R6 Wave  (sweep gesture)
}

-- ═══════════════════════════════════════════════════════════
-- SKILL DEFINITIONS (Slots 1-4)
-- ═══════════════════════════════════════════════════════════

ArcanistSkills.Skills = {

	-- ═══════════════════════════════════════════════════════
	-- SLOT 1: Arcane Beam (Line / laser — instant damage)
	-- ═══════════════════════════════════════════════════════
	[1] = {
		id   = "ArcaneBeam",
		name = "Arcane Beam",
		description = "Fire a beam of concentrated arcane energy in a straight line, scorching all enemies in its path.",
		icon = "rbxassetid://0",
		slot = 1,

		resourceCost = 12,          -- §30.2
		cooldown     = 4,

		skillType = "AreaEffect",          -- line damage, not a projectile
		element   = "None",

		castTime         = 0.3,
		lockMovement     = false,
		lockSkills       = false,
		lockAttack       = false,
		canBeInterrupted = false,

		-- Damage
		damageMultiplier = 1.2,

		-- Line shape (narrow rectangle stretching forward)
		shape      = "Rectangle",
		shapeParams = {
			range = 40,
			width = 4,
		},

		-- Animation
		animation         = ANIM.Cast,
		animationDuration = 0.4,

		-- Visual
		debugColor = Color3.fromRGB(100, 80, 230),

		effects = {},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 2: Frost Bind (forward-cast AoE — Slow + DpS)
	--
	--   Lands castDistance ahead of the caster (§LD-SK1).
	--   Initial impact damage + lingering effects:
	--       • −50 % movement speed for 3 s
	--       • 0.15 × player Damage per second for 3 s (tick every 1 s)
	-- ═══════════════════════════════════════════════════════
	[2] = {
		id   = "FrostBind",
		name = "Frost Bind",
		description = "Conjure a glacial field at the target location that slows enemies and deals sustained frost damage.",
		icon = "rbxassetid://0",
		slot = 2,

		resourceCost = 20,          -- §30.2
		cooldown     = 12,          -- §30.2

		skillType    = "AreaEffect",
		element      = "Water",            -- Frost = Water element
		-- §LD-SK1: "Forward" = land at a fixed distance ahead of the
		-- caster's facing direction (works on every input device);
		-- mirrored on client.
		targetMode   = "Forward",
		maxRange     = 40,                 -- studs from player (sanity cap)
		castDistance = 20,                 -- where the AoE actually lands

		castTime         = 0.6,
		lockMovement     = true,
		lockSkills       = true,
		lockAttack       = true,
		canBeInterrupted = false,

		-- Initial impact damage
		damageMultiplier = 0.5,     -- §31: utility first, 0.5x upfront

		-- Shape (centred on target position)
		shape      = "Circle",
		shapeParams = {
			range = 14,
		},

		-- Animation
		animation         = ANIM.Stomp,
		animationDuration = 0.6,

		-- Visual
		debugColor = Color3.fromRGB(100, 200, 255),

		effects = {
			{
				type     = "Slow",
				amount   = 50,             -- −50 % move speed
				duration = 3,
			},
			{
				type          = "DamagePerSecond",
				damagePerTick = 0.15,      -- ×0.15 of player Damage per tick
				tickInterval  = 1,
				duration      = 3,
			},
		},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 3: Arcane Surge (Channelled massive blast)
	-- ═══════════════════════════════════════════════════════
	[3] = {
		id   = "ArcaneSurge",
		name = "Arcane Surge",
		description = "Channel all arcane power into a devastating explosion that obliterates everything in front of you.",
		icon = "rbxassetid://0",
		slot = 3,

		resourceCost = 30,          -- §30.2
		cooldown     = 16,

		skillType = "AreaEffect",
		element   = "Fire",                -- Surge generates intense heat

		-- Long channel — huge reward for completing it
		castTime         = 2.0,
		lockMovement     = true,
		lockSkills       = true,
		lockAttack       = true,
		canBeInterrupted = false,

		-- Heavy damage
		damageMultiplier = 3.0,     -- §31: reduce to 3.0x

		-- Large cone
		shape      = "Cone",
		shapeParams = {
			range = 30,
			angle = 90,
		},

		-- Animation
		animation         = ANIM.Channel,
		animationDuration = 2.0,

		-- Visual
		debugColor = Color3.fromRGB(220, 80, 255),

		effects = {
			{
				type     = "Knockback",
				strength = 30,
				range    = 30,
			},
		},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 4 ★ ULTIMATE: Meteorite
	--
	--   Forward-cast AoE (§LD-SK1).
	--   Two separate damage instances: Fire then Earth.
	--   All mobs hit receive vulnerabilityMultiplier (1.25×) damage taken for 3 s.
	--   Damage scales linearly with Aether spent:
	--       hitMult = baseDamageMultiplier × (1 + resourceUsed / 100)
	--       100 Aether → 2× base  |  200 → 3× base  |  etc.
	--
	--   Uses ALL Aether (min 100). Level-gated by unlockLevel (BACKLOG §ULT-LEVEL).
	-- ═══════════════════════════════════════════════════════
	[4] = {
		id   = "Meteorite",
		name = "Meteorite",
		description = "Call down a cataclysmic meteor that strikes with fire and earth, leaving shattered foes vulnerable.",
		icon = "rbxassetid://0",
		slot = 4,

		-- Ultimate resource rules
		usesAllResource = true,
		minimumResource = 100,      -- §30.2: all, min 100
		resourceCost    = 0,
		cooldown        = 75,       -- §30.2

		-- Ultimate flags
		isUltimate  = true,
		unlockLevel = 30,

		skillType    = "AreaEffect",
		element      = "Fire",             -- primary element; Earth applied as second hit
		-- §LD-SK1: forward cast (see FrostBind comment).
		targetMode   = "Forward",
		maxRange     = 50,
		castDistance = 26,

		castTime         = 1.5,
		lockMovement     = true,
		lockSkills       = true,
		lockAttack       = true,
		canBeInterrupted = false,

		-- Base damage per element (scaled by resource in execution)
		baseDamageMultiplier = 1.0,        -- each element uses this as base
		resourceScalingDiv   = 100,        -- hitMult = base × (1 + R / div)

		-- Area (bigger than Frost Bind's 14)
		shape      = "Circle",
		shapeParams = {
			range = 20,
		},

		-- Vulnerability debuff applied to all targets hit
		vulnerabilityMultiplier = 1.25,    -- §31: +25% damage taken
		vulnerabilityDuration   = 3,

		-- Animation
		animation         = ANIM.Channel,
		animationDuration = 1.5,

		-- Visual
		debugColor = Color3.fromRGB(255, 120, 30),

		effects = {},   -- built dynamically
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 5: Space Jump (Dash)
	-- ═══════════════════════════════════════════════════════
	[5] = {
		id = "SpaceJump",
		name = "Space Jump",
		description = "Blink through space, covering a long distance in an instant.",
		skillType = "Dash",
		slot = 5,
		cooldown = 6,
		resourceCost = 10,          -- §30.2
		castTime = 0,
		dashDistance = 25,
		dashDuration = 0.15,
		unstoppable = false,
		fallbackDirection = Vector3.new(0, 0, -1),
		debugColor = Color3.fromRGB(160, 80, 220),
		visualId = "Dash",
	},
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.Init(baseSkills, skillEffects)
	Base    = baseSkills
	Effects = skillEffects
	baseSkills.InjectGetters(ArcanistSkills)
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 5: SPACE JUMP (Dash)
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.SpaceJumpExec(player, skill, inputData)
	return BaseSkills.ExecuteDash(player, skill, inputData)
end

-- ═══════════════════════════════════════════════════════════
-- MAIN EXECUTE
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.Execute(player, skill, inputData)
	local id = skill.id

	if id == "ArcaneBeam" then
		return ArcanistSkills.ArcaneBeamExec(player, skill, inputData)

	elseif id == "FrostBind" then
		return ArcanistSkills.FrostBindExec(player, skill, inputData)

	elseif id == "ArcaneSurge" then
		return ArcanistSkills.ArcaneSurgeExec(player, skill, inputData)

	elseif id == "Meteorite" then
		return ArcanistSkills.MeteoriteExec(player, skill, inputData)

	elseif id == "SpaceJump" then
		return ArcanistSkills.SpaceJumpExec(player, skill, inputData)

	else
		warn("[ArcanistSkills] Unknown skill:", id)
		return false
	end
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 1: ARCANE BEAM  (line / laser)
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.ArcaneBeamExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin    = rootPart.Position
	-- §T2/Z3: server-authoritative aim (no inputData on purpose — see
	-- BaseSkills.GetCastDirection doc).
	local direction = Base.GetCastDirection(rootPart)

	-- Visual
	Base.SendVisualToAll("ArcaneBeam", {
		skillId   = skill.id,
		playerId  = player.UserId,
		origin    = origin,
		direction = direction,
		range     = skill.shapeParams.range,
		width     = skill.shapeParams.width,
		color     = skill.debugColor,
	})

	-- Damage all mobs in line
	local targets = Base.GetTargetsInShape(origin, direction, skill)
	local hits    = Base.DamageTargets(targets, player, skill.damageMultiplier, skill.id, skill.element)

	-- §T2/Z6: no telemetry print (log spam).
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 2: FROST BIND  (forward-cast AoE + Slow + DpS)
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.FrostBindExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local playerPos = rootPart.Position

	-- §LD-SK1: deterministic forward cast: lands at a fixed distance ahead
	-- of the player, and the client's visual preview matches.
	local targetPos = Base.GetForwardCastPosition(player, skill, inputData)

	-- Visual
	Base.SendVisualToAll("FrostField", {
		skillId  = skill.id,
		playerId = player.UserId,
		origin   = targetPos,
		range    = skill.shapeParams.range,
		duration = 3,
		color    = skill.debugColor,
	})

	-- Initial impact damage at target location
	local targets = Base.GetTargetsInCircle(targetPos, skill.shapeParams.range)
	local hits    = Base.DamageTargets(targets, player, skill.damageMultiplier, skill.id, skill.element)

	-- Apply Slow + DpS to mobs in area
	Effects.ApplyEffectsToMobs(player, skill.effects, targets)

	-- §T2/Z6: no telemetry print (log spam).
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 3: ARCANE SURGE  (channelled cone blast)
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.ArcaneSurgeExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin    = rootPart.Position
	-- §T2/Z3: server-authoritative aim (no inputData on purpose — see
	-- BaseSkills.GetCastDirection doc).
	local direction = Base.GetCastDirection(rootPart)

	-- Visual
	Base.SendVisualToAll("ArcaneSurge", {
		skillId   = skill.id,
		playerId  = player.UserId,
		origin    = origin,
		direction = direction,
		range     = skill.shapeParams.range,
		angle     = skill.shapeParams.angle,
		color     = skill.debugColor,
	})

	-- Damage
	local targets = Base.GetTargetsInShape(origin, direction, skill)
	local hits    = Base.DamageTargets(targets, player, skill.damageMultiplier, skill.id, skill.element)

	-- Knockback
	Effects.ApplyEffects(player, skill.effects, origin)

	-- §T2/Z6: no telemetry print (log spam).
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 4 ★ ULTIMATE: METEORITE
-- ═══════════════════════════════════════════════════════════

-- §LD-SK1: forward cast, as Frost Bind.
function ArcanistSkills.MeteoriteExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local playerPos = rootPart.Position

	local targetPos = Base.GetForwardCastPosition(player, skill, inputData)

	-- Resource consumed
	local resourceUsed = (inputData and inputData.resourceUsed) or skill.minimumResource

	-- Scaled damage multiplier:  base × (1 + R / div)
	local base = skill.baseDamageMultiplier or 1.0
	local div  = skill.resourceScalingDiv or 100
	local scaledMult = base * (1 + resourceUsed / div)

	-- §T2/Z6: no telemetry print (log spam).

	-- Find targets once
	local targets = Base.GetTargetsInCircle(targetPos, skill.shapeParams.range)

	-- Hit 1: Fire damage
	Base.DamageTargets(targets, player, scaledMult, skill.id .. "_Fire", "Fire")

	-- Hit 2: Earth damage (slight delay for feel)
	task.delay(0.15, function()
		-- Re-fetch alive targets
		local aliveTargets = Base.GetTargetsInCircle(targetPos, skill.shapeParams.range)
		Base.DamageTargets(aliveTargets, player, scaledMult, skill.id .. "_Earth", "Earth")
	end)

	-- Apply Vulnerability debuff to all targets hit
	local vulnEffect = {
		type                = "Vulnerability",
		damageMultiplier    = skill.vulnerabilityMultiplier or 1.5,
		duration            = skill.vulnerabilityDuration or 3,
	}
	Effects.ApplyEffectsToMobs(player, { vulnEffect }, targets)

	-- Visual
	Base.SendVisualToAll("Meteorite", {
		skillId      = skill.id,
		playerId     = player.UserId,
		origin       = targetPos,
		range        = skill.shapeParams.range,
		resourceUsed = resourceUsed,
		scaledMult   = scaledMult,
		color        = skill.debugColor,
	})

	return true
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.GetDebugInfo()
	local ids = {}
	for _, skill in pairs(ArcanistSkills.Skills) do
		table.insert(ids, skill.id)
	end
	return { class = ArcanistSkills.CLASS, skillCount = ArcanistSkills.GetSkillCount(), skills = ids }
end

return ArcanistSkills
