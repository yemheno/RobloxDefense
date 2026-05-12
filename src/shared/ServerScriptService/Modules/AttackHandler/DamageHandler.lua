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
		-- Queue until Init resolves KillRewardManager
		task.spawn(function()
			repeat task.wait(0.05) until KillRewardManager ~= nil
			KillRewardManager.OnMobKilled(callback)
		end)
	end
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DamageHandler.Init()
	-- Pre-create damage number event
	NetworkManager.GetEvent("DamageNumber")

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

function DamageHandler.SendDamageNumber(mob, player, damageResult)
	local rootPart = mob:FindFirstChild("HumanoidRootPart") or mob.PrimaryPart
	local position = rootPart and rootPart.Position or mob:GetPivot().Position

	local damageData = {
		position     = position,
		damage       = damageResult.damage,
		wasCrit      = damageResult.wasCrit,
		critProcs    = damageResult.critProcs,
		attackerName = player.Name,
		attackerUserId = player.UserId,
		-- Elemental (used for damage number colour)
		attackElement = damageResult.attackElement  or "None",
		elementLabel  = damageResult.elementLabel   or "Neutral",
		elementMult   = damageResult.elementMult    or 1.0,
	}

	NetworkManager.FireClient(player, "DamageNumber", damageData)

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			local showAll = otherPlayer:GetAttribute("ShowAllDamage")
			if showAll == true then
				NetworkManager.FireClient(otherPlayer, "DamageNumber", damageData)
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- MOB DEATH
-- ═══════════════════════════════════════════════════════════

function DamageHandler.HandleMobDeath(mob, player, damageResult)
	-- Delegate all reward logic (XP, drops, weapon XP, callbacks, client notify)
	-- to the centralised KillRewardManager.
	-- Wrapped in pcall so an error in reward processing never leaves a phantom mob.
	if KillRewardManager then
		local ok, err = pcall(KillRewardManager.ProcessKill, player, mob, damageResult)
		if not ok then
			warn("[DamageHandler] KillRewardManager.ProcessKill error:", err)
		end
	else
		warn("[DamageHandler] KillRewardManager unavailable — rewards skipped for", player.Name)
	end

	if mob and mob.Parent then
		mob:Destroy()
	end
end

return DamageHandler