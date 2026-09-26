-- UI/Common/Theme.lua
--[[
    Theme  (§T10/U3, v2 §AGX/UI-P1v2)
    =================================
    SINGLE source of truth for the game's UI look. Every component
    should read colors/fonts from here instead of a per-file `C` table
    (the per-file tables are why menus drifted apart).

    §AGX/UI-P1v2: D1 = HYBRID (DESIGN_DECISIONS.md#ui-decisions UI-D1, visual-system.md §4.6).
      • Bodies and lists: "Clean Tactical" — dark navy surfaces, ONE body
        accent = electric blue (Roles.accent.secondary), flat fills.
      • Identity: "Speed Anime" orange (Roles.accent.primary) ONLY on
        window header ribbons, primary CTAs and HUD vitals chrome.
      • Currencies own their colour + icon (Theme.Currency), never the accent.

    READ ORDER for new code (v2):
        Theme.Roles     semantic colours (surface/text/accent/state/border/
                        vital/currency/rarity). Features use ONLY these.
        Theme.color(x)  "text.secondary" -> Color3 (Color3 passes through)
        Theme.Type      type scale; Theme.typeFor(style, kind)
        Theme.Space / Radius / Stroke / Z / DisplayOrder / Motion / Metrics
        Theme.Currency  merits / essence identity (icon + colour + glyph)
        Theme.Layout    per-form-factor DESIGN px (phone scale, D2)
    Theme.Palette holds raw swatches; never reference it from features.

    LEGACY (kept for one release; do not use in new code):
        Theme.Colors.*  flat keys, each ALIASED to a v2 role below.
        Theme.Fonts.*   Enum.Font values (v2 = Theme.FontFaces).

    ICONS: swap the rbxassetid placeholders below and every menu
    updates at once. Recommended workflow: generate icon sheets
    (Claude Design or any image tool — see BACKLOG §T10/ICONS
    for the art brief), upload to Roblox as Decals, paste ids here.
    Source PNGs for every entry are in assets/ui/.
]]

local Theme = {}

local rgb = Color3.fromRGB

-- ── Palette: raw swatches (§AGX/UI-P1v2) ─────────────────────────────────────
-- Never read these from a feature; go through Theme.Roles.
Theme.Palette = {
	navy950  = rgb(  8,   8,  12),
	navy900  = rgb( 12,  12,  18),
	navy800  = rgb( 18,  18,  26),
	navy700  = rgb( 24,  24,  36),
	navy650  = rgb( 28,  30,  46),   -- btnSecondary plate body
	navy600  = rgb( 35,  35,  50),
	navy500  = rgb( 55,  55,  70),

	orange500 = rgb(255, 170,  40),  -- speed orange (identity)
	orange700 = rgb(200, 120,  20),
	blue400   = rgb( 90, 190, 255),  -- electric blue (body accent)
	blue300   = rgb(130, 210, 255),  -- essence (lighter than the accent)
	blue500   = rgb( 80, 160, 255),  -- resource bar
	green400  = rgb( 80, 210, 120),
	green500  = rgb( 80, 210,  90),  -- hp bar
	red400    = rgb(235,  90,  90),  -- danger text/stroke: 5.1:1 on navy700
	red600    = rgb(196,  48,  52),  -- danger fill: white text 5.5:1
	red700    = rgb(160,  40,  45),
	yellow400 = rgb(255, 200,  60),
	gold400   = rgb(255, 205,  70),  -- merits
	gold300   = rgb(255, 220, 100),  -- ult ring / legendary sheen
	amber500  = rgb(210, 150,  40),  -- xp
	purple400 = rgb(185, 120, 255),

	grey100 = rgb(235, 235, 245),    -- text.primary   14.4:1 on navy700
	grey300 = rgb(170, 172, 192),    -- text.secondary  7.8:1 on navy700
	grey500 = rgb(128, 130, 150),    -- text.disabled   4.6:1 on navy700
	white   = rgb(255, 255, 255),
	ink     = rgb( 20,  14,   6),    -- text on bright fills (orange/blue/green/yellow)
	black   = rgb(  0,   0,   0),
}
local P = Theme.Palette

-- ── Roles: semantic colours (§AGX/UI-P1v2) ───────────────────────────────────
-- Pairing rules (WCAG AA, 4.5:1 for body text; ratios measured):
--   text.primary / text.secondary on ANY surface.*            >= 6.9:1
--   bright fills (accent.primary, accent.secondary, state.success,
--   state.warning, currency.*) take text.onAccent (ink)       >= 9.3:1
--   state.dangerFill takes text.onDanger (white)                  5.5:1
--   state.locked fill takes text.secondary                        5.2:1
--   NEVER white/text.primary on orange, blue, green or yellow fills
--   (1.5–2.1:1).
Theme.Roles = {
	surface = {
		base   = P.navy900,   -- fullscreen base / sheets
		panel  = P.navy800,   -- windowed panel body
		raised = P.navy700,   -- cards, rows, header strip
		sunken = P.navy950,   -- wells, pills, inputs
		track  = P.navy600,   -- bar / slider tracks
		scrim  = P.black,     -- backdrop dim (use with Theme.Elevation.overlay)
	},
	text = {
		primary   = P.grey100,
		secondary = P.grey300,
		disabled  = P.grey500,
		onAccent  = P.ink,
		onDanger  = P.white,
		link      = P.blue400,
	},
	accent = {
		primary   = P.orange500,  -- ONLY: header ribbon, primary CTA, HUD vitals
		primaryDeep = P.orange700,
		secondary = P.blue400,    -- bodies/lists: selection, active tab, focus, links
	},
	state = {
		success    = P.green400,
		warning    = P.yellow400,
		danger     = P.red400,    -- text / icon / stroke
		dangerFill = P.red600,    -- button / close fills (white text)
		locked     = P.navy500,   -- locked fill; its text = text.secondary
	},
	border = {
		subtle = P.navy500,
		strong = P.grey500,
		focus  = P.blue400,
		identity = P.orange500,   -- window frame hairline, vitals frame
	},
	vital = {
		hp       = P.green500,
		hpLow    = P.red400,
		resource = P.blue500,
		xp       = P.amber500,
		shield   = P.blue300,
		boss     = { P.red600, P.orange500, P.purple400 },
	},
	currency = {
		merits  = P.gold400,
		essence = P.blue300,
	},
	rarity = {
		common    = P.grey300,
		uncommon  = P.green400,
		rare      = P.blue400,
		epic      = P.purple400,
		legendary = P.gold300,
	},
}
local R = Theme.Roles

--- §AGX/UI-P1v2: resolve "group.name" (e.g. "text.secondary") to a Color3.
--- A Color3 passes through; nil/unknown returns `fallback` (or text.primary).
function Theme.color(value, fallback)
	if typeof(value) == "Color3" then return value end
	if type(value) == "string" then
		local group, name = string.match(value, "^(%w+)%.(%w+)$")
		local t = group and R[group]
		local c = t and t[name]
		if typeof(c) == "Color3" then return c end
	end
	return fallback or R.text.primary
end

-- ── Legacy flat palette (aliases onto Roles) ─────────────────────────────────
-- §AGX/UI-P1v2: every key that current files read is kept and aliased to its
-- v2 role.
Theme.Colors = {
	-- Surfaces
	bg          = R.surface.base,       -- fullscreen base
	panel       = R.surface.panel,      -- windowed panel
	panelAlt    = R.surface.raised,     -- nested cards / rows
	track       = R.surface.track,      -- bar backgrounds
	dim         = R.surface.scrim,      -- backdrop dim layer

	-- Identity / accents
	accent      = R.accent.primary,     -- speed orange (ribbons/CTAs/vitals only)
	accent2     = R.accent.secondary,   -- electric blue (body accent)
	gold        = P.gold300,

	-- Text
	text        = R.text.primary,
	textDim     = R.text.secondary,
	textOnAccent= R.text.onAccent,

	-- States
	good        = R.state.success,
	warn        = R.state.warning,
	bad         = R.state.danger,
	locked      = R.state.locked,

	-- Bars (HUD)
	hp          = R.vital.hp,
	resource    = R.vital.resource,
	xp          = R.vital.xp,
}

-- ── Type ──────────────────────────────────────────────────────────────────────
Theme.Fonts = {  -- legacy Enum.Font (kept: AppWindow v1, SkillPad, ActionBar, Notify)
	title  = Enum.Font.GothamBlack,   -- headers (uppercase for the speed look)
	bold   = Enum.Font.GothamBold,
	body   = Enum.Font.Gotham,
}

-- §AGX/UI-P1v2: FontFace equivalents (same family, explicit weights).
local GOTHAM = "rbxasset://fonts/families/GothamSSm.json"
Theme.FontFaces = {
	heavy   = Font.new(GOTHAM, Enum.FontWeight.Heavy),
	bold    = Font.new(GOTHAM, Enum.FontWeight.Bold),
	medium  = Font.new(GOTHAM, Enum.FontWeight.Medium),
	regular = Font.new(GOTHAM, Enum.FontWeight.Regular),
}
local FF = Theme.FontFaces

-- §AGX/UI-P1v2: type scale in DESIGN px (phone scale; the root UIScale
-- multiplies them). `size` is the TextSize; min/max feed a
-- UITextSizeConstraint and are per form factor so that the FINAL px meet
-- mobile.md §2.2 (Phone 12 / Tablet 14 / Desktop 12 / Console 20 body floor)
-- after scale: e.g. Console body min 14 x 1.5 = 21.
--   { Phone, Tablet, Desktop, Console }
Theme.Type = {
	display = { font = FF.heavy,  upper = true, size = 32, lineHeight = 38,
		min = { Phone = 24, Tablet = 24, Desktop = 22, Console = 26 },
		max = { Phone = 48, Tablet = 48, Desktop = 48, Console = 48 } },
	title   = { font = FF.heavy,  upper = true, size = 22, lineHeight = 28,
		min = { Phone = 18, Tablet = 18, Desktop = 16, Console = 20 },
		max = { Phone = 32, Tablet = 32, Desktop = 32, Console = 32 } },
	heading = { font = FF.bold,   size = 18, lineHeight = 24,
		min = { Phone = 15, Tablet = 15, Desktop = 14, Console = 16 },
		max = { Phone = 24, Tablet = 24, Desktop = 24, Console = 24 } },
	body    = { font = FF.medium, size = 16, lineHeight = 22,
		min = { Phone = 13, Tablet = 13, Desktop = 12, Console = 14 },
		max = { Phone = 20, Tablet = 20, Desktop = 20, Console = 20 } },
	label   = { font = FF.bold,   size = 15, lineHeight = 20,
		min = { Phone = 12, Tablet = 12, Desktop = 12, Console = 14 },
		max = { Phone = 18, Tablet = 18, Desktop = 18, Console = 18 } },
	caption = { font = FF.regular, size = 13, lineHeight = 18,
		min = { Phone = 11, Tablet = 11, Desktop = 11, Console = 13 },
		max = { Phone = 15, Tablet = 15, Desktop = 15, Console = 15 } },
	numeric = { font = FF.bold,   size = 16, lineHeight = 20,
		min = { Phone = 12, Tablet = 12, Desktop = 12, Console = 14 },
		max = { Phone = 22, Tablet = 22, Desktop = 22, Console = 22 } },
}

--- §AGX/UI-P1v2: resolved style for a form factor kind ("Phone"...).
--- -> { font, size, min, max, lineHeight, upper }
function Theme.typeFor(style, kind)
	local t = Theme.Type[style] or Theme.Type.body
	kind = kind or "Phone"
	local min = t.min[kind] or t.min.Phone
	local max = t.max[kind] or t.max.Phone
	return {
		font       = t.font,
		size       = math.clamp(t.size, min, max),
		min        = min,
		max        = max,
		lineHeight = t.lineHeight,
		upper      = t.upper == true,
	}
end

-- ── Spacing, radii, strokes (§AGX/UI-P1v2, design px) ───────────────────────
Theme.Space = { none = 0, xxs = 2, xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32 }

-- 5 radii (collapses the 26 values found in the audit).
Theme.Radius = {
	none = UDim.new(0, 0),
	sm   = UDim.new(0, 4),
	md   = UDim.new(0, 8),
	lg   = UDim.new(0, 12),
	pill = UDim.new(0.5, 0),
}

Theme.Stroke = { hair = 1, base = 1.5, strong = 2, focus = 2.5 }

--- Space token name or number -> number (design px).
function Theme.space(v)
	if type(v) == "number" then return v end
	return Theme.Space[v or "md"] or Theme.Space.md
end

-- ── Layers (§AGX/UI-P1v2) ────────────────────────────────────────────────────
-- ZIndex bands INSIDE one ScreenGui (ZIndexBehavior.Sibling): siblings under
-- an App root compare by these. HUD < windows < modals < toasts < tooltips.
Theme.Z = {
	world = 0, hud = 1, hudFloat = 5,
	window = 10, windowOver = 20,
	modal = 40, toast = 60, tooltip = 80, debug = 100,
}
-- ScreenGui DisplayOrder bands (between ScreenGuis). Matches what ships:
-- AppGui 0, SkillPad/ActionBar 1 (Layout.CombatControls), JoystickAim 5,
-- SkillVisuals cast bar 8, NotifyGui 30, modals 40+, MobVisuals flash 100,
-- LoadingScreen 1000.
Theme.DisplayOrder = {
	app = 0, combatControls = 1, joystick = 5, castBar = 8,
	notify = 30, modal = 40, tooltip = 50, flash = 100, loading = 1000,
	-- §AGX/UI-P3: PanelGui (PanelHost) sits above the combat controls (1),
	-- JoystickAim (5) and the cast bar (8) and below NotifyGui (30), so
	-- toasts stay readable over panels (shell-spec §3.2 rule 6).
	panels = 20,
}

Theme.Elevation = {
	flat    = { surface = "panel",  stroke = "hair" },
	raised  = { surface = "raised", stroke = "base" },
	sunken  = { surface = "sunken", stroke = nil },
	overlay = { scrim = 0.42 },   -- BackgroundTransparency of the scrim
}

Theme.Motion = {
	fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	base = TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	emph = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

-- ── Component metrics (§AGX/UI-P1v2, design px, all form factors) ──────────
-- Every tappable height here is >= 44 design px, and the root UIScale is
-- >= 1 on every form factor, so every target is >= 44 px on screen.
Theme.Metrics = {
	button     = { sm = 44, md = 48, lg = 56, padX = 16, iconGap = 8, minWidth = 88, icon = 22 },
	iconButton = { sm = 44, md = 48, lg = 56, glyph = 0.5 },   -- glyph = share of the side
	tabs       = { height = 44, minWidth = 88, underline = 3, chipThreshold = 4 },
	pill       = { height = 32, tapHeight = 44, icon = 20, padX = 10 },
	bar        = { height = 16, vitalHeight = 20, labelGap = 4 },
	card       = { pad = 12, minTap = 44 },
	modal      = { width = 420, maxWidthScale = 0.92, maxHeightScale = 0.9 },
	tooltip    = { maxWidth = 260, pad = 8, offset = 10, holdTime = 0.35, moveCancel = 10 },
	window     = { windowedSize = UDim2.fromScale(0.88, 0.82), topGap = 4, closeInset = 8, titleSize = 26 },
	scrollBar  = 6,
	-- §AGX/UI-P3: menu surfaces (shell-spec §4.5). Kind-independent values;
	-- the per-kind rail sizes live in Theme.Layout[kind].rail. Ratios and
	-- times are here, NOT in Theme.Layout, because FormFactor multiplies
	-- every number in a Layout table into ff.tokens.
	menu       = {
		tileGap      = 8,      -- between tiles in a section
		sectionGap   = 16,     -- between sections that share a row
		rowGap       = 12,     -- between rows of sections
		tileMinW     = 88,     -- a sheet may shrink 96 -> 88 to save a whole row
		tileIcon     = 28,
		badge        = 16,     -- badge circle (Phone: badgePhone)
		badgePhone   = 18,
		sheetMaxW    = 780,    -- the sheet is a centred card on wide screens
		radialShortFrac = 0.62,
		radialDeadzone  = 0.5,
		holdConfirm     = 0.25,  -- s of DPadDown hold before release confirms
		flyoutGroups = { character = true, progress = true },  -- D3: flyouts only here
	},
}

-- ── Speed styling constants (used by AppWindow chrome) ────────────────────────
Theme.Speed = {
	slantDeg    = -8,     -- header ribbon slant
	lineCount   = 3,      -- motion lines trailing the title
	lineSlantDeg= -25,    -- motion line angle
}

-- ── Icon registry ─────────────────────────────────────────────────────────────
-- rbxassetid://0 = placeholder (renders empty). Paste real ids here.
Theme.Icons = {
	-- Menu / window icons
	classes     = "rbxassetid://0",
	stats       = "rbxassetid://0",
	talents     = "rbxassetid://0",
	equipment   = "rbxassetid://0",
	wardrobe    = "rbxassetid://0",
	achievements= "rbxassetid://0",
	settings    = "rbxassetid://0",
	shop        = "rbxassetid://0",
	inventory   = "rbxassetid://0",
	dailyLogin  = "rbxassetid://0",
	leaderboard = "rbxassetid://0",
	social      = "rbxassetid://0",

	-- Currencies / resources
	essence     = "rbxassetid://0",
	merits      = "rbxassetid://0",

	-- Combat
	attack      = "rbxassetid://0",
	skillLocked = "rbxassetid://0",

	-- §AGX/UI-P3: shell menu icons with no delivered art yet (shell-spec
	-- §2.1). Add to the Claude Design brief; the glyphs below render meanwhile.
	play        = "rbxassetid://0",
	leave       = "rbxassetid://0",
	emote       = "rbxassetid://0",
	menu        = "rbxassetid://0",
}

-- §AGX/UI-P1v2: text glyph fallbacks while an icon id is a placeholder (and
-- for the few UI glyphs that have no art: close/back/check/lock/plus/minus).
Theme.Glyphs = {
	close = "✕", back = "‹", check = "✓", lock = "🔒", plus = "+", minus = "−",
	info = "i", warning = "!", menu = "☰", more = "⋮",
	merits = "★", essence = "◆",
	-- §AGX/UI-P3: menu icon fallbacks while Theme.Icons are placeholders.
	-- Keyed like Theme.Icons, so IconButton / Card / MenuIcon pick them up.
	-- Colour emoji ignore TextColor3: dim them with TextTransparency.
	classes = "⚔️", stats = "📊", talents = "✨", equipment = "🛡️",
	wardrobe = "👕", inventory = "🎒", achievements = "🏆", dailyLogin = "🎁",
	leaderboard = "🏅", social = "👥", shop = "🛒", settings = "⚙️",
	play = "▶", leave = "🚪", emote = "👋",
	appearance = "🪞",  -- §AGX/X18b: menu "Change appearance"
}

--- Convenience: icon id or nil when still a placeholder (lets callers
--- fall back to text glyphs until real art lands).
function Theme.GetIcon(name)
	local id = Theme.Icons[name]
	if not id or id == "rbxassetid://0" then return nil end
	return id
end

-- ── Image registry (§BEAUTY: Claude Design drop, source PNGs in assets/ui/) ───
-- Same placeholder convention as Icons. `slice` = SliceCenter for 9-slice
-- plates (source sizes: buttons 256², barFrame 512×128).
Theme.Images = {
	-- 9-slice button plates
	btnPrimary   = { id = "rbxassetid://0", slice = Rect.new(48, 48, 208, 208) },
	btnSecondary = { id = "rbxassetid://0", slice = Rect.new(48, 48, 208, 208) },
	btnDanger    = { id = "rbxassetid://0", slice = Rect.new(48, 48, 208, 208) },
	btnLocked    = { id = "rbxassetid://0", slice = Rect.new(48, 48, 208, 208) },

	-- Vitals bar kit (fills stay code-side UIGradients)
	barFrame     = { id = "rbxassetid://0", slice = Rect.new(80, 32, 432, 96) },
	barShine     = { id = "rbxassetid://0" }, -- stretch overlay, no slice

	-- 2D particle sprites — WHITE on transparent; tint via ImageColor3
	pGlow        = { id = "rbxassetid://0" },
	pSpark       = { id = "rbxassetid://0" },
	pBolt        = { id = "rbxassetid://0" }, -- 256×64, horizontally tileable
	pStreak      = { id = "rbxassetid://0" },
	pEmber       = { id = "rbxassetid://0" },
}

--- Image entry or nil while still a placeholder (same contract as GetIcon).
function Theme.GetImage(name)
	local entry = Theme.Images[name]
	if not entry or entry.id == "rbxassetid://0" then return nil end
	return entry
end

-- ── Currency identity (§AGX/UI-P1v2) ─────────────────────────────────────────
-- ONE icon + ONE colour per currency, used everywhere via CurrencyPill.
-- Colours come from the delivered art (merits.png = amber star medal,
-- essence.png = blue drop); essence is lighter than the body accent so a
-- price never reads as a link.
Theme.Currency = {
	merits  = { icon = "merits",  glyph = Theme.Glyphs.merits,  color = R.currency.merits,  label = "Merits" },
	essence = { icon = "essence", glyph = Theme.Glyphs.essence, color = R.currency.essence, label = "Essence" },
}

-- ── Layout tokens (§AGX/UI-P2, §AGX/UI-P1v2) ─────────────────────────────────
-- D2 = "fixed sizes at PHONE scale + one root UIScale per form
-- factor". Every number below is a DESIGN px at phone scale. The final
-- on-screen px = design x uiScale, applied ONCE, either by
--   (a) a UIScale ancestor (UI/Common/UIScaleRoot)  -> read ff.design, or
--   (b) FormFactor pre-multiplying the numbers for code that lives in its own
--       ScreenGui with no UIScale (SkillPad, ActionBar, Notify) -> ff.tokens.
-- Never both (that is the double-scale bug).
-- uiScale: Phone 1, Tablet 1.15, Desktop/Console computed from the viewport
-- by Theme.Layout.UIScale (1080p desktop = 1.333: the 56 px design header
-- renders at 75 px). After the UIScale, Tablet / Console land on the
-- mobile.md §2.2 sizes (98 x 1.15 = 113, 54 x 1.5 = 81).
Theme.Layout = {
	-- Classification thresholds (mobile.md §2.1 / §2.7)
	Breakpoints = {
		phoneMaxShort = 500,   -- touch + viewport short side <= this -> Phone
		inputDebounce = 0.25,  -- seconds a LastInputType flip must hold
	},

	-- §AGX/UI-P1v2: uiScale rule per kind. A number is fixed; a table is
	-- clamp(viewport short side / refShort, min, max), rounded to 0.01.
	-- min >= 1 everywhere keeps every 44-design-px target >= 44 px.
	UIScale = {
		Phone   = 1,
		Tablet  = 1.15,
		Desktop = { refShort = 810, min = 1,    max = 2 },    -- 1080p -> 1.333
		Console = { refShort = 720, min = 1.25, max = 2.5 },  -- 1080p -> 1.5
	},

	-- Shared by all form factors
	CombatControls = {
		displayOrder = 1,      -- SkillPad / ActionBar ScreenGui (AppGui is 0)
		attackRepeat = 0.1,    -- s between repeat presses while Attack is held
	},

	Phone = {
		uiScale   = 1,
		minTarget = 48, gap = 8, edge = 16,
		font      = { min = 12, body = 16, title = 22, hudMax = 28 },
		header    = 56, close = 48,
		attack    = 96, skill = 60, dash = 52,
		-- §AGX/UI-P3: shell-spec §4.4; the rail never fits the phone band.
		rail      = { collapsed = true, menuButton = 48, tile = Vector2.new(96, 72) },
		skillPad  = {
			-- Attack centre, measured in from the safe area's bottom-right corner
			anchor     = Vector2.new(68, 68),
			arcRadius  = 128,                    -- chord 2*128*sin15 = 66 >= 60+6
			arcAngles  = { 180, 210, 240, 270 }, -- Skill1..4, screen degrees (270 = up); NOT scaled
			dashOffset = Vector2.new(-208, 16),  -- Dash centre relative to Attack centre
			aimDeadzone = 12,                    -- px of drag before twin-stick aims
			knob       = 34,                     -- twin-stick knob diameter
			stroke     = 2,
			ultStroke  = 3,                      -- Skill4 gold ring
		},
	},

	-- §AGX/UI-P1v2: phone-scale values; x1.15 gives mobile.md's tablet sizes.
	Tablet = {
		uiScale   = 1.15,
		minTarget = 48, gap = 9, edge = 18,
		font      = { min = 12, body = 16, title = 22, hudMax = 28 },
		header    = 56, close = 48,
		attack    = 98, skill = 60, dash = 52,
		-- §AGX/UI-P3: rail in Lobby/Plaza, ☰ in combat (the band decides, §4.4).
		rail      = { cell = 44, gap = 8, pad = 6, icon = 28, menuButton = 48,
			tile = Vector2.new(96, 72) },
		skillPad  = {
			anchor     = Vector2.new(70, 70),
			arcRadius  = 130,                    -- chord 67.3 >= 60+6
			arcAngles  = { 180, 210, 240, 270 },
			dashOffset = Vector2.new(-210, 17),
			aimDeadzone = 12,
			knob       = 35,
			stroke     = 2,
			ultStroke  = 3,
		},
	},

	-- §AGX/UI-P1v2: x1.333 at 1080p: header 75, close 59, slot 64, font 16/21/28/32.
	Desktop = {
		uiScale   = 1,         -- floor; the live value comes from UIScale.Desktop
		minTarget = 44, gap = 6, edge = 12,
		font      = { min = 12, body = 16, title = 21, hudMax = 24 },
		header    = 56, close = 44,
		skill     = 48,
		-- §AGX/UI-P3: rail in every place (shell-spec §4.4).
		rail      = { cell = 44, gap = 8, pad = 6, icon = 28, menuButton = 44,
			tile = Vector2.new(88, 64) },
		actionBar = {
			slot     = 48,     -- Skill1..4
			dashSlot = 44,
			gap      = 6,
			bottom   = 12,     -- distance from the screen's bottom edge
			padding  = 5,
			badge    = 14,     -- key badge height
			radius   = 6,
			stroke   = 1.5,
		},
	},

	-- §AGX/UI-P1v2: x1.5 at 1080p: header 81, close 66, slot 66, font 21/24/36/40.
	Console = {
		uiScale   = 1.25,      -- floor; the live value comes from UIScale.Console
		minTarget = 44, gap = 11, edge = 32,
		font      = { min = 14, body = 16, title = 24, hudMax = 27 },
		header    = 54, close = 44,
		skill     = 44,
		-- §AGX/UI-P3: radial menu (shell-spec §4.5). min/max are SCREEN px of
		-- the wheel diameter (like EmoteWheel); btnMin is design px. The
		-- short-side fraction is Theme.Metrics.menu.radialShortFrac.
		rail      = { collapsed = true, menuButton = 64, tile = Vector2.new(96, 72),
			radial = { min = 320, max = 560, btnMin = 64 } },
		actionBar = {
			slot     = 44,
			dashSlot = 40,
			gap      = 11,
			bottom   = 32,
			padding  = 5,
			badge    = 16,
			radius   = 7,
			stroke   = 1.5,
		},
	},
}

return Theme
