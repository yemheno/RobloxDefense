-- hordemode/ServerScriptService/HordeModeMain.server.lua
--[[
    HordeMode place bootstrap.

    Loads shared core + all combat systems.
    Reads TeleportData from the Lobby place (party, difficulty, mode).

    Distinction from CentralBoss:
      • Mode identifier is "HordeMode" (reported to TeleportDataReader).
      • Camera is TopDown (configurable top-down arcade view).
      • Player faces mouse cursor (PC) or joystick direction (mobile).
      • DefenseLine is NOT loaded — this mode has no lane to defend.
      • All combat functionality is identical to CentralBoss.

    Lobby-specific systems (party manager, matchmaking, NPCs, scene manager)
    are NOT loaded — they live only in the lobby place.
]]

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

local SharedModules    = SSS:WaitForChild("Modules")
local HordeModeModules = SSS:WaitForChild("HordeMode"):WaitForChild("Modules")

-- ───────────────────────────────────────────────────────────
-- ADMIN GUARD
-- ───────────────────────────────────────────────────────────
local _AdminCfg = require(SharedModules:WaitForChild("PlayerDataConfig"))
local function IsAdmin(player)
	if player.UserId == game.CreatorId then return true end
	return _AdminCfg.AdminUserIds and _AdminCfg.AdminUserIds[player.UserId] == true
end

-- ───────────────────────────────────────────────────────────
-- MODULE LOADER HELPER
-- ───────────────────────────────────────────────────────────
local loaded = {}

local function Load(parent, name)
	local mod = parent:FindFirstChild(name)
	if not mod then
		warn("[HordeModeMain] Module not found:", name)
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[HordeModeMain] Failed to load", name, ":", result)
		return nil
	end
	loaded[name] = result
	if type(result.Init) == "function" then
		result.Init()
	end
	return result
end

-- §3.4: loud dependency validation.
-- RequireLoaded hard-errors if a module name isn't in `loaded`. Use this
-- for anything that the Horde Mode game loop literally cannot run without
-- (PlayerDataManager, MobRegistry, VoteManager, etc.). Using it prevents
-- a partial-load silent bug where the server starts with no mobs / no
-- skills / no vote UI and looks "working" to the telemetry but is dead.
local function RequireLoaded(name)
	if not loaded[name] then
		error(string.format(
			"[HordeModeMain] CRITICAL: required module '%s' failed to load — cannot start Horde Mode. " ..
			"Check earlier warnings from the Load() helper for the root cause.",
			tostring(name)
		), 0)
	end
	return loaded[name]
end
-- Export so other scripts in the place can assert too.
_G.HordeModeRequireLoaded = RequireLoaded

-- ───────────────────────────────────────────────────────────
-- SHARED CORE MODULES
-- ───────────────────────────────────────────────────────────
-- Config
Load(SharedModules, "PlayerDataConfig")
Load(SharedModules, "WeaponConfig")
Load(SharedModules, "ArmorConfig")
Load(SharedModules, "ClassConfig")
Load(SharedModules, "CharacterConfig")
Load(SharedModules, "GameModeConfig")
Load(SharedModules, "ProjectileConfig")
Load(SharedModules, "StatusEffectTypes")

-- Network
Load(SharedModules, "NetworkManager")

-- ReadyGate: per-player queue for server-push events fired before the
-- client's listeners are bound. See ReadyGate.lua for protocol.
Load(SharedModules, "ReadyGate")

-- Player data
Load(SharedModules, "PlayerDataManager")
Load(SharedModules, "CharacterManager")

-- Registries
Load(SharedModules, "WeaponRegistry")
Load(SharedModules, "ArmorRegistry")
Load(SharedModules, "SkillRegistry")
Load(SharedModules, "MobSkillRegistry")
Load(SharedModules, "MobRegistry")

-- Stats & Currency
Load(SharedModules, "StatsManager")
Load(SharedModules, "CurrencyManager")

