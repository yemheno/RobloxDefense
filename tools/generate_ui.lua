--[[
	generate_ui.lua  –  Paste into Roblox Studio Command Bar
	=========================================================
	Creates the complete Lobby + Social Plaza UI hierarchy inside
	game.StarterGui as native Instances.  All sizes use Scale (%)
	for mobile / PC support — zero pixel offsets.

	After running, open StarterGui ▸ AppGui in the Explorer and
	adjust positions, sizes, and colours in the Properties panel.

	Components created (matching the React tree):
	  HUD  ·  ClassMenu  ·  StatsMenu  ·  EquipmentUI  ·  TalentTreeUI
	  WardrobeUI  ·  AchievementsUI  ·  SettingsUI  ·  GlobalShopUI
	  CharacterCreation  ·  EmoteWheel  ·  DeathUI  ·  TeammateVitals
	  VoteUI  ·  MainMenu  ·  MatchmakingUI  ·  SocialPanel  ·  NPCDialog
	  ShopUI  ·  WeaponSmithUI  ·  DailyLoginUI  ·  LeaderboardUI
	  InventoryUI  ·  PartyInviteToast  ·  BattleClassUI  ·  TestingUI
	  AppearanceBar (Social Plaza)

	Overlay panels start Visible = false – they are toggled by scripts.
]]

-- ═══════════════════════════════════════════════════════════
-- HELPER
-- ═══════════════════════════════════════════════════════════

local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then inst.Parent = parent end
	return inst
end

-- StatusBar builder (reused by HUD bars)
local function mkStatusBar(parent, barName, label, color, layoutOrder)
	local row = mk("Frame", {
		Name = barName,
		Size = UDim2.fromScale(1, 0.27),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,
	}, parent)

	local inner = mk("Frame", {
		Name = "Inner",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, row)

	mk("TextLabel", {
		Name = "Label",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(0.18, 1),
		BackgroundTransparency = 1,
		Text = label,
		TextColor3 = Color3.fromRGB(140, 140, 160),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, inner)

	local track = mk("Frame", {
		Name = "Track",
		Position = UDim2.fromScale(0.19, 0.15),
		Size = UDim2.fromScale(0.55, 0.70),
		BackgroundColor3 = Color3.fromRGB(35, 35, 50),
		BorderSizePixel = 0,
	}, inner)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, track)

	local fill = mk("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.65, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, track)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fill)

	mk("TextLabel", {
		Name = "Value",
		Position = UDim2.fromScale(0.75, 0),
		Size = UDim2.fromScale(0.25, 1),
		BackgroundTransparency = 1,
		Text = "100 / 100",
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, inner)

	return row
end

-- Simple overlay-panel builder (backdrop + centred panel + title + close)
local function mkOverlayPanel(parent, name, panelW, panelH, titleText, zIndex, panelAnchorX, panelAnchorY, panelPosX, panelPosY)
	panelAnchorX = panelAnchorX or 0.5
	panelAnchorY = panelAnchorY or 0.5
	panelPosX = panelPosX or 0.5
	panelPosY = panelPosY or 0.5
	zIndex = zIndex or 10

	local backdrop = mk("Frame", {
		Name = name .. "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.42,
		ZIndex = zIndex,
		Visible = false,
	}, parent)

	local panel = mk("Frame", {
		Name = name .. "Panel",
		AnchorPoint = Vector2.new(panelAnchorX, panelAnchorY),
		Position = UDim2.fromScale(panelPosX, panelPosY),
		Size = UDim2.fromScale(panelW, panelH),
		BackgroundColor3 = Color3.fromRGB(18, 18, 24),
		BorderSizePixel = 0,
		ZIndex = zIndex + 1,
	}, backdrop)
	mk("UICorner", { CornerRadius = UDim.new(0.015, 0) }, panel)

	mk("TextLabel", {
		Name = "Title",
		Position = UDim2.fromScale(0.03, 0.02),
		Size = UDim2.fromScale(0.72, 0.07),
		BackgroundTransparency = 1,
		Text = titleText,
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = zIndex + 2,
	}, panel)

	local closeBtn = mk("TextButton", {
		Name = "CloseBtn",
		Position = UDim2.fromScale(0.915, 0.015),
		Size = UDim2.fromScale(0.07, 0.09),
		BackgroundColor3 = Color3.fromRGB(80, 36, 36),
		BorderSizePixel = 0,
		Text = "✕",
		TextColor3 = Color3.fromRGB(245, 100, 100),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = zIndex + 2,
	}, panel)
	mk("UICorner", { CornerRadius = UDim.new(0.25, 0) }, closeBtn)

	return backdrop, panel
end

-- Nav-style button (used in HUD nav panel)
local function mkNavBtn(parent, name, text, textColor, strokeColor, layoutOrder, zIndex)
	local btn = mk("TextButton", {
		Name = name,
		Size = UDim2.fromScale(1, 0.037),
		BackgroundColor3 = Color3.fromRGB(35, 35, 52),
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = textColor,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		LayoutOrder = layoutOrder,
		ZIndex = zIndex or 6,
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0.18, 0) }, btn)
	mk("UIStroke", { Color = strokeColor, Thickness = 1.5 }, btn)
	return btn
end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP + SCREEN GUI
-- ═══════════════════════════════════════════════════════════

local existing = game.StarterGui:FindFirstChild("AppGui")
if existing then existing:Destroy() end

local gui = mk("ScreenGui", {
	Name = "AppGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
}, game.StarterGui)

local root = mk("Frame", {
	Name = "AppRoot",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, gui)


-- ═══════════════════════════════════════════════════════════
-- HUD  (always visible)
-- ═══════════════════════════════════════════════════════════

local hud = mk("Frame", {
	Name = "HUD",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, root)

-- ── Menu button (top-left) ────────────────────────────────
local menuBtn = mk("TextButton", {
	Name = "MenuBtn",
	Position = UDim2.fromScale(0.003, 0.005),
	Size = UDim2.fromScale(0.035, 0.05),
	BackgroundColor3 = Color3.fromRGB(35, 35, 52),
	BorderSizePixel = 0,
	Text = "☰",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 4,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.2, 0) }, menuBtn)
mk("UIStroke", { Color = Color3.fromRGB(60, 100, 180), Thickness = 1.5 }, menuBtn)

-- ── Currency strip (top) ──────────────────────────────────
local currStrip = mk("Frame", {
	Name = "CurrencyStrip",
	Position = UDim2.fromScale(0.04, 0),
	Size = UDim2.fromScale(0.96, 0.055),
	BackgroundColor3 = Color3.fromRGB(18, 18, 24),
	BackgroundTransparency = 0.30,
	BorderSizePixel = 0,
}, hud)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.008, 0),
}, currStrip)
mk("UIPadding", { PaddingLeft = UDim.new(0.01, 0) }, currStrip)

local function mkCurrencyPill(parent, name, icon, value, color, order)
	local pill = mk("Frame", {
		Name = name,
		Size = UDim2.fromScale(0.20, 0.75),
		BackgroundColor3 = Color3.fromRGB(28, 28, 42),
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, pill)
	mk("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = icon .. "  " .. tostring(value),
		TextColor3 = color,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
	}, pill)
	return pill
end

mkCurrencyPill(currStrip, "EssencePill", "♦", 0, Color3.fromRGB(80, 210, 255), 1)
mkCurrencyPill(currStrip, "MeritsPill", "★", 0, Color3.fromRGB(255, 200, 60), 2)
mkCurrencyPill(currStrip, "PowerPill", "⚡", 0, Color3.fromRGB(255, 180, 40), 3)

-- ── Status panel (bottom-left) ────────────────────────────
local statusPanel = mk("Frame", {
	Name = "StatusPanel",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0.01, 0.985),
	Size = UDim2.fromScale(0.32, 0.17),
	BackgroundColor3 = Color3.fromRGB(18, 18, 24),
	BackgroundTransparency = 0.30,
	BorderSizePixel = 0,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.04, 0) }, statusPanel)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.03, 0),
}, statusPanel)
mk("UIPadding", {
	PaddingLeft = UDim.new(0.03, 0),
	PaddingRight = UDim.new(0.03, 0),
	PaddingTop = UDim.new(0.03, 0),
	PaddingBottom = UDim.new(0.03, 0),
}, statusPanel)

mkStatusBar(statusPanel, "HPRow", "HP", Color3.fromRGB(80, 210, 90), 1)
mkStatusBar(statusPanel, "ResRow", "Resource", Color3.fromRGB(80, 160, 255), 2)
mkStatusBar(statusPanel, "XPRow", "Lv1", Color3.fromRGB(210, 150, 40), 3)

-- ── Start Game button (top-centre, hidden by default) ─────
local startBtn = mk("TextButton", {
	Name = "StartBtn",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.068),
	Size = UDim2.fromScale(0.16, 0.065),
	BackgroundColor3 = Color3.fromRGB(50, 160, 70),
	BorderSizePixel = 0,
	Text = "▶  Start Game",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 3,
	Visible = false,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.35, 0) }, startBtn)

-- ── Countdown badge (top-centre) ──────────────────────────
local cdBadge = mk("TextLabel", {
	Name = "CountdownBadge",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.068),
	Size = UDim2.fromScale(0.16, 0.065),
	BackgroundColor3 = Color3.fromRGB(200, 140, 30),
	BorderSizePixel = 0,
	Text = "Starting in 5...",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 3,
	Visible = false,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.35, 0) }, cdBadge)

-- ── Combo badge (bottom-centre) ───────────────────────────
local comboBadge = mk("Frame", {
	Name = "ComboBadge",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.92),
	Size = UDim2.fromScale(0.14, 0.07),
	BackgroundColor3 = Color3.fromRGB(20, 20, 30),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	ZIndex = 3,
	Visible = false,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, comboBadge)
mk("UIStroke", { Color = Color3.fromRGB(255, 200, 50), Thickness = 2 }, comboBadge)
mk("TextLabel", {
	Name = "ComboLabel",
	Size = UDim2.fromScale(1, 0.55),
	BackgroundTransparency = 1,
	Text = "5x  COMBO",
	TextColor3 = Color3.fromRGB(255, 210, 60),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
}, comboBadge)

-- ── Wave banner (top-centre) ──────────────────────────────
local waveBanner = mk("TextLabel", {
	Name = "WaveBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.117),
	Size = UDim2.fromScale(0.30, 0.055),
	BackgroundColor3 = Color3.fromRGB(20, 20, 30),
	BackgroundTransparency = 0.20,
	BorderSizePixel = 0,
	Text = "WAVE 1  (20 mobs)",
	TextColor3 = Color3.fromRGB(80, 210, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 3,
	Visible = false,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.35, 0) }, waveBanner)
mk("UIStroke", { Color = Color3.fromRGB(80, 210, 255), Thickness = 1.5, Transparency = 0.4 }, waveBanner)

-- ── Defense line HP bar (bottom-left, above status) ───────
local defBar = mk("Frame", {
	Name = "DefenseBar",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0.01, 0.80),
	Size = UDim2.fromScale(0.32, 0.05),
	BackgroundColor3 = Color3.fromRGB(18, 18, 24),
	BackgroundTransparency = 0.30,
	BorderSizePixel = 0,
	ZIndex = 3,
	Visible = false,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, defBar)
mkStatusBar(defBar, "DefenseBarInner", "Defense", Color3.fromRGB(210, 80, 80), 1)

-- ── Defense combo badge ───────────────────────────────────
local defComboBadge = mk("TextLabel", {
	Name = "DefComboBadge",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.84),
	Size = UDim2.fromScale(0.18, 0.04),
	BackgroundColor3 = Color3.fromRGB(30, 20, 40),
	BackgroundTransparency = 0.20,
	BorderSizePixel = 0,
	Text = "Defense Combo Lv1  x1.5",
	TextColor3 = Color3.fromRGB(255, 180, 80),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 3,
	Visible = false,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.35, 0) }, defComboBadge)

-- ── Death killfeed (top-right) ────────────────────────────
local deathFeed = mk("TextLabel", {
	Name = "DeathFeed",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.98, 0.08),
	Size = UDim2.fromScale(0.24, 0.04),
	BackgroundColor3 = Color3.fromRGB(60, 15, 15),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	Text = "Player was slain by a Mob",
	TextColor3 = Color3.fromRGB(255, 100, 100),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 4,
	Visible = false,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, deathFeed)

-- ── Combo summary toast (centre) ──────────────────────────
local comboToast = mk("TextLabel", {
	Name = "ComboToast",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.40),
	Size = UDim2.fromScale(0.22, 0.06),
	BackgroundColor3 = Color3.fromRGB(25, 20, 40),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Text = "12x Combo!  1500 dmg  3 crits",
	TextColor3 = Color3.fromRGB(255, 210, 60),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 5,
	Visible = false,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, comboToast)
mk("UIStroke", { Color = Color3.fromRGB(200, 160, 40), Thickness = 1.5, Transparency = 0.3 }, comboToast)

-- ── Next Wave button (top-centre) ─────────────────────────
local nextWaveBtn = mk("TextButton", {
	Name = "NextWaveBtn",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.068),
	Size = UDim2.fromScale(0.16, 0.065),
	BackgroundColor3 = Color3.fromRGB(40, 130, 200),
	BorderSizePixel = 0,
	Text = "Next Wave  >>",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 3,
	Visible = false,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.35, 0) }, nextWaveBtn)

-- ── Return to Lobby button ────────────────────────────────
local returnBtn = mk("TextButton", {
	Name = "ReturnBtn",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.14),
	Size = UDim2.fromScale(0.16, 0.065),
	BackgroundColor3 = Color3.fromRGB(160, 60, 60),
	BorderSizePixel = 0,
	Text = "Return to Lobby",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 3,
	Visible = false,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.35, 0) }, returnBtn)

-- ── Nav toggle button (right) ─────────────────────────────
local navToggle = mk("TextButton", {
	Name = "NavToggle",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(0.985, 0.50),
	Size = UDim2.fromScale(0.055, 0.075),
	BackgroundColor3 = Color3.fromRGB(35, 35, 52),
	BorderSizePixel = 0,
	Text = "⋮",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 6,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.2, 0) }, navToggle)
mk("UIStroke", { Color = Color3.fromRGB(60, 100, 180), Thickness = 1.5 }, navToggle)

-- ── Nav panel (right, slides in/out) ──────────────────────
local navPanel = mk("Frame", {
	Name = "NavPanel",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(1.20, 0.50),
	Size = UDim2.fromScale(0.22, 0.30),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = Color3.fromRGB(18, 18, 28),
	BackgroundTransparency = 0.10,
	BorderSizePixel = 0,
	ZIndex = 5,
	Visible = false,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0.04, 0) }, navPanel)
mk("UIStroke", { Color = Color3.fromRGB(60, 80, 160), Thickness = 1.5 }, navPanel)
mk("UIGridLayout", {
	CellSize = UDim2.fromScale(0.47, 0.033),
	CellPadding = UDim2.fromScale(0.02, 0.005),
	SortOrder = Enum.SortOrder.LayoutOrder,
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Top,
}, navPanel)
mk("UIPadding", {
	PaddingLeft = UDim.new(0.002, 0),
	PaddingRight = UDim.new(0.002, 0),
	PaddingTop = UDim.new(0.005, 0),
	PaddingBottom = UDim.new(0.005, 0),
}, navPanel)

