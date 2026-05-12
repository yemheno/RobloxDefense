-- ServerScriptService/Modules/DeathSystem
--[[
    DeathSystem
    ===========
    Replaces default Roblox death with a two-phase downed state.

    Phase 1 — KNOCKED DOWN  (10 s)
        • Player drops to the ground (plays knockdown animation, then crawl loop).
        • Movement speed drastically reduced (crawl only).
        • Skills, attacks, and resource generation disabled.
        • Resource drains at −10 / s.
        • Client sees a red-hue overlay.
        • Other players (healers) can revive during this window.

    Phase 2 — DEAD
        • Player fully dies. Body stays on the ground.
        • Client sees grayscale overlay + Respawn button.
        • On respawn: teleport to spawn, restore HP, re-enable systems.

    Network Events:
        Server → Client:
            "DeathState"   { state = "KnockedDown" | "Dead" | "Alive" }
        Client → Server:
            "RequestRespawn"
]]

local DeathSystem = {}

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")

local Modules = script.Parent

-- Dependencies (set in Init)
local NetworkManager   = nil
local ResourceManager  = nil

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

local CONFIG = {
	KnockdownDuration   = 10,       -- seconds before death
	KnockdownSpeed      = 4,        -- WalkSpeed while downed (default is 16)
	ResourceDrainRate   = -10,      -- per second
	RespawnDelay        = 1,        -- brief delay after clicking respawn
}

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

-- { [player] = { state, knockdownTime, originalSpeed, diedConnection } }
local playerStates: { [Player]: { state: string, knockdownTime: number, originalSpeed: number, diedConnection: RBXScriptConnection? } } = {}

local initialized = false

-- ═══════════════════════════════════════════════════════════
-- ANIMATION IDS (R6 placeholders — replace with custom later)
-- ═══════════════════════════════════════════════════════════

local ANIM = {
	-- R6 placeholder animations (guaranteed visible)
	KnockdownFall = "rbxassetid://125750702",  -- Jump (collapse to ground)
	KnockdownCrawl = "rbxassetid://128777973", -- Wave (crawl loop)
}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DeathSystem.Init()
	if initialized then return end
	initialized = true

	NetworkManager  = require(Modules:WaitForChild("NetworkManager"))
	ResourceManager = require(Modules:WaitForChild("ResourceManager"))

	-- Disable automatic respawn
	Players.CharacterAutoLoads = false

	-- Network events
	NetworkManager.GetEvent("DeathState")
	NetworkManager.GetEvent("RequestRespawn")

	-- Listen for respawn requests
	NetworkManager.OnClientEvent("RequestRespawn", function(player)
		DeathSystem.HandleRespawnRequest(player)
	end)

	-- Setup existing players
	for _, player in ipairs(Players:GetPlayers()) do
		DeathSystem.SetupPlayer(player)
	end

	-- New players
	Players.PlayerAdded:Connect(function(player)
		DeathSystem.SetupPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		DeathSystem.CleanupPlayer(player)
	end)

	-- Tick loop for knockdown timer + resource drain
	RunService.Heartbeat:Connect(function(dt)
		DeathSystem.Update(dt)
	end)

end

-- ═══════════════════════════════════════════════════════════
-- PLAYER SETUP
-- ═══════════════════════════════════════════════════════════

function DeathSystem.SetupPlayer(player)
	playerStates[player] = {
		state          = "Alive" :: string,
		knockdownTime  = 0,
		originalSpeed  = 16,
		diedConnection = nil,
	}

	-- §LD-DS1 fix: set DeathState BEFORE the first character spawn so the
	-- attribute is replicated to the client by the time it tries to fire
	-- its first attack. Previously this only happened inside
	-- OnCharacterAdded after WaitForChild("Humanoid", 5), which left a
	-- ~0.5–1 s window where the client read DeathState=nil and silently
	-- aborted PlayerAttack.DoAttack ("not Alive" guard).
	player:SetAttribute("DeathState", "Alive")

	-- Spawn the character manually (since AutoLoads is off)
	player.CharacterAdded:Connect(function(character)
		DeathSystem.OnCharacterAdded(player, character)
	end)

	-- Initial spawn
	task.defer(function()
		player:LoadCharacter()
	end)