-- Bonus aggregation (must load before combat systems)
Load(SharedModules, "BonusManager")
if loaded["BonusManager"] and loaded["PlayerDataManager"] then
	loaded["BonusManager"].InjectDataManager(loaded["PlayerDataManager"])
end

-- Talent system (must load after BonusManager)
Load(SharedModules, "TalentEffectAggregator")
Load(SharedModules, "TalentManager")

-- Bonus XP system (party bonuses, etc.)
Load(SharedModules, "BonusExpSystem")

-- Class & Weapon
Load(SharedModules, "ClassManager")
Load(SharedModules, "WeaponManager")
Load(SharedModules, "ArmorManager")
Load(SharedModules, "VisualEquipmentManager")

-- Cosmetic & Animation config/manager
Load(SharedModules, "AnimationConfig")
Load(SharedModules, "CosmeticConfig")
Load(SharedModules, "CosmeticManager")

-- Achievement system
Load(SharedModules, "AchievementManager")

-- Equipment info handler
Load(SharedModules, "EquipmentHandler")

-- Inventory & accessory equip system
Load(SharedModules, "InventoryManager")

-- Daily login rewards
Load(SharedModules, "DailyLoginManager")

-- Shop system
Load(SharedModules, "ShopManager")

-- Leaderboard system
Load(SharedModules, "LeaderboardManager")

-- Combat support
Load(SharedModules, "HitTracker")
Load(SharedModules, "ResourceManager")
Load(SharedModules, "AttackShapes")
Load(SharedModules, "ElementalSystem")

-- Drop system
Load(SharedModules, "DropTableConfig")
Load(SharedModules, "DropManager")

-- Monitoring
Load(SharedModules, "MonitoringSystem")

-- Shared event handlers (GetPlayerInfo, GetStats, AllocateStat, ModifySystemStat)
Load(SharedModules, "SharedEventHandlers")

-- ── HordeMode asset pre-load ─────────────────────────────────────────
-- MapLoader moves ServerStorage.Models.Mobs → ReplicatedStorage.Mobs
-- so MobSpawner finds templates when it initialises.
-- This MUST run before MobSpawner.Init().
Load(HordeModeModules, "HordeModeMapLoader")
if loaded["HordeModeMapLoader"] then
	loaded["HordeModeMapLoader"].LoadAssets()
end

-- Mob systems
Load(SharedModules, "MobAI")
-- Switch MobAI into HordeMode: no X-axis lane filter, no perception cap.
if loaded["MobAI"] then
	loaded["MobAI"].SetHordeModeTargeting(true)
end
Load(SharedModules, "WaveConfig")
Load(SharedModules, "MobSpawner")

-- Combat
Load(SharedModules, "AttackHandler")
Load(SharedModules, "SkillEffects")
Load(SharedModules, "SkillManager")

-- Kill reward pipeline (XP, drops, weapon XP, callbacks)
Load(SharedModules, "KillRewardManager")

-- Death system (must load after ResourceManager, NetworkManager)
Load(SharedModules, "DeathSystem")

-- Game state
Load(SharedModules, "GameStateManager")

-- ───────────────────────────────────────────────────────────
-- HORDEMODE-SPECIFIC MODULES
-- ───────────────────────────────────────────────────────────
loaded["TeleportDataReader"] = require(SharedModules:WaitForChild("TeleportDataReader"))
loaded["TeleportDataReader"].Init("HordeMode")

-- Wire difficulty from teleport data into HordeModeSpawner (not MobSpawner —
-- Horde uses its own spawner with mode-specific base multipliers).
pcall(function()
	if loaded["TeleportDataReader"] then
		local difficulty = loaded["TeleportDataReader"].GetDifficulty()
		if difficulty then
			print("[HordeMode] Difficulty from teleport data:", difficulty)
		else
			difficulty = "Normal"
			print("[HordeMode] No difficulty in teleport data, defaulting to Normal")
		end
		-- HordeModeSpawner is loaded later; stash the value for post-load wiring
		loaded["_hordeDifficulty"] = tostring(difficulty)
	end
end)