local accent = Color3.fromRGB(105, 190, 255)
local btnStroke = Color3.fromRGB(60, 100, 180)
mkNavBtn(navPanel, "NavClasses", "Classes", accent, btnStroke, 1)
mkNavBtn(navPanel, "NavStats", "Stats", accent, btnStroke, 2)
mkNavBtn(navPanel, "NavEquip", "Equipment", accent, btnStroke, 3)
mkNavBtn(navPanel, "NavTalents", "Talents", accent, btnStroke, 5)
mkNavBtn(navPanel, "NavAchievements", "Achievements", Color3.fromRGB(255, 200, 60), Color3.fromRGB(160, 120, 30), 6)
mkNavBtn(navPanel, "NavSocial", "Social", accent, btnStroke, 7)
mkNavBtn(navPanel, "NavShop", "🛒 Shop", Color3.fromRGB(255, 210, 60), Color3.fromRGB(160, 130, 30), 8)
mkNavBtn(navPanel, "NavSettings", "⚙ Settings", Color3.fromRGB(180, 180, 180), btnStroke, 9)
mkNavBtn(navPanel, "NavInventory", "🎺 Inventory", accent, btnStroke, 10)
mkNavBtn(navPanel, "NavLeaderboard", "🏆 Leaderboard", Color3.fromRGB(255, 200, 60), Color3.fromRGB(160, 130, 30), 11)
mkNavBtn(navPanel, "NavDailyLogin", "📅 Daily Login", Color3.fromRGB(100, 220, 120), Color3.fromRGB(40, 140, 60), 12)


-- ═══════════════════════════════════════════════════════════
-- CLASS MENU  (overlay)
-- ═══════════════════════════════════════════════════════════

local cmBackdrop, cmPanel = mkOverlayPanel(root, "ClassMenu", 0.88, 0.82, "Classes", 10)

-- 4 category columns
local cmColumns = mk("Frame", {
	Name = "Columns",
	Position = UDim2.fromScale(0, 0.10),
	Size = UDim2.fromScale(1, 0.88),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, cmPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.006, 0),
}, cmColumns)

local CLASS_COLUMNS = { "Melee", "Ranged", "Magic", "Support" }

for ci, catName in ipairs(CLASS_COLUMNS) do
	local col = mk("Frame", {
		Name = "Col_" .. catName,
		Size = UDim2.fromScale(0.244, 0.98),
		BackgroundColor3 = Color3.fromRGB(24, 24, 33),
		BorderSizePixel = 0,
		LayoutOrder = ci,
		ZIndex = 12,
	}, cmColumns)

	-- Header
	local colHeader = mk("Frame", {
		Name = "Header",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 0.095),
		BackgroundColor3 = Color3.fromRGB(30, 30, 44),
		BorderSizePixel = 0,
		ZIndex = 12,
	}, col)
	mk("TextLabel", {
		Name = "HeaderLabel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = catName,
		TextColor3 = Color3.fromRGB(105, 190, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 12,
	}, colHeader)

	-- 4 class slots per column
	for si = 1, 4 do
		local yPos = 0.110 + (si - 1) * 0.225
		local slot = mk("Frame", {
			Name = "Slot_" .. si,
			Position = UDim2.fromScale(0.04, yPos),
			Size = UDim2.fromScale(0.92, 0.205),
			BackgroundColor3 = Color3.fromRGB(40, 40, 55),
			BorderSizePixel = 0,
			ZIndex = 12,
		}, col)
		mk("UICorner", { CornerRadius = UDim.new(0.05, 0) }, slot)

		mk("TextLabel", {
			Name = "ClassName",
			Position = UDim2.fromScale(0.05, 0.06),
			Size = UDim2.fromScale(0.90, 0.32),
			BackgroundTransparency = 1,
			Text = catName .. " Class " .. si,
			TextColor3 = Color3.fromRGB(225, 225, 230),
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 12,
		}, slot)

		mk("TextLabel", {
			Name = "Desc",
			Position = UDim2.fromScale(0.05, 0.38),
			Size = UDim2.fromScale(0.90, 0.27),
			BackgroundTransparency = 1,
			Text = "Class description",
			TextColor3 = Color3.fromRGB(140, 140, 160),
			Font = Enum.Font.Gotham,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 12,
		}, slot)

		local slotBtn = mk("TextButton", {
			Name = "SwitchBtn",
			Position = UDim2.fromScale(0.40, 0.67),
			Size = UDim2.fromScale(0.55, 0.27),
			BackgroundColor3 = Color3.fromRGB(60, 135, 235),
			BorderSizePixel = 0,
			Text = "Switch",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			ZIndex = 12,
		}, slot)
		mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, slotBtn)
	end
end

-- Toast
mk("TextLabel", {
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.97),
	Size = UDim2.fromScale(0.55, 0.065),
	BackgroundColor3 = Color3.fromRGB(28, 28, 44),
	BackgroundTransparency = 0.10,
	BorderSizePixel = 0,
	Text = "",
	TextColor3 = Color3.fromRGB(220, 220, 230),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	Visible = false,
	ZIndex = 12,
}, cmPanel)


-- ═══════════════════════════════════════════════════════════
-- STATS MENU  (overlay)
-- ═══════════════════════════════════════════════════════════

local smBackdrop, smPanel = mkOverlayPanel(root, "StatsMenu", 0.72, 0.78, "Stats  —  Lv. 1", 10)

-- Points badge
local ptsBadge = mk("Frame", {
	Name = "PointsBadge",
	Position = UDim2.fromScale(0.03, 0.11),
	Size = UDim2.fromScale(0.34, 0.07),
	BackgroundColor3 = Color3.fromRGB(38, 32, 12),
	BorderSizePixel = 0,
	ZIndex = 12,
}, smPanel)
mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, ptsBadge)
mk("TextLabel", {
	Name = "PointsLabel",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "★  Unallocated:  0",
	TextColor3 = Color3.fromRGB(245, 195, 60),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 12,
}, ptsBadge)

-- Respec button
local respecBtn = mk("TextButton", {
	Name = "RespecBtn",
	Position = UDim2.fromScale(0.39, 0.11),
	Size = UDim2.fromScale(0.28, 0.07),
	BackgroundColor3 = Color3.fromRGB(140, 50, 50),
	BorderSizePixel = 0,
	Text = "Respec  (Token / 500 ♦)",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 12,
}, smPanel)
mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, respecBtn)

-- Left panel: primary stats
local smLeft = mk("Frame", {
	Name = "PrimaryStats",
	Position = UDim2.fromScale(0.03, 0.20),
	Size = UDim2.fromScale(0.56, 0.76),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, smPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.012, 0),
}, smLeft)

local STATS = {
	{ "MIG", "Might", "Damage / Armor" },
	{ "VIT", "Vitality", "Max Health" },
	{ "PRE", "Precision", "Penetration / Crit Chance" },
	{ "MAG", "Magic", "Magic Damage / Resource" },
	{ "RSV", "Resolve", "CDR / Status Resist" },
}

for i, s in ipairs(STATS) do
	local row = mk("Frame", {
		Name = "Row_" .. s[1],
		Size = UDim2.fromScale(1, 0.115),
		BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(30, 30, 44) or Color3.fromRGB(26, 26, 38),
		BorderSizePixel = 0,
		LayoutOrder = i,
		ZIndex = 12,
	}, smLeft)
	mk("UICorner", { CornerRadius = UDim.new(0.08, 0) }, row)

	mk("TextLabel", {
		Name = "StatId",
		Position = UDim2.fromScale(0.02, 0),
		Size = UDim2.fromScale(0.12, 1),
		BackgroundTransparency = 1,
		Text = s[1],
		TextColor3 = Color3.fromRGB(105, 190, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	}, row)

	mk("TextLabel", {
		Name = "StatName",
		Position = UDim2.fromScale(0.15, 0),
		Size = UDim2.fromScale(0.25, 0.55),
		BackgroundTransparency = 1,
		Text = s[2],
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	}, row)

	mk("TextLabel", {
		Name = "Affects",
		Position = UDim2.fromScale(0.15, 0.52),
		Size = UDim2.fromScale(0.42, 0.48),
		BackgroundTransparency = 1,
		Text = s[3],
		TextColor3 = Color3.fromRGB(140, 140, 160),
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	}, row)

	mk("TextLabel", {
		Name = "AllocatedCount",
		Position = UDim2.fromScale(0.60, 0),
		Size = UDim2.fromScale(0.24, 1),
		BackgroundTransparency = 1,
		Text = "0",
		TextColor3 = Color3.fromRGB(105, 190, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 12,
	}, row)

	local addBtn = mk("TextButton", {
		Name = "AddBtn",
		Position = UDim2.fromScale(0.86, 0.15),
		Size = UDim2.fromScale(0.10, 0.70),
		BackgroundColor3 = Color3.fromRGB(45, 140, 80),
		BorderSizePixel = 0,
		Text = "+",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 12,
	}, row)
	mk("UICorner", { CornerRadius = UDim.new(0.2, 0) }, addBtn)
end

-- Right panel: derived stats
local smRight = mk("Frame", {
	Name = "DerivedStats",
	Position = UDim2.fromScale(0.62, 0.20),
	Size = UDim2.fromScale(0.35, 0.76),
	BackgroundColor3 = Color3.fromRGB(26, 26, 38),
	BorderSizePixel = 0,
	ZIndex = 12,
}, smPanel)
mk("UICorner", { CornerRadius = UDim.new(0.03, 0) }, smRight)

mk("TextLabel", {
	Name = "DerivedHeader",
	Position = UDim2.fromScale(0, 0),
	Size = UDim2.fromScale(1, 0.08),
	BackgroundTransparency = 1,
	Text = "Derived Stats",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 12,
}, smRight)

local smDRows = mk("Frame", {
	Name = "Rows",
	Position = UDim2.fromScale(0.03, 0.09),
	Size = UDim2.fromScale(0.94, 0.88),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, smRight)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.010, 0),
}, smDRows)

local DERIVED = { "Max HP", "Damage", "Armor", "Penetration", "Crit Chance", "Crit Damage", "CDR", "Status Resistance" }
for i, name in ipairs(DERIVED) do
	local drow = mk("Frame", {
		Name = "Derived_" .. i,
		Size = UDim2.fromScale(1, 0.10),
		BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(30, 30, 44) or Color3.fromRGB(26, 26, 38),
		BorderSizePixel = 0,
		LayoutOrder = i,
		ZIndex = 12,
	}, smDRows)
	mk("UICorner", { CornerRadius = UDim.new(0.1, 0) }, drow)

	mk("TextLabel", {
		Name = "Label",
		Position = UDim2.fromScale(0.04, 0),
		Size = UDim2.fromScale(0.58, 1),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = Color3.fromRGB(140, 140, 160),
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	}, drow)

	mk("TextLabel", {
		Name = "Value",
		Position = UDim2.fromScale(0.62, 0),
		Size = UDim2.fromScale(0.38, 1),
		BackgroundTransparency = 1,
		Text = "—",
		TextColor3 = Color3.fromRGB(105, 190, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 12,
	}, drow)
end


-- ═══════════════════════════════════════════════════════════
-- EQUIPMENT UI  (overlay)
-- ═══════════════════════════════════════════════════════════

local eqBackdrop, eqPanel = mkOverlayPanel(root, "EquipmentUI", 0.82, 0.83, "Equipment", 10, 0.5, 0.5, 0.44, 0.52)
eqPanel.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
eqPanel.BackgroundTransparency = 0.05

-- Two columns: Weapon (left) and Armor (right)
local eqLayout = mk("Frame", {
	Name = "CardLayout",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.54),
	Size = UDim2.fromScale(0.94, 0.85),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, eqPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0.03, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, eqLayout)

local function mkEquipCard(parent, cardName, title, accentColor, order)
	local card = mk("Frame", {
		Name = cardName,
		Size = UDim2.fromScale(0.44, 0.85),
		BackgroundColor3 = Color3.fromRGB(28, 28, 42),
		BorderSizePixel = 0,
		LayoutOrder = order,
		ZIndex = 12,
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0.02, 0) }, card)
	mk("UIStroke", { Color = accentColor, Thickness = 1.5, Transparency = 0.5 }, card)
	mk("UIPadding", {
		PaddingLeft = UDim.new(0.04, 0),
		PaddingRight = UDim.new(0.04, 0),
		PaddingTop = UDim.new(0.03, 0),
		PaddingBottom = UDim.new(0.03, 0),
	}, card)

	local scroll = mk("ScrollingFrame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 12,
	}, card)

	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 3),
	}, scroll)

	mk("TextLabel", {
		Name = "Title",
		Size = UDim2.fromScale(1, 0.05),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = accentColor,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		LayoutOrder = 0,
		ZIndex = 12,
	}, scroll)

	mk("TextLabel", {
		Name = "ItemName",
		Size = UDim2.fromScale(1, 0.04),
		BackgroundTransparency = 1,
		Text = "None",
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		LayoutOrder = 1,
		ZIndex = 12,
	}, scroll)

	-- XP bar placeholder
	local xpBar = mk("Frame", {
		Name = "XPBar",
		Size = UDim2.fromScale(1, 0.04),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		ZIndex = 12,
	}, scroll)
	mk("TextLabel", {
		Name = "LevelLabel",
		Size = UDim2.fromScale(0.30, 1),
		BackgroundTransparency = 1,
		Text = "Lv 1/50",
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	}, xpBar)
	local xpTrack = mk("Frame", {
		Name = "Track",
		Position = UDim2.fromScale(0.32, 0.20),
		Size = UDim2.fromScale(0.45, 0.60),
		BackgroundColor3 = Color3.fromRGB(35, 35, 50),
		BorderSizePixel = 0,
		ZIndex = 12,
	}, xpBar)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, xpTrack)
	local xpFill = mk("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(210, 150, 40),
		BorderSizePixel = 0,
		ZIndex = 12,
	}, xpTrack)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, xpFill)

	-- Stat lines placeholder
	for _, statInfo in ipairs({ { "Attack", 3 }, { "ATK Speed", 4 }, { "Refinement", 5 }, { "Tier", 6 } }) do
		local sl = mk("Frame", {
			Name = "Stat_" .. statInfo[1]:gsub(" ", ""),
			Size = UDim2.fromScale(1, 0.035),
			BackgroundTransparency = 1,
			LayoutOrder = statInfo[2] + 5,
			ZIndex = 12,
		}, scroll)
		mk("TextLabel", {
			Name = "Label",
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(0.55, 1),
			BackgroundTransparency = 1,
			Text = statInfo[1],
			TextColor3 = Color3.fromRGB(140, 140, 160),
			Font = Enum.Font.Gotham,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 12,
		}, sl)
		mk("TextLabel", {
			Name = "Value",
			Position = UDim2.fromScale(0.55, 0),
			Size = UDim2.fromScale(0.45, 1),
			BackgroundTransparency = 1,
			Text = "—",
			TextColor3 = Color3.fromRGB(220, 220, 230),
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 12,
		}, sl)
	end

	return card
end

mkEquipCard(eqLayout, "WeaponCard", "⚔  Weapon", Color3.fromRGB(255, 120, 80), 1)
mkEquipCard(eqLayout, "ArmorCard", "🛡  Armor", Color3.fromRGB(80, 180, 255), 2)


