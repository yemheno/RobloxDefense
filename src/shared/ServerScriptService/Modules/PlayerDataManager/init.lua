-- ServerScriptService/Modules/PlayerDataManager

local PlayerDataManager = {}

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local DATA_STORE_KEY = "PlayerData_v1"
local AUTO_SAVE_INTERVAL = 300  -- seconds between auto-saves

-- §PDM-D7: gate the noisy save-entry print behind a flag. Was useful to
-- diagnose the §PERSIST1 XP-loss bug; now it's just log spam in production.
-- Flip to true if a save bug ever resurfaces.
local DEBUG_SAVE = false

local LOCAL_DATASTORE = DataStoreService:GetDataStore(DATA_STORE_KEY)

local Modules = script.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))

-- §PDM-D6: hoisted from below for readability. Tracks in-progress saves
-- so concurrent auto-save + terminal save don't double-write.
local savingPlayers = {}

-- Child systems (loaded in Init)
local ClassSystem
local StatSystem
local BonusSystem
local LevelSystem

-- Lazy-loaded for XP HUD notifications (avoids circular dep at module load time)
local _NetworkManager = nil
local function getNetworkManager()
	if not _NetworkManager then
		local nm = Modules:FindFirstChild("NetworkManager")
		if nm then
			local ok, result = pcall(require, nm)
			if ok then _NetworkManager = result end
		end
	end
	return _NetworkManager
end

-- Internal storage (shared with children via getter)
local playerDataStore = {}

-- Callbacks fired when a player's data finishes loading from the DataStore.
-- Registered via PlayerDataManager.OnPlayerDataReady(callback).
local dataReadyCallbacks = {}

--============================================
-- INITIALIZATION
--============================================
function PlayerDataManager.Init()
	-- Load child systems
	ClassSystem = require(script:WaitForChild("PlayerClassSystem"))
	StatSystem = require(script:WaitForChild("PlayerStatSystem"))
	BonusSystem = require(script:WaitForChild("PlayerBonusSystem"))
	LevelSystem = require(script:WaitForChild("PlayerLevelSystem"))

	-- Give children access to parent and data store
	ClassSystem.PlayerDataManager = PlayerDataManager
	StatSystem.PlayerDataManager = PlayerDataManager
	BonusSystem.PlayerDataManager = PlayerDataManager
	LevelSystem.PlayerDataManager = PlayerDataManager

	ClassSystem.GetDataStore = function() return playerDataStore end
	StatSystem.GetDataStore = function() return playerDataStore end
	BonusSystem.GetDataStore = function() return playerDataStore end
	LevelSystem.GetDataStore = function() return playerDataStore end

	-- Initialize children
	ClassSystem.Init()
	StatSystem.Init()
	BonusSystem.Init()
	LevelSystem.Init()

	-- Player connections
	Players.PlayerAdded:Connect(PlayerDataManager.SetupPlayer)
	Players.PlayerRemoving:Connect(PlayerDataManager.RemovePlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		PlayerDataManager.SetupPlayer(player)
	end

	-- Auto-save loop
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				PlayerDataManager.SavePlayer(player)
			end
		end
	end)

	-- Save all on server shutdown. §PERSIST1: force=true so the dedup
	-- can't skip the terminal save when an auto-save is in flight.
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			PlayerDataManager.SavePlayer(player, true)
		end
	end)

end

--============================================
-- DEFAULT DATA CREATION
--============================================

-- Deep-merge: add any missing keys from 'defaults' into 'target' without overwriting.
local function DeepMerge(target, defaults)
	for key, defaultValue in pairs(defaults) do
		if target[key] == nil then
			if type(defaultValue) == "table" then
				target[key] = {}
				DeepMerge(target[key], defaultValue)
			else
				target[key] = defaultValue
			end
		elseif type(target[key]) == "table" and type(defaultValue) == "table" then
			DeepMerge(target[key], defaultValue)
		end
	end
end