end

function DeathSystem.CleanupPlayer(player)
	local data = playerStates[player]
	if data and data.diedConnection then
		data.diedConnection:Disconnect()
	end
	playerStates[player] = nil
end

-- ═══════════════════════════════════════════════════════════
-- CHARACTER EVENTS
-- ═══════════════════════════════════════════════════════════

function DeathSystem.OnCharacterAdded(player, character)
	local data = playerStates[player]
	if not data then return end

	-- Reset state to alive
	data.state = "Alive"
	data.knockdownTime = 0

	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then return end

	-- Store default speed
	data.originalSpeed = humanoid.WalkSpeed

	-- §LD-DS2: disable EVERY way Roblox can tear down the character on
	-- death. Pablo's spec: the same Character must persist across
	-- knockdown → death → respawn. Recreating it via LoadCharacter is
	-- too risky — every visual (weapon, hair, armor, cosmetics) has to
	-- re-attach in the right order against the new model, and any
	-- timing race leaves the player without a weapon (which we hit
	-- yesterday). Keep the same character; just freeze it on death and
	-- teleport-in-place on respawn.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
	humanoid.BreakJointsOnDeath = false  -- prevent ragdoll piece-break at HP=0
	humanoid.RequiresNeck = false        -- some Roblox internal tear-down trips on neck removal

	-- Disable the default Roblox health-regen script ("Health") so we fully
	-- control when HP regenerates.  Without this, HP recovers from zero while
	-- the player is dead and mobs can kill them over and over.
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Script") and child.Name == "Health" then
			child.Disabled = true
		end
	end

	-- Disconnect old connection
	if data.diedConnection then
		data.diedConnection:Disconnect()
	end

	-- Listen for health reaching 0
	data.diedConnection = humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth <= 0 and data.state == "Alive" then
			DeathSystem.EnterKnockdown(player)
		end
	end)

	-- Publish state to a replicated attribute so clients can read it instantly
	player:SetAttribute("DeathState", "Alive")
	-- Notify client they're alive
	NetworkManager.FireClient(player, "DeathState", { state = "Alive" })
end

-- ═══════════════════════════════════════════════════════════
-- KNOCKDOWN (Phase 1)
-- ═══════════════════════════════════════════════════════════

function DeathSystem.EnterKnockdown(player)
	local data = playerStates[player]
	if not data then return end
	if data.state ~= "Alive" then return end

	data.state = "KnockedDown"
	data.knockdownTime = CONFIG.KnockdownDuration

	-- §LD-DS6: interrupt any active cast IMMEDIATELY on knockdown.
	-- Without this, the cast keeps ticking and CastingLockAttack /
	-- CastingLockSkills stay set until cast time elapses — and if the
	-- player is revived before that, the locks are still latched, so the
	-- first basic attack and skill press post-revive get silently swallowed
	-- by the lock check in AttackHandler.HandleAttack / PlayerAttack.DoAttack.
	-- Lazy require to avoid circular dependency at module load.
	local okSM, SkillManager = pcall(require, Modules:WaitForChild("SkillManager", 1))
	if okSM and SkillManager and SkillManager.InterruptCasting then
		pcall(SkillManager.InterruptCasting, player, "Knocked down")
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if not humanoid then return end

	-- §2.4a: disconnect HealthChanged while the player is no longer "Alive".
	-- During knockdown we pin HP back to 1 every Heartbeat, which would
	-- otherwise fire HealthChanged on every tick. The connection is only
	-- needed to detect the initial fall-to-zero from "Alive", so we can
	-- safely tear it down here and re-attach on character respawn or revive.
	-- LifeSteward's revive path works via RevivePlayer → OnCharacterAdded,
	-- neither of which relies on this connection being live during knockdown.
	if data.diedConnection then
		data.diedConnection:Disconnect()
		data.diedConnection = nil
	end

	-- Keep HP at 1 so the character doesn't enter Roblox death state
	humanoid.Health = 1

	-- Slow movement to crawl speed
	data.originalSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = CONFIG.KnockdownSpeed

	-- Disable jumping
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	-- Play knockdown animation
	DeathSystem.PlayAnimation(character, ANIM.KnockdownFall, false)
	task.delay(0.5, function()
		-- §2.4b: the captured `character` may be stale if a revive or respawn
		-- remounted the player in the 0.5s between the two animations. Verify
		-- identity (player.Character must still be the same model) and parent
		-- before playing the crawl loop; otherwise we'd play it on an old,
		-- soon-to-be-destroyed character.
		local currentData = playerStates[player]
		if currentData
			and currentData.state == "KnockedDown"
			and character.Parent
			and player.Character == character then
			DeathSystem.PlayAnimation(character, ANIM.KnockdownCrawl, true)
		end
	end)

	-- Publish state (replicates to client automatically)
	player:SetAttribute("DeathState", "KnockedDown")
	-- Notify client
	NetworkManager.FireClient(player, "DeathState", {
		state = "KnockedDown",
		duration = CONFIG.KnockdownDuration,
	})

	print("[DeathSystem]", player.Name, "knocked down —", CONFIG.KnockdownDuration, "s until death")
