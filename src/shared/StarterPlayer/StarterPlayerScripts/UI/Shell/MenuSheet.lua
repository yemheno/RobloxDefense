-- UI/Shell/MenuSheet.lua
--[[
    §AGX/UI-P3: MenuSheet, the PRIMARY menu surface (shell-spec §0.2, §4.5, B5).
    Used on Phone (every place), collapsed Tablet (combat) and by the Desktop
    M key. Registry entry `menuSheet` (class menu, dismissOnBackdrop).

    Props (PanelHost passes the open() props plus onClose):
        place      = "Lobby"|"Plaza"|"Combat"   (default: PlayerScripts probe)
        onClose    = function(reason)           (PanelHost: close(id, "self"))
        onBackdrop = function()?                (A8 AppWindow; default onClose("backdrop"))
        onSelect   = function(id, item)?        (override; default PanelStack.replace)

    Anatomy (D1 Hybrid: blue body, orange ONLY on the ribbon and PLAY):
        AppWindow chrome   "MENU" orange ribbon, 48 px danger close (Layout.close)
        header slot        currency pills (D13) + the play group's entry:
                           Lobby PLAY = primary (orange) Button; elsewhere
                           LEAVE = secondary Button (opens the confirm)
        body               one section per group (label + UIGridLayout of
                           96x72 tiles, FillDirectionMaxCells = cols, mobile.md
                           §2.6). Sections flow left-to-right and wrap, so an
                           iPhone landscape sheet is two rows with no scroll:
                             CHARACTER x6 | PROGRESS x3  SOCIAL x2  STORE  SYSTEM
                           Tiles may shrink 96 -> 88 wide when that saves a row.
        Tabs               only when the sections overflow the sheet (portrait,
                           very short screens): a jump bar with scroll-spy.
    Narrow sheets (< 600 design px) move the pills into a strip on top of
    the body instead of the header.

    Sizing: design px inside UIScaleRoot.Local (correct in a legacy tree or
    inside a Root). Measured AbsoluteSize is divided by the target scale.
    Phone = AppWindow "sheet" (fills the safe area under the topbar);
    other kinds = a centred "windowed" card, max 780 design px wide, sized
    to its content. A PanelHost presentation (A8) overrides the variant.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local Modules       = PlayerScripts:WaitForChild("Modules")
local Common        = script.Parent.Parent:WaitForChild("Common")
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))
local AppWindow     = require(Common:WaitForChild("AppWindow"))
local Text          = require(Common:WaitForChild("Text"))
local Button        = require(Common:WaitForChild("Button"))
local Tabs          = require(Common:WaitForChild("Tabs"))
local CurrencyPill  = require(Common:WaitForChild("CurrencyPill"))
local Locale        = require(Modules:WaitForChild("Locale"))
local Badge         = require(script.Parent:WaitForChild("Badge"))
local MenuIcon      = require(script.Parent:WaitForChild("MenuIcon"))

local e = React.createElement
local R = Theme.Roles
local MM = Theme.Metrics.menu
local Model = MenuIcon.Model

local PAD        = Theme.Space.lg   -- body padding (16)
local HEAD_H     = 20               -- section label row
local HEAD_GAP   = 6
local WALLET_H   = 40               -- pill strip on narrow sheets
local WIDE_HEADER = 600             -- design px: pills fit in the header slot

-- ═══════════════════════════════════════════════════════════════════════════
-- Wallet (D13): module-level cache, wired at first require. MenuSurface
-- requires this module when the shell mounts, so the values are warm long
-- before the first open. NetworkManager listeners are independent, so this
-- sits beside the HUD's own (shell-spec §6).
-- ═══════════════════════════════════════════════════════════════════════════
local wallet = { loaded = false, essence = 0, merits = 0 }
local walletListeners = {}
local NetworkManager = nil

local function setWallet(data)
	if type(data) ~= "table" or (data.essence == nil and data.merits == nil) then return end
	wallet = {
		loaded  = true,
		essence = tonumber(data.essence) or wallet.essence,
		merits  = tonumber(data.merits) or wallet.merits,
	}
	for cb in pairs(walletListeners) do task.spawn(cb, wallet) end
