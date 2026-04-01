-- socialplaza/StarterPlayerScripts/UI/AppearanceBar.lua
--[[
    Appearance shortcut ribbon — bottom-right of screen.

    A minimal floating bar that gives quick access to the core appearance
    tools available in the Social Plaza:
      • [👗]  Wardrobe  — opens WardrobeUI to browse and equip cosmetics.
      • [Q]   Emotes    — reminds the player of the Q shortcut for EmoteWheel.

    Props:
      onWardrobeOpen : () → void   called when the Wardrobe button is clicked

    Future: add Poses, Avatar Preview, Dye Station, etc. as buttons here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React    = require(ReplicatedStorage.Packages.React)
local e        = React.createElement
local useState = React.useState

-- ── Palette (matches the rest of the plaza UI) ────────────
local C = {
	bar_bg     = Color3.fromRGB(18,  18,  26),
	btn_bg     = Color3.fromRGB(38,  38,  54),
	btn_hover  = Color3.fromRGB(60,  60,  90),
	btn_border = Color3.fromRGB(90,  90, 130),
	label      = Color3.fromRGB(220, 220, 235),
	label_sub  = Color3.fromRGB(140, 140, 160),
	accent     = Color3.fromRGB(105, 190, 255),
}

-- ── Single bar button ─────────────────────────────────────
local function BarButton(props)
	local hovered, setHovered = useState(false)

	return e("TextButton", {
		Size             = UDim2.fromScale(0.029, 0.052),
		BackgroundColor3 = hovered and C.btn_hover or C.btn_bg,
		BorderSizePixel  = 0,
		AutoButtonColor  = false,
		[React.Event.Activated]  = props.onActivated,
		[React.Event.MouseEnter] = function() setHovered(true) end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0.2, 0) }),

		Stroke = e("UIStroke", {
			Color     = hovered and C.accent or C.btn_border,
			Thickness = hovered and 2 or 1,
		}),

		Icon = e("TextLabel", {
			Size                   = UDim2.fromScale(1, 0.5),
			AnchorPoint            = Vector2.new(0.5, 0),
			Position               = UDim2.fromScale(0.5, 0.04),
			BackgroundTransparency = 1,
			Text                   = props.icon,
			TextScaled             = true,
			Font                   = Enum.Font.GothamBold,
			TextColor3             = hovered and C.accent or C.label,
		}),

		Label = e("TextLabel", {
			Size                   = UDim2.fromScale(1, 0.36),
			AnchorPoint            = Vector2.new(0.5, 1),
			Position               = UDim2.fromScale(0.5, 0.97),
			BackgroundTransparency = 1,
			Text                   = props.label,
			TextScaled             = true,
			Font                   = Enum.Font.Gotham,
			TextColor3             = C.label_sub,
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- APPEARANCE BAR ROOT
-- ═══════════════════════════════════════════════════════════
local function AppearanceBar(props)
	local onWardrobeOpen = props.onWardrobeOpen or function() end

	-- Gap between buttons
	local GAP    = 8
	local BTN_W  = 56
	local BTN_H  = 56
	local PAD    = 10
	local N      = 2   -- number of buttons
	local barW   = PAD * 2 + BTN_W * N + GAP * (N - 1)
	local barH   = PAD * 2 + BTN_H

	return e("Frame", {
		Name            = "AppearanceBar",
		AnchorPoint     = Vector2.new(1, 1),
		Position        = UDim2.new(1, -16, 1, -16),
		Size            = UDim2.fromScale(barW / 1920, barH / 1080),
		BackgroundColor3 = C.bar_bg,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0.15, 0) }),

		Stroke = e("UIStroke", {
			Color     = C.btn_border,
			Thickness = 1,
		}),

		Layout = e("UIListLayout", {
			FillDirection       = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment   = Enum.VerticalAlignment.Center,
			Padding             = UDim.new(0, GAP),
		}),

		Padding = e("UIPadding", {
			PaddingLeft   = UDim.new(0, PAD),
			PaddingRight  = UDim.new(0, PAD),
			PaddingTop    = UDim.new(0, PAD),
			PaddingBottom = UDim.new(0, PAD),
		}),

		-- Wardrobe button
		WardrobeBtn = e(BarButton, {
			icon        = "👗",
			label       = "Wardrobe",
			onActivated = onWardrobeOpen,
		}),

		-- Emote hint button (not a toggle — EmoteWheel owns its own Q binding)
		EmoteBtn = e(BarButton, {
			icon        = "Q",
			label       = "Emotes",
			onActivated = function() end,  -- EmoteWheel opens via InputSystem
		}),
	})
end

return AppearanceBar
