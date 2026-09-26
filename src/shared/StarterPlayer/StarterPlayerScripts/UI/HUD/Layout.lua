-- UI/HUD/Layout.lua
--[[
    §AGX/UI-P5: HUD regions — the layout table (shell-spec §4.2), the rail
    band / collapse rule (§4.4) and the attribute contract (§4.3).

    UNITS (D2, UIScaleRoot rules)
      Every rect below is DESIGN px (phone points). The HUD renders its
      regions inside a UIScaleRoot.Local, so the UIScale multiplies them
      once. W/H are the HUD root's measured AbsoluteSize converted with
      UIScaleRoot.toLocal (screen px / uiScale). Spacing comes from
      ff.design (edge / gap), so Theme v2's per-kind values win over the
      spec's rounded screen numbers (Tablet 18/9 x 1.15 ~ 20/10).
      Attributes are published in SCREEN px (design x uiScale) relative to
      the safe-area origin, and read back divided by uiScale.

    API
      Layout.compute(args) -> L          pure; see the `args` fields below
      Layout.useHudLayout(place, ff, hudMode, dyn) -> L
                                         compute + publish the §4.3 attributes
      Layout.useAttrs() -> { [ATTR] = number? }  live read of the inputs
      Layout.padFootprint(pad, attack, skill, dash) -> { top, left, dashTop }?
                                         SkillPad footprint from its tokens
                                         (units of whatever table you pass)
      Layout.ATTR                        attribute names
      Layout.rect(...)                   rect helper (see below)

    RECT = { anchorPoint, position, size (UDim2), x, y, w, h } — x/y is the
    top-left corner in design px, for the maths; position keeps the spec's
    Scale+Offset form so a stale W/H never misplaces an edge-anchored region.

    L (per render)
      kind, place, hudMode, E, G, S, W, H, scale
      show      = { vitals, defense, party, topCentre, rail, currencies,
                    play, quick, combo, classBadge }
      vitals, vitalsVariant ("full"|"chip"), defense, party, classBadge,
      currencies, menu, rail, railCollapsed, band, bossSlot, bossReserved,
      run (Start/Countdown/Next/Return slot), runReturnIdleY, corridor,
      combo, defCombo, play, emote, wardrobe
      publish   = { [ATTR] = screen px | nil }; publishReserve = HUD owns
                  UI_TopCentreReservedPx (slotted boss)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Theme = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("Theme"))

local Layout = {}

-- ── §4.3 attribute names ─────────────────────────────────────────────────────
local ATTR = {
	topRightBottom    = "UI_TopRightBottomPx",
	topCentreReserved = "UI_TopCentreReservedPx",
	topCentreButtons  = "UI_TopCentreButtonsBottomPx",
	leftColumnRight   = "UI_LeftColumnRightPx",     -- §AGX/UI-P5 new
	rightRailLeft     = "UI_RightRailLeftPx",       -- §AGX/UI-P5 new
	skillPadTop       = "UI_SkillPadTopPx",         -- §AGX/UI-P5 new (SkillPad)
	skillPadLeft      = "UI_SkillPadLeftPx",        -- §AGX/UI-P5 new (SkillPad)
	actionBarTop      = "UI_ActionBarTopPx",        -- §AGX/UI-P5 new (ActionBar)
	hudMode           = "UI_HudMode",               -- §AGX/UI-P5 new (PanelStack, string)
	-- legacy: published while legacyNav / a standalone TeammateVitals exist (retired in W3)
	topLeftBottom     = "UI_TopLeftBottomPx",
	topLeftX          = "UI_TopLeftXPx",
	navToggleTop      = "UI_NavToggleTopPx",        -- published by HUD/LegacyNav
}
Layout.ATTR = ATTR

-- The attributes the layout READS (published by siblings).
local INPUT_ATTRS = {
	ATTR.topCentreReserved, ATTR.skillPadTop, ATTR.skillPadLeft, ATTR.actionBarTop,
}

-- The attributes the layout WRITES (cleared on unmount).
local OUTPUT_ATTRS = {
	ATTR.topRightBottom, ATTR.leftColumnRight, ATTR.rightRailLeft,
	ATTR.topLeftBottom, ATTR.topLeftX,
}

local TOP_GAP = 10                        -- S = topbar + 10 (HUD.lua:280, Notify)
local DEFAULT_RAIL = { cell = 44, gap = 8, pad = 6 }
local BADGE_SCALE = Vector2.new(0.13, 0.07)  -- BattleClassUI badge (scale-sized, A's file)
local LEGACY_BADGE_DY = 40                   -- BattleClassUI default y = safeTop + 40 (screen px)
local RUN_MIN_HALF = 60                      -- half the narrowest run button (120)
local MIN_VITALS_W = 160

local V2 = Vector2.new

-- ── §4.2 sizes per form factor (design px) ───────────────────────────────────
local SIZES = {
	Phone = {
		vitalsFull = V2(220, 72), vitalsChip = V2(220, 40), currency = V2(240, 40),
		defenseH = 24, defenseGap = 6,
		run = V2(200, 48), runSize = "md",
		bossH = 46, bossReserve = 54,
		combo = V2(160, 44), defCombo = V2(220, 28),
		party = { w = 200, row = 28, gap = 4 },
		menuButton = 48,
		lobbyReserveBR = 166,   -- jump + PLAY on a touch phone (§4.4)
		play     = { w = 140, h = 56, pos = UDim2.new(1, -20, 1, -110) },
		emote    = { w = 56,  h = 56, pos = UDim2.new(1, -194, 1, -24) },
		plazaEmote    = { w = 64, h = 64, pos = UDim2.new(1, -110, 1, -24) },
		plazaWardrobe = { w = 56, h = 56, pos = UDim2.new(1, -20, 1, -110) },
	},
	Tablet = {
		vitalsFull = V2(220, 72), vitalsChip = V2(220, 40), currency = V2(240, 40),
		defenseH = 24, defenseGap = 6,
		run = V2(200, 48), runSize = "md",
		bossH = 46, bossReserve = 54,
		combo = V2(160, 44), defCombo = V2(220, 28),
		party = { w = 200, row = 28, gap = 4 },
		menuButton = 48,
		lobbyReserveBR = 175,
		play     = { w = 140, h = 56, pos = UDim2.new(1, -190, 1, -24) },
		emote    = { w = 56,  h = 56, pos = UDim2.new(1, -338, 1, -24) },
		plazaEmote    = { w = 64, h = 64, pos = UDim2.new(1, -110, 1, -24) },
		plazaWardrobe = { w = 56, h = 56, pos = UDim2.new(1, -20, 1, -110) },
	},
	Desktop = {
		vitalsFull = V2(360, 96), vitalsChip = V2(300, 48), currency = V2(300, 40),
		defenseH = 24, defenseGap = 6,
		run = V2(240, 48), runSize = "md",
		bossH = 46, bossReserve = 54,
		combo = V2(200, 48), defCombo = V2(220, 28),
		party = { w = 240, row = 38, gap = 4 },
		menuButton = 48,
		play = { w = 200, h = 56 },   -- (1,-E,1,-E)
	},
	Console = {
		vitalsFull = V2(420, 112), vitalsChip = V2(360, 56), currency = V2(300, 48),
		defenseH = 28, defenseGap = 8,
		-- Spec: 280x64. Button tops out at "lg" = 56 design (84 px at 1.5).
		run = V2(280, 56), runSize = "lg",
		bossH = 56, bossReserve = 64,
		combo = V2(200, 48), defCombo = V2(220, 28),
		party = { w = 240, row = 48, gap = 4 },
		menuButton = 64,
		play = { w = 240, h = 64 },   -- (1,-E,1,-E)
	},
}
Layout.SIZES = SIZES

--- Rect from an anchor point + Scale/Offset position + size (design px).
local function rect(apX, apY, sx, ox, sy, oy, w, h, W, H)
	local px = sx * W + ox
	local py = sy * H + oy
	return {
		anchorPoint = Vector2.new(apX, apY),
		position    = UDim2.new(sx, ox, sy, oy),
		size        = UDim2.fromOffset(w, h),
		x = px - apX * w, y = py - apY * h, w = w, h = h,
	}
end
Layout.rect = rect

local function rectFromUDim(apX, apY, pos, w, h, W, H)
	return rect(apX, apY, pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset, w, h, W, H)
end

--- SkillPad footprint, measured from the safe area's bottom / right edges,
--- in the units of the table passed (ff.design -> design px, ff.tokens ->
--- screen px). Mirrors SkillPad's own placement: a button centre sits at
--- (anchor - offset) from the bottom-right corner.
function Layout.padFootprint(pad, attack, skill, dash)
	if type(pad) ~= "table" or typeof(pad.anchor) ~= "Vector2" then return nil end
	local ax, ay = pad.anchor.X, pad.anchor.Y
	local r = pad.arcRadius or 0
	attack, skill, dash = attack or 0, skill or 0, dash or 0
	local top  = ay + attack / 2
	local left = ax + attack / 2
	for _, deg in ipairs(pad.arcAngles or {}) do
		local rad = math.rad(deg)
		top  = math.max(top,  ay - r * math.sin(rad) + skill / 2)
		left = math.max(left, ax - r * math.cos(rad) + skill / 2)
	end
	local dashTop = nil
	if typeof(pad.dashOffset) == "Vector2" then
		dashTop = ay - pad.dashOffset.Y + dash / 2
		top  = math.max(top, dashTop)
		left = math.max(left, ax - pad.dashOffset.X + dash / 2)
	end
	return { top = top, left = left, dashTop = dashTop }
end

local function railConfig(kind)
	local k = Theme.Layout[kind]
	local r = (type(k) == "table" and type(k.rail) == "table") and k.rail or {}
	return {
		cell       = r.cell or DEFAULT_RAIL.cell,
		gap        = r.gap or DEFAULT_RAIL.gap,
		pad        = r.pad or DEFAULT_RAIL.pad,
		collapsed  = r.collapsed == true,
		menuButton = r.menuButton,
	}
end

--[[ args:
      place            "Combat" | "Lobby" | "Plaza"
      ff               useFormFactor() snapshot
      hudMode          "full" | "combatSide" | "none"
      W, H             HUD root size, design px
      scale            uiScale (design -> screen)
      attrs            Layout.useAttrs() (screen px)
      legacyNav        bool   (today's ☰ + ⋮ drawer is rendered)
      legacyMenu       Vector2? design size of the legacy ☰ (Lobby onMenuClick)
      hasRail          bool   (props.railSlot given)
      railCount        number? groups in the rail (default 6)
      classBadge       true | false | nil (nil = the App mounts BattleClassUI itself)
      legacyTopbar     GetGuiInset().Y (what BattleClassUI uses for its own spot)
      hasTopCentreSlot bool
      bossActive       bool   (slotted boss bar is showing)
      defense          bool   (defense line known)
      partyInHud       bool
]]
function Layout.compute(args)
	local ff = args.ff
	local kind = ff.kind or "Phone"
	local d = ff.design or Theme.Layout[kind] or {}
	local sz = SIZES[kind] or SIZES.Phone
	local s = args.scale or ff.uiScale or 1
	local W, H = args.W, args.H
	local E, G = d.edge or 16, d.gap or 8
	local S = (ff.topbar or 0) / s + TOP_GAP
	local place = args.place or "Combat"
	local combat = place == "Combat"
	local isTouch = ff.isTouch == true
	local mode = args.hudMode or "full"
	local full = mode == "full"
	local core = full or mode == "combatSide"
	local attrs = args.attrs or {}
	local function fromPx(v) return (type(v) == "number") and (v / s) or nil end

	local L = {
		kind = kind, place = place, hudMode = mode,
		E = E, G = G, S = S, W = W, H = H, scale = s,
	}

	-- ── Rail / menu button (§4.4) ────────────────────────────────────────
	local rc = railConfig(kind)
	local n = args.railCount or 6
	local railH = n * rc.cell + (n - 1) * rc.gap + 2 * rc.pad   -- 6 -> 316
	local railW = rc.cell + 2 * rc.pad                           -- 56
	local mb = rc.menuButton or sz.menuButton
	local hasRail = args.hasRail == true

	-- Currencies: D13 hides them on phone combat, but only once the
	-- MenuSheet (railSlot) exists to show them instead.
	local currencyAvail = not (kind == "Phone" and combat and hasRail)
	local cur = sz.currency

	-- Band with the rail EXPANDED (no menu button in the top-right row).
	local expandedRowH = math.max(currencyAvail and cur.Y or 0,
		args.legacyMenu and args.legacyMenu.Y or 0)
	local reserveBR = 0
	if isTouch and combat then
		local fromAttr = fromPx(attrs[ATTR.skillPadTop])
		if fromAttr then
			reserveBR = fromAttr
		else
			-- SkillPad hidden (UI context / down): use its token footprint so
			-- the rail doesn't flip to expanded while a panel is open.
			local fp = Layout.padFootprint(d.skillPad, d.attack, d.skill, d.dash)
			reserveBR = fp and fp.top or 0
		end
	elseif isTouch then
		reserveBR = sz.lobbyReserveBR or 0
	elseif place == "Lobby" then
		reserveBR = E + (sz.play and sz.play.h or 56)
	end
	local bandTop = S + expandedRowH + G + G
	local bandBottom = H - reserveBR - G
	local collapsed = kind == "Phone" or kind == "Console" or rc.collapsed
		or (bandBottom - bandTop) < railH
	L.band = { top = bandTop, bottom = bandBottom, height = bandBottom - bandTop, needed = railH }
	L.railCollapsed = collapsed

	-- ── Top-right row ────────────────────────────────────────────────────
	local rightReserve, rowH = 0, 0
	L.menu = rect(1, 0, 1, -E, 0, S, mb, mb, W, H)
	if hasRail and collapsed then
		rightReserve, rowH = mb + G, mb
	elseif args.legacyMenu then
		rightReserve, rowH = args.legacyMenu.X + G, args.legacyMenu.Y
	end
	L.currencies = rect(1, 0, 1, -(E + rightReserve), 0, S, cur.X, cur.Y, W, H)
	if currencyAvail then rowH = math.max(rowH, cur.Y) end
	local trBottom = S + rowH + G
	L.topRightBottom = trBottom

	if hasRail then
		if collapsed then
			L.rail = L.menu
		else
			local bandMid = (bandTop + bandBottom) / 2
			L.rail = rect(1, 0.5, 1, -E, 0, bandMid, railW, railH, W, H)
		end
	end

	-- ── Left column ──────────────────────────────────────────────────────
	-- classBadge == nil: the App still mounts BattleClassUI itself at
	-- (safeLeft, safeTop + 40) with 0.13W x 0.07H, so keep clear of it.
	local legacyBadge = combat and args.classBadge == nil
	local badge = nil
	if combat and args.classBadge == true and not isTouch then
		badge = rect(0, 0, 0, E, 0, S, BADGE_SCALE.X * W, BADGE_SCALE.Y * H, W, H)
	elseif legacyBadge then
		local y = ((args.legacyTopbar or ff.topbar or 0) + TOP_GAP + LEGACY_BADGE_DY) / s
		badge = rect(0, 0, 0, 0, 0, y, BADGE_SCALE.X * W, BADGE_SCALE.Y * H, W, H)
	end
	L.classBadge = (args.classBadge == true) and badge or nil

	local leftX = E
	if legacyBadge and isTouch then
		leftX = math.max(E, BADGE_SCALE.X * W + G)   -- was 0.14W + 8 (HUD.lua:346)
	end

	local variant = combat and "full" or "chip"
	local vs = combat and sz.vitalsFull or sz.vitalsChip
	if isTouch and combat then
		-- Keep a corridor for a 120-wide run button (the Wave-1 badge shift
		-- pushes the stack right; HUD.lua:347 capped the width the same way).
		local maxW = W / 2 - RUN_MIN_HALF - G - leftX
		if maxW < vs.X then vs = V2(math.max(MIN_VITALS_W, maxW), vs.Y) end
	end
	L.vitalsVariant = variant
	local defH, defGap = sz.defenseH, sz.defenseGap
	local hasDefense = combat and args.defense == true
	local defExtra = hasDefense and (defGap + defH) or 0

	if isTouch then
		L.vitals  = rect(0, 0, 0, leftX, 0, S, vs.X, vs.Y, W, H)
		L.defense = rect(0, 0, 0, leftX, 0, S + vs.Y + defGap, vs.X, defH, W, H)
	else
		L.vitals  = rect(0, 1, 0, E, 1, -E, vs.X, vs.Y, W, H)
		L.defense = rect(0, 1, 0, E, 1, -(E + vs.Y + defGap), vs.X, defH, W, H)
	end

	local leftBottom = S + vs.Y + defExtra          -- touch: top-left stack bottom
	local leftStackTop = E + vs.Y + defExtra        -- desktop: stack height from the bottom
	local p = sz.party
	if isTouch then
		local top = leftBottom + G
		L.party = {
			anchorPoint = Vector2.new(0, 0),
			position    = UDim2.fromOffset(leftX, top),
			width = p.w, rowH = p.row, rowGap = p.gap,
			maxHeight = math.max(p.row, 0.60 * H - top),
		}
	else
		local topLimit = (badge and (badge.y + badge.h) or S) + G
		local bottom = H - (leftStackTop + G)
		L.party = {
			anchorPoint = Vector2.new(0, 1),
			position    = UDim2.new(0, E, 1, -(leftStackTop + G)),
			width = p.w, rowH = p.row, rowGap = p.gap,
			maxHeight = math.max(p.row, bottom - topLimit),
		}
	end
	local partyShown = combat and args.partyInHud == true

	local leftColumnRight
	if isTouch then
		leftColumnRight = leftX + math.max(vs.X, partyShown and p.w or 0)
	else
		leftColumnRight = badge and (badge.x + badge.w) or nil
	end
	L.leftColumnRight = leftColumnRight

	-- ── Top-centre ───────────────────────────────────────────────────────
	-- Corridor between the top-left and top-right occupants. The spec's
	-- formula assumes an empty top-right row; this uses the row that is
	-- actually there (currencies shown on tablet combat / legacy phone).
	local leftR = (isTouch and (leftX + vs.X) or (badge and (badge.x + badge.w) or E)) + G
	local rightW = rightReserve + (currencyAvail and cur.X or 0)
	local rightL = W - (E + rightW + G)
	local corridor = math.max(0, 2 * math.min(W / 2 - leftR, rightL - W / 2))
	L.corridor = corridor

	local slotted = args.hasTopCentreSlot == true
	local reserved
	if slotted then
		if isTouch then
			L.bossSlot = rect(0.5, 0, 0.5, 0, 0, S, corridor, sz.bossH, W, H)
		else
			L.bossSlot = {
				anchorPoint = Vector2.new(0.5, 0),
				position    = UDim2.new(0.5, 0, 0, S),
				size        = UDim2.new(0.36, 0, 0, sz.bossH),
				x = W * 0.32, y = S, w = W * 0.36, h = sz.bossH,
			}
		end
		reserved = (args.bossActive == true) and sz.bossReserve or 0
	else
		reserved = fromPx(attrs[ATTR.topCentreReserved]) or 0   -- standalone BossHud
	end
	L.bossReserved = reserved

	local runW = sz.run.X
	if isTouch then runW = math.min(runW, math.max(120, corridor)) end
	L.run = rect(0.5, 0, 0.5, 0, 0, S + reserved, runW, sz.run.Y, W, H)
	L.runSize = sz.runSize
	L.runReturnIdleY = S + reserved + sz.run.Y + G

	-- ── Bottom-centre: combo + defense combo ─────────────────────────────
	local comboBottom          -- distance from the bottom edge
	local comboCx = W / 2
	if isTouch then
		comboBottom = E
		local padLeft = fromPx(attrs[ATTR.skillPadLeft])
		if padLeft then
			-- keep the counter left of the SkillPad footprint (Dash)
			comboCx = math.min(comboCx, W - padLeft - G - sz.combo.X / 2)
		end
	else
		local abTop = fromPx(attrs[ATTR.actionBarTop])
		comboBottom = (abTop or 0) + G
		if not abTop then comboBottom = E end
	end
	local dx = comboCx - W / 2
	L.combo = rect(0.5, 1, 0.5, dx, 1, -comboBottom, sz.combo.X, sz.combo.Y, W, H)
	L.defCombo = rect(0.5, 1, 0.5, dx, 1, -(comboBottom + sz.combo.Y + G),
		sz.defCombo.X, sz.defCombo.Y, W, H)

	-- ── Lobby / Plaza bottom-right ───────────────────────────────────────
	local pl = sz.play
	if pl then
		local pos = pl.pos or UDim2.new(1, -E, 1, -E)
		L.play = rectFromUDim(1, 1, pos, pl.w, pl.h, W, H)
	end
	if place == "Plaza" then
		if sz.plazaEmote then L.emote = rectFromUDim(1, 1, sz.plazaEmote.pos, sz.plazaEmote.w, sz.plazaEmote.h, W, H) end
		if sz.plazaWardrobe then L.wardrobe = rectFromUDim(1, 1, sz.plazaWardrobe.pos, sz.plazaWardrobe.w, sz.plazaWardrobe.h, W, H) end
	elseif sz.emote then
		L.emote = rectFromUDim(1, 1, sz.emote.pos, sz.emote.w, sz.emote.h, W, H)
	end

	-- ── Visibility by hudMode (§4.2) ─────────────────────────────────────
	L.show = {
		vitals     = core,
		defense    = core and hasDefense,
		party      = core and partyShown,
		topCentre  = core and combat,
		rail       = full and hasRail,
		currencies = full and currencyAvail,
		play       = full and place == "Lobby",
		quick      = full and isTouch and place ~= "Combat",
		combo      = full and combat,
		classBadge = full and L.classBadge ~= nil,
	}

	-- ── §4.3 attributes (screen px; nil = region absent) ──────────────────
	local function px(v) return v and math.floor(v * s + 0.5) or nil end
	local legacyAttrs = args.legacyNav ~= false or not partyShown
	L.publish = {
		-- Geometry of the row, kept while the HUD is hidden: toasts must not
		-- jump up over a window's close button.
		[ATTR.topRightBottom]    = px(trBottom),
		[ATTR.leftColumnRight]   = px(leftColumnRight),
		[ATTR.rightRailLeft]     = hasRail and px(E + (collapsed and mb or railW)) or nil,
		[ATTR.topLeftBottom]     = (legacyAttrs and isTouch) and px(leftBottom + G) or nil,
		[ATTR.topLeftX]          = (legacyAttrs and isTouch) and px(leftX) or nil,
	}

	-- UI_TopCentreReservedPx only while slotted (standalone BossHud owns it
	-- otherwise). Not an and/or: a nil reserve must still clear a stale value.
	if slotted then
		L.publish[ATTR.topCentreReserved] = (reserved > 0) and px(reserved) or nil
	end
	L.publishReserve = slotted

	return L
end

-- ── Hooks ────────────────────────────────────────────────────────────────────

local function readAttrs(names)
	local t = {}
	for _, name in ipairs(names) do
		t[name] = ReplicatedStorage:GetAttribute(name)
	end
	return t
end

--- Live values of the attributes the layout consumes (screen px).
function Layout.useAttrs()
	local value, setValue = React.useState(function() return readAttrs(INPUT_ATTRS) end)
	React.useEffect(function()
		local conns = {}
		local function refresh() setValue(readAttrs(INPUT_ATTRS)) end
		for _, name in ipairs(INPUT_ATTRS) do
			table.insert(conns, ReplicatedStorage:GetAttributeChangedSignal(name):Connect(refresh))
		end
		refresh()
		return function()
			for _, c in ipairs(conns) do c:Disconnect() end
		end
	end, {})
	return value
end

--- compute() + publish. `dyn` carries every args field except place / ff /
--- hudMode (see compute).
function Layout.useHudLayout(place, ff, hudMode, dyn)
	local args = table.clone(dyn or {})
	args.place, args.ff, args.hudMode = place, ff, hudMode
	local L = Layout.compute(args)

	-- One effect per value keeps each write minimal.
	local pub = L.publish
	local deps = {}
	for _, name in ipairs(OUTPUT_ATTRS) do table.insert(deps, pub[name] or 0) end
	local slotted = L.publishReserve == true
	local tcr = slotted and pub[ATTR.topCentreReserved] or nil
	table.insert(deps, slotted and (tcr or 0) or -1)

	React.useEffect(function()
		for _, name in ipairs(OUTPUT_ATTRS) do
			ReplicatedStorage:SetAttribute(name, pub[name])
		end
		if slotted then
			ReplicatedStorage:SetAttribute(ATTR.topCentreReserved, tcr)
		end
	end, deps)

	-- The slotted boss reserve belongs to the HUD only while slotted.
	React.useEffect(function()
		if not slotted then return nil end
		return function()
			ReplicatedStorage:SetAttribute(ATTR.topCentreReserved, nil)
		end
	end, { slotted })

	React.useEffect(function()
		return function()
			for _, name in ipairs(OUTPUT_ATTRS) do
				ReplicatedStorage:SetAttribute(name, nil)
			end
		end
	end, {})

	return L
end

return Layout