-- §4.2 + §4.3: deprecated-key sweep.
-- DeepMerge only ADDS missing keys; it never removes stale ones from older
-- save formats. Every key listed here is a field we no longer use (either
-- migrated to a different system, or removed outright). We strip them on
-- load so they don't bloat the save blob, shadow newer defaults, or trip
-- up code that does `for k, v in pairs(data.Account)` iteration.
--
-- When adding to this list:
--   • path is a dot-separated address relative to the root `data` table
--   • Use "*" segments for table values (not needed yet but reserved)
--   • Prefer outright deletion to renaming — DeepMerge fills the new name.
local DEPRECATED_KEY_PATHS = {
	"Account.RespecTokens",     -- migrated to inventory item `respec_scroll`
	"Account.ArmorXP",          -- armor-XP system removed (§1.3)
	"Account.ArmorLevel",       -- armor-level system removed (§1.3)
	"Account.ArmorAllocated",   -- armor-allocation system removed (§1.3)
}

local function PruneDeprecatedKeys(data)
	if type(data) ~= "table" then return end
	for _, path in ipairs(DEPRECATED_KEY_PATHS) do
		local segs = string.split(path, ".")
		local parent = data
		for i = 1, #segs - 1 do
			parent = parent and parent[segs[i]]
			if type(parent) ~= "table" then parent = nil; break end
		end
		if parent then
			local leaf = segs[#segs]
			if parent[leaf] ~= nil then
				parent[leaf] = nil
				-- Quiet on purpose: this is expected housekeeping on load.
				-- If you want to verify a migration ran, flip this to print.
			end
		end
	end
end

-- Sentinel value: distinguishes "first visit (nil)" from "DataStore error".
local LOAD_FAILED = { __loadFailed = true }

local LOAD_MAX_RETRIES = 3
local LOAD_RETRY_DELAY = 2  -- seconds (doubles each retry)

-- Load raw data from DataStore with retry.
-- Returns the saved table on success, nil on genuine first visit,
-- or LOAD_FAILED if all retries are exhausted.
local function LoadRawData(userId)
	local delay = LOAD_RETRY_DELAY
	for attempt = 1, LOAD_MAX_RETRIES do
		local ok, result = pcall(function()
			return LOCAL_DATASTORE:GetAsync(tostring(userId))
		end)
		if ok then
			return result  -- nil = first visit, table = existing data
		end
		warn("[PlayerDataManager] DataStore load error (attempt "
			.. attempt .. "/" .. LOAD_MAX_RETRIES .. ") for userId",
			userId, ":", result)
		if attempt < LOAD_MAX_RETRIES then
			task.wait(delay)
			delay = delay * 2
		end
	end
	return LOAD_FAILED
end
local function CreateDefaultData()
	local data = {
		Account = {},
		Classes = {},
		ActiveClass = "Aegis",
		LastClassSwitch = 0,
		Bonus = {},
	}

	-- Copy account defaults
	for key, value in pairs(Config.AccountDefaults) do
		if type(value) == "table" then
			data.Account[key] = {}
			for k, v in pairs(value) do
				data.Account[key][k] = v
			end
		else
			data.Account[key] = value
		end
	end

	-- CharacterData needs a fresh copy (avoid shared skins table between players)
	data.Account.CharacterData = {
		isCreated    = false,
		gender       = nil,
		preset       = nil,
		skins        = {},
		equippedSkin = nil,
	}

	-- Create class data for unlocked classes
	for _, className in ipairs(data.Account.UnlockedClasses) do
		data.Classes[className] = Config.CreateClassData()
	end

	-- Bonus stats (flat modifiers on top of primary-derived values)
	for key, value in pairs(Config.BonusStats) do
		data.Bonus[key] = value
	end

	return data
end

--============================================
-- PLAYER SETUP / REMOVAL
--============================================
-- Guard: prevent double-setup if PlayerAdded fires during Init() loop.
local setupInProgress = {}

function PlayerDataManager.SetupPlayer(player)
	if setupInProgress[player] or playerDataStore[player] then
		return  -- already setting up or already set up
	end
	setupInProgress[player] = true

	-- Try loading persisted data; fall back to fresh defaults only on genuine first visit.
	local rawSaved = LoadRawData(player.UserId)

	if rawSaved == LOAD_FAILED then
		-- All DataStore retries exhausted — DO NOT give default data (would erase progress).
		warn("[PlayerDataManager] CRITICAL: Cannot load data for", player.Name, "— kicking to prevent data loss.")
		setupInProgress[player] = nil
		player:Kick("Unable to load your saved data. Please rejoin. If this persists, contact support.")
		return
	end

	local data = CreateDefaultData()

	if rawSaved and type(rawSaved) == "table" then
		-- Merge saved data onto defaults so new keys added in updates are present.
		DeepMerge(rawSaved, data)
		data = rawSaved
		-- §4.2: strip deprecated keys that DeepMerge can't remove on its own.
		PruneDeprecatedKeys(data)
		print("[PlayerDataManager] Loaded saved data for", player.Name)
	else
		print("[PlayerDataManager] First visit — using default data for", player.Name)
	end

	playerDataStore[player] = data
	setupInProgress[player] = nil

	-- ── Sanitize Allocated tables ────────────────────────────────────────
	-- Remove any keys from classData.Allocated that are no longer in
	-- Config.PrimaryStats.  Orphaned stat names (e.g. from a rename) are
	-- silently counted by GetSpentPoints (which uses pairs) even though they
	-- are invisible in the UI (which uses ipairs(PrimaryStats)).  This causes
	-- the unallocated budget to be drained by "ghost" points, showing 0 free
	-- points when the player still expects to allocate.
	local primarySet = {}
	for _, s in ipairs(Config.PrimaryStats) do primarySet[s] = true end

	for _, classData in pairs(data.Classes) do
		if classData.Allocated then
			for key in pairs(classData.Allocated) do
				if not primarySet[key] then
					classData.Allocated[key] = nil   -- delete the orphaned key
				end
			end
		end
	end

	-- Fire all registered data-ready callbacks so other systems (e.g. SharedEventHandlers)
	-- can push the initial PlayerInfoUpdate immediately after data loads.
	for _, cb in ipairs(dataReadyCallbacks) do
		task.spawn(cb, player)
	end

	-- Auto-unlock any classes this player now qualifies for (handles both
	-- returning players and future live updates to unlock requirements).
	task.defer(function()
		if ClassSystem then
			ClassSystem.CheckAndUnlockEligibleClasses(player)
		end
	end)

	-- Create leaderstats (the Roblox built-in player-list overlay).
	-- §PDM-D12: Level + PowerScore are the headline stats players want at a
	-- glance; Merits/Essence are economy and don't belong in the always-on
	-- player list (Achievement UI shows them in detail).
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local levelValue = Instance.new("IntValue")
	levelValue.Name = "Level"
	levelValue.Value = data.Account.Level
	levelValue.Parent = leaderstats

	local powerValue = Instance.new("IntValue")
	powerValue.Name = "Power"
	powerValue.Value = 0  -- computed by RefreshPowerScore below; safe default
	powerValue.Parent = leaderstats

	-- Expose level as a player Attribute so other systems (TeleportDataReader,
	-- HordeModeMain) can read it without a PlayerDataManager reference.
	player:SetAttribute("Level", data.Account.Level)

	-- Initial power score. Subsequent equipment / level changes call
	-- PlayerDataManager.RefreshPowerScore(player) to keep this current.
	PlayerDataManager.RefreshPowerScore(player)

	-- Apply health on spawn. §PDM-D9: pass freshSpawn=true so the player
	-- starts at full HP — the proportional-rescale branch is reserved for
	-- mid-life stat changes (AllocateStat etc.).
	player.CharacterAdded:Connect(function(character)
		StatSystem.ApplyHealthToCharacter(player, character, true)
	end)

	if player.Character then
		StatSystem.ApplyHealthToCharacter(player, player.Character, true)
	end
end

function PlayerDataManager.RemovePlayer(player)
	-- §PERSIST1: force save on player leaving (teleport-out, disconnect,
	-- kick). This MUST NOT be skipped by the auto-save dedup or the
	-- player loses XP / progression earned since the last successful save.
	PlayerDataManager.SavePlayer(player, true)
	playerDataStore[player] = nil
end

--- Permanently delete all saved data for a player from the DataStore and from
--- the in-memory store.  Call this for admin "full wipe" testing only.
--- Returns (true) on success or (false, errorMessage) on DataStore failure.
--- The caller is responsible for kicking the player afterwards so they rejoin
--- with clean default data.
function PlayerDataManager.WipeData(player)
	local key = tostring(player.UserId)

	-- Cancel any in-flight save so it doesn't overwrite the removal.
	savingPlayers[key] = nil

	-- Remove from DataStore (this is the authoritative wipe).
	local ok, err = pcall(function()
		LOCAL_DATASTORE:RemoveAsync(key)
	end)

	if not ok then
		warn("[PlayerDataManager] WipeData failed for", player.Name, ":", err)
		return false, tostring(err)
	end

	-- Clear in-memory so RemovePlayer's SavePlayer doesn't re-persist data
	-- if the player disconnects before being fully kicked.
	playerDataStore[player] = nil

	print("[PlayerDataManager] Data wiped for", player.Name, "(userId:", key .. ")")
	return true
end

-- §PERSIST1 fix: force-save bypasses the dedup that was silently
-- swallowing terminal saves. Story: auto-save fires at minute 4,
-- yields inside SetAsync. Player teleports at minute 4.5. PlayerRemoving
-- runs, calls SavePlayer, sees savingPlayers[key]=true, returns.
-- Auto-save completes — wrote the PRE-XP snapshot. Post-XP is gone.
-- Force=true waits for the in-flight save to clear (max 3s), then
-- writes the latest state. Auto-save still uses force=false for
-- normal dedup behaviour.
function PlayerDataManager.SavePlayer(player, force)
	if DEBUG_SAVE then
		print(string.format("[PlayerDataManager] SavePlayer ENTRY: %s force=%s",
			tostring(player and player.Name), tostring(force == true)))
	end

	local data = playerDataStore[player]
	if not data then
		warn(string.format(
			"[PlayerDataManager] SavePlayer aborted for %s: in-memory data is nil. " ..
			"Either SetupPlayer never ran or another system already cleared it.",
			tostring(player and player.Name)))
		return
	end

	local key = tostring(player.UserId)

	if force then
		-- §PERSIST1: wait for any in-flight save (auto-save) to clear
		-- so we know our subsequent SetAsync writes the LATEST state.
		-- Cap the wait at 3s; beyond that we proceed regardless rather
		-- than block teleport / shutdown indefinitely.
		local waited = 0
		while savingPlayers[key] and waited < 3 do
			task.wait(0.1)
			waited = waited + 0.1
		end
	else
		-- Non-force (auto-save): skip if a save is already in flight.
		if savingPlayers[key] then return end
	end

	savingPlayers[key] = true

	local ok, err = pcall(function()
		LOCAL_DATASTORE:SetAsync(key, data)
	end)

	savingPlayers[key] = nil

	if not ok then
		warn("[PlayerDataManager] Failed to save data for", player.Name, ":", err)
	else
		print("[PlayerDataManager] Saved data for", player.Name, force and "(force)" or "")
	end
end

--============================================
-- RAW DATA ACCESS
--============================================
--- Register a callback invoked (task.spawn) when a player's data is ready.
--- The callback receives the Player instance as its sole argument.
---
--- CONTRACT — callbacks MUST be idempotent. They may fire more than once
--- for the same player across server-lifetime edge cases (e.g. a player
--- who teleports out then back into the same server during dev tooling).
--- New callers should treat "already initialized" as a normal return path,
--- not an error.
function PlayerDataManager.OnPlayerDataReady(callback)
	table.insert(dataReadyCallbacks, callback)
end

--============================================
-- POWER SCORE (leaderstats sync)
--============================================
-- §PDM-D12: GearRating.GetDisplayPower is the single source of truth for
-- the composite power rating. We mirror it into the player's `Power`
-- leaderstat so the Roblox player-list overlay always shows a current
-- value. Call this whenever something that affects power changes:
-- level-up, weapon/armor change, talent allocation, accessory equip.
-- The function is cheap (pure data computation, no DataStore touch).
local _GearRating = nil
local function getGearRating()
	if _GearRating ~= nil then return _GearRating end
	local ok, mod = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GearRating"))
	end)
	if ok then _GearRating = mod else _GearRating = false end
	return _GearRating or nil
