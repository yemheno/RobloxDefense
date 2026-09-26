-- UI/Common/Theme.lua
--[[
    Theme  (§T10/U3)
    ================
    SINGLE source of truth for the game's UI look. Every component
    should read colors/fonts from here instead of a per-file `C` table
    (the per-file tables are why menus drifted apart).

    Style direction (Pablo): anime / speed. Slanted ribbons, high
    contrast, motion-line accents. The geometry for that lives in
    AppWindow; the palette and icon registry live here.

    ICONS: swap the rbxassetid placeholders below and every menu
    updates at once. Recommended workflow: generate icon sheets
    (Claude Design or any image tool — see docs/TODO.md §T10/ICONS
    for the art brief), upload to Roblox as Decals, paste ids here.
]]

local Theme = {}

-- ── Palette ───────────────────────────────────────────────────────────────────
Theme.Colors = {
	-- Surfaces
	bg          = Color3.fromRGB( 12,  12,  18),   -- fullscreen base
	panel       = Color3.fromRGB( 18,  18,  26),   -- windowed panel
	panelAlt    = Color3.fromRGB( 24,  24,  36),   -- nested cards / rows
	track       = Color3.fromRGB( 35,  35,  50),   -- bar backgrounds
	dim         = Color3.fromRGB(  0,   0,   0),   -- backdrop dim layer

	-- Identity / accents  (speed-orange + electric blue duo)
	accent      = Color3.fromRGB(255, 170,  40),   -- primary: speed orange
	accent2     = Color3.fromRGB( 90, 190, 255),   -- secondary: electric blue
	gold        = Color3.fromRGB(255, 220, 100),

	-- Text
	text        = Color3.fromRGB(235, 235, 245),
	textDim     = Color3.fromRGB(140, 140, 160),
	textOnAccent= Color3.fromRGB( 20,  14,   6),

	-- States
	good        = Color3.fromRGB( 80, 210, 120),
	warn        = Color3.fromRGB(255, 200,  60),
	bad         = Color3.fromRGB(225,  70,  70),
	locked      = Color3.fromRGB( 55,  55,  70),

	-- Bars (HUD)
	hp          = Color3.fromRGB( 80, 210,  90),
	resource    = Color3.fromRGB( 80, 160, 255),
	xp          = Color3.fromRGB(210, 150,  40),
}

-- ── Type ──────────────────────────────────────────────────────────────────────
Theme.Fonts = {
	title  = Enum.Font.GothamBlack,   -- headers (uppercase for the speed look)
	bold   = Enum.Font.GothamBold,
	body   = Enum.Font.Gotham,
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

-- ── Layout tokens (§AGX/UI-P2) ───────────────────────────────────────────────
-- §AGX/UI-P2: per-form-factor size tokens from docs/ui_audit/mobile.md §2.2,
-- plus the combat-control geometry (SkillPad arc §2.4/§2.5, ActionBar). This is
-- the ONE place every SkillPad/ActionBar size and position comes from, so the
-- pending D1/D2 decisions can restyle them without touching component code.
-- Read it through FormFactor.Get().tokens (= Theme.Layout[kind]).
-- All numbers are offset pixels at the form factor's reference scale.
-- `uiScale` is recorded for D2 option (a) but is NOT applied yet.
Theme.Layout = {
	-- Classification thresholds (mobile.md §2.1 / §2.7)
	Breakpoints = {
		phoneMaxShort = 500,   -- touch + viewport short side <= this -> Phone
		inputDebounce = 0.25,  -- seconds a LastInputType flip must hold
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
		skillPad  = {
			-- Attack centre, measured in from the safe area's bottom-right corner
			anchor     = Vector2.new(68, 68),
			arcRadius  = 128,                    -- chord 2*128*sin15 = 66 >= 60+6
			arcAngles  = { 180, 210, 240, 270 }, -- Skill1..4, screen degrees (270 = up)
			dashOffset = Vector2.new(-208, 16),  -- Dash centre relative to Attack centre
			aimDeadzone = 12,                    -- px of drag before twin-stick aims
			knob       = 34,                     -- twin-stick knob diameter
			stroke     = 2,
			ultStroke  = 3,                      -- Skill4 gold ring
		},
	},

	Tablet = {
		uiScale   = 1.2,
		minTarget = 48, gap = 10, edge = 20,
		font      = { min = 14, body = 18, title = 26, hudMax = 32 },
		header    = 64, close = 48,
		attack    = 112, skill = 72, dash = 60,
		skillPad  = {
			anchor     = Vector2.new(80, 80),
			arcRadius  = 150,                    -- chord 77.6 >= 72+6
			arcAngles  = { 180, 210, 240, 270 },
			dashOffset = Vector2.new(-242, 20),
			aimDeadzone = 14,
			knob       = 40,
			stroke     = 2,
			ultStroke  = 3,
		},
	},

	Desktop = {
		uiScale   = 1,
		minTarget = 32, gap = 8, edge = 16,
		font      = { min = 12, body = 16, title = 28, hudMax = 32 },
		header    = 56, close = 40,
		skill     = 52,
		actionBar = {
			slot     = 52,     -- Skill1..4
			dashSlot = 40,
			gap      = 8,
			bottom   = 16,     -- distance from the screen's bottom edge
			padding  = 6,
			badge    = 18,     -- key badge height
			radius   = 8,
			stroke   = 2,
		},
	},

	Console = {
		uiScale   = 1.5,
		minTarget = 64, gap = 16, edge = 48,
		font      = { min = 20, body = 24, title = 36, hudMax = 40 },
		header    = 80, close = 64,
		skill     = 64,
		actionBar = {
			slot     = 64,
			dashSlot = 52,
			gap      = 16,
			bottom   = 48,
			padding  = 8,
			badge    = 24,
			radius   = 10,
			stroke   = 2,
		},
	},
}

return Theme
