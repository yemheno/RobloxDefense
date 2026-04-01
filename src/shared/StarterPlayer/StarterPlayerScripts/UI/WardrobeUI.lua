-- UI/WardrobeUI.lua
--[[
    WardrobeUI
    ==========
    Full-screen React component for browsing and equipping cosmetics.

    Two tabs:
      • Headgear  (cosmetics for the Head slot)
      • Outfit    (cosmetics for the body / Torso+Arms+Legs)

    Each owned cosmetic is shown as a card. Clicking equips it.
    The currently equipped item is highlighted. A button to unequip
    (revert to class default) is shown at the top of each tab.

    Props:
        onClose  function()  -- called when the close button is pressed
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local Modules        = PlayerScripts:WaitForChild("Modules")
local CosmeticClient = require(Modules:WaitForChild("CosmeticClient"))

local e         = React.createElement
local useState  = React.useState
local useEffect = React.useEffect

-- ── Palette ───────────────────────────────────────────────
local C = {
	overlay    = Color3.fromRGB(0, 0, 0),
	panel      = Color3.fromRGB(18, 18, 26),
	card_bg    = Color3.fromRGB(32, 32, 48),
	card_sel   = Color3.fromRGB(50, 160, 100),
	tab_bg     = Color3.fromRGB(28, 28, 42),
	tab_active = Color3.fromRGB(60, 60, 90),
	text       = Color3.fromRGB(220, 220, 235),
	text_dim   = Color3.fromRGB(140, 140, 160),
	btn_close  = Color3.fromRGB(180, 50, 50),
	btn_equip  = Color3.fromRGB(60, 180, 110),
	btn_unequip = Color3.fromRGB(120, 80, 60),
	accent     = Color3.fromRGB(105, 190, 255),
	stroke     = Color3.fromRGB(60, 100, 180),
}

-- ── Rarity colors (mirrors CosmeticConfig.RarityColors) ───
local RARITY_COLORS = {
	Common    = Color3.fromRGB(180, 180, 180),
	Uncommon  = Color3.fromRGB(80, 200, 120),
	Rare      = Color3.fromRGB(80, 140, 230),
	Epic      = Color3.fromRGB(160, 80, 220),
	Legendary = Color3.fromRGB(255, 180, 40),
}

local SUPPORTED_HEADGEAR_PATTERNS = {
	"^none$",
	"^hood_",
	"^helm_",
	"^circlet_",
	"^mask_",
}

local SUPPORTED_OUTFIT_PATTERNS = {
	"^default_",
	"^peasant_",
	"^dark_",
	"^shadow_",
	"^forest_",
}

local function matchesAnyPattern(value, patterns)
	for _, pattern in ipairs(patterns) do
		if value:match(pattern) then
			return true
		end
	end
	return false
end

-- ═══════════════════════════════════════════════════════════
-- COSMETIC CARD
-- ═══════════════════════════════════════════════════════════

local function CosmeticCard(props)
	local cosmetic   = props.cosmetic   -- full entry from CosmeticConfig
	local isEquipped = props.isEquipped
	local isOwned    = props.isOwned
	local onSelect   = props.onSelect

	local hovered, setHovered = useState(false)
	local rarityColor = RARITY_COLORS[cosmetic.rarity] or RARITY_COLORS.Common
	local bgColor = isEquipped and C.card_sel or (hovered and C.tab_active or C.card_bg)

	return e("TextButton", {
		Size              = UDim2.fromScale(0.068, 0.102),
		BackgroundColor3  = bgColor,
		Text              = "",
		BorderSizePixel   = 0,
		AutoButtonColor   = false,
		LayoutOrder       = isEquipped and 0 or 1,
		[React.Event.Activated]  = function()
			if isOwned and onSelect then onSelect(cosmetic.id) end
		end,
		[React.Event.MouseEnter] = function() setHovered(true) end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
	}, {
		corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
		stroke = e("UIStroke", {
			Color     = isEquipped and C.accent or rarityColor,
			Thickness = isEquipped and 2 or 1,
		}),

		-- Name
		nameLabel = e("TextLabel", {
			Size                   = UDim2.new(1, -10, 0, 22),
			Position               = UDim2.new(0, 5, 0, 6),
			BackgroundTransparency = 1,
			Text                   = cosmetic.name or cosmetic.id,
			TextColor3             = C.text,
			TextScaled             = true,
			Font                   = Enum.Font.GothamBold,
			TextXAlignment         = Enum.TextXAlignment.Left,
			TextTruncate           = Enum.TextTruncate.AtEnd,
		}),

		-- Rarity
		rarityLabel = e("TextLabel", {
			Size                   = UDim2.new(1, -10, 0, 16),
			Position               = UDim2.new(0, 5, 0, 30),
			BackgroundTransparency = 1,
			Text                   = cosmetic.rarity or "Common",
			TextColor3             = rarityColor,
			TextScaled             = true,
			Font                   = Enum.Font.Gotham,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}),

		-- Description
		descLabel = e("TextLabel", {
			Size                   = UDim2.new(1, -10, 0, 32),
			Position               = UDim2.new(0, 5, 0, 50),
			BackgroundTransparency = 1,
			Text                   = cosmetic.description or "",
			TextColor3             = C.text_dim,
			TextWrapped            = true,
			TextSize               = 11,
			Font                   = Enum.Font.Gotham,
			TextXAlignment         = Enum.TextXAlignment.Left,
			TextYAlignment         = Enum.TextYAlignment.Top,
		}),

		-- Equipped badge
		equippedBadge = isEquipped and e("TextLabel", {
			Size                   = UDim2.fromScale(0.031, 0.015),
			Position               = UDim2.new(1, -65, 1, -22),
			BackgroundColor3       = C.accent,
			BackgroundTransparency = 0.1,
			Text                   = "EQUIPPED",
			TextColor3             = C.panel,
			TextScaled             = true,
			Font                   = Enum.Font.GothamBold,
			BorderSizePixel        = 0,
		}, {
			corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
		}) or nil,

		-- Locked overlay
		lockedOverlay = (not isOwned) and e("Frame", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.6,
			BorderSizePixel        = 0,
		}, {
			corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
			lock = e("TextLabel", {
				Size                   = UDim2.fromScale(1, 0.4),
				AnchorPoint            = Vector2.new(0.5, 0.5),
				Position               = UDim2.fromScale(0.5, 0.5),
				BackgroundTransparency = 1,
				Text                   = "LOCKED",
				TextColor3             = C.text_dim,
				TextScaled             = true,
				Font                   = Enum.Font.GothamBold,
			}),
		}) or nil,
	})
end

-- ═══════════════════════════════════════════════════════════
-- TAB BUTTON
-- ═══════════════════════════════════════════════════════════

local function TabButton(props)
	local isActive = props.isActive
	return e("TextButton", {
		Size             = UDim2.new(0.5, -4, 0, 36),
		BackgroundColor3 = isActive and C.tab_active or C.tab_bg,
		Text             = props.label,
		TextColor3       = isActive and C.accent or C.text_dim,
		Font             = Enum.Font.GothamBold,
		TextScaled       = true,
		BorderSizePixel  = 0,
		AutoButtonColor  = false,
		LayoutOrder      = props.order or 0,
		[React.Event.Activated] = props.onActivated,
	}, {
		corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
	})
end

-- ═══════════════════════════════════════════════════════════
-- WARDROBE ROOT
-- ═══════════════════════════════════════════════════════════

local function WardrobeUI(props)
	local onClose = props.onClose

	local activeTab, setActiveTab = useState("headgear")
	local wardrobe, setWardrobe   = useState({ owned = {}, equipped = {}, className = nil })

	-- Subscribe to CosmeticClient updates
	useEffect(function()
		-- Seed with current data
		setWardrobe({
			owned     = CosmeticClient.GetOwned(),
			equipped  = CosmeticClient.GetEquipped(),
			className = CosmeticClient.GetClassName(),
		})

		-- Request fresh data from server
		CosmeticClient.RequestWardrobe()

		-- Listen for updates
		local unsub = CosmeticClient.OnWardrobeUpdated(function(data)
			setWardrobe({
				owned     = data.owned     or {},
				equipped  = data.equipped  or {},
				className = data.className or nil,
			})
		end)

		return function()
			if unsub then unsub() end
		end
	end, {})

	local function onSelectCosmetic(cosmeticId)
		CosmeticClient.EquipCosmetic(cosmeticId)
	end

	local function onUnequipSlot()
		CosmeticClient.UnequipSlot(activeTab)
	end

	-- ── Build card list ───────────────────────────────────
	-- We need access to the cosmetic catalogs. Since CosmeticConfig is a
	-- server module, we inline a lightweight catalog lookup via known IDs
	-- from the wardrobe.owned table.  The server already validated
	-- ownership and class restrictions.  For card display we use the
	-- owned IDs and the equipped map.

	local cardChildren = {
		layout = e("UIGridLayout", {
			CellSize                = UDim2.fromScale(0.068, 0.102),
			CellPadding             = UDim2.fromOffset(8, 8),
			FillDirection           = Enum.FillDirection.Horizontal,
			HorizontalAlignment     = Enum.HorizontalAlignment.Left,
			SortOrder               = Enum.SortOrder.LayoutOrder,
		}),
	}

	-- Build simple cosmetic entries from owned IDs.
	-- The full catalog data is on the server; here we show id + equipped state.
	local equippedId = wardrobe.equipped[activeTab]

	local idx = 0
	for cosmeticId, _ in pairs(wardrobe.owned) do
		local isHeadgear = matchesAnyPattern(cosmeticId, SUPPORTED_HEADGEAR_PATTERNS)
		local isSupportedOutfit = matchesAnyPattern(cosmeticId, SUPPORTED_OUTFIT_PATTERNS)
		local belongsToTab = (activeTab == "headgear" and isHeadgear)
			or (activeTab == "outfit" and isSupportedOutfit)

		if belongsToTab then
			idx = idx + 1
			cardChildren["card_" .. cosmeticId] = e(CosmeticCard, {
				cosmetic = {
					id          = cosmeticId,
					name        = cosmeticId:gsub("_", " "):gsub("(%a)([%w_']*)", function(a, b) return string.upper(a) .. b end),
					rarity      = "Common",
					description = "",
				},
				isEquipped = (cosmeticId == equippedId),
				isOwned    = true,
				onSelect   = onSelectCosmetic,
			})
		end
	end

	return e("Frame", {
		Name                   = "WardrobeUI",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = 20,
	}, {
		-- Overlay
		overlay = e("Frame", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = C.overlay,
			BackgroundTransparency = 0.35,
		}),

		-- Panel
		panel = e("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = UDim2.fromScale(0.5, 0.5),
			Size             = UDim2.fromScale(0.55, 0.65),
			BackgroundColor3 = C.panel,
			BorderSizePixel  = 0,
		}, {
			corner = e("UICorner", { CornerRadius = UDim.new(0, 12) }),

			-- Title
			title = e("TextLabel", {
				Size                   = UDim2.new(1, -100, 0, 40),
				Position               = UDim2.new(0, 16, 0, 10),
				BackgroundTransparency = 1,
				Text                   = "Wardrobe",
				TextColor3             = C.text,
				TextScaled             = true,
				Font                   = Enum.Font.GothamBold,
				TextXAlignment         = Enum.TextXAlignment.Left,
			}),

			-- Close button
			closeBtn = e("TextButton", {
				AnchorPoint      = Vector2.new(1, 0),
				Position         = UDim2.new(1, -10, 0, 10),
				Size             = UDim2.fromScale(0.019, 0.033),
				BackgroundColor3 = C.btn_close,
				Text             = "X",
				TextColor3       = C.text,
				TextScaled       = true,
				Font             = Enum.Font.GothamBold,
				BorderSizePixel  = 0,
				[React.Event.Activated] = onClose,
			}, {
				corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			}),

			-- Tab bar
			tabBar = e("Frame", {
				Position               = UDim2.new(0, 16, 0, 56),
				Size                   = UDim2.new(1, -32, 0, 36),
				BackgroundTransparency = 1,
			}, {
				layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding       = UDim.new(0, 8),
				}),
				headgearTab = e(TabButton, {
					label       = "Headgear",
					isActive    = activeTab == "headgear",
					order       = 1,
					onActivated = function() setActiveTab("headgear") end,
				}),
				outfitTab = e(TabButton, {
					label       = "Outfit",
					isActive    = activeTab == "outfit",
					order       = 2,
					onActivated = function() setActiveTab("outfit") end,
				}),
			}),

			-- Unequip button
			unequipBtn = e("TextButton", {
				Position         = UDim2.new(0, 16, 0, 100),
				Size             = UDim2.fromScale(0.063, 0.026),
				BackgroundColor3 = C.btn_unequip,
				Text             = "Unequip",
				TextColor3       = C.text,
				TextScaled       = true,
				Font             = Enum.Font.Gotham,
				BorderSizePixel  = 0,
				[React.Event.Activated] = onUnequipSlot,
			}, {
				corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			}),

			-- Scrolling card grid
			cardScroll = e("ScrollingFrame", {
				Position               = UDim2.new(0, 16, 0, 138),
				Size                   = UDim2.new(1, -32, 1, -154),
				BackgroundTransparency = 1,
				ScrollBarThickness     = 4,
				BorderSizePixel        = 0,
				CanvasSize             = UDim2.fromScale(0, 0),
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
			}, cardChildren),
		}),
	})
end

return WardrobeUI
