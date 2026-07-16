-- ReplicatedStorage/Shared/BootProfiler
--[[
    BootProfiler  (§PERF/BP — boot timing + race detection)
    ========================================================
    Lightweight timeline profiler for the boot path. Works on BOTH sides:
    the server (PlaceBootstrap/PlaceLifecycle/PlayerDataManager hooks) and
    the client (the five place bootstraps' Load helpers).

    API:
        BootProfiler.SetContext("HordeMode")     -- once, names the report
        BootProfiler.Mark("ServerReady fired")   -- point event
        local done = BootProfiler.Begin("require PlayerDataManager")
        ...                                       -- timed span
        done()
        BootProfiler.Dump()                       -- manual re-dump (optional)

    The report dumps AUTOMATICALLY ~5 s after the last recorded activity
    (debounced), so after a Studio run the full timeline is waiting in:

      1. the Output window — single block, easy to copy/paste
         (Studio also writes Output to disk: %LOCALAPPDATA%\Roblox\logs)
      2. a StringValue snapshot, refreshed on every dump:
           server → ServerStorage.BootProfile_SERVER
           client → LocalPlayer.PlayerGui.BootProfile_CLIENT
         (select it in the Explorer during play, copy Value from Properties)

    Flags in the report:
      ⚠ SLOW        span took ≥ 100 ms
      ⚠ UNFINISHED  Begin() whose done() never ran — a hang or a missed
                    code path (prime race-condition evidence)
      ⚠ gap N.NNs   ≥ 350 ms of silence between consecutive activity —
                    something was waiting without telling us

    Zero-cost kill switch: set ENABLED = false for release builds.
]]

local RunService = game:GetService("RunService")

local BootProfiler = {}

local ENABLED          = true
local SLOW_THRESHOLD   = 0.100  -- s
local GAP_THRESHOLD    = 0.350  -- s
local QUIET_DUMP_DELAY = 5      -- s of inactivity before auto-dump

local IS_SERVER = RunService:IsServer()
local SIDE      = IS_SERVER and "SERVER" or "CLIENT"

local t0        = os.clock()
local entries   = {}            -- { t, label, dur? } (dur = -1 while open)
local context   = "?"
local dumpGen   = 0
local dumpCount = 0

local function now()
	return os.clock() - t0
end

--============================================
-- AUTO-DUMP DEBOUNCE
--============================================
local function scheduleDump()
	dumpGen += 1
	local myGen = dumpGen
	task.delay(QUIET_DUMP_DELAY, function()
		if myGen == dumpGen then
			BootProfiler.Dump()
		end
	end)
end

--============================================
-- RECORDING
--============================================
function BootProfiler.SetContext(name)
	context = tostring(name)
end

function BootProfiler.Mark(label)
	if not ENABLED then return end
	table.insert(entries, { t = now(), label = tostring(label) })
	scheduleDump()
end

--- Returns a closer. Call it when the span ends; a span that is never
--- closed shows up as ⚠ UNFINISHED in the report.
function BootProfiler.Begin(label)
	if not ENABLED then
		return function() end
	end
	local entry = { t = now(), label = tostring(label), dur = -1 }
	table.insert(entries, entry)
	scheduleDump()
	return function()
		if entry.dur < 0 then
			entry.dur = now() - entry.t
		end
		scheduleDump()
	end
end

--============================================
-- REPORT
--============================================
local function buildReport()
	local sorted = table.clone(entries)
	table.sort(sorted, function(a, b) return a.t < b.t end)

	local lines = {}
	local slowCount, openCount = 0, 0

	table.insert(lines, string.format(
		"════ BootProfile · %s · %s · dump #%d · %d entries ════",
		SIDE, context, dumpCount, #sorted))

	local prevEnd = 0
	for _, e in ipairs(sorted) do
		-- silence gap since the previous activity ended
		local gap = e.t - prevEnd
		if gap >= GAP_THRESHOLD and prevEnd > 0 then
			table.insert(lines, string.format(
				"         │            ⚠ gap %.2fs of silence", gap))
		end

		local durStr, flag = "", ""
		if e.dur then
			if e.dur < 0 then
				durStr = "   ...  "
				flag = "  ⚠ UNFINISHED"
				openCount += 1
			else
				durStr = string.format("%7.1fms", e.dur * 1000)
				if e.dur >= SLOW_THRESHOLD then
					flag = "  ⚠ SLOW"
					slowCount += 1
				end
			end
		end
		table.insert(lines, string.format(
			"%8.3f │ %-48s %s%s", e.t, e.label, durStr, flag))

		prevEnd = math.max(prevEnd, e.t + math.max(e.dur or 0, 0))
	end

	table.insert(lines, string.format(
		"════ total %.3fs · %d slow · %d unfinished ════",
		prevEnd, slowCount, openCount))

	return table.concat(lines, "\n")
end

local function writeSnapshot(report)
	local ok, err = pcall(function()
		local parent
		local name = "BootProfile_" .. SIDE
		if IS_SERVER then
			parent = game:GetService("ServerStorage")
		else
			local player = game:GetService("Players").LocalPlayer
			parent = player and player:FindFirstChildOfClass("PlayerGui")
		end
		if not parent then return end

		local sv = parent:FindFirstChild(name)
		if not sv then
			sv = Instance.new("StringValue")
			sv.Name = name
			sv.Parent = parent
		end
		sv.Value = report
	end)
	if not ok then
		warn("[BootProfiler] snapshot write failed:", err)
	end
end

function BootProfiler.Dump()
	if not ENABLED or #entries == 0 then return end
	dumpCount += 1
	local report = buildReport()
	print("\n" .. report)
	writeSnapshot(report)
end

return BootProfiler
