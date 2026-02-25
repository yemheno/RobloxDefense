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

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DamageHandler.Init()
	-- Pre-create damage number event
	NetworkManager.GetEvent("DamageNumber")

	-- Try to get HitTracker if it exists
	local HitTrackerModule = Modules:FindFirstChild("HitTracker")
	if HitTrackerModule then
		DamageHandler.HitTracker = require(HitTrackerModule)
	end

	print("[DamageHandler] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- DAMAGE APPLICATION
-- ═══════════════════════════════════════════════════════════

function DamageHandler.DamageMob(mob, player, options)
	options = options or {}

	local humanoid = mob:FindFirstChild("Humanoid")
	if not humanoid then return nil end

	-- Get mob info (CHANGED: use MobId attribute and MobRegistry)
	local mobId = mob:GetAttribute("MobId") or mob:GetAttribute("MobType") or "Unknown"
	local mobTier = mob:GetAttribute("MobTier") or MobRegistry.GetMobTier(mobId) or "normal"

	-- Resolve attack element:
	--   Skills set options.attackElement themselves.
	--   Basic attacks derive it from the player's equipped weapon.
	if not options.attackElement then
		local WeaponManagerModule = Modules:FindFirstChild("WeaponManager")
		if WeaponManagerModule then
			local WeaponManager = require(WeaponManagerModule)
			local weaponDef = WeaponManager.GetEquippedWeaponDef(player)
			options.attackElement = ElementalSystem.GetWeaponElement(weaponDef)
		end
	end

	-- Calculate damage using StatsManager (element mult applied inside)
	local damageResult = StatsManager.CalculateDamage(player, mob, options)
	local finalDamage = damageResult.damage

	-- Apply damage multiplier (for abilities)
	if options.damageMultiplier then
		finalDamage = finalDamage * options.damageMultiplier
		damageResult.damage = finalDamage
	end

	-- Apply damage
	humanoid:TakeDamage(finalDamage)

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

	-- Debug output
	DamageHandler.DebugPrint(mob, player, damageResult)

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
	local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))

	-- Player XP
	local xpReward = DamageHandler.GetXPReward(damageResult.mobTier)
	if xpReward > 0 then
		PlayerDataManager.AddExperience(player, xpReward)
	end

	-- Weapon XP (NEW!)
	local WeaponManagerModule = Modules:FindFirstChild("WeaponManager")
	if WeaponManagerModule then
		local WeaponManager = require(WeaponManagerModule)
		local mobLevel = mob:GetAttribute("Level") or 1
		local mobType = damageResult.mobTier == "miniboss" and "Mini" 
			or damageResult.mobTier == "boss" and "Boss" 
			or "Normal"

		local systems = WeaponManager.GetSystems()
		if systems and systems.XP then
			systems.XP.AddMobKillXP(player, mobLevel, mobType)
		end
	end

	-- Notify all clients
	NetworkManager.FireAllClients("MobDeath", {
		mobId = damageResult.mobId,
		mobTier = damageResult.mobTier,
		killerName = player.Name,
		position = mob:GetPivot().Position,
	})

	mob:Destroy()
	print("[DamageHandler] Mob killed by", player.Name, "- Tier:", damageResult.mobTier)
end

function DamageHandler.GetXPReward(mobTier)
	local rewards = {
		normal = 5,
		miniboss = 25,
		boss = 100,
	}
	return rewards[mobTier] or 5
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function DamageHandler.DebugPrint(mob, player, damageResult)
	local critText = ""
	if damageResult.wasCrit then
		critText = " (CRIT x" .. damageResult.critProcs .. "!)"
	end

	local humanoid = mob:FindFirstChild("Humanoid")
	local health = humanoid and humanoid.Health or 0

	local tierText = damageResult.mobTier ~= "normal" and " [" .. damageResult.mobTier:upper() .. "]" or ""

	print("[DamageHandler]", player.Name, "hit", (damageResult.mobId or "Unknown") .. tierText, 
		"for", math.floor(damageResult.damage), "damage!" .. critText, 
		"HP:", math.floor(health))
end

return DamageHandler