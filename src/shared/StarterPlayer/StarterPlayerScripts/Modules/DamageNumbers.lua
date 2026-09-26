-- StarterPlayerScripts/Modules/DamageNumbers
--[[
    DamageNumbers v2  (§PERF/F6 — pooled, capped, single-stepper)
    ==============================================================
    v1 created a Part + BillboardGui + TextLabel + 2 Tweens + 2 task.delay
    closures PER NUMBER and destroyed them after. In world-boss-scale
    fights that instance churn is what makes players turn numbers off.

    v2 keeps the exact same visuals + public API but bounds the cost:
      • POOL      — attachment/billboard/label trios are reused forever
      • STEPPER   — ONE RenderStepped drives every active number
                    (easeOutQuad float + linear tail fade, identical to
                    the old Quad/Out + Linear tweens); connected only
                    while numbers are on screen
      • HARD CAP  — at MAX_ACTIVE the oldest number is recycled, so a
                    world boss with 8 players spamming AoE costs the
                    same frame budget as a training dummy
      • CULL      — numbers beyond MAX_DISTANCE from the camera are
                    skipped entirely (previously still paid creation)

    Server-side §PERF/F5 already merges same-mob hits into 0.1 s windows,
    so the two layers together give: bounded events AND bounded rendering.
]]

local DamageNumbers = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

local player = Players.LocalPlayer

-- ── Layout constants ──────────────────────────────────────
local FLOAT_HEIGHT  = 4
local FLOAT_TIME    = 1.0
local FADE_TIME     = 0.5
local MAX_DISTANCE  = 500

-- §PERF/F6: hard ceilings on simultaneously animating numbers — SPLIT
-- budgets (Pablo): your own numbers and allies' numbers are tracked
-- separately, so a 7-ally AoE storm can never crowd out your own hits.
local MAX_ACTIVE_OWN  = 30
local MAX_ACTIVE_ALLY = 20

-- §PERF/F6b: allies' numbers start exactly this much later than yours,
-- so the two streams alternate visually instead of stacking.
local ALLY_STAGGER = 0.05

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

-- Heal-specific constants
local HEAL_FLOAT_HEIGHT = 3.5
local HEAL_FLOAT_TIME   = 0.9
local HEAL_DRIFT_X      = 1.5   -- slight sideways arc

local HOT_FLOAT_HEIGHT  = 2.0
local HOT_FLOAT_TIME    = 0.7
local HOT_SIDE_OFFSET   = 2.0

-- ═══════════════════════════════════════════════════════════
-- §PERF/F6: POOL + STEPPER
-- ═══════════════════════════════════════════════════════════

local rootPart = nil          -- single invisible anchored holder
local pool = {}               -- idle units
local activeOwn = {}          -- your numbers (FIFO — [1] is oldest)
local activeAlly = {}         -- allies' numbers (FIFO)
local stepperConn = nil

local function getRoot()
	if rootPart and rootPart.Parent then return rootPart end
	rootPart = Instance.new("Part")
	rootPart.Name = "DamageNumbersRoot"
	rootPart.Anchored = true
	rootPart.CanCollide = false
	rootPart.CanQuery = false
	rootPart.CanTouch = false
	rootPart.Transparency = 1
	rootPart.Size = Vector3.new(0.1, 0.1, 0.1)
	rootPart.Position = Vector3.new(0, -500, 0)
	rootPart.Parent = workspace
	return rootPart
end

local function makeUnit()
	local attachment = Instance.new("Attachment")
	attachment.Parent = getRoot()

	local billboard = Instance.new("BillboardGui")
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Adornee = attachment
	billboard.Enabled = false
	billboard.Parent = attachment

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Parent = billboard

	return { attachment = attachment, billboard = billboard, label = label }
end

local function releaseEntry(entry)
	entry.unit.billboard.Enabled = false
	table.insert(pool, entry.unit)
end

local function easeOutQuad(p)
	local inv = 1 - p
	return 1 - inv * inv
end

local function stepList(list, dt)
	for i = #list, 1, -1 do
		local e = list[i]

		-- §PERF/F6b: stagger — number stays hidden until its delay elapses.
		if e.delay > 0 then
			e.delay -= dt
			if e.delay <= 0 then
				e.unit.billboard.Enabled = true
			else
				continue
			end
		end

		e.t += dt
		if e.t >= e.floatTime then
			releaseEntry(e)
			table.remove(list, i)
		else
			local p = easeOutQuad(e.t / e.floatTime)
			e.unit.attachment.WorldPosition = e.startPos:Lerp(e.endPos, p)

			-- linear fade over the last FADE_TIME seconds
			local fadeStart = e.floatTime - FADE_TIME
			if e.t > fadeStart then
				local f = (e.t - fadeStart) / FADE_TIME
				e.unit.label.TextTransparency = f
				e.unit.label.TextStrokeTransparency =
					e.strokeBase + (1 - e.strokeBase) * f
			end
		end
	end
end

local function step(dt)
	stepList(activeOwn, dt)
	stepList(activeAlly, dt)

	if #activeOwn == 0 and #activeAlly == 0 and stepperConn then
		stepperConn:Disconnect()
		stepperConn = nil
	end
end

