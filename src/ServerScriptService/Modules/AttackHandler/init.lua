-- ServerScriptService/Modules/AttackHandler

local AttackHandler = {}

local RunService = game:GetService("RunService")

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local ClassManager = require(Modules:WaitForChild("ClassManager"))

-- Child Systems
local ProjectileSystem
local MeleeSystem
local DamageHandler

-- Cooldown tracking
local playerCooldowns = {}

-- ═══════════════════════════════════════════════════════════
-- ATTACK DIRECTION CONFIG
-- ═══════════════════════════════════════════════════════════
--[[
    "Fixed"   = Always attack in a fixed direction (lane defense)
    "Facing"  = Attack in direction player is facing (boss fight)
]]
local ATTACK_DIRECTION_MODE = "Fixed"
local FIXED_DIRECTION = Vector3.new(1, 0, 0)  -- +X for lane defense

-- Get attack direction based on mode
function AttackHandler.GetAttackDirection(rootPart)
	if ATTACK_DIRECTION_MODE == "Fixed" then
		return FIXED_DIRECTION
	else
		-- Use player's facing direction (ignore Y)
		local lookVector = rootPart.CFrame.LookVector
		return Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	end
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function AttackHandler.Init()
	-- Load child systems
	DamageHandler = require(script:WaitForChild("DamageHandler"))
	ProjectileSystem = require(script:WaitForChild("ProjectileSystem"))
	MeleeSystem = require(script:WaitForChild("MeleeSystem"))

	-- Give child systems access
	ProjectileSystem.DamageHandler = DamageHandler
	ProjectileSystem.GetAttackDirection = AttackHandler.GetAttackDirection
	MeleeSystem.DamageHandler = DamageHandler
	MeleeSystem.GetAttackDirection = AttackHandler.GetAttackDirection

	-- Initialize child systems
	DamageHandler.Init()
	ProjectileSystem.Init()
	MeleeSystem.Init()

	-- Create network events (MUST create before listening!)
	NetworkManager.GetEvent("AttackEvent")       -- Client → Server (player attacks)
	NetworkManager.GetEvent("AttackActivated")   -- Server → Client (play animation)

	-- Listen for attack events
	NetworkManager.OnClientEvent("AttackEvent", function(player)
		AttackHandler.HandleAttack(player)
	end)

	-- Player cleanup
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		AttackHandler.RemovePlayer(player)
	end)

	-- Projectile update loop
	RunService.Heartbeat:Connect(function(dt)
		ProjectileSystem.Update(dt)
	end)

	print("[AttackHandler] Initialized - Direction Mode:", ATTACK_DIRECTION_MODE)
end

-- ═══════════════════════════════════════════════════════════
-- ATTACK HANDLING
-- ═══════════════════════════════════════════════════════════

function AttackHandler.HandleAttack(player)
	-- Check if player is casting and attacks are locked
	if player:GetAttribute("CastingLockAttack") then
		return
	end

	if not AttackHandler.CheckCooldown(player) then
		return
	end

	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local isRanged = ClassManager.IsRanged(player)

	-- Execute attack
	if isRanged then
		ProjectileSystem.Fire(player, rootPart)
	else
		MeleeSystem.Execute(player, rootPart)
	end

	-- Notify client to play animation
	AttackHandler.SendAttackActivated(player, isRanged)
end

-- ═══════════════════════════════════════════════════════════
-- ATTACK FEEDBACK
-- ═══════════════════════════════════════════════════════════

function AttackHandler.SendAttackActivated(player, isRanged)
	local animationId = ClassManager.GetBasicAttackAnimation(player)
	local attackSpeed = ClassManager.GetAttackSpeed(player)

	NetworkManager.FireClient(player, "AttackActivated", {
		animationId = animationId,
		attackType = isRanged and "Ranged" or "Melee",
		attackSpeed = attackSpeed,
	})
end

-- ═══════════════════════════════════════════════════════════
-- COOLDOWN MANAGEMENT
-- ═══════════════════════════════════════════════════════════

function AttackHandler.CheckCooldown(player)
	local now = tick()
	local cooldown = AttackHandler.GetCooldown(player)

	if playerCooldowns[player] and (now - playerCooldowns[player]) < cooldown then
		return false
	end

	playerCooldowns[player] = now
	return true
end

function AttackHandler.GetCooldown(player)
	return ClassManager.GetAttackCooldown(player)
end

function AttackHandler.RemovePlayer(player)
	playerCooldowns[player] = nil
	ProjectileSystem.RemovePlayer(player)
end

-- ═══════════════════════════════════════════════════════════
-- EXPOSE CHILD SYSTEMS
-- ═══════════════════════════════════════════════════════════

function AttackHandler.GetSystems()
	return {
		Projectiles = ProjectileSystem,
		Melee = MeleeSystem,
		Damage = DamageHandler,
	}
end

return AttackHandler