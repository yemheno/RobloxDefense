-- ServerScriptService/Modules/MonitoringSystem

local MonitoringSystem = {}

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

--[[
    ═══════════════════════════════════════════════════════════
    MONITORING SYSTEM
    ═══════════════════════════════════════════════════════════
    
    Tracks suspicious activity without affecting gameplay.
    Logs events for manual review.
    
    NOT anti-cheat - just monitoring for awareness.
    Player experience is NEVER affected by this system.
    
    ═══════════════════════════════════════════════════════════
]]

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

local CONFIG = {
	-- Enable/disable monitoring
	Enabled = true,

	-- Log to output
	LogToOutput = true,

	-- Store in-memory (for review commands)
	StoreInMemory = true,
	MaxStoredEvents = 1000,

	-- Thresholds (for flagging, NOT blocking)
	Thresholds = {
		-- Dodge rate above this % gets flagged
		SuspiciousDodgeRate = 95,

		-- Hits reported from further than skill range + this buffer
		DistanceBuffer = 10,

		-- Time window for hit reports (seconds after skill cast)
		MaxHitReportDelay = 3.0,

		-- Minimum hits to evaluate dodge rate
		MinHitsForEvaluation = 20,
	},
}

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local playerStats = {}  -- { [player] = { hits, dodges, flags, ... } }
local eventLog = {}     -- Recent events for review
local flaggedPlayers = {} -- Players with suspicious patterns

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function MonitoringSystem.Init()
	if not CONFIG.Enabled then
		print("[MonitoringSystem] Disabled")
		return
	end

	-- Clean up when players leave
	-- §MEM/M2, §MEM/M1: drop per-player stats on leave (keeping them would
	-- pin the Player and its pendingHits for the server's lifetime). Flagged
	-- players' reports are snapshotted into the capped eventLog for review.
	Players.PlayerRemoving:Connect(function(player)
		local stats = playerStats[player]
		if stats then
			stats.leftAt = os.time()
			if flaggedPlayers[player] then
				MonitoringSystem.LogEvent(player, "FlaggedPlayerLeft",
					MonitoringSystem.GetPlayerReport(player))
			end
		end
		playerStats[player] = nil
		flaggedPlayers[player] = nil
	end)

	-- §SCALE/S4: amortized pending-hit sweep (replaces per-hit task.delay
	-- closures). 1 s cadence — half the report window, ample resolution
	-- for dodge accounting.
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(MonitoringSystem._SweepPendingHits)
			if not ok then
				warn("[MonitoringSystem] Sweep errored:", err)
			end
		end
	end)

end

-- ═══════════════════════════════════════════════════════════
-- PLAYER STATS TRACKING
-- ═══════════════════════════════════════════════════════════

local function GetPlayerStats(player)
	if not playerStats[player] then
		playerStats[player] = {
			-- Hit tracking
			totalSkillsTargeted = 0,  -- Times player was in skill range
			totalHitsReported = 0,    -- Times player reported being hit
			totalDodges = 0,          -- Times player dodged (no report)

			-- Suspicious events
			lateHitReports = 0,       -- Hits reported after time window
			distantHitReports = 0,    -- Hits reported from far away
			impossibleDodges = 0,     -- Dodged when shouldn't be possible

			-- Buff tracking
			buffsReceived = 0,
			buffsOutOfRange = 0,      -- Received buff when out of range

			-- Flags
			flags = {},
			flagCount = 0,

			-- Session info
			joinedAt = os.time(),
			leftAt = nil,
		}
	end
	return playerStats[player]
end

-- ═══════════════════════════════════════════════════════════
-- SKILL HIT TRACKING
-- ═══════════════════════════════════════════════════════════

--[[
    Called when server broadcasts a skill that COULD hit a player.
    
    Parameters:
    - player: Player who was in range
    - skillData: { skillId, mobId, origin, range, timestamp }
]]
-- §SCALE/S4: monitoring cost is (mob casts/s) × (players in range), so it
-- uses monotonic integer ids, no per-hit closure (one amortized sweep in
-- Init resolves dodges), and a sampling dial for extreme scenarios.
local hitIdCounter = 0

-- 1 = record every potential hit (current behavior). Raise to N to record
-- 1-in-N when a mode is expected to enroll 20+ players per cast — dodge
-- RATES stay statistically valid since both numerator and denominator
-- sample together (this is monitoring, not anti-cheat — §CONFIG note).
local SAMPLE_RATE = 1

