-- ServerScriptService/Modules/NetworkManager

local NetworkManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local eventsFolder = nil
local remoteEvents = {}

-- ── Rate limiting ──────────────────────────────────────────
local RATE_LIMIT    = 30   -- max calls per player per event per window
local RATE_WINDOW   = 1    -- window length in seconds
-- rateBuckets[eventName][player] = { count, windowStart, lastAccess }
local rateBuckets   = {}
local BUCKET_CLEANUP_INTERVAL = 60  -- seconds between cleanups
local BUCKET_MAX_AGE = 60  -- remove entries not accessed in this many seconds

local function isRateLimited(eventName, player)
	local buckets = rateBuckets[eventName]
	if not buckets then
		buckets = {}
		rateBuckets[eventName] = buckets
	end

	local now = os.clock()
	local bucket = buckets[player]
	if not bucket or (now - bucket.start) >= RATE_WINDOW then
		buckets[player] = { count = 1, start = now, lastAccess = now }
		return false
	end

	bucket.count = bucket.count + 1
	bucket.lastAccess = now
	if bucket.count > RATE_LIMIT then
		return true
	end
	return false
end

local function cleanupStaleBuckets()
	local now = os.clock()
	for eventName, buckets in pairs(rateBuckets) do
		for player, bucket in pairs(buckets) do
			if (now - bucket.lastAccess) > BUCKET_MAX_AGE then
				buckets[player] = nil
			end
		end
		-- Remove empty event entries
		if next(buckets) == nil then
			rateBuckets[eventName] = nil
		end
	end
end


