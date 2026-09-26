-- ServerScriptService/Modules/PlayerDataManager

local PlayerDataManager = {}

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local DATA_STORE_KEY = "PlayerData_v1"
-- §AGX/X3: was 300. Auto-save is also the session-lock heartbeat, so it
-- has to beat LOCK_STALE_AFTER below — at 300 s a live server's lock
-- would look stale for 3.5 min of every 5 and could be stolen.
local AUTO_SAVE_INTERVAL = 60  -- seconds between auto-saves

-- §AGX/X3: session lock. The saved record carries
-- `_session = { jobId, placeId, time }` next to Account/Classes/… (there
-- is no wrapper table and adding one would break every existing save).
-- It is stripped on load and never lives in the in-memory data.
-- §AGX/X3r3: was 90 — one failed/slow 60 s heartbeat let a live lock go stale; ≥ 3 × AUTO_SAVE_INTERVAL.
local LOCK_STALE_AFTER   = 200  -- s; a lock older than this is dead and may be stolen
-- §AGX/X3r5: was 20 — give a slow teleport-source leave-save more time before we kick.
local LOCK_WAIT_MAX      = 30   -- s; how long a load waits on another live server's lock
local FINAL_SAVE_RETRIES = 3    -- §AGX/X3: extra attempts for the lock-releasing leave save
-- §AGX/X3r3: a failed heartbeat (auto-save) is retried once after this delay.
local HEARTBEAT_RETRY_DELAY = 10
-- §AGX/X3r1: cap on a rejoin waiting for this server's own release save
-- (worst case ≈ 3 s force-wait + 4 UpdateAsyncs + 1+2+4 s backoff).
local RELEASE_WAIT_MAX = 25

-- §AGX/X2: number of SavePlayer / lock-release calls currently running.
-- BindToClose waits for this to reach 0 so leave-saves that started
-- just before shutdown (ReturnTeleporter empties a server in one go)
-- aren't cut off.
local pendingSaves = 0

-- §AGX/X2: set once BindToClose starts. Stops the auto-save loop so it
-- can't re-take a lock the shutdown save just released.
local shuttingDown = false

-- §PDM-D7: gate the noisy save-entry print behind a flag. Was useful to
-- diagnose the §PERSIST1 XP-loss bug; now it's just log spam in production.
-- Flip to true if a save bug ever resurfaces.
local DEBUG_SAVE = false

local LOCAL_DATASTORE = DataStoreService:GetDataStore(DATA_STORE_KEY)

local Modules = script.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))

-- §PERF/BP: DataStore load is the single biggest boot yield — timed.
local BootProfiler = require(game:GetService("ReplicatedStorage")
	:WaitForChild("Shared"):WaitForChild("BootProfiler"))

-- §PDM-D6: hoisted from below for readability. Tracks in-progress saves
-- so concurrent auto-save + terminal save don't double-write.
local savingPlayers = {}

-- §T0P2/X17: tombstones for admin-wiped keys. Clearing savingPlayers
-- can't cancel an in-flight SetAsync — if one is mid-air it could land
-- AFTER RemoveAsync and resurrect the wiped data. SavePlayer checks
-- this set before writing. Cleared when the player sets up again.
local wipedPlayers = {}

-- §AGX/X3: keys whose lock-releasing final save has started. A plain
-- (auto/force) save that lands after it would re-take the lock and make
-- the player's next server wait until it goes stale, so the UpdateAsync
-- transform aborts non-releasing writes for these keys. Cleared when
-- the player sets up again.
-- §AGX/X3r8: also cleared once the release save succeeds (releasedPlayers takes over).
local releasingPlayers = {}

-- §AGX/X3r1: keys with a release save running right now. Set before the
-- force-wait (savingPlayers is only set after it) and cleared by the
-- SavePlayer wrapper after its pcall, so a same-server rejoin can wait
-- for the release write to land before loading.
local releaseInFlight = {}
-- §AGX/X3r12: per-key session generation. Bumped when a new session for
-- the key starts on this server; a save captured under an older generation
-- (e.g. an auto-save still queued in UpdateAsync across a quick same-server
-- rejoin) aborts instead of writing its stale snapshot over the new session.
local sessionGen = {}


