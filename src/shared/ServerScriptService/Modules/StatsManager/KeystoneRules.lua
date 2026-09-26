-- ServerScriptService/Modules/StatsManager/KeystoneRules
--[[
    §AGX/X11: gameplay code for the talent keystone rules.

    Every keystone node in TalentTreeConfig carries a `{ stat = "<Rule>",
    rule = true }` flag. TalentEffectAggregator stores those per player and
    answers HasRule(player, name). This module is the ONE place that asks
    it, from cheap hooks the combat pipeline calls:

      Hook (caller)                                  Rules
      ─────────────────────────────────────────────  ───────────────────────────
      OutgoingHit       (DamageSystem, per hit)      Overwhelm, CullTheWeak,
                                                     SecondHeart (−12%), RelentlessQuarry
      CritBonus         (CriticalSystem, per roll)   PerfectForm (damage AND heals)
      IncomingDR        (DamageSystem, per hit taken) UnyieldingAdvance, LastBastion
      AfterIncomingDamage (DamageSystem)             SecondHeart (trigger)
      ModifyLifesteal   (DamageHandler)              ClaritySurge (→0), SharedGrace (×0.5)
      OnCritSkillHit    (DamageHandler)              ClaritySurge (+4 Aether)
      OnHealCast        (LifeStewardSkills/SkillEffects) ClaritySurge (+8 Life Energy)
      OnOverheal        (SkillEffects.HealPlayer)    SharedGrace (20% of excess as 4 s HoT)
      TauntDurationBonus (AegisSkills Taunt)         LastBastion (+20%)
      sampler loop (5 Hz)                            PerfectForm stillness,
                                                     LastBastion low-Determination penalty

    Rules NOT here stay "(coming soon)" (TalentTreeConfig.IMPLEMENTED_RULES):
    ArcSaturation, EyeOfTheStorm (AoESize has no consumer), CalmUnderFire
    (CDR / StatusResistance / AttackSpeed have no consumer), SpellRhythm
    (description is self-contradictory), PatronSaint, FortuneFavors (need a
    party-aura system).

    Hot path (Audit_4.7 §5.4): HasRule and every sibling function are
    resolved ONCE and cached as function refs; per-hit work is table reads
    plus, only for players holding the rule, a Humanoid lookup on the target.
    All numbers below are the keystone descriptions verbatim.
]]

local KeystoneRules = {}

local Players = game:GetService("Players")

local Modules = script.Parent.Parent

-- ═══════════════════════════════════════════════════════════
-- TUNING  (straight from TalentTreeConfig descriptions)
-- ═══════════════════════════════════════════════════════════

local OVERWHELM_HP_ABOVE      = 0.70
local OVERWHELM_PEN           = 15
local OVERWHELM_DMG_PCT       = 10

local CULL_HP_BELOW           = 0.25
local CULL_DMG_PCT            = 15
local CULL_LIFESTEAL          = 2
local CULL_FULL_LIFE_DMG_PCT  = -5

local SECOND_HEART_THRESHOLD  = 0.35
local SECOND_HEART_ICD        = 45
local SECOND_HEART_HEAL_FRAC  = 0.08   -- of max HP, over…
local SECOND_HEART_TICKS      = 4      -- …4 ticks of 1 s
local SECOND_HEART_DMG_PCT    = -12    -- while the regen is active

local PERFECT_FORM_STILL      = 1.5    -- seconds stationary to arm
local PERFECT_FORM_SUPPRESS   = 2.0    -- seconds a movement burst locks it out
local PERFECT_FORM_CRIT       = 12
local PERFECT_FORM_CRIT_DMG   = 0.10

local UNYIELDING_RADIUS       = 10
local UNYIELDING_DR_PER_ENEMY = 1
local UNYIELDING_DR_MAX       = 10
local UNYIELDING_CACHE        = 0.25   -- s; the count is re-queried at most 4×/s

