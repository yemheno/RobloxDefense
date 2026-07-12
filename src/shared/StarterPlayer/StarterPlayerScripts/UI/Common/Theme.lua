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

return Theme