-- §AGX/X3r7: keys whose release save succeeded this session. Lets a
-- second release (BindToClose + PlayerRemoving) be skipped, and keeps
-- the transform refusing plain saves after releasingPlayers is cleared
-- (§AGX/X3r8). Cleared when the player sets up again.
local releasedPlayers = {}

-- Guard: prevent double-setup if PlayerAdded fires during Init() loop.
-- §AGX/X3r9: hoisted from PLAYER SETUP so the auto-save loop in Init can read it.
local setupInProgress = {}
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

-- §AGX/X27: session play-time accumulator. Account.TotalPlayTime (whole
-- SECONDS — LeaderboardManager floors it and stores it as an integer) was
-- never written, so the TotalPlayTime board was always empty. The mark is
-- set when data is ready; AccruePlayTime folds the elapsed time into the
-- account and moves the mark forward, so it is idempotent and can run on
-- every save (heartbeat, leave, shutdown) and before a leaderboard persist.
-- Weak keys: a rejoin gets a new Player object and a fresh mark.
local playTimeMark = setmetatable({}, { __mode = "k" })  -- [player] = os.clock() of last accrual

table.insert(dataReadyCallbacks, function(player)
	playTimeMark[player] = os.clock()
end)

function PlayerDataManager.AccruePlayTime(player)
	local mark = playTimeMark[player]
	if not mark then return end
	local data = playerDataStore[player]
	if not data or not data.Account then return end
	local whole = math.floor(os.clock() - mark)
	if whole <= 0 then return end
	-- Keep the fractional remainder in the mark so nothing is lost to flooring.
	playTimeMark[player] = mark + whole
	data.Account.TotalPlayTime = (tonumber(data.Account.TotalPlayTime) or 0) + whole
end

-- §T0-FOLLOWUP/L2: per-player Janitor tracks the CharacterAdded conn
-- registered inside SetupPlayer so we can tear it down on PlayerRemoving.
local Janitor = require(script.Parent:WaitForChild("Janitor"))
local playerJanitors = setmetatable({}, { __mode = "k" })
local function getPlayerJanitor(player)
	local jan = playerJanitors[player]
	if not jan then
		jan = Janitor.new("PlayerDataManager.player")
		playerJanitors[player] = jan
	end
	return jan
end

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

	-- Save all on server shutdown. §PERSIST1: force=true so the dedup
	-- can't skip the terminal save when an auto-save is in flight.
	-- §T0P2/X6: saves run in PARALLEL. Sequentially, each force-save can
	-- wait up to 3 s for an in-flight auto-save plus the SetAsync yield —
	-- a full server could blow the 30 s BindToClose budget and lose the
	-- tail of the player list. Spawn all, then wait for completion.
	-- §AGX/X2: wait on the global pendingSaves counter instead of only the
	-- saves spawned here, and never early-return on an empty server — the
	-- usual case is ReturnTeleporter emptying the server, whose
	-- PlayerRemoving leave-saves are still in flight when this runs.
	-- §AGX/X3: these are final saves, so they release the session lock.
	-- §AGX/X3r4: registered BEFORE the existing-players setup below, so a
	-- shutdown during that (yielding) setup still saves/releases.
	game:BindToClose(function()
		shuttingDown = true
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(PlayerDataManager.SavePlayer, player, true, true)
		end
		-- 25 s cap keeps us inside Roblox's 30 s shutdown budget.
		local deadline = os.clock() + 25
		while pendingSaves > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
		if pendingSaves > 0 then
			warn("[PlayerDataManager] BindToClose deadline hit with", pendingSaves, "save(s) unfinished")
		end
	end)

	-- §AGX/X3r4: spawned — SetupPlayer yields on the DataStore (and up to
	-- LOCK_WAIT_MAX on a lock), which used to block the place's boot.
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(PlayerDataManager.SetupPlayer, player)
	end

	-- §AGX/X3r3: one heartbeat save; a failed write is retried once after
	-- HEARTBEAT_RETRY_DELAY so a single DataStore hiccup can't let the lock
	-- age toward LOCK_STALE_AFTER.
	local function HeartbeatSave(player)
		if PlayerDataManager.SavePlayer(player) ~= "error" then return end
		task.wait(HEARTBEAT_RETRY_DELAY)
		if shuttingDown or not player.Parent then return end
		PlayerDataManager.SavePlayer(player)
	end

	-- Auto-save loop
	task.spawn(function()
		while not shuttingDown do  -- §AGX/X2: stop once shutdown saves begin
			task.wait(AUTO_SAVE_INTERVAL)
			if shuttingDown then break end
			for _, player in ipairs(Players:GetPlayers()) do
				-- §AGX/X3r9: nothing to save yet while setup is loading — skip silently.
				if not setupInProgress[player] then
					-- §AGX/X3r3: spawned so slow saves don't stretch the heartbeat period.
					task.spawn(HeartbeatSave, player)
				end
			end
		end
	end)