end

-- ═══════════════════════════════════════════════════════════
-- DEATH (Phase 2)
-- ═══════════════════════════════════════════════════════════

function DeathSystem.EnterDeath(player)
	local data = playerStates[player]
	if not data then return end

	data.state = "Dead"

	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if humanoid then
		-- Freeze the body in place
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		-- §LD-DS5: pin Health at 1, NOT 0. Even with Dead state and
		-- BreakJointsOnDeath disabled, Roblox's humanoid still tries to
		-- transition into Physics / PlatformStanding when Health hits 0,
		-- which leaves the humanoid in a state where :Move() input no
		-- longer translates the character (Pablo's "only moves via attack
		-- recoil"). Keeping Health > 0 keeps the humanoid in Running/
		-- GettingUp the entire time. The DeathState attribute is now the
		-- single source of truth for "is this player dead?" — every
		-- damage / interaction system reads it instead of humanoid.Health.
		humanoid.Health = 1
	end

	-- Stop all animations, body stays on ground
	DeathSystem.StopAllAnimations(character)

	-- Publish state (replicates to client automatically)
	player:SetAttribute("DeathState", "Dead")
	-- Notify client → grayscale + respawn button
	NetworkManager.FireClient(player, "DeathState", { state = "Dead" })

	print("[DeathSystem]", player.Name, "is dead — waiting for respawn")
end

-- ═══════════════════════════════════════════════════════════
-- REVIVE (from healer skill — restores during knockdown)
-- ═══════════════════════════════════════════════════════════

function DeathSystem.RevivePlayer(player, healthPercent, resourcePercent)
	local data = playerStates[player]
	if not data then return false end
	if data.state ~= "KnockedDown" then return false end

	-- §2.4c: defensive humanoid nil-guard. Even after a non-nil check it's
	-- possible for the character to be reparented or destroyed between this
	-- point and any later .Health write (CharacterRemoving races), so we
	-- also verify the character is still the player's current one and has
	-- a live Parent before mutating.
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if not humanoid or not character or not character.Parent or player.Character ~= character then
		warn("[DeathSystem] RevivePlayer: " .. player.Name ..
			" has no live humanoid/character — aborting revive.")
		return false
	end

	-- Restore HP
	local restoreHP = math.floor(humanoid.MaxHealth * (healthPercent or 0.7))
	humanoid.Health = restoreHP

	-- Restore resource
	if ResourceManager and resourcePercent and resourcePercent > 0 then
		local maxRes = ResourceManager.GetMaxResource(player)
		ResourceManager.SetResource(player, math.floor(maxRes * resourcePercent))
	end

	-- Restore movement
	humanoid.WalkSpeed = data.originalSpeed
	humanoid.JumpPower = 50
	humanoid.JumpHeight = 7.2

	-- Clear knockdown state
	data.state = "Alive"
	data.knockdownTime = 0

	-- §2.4a: re-attach HealthChanged so a second knockdown can fire. We
	-- disconnected it in EnterKnockdown to avoid spam while pinning HP at 1.
	if data.diedConnection then
		data.diedConnection:Disconnect()
	end
	data.diedConnection = humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth <= 0 and data.state == "Alive" then
			DeathSystem.EnterKnockdown(player)
		end
	end)

	-- Stop crawl animation
	DeathSystem.StopAllAnimations(character)

	-- Publish state (replicates to client automatically)
	player:SetAttribute("DeathState", "Alive")
	-- Notify client
	NetworkManager.FireClient(player, "DeathState", { state = "Alive" })

	print("[DeathSystem]", player.Name, "revived with", restoreHP, "HP")
	return true