-- ═══════════════════════════════════════════════════════════
-- TALENT TREE  (fullscreen overlay, matches TalentTreeUI.lua)
-- ═══════════════════════════════════════════════════════════
-- Structure:
--   TalentTreeBackdrop (fullscreen, bg=12,12,18)
--     Header (1 × 7%)  → Title | PointsLabel | RespecBtn | CloseBtn
--     TalentCanvas     → populated at runtime by AppGuiWiring
--     Legend           (bottom-left 18% × 8%)
--     Tooltip          (centre-bottom 30% × 16%, Visible=false until hover)

local ttBackdrop = mk("Frame", {
	Name = "TalentTreeBackdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(12, 12, 18),
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	ZIndex = 10,
	Visible = false,
}, root)

-- ── Header bar ────────────────────────────────────────────
local ttHeader = mk("Frame", {
	Name = "Header",
	Size = UDim2.fromScale(1, 0.07),
	BackgroundColor3 = Color3.fromRGB(18, 18, 26),
	BorderSizePixel = 0,
	ZIndex = 12,
}, ttBackdrop)

-- Title (left)
mk("TextLabel", {
	Name = "Title",
	Position = UDim2.fromScale(0.02, 0),
	Size = UDim2.fromScale(0.30, 1),
	BackgroundTransparency = 1,
	Text = "Talent Tree",
	TextColor3 = Color3.fromRGB(220, 220, 230),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 13,
}, ttHeader)

-- Points counter (centre)
mk("TextLabel", {
	Name = "PointsLabel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.30, 0.7),
	BackgroundTransparency = 1,
	Text = "Points: 0 / 0   (Available: 0)",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 13,
}, ttHeader)

-- Respec button
local ttRespecBtn = mk("TextButton", {
	Name = "RespecBtn",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(0.88, 0.5),
	Size = UDim2.fromScale(0.16, 0.65),
	BackgroundColor3 = Color3.fromRGB(140, 50, 50),
	BorderSizePixel = 0,
	Text = "Respec  (Token / 500 \xe2\x99\xa6)",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 13,
}, ttHeader)
mk("UICorner", { CornerRadius = UDim.new(0.25, 0) }, ttRespecBtn)
mk("UIStroke", { Color = Color3.fromRGB(60, 100, 180), Thickness = 1 }, ttRespecBtn)

-- Close button (far right)
local ttCloseBtn = mk("TextButton", {
	Name = "CloseBtn",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(0.995, 0.5),
	Size = UDim2.fromScale(0.04, 0.65),
	BackgroundColor3 = Color3.fromRGB(180, 50, 50),
	BorderSizePixel = 0,
	Text = "\xe2\x9c\x95",
	TextColor3 = Color3.fromRGB(220, 220, 230),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 13,
}, ttHeader)
mk("UICorner", { CornerRadius = UDim.new(0.25, 0) }, ttCloseBtn)

-- ── Canvas (nodes + edges populated at runtime) ───────────
local ttCanvas = mk("Frame", {
	Name = "TalentCanvas",
	Position = UDim2.fromScale(0, 0.07),
	Size = UDim2.fromScale(1, 0.93),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 11,
}, ttBackdrop)

-- ── Legend (bottom-left) ──────────────────────────────────
local ttLegend = mk("Frame", {
	Name = "Legend",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0.01, 0.98),
	Size = UDim2.fromScale(0.18, 0.08),
	BackgroundColor3 = Color3.fromRGB(18, 18, 26),
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	ZIndex = 15,
}, ttBackdrop)
mk("UICorner", { CornerRadius = UDim.new(0.15, 0) }, ttLegend)
mk("UIPadding", { PaddingLeft = UDim.new(0.03, 0), PaddingRight = UDim.new(0.03, 0) }, ttLegend)
mk("TextLabel", {
	Name = "LegendLabel",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "Click = Allocate  |  Drag background = Pan",
	TextColor3 = Color3.fromRGB(140, 140, 160),
	Font = Enum.Font.Gotham,
	TextScaled = true,
	ZIndex = 16,
}, ttLegend)

-- ── Tooltip template (shown on node hover) ────────────────
local ttTooltip = mk("Frame", {
	Name = "Tooltip",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.82),
	Size = UDim2.fromScale(0.30, 0.16),
	BackgroundColor3 = Color3.fromRGB(22, 22, 32),
	BorderSizePixel = 0,
	ZIndex = 20,
	Visible = false,
}, ttBackdrop)
mk("UICorner", { CornerRadius = UDim.new(0.04, 0) }, ttTooltip)
mk("UIStroke", { Color = Color3.fromRGB(60, 100, 180), Thickness = 1 }, ttTooltip)
mk("UIPadding", {
	PaddingLeft = UDim.new(0.02, 0), PaddingRight = UDim.new(0.02, 0),
	PaddingTop = UDim.new(0.05, 0), PaddingBottom = UDim.new(0.05, 0),
}, ttTooltip)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.02, 0),
}, ttTooltip)
mk("TextLabel", { Name = "NameLabel",
	Size = UDim2.fromScale(1, 0.28), BackgroundTransparency = 1, Text = "",
	TextColor3 = Color3.fromRGB(220, 220, 230), Font = Enum.Font.GothamBold,
	TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder = 1, ZIndex = 21,
}, ttTooltip)
mk("TextLabel", { Name = "DescLabel",
	Size = UDim2.fromScale(1, 0.30), BackgroundTransparency = 1, Text = "",
	TextColor3 = Color3.fromRGB(140, 140, 160), Font = Enum.Font.Gotham,
	TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
	LayoutOrder = 2, ZIndex = 21,
}, ttTooltip)
mk("TextLabel", { Name = "EffectsLabel",
	Size = UDim2.fromScale(1, 0.25), BackgroundTransparency = 1, Text = "",
	TextColor3 = Color3.fromRGB(80, 210, 120), Font = Enum.Font.GothamBold,
	TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
	LayoutOrder = 3, ZIndex = 21,
}, ttTooltip)
mk("TextLabel", { Name = "CostLabel",
	Size = UDim2.fromScale(1, 0.15), BackgroundTransparency = 1, Text = "",
	TextColor3 = Color3.fromRGB(140, 140, 160), Font = Enum.Font.Gotham,
	TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder = 4, ZIndex = 21,
}, ttTooltip)


-- ═══════════════════════════════════════════════════════════
-- WARDROBE UI  (overlay)
-- ═══════════════════════════════════════════════════════════

local wdBackdrop = mk("Frame", {
	Name = "WardrobeBackdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 20,
	Visible = false,
}, root)

mk("Frame", {
	Name = "Overlay",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.35,
	ZIndex = 20,
}, wdBackdrop)

local wdPanel = mk("Frame", {
	Name = "WardrobePanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.55, 0.65),
	BackgroundColor3 = Color3.fromRGB(18, 18, 26),
	BorderSizePixel = 0,
	ZIndex = 21,
}, wdBackdrop)
mk("UICorner", { CornerRadius = UDim.new(0.011, 0) }, wdPanel)

mk("TextLabel", {
	Name = "Title",
	Position = UDim2.fromScale(0.008, 0.015),
	Size = UDim2.fromScale(0.47, 0.06),
	BackgroundTransparency = 1,
	Text = "Wardrobe",
	TextColor3 = Color3.fromRGB(220, 220, 235),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 22,
}, wdPanel)

local wdClose = mk("TextButton", {
	Name = "CloseBtn",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.99, 0.015),
	Size = UDim2.fromScale(0.019, 0.033),
	BackgroundColor3 = Color3.fromRGB(180, 50, 50),
	BorderSizePixel = 0,
	Text = "X",
	TextColor3 = Color3.fromRGB(220, 220, 235),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 22,
}, wdPanel)
mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, wdClose)

-- Tab bar
local wdTabs = mk("Frame", {
	Name = "TabBar",
	Position = UDim2.fromScale(0.008, 0.085),
	Size = UDim2.fromScale(0.984, 0.055),
	BackgroundTransparency = 1,
	ZIndex = 22,
}, wdPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0.008, 0),
}, wdTabs)

for ti, tabName in ipairs({ "Headgear", "Outfit" }) do
	local tab = mk("TextButton", {
		Name = "Tab_" .. tabName,
		Size = UDim2.fromScale(0.48, 1),
		BackgroundColor3 = ti == 1 and Color3.fromRGB(60, 60, 90) or Color3.fromRGB(28, 28, 42),
		BorderSizePixel = 0,
		Text = tabName,
		TextColor3 = ti == 1 and Color3.fromRGB(105, 190, 255) or Color3.fromRGB(140, 140, 160),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		LayoutOrder = ti,
		ZIndex = 22,
	}, wdTabs)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, tab)
end

-- Unequip button
local wdUnequip = mk("TextButton", {
	Name = "UnequipBtn",
	Position = UDim2.fromScale(0.008, 0.155),
	Size = UDim2.fromScale(0.063, 0.04),
	BackgroundColor3 = Color3.fromRGB(120, 80, 60),
	BorderSizePixel = 0,
	Text = "Unequip",
	TextColor3 = Color3.fromRGB(220, 220, 235),
	Font = Enum.Font.Gotham,
	TextScaled = true,
	ZIndex = 22,
}, wdPanel)
mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, wdUnequip)

-- Card grid scroll
local wdScroll = mk("ScrollingFrame", {
	Name = "CardScroll",
	Position = UDim2.fromScale(0.008, 0.21),
	Size = UDim2.fromScale(0.984, 0.77),
	BackgroundTransparency = 1,
	ScrollBarThickness = 4,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromScale(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 22,
}, wdPanel)

mk("UIGridLayout", {
	CellSize = UDim2.fromScale(0.22, 0.18),
	CellPadding = UDim2.fromScale(0.01, 0.01),
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, wdScroll)

-- Placeholder cosmetic cards
for ci = 1, 6 do
	local cCard = mk("TextButton", {
		Name = "CosmeticCard_" .. ci,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(32, 32, 48),
		BorderSizePixel = 0,
		Text = "",
		LayoutOrder = ci,
		ZIndex = 22,
	}, wdScroll)
	mk("UICorner", { CornerRadius = UDim.new(0.08, 0) }, cCard)
	mk("UIStroke", { Color = Color3.fromRGB(180, 180, 180), Thickness = 1 }, cCard)
	mk("TextLabel", {
		Name = "CardName",
		Position = UDim2.fromScale(0.04, 0.05),
		Size = UDim2.fromScale(0.92, 0.30),
		BackgroundTransparency = 1,
		Text = "Cosmetic " .. ci,
		TextColor3 = Color3.fromRGB(220, 220, 235),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	}, cCard)
end


-- ═══════════════════════════════════════════════════════════
-- ACHIEVEMENTS UI  (overlay)
-- ═══════════════════════════════════════════════════════════

local achBackdrop, achPanel = mkOverlayPanel(root, "AchievementsUI", 0.72, 0.88, "🏆  Achievements", 8)
achPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 22)

-- Category sidebar (left)
local achSidebar = mk("Frame", {
	Name = "CategorySidebar",
	Position = UDim2.fromScale(0.02, 0.11),
	Size = UDim2.fromScale(0.20, 0.86),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, achPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.008, 0),
}, achSidebar)

local ACH_CATEGORIES = { "Combat", "Progression", "Collection", "Social", "Exploration" }
for i, cat in ipairs(ACH_CATEGORIES) do
	local catBtn = mk("TextButton", {
		Name = "Cat_" .. cat,
		Size = UDim2.fromScale(1, 0.05),
		BackgroundColor3 = i == 1 and Color3.fromRGB(50, 80, 160) or Color3.fromRGB(28, 28, 42),
		BorderSizePixel = 0,
		Text = cat,
		TextColor3 = i == 1 and Color3.fromRGB(220, 220, 230) or Color3.fromRGB(130, 130, 150),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		LayoutOrder = i,
		ZIndex = 10,
	}, achSidebar)
	mk("UICorner", { CornerRadius = UDim.new(0.25, 0) }, catBtn)
end

-- Card scroll area (right)
local achScroll = mk("ScrollingFrame", {
	Name = "CardScroll",
	Position = UDim2.fromScale(0.24, 0.11),
	Size = UDim2.fromScale(0.74, 0.86),
	BackgroundTransparency = 1,
	ScrollBarThickness = 4,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromScale(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 10,
}, achPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 4),
}, achScroll)

-- Placeholder achievement cards
for ai = 1, 5 do
	local aCard = mk("Frame", {
		Name = "AchCard_" .. ai,
		Size = UDim2.fromScale(1, 0.12),
		BackgroundColor3 = Color3.fromRGB(30, 30, 46),
		BorderSizePixel = 0,
		LayoutOrder = ai,
		ZIndex = 10,
	}, achScroll)
	mk("UICorner", { CornerRadius = UDim.new(0.05, 0) }, aCard)

	mk("TextLabel", {
		Name = "Icon",
		Position = UDim2.fromScale(0.01, 0.06),
		Size = UDim2.fromScale(0.12, 0.55),
		BackgroundTransparency = 1,
		Text = "🏅",
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 10,
	}, aCard)

	mk("TextLabel", {
		Name = "Name",
		Position = UDim2.fromScale(0.14, 0.05),
		Size = UDim2.fromScale(0.62, 0.32),
		BackgroundTransparency = 1,
		Text = "Achievement " .. ai,
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 10,
	}, aCard)

	mk("TextLabel", {
		Name = "Desc",
		Position = UDim2.fromScale(0.14, 0.38),
		Size = UDim2.fromScale(0.84, 0.22),
		BackgroundTransparency = 1,
		Text = "Achievement description",
		TextColor3 = Color3.fromRGB(130, 130, 150),
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 10,
	}, aCard)

	-- Progress bar
	local aPBg = mk("Frame", {
		Name = "BarBg",
		Position = UDim2.fromScale(0.13, 0.65),
		Size = UDim2.fromScale(0.84, 0.20),
		BackgroundColor3 = Color3.fromRGB(22, 22, 34),
		BorderSizePixel = 0,
		ZIndex = 10,
	}, aCard)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, aPBg)
	local aPFill = mk("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.4, 1),
		BackgroundColor3 = Color3.fromRGB(80, 160, 255),
		BorderSizePixel = 0,
		ZIndex = 10,
	}, aPBg)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, aPFill)
end

-- Achievement Toast (always visible, bottom-right)
local achToast = mk("Frame", {
	Name = "AchievementToast",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.fromScale(0.98, 0.95),
	Size = UDim2.fromScale(0.22, 0.07),
	BackgroundColor3 = Color3.fromRGB(24, 24, 36),
	BorderSizePixel = 0,
	ZIndex = 30,
	Visible = false,
}, root)
mk("UICorner", { CornerRadius = UDim.new(0.15, 0) }, achToast)
mk("UIStroke", { Color = Color3.fromRGB(255, 200, 60), Thickness = 2 }, achToast)
mk("TextLabel", {
	Name = "ToastText",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "🏆 Achievement Unlocked!",
	TextColor3 = Color3.fromRGB(255, 200, 60),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 30,
}, achToast)


-- ═══════════════════════════════════════════════════════════
-- SETTINGS UI  (overlay)
-- ═══════════════════════════════════════════════════════════

local setBackdrop, setPanel = mkOverlayPanel(root, "SettingsUI", 0.48, 0.68, "⚙  Settings", 10)

-- 3 tabs
local setTabs = mk("Frame", {
	Name = "TabBar",
	Position = UDim2.fromScale(0.03, 0.11),
	Size = UDim2.fromScale(0.94, 0.07),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, setPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.01, 0),
}, setTabs)

