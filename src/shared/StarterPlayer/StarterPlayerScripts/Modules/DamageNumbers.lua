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

-- ── Healing colours ──────────────────────────────────────
local HEAL_COLOR        = Color3.fromRGB(100, 255, 100)   -- Bright green
local HEAL_CRIT_COLOR   = Color3.fromRGB(180, 255, 130)   -- Lime flash for crit
local HEAL_OTHER_COLOR  = Color3.fromRGB(130, 210, 130)   -- Other player heals

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
-- Normal: 100×50  ·  Crit: 120×60  ·  Multi-crit: 150×75  ·  DoT: 70×35
local SIZE = {
	normal     = UDim2.new(0, 100, 0, 50),
	crit       = UDim2.new(0, 120, 0, 60),
	multiCrit  = UDim2.new(0, 150, 0, 75),
	other      = UDim2.new(0, 80,  0, 40),
	dot        = UDim2.new(0, 70,  0, 35),
	-- Healing
	heal       = UDim2.new(0, 100, 0, 50),
	healCrit   = UDim2.new(0, 120, 0, 60),
	healOther  = UDim2.new(0, 80,  0, 40),
	hot        = UDim2.new(0, 70,  0, 35),
}

-- DoT-specific constants
local DOT_FLOAT_HEIGHT = 2.5        -- shorter float
local DOT_FLOAT_TIME   = 0.75       -- faster
local DOT_SIDE_OFFSET  = 2.5        -- studs to the side

function DamageNumbers.Init()
	NetworkManager.OnServerEvent("DamageNumber", function(data)
		DamageNumbers.ShowDamageNumber(data)
	end)
	NetworkManager.OnServerEvent("HealNumber", function(data)
		DamageNumbers.ShowHealNumber(data)
	end)
end

function DamageNumbers.ShowDamageNumber(data)
	local position   = data.position
	local damage     = data.damage
	local wasCrit    = data.wasCrit
	local critProcs  = data.critProcs or 0
	local isOwn      = (data.attackerUserId == player.UserId)
	local element    = data.attackElement or "None"
	local isDoT      = data.isDoT or false

	-- ── DoT numbers: small, offset to the side ───────────
	if isDoT then
		-- Random side offset so consecutive ticks don't overlap
		local sideDir = (math.random() > 0.5) and 1 or -1
		local offsetX = sideDir * (DOT_SIDE_OFFSET + math.random() * 1.0)
		local offsetZ = (math.random() - 0.5) * 1.5
		local dotPos  = position + Vector3.new(offsetX, 0.5, offsetZ)

		local anchor = Instance.new("Part")
		anchor.Name        = "DotAnchor"
		anchor.Anchored    = true
		anchor.CanCollide  = false
		anchor.Transparency = 1
		anchor.Size        = Vector3.new(0.1, 0.1, 0.1)
		anchor.Position    = dotPos
		anchor.Parent      = workspace

		local billboard = Instance.new("BillboardGui")
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = MAX_DISTANCE
		billboard.StudsOffset = Vector3.new(0, 1, 0)
		billboard.Size        = SIZE.dot
		billboard.Adornee     = anchor
		billboard.Parent      = anchor

		local face   = ElementColor(element, isOwn)
		local stroke = StrokeColor(face)

		local label = Instance.new("TextLabel")
		label.Size                  = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font                  = Enum.Font.Gotham  -- lighter font for DoT
		label.TextScaled            = true
		label.TextColor3            = face
		label.TextStrokeColor3      = stroke
		label.TextStrokeTransparency = 0.3
		label.Text                  = tostring(math.floor(damage))
		label.Parent                = billboard

		local floatTween = TweenService:Create(
			anchor,
			TweenInfo.new(DOT_FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = dotPos + Vector3.new(0, DOT_FLOAT_HEIGHT, 0) }
		)
		local fadeTween = TweenService:Create(
			label,
			TweenInfo.new(FADE_TIME, Enum.EasingStyle.Linear),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)

		floatTween:Play()
		task.delay(DOT_FLOAT_TIME - FADE_TIME, function()
			fadeTween:Play()
		end)
		task.delay(DOT_FLOAT_TIME + 0.1, function()
			anchor:Destroy()
		end)
		return
	end

	-- ── Normal damage numbers (non-DoT) ───────────────────

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

-- ═══════════════════════════════════════════════════════════
-- HEAL NUMBERS
-- ═══════════════════════════════════════════════════════════
-- Heal numbers are visually distinct from damage:
--   • Bright green colour (vs element-coded damage)
--   • "+" prefix (+352 vs 352)
--   • Arced float path (up + slight backward drift)
--   • HoT ticks: small, side-offset (mirrors DoT pattern)
-- Numbers appear above the HEALED player (vs above the mob).

