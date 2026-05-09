-- ServerScriptService/Modules/AttackHandler
-- Client-authoritative: clients detect hits locally and report them.
-- Server validates cooldowns, broadcasts attacks to other clients,
-- and applies damage from verified hit reports.

local AttackHandler = {}

local Players = game:GetService("Players")

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local ClassManager = require(Modules:WaitForChild("ClassManager"))

-- Child Systems
local DamageHandler

-- Cooldown tracking
local playerCooldowns = {}

-- Attack ticket tracking (dedup + maxHits enforcement)
local pendingAttacks = {}   -- [player] = { [attackId] = { maxHits, hitsUsed, targetsHit, time } }
local lastAttackId   = {}   -- [player] = last accepted attackId (monotonic)

-- Config
local MAX_PENDING_TICKETS = 5       -- max tickets kept per player
local TICKET_EXPIRY_SECONDS = 5     -- tickets older than this are pruned
local MELEE_AOE_HIT_CAP = 20       -- generous cap for melee / AoE splash shapes

-- Range buffers (studs) to account for network latency and character movement
local MELEE_RANGE_BUFFER = 10
local RANGED_RANGE_BUFFER = 15

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function AttackHandler.Init()
	-- Load child systems
	DamageHandler = require(script:WaitForChild("DamageHandler"))
	DamageHandler.Init()

	-- Create network events
	NetworkManager.GetEvent("AttackEvent")       -- Client → Server (player attacked)
	NetworkManager.GetEvent("AttackFired")       -- Server → Other Clients (visual replication)
	NetworkManager.GetEvent("CombatConfig")      -- Server → Client (class combat data)
	NetworkManager.GetEvent("PlayerHitReport")   -- Client → Server (hit reports)

	-- Listen for attack events (cooldown tracking + broadcast)
	NetworkManager.OnClientEvent("AttackEvent", function(player, data)
		AttackHandler.HandleAttack(player, data)
	end)

	-- Listen for hit reports from clients
	NetworkManager.OnClientEvent("PlayerHitReport", function(player, data)
		AttackHandler.HandleHitReport(player, data)
	end)

	-- Client-side re-request after spawn (handles the race condition where
	-- CombatConfig was fired before the client registered its OnServerEvent listener)
	NetworkManager.GetEvent("RequestCombatConfig")
	NetworkManager.OnClientEvent("RequestCombatConfig", function(player)
		if player.Character then
			AttackHandler.SendCombatConfig(player)
		end
	end)

	-- Setup CharacterAdded handler for all players (new and existing)
	local function setupPlayerCharacterHandler(player)
		-- §A2 helper: clear all attack-ticket state for a fresh "spawn".
		-- The monotonic attackId guard prevents replay attacks WITHIN a
		-- character lifetime, but the client legitimately resets its
		-- counter back to 1 on respawn (PlayerAttack module re-runs).
		-- Without clearing here, lastAttackId stays at the old session's
		-- high-water mark and every post-respawn attack is rejected by
		-- the `attackId <= prev` check until the client outpaces it.
		-- Pablo's "sometimes can't attack at all" reproduces here.
		local function resetAttackState()
			lastAttackId[player] = nil
			pendingAttacks[player] = nil
			playerCooldowns[player] = nil
		end

		player.CharacterAdded:Connect(function()
			resetAttackState()
			task.defer(function()
				AttackHandler.SendCombatConfig(player)
			end)
		end)
		-- If player already has character, send config immediately
		if player.Character then
			task.defer(function()
				AttackHandler.SendCombatConfig(player)
			end)
		end
		-- §A3 fix: in-place respawn (DeathSystem §LD-DS5) preserves the same
		-- Character instance, so CharacterAdded never fires on revive. Listen
		-- on the DeathState attribute instead and reset whenever the player
		-- transitions back to "Alive" (covers both KnockedDown→Alive recovery
		-- and Dead→Alive respawn). PlayerAttack on the client also resets its
		-- attackId counter on these transitions, so the server must mirror
		-- that to avoid `attackId <= lastAttackId` rejections.
		player:GetAttributeChangedSignal("DeathState"):Connect(function()
			if player:GetAttribute("DeathState") == "Alive" then
				resetAttackState()
				task.defer(function()
					if player.Character then
						AttackHandler.SendCombatConfig(player)
					end
				end)
			end
		end)
	end

	-- Handle future joins
	Players.PlayerAdded:Connect(setupPlayerCharacterHandler)

	-- Handle players who already joined before Init ran
	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayerCharacterHandler(player)
	end

	-- Player cleanup
	Players.PlayerRemoving:Connect(function(player)
		AttackHandler.RemovePlayer(player)
	end)

	print("[AttackHandler] Initialized (Client-Auth)")