end

function PlayerDataManager.RefreshPowerScore(player)
	local data = playerDataStore[player]
	if not data then return end
	local gr = getGearRating()
	if not gr then return end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local powerStat = leaderstats:FindFirstChild("Power")
	if not powerStat then return end

	local ok, score = pcall(gr.GetDisplayPower, data)
	if ok and type(score) == "number" then
		powerStat.Value = math.floor(score)
	end
end

function PlayerDataManager.GetData(player)
	return playerDataStore[player]
end

function PlayerDataManager.GetDataStore()
	return playerDataStore
end

function PlayerDataManager.GetLeaderstats(player)
	return player:FindFirstChild("leaderstats")
end

--============================================
-- ACCOUNT DATA ACCESS
--============================================
function PlayerDataManager.GetAccountData(player, key)
	local data = playerDataStore[player]
	if not data then return nil end

	if key then
		return data.Account[key]
	end
	return data.Account
end

function PlayerDataManager.SetAccountData(player, key, value)
	local data = playerDataStore[player]
	if not data then return false end

	data.Account[key] = value

	if key == "Level" then
		-- Keep leaderstats and player Attribute in sync.
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local stat = leaderstats:FindFirstChild(key)
			if stat then stat.Value = value end
		end
		player:SetAttribute("Level", value)
		-- §PDM-D12: level is a Power component, refresh the leaderstat.
		PlayerDataManager.RefreshPowerScore(player)
		return true
	end

	-- Other keys that used to mirror to leaderstats (Merits) no longer do —
	-- the only leaderstats are Level and Power. Both are handled explicitly.
	return true
