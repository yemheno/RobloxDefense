-- ServerScriptService/Modules/ClassSkills/LifeStewardSkills
--[[
    Life Steward Skill Layout
    ═════════════════════════
    Slot 1 — Mending Touch    Targeted heal on the ally with the lowest HP
    Slot 2 — Verdant Bloom    AoE heal around the caster
    Slot 3 — Nature's Purge   Cleanse 1 debuff from all party members
    Slot 4 — Genesis     ★ULT If a knocked-down ally is in range, revive them (70% HP).
                               Otherwise, heal the ally with the lowest HP to 100%.
                               Uses ALL Life Energy (min 100).
    Slot 5 — Vine Slide        Dash

    Element: Wood (nature theme)
]]

local LifeStewardSkills = {}

local BaseSkills = require(script.Parent:WaitForChild("BaseSkills"))
local Base    = nil
local Effects = nil

-- ═══════════════════════════════════════════════════════════
-- CLASS IDENTIFIER
-- ═══════════════════════════════════════════════════════════

LifeStewardSkills.CLASS = "LifeSteward"

-- ═══════════════════════════════════════════════════════════
-- ANIMATIONS (R6 placeholders — replace with custom later)
-- ═══════════════════════════════════════════════════════════

local ANIM = {
	Cast    = "rbxassetid://128853357",  -- R6 Point (arm extend = casting)
	Channel = "rbxassetid://128777973",  -- R6 Wave  (arm motion = channeling)
	Stomp   = "rbxassetid://125750702",  -- R6 Jump  (body motion = AoE burst)
}

-- ═══════════════════════════════════════════════════════════
-- SKILL DEFINITIONS
-- ═══════════════════════════════════════════════════════════

LifeStewardSkills.Skills = {

	-- ═══════════════════════════════════════════════════════
	-- SLOT 1: Mending Touch (targeted single heal)
	--
	--   Heals the ally with the LOWEST current HP percentage
	--   within range. If no allies are injured, heals self.
	--   healMultiplier × base healing output (from HealingSystem).
	-- ═══════════════════════════════════════════════════════
	[1] = {
		id   = "MendingTouch",
		name = "Mending Touch",
		description = "Channel nature's essence to restore vitality to the most wounded ally in range.",
		icon = "rbxassetid://0",
		slot = 1,

		resourceCost = 8,
		cooldown     = 3,

		skillType = "Heal",
		element   = "Wood",

		castTime         = 0.4,
		lockMovement     = false,
		lockSkills       = false,
		lockAttack       = false,
		canBeInterrupted = false,

		-- Healing
		healMultiplier = 2.2,     -- §31: 2.1x-2.3x
		canCrit        = true,

		-- Target finding
		healRange = 30,           -- studs

		-- Animation
		animation         = ANIM.Cast,
		animationDuration = 0.4,

		-- Visual
		debugColor = Color3.fromRGB(100, 220, 80),

		effects = {},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 2: Verdant Bloom (AoE heal around caster)
	--
	--   Heals ALL allies within a circle centred on the caster.
	--   Also applies a small HoT (Heal-over-Time) for 6 s.
	-- ═══════════════════════════════════════════════════════
	[2] = {
		id   = "VerdantBloom",
		name = "Verdant Bloom",
		description = "Call upon the forest's power to heal all nearby allies and leave a lingering regeneration.",
		icon = "rbxassetid://0",
		slot = 2,

		resourceCost = 18,         -- §30.4
		cooldown     = 8,

		skillType = "Heal",
		element   = "Wood",

		castTime         = 0.6,
		lockMovement     = true,
		lockSkills       = true,
		lockAttack       = true,
		canBeInterrupted = false,

		-- Healing (initial burst)
		healMultiplier = 1.3,      -- §31: 1.2x-1.4x
		canCrit        = true,

		-- AoE
		healRange = 20,            -- studs

		-- HoT follow-up
		hotHealing = {
			type          = "HealOverTime",
			id            = "VerdantBloom_HoT",
			healPerTick   = 0.08,  -- ×0.08 of healer's Damage per tick
			tickInterval  = 1,
			duration      = 6,
			maxStacks     = 2,
			range         = 20,
		},

		-- Animation
		animation         = ANIM.Stomp,
		animationDuration = 0.6,

		-- Visual
		debugColor = Color3.fromRGB(60, 200, 60),

		effects = {},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 3: Nature's Purge (party-wide debuff cleanse)
	--
	--   Removes ONE active debuff from every ally in range.
	--   Prioritises the most impactful debuff (Stun > Slow > DoT > etc.).
	--   Does NOT deal damage or heal (pure utility).
	-- ═══════════════════════════════════════════════════════
	[3] = {
		id   = "NaturesPurge",
		name = "Nature's Purge",
		description = "Purify the battlefield with nature's cleansing wind, removing harmful effects from all allies.",
		icon = "rbxassetid://0",
		slot = 3,

		resourceCost = 14,         -- §30.4
		cooldown     = 12,

		skillType = "Cleanse",
		element   = "Wood",

		castTime         = 0.5,
		lockMovement     = false,
		lockSkills       = true,
		lockAttack       = true,
		canBeInterrupted = false,

		-- Range
		cleanseRange = 25,

		-- Animation
		animation         = ANIM.Channel,
		animationDuration = 0.5,

		-- Visual
		debugColor = Color3.fromRGB(180, 255, 100),

		effects = {},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 4 ★ ULTIMATE: Genesis
	--
	--   Dual-purpose life saver:
	--   1. If a knocked-down ally is in range → revive them (70% HP, 20% resource)
	--   2. If nobody is knocked down → heal the lowest-HP ally to 100% HP
	--   Uses ALL Life Energy (min 100).
	-- ═══════════════════════════════════════════════════════
	[4] = {
		id   = "Genesis",
		name = "Genesis",
		description = "Channel the primal force of nature. Revives a fallen ally, or fully restores the most wounded one.",
		icon = "rbxassetid://0",
		slot = 4,

		-- Ultimate resource rules
		usesAllResource = true,
		minimumResource = 100,     -- §30.4: all, min 100
		resourceCost    = 0,
		cooldown        = 60,      -- §30.4 (was 90 — tightened per alpha balance pass)

		-- Ultimate flags
		isUltimate  = true,
		unlockLevel = 30,

		skillType = "Revival",   -- dual: revive if knocked-down, else full heal
		element   = "Wood",

		castTime         = 2.0,
		lockMovement     = true,
		lockSkills       = true,
		lockAttack       = true,
		canBeInterrupted = false,

		-- Revive params (base values — talents can override)
		reviveHealthPercent   = 0.70,   -- 70% of max HP
		reviveResourcePercent = 0.20,   -- 20% of max resource
		reviveRange           = 30,     -- studs

		-- Animation
		animation         = ANIM.Channel,
		animationDuration = 2.0,

		-- Visual
		debugColor = Color3.fromRGB(200, 255, 60),

		effects = {},
	},

	-- ═══════════════════════════════════════════════════════
	-- SLOT 5: Vine Slide (Dash)
	-- ═══════════════════════════════════════════════════════
	[5] = {
		id = "VineSlide",
		name = "Vine Slide",
		description = "Slide forward on a burst of vines, covering ground quickly.",
		skillType = "Dash",
		slot = 5,
		cooldown = 6,
		resourceCost = 8,           -- §30.4
		castTime = 0,
		dashDistance = 22,
		dashDuration = 0.15,
		unstoppable = false,
		fallbackDirection = Vector3.new(0, 0, -1),
		debugColor = Color3.fromRGB(80, 200, 80),
		visualId = "Dash",
	},
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function LifeStewardSkills.Init(baseSkills, skillEffects)
	Base    = baseSkills
	Effects = skillEffects
	baseSkills.InjectGetters(LifeStewardSkills)
	print("[LifeStewardSkills] Initialized with", LifeStewardSkills.GetSkillCount(), "skills")
end

-- ═══════════════════════════════════════════════════════════
-- MAIN EXECUTE (routes to per-skill handlers)
-- ═══════════════════════════════════════════════════════════

function LifeStewardSkills.Execute(player, skill, inputData)
	local id = skill.id

	if id == "MendingTouch" then
		return LifeStewardSkills.MendingTouchExec(player, skill, inputData)

	elseif id == "VerdantBloom" then
		return LifeStewardSkills.VerdantBloomExec(player, skill, inputData)

	elseif id == "NaturesPurge" then
		return LifeStewardSkills.NaturesPurgeExec(player, skill, inputData)

	elseif id == "Genesis" then
		return LifeStewardSkills.GenesisExec(player, skill, inputData)

	elseif id == "VineSlide" then
		return BaseSkills.ExecuteDash(player, skill, inputData)

	else
		warn("[LifeStewardSkills] Unknown skill:", id)
		return false
	end
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 1: MENDING TOUCH (targeted single heal)
--
-- Finds the ally with lowest HP% in range, heals them.
-- If no injured ally found, heals self.
-- ═══════════════════════════════════════════════════════════

function LifeStewardSkills.MendingTouchExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position
	local range  = skill.healRange or 30

	-- Find lowest-HP ally in range
	local target = LifeStewardSkills.FindLowestHPAlly(origin, range, player)

	-- Fallback to self if no injured ally
	if not target then
		target = player
	end

	-- Calculate heal
	local StatsManager = Base.SkillManager and Base.SkillManager.StatsManager
		or (Effects and Effects.StatsManager)
	if not StatsManager then
		warn("[LifeStewardSkills] StatsManager not available")
		return false
	end

	local healResult = StatsManager.CalculateHeal(player, {
		healMultiplier = skill.healMultiplier or 2.5,
		canCrit = skill.canCrit ~= false,
	})

	-- Apply heal via SkillEffects
	if Effects then
		Effects.HealPlayer(target, healResult.heal, player, healResult.wasCrit, healResult.critProcs)
	end

	-- Visual
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	Base.SendVisualToAll("HealSingle", {
		skillId   = skill.id,
		playerId  = player.UserId,
		targetId  = target.UserId,
		origin    = origin,
		targetPos = targetRoot and targetRoot.Position or origin,
		color     = skill.debugColor,
	})

	print("[LifeStewardSkills] Mending Touch — healed", target.Name, "for", math.floor(healResult.heal),
		healResult.wasCrit and "(CRIT)" or "")
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 2: VERDANT BLOOM (AoE heal + HoT)
-- ═══════════════════════════════════════════════════════════

function LifeStewardSkills.VerdantBloomExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position
	local range  = skill.healRange or 20

	-- Calculate heal
	local StatsManager = Base.SkillManager and Base.SkillManager.StatsManager
		or (Effects and Effects.StatsManager)
	if not StatsManager then return false end

	local healResult = StatsManager.CalculateHeal(player, {
		healMultiplier = skill.healMultiplier or 1.5,
		canCrit = skill.canCrit ~= false,
	})

	-- Apply heal to all allies (uses SkillEffects.GetAlliesInRange which includes self)
	if Effects then
		local allies = Effects.GetAlliesInRange(origin, range, player)
		for _, ally in ipairs(allies) do
			Effects.HealPlayer(ally, healResult.heal, player, healResult.wasCrit, healResult.critProcs)
		end

		-- Apply HoT follow-up
		if skill.hotHealing then
			Effects.ApplyHealOverTime(player, skill.hotHealing, origin)
		end

		print("[LifeStewardSkills] Verdant Bloom — healed", #allies, "allies")
	end

	-- Visual
	Base.SendVisualToAll("HealAoE", {
		skillId  = skill.id,
		playerId = player.UserId,
		origin   = origin,
		range    = range,
		color    = skill.debugColor,
	})

	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 3: NATURE'S PURGE (party-wide cleanse)
-- ═══════════════════════════════════════════════════════════

function LifeStewardSkills.NaturesPurgeExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position
	local range  = skill.cleanseRange or 25

	if not Effects then return false end

	local allies = Effects.GetAlliesInRange(origin, range, player)
	local cleansedCount = 0

	for _, ally in ipairs(allies) do
		local removed = Effects.CleansePlayerDebuff(ally)
		if removed then
			cleansedCount = cleansedCount + 1
		end
	end

	-- Visual
	Base.SendVisualToAll("Cleanse", {
		skillId  = skill.id,
		playerId = player.UserId,
		origin   = origin,
		range    = range,
		color    = skill.debugColor,
	})

	print("[LifeStewardSkills] Nature's Purge — cleansed", cleansedCount, "allies")
	return true
end

-- ═══════════════════════════════════════════════════════════
-- SKILL 4 ★ ULTIMATE: GENESIS (Dual-purpose life saver)
--
-- Priority 1: Revive the nearest knocked-down ally (70% HP, 20% resource)
-- Priority 2: If nobody knocked down, heal ally with lowest HP to 100%
-- ═══════════════════════════════════════════════════════════

function LifeStewardSkills.GenesisExec(player, skill, inputData)
	local rootPart = Base.GetPlayerRootPart(player)
	if not rootPart then return false end

	local origin = rootPart.Position
	local range  = skill.reviveRange or 30

	-- Try to find DeathSystem for revive priority
	local DeathSystem = nil
	local ok, ds = pcall(function()
		return require(script.Parent.Parent:WaitForChild("DeathSystem", 1))
	end)
	if ok then DeathSystem = ds end

	-- Priority 1: Revive a knocked-down ally
	if DeathSystem then
		local knockedTarget = LifeStewardSkills.FindNearestKnockedDown(origin, range, player, DeathSystem)
		if knockedTarget then
			local healthPct   = skill.reviveHealthPercent or 0.70
			local resourcePct = skill.reviveResourcePercent or 0.20

			local revived = DeathSystem.RevivePlayer(knockedTarget, healthPct, resourcePct)
			if revived then
				-- Grant weapon XP to the healer for performing the revive.
				local _wm = nil
				local wmMod = script.Parent.Parent:FindFirstChild("WeaponManager")
				if wmMod then
					local ok2, wm = pcall(require, wmMod)
					if ok2 then _wm = wm end
				end
				if _wm then _wm.GrantReviveXP(player) end

				-- Track revive for achievements.
				do
					local amMod = script.Parent.Parent:FindFirstChild("AchievementManager")
					if amMod then
						local ok3, am = pcall(require, amMod)
						if ok3 then am.OnReviveDone(player) end
					end
				end

				local targetRoot = knockedTarget.Character and knockedTarget.Character:FindFirstChild("HumanoidRootPart")
				Base.SendVisualToAll("Revive", {
					skillId   = skill.id,
					playerId  = player.UserId,
					targetId  = knockedTarget.UserId,
					origin    = origin,
					targetPos = targetRoot and targetRoot.Position or origin,
					color     = skill.debugColor,
				})

				print("[LifeStewardSkills] Genesis — REVIVED", knockedTarget.Name, "with",
					math.floor(healthPct * 100) .. "% HP,", math.floor(resourcePct * 100) .. "% resource")
				return true
			end
		end
	end

	-- Priority 2: Full heal the ally with the lowest HP
	local target = LifeStewardSkills.FindLowestHPAlly(origin, range, player)
	if not target then
		-- Fallback to self
		target = player
	end

	local targetChar = target.Character
	local targetHum  = targetChar and targetChar:FindFirstChild("Humanoid")
	if targetHum and targetHum.Health > 0 then
		local maxHP = targetHum.MaxHealth
		local missingHP = maxHP - targetHum.Health
		if missingHP > 0 then
			targetHum.Health = maxHP

			if Effects then
				-- Notify via heal visual
				Effects.HealPlayer(target, math.floor(missingHP), player, false, 0)
			end
		end

		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
		Base.SendVisualToAll("HealSingle", {
			skillId   = skill.id,
			playerId  = player.UserId,
			targetId  = target.UserId,
			origin    = origin,
			targetPos = targetRoot and targetRoot.Position or origin,
			color     = skill.debugColor,
			isGenesis = true,
		})

		print("[LifeStewardSkills] Genesis — FULL HEALED", target.Name, "to 100% HP")
		return true
	end

	warn("[LifeStewardSkills] Genesis — no valid target found")
	return false
end

-- ═══════════════════════════════════════════════════════════
-- HELPER: Find ally with lowest HP percentage in range
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")

function LifeStewardSkills.FindLowestHPAlly(origin, range, healer)
	local best = nil
	local bestPercent = 1.0  -- 100% — looking for lower

	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if not char then continue end
		local hum = char:FindFirstChild("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then continue end
		if (root.Position - origin).Magnitude > range then continue end

		local pct = hum.Health / math.max(hum.MaxHealth, 1)
		-- Only heal if actually injured
		if pct < 1.0 and pct < bestPercent then
			bestPercent = pct
			best = p
		end
	end

	return best
end

-- ═══════════════════════════════════════════════════════════
-- HELPER: Find nearest knocked-down ally in range
-- ═══════════════════════════════════════════════════════════

function LifeStewardSkills.FindNearestKnockedDown(origin, range, healer, DeathSystem)
	local best = nil
	local bestDist = math.huge

	for _, p in ipairs(Players:GetPlayers()) do
		if p == healer then continue end
		if not DeathSystem.IsKnockedDown(p) then continue end

		local char = p.Character
		if not char then continue end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		local dist = (root.Position - origin).Magnitude
		if dist <= range and dist < bestDist then
			bestDist = dist
			best = p
		end
	end

	return best
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function LifeStewardSkills.GetDebugInfo()
	local ids = {}
	for _, skill in pairs(LifeStewardSkills.Skills) do
		table.insert(ids, skill.id)
	end
	return { class = LifeStewardSkills.CLASS, skillCount = LifeStewardSkills.GetSkillCount(), skills = ids }
end

return LifeStewardSkills
