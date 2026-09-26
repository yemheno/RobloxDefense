-- ServerScriptService/Modules/SkillManager

local SkillManager = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = script.Parent

-- Dependencies (lazy load)
local NetworkManager = nil
local ResourceManager = nil
local StatsManager = nil
local ClassManager = nil
local SkillRegistry = nil
local BonusManager = nil
local PlayerDataManager = nil
-- §AGX/STATS: stat readers resolved once in Init (ARCHITECTURE.md#hot-path-ref-cache) —
-- CooldownReduction, CastTimeReduction and AoESize are read per cast.
local getTotalStat = function(_player, _stat) return 0 end
local capStat = function(_stat, v) return v end

-- Skill execution helpers (set during Init)
local BaseSkills = nil
local SkillEffects = nil

-- §AGX/X7: Horde vote-pause check, bound in Init from AttackHandler so the
-- rule lives in one place. Default is "never paused" until Init runs.
local isWorldPaused = function(_player) return false end

-- §AGX/STATS: ReadyGate, lazy (ARCHITECTURE.md#lazy-getter). SetupPlayer runs on
-- PlayerAdded, before the client's SkillCooldownUpdate listener exists
-- (ARCHITECTURE.md#readygate-pushes).
local _ReadyGate
local function getReadyGate()
	if _ReadyGate ~= nil then return _ReadyGate or nil end
	local mod = Modules:FindFirstChild("ReadyGate")
	local ok, result = false, nil
	if mod then ok, result = pcall(require, mod) end
	_ReadyGate = (ok and result) or false
	return _ReadyGate or nil
end

-- ═══════════════════════════════════════════════════════════
-- §AGX/STATS: CAST-TIME STAT READERS
-- ═══════════════════════════════════════════════════════════

-- Capped percent of a derived stat (base + primary scaling + data.Bonus).
local function cappedStat(player, statName)
	return capStat(statName, getTotalStat(player, statName) or 0)
end

--- CooldownReduction % (StatCaps 40) applied to a skill cooldown.
function SkillManager.GetEffectiveCooldown(player, duration)
	local cdr = cappedStat(player, "CooldownReduction")
	if cdr > 0 then return duration * (1 - cdr / 100) end
	return duration
end

--- CastTimeReduction % (StatCaps 40) applied to a skill's cast time.
function SkillManager.GetEffectiveCastTime(player, castTime)
	local ctr = cappedStat(player, "CastTimeReduction")
	if ctr > 0 then return castTime * (1 - ctr / 100) end
	return castTime
end

-- AoESize: skills execute with a per-cast view whose shapeParams are
-- scaled by (1 + AoESize/100). BaseSkills.GetTargetsInShape and the
-- GetTargetsInCircle(skill.shapeParams.range) call sites then resolve the
-- bigger shape with no class-module change, and the SkillActivated /
-- SkillCastStarted payloads carry the same numbers to the client visuals.
-- Scaled views are cached per (skill, whole-percent), so steady-state casts
-- allocate nothing. `angle` and cast distance (`maxRange`) are not sizes.
local AOE_SCALED_KEYS = { range = true, width = true, innerRadius = true, radius = true, length = true }
local aoeViews = setmetatable({}, { __mode = "k" })  -- [skill] = { [pct] = view }

local function withAoESize(player, skill)
	if type(skill.shapeParams) ~= "table" then return skill end
	local data = PlayerDataManager.GetData(player)
	local raw = data and data.Bonus and data.Bonus.AoESize or 0
	local pct = math.floor(capStat("AoESize", raw) + 0.5)
	if pct == 0 then return skill end

	local perSkill = aoeViews[skill]
	if not perSkill then
		perSkill = {}
		aoeViews[skill] = perSkill
	end
	local view = perSkill[pct]
	if view then return view end

	local mult = 1 + pct / 100
	view = table.clone(skill)
	local params = table.clone(skill.shapeParams)
	for key, value in pairs(params) do
		if AOE_SCALED_KEYS[key] and type(value) == "number" then
			params[key] = value * mult
		end
	end
	view.shapeParams = params
	perSkill[pct] = view
	return view
end

-- Player tracking
local playerCooldowns = {}    -- [player] = { [skillId] = endTime }
local activeBuffs = {}        -- [player] = { [buffId] = buffData }
local playerCasting = {}      -- [player] = { skillId, endTime, skill } or nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function SkillManager.Init()
	-- Load dependencies
	NetworkManager = require(Modules:WaitForChild("NetworkManager"))
	ResourceManager = require(Modules:WaitForChild("ResourceManager"))
	StatsManager = require(Modules:WaitForChild("StatsManager"))
	ClassManager = require(Modules:WaitForChild("ClassManager"))
	SkillRegistry = require(Modules:WaitForChild("SkillRegistry"))
	PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
	-- §AGX/STATS: cache the function refs (see the declarations above).
	if PlayerDataManager.GetTotalStat then getTotalStat = PlayerDataManager.GetTotalStat end
	local DataConfig = require(Modules:WaitForChild("PlayerDataConfig"))
	if DataConfig.CapStat then capStat = DataConfig.CapStat end

	-- Optional: BonusManager (source-separated bonus aggregation)
	local bmMod = Modules:FindFirstChild("BonusManager")
	if bmMod then BonusManager = require(bmMod) end

	-- ───────────────────────────────────────────────────────────
	-- Skill execution wiring
	-- Sets up BaseSkills + SkillEffects + per-class skill modules with
	-- the shared dependency bundle they expect.
	-- ───────────────────────────────────────────────────────────
	local ClassSkillsFolder = Modules:FindFirstChild("ClassSkills")

	local baseModule = ClassSkillsFolder and ClassSkillsFolder:FindFirstChild("BaseSkills")
	if baseModule then
		BaseSkills = require(baseModule)
	end

	local effectsModule = Modules:FindFirstChild("SkillEffects")
	if effectsModule then
		SkillEffects = require(effectsModule)
	end

	-- DamageHandler must exist before SkillManager initializes
	local AttackHandler = require(Modules:WaitForChild("AttackHandler"))
	local DamageHandler = AttackHandler.GetSystems().Damage
	-- §AGX/X7: share AttackHandler's pause check (attribute read only).
	if AttackHandler.IsWorldPaused then isWorldPaused = AttackHandler.IsWorldPaused end
	assert(DamageHandler, "[SkillManager] AttackHandler.Init() must run before SkillManager")

	local dependencies = {
		AttackShapes   = require(Modules:WaitForChild("AttackShapes")),
		StatsManager   = StatsManager,
		NetworkManager = NetworkManager,
		DamageHandler  = DamageHandler,
		MobAI          = nil,  -- populated async below
		SkillManager   = SkillManager,
	}

	-- Make sure SkillVisual exists before any class module tries to fire it
	NetworkManager.GetEvent("SkillVisual")

	if BaseSkills   then BaseSkills.Init(dependencies)   end
	if SkillEffects then SkillEffects.Init(dependencies) end

	for _, className in ipairs(SkillRegistry.GetAllClassNames()) do
		local classModule = SkillRegistry.GetClassModule(className)
		if classModule and classModule.Init then
			classModule.Init(BaseSkills, SkillEffects)
		end
	end

	-- MobAI may not exist in non-combat places (Lobby, etc.), so wait async.
	-- If it doesn't show up in 10s we warn once and leave MobAI nil — code
	-- paths that need it already null-check.
	task.spawn(function()
		local mobAIModule = Modules:WaitForChild("MobAI", 10)
		if mobAIModule then
			local MobAI = require(mobAIModule)
			dependencies.MobAI = MobAI
			if BaseSkills   then BaseSkills.MobAI   = MobAI end
			if SkillEffects then SkillEffects.MobAI = MobAI end
		else
			warn("[SkillManager] MobAI not available within 10s — skills that rely on it will no-op")
		end
	end)

	-- Create network events
	NetworkManager.GetEvent("SkillRequest")
	NetworkManager.GetEvent("SkillActivated")
	NetworkManager.GetEvent("SkillFailed")
	NetworkManager.GetEvent("SkillCooldownUpdate")
	NetworkManager.GetEvent("SkillCastStarted")
	NetworkManager.GetEvent("SkillCastCompleted")
	NetworkManager.GetEvent("SkillCastInterrupted")
	NetworkManager.GetEvent("BuffApplied")
	NetworkManager.GetEvent("BuffRemoved")

	-- Listen for skill requests
	NetworkManager.OnClientEvent("SkillRequest", function(player, skillId, inputData)
		SkillManager.TryUseSkill(player, skillId, inputData)
	end)

	-- Player lifecycle
	Players.PlayerAdded:Connect(function(player)
		SkillManager.SetupPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		SkillManager.RemovePlayer(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		SkillManager.SetupPlayer(player)
	end

	-- Update loop (buffs + casting)
	RunService.Heartbeat:Connect(function(dt)
		SkillManager.UpdateBuffs(dt)
		SkillManager.UpdateCasting(dt)
	end)

end

-- ═══════════════════════════════════════════════════════════
-- PLAYER SETUP / CLEANUP
-- ═══════════════════════════════════════════════════════════

function SkillManager.SetupPlayer(player)
	playerCooldowns[player] = {}
	activeBuffs[player] = {}
	playerCasting[player] = nil

	-- Send initial skill data to client
	local className = ClassManager.GetClassName(player)
	local classSkills = SkillRegistry.GetClassSkillIds(className)

	-- §AGX/UI-P2: include base resource costs so the touch SkillPad /
	-- ActionBar can dim unaffordable skills from the start.
	-- usesAllResource skills need any > 0.
	local costs = {}
	local classModule = SkillRegistry.GetClassModule(className)
	if classModule and classModule.GetAllSkills then
		for slot, skill in pairs(classModule.GetAllSkills()) do
			costs[slot] = skill.usesAllResource and 1 or (skill.resourceCost or 0)
		end
	end

	-- §AGX/STATS: PlayerAdded push → ReadyGate (ARCHITECTURE.md#readygate-pushes);
	-- a plain FireClient here races the client's listener and is dropped.
	local payload = {
		skills = classSkills,
		costs = costs,
		cooldowns = {},
	}
	local rg = getReadyGate()
	if rg then
		rg.FireClient(player, "SkillCooldownUpdate", payload)
	else
		NetworkManager.FireClient(player, "SkillCooldownUpdate", payload)
	end
end

function SkillManager.RemovePlayer(player)
	playerCooldowns[player] = nil
	activeBuffs[player] = nil
	playerCasting[player] = nil
end

-- ═══════════════════════════════════════════════════════════
-- CASTING SYSTEM
-- ═══════════════════════════════════════════════════════════

-- §AGX/STATS: `castTime` is the CastTimeReduction-adjusted duration
-- (ExecuteSkill computes it); falls back to the skill's own value.
function SkillManager.StartCasting(player, skill, inputData, castTime)
	castTime = castTime or skill.castTime
	local character = player.Character
	if not character then return false end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return false end

	-- Store original walk speed
	-- §AGX/X13: prefer the natural speed so a mob slow active at cast
	-- start isn't restored after it has expired.
	local originalWalkSpeed = humanoid:GetAttribute("BaseWalkSpeed") or humanoid.WalkSpeed

	-- Lock movement if needed
	if skill.lockMovement then
		humanoid.WalkSpeed = 0
		humanoid:SetAttribute("CastMoveLock", true)
	end

	-- Set casting state
	playerCasting[player] = {
		skillId = skill.id,
		skill = skill,
		inputData = inputData,
		endTime = os.clock() + castTime,
		originalWalkSpeed = originalWalkSpeed,
	}

	-- Set attributes for other systems to check
	player:SetAttribute("IsCasting", true)
	if skill.lockSkills then
		player:SetAttribute("CastingLockSkills", true)
	end
	if skill.lockAttack then
		player:SetAttribute("CastingLockAttack", true)
	end

	-- Notify client
	NetworkManager.FireClient(player, "SkillCastStarted", {
		skillId = skill.id,
		castTime = castTime,  -- §AGX/STATS: reduced; drives the client cast bar
		skillData = skill,
	})

	-- Notify the caster for the cast-time animation.
	-- §AGX/X21: caster only: SkillVisuals.OnSkillActivated filters on
	-- playerId, and Roblox replicates the caster's animation itself.
	-- Still the ONLY event that plays cast-time animations — don't remove.
	NetworkManager.FireClient(player, "SkillActivated", {
		skillId = skill.id,
		playerId = player.UserId,
		skillData = skill,
		isCasting = true,
	})

	return true
end

function SkillManager.CompleteCasting(player, castData)
	-- §S4: bail if the player has left during the cast.
	if not player or not player.Parent then
		playerCasting[player] = nil
		return
	end

	local character = player.Character
	if not character then return end

	-- §S3: knockdown / death / stun during cast → interrupt instead.
	if not SkillManager.CanPlayerAct(player) then
		SkillManager.InterruptCasting(player, "Knocked down during cast")
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	local skill = castData.skill

	-- Restore walk speed
	if humanoid and skill.lockMovement then
		-- §AGX/X13: honour a mob Stun/Slow still active on the player.
		humanoid:SetAttribute("CastMoveLock", nil)
		-- §AGX/STATS: current BaseWalkSpeed — a MovementSpeed change during
		-- the cast re-derived it; castData's copy is from cast start.
		humanoid.WalkSpeed = humanoid:GetAttribute("MoveFxSpeed")
			or humanoid:GetAttribute("BaseWalkSpeed") or castData.originalWalkSpeed
	end

	-- Clear casting state
	playerCasting[player] = nil
	player:SetAttribute("IsCasting", false)
	player:SetAttribute("CastingLockSkills", false)
	player:SetAttribute("CastingLockAttack", false)

	-- Notify client
	NetworkManager.FireClient(player, "SkillCastCompleted", {
		skillId = skill.id,
	})

	-- Execute the skill effect
	if StatsManager and StatsManager.KeystoneRules then StatsManager.KeystoneRules.OnSkillCast(player) end -- §AGX/X11: Spell Rhythm
	SkillRegistry.ExecuteSkill(player, skill, castData.inputData)
end

function SkillManager.InterruptCasting(player, reason)
	local castData = playerCasting[player]
	if not castData then return end

	-- §S5: bail cleanly if the player has left.
	if not player or not player.Parent then
		playerCasting[player] = nil
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	local skill = castData.skill

	-- Restore walk speed
	if humanoid and skill.lockMovement then
		-- §AGX/X13: honour a mob Stun/Slow still active on the player.
		humanoid:SetAttribute("CastMoveLock", nil)
		-- §AGX/STATS: current BaseWalkSpeed — a MovementSpeed change during
		-- the cast re-derived it; castData's copy is from cast start.
		humanoid.WalkSpeed = humanoid:GetAttribute("MoveFxSpeed")
			or humanoid:GetAttribute("BaseWalkSpeed") or castData.originalWalkSpeed
	end

	-- Refund resource
	if skill.usesAllResource then
		-- Ultimate: refund whatever was consumed (stored in castData)
		local refund = castData.inputData and castData.inputData.resourceUsed or 0
		ResourceManager.ModifyResource(player, refund)
	else
		ResourceManager.ModifyResource(player, skill.resourceCost)
	end

	-- Reset cooldown (skill was interrupted, shouldn't go on cooldown)
	SkillManager.ResetCooldown(player, skill.id)

	-- Clear casting state
	playerCasting[player] = nil
	player:SetAttribute("IsCasting", false)
	player:SetAttribute("CastingLockSkills", false)
	player:SetAttribute("CastingLockAttack", false)

	-- Notify client
	NetworkManager.FireClient(player, "SkillCastInterrupted", {
		skillId = skill.id,
		reason = reason or "Interrupted",
	})
end

function SkillManager.UpdateCasting(dt)
	local now = os.clock()

	-- §S2: collect first, then mutate. CompleteCasting nils
	-- playerCasting[player], which is unsafe inside `pairs()` iteration
	-- of the same table.
	-- §MEM/M4: collector is lazily allocated — this runs at 60 Hz and the
	-- common frame completes nothing.
	local toComplete
	for player, castData in pairs(playerCasting) do
		if castData and now >= castData.endTime then
			toComplete = toComplete or {}
			table.insert(toComplete, { player = player, castData = castData })
		end
	end
	if toComplete then
		for _, entry in ipairs(toComplete) do
			SkillManager.CompleteCasting(entry.player, entry.castData)
		end
	end
end

function SkillManager.IsCasting(player)
	return playerCasting[player] ~= nil
end

-- ═══════════════════════════════════════════════════════════
-- SKILL USAGE
-- ═══════════════════════════════════════════════════════════

-- §S1: per-player atomic-request lock. Two SkillRequest packets
-- arriving in the same network frame would otherwise both pass the
-- cooldown + casting checks, both deduct resource, and both start a
-- cooldown — a duplicated cast worth real damage. The lock is
-- module-scoped, keyed by Player, and yields nothing while held.
local skillRequestLock = setmetatable({}, { __mode = "k" })

function SkillManager.TryUseSkill(player, skillId, inputData)
	-- §AGX/X7: no skills while the Horde vote pause is active. Checked
	-- before the §S1 lock so a paused request never touches state.
	if isWorldPaused(player) then
		SkillManager.SendFailure(player, skillId, "Game paused")
		return false
	end

	-- §S1: atomic gate. The check-then-mutate sequence below is the
	-- critical section; reject reentrant calls outright.
	if skillRequestLock[player] then
		SkillManager.SendFailure(player, skillId, "Concurrent request")
		return false
	end
	skillRequestLock[player] = true

	local function release(result)
		skillRequestLock[player] = nil
		return result
	end

	local skill = nil
	local className = ClassManager.GetClassName(player)

	-- Handle slot-based requests
	if type(skillId) == "string" and skillId:sub(1, 5) == "slot_" then
		local slot = tonumber(skillId:sub(6))

		skill = SkillRegistry.GetSkillBySlot(className, slot)

		if not skill then
			SkillManager.SendFailure(player, skillId, "No skill in slot " .. slot)
			return release(false)
		end

		skillId = skill.id
	else
		skill = SkillRegistry.GetSkill(skillId)
		if not skill then
			SkillManager.SendFailure(player, skillId, "Invalid skill")
			return release(false)
		end

		if not SkillRegistry.IsSkillForClass(skillId, className) then
			SkillManager.SendFailure(player, skillId, "Wrong class")
			return release(false)
		end
	end

	-- Check if already casting
	if SkillManager.IsCasting(player) then
		SkillManager.SendFailure(player, skillId, "Already casting")
		return release(false)
	end

	-- Check cooldown
	local canUse, remaining = SkillManager.CheckCooldown(player, skillId)
	if not canUse then
		SkillManager.SendFailure(player, skillId, "On cooldown", remaining)
		return release(false)
	end

	-- Ultimates: level-gate check
	if skill.isUltimate and skill.unlockLevel then
		local data = PlayerDataManager.GetData(player)
		local level = data and data.Account and data.Account.Level or 1
		if level < skill.unlockLevel then
			SkillManager.SendFailure(player, skillId, "Unlock at level " .. skill.unlockLevel)
			return release(false)
		end
	end

	-- Check resource
	local currentResource = ResourceManager.GetResource(player)

	if skill.usesAllResource then
		-- §EASY/E1 (Pablo): ultimates unlock at base level 10. But the
		-- skill.unlockLevel gate above (30 on every ultimate) runs first and
		-- wins; BACKLOG §ULT-LEVEL picks one. Level attribute: §T0P2/X4.
		local ULTIMATE_UNLOCK_LEVEL = 10
		if (player:GetAttribute("Level") or 1) < ULTIMATE_UNLOCK_LEVEL then
			SkillManager.SendFailure(player, skillId,
				"Ultimate unlocks at level " .. ULTIMATE_UNLOCK_LEVEL)
			return release(false)
		end

		-- Ultimate: need at least minimumResource
		local minRequired = skill.minimumResource or 100
		if currentResource < minRequired then
			SkillManager.SendFailure(player, skillId,
				"Need at least " .. minRequired .. " " .. ResourceManager.GetResourceName(player))
			return release(false)
		end
	else
		if currentResource < skill.resourceCost then
			SkillManager.SendFailure(player, skillId,
				"Not enough " .. ResourceManager.GetResourceName(player))
			return release(false)
		end
	end

	-- Check if player can act (not stunned, etc.)
	if not SkillManager.CanPlayerAct(player) then
		SkillManager.SendFailure(player, skillId, "Cannot act")
		return release(false)
	end

	-- All checks passed! Execute or start casting (still inside the
	-- atomic gate so the deduct + cooldown-start in ExecuteSkill is
	-- sequenced with the checks above).
	return release(SkillManager.ExecuteSkill(player, skill, inputData))
end

function SkillManager.ExecuteSkill(player, skill, inputData)
	-- §AGX/STATS: AoESize-scaled view of the skill for this cast.
	skill = withAoESize(player, skill)

	-- Deduct resource
	if skill.usesAllResource then
		-- Ultimate: consume ALL current resource and pass amount to skill
		local resourceUsed = ResourceManager.GetResource(player)
		ResourceManager.SetResource(player, 0)
		inputData = inputData or {}
		inputData.resourceUsed = resourceUsed
	else
		ResourceManager.ModifyResource(player, -skill.resourceCost)
	end

	-- Start cooldown
	SkillManager.StartCooldown(player, skill.id, skill.cooldown)

	-- Check if skill has cast time
	if skill.castTime and skill.castTime > 0 then
		-- Start casting (skill executes after cast time)
		-- §AGX/STATS: CastTimeReduction shortens the wind-up.
		return SkillManager.StartCasting(player, skill, inputData,
			SkillManager.GetEffectiveCastTime(player, skill.castTime))
	else
		-- Instant skill - execute immediately
		NetworkManager.FireClient(player, "SkillActivated", {
			skillId = skill.id,
			skillData = skill,
		})

		if StatsManager and StatsManager.KeystoneRules then StatsManager.KeystoneRules.OnSkillCast(player) end -- §AGX/X11: Spell Rhythm
		return SkillRegistry.ExecuteSkill(player, skill, inputData)
	end
end

-- ═══════════════════════════════════════════════════════════
-- COOLDOWN MANAGEMENT
-- ═══════════════════════════════════════════════════════════

function SkillManager.CheckCooldown(player, skillId)
	local cooldowns = playerCooldowns[player]
	if not cooldowns then return true, 0 end

	local endTime = cooldowns[skillId]
	if not endTime then return true, 0 end

	local now = os.clock()
	if now >= endTime then
		cooldowns[skillId] = nil
		return true, 0
	end

	return false, endTime - now
end

function SkillManager.StartCooldown(player, skillId, duration)
	if not playerCooldowns[player] then
		-- §AGX/T11-JAN: a late call for a player who already left (RemovePlayer
		-- ran) must not re-create the Player-keyed entry; it would never clear.
		if not player.Parent then return end
		playerCooldowns[player] = {}
	end

	-- §AGX/STATS: CooldownReduction (capped 40%). The reduced duration is
	-- what the client's cooldown sweep receives, so display == server.
	duration = SkillManager.GetEffectiveCooldown(player, duration)
	playerCooldowns[player][skillId] = os.clock() + duration

	NetworkManager.FireClient(player, "SkillCooldownUpdate", {
		skillId = skillId,
		cooldown = duration,
		endTime = playerCooldowns[player][skillId],
	})
end

function SkillManager.ResetCooldown(player, skillId)
	if playerCooldowns[player] then
		playerCooldowns[player][skillId] = nil

		NetworkManager.FireClient(player, "SkillCooldownUpdate", {
			skillId = skillId,
			cooldown = 0,
			reset = true,
		})
	end
end

function SkillManager.ResetAllCooldowns(player)
	if not playerCooldowns[player] then return end
	for skillId, _ in pairs(playerCooldowns[player]) do
		playerCooldowns[player][skillId] = nil
		NetworkManager.FireClient(player, "SkillCooldownUpdate", {
			skillId = skillId,
			cooldown = 0,
			reset = true,
		})
	end
end

-- ═══════════════════════════════════════════════════════════
-- BUFF MANAGEMENT
-- ═══════════════════════════════════════════════════════════

function SkillManager.ApplyBuff(player, buffId, buffData)
	if not activeBuffs[player] then
		-- §AGX/T11-JAN: same re-create-after-leave leak as StartCooldown.
		if not player.Parent then return end
		activeBuffs[player] = {}
	end

	-- If a buff with this ID already exists, remove the old stat effect first
	if activeBuffs[player][buffId] then
		SkillManager.RemoveBuffEffect(player, activeBuffs[player][buffId].data)
	end

	activeBuffs[player][buffId] = {
		data = buffData,
		endTime = os.clock() + buffData.duration,
		appliedAt = os.clock(),
	}

	SkillManager.ApplyBuffEffect(player, buffData)

	NetworkManager.FireClient(player, "BuffApplied", {
		buffId = buffId,
		buffData = buffData,
	})
end

function SkillManager.RemoveBuff(player, buffId)
	local buffs = activeBuffs[player]
	if not buffs or not buffs[buffId] then return end

	local buffInfo = buffs[buffId]

	SkillManager.RemoveBuffEffect(player, buffInfo.data)

	buffs[buffId] = nil

	NetworkManager.FireClient(player, "BuffRemoved", {
		buffId = buffId,
	})
end

-- Unified buff-type → stat mapping (maintained in one place)
local BUFF_STAT_MAP = {
	DamageReduction                      = "DamageReduction",
	CritChance                           = "CritChance",
	CritChanceUp                         = "CritChance",
	AttackSpeed                          = "AttackSpeed",
	AttackSpeedDown                      = "AttackSpeed",
	HealingPowerUp                       = "HealingPercent",
	HealingPercent                       = "HealingPercent",
}

function SkillManager.ApplyBuffEffect(player, buffData)
	local stat = BUFF_STAT_MAP[buffData.type]
	if not stat then return end

	if BonusManager then
		BonusManager.ModifySourceBonus(player, "buff", stat, buffData.amount)
	else
		local current = StatsManager.GetBonus(player, stat) or 0
		StatsManager.SetBonus(player, stat, current + buffData.amount)
	end
end

function SkillManager.RemoveBuffEffect(player, buffData)
	local stat = BUFF_STAT_MAP[buffData.type]
	if not stat then return end

	if BonusManager then
		BonusManager.ModifySourceBonus(player, "buff", stat, -buffData.amount)
	else
		local current = StatsManager.GetBonus(player, stat) or 0
		StatsManager.SetBonus(player, stat, current - buffData.amount)
	end
end

function SkillManager.UpdateBuffs(dt)
	local now = os.clock()

	for player, buffs in pairs(activeBuffs) do
		-- Collect expired buffs first to avoid mutating table during iteration
		-- §MEM/M4: lazily allocated — 60 Hz × N players, almost always empty.
		local expired
		for buffId, buffInfo in pairs(buffs) do
			if now >= buffInfo.endTime then
				expired = expired or {}
				table.insert(expired, buffId)
			end
		end
		if expired then
			for _, buffId in ipairs(expired) do
				SkillManager.RemoveBuff(player, buffId)
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function SkillManager.CanPlayerAct(player)
	-- Block actions while knocked down or dead
	if player:GetAttribute("DeathState") ~= "Alive" then
		return false
	end

	if player:GetAttribute("IsStunned") then
		return false
	end

	return true
end

function SkillManager.SendFailure(player, skillId, reason, cooldownRemaining)
	NetworkManager.FireClient(player, "SkillFailed", {
		skillId = skillId,
		reason = reason,
		cooldownRemaining = cooldownRemaining,
	})
end

-- ═══════════════════════════════════════════════════════════
-- CLEANSE: Remove one negative buff (debuff) from a player
-- Returns true + the buffId if a debuff was removed, false otherwise.
-- Negative buff types: AttackSpeedDown
-- ═══════════════════════════════════════════════════════════

local DEBUFF_TYPES = {
	AttackSpeedDown = true,
	-- Add future negative buff types here
}

function SkillManager.CleanseOneDebuff(player)
	local buffs = activeBuffs[player]
	if not buffs then return false end

	for buffId, buffInfo in pairs(buffs) do
		local t = buffInfo.data and buffInfo.data.type
		if t and DEBUFF_TYPES[t] then
			SkillManager.RemoveBuff(player, buffId)
			return true, buffId
		end
	end

	return false
end

return SkillManager