local BASTION_HIGH_PCT        = 70
local BASTION_LOW_PCT         = 20
local BASTION_DR              = 8
local BASTION_TAUNT_PCT       = 20
local BASTION_MOVE_PENALTY    = -10

local QUARRY_HITS             = 4
local QUARRY_WINDOW           = 3
local QUARRY_MARK             = 6
local QUARRY_CRIT             = 10
local QUARRY_PEN              = 10

local CLARITY_HEAL_LE         = 8
local CLARITY_SKILL_AETHER    = 4

local GRACE_EXCESS_FRAC       = 0.20
local GRACE_HOT_DURATION      = 4
local GRACE_LIFESTEAL_MULT    = 0.5

local SAMPLE_INTERVAL         = 0.2
local MOVE_EPS_SQ             = 0.5 * 0.5   -- studs² per sample (≈2.5 studs/s)

-- ═══════════════════════════════════════════════════════════
-- CACHED REFERENCES  (Audit_4.7 §5.4 — resolve once, keep the fn ref)
-- ═══════════════════════════════════════════════════════════

local _hasRule = nil  -- function | false
local function hasRule(player, ruleName)
	if _hasRule == nil then
		_hasRule = false
		local mod = Modules:FindFirstChild("TalentEffectAggregator")
		if mod then
			local ok, tea = pcall(require, mod)
			if ok and tea and type(tea.HasRule) == "function" then
				_hasRule = tea.HasRule
			end
		end
	end
	if _hasRule then return _hasRule(player, ruleName) end
	return false
end
KeystoneRules.HasRule = hasRule

local _rmResolved = false
local _rmGetName, _rmGet, _rmGetMax, _rmModify = nil, nil, nil, nil
local function resolveResourceManager()
	if _rmResolved then return _rmGetName ~= nil end
	_rmResolved = true
	local mod = Modules:FindFirstChild("ResourceManager")
	if mod then
		local ok, rm = pcall(require, mod)
		if ok and rm then
			_rmGetName = rm.GetResourceName
			_rmGet     = rm.GetResource
			_rmGetMax  = rm.GetMaxResource
			_rmModify  = rm.ModifyResource
		end
	end
	return _rmGetName ~= nil
end

--- Resource % (0–100) of `player` IF their class resource is `name`, else nil.
--- `pending` is added to the current value first (a cost just deducted).
local function resourcePctIf(player, name, pending)
	if not resolveResourceManager() then return nil end
	if _rmGetName(player) ~= name then return nil end
	local max = _rmGetMax(player)
	if not max or max <= 0 then return nil end
	return math.min(_rmGet(player) + (pending or 0), max) / max * 100
end

local function grantResourceIf(player, name, amount)
	if not resolveResourceManager() then return end
	if _rmGetName(player) == name then
		_rmModify(player, amount)
	end
end

local _circleQuery = nil  -- function | false
local function getCircleQuery()
	if _circleQuery == nil then
		_circleQuery = false
		local mod = Modules:FindFirstChild("AttackShapes")
		if mod then
			local ok, shapes = pcall(require, mod)
			if ok and shapes and shapes.GetTargetsInCircle then
				_circleQuery = shapes.GetTargetsInCircle
			end
		end
	end
	return _circleQuery or nil
end

-- SkillEffects is a leaf module (it never requires StatsManager), so a
-- lazy require here cannot cycle.
local _SkillEffects = nil  -- module | false
local function getSkillEffects()
	if _SkillEffects == nil then
		_SkillEffects = false
		local mod = Modules:FindFirstChild("SkillEffects")
		if mod then
			local ok, se = pcall(require, mod)
			if ok and se then _SkillEffects = se end
		end
	end
	return _SkillEffects or nil
end

local _BonusManager = nil  -- module | false
local function getBonusManager()
	if _BonusManager == nil then
		_BonusManager = false
		local mod = Modules:FindFirstChild("BonusManager")
		if mod then
			local ok, bm = pcall(require, mod)
			if ok and bm then _BonusManager = bm end
		end
	end
	return _BonusManager or nil