end

-- ═══════════════════════════════════════════════════════════
-- RESPAWN (from UI button after death)
-- ═══════════════════════════════════════════════════════════

-- §LD-DS3: in-place respawn. Keep the SAME Character through the
-- knockdown → death → respawn cycle so we don't have to re-attach
-- every accessory/visual against a fresh model. Steps:
--   1. teleport HumanoidRootPart to the spawn location
--   2. restore Health → MaxHealth
--   3. restore movement (WalkSpeed, JumpPower, JumpHeight)
--   4. clear the DeathState attribute → "Alive"
-- The HealthChanged listener was disconnected during EnterKnockdown
-- (§2.4a) and reattached on revive — for full death we re-attach it
-- here too so the next damage burst can knock-down again.
local function findSpawnLocation()
	-- Prefer an explicit "PlayerSpawn" Part placed by the map; fall
	-- back to any SpawnLocation; final fallback is origin (rare,
	-- only if the place has no spawn at all).
	local explicit = workspace:FindFirstChild("PlayerSpawn")
	if explicit and explicit:IsA("BasePart") then
		return explicit.CFrame + Vector3.new(0, 4, 0)
	end
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("SpawnLocation") then
			return inst.CFrame + Vector3.new(0, 4, 0)
		end
	end
	return CFrame.new(0, 50, 0)
end

function DeathSystem.HandleRespawnRequest(player)
	local data = playerStates[player]
	if not data then return end
	if data.state ~= "Dead" then return end

	task.delay(CONFIG.RespawnDelay, function()
		if not player or not player.Parent then return end
		if not playerStates[player] then return end  -- left during delay

		local character = player.Character
		local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid then
			-- Edge case: character was destroyed by something external.
			-- Fall back to LoadCharacter so the player is at least playable;
			-- visual systems will re-attach via their CharacterAdded hooks.
			warn("[DeathSystem]", player.Name,
				"has no live character at respawn — falling back to LoadCharacter")
			player:LoadCharacter()
			return
		end

		-- §LD-DS4: order matters. The Heartbeat Update loop pins
		-- humanoid.Health = 0 while data.state == "Dead". So we MUST
		-- flip data.state to "Alive" BEFORE writing Health = MaxHealth,
		-- otherwise the very next Heartbeat tick wipes the heal we just
		-- did and the player ends up at HP 0 with state = Alive (which
		-- our re-attached HealthChanged listener then re-knocks-down).
		data.state = "Alive"
		data.knockdownTime = 0

		-- Teleport to spawn first so the player doesn't briefly stand
		-- alive at the death spot before being moved.
		pcall(function() character:PivotTo(findSpawnLocation()) end)

		-- §LD-DS4: clear every state Roblox can leave the humanoid in
		-- when Health hit 0 with BreakJointsOnDeath=false. Without these
		-- resets the character feels weightless and inputs do nothing
		-- because PlatformStand is true and the state machine is stuck
		-- in a non-Running state.
		humanoid.PlatformStand = false
		humanoid.Sit           = false
		humanoid.AutoRotate    = true

		-- Restore movement props.
		humanoid.WalkSpeed  = data.originalSpeed
		humanoid.JumpPower  = 50
		humanoid.JumpHeight = 7.2

		-- Make sure HumanoidRootPart isn't anchored. Mob skills with
		-- knockback could have anchored it during the knockdown window.
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.Anchored = false end

		-- Restore HP. With state already "Alive" the Update loop won't
		-- pin it back to 0 on the next Heartbeat.
		humanoid.Health = humanoid.MaxHealth

		-- Force a clean state transition out of Physics / PlatformStand
		-- and into Running. Without this the humanoid sometimes stays
		-- in a falling/floating state even after the props are reset.
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)

		-- Re-attach the HealthChanged listener for the next death cycle.
		if data.diedConnection then
			data.diedConnection:Disconnect()
		end
		data.diedConnection = humanoid.HealthChanged:Connect(function(newHealth)
			if newHealth <= 0 and data.state == "Alive" then
				DeathSystem.EnterKnockdown(player)
			end
		end)

		player:SetAttribute("DeathState", "Alive")
		NetworkManager.FireClient(player, "DeathState", { state = "Alive" })

		print("[DeathSystem]", player.Name, "respawned in-place")
	end)