end

--============================================
-- DEFAULT DATA CREATION
--============================================

-- §T0P2/X1: true deep copy for default tables. The old CreateDefaultData
-- copy was only two levels deep, so nested defaults (Wardrobe.owned,
-- Achievements.unlocked, Quests.active, …) were shared BY REFERENCE
-- between every first-visit player on the server AND with
-- PlayerDataConfig.AccountDefaults itself — player A's writes leaked
-- into player B's fresh save and into the config module for the rest
-- of the server's lifetime.
local function DeepCopy(source)
	local copy = {}
	for key, value in pairs(source) do
		if type(value) == "table" then
			copy[key] = DeepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

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
	"Account.RespecTokens",                  -- migrated to inventory item `respec_scroll`
	"Account.ArmorXP",                       -- armor-XP system removed (§1.3)
	"Account.ArmorLevel",                    -- armor-level system removed (§1.3)
	"Account.ArmorAllocated",                -- armor-allocation system removed (§1.3)
	"Account.CharacterData.skins",           -- §CC-T1.1: armor-as-part-replacement abandoned
	"Account.CharacterData.equippedSkin",    -- §CC-T1.1: armor-as-part-replacement abandoned
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
-- §AGX/X3: another live server still holds the session lock after
-- LOCK_WAIT_MAX (e.g. its leave-save never landed). Kicked like
-- LOAD_FAILED, with a "try again shortly" message.
local LOAD_LOCKED = { __loadLocked = true }
-- §AGX/X3: the player left while we were waiting on the lock.
local LOAD_ABANDONED = { __loadAbandoned = true }

local LOAD_MAX_RETRIES = 3
local LOAD_RETRY_DELAY = 2  -- seconds (doubles each retry)

-- §AGX/X3: session-lock helpers. game.JobId is "" in Studio, which is
-- still a consistent per-session id for this logic.
local function NewSessionLock()
	return { jobId = game.JobId, placeId = game.PlaceId, time = os.time() }
end

-- True when `lock` belongs to ANOTHER server and is recent enough that
-- the server is presumed alive. Records from before §AGX/X3 have no
-- `_session` at all and read as unlocked.
local function IsForeignLiveLock(lock)
	if type(lock) ~= "table" then return false end
	if lock.jobId == game.JobId then return false end
	local t = tonumber(lock.time) or 0
	return (os.time() - t) < LOCK_STALE_AFTER
end