end

-- ═══════════════════════════════════════════════════════════
-- PER-PLAYER STATE  (weak keys: a departed Player is collectable)
-- ═══════════════════════════════════════════════════════════

local secondHeart = setmetatable({}, { __mode = "k" })  -- [player] = { readyAt, activeUntil }
local quarry      = setmetatable({}, { __mode = "k" })  -- [player] = { target, h1, h2, h3, markedUntil }
local stillness   = setmetatable({}, { __mode = "k" })  -- [player] = { x, z, moving, lastMovedAt, moveStartedAt }
local nearby      = setmetatable({}, { __mode = "k" })  -- [player] = { at, count }
local bastionSlow = setmetatable({}, { __mode = "k" })  -- [player] = true while the move penalty is applied

-- ═══════════════════════════════════════════════════════════
-- RELENTLESS QUARRY
-- ═══════════════════════════════════════════════════════════

--- Records a hit on `mob`; returns true if `mob` was ALREADY marked (the
--- hit that completes the 4-in-3s sequence marks it for the following hits).
local function quarryHit(player, mob, now)
	local q = quarry[player]
	if not q then
		q = { target = nil, h1 = -math.huge, h2 = -math.huge, h3 = -math.huge, markedUntil = 0 }
		quarry[player] = q
	end
	if q.target ~= mob then
		-- "Hitting a different target removes the mark" (and restarts the count).
		q.target = mob
		q.h1, q.h2, q.h3 = -math.huge, -math.huge, -math.huge
		q.markedUntil = 0
	end
	local wasMarked = now < q.markedUntil
	-- h1..h3 are the three previous hits (oldest first); this is the 4th.
	if now - q.h1 <= QUARRY_WINDOW then
		q.markedUntil = now + QUARRY_MARK
	end
	q.h1, q.h2, q.h3 = q.h2, q.h3, now
	return wasMarked
end

-- ═══════════════════════════════════════════════════════════
-- SECOND HEART
-- ═══════════════════════════════════════════════════════════

local function secondHeartRegen(player, humanoid, state)
	local perTick = SECOND_HEART_HEAL_FRAC / SECOND_HEART_TICKS
	for _ = 1, SECOND_HEART_TICKS do
		task.wait(1)
		if not player.Parent or player:GetAttribute("DeathState") ~= "Alive"
			or not humanoid.Parent or humanoid.Health <= 0 then
			state.activeUntil = 0
			return
		end
		local amount = math.min(humanoid.MaxHealth * perTick, humanoid.MaxHealth - humanoid.Health)
		if amount > 0 then
			humanoid.Health = humanoid.Health + amount
			local se = getSkillEffects()
			if se and se.SendHealNumber then
				se.SendHealNumber(player, math.floor(amount), player, false, 0)
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- HOOKS — OUTGOING DAMAGE
-- ═══════════════════════════════════════════════════════════