-- Admin testing panel (admin-only; harmless in production)
Load(SharedModules, "AdminTesting")

-- Wire TeleportDataReader cleanup on player leave
Players.PlayerRemoving:Connect(function(player)
	if loaded["TeleportDataReader"] and loaded["TeleportDataReader"].OnPlayerRemoving then
		loaded["TeleportDataReader"].OnPlayerRemoving(player)
	end
end)

Load(HordeModeModules, "HordeModeSpawner")
Load(HordeModeModules, "HordePauseManager")
Load(SharedModules, "ReturnTeleporter")

-- Card / vote system
Load(SharedModules, "CardRegistry")
Load(SharedModules, "RunModifiers")
Load(SharedModules, "VoteManager")

-- ───────────────────────────────────────────────────────────
-- CROSS-SYSTEM WIRING (weapon XP hooks)
-- Must run after WeaponManager, SkillEffects, and KillRewardManager are loaded.
-- DamageSystem lazy-loads WeaponManager itself; only the others need injection.
-- ───────────────────────────────────────────────────────────
do
	local wm = loaded["WeaponManager"]
	-- SkillEffects → healer/support XP (heal, buff, revive events).
	if wm and loaded["SkillEffects"] then
		loaded["SkillEffects"].WeaponManager = wm
	end
	-- KillRewardManager → DPS XP (mob kill events).
	if wm and loaded["KillRewardManager"] then
		loaded["KillRewardManager"].WeaponManager = wm
	end
end

-- ───────────────────────────────────────────────────────────
-- LATE INIT
-- ───────────────────────────────────────────────────────────
-- §3.4: validate the critical-path modules before we reach the Setup/Start
-- phase. If any of these is nil we can't run a Horde Mode session, and
-- without this check the subsequent `if loaded[...]` blocks would silently
-- skip their wiring and leave the server half-initialized.
RequireLoaded("PlayerDataManager")
RequireLoaded("MobAI")
RequireLoaded("MobRegistry")
RequireLoaded("HordeModeSpawner")
RequireLoaded("VoteManager")
RequireLoaded("NetworkManager")
RequireLoaded("StatsManager")
RequireLoaded("CurrencyManager")

if loaded["GameStateManager"] then
	loaded["GameStateManager"].LateInit()
end

-- Start HordeModeSpawner now that MobAI + MobRegistry are ready.
-- IMPORTANT (§3.1 fix): Do NOT call Start() here. The first mobs could otherwise
-- spawn before any player's DataStore load finishes, so the spawner would read
-- a stale default Level of 1 for the party anchor. Defer Start() until the
-- FIRST player's data is ready, using PlayerDataManager.OnPlayerDataReady as
-- the server-readiness signal. Subsequent data-ready players re-anchor in
-- OnPlayerReady further down.
local hordeSpawnerStarted = false
if loaded["HordeModeSpawner"] then
	loaded["HordeModeSpawner"].Setup(loaded["MobAI"], loaded["MobRegistry"])
	-- Apply difficulty BEFORE Start() so mobs spawn with correct stats
	if loaded["_hordeDifficulty"] then
		loaded["HordeModeSpawner"].SetDifficulty(loaded["_hordeDifficulty"])
	end

	local function startSpawnerOnce()
		if hordeSpawnerStarted then return end
		hordeSpawnerStarted = true

		-- Compute the party anchor from loaded players BEFORE Start() so the
		-- very first mob already spawns at the correct level.
		local highest = 1
		if loaded["PlayerDataManager"] then
			for _, p in ipairs(Players:GetPlayers()) do
				local lvl = loaded["PlayerDataManager"].GetAccountData(p, "Level") or 1
				if lvl > highest then highest = lvl end
			end
		end
		if highest > 1 then
			loaded["HordeModeSpawner"].SetPartyAnchorLevel(highest)
			print("[HordeMode] Initial party anchor level (on server-ready):", highest)
		end

		loaded["HordeModeSpawner"].Start()
		print("[HordeMode] Spawner started after first player's data loaded")
	end

	if loaded["PlayerDataManager"] and loaded["PlayerDataManager"].OnPlayerDataReady then
		loaded["PlayerDataManager"].OnPlayerDataReady(function(_)
			startSpawnerOnce()
		end)
	else
		-- Fallback — should never happen, but we do not want to silently no-op.
		warn("[HordeMode] PlayerDataManager.OnPlayerDataReady missing; starting spawner immediately")
		startSpawnerOnce()
	end