for ti, tabName in ipairs({ "Audio", "Skills", "Controls" }) do
	local sTab = mk("TextButton", {
		Name = "Tab_" .. tabName,
		Size = UDim2.fromScale(0.32, 1),
		BackgroundColor3 = ti == 1 and Color3.fromRGB(50, 80, 160) or Color3.fromRGB(28, 28, 42),
		BorderSizePixel = 0,
		Text = tabName,
		TextColor3 = ti == 1 and Color3.fromRGB(220, 220, 230) or Color3.fromRGB(130, 130, 150),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		LayoutOrder = ti,
		ZIndex = 12,
	}, setTabs)
	mk("UICorner", { CornerRadius = UDim.new(0.25, 0) }, sTab)
end

-- Content area
local setContent = mk("ScrollingFrame", {
	Name = "Content",
	Position = UDim2.fromScale(0.03, 0.20),
	Size = UDim2.fromScale(0.94, 0.76),
	BackgroundTransparency = 1,
	ScrollBarThickness = 4,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromScale(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 12,
}, setPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.008, 0),
}, setContent)

-- Placeholder setting rows
local SETTING_ROWS = { "Music Volume", "SFX Volume", "UI Volume", "Master Volume", "Auto-Aim", "Show Damage Numbers", "Camera Sensitivity" }
for si, name in ipairs(SETTING_ROWS) do
	local sRow = mk("Frame", {
		Name = "Setting_" .. si,
		Size = UDim2.fromScale(1, 0.065),
		BackgroundColor3 = (si % 2 == 0) and Color3.fromRGB(30, 30, 44) or Color3.fromRGB(26, 26, 38),
		BorderSizePixel = 0,
		LayoutOrder = si,
		ZIndex = 12,
	}, setContent)
	mk("UICorner", { CornerRadius = UDim.new(0.12, 0) }, sRow)

	mk("TextLabel", {
		Name = "SettingName",
		Position = UDim2.fromScale(0.03, 0),
		Size = UDim2.fromScale(0.50, 1),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	}, sRow)

	-- Slider track placeholder
	local sTrack = mk("Frame", {
		Name = "SliderTrack",
		Position = UDim2.fromScale(0.55, 0.30),
		Size = UDim2.fromScale(0.40, 0.40),
		BackgroundColor3 = Color3.fromRGB(40, 40, 60),
		BorderSizePixel = 0,
		ZIndex = 12,
	}, sRow)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, sTrack)
	local sFill = mk("Frame", {
		Name = "SliderFill",
		Size = UDim2.fromScale(0.7, 1),
		BackgroundColor3 = Color3.fromRGB(80, 160, 255),
		BorderSizePixel = 0,
		ZIndex = 12,
	}, sTrack)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, sFill)
end


-- ═══════════════════════════════════════════════════════════
-- GLOBAL SHOP UI  (overlay)
-- ═══════════════════════════════════════════════════════════

local gsBackdrop, gsPanel = mkOverlayPanel(root, "GlobalShop", 0.55, 0.75, "🛒  Shop", 10)

-- 3 tabs
local gsTabs = mk("Frame", {
	Name = "TabBar",
	Position = UDim2.fromScale(0.03, 0.11),
	Size = UDim2.fromScale(0.94, 0.07),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, gsPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.01, 0),
}, gsTabs)

for ti, tabName in ipairs({ "Cosmetics", "Consumables", "Premium" }) do
	local gsTab = mk("TextButton", {
		Name = "Tab_" .. tabName,
		Size = UDim2.fromScale(0.32, 1),
		BackgroundColor3 = ti == 1 and Color3.fromRGB(60, 80, 120) or Color3.fromRGB(28, 28, 42),
		BorderSizePixel = 0,
		Text = tabName,
		TextColor3 = ti == 1 and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(130, 130, 150),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		LayoutOrder = ti,
		ZIndex = 12,
	}, gsTabs)
	mk("UICorner", { CornerRadius = UDim.new(0.25, 0) }, gsTab)
end

-- Grid area
local gsScroll = mk("ScrollingFrame", {
	Name = "ItemGrid",
	Position = UDim2.fromScale(0.03, 0.20),
	Size = UDim2.fromScale(0.94, 0.76),
	BackgroundTransparency = 1,
	ScrollBarThickness = 4,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromScale(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 12,
}, gsPanel)

mk("UIGridLayout", {
	CellSize = UDim2.fromScale(0.30, 0.22),
	CellPadding = UDim2.fromScale(0.02, 0.02),
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, gsScroll)

-- Placeholder shop items
for si = 1, 6 do
	local gsCard = mk("Frame", {
		Name = "ShopItem_" .. si,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(30, 30, 46),
		BorderSizePixel = 0,
		LayoutOrder = si,
		ZIndex = 12,
	}, gsScroll)
	mk("UICorner", { CornerRadius = UDim.new(0.06, 0) }, gsCard)

	mk("TextLabel", {
		Name = "ItemName",
		Position = UDim2.fromScale(0.04, 0.04),
		Size = UDim2.fromScale(0.92, 0.25),
		BackgroundTransparency = 1,
		Text = "Item " .. si,
		TextColor3 = Color3.fromRGB(105, 190, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	}, gsCard)

	mk("TextLabel", {
		Name = "Price",
		Position = UDim2.fromScale(0.04, 0.70),
		Size = UDim2.fromScale(0.5, 0.22),
		BackgroundTransparency = 1,
		Text = "500 ♦",
		TextColor3 = Color3.fromRGB(255, 200, 60),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	}, gsCard)

	local buyBtn = mk("TextButton", {
		Name = "BuyBtn",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.96, 0.92),
		Size = UDim2.fromScale(0.35, 0.25),
		BackgroundColor3 = Color3.fromRGB(50, 170, 80),
		BorderSizePixel = 0,
		Text = "Buy",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 12,
	}, gsCard)
	mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, buyBtn)
end


-- ═══════════════════════════════════════════════════════════
-- CHARACTER CREATION  (overlay)
-- ═══════════════════════════════════════════════════════════

local ccBackdrop = mk("Frame", {
	Name = "CharCreationBackdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.35,
	ZIndex = 10,
	Visible = false,
}, root)

local ccPanel = mk("Frame", {
	Name = "CharCreationPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.25, 0.389),
	BackgroundColor3 = Color3.fromRGB(18, 18, 26),
	BorderSizePixel = 0,
	ZIndex = 11,
}, ccBackdrop)
mk("UICorner", { CornerRadius = UDim.new(0.04, 0) }, ccPanel)

mk("TextLabel", {
	Name = "Title",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.03),
	Size = UDim2.fromScale(0.80, 0.10),
	BackgroundTransparency = 1,
	Text = "Create Character",
	TextColor3 = Color3.fromRGB(220, 220, 230),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 12,
}, ccPanel)

-- Gender buttons
mk("TextLabel", {
	Name = "GenderLabel",
	Position = UDim2.fromScale(0.06, 0.16),
	Size = UDim2.fromScale(0.88, 0.08),
	BackgroundTransparency = 1,
	Text = "Gender",
	TextColor3 = Color3.fromRGB(140, 140, 160),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 12,
}, ccPanel)

local genderRow = mk("Frame", {
	Name = "GenderRow",
	Position = UDim2.fromScale(0.06, 0.26),
	Size = UDim2.fromScale(0.88, 0.12),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, ccPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.03, 0),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, genderRow)

for gi, gender in ipairs({ "Male", "Female" }) do
	local gBtn = mk("TextButton", {
		Name = "Gender_" .. gender,
		Size = UDim2.fromScale(0.40, 1),
		BackgroundColor3 = gi == 1 and Color3.fromRGB(60, 135, 235) or Color3.fromRGB(40, 40, 58),
		BorderSizePixel = 0,
		Text = gender,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		LayoutOrder = gi,
		ZIndex = 12,
	}, genderRow)
	mk("UICorner", { CornerRadius = UDim.new(0.35, 0) }, gBtn)
end

-- Skin color label + palette
mk("TextLabel", {
	Name = "SkinLabel",
	Position = UDim2.fromScale(0.06, 0.42),
	Size = UDim2.fromScale(0.88, 0.08),
	BackgroundTransparency = 1,
	Text = "Skin Tone",
	TextColor3 = Color3.fromRGB(140, 140, 160),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 12,
}, ccPanel)

local skinGrid = mk("Frame", {
	Name = "SkinGrid",
	Position = UDim2.fromScale(0.06, 0.52),
	Size = UDim2.fromScale(0.88, 0.22),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, ccPanel)

mk("UIGridLayout", {
	CellSize = UDim2.fromScale(0.12, 0.45),
	CellPadding = UDim2.fromScale(0.02, 0.05),
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, skinGrid)

local SKIN_TONES = {
	Color3.fromRGB(255, 224, 189),
	Color3.fromRGB(234, 192, 134),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(100, 60, 28),
	Color3.fromRGB(66, 39, 16),
}

for si, color in ipairs(SKIN_TONES) do
	local skinBtn = mk("TextButton", {
		Name = "Skin_" .. si,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Text = "",
		LayoutOrder = si,
		ZIndex = 12,
	}, skinGrid)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, skinBtn)
end

-- Confirm button
local ccConfirm = mk("TextButton", {
	Name = "ConfirmBtn",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.94),
	Size = UDim2.fromScale(0.65, 0.11),
	BackgroundColor3 = Color3.fromRGB(50, 160, 70),
	BorderSizePixel = 0,
	Text = "Confirm",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 12,
}, ccPanel)
mk("UICorner", { CornerRadius = UDim.new(0.35, 0) }, ccConfirm)


-- ═══════════════════════════════════════════════════════════
-- EMOTE WHEEL  (overlay)
-- ═══════════════════════════════════════════════════════════

local emoteBackdrop = mk("Frame", {
	Name = "EmoteWheelBackdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 30,
	Visible = false,
}, root)

local emoteWheel = mk("Frame", {
	Name = "EmoteWheel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.121, 0.215),
	BackgroundColor3 = Color3.fromRGB(18, 18, 28),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	ZIndex = 31,
}, emoteBackdrop)
mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, emoteWheel)
mk("UIStroke", { Color = Color3.fromRGB(80, 80, 120), Thickness = 2, Transparency = 0.3 }, emoteWheel)

-- 4 emote slots (NSEW)
local EMOTE_POS = {
	{ name = "Top", x = 0.5, y = 0.12, label = "Wave" },
	{ name = "Right", x = 0.82, y = 0.5, label = "Dance" },
	{ name = "Bottom", x = 0.5, y = 0.88, label = "Sit" },
	{ name = "Left", x = 0.18, y = 0.5, label = "Laugh" },
}

for _, e in ipairs(EMOTE_POS) do
	local eBtn = mk("TextButton", {
		Name = "Emote_" .. e.name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(e.x, e.y),
		Size = UDim2.fromScale(0.32, 0.24),
		BackgroundColor3 = Color3.fromRGB(40, 40, 60),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Text = e.label,
		TextColor3 = Color3.fromRGB(220, 220, 235),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 32,
	}, emoteWheel)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, eBtn)
end

-- Centre "Q" hint
mk("TextLabel", {
	Name = "QHint",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.25, 0.18),
	BackgroundTransparency = 1,
	Text = "Q",
	TextColor3 = Color3.fromRGB(100, 100, 130),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 32,
}, emoteWheel)


-- ═══════════════════════════════════════════════════════════
-- DEATH UI  (overlay, fullscreen)
-- ═══════════════════════════════════════════════════════════

local deathUI = mk("Frame", {
	Name = "DeathUI",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(40, 10, 10),
	BackgroundTransparency = 0.50,
	ZIndex = 100,
	Visible = false,
}, root)

mk("TextLabel", {
	Name = "DeathTitle",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.40),
	Size = UDim2.fromScale(0.30, 0.08),
	BackgroundTransparency = 1,
	Text = "YOU DIED",
	TextColor3 = Color3.fromRGB(255, 80, 80),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 101,
}, deathUI)

mk("TextLabel", {
	Name = "DeathSubtitle",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.50),
	Size = UDim2.fromScale(0.25, 0.05),
	BackgroundTransparency = 1,
	Text = "Respawning...",
	TextColor3 = Color3.fromRGB(200, 160, 160),
	Font = Enum.Font.Gotham,
	TextScaled = true,
	ZIndex = 101,
}, deathUI)


-- ═══════════════════════════════════════════════════════════
-- TEAMMATE VITALS  (right edge)
-- ═══════════════════════════════════════════════════════════

local tmVitals = mk("Frame", {
	Name = "TeammateVitals",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.996, 0.111),
	Size = UDim2.fromScale(0.099, 0.35),
	BackgroundTransparency = 1,
	Visible = false,
}, root)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.02, 0),
}, tmVitals)

-- Placeholder teammate rows
for ti = 1, 4 do
	local tmRow = mk("Frame", {
		Name = "Teammate_" .. ti,
		Size = UDim2.fromScale(1, 0.15),
		BackgroundColor3 = Color3.fromRGB(22, 22, 32),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		LayoutOrder = ti,
	}, tmVitals)
	mk("UICorner", { CornerRadius = UDim.new(0.15, 0) }, tmRow)

	mk("TextLabel", {
		Name = "PlayerName",
		Position = UDim2.fromScale(0.04, 0.05),
		Size = UDim2.fromScale(0.92, 0.40),
		BackgroundTransparency = 1,
		Text = "Player " .. ti,
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, tmRow)

	local tmBar = mk("Frame", {
		Name = "HPTrack",
		Position = UDim2.fromScale(0.04, 0.55),
		Size = UDim2.fromScale(0.92, 0.30),
		BackgroundColor3 = Color3.fromRGB(35, 35, 50),
		BorderSizePixel = 0,
	}, tmRow)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, tmBar)
	local tmFill = mk("Frame", {
		Name = "HPFill",
		Size = UDim2.fromScale(0.7, 1),
		BackgroundColor3 = Color3.fromRGB(80, 210, 90),
		BorderSizePixel = 0,
	}, tmBar)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, tmFill)
end


-- ═══════════════════════════════════════════════════════════
-- VOTE UI  (overlay)
-- ═══════════════════════════════════════════════════════════

local voteBackdrop = mk("Frame", {
	Name = "VoteUIBackdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 50,
	Visible = false,
}, root)

local votePanel = mk("Frame", {
	Name = "VotePanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.fromScale(0.72, 0.38),
	BackgroundTransparency = 1,
	ZIndex = 51,
}, voteBackdrop)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.02, 0),
}, votePanel)

for vi = 1, 3 do
	local vCard = mk("Frame", {
		Name = "VoteCard_" .. vi,
		Size = UDim2.fromScale(0.30, 0.90),
		BackgroundColor3 = Color3.fromRGB(26, 26, 38),
		BorderSizePixel = 0,
		LayoutOrder = vi,
		ZIndex = 52,
	}, votePanel)
	mk("UICorner", { CornerRadius = UDim.new(0.06, 0) }, vCard)
	mk("UIStroke", { Color = Color3.fromRGB(60, 60, 90), Thickness = 1 }, vCard)

	mk("TextLabel", {
		Name = "OptionTitle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.05),
		Size = UDim2.fromScale(0.90, 0.20),
		BackgroundTransparency = 1,
		Text = "Option " .. vi,
		TextColor3 = Color3.fromRGB(105, 190, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 52,
	}, vCard)

	local vBtn = mk("TextButton", {
		Name = "VoteBtn",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.92),
		Size = UDim2.fromScale(0.70, 0.18),
		BackgroundColor3 = Color3.fromRGB(50, 170, 80),
		BorderSizePixel = 0,
		Text = "Vote",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 52,
	}, vCard)
	mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, vBtn)