-- INITIALIZATION
function NetworkManager.Init()
	-- Create Events folder
	eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	-- Pre-register every event that clients subscribe to on load.
	-- Without this, clients calling WaitForChild(eventName, 3) before the
	-- server first fires the event will time-out with "Event not found".
	local PRE_REGISTER = {
		-- Core / player data
		"ServerReady", "PlayerInfoUpdate", "CharacterCreationRequired", "CharacterCreationSaved",
		"ClassSwitchResult", "StatsUpdate", "CurrencyUpdate",
		-- Equipment
		"EquipmentInfo", "WeaponEquipped", "ArmorEquipped",
		"WeaponLevelUp",
		"WeaponRefinementResult", "ArmorRefinementResult",
		"WeaponTierUp", "ArmorTierUp",
		"WeaponRerollResult", "ArmorRerollResult",
		-- NPC
		"NPCDialogue", "NPCQuestOffer", "NPCTeleportOffer",
		"NPCShopOpen", "NPCResponse", "NPCSmithOpen",
		-- Talents & Skills
		"TalentStateUpdate",
		"SkillActivated", "SkillVisual", "SkillCooldownUpdate", "SkillFailed",
		"BuffApplied", "BuffRemoved",
		"SkillCastStarted", "SkillCastCompleted", "SkillCastInterrupted",
		-- Combat (client→server events that must exist before client fires)
		"AttackEvent", "DamageNumber", "HealNumber", "ResourceUpdate",
		"SkillRequest",
		-- Mob events
		"MobSkillCast", "MobSkillHit",
		"LootDrop", "VitalsUpdate", "ComboUpdate",
		-- Scene & matchmaking
		"SceneChanged", "RequestSceneInfo", "MatchmakingUpdate",
		"GameStateChanged", "CountdownUpdate",
		-- Social
		"PartyUpdate", "PartyInvite", "PartyError", "PlayerListUpdate",
		-- Wave & defense-line events (HUD subscribes in both Lobby and LaneDefense)
		"WaveStarted", "WaveCompleted", "AllWavesCompleted",
		"DefenseLineUpdate", "DefenseLineDamaged", "DefenseLineDestroyed", "DefenseLineCombo",
		"PlayerDeath", "ComboEnded", "MobDeath",
		-- Equipment XP incremental updates
		"WeaponXPGained",
		-- Stats / respec (client listens)
		"RespecResult",
		-- Cosmetics (client listens)
		"WardrobeUpdate", "CosmeticEquipped",
		-- Achievements (client listens)
		"AchievementsData", "AchievementUnlocked",
		-- Shop (client listens)
		"ShopState", "ShopResult",
		-- Admin
		"AdminAction", "AdminActionResult",
		-- Debug
		"DebugCommand",
		-- Vote system (server→client, client→server)
		"VoteStart", "VoteUpdate", "VoteResult", "VoteRewardGranted", "VoteCast",
		-- Client → server (also need to exist so server can listen)
		"GetEquipmentInfo", "GetPlayerInfo", "GetStats",
		"RequestCharacterStatus", "CharacterCreationComplete",
		"RequestClassSwitch", "AllocateStat", "AllocateTalent",
		"PartyRequest",
		-- Matchmaking / social (client→server)
		"MatchmakingRequest", "PlayerListRequest", "GetPartyState",
		-- NPC interaction (client→server)
		"NPCInteract",
		-- Combat requests (client→server)
		"RequestStartGame", "RequestNextWave", "RequestReturnToLobby",
		"MobSkillHitReport",
		"MobBasicAttackHitReport",
		"PlayerHitReport",
		-- Combat visuals (server→client)
		"AttackFired", "CombatConfig", "RequestCombatConfig",
		"MobBasicAttackCast",
		-- Stats / respec (client→server)
		"RespecStats", "SaveKeybindings",
		-- Cosmetics (client→server)
		"GetWardrobe", "EquipCosmetic", "UnequipCosmetic",
		-- Achievements (client→server)
		"GetAchievements",
		-- Talents (client→server)
		"GetTalentState", "RespecTalents",
		-- Shop (client→server)
		"ShopPurchase", "GetShopState",
		-- Character creation (client→server)
		"RequestCharacterCreationCheck",
		-- Inventory (client→server, server→client)
		"GetInventory", "EquipAccessory", "UnequipAccessory", "InventoryUpdate",
		-- Daily login (client→server, server→client)
		"ClaimDailyLogin", "GetDailyLoginStatus", "DailyLoginResult", "DailyLoginStatus",
		-- Leaderboard (client→server, server→client)
		"GetLeaderboard", "LeaderboardData", "PlayerGearScore",
	}
	for _, name in ipairs(PRE_REGISTER) do
		NetworkManager.GetEvent(name)
	end

	-- Clean up rate-limit buckets when players leave
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		for _, buckets in pairs(rateBuckets) do
			buckets[player] = nil
		end
	end)

	-- Start periodic cleanup of stale rate-limit buckets
	task.spawn(function()
		while true do
			task.wait(BUCKET_CLEANUP_INTERVAL)
			cleanupStaleBuckets()
		end
	end)

	print("[NetworkManager] Initialized")
end


-- GET OR CREATE EVENT
function NetworkManager.GetEvent(eventName)
	-- Return cached event if exists
	if remoteEvents[eventName] then
		return remoteEvents[eventName]
	end

	-- Check if already in folder
	local event = eventsFolder:FindFirstChild(eventName)

	-- Create if doesn't exist
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = eventName
		event.Parent = eventsFolder
	end

	-- Cache and return
	remoteEvents[eventName] = event
	return event
end

-- FIRE EVENTS
function NetworkManager.FireClient(player, eventName, ...)
	local event = NetworkManager.GetEvent(eventName)
	event:FireClient(player, ...)
end

function NetworkManager.FireAllClients(eventName, ...)
	local event = NetworkManager.GetEvent(eventName)
	event:FireAllClients(...)
end


-- LISTEN FOR CLIENT EVENTS
function NetworkManager.OnClientEvent(eventName, callback)
	local event = NetworkManager.GetEvent(eventName)
	event.OnServerEvent:Connect(function(player, ...)
		if isRateLimited(eventName, player) then
			return
		end
		callback(player, ...)
	end)
end

return NetworkManager