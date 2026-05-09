-- lobby/ServerScriptService/LobbyMain.server.lua
--[[
    Lobby place bootstrap.

    Loads ONLY the modules relevant to the lobby place:
      • Shared core (data, classes, stats, currency, weapons, network)
      • Lobby-specific (party, matchmaking, scene, NPC, teleport)
    
    Combat systems (mobs, waves, defense line, attack handler) are NOT loaded.
]]

local Players = game:GetService("Players")
local SSS     = game:GetService("ServerScriptService")

local SharedModules = SSS:WaitForChild("Modules")
local LobbyModules  = SSS:WaitForChild("Lobby"):WaitForChild("Modules")

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
		warn("[LobbyMain] Module not found:", name)
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[LobbyMain] Failed to load", name, ":", result)
		return nil
	end
	loaded[name] = result
	if type(result.Init) == "function" then
		result.Init()
	end
	return result
end

-- §L2: loud dependency validation. Hard-error if a critical lobby module
-- is missing — a half-loaded lobby produces broken party/matchmaking
-- state and looks like a network problem to players.
local function RequireLoaded(name)
	if not loaded[name] then
		error(string.format(
			"[LobbyMain] CRITICAL: required module '%s' failed to load — cannot run the lobby. " ..
			"Check earlier warnings from Load() for the root cause.",
			tostring(name)), 0)
	end
	return loaded[name]
end
_G.LobbyMainRequireLoaded = RequireLoaded

-- ───────────────────────────────────────────────────────────
-- SHARED CORE MODULES
-- ───────────────────────────────────────────────────────────
-- NOTE: R6 character type is configured directly in Roblox Studio game settings.
-- ForceR6 module was removed. CharacterAutoLoads control will be needed when
-- the character creation visual system is built (see CharacterManager.ApplyTemplate).

-- Config (pure data, no Init)
Load(SharedModules, "PlayerDataConfig")
Load(SharedModules, "WeaponConfig")
Load(SharedModules, "ArmorConfig")
Load(SharedModules, "ClassConfig")
Load(SharedModules, "CharacterConfig")
Load(SharedModules, "GameModeConfig")
-- ProjectileConfig and StatusEffectTypes are combat-only; other modules
-- will require them directly if needed.

-- Network
Load(SharedModules, "NetworkManager")

-- ReadyGate: per-player queue for server-push events fired before the
-- client's listeners are bound. Loaded right after NetworkManager so any
-- subsequent module that wants to push state at boot can route through it.
Load(SharedModules, "ReadyGate")

-- Player data
Load(SharedModules, "PlayerDataManager")
Load(SharedModules, "CharacterManager")

-- Registries
Load(SharedModules, "WeaponRegistry")
Load(SharedModules, "ArmorRegistry")
Load(SharedModules, "SkillRegistry")

-- Stats & Currency
Load(SharedModules, "StatsManager")
Load(SharedModules, "CurrencyManager")

-- Bonus aggregation
Load(SharedModules, "BonusManager")
if loaded["BonusManager"] and loaded["PlayerDataManager"] then
	loaded["BonusManager"].InjectDataManager(loaded["PlayerDataManager"])
end

-- Talent system (must load after BonusManager)
Load(SharedModules, "TalentEffectAggregator")
Load(SharedModules, "TalentManager")

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

-- Equipment info handler (uses both weapon + armor managers)
Load(SharedModules, "EquipmentHandler")

-- Inventory & accessory equip system
Load(SharedModules, "InventoryManager")

-- Daily login rewards
Load(SharedModules, "DailyLoginManager")

-- Shop system (3-tab: Cosmetics, Consumables, Premium)
Load(SharedModules, "ShopManager")

-- Leaderboard system (OrderedDataStore + GearScore)
Load(SharedModules, "LeaderboardManager")

-- Resource (lightweight — lets HUD show resource bar even in lobby)
Load(SharedModules, "ResourceManager")

-- Monitoring
Load(SharedModules, "MonitoringSystem")

-- Shared event handlers (GetPlayerInfo, GetStats, AllocateStat, ModifySystemStat)
Load(SharedModules, "SharedEventHandlers")

-- Bonus systems (must load before PartyManager so it can wire in)
Load(SharedModules, "BonusExpSystem")

-- ───────────────────────────────────────────────────────────
-- LOBBY-SPECIFIC MODULES
-- ───────────────────────────────────────────────────────────
Load(LobbyModules, "SceneManager")
Load(LobbyModules, "PartyManager")
Load(LobbyModules, "MatchmakingManager")
Load(LobbyModules, "TeleportManager")

-- NPCManager lives in shared (future modes can use it too).
-- Load manually so we can inject place-specific deps: SceneManager + lobby NPC list.
do
	local mod = SharedModules:FindFirstChild("NPCManager")
	if mod then
		local ok, npcMgr = pcall(require, mod)
		if ok then
			loaded["NPCManager"] = npcMgr

			-- Load the lobby-specific NPC definitions.
			local lobbyNpcs = {}
			local npcRegMod = LobbyModules:FindFirstChild("LobbyNPCRegistry")
			if npcRegMod then
				local rok, defs = pcall(require, npcRegMod)
				if rok then
					lobbyNpcs = defs
					-- loaded silently
				else
					warn("[LobbyMain] Failed to load LobbyNPCRegistry:", defs)
				end
			else
				warn("[LobbyMain] LobbyNPCRegistry not found — no lobby NPCs will spawn")
			end

			npcMgr.Init({
				SceneManager       = loaded["SceneManager"],
				MatchmakingManager = loaded["MatchmakingManager"],
				npcs               = lobbyNpcs,
			})
		else
			warn("[LobbyMain] Failed to load NPCManager:", npcMgr)
		end
	else
		warn("[LobbyMain] Module not found: NPCManager")
	end
