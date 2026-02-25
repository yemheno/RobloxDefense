-- StarterPlayerScripts/Modules/DamageNumbers

local DamageNumbers = {}

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

local player = Players.LocalPlayer

-- ── Layout constants ──────────────────────────────────────
local FLOAT_HEIGHT  = 4
local FLOAT_TIME    = 1.0
local FADE_TIME     = 0.5
local MAX_DISTANCE  = 500

-- ── Element colours ───────────────────────────────────────
-- The number's TEXT COLOUR reflects the element of the attack.
-- Crit feedback is expressed via SIZE and '!' marks, not colour.
local ELEMENT_COLOR = {
	None  = Color3.fromRGB(255, 255, 255),   -- Physical / untyped  → white
	Wood  = Color3.fromRGB( 80, 215,  80),   -- Wood                → green
	Earth = Color3.fromRGB(210, 165,  70),   -- Earth               → sandy gold
	Water = Color3.fromRGB( 85, 185, 255),   -- Water               → sky blue
	Fire  = Color3.fromRGB(255,  90,  40),   -- Fire                → orange-red
}
local OTHER_PLAYER_BASE = Color3.fromRGB(200, 200, 200)  -- Other players: desaturated

-- Stroke tint: slightly darkened version of the face colour
local STROKE_DARKEN = 0.4   -- multiply RGB by this

local function ElementColor(element, isOwn)
	if not isOwn then return OTHER_PLAYER_BASE end
	return ELEMENT_COLOR[element] or ELEMENT_COLOR.None
end

local function StrokeColor(faceColor)
	return Color3.new(
		faceColor.R * STROKE_DARKEN,
		faceColor.G * STROKE_DARKEN,
		faceColor.B * STROKE_DARKEN
	)
end

-- ── Billboard sizing ──────────────────────────────────────
-- Normal: 100×50  ·  Crit: 120×60  ·  Multi-crit: 150×75
local SIZE = {
	normal     = UDim2.new(0, 100, 0, 50),
	crit       = UDim2.new(0, 120, 0, 60),
	multiCrit  = UDim2.new(0, 150, 0, 75),
	other      = UDim2.new(0, 80,  0, 40),
}

function DamageNumbers.Init()
	NetworkManager.OnServerEvent("DamageNumber", function(data)
		DamageNumbers.ShowDamageNumber(data)
	end)
	print("[DamageNumbers] Initialized")
end

function DamageNumbers.ShowDamageNumber(data)
	local position   = data.position
	local damage     = data.damage
	local wasCrit    = data.wasCrit
	local critProcs  = data.critProcs or 0
	local isOwn      = (data.attackerName == player.Name)
	local element    = data.attackElement or "None"

	-- ── Anchor part ───────────────────────────────────────
	local anchor = Instance.new("Part")
	anchor.Name        = "DmgAnchor"
	anchor.Anchored    = true
	anchor.CanCollide  = false
	anchor.Transparency = 1
	anchor.Size        = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position    = position
	anchor.Parent      = workspace

	-- ── Billboard ─────────────────────────────────────────
	local billboard = Instance.new("BillboardGui")
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.Adornee     = anchor
	billboard.Parent      = anchor

	-- ── Determine style ───────────────────────────────────
	local suffix = ""
	local bbSize

	if not isOwn then
		bbSize = SIZE.other
		if wasCrit then suffix = "!" end
	elseif wasCrit and critProcs >= 2 then
		bbSize = SIZE.multiCrit
		suffix = "!!"
	elseif wasCrit then
		bbSize = SIZE.crit
		suffix = "!"
	else
		bbSize = SIZE.normal
	end

	billboard.Size = bbSize

	-- ── Text label ────────────────────────────────────────
	local face   = ElementColor(element, isOwn)
	local stroke = StrokeColor(face)

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font                  = Enum.Font.GothamBold
	label.TextScaled            = true
	label.TextColor3            = face
	label.TextStrokeColor3      = stroke
	label.TextStrokeTransparency = 0
	label.Text                  = tostring(math.floor(damage)) .. suffix
	label.Parent                = billboard

	-- ── Animation ─────────────────────────────────────────
	local floatTween = TweenService:Create(
		anchor,
		TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = position + Vector3.new(0, FLOAT_HEIGHT, 0) }
	)
	local fadeTween = TweenService:Create(
		label,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Linear),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)

	floatTween:Play()
	task.delay(FLOAT_TIME - FADE_TIME, function()
		fadeTween:Play()
	end)
	task.delay(FLOAT_TIME + 0.1, function()
		anchor:Destroy()
	end)
end

return DamageNumbers