end

-- ═══════════════════════════════════════════════════════════
-- UPDATE LOOP
-- ═══════════════════════════════════════════════════════════

function DeathSystem.Update(dt)
	for player, data in pairs(playerStates) do
		if data.state == "KnockedDown" then
			-- Count down
			data.knockdownTime = data.knockdownTime - dt

			-- Drain resource
			if ResourceManager then
				ResourceManager.ModifyResource(player, CONFIG.ResourceDrainRate * dt)
			end

			-- Keep HP pinned at 1 during knockdown so the Humanoid stays valid.
			-- Mobs are blocked from damaging knocked-down players via the
			-- DeathState attribute check in MobAI, so this pin is just a safety net.
			local character = player.Character
			local humanoid = character and character:FindFirstChild("Humanoid")
			if humanoid then
				humanoid.Health = math.max(humanoid.Health, 1)
			end

			-- Timer expired → full death
			if data.knockdownTime <= 0 then
				DeathSystem.EnterDeath(player)
			end

		elseif data.state == "Dead" then
			-- §LD-DS5: pin Health = 1 (not 0). Roblox's automatic regen
			-- script is already disabled in OnCharacterAdded; this just
			-- catches anything else (a heal effect, admin command) that
			-- would push Health up while the player is still in the Dead
			-- state. Damage is blocked via the DeathState attribute check
			-- in MobAI/DamageHandler, not via Health ≤ 0 anymore.
			local character = player.Character
			local humanoid = character and character:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health ~= 1 then
				humanoid.Health = 1
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- STATE QUERIES
-- ═══════════════════════════════════════════════════════════

function DeathSystem.GetState(player)
	local data = playerStates[player]
	return data and data.state or "Alive"
end

function DeathSystem.IsKnockedDown(player)
	return DeathSystem.GetState(player) == "KnockedDown"
end

function DeathSystem.IsDead(player)
	return DeathSystem.GetState(player) == "Dead"
end

function DeathSystem.IsAlive(player)
	return DeathSystem.GetState(player) == "Alive"
end

function DeathSystem.GetKnockdownTimeRemaining(player)
	local data = playerStates[player]
	if not data or data.state ~= "KnockedDown" then return 0 end
	return math.max(0, data.knockdownTime)
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATION HELPERS
-- ═══════════════════════════════════════════════════════════

function DeathSystem.PlayAnimation(character, animId, looped)
	if not character then return nil end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return nil end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId

	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = looped or false
	track:Play()

	return track
end

function DeathSystem.StopAllAnimations(character)
	if not character then return end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Priority == Enum.AnimationPriority.Action4 then
			track:Stop(0.3)
		end
	end
end

return DeathSystem
