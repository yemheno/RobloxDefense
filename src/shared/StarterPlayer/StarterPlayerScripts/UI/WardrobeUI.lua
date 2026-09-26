-- UI/WardrobeUI.lua
--[[
    WardrobeUI
    ==========
    React component for browsing and equipping cosmetics.
    §AGX/UI-P6: AppWindow (windowed; sheet on phone) + Tabs + Button + Card
    grid, design px inside UIScaleRoot.Local. Removed: the hand-rolled
    overlay/panel/title/"X" close, TabButton, the hitArea/minText helpers,
    the private palette and RARITY_COLORS (Theme.Roles.rarity), and the
    154 px chrome subtraction that left the grid 80-100 px tall on phones.

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

-- §AGX/UI-P6: shared components
local Common      = script.Parent:WaitForChild("Common")
local AppWindow   = require(Common:WaitForChild("AppWindow"))
local Theme       = require(Common:WaitForChild("Theme"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local Text        = require(Common:WaitForChild("Text"))
local Button      = require(Common:WaitForChild("Button"))
local Tabs        = require(Common:WaitForChild("Tabs"))
local Card        = require(Common:WaitForChild("Card"))
local GamepadFocus = require(Common:WaitForChild("GamepadFocus"))   -- §AGX/UI-FIX: R3

-- §AGX/UI-FIX: R3: PanelStack.EntryContext, nil-safe (nil outside a PanelHost).
local EntryContext = nil
do
	local shell = script.Parent:FindFirstChild("Shell")
	local mod = shell and shell:FindFirstChild("PanelStack")
	if mod then
		local ok, PanelStack = pcall(require, mod)
		if ok and type(PanelStack) == "table" then EntryContext = PanelStack.EntryContext end
	end
end
EntryContext = EntryContext or React.createContext(nil)

local R  = Theme.Roles
local SP = Theme.Space

-- §AGX/UI-P6: design px
local CELL        = Vector2.new(168, 88)
local UNEQUIP_W   = 132
local TOOLBAR_H   = Theme.Metrics.tabs.height   -- 44

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

	-- §AGX/UI-P6: Card (rarity stroke, blue selected ring, EQUIPPED badge,
	-- locked look).
	local rarity = string.lower(cosmetic.rarity or "Common")
	return e(Card, {
		title       = cosmetic.name or cosmetic.id,
		subtitle    = (cosmetic.description ~= nil and cosmetic.description ~= "")
			and ((cosmetic.rarity or "Common") .. " · " .. cosmetic.description)
			or (cosmetic.rarity or "Common"),
		rarity      = R.rarity[rarity] and rarity or "common",
		selected    = isEquipped,
		locked      = not isOwned,
		badge       = isEquipped and "Equipped" or nil,
		size        = UDim2.fromScale(1, 1),   -- the grid's CellSize wins
		layoutOrder = isEquipped and 0 or 1,
		onActivated = function()
			if isOwned and onSelect then onSelect(cosmetic.id) end
		end,
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
			-- §AGX/UI-P1 M14/T27 / §AGX/UI-P6: design px cells (>= 44 tall).
			CellSize                = UDim2.fromOffset(CELL.X, CELL.Y),
			CellPadding             = UDim2.fromOffset(SP.sm, SP.sm),
			FillDirection           = Enum.FillDirection.Horizontal,
			HorizontalAlignment     = Enum.HorizontalAlignment.Left,
			SortOrder               = Enum.SortOrder.LayoutOrder,
		}),
		pad = e("UIPadding", {
			PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4),   -- room for the badge
			PaddingBottom = UDim.new(0, SP.lg),
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

	-- §AGX/UI-FIX: R3: explicit gamepad first focus = the first item card
	-- (top-left of the grid), never "Unequip" in the top row. A Card has no
	-- ref, and the cards arrive with RequestWardrobe after mount, so this is
	-- a first focus scoped to the grid that waits for the cards (and one
	-- frame for the grid layout) instead of PanelStack.useFirstFocus, which
	-- would fire once at mount on an empty grid. Gamepad only, while top.
	local entryCtx = React.useContext(EntryContext)
	local isTop = entryCtx == nil or entryCtx.top == true
	local gridRef = React.useRef(nil)
	GamepadFocus.useAutoSelect(gridRef, (isTop and idx > 0) and "cards" or nil,
		{ steal = true, defer = true })

	return e(AppWindow, {
		variant = "windowed",
		title   = "Wardrobe",
		icon    = "wardrobe",
		onClose = onClose,
		size    = UDim2.fromScale(0.62, 0.72),
		zIndex  = 20,
	}, {
		-- §AGX/UI-P6: design px from here down.
		content = e(UIScaleRoot.Local, { name = "WardrobeBody" }, {
			inner = e("Frame", {
				Name                   = "Inner",
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				pad = e("UIPadding", {
					PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
					PaddingTop = UDim.new(0, SP.md),
				}),
				-- Tab bar (Tabs) + Unequip on one 44 px row
				tabBar = e(Tabs, {
					size     = UDim2.new(1, -(UNEQUIP_W + SP.sm), 0, TOOLBAR_H),
					value    = activeTab,
					onChange = setActiveTab,
					items    = {
						{ id = "headgear", label = "Headgear" },
						{ id = "outfit",   label = "Outfit" },
					},
				}),
				unequipBtn = e(Button, {
					name        = "Unequip",
					variant     = "secondary",
					size        = "sm",
					width       = UNEQUIP_W,
					label       = "Unequip",
					tooltip     = "Revert this slot to the class default",
					anchorPoint = Vector2.new(1, 0),
					position    = UDim2.fromScale(1, 0),
					onActivated = onUnequipSlot,
				}),
				-- Scrolling card grid
				cardScroll = e("ScrollingFrame", {
					Name                   = "Grid",
					ref                    = gridRef,   -- §AGX/UI-FIX: R3
					Position               = UDim2.fromOffset(0, TOOLBAR_H + SP.md),
					Size                   = UDim2.new(1, 0, 1, -(TOOLBAR_H + SP.md)),
					BackgroundTransparency = 1,
					ScrollBarThickness     = Theme.Metrics.scrollBar,
					ScrollBarImageColor3   = R.text.secondary,
					BorderSizePixel        = 0,
					CanvasSize             = UDim2.fromScale(0, 0),
					AutomaticCanvasSize    = Enum.AutomaticSize.Y,
					ScrollingDirection     = Enum.ScrollingDirection.Y,
				}, cardChildren),
				empty = (idx == 0) and e(Text, {
					style    = "body",
					text     = "Nothing owned for this slot yet.",
					color    = "text.secondary",
					align    = "center",
					position = UDim2.fromOffset(0, TOOLBAR_H + SP.xl),
				}) or nil,
			}),
		}),
	})
end

return WardrobeUI