end

--============================================
-- CLASS DATA ACCESS (basic getters)
--============================================
function PlayerDataManager.GetActiveClass(player)
	local data = playerDataStore[player]
	return data and data.ActiveClass or "Aegis"
end

function PlayerDataManager.GetActiveClassData(player)
	local data = playerDataStore[player]
	if not data then return nil end

	return data.Classes[data.ActiveClass]
end

function PlayerDataManager.GetClassData(player, className)
	local data = playerDataStore[player]
	if not data then return nil end

	return data.Classes[className]
end

function PlayerDataManager.SetClassData(player, className, key, value)
	local data = playerDataStore[player]
	if not data or not data.Classes[className] then return false end

	data.Classes[className][key] = value
	return true
end

function PlayerDataManager.HasClassData(player, className)
	local data = playerDataStore[player]
	return data and data.Classes[className] ~= nil
end

--============================================
-- WEAPON DATA ACCESS
--============================================
function PlayerDataManager.GetEquippedWeapon(player, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return nil end
	return classData.EquippedWeapon
end

function PlayerDataManager.SetEquippedWeapon(player, weaponInstance, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return false end
	classData.EquippedWeapon = weaponInstance
	return true
end

function PlayerDataManager.GetOwnedWeapons(player, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return {} end
	return classData.OwnedWeapons or {}
end

function PlayerDataManager.AddOwnedWeapon(player, weaponId, weaponInstance, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return false end

	classData.OwnedWeapons = classData.OwnedWeapons or {}

	if classData.OwnedWeapons[weaponId] then
		return false
	end

	classData.OwnedWeapons[weaponId] = weaponInstance
	return true
end

function PlayerDataManager.GetOwnedWeapon(player, weaponId, className)
	local ownedWeapons = PlayerDataManager.GetOwnedWeapons(player, className)
	return ownedWeapons[weaponId]
end

function PlayerDataManager.HasWeapon(player, weaponId, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return false end

	if classData.EquippedWeapon and classData.EquippedWeapon.weaponId == weaponId then
		return true
	end

	if classData.OwnedWeapons and classData.OwnedWeapons[weaponId] then
		return true
	end

	return false
end

--============================================
-- EXPOSE CHILD SYSTEMS
--============================================
function PlayerDataManager.GetSystems()
	return {
		Class = ClassSystem,
		Stat = StatSystem,
		Bonus = BonusSystem,
		Level = LevelSystem,
	}
end

function PlayerDataManager.CheckUnlockEligibleClasses(player)
	return ClassSystem.CheckAndUnlockEligibleClasses(player)
end

-- Convenience pass-through functions (so existing code doesn't break)

-- Class System
function PlayerDataManager.SetActiveClass(player, className)
	return ClassSystem.SetActiveClass(player, className)
end

function PlayerDataManager.CanSwitchClass(player)
	return ClassSystem.CanSwitchClass(player)
end

function PlayerDataManager.GetSwitchCooldownRemaining(player)
	return ClassSystem.GetSwitchCooldownRemaining(player)
end

function PlayerDataManager.IsClassUnlocked(player, className)
	return ClassSystem.IsClassUnlocked(player, className)
end

function PlayerDataManager.UnlockClass(player, className)
	return ClassSystem.UnlockClass(player, className)
end

function PlayerDataManager.CreateClassData(player, className)
	return ClassSystem.CreateClassData(player, className)
end

-- Stat System
function PlayerDataManager.GetAvailablePoints(player)
	return StatSystem.GetAvailablePoints(player)
end

function PlayerDataManager.GetSpentPoints(player, className)
	return StatSystem.GetSpentPoints(player, className)
end

function PlayerDataManager.GetUnallocatedPoints(player, className)
	return StatSystem.GetUnallocatedPoints(player, className)
end

function PlayerDataManager.GetAllocatedStat(player, statName, className)
	return StatSystem.GetAllocatedStat(player, statName, className)
end

function PlayerDataManager.AllocateStat(player, statName, points)
	return StatSystem.AllocateStat(player, statName, points)
end

function PlayerDataManager.DeallocateStat(player, statName, points)
	return StatSystem.DeallocateStat(player, statName, points)
end

function PlayerDataManager.ResetAllocation(player, className)
	return StatSystem.ResetAllocation(player, className)
end

function PlayerDataManager.GetTotalStat(player, statName)
	return StatSystem.GetTotalStat(player, statName)
end

function PlayerDataManager.ApplyHealthToCharacter(player, character)
	return StatSystem.ApplyHealthToCharacter(player, character)
end

function PlayerDataManager.ResetHealth(player)
	return StatSystem.ResetHealth(player)
end

-- Bonus System
function PlayerDataManager.GetBonus(player, bonusName)
	return BonusSystem.GetBonus(player, bonusName)
end

function PlayerDataManager.SetBonus(player, bonusName, value)
	return BonusSystem.SetBonus(player, bonusName, value)
end

function PlayerDataManager.ModifyBonus(player, bonusName, delta)
	return BonusSystem.ModifyBonus(player, bonusName, delta)
end

-- §PDM-D2: GetSystemStat / SetSystemStat removed — they were aliases of
-- GetBonus / SetBonus. Use the Bonus API directly.

function PlayerDataManager.ApplyWeaponBonuses(player)
	return BonusSystem.ApplyWeaponBonuses(player)
end

function PlayerDataManager.RefreshWeaponStats(player)
	return BonusSystem.RefreshWeaponStats(player)
end

function PlayerDataManager.ApplyArmorBonuses(player)
	return BonusSystem.ApplyArmorBonuses(player)
end

function PlayerDataManager.RefreshArmorStats(player)
	return BonusSystem.RefreshArmorStats(player)
end

-- Level System
function PlayerDataManager.AddExperience(player, amount)
	LevelSystem.AddExperience(player, amount)

	-- Push updated XP / level to the player's HUD immediately.
	-- This central notification covers ALL XP sources: kill rewards, wave bonuses,
	-- admin commands, etc. — so every caller gets the HUD update for free.
	local account = PlayerDataManager.GetAccountData(player)
	if account then
		local net = getNetworkManager()
		if net then
			net.FireClient(player, "PlayerInfoUpdate", {
				level    = account.Level,
				xp       = account.Experience,
				xpNeeded = Config.GetXPForLevel(account.Level),
			})
		end
	end
end

--============================================
-- DEBUG
--============================================
function PlayerDataManager.GetDebugInfo(player)
	local data = playerDataStore[player]
	if not data then return "No data" end

	local activeClass = data.ActiveClass
	local classData = data.Classes[activeClass]

	local info = {
		"=== PlayerDataManager Debug ===",
		"Account Level: " .. data.Account.Level,
		"Active Class: " .. activeClass,
	}

	-- Stat info
	local statInfo = StatSystem.GetDebugInfo(player)
	if statInfo then
		table.insert(info, statInfo)
	end

	-- Weapon info
	table.insert(info, "--- Weapon ---")
	local weapon = classData and classData.EquippedWeapon
	if weapon then
		table.insert(info, "ID: " .. weapon.weaponId)
		table.insert(info, "Level: " .. weapon.level .. " | +: " .. weapon.refinement .. " | Tier: " .. weapon.tier)
		if weapon.bonuses then
			for i, bonus in ipairs(weapon.bonuses) do
				table.insert(info, "  " .. i .. ". " .. bonus.stat .. ": +" .. bonus.value)
			end
		end
	else
		table.insert(info, "No weapon equipped")
	end

	return table.concat(info, "\n")
end

return PlayerDataManager