-- ServerScriptService/Modules/AttackHandler
-- Client-authoritative: clients detect hits locally and report them.
-- Server validates cooldowns, broadcasts attacks to other clients,
-- and applies damage from verified hit reports.

local AttackHandler = {}

local Players = game:GetService("Players")

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local ClassManager = require(Modules:WaitForChild("ClassManager"))

-- §T2/Z5 (§14b): per-player Janitor for the CharacterAdded +
-- DeathState-attribute connections wired in setupPlayerCharacterHandler.
-- Player destruction disconnects them in practice; tracking them keeps
-- AttackHandler consistent with the L1/L2 lifetime pattern.
local Janitor = require(Modules:WaitForChild("Janitor"))
local playerJanitors = setmetatable({}, { __mode = "k" })
local function getPlayerJanitor(player)
	local jan = playerJanitors[player]
	if not jan then
		jan = Janitor.new("AttackHandler.player")  -- §AGX/T11-JAN: JAN2 label
		playerJanitors[player] = jan
	end
	return jan
end

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

-- §AGX/STATS: AttackSpeed changes (buff expiry, Eagle Eye, Frenzy) are
-- pushed to the client via CombatConfig, which takes a round trip. For
-- this long after a change the server accepts the FASTER of the old and
-- new cadence, so a buff ending mid-swing doesn't get legit attacks
-- rejected. A debuff can be outrun for at most this window.
local ATTACK_SPEED_GRACE = 1.0
local graceCooldown = {}    -- [player] = pre-change cooldown (seconds)
local graceUntil    = {}    -- [player] = os.clock() deadline
local resendQueued  = {}    -- [player] = true while a stats resend is deferred

-- Range buffers (studs) to account for network latency and character movement
local MELEE_RANGE_BUFFER = 10
local RANGED_RANGE_BUFFER = 15

-- §AGX/X7: server-side enforcement of the Horde vote pause. HordePauseManager
-- sets the `HordePaused` attribute on workspace (world flag, covers players
-- who join mid-pause) and on every Player. Two attribute reads, no requires,
-- so it is safe on the hit hot path and a no-op in places without
-- HordePauseManager (the attribute is simply never set there).
local function isWorldPaused(player)
	if workspace:GetAttribute("HordePaused") == true then return true end
	return player ~= nil and player:GetAttribute("HordePaused") == true
end
AttackHandler.IsWorldPaused = isWorldPaused

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
		-- §AGX/T11-JAN: a player who joins between the PlayerAdded connect
		-- and the GetPlayers() loop below reached this twice and got two
		-- CharacterAdded + two DeathState handlers. Wire once per player.
		if playerJanitors[player] then return end
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

		local jan = getPlayerJanitor(player)
		jan:Add(player.CharacterAdded:Connect(function()
			resetAttackState()
			task.defer(function()
				AttackHandler.SendCombatConfig(player)
			end)
		end))
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
		jan:Add(player:GetAttributeChangedSignal("DeathState"):Connect(function()
			if player:GetAttribute("DeathState") == "Alive" then
				resetAttackState()
				task.defer(function()
					if player.Character then
						AttackHandler.SendCombatConfig(player)
					end
				end)
			end
		end))
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

	-- §AGX/STATS: AttackSpeed moved → open the transition grace and resend
	-- the client its pacing (coalesced: several sources changing in one
	-- frame send one CombatConfig).
	local bmMod = Modules:FindFirstChild("BonusManager")
	local okBM, BonusManager = false, nil
	if bmMod then okBM, BonusManager = pcall(require, bmMod) end
	if okBM and BonusManager and BonusManager.OnChanged then
		BonusManager.OnChanged(function(player, changed)
			local oldPct = changed.AttackSpeed
			if oldPct == nil or not player.Parent then return end
			local oldSpeed = ClassManager.GetAttackSpeed(player, oldPct)
			if oldSpeed and oldSpeed > 0 then
				graceCooldown[player] = 1 / oldSpeed
				graceUntil[player] = os.clock() + ATTACK_SPEED_GRACE
			end
			if resendQueued[player] then return end
			resendQueued[player] = true
			task.defer(function()
				resendQueued[player] = nil
				if player.Parent and player.Character then
					AttackHandler.SendCombatConfig(player, "stats")
				end
			end)
		end)
	end

end

-- ═══════════════════════════════════════════════════════════
-- COMBAT CONFIG (sent to client on spawn / class change)
-- ═══════════════════════════════════════════════════════════

-- §AGX/STATS: `reason = "stats"` marks a mid-combat pacing update (the
-- AttackSpeed bonus changed); the client keeps its attack timer instead
-- of resetting it, so the resend can't grant a free early swing.
function AttackHandler.SendCombatConfig(player, reason)
	local isRanged = ClassManager.IsRanged(player)
	local config = {
		isRanged   = isRanged,
		attackSpeed = ClassManager.GetAttackSpeed(player),
		animationId = ClassManager.GetBasicAttackAnimation(player),
		reason      = reason,
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

	-- §AGX/X7: no attacks while the Horde vote pause is active.
	if isWorldPaused(player) then return end

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

	-- §AGX/X31: relayed verbatim to every other client — accept only a
	-- finite Vector3 and normalise it (drops type-confused / huge payloads).
	local lookDirection = type(data) == "table" and data.lookDirection or nil
	if typeof(lookDirection) ~= "Vector3" then
		lookDirection = nil
	else
		local mag = lookDirection.Magnitude
		if mag > 1e-3 and mag < math.huge then
			lookDirection = lookDirection / mag
		else
			lookDirection = nil
		end
	end
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

	-- §AGX/X7: drop hit reports while the Horde vote pause is active
	-- (a modified client could otherwise keep hitting frozen mobs).
	if isWorldPaused(player) then return end

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

	-- §T2/Z1: VALIDATE FIRST, CONSUME AFTER. The old order marked the
	-- target + burned a hit slot BEFORE the alive/range checks, so a
	-- report invalidated by lag (mob died in flight, player moved) still
	-- consumed the slot and permanently dedup'd that target for the
	-- attack — the player's legit follow-up hit was rejected. Painful
	-- on pierce projectiles (maxHits 3).
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
	-- §AGX/X17: written fail-closed — a NaN distance (NaN position) made
	-- `distance > maxRange` false and accepted the hit from any range.
	if not (distance <= maxRange) then return end

	-- Hit accepted — consume the slot and mark the target.
	ticket.targetsHit[target] = true
	ticket.hitsUsed = ticket.hitsUsed + 1

	-- Apply damage (server-authoritative — no client-controlled multiplier)
	-- §AGX/X11: the swing's attackId lets every target of one cleave /
	-- pierce share the Spell Rhythm bonus (KeystoneRules.OutgoingHit).
	DamageHandler.DamageMob(target, player, { basicAttackId = attackId })
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

	-- §AGX/STATS: transition grace (see ATTACK_SPEED_GRACE).
	local gUntil = graceUntil[player]
	if gUntil then
		if now < gUntil then
			local prev = graceCooldown[player]
			if prev and prev < cooldown then cooldown = prev end
		else
			graceUntil[player] = nil
			graceCooldown[player] = nil
		end
	end

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
	graceCooldown[player] = nil  -- §AGX/STATS
	graceUntil[player] = nil
	resendQueued[player] = nil
	pendingAttacks[player] = nil
	lastAttackId[player] = nil
	-- §T2/Z5: tear down the per-player connections.
	local jan = playerJanitors[player]
	if jan then
		jan:Destroy()
		playerJanitors[player] = nil
	end
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