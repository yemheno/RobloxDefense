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
            "WipeReviveOffer" / "WipeReviveResolved"  (§DISC/D3b)
        Client → Server:
            "RequestRespawn"
            "WipeReviveAccept"
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

	-- §DISC/D3b, §AGX/X40 (Pablo): party-wipe revive failsafe. On full wipe
	-- the game pauses (mobs + spawns) and players get a decision window to
	-- revive in place; otherwise the run ends. Free wipe-revives per run by
	-- difficulty, then ONE Essence-paid revive, shown only to players who can
	-- already afford it (no upsell under a countdown). Never a Robux product
	-- (DESIGN_DECISIONS.md#disc-decisions, DISC-D3b: won't do).
	WipeGraceSeconds    = 15,
	WipeReviveEssence   = 25,       -- placeholder price, tune freely
	WipeInvulnSeconds   = 3,        -- invulnerability after wipe-revive
	FreeWipeRevives     = { Normal = 3, Hard = 2, Nightmare = 1 },
	FreeWipeReviveDefault = 1,      -- unknown difficulty → strictest
	PaidWipeRevivesPerRun = 1,
}

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

-- { [player] = { state, knockdownTime, originalSpeed, diedConnection,
--   characterAddedConn (§T4/V1), respawnQueued (§T4/V2) } }
local playerStates: { [Player]: { state: string, knockdownTime: number, originalSpeed: number, diedConnection: RBXScriptConnection?, characterAddedConn: RBXScriptConnection?, respawnQueued: boolean? } } = {}

local initialized = false

-- §DISC/D3b: wipe-grace state. `token` invalidates the pending defeat
-- timer when a revive resolves the wipe first.
local wipeGraceActive = false
local wipeGraceToken  = 0
local wipeGraceEndsAt = 0

-- §AGX/X40: per-run revive budget; reset when a run starts (PREPARING).
local freeWipeRevivesUsed = 0
local paidWipeRevivesUsed = 0


-- Lazy sibling getters (avoid load-order coupling)
local _CurrencyManager
local function getCurrencyManager()
	if _CurrencyManager ~= nil then return _CurrencyManager or nil end
	local mod = Modules:FindFirstChild("CurrencyManager")
	-- §AGX/D-FIX: two-step pcall; `x and pcall(...)` keeps only ONE value.
	local ok, result = false, nil
	if mod then ok, result = pcall(require, mod) end
	_CurrencyManager = (ok and result) or false
	return _CurrencyManager or nil
end

local _MobAI
local function getMobAI()
	if _MobAI ~= nil then return _MobAI or nil end
	local mod = Modules:FindFirstChild("MobAI")
	-- §AGX/D-FIX: two-step pcall; `x and pcall(...)` keeps only ONE value.
	local ok, result = false, nil
	if mod then ok, result = pcall(require, mod) end
	_MobAI = (ok and result) or false
	return _MobAI or nil
end