end

-- ═══════════════════════════════════════════════════════════
-- COMBAT CONFIG (sent to client on spawn / class change)
-- ═══════════════════════════════════════════════════════════

function AttackHandler.SendCombatConfig(player)
	local isRanged = ClassManager.IsRanged(player)
	local config = {
		isRanged   = isRanged,
		attackSpeed = ClassManager.GetAttackSpeed(player),
		animationId = ClassManager.GetBasicAttackAnimation(player),
	}

	if isRanged then
		config.projectile = ClassManager.GetProjectileConfig(player)
	else
		config.attackShape = ClassManager.GetAttackShape(player)
		config.shapeParams = ClassManager.GetShapeParams(player)
	end

	NetworkManager.FireClient(player, "CombatConfig", config)
end

-- ═══════════════════════════════════════════════════════════
-- ATTACK TICKETS
-- ═══════════════════════════════════════════════════════════

--- Compute the maximum number of hit reports a single attack can produce.
function AttackHandler.GetMaxHitsForAttack(player)
	if ClassManager.IsRanged(player) then
		local projectile = ClassManager.GetProjectileConfig(player)
		if projectile then
			if projectile.type == "Pierce" then
				return projectile.maxHits or 1
			end
			-- AoE splash can hit many
			return MELEE_AOE_HIT_CAP
		end
		return 1
	end
	-- Melee shapes (Cone, Circle, etc.) can hit many mobs
	return MELEE_AOE_HIT_CAP
end

--- Prune expired and overflow tickets for a player.
-- §A1: keep evicting oldest until under cap. The previous version
-- evicted one ticket per call, so a flood of attackIds in one frame
-- could grow the table arbitrarily until many subsequent prunes ran.
local function pruneTickets(player)
	local tickets = pendingAttacks[player]
	if not tickets then return end
	local now = os.clock()

	-- First pass: drop expired tickets and count.
	local count = 0
	for id, ticket in pairs(tickets) do
		if now - ticket.time > TICKET_EXPIRY_SECONDS then
			tickets[id] = nil
		else
			count = count + 1
		end
	end

	-- Second pass: while still over cap, evict the single oldest each loop.
	while count > MAX_PENDING_TICKETS do
		local oldest, oldestId
		for id, ticket in pairs(tickets) do
			if not oldest or ticket.time < oldest then
				oldest = ticket.time
				oldestId = id
			end
		end
		if not oldestId then break end
		tickets[oldestId] = nil
		count = count - 1
	end
end

-- ═══════════════════════════════════════════════════════════
-- ATTACK HANDLING (cooldown + ticket + broadcast to others)
-- ═══════════════════════════════════════════════════════════

function AttackHandler.HandleAttack(player, data)
	-- Block attacks from knocked-down or dead players
	if player:GetAttribute("DeathState") ~= "Alive" then return end

	-- Casting lock
	if player:GetAttribute("CastingLockAttack") then return end

	if not AttackHandler.CheckCooldown(player) then return end

	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	-- Register attack ticket
	local attackId = data and data.attackId
	if attackId ~= nil then
		if not pendingAttacks[player] then
			pendingAttacks[player] = {}
		end
		pruneTickets(player)
		-- Monotonic: reject attackIds that are not strictly increasing
		if type(attackId) ~= "number" then return end
		local prev = lastAttackId[player] or 0
		if attackId <= prev then return end
		lastAttackId[player] = attackId

		pendingAttacks[player][attackId] = {
			maxHits    = AttackHandler.GetMaxHitsForAttack(player),
			hitsUsed   = 0,
			targetsHit = {},  -- [target instance] = true  (per-target dedup)
			time       = os.clock(),
		}
	end

	local lookDirection = data and data.lookDirection
	local isRanged = ClassManager.IsRanged(player)

	-- Broadcast to other clients for visual replication
	AttackHandler.BroadcastAttack(player, isRanged, lookDirection)
