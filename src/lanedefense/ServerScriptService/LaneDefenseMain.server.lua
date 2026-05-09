-- lanedefense/ServerScriptService/LaneDefenseMain.server.lua
--[[
    LaneDefense place bootstrap.

    Loads shared core + all combat systems.
    Reads TeleportData from the Lobby place (party, difficulty, mode).
    
    Lobby-specific systems (party manager, matchmaking, NPCs, scene manager)
    are NOT loaded — they live only in the lobby place.
]]

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

local SharedModules     = SSS:WaitForChild("Modules")


-- ───────────────────────────────────────────────────────────
-- ADMIN GUARD
-- Allowlist is centralised in PlayerDataConfig.AdminUserIds.
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
		warn("[LaneDefenseMain] Module not found:", name)
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[LaneDefenseMain] Failed to load", name, ":", result)
		return nil
	end
	loaded[name] = result
	if type(result.Init) == "function" then
		result.Init()
	end
	return result
end

-- §LD2: loud dependency validation. Hard-error if a critical combat
-- module is missing — a half-loaded LaneDefense place would let players
-- teleport in and stand around with no mobs.
local function RequireLoaded(name)
	if not loaded[name] then
		error(string.format(
			"[LaneDefenseMain] CRITICAL: required module '%s' failed to load — cannot run Lane Defense. " ..
			"Check earlier warnings from Load() for the root cause.",
			tostring(name)), 0)
	end
	return loaded[name]
end
_G.LaneDefenseRequireLoaded = RequireLoaded

-- ───────────────────────────────────────────────────────────
-- SHARED CORE MODULES
-- ───────────────────────────────────────────────────────────
-- NOTE: R6 character type is configured directly in Roblox Studio game settings.
-- ForceR6 module was removed. CharacterAutoLoads control will be needed when
-- the character creation visual system is built (see CharacterManager.ApplyTemplate).

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

-- Achievement system (tracks kills/hits/merits/waves → persistent unlocks)
Load(SharedModules, "AchievementManager")

-- Equipment info handler
Load(SharedModules, "EquipmentHandler")

-- Inventory & accessory equip system
Load(SharedModules, "InventoryManager")

-- Daily login rewards
Load(SharedModules, "DailyLoginManager")

-- Shop system (3-tab: Cosmetics, Consumables, Premium)
Load(SharedModules, "ShopManager")

-- Leaderboard system (OrderedDataStore + GearScore)
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

-- Mob systems
-- Move templates from ServerStorage → ReplicatedStorage before MobSpawner.Init()
Load(SharedModules, "MobAssetLoader")
if loaded["MobAssetLoader"] then loaded["MobAssetLoader"].Load() end
Load(SharedModules, "MobAI")
Load(SharedModules, "WaveConfig")
Load(SharedModules, "MobSpawner")

-- Defense
Load(SharedModules, "DefenseLine")

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

-- Card / vote system
Load(SharedModules, "CardRegistry")
Load(SharedModules, "RunModifiers")
Load(SharedModules, "VoteManager")

-- ───────────────────────────────────────────────────────────
-- LANEDEFENSE-SPECIFIC MODULES
-- ───────────────────────────────────────────────────────────
loaded["TeleportDataReader"] = require(SharedModules:WaitForChild("TeleportDataReader"))
loaded["TeleportDataReader"].Init("Defense")

-- Wire difficulty from teleport data into mob spawner
pcall(function()
	if loaded["TeleportDataReader"] and loaded["MobSpawner"] then
		local difficulty = loaded["TeleportDataReader"].GetDifficulty()
		if difficulty then
			loaded["MobSpawner"].SetDifficulty(tostring(difficulty))
			print("[LaneDefense] Difficulty from teleport data:", difficulty)
		else
			loaded["MobSpawner"].SetDifficulty("Normal")
			print("[LaneDefense] No difficulty in teleport data, defaulting to Normal")
		end
	end
end)

-- §LD1 fix: anchor mob levels to the highest player level — but ONLY after
-- the first player's DataStore load completes. The previous task.wait(0)
-- approach raced with PlayerDataManager.SetupPlayer and could read a stale
-- default Level=1 for the entire run. This mirrors the HordeMode §3.1 fix.
local laneAnchorApplied = false
local function applyLaneAnchorOnce()
	if laneAnchorApplied then return end
	laneAnchorApplied = true
	local ok, err = pcall(function()
		if not loaded["MobSpawner"] or not loaded["PlayerDataManager"] then return end
		local highest = 1
		for _, player in ipairs(Players:GetPlayers()) do
			local lvl = loaded["PlayerDataManager"].GetAccountData(player, "Level") or 1
			if lvl > highest then highest = lvl end
		end
		loaded["MobSpawner"].SetPartyAnchorLevel(highest)
		print("[LaneDefense] Party anchor level (on data-ready):", highest)
	end)
	if not ok then
		warn("[LaneDefense] Party anchor computation failed:", err)
	end