end

-- HordeMode manages spawning via HordeModeSpawner, NOT MobSpawner waves.
-- Suppress wave auto-start and transition straight to Defending so the
-- client HUD never shows the "Start Game" button.
if loaded["GameStateManager"] then
	loaded["GameStateManager"].suppressWaveStart = true
	loaded["GameStateManager"].SetState("Defending")
end

-- (Former early party-anchor task.spawn block removed — the spawner is now
-- deferred until OnPlayerDataReady via startSpawnerOnce(), so anchoring
-- happens exactly once with loaded data. See §3.1 fix above.)

-- Wire up the pause system
if loaded["HordePauseManager"] then
	loaded["HordePauseManager"].Setup({
		MobAI            = loaded["MobAI"],
		HordeModeSpawner = loaded["HordeModeSpawner"],
		NetworkManager   = loaded["NetworkManager"],
	})
end

-- Wire up the card / vote system
if loaded["VoteManager"] then
	loaded["VoteManager"].Setup({
		NetworkManager   = loaded["NetworkManager"],
		CardRegistry     = loaded["CardRegistry"],
		RunModifiers     = loaded["RunModifiers"],
		PlayerDataManager = loaded["PlayerDataManager"],
		BonusManager     = loaded["BonusManager"],
		ResourceManager  = loaded["ResourceManager"],
		CurrencyManager  = loaded["CurrencyManager"],
	})
	loaded["VoteManager"].SetModeDeps({
		mobSpawner = loaded["HordeModeSpawner"],
	})
	-- §3.2 fix: seed run state at bootstrap so any stray StartVote (admin tool,
	-- test harness, pause/resume edge) does not trip over an uninitialized
	-- runState. The per-vote loop below refreshes difficulty/elapsed before
	-- each vote fires.
	loaded["VoteManager"].SetRunState({
		difficulty = loaded["_hordeDifficulty"] or "Normal",
		elapsed    = 0,
		modeId     = "HordeMode",
	})
end

-- ───────────────────────────────────────────────────────────
-- SHORTCUTS
-- ───────────────────────────────────────────────────────────
local Config            = loaded["PlayerDataConfig"]
local NetworkManager    = loaded["NetworkManager"]
local DataManager       = loaded["PlayerDataManager"]
local StatsManager      = loaded["StatsManager"]
local ResourceManager   = loaded["ResourceManager"]
local GameStateManager  = loaded["GameStateManager"]
local MobSpawner        = loaded["MobSpawner"]
local HitTracker        = loaded["HitTracker"]
local TeleportDataReader = loaded["TeleportDataReader"]
local ReturnTeleporter   = loaded["ReturnTeleporter"]
local HordeModeSpawner   = loaded["HordeModeSpawner"]
local MobAI              = loaded["MobAI"]
local HordePauseManager  = loaded["HordePauseManager"]
local VoteManager        = loaded["VoteManager"]
local RunModifiers       = loaded["RunModifiers"]



-- ───────────────────────────────────────────────────────────
-- SHARED EVENT HANDLERS
-- ───────────────────────────────────────────────────────────
NetworkManager.GetEvent("CurrencyUpdate")
NetworkManager.GetEvent("PlayerInfoUpdate")
NetworkManager.GetEvent("StatsUpdate")
NetworkManager.GetEvent("ServerReady")
NetworkManager.GetEvent("ResourceUpdate")
NetworkManager.GetEvent("VitalsUpdate")
NetworkManager.GetEvent("GameStateChanged")
NetworkManager.GetEvent("CountdownUpdate")
NetworkManager.GetEvent("HordePaused")