end


-- ═══════════════════════════════════════════════════════════
-- MAIN MENU  (lobby-specific overlay)
-- ═══════════════════════════════════════════════════════════

local mmBackdrop = mk("Frame", {
	Name = "MainMenuBackdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(10, 10, 16),
	BackgroundTransparency = 0.15,
	ZIndex = 10,
	Visible = false,
}, root)

mk("TextLabel", {
	Name = "Title",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.06),
	Size = UDim2.fromScale(0.3, 0.08),
	BackgroundTransparency = 1,
	Text = "Game Modes",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 11,
}, mmBackdrop)

local mmClose = mk("TextButton", {
	Name = "CloseBtn",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.96, 0.03),
	Size = UDim2.fromScale(0.06, 0.06),
	BackgroundColor3 = Color3.fromRGB(180, 50, 50),
	BorderSizePixel = 0,
	Text = "X",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 11,
}, mmBackdrop)
mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, mmClose)

local mmContainer = mk("Frame", {
	Name = "CardContainer",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.fromScale(0.62, 0.84),
	BackgroundTransparency = 1,
	ZIndex = 11,
}, mmBackdrop)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.01, 0),
}, mmContainer)

local GAME_MODES = {
	{ "Defense", "Defend the line against waves.", true },
	{ "Central Boss", "Collaborate to take down a central boss.", true },
	{ "Horde Mode", "Survive endless waves of enemies.", true },
	{ "Arena", "PvP Arena — Coming soon.", false },
	{ "Raid", "Cooperative boss raids — Coming soon.", false },
	{ "Exploration", "Open-world zones — Coming soon.", false },
}

for mi, mode in ipairs(GAME_MODES) do
	local modeWrap = mk("Frame", {
		Name = "Mode_" .. mi,
		Size = UDim2.fromScale(1, 0.145),
		BackgroundTransparency = 1,
		LayoutOrder = mi,
		ZIndex = 11,
	}, mmContainer)

	local modeCard = mk("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = mode[3] and Color3.fromRGB(26, 26, 38) or Color3.fromRGB(20, 20, 28),
		BorderSizePixel = 0,
		ZIndex = 11,
	}, modeWrap)
	mk("UICorner", { CornerRadius = UDim.new(0.08, 0) }, modeCard)

	if mode[3] then
		mk("UIStroke", { Color = Color3.fromRGB(105, 190, 255), Thickness = 1 }, modeCard)
	end

	mk("UIPadding", {
		PaddingLeft = UDim.new(0.04, 0),
		PaddingRight = UDim.new(0.04, 0),
		PaddingTop = UDim.new(0.04, 0),
		PaddingBottom = UDim.new(0.04, 0),
	}, modeCard)

	mk("TextLabel", {
		Name = "ModeName",
		Size = UDim2.fromScale(0.50, 0.35),
		BackgroundTransparency = 1,
		Text = mode[1],
		TextColor3 = mode[3] and Color3.fromRGB(220, 220, 230) or Color3.fromRGB(70, 70, 90),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
	}, modeCard)

	mk("TextLabel", {
		Name = "ModeDesc",
		Position = UDim2.fromScale(0, 0.35),
		Size = UDim2.fromScale(0.50, 0.25),
		BackgroundTransparency = 1,
		Text = mode[2],
		TextColor3 = mode[3] and Color3.fromRGB(100, 100, 120) or Color3.fromRGB(70, 70, 90),
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ZIndex = 11,
	}, modeCard)

	if mode[3] then
		-- Difficulty picker row
		local diffRow = mk("Frame", {
			Name = "DifficultyRow",
			Position = UDim2.fromScale(0, 0.65),
			Size = UDim2.fromScale(0.60, 0.32),
			BackgroundTransparency = 1,
			ZIndex = 11,
		}, modeCard)

		mk("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0.02, 0),
		}, diffRow)

		local DIFFS = {
			{ "Normal", Color3.fromRGB(50, 180, 80), true },
			{ "Hard", Color3.fromRGB(220, 150, 40), false },
			{ "Nightmare", Color3.fromRGB(160, 60, 200), false },
		}

		for di, diff in ipairs(DIFFS) do
			local dBtn = mk("TextButton", {
				Name = "Diff_" .. diff[1],
				Size = UDim2.fromScale(0.30, 0.85),
				BackgroundColor3 = diff[3] and diff[2] or Color3.fromRGB(20, 20, 28),
				BorderSizePixel = 0,
				Text = diff[1],
				TextColor3 = diff[3] and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(100, 100, 120),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				LayoutOrder = di,
				ZIndex = 11,
			}, diffRow)
			mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, dBtn)
		end

		-- Play button
		local playBtn = mk("TextButton", {
			Name = "PlayBtn",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromScale(0.22, 0.55),
			BackgroundColor3 = Color3.fromRGB(50, 180, 80),
			BorderSizePixel = 0,
			Text = "Play",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			ZIndex = 11,
		}, modeCard)
		mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, playBtn)
	else
		mk("TextLabel", {
			Name = "LockedLabel",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromScale(0.24, 0.5),
			BackgroundTransparency = 1,
			Text = "Locked",
			TextColor3 = Color3.fromRGB(70, 70, 90),
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			ZIndex = 11,
		}, modeCard)
	end
end


-- ═══════════════════════════════════════════════════════════
-- MATCHMAKING UI  (self-managing bar)
-- ═══════════════════════════════════════════════════════════

local mmkBar = mk("Frame", {
	Name = "MatchmakingUI",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.03),
	Size = UDim2.fromScale(0.38, 0.065),
	BackgroundColor3 = Color3.fromRGB(18, 18, 24),
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	ZIndex = 25,
	Visible = false,
}, root)
mk("UICorner", { CornerRadius = UDim.new(0.25, 0) }, mmkBar)

mk("TextLabel", {
	Name = "StatusLabel",
	Position = UDim2.fromScale(0.04, 0),
	Size = UDim2.fromScale(0.62, 1),
	BackgroundTransparency = 1,
	Text = "Queued for Defense…",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 25,
}, mmkBar)

local mmkCancel = mk("TextButton", {
	Name = "CancelBtn",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(0.96, 0.5),
	Size = UDim2.fromScale(0.26, 0.65),
	BackgroundColor3 = Color3.fromRGB(170, 50, 50),
	BorderSizePixel = 0,
	Text = "Cancel",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 25,
}, mmkBar)
mk("UICorner", { CornerRadius = UDim.new(0.35, 0) }, mmkCancel)


-- ═══════════════════════════════════════════════════════════
-- SOCIAL PANEL  (lobby overlay)
-- ═══════════════════════════════════════════════════════════

local spBackdrop, spPanel = mkOverlayPanel(root, "SocialPanel", 0.88, 0.82, "Social  —  Party", 10)
spPanel.BackgroundColor3 = Color3.fromRGB(18, 18, 24)

-- Tab bar
local spTabBar = mk("Frame", {
	Name = "TabBar",
	Position = UDim2.fromScale(0.03, 0.01),
	Size = UDim2.fromScale(0.40, 0.06),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, spPanel)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.01, 0),
}, spTabBar)

for ti, tabName in ipairs({ "Party", "Guild" }) do
	local spTab = mk("TextButton", {
		Name = "Tab_" .. tabName,
		Size = UDim2.fromScale(0.18, 1),
		BackgroundColor3 = ti == 1 and Color3.fromRGB(35, 35, 52) or Color3.fromRGB(22, 22, 32),
		BorderSizePixel = 0,
		Text = tabName,
		TextColor3 = ti == 1 and Color3.fromRGB(105, 190, 255) or Color3.fromRGB(140, 140, 160),
		Font = ti == 1 and Enum.Font.GothamBold or Enum.Font.Gotham,
		TextScaled = true,
		LayoutOrder = ti,
		ZIndex = 12,
	}, spTabBar)
	mk("UICorner", { CornerRadius = UDim.new(0.35, 0) }, spTab)
end

-- Left panel: Player browser (40% width)
local spLeft = mk("Frame", {
	Name = "PlayerBrowser",
	Position = UDim2.fromScale(0.02, 0.12),
	Size = UDim2.fromScale(0.38, 0.85),
	BackgroundColor3 = Color3.fromRGB(24, 24, 33),
	BorderSizePixel = 0,
	ZIndex = 12,
}, spPanel)
mk("UICorner", { CornerRadius = UDim.new(0.02, 0) }, spLeft)

mk("TextLabel", {
	Name = "BrowserTitle",
	Position = UDim2.fromScale(0.03, 0.01),
	Size = UDim2.fromScale(0.94, 0.06),
	BackgroundTransparency = 1,
	Text = "Players in Lobby",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 12,
}, spLeft)

local spBrowserScroll = mk("ScrollingFrame", {
	Name = "PlayerScroll",
	Position = UDim2.fromScale(0.02, 0.08),
	Size = UDim2.fromScale(0.96, 0.90),
	BackgroundTransparency = 1,
	ScrollBarThickness = 4,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromScale(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 12,
}, spLeft)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.005, 0),
}, spBrowserScroll)

-- Placeholder player rows
for pi = 1, 5 do
	local pRow = mk("Frame", {
		Name = "PlayerRow_" .. pi,
		Size = UDim2.fromScale(1, 0.065),
		BackgroundColor3 = Color3.fromRGB(30, 30, 44),
		BorderSizePixel = 0,
		LayoutOrder = pi,
		ZIndex = 12,
	}, spBrowserScroll)
	mk("UICorner", { CornerRadius = UDim.new(0.2, 0) }, pRow)

	mk("TextLabel", {
		Name = "Name",
		Position = UDim2.fromScale(0.03, 0.12),
		Size = UDim2.fromScale(0.62, 0.76),
		BackgroundTransparency = 1,
		Text = "Player " .. pi,
		TextColor3 = Color3.fromRGB(225, 225, 230),
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	}, pRow)

	local invBtn = mk("TextButton", {
		Name = "InviteBtn",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.97, 0.5),
		Size = UDim2.fromScale(0.30, 0.70),
		BackgroundColor3 = Color3.fromRGB(60, 135, 235),
		BorderSizePixel = 0,
		Text = "Invite",
		TextColor3 = Color3.fromRGB(225, 225, 230),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 12,
	}, pRow)
	mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, invBtn)
end

-- Right panel: Party roster (60% width)
local spRight = mk("Frame", {
	Name = "PartyRoster",
	Position = UDim2.fromScale(0.42, 0.12),
	Size = UDim2.fromScale(0.56, 0.85),
	BackgroundColor3 = Color3.fromRGB(24, 24, 33),
	BorderSizePixel = 0,
	ZIndex = 12,
}, spPanel)
mk("UICorner", { CornerRadius = UDim.new(0.02, 0) }, spRight)

mk("TextLabel", {
	Name = "RosterTitle",
	Position = UDim2.fromScale(0.03, 0.01),
	Size = UDim2.fromScale(0.94, 0.06),
	BackgroundTransparency = 1,
	Text = "Your Party (0/5)",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 12,
}, spRight)

-- Create Party button
local createPartyBtn = mk("TextButton", {
	Name = "CreatePartyBtn",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.40, 0.08),
	BackgroundColor3 = Color3.fromRGB(45, 175, 95),
	BorderSizePixel = 0,
	Text = "Create Party",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 12,
}, spRight)
mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, createPartyBtn)

-- Bonus XP bar at bottom
mk("Frame", {
	Name = "BonusXPBar",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0.02, 0.98),
	Size = UDim2.fromScale(0.96, 0.07),
	BackgroundColor3 = Color3.fromRGB(18, 30, 48),
	BorderSizePixel = 0,
	ZIndex = 12,
}, spRight)


-- ═══════════════════════════════════════════════════════════
-- NPC DIALOG  (self-managing overlay)
-- ═══════════════════════════════════════════════════════════

local npcBackdrop = mk("Frame", {
	Name = "NPCDialogBackdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.50,
	BorderSizePixel = 0,
	ZIndex = 15,
	Visible = false,
}, root)

local npcPanel = mk("Frame", {
	Name = "NPCDialogPanel",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.92),
	Size = UDim2.fromScale(0.45, 0.35),
	BackgroundColor3 = Color3.fromRGB(22, 22, 30),
	BorderSizePixel = 0,
	ZIndex = 16,
}, npcBackdrop)
mk("UICorner", { CornerRadius = UDim.new(0.03, 0) }, npcPanel)

mk("TextLabel", {
	Name = "SpeakerName",
	Position = UDim2.fromScale(0.04, 0.03),
	Size = UDim2.fromScale(0.70, 0.12),
	BackgroundTransparency = 1,
	Text = "NPC Name",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 17,
}, npcPanel)

local npcClose = mk("TextButton", {
	Name = "CloseBtn",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.97, 0.03),
	Size = UDim2.fromScale(0.05, 0.10),
	BackgroundTransparency = 1,
	Text = "✕",
	TextColor3 = Color3.fromRGB(140, 140, 160),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 17,
}, npcPanel)

mk("TextLabel", {
	Name = "DialogText",
	Position = UDim2.fromScale(0.04, 0.18),
	Size = UDim2.fromScale(0.92, 0.40),
	BackgroundTransparency = 1,
	Text = "Hello, traveler! How can I help you?",
	TextColor3 = Color3.fromRGB(220, 220, 230),
	Font = Enum.Font.Gotham,
	TextScaled = true,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 17,
}, npcPanel)

-- Choices area
local npcChoices = mk("Frame", {
	Name = "Choices",
	Position = UDim2.fromScale(0.04, 0.60),
	Size = UDim2.fromScale(0.92, 0.36),
	BackgroundTransparency = 1,
	ZIndex = 17,
}, npcPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.02, 0),
}, npcChoices)

for ci = 1, 3 do
	local choiceBtn = mk("TextButton", {
		Name = "Choice_" .. ci,
		Size = UDim2.fromScale(1, 0.28),
		BackgroundColor3 = Color3.fromRGB(38, 38, 54),
		BorderSizePixel = 0,
		Text = "Choice " .. ci,
		TextColor3 = Color3.fromRGB(105, 190, 255),
		Font = Enum.Font.Gotham,
		TextScaled = true,
		LayoutOrder = ci,
		ZIndex = 17,
	}, npcChoices)
	mk("UICorner", { CornerRadius = UDim.new(0.2, 0) }, choiceBtn)
end


-- ═══════════════════════════════════════════════════════════
-- NPC SHOP UI  (self-managing overlay)
-- ═══════════════════════════════════════════════════════════

local shopBackdrop = mk("Frame", {
	Name = "ShopUIBackdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	ZIndex = 20,
	Visible = false,
}, root)

local shopPanel = mk("Frame", {
	Name = "ShopUIPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.50, 0.55),
	BackgroundColor3 = Color3.fromRGB(22, 22, 30),
	BorderSizePixel = 0,
	ZIndex = 21,
}, shopBackdrop)
mk("UICorner", { CornerRadius = UDim.new(0.02, 0) }, shopPanel)
mk("UIPadding", {
	PaddingLeft = UDim.new(0.03, 0),
	PaddingRight = UDim.new(0.03, 0),
	PaddingTop = UDim.new(0.03, 0),
	PaddingBottom = UDim.new(0.03, 0),
}, shopPanel)