end

if loaded["PlayerDataManager"] and loaded["PlayerDataManager"].OnPlayerDataReady then
	loaded["PlayerDataManager"].OnPlayerDataReady(function(_)
		applyLaneAnchorOnce()
	end)
else
	-- Fallback — should never happen, but never silently skip the anchor.
	warn("[LaneDefense] PlayerDataManager.OnPlayerDataReady missing; applying anchor immediately")
	applyLaneAnchorOnce()
end

-- Admin testing panel (admin-only; harmless in production if no admin is present)
Load(SharedModules, "AdminTesting")

-- Wire TeleportDataReader cleanup on player leave
Players.PlayerRemoving:Connect(function(player)
	if loaded["TeleportDataReader"] and loaded["TeleportDataReader"].OnPlayerRemoving then
		loaded["TeleportDataReader"].OnPlayerRemoving(player)
	end
end)

Load(SharedModules, "ReturnTeleporter")

-- ───────────────────────────────────────────────────────────
-- CROSS-SYSTEM WIRING (weapon XP hooks)
-- ───────────────────────────────────────────────────────────
do
	local wm = loaded["WeaponManager"]
	if wm and loaded["SkillEffects"] then
		loaded["SkillEffects"].WeaponManager = wm
	end
	if wm and loaded["KillRewardManager"] then
		loaded["KillRewardManager"].WeaponManager = wm
	end
end

-- ───────────────────────────────────────────────────────────
-- §LD2: validate the critical-path modules before LateInit.
-- ───────────────────────────────────────────────────────────
RequireLoaded("PlayerDataManager")
RequireLoaded("NetworkManager")
RequireLoaded("MobAI")
RequireLoaded("MobRegistry")
RequireLoaded("MobSpawner")
RequireLoaded("DefenseLine")
RequireLoaded("VoteManager")
RequireLoaded("StatsManager")
RequireLoaded("CurrencyManager")
RequireLoaded("GameStateManager")
RequireLoaded("SharedEventHandlers")

-- ───────────────────────────────────────────────────────────
-- LATE INIT (modules that depend on other modules)
-- ───────────────────────────────────────────────────────────
if loaded["GameStateManager"] then
	loaded["GameStateManager"].LateInit()
end
if loaded["DefenseLine"] then
	loaded["DefenseLine"].LateInit()
end