end

-- ═══════════════════════════════════════════════════════════
-- BROADCAST (other clients see the attack visually)
-- ═══════════════════════════════════════════════════════════

function AttackHandler.BroadcastAttack(player, isRanged, lookDirection)
	local character = player.Character
	local animationId = ClassManager.GetBasicAttackAnimation(player)
	local attackSpeed = ClassManager.GetAttackSpeed(player)

	local payload = {
		character = character,
		animationId = animationId,
		attackSpeed = attackSpeed,
		isRanged = isRanged,
		lookDirection = lookDirection,
	}

	if isRanged then
		payload.projectileConfig = ClassManager.GetProjectileConfig(player)
	end

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			NetworkManager.FireClient(otherPlayer, "AttackFired", payload)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- HIT REPORT HANDLING (client reports a mob hit)
-- ═══════════════════════════════════════════════════════════

function AttackHandler.HandleHitReport(player, data)
	-- Block hit reports from knocked-down or dead players
	if player:GetAttribute("DeathState") ~= "Alive" then return end

	-- Must have attacked recently
	if not playerCooldowns[player] then return end

	-- Validate attack ticket
	local attackId = data.attackId
	local tickets = pendingAttacks[player]
	if not tickets or attackId == nil then return end
	local ticket = tickets[attackId]
	if not ticket then return end
	if ticket.hitsUsed >= ticket.maxHits then return end

	local target = data.target
	if not target or not target.Parent then return end
	if not target:GetAttribute("IsMob") then return end

	-- Per-target dedup: reject repeated hits on the same mob within one attack
	if ticket.targetsHit[target] then return end
	ticket.targetsHit[target] = true
	ticket.hitsUsed = ticket.hitsUsed + 1

	local humanoid = target:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Basic range validation (generous buffer for latency)
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local mobRoot = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
	if not mobRoot then return end

	local distance = (rootPart.Position - mobRoot.Position).Magnitude
	local maxRange = AttackHandler.GetMaxBasicAttackRange(player)
	if distance > maxRange then return end

	-- Apply damage (server-authoritative — no client-controlled multiplier)
	DamageHandler.DamageMob(target, player, {})
end

-- ═══════════════════════════════════════════════════════════
-- RANGE VALIDATION
-- ═══════════════════════════════════════════════════════════

--- Compute the maximum valid hit distance for a player's basic attack.
--- Melee: shape range + buffer.  Ranged: projectile speed * lifetime + buffer.
function AttackHandler.GetMaxBasicAttackRange(player)
	if ClassManager.IsRanged(player) then
		local projectile = ClassManager.GetProjectileConfig(player)
		if projectile and projectile.speed and projectile.lifetime then
			return projectile.speed * projectile.lifetime + RANGED_RANGE_BUFFER
		end
		return 120 -- safe fallback for ranged
	else
		local shapeParams = ClassManager.GetShapeParams(player)
		local range = shapeParams and shapeParams.range or 10
		return range + MELEE_RANGE_BUFFER
	end
end

-- ═══════════════════════════════════════════════════════════
-- COOLDOWN MANAGEMENT
-- ═══════════════════════════════════════════════════════════

function AttackHandler.CheckCooldown(player)
	local now = os.clock()
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
	pendingAttacks[player] = nil
	lastAttackId[player] = nil
end

-- ═══════════════════════════════════════════════════════════
-- EXPOSE CHILD SYSTEMS
-- ═══════════════════════════════════════════════════════════

function AttackHandler.GetSystems()
	return {
		Damage = DamageHandler,
	}
end

return AttackHandler