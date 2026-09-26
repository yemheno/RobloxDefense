-- StarterPlayerScripts/Modules/LootNotification
--[[
    Combo-style loot accumulator.

    Instead of spawning a floating number per kill, this module keeps a
    persistent counter on screen that ADDS to the running total every
    time a LootDrop arrives.  The counter has a lifetime: after no new
    drops for DISPLAY_TIMEOUT seconds the counter fades out and resets.

    Every time the total increases the label "pulses" (scales up then
    back) to give tactile feedback.

    §AGX/UI-P4: rendering moved onto Notify's feed (UI/Common/Notify.lua).
    This module used to own a ScreenGui (DisplayOrder 5, IgnoreGuiInset,
    bottom-right at 0.82 scale, i.e. under the phone SkillPad) plus its own
    tween/timer bookkeeping. It now only keeps the running totals; one
    feed line per currency (key "loot:<type>") is updated in place, and
    the feed does the pulse, the 4 s lifetime and the fade. Public API
    (Init / OnLootDrop) is unchanged for the place client loaders.
]]

local LootNotification = {}

local Players = game:GetService("Players")

local Modules        = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- §AGX/UI-P4: Notify lives in PlayerScripts/UI/Common (lazy: the UI folder
-- is replicated with PlayerScripts, but keep module load non-blocking).
local Notify = nil
local function getNotify()
	if not Notify then
		local ok, mod = pcall(function()
			return require(Players.LocalPlayer:WaitForChild("PlayerScripts")
				:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("Notify"))
		end)
		if ok then Notify = mod else warn("[LootNotification] Notify unavailable:", mod) end
	end
	return Notify
end

-- ── Config ────────────────────────────────────────────────
local DISPLAY_TIMEOUT = 4          -- seconds of silence before the counter fades

local TYPE_CONFIG = {
	Merits  = { icon = "[M]", color = Color3.fromRGB(255, 210, 60) },
	Essence = { icon = "[E]", color = Color3.fromRGB(140, 100, 255) },
}
local DEFAULT_CFG = { icon = "[+]", color = Color3.fromRGB(255, 255, 255) }

-- ── Per-type running totals ───────────────────────────────
-- §AGX/UI-P4: [typeName] = { total, lastAt } (was label/frame/tween state)
local trackers = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function LootNotification.Init()
	-- §AGX/UI-P4: no ScreenGui any more; Notify.Host renders the feed.
	NetworkManager.OnServerEvent("LootDrop", function(data)
		LootNotification.OnLootDrop(data)
	end)
end

-- ═══════════════════════════════════════════════════════════
-- ACCUMULATE
-- ═══════════════════════════════════════════════════════════

local function AddToTracker(typeName, amount)
	local now = os.clock()
	local tracker = trackers[typeName]
	-- §AGX/UI-P4: same reset rule as before: a counter that has been
	-- silent for DISPLAY_TIMEOUT has faded out, so it starts from 0.
	if not tracker or (now - tracker.lastAt) >= DISPLAY_TIMEOUT then
		tracker = { total = 0, lastAt = now }
		trackers[typeName] = tracker
	end
	tracker.total  = tracker.total + (tonumber(amount) or 0)
	tracker.lastAt = now

	local cfg = TYPE_CONFIG[typeName] or DEFAULT_CFG
	local notify = getNotify()
	if notify then
		notify.feed(cfg.icon .. " +" .. tostring(tracker.total) .. " " .. tostring(typeName), {
			key      = "loot:" .. tostring(typeName),
			color    = cfg.color,
			duration = DISPLAY_TIMEOUT,
		})
	end
end

-- ═══════════════════════════════════════════════════════════
-- EVENT HANDLER
-- ═══════════════════════════════════════════════════════════

function LootNotification.OnLootDrop(data)
	local drops = data.drops
	if not drops then return end

	for _, drop in ipairs(drops) do
		AddToTracker(drop.type, drop.amount)
	end
end

return LootNotification
