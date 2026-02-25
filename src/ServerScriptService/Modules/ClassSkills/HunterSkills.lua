-- ServerScriptService/Modules/ClassSkills/HunterSkills

local HunterSkills = {}

local Base    = nil
local Effects = nil

-- ═══════════════════════════════════════════════════════════
-- CLASS IDENTIFIER
-- ═══════════════════════════════════════════════════════════

HunterSkills.CLASS = "Hunter"

-- ═══════════════════════════════════════════════════════════
-- ANIMATIONS
-- ═══════════════════════════════════════════════════════════

local ANIM = {
	Draw   = "rbxassetid://522638767",  -- Lunge (draw bow)
	Roll   = "rbxassetid://522635514",  -- Slash (repurpose for roll)
	Cheer  = "rbxassetid://507770677",  -- Cheer (mark flourish)
	Jump   = "rbxassetid://507771019",  -- Stomp (leap landing)
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

		resourceCost = 10,
		cooldown     = 1.5,

		skillType = "Projectile_Pierce",
		element   = "None",   -- Inherits weapon element (ShortBow, etc.)

		-- Instant: no lock
		castTime         = 0,
		lockMovement     = false,
		lockSkills       = false,
		lockAttack       = false,
		canBeInterrupted = false,

		-- Damage
		damageMultiplier = 1.2,

		-- Projectile (inherits class projectile config)
		maxHits         = 3,     -- Pierce through up to 3 targets
		damageReduction = 0.20,  -- -20% per additional target hit

		-- Animation
		animation         = ANIM.Draw,
		animationDuration = 0.35,

		-- Visual
		debugColor = Color3.fromRGB(180, 230, 100),

		effects = {},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 2: Hunter's Mark (Debuff area)
	-- ═══════════════════════════════════════════════════════
	[2] = {
		id   = "HuntersMark",
		name = "Hunter's Mark",
		description = "Mark all enemies in the area. Marked enemies receive 35% more damage from all sources.",
		icon = "rbxassetid://0",
		slot = 2,

		resourceCost = 20,
		cooldown     = 8,

		skillType = "AreaEffect",
		element   = "None",

		-- Short cast
		castTime         = 0.3,
		lockMovement     = false,
		lockSkills       = false,
		lockAttack       = false,
		canBeInterrupted = false,

		-- No direct damage — only applies the debuff
		damageMultiplier = 0,

		-- Shape
		shape      = "Circle",
		shapeParams = {
			range = 20,
		},

		-- Animation
		animation         = ANIM.Cheer,
		animationDuration = 0.4,

		-- Visual
		debugColor = Color3.fromRGB(255, 160, 40),

		effects = {
			{
				type     = "Mark",
				bonusDamagePercent = 35,
				duration = 8,
				range    = 20,
			},
		},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 3: Rain of Arrows (AoE overhead volley)
	-- ═══════════════════════════════════════════════════════
	[3] = {
		id   = "RainOfArrows",
		name = "Rain of Arrows",
		description = "Lock on and unleash a volley of arrows that fall over a wide area.",
		icon = "rbxassetid://0",
		slot = 3,

		resourceCost = 40,
		cooldown     = 12,

		skillType = "AreaEffect",
		element   = "Wood",   -- Rain of Arrows channels natural energy

		-- Cast time (channel with locked stance)
		castTime         = 1.2,
		lockMovement     = true,
		lockSkills       = true,
		lockAttack       = true,
		canBeInterrupted = false,

		-- Damage (hits multiple times — each wave reduced for balance)
		damageMultiplier = 0.8,
		hitWaves         = 3,
		waveDelay        = 0.2,

		-- Shape: large rectangle (volley lane)
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
	-- SLOT 4: Leap Back (Backward dash for distance)
	-- ═══════════════════════════════════════════════════════
	[4] = {
		id   = "LeapBack",
		name = "Leap Back",
		description = "Propel yourself backward to create distance from enemies.",
		icon = "rbxassetid://0",
		slot = 4,

		resourceCost = 15,
		cooldown     = 6,

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

		-- Dash (opposite to movement / always backward)
		dashDistance   = 18,
		dashDuration   = 0.25,
		directionMode  = "Backward",   -- Always leap away from the mob lane
		fallbackDirection = Vector3.new(-1, 0, 0),

		-- Animation
		animation         = ANIM.Jump,
		animationDuration = 0.35,

		-- Visual
		debugColor = Color3.fromRGB(180, 180, 255),

		effects = {},

		unstoppable = true,
	},
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function HunterSkills.Init(baseSkills, skillEffects)
	Base    = baseSkills
	Effects = skillEffects
	print("[HunterSkills] Initialized with", HunterSkills.GetSkillCount(), "skills")
end

-- ═══════════════════════════════════════════════════════════
-- SKILL GETTERS
-- ═══════════════════════════════════════════════════════════

function HunterSkills.GetSkillBySlot(slot)
	return HunterSkills.Skills[slot]
end

function HunterSkills.GetSkillById(skillId)
	for _, skill in pairs(HunterSkills.Skills) do
		if skill.id == skillId then return skill end
	end
	return nil
end

function HunterSkills.GetAllSkills()
	return HunterSkills.Skills
end

function HunterSkills.GetSkillCount()
	local count = 0
	for _ in pairs(HunterSkills.Skills) do count = count + 1 end
	return count
end

-- ═══════════════════════════════════════════════════════════
-- MAIN EXECUTE
-- ═══════════════════════════════════════════════════════════

function HunterSkills.Execute(player, skill, inputData)
	local id = skill.id

	if id == "SwiftArrow" then
		return HunterSkills.SwiftArrow(player, skill, inputData)

	elseif id == "HuntersMark" then
		return HunterSkills.HuntersMark(player, skill, inputData)

	elseif id == "RainOfArrows" then
		return HunterSkills.RainOfArrows(player, skill, inputData)

	elseif id == "LeapBack" then
		return HunterSkills.LeapBack(player, skill, inputData)

	else
		warn("[HunterSkills] Unknown skill:", id)
		return false
	end
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 1: SWIFT ARROW
-- ═══════════════════════════════════════════════════════════

function HunterSkills.SwiftArrow(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin    = rootPart.Position
	local direction = Vector3.new(1, 0, 0)

	Base.SendVisualToAll("Projectile", {
		skillId   = skill.id,
		playerId  = player.UserId,
		startPos  = origin,
		direction = direction,
		speed     = 60,
		lifetime  = 3,
		color     = skill.debugColor,
	})

	local targets = Base.GetTargetsInShape(origin, direction, {
		shape      = "Rectangle",
		shapeParams = { range = 60, width = 2 },
	})

	local maxHits    = skill.maxHits or 1
	local reduction  = skill.damageReduction or 0
	local hitCount   = 0

	for _, mob in ipairs(targets) do
		if hitCount >= maxHits then break end
		local mult = skill.damageMultiplier * ((1 - reduction) ^ hitCount)
		Base.DamageMob(mob, player, mult, skill.id, skill.element)
		hitCount = hitCount + 1
	end

	print("[HunterSkills] Swift Arrow — Hits:", hitCount)
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 2: HUNTER'S MARK
-- ═══════════════════════════════════════════════════════════

function HunterSkills.HuntersMark(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position

	Base.SendVisualToAll("AreaMark", {
		skillId  = skill.id,
		playerId = player.UserId,
		origin   = origin,
		range    = skill.shapeParams.range,
		duration = 8,
		color    = skill.debugColor,
	})

	Effects.ApplyEffects(player, skill.effects, origin)

	print("[HunterSkills] Hunter's Mark — Applied in range", skill.shapeParams.range)
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 3: RAIN OF ARROWS
-- ═══════════════════════════════════════════════════════════

function HunterSkills.RainOfArrows(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin    = rootPart.Position
	local direction = Vector3.new(1, 0, 0)

	Base.SendVisualToAll("RainOfArrows", {
		skillId  = skill.id,
		playerId = player.UserId,
		origin   = origin,
		range    = skill.shapeParams.range,
		width    = skill.shapeParams.width,
		waves    = skill.hitWaves,
		color    = skill.debugColor,
	})

	local waves = skill.hitWaves or 1
	for wave = 1, waves do
		task.delay((wave - 1) * (skill.waveDelay or 0.2), function()
			local rp = Base.GetPlayerRootPart(player)
			if not rp then return end

			local targets = Base.GetTargetsInShape(rp.Position, direction, skill)
			local hits    = Base.DamageTargets(targets, player, skill.damageMultiplier, skill.id, skill.element)
			print("[HunterSkills] Rain of Arrows wave", wave, "— Hits:", hits)
		end)
	end

	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 4: LEAP BACK
-- ═══════════════════════════════════════════════════════════

function HunterSkills.LeapBack(player, skill, inputData)
	return Base.ExecuteDash(player, skill, inputData)
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