local HEAL_FLOAT_HEIGHT = 3.5
local HEAL_FLOAT_TIME   = 0.9
local HEAL_DRIFT_X      = 1.5   -- slight sideways arc

local HOT_FLOAT_HEIGHT  = 2.0
local HOT_FLOAT_TIME    = 0.7
local HOT_SIDE_OFFSET   = 2.0

function DamageNumbers.ShowHealNumber(data)
	local position  = data.position
	local amount    = data.amount
	local wasCrit   = data.wasCrit
	local critProcs = data.critProcs or 0
	local isOwn     = (data.healerUserId == player.UserId)
	local isHoT     = data.isHoT or false

	-- ── HoT ticks: small, offset to the side ─────────────
	if isHoT then
		local sideDir = (math.random() > 0.5) and 1 or -1
		local offsetX = sideDir * (HOT_SIDE_OFFSET + math.random() * 0.8)
		local offsetZ = (math.random() - 0.5) * 1.2
		local hotPos  = position + Vector3.new(offsetX, 0.5, offsetZ)

		local anchor = Instance.new("Part")
		anchor.Name        = "HoTAnchor"
		anchor.Anchored    = true
		anchor.CanCollide  = false
		anchor.Transparency = 1
		anchor.Size        = Vector3.new(0.1, 0.1, 0.1)
		anchor.Position    = hotPos
		anchor.Parent      = workspace

		local billboard = Instance.new("BillboardGui")
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = MAX_DISTANCE
		billboard.StudsOffset = Vector3.new(0, 1, 0)
		billboard.Size        = SIZE.hot
		billboard.Adornee     = anchor
		billboard.Parent      = anchor

		local face   = isOwn and HEAL_COLOR or HEAL_OTHER_COLOR
		local stroke = StrokeColor(face)

		local label = Instance.new("TextLabel")
		label.Size                  = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font                  = Enum.Font.Gotham
		label.TextScaled            = true
		label.TextColor3            = face
		label.TextStrokeColor3      = stroke
		label.TextStrokeTransparency = 0.3
		label.Text                  = "+" .. tostring(math.floor(amount))
		label.Parent                = billboard

		local floatTween = TweenService:Create(
			anchor,
			TweenInfo.new(HOT_FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = hotPos + Vector3.new(0, HOT_FLOAT_HEIGHT, 0) }
		)
		local fadeTween = TweenService:Create(
			label,
			TweenInfo.new(FADE_TIME, Enum.EasingStyle.Linear),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)

		floatTween:Play()
		task.delay(HOT_FLOAT_TIME - FADE_TIME, function()
			fadeTween:Play()
		end)
		task.delay(HOT_FLOAT_TIME + 0.1, function()
			anchor:Destroy()
		end)
		return
	end

	-- ── Normal heal numbers ───────────────────────────────

	local anchor = Instance.new("Part")
	anchor.Name        = "HealAnchor"
	anchor.Anchored    = true
	anchor.CanCollide  = false
	anchor.Transparency = 1
	anchor.Size        = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position    = position
	anchor.Parent      = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.Adornee     = anchor
	billboard.Parent      = anchor

	-- Style
	local suffix = ""
	local bbSize
	local face

	if not isOwn then
		bbSize = SIZE.healOther
		face   = HEAL_OTHER_COLOR
		if wasCrit then suffix = "!" end
	elseif wasCrit and critProcs >= 2 then
		bbSize = SIZE.healCrit
		face   = HEAL_CRIT_COLOR
		suffix = "!!"
	elseif wasCrit then
		bbSize = SIZE.healCrit
		face   = HEAL_CRIT_COLOR
		suffix = "!"
	else
		bbSize = SIZE.heal
		face   = HEAL_COLOR
	end

	billboard.Size = bbSize
	local stroke = StrokeColor(face)

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font                  = Enum.Font.GothamBold
	label.TextScaled            = true
	label.TextColor3            = face
	label.TextStrokeColor3      = stroke
	label.TextStrokeTransparency = 0
	label.Text                  = "+" .. tostring(math.floor(amount)) .. suffix
	label.Parent                = billboard

	-- Animation: arced float (up + slight drift)
	local driftDir = (math.random() > 0.5) and 1 or -1
	local endPos = position + Vector3.new(driftDir * HEAL_DRIFT_X, HEAL_FLOAT_HEIGHT, 0)

	local floatTween = TweenService:Create(
		anchor,
		TweenInfo.new(HEAL_FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = endPos }
	)
	local fadeTween = TweenService:Create(
		label,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Linear),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)

	floatTween:Play()
	task.delay(HEAL_FLOAT_TIME - FADE_TIME, function()
		fadeTween:Play()
	end)
	task.delay(HEAL_FLOAT_TIME + 0.1, function()
		anchor:Destroy()
	end)
end

return DamageNumbers