function MonitoringSystem.RecordPotentialHit(player, skillData)
	if not CONFIG.Enabled then return end

	local stats = GetPlayerStats(player)

	if SAMPLE_RATE > 1 then
		hitIdCounter = hitIdCounter + 1
		if hitIdCounter % SAMPLE_RATE ~= 0 then return end
	end

	-- Counted only for SAMPLED hits so dodge-rate math stays unbiased.
	stats.totalSkillsTargeted = stats.totalSkillsTargeted + 1

	-- Store pending hit for validation
	if not stats.pendingHits then
		stats.pendingHits = {}
	end

	hitIdCounter = hitIdCounter + 1
	local hitId = hitIdCounter
	stats.pendingHits[hitId] = {
		skillId = skillData.skillId,
		mobId = skillData.mobId,
		origin = skillData.origin,
		range = skillData.range,
		timestamp = skillData.timestamp or os.clock(),
		resolved = false,
	}

	return hitId
end

-- §SCALE/S4 + §MEM/M1: single amortized sweep replaces the per-hit
-- task.delay. Entries past the report window resolve as dodges (if
-- unreported) and are deleted either way.
function MonitoringSystem._SweepPendingHits()
	local cutoff = os.clock() - (CONFIG.Thresholds.MaxHitReportDelay + 0.5)
	for player, stats in pairs(playerStats) do
		local pendingTable = stats.pendingHits
		if pendingTable then
			for hitId, pending in pairs(pendingTable) do
				if pending.timestamp <= cutoff then
					if not pending.resolved then
						stats.totalDodges = stats.totalDodges + 1
						MonitoringSystem.CheckDodgeRate(player)
					end
					pendingTable[hitId] = nil
				end
			end
		end
	end
end

--[[
    Called when client reports being hit by a skill.
    
    Parameters:
    - player: Player reporting the hit
    - hitData: { skillId, hitId (optional), position, timestamp }
]]
function MonitoringSystem.RecordHitReport(player, hitData)
	if not CONFIG.Enabled then return end

	local stats = GetPlayerStats(player)
	stats.totalHitsReported = stats.totalHitsReported + 1

	-- Try to match with pending hit
	local matched = false
	if stats.pendingHits then
		for hitId, pending in pairs(stats.pendingHits) do
			if not pending.resolved and pending.skillId == hitData.skillId then
				pending.resolved = true
				matched = true

				-- Check timing
				local delay = os.clock() - pending.timestamp
				if delay > CONFIG.Thresholds.MaxHitReportDelay then
					stats.lateHitReports = stats.lateHitReports + 1
					MonitoringSystem.LogEvent(player, "LateHitReport", {
						skillId = hitData.skillId,
						delay = delay,
					})
				end

				-- Check distance (if position provided)
				if hitData.position and pending.origin then
					local distance = (hitData.position - pending.origin).Magnitude
					local maxRange = pending.range + CONFIG.Thresholds.DistanceBuffer
					if distance > maxRange then
						stats.distantHitReports = stats.distantHitReports + 1
						MonitoringSystem.LogEvent(player, "DistantHitReport", {
							skillId = hitData.skillId,
							distance = distance,
							maxExpected = maxRange,
						})
					end
				end

				break
			end
		end
	end

	if not matched then
		-- Hit report without matching pending hit
		MonitoringSystem.LogEvent(player, "UnmatchedHitReport", {
			skillId = hitData.skillId,
		})
	end
end

-- ═══════════════════════════════════════════════════════════
-- BUFF TRACKING
-- ═══════════════════════════════════════════════════════════

--[[
    Called when a buff is applied to a player.
    
    Parameters:
    - player: Player receiving buff
    - buffData: { buffId, casterId, casterPosition, playerPosition, range }
]]
function MonitoringSystem.RecordBuffReceived(player, buffData)
	if not CONFIG.Enabled then return end

	local stats = GetPlayerStats(player)
	stats.buffsReceived = stats.buffsReceived + 1

	-- Check if player was actually in range
	if buffData.casterPosition and buffData.playerPosition and buffData.range then
		local distance = (buffData.playerPosition - buffData.casterPosition).Magnitude
		if distance > buffData.range + CONFIG.Thresholds.DistanceBuffer then
			stats.buffsOutOfRange = stats.buffsOutOfRange + 1
			MonitoringSystem.LogEvent(player, "BuffOutOfRange", {
				buffId = buffData.buffId,
				casterId = buffData.casterId,
				distance = distance,
				maxRange = buffData.range,
			})
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- DODGE RATE ANALYSIS
-- ═══════════════════════════════════════════════════════════