mk("TextLabel", {
	Name = "ShopHeader",
	Size = UDim2.fromScale(0.80, 0.10),
	BackgroundTransparency = 1,
	Text = "Shop",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 22,
}, shopPanel)

local shopClose = mk("TextButton", {
	Name = "CloseBtn",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromScale(0.06, 0.08),
	BackgroundTransparency = 1,
	Text = "✕",
	TextColor3 = Color3.fromRGB(140, 140, 160),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 22,
}, shopPanel)

local shopGrid = mk("ScrollingFrame", {
	Name = "ItemGrid",
	Position = UDim2.fromScale(0, 0.13),
	Size = UDim2.fromScale(1, 0.85),
	BackgroundTransparency = 1,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.fromScale(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	BorderSizePixel = 0,
	ZIndex = 22,
}, shopPanel)

mk("UIGridLayout", {
	CellSize = UDim2.fromScale(0.46, 0.3),
	CellPadding = UDim2.fromScale(0.04, 0.04),
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	FillDirectionMaxCells = 2,
}, shopGrid)

for si = 1, 4 do
	local sCard = mk("Frame", {
		Name = "ShopCard_" .. si,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(32, 32, 46),
		BorderSizePixel = 0,
		LayoutOrder = si,
		ZIndex = 22,
	}, shopGrid)
	mk("UICorner", { CornerRadius = UDim.new(0.06, 0) }, sCard)

	mk("TextLabel", {
		Name = "ItemName",
		Position = UDim2.fromScale(0.04, 0.06),
		Size = UDim2.fromScale(0.70, 0.25),
		BackgroundTransparency = 1,
		Text = "Item " .. si,
		TextColor3 = Color3.fromRGB(105, 190, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	}, sCard)

	mk("TextLabel", {
		Name = "Price",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.96, 0.06),
		Size = UDim2.fromScale(0.28, 0.22),
		BackgroundTransparency = 1,
		Text = "100 Essence",
		TextColor3 = Color3.fromRGB(255, 210, 60),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 22,
	}, sCard)

	local sBuyBtn = mk("TextButton", {
		Name = "BuyBtn",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.96, 0.92),
		Size = UDim2.fromScale(0.28, 0.25),
		BackgroundColor3 = Color3.fromRGB(50, 170, 80),
		BorderSizePixel = 0,
		Text = "Buy",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 22,
	}, sCard)
	mk("UICorner", { CornerRadius = UDim.new(0.25, 0) }, sBuyBtn)
end


-- ═══════════════════════════════════════════════════════════
-- WEAPON SMITH UI  (self-managing overlay)
-- ═══════════════════════════════════════════════════════════

local wsBackdrop, wsPanel = mkOverlayPanel(root, "WeaponSmith", 0.55, 0.60, "⚒  Weapon Smith", 20)

-- Two columns: Weapon (left), Armor (right)
local wsLayout = mk("Frame", {
	Name = "UpgradeLayout",
	Position = UDim2.fromScale(0.03, 0.14),
	Size = UDim2.fromScale(0.94, 0.82),
	BackgroundTransparency = 1,
	ZIndex = 22,
}, wsPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.02, 0),
}, wsLayout)

for wi, wpType in ipairs({ "Weapon", "Armor" }) do
	local wsCol = mk("Frame", {
		Name = wpType .. "Col",
		Size = UDim2.fromScale(0.47, 0.95),
		BackgroundColor3 = Color3.fromRGB(24, 24, 36),
		BorderSizePixel = 0,
		LayoutOrder = wi,
		ZIndex = 22,
	}, wsLayout)
	mk("UICorner", { CornerRadius = UDim.new(0.03, 0) }, wsCol)

	mk("TextLabel", {
		Name = "ColTitle",
		Position = UDim2.fromScale(0.04, 0.02),
		Size = UDim2.fromScale(0.92, 0.08),
		BackgroundTransparency = 1,
		Text = wpType,
		TextColor3 = wi == 1 and Color3.fromRGB(255, 120, 80) or Color3.fromRGB(80, 180, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	}, wsCol)

	local upgradeBtn = mk("TextButton", {
		Name = "UpgradeBtn",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.95),
		Size = UDim2.fromScale(0.80, 0.10),
		BackgroundColor3 = Color3.fromRGB(60, 135, 235),
		BorderSizePixel = 0,
		Text = "Upgrade",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 22,
	}, wsCol)
	mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, upgradeBtn)
end


-- ═══════════════════════════════════════════════════════════
-- DAILY LOGIN UI  (overlay)
-- ═══════════════════════════════════════════════════════════

local dlBackdrop, dlPanel = mkOverlayPanel(root, "DailyLogin", 0.38, 0.46, "📅  Daily Login", 10)

-- Override title color
dlPanel:FindFirstChild("Title").TextColor3 = Color3.fromRGB(255, 200, 60)

mk("TextLabel", {
	Name = "StreakLabel",
	Position = UDim2.fromScale(0.05, 0.22),
	Size = UDim2.fromScale(0.90, 0.13),
	BackgroundTransparency = 1,
	Text = "Day 1  ·  Total days: 1",
	TextColor3 = Color3.fromRGB(220, 220, 230),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 12,
}, dlPanel)

mk("TextLabel", {
	Name = "RewardCaption",
	Position = UDim2.fromScale(0.05, 0.38),
	Size = UDim2.fromScale(0.90, 0.09),
	BackgroundTransparency = 1,
	Text = "Today's reward:",
	TextColor3 = Color3.fromRGB(140, 140, 160),
	Font = Enum.Font.Gotham,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 12,
}, dlPanel)

mk("TextLabel", {
	Name = "RewardValue",
	Position = UDim2.fromScale(0.05, 0.47),
	Size = UDim2.fromScale(0.90, 0.12),
	BackgroundTransparency = 1,
	Text = "100 Essence",
	TextColor3 = Color3.fromRGB(255, 200, 60),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 12,
}, dlPanel)

local dlClaim = mk("TextButton", {
	Name = "ClaimBtn",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.94),
	Size = UDim2.fromScale(0.55, 0.14),
	BackgroundColor3 = Color3.fromRGB(50, 170, 80),
	BorderSizePixel = 0,
	Text = "Claim Reward",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 12,
}, dlPanel)
mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, dlClaim)


-- ═══════════════════════════════════════════════════════════
-- LEADERBOARD UI  (overlay)
-- ═══════════════════════════════════════════════════════════

local lbBackdrop, lbPanel = mkOverlayPanel(root, "Leaderboard", 0.50, 0.72, "🏆  Leaderboard", 10)
lbPanel.BackgroundColor3 = Color3.fromRGB(18, 18, 24)

-- Override title color
lbPanel:FindFirstChild("Title").TextColor3 = Color3.fromRGB(255, 200, 60)

-- Tab bar
local lbTabs = mk("Frame", {
	Name = "TabBar",
	Position = UDim2.fromScale(0.04, 0.11),
	Size = UDim2.fromScale(0.92, 0.07),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, lbPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.01, 0),
}, lbTabs)

for ti, tabName in ipairs({ "GearScore", "HighestWave", "TotalPlayTime" }) do
	local lbTab = mk("TextButton", {
		Name = "Tab_" .. tabName,
		Size = UDim2.fromScale(0.32, 1),
		BackgroundColor3 = ti == 1 and Color3.fromRGB(60, 80, 120) or Color3.fromRGB(30, 30, 42),
		BorderSizePixel = 0,
		Text = tabName,
		TextColor3 = ti == 1 and Color3.fromRGB(80, 160, 255) or Color3.fromRGB(140, 140, 160),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		LayoutOrder = ti,
		ZIndex = 12,
	}, lbTabs)
	mk("UICorner", { CornerRadius = UDim.new(0.15, 0) }, lbTab)
end

-- List
local lbScroll = mk("ScrollingFrame", {
	Name = "ListFrame",
	Position = UDim2.fromScale(0.04, 0.20),
	Size = UDim2.fromScale(0.92, 0.69),
	BackgroundTransparency = 1,
	ScrollBarThickness = 4,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromScale(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 12,
}, lbPanel)

mk("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 3),
}, lbScroll)

for li = 1, 10 do
	local lRow = mk("Frame", {
		Name = "Row_" .. li,
		Size = UDim2.fromScale(1, 0.065),
		BackgroundColor3 = Color3.fromRGB(32, 32, 46),
		BorderSizePixel = 0,
		LayoutOrder = li,
		ZIndex = 12,
	}, lbScroll)
	mk("UICorner", { CornerRadius = UDim.new(0.08, 0) }, lRow)

	mk("TextLabel", {
		Name = "Rank",
		Position = UDim2.fromScale(0.01, 0),
		Size = UDim2.fromScale(0.10, 1),
		BackgroundTransparency = 1,
		Text = "#" .. li,
		TextColor3 = li <= 3 and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(140, 140, 160),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 12,
	}, lRow)

	mk("TextLabel", {
		Name = "PlayerName",
		Position = UDim2.fromScale(0.13, 0),
		Size = UDim2.fromScale(0.62, 1),
		BackgroundTransparency = 1,
		Text = "Player " .. li,
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	}, lRow)

	mk("TextLabel", {
		Name = "Score",
		Position = UDim2.fromScale(0.76, 0),
		Size = UDim2.fromScale(0.22, 1),
		BackgroundTransparency = 1,
		Text = "0",
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 12,
	}, lRow)
end

-- My score label
mk("TextLabel", {
	Name = "MyScoreLabel",
	Position = UDim2.fromScale(0.04, 0.91),
	Size = UDim2.fromScale(0.92, 0.06),
	BackgroundTransparency = 1,
	Text = "Your Gear Score: 0",
	TextColor3 = Color3.fromRGB(80, 160, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 12,
}, lbPanel)


-- ═══════════════════════════════════════════════════════════
-- INVENTORY UI  (overlay)
-- ═══════════════════════════════════════════════════════════

local invBackdrop, invPanel = mkOverlayPanel(root, "Inventory", 0.50, 0.70, "🎒  Inventory", 10)

-- Override title color
invPanel:FindFirstChild("Title").TextColor3 = Color3.fromRGB(255, 200, 60)

mk("TextLabel", {
	Name = "EquippedBar",
	Position = UDim2.fromScale(0.04, 0.12),
	Size = UDim2.fromScale(0.92, 0.07),
	BackgroundTransparency = 1,
	Text = "Equipped: None",
	TextColor3 = Color3.fromRGB(80, 160, 255),
	Font = Enum.Font.Gotham,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 12,
}, invPanel)

local invScroll = mk("ScrollingFrame", {
	Name = "ListFrame",
	Position = UDim2.fromScale(0.04, 0.21),
	Size = UDim2.fromScale(0.92, 0.76),
	BackgroundTransparency = 1,
	ScrollBarThickness = 4,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromScale(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 12,
}, invPanel)

mk("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 4),
}, invScroll)

for ii = 1, 5 do
	local iRow = mk("Frame", {
		Name = "Item_" .. ii,
		Size = UDim2.fromScale(1, 0.09),
		BackgroundColor3 = Color3.fromRGB(32, 32, 46),
		BorderSizePixel = 0,
		LayoutOrder = ii,
		ZIndex = 12,
	}, invScroll)
	mk("UICorner", { CornerRadius = UDim.new(0.06, 0) }, iRow)

	mk("TextLabel", {
		Name = "ItemName",
		Position = UDim2.fromScale(0.02, 0.10),
		Size = UDim2.fromScale(0.40, 0.45),
		BackgroundTransparency = 1,
		Text = "Accessory " .. ii,
		TextColor3 = Color3.fromRGB(220, 220, 230),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	}, iRow)

	local iBtn = mk("TextButton", {
		Name = "ActionBtn",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.98, 0.5),
		Size = UDim2.fromScale(0.24, 0.72),
		BackgroundColor3 = Color3.fromRGB(50, 170, 80),
		BorderSizePixel = 0,
		Text = "Equip",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		ZIndex = 12,
	}, iRow)
	mk("UICorner", { CornerRadius = UDim.new(0.2, 0) }, iBtn)
end


-- ═══════════════════════════════════════════════════════════
-- PARTY INVITE TOAST  (always mounted, bottom-centre)
-- ═══════════════════════════════════════════════════════════

local piToast = mk("Frame", {
	Name = "PartyInviteToast",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.96),
	Size = UDim2.fromScale(0.34, 0.10),
	BackgroundColor3 = Color3.fromRGB(22, 22, 36),
	BorderSizePixel = 0,
	ZIndex = 30,
	Visible = false,
}, root)
mk("UICorner", { CornerRadius = UDim.new(0.15, 0) }, piToast)
mk("UIStroke", { Color = Color3.fromRGB(60, 100, 180), Thickness = 1.5 }, piToast)

mk("TextLabel", {
	Name = "InviteText",
	Position = UDim2.fromScale(0.04, 0.05),
	Size = UDim2.fromScale(0.92, 0.35),
	BackgroundTransparency = 1,
	Text = "Player invited you to a party!",
	TextColor3 = Color3.fromRGB(220, 220, 230),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 30,
}, piToast)

local piAccept = mk("TextButton", {
	Name = "AcceptBtn",
	Position = UDim2.fromScale(0.04, 0.50),
	Size = UDim2.fromScale(0.28, 0.40),
	BackgroundColor3 = Color3.fromRGB(45, 175, 95),
	BorderSizePixel = 0,
	Text = "Accept",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 30,
}, piToast)
mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, piAccept)

local piDecline = mk("TextButton", {
	Name = "DeclineBtn",
	Position = UDim2.fromScale(0.36, 0.50),
	Size = UDim2.fromScale(0.28, 0.40),
	BackgroundColor3 = Color3.fromRGB(170, 50, 50),
	BorderSizePixel = 0,
	Text = "Decline",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 30,
}, piToast)
mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, piDecline)

local piDismiss = mk("TextButton", {
	Name = "DismissBtn",
	Position = UDim2.fromScale(0.68, 0.50),
	Size = UDim2.fromScale(0.28, 0.40),
	BackgroundColor3 = Color3.fromRGB(58, 58, 78),
	BorderSizePixel = 0,
	Text = "Dismiss",
	TextColor3 = Color3.fromRGB(220, 220, 230),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 30,
}, piToast)
mk("UICorner", { CornerRadius = UDim.new(0.3, 0) }, piDismiss)


-- ═══════════════════════════════════════════════════════════
-- BATTLE CLASS UI  (top-left info badge)
-- ═══════════════════════════════════════════════════════════

local bcBadge = mk("Frame", {
	Name = "BattleClassUI",
	Position = UDim2.fromScale(0.003, 0.065),
	Size = UDim2.fromScale(0.09, 0.04),
	BackgroundColor3 = Color3.fromRGB(22, 22, 36),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Visible = false,
}, root)
mk("UICorner", { CornerRadius = UDim.new(0.25, 0) }, bcBadge)
mk("UIStroke", { Color = Color3.fromRGB(60, 80, 160), Thickness = 1 }, bcBadge)

mk("TextLabel", {
	Name = "ClassName",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "Aegis",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
}, bcBadge)


-- ═══════════════════════════════════════════════════════════
-- TESTING UI  (admin-only debug panel)
-- ═══════════════════════════════════════════════════════════

