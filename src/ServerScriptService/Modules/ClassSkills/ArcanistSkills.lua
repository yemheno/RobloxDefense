-- ServerScriptService/Modules/ClassSkills/ArcanistSkills

local ArcanistSkills = {}

local Base    = nil
local Effects = nil

-- ═══════════════════════════════════════════════════════════
-- CLASS IDENTIFIER
-- ═══════════════════════════════════════════════════════════

ArcanistSkills.CLASS = "Arcanist"

-- ═══════════════════════════════════════════════════════════
-- ANIMATIONS
-- ═══════════════════════════════════════════════════════════

local ANIM = {
	Cast    = "rbxassetid://522638767",  -- Lunge (casting motion)
	Channel = "rbxassetid://507770677",  -- Cheer (channeling stance)
	Blink   = "rbxassetid://522635514",  -- Slash (blink flash)
	Stomp   = "rbxassetid://507771019",  -- Stomp (frost slam)
}

-- ═══════════════════════════════════════════════════════════
-- SKILL DEFINITIONS (Slots 1-4)
-- ═══════════════════════════════════════════════════════════

ArcanistSkills.Skills = {

	-- ═══════════════════════════════════════════════════════
	-- SLOT 1: Arcane Bolt (Fast AoE projectile)
	-- ═══════════════════════════════════════════════════════
	[1] = {
		id   = "ArcaneBolt",
		name = "Arcane Bolt",
		description = "Launch a bolt of pure arcane energy that detonates on contact.",
		icon = "rbxassetid://0",
		slot = 1,

		resourceCost = 15,
		cooldown     = 2,

		skillType = "Projectile_AoE",
		element   = "None",   -- Assign weapon element or choose here

		-- Short cast (Arcanist's bread-and-butter, not instant)
		castTime         = 0.3,
		lockMovement     = false,
		lockSkills       = false,
		lockAttack       = false,
		canBeInterrupted = false,

		-- Damage
		damageMultiplier  = 1.1,
		primaryMultiplier = 1.5,   -- Direct hit bonus

		-- Explosion shape
		shape      = "Circle",
		shapeParams = {
			range = 6,
		},

		-- Projectile travel
		projectileSpeed   = 40,
		projectileLifetime = 4,

		-- Animation
		animation         = ANIM.Cast,
		animationDuration = 0.4,

		-- Visual
		debugColor = Color3.fromRGB(100, 80, 230),

		effects = {},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 2: Frost Bind (Slow + DoT AoE)
	-- ═══════════════════════════════════════════════════════
	[2] = {
		id   = "FrostBind",
		name = "Frost Bind",
		description = "Conjure a glacial field that slows enemies and deals sustained frost damage.",
		icon = "rbxassetid://0",
		slot = 2,

		resourceCost = 30,
		cooldown     = 10,

		skillType = "AreaEffect",
		element   = "Water",   -- Frost = Water element

		castTime         = 0.6,
		lockMovement     = true,
		lockSkills       = true,
		lockAttack       = true,
		canBeInterrupted = false,

		-- Initial impact damage
		damageMultiplier = 0.6,

		-- Shape
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
				type    = "Slow",
				amount  = 50,    -- 50% movement speed reduction
				duration = 3,
				range   = 14,
			},
			{
				type     = "DamageOverTime",
				damagePerTick = 0.15,  -- 15% of initial hit per tick
				tickInterval = 1,
				duration = 3,
				range    = 14,
			},
		},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 3: Arcane Surge (Channeled massive blast)
	-- ═══════════════════════════════════════════════════════
	[3] = {
		id   = "ArcaneSurge",
		name = "Arcane Surge",
		description = "Channel all arcane power into a devastating explosion that obliterates everything in front of you.",
		icon = "rbxassetid://0",
		slot = 3,

		resourceCost = 60,
		cooldown     = 18,

		skillType = "AreaEffect",
		element   = "Fire",   -- Surge generates intense heat

		-- Long channel — huge reward for completing it
		castTime         = 2.0,
		lockMovement     = true,
		lockSkills       = true,
		lockAttack       = true,
		canBeInterrupted = false,

		-- Heavy damage
		damageMultiplier = 3.5,

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
	-- SLOT 4: Blink (Short-range teleport)
	-- ═══════════════════════════════════════════════════════
	[4] = {
		id   = "Blink",
		name = "Blink",
		description = "Rip through space to teleport a short distance instantly.",
		icon = "rbxassetid://0",
		slot = 4,

		resourceCost = 20,
		cooldown     = 7,

		skillType = "Dash",
		element   = "None",

		-- Instant
		castTime         = 0,
		lockMovement     = false,
		lockSkills       = false,
		lockAttack       = false,
		canBeInterrupted = false,

		-- No damage
		damageMultiplier = 0,

		-- Blink is a teleport (instant, same direction as movement)
		dashDistance  = 20,
		dashDuration  = 0.05,   -- Near-instant to feel like a teleport
		directionMode = "Movement",
		fallbackDirection = Vector3.new(1, 0, 0),

		-- Animation
		animation         = ANIM.Blink,
		animationDuration = 0.2,

		-- Visual
		debugColor = Color3.fromRGB(160, 60, 255),

		effects = {},

		unstoppable = true,
	},
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.Init(baseSkills, skillEffects)
	Base    = baseSkills
	Effects = skillEffects
	print("[ArcanistSkills] Initialized with", ArcanistSkills.GetSkillCount(), "skills")
end

-- ═══════════════════════════════════════════════════════════
-- SKILL GETTERS
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.GetSkillBySlot(slot)
	return ArcanistSkills.Skills[slot]
end

function ArcanistSkills.GetSkillById(skillId)
	for _, skill in pairs(ArcanistSkills.Skills) do
		if skill.id == skillId then return skill end
	end
	return nil
end

function ArcanistSkills.GetAllSkills()
	return ArcanistSkills.Skills
end

function ArcanistSkills.GetSkillCount()
	local count = 0
	for _ in pairs(ArcanistSkills.Skills) do count = count + 1 end
	return count
end

-- ═══════════════════════════════════════════════════════════
-- MAIN EXECUTE
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.Execute(player, skill, inputData)
	local id = skill.id

	if id == "ArcaneBolt" then
		return ArcanistSkills.ArcaneBolt(player, skill, inputData)

	elseif id == "FrostBind" then
		return ArcanistSkills.FrostBind(player, skill, inputData)

	elseif id == "ArcaneSurge" then
		return ArcanistSkills.ArcaneSurge(player, skill, inputData)

	elseif id == "Blink" then
		return ArcanistSkills.BlinkSkill(player, skill, inputData)

	else
		warn("[ArcanistSkills] Unknown skill:", id)
		return false
	end
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 1: ARCANE BOLT
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.ArcaneBolt(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin    = rootPart.Position
	local direction = Vector3.new(1, 0, 0)

	Base.SendVisualToAll("AoEProjectile", {
		skillId           = skill.id,
		playerId          = player.UserId,
		startPos          = origin,
		direction         = direction,
		speed             = skill.projectileSpeed or 40,
		lifetime          = skill.projectileLifetime or 4,
		explosionRange    = skill.shapeParams.range,
		color             = skill.debugColor,
	})

	-- Simulate projectile travel and detonation
	local travelTime = 20 / (skill.projectileSpeed or 40)   -- rough mid-range estimate
	task.delay(travelTime, function()
		local rp = Base.GetPlayerRootPart(player)
		local detonatePos = rp and rp.Position + direction * 20 or origin + direction * 20

		local targets = Base.GetTargetsInShape(detonatePos, direction, skill)
		local hits    = Base.DamageTargets(targets, player, skill.damageMultiplier, skill.id, skill.element)
		print("[ArcanistSkills] Arcane Bolt detonated — Hits:", hits)
	end)

	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 2: FROST BIND
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.FrostBind(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position

	Base.SendVisualToAll("FrostField", {
		skillId  = skill.id,
		playerId = player.UserId,
		origin   = origin,
		range    = skill.shapeParams.range,
		duration = 3,
		color    = skill.debugColor,
	})

	local targets = Base.GetTargetsInShape(origin, Vector3.new(1, 0, 0), skill)
	local hits    = Base.DamageTargets(targets, player, skill.damageMultiplier, skill.id, skill.element)

	Effects.ApplyEffects(player, skill.effects, origin)

	print("[ArcanistSkills] Frost Bind — Hits:", hits)
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 3: ARCANE SURGE
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.ArcaneSurge(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin    = rootPart.Position
	local direction = Vector3.new(1, 0, 0)

	Base.SendVisualToAll("ArcaneSurge", {
		skillId  = skill.id,
		playerId = player.UserId,
		origin   = origin,
		range    = skill.shapeParams.range,
		angle    = skill.shapeParams.angle,
		color    = skill.debugColor,
	})

	local targets = Base.GetTargetsInShape(origin, direction, skill)
	local hits    = Base.DamageTargets(targets, player, skill.damageMultiplier, skill.id, skill.element)

	Effects.ApplyEffects(player, skill.effects, origin)

	print("[ArcanistSkills] Arcane Surge — Hits:", hits)
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 4: BLINK
-- ═══════════════════════════════════════════════════════════

function ArcanistSkills.BlinkSkill(player, skill, inputData)
	return Base.ExecuteDash(player, skill, inputData)
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
