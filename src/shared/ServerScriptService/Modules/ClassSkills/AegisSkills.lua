-- ServerScriptService/Modules/ClassSkills/AegisSkills
--[[
    Aegis Skill Layout
    ══════════════════
    Slot 1 — Shield Boomerang   Projectile (boomerang, hits twice)
    Slot 2 — Taunt              AoE pull + forced aggro
    Slot 3 — Sundering Strikes  Stacking DpS debuff + armor shred
    Slot 4 — Battle Beast  ★ULT Massive damage reduction (self + allies behind)
                                Uses ALL Determination (min 100). Scales with amount.
]]

local AegisSkills = {}

local BaseSkills = require(script.Parent:WaitForChild("BaseSkills"))
local Base    = nil
local Effects = nil

-- ═══════════════════════════════════════════════════════════
-- CLASS IDENTIFIER
-- ═══════════════════════════════════════════════════════════

AegisSkills.CLASS = "Aegis"

-- ═══════════════════════════════════════════════════════════
-- ANIMATIONS
-- ═══════════════════════════════════════════════════════════

-- R6 Animate-script IDs (guaranteed visible on R6 rigs).
local ANIM = {
	Slash = "rbxassetid://128777973",  -- R6 Wave  (arm swing)
	Stomp = "rbxassetid://125750702",  -- R6 Jump  (AoE slam)
	Cheer = "rbxassetid://128777973",  -- R6 Wave  (buff raise)
	Lunge = "rbxassetid://128777973",  -- R6 Wave  (shield throw)
}

-- ═══════════════════════════════════════════════════════════
-- SKILL DEFINITIONS (Slots 1-4)
-- ═══════════════════════════════════════════════════════════

