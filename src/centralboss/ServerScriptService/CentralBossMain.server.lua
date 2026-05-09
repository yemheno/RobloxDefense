-- centralboss/ServerScriptService/CentralBossMain.server.lua
--[[
    CentralBoss place bootstrap.

    Loads shared core + all combat systems.
    Reads TeleportData from the Lobby place (party, difficulty, mode).

    Distinction from LaneDefense:
      • Mode identifier is "CentralBoss" (reported to TeleportDataReader).
      • DefenseLine is NOT loaded — this mode has no lane to defend.
      • A "BossPoint" Part in Workspace is expected for character facing targets.
        The server does not enforce its presence — map designers place it.

    Lobby-specific systems (party manager, matchmaking, NPCs, scene manager)
    are NOT loaded — they live only in the lobby place.
]]

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

local SharedModules      = SSS:WaitForChild("Modules")

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
		warn("[CentralBossMain] Module not found:", name)
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[CentralBossMain] Failed to load", name, ":", result)
		return nil
	end
	loaded[name] = result
	if type(result.Init) == "function" then
		result.Init()
	end
	return result
end

-- §L2 (also covers CentralBoss): loud dependency validation. Note this
-- place is currently UNAUTHORED (see warn at end-of-file) — even so, we
-- want bootstrap-time crashes to be unmistakable rather than silent.
local function RequireLoaded(name)
	if not loaded[name] then
		error(string.format(
			"[CentralBossMain] CRITICAL: required module '%s' failed to load. " ..
			"Even though the boss fight is unauthored, the shared-systems load " ..
			"path must succeed; check earlier Load() warnings for the cause.",
			tostring(name)), 0)
	end
	return loaded[name]
end
_G.CentralBossRequireLoaded = RequireLoaded

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

-- Mob systems
-- Move templates from ServerStorage → ReplicatedStorage before MobSpawner.Init()
Load(SharedModules, "MobAssetLoader")
if loaded["MobAssetLoader"] then loaded["MobAssetLoader"].Load() end
Load(SharedModules, "MobAI")
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
-- CENTRALBOSS-SPECIFIC MODULES
-- ───────────────────────────────────────────────────────────
loaded["TeleportDataReader"] = require(SharedModules:WaitForChild("TeleportDataReader"))
loaded["TeleportDataReader"].Init("CentralBoss")

-- Wire difficulty from teleport data into mob spawner
pcall(function()
	if loaded["TeleportDataReader"] and loaded["MobSpawner"] then
		local difficulty = loaded["TeleportDataReader"].GetDifficulty()
		if difficulty then
			loaded["MobSpawner"].SetDifficulty(tostring(difficulty))
			print("[CentralBoss] Difficulty from teleport data:", difficulty)
		else
			loaded["MobSpawner"].SetDifficulty("Normal")
			print("[CentralBoss] No difficulty in teleport data, defaulting to Normal")
		end
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
-- §L2: validate critical shared modules before LateInit.
-- (No boss/vote modules are required here since the place is unauthored.)
-- ───────────────────────────────────────────────────────────
RequireLoaded("PlayerDataManager")
RequireLoaded("NetworkManager")
RequireLoaded("StatsManager")
RequireLoaded("CurrencyManager")
RequireLoaded("GameStateManager")
RequireLoaded("SharedEventHandlers")

-- ───────────────────────────────────────────────────────────
-- LATE INIT
-- ───────────────────────────────────────────────────────────
if loaded["GameStateManager"] then
	loaded["GameStateManager"].LateInit()
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

loaded["SharedEventHandlers"].Register({
	NetworkManager  = NetworkManager,
	DataManager     = DataManager,
	Config          = Config,
	ResourceManager = ResourceManager,
	IsAdmin         = IsAdmin,
})

-- ───────────────────────────────────────────────────────────
-- GAME STATE EVENTS
-- ───────────────────────────────────────────────────────────
GameStateManager.OnStateChanged(function(newState, oldState)
	print("[CentralBoss] Game state:", oldState, "→", newState)
end)

-- Wire return-to-lobby teleport
GameStateManager.OnReturnToLobby(function()
	if ReturnTeleporter then
		ReturnTeleporter.TeleportAllToLobby()
	end
end)

MobSpawner.OnWaveStarted(function(waveNumber, mobCount)
	print("[CentralBoss] Wave", waveNumber, "-", mobCount, "mobs")
end)

MobSpawner.OnWaveCompleted(function(waveNumber)
	print("[CentralBoss] Wave", waveNumber, "completed!")
	local waveXP = 15 + (15 * waveNumber)
	for _, p in ipairs(Players:GetPlayers()) do
		if DataManager then
			DataManager.AddExperience(p, waveXP)
		end
	end
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
	end
end)

-- ───────────────────────────────────────────────────────────
-- PLAYER VITALS BROADCAST
--
-- §CB2 fix: HP regen runs on its own loop independent of broadcast,
-- and GearRating require is hoisted out of the broadcast loop.
-- Mirrors §LD3/§LD4 in LaneDefense.
-- ───────────────────────────────────────────────────────────
NetworkManager.GetEvent("VitalsUpdate")

local GearRating = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GearRating"))

local VITALS_INTERVAL = 1
local REGEN_INTERVAL  = 1

-- Independent regen loop.
-- §LD-RG1 follow-up: gate regen on Alive state so a knocked-down player
-- doesn't fight DeathSystem's HP-pin heartbeat.
task.spawn(function()
	while true do
		task.wait(REGEN_INTERVAL)

		-- §VG1: pause HP regen while a vote is active so players
		-- can't drag a vote to recover. Same gate as ResourceManager.
		if loaded["VoteManager"] and loaded["VoteManager"].IsVoteActive and loaded["VoteManager"].IsVoteActive() then
			continue
		end

		for _, p in ipairs(Players:GetPlayers()) do
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

-- Independent broadcast loop (read-only).
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
-- §CB3 fix: subscribe to OnPlayerDataReady instead of polling GetData.
local function OnPlayerReady(player)
	local data = DataManager.GetData(player)
	if not data then
		warn("[CentralBoss] OnPlayerReady fired with no data for", player.Name)
		return
	end

	local account = DataManager.GetAccountData(player)

	-- Read teleport data for this player
	if TeleportDataReader then
		TeleportDataReader.ProcessPlayer(player)
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
	-- (no need to open the menu first; avoids displaying stale cached data).
	loaded["SharedEventHandlers"].PushStatsUpdate(player)

	NetworkManager.FireClient(player, "ServerReady")
end

if DataManager.OnPlayerDataReady then
	DataManager.OnPlayerDataReady(OnPlayerReady)
else
	warn("[CentralBoss] PlayerDataManager.OnPlayerDataReady missing — falling back to polling")
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

print("[CentralBoss] Place ready — waiting for players")

-- §CB1: this place currently has NO authored boss fight. Bootstrap loads
-- shared modules and registers wave callbacks, but nothing calls
-- MobSpawner.Start() and no boss is spawned. A player teleporting here
-- will see an empty arena. We surface this loudly at boot so testers
-- (and the dev console) make it obvious instead of looking like a
-- network problem. Remove this warn once the boss fight is wired.
warn("[CentralBoss] ⚠ Mode is UNAUTHORED — no boss will spawn. " ..
	"This bootstrap is a placeholder. See docs/TODO_PARKING_LOT.md →" ..
	" 'Central-boss mode — unfinished'.")