-- Load raw data from DataStore with retry.
-- Returns the saved table on success, nil on genuine first visit,
-- or LOAD_FAILED if all retries are exhausted.
-- §AGX/X3: now an UpdateAsync that takes the session lock in the same
-- round-trip (GetAsync couldn't). If another live server holds the lock
-- — normally the teleport source whose leave-save hasn't landed yet —
-- back off and retry for up to LOCK_WAIT_MAX, then return LOAD_LOCKED.
-- A stale lock is simply overwritten (stolen). First visits write a
-- lock-only record so a second server can't also treat them as new.
-- The returned table has `_session` stripped; an empty table means
-- first visit and is returned as nil.
local function LoadRawData(userId, player)
	local key = tostring(userId)
	local delay = LOAD_RETRY_DELAY
	local errorAttempts = 0
	local lockDelay = 1
	local lockDeadline = os.clock() + LOCK_WAIT_MAX
	while true do
		local heldBy = nil
		local ok, result = pcall(function()
			return LOCAL_DATASTORE:UpdateAsync(key, function(old)
				heldBy = nil  -- transform can run more than once; reset per call
				if type(old) == "table" and IsForeignLiveLock(old._session) then
					heldBy = old._session
					return nil  -- abort: don't touch another live server's record
				end
				local record = if type(old) == "table" then old else {}
				record._session = NewSessionLock()
				return record
			end)
		end)
		if ok and not heldBy then
			if type(result) ~= "table" then return nil end
			result._session = nil
			if next(result) == nil then return nil end  -- lock-only record = first visit
			return result
		end
		if ok then
			-- Locked by another live server.
			if os.clock() >= lockDeadline then
				warn("[PlayerDataManager] Session lock for userId", userId,
					"still held by job", tostring(heldBy.jobId), "after", LOCK_WAIT_MAX, "s")
				return LOAD_LOCKED
			end
			task.wait(math.min(lockDelay, math.max(0, lockDeadline - os.clock())))
			lockDelay = math.min(lockDelay * 2, 4)
		else
			errorAttempts += 1
			warn("[PlayerDataManager] DataStore load error (attempt "
				.. errorAttempts .. "/" .. LOAD_MAX_RETRIES .. ") for userId",
				userId, ":", result)
			if errorAttempts >= LOAD_MAX_RETRIES then
				return LOAD_FAILED
			end
			task.wait(delay)
			delay = delay * 2
		end
		-- §AGX/X3r2: also give up on shutdown — this load is counted in
		-- pendingSaves, so waiting out LOCK_WAIT_MAX would only stall
		-- BindToClose. We hold no lock on this path (success returned above).
		if (player and not player.Parent) or shuttingDown then
			return LOAD_ABANDONED
		end
	end
end

-- §AGX/X3: drop our lock without writing data. Used when the player
-- leaves between the lock-taking load and SetupPlayer storing the data
-- (the §T0P2/X3 guard) — otherwise their next server waits
-- LOCK_WAIT_MAX on a lock nobody will release. Counted in pendingSaves.
local function ReleaseLockOnly(key)
	pendingSaves += 1
	local ok, err = pcall(function()
		LOCAL_DATASTORE:UpdateAsync(key, function(old)
			if type(old) ~= "table" or type(old._session) ~= "table" then return nil end
			if old._session.jobId ~= game.JobId then return nil end  -- not ours
			old._session = nil
			return old
		end)
	end)
	pendingSaves -= 1
	if not ok then
		warn("[PlayerDataManager] Failed to release session lock for key", key, ":", err)
	end
end
local function CreateDefaultData()
	local data = {
		Account = {},
		Classes = {},
		ActiveClass = "Aegis",
		LastClassSwitch = 0,
		Bonus = {},
	}

	-- §T0P2/X1: copy account defaults via DeepCopy so NO nested table is
	-- ever shared between players or with the config module. This also
	-- removes the old hand-built CharacterData special case — DeepCopy
	-- covers it (the schema in AccountDefaults stays the single source).
	data.Account = DeepCopy(Config.AccountDefaults)

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
-- (setupInProgress is declared at the top — §AGX/X3r9.)

-- §AGX/X3r2: the lock-taking part of SetupPlayer — load, then either
-- store the data or bail out (abandon / shutdown / kick). Split out so
-- SetupPlayer can count it in pendingSaves under a pcall: a load still
-- running at shutdown holds a fresh lock, and BindToClose must wait for
-- it to be stored-and-released or handed back. Returns the stored data,
-- or nil when setup must stop (setupInProgress already cleared).
local function LoadAndStorePlayerData(player, userKey)
	-- Try loading persisted data; fall back to fresh defaults only on genuine first visit.
	local doneDataLoad = BootProfiler.Begin("DataLoad " .. player.Name)  -- §PERF/BP
	local rawSaved = LoadRawData(player.UserId, player)
	doneDataLoad()

	-- §T0P2/X3: the player may have left while LoadRawData was yielding
	-- (PlayerRemoving already ran — there was nothing to clean up yet).
	-- Without this guard we'd store data for a departed Player (strong
	-- key → leaks forever) and fire dataReadyCallbacks for a ghost,
	-- setting up downstream state whose cleanup hook already fired.
	-- §AGX/X3r2: same on shutdown — BindToClose already snapshotted the
	-- player list, so nobody would release a lock taken by this load.
	-- No yield between here and the store below, so this check is final.
	if not player.Parent or rawSaved == LOAD_ABANDONED or shuttingDown then
		setupInProgress[player] = nil
		-- §AGX/X3: the load took the session lock; hand it back so the
		-- player's next server doesn't wait on it.
		if rawSaved ~= LOAD_FAILED and rawSaved ~= LOAD_LOCKED and rawSaved ~= LOAD_ABANDONED then
			-- Runs up to its first yield now, so its pendingSaves += 1
			-- lands before our caller's decrement.
			task.spawn(ReleaseLockOnly, userKey)
		end
		return nil
	end

	if rawSaved == LOAD_FAILED then
		-- All DataStore retries exhausted — DO NOT give default data (would erase progress).
		warn("[PlayerDataManager] CRITICAL: Cannot load data for", player.Name, "— kicking to prevent data loss.")
		setupInProgress[player] = nil
		player:Kick("Unable to load your saved data. Please rejoin. If this persists, contact support.")
		return nil
	end

	-- §AGX/X3: another server still owns this save (its leave-save never
	-- landed within LOCK_WAIT_MAX). Loading anyway would fork the data.
	if rawSaved == LOAD_LOCKED then
		warn("[PlayerDataManager] Session still locked by another server for", player.Name, "— kicking.")
		setupInProgress[player] = nil
		player:Kick("Your data is still being saved by another server. Please rejoin in a minute.")
		return nil
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
	return data
