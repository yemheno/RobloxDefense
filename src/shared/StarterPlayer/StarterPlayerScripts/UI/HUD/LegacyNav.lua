-- UI/HUD/LegacyNav.lua
--[[
    §AGX/UI-P5: today's ☰ (Lobby main menu) + ⋮ drawer, moved VERBATIM from
    HUD.lua (:223-226, 658-695, 726-754, 1046-1320). Rendered by the HUD
    while props.legacyNav ~= false; deleted in W3 (shell-spec §5), which
    also fixes F1 (the ⋮ toggle under SkillPad's Skill 4 on phones).

    UNSCALED: this code measures in SCREEN px (scale sizes + pixel floors),
    so the HUD mounts it OUTSIDE its UIScaleRoot layer. Mount the HUD itself
    unscaled (it scales its own regions) or these offsets double-scale.

    Publishes UI_NavToggleTopPx (top of the ⋮ toggle, screen px) for the
    standalone TeammateVitals.
    props: viewport (Vector2 screen px), safeTop (screen px), visible,
           onMenuClick, onClassesClick, onStatsClick, onTalentsClick,
           onEquipClick, onCosmeticsClick, onAchievementsClick,
           onSettingsClick, onShopClick, onPartyClick, onDailyLoginClick,
           onLeaderboardClick, onInventoryClick
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local Modules = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local Locale  = require(Modules:WaitForChild("Locale"))

local ATTR_NAV_TOP = "UI_NavToggleTopPx"   -- top of the ⋮ toggle

-- ── Palette (legacy, unchanged) ──────────────────────────────────────────────
local C = {
	btn_bg     = Color3.fromRGB( 35,  35,  52),
	btn_text   = Color3.fromRGB(105, 190, 255),
	btn_stroke = Color3.fromRGB( 60, 100, 180),
}

local MIN_TAP_PX = 44   -- mobile.md §1.3 absolute floor

local function minTap(w, h)
	return React.createElement("UISizeConstraint", {
		MinSize = Vector2.new(w or 0, h or MIN_TAP_PX),
	})
end

local function minText()
	return React.createElement("UITextSizeConstraint", { MinTextSize = 12 })
end

--- Size of the legacy ☰ in screen px (the HUD reserves it in the top-right row).
local function menuButtonSize(viewport)
	return Vector2.new(math.max(MIN_TAP_PX, 0.05 * viewport.X), math.max(MIN_TAP_PX, 0.07 * viewport.Y))
end

local function LegacyNav(props)
	local onClassesClick      = props.onClassesClick
	local onStatsClick        = props.onStatsClick
	local onTalentsClick      = props.onTalentsClick
	local onEquipClick        = props.onEquipClick
	local onCosmeticsClick    = props.onCosmeticsClick
	local onAchievementsClick = props.onAchievementsClick
	local onSettingsClick     = props.onSettingsClick
	local onShopClick         = props.onShopClick
	local onMenuClick         = props.onMenuClick
	local onPartyClick        = props.onPartyClick
	local onDailyLoginClick   = props.onDailyLoginClick
	local onLeaderboardClick  = props.onLeaderboardClick
	local onInventoryClick    = props.onInventoryClick
	local safeTop = props.safeTop
	local vpH     = props.viewport.Y

	-- Nav panel: collapsed / expanded
	local menuOpen, setMenuOpen = React.useState(false)
	local panelRef = React.useRef(nil)
	local didMount        = React.useRef(false)
	local closeTimerRef   = React.useRef(nil)

	-- Right-middle ⋮ toggle
	local toggleH   = math.max(MIN_TAP_PX, 0.09 * vpH)
	local toggleTop = 0.5 * vpH - toggleH / 2

	React.useEffect(function()
		ReplicatedStorage:SetAttribute(ATTR_NAV_TOP, toggleTop)
	end, { toggleTop })
	React.useEffect(function()
		return function()
			ReplicatedStorage:SetAttribute(ATTR_NAV_TOP, nil)
		end
	end, {})

	-- Nav grid (T3): cells in pixels with a 44 px floor; the panel scrolls
	-- when 6 rows no longer fit (phones). 1080p values equal the old scales.
	local navPanelH = 0.62 * vpH
	local navCellH  = math.max(MIN_TAP_PX, 0.135 * navPanelH)
	local navGapY   = 0.018 * navPanelH
	local navPadY   = 0.02 * navPanelH

	-- ── Nav panel slide animation ──────────────────────────────────────────
	React.useEffect(function()
		local frame = panelRef.current
		if not frame then return end

		if not didMount.current then
			-- First mount: park off-screen and hide immediately (no flash)
			frame.Position = UDim2.fromScale(1.20, 0.50)
			frame.Visible  = false
			didMount.current = true
			return
		end

		if menuOpen then
			-- Cancel any pending close-hide timer so a quick toggle doesn't hide the panel
			if closeTimerRef.current then
				task.cancel(closeTimerRef.current)
				closeTimerRef.current = nil
			end
			frame.Visible = true
			TweenService:Create(
				frame,
				TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = UDim2.fromScale(0.985, 0.50) }
			):Play()
		else
			local CLOSE_TIME = 0.13
			TweenService:Create(
				frame,
				TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
				{ Position = UDim2.fromScale(1.20, 0.50) }
			):Play()
			closeTimerRef.current = task.delay(CLOSE_TIME, function()
				closeTimerRef.current = nil
				if frame and frame.Parent then frame.Visible = false end
			end)
		end
	end, { menuOpen })

	return React.createElement("Frame", {
		Name                   = "LegacyNav",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible                = props.visible ~= false,
		ZIndex                 = 4,
	}, {
		-- ── Top-right: Menu button ────────────────────────────────────────────
		-- §UI-HUD1: was 3.5% × 5% — at 1080p that's 67×54, at higher resolutions
		-- the icon was unclickable. Bumped to 5% × 7% pure-scale per the
		-- "no hardcoded pixel sizes" rule.
		-- §AGX/UI-P1: M7/V3/T1: was top-left at (0.005, 0.008), i.e. under
		-- Roblox's own menu button on phones (the only non-NPC route to
		-- matchmaking). Now top-right, below the topbar (safeTop), with a
		-- 44x44 floor. Same 5% x 7% size on desktop.
		menuBtn = onMenuClick and React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0),
			Position         = UDim2.new(0.995, 0, 0, safeTop),
			Size             = UDim2.fromScale(0.05, 0.07),
			BackgroundColor3 = C.btn_bg,
			BorderSizePixel  = 0,
			Text             = "☰",
			TextColor3       = C.btn_text,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			ZIndex           = 4,
			[React.Event.Activated] = onMenuClick,
		}, {
			minSize = minTap(MIN_TAP_PX, MIN_TAP_PX),  -- §AGX/UI-P1
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
			stroke = React.createElement("UIStroke", {
				Color        = C.btn_stroke,
				Thickness    = 1.5,
				Transparency = 0,
			}),
		}) or nil,

		-- ── Right: Classes + Stats buttons ─────────────────────────────────────
		-- Nav toggle button: always visible, slides the panel open/closed
		-- §UI-HUD2: bumped from 5.5% × 7.5% → 7% × 9% so the ⋮/✕ chip is
		-- comfortably clickable at any viewport.
		navToggle = React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0.5),
			Position         = UDim2.fromScale(0.985, 0.50),
			Size             = UDim2.fromScale(0.07, 0.09),
			BackgroundColor3 = menuOpen and Color3.fromRGB(60, 45, 80) or C.btn_bg,
			BorderSizePixel  = 0,
			Text             = menuOpen and "✕" or "⋮",
			TextColor3       = menuOpen and Color3.fromRGB(200, 170, 255) or C.btn_text,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			ZIndex           = 6,
			[React.Event.Activated] = function() setMenuOpen(not menuOpen) end,
		}, {
			minSize = minTap(MIN_TAP_PX, MIN_TAP_PX),  -- §AGX/UI-P1: T2 (was 59x35 on iPhone)
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
			stroke = React.createElement("UIStroke", {
				Color        = menuOpen and Color3.fromRGB(120, 80, 200) or C.btn_stroke,
				Thickness    = 1.5,
				Transparency = 0,
			}),
		}),

		-- Nav panel: slides from right via TweenService (Position controlled by panelRef effect).
		-- §UI-HUD3: navPanel was AutomaticSize.Y with a pixel-sized grid
		-- (CellSize 0,36 height + 0,5 padding = 41 px per row × 6 rows = 246 px).
		-- That made every button "nano" on a 4K monitor and unclickable on
		-- mobile. Switched to a pure-scale Y dimension on the panel and
		-- pure-scale CellSize/CellPadding on the grid so buttons resize with
		-- the viewport.
		-- §AGX/UI-P1: T3: ScrollingFrame (was Frame) + pixel cell heights with
		-- a 44 px floor. At 1080p the pixel values equal the old scales and
		-- all rows fit, so no scrollbar shows; on phones it scrolls.
		navPanel = React.createElement("ScrollingFrame", {
			ref              = panelRef,
			AnchorPoint      = Vector2.new(1, 0.5),
			-- Position is NOT a managed prop — TweenService controls it via panelRef
			Size             = UDim2.fromScale(0.22, 0.62),
			BackgroundColor3 = Color3.fromRGB(18, 18, 28),
			BackgroundTransparency = 0.10,
			BorderSizePixel  = 0,
			CanvasSize       = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection  = Enum.ScrollingDirection.Y,
			ScrollBarThickness  = 4,
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			ZIndex           = 5,
		}, {
			minSize = React.createElement("UISizeConstraint", {
				MinSize = Vector2.new(180, 0),  -- §AGX/UI-P1: two 44+ px wide columns
			}),
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.04, 0) }),
			stroke = React.createElement("UIStroke", {
				Color        = Color3.fromRGB(60, 80, 160),
				Thickness    = 1.5,
				Transparency = 0,
			}),
			-- 2-column grid: 12 buttons → 6 rows of 2.
			-- 6 rows × 0.135 height + 5 paddings × 0.018 = 0.90 of panel
			-- height → fits within the 4% UIPadding above/below.
			layout = React.createElement("UIGridLayout", {
				CellSize            = UDim2.new(0.47, 0, 0, navCellH),   -- §AGX/UI-P1
				CellPadding         = UDim2.new(0.02, 0, 0, navGapY),    -- §AGX/UI-P1
				SortOrder           = Enum.SortOrder.LayoutOrder,
				FillDirection       = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment   = Enum.VerticalAlignment.Top,
			}),
			pad = React.createElement("UIPadding", {
				PaddingLeft   = UDim.new(0.02, 0),
				PaddingRight  = UDim.new(0.02, 0),
				PaddingTop    = UDim.new(0, navPadY),     -- §AGX/UI-P1
				PaddingBottom = UDim.new(0, navPadY),     -- §AGX/UI-P1
			}),

			navClasses = onClassesClick and React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = Locale.Get("btn_classes"), TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 1, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onClassesClick then onClassesClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}) or nil,

			navStats = React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "Stats", TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 2, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onStatsClick then onStatsClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}),

			navEquip = React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "Equipment", TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 3, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onEquipClick then onEquipClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}),

			-- §AGX/UX-01: Wardrobe entry was dropped in v0.5 (d862558), leaving
			-- WardrobeUI unreachable; restored in the empty LayoutOrder 4 slot.
			navWardrobe = onCosmeticsClick and React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "Wardrobe", TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 4, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onCosmeticsClick then onCosmeticsClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}) or nil,

			navTalents = React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "Talents", TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 5, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onTalentsClick then onTalentsClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}),

			navAchievements = React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "Achievements",
				TextColor3 = Color3.fromRGB(255, 200, 60),
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 6, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onAchievementsClick then onAchievementsClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", {
					Color = Color3.fromRGB(160, 120, 30), Thickness = 1.5,
				}),
			}),

			navSocial = onPartyClick and React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "Social", TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 7, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onPartyClick then onPartyClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}) or nil,

			navShop = React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "\u{1F6D2} Shop",
				TextColor3 = Color3.fromRGB(255, 210, 60),
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 8, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onShopClick then onShopClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", {
					Color = Color3.fromRGB(160, 130, 30), Thickness = 1.5,
				}),
			}),

			navSettings = React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "\u{2699} Settings",
				TextColor3 = Color3.fromRGB(180, 180, 180),
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 9, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onSettingsClick then onSettingsClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}),

			navInventory = onInventoryClick and React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				-- §AGX/UX-01 (freebie): was U+1F3BA (trumpet); backpack fits Inventory.
				Text = "\u{1F392} Inventory",
				TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 10, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onInventoryClick then onInventoryClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}) or nil,

			navLeaderboard = onLeaderboardClick and React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "\u{1F3C6} Leaderboard",
				TextColor3 = Color3.fromRGB(255, 200, 60),
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 11, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onLeaderboardClick then onLeaderboardClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", {
					Color = Color3.fromRGB(160, 130, 30), Thickness = 1.5,
				}),
			}) or nil,

			navDailyLogin = onDailyLoginClick and React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "\u{1F4C5} Daily Login",
				TextColor3 = Color3.fromRGB(100, 220, 120),
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 12, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onDailyLoginClick then onDailyLoginClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", {
					Color = Color3.fromRGB(40, 140, 60), Thickness = 1.5,
				}),
			}) or nil,
		}),
	})
end

return {
	default        = LegacyNav,
	menuButtonSize = menuButtonSize,
}