loaded["SharedEventHandlers"].Register({
	NetworkManager  = NetworkManager,
	DataManager     = DataManager,
	Config          = Config,
	ResourceManager = ResourceManager,
	IsAdmin         = IsAdmin,
})

-- ───────────────────────────────────────────────────────────
-- RUN-TIMING STATE
-- §HM3 fix: these locals USED to be declared further down in the chunk,
-- which meant the OnStateChanged closure below — compiled while the names
-- were still undeclared — silently captured them as globals. Result: the
-- "reset on Defending" branch wrote into _G.hordeStartTime etc. while the
-- vote loop / run timer (compiled later) read the real locals, so the
-- reset never took effect. Hoisting fixes the scope.
-- ───────────────────────────────────────────────────────────
local hordeStartTime     = os.clock()
local hordeRunActive     = true
local totalPauseDuration = 0
local pauseStartedAt     = nil

-- ───────────────────────────────────────────────────────────
-- GAME STATE EVENTS
-- ───────────────────────────────────────────────────────────
GameStateManager.OnStateChanged(function(newState, oldState)
	print("[HordeMode] Game state:", oldState, "→", newState)
	-- Reset pause tracking when a new run starts
	if newState == "Defending" then
		hordeStartTime = os.clock()
		totalPauseDuration = 0
		pauseStartedAt = nil
		hordeRunActive = true
	end
end)

-- Wire return-to-lobby teleport
GameStateManager.OnReturnToLobby(function()
	-- Clean up run state before teleporting
	if RunModifiers then RunModifiers.Reset() end
	if ReturnTeleporter then
		ReturnTeleporter.TeleportAllToLobby()
	end
end)

-- NOTE: HordeMode uses HordeModeSpawner, NOT MobSpawner waves.
-- These callbacks are registered as safety guards — if MobSpawner somehow
-- fires wave events they are logged but do NOT grant rewards (to prevent
-- double-counting with the horde vote/timer system).
MobSpawner.OnWaveStarted(function(waveNumber, mobCount)
	warn("[HordeMode] Unexpected MobSpawner wave event — ignoring. Wave:", waveNumber)
end)

MobSpawner.OnWaveCompleted(function(waveNumber)
	warn("[HordeMode] Unexpected MobSpawner wave-complete event — ignoring. Wave:", waveNumber)
end)

-- ───────────────────────────────────────────────────────────
-- DEBUG COMMANDS
-- ───────────────────────────────────────────────────────────
NetworkManager.GetEvent("DebugCommand")
NetworkManager.OnClientEvent("DebugCommand", function(player, command, ...)
	if not IsAdmin(player) then return end
	local args = {...}

	if command == "skipWave" then
		MobSpawner.ForceCompleteWave()
	elseif command == "addXP" then
		local amount = args[1] or 100
		DataManager.AddExperience(player, amount)
	elseif command == "setHordeLevel" then
		-- Usage: setHordeLevel <level>
		if HordeModeSpawner then
			local level = tonumber(args[1]) or 1
			HordeModeSpawner.SetLevel(level)
			print("[HordeMode] Admin", player.Name, "set horde level to", level)
		end
	elseif command == "stopHorde" then
		if HordeModeSpawner then
			HordeModeSpawner.Stop()
			print("[HordeMode] Admin", player.Name, "stopped horde spawner")
		end
	elseif command == "startHorde" then
		if HordeModeSpawner then
			HordeModeSpawner.Start()
			print("[HordeMode] Admin", player.Name, "started horde spawner")
		end
	elseif command == "pauseHorde" then
		if HordePauseManager then
			HordePauseManager.Pause()
			print("[HordeMode] Admin", player.Name, "paused horde")
		end
	elseif command == "resumeHorde" then
		if HordePauseManager then
			HordePauseManager.Resume()
			print("[HordeMode] Admin", player.Name, "resumed horde")
		end
	elseif command == "toggleHordePause" then
		if HordePauseManager then
			HordePauseManager.Toggle()
			print("[HordeMode] Admin", player.Name, "toggled horde pause")
		end
	end
end)