end

function PlayerDataManager.SetupPlayer(player)
	if setupInProgress[player] or playerDataStore[player] then
		return  -- already setting up or already set up
	end
	setupInProgress[player] = true

	-- §T0P2/X17: a rejoin after an admin wipe starts a fresh life for
	-- this key — lift the save tombstone.
	local userKey = tostring(player.UserId)
	wipedPlayers[userKey] = nil

	-- §AGX/X3: a quick rejoin to THIS server can arrive while the previous
	-- session's leave-save is still running. Our own jobId never blocks
	-- the lock, so wait for that save here (capped) or we'd load the
	-- pre-save record.
	-- §AGX/X3r1: wait on releaseInFlight, not savingPlayers — savingPlayers
	-- is only set after the release save's 3 s force-wait (and an auto-save
	-- finishing clears it early); 25 s covers the release's full retry chain.
	local waitedForSave = 0
	while releaseInFlight[userKey] and waitedForSave < RELEASE_WAIT_MAX do
		task.wait(0.1)
		waitedForSave += 0.1
	end
	-- §AGX/X3r1: player left, or shutdown began, during the wait — no lock taken yet.
	if not player.Parent or shuttingDown then
		setupInProgress[player] = nil
		return
	end
	-- §AGX/X3r1: still running after the cap — loading now could read the
	-- pre-save record, and the old release finishing later would mark this
	-- new session released (blocking its saves). Kick like LOAD_LOCKED.
	if releaseInFlight[userKey] then
		warn("[PlayerDataManager] Release save for", player.Name, "still running after",
			RELEASE_WAIT_MAX, "s — kicking.")
		setupInProgress[player] = nil
		player:Kick("Your data is still being saved. Please rejoin in a minute.")
		return
	end
	releasingPlayers[userKey] = nil  -- §AGX/X3: new session for this key
	sessionGen[userKey] = (sessionGen[userKey] or 0) + 1  -- §AGX/X3r12
	releasedPlayers[userKey] = nil   -- §AGX/X3r7: likewise for the release-done marker

	-- §AGX/X3r2: count the lock-taking load so BindToClose waits for it;
	-- pcall guarantees the decrement.
	pendingSaves += 1
	local loadOk, data = pcall(LoadAndStorePlayerData, player, userKey)
	pendingSaves -= 1
	if not loadOk then
		warn("[PlayerDataManager] CRITICAL: SetupPlayer load errored for", player.Name, ":", data)
		setupInProgress[player] = nil
		playerDataStore[player] = nil
		task.spawn(ReleaseLockOnly, userKey)  -- no-op unless the lock is ours
		if player.Parent then
			player:Kick("Unable to load your saved data. Please rejoin. If this persists, contact support.")
		end
		return
	end
	if not data then return end
	BootProfiler.Mark("DataReady " .. player.Name)  -- §PERF/BP

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

	-- §T0P2/X7: fire data-ready callbacks AFTER leaderstats + the Level
	-- attribute exist. task.spawn runs each callback immediately (until
	-- its first yield), so anything fired here that reads
	-- player:GetAttribute("Level") — e.g. TeleportDataReader's
	-- no-teleport-data fallback — now sees the real level, not nil.
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

	-- Apply health on spawn. §PDM-D9: pass freshSpawn=true so the player
	-- starts at full HP — the proportional-rescale branch is reserved for
	-- mid-life stat changes (AllocateStat etc.).
	-- §T0-FOLLOWUP/L2: track the conn through the per-player Janitor so
	-- PlayerRemoving cleanly disconnects it.
	getPlayerJanitor(player):Add(player.CharacterAdded:Connect(function(character)
		StatSystem.ApplyHealthToCharacter(player, character, true)
	end))

	if player.Character then
		StatSystem.ApplyHealthToCharacter(player, player.Character, true)
	end
