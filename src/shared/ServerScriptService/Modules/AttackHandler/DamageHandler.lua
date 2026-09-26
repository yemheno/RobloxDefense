-- ServerScriptService/Modules/AttackHandler/DamageHandler

local DamageHandler = {}

local Players = game:GetService("Players")

local Modules = script.Parent.Parent  -- Go up to Modules folder
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local StatsManager = require(Modules:WaitForChild("StatsManager"))
local MobRegistry = require(Modules:WaitForChild("MobRegistry"))  -- CHANGED from MobConfig
local ElementalSystem = require(Modules:WaitForChild("ElementalSystem"))

-- HitTracker reference (set after it's created)
DamageHandler.HitTracker = nil

-- Centralised kill rewards (XP, drops, weapon XP, callbacks) — see KillRewardManager
local KillRewardManager = nil

-- Cached WeaponManager reference (resolved in Init)
local _WeaponManager = nil

--- Backwards-compatible kill callback hook. Delegates to KillRewardManager.
function DamageHandler.OnMobKilled(callback)
	if KillRewardManager then
		KillRewardManager.OnMobKilled(callback)
	else
		-- Queue until Init resolves KillRewardManager.
		-- §T2/Z6: bounded — the old loop polled forever if KRM never
		-- loaded. 10 s covers any legitimate boot ordering; past that,
		-- warn loudly and drop (loud-at-boot over silent spin).
		task.spawn(function()
			local deadline = os.clock() + 10
			repeat task.wait(0.05) until KillRewardManager ~= nil or os.clock() > deadline
			if KillRewardManager then
				KillRewardManager.OnMobKilled(callback)
			else
				warn("[DamageHandler] OnMobKilled callback dropped — KillRewardManager never loaded (10 s)")
			end
		end)
	end
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DamageHandler.Init()
	-- Pre-create damage number event
	NetworkManager.GetEvent("DamageNumber")
	NetworkManager.GetEvent("DamageNumberBatch")  -- §PERF/F5

	-- Load KillRewardManager (centralised kill rewards)
	local krmModule = Modules:FindFirstChild("KillRewardManager")
	if krmModule then
		KillRewardManager = require(krmModule)
	else
		warn("[DamageHandler] KillRewardManager not found — kill rewards will not fire")
	end

	-- Try to get HitTracker if it exists
	local HitTrackerModule = Modules:FindFirstChild("HitTracker")
	if HitTrackerModule then
		DamageHandler.HitTracker = require(HitTrackerModule)
	end

	-- Cache WeaponManager for hot-path element resolution
	local wmMod = Modules:FindFirstChild("WeaponManager")
	if wmMod then _WeaponManager = require(wmMod) end

end

-- ═══════════════════════════════════════════════════════════
-- DAMAGE APPLICATION
-- ═══════════════════════════════════════════════════════════

function DamageHandler.DamageMob(mob, player, options)
	options = options or {}

	local humanoid = mob:FindFirstChild("Humanoid")
	if not humanoid then return nil end

	-- Guard against double-kill: if mob is already dead, skip
	if humanoid.Health <= 0 then return nil end

	-- Get mob info (CHANGED: use MobId attribute and MobRegistry)
	local mobId = mob:GetAttribute("MobId") or mob:GetAttribute("MobType") or "Unknown"
	local mobTier = mob:GetAttribute("MobTier") or MobRegistry.GetMobTier(mobId) or "normal"

	-- Resolve attack element:
	--   Skills set options.attackElement themselves.
	--   Basic attacks derive it from the player's equipped weapon.
	if not options.attackElement then
		if _WeaponManager then
			local weaponDef = _WeaponManager.GetEquippedWeaponDef(player)
			options.attackElement = ElementalSystem.GetWeaponElement(weaponDef)
		end
	end

	-- Move damageMultiplier into actionMultiplier for the damage pipeline
	-- (applied before armor per §42.1, not as a post-multiply)
	if options.damageMultiplier then
		options.actionMultiplier = options.damageMultiplier
	end

	-- Calculate damage using StatsManager (element mult applied inside)
	local damageResult = StatsManager.CalculateDamage(player, mob, options)
	local finalDamage = damageResult.damage

	-- Apply damage
	humanoid:TakeDamage(finalDamage)

	-- Lifesteal: heal attacker for a percentage of damage dealt
	local lifesteal = StatsManager.GetBonus(player, "Lifesteal") or 0
	if lifesteal > 0 and player.Character then
		local playerHumanoid = player.Character:FindFirstChild("Humanoid")
		if playerHumanoid and playerHumanoid.Health > 0 then
			local healAmount = finalDamage * lifesteal / 100
			playerHumanoid.Health = math.min(playerHumanoid.MaxHealth, playerHumanoid.Health + healAmount)
		end
	end

	-- Check for death
	local isKill = humanoid.Health <= 0

	-- Enrich result with mob info
	damageResult.mobId = mobId
	damageResult.mobTier = mobTier
	damageResult.isKill = isKill

	-- Track the hit
	if not options.skipHitTracking and DamageHandler.HitTracker then
		DamageHandler.HitTracker.RecordHitDealt(player, {
			mobTier = mobTier,
			damage = finalDamage,
			isCrit = damageResult.wasCrit,
			critProcs = damageResult.critProcs,
			isKill = isKill,
		})
	end

	-- Send damage number
	if not options.skipDamageNumber then
		DamageHandler.SendDamageNumber(mob, player, damageResult)
	end

	-- Handle death
	if isKill then
		DamageHandler.HandleMobDeath(mob, player, damageResult)
	end

	return damageResult
end

-- ═══════════════════════════════════════════════════════════
-- DAMAGE NUMBERS
-- ═══════════════════════════════════════════════════════════

-- §PERF/F4 (task #17): spectator cache. SendDamageNumber fires for every
-- landing hit (dozens/sec in combat) and used to call GetPlayers() plus a
-- GetAttribute per player per hit. The set of players with ShowAllDamage
-- changes rarely — maintain it on the attribute signal instead.
local spectators = {}  -- [player] = true while ShowAllDamage == true
local spectatorsWired = setmetatable({}, { __mode = "k" })

local function wireSpectator(player)
	if spectatorsWired[player] then return end
	spectatorsWired[player] = true
	if player:GetAttribute("ShowAllDamage") == true then
		spectators[player] = true
	end
	-- Connection lives on the Player instance — auto-disconnected when
	-- the player leaves (instance destroyed).
	player:GetAttributeChangedSignal("ShowAllDamage"):Connect(function()
		if player:GetAttribute("ShowAllDamage") == true then
			spectators[player] = true
		else
			spectators[player] = nil
		end
	end)
end

Players.PlayerAdded:Connect(wireSpectator)
for _, p in ipairs(Players:GetPlayers()) do
	wireSpectator(p)
end
Players.PlayerRemoving:Connect(function(p)
	spectators[p] = nil
end)

-- §PERF/F5 (Tibia window): hits are queued and flushed every
-- DAMAGE_NUMBER_WINDOW seconds as ONE "DamageNumberBatch" event per
-- recipient. Hits by the same attacker on the same mob inside a window
-- MERGE into a single summed number (crit if any hit crit, `hits` count
-- carried for the client's "x N" suffix). 0.1 s is below perception
-- threshold but collapses rapid-fire attacks to 1 event per window.
local DAMAGE_NUMBER_WINDOW = 0.1
local pendingByAttacker = {}  -- [player] = { [mob] = damageData }
local flushScheduled = false

local function flushDamageNumbers()
	flushScheduled = false

	local all = (next(spectators) ~= nil) and {} or nil

	for attacker, byMob in pairs(pendingByAttacker) do
		local batch = {}
		for _, dd in pairs(byMob) do
			table.insert(batch, dd)
			if all then table.insert(all, dd) end
		end
		if attacker.Parent and #batch > 0 then
			NetworkManager.FireClient(attacker, "DamageNumberBatch", batch)
		end
	end
	table.clear(pendingByAttacker)

	-- §PERF/F4 semantics preserved: spectators see everyone ELSE's
	-- numbers (their own arrived in their attacker batch above).
	if all and #all > 0 then
		for spec in pairs(spectators) do
			if spec.Parent then
				local others = {}
				for _, dd in ipairs(all) do
					if dd.attackerUserId ~= spec.UserId then
						table.insert(others, dd)
					end
				end
				if #others > 0 then
					NetworkManager.FireClient(spec, "DamageNumberBatch", others)
				end
			end
		end
	end
end

function DamageHandler.SendDamageNumber(mob, player, damageResult)
	local rootPart = mob:FindFirstChild("HumanoidRootPart") or mob.PrimaryPart
	local position = rootPart and rootPart.Position or mob:GetPivot().Position

	local byMob = pendingByAttacker[player]
	if not byMob then
		byMob = {}
		pendingByAttacker[player] = byMob
	end

	local existing = byMob[mob]
	if existing then
		-- Merge into the window's running number for this mob.
		existing.damage    = existing.damage + damageResult.damage
		existing.hits      = existing.hits + 1
		existing.wasCrit   = existing.wasCrit or damageResult.wasCrit
		existing.critProcs = math.max(existing.critProcs or 0, damageResult.critProcs or 0)
		existing.position  = position
	else
		byMob[mob] = {
			position     = position,
			damage       = damageResult.damage,
			hits         = 1,
			wasCrit      = damageResult.wasCrit,
			critProcs    = damageResult.critProcs,
			attackerName = player.Name,
			attackerUserId = player.UserId,
			-- Elemental (used for damage number colour)
			attackElement = damageResult.attackElement  or "None",
			elementLabel  = damageResult.elementLabel   or "Neutral",
			elementMult   = damageResult.elementMult    or 1.0,
		}
	end

	if not flushScheduled then
		flushScheduled = true
		task.delay(DAMAGE_NUMBER_WINDOW, flushDamageNumbers)
	end
end

-- ═══════════════════════════════════════════════════════════
-- MOB DEATH
-- ═══════════════════════════════════════════════════════════

-- §AGX/X12: mobs whose death has already been processed. HandleMobDeath
-- is now reachable from three paths (DamageMob, DoT ticks, Thorns reflect)
-- that can land in the same frame; the first one wins and the rest are
-- no-ops, so a mob can never be rewarded twice. Weak keys: the mob is
-- Destroy()ed right after, so the entry is collectable.
local handledMobs = setmetatable({}, { __mode = "k" })

--- §AGX/X12: true once HandleMobDeath has run for this mob (used by the
--- MobAI Died safety net and by ApplyRawDamage).
function DamageHandler.IsDeathHandled(mob)
	return handledMobs[mob] == true
end

function DamageHandler.HandleMobDeath(mob, player, damageResult)
	-- §AGX/X12: idempotent — see handledMobs above.
	if not mob or handledMobs[mob] then return end
	handledMobs[mob] = true

	-- Delegate all reward logic (XP, drops, weapon XP, callbacks, client notify)
	-- to the centralised KillRewardManager.
	-- Wrapped in pcall so an error in reward processing never leaves a phantom mob.
	-- §AGX/X12: player may be nil (raw damage whose source left); the
	-- corpse is still destroyed, it just pays nothing.
	if player and KillRewardManager then
		local ok, err = pcall(KillRewardManager.ProcessKill, player, mob, damageResult)
		if not ok then
			warn("[DamageHandler] KillRewardManager.ProcessKill error:", err)
		end
	elseif player then
		warn("[DamageHandler] KillRewardManager unavailable — rewards skipped for", player.Name)
	end

	if mob.Parent then
		mob:Destroy()
	end
end

--- §AGX/X12: damage that bypasses StatsManager.CalculateDamage (DoT ticks,
--- Thorns reflect) used to call humanoid:TakeDamage directly, so a kill
--- skipped HandleMobDeath: the corpse was never destroyed and paid no XP,
--- drops, weapon XP or achievements. Every raw-damage site goes through
--- here instead. `amount` is final (already scaled by the caller).
--- `sourcePlayer` is credited with the kill; nil / departed = no rewards,
--- but the mob is still cleaned up. Returns true if this call killed it.
function DamageHandler.ApplyRawDamage(mob, amount, sourcePlayer)
	if not mob or handledMobs[mob] then return false end
	local humanoid = mob:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	humanoid:TakeDamage(amount)
	if humanoid.Health > 0 then return false end

	if sourcePlayer and not sourcePlayer.Parent then
		sourcePlayer = nil
	end
	local mobId = mob:GetAttribute("MobId") or mob:GetAttribute("MobType") or "Unknown"
	DamageHandler.HandleMobDeath(mob, sourcePlayer, {
		damage  = amount,
		mobId   = mobId,
		mobTier = mob:GetAttribute("MobTier") or MobRegistry.GetMobTier(mobId) or "normal",
		isKill  = true,
	})
	return true
end

return DamageHandler