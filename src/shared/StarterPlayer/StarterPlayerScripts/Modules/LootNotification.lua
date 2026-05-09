-- StarterPlayerScripts/Modules/LootNotification
--[[
    Combo-style loot accumulator.

    Instead of spawning a floating number per kill, this module keeps a
    persistent counter on screen that ADDS to the running total every
    time a LootDrop arrives.  The counter has a lifetime: after no new
    drops for DISPLAY_TIMEOUT seconds the counter fades out and resets.

    Every time the total increases the label "pulses" (scales up then
    back) to give tactile feedback.
]]

local LootNotification = {}

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Modules        = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

local LocalPlayer = Players.LocalPlayer

-- ── Config ────────────────────────────────────────────────
local DISPLAY_TIMEOUT = 4          -- seconds of silence before the counter fades
local FADE_OUT_TIME   = 0.5        -- fade-out tween duration
local PULSE_SCALE     = 1.25       -- scale multiplier on pulse
local PULSE_TIME      = 0.12       -- time to grow
local PULSE_RETURN    = 0.15       -- time to shrink back

local TYPE_CONFIG = {
	Merits  = { icon = "[M]", color = Color3.fromRGB(255, 210, 60) },
	Essence = { icon = "[E]", color = Color3.fromRGB(140, 100, 255) },
}
local DEFAULT_CFG = { icon = "[+]", color = Color3.fromRGB(255, 255, 255) }

-- ── Per-type runtime state ────────────────────────────────
--  [typeName] = { total, label, frame, hideHandle, pulseHandle }
local trackers = {}

-- ── GUI root ──────────────────────────────────────────────
local screenGui = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function LootNotification.Init()
	-- Create ScreenGui once
	screenGui = Instance.new("ScreenGui")
	screenGui.Name            = "LootNotificationGui"
	screenGui.ResetOnSpawn    = false
	screenGui.IgnoreGuiInset  = true
	screenGui.DisplayOrder    = 5
	screenGui.Parent          = LocalPlayer:WaitForChild("PlayerGui")

	NetworkManager.OnServerEvent("LootDrop", function(data)
		LootNotification.OnLootDrop(data)
	end)

	print("[LootNotification] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- CREATE / GET TRACKER FOR A DROP TYPE
-- ═══════════════════════════════════════════════════════════

local function GetSlotIndex(typeName)
	-- Merits always slot 0, Essence slot 1, others appended
	if typeName == "Merits"  then return 0 end
	if typeName == "Essence" then return 1 end
	-- count existing non-standard
	local n = 2
	for k, _ in pairs(trackers) do
		if k ~= "Merits" and k ~= "Essence" then n = n + 1 end
	end
	return n
end

local function CreateTracker(typeName)
	local cfg   = TYPE_CONFIG[typeName] or DEFAULT_CFG
	local slot  = GetSlotIndex(typeName)
	local yPos  = 0.82 - slot * 0.06   -- stack upward from bottom-right

	-- Outer frame (anchored right)
	local frame = Instance.new("Frame")
	frame.Name                   = "Loot_" .. typeName
	frame.AnchorPoint            = Vector2.new(1, 0.5)
	frame.Position               = UDim2.fromScale(0.985, yPos)
	frame.Size                   = UDim2.fromScale(0.14, 0.045)
	frame.BackgroundColor3       = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel        = 0
	frame.Parent                 = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent       = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color        = cfg.color
	stroke.Thickness    = 1.5
	stroke.Transparency = 0
	stroke.Parent       = frame

	-- Label
	local label = Instance.new("TextLabel")
	label.Name                   = "Amount"
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text                   = cfg.icon .. " +0 " .. typeName
	label.TextColor3             = cfg.color
	label.Font                   = Enum.Font.GothamBold
	label.TextScaled             = true
	label.TextStrokeTransparency = 0.35
	label.TextStrokeColor3       = Color3.new(0, 0, 0)
	label.Parent                 = frame

	-- UIScale for the pulse effect (we tween this)
	local uiScale = Instance.new("UIScale")
	uiScale.Scale  = 1
	uiScale.Parent = frame

	local tracker = {
		total       = 0,
		label       = label,
		frame       = frame,
		uiScale     = uiScale,
		cfg         = cfg,
		typeName    = typeName,
		hideHandle  = nil,
		pulseReturn = nil,
	}

	trackers[typeName] = tracker
	return tracker
end

-- ═══════════════════════════════════════════════════════════
-- ACCUMULATE + PULSE
-- ═══════════════════════════════════════════════════════════

local function PulseTracker(tracker)
	-- Cancel any in-flight return tween
	if tracker.pulseReturn then
		tracker.pulseReturn:Cancel()
		tracker.pulseReturn = nil
	end

	-- Grow
	local grow = TweenService:Create(tracker.uiScale,
		TweenInfo.new(PULSE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = PULSE_SCALE })
	grow:Play()

	-- Shrink back after grow completes
	grow.Completed:Connect(function()
		local shrink = TweenService:Create(tracker.uiScale,
			TweenInfo.new(PULSE_RETURN, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ Scale = 1 })
		shrink:Play()
		tracker.pulseReturn = shrink
	end)
end

local function ShowTracker(tracker)
	tracker.frame.Visible = true
	tracker.frame.BackgroundTransparency = 0.3
	tracker.label.TextTransparency       = 0
	tracker.label.TextStrokeTransparency = 0.35
end

local function HideTracker(tracker)
	-- Fade out then reset
	local fadeBg = TweenService:Create(tracker.frame,
		TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = 1 })
	local fadeTxt = TweenService:Create(tracker.label,
		TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Linear),
		{ TextTransparency = 1, TextStrokeTransparency = 1 })

	fadeBg:Play()
	fadeTxt:Play()

	fadeTxt.Completed:Connect(function()
		tracker.total          = 0
		tracker.frame.Visible  = false
		tracker.uiScale.Scale  = 1
	end)
end

local function AddToTracker(tracker, amount)
	tracker.total = tracker.total + amount
	tracker.label.Text = tracker.cfg.icon .. " +" .. tostring(tracker.total) .. " " .. tracker.typeName

	ShowTracker(tracker)
	PulseTracker(tracker)

	-- Reset the hide timer
	if tracker.hideHandle then
		task.cancel(tracker.hideHandle)
	end
	tracker.hideHandle = task.delay(DISPLAY_TIMEOUT, function()
		HideTracker(tracker)
		tracker.hideHandle = nil
	end)
end

-- ═══════════════════════════════════════════════════════════
-- EVENT HANDLER
-- ═══════════════════════════════════════════════════════════

function LootNotification.OnLootDrop(data)
	local drops = data.drops
	if not drops then return end

	for _, drop in ipairs(drops) do
		local tracker = trackers[drop.type] or CreateTracker(drop.type)
		AddToTracker(tracker, drop.amount)
	end
end

return LootNotification