end

function PlayerDataManager.RemovePlayer(player)
	-- §PERSIST1: force save on player leaving (teleport-out, disconnect,
	-- kick). This MUST NOT be skipped by the auto-save dedup or the
	-- player loses XP / progression earned since the last successful save.
	-- §AGX/X3: release=true — this save hands the session lock back (the
	-- teleport destination is waiting on it) and retries with backoff
	-- before we drop the in-memory copy below.
	-- §AGX/X3r7: on shutdown BindToClose's release usually got here first;
	-- SavePlayer skips this one if a release is in flight or done for the key.
	PlayerDataManager.SavePlayer(player, true, true)
	playerDataStore[player] = nil

	-- §T0-FOLLOWUP/L3: clear the in-flight setup flag in case the player
	-- left while LoadRawData was still yielding. Without this the boolean
	-- stays true forever, holding a strong ref to the Player object.
	setupInProgress[player] = nil

	-- §T0-FOLLOWUP/L2: tear down the per-player Janitor (CharacterAdded
	-- conn for HP-on-spawn, and any future per-player conns we add).
	local jan = playerJanitors[player]
	if jan then
		jan:Destroy()
		playerJanitors[player] = nil
	end
end

--- Permanently delete all saved data for a player from the DataStore and from
--- the in-memory store.  Call this for admin "full wipe" testing only.
--- Returns (true) on success or (false, errorMessage) on DataStore failure.
--- The caller is responsible for kicking the player afterwards so they rejoin
--- with clean default data.
function PlayerDataManager.WipeData(player)
	local key = tostring(player.UserId)

	-- §T0P2/X17: tombstone the key BEFORE removing. SavePlayer checks
	-- wipedPlayers right before SetAsync, so an in-flight or future save
	-- can't resurrect the wiped data. (The old `savingPlayers[key] = nil`
	-- couldn't actually cancel anything — it only confused the
	-- force-save wait of concurrent savers.)
	wipedPlayers[key] = true

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
-- §AGX/X3: `release` marks the player's final save (PlayerRemoving /
-- BindToClose): it clears the session lock in the same UpdateAsync and
-- retries FINAL_SAVE_RETRIES times with backoff. Other saves refresh
-- the lock's timestamp (auto-save is the lock heartbeat).
local function WriteRecord(key, data, release, gen)
	local abortReason = nil
	local ok, err = pcall(function()
		LOCAL_DATASTORE:UpdateAsync(key, function(old)
			abortReason = nil  -- transform can run more than once; reset per call
			if gen ~= nil and sessionGen[key] ~= gen then
				abortReason = "stale session"
				return nil
			end
			-- §T0P2/X17: re-check the tombstone at write time too.
			if wipedPlayers[key] then
				abortReason = "wiped"
				return nil
			end
			-- §AGX/X3r8: releasedPlayers keeps this guard after a successful
			-- release clears releasingPlayers.
			if not release and (releasingPlayers[key] or releasedPlayers[key]) then
				abortReason = "lock already released"
				return nil
			end
			-- Never overwrite a record another live server owns — its
			-- copy is newer than ours (it loaded after we lost the lock).
			if type(old) == "table" and IsForeignLiveLock(old._session) then
				abortReason = "locked by job " .. tostring(old._session.jobId)
				return nil
			end
			-- Shallow copy so `_session` never lands in the in-memory data.
			local record = table.clone(data)
			record._session = if release then nil else NewSessionLock()
			return record
		end)
	end)
	if not ok then return "error", err end
	if abortReason then return "aborted", abortReason end
	return "ok"