-- ───────────────────────────────────────────────────────────
-- PLAYER VITALS BROADCAST
-- ───────────────────────────────────────────────────────────
NetworkManager.GetEvent("VitalsUpdate")

local VITALS_INTERVAL = 1

task.spawn(function()
	while true do
		task.wait(VITALS_INTERVAL)

		local allPlayers = Players:GetPlayers()
		if #allPlayers == 0 then continue end

		local vitals = {}
		local GearRating = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GearRating"))
		for _, p in ipairs(allPlayers) do
			local maxHp    = StatsManager.GetTotalHealth(p) or 100
			local char     = p.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			-- HP regeneration tick (applied before broadcast so the client sees the updated value).
			-- §LD-RG1 follow-up: skip regen while knocked-down/dead so the
			-- DeathSystem heartbeat doesn't have to fight a tick adding HP.
			local deathState = p:GetAttribute("DeathState")
			local isAlive = deathState ~= "KnockedDown" and deathState ~= "Dead"
			if isAlive and humanoid and humanoid.Health > 0 and humanoid.Health < maxHp then
				local regenPct  = DataManager.GetTotalStat(p, "HpRegen") or 0.5
				local regenFlat = DataManager.GetTotalStat(p, "FlatHpRegen") or 0
				humanoid.Health = math.min(
					humanoid.Health + maxHp * (regenPct / 100) * VITALS_INTERVAL + regenFlat * VITALS_INTERVAL,
					maxHp
				)
			end
			-- §HUD-HP1: cosmetic 0 HP when not Alive. Engine-side the
			-- humanoid is pinned at 1 (§LD-DS5) so Roblox doesn't tear
			-- down the character; UI-side teammates see 0 for the dramatic
			-- effect.
			local hp
			if p:GetAttribute("DeathState") ~= "Alive" then
				hp = 0
			else
				hp = humanoid and math.floor(humanoid.Health) or maxHp
			end
			local data     = DataManager.GetData(p)
			vitals[tostring(p.UserId)] = {
				name       = p.Name,
				hp         = hp,
				maxHp      = maxHp,
				class      = data and data.ActiveClass or "Aegis",
				level      = data and data.Account and data.Account.Level or 1,
				powerLevel = data and GearRating.GetDisplayPower(data) or 0,
			}
		end

		NetworkManager.FireAllClients("VitalsUpdate", vitals)
	end
end)

-- ───────────────────────────────────────────────────────────
-- HORDE VOTE CADENCE + RUN DURATION
-- ───────────────────────────────────────────────────────────
-- Supply Vote every 45s, Threat Vote every 90s.
-- Run lasts exactly RUN_DURATION seconds of *play time* (pause time excluded
-- because HordePauseManager freezes mobs and the spawner, but os.clock keeps
-- ticking).  The vote loops and spawner stop once the budget is exhausted;
-- remaining mobs are killed off and then the game ends.
--
-- Budget math:  14 × 45s = 630s = 10:30  (also 7 × 90s).
--   Each supply vote pauses for ~12s → 14 × 12 = 168s of pause.
--   Each threat vote pauses for ~12s but overlaps every-other supply → 7 shared.
--   Total wall-clock ≈ 630 + 168 ≈ 13:18, but players see 10:30 of action.
local SUPPLY_INTERVAL     = 45    -- seconds of play-time between votes
local RUN_DURATION        = 630   -- 10 min 30 s of play time
local VOTE_RESULT_DISPLAY = 3.5   -- must be > VoteUI client dismiss delay (3 s) + network slack

-- §HM3 fix: hordeStartTime / hordeRunActive / totalPauseDuration /
-- pauseStartedAt are now declared at the top of the chunk (above the
-- OnStateChanged closure) so the closure correctly resolves them as
-- locals. Re-asserting initial values here in case future edits move the
-- state-change registration.
hordeStartTime     = os.clock()
hordeRunActive     = true
totalPauseDuration = 0
pauseStartedAt     = nil