--- Called once per direct hit (basic or skill) from
--- DamageSystem.CalculateOutgoingDamage, BEFORE the damage lands.
--- Returns: extraDamagePercent, extraPenetration, extraCritChance, extraLifesteal
function KeystoneRules.OutgoingHit(player, targetMob)
	local dmgPct, pen, crit, lifesteal = 0, 0, 0, 0
	if not player then return dmgPct, pen, crit, lifesteal end

	local overwhelm = hasRule(player, "Overwhelm")
	local cull      = hasRule(player, "CullTheWeak")
	if (overwhelm or cull) and targetMob then
		local hum = targetMob:FindFirstChildOfClass("Humanoid")
		if hum and hum.MaxHealth > 0 then
			local ratio = hum.Health / hum.MaxHealth
			if overwhelm and ratio > OVERWHELM_HP_ABOVE then
				dmgPct = dmgPct + OVERWHELM_DMG_PCT
				pen    = pen + OVERWHELM_PEN
			end
			if cull then
				if ratio < CULL_HP_BELOW then
					dmgPct    = dmgPct + CULL_DMG_PCT
					lifesteal = lifesteal + CULL_LIFESTEAL
				elseif hum.Health >= hum.MaxHealth then
					dmgPct = dmgPct + CULL_FULL_LIFE_DMG_PCT
				end
			end
		end
	end

	local now = os.clock()
	if hasRule(player, "SecondHeart") then
		local s = secondHeart[player]
		if s and now < s.activeUntil then
			dmgPct = dmgPct + SECOND_HEART_DMG_PCT
		end
	end

	if targetMob and hasRule(player, "RelentlessQuarry") then
		if quarryHit(player, targetMob, now) then
			crit = crit + QUARRY_CRIT
			pen  = pen + QUARRY_PEN
		end
	end

	return dmgPct, pen, crit, lifesteal
end

--- Called by CriticalSystem.ApplyCrit (damage AND heals share it).
--- Returns: extraCritChance, extraCritDamage
function KeystoneRules.CritBonus(player)
	if not player or not hasRule(player, "PerfectForm") then return 0, 0 end
	local st = stillness[player]
	if not st then return 0, 0 end
	local now = os.clock()
	if now - st.lastMovedAt >= PERFECT_FORM_STILL and now - st.moveStartedAt >= PERFECT_FORM_SUPPRESS then
		return PERFECT_FORM_CRIT, PERFECT_FORM_CRIT_DMG
	end
	return 0, 0
end

-- ═══════════════════════════════════════════════════════════
-- HOOKS — INCOMING DAMAGE
-- ═══════════════════════════════════════════════════════════

local function nearbyEnemyCount(player)
	local now = os.clock()
	local c = nearby[player]
	if c and now - c.at < UNYIELDING_CACHE then return c.count end

	local count = 0
	local query = getCircleQuery()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if query and root then
		count = #query(root.Position, UNYIELDING_RADIUS, "IsMob")
	end
	if c then
		c.at, c.count = now, count
	else
		nearby[player] = { at = now, count = count }
	end
	return count
end

--- Extra regular DamageReduction (percentage points; still capped by
--- StatCaps.DamageReduction in DamageSystem).
function KeystoneRules.IncomingDR(player)
	local dr = 0
	if hasRule(player, "UnyieldingAdvance") then
		dr = dr + math.min(nearbyEnemyCount(player) * UNYIELDING_DR_PER_ENEMY, UNYIELDING_DR_MAX)
	end
	if hasRule(player, "LastBastion") then
		local pct = resourcePctIf(player, "Determination")
		if pct and pct > BASTION_HIGH_PCT then
			dr = dr + BASTION_DR
		end
	end
	return dr
end

--- Called with the FINAL damage of a hit about to land on `player`.
--- Second Heart: a hit that leaves the player alive below 35% max HP starts
--- the regen (8% max HP over 4 s) and the −12% damage window; 45 s ICD.
function KeystoneRules.AfterIncomingDamage(player, finalDamage)
	if not hasRule(player, "SecondHeart") then return end
	local now = os.clock()
	local s = secondHeart[player]
	if s and now < s.readyAt then return end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.MaxHealth <= 0 then return end
	local after = hum.Health - finalDamage
	if after <= 0 or after >= hum.MaxHealth * SECOND_HEART_THRESHOLD then return end

	if not s then
		s = {}
		secondHeart[player] = s
	end
	s.readyAt     = now + SECOND_HEART_ICD
	s.activeUntil = now + SECOND_HEART_TICKS
	task.spawn(secondHeartRegen, player, hum, s)
end

-- ═══════════════════════════════════════════════════════════
-- HOOKS — LIFESTEAL / RESOURCE / HEALING
-- ═══════════════════════════════════════════════════════════