end

local function SavePlayerImpl(player, force, release)
	-- §AGX/X3r12: capture the session generation before any yield.
	local gen = player and sessionGen[tostring(player.UserId)]
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

	-- §AGX/X3: from here on no plain save may re-take the lock.
	if release then
		releasingPlayers[key] = true
	elseif shuttingDown then
		return  -- §AGX/X2: shutdown saves are release saves only
	end

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

	-- §T0P2/X17: never write a key an admin has wiped this session —
	-- the player must rejoin (rejoin clears the tombstone in SetupPlayer).
	if wipedPlayers[key] then
		warn("[PlayerDataManager] Skipping save for wiped key", key, "(", player.Name, ")")
		return
	end

	savingPlayers[key] = true

	-- §AGX/X3: UpdateAsync + session lock (was a blind SetAsync). The
	-- final save retries with backoff; an "aborted" result is never
	-- retried — another server owns the record, or the key was wiped.
	local attempts = if release then 1 + FINAL_SAVE_RETRIES else 1
	local backoff = 1
	local status, detail
	for attempt = 1, attempts do
		status, detail = WriteRecord(key, data, release, gen)
		if status ~= "error" then break end
		if attempt < attempts then
			warn("[PlayerDataManager] Save error for", player.Name, "(attempt "
				.. attempt .. "/" .. attempts .. "):", detail, "— retrying")
			task.wait(backoff)
			backoff *= 2
		end
	end

	savingPlayers[key] = nil

	if status == "error" then
		warn("[PlayerDataManager] Failed to save data for", player.Name, ":", detail)
	elseif status == "aborted" then
		warn("[PlayerDataManager] Save skipped for", player.Name, "—", detail)
	else
		-- §AGX/X3r8: release landed — drop the in-progress marker;
		-- releasedPlayers keeps plain saves out and dedups a 2nd release (r7).
		if release then
			releasingPlayers[key] = nil
			releasedPlayers[key] = true
		end
		print("[PlayerDataManager] Saved data for", player.Name,
			release and "(final)" or (force and "(force)" or ""))
	end
	return status  -- §AGX/X3r3: HeartbeatSave retries on "error"
end