-- Single alternating vote loop: supply → threat → supply → threat …
-- Fires VotePending 2 s before pausing so players have a heads-up.
-- After all players vote the game resumes immediately (no hardcoded wait).
task.spawn(function()
	local voteIndex = 0
	task.wait(SUPPLY_INTERVAL)       -- first vote at 45 s
	while HordeModeSpawner and hordeRunActive do
		voteIndex = voteIndex + 1
		local voteType = (voteIndex % 2 == 1) and "supply" or "threat"

		if VoteManager and not VoteManager.IsVoteActive() then
			-- ① 2-second heads-up so players can finish their current action
			NetworkManager.FireAllClients("VotePending", {
				voteType  = voteType,
				countdown = 2,
			})
			task.wait(2)

			-- ② Pause game and start vote
			if HordePauseManager then
				pauseStartedAt = os.clock()
				HordePauseManager.Pause()
			end
			VoteManager.SetRunState({
				difficulty = loaded["_hordeDifficulty"] or "Normal",
				elapsed    = os.clock() - hordeStartTime - totalPauseDuration,
				modeId     = "HordeMode",
			})
			VoteManager.StartVote(voteType)

			-- ③ Wait for vote to finish (early if all voted, or timer expires)
			local maxWait = os.clock() + 12  -- VOTE_TIMER_SEC(10) + buffer
			repeat task.wait(0.1) until not VoteManager.IsVoteActive() or os.clock() > maxWait

			-- ④ Resume combat. §VG4-RESUME: VoteManager now keeps
			-- voteActive=true for the full 5 s display+countdown grace,
			-- so the IsVoteActive loop above already waits the right
			-- amount. The old task.wait(VOTE_RESULT_DISPLAY) here was
			-- stacking 3.5 s ON TOP of the grace, hence Pablo's "3 secs
			-- after the countdown". Removed.
			-- §HM12 fix preserved: don't resume the spawner if the run
			-- timer expired while the vote was active.
			if HordePauseManager then
				if pauseStartedAt then
					totalPauseDuration = totalPauseDuration + (os.clock() - pauseStartedAt)
					pauseStartedAt = nil
				end
				if hordeRunActive then
					HordePauseManager.Resume()
				end
			end
		end

		task.wait(SUPPLY_INTERVAL)
	end
end)

-- Run timer — stops spawning, waits for mobs to clear, then ends the run.
-- §HM1 fix: was a flat `task.wait(RUN_DURATION)` which counted pause time
-- against the run budget. Header comment says the run lasts RUN_DURATION
-- seconds of *play time* (pause excluded), so poll for elapsed play-time
-- instead. Pause windows live in totalPauseDuration + (pauseStartedAt extra).
task.spawn(function()
	while hordeRunActive do
		task.wait(1)
		local pauseExtra = pauseStartedAt and (os.clock() - pauseStartedAt) or 0
		local elapsedPlay = (os.clock() - hordeStartTime) - totalPauseDuration - pauseExtra
		if elapsedPlay >= RUN_DURATION then break end
	end
	hordeRunActive = false
	print("[HordeMode] Run timer expired (", RUN_DURATION, "s of play time) — stopping spawner")

	if HordeModeSpawner then
		HordeModeSpawner.Stop()
	end

	-- Wait for all remaining mobs to die.
	-- §HM11 fix: cap the wait so a stuck/unreachable mob can't hang the
	-- end-of-run forever. After 30 s of trying we proceed regardless;
	-- mobs are about to be wiped by the lobby teleport anyway.
	if MobAI then
		local waitDeadline = os.clock() + 30
		while MobAI.IsAnyMobAlive() and os.clock() < waitDeadline do
			task.wait(1)
		end
		if MobAI.IsAnyMobAlive() then
			warn("[HordeMode] Run-end mob clear timed out (30 s); proceeding to lobby return")
		end
	end

	print("[HordeMode] All mobs cleared — run complete!")

	-- Clean up run modifiers
	if RunModifiers then RunModifiers.Reset() end

	-- Trigger return to lobby
	if GameStateManager then
		GameStateManager.TriggerVictory()
	end
end)