-- §AGX/STATS: MovementSpeed bonus → BaseWalkSpeed. Lazy (ARCHITECTURE.md#lazy-getter); only
-- touched on spawn and on a MovementSpeed change, never per frame.
local _BonusManager
local function getBonusManager()
	if _BonusManager ~= nil then return _BonusManager or nil end
	local mod = Modules:FindFirstChild("BonusManager")
	-- §AGX/D-FIX: two-step pcall; `x and pcall(...)` keeps only ONE value.
	local ok, result = false, nil
	if mod then ok, result = pcall(require, mod) end
	_BonusManager = (ok and result) or false
	return _BonusManager or nil
end

local _DataConfig
local function getDataConfig()
	if _DataConfig ~= nil then return _DataConfig or nil end
	local mod = Modules:FindFirstChild("PlayerDataConfig")
	-- §AGX/D-FIX: two-step pcall; `x and pcall(...)` keeps only ONE value.
	local ok, result = false, nil
	if mod then ok, result = pcall(require, mod) end
	_DataConfig = (ok and result) or false
	return _DataConfig or nil
end

-- §AGX/STATS: natural speed (stamped once per character as
-- "NaturalWalkSpeed") × (1 + capped MovementSpeed %). This is the X13
-- "BaseWalkSpeed": MobAI slows/stuns, cast locks and knockdown all work
-- from it, so they stack on top of the bonus instead of replacing it.
local function computeBaseWalkSpeed(player, humanoid)
	local natural = humanoid:GetAttribute("NaturalWalkSpeed") or 16
	local bm  = getBonusManager()
	local cfg = getDataConfig()
	local pct = bm and bm.GetAggregatedBonus(player, "MovementSpeed") or 0
	if cfg and cfg.CapStat then pct = cfg.CapStat("MovementSpeed", pct) end
	return natural * (1 + pct / 100)
end

-- §AGX/X40 helpers (after the lazy getters they use).
local function getRunDifficulty()
	local mod = Modules:FindFirstChild("TeleportDataReader")
	-- §AGX/D-FIX: two-step pcall; `x and pcall(...)` keeps only ONE value.
	local ok, tdr = false, nil
	if mod then ok, tdr = pcall(require, mod) end
	local diff = ok and tdr and tdr.GetDifficulty and tdr.GetDifficulty()
	return type(diff) == "string" and diff or "Normal"
end

local function freeWipeRevivesLeft()
	local cap = CONFIG.FreeWipeRevives[getRunDifficulty()] or CONFIG.FreeWipeReviveDefault
	return math.max(0, cap - freeWipeRevivesUsed)
end

local function paidWipeRevivesLeft()
	return math.max(0, CONFIG.PaidWipeRevivesPerRun - paidWipeRevivesUsed)
end

-- Per-player offer: free if any left; otherwise paid only for players who
-- can afford it and only while the per-run paid budget remains.
local function buildWipeOffer(player)
	local free = freeWipeRevivesLeft()
	if free > 0 then
		return { kind = "free", freeLeft = free, seconds = math.max(0, wipeGraceEndsAt - os.clock()) }
	end
	if paidWipeRevivesLeft() > 0 then
		local cm = getCurrencyManager()
		local canPay = cm and cm.CanAffordEssence and cm.CanAffordEssence(player, CONFIG.WipeReviveEssence)
		if canPay then
			return { kind = "paid", cost = CONFIG.WipeReviveEssence, seconds = math.max(0, wipeGraceEndsAt - os.clock()) }
		end
	end
	return { kind = "none", seconds = math.max(0, wipeGraceEndsAt - os.clock()) }
end

local function getHordePauseManager()
	local sss = game:GetService("ServerScriptService")
	local folder = sss:FindFirstChild("HordeMode")
	local mods = folder and folder:FindFirstChild("Modules")
	local mod = mods and mods:FindFirstChild("HordePauseManager")
	if not mod then return nil end
	local ok, result = pcall(require, mod)
	return ok and result or nil
end

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

	-- §AGX/X40: reset the per-run wipe-revive budget when a run starts.
	-- Deferred so GameStateManager (combat places only) is loaded first.
	task.defer(function()
		local gsmMod = Modules:FindFirstChild("GameStateManager")
		-- §AGX/D-FIX: two-step pcall; `x and pcall(...)` keeps only ONE value.
		local ok, gsm = false, nil
		if gsmMod then ok, gsm = pcall(require, gsmMod) end
		if ok and gsm and gsm.OnStateChanged then
			gsm.OnStateChanged(function(newState)
				if newState == "Preparing" then
					freeWipeRevivesUsed = 0
					paidWipeRevivesUsed = 0
				end
			end)
		end
	end)

	-- §DISC/D3b: wipe-revive events
	NetworkManager.GetEvent("WipeReviveOffer")
	NetworkManager.GetEvent("WipeReviveResolved")
	NetworkManager.GetEvent("WipeReviveAccept")
	NetworkManager.OnClientEvent("WipeReviveAccept", function(player)
		DeathSystem.HandleWipeRevive(player)
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

	-- §AGX/STATS: re-derive BaseWalkSpeed when MovementSpeed changes
	-- (gear, talents, innate, cards, Swiftness Elixir, keystones).
	local bm = getBonusManager()
	if bm and bm.OnChanged then
		bm.OnChanged(function(player, changed)
			if changed.MovementSpeed ~= nil then
				DeathSystem.RefreshMoveSpeed(player)
			end
		end)
	end

end

--- §AGX/STATS: recompute BaseWalkSpeed and apply it without fighting the
--- other WalkSpeed owners. Downed/dead: only the attribute moves (revive
--- and respawn read it). Alive: MobAI's recompute applies it, honouring an
--- active Stun/Slow and a CastMoveLock.
function DeathSystem.RefreshMoveSpeed(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid:GetAttribute("NaturalWalkSpeed") == nil then return end

	local base = computeBaseWalkSpeed(player, humanoid)
	if humanoid:GetAttribute("BaseWalkSpeed") == base then return end
	humanoid:SetAttribute("BaseWalkSpeed", base)

	local data = playerStates[player]
	if data and data.state ~= "Alive" then return end

	local mobAI = getMobAI()
	if mobAI and mobAI.RecomputePlayerMoveSpeed then
		mobAI.RecomputePlayerMoveSpeed(player, humanoid)
	elseif not humanoid:GetAttribute("CastMoveLock") and humanoid:GetAttribute("MoveFxSpeed") == nil then
		humanoid.WalkSpeed = base
	end
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

	-- §LD-DS1: set DeathState BEFORE the first character spawn so the
	-- attribute has replicated by the client's first attack; a nil
	-- DeathState fails PlayerAttack.DoAttack's "not Alive" guard.
	player:SetAttribute("DeathState", "Alive")

	-- Spawn the character manually (since AutoLoads is off)
	-- §T4/V1, §14b: tracked so CleanupPlayer can disconnect it.
	playerStates[player].characterAddedConn = player.CharacterAdded:Connect(function(character)
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
	-- §T4/V1: disconnect the per-player CharacterAdded hook too.
	if data and data.characterAddedConn then
		data.characterAddedConn:Disconnect()
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
	-- §AGX/X13: the character's natural speed, read by MobAI's player
	-- Stun/Slow recompute and SkillManager's cast-lock restore.
	-- §AGX/STATS: stamp the untouched speed as NaturalWalkSpeed and fold
	-- the MovementSpeed bonus into BaseWalkSpeed.
	humanoid:SetAttribute("NaturalWalkSpeed", humanoid.WalkSpeed)
	local baseSpeed = computeBaseWalkSpeed(player, humanoid)
	humanoid:SetAttribute("BaseWalkSpeed", baseSpeed)
	humanoid.WalkSpeed = baseSpeed
	data.originalSpeed = baseSpeed

	-- §LD-DS2: disable EVERY way Roblox can tear down the character on
	-- death. Pablo's spec: the same Character must persist across
	-- knockdown → death → respawn. Recreating it via LoadCharacter would
	-- re-attach every visual (weapon, hair, armor, cosmetics) against a new
	-- model, and a timing race there leaves the player without a weapon.
	-- Keep the same character; freeze it on death, teleport on respawn.
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
	-- §AGX/X13: capture the natural speed, not a mob-slowed/stunned one,
	-- or revive would restore the debuffed speed permanently.
	data.originalSpeed = humanoid:GetAttribute("BaseWalkSpeed") or humanoid.WalkSpeed
	humanoid:SetAttribute("StunUntil", nil)
	humanoid:SetAttribute("MoveFxSpeed", nil)
	local mobAI = getMobAI()
	if mobAI and mobAI.ClearPlayerMoveEffects then
		mobAI.ClearPlayerMoveEffects(humanoid)
	end
	player:SetAttribute("IsStunned", nil)
	player:SetAttribute("IsSlowed", nil)
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
		-- BreakJointsOnDeath disabled, a humanoid at Health 0 drops into
		-- Physics / PlatformStanding and :Move() input stops working.
		-- The DeathState attribute is the single source of truth for "is
		-- this player dead?"; damage / interaction systems read it, not Health.
		humanoid.Health = 1
	end

	-- Stop all animations, body stays on ground
	DeathSystem.StopAllAnimations(character)

	-- Publish state (replicates to client automatically)
	player:SetAttribute("DeathState", "Dead")
	-- Notify client → grayscale + respawn button
	NetworkManager.FireClient(player, "DeathState", { state = "Dead" })

	print("[DeathSystem]", player.Name, "is dead — waiting for respawn")

	-- §DISC/D3: full party wipe ends the run.
	DeathSystem.CheckPartyWipe()
end

-- §DISC/D3 + §DISC/D3b (Pablo): when EVERY player in the server is
-- Dead, the game pauses immediately (mobs AND spawns — same freeze the
-- card votes use) and players get CONFIG.WipeGraceSeconds to take a
-- revive-in-place (free or paid, §AGX/X40). If someone revives: they come
-- back where they died with brief invulnerability and the fight resumes.
-- If nobody does, the run ends — everyone back to the lobby. Free respawn
-- is disabled during the window (the wipe-revive is the only out).
-- NOTE: a SOLO death triggers this immediately (no teammate to outlive).
function DeathSystem.CheckPartyWipe()
	if wipeGraceActive then return end
	local all = Players:GetPlayers()
	if #all == 0 then return end
	for _, p in ipairs(all) do
		local st = playerStates[p]
		if not st or st.state ~= "Dead" then return end
	end

	-- GameStateManager is only loaded in combat places; lobby/plaza no-op.
	local gsmMod = Modules:FindFirstChild("GameStateManager")
	if not gsmMod then return end
	local ok, gsm = pcall(require, gsmMod)
	if not ok or not gsm or not gsm.TriggerDefeat then return end
	if gsm.IsInGame and not gsm.IsInGame() then return end

	warn(string.format(
		"[DeathSystem] PARTY WIPE — pausing; %ds revive window (§DISC/D3b)",
		CONFIG.WipeGraceSeconds))

	wipeGraceActive = true
	wipeGraceToken += 1
	wipeGraceEndsAt = os.clock() + CONFIG.WipeGraceSeconds
	local myToken = wipeGraceToken

	-- Freeze combat: mob AI + movement everywhere; HordeMode also stops
	-- its spawner/markers via the pause manager. (Lane wave spawns that
	-- land during the window stand idle — MobAI.Update is pause-gated.)
	local mobAI = getMobAI()
	if mobAI and mobAI.SetPaused then pcall(mobAI.SetPaused, true) end
	local hpm = getHordePauseManager()
	if hpm and hpm.Pause then pcall(hpm.Pause) end

	-- §AGX/X40: nothing left to offer → end the run now (no dead-air
	-- countdown with no options).
	if freeWipeRevivesLeft() == 0 and paidWipeRevivesLeft() == 0 then
		wipeGraceActive = false
		if mobAI and mobAI.SetPaused then pcall(mobAI.SetPaused, false) end
		if hpm and hpm.Resume then pcall(hpm.Resume) end
		NetworkManager.FireAllClients("WipeReviveResolved", { revived = false })
		gsm.TriggerDefeat()
		return
	end

	-- §AGX/X40: per-player offer (free / paid-if-affordable / none).
	for _, p in ipairs(all) do
		NetworkManager.FireClient(p, "WipeReviveOffer", buildWipeOffer(p))
	end

	task.delay(CONFIG.WipeGraceSeconds, function()
		if not wipeGraceActive or wipeGraceToken ~= myToken then return end
		wipeGraceActive = false
		NetworkManager.FireAllClients("WipeReviveResolved", { revived = false })
		gsm.TriggerDefeat()
	end)
end

-- §AGX/X50: forward-declared — defined below (search `function performRevive`).
-- HandleWipeRevive calls it after spending Essence; an undeclared local
-- would be a nil global there and soft-lock the run.
local performRevive

-- §DISC/D3b: a dead player accepts the wipe-revive offer. First
-- successful payment wins the run back; the buyer revives IN PLACE
-- with brief invulnerability and combat resumes for everyone.
function DeathSystem.HandleWipeRevive(player)
	if not wipeGraceActive then return end
	local data = playerStates[player]
	if not data or data.state ~= "Dead" then return end

	-- §AGX/X40: free revives first; the paid one only once they're gone.
	local usedFree = false
	if freeWipeRevivesLeft() > 0 then
		freeWipeRevivesUsed += 1
		usedFree = true
	else
		if paidWipeRevivesLeft() <= 0 then return end
		local cm = getCurrencyManager()
		if not cm or not cm.SpendEssence then return end
		if not cm.SpendEssence(player, CONFIG.WipeReviveEssence) then
			-- Personal denial — re-offer with the reason + remaining time.
			local offer = buildWipeOffer(player)
			offer.denied = "Not enough Essence"
			NetworkManager.FireClient(player, "WipeReviveOffer", offer)
			return
		end
		paidWipeRevivesUsed += 1
	end

	-- Revive granted → resolve the wipe.
	wipeGraceActive = false
	wipeGraceToken += 1  -- invalidates the pending defeat timer

	performRevive(player, false)  -- in place, per design

	-- Invulnerability window.
	player:SetAttribute("WipeInvulnerable", true)
	task.delay(CONFIG.WipeInvulnSeconds, function()
		if player and player.Parent then
			player:SetAttribute("WipeInvulnerable", nil)
		end
	end)

	-- Resume combat.
	local mobAI = getMobAI()
	if mobAI and mobAI.SetPaused then pcall(mobAI.SetPaused, false) end
	local hpm = getHordePauseManager()
	if hpm and hpm.Resume then pcall(hpm.Resume) end

	NetworkManager.FireAllClients("WipeReviveResolved", {
		revived = true,
		name    = player.Name,
		free    = usedFree,
	})
	print("[DeathSystem]", player.Name, usedFree and "used a free wipe-revive" or "bought the wipe-revive",
		"— run continues (free used", freeWipeRevivesUsed, "/ paid used", paidWipeRevivesUsed, ")")
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
	-- §AGX/STATS: BaseWalkSpeed may have moved while downed (a buff
	-- expired); mob effects were cleared at knockdown, so base is right.
	humanoid.WalkSpeed = humanoid:GetAttribute("BaseWalkSpeed") or data.originalSpeed
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
local cachedSpawnLocation = nil
local function findSpawnLocation()
	-- Prefer an explicit "PlayerSpawn" Part placed by the map; fall
	-- back to any SpawnLocation; final fallback is origin (rare,
	-- only if the place has no spawn at all).
	local explicit = workspace:FindFirstChild("PlayerSpawn")
	if explicit and explicit:IsA("BasePart") then
		return explicit.CFrame + Vector3.new(0, 4, 0)
	end
	-- §AGX/X36: cache the SpawnLocation; the full GetDescendants() walk
	-- hitches when several players respawn together.
	if not (cachedSpawnLocation and cachedSpawnLocation:IsDescendantOf(workspace)) then
		cachedSpawnLocation = nil
		for _, inst in ipairs(workspace:GetDescendants()) do
			if inst:IsA("SpawnLocation") then
				cachedSpawnLocation = inst
				break
			end
		end
	end
	if cachedSpawnLocation then
		return cachedSpawnLocation.CFrame + Vector3.new(0, 4, 0)
	end
	return CFrame.new(0, 50, 0)
end

-- §DISC/D3b: revive core, shared by the normal respawn (teleports to
-- spawn) and the wipe-revive (revives IN PLACE).
function performRevive(player, teleportToSpawn)
	if not player or not player.Parent then return end
	local data = playerStates[player]
	if not data then return end

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

	-- §LD-DS4, §LD-DS5: order matters. The Heartbeat Update loop pins
	-- humanoid.Health = 1 while data.state == "Dead", so flip data.state
	-- to "Alive" BEFORE writing Health = MaxHealth, or the next tick
	-- overwrites the heal.
	data.state = "Alive"
	data.knockdownTime = 0

	if teleportToSpawn then
		-- Teleport to spawn first so the player doesn't briefly stand
		-- alive at the death spot before being moved.
		pcall(function() character:PivotTo(findSpawnLocation()) end)
	end

		-- §LD-DS4: clear every state Roblox can leave the humanoid in
		-- when Health hit 0 with BreakJointsOnDeath=false. Without these
		-- resets the character feels weightless and inputs do nothing
		-- because PlatformStand is true and the state machine is stuck
		-- in a non-Running state.
		humanoid.PlatformStand = false
		humanoid.Sit           = false
		humanoid.AutoRotate    = true

		-- Restore movement props.
		-- §AGX/STATS: current BaseWalkSpeed (bonus may have changed while dead).
		humanoid.WalkSpeed  = humanoid:GetAttribute("BaseWalkSpeed") or data.originalSpeed
		humanoid.JumpPower  = 50
		humanoid.JumpHeight = 7.2

		-- Make sure HumanoidRootPart isn't anchored. Mob skills with
		-- knockback could have anchored it during the knockdown window.
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.Anchored = false end

		-- Restore HP. With state already "Alive" the Update loop won't
		-- pin it back to 1 on the next Heartbeat.
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

	print("[DeathSystem]", player.Name, "revived",
		teleportToSpawn and "(at spawn)" or "(in place)")
end

function DeathSystem.HandleRespawnRequest(player)
	local data = playerStates[player]
	if not data then return end
	if data.state ~= "Dead" then return end

	-- §DISC/D3b: during a wipe-grace window the free respawn is OFF the
	-- table — the run is ending; the only out is the wipe-revive.
	if wipeGraceActive then return end

	-- §T4/V2: dedup — one queued respawn per death, however many
	-- RequestRespawn packets arrive.
	if data.respawnQueued then return end
	data.respawnQueued = true

	-- §EASY, §2.4d: per-run respawn counter. Nothing reads it yet
	-- (TODO: BACKLOG §2.4d — end-of-run panel, "Die N times" achievements).
	data.respawnCount = (data.respawnCount or 0) + 1

	task.delay(CONFIG.RespawnDelay, function()
		if playerStates[player] then playerStates[player].respawnQueued = nil end
		if wipeGraceActive then return end  -- wipe started during the delay
		performRevive(player, true)
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
			-- in MobAI/DamageHandler, not via Health ≤ 0.
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

--- §AGX/STATS: true once Init ran. Only combat places (LaneDefense,
--- HordeMode, CentralBoss) load DeathSystem, so ConsumableEffects uses
--- this as its "is this a run?" gate (Lobby / SocialPlaza → false).
function DeathSystem.IsActive()
	return initialized
end

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