local testUI = mk("Frame", {
	Name = "TestingUI",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 100,
	Visible = false,
}, root)

-- Toggle button
local testToggle = mk("TextButton", {
	Name = "ToggleBtn",
	Position = UDim2.fromScale(0.003, 0.005),
	Size = UDim2.fromScale(0.028, 0.037),
	BackgroundColor3 = Color3.fromRGB(200, 150, 20),
	BorderSizePixel = 0,
	Text = "🧪",
	TextColor3 = Color3.fromRGB(14, 14, 20),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	ZIndex = 101,
}, testUI)
mk("UICorner", { CornerRadius = UDim.new(0.2, 0) }, testToggle)

-- Panel
local testPanel = mk("ScrollingFrame", {
	Name = "Panel",
	Position = UDim2.fromScale(0.005, 0.05),
	Size = UDim2.fromScale(0.193, 0.72),
	BackgroundColor3 = Color3.fromRGB(22, 22, 32),
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.fromScale(0, 0),
	ZIndex = 102,
	Visible = false,
}, testUI)
mk("UIStroke", { Color = Color3.fromRGB(60, 60, 90), Thickness = 1 }, testPanel)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 2),
}, testPanel)

mk("TextLabel", {
	Name = "PanelTitle",
	Size = UDim2.fromScale(1, 0.035),
	BackgroundTransparency = 1,
	Text = "🧪 Test Panel",
	TextColor3 = Color3.fromRGB(200, 150, 20),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	LayoutOrder = 0,
	ZIndex = 102,
}, testPanel)


-- ═══════════════════════════════════════════════════════════
-- APPEARANCE BAR  (Social Plaza specific)
-- ═══════════════════════════════════════════════════════════

local appBar = mk("Frame", {
	Name = "AppearanceBar",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.fromScale(0.99, 0.97),
	Size = UDim2.fromScale(0.12, 0.08),
	BackgroundTransparency = 1,
	Visible = false,
}, root)

mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.015, 0),
}, appBar)

local wdBarBtn = mk("TextButton", {
	Name = "WardrobeBtn",
	Size = UDim2.fromScale(0.45, 0.80),
	BackgroundColor3 = Color3.fromRGB(35, 35, 52),
	BorderSizePixel = 0,
	Text = "👕",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	LayoutOrder = 1,
}, appBar)
mk("UICorner", { CornerRadius = UDim.new(0.2, 0) }, wdBarBtn)
mk("UIStroke", { Color = Color3.fromRGB(60, 100, 180), Thickness = 1.5 }, wdBarBtn)