--- Spawn one pooled number. params:
---   position, endPos, floatTime, text, face, size (UDim2),
---   font (Enum.Font), strokeBase (0 crisp / 0.3 soft), studsOffsetY,
---   own (bool — picks the budget + ally stagger)
local function spawnNumber(params)
	-- Distance cull: beyond billboard visibility nothing would render —
	-- don't pay for it at all.
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - params.position).Magnitude > MAX_DISTANCE then
		return
	end

	local list, cap
	if params.own then
		list, cap = activeOwn, MAX_ACTIVE_OWN
	else
		list, cap = activeAlly, MAX_ACTIVE_ALLY
	end

	local unit
	if #list >= cap then
		-- Recycle the OLDEST number of the SAME stream (own numbers are
		-- never stolen by ally spam, and vice versa).
		local oldest = table.remove(list, 1)
		unit = oldest.unit
	else
		unit = table.remove(pool) or makeUnit()
	end

	local label = unit.label
	label.Font = params.font
	label.Text = params.text
	label.TextColor3 = params.face
	label.TextStrokeColor3 = StrokeColor(params.face)
	label.TextTransparency = 0
	label.TextStrokeTransparency = params.strokeBase

	unit.billboard.Size = params.size
	unit.billboard.StudsOffset = Vector3.new(0, params.studsOffsetY, 0)
	unit.attachment.WorldPosition = params.position

	-- §PERF/F6b: own numbers show instantly; ally numbers hold hidden
	-- for exactly ALLY_STAGGER so the streams alternate.
	local delay = params.own and 0 or ALLY_STAGGER
	unit.billboard.Enabled = (delay == 0)

	table.insert(list, {
		unit = unit,
		t = 0,
		delay = delay,
		floatTime = params.floatTime,
		startPos = params.position,
		endPos = params.endPos,
		strokeBase = params.strokeBase,
	})

	if not stepperConn then
		stepperConn = RunService.RenderStepped:Connect(step)
	end
end

-- ═══════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════

function DamageNumbers.Init()
	NetworkManager.OnServerEvent("DamageNumber", function(data)
		DamageNumbers.ShowDamageNumber(data)
	end)
	-- §PERF/F5: Tibia-style server batching — one event, N merged numbers
	-- (0.1 s window; same-mob-same-attacker hits arrive pre-summed with a
	-- `hits` count). The single-number event above stays for DoT ticks.
	NetworkManager.OnServerEvent("DamageNumberBatch", function(batch)
		for _, data in ipairs(batch) do
			DamageNumbers.ShowDamageNumber(data)
		end
	end)
	-- §AGX/SEC (§T0P2-ORPHANS): the single "HealNumber" event was never
	-- fired server-side (heals go through HealNumberBatch); listener removed.
	-- §SCALE/S5: batched DoT/HoT/heal windows from SkillEffects.
	NetworkManager.OnServerEvent("HealNumberBatch", function(batch)
		for _, data in ipairs(batch) do
			DamageNumbers.ShowHealNumber(data)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- DAMAGE NUMBERS
-- ═══════════════════════════════════════════════════════════

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
		local sideDir = (math.random() > 0.5) and 1 or -1
		local offsetX = sideDir * (DOT_SIDE_OFFSET + math.random() * 1.0)
		local offsetZ = (math.random() - 0.5) * 1.5
		local dotPos  = position + Vector3.new(offsetX, 0.5, offsetZ)

		spawnNumber({
			own          = isOwn,
			position     = dotPos,
			endPos       = dotPos + Vector3.new(0, DOT_FLOAT_HEIGHT, 0),
			floatTime    = DOT_FLOAT_TIME,
			text         = tostring(math.floor(damage)),
			face         = ElementColor(element, isOwn),
			size         = SIZE.dot,
			font         = Enum.Font.Gotham,  -- lighter font for DoT
			strokeBase   = 0.3,
			studsOffsetY = 1,
		})
		return
	end

	-- ── Normal damage numbers (non-DoT) ───────────────────
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

	-- §PERF/F5: merged windows show the summed damage with a hit count.
	local hitsSuffix = (data.hits and data.hits > 1) and (" x" .. data.hits) or ""

	spawnNumber({
		own          = isOwn,
		position     = position,
		endPos       = position + Vector3.new(0, FLOAT_HEIGHT, 0),
		floatTime    = FLOAT_TIME,
		text         = tostring(math.floor(damage)) .. suffix .. hitsSuffix,
		face         = ElementColor(element, isOwn),
		size         = bbSize,
		font         = Enum.Font.GothamBold,
		strokeBase   = 0,
		studsOffsetY = 2,
	})
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

		spawnNumber({
			own          = isOwn,
			position     = hotPos,
			endPos       = hotPos + Vector3.new(0, HOT_FLOAT_HEIGHT, 0),
			floatTime    = HOT_FLOAT_TIME,
			text         = "+" .. tostring(math.floor(amount)),
			face         = isOwn and HEAL_COLOR or HEAL_OTHER_COLOR,
			size         = SIZE.hot,
			font         = Enum.Font.Gotham,
			strokeBase   = 0.3,
			studsOffsetY = 1,
		})
		return
	end

	-- ── Normal heal numbers ───────────────────────────────
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

	-- Animation: arced float (up + slight drift)
	local driftDir = (math.random() > 0.5) and 1 or -1
	local endPos = position + Vector3.new(driftDir * HEAL_DRIFT_X, HEAL_FLOAT_HEIGHT, 0)

	spawnNumber({
		own          = isOwn,
		position     = position,
		endPos       = endPos,
		floatTime    = HEAL_FLOAT_TIME,
		text         = "+" .. tostring(math.floor(amount)) .. suffix,
		face         = face,
		size         = bbSize,
		font         = Enum.Font.GothamBold,
		strokeBase   = 0,
		studsOffsetY = 2,
	})
end

return DamageNumbers