-- Wire up the card / vote system
if loaded["VoteManager"] then
	local laneDifficulty = "Normal"
	pcall(function()
		laneDifficulty = tostring(loaded["TeleportDataReader"].GetDifficulty())
	end)
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
		mobSpawner  = loaded["MobSpawner"],
		defenseLine = loaded["DefenseLine"],
	})
	loaded["VoteManager"].SetRunState({
		difficulty = laneDifficulty,
		modeId     = "Defense",
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
local DefenseLine       = loaded["DefenseLine"]
local HitTracker        = loaded["HitTracker"]
local TeleportDataReader = loaded["TeleportDataReader"]
local ReturnTeleporter   = loaded["ReturnTeleporter"]
local VoteManager        = loaded["VoteManager"]
local RunModifiers       = loaded["RunModifiers"]



-- ───────────────────────────────────────────────────────────
-- SHARED EVENT HANDLERS (extracted to SharedEventHandlers.lua)
-- ───────────────────────────────────────────────────────────
-- Pre-create server→client events so clients never hit the 3-second
-- WaitForChild timeout on startup.
NetworkManager.GetEvent("CurrencyUpdate")
NetworkManager.GetEvent("PlayerInfoUpdate")
NetworkManager.GetEvent("StatsUpdate")
NetworkManager.GetEvent("ServerReady")
NetworkManager.GetEvent("ResourceUpdate")
NetworkManager.GetEvent("VitalsUpdate")
NetworkManager.GetEvent("GameStateChanged")
NetworkManager.GetEvent("CountdownUpdate")

-- Register shared handlers (GetPlayerInfo, GetStats, AllocateStat, ModifySystemStat)
loaded["SharedEventHandlers"].Register({
	NetworkManager  = NetworkManager,
	DataManager     = DataManager,
	Config          = Config,
	ResourceManager = ResourceManager,
	IsAdmin         = IsAdmin,
})

-- ───────────────────────────────────────────────────────────
-- GAME STATE EVENTS (LaneDefense-only)
-- ───────────────────────────────────────────────────────────
GameStateManager.OnStateChanged(function(newState, oldState)
	print("[LaneDefense] Game state:", oldState, "→", newState)

	-- §47.1: Set defense line HP based on the highest player level
	if newState == "Defending" and DataManager and DefenseLine then
		local highestLevel = 1
		for _, p in ipairs(Players:GetPlayers()) do
			local data = DataManager.GetData(p)
			if data and data.Account and data.Account.Level then
				highestLevel = math.max(highestLevel, data.Account.Level)
			end
		end
		DefenseLine.SetChapterLevel(highestLevel)
	end
end)

-- Wire return-to-lobby teleport
GameStateManager.OnReturnToLobby(function()
	if RunModifiers then RunModifiers.Reset() end
	if ReturnTeleporter then
		ReturnTeleporter.TeleportAllToLobby()
	end
end)

MobSpawner.OnWaveStarted(function(waveNumber, mobCount)
	print("[LaneDefense] Wave", waveNumber, "-", mobCount, "mobs")

	-- Tactical Vote at the start of each wave
	if VoteManager and RunModifiers then
		RunModifiers.ResetWaveDanger()
		VoteManager.SetRunState({ waveNumber = waveNumber })
		VoteManager.StartVote("tactical")
	end
end)

-- Gate mob spawning on tactical-vote resolution.  The pre-spawn hook runs
-- inside SpawnWave (on a task.spawn thread) and holds spawning until the vote
-- is no longer active.
-- §LD-V1 fix: previously released the spawn gate the instant
-- VoteManager.IsVoteActive() returned false. The client-side VoteUI keeps
-- the result card visible for ~3 s after VoteResult to highlight the
-- winning option, so mobs were resuming under a still-open card overlay
-- (the "freeze removed but card still on screen" complaint). Hold the
-- gate for the same display window so the card-dismiss matches the
-- spawn-resume.
local VOTE_CARD_DISPLAY = 3.5  -- mirrors HordeMode's VOTE_RESULT_DISPLAY
if MobSpawner and VoteManager then
	MobSpawner.SetPreSpawnHook(function(_waveNumber)
		-- Brief yield to ensure OnWaveStarted callbacks (which start the vote)
		-- have run before we begin polling.
		task.wait(0.1)
		-- Vote was started in OnWaveStarted above; wait for it to resolve
		while VoteManager.IsVoteActive() do
			task.wait(0.25)
		end
		-- §VG4-RESUME: no extra wait. VoteManager's IsVoteActive stays
		-- true through the full 5 s display+countdown grace, so by the
		-- time the loop above exits the cards are dismissed and the
		-- countdown has finished. Stacking another 3.5 s here was the
		-- phantom delay Pablo reported.
	end)
end

MobSpawner.OnWaveCompleted(function(waveNumber)
	print("[LaneDefense] Wave", waveNumber, "completed!")

	-- Wave completion XP bonus: 15 + (15 × wave) to every active player
	-- Wave 1 = 30 XP, Wave 2 = 45, Wave 3 = 60, etc.
	-- Combined with kill XP (@baseFraction=0.03), players level up during wave 3-4.
	local waveXP = 15 + (15 * waveNumber)

	-- Apply danger bonus as XP multiplier (positive danger = more XP, negative = less)
	if RunModifiers then
		local danger = RunModifiers.GetTotalDangerBonus()
		waveXP = math.floor(waveXP * (1 + danger))
	end

	for _, p in ipairs(Players:GetPlayers()) do
		if DataManager then
			DataManager.AddExperience(p, waveXP)
		end
	end
end)

-- ───────────────────────────────────────────────────────────
-- DEFENSE LINE EVENTS
-- ───────────────────────────────────────────────────────────


DefenseLine.OnComboChanged(function(level, hitCount)
	if level >= 3 then
		warn("[LaneDefense] DEFENSE COMBO x" .. level .. "! (" .. hitCount .. " hits)")
	end
end)

DefenseLine.OnDestroyedCallback(function()
	print("[LaneDefense] DEFENSE LINE DESTROYED - GAME OVER!")
	GameStateManager.TriggerDefeat()
end)

-- ───────────────────────────────────────────────────────────
-- DEBUG COMMANDS
-- ───────────────────────────────────────────────────────────
NetworkManager.GetEvent("DebugCommand")
NetworkManager.OnClientEvent("DebugCommand", function(player, command, ...)
	if not IsAdmin(player) then return end
	local args = {...}

	if command == "testDamage" then
		local tier = args[1] or "normal"
		local hp = args[2] or 50
		local atk = args[3] or 10
		DefenseLine.TestDamage(tier, hp, atk)
	elseif command == "healLine" then
		local amount = args[1] or 100
		DefenseLine.Heal(amount)
	elseif command == "setLineHP" then
		local hp = args[1] or DefenseLine.GetMaxHealth()
		DefenseLine.SetHealth(hp)
	elseif command == "skipWave" then
		MobSpawner.ForceCompleteWave()
	elseif command == "addXP" then
		local amount = args[1] or 100
		DataManager.AddExperience(player, amount)
	end
end)

-- ───────────────────────────────────────────────────────────
-- PLAYER VITALS BROADCAST
--   Sends HP/MaxHP/Class/Level for every connected player
--   to all clients. TeammateVitals listens for this event.
--
-- §LD3 fix: HP regen runs on its OWN loop independent of broadcast.
-- Bumping broadcast frequency no longer accelerates regen.
-- §LD4 fix: GearRating require hoisted out of the broadcast loop.
-- ───────────────────────────────────────────────────────────
NetworkManager.GetEvent("VitalsUpdate")

local GearRating = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GearRating"))

local VITALS_INTERVAL = 1   -- seconds between broadcasts
local REGEN_INTERVAL  = 1   -- seconds between regen ticks (was tied to broadcast)

-- Independent regen loop.
-- §LD-RG1 fix: was regen-while-knocked-down. DeathSystem pins HP to 1 on
-- Heartbeat during a knockdown, but this loop kept adding small ticks
-- that the heartbeat then snapped back, producing jitter and (more
-- importantly) violating the design intent that knocked players don't
-- regenerate. Gate the loop on the strict "Alive" state — Dead and
-- KnockedDown both block.
task.spawn(function()
	while true do
		task.wait(REGEN_INTERVAL)

		-- §VG1: pause HP regen while a vote is active so players
		-- can't drag a vote to recover. Same gate as ResourceManager.
		if loaded["VoteManager"] and loaded["VoteManager"].IsVoteActive and loaded["VoteManager"].IsVoteActive() then
			continue
		end

		for _, p in ipairs(Players:GetPlayers()) do
			-- Skip non-alive states. Treat nil as alive for the same
			-- first-spawn race reason as PlayerAttack.DoAttack: until
			-- DeathState replicates from the server we'd rather over-
			-- regen by one tick than under-regen forever.
			local deathState = p:GetAttribute("DeathState")
			if deathState == "KnockedDown" or deathState == "Dead" then
				continue
			end

			local maxHp    = StatsManager.GetTotalHealth(p) or 100
			local char     = p.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and humanoid.Health < maxHp then
				local regenPct  = DataManager.GetTotalStat(p, "HpRegen") or 0.5
				local regenFlat = DataManager.GetTotalStat(p, "FlatHpRegen") or 0
				humanoid.Health = math.min(
					humanoid.Health + maxHp * (regenPct / 100) * REGEN_INTERVAL + regenFlat * REGEN_INTERVAL,
					maxHp
				)
			end
		end
	end
end)

-- Independent broadcast loop (read-only — does NOT mutate health).
task.spawn(function()
	while true do
		task.wait(VITALS_INTERVAL)

		local allPlayers = Players:GetPlayers()
		if #allPlayers == 0 then continue end

		local vitals = {}
		for _, p in ipairs(allPlayers) do
			local maxHp    = StatsManager.GetTotalHealth(p) or 100
			local char     = p.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
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
-- PLAYER CONNECTIONS
-- ───────────────────────────────────────────────────────────
-- §LD3 fix: subscribe to OnPlayerDataReady instead of polling GetData.
local function OnPlayerReady(player)
	local data = DataManager.GetData(player)
	if not data then
		warn("[LaneDefense] OnPlayerReady fired with no data for", player.Name)
		return
	end

	local account = DataManager.GetAccountData(player)

	-- Read teleport data for this player
	if TeleportDataReader then
		TeleportDataReader.ProcessPlayer(player)
	end

	-- Apply innate class passives for the player's current class
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

	-- Send defense line state
	if DefenseLine then
		DefenseLine.SendStateToPlayer(player)
	end

	-- Push fresh StatsUpdate so the client stats panel is correct immediately
	-- (no need to open the menu first; avoids displaying stale cached data).
	loaded["SharedEventHandlers"].PushStatsUpdate(player)

	NetworkManager.FireClient(player, "ServerReady")
end

if DataManager.OnPlayerDataReady then
	DataManager.OnPlayerDataReady(OnPlayerReady)
else
	warn("[LaneDefense] PlayerDataManager.OnPlayerDataReady missing — falling back to polling")
	local function pollPlayerReady(player)
		local data
		for _ = 1, 20 do
			data = DataManager.GetData(player)
			if data then break end
			task.wait(0.5)
		end
		if data then OnPlayerReady(player) end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(pollPlayerReady, player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(pollPlayerReady, player)
	end)
end

print("[LaneDefense] Place ready — waiting for players")