end

-- Admin testing panel
Load(SharedModules, "AdminTesting")

-- ───────────────────────────────────────────────────────────
-- §L2: validate critical lobby modules before wiring any handlers.
-- ───────────────────────────────────────────────────────────
RequireLoaded("PlayerDataConfig")
RequireLoaded("PlayerDataManager")
RequireLoaded("NetworkManager")
RequireLoaded("StatsManager")
RequireLoaded("CurrencyManager")
RequireLoaded("SharedEventHandlers")
RequireLoaded("PartyManager")
RequireLoaded("MatchmakingManager")
RequireLoaded("TeleportManager")
RequireLoaded("SceneManager")

-- ───────────────────────────────────────────────────────────
-- SHORTCUTS
-- ───────────────────────────────────────────────────────────
local Config            = loaded["PlayerDataConfig"]
local NetworkManager    = loaded["NetworkManager"]
local DataManager       = loaded["PlayerDataManager"]
local StatsManager      = loaded["StatsManager"]
local ResourceManager   = loaded["ResourceManager"]

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
NetworkManager.GetEvent("GameStateChanged")  -- HUD subscribes; not fired in lobby but must exist
NetworkManager.GetEvent("CountdownUpdate")    -- HUD subscribes; not fired in lobby but must exist
NetworkManager.GetEvent("ComboUpdate")         -- HUD subscribes; not fired in lobby but must exist
NetworkManager.GetEvent("PlayerListUpdate")    -- Social panel player browser
NetworkManager.GetEvent("PlayerListRequest")   -- client requests refresh
NetworkManager.GetEvent("PartyUpdate")         -- party roster changes
NetworkManager.GetEvent("PartyInvite")         -- incoming invite toast
NetworkManager.GetEvent("PartyError")          -- error toast in Social panel
NetworkManager.GetEvent("PartyRequest")        -- client → server actions (InviteById, CreateParty, etc.)
NetworkManager.GetEvent("GetPartyState")        -- client requests their current party state on panel open

-- Register shared handlers (GetPlayerInfo, GetStats, AllocateStat, ModifySystemStat)
loaded["SharedEventHandlers"].Register({
	NetworkManager  = NetworkManager,
	DataManager     = DataManager,
	Config          = Config,
	ResourceManager = ResourceManager,
	IsAdmin         = IsAdmin,
})

-- ── GetPartyState (Lobby-specific) ────────────────────────
NetworkManager.OnClientEvent("GetPartyState", function(player)
	local pm = loaded["PartyManager"]
	if pm and pm.SendPartyState then
		pm.SendPartyState(player)
	end
end)

-- ── Admin: Debug commands (Lobby-specific) ────────────────
NetworkManager.GetEvent("DebugCommand")
NetworkManager.OnClientEvent("DebugCommand", function(player, command, ...)
	if not IsAdmin(player) then
		warn("[Security] DebugCommand blocked for", player.Name)
		return
	end
	local args = {...}

	if command == "addXP" then
		local amount = args[1] or 100
		DataManager.AddExperience(player, amount)
	end
end)

-- ───────────────────────────────────────────────────────────
-- PLAYER CONNECTIONS
-- ───────────────────────────────────────────────────────────
-- §L1 fix: drive OnPlayerReady from PlayerDataManager.OnPlayerDataReady
-- instead of a 20×500ms polling loop. The callback fires exactly once
-- per player as soon as their DataStore load completes — no timeout,
-- no wasted task.wait cycles, no risk of timing out before slow loads.
local function OnPlayerReady(player)
	local data = DataManager.GetData(player)
	if not data then
		-- Should be impossible since this fires only after data is ready,
		-- but never silently no-op on edge cases.
		warn("[Lobby] OnPlayerReady fired with no data for", player.Name)
		return
	end

	local account = DataManager.GetAccountData(player)

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

	-- Push fresh StatsUpdate so the client stats panel is correct immediately
	-- (no need to open the menu first; avoids displaying stale cached data).
	loaded["SharedEventHandlers"].PushStatsUpdate(player)

	NetworkManager.FireClient(player, "ServerReady")
end

if DataManager.OnPlayerDataReady then
	DataManager.OnPlayerDataReady(OnPlayerReady)
else
	-- Fallback: keep the old polling behaviour so the place still boots
	-- if PlayerDataManager hasn't yet exposed the callback API.
	warn("[Lobby] PlayerDataManager.OnPlayerDataReady missing — falling back to polling")
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

Players.PlayerRemoving:Connect(function(player)
	local DataManager = loaded["PlayerDataManager"]
	if DataManager then
		DataManager.RemovePlayer(player)
	end
end)

print("[Lobby] Place ready — waiting for players")