-- ───────────────────────────────────────────────────────────
-- PLAYER CONNECTIONS
-- ───────────────────────────────────────────────────────────
local function OnPlayerReady(player)
	-- §HM2 fix: prefer OnPlayerDataReady-driven invocation (registered below)
	-- over polling. We still keep a short poll as a hard fallback for
	-- callers that invoke OnPlayerReady directly.
	local data = DataManager.GetData(player)
	if not data then
		for _ = 1, 20 do
			task.wait(0.5)
			if not player.Parent then return end
			data = DataManager.GetData(player)
			if data then break end
		end
	end
	if not data then
		warn("[HordeMode] Timed out waiting for player data –", player.Name)
		return
	end

	local account = DataManager.GetAccountData(player)

	-- Read teleport data for this player
	if TeleportDataReader then
		TeleportDataReader.ProcessPlayer(player)
	end

	-- Re-anchor mob levels now that this player's data is confirmed loaded.
	-- This replaces the unreliable task.wait(0) block; OnPlayerReady already
	-- polls until data is available, so GetAccountData is safe here.
	do
		local hms = loaded["HordeModeSpawner"]
		if hms then
			local highest = 1
			for _, p in ipairs(Players:GetPlayers()) do
				local lvl = DataManager.GetAccountData(p, "Level") or 1
				if lvl > highest then highest = lvl end
			end
			hms.SetPartyAnchorLevel(highest)
			print("[HordeMode] Party anchor updated:", highest)
		end
	end

	-- Apply innate class passives
	local ClassManager = loaded["ClassManager"]
	if ClassManager then
		ClassManager.ApplyInnateBonus(player)
	end

	-- Initialize talent tree from persisted data
	local TalentManager = loaded["TalentManager"]
	if TalentManager then
		TalentManager.SetupPlayer(player)
		TalentManager.SendState(player)
	end

	-- Reapply equipped accessories → BonusManager
	local InventoryManager = loaded["InventoryManager"]
	if InventoryManager and InventoryManager.SetupPlayer then
		InventoryManager.SetupPlayer(player)
	end

	-- Push fresh StatsUpdate so the client stats panel is correct immediately
	loaded["SharedEventHandlers"].PushStatsUpdate(player)

	-- Push current game state so late-joining players don't see the "Idle" start button
	if GameStateManager then
		local state = GameStateManager.GetState()
		NetworkManager.FireClient(player, "GameStateChanged", {
			oldState  = state,
			newState  = state,
			timestamp = os.clock(),
		})
	end

	NetworkManager.FireClient(player, "ServerReady")
end

-- §HM2 fix: drive OnPlayerReady from the data-ready signal so it runs
-- exactly once per player, the moment their data is available. We also
-- cover already-loaded data (server already ran the load) by checking
-- DataManager.GetData up front.
local _onPlayerReadyFired = {}
local function fireOnPlayerReadyOnce(player)
	if _onPlayerReadyFired[player] then return end
	_onPlayerReadyFired[player] = true
	task.spawn(OnPlayerReady, player)
end

if DataManager.OnPlayerDataReady then
	DataManager.OnPlayerDataReady(fireOnPlayerReadyOnce)
end

-- Cover players already in the server whose data is already loaded.
for _, player in ipairs(Players:GetPlayers()) do
	if DataManager.GetData(player) then
		fireOnPlayerReadyOnce(player)
	end
end

-- Fallback path for players who somehow miss both branches above
-- (e.g. PlayerDataManager build without OnPlayerDataReady).
Players.PlayerAdded:Connect(function(player)
	-- Wait briefly to give OnPlayerDataReady a chance to fire first.
	task.delay(2, function()
		if not player.Parent then return end
		if not _onPlayerReadyFired[player] then
			fireOnPlayerReadyOnce(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	_onPlayerReadyFired[player] = nil
end)

print("[HordeMode] Place ready — waiting for players")