-- §AGX/X2: every save goes through this counted wrapper so BindToClose
-- can wait for leave-saves already in flight. pcall guarantees the
-- decrement even if the save body throws.
-- §AGX/X3r3: returns SavePlayerImpl's status ("ok"/"aborted"/"error",
-- nil when skipped) so the heartbeat can retry a failed write.
function PlayerDataManager.SavePlayer(player, force, release)
	-- §AGX/X3r1: mark the release in flight before SavePlayerImpl's
	-- force-wait (same effect as setting it at its top — nothing yields in
	-- between) so the wrapper that set it is the one that clears it.
	local releaseKey = nil
	if release and player then
		releaseKey = tostring(player.UserId)
		-- §AGX/X3r7: one release per key per session — BindToClose and
		-- PlayerRemoving both release on shutdown; skip the second.
		if releaseInFlight[releaseKey] or releasedPlayers[releaseKey] then
			return nil
		end
		releaseInFlight[releaseKey] = true
	end
	-- §AGX/X27: fold session play time into the snapshot (sync, no yield).
	PlayerDataManager.AccruePlayTime(player)
	pendingSaves += 1
	local ok, result = pcall(SavePlayerImpl, player, force, release)
	pendingSaves -= 1
	if releaseKey then
		releaseInFlight[releaseKey] = nil  -- §AGX/X3r1: cleared after the pcall, always
	end
	if not ok then
		warn("[PlayerDataManager] SavePlayer errored for", tostring(player and player.Name), ":", result)
		return "error"
	end
	return result
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

-- §T0P2/X22: no callers today — KEPT deliberately as the seam for the
-- planned single-point deallocation feature (undo a misclicked point
-- without paying for a full respec). Wire a remote + UI before using;
-- when that lands, decide whether single-point deallocs cost anything.
function PlayerDataManager.DeallocateStat(player, statName, points)
	return StatSystem.DeallocateStat(player, statName, points)
end

function PlayerDataManager.ResetAllocation(player, className)
	return StatSystem.ResetAllocation(player, className)
end

function PlayerDataManager.GetTotalStat(player, statName)
	return StatSystem.GetTotalStat(player, statName)
end

-- §T0P2/X22: forward freshSpawn — the old passthrough silently dropped
-- the third argument, so any caller asking for a fresh-spawn full heal
-- would have gotten the mid-life proportional rescale instead.
function PlayerDataManager.ApplyHealthToCharacter(player, character, freshSpawn)
	return StatSystem.ApplyHealthToCharacter(player, character, freshSpawn)
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

-- §AGX/X22: XP HUD pushes are coalesced (SCALING_AUDIT §SCALE/S5 pattern).
-- Every kill used to fire one PlayerInfoUpdate per recipient (≤ 5 party
-- members), so a 15-kill Horde burst was up to 75 sends in one frame.
-- Now AddExperience only marks the player dirty; one flush per
-- XP_PUSH_WINDOW sends the LATEST level/xp once per dirty player. The
-- payload is a snapshot, so dropping the intermediate ones loses nothing.
local XP_PUSH_WINDOW = 0.25
local xpPushDirty = {}  -- [player] = true
local xpPushScheduled = false

local function flushXPPushes()
	xpPushScheduled = false
	local net = getNetworkManager()
	for player in pairs(xpPushDirty) do
		xpPushDirty[player] = nil
		local account = player.Parent and PlayerDataManager.GetAccountData(player)
		if net and account then
			net.FireClient(player, "PlayerInfoUpdate", {
				level    = account.Level,
				xp       = account.Experience,
				xpNeeded = Config.GetXPForLevel(account.Level),
			})
		end
	end
end

-- Level System
function PlayerDataManager.AddExperience(player, amount)
	LevelSystem.AddExperience(player, amount)

	-- Push updated XP / level to the player's HUD (batched — §AGX/X22).
	-- This central notification covers ALL XP sources: kill rewards, wave bonuses,
	-- admin commands, etc. — so every caller gets the HUD update for free.
	if not player then return end
	xpPushDirty[player] = true
	if not xpPushScheduled then
		xpPushScheduled = true
		task.delay(XP_PUSH_WINDOW, flushXPPushes)
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