AegisSkills.Skills = {

	-- ═══════════════════════════════════════════════════════
	-- SLOT 1: Shield Boomerang (Projectile — no cast time)
	-- ═══════════════════════════════════════════════════════
	[1] = {
		id   = "ShieldBoomerang",
		name = "Shield Boomerang",
		description = "Hurl your shield forward, damaging enemies on the way out and back.",
		icon = "rbxassetid://0",
		slot = 1,

		resourceCost = 8,           -- §30.1
		cooldown     = 6,

		skillType = "Projectile_Boomerang",
		element   = "None",

		castTime         = 0,
		lockMovement     = false,
		lockSkills       = false,
		lockAttack       = false,
		canBeInterrupted = false,

		-- Damage (two passes)
		outgoingMultiplier  = 1.0,
		returningMultiplier = 0.7,   -- §31: keep near 0.7x return

		-- Shape
		baseRange = 25,
		baseWidth = 6,
		shape      = "Rectangle",
		shapeParams = {
			range = 25,
			width = 6,
		},

		-- Timing
		travelTime  = 0.4,
		returnDelay = 0.1,

		-- Animation
		animation         = ANIM.Slash,
		animationDuration = 0.5,

		-- Visual
		debugColor = Color3.fromRGB(100, 150, 255),

		effects = {},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 2: Taunt (Cast time — locked in place)
	-- ═══════════════════════════════════════════════════════
	[2] = {
		id   = "Taunt",
		name = "Taunt",
		description = "Stomp the ground, pulling nearby enemies and forcing distant ones to target you.",
		icon = "rbxassetid://0",
		slot = 2,

		resourceCost = 20,          -- §30.1
		cooldown     = 12,          -- §30.1

		skillType = "AreaEffect",
		element   = "None",

		castTime         = 0.5,
		lockMovement     = true,
		lockSkills       = true,
		lockAttack       = true,
		canBeInterrupted = false,

		-- Damage
		damageMultiplier = 0.45,    -- §31: 0.4x-0.5x

		-- Shape
		shape      = "Circle",
		shapeParams = {
			range = 12,
		},

		-- Animation
		animation         = ANIM.Stomp,
		animationDuration = 0.6,

		-- Visual
		debugColor = Color3.fromRGB(255, 200, 50),

		effects = {
			{
				type         = "Pull",
				range        = 12,
				flatStrength = 20,
			},
			{
				type     = "Taunt",
				range    = 25,
				duration = 5,
			},
		},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 3: Sundering Strikes (Stacking debuff — DpS + Armor Shred)
	--
	--   Each use applies 1 stack (max 5) to all mobs in melee cone.
	--   Per stack:
	--       • 0.1 × player Damage dealt as DpS (every 1 s)
	--       • −5 % mob Armor
	--   Stacks refresh the full duration on reapplication.
	-- ═══════════════════════════════════════════════════════
	[3] = {
		id   = "SunderingStrikes",
		name = "Sundering Strikes",
		description = "Rend your foes with a vicious strike. Each application stacks a bleed and shreds armor (max 5).",
		icon = "rbxassetid://0",
		slot = 3,

		resourceCost = 16,          -- §30.1
		cooldown     = 6,           -- §30.1

		skillType = "AreaEffect",
		element   = "None",

		castTime         = 0.3,
		lockMovement     = false,
		lockSkills       = false,
		lockAttack       = false,
		canBeInterrupted = false,

		-- Light impact damage on application
		damageMultiplier = 0.35,    -- §31: 0.35x upfront

		-- Melee cone (same as basic attack shape)
		shape      = "Cone",
		shapeParams = {
			range = 10,
			angle = 120,
		},

		-- Animation
		animation         = ANIM.Slash,
		animationDuration = 0.4,

		-- Visual
		debugColor = Color3.fromRGB(200, 60, 60),

		-- Stacking debuff data (consumed by execution code)
		effects = {
			{
				type            = "DamagePerSecond",
				damagePerTick   = 0.1,      -- ×0.1 of player Damage per tick per stack
				tickInterval    = 1,
				duration        = 6,
				stackable       = true,
				maxStacks       = 5,
				refreshDuration = true,
			},
			{
				type            = "ArmorReduction",
				amountPerStack  = 5,        -- −5 % Armor per stack
				duration        = 6,
				stackable       = true,
				maxStacks       = 5,
				refreshDuration = true,
			},
		},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 4 ★ ULTIMATE: Battle Beast
	--
	--   Consumes ALL Determination (minimum 100).
	--   Grants damage reduction to self and all allies behind.
	--
	--   Self DR formula (diminishing returns):
	--       DR% = ResourceUsed / (ResourceUsed + K) × 100
	--       100 res → 50 %  |  200 → 66.7 %  |  500 → 83.3 %
	--
	--   Allies behind: allyDrFraction (70 %) of self DR per BALANCE_NUMBERS,
	--   but BattleBeastExec currently applies a flat 100 % instead.
	--   Duration: 6 seconds (fixed).
	--
	--   Unlocks at level 30.
	-- ═══════════════════════════════════════════════════════
	[4] = {
		id   = "BattleBeast",
		name = "Battle Beast",
		description = "Channel all your Determination into an unbreakable defensive stance, shielding yourself and every ally behind you.",
		icon = "rbxassetid://0",
		slot = 4,

		-- Ultimate resource rules
		usesAllResource  = true,
		minimumResource  = 100,         -- §30.1: all, min 100
		resourceCost     = 0,           -- overridden by usesAllResource
		cooldown         = 75,          -- §30.1

		-- Ultimate flags
		isUltimate  = true,
		unlockLevel = 30,

		skillType = "Buff",
		element   = "None",

		castTime         = 1.0,
		lockMovement     = true,
		lockSkills       = true,
		lockAttack       = true,
		canBeInterrupted = false,

		-- No direct damage
		damageMultiplier = 0,

		-- Scaling constants (used by execution code)
		drFormulaK       = 100,         -- DR% = R / (R + K) × 100
		allyDrFraction   = 0.70,        -- allies' share of self DR (computed, not applied: see BattleBeastExec)
		buffDuration     = 6,

		-- Ally detection cone (behind the Aegis)
		allyConeRange = 20,
		allyConeAngle = 120,

		-- Animation
		animation         = ANIM.Cheer,
		animationDuration = 1.0,

		-- Visual
		debugColor = Color3.fromRGB(50, 255, 50),

		effects = {},   -- built dynamically based on resource spent
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 5: Rush (Dash)
	-- ═══════════════════════════════════════════════════════
	[5] = {
		id = "Rush",
		name = "Rush",
		description = "Charge forward with your shield, becoming unstoppable.",
		skillType = "Dash",
		slot = 5,
		cooldown = 5,
		resourceCost = 8,           -- §30.1
		castTime = 0,
		dashDistance = 18,
		dashDuration = 0.25,
		unstoppable = true,
		fallbackDirection = Vector3.new(0, 0, -1),
		debugColor = Color3.fromRGB(80, 120, 200),
		visualId = "Dash",
	},
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function AegisSkills.Init(baseSkills, skillEffects)
	Base    = baseSkills
	Effects = skillEffects
	baseSkills.InjectGetters(AegisSkills)
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 5: RUSH (Dash)
-- ═══════════════════════════════════════════════════════════

function AegisSkills.RushExec(player, skill, inputData)
	return BaseSkills.ExecuteDash(player, skill, inputData)
end

-- ═══════════════════════════════════════════════════════════
-- MAIN EXECUTE  (called AFTER cast time completes)
-- ═══════════════════════════════════════════════════════════

function AegisSkills.Execute(player, skill, inputData)
	local id = skill.id

	if id == "ShieldBoomerang" then
		return AegisSkills.ShieldBoomerang(player, skill, inputData)

	elseif id == "Taunt" then
		return AegisSkills.Taunt(player, skill, inputData)

	elseif id == "SunderingStrikes" then
		return AegisSkills.SunderingStrikesExec(player, skill, inputData)

	elseif id == "BattleBeast" then
		return AegisSkills.BattleBeastExec(player, skill, inputData)

	elseif id == "Rush" then
		return AegisSkills.RushExec(player, skill, inputData)

	else
		warn("[AegisSkills] Unknown skill:", id)
		return false
	end
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 1: SHIELD BOOMERANG
-- ═══════════════════════════════════════════════════════════

function AegisSkills.ShieldBoomerang(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin    = rootPart.Position
	-- §T2/Z3: server-authoritative aim (no inputData on purpose — see
	-- BaseSkills.GetCastDirection doc).
	local direction = Base.GetCastDirection(rootPart)

	Base.SendVisualToAll("Boomerang", {
		skillId   = skill.id,
		playerId  = player.UserId,
		startPos  = origin,
		direction = direction,
		range     = skill.shapeParams.range,
		width     = skill.shapeParams.width,
		travelTime = skill.travelTime,
		returnDelay = skill.returnDelay,
		color     = skill.debugColor,
	})

	-- PASS 1: Outgoing
	local outTargets = Base.GetTargetsInShape(origin, direction, skill)
	local hitCount   = Base.DamageTargets(outTargets, player, skill.outgoingMultiplier, skill.id, skill.element)
	-- §T2/Z6: no telemetry print (log spam).

	-- PASS 2: Returning (delayed)
	task.delay(skill.travelTime + (skill.returnDelay or 0), function()
		local rp = Base.GetPlayerRootPart(player)
		if not rp then return end
		local retTargets = Base.GetTargetsInShape(rp.Position, direction, skill)
		local retHits    = Base.DamageTargets(retTargets, player, skill.returningMultiplier, skill.id .. "_return", skill.element)
		-- §T2/Z6: no telemetry print (log spam).
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

	Base.SendVisualToAll("Taunt", {
		skillId  = skill.id,
		playerId = player.UserId,
		origin   = origin,
		range    = skill.shapeParams.range,
		effects  = skill.effects,
		color    = skill.debugColor,
	})

	-- Damage
	if skill.damageMultiplier and skill.damageMultiplier > 0 then
		local targets = Base.GetTargetsInCircle(origin, skill.shapeParams.range)
		Base.DamageTargets(targets, player, skill.damageMultiplier, skill.id, skill.element)
	end

	-- Scale Taunt duration by TauntDuration bonus
	local tauntDurationBonus = 0
	if BaseSkills.StatsManager then
		tauntDurationBonus = BaseSkills.StatsManager.GetBonus(player, "TauntDuration") or 0
		-- §AGX/X11: Last Bastion +20% while Determination > 70% (pre-cost value).
		local KR = BaseSkills.StatsManager.KeystoneRules
		if KR then
			tauntDurationBonus = tauntDurationBonus + KR.TauntDurationBonus(player, skill.resourceCost or 0)
		end
	end
	local scaledEffects = skill.effects
	if tauntDurationBonus ~= 0 then
		scaledEffects = {}
		for i, effect in ipairs(skill.effects) do
			if effect.type == "Taunt" then
				local copy = {}
				for k, v in pairs(effect) do copy[k] = v end
				copy.duration = effect.duration * (1 + tauntDurationBonus / 100)
				scaledEffects[i] = copy
			else
				scaledEffects[i] = effect
			end
		end
	end

	-- Effects (Pull + Taunt)
	Effects.ApplyEffects(player, scaledEffects, origin)

	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 3: SUNDERING STRIKES
-- ═══════════════════════════════════════════════════════════

function AegisSkills.SunderingStrikesExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin    = rootPart.Position
	-- §T2/Z3: server-authoritative aim (no inputData on purpose — see
	-- BaseSkills.GetCastDirection doc).
	local direction = Base.GetCastDirection(rootPart)

	-- Visual
	Base.SendVisualToAll("SunderingStrikes", {
		skillId  = skill.id,
		playerId = player.UserId,
		origin   = origin,
		range    = skill.shapeParams.range,
		angle    = skill.shapeParams.angle,
		color    = skill.debugColor,
	})

	-- Hit mobs in cone
	local targets = Base.GetTargetsInShape(origin, direction, skill)

	-- Apply initial damage
	Base.DamageTargets(targets, player, skill.damageMultiplier, skill.id, skill.element)

	-- Apply stacking debuff effects to each mob
	Effects.ApplyStackingEffects(player, skill.effects, targets)

	-- §T2/Z6: no telemetry print (log spam).
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 4 ★ ULTIMATE: BATTLE BEAST
-- ═══════════════════════════════════════════════════════════

function AegisSkills.BattleBeastExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position

	-- Resource consumed (passed by SkillManager via inputData)
	local resourceUsed = (inputData and inputData.resourceUsed) or skill.minimumResource

	-- ── Diminishing-returns formula ──
	-- DR% = ResourceUsed / (ResourceUsed + K) × 100
	local K      = skill.drFormulaK or 100
	local selfDR = (resourceUsed / (resourceUsed + K)) * 100
	local allyDR = selfDR * (skill.allyDrFraction or 0.70)
	local dur    = skill.buffDuration or 6

	-- Allies always receive 100% DR (full protection — no cap applies to ultimates)
	local allyFullDR = 100

	-- §T2/Z6: no telemetry print (log spam).

	-- Apply self DR buff via the UNCAPPED path (bypasses the 75% stat cap)
	Effects.ApplyEffect(player, {
		type     = "UncappedDamageReduction",
		target   = "Self",
		amount   = selfDR,
		duration = dur,
	}, origin)

	-- Find allies in cone behind (use the player's actual facing direction, negated)
	local lookFlat = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
	local behindDir
	if lookFlat.Magnitude > 0.01 then
		behindDir = -lookFlat.Unit
	else
		behindDir = Vector3.new(-1, 0, 0) -- fallback for purely vertical edge case
	end
	local allies = Base.GetAlliesInShape(player, "Cone", {
		origin    = origin,
		direction = behindDir,
		range     = skill.allyConeRange or 20,
		angle     = skill.allyConeAngle or 120,
	})

	for _, allyPlayer in ipairs(allies) do
		-- Allies receive full 100% damage reduction — uncapped, no stat cap applied
		Effects.ApplyEffect(allyPlayer, {
			type     = "UncappedDamageReduction",
			target   = "Self",
			amount   = allyFullDR,
			duration = dur,
		}, origin)
	end

	-- Visual
	Base.SendVisualToAll("BattleBeast", {
		skillId           = skill.id,
		playerId          = player.UserId,
		origin            = origin,
		selfDR            = selfDR,
		allyDR            = allyFullDR,
		duration          = dur,
		resourceUsed      = resourceUsed,
		color             = skill.debugColor,
		animation         = skill.animation,
		animationDuration = skill.animationDuration,
	})

	return true
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function AegisSkills.GetDebugInfo()
	local ids = {}
	for _, skill in pairs(AegisSkills.Skills) do
		table.insert(ids, skill.id)
	end
	return { class = AegisSkills.CLASS, skillCount = AegisSkills.GetSkillCount(), skills = ids }
end

return AegisSkills