local emBarBtn = mk("TextButton", {
	Name = "EmoteHint",
	Size = UDim2.fromScale(0.45, 0.80),
	BackgroundColor3 = Color3.fromRGB(35, 35, 52),
	BorderSizePixel = 0,
	Text = "Q",
	TextColor3 = Color3.fromRGB(105, 190, 255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	LayoutOrder = 2,
}, appBar)
mk("UICorner", { CornerRadius = UDim.new(0.2, 0) }, emBarBtn)
mk("UIStroke", { Color = Color3.fromRGB(60, 100, 180), Thickness = 1.5 }, emBarBtn)


-- ═══════════════════════════════════════════════════════════
-- WIRING  — LocalScript embedded inside AppGui
-- Runs client-side automatically when AppGui loads.
-- All Activated signals require client context; this is why
-- we embed a LocalScript rather than wiring here directly.
-- ═══════════════════════════════════════════════════════════

local wiringScript = Instance.new("LocalScript")
wiringScript.Name  = "AppGuiWiring"
wiringScript.Source = [==[
-- AppGuiWiring  ·  auto-generated by generate_ui.lua
-- Connects every button in AppGui to its panel / action.

local UIS  = game:GetService("UserInputService")
local gui  = script.Parent          -- ScreenGui "AppGui"
local root = gui:WaitForChild("AppRoot")

-- ── Helpers ───────────────────────────────────────────────

-- WaitForChild chain: w(root, "HUD", "MenuBtn")
local function w(p, ...)
	for _, n in ipairs({...}) do p = p:WaitForChild(n, 10) end
	return p
end

-- Highlight the active tab button in a tab bar
local function setTab(bar, activeName, onColor, offColor)
	for _, b in ipairs(bar:GetChildren()) do
		if b:IsA("TextButton") then
			local on = b.Name == activeName
			b.BackgroundColor3 = on and onColor or offColor
			b.TextColor3 = on
				and Color3.fromRGB(220, 220, 230)
				or  Color3.fromRGB(130, 130, 150)
		end
	end
end

local function wireTabBar(bar, onColor, offColor)
	for _, b in ipairs(bar:GetChildren()) do
		if b:IsA("TextButton") then
			b.Activated:Connect(function() setTab(bar, b.Name, onColor, offColor) end)
		end
	end
end

-- ── Instance references ───────────────────────────────────

local hud       = w(root, "HUD")
local menuBtn   = w(hud,  "MenuBtn")
local navToggle = w(hud,  "NavToggle")
local navPanel  = w(hud,  "NavPanel")

-- Shorthand: backdrop + panel pairs created by mkOverlayPanel
local function bd(name) return w(root, name .. "Backdrop") end
local function op(backdrop, name) return w(backdrop, name .. "Panel") end

local cmBd  = bd("ClassMenu");       local cmPn  = op(cmBd,  "ClassMenu")
local smBd  = bd("StatsMenu");       local smPn  = op(smBd,  "StatsMenu")
local eqBd  = bd("EquipmentUI");     local eqPn  = op(eqBd,  "EquipmentUI")
local ttBd  = w(root, "TalentTreeBackdrop")
local wdBd  = w(root, "WardrobeBackdrop");       local wdPn  = w(wdBd,  "WardrobePanel")
local achBd = bd("AchievementsUI");  local achPn = op(achBd, "AchievementsUI")
local setBd = bd("SettingsUI");      local setPn = op(setBd, "SettingsUI")
local gsBd  = bd("GlobalShop");      local gsPn  = op(gsBd,  "GlobalShop")
local ccBd  = w(root, "CharCreationBackdrop");   local ccPn  = w(ccBd,  "CharCreationPanel")
local emBd  = w(root, "EmoteWheelBackdrop")
local voteBd = w(root, "VoteUIBackdrop");        local voteP = w(voteBd,"VotePanel")
local mmBd  = w(root, "MainMenuBackdrop")
local mmkBar = w(root, "MatchmakingUI")
local spBd  = bd("SocialPanel");     local spPn  = op(spBd,  "SocialPanel")
local npcBd = w(root, "NPCDialogBackdrop");      local npcPn = w(npcBd, "NPCDialogPanel")
local shopBd = w(root, "ShopUIBackdrop");        local shopPn = w(shopBd,"ShopUIPanel")
local wsBd  = bd("WeaponSmith");     local wsPn  = op(wsBd,  "WeaponSmith")
local dlBd  = bd("DailyLogin");      local dlPn  = op(dlBd,  "DailyLogin")
local lbBd  = bd("Leaderboard");     local lbPn  = op(lbBd,  "Leaderboard")
local invBd = bd("Inventory");       local invPn = op(invBd, "Inventory")
local piToast = w(root, "PartyInviteToast")
local testUI  = w(root, "TestingUI")
local appBar  = w(root, "AppearanceBar")

-- ── Escape key: close topmost open overlay ────────────────

local OVERLAYS = {
	cmBd, smBd, eqBd, ttBd, wdBd, achBd, setBd, gsBd,
	mmBd, spBd, shopBd, wsBd, dlBd, lbBd, invBd,
}

UIS.InputBegan:Connect(function(inp, proc)
	if proc then return end
	if inp.KeyCode == Enum.KeyCode.Escape then
		for _, overlay in ipairs(OVERLAYS) do
			if overlay.Visible then
				overlay.Visible = false
				return
			end
		end
	elseif inp.KeyCode == Enum.KeyCode.Q then
		emBd.Visible = not emBd.Visible
	end
end)

-- ── Nav toggle (right-edge button) ───────────────────────

navToggle.Activated:Connect(function()
	navPanel.Visible = not navPanel.Visible
end)

-- Menu button (top-left hamburger) → opens Main Menu
menuBtn.Activated:Connect(function()
	navPanel.Visible = false
	mmBd.Visible     = true
end)

-- Nav panel buttons → open their matching panel
local NAV_MAP = {
	NavClasses      = cmBd,
	NavStats        = smBd,
	NavEquip        = eqBd,
	NavTalents      = ttBd,
	NavAchievements = achBd,
	NavSocial       = spBd,
	NavShop         = gsBd,
	NavSettings     = setBd,
	NavInventory    = invBd,
	NavLeaderboard  = lbBd,
	NavDailyLogin   = dlBd,
}

for _, b in ipairs(navPanel:GetChildren()) do
	if b:IsA("TextButton") and NAV_MAP[b.Name] then
		local tgt = NAV_MAP[b.Name]
		b.Activated:Connect(function()
			navPanel.Visible = false
			tgt.Visible      = true
		end)
	end
end

-- ── Close buttons (X) on every panel ─────────────────────
-- For mkOverlayPanel panels the CloseBtn lives on the panel.
-- MainMenu CloseBtn sits directly on the backdrop.
-- TalentTree CloseBtn is inside the Header frame — wired by _setupTalentTree().

local CLOSE_PAIRS = {
	{ cmPn,  cmBd  }, { smPn,  smBd  }, { eqPn,  eqBd  },
	-- ttBd skipped: TalentTree close is wired in _setupTalentTree()
	{ wdPn,  wdBd  }, { achPn, achBd },
	{ setPn, setBd }, { gsPn,  gsBd  }, { mmBd,  mmBd  },
	{ spPn,  spBd  }, { npcPn, npcBd }, { shopPn,shopBd},
	{ wsPn,  wsBd  }, { dlPn,  dlBd  }, { lbPn,  lbBd  },
	{ invPn, invBd },
}

for _, pair in ipairs(CLOSE_PAIRS) do
	local cb = pair[1]:FindFirstChild("CloseBtn")
	if cb then
		cb.Activated:Connect(function() pair[2].Visible = false end)
	end
end

-- ── Daily Login: Claim ────────────────────────────────────

local claimBtn = dlPn:FindFirstChild("ClaimBtn")
if claimBtn then
	claimBtn.Activated:Connect(function()
		claimBtn.Text             = "Claimed!  ✓"
		claimBtn.BackgroundColor3 = Color3.fromRGB(35, 90, 45)
		claimBtn.Active           = false
		task.delay(1.5, function() dlBd.Visible = false end)
	end)
end

-- ── Matchmaking: Cancel ───────────────────────────────────

w(mmkBar, "CancelBtn").Activated:Connect(function()
	mmkBar.Visible = false
end)

-- ── Party Invite Toast ────────────────────────────────────

w(piToast, "AcceptBtn").Activated:Connect(function()
	piToast.Visible = false
	print("[Party] Invite accepted")
end)
w(piToast, "DeclineBtn").Activated:Connect(function()
	piToast.Visible = false
	print("[Party] Invite declined")
end)
w(piToast, "DismissBtn").Activated:Connect(function()
	piToast.Visible = false
end)

-- ── Testing Panel toggle ──────────────────────────────────

local testPanel = testUI:FindFirstChild("Panel")
w(testUI, "ToggleBtn").Activated:Connect(function()
	if testPanel then testPanel.Visible = not testPanel.Visible end
end)

-- ── Appearance Bar (Social Plaza) ────────────────────────

w(appBar, "WardrobeBtn").Activated:Connect(function() wdBd.Visible = true end)
w(appBar, "EmoteHint").Activated:Connect(function() emBd.Visible = not emBd.Visible end)

-- ── Tab Bars ──────────────────────────────────────────────

local tabBase = Color3.fromRGB(28, 28, 42)
wireTabBar(w(setPn,  "TabBar"), Color3.fromRGB(50, 80, 160),  tabBase)
wireTabBar(w(gsPn,   "TabBar"), Color3.fromRGB(60, 80, 120),  tabBase)
wireTabBar(w(lbPn,   "TabBar"), Color3.fromRGB(60, 80, 120),  Color3.fromRGB(30, 30, 42))
wireTabBar(w(wdPn,   "TabBar"), Color3.fromRGB(60, 60, 90),   tabBase)
wireTabBar(w(spPn,   "TabBar"), Color3.fromRGB(35, 35, 52),   Color3.fromRGB(22, 22, 32))

-- Achievements: category sidebar buttons
local achSidebar = achPn:WaitForChild("CategorySidebar")
for _, b in ipairs(achSidebar:GetChildren()) do
	if b:IsA("TextButton") then
		b.Activated:Connect(function()
			for _, x in ipairs(achSidebar:GetChildren()) do
				if x:IsA("TextButton") then
					x.BackgroundColor3 = tabBase
					x.TextColor3       = Color3.fromRGB(130, 130, 150)
				end
			end
			b.BackgroundColor3 = Color3.fromRGB(50, 80, 160)
			b.TextColor3       = Color3.fromRGB(220, 220, 230)
		end)
	end
end

-- ── Class Menu: Switch buttons ────────────────────────────

for _, col in ipairs(w(cmPn, "Columns"):GetChildren()) do
	if not col:IsA("Frame") then continue end
	for _, slot in ipairs(col:GetChildren()) do
		if not slot:IsA("Frame") then continue end
		local btn = slot:FindFirstChild("SwitchBtn")
		local lbl = slot:FindFirstChild("ClassName")
		if btn and lbl then
			btn.Activated:Connect(function()
				print("[ClassMenu] Switching to:", lbl.Text)
				cmBd.Visible = false
			end)
		end
	end
end

-- ── Stats Menu: + allocate buttons ───────────────────────

for _, row in ipairs(w(smPn, "PrimaryStats"):GetChildren()) do
	if not row:IsA("Frame") then continue end
	local addBtn  = row:FindFirstChild("AddBtn")
	local countLbl = row:FindFirstChild("AllocatedCount")
	if addBtn and countLbl then
		addBtn.Activated:Connect(function()
			countLbl.Text = tostring((tonumber(countLbl.Text) or 0) + 1)
		end)
	end
end

local respecBtn = smPn:FindFirstChild("RespecBtn")
if respecBtn then
	respecBtn.Activated:Connect(function() print("[StatsMenu] Respec requested") end)
end

-- ── Inventory: Equip buttons ──────────────────────────────

local equippedBar = invPn:WaitForChild("EquippedBar")
for _, item in ipairs(w(invPn, "ListFrame"):GetChildren()) do
	if item:IsA("Frame") then
		local btn = item:FindFirstChild("ActionBtn")
		local lbl = item:FindFirstChild("ItemName")
		if btn and lbl then
			btn.Activated:Connect(function()
				equippedBar.Text = "Equipped:  " .. lbl.Text
			end)
		end
	end
end

-- ── Main Menu: Play + Difficulty buttons ──────────────────

for _, wrap in ipairs(w(mmBd, "CardContainer"):GetChildren()) do
	if not wrap:IsA("Frame") then continue end
	local card = wrap:FindFirstChild("Card")
	if not card then continue end

	-- Difficulty picker: highlight selected difficulty
	local diffRow = card:FindFirstChild("DifficultyRow")
	if diffRow then
		for _, dBtn in ipairs(diffRow:GetChildren()) do
			if dBtn:IsA("TextButton") then
				dBtn.Activated:Connect(function()
					for _, x in ipairs(diffRow:GetChildren()) do
						if x:IsA("TextButton") then
							x.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
							x.TextColor3       = Color3.fromRGB(100, 100, 120)
						end
					end
					dBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 70)
					dBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
				end)
			end
		end
	end

	-- Play button → queue matchmaking
	local playBtn  = card:FindFirstChild("PlayBtn")
	local modeLbl  = card:FindFirstChild("ModeName")
	if playBtn and modeLbl then
		playBtn.Activated:Connect(function()
			mmBd.Visible = false
			mmkBar.Visible = true
			local sl = mmkBar:FindFirstChild("StatusLabel")
			if sl then sl.Text = "Queued for " .. modeLbl.Text .. "…" end
		end)
	end
end

-- ── NPC Dialog: Choice buttons ────────────────────────────

for _, b in ipairs(w(npcPn, "Choices"):GetChildren()) do
	if b:IsA("TextButton") then
		b.Activated:Connect(function()
			print("[NPCDialog] Choice selected:", b.Text)
			npcBd.Visible = false
		end)
	end
end

-- ── NPC Shop: Buy buttons ─────────────────────────────────

for _, c in ipairs(w(shopPn, "ItemGrid"):GetChildren()) do
	if c:IsA("Frame") then
		local btn = c:FindFirstChild("BuyBtn")
		local lbl = c:FindFirstChild("ItemName")
		if btn and lbl then
			btn.Activated:Connect(function() print("[Shop] Buy:", lbl.Text) end)
		end
	end
end

-- ── Global Shop: Buy buttons ──────────────────────────────

for _, c in ipairs(w(gsPn, "ItemGrid"):GetChildren()) do
	if c:IsA("Frame") then
		local btn = c:FindFirstChild("BuyBtn")
		local lbl = c:FindFirstChild("ItemName")
		if btn and lbl then
			btn.Activated:Connect(function() print("[GlobalShop] Buy:", lbl.Text) end)
		end
	end
end

-- ── Vote buttons ──────────────────────────────────────────

for _, c in ipairs(voteP:GetChildren()) do
	if c:IsA("Frame") then
		local btn   = c:FindFirstChild("VoteBtn")
		local title = c:FindFirstChild("OptionTitle")
		if btn then
			btn.Activated:Connect(function()
				print("[Vote] Voted for:", title and title.Text or "?")
				voteBd.Visible = false
			end)
		end
	end
end

-- ── Social: Create Party ──────────────────────────────────

local rosterFrame = spPn:FindFirstChild("PartyRoster")
local cpBtn = rosterFrame and rosterFrame:FindFirstChild("CreatePartyBtn")
if cpBtn then
	cpBtn.Activated:Connect(function()
		cpBtn.Text             = "Party Created!  ✓"
		cpBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
		print("[Social] Party created")
	end)
end

-- ── Character Creation: Confirm ───────────────────────────

local cfBtn = ccPn:FindFirstChild("ConfirmBtn")
if cfBtn then
	cfBtn.Activated:Connect(function() ccBd.Visible = false end)
end

-- Skin tone picker: ring highlight on selected swatch
local skinGrid = ccPn:FindFirstChild("SkinGrid")
if skinGrid then
	for _, b in ipairs(skinGrid:GetChildren()) do
		if b:IsA("TextButton") then
			b.Activated:Connect(function()
				for _, x in ipairs(skinGrid:GetChildren()) do
					if x:IsA("TextButton") then x.BorderSizePixel = 0 end
				end
				b.BorderSizePixel = 3
			end)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- TALENT TREE  (dynamic from TalentTreeConfig + TalentClient)
-- ═══════════════════════════════════════════════════════════

local function _setupTalentTree()
	local RS   = game:GetService("ReplicatedStorage")
	local Plrs = game:GetService("Players")

	local ok1, TalentClient = pcall(function()
		return require(Plrs.LocalPlayer
			:WaitForChild("PlayerScripts")
			:WaitForChild("Modules")
			:WaitForChild("TalentClient"))
	end)
	local ok2, TreeConfig = pcall(function()
		return require(RS:WaitForChild("Shared"):WaitForChild("TalentTreeConfig"))
	end)
	if not (ok1 and ok2) then
		warn("[AppGuiWiring] TalentClient or TalentTreeConfig not available — tree wiring skipped")
		return
	end

	-- Layout constants (must match TalentTreeUI.lua)
	local GRID_CELL = 42
	local NODE_SIZE = 36
	local CENTER_X  = 0.5
	local CENTER_Y  = 0.45

	-- Palette (must match TalentTreeUI.lua)
	local PC = {
		allocated   = Color3.fromRGB( 80, 210, 120),
		allocatable = Color3.fromRGB(120, 180, 255),
		locked      = Color3.fromRGB( 55,  55,  70),
		keystone_bg = Color3.fromRGB(200, 170,  50),
		notable_bg  = Color3.fromRGB(100, 130, 200),
		small_bg    = Color3.fromRGB( 80,  80, 100),
		line        = Color3.fromRGB( 45,  45,  65),
		line_active = Color3.fromRGB( 60, 180, 100),
		text        = Color3.fromRGB(220, 220, 230),
		text_dim    = Color3.fromRGB(140, 140, 160),
		btn_stroke  = Color3.fromRGB( 60, 100, 180),
	}

	local canvasFrame  = ttBd:WaitForChild("TalentCanvas")
	local headerFrame  = ttBd:WaitForChild("Header")
	local pointsLbl    = headerFrame:WaitForChild("PointsLabel")
	local respecBtnTT  = headerFrame:WaitForChild("RespecBtn")
	local closeBtnTT   = headerFrame:WaitForChild("CloseBtn")
	local tooltip      = ttBd:WaitForChild("Tooltip")
	local ttNameLbl    = tooltip:WaitForChild("NameLabel")
	local ttDescLbl    = tooltip:WaitForChild("DescLabel")
	local ttEffLbl     = tooltip:WaitForChild("EffectsLabel")
	local ttCostLbl    = tooltip:WaitForChild("CostLabel")

	closeBtnTT.Activated:Connect(function() ttBd.Visible = false end)
	respecBtnTT.Activated:Connect(function() TalentClient.RespecAll() end)

	-- Helpers
	local function getSizeMul(t)
		if t == "keystone" then return 1.45 end
		if t == "notable"  then return 1.20 end
		return 1.0
	end
	local function nodeBg(nd, alloc, avail)
		if alloc then return PC.allocated end
		if avail then return PC.allocatable end
		return PC.locked
	end
	local function nodeBorder(nd, alloc, avail)
		if nd.type == "keystone" then return PC.keystone_bg end
		if nd.type == "notable"  then return PC.notable_bg  end
		if alloc then return PC.allocated end
		if avail then return PC.allocatable end
		return PC.small_bg
	end

	local nodeMap    = TreeConfig.GetNodeMap()
	local nodeButtons = {}   -- [nodeId] = TextButton
	local edgeFrames  = {}   -- [i]      = Frame

	-- Drag state
	local isDragging = false
	local dragStart  = Vector2.new(0, 0)
	local offsetBase = Vector2.new(0, 0)
	local dragOff    = Vector2.new(0, 0)
	local cvSize     = Vector2.new(1200, 800)

	local function pxPos(nd)
		return
			cvSize.X * CENTER_X + nd.x * GRID_CELL + dragOff.X,
			cvSize.Y * CENTER_Y + nd.y * GRID_CELL + dragOff.Y
	end

	local function refreshEdge(ef, n1, n2)
		local x1, y1 = pxPos(n1)
		local x2, y2 = pxPos(n2)
		local dx, dy = x2 - x1, y2 - y1
		ef.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
		ef.Size     = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), 2)
		ef.Rotation = math.deg(math.atan2(dy, dx))
	end

	local built = false
	local function buildTree()
		if built then return end
		built = true
		cvSize = canvasFrame.AbsoluteSize
		if cvSize.X == 0 then cvSize = Vector2.new(1200, 800) end

		local state  = TalentClient.GetState()
		local alloc  = state and state.allocatedNodes or {}
		local avSet  = {}
		for _, id in ipairs(TalentClient.GetAllocatableNodes()) do avSet[id] = true end

		-- Edges (lower Z-index, drawn first)
		for i, edge in ipairs(TreeConfig.Edges) do
			local n1, n2 = nodeMap[edge[1]], nodeMap[edge[2]]
			if n1 and n2 then
				local isAct = alloc[edge[1]] and alloc[edge[2]]
				local ef = Instance.new("Frame")
				ef.Name             = "Edge_" .. i
				ef.AnchorPoint      = Vector2.new(0.5, 0.5)
				ef.BackgroundColor3 = isAct and PC.line_active or PC.line
				ef.BorderSizePixel  = 0
				ef.ZIndex           = 2
				ef.Parent           = canvasFrame
				refreshEdge(ef, n1, n2)
				edgeFrames[i] = ef
			end
		end

		-- Nodes
		for _, nd in ipairs(TreeConfig.Nodes) do
			local a   = alloc[nd.id] == true
			local v   = avSet[nd.id] == true
			local px  = NODE_SIZE * getSizeMul(nd.type)
			local bx, by = pxPos(nd)

			local btn = Instance.new("TextButton")
			btn.Name             = "Node_" .. nd.id
			btn.AnchorPoint      = Vector2.new(0.5, 0.5)
			btn.Position         = UDim2.fromOffset(bx, by)
			btn.Size             = UDim2.fromOffset(px, px)
			btn.BackgroundColor3 = nodeBg(nd, a, v)
			btn.BorderSizePixel  = 0
			btn.Text             = ""
			btn.AutoButtonColor  = v or (a and TalentClient.CanRefund(nd.id))
			btn.ZIndex           = 5
			btn.Parent           = canvasFrame

			local co = Instance.new("UICorner")
			co.CornerRadius = UDim.new(0.5, 0)
			co.Parent = btn

			local sk = Instance.new("UIStroke")
			sk.Color     = nodeBorder(nd, a, v)
			sk.Thickness = (nd.type == "keystone") and 3 or 2
			sk.Parent    = btn

			local lbl = Instance.new("TextLabel")
			lbl.Size                   = UDim2.fromScale(0.85, 0.85)
			lbl.AnchorPoint            = Vector2.new(0.5, 0.5)
			lbl.Position               = UDim2.fromScale(0.5, 0.5)
			lbl.BackgroundTransparency = 1
			lbl.Text                   = string.sub(nd.name, 1, 5)
			lbl.TextColor3             = PC.text
			lbl.Font                   = Enum.Font.GothamBold
			lbl.TextScaled             = true
			lbl.TextTruncate           = Enum.TextTruncate.AtEnd
			lbl.ZIndex                 = 6
			lbl.Parent                 = btn

			-- Allocate / refund on click (reads live state)
			local captId = nd.id
			btn.Activated:Connect(function()
				local st2   = TalentClient.GetState()
				local al2   = st2 and st2.allocatedNodes or {}
				local av2   = {}
				for _, id in ipairs(TalentClient.GetAllocatableNodes()) do av2[id] = true end
				if av2[captId] and not al2[captId] then
					TalentClient.AllocateNode(captId)
				elseif al2[captId] and TalentClient.CanRefund(captId) then
					TalentClient.RefundNode(captId)
				end
			end)

			-- Hover tooltip
			local captNd = nd
			btn.MouseEnter:Connect(function()
				local lines = {}
				for _, eff in ipairs(captNd.effects or {}) do
					local lname = eff.stat or eff.primary or "?"
					if eff.rule then
						table.insert(lines, "* " .. lname .. " (passive)")
					elseif eff.value ~= nil then
						local sign = eff.value >= 0 and "+" or ""
						table.insert(lines, sign .. tostring(eff.value) .. " " .. lname)
					end
				end
				local costN = captNd.cost or 1
				ttNameLbl.Text  = captNd.name .. "  [" .. string.upper(captNd.type or "") .. "]"
				ttDescLbl.Text  = captNd.description or ""
				ttEffLbl.Text   = table.concat(lines, "\n")
				ttCostLbl.Text  = costN > 0 and ("Cost: " .. costN .. " point") or "Free"
				tooltip.Visible = true
			end)
			btn.MouseLeave:Connect(function() tooltip.Visible = false end)

			nodeButtons[nd.id] = btn
		end
	end

	-- Refresh node visuals + points label + edge colours after a state change
	local function updateVisuals()
		local state = TalentClient.GetState()
		local alloc = state and state.allocatedNodes or {}
		local avSet = {}
		for _, id in ipairs(TalentClient.GetAllocatableNodes()) do avSet[id] = true end

		for _, nd in ipairs(TreeConfig.Nodes) do
			local btn = nodeButtons[nd.id]
			if not btn then continue end
			local a = alloc[nd.id] == true
			local v = avSet[nd.id] == true
			btn.BackgroundColor3 = nodeBg(nd, a, v)
			local sk = btn:FindFirstChildOfClass("UIStroke")
			if sk then sk.Color = nodeBorder(nd, a, v) end
		end

		local ts = state or {}
		pointsLbl.Text = string.format(
			"Points: %d / %d   (Available: %d)",
			ts.pointsSpent or 0, ts.pointsTotal or 0, ts.pointsAvailable or 0
		)

		for i, ef in ipairs(edgeFrames) do
			local edge = TreeConfig.Edges[i]
			if ef and edge then
				ef.BackgroundColor3 = (alloc[edge[1]] and alloc[edge[2]]) and PC.line_active or PC.line
			end
		end
	end

	-- Drag / pan the canvas
	canvasFrame.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
			dragStart  = Vector2.new(inp.Position.X, inp.Position.Y)
			offsetBase = dragOff
		end
	end)

	UIS.InputChanged:Connect(function(inp)
		if inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
		if not isDragging then return end
		dragOff = offsetBase + (Vector2.new(inp.Position.X, inp.Position.Y) - dragStart)
		for _, nd in ipairs(TreeConfig.Nodes) do
			local btn = nodeButtons[nd.id]
			if btn then
				local bx, by = pxPos(nd)
				btn.Position = UDim2.fromOffset(bx, by)
			end
		end
		for i, ef in ipairs(edgeFrames) do
			local edge = TreeConfig.Edges[i]
			local n1   = nodeMap[edge and edge[1]]
			local n2   = nodeMap[edge and edge[2]]
			if n1 and n2 and ef then refreshEdge(ef, n1, n2) end
		end
	end)

	UIS.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			isDragging = false
		end
	end)

	-- Build on first open; refresh visuals on subsequent opens
	ttBd:GetPropertyChangedSignal("Visible"):Connect(function()
		if not ttBd.Visible then return end
		task.defer(function()
			buildTree()
			updateVisuals()
		end)
	end)

	-- Live subscription for state changes while the panel is open
	TalentClient.Subscribe(function()
		if not ttBd.Visible then return end
		updateVisuals()
	end)
end

_setupTalentTree()

print("✅  AppGuiWiring connected —", #root:GetDescendants(), "descendants wired.")
]==]

wiringScript.Parent = gui

-- ═══════════════════════════════════════════════════════════
-- DONE
-- ═══════════════════════════════════════════════════════════

print("✅  AppGui generated under StarterGui with " .. #gui:GetDescendants() .. " instances.")
print("    AppGuiWiring LocalScript embedded — buttons are live when game runs.")
print("    Overlay panels start Visible=false — toggle in Properties to preview.")
