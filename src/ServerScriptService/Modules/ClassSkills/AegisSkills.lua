-- ServerScriptService/Modules/ClassSkills/AegisSkills

local AegisSkills = {}

local Base = nil
local Effects = nil

-- ═══════════════════════════════════════════════════════════
-- CLASS IDENTIFIER
-- ═══════════════════════════════════════════════════════════

AegisSkills.CLASS = "Aegis"

-- ═══════════════════════════════════════════════════════════
-- ANIMATIONS
-- ═══════════════════════════════════════════════════════════

local ANIM = {
	Slash = "rbxassetid://522635514",
	Stomp = "rbxassetid://507771019",
	Cheer = "rbxassetid://507770677",
	Lunge = "rbxassetid://522638767",
}

-- ═══════════════════════════════════════════════════════════
-- SKILL DEFINITIONS (Slots 1-4)
-- ═══════════════════════════════════════════════════════════

AegisSkills.Skills = {

	-- ═══════════════════════════════════════════════════════
	-- SLOT 1: Shield Boomerang (Projectile - no cast time)
	-- ═══════════════════════════════════════════════════════
	[1] = {
		id = "ShieldBoomerang",
		name = "Shield Boomerang",
		description = "Hurl your shield forward, damaging enemies on the way out and back.",
		icon = "rbxassetid://0",
		slot = 1,

		resourceCost = 0,
		cooldown = 2,

		skillType = "Projectile_Boomerang",
		element = "None",		-- Assign element here (Wood/Earth/Water/Fire/None)
		castTime = 0,
		lockMovement = false,
		lockSkills = false,
		lockAttack = false,
		canBeInterrupted = false,

		-- Damage (two passes!)
		outgoingMultiplier = 1.0,
		returningMultiplier = 0.75,

		-- Projectile shape (can be modified by talents)
		baseRange = 25,          -- Talent: "Further Throw" +5 range
		baseWidth = 6,           -- Talent: "Bigger Shield" +2 width

		-- Current values (modified by talents in future)
		shape = "Rectangle",
		shapeParams = {
			range = 25,
			width = 6,
		},

		-- Timing
		travelTime = 0.4,
		returnDelay = 0.1,

		-- Animation
		animation = ANIM.Slash,
		animationDuration = 0.5,

		-- Visual
		debugColor = Color3.fromRGB(100, 150, 255),

		effects = {},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 2: Taunt (Cast time - locked in place)
	-- ═══════════════════════════════════════════════════════
	[2] = {
		id = "Taunt",
		name = "Taunt",
		description = "Stomp the ground, pulling nearby enemies and forcing distant ones to target you.",
		icon = "rbxassetid://0",
		slot = 2,

		resourceCost = 0,
		cooldown = 3,

		skillType = "AreaEffect",
		element = "None",		-- Assign element here (Wood/Earth/Water/Fire/None)
		lockMovement = true,
		lockSkills = true,
		lockAttack = true,
		canBeInterrupted = false,  -- OFF for now

		-- Damage
		damageMultiplier = 0.5,

		-- Shape
		shape = "Circle",
		shapeParams = {
			range = 12,
		},

		-- Animation
		animation = ANIM.Stomp,
		animationDuration = 0.6,

		-- Visual
		debugColor = Color3.fromRGB(255, 200, 50),

		effects = {
			{
				type = "Pull",
				range = 12,
				strength = 20,
			},
			{
				type = "Taunt",
				range = 25,
				duration = 5,
			},
		},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 3: Battle Beast (Cast time - locked in place)
	-- ═══════════════════════════════════════════════════════
	[3] = {
		id = "BattleBeast",
		name = "Battle Beast",
		description = "Enter a defensive stance. Reduce damage taken and protect allies behind you.",
		icon = "rbxassetid://0",
		slot = 3,

		resourceCost = 0,
		cooldown = 5,

		skillType = "Buff",
		element = "None",		-- Assign element here (Wood/Earth/Water/Fire/None)
		lockMovement = true,
		lockSkills = true,
		lockAttack = true,
		canBeInterrupted = false,  -- OFF for now

		-- No damage
		damageMultiplier = 0,

		shape = nil,
		shapeParams = {},

		-- Animation
		animation = ANIM.Cheer,
		animationDuration = 0.8,

		-- Visual
		debugColor = Color3.fromRGB(50, 255, 50),

		effects = {
			{
				type = "DamageReduction",
				target = "Self",
				amount = 80,
				duration = 4,
			},
			{
				type = "DamageReduction",
				target = "AlliesBehind",
				amount = 100,
				duration = 4,
				shape = "Cone",
				shapeParams = {
					range = 15,
					angle = 120,
				},
				direction = "Behind",
			},
		},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 4: Rush (No cast time - instant dash)
	-- ═══════════════════════════════════════════════════════
	[4] = {
		id = "Rush_Aegis",
		name = "Rush",
		description = "Dash quickly in your movement direction. Toward the base if standing still.",
		icon = "rbxassetid://0",
		slot = 4,

		resourceCost = 0,
		cooldown = 1,

		skillType = "Dash",
		element = "None",		-- Assign element here (Wood/Earth/Water/Fire/None)

		-- No cast time (instant)
		castTime = 0,
		lockMovement = false,
		lockSkills = false,
		lockAttack = false,
		canBeInterrupted = false,

		-- No damage
		damageMultiplier = 0,

		-- Dash params
		dashDistance = 15,
		dashDuration = 0.2,
		directionMode = "Movement",
		fallbackDirection = Vector3.new(-1, 0, 0),

		-- Animation
		animation = ANIM.Lunge,
		animationDuration = 0.3,

		-- Visual
		debugColor = Color3.fromRGB(255, 100, 100),

		effects = {},

		unstoppable = true,
	},
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function AegisSkills.Init(baseSkills, skillEffects)
	Base = baseSkills
	Effects = skillEffects

	print("[AegisSkills] Initialized with", AegisSkills.GetSkillCount(), "skills")
end

-- ═══════════════════════════════════════════════════════════
-- SKILL GETTERS
-- ═══════════════════════════════════════════════════════════

function AegisSkills.GetSkillBySlot(slot)
	return AegisSkills.Skills[slot]
end

function AegisSkills.GetSkillById(skillId)
	for slot, skill in pairs(AegisSkills.Skills) do
		if skill.id == skillId then
			return skill
		end
	end
	return nil
end

function AegisSkills.GetAllSkills()
	return AegisSkills.Skills
end

function AegisSkills.GetSkillCount()
	local count = 0
	for _ in pairs(AegisSkills.Skills) do
		count = count + 1
	end
	return count
end

-- ═══════════════════════════════════════════════════════════
-- MAIN EXECUTE (Called AFTER cast time completes)
-- ═══════════════════════════════════════════════════════════

function AegisSkills.Execute(player, skill, inputData)
	local skillId = skill.id

	if skillId == "ShieldBoomerang" then
		return AegisSkills.ShieldBoomerang(player, skill, inputData)

	elseif skillId == "Taunt" then
		return AegisSkills.Taunt(player, skill, inputData)

	elseif skillId == "BattleBeast" then
		return AegisSkills.BattleBeast(player, skill, inputData)

	elseif skillId == "Rush_Aegis" then
		return AegisSkills.Rush(player, skill, inputData)

	else
		warn("[AegisSkills] Unknown skill:", skillId)
		return false
	end
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 1: SHIELD BOOMERANG (Projectile)
-- ═══════════════════════════════════════════════════════════

function AegisSkills.ShieldBoomerang(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position
	local direction = Vector3.new(1, 0, 0)

	local range = skill.shapeParams.range
	local width = skill.shapeParams.width

	-- Send visual
	Base.SendVisualToAll("Boomerang", {
		skillId = skill.id,
		playerId = player.UserId,
		startPos = origin,
		direction = direction,
		range = range,
		width = width,
		travelTime = skill.travelTime,
		returnDelay = skill.returnDelay,
		color = skill.debugColor,
	})

	-- PASS 1: Outgoing (multiplier, not flat damage!)
	local outgoingTargets = Base.GetTargetsInShape(origin, direction, skill)
	local hitCount = Base.DamageTargets(outgoingTargets, player, skill.outgoingMultiplier, skill.id)
	print("[AegisSkills] Shield Boomerang OUT - Hits:", hitCount)

	-- PASS 2: Returning (delayed)
	task.delay(skill.travelTime + (skill.returnDelay or 0), function()
		local newRootPart = Base.GetPlayerRootPart(player)
		if not newRootPart then return end

		local returnOrigin = newRootPart.Position
		local returningTargets = Base.GetTargetsInShape(returnOrigin, direction, skill)
		local returnHits = Base.DamageTargets(returningTargets, player, skill.returningMultiplier, skill.id .. "_return")
		print("[AegisSkills] Shield Boomerang BACK - Hits:", returnHits)
	end)

	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 2: TAUNT
-- ═══════════════════════════════════════════════════════════

function AegisSkills.Taunt(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position

	-- Send visual
	Base.SendVisualToAll("Taunt", {
		skillId = skill.id,
		playerId = player.UserId,
		origin = origin,
		range = skill.shapeParams.range,
		color = skill.debugColor,
	})

	-- Damage in shape
	if skill.damageMultiplier and skill.damageMultiplier > 0 then
		local targets = Base.GetTargetsInCircle(origin, skill.shapeParams.range)
		local hitCount = Base.DamageTargets(targets, player, skill.damageMultiplier, skill.id)
		print("[AegisSkills] Taunt - Hits:", hitCount)
	end

	-- Apply effects (Pull + Taunt)
	Effects.ApplyEffects(player, skill.effects, origin)

	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 3: BATTLE BEAST
-- ═══════════════════════════════════════════════════════════

function AegisSkills.BattleBeast(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position

	print("[AegisSkills] Battle Beast - Applying defensive buffs")

	-- Apply each effect
	for _, effect in ipairs(skill.effects or {}) do
		Effects.ApplyEffect(player, effect, origin)
	end

	-- Send visual
	Base.SendVisualToAll("Buff", {
		skillId = skill.id,
		playerId = player.UserId,
		origin = origin,
		duration = 4,
		color = skill.debugColor,
	})

	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 4: RUSH
-- ═══════════════════════════════════════════════════════════

function AegisSkills.Rush(player, skill, inputData)
	return Base.ExecuteDash(player, skill, inputData)
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function AegisSkills.GetDebugInfo()
	local skillIds = {}
	for slot, skill in pairs(AegisSkills.Skills) do
		table.insert(skillIds, skill.id)
	end

	return {
		class = AegisSkills.CLASS,
		skillCount = AegisSkills.GetSkillCount(),
		skills = skillIds,
	}
end

return AegisSkills