--- Clarity Surge sets Lifesteal to 0; Shared Grace halves it.
function KeystoneRules.ModifyLifesteal(player, lifesteal)
	if lifesteal <= 0 then return lifesteal end
	if hasRule(player, "ClaritySurge") then return 0 end
	if hasRule(player, "SharedGrace") then return lifesteal * GRACE_LIFESTEAL_MULT end
	return lifesteal
end

--- Clarity Surge: each critical SKILL hit restores 4 Aether.
function KeystoneRules.OnCritSkillHit(player)
	if hasRule(player, "ClaritySurge") then
		grantResourceIf(player, "Aether", CLARITY_SKILL_AETHER)
	end
end

--- Clarity Surge: each critical heal (one per cast — an AoE heal rolls
--- crit once) restores 8 Life Energy.
function KeystoneRules.OnHealCast(healer, healResult)
	if healer and healResult and healResult.wasCrit and hasRule(healer, "ClaritySurge") then
		grantResourceIf(healer, "Life Energy", CLARITY_HEAL_LE)
	end
end

--- Shared Grace: 20% of an overheal comes back as a 4 s HoT on the target.
function KeystoneRules.OnOverheal(healer, target, excess)
	if not healer or excess <= 0 or not hasRule(healer, "SharedGrace") then return end
	local se = getSkillEffects()
	if se and se.ApplyFlatHoT then
		se.ApplyFlatHoT(healer, target, excess * GRACE_EXCESS_FRAC, GRACE_HOT_DURATION, "SharedGrace")
	end
end

--- Last Bastion: +20% Taunt Duration while Determination > 70%. `spent`
--- is the skill's cost (already deducted) so the check sees the pre-cast value.
function KeystoneRules.TauntDurationBonus(player, spent)
	if not hasRule(player, "LastBastion") then return 0 end
	local pct = resourcePctIf(player, "Determination", spent)
	if pct and pct > BASTION_HIGH_PCT then return BASTION_TAUNT_PCT end
	return 0
end

-- ═══════════════════════════════════════════════════════════
-- SAMPLER  (Perfect Form stillness + Last Bastion movement penalty)
-- ═══════════════════════════════════════════════════════════

local function sampleStillness(player, now)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		stillness[player] = nil
		return
	end
	local pos = root.Position
	local st = stillness[player]
	if not st then
		-- First sight: must arm from scratch.
		stillness[player] = { x = pos.X, z = pos.Z, moving = true, lastMovedAt = now, moveStartedAt = now }
		return
	end
	local dx, dz = pos.X - st.x, pos.Z - st.z
	st.x, st.z = pos.X, pos.Z
	if dx * dx + dz * dz > MOVE_EPS_SQ then
		if not st.moving then
			st.moving = true
			st.moveStartedAt = now
		end
		st.lastMovedAt = now
	else
		st.moving = false
	end
end

-- MovementSpeed is a BonusStats key; the penalty goes through BonusManager
-- under its own "keystone" source so it clears independently.
local function updateBastionSlow(player)
	local want = false
	if hasRule(player, "LastBastion") then
		local pct = resourcePctIf(player, "Determination")
		want = pct ~= nil and pct < BASTION_LOW_PCT
	end
	if want == (bastionSlow[player] == true) then return end
	local bm = getBonusManager()
	if not bm or not bm.SetSourceBonus then return end
	bm.SetSourceBonus(player, "keystone", "MovementSpeed", want and BASTION_MOVE_PENALTY or 0)
	bastionSlow[player] = want or nil
end

local started = false
function KeystoneRules.Start()
	if started then return end
	started = true
	task.spawn(function()
		while true do
			task.wait(SAMPLE_INTERVAL)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				if hasRule(player, "PerfectForm") then
					sampleStillness(player, now)
				elseif stillness[player] then
					stillness[player] = nil
				end
				updateBastionSlow(player)
			end
		end
	end)
end

return KeystoneRules