end

do
	local mod = Modules:FindFirstChild("NetworkManager")
	local ok, nm = false, nil
	if mod then ok, nm = pcall(require, mod) end
	if ok and type(nm) == "table" and nm.OnServerEvent then
		NetworkManager = nm
		nm.OnServerEvent("PlayerInfoUpdate", setWallet)
		nm.OnServerEvent("CurrencyUpdate", setWallet)
	end
end

local function useWallet()
	local value, setValue = React.useState(wallet)
	React.useEffect(function()
		walletListeners[setValue] = true
		setValue(wallet)
		if not wallet.loaded and NetworkManager and NetworkManager.FireServer then
			NetworkManager.FireServer("GetPlayerInfo")
		end
		return function() walletListeners[setValue] = nil end
	end, {})
	return value
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Packing: sections flow left-to-right and wrap (design px).
-- ═══════════════════════════════════════════════════════════════════════════
local function packSections(sections, availW, tile)
	local gap, sGap, rGap = MM.tileGap, MM.sectionGap, MM.rowGap
	local maxCols = math.max(1, math.floor((availW + gap) / (tile.X + gap)))
	local placed = {}
	local x, y, rowH = 0, 0, 0
	for i, s in ipairs(sections) do
		local n = #s.items
		local cols = math.max(1, math.min(n, maxCols))
		local tileRows = math.ceil(n / cols)
		local w = cols * tile.X + (cols - 1) * gap
		local h = HEAD_H + HEAD_GAP + tileRows * tile.Y + (tileRows - 1) * gap
		if x > 0 and x + sGap + w > availW then
			y += rowH + rGap
			x, rowH = 0, 0
		end
		local px = (x > 0) and (x + sGap) or 0
		placed[i] = { section = s, x = px, y = y, w = w, h = h, cols = cols }
		x = px + w
		rowH = math.max(rowH, h)
	end
	return placed, (#sections > 0) and (y + rowH) or 0
end

--- Pick the tile size: the form factor's tile, or the 88-wide minimum when
--- that makes the content shorter (fewer rows).
local function layoutFor(sections, availW, baseTile)
	local placed, height = packSections(sections, availW, baseTile)
	if baseTile.X > MM.tileMinW then
		local narrow = Vector2.new(MM.tileMinW, baseTile.Y)
		local p2, h2 = packSections(sections, availW, narrow)
		if h2 < height then return p2, h2, narrow end
	end
	return placed, height, baseTile
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Pieces
-- ═══════════════════════════════════════════════════════════════════════════
local function SectionHead(props)
	return e("Frame", {
		Name                   = "Head",
		Size                   = UDim2.new(1, 0, 0, HEAD_H),
		BackgroundTransparency = 1,
		ZIndex                 = props.zIndex,
	}, {
		-- blue body-accent marker (Hybrid: the body accent is blue)
		marker = e("Frame", {
			AnchorPoint      = Vector2.new(0, 0.5),
			Position         = UDim2.new(0, 0, 0.5, 0),
			Size             = UDim2.fromOffset(3, 14),
			BackgroundColor3 = R.accent.secondary,
			BorderSizePixel  = 0,
			ZIndex           = props.zIndex,
		}, { corner = e("UICorner", { CornerRadius = Theme.Radius.pill }) }),
		label = e(Text, {
			style    = "label",
			text     = props.text,
			upper    = true,
			color    = "text.secondary",
			size     = UDim2.new(1, -9, 1, 0),
			position = UDim2.fromOffset(9, 0),
			zIndex   = props.zIndex,
		}),
	})
end

local function Section(props)
	local p = props.placed
	local tiles = {
		grid = e("UIGridLayout", {
			CellSize              = UDim2.fromOffset(props.tile.X, props.tile.Y),
			CellPadding           = UDim2.fromOffset(MM.tileGap, MM.tileGap),
			FillDirection         = Enum.FillDirection.Horizontal,
			FillDirectionMaxCells = p.cols,
			SortOrder             = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, item in ipairs(p.section.items) do
		tiles["t" .. i] = e(MenuIcon.Tile, {
			item        = item,
			size        = props.tile,
			badge       = props.getBadge(item.badgeKey),
			layoutOrder = i,
			zIndex      = props.zIndex + 1,
			tileRef     = (props.firstRef and i == 1) and props.firstRef or nil,
			onActivated = function() props.onPick(item) end,
		})
	end
	return e("Frame", {
		Name                   = "Section_" .. tostring(p.section.id),
		Position               = UDim2.fromOffset(p.x, p.y + props.offsetY),
		Size                   = UDim2.fromOffset(p.w, p.h),
		BackgroundTransparency = 1,
		ZIndex                 = props.zIndex,
	}, {
		head = e(SectionHead, { text = p.section.label, zIndex = props.zIndex }),
		grid = e("Frame", {
			Name                   = "Tiles",
			Position               = UDim2.fromOffset(0, HEAD_H + HEAD_GAP),
			Size                   = UDim2.new(1, 0, 1, -(HEAD_H + HEAD_GAP)),
			BackgroundTransparency = 1,
			ZIndex                 = props.zIndex,
		}, tiles),
	})
end

local function WalletRow(props)
	local w = props.wallet
	if not w.loaded then return nil end
	return e("Frame", {
		Name                   = "Wallet",
		AnchorPoint            = props.anchorPoint,
		Position               = props.position,
		Size                   = props.size or UDim2.new(0, 0, 1, 0),
		AutomaticSize          = if props.size then nil else Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder            = props.layoutOrder,
		ZIndex                 = props.zIndex,
	}, {
		layout = e("UIListLayout", {
			FillDirection       = Enum.FillDirection.Horizontal,
			HorizontalAlignment = props.align or Enum.HorizontalAlignment.Right,
			VerticalAlignment   = Enum.VerticalAlignment.Center,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Padding             = UDim.new(0, Theme.Space.sm),
		}),
		essence = e(CurrencyPill, { currency = "essence", value = w.essence, compact = true, layoutOrder = 1, zIndex = props.zIndex }),
		merits  = e(CurrencyPill, { currency = "merits",  value = w.merits,  compact = true, layoutOrder = 2, zIndex = props.zIndex }),
	})
end

--- The play group's entry as a header button: PLAY = the one primary (orange)
--- CTA; LEAVE = secondary (the confirm dialog carries the weight).
local function PlayButton(props)
	local item = props.item
	local isPlay = item.id == "play"
	local glyph = Theme.Glyphs[item.icon or ""] or ""
	return e(Button, {
		name        = "Cta_" .. tostring(item.id),
		variant     = isPlay and "primary" or "secondary",
		size        = "sm",
		label       = (isPlay and glyph ~= "") and (glyph .. "  " .. item.label) or item.label,
		disabled    = not item.available,
		tooltip     = (not item.available) and Model.reason(item, true) or nil,
		layoutOrder = props.layoutOrder,
		zIndex      = props.zIndex,
		onActivated = props.onActivated,
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MenuSheet
-- ═══════════════════════════════════════════════════════════════════════════
local function MenuSheet(props)
	local ff = useFormFactor()
	local scale = UIScaleRoot.useUIScale()
	local getBadge = Badge.useBadges()
	local walletNow = useWallet()
	local bodySize, setBodySize = React.useState(Vector2.zero)
	local activeId, setActiveId = React.useState(nil)
	local scrollRef = React.useRef(nil)
	local firstRef = React.useRef(nil)

	-- P7 hook: first focus for gamepad (no-op without PanelStack).
	local PS = Model.PanelStack()
	if PS and type(PS.useFirstFocus) == "function" then PS.useFirstFocus(firstRef) end

	local entryCtx = Model.useEntry()
	local place = Model.resolvePlace(props.place, entryCtx)
	local groups = Model.useGroups(place)  -- §AGX/X18b: re-reads on gate changes

	local playGroup, sections = nil, {}
	for _, g in ipairs(groups) do
		if g.id == "play" then playGroup = g else sections[#sections + 1] = g end
	end

	local isPhone = ff.kind == "Phone"
	local target = scale.target
	local rail = ff.design.rail or {}
	local baseTile = rail.tile or Vector2.new(96, 72)

	-- A-priori sheet width (design px) for the windowed card; the measured
	-- body width wins once known.
	local viewW = ff.viewport.X / target
	local viewH = ff.viewport.Y / target
	local edge = ff.design.edge or 16
	local cardW = math.min(MM.sheetMaxW, viewW - 2 * edge)
	local bodyW = (bodySize.X > 0) and bodySize.X or (isPhone and viewW or cardW)
	local wideHeader = bodyW >= WIDE_HEADER
	-- Content column: never wider than the card, centred in a wide sheet
	-- (the registry presents menuSheet as "sheet" on every form factor).
	local columnW = math.min(bodyW, MM.sheetMaxW)
	local sideInset = math.max(PAD, math.floor((bodyW - columnW) / 2) + PAD)
	local availW = math.max(baseTile.X, bodyW - 2 * sideInset)

	local placed, contentH, tile = layoutFor(sections, availW, baseTile)
	local walletStrip = (not wideHeader) and walletNow.loaded
	local offsetY = walletStrip and (WALLET_H + Theme.Space.md) or 0
	local canvasH = PAD + offsetY + contentH + PAD

	local tabsH = Theme.Metrics.tabs.height
	local bodyH = bodySize.Y
	local showTabs = (#sections > 1) and bodyH > 0 and canvasH > bodyH + 1

	local function close(reason)
		if props.onClose then props.onClose(reason) end
	end
	local function pick(item)
		if props.onSelect then
			props.onSelect(item.id, item)
		else
			Model.activate(item, place, { from = "menu" })
		end
	end

	-- Tabs jump + scroll-spy (only when overflowing).
	local function sectionTop(id)
		for _, p in ipairs(placed) do
			if p.section.id == id then return PAD + offsetY + p.y end
		end
		return 0
	end
	local function onTab(id)
		setActiveId(id)
		local sf = scrollRef.current
		if not sf then return end
		local maxY = math.max(0, sf.AbsoluteCanvasSize.Y - sf.AbsoluteWindowSize.Y) / target
		local y = math.clamp(sectionTop(id) - PAD, 0, maxY)
		TweenService:Create(sf, Theme.Motion.base, { CanvasPosition = Vector2.new(0, y) }):Play()
	end
	local function onScroll(sf)
		if not showTabs then return end
		local y = sf.CanvasPosition.Y + PAD + 4
		local current = nil
		for _, p in ipairs(placed) do
			if PAD + offsetY + p.y <= y then current = p.section.id end
		end
		if current and current ~= activeId then setActiveId(current) end
	end

	local canvas = {}
	if walletStrip then
		canvas.wallet = e(WalletRow, {
			wallet   = walletNow,
			align    = Enum.HorizontalAlignment.Left,
			position = UDim2.fromOffset(0, PAD),   -- the canvas is already inset by PAD
			size     = UDim2.new(1, 0, 0, WALLET_H),
			zIndex   = 3,
		})
	end
	local firstAssigned = false
	for i, p in ipairs(placed) do
		local useFirst = (not firstAssigned) and p.section.items[1] ~= nil and p.section.items[1].available
		if useFirst then firstAssigned = true end
		canvas["s" .. i] = e(Section, {
			placed   = p,
			tile     = tile,
			offsetY  = PAD + offsetY,
			getBadge = getBadge,
			onPick   = pick,
			firstRef = useFirst and firstRef or nil,
			zIndex   = 3,
		})
	end
	if #placed == 0 then
		canvas.empty = e(Text, {
			style    = "body",
			text     = "…",
			color    = "text.secondary",
			align    = "center",
			position = UDim2.fromOffset(0, PAD),
			zIndex   = 3,
		})
	end

	local tabItems = {}
	if showTabs then
		for _, s in ipairs(sections) do
			local keys = Model.badgeKeys(s.items)
			local n = Badge.sum(getBadge, keys)
			tabItems[#tabItems + 1] = { id = s.id, label = s.label, badge = (n > 0) and "•" or nil }
		end
	end

	local body = e(UIScaleRoot.Local, { name = "MenuBody", zIndex = 2 }, {
		measure = e("Frame", {
			Name                   = "Measure",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex                 = 2,
			[React.Change.AbsoluteSize] = function(rbx)
				local s = rbx.AbsoluteSize / target
				if (s - bodySize).Magnitude > 0.5 then setBodySize(s) end
			end,
		}, {
			tabs = showTabs and e(Tabs, {
				items    = tabItems,
				value    = activeId or (sections[1] and sections[1].id),
				onChange = onTab,
				fill     = false,
				zIndex   = 4,
			}) or nil,
			scroll = e("ScrollingFrame", {
				Name                   = "Sections",
				Position               = UDim2.fromOffset(0, showTabs and tabsH or 0),
				Size                   = UDim2.new(1, 0, 1, -(showTabs and tabsH or 0)),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				CanvasSize             = UDim2.fromOffset(0, canvasH),
				ScrollingDirection     = Enum.ScrollingDirection.Y,
				ScrollBarThickness     = Theme.Metrics.scrollBar,
				ScrollBarImageColor3   = R.text.secondary,
				ElasticBehavior        = Enum.ElasticBehavior.WhenScrollable,
				Selectable             = false,
				ZIndex                 = 2,
				[React.Ref]            = scrollRef,
				[React.Change.CanvasPosition] = onScroll,
			}, {
				pad = e("UIPadding", { PaddingLeft = UDim.new(0, sideInset), PaddingRight = UDim.new(0, sideInset) }),
				content = e("Frame", {
					Name                   = "Canvas",
					Position               = UDim2.fromOffset(0, 0),
					Size                   = UDim2.new(1, 0, 0, canvasH),
					BackgroundTransparency = 1,
					ZIndex                 = 2,
				}, canvas),
			}),
		}),
	})

	-- Header slot: pills (wide sheets) + the play group's entry.
	local slot = {
		layout = e("UIListLayout", {
			FillDirection       = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment   = Enum.VerticalAlignment.Center,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Padding             = UDim.new(0, Theme.Space.md),
		}),
		wallet = (wideHeader and walletNow.loaded) and e(WalletRow, { wallet = walletNow, layoutOrder = 1, zIndex = 5 }) or nil,
	}
	if playGroup then
		for i, item in ipairs(playGroup.items) do
			slot["cta" .. i] = e(PlayButton, {
				item        = item,
				layoutOrder = 10 + i,
				zIndex      = 5,
				onActivated = function() pick(item) end,
			})
		end
	end
	local headerContent = e("Frame", {
		Name                   = "MenuHeaderSlot",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = 5,
	}, slot)

	-- Outside a PanelHost (whose presentation wins in AppWindow): Phone =
	-- sheet, others = a windowed card sized to the content, in the caller's
	-- units (Offset x remaining scale).
	local variant = isPhone and "sheet" or "windowed"
	local size = nil
	if not isPhone and entryCtx == nil then
		local headerH = ff.design.header or 56
		local wantH = headerH + canvasH + ((showTabs and tabsH) or 0)
		local maxH = viewH - 2 * edge - (ff.topbar or 0) / target
		size = UDim2.fromOffset(cardW * scale.remaining, math.min(wantH, maxH) * scale.remaining)
	end

	return e(AppWindow, {
		variant       = variant,
		title         = Locale.Get("nav_menu_title"),
		icon          = "menu",
		size          = size,
		zIndex        = props.zIndex,
		headerContent = headerContent,
		onClose       = close,
		-- In a PanelHost, AppWindow falls back to the stack's back("backdrop").
		onBackdrop    = props.onBackdrop or ((entryCtx == nil) and function() close("backdrop") end or nil),
	}, { body = body })
end

return MenuSheet