function MonitoringSystem.CheckDodgeRate(player)
	local stats = GetPlayerStats(player)

	-- Need minimum hits to evaluate
	if stats.totalSkillsTargeted < CONFIG.Thresholds.MinHitsForEvaluation then
		return
	end

	local dodgeRate = (stats.totalDodges / stats.totalSkillsTargeted) * 100

	if dodgeRate >= CONFIG.Thresholds.SuspiciousDodgeRate then
		if not flaggedPlayers[player] or not flaggedPlayers[player].highDodgeRate then
			flaggedPlayers[player] = flaggedPlayers[player] or {}
			flaggedPlayers[player].highDodgeRate = true

			MonitoringSystem.FlagPlayer(player, "HighDodgeRate", {
				dodgeRate = dodgeRate,
				totalTargeted = stats.totalSkillsTargeted,
				totalDodged = stats.totalDodges,
			})
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- EVENT LOGGING
-- ═══════════════════════════════════════════════════════════

function MonitoringSystem.LogEvent(player, eventType, data)
	if not CONFIG.Enabled then return end

	local event = {
		timestamp = os.time(),
		tickTime = os.clock(),
		player = player.Name,
		playerId = player.UserId,
		eventType = eventType,
		data = data,
	}

	-- Log to output
	if CONFIG.LogToOutput then
		local dataStr = ""
		if data then
			for k, v in pairs(data) do
				dataStr = dataStr .. k .. "=" .. tostring(v) .. " "
			end
		end
		print("[Monitor]", player.Name, eventType, dataStr)
	end

	-- Store in memory
	if CONFIG.StoreInMemory then
		table.insert(eventLog, event)

		-- Trim old events
		while #eventLog > CONFIG.MaxStoredEvents do
			table.remove(eventLog, 1)
		end
	end
end

function MonitoringSystem.FlagPlayer(player, flagType, data)
	local stats = GetPlayerStats(player)
	stats.flagCount = stats.flagCount + 1

	local flag = {
		type = flagType,
		timestamp = os.time(),
		data = data,
	}
	table.insert(stats.flags, flag)

	-- Log with warning level
	warn("[Monitor] FLAG:", player.Name, flagType)
	if data then
		for k, v in pairs(data) do
			warn("  ", k .. ":", tostring(v))
		end
	end

	flaggedPlayers[player] = flaggedPlayers[player] or {}
	flaggedPlayers[player][flagType] = true
end

-- ═══════════════════════════════════════════════════════════
-- ADMIN/DEBUG COMMANDS
-- ═══════════════════════════════════════════════════════════

function MonitoringSystem.GetPlayerReport(player)
	local stats = playerStats[player]
	if not stats then
		return { error = "No data for player" }
	end

	local dodgeRate = 0
	if stats.totalSkillsTargeted > 0 then
		dodgeRate = (stats.totalDodges / stats.totalSkillsTargeted) * 100
	end

	return {
		player = player.Name,
		userId = player.UserId,

		-- Hit stats
		skillsTargeted = stats.totalSkillsTargeted,
		hitsReported = stats.totalHitsReported,
		dodges = stats.totalDodges,
		dodgeRate = string.format("%.1f%%", dodgeRate),

		-- Suspicious events
		lateHits = stats.lateHitReports,
		distantHits = stats.distantHitReports,
		impossibleDodges = stats.impossibleDodges,

		-- Buffs
		buffsReceived = stats.buffsReceived,
		buffsOutOfRange = stats.buffsOutOfRange,

		-- Flags
		flagCount = stats.flagCount,
		flags = stats.flags,

		-- Session
		sessionDuration = os.time() - stats.joinedAt,
	}
end

function MonitoringSystem.GetAllFlaggedPlayers()
	local flagged = {}
	for player, flags in pairs(flaggedPlayers) do
		local report = MonitoringSystem.GetPlayerReport(player)
		if report and not report.error then
			table.insert(flagged, report)
		end
	end
	return flagged
end

function MonitoringSystem.GetRecentEvents(count)
	count = count or 50
	local recent = {}
	local startIdx = math.max(1, #eventLog - count + 1)
	for i = startIdx, #eventLog do
		table.insert(recent, eventLog[i])
	end
	return recent
end

function MonitoringSystem.GetStats()
	local totalPlayers = 0
	local totalFlagged = 0
	local totalEvents = #eventLog

	for _ in pairs(playerStats) do
		totalPlayers = totalPlayers + 1
	end
	for _ in pairs(flaggedPlayers) do
		totalFlagged = totalFlagged + 1
	end

	return {
		playersTracked = totalPlayers,
		playersFlagged = totalFlagged,
		eventsLogged = totalEvents,
		enabled = CONFIG.Enabled,
	}
end

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

function MonitoringSystem.SetEnabled(enabled)
	CONFIG.Enabled = enabled
	print("[MonitoringSystem] Enabled:", enabled)
end

function MonitoringSystem.SetLogToOutput(enabled)
	CONFIG.LogToOutput = enabled
end

function MonitoringSystem.GetConfig()
	return CONFIG
end

return MonitoringSystem