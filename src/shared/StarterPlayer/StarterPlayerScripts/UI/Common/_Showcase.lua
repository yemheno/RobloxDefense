-- UI/Common/_Showcase.lua
--[[
    §AGX/UI-P1v2: DEV-ONLY design-system showcase. NOT mounted by any App.
    Renders every Common component and the v2 tokens so the look can be
    reviewed per form factor (Studio Device Emulator: iPhone 844x390,
    Android 800x360, tablet 1024x768, 1080p).

    Mount it (Play Solo -> command bar switched to CLIENT):
        local P = game.Players.LocalPlayer
        local React = require(game.ReplicatedStorage.Packages.React)
        local ReactRoblox = require(game.ReplicatedStorage.Packages.ReactRoblox)
        local gui = Instance.new("ScreenGui")
        gui.Name = "ShowcaseGui"; gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true; gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.DisplayOrder = 45
        gui.Parent = P.PlayerGui
        ReactRoblox.createRoot(gui):render(React.createElement(
            require(P.PlayerScripts.UI.Common._Showcase), { withTooltipHost = false }))
    (withTooltipHost = false inside a Place whose App already mounts the
    TooltipHost; true when mounted in an empty baseplate.)
    Remove: gui:Destroy().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))
local Text          = require(Common:WaitForChild("Text"))
local Button        = require(Common:WaitForChild("Button"))
local IconButton    = require(Common:WaitForChild("IconButton"))
local Panel         = require(Common:WaitForChild("Panel"))
local Tabs          = require(Common:WaitForChild("Tabs"))
local Bar           = require(Common:WaitForChild("Bar"))
local Card          = require(Common:WaitForChild("Card"))
local CurrencyPill  = require(Common:WaitForChild("CurrencyPill"))
local Modal         = require(Common:WaitForChild("Modal"))
local Tooltip       = require(Common:WaitForChild("Tooltip"))
local SafeArea      = require(Common:WaitForChild("SafeArea"))
local AppWindow     = require(Common:WaitForChild("AppWindow"))

local e = React.createElement
local R = Theme.Roles

local function row(children, order, gap)
	local c = {
		layout = e("UIListLayout", {
			FillDirection     = Enum.FillDirection.Horizontal,
			SortOrder         = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding           = UDim.new(0, gap or Theme.Space.sm),
			Wraps             = true,
		}),
	}
	for k, v in pairs(children) do c[k] = v end
	return e("Frame", {
		LayoutOrder            = order,
		Size                   = UDim2.fromScale(1, 0),
		AutomaticSize          = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, c)
end

local function section(title, order, children)
	local c = { heading = e(Text, { style = "heading", text = title, layoutOrder = 0 }) }
	for k, v in pairs(children) do c[k] = v end
	return e(Panel, {
		elevation   = "flat",
		layout      = "vertical",
		gap         = "sm",
		size        = UDim2.fromScale(1, 0),
		autoSize    = "Y",
		layoutOrder = order,
	}, c)
end

local function swatch(name, color, order)
	return e("Frame", {
		LayoutOrder = order, Size = UDim2.fromOffset(120, 44),
		BackgroundColor3 = color, BorderSizePixel = 0,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.sm }),
		stroke = e("UIStroke", { Color = R.border.subtle, Thickness = 1 }),
		label = e("TextLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = name,
			TextColor3 = R.text.primary, TextStrokeTransparency = 0.3,
			FontFace = Theme.FontFaces.bold, TextSize = 12, TextWrapped = true,
		}),
	})
end

local function Showcase(props)
	local ff = useFormFactor()
	local scale = UIScaleRoot.useUIScale()
	local open, setOpen           = React.useState(true)
	local tab, setTab             = React.useState("a")
	local manyTab, setManyTab     = React.useState(1)
	local showModal, setShowModal = React.useState(false)
	local showWindow, setShowWindow = React.useState(nil)  -- nil | variant string
	local hp, setHp               = React.useState(0.62)
	local selectedCard, setSelectedCard = React.useState(2)

	local withHost = props.withTooltipHost ~= false
	local tooltipHost = withHost and e(UIScaleRoot.Root, { name = "ShowcaseTooltips", zIndex = Theme.Z.tooltip }, {
		host = e(Tooltip.Host),
	}) or nil

	if not open then
		return e(UIScaleRoot.Local, { name = "Showcase" }, {
			safe = e(SafeArea, { margin = true }, {
				reopen = e(IconButton, {
					icon = "menu", variant = "secondary", tooltip = "Open the design-system showcase",
					onActivated = function() setOpen(true) end,
				}),
			}),
			tooltips = tooltipHost,
		})
	end

	-- ── Sections ──
	local swatches = {}
	local n = 0
	for _, group in ipairs({ "surface", "text", "accent", "state", "currency" }) do
		for name, color in pairs(R[group]) do
			if typeof(color) == "Color3" then
				n += 1
				swatches["s" .. n] = swatch(group .. "." .. name, color, n)
			end
		end
	end

	local textRows = {}
	for i, style in ipairs({ "display", "title", "heading", "body", "label", "caption", "numeric" }) do
		local ty = Theme.typeFor(style, ff.kind)
		textRows[style] = e(Text, {
			style = style, layoutOrder = i,
			text = string.format("%s  %d px (min %d / max %d)  The quick brown fox", style, ty.size, ty.min, ty.max),
		})
	end
	textRows.secondary = e(Text, { style = "body", color = "text.secondary", layoutOrder = 20,
		text = "text.secondary on surface: 7.8:1 (was 5.2:1)" })
	textRows.disabled = e(Text, { style = "body", color = "text.disabled", layoutOrder = 21,
		text = "text.disabled: 4.6:1" })
	textRows.wrap = e(Text, { style = "body", wrap = true, layoutOrder = 22,
		text = "Wrapped body text grows in height. Bodies and lists use the blue accent; orange is reserved for window ribbons, primary CTAs and HUD vitals." })

	local buttons = {}
	for i, v in ipairs({ "primary", "secondary", "danger", "success", "ghost", "locked" }) do
		buttons[v] = e(Button, { variant = v, label = v, layoutOrder = i,
			tooltip = "variant = \"" .. v .. "\"", onActivated = function() print("[Showcase] " .. v) end })
	end
	buttons.sm = e(Button, { variant = "secondary", size = "sm", label = "sm 44", layoutOrder = 10 })
	buttons.lg = e(Button, { variant = "primary", size = "lg", label = "lg 56", icon = "shop", layoutOrder = 11 })
	buttons.dis = e(Button, { variant = "primary", label = "disabled", disabled = true, layoutOrder = 12 })
	buttons.load = e(Button, { variant = "primary", label = "loading", loading = true, layoutOrder = 13 })
	buttons.sel = e(Button, { variant = "secondary", label = "selected", selected = true, layoutOrder = 14 })
	buttons.wide = e(Button, { variant = "secondary", label = "width 240", width = 240, layoutOrder = 15 })

	local icons = {}
	for i, spec in ipairs({
		{ "close", "danger" }, { "back", "ghost" }, { "check", "secondary" }, { "plus", "primary" },
		{ "settings", "secondary" }, { "more", "ghost" },
	}) do
		icons[spec[1]] = e(IconButton, { icon = spec[1], variant = spec[2], layoutOrder = i,
			tooltip = spec[1] .. " / " .. spec[2], badge = (i == 5) and 3 or nil })
	end
	icons.lg = e(IconButton, { icon = "menu", variant = "secondary", size = "lg", layoutOrder = 10 })
	icons.wrapped = e(Tooltip.Tooltip, {
		text = "Tooltip wrapper: hover (PC), hold 0.35 s (touch), select (gamepad)",
		target = e(IconButton, { icon = "info", variant = "secondary", layoutOrder = 11 }),
	})

	local panels = {
		flat = e(Panel, { elevation = "flat", size = UDim2.fromOffset(160, 72), layoutOrder = 1 },
			{ t = e(Text, { style = "caption", text = "flat" }) }),
		raised = e(Panel, { elevation = "raised", size = UDim2.fromOffset(160, 72), layoutOrder = 2 },
			{ t = e(Text, { style = "caption", text = "raised" }) }),
		sunken = e(Panel, { elevation = "sunken", size = UDim2.fromOffset(160, 72), layoutOrder = 3 },
			{ t = e(Text, { style = "caption", text = "sunken" }) }),
		accent = e(Panel, { elevation = "raised", accent = "accent.secondary", size = UDim2.fromOffset(160, 72), layoutOrder = 4 },
			{ t = e(Text, { style = "caption", text = "accent (selected)" }) }),
	}

	local bars = {
		hp = e(Bar, { kind = "hp", vital = true, value = hp * 1200, max = 1200, label = "HP (vital chrome)", showValue = true, layoutOrder = 1 }),
		res = e(Bar, { kind = "resource", vital = true, value = 70, max = 100, label = "Resource (lightning)", effect = "lightning", layoutOrder = 2 }),
		xp = e(Bar, { kind = "xp", value = 3400, max = 5000, label = "XP", showValue = true, layoutOrder = 3 }),
		boss = e(Bar, { kind = "boss", bossPhase = 2, value = 0.55, max = 1, segments = 3, height = 20, label = "Boss (3 phases)", layoutOrder = 4 }),
		prog = e(Bar, { kind = "progress", value = 7, max = 10, label = "Achievement 7 / 10", showValue = true, layoutOrder = 5 }),
		ctl = row({
			minus = e(Button, { size = "sm", label = "HP -", layoutOrder = 1, onActivated = function() setHp(math.max(0, hp - 0.15)) end }),
			plus = e(Button, { size = "sm", label = "HP +", layoutOrder = 2, onActivated = function() setHp(math.min(1, hp + 0.15)) end }),
		}, 6),
	}

	local cards = {}
	for i, spec in ipairs({
		{ "Common Blade", "common", nil }, { "Rare Shield", "rare", "EQUIPPED" },
		{ "Epic Relic", "epic", nil }, { "Legendary Crown", "legendary", "NEW" },
	}) do
		cards["c" .. i] = e(Card, {
			title = spec[1], subtitle = "rarity = " .. spec[2], rarity = spec[2], icon = "equipment",
			badge = spec[3], selected = selectedCard == i, layoutOrder = i,
			size = UDim2.fromOffset(240, 0),
			onActivated = function() setSelectedCard(i) end,
			footer = e(CurrencyPill, { currency = (i % 2 == 0) and "essence" or "merits", value = i * 750, cost = true }),
		})
	end
	cards.locked = e(Card, { title = "Locked Slot", subtitle = "Reach level 20", locked = true,
		icon = "lock", layoutOrder = 9, size = UDim2.fromOffset(240, 0) })

	local pills = {
		m = e(CurrencyPill, { currency = "merits", value = 12500, layoutOrder = 1 }),
		es = e(CurrencyPill, { currency = "essence", value = 1234567, compact = true, layoutOrder = 2 }),
		lbl = e(CurrencyPill, { currency = "merits", value = 250, showLabel = true, layoutOrder = 3 }),
		tap = e(CurrencyPill, { currency = "essence", value = 80, onActivated = function() print("[Showcase] get more") end, layoutOrder = 4 }),
		cost = e(CurrencyPill, { currency = "essence", value = 500, cost = true, insufficient = true, layoutOrder = 5 }),
	}

	local overlays = row({
		modal = e(Button, { label = "Open Modal", layoutOrder = 1, onActivated = function() setShowModal(true) end }),
		auto = e(Button, { label = "Window auto", layoutOrder = 2, onActivated = function() setShowWindow("auto") end }),
		win = e(Button, { label = "Window windowed", layoutOrder = 3, onActivated = function() setShowWindow("windowed") end }),
		full = e(Button, { label = "Window fullscreen", layoutOrder = 4, onActivated = function() setShowWindow("fullscreen") end }),
	}, 1)

	local body = {
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0, Theme.Space.md),
		}),
		padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.Space.lg), PaddingRight = UDim.new(0, Theme.Space.lg),
			PaddingTop = UDim.new(0, Theme.Space.lg), PaddingBottom = UDim.new(0, Theme.Space.xxl),
		}),
		info = e(Text, { style = "caption", color = "text.secondary", layoutOrder = 0,
			text = string.format("FormFactor %s · input %s · uiScale %.2f (applied %.2f) · viewport %dx%d",
				ff.kind, ff.input, scale.target, scale.applied, ff.viewport.X, ff.viewport.Y) }),
		colours = section("Roles (Hybrid palette)", 1, { r = row(swatches, 1, 6) }),
		type = section("Type scale (" .. ff.kind .. ")", 2, textRows),
		buttons = section("Button (every target >= 44 px)", 3, { r = row(buttons, 1) }),
		icons = section("IconButton + Tooltip", 4, { r = row(icons, 1) }),
		tabs = section("Tabs", 5, {
			a = e(Tabs, { layoutOrder = 1, value = tab, onChange = setTab, items = {
				{ id = "a", label = "Skills" }, { id = "b", label = "Gear", badge = 2 }, { id = "c", label = "Locked", locked = true },
			} }),
			b = e(Tabs, { layoutOrder = 2, value = manyTab, onChange = setManyTab, items = {
				{ id = 1, label = "All" }, { id = 2, label = "Weapons" }, { id = 3, label = "Armor" },
				{ id = 4, label = "Relics" }, { id = 5, label = "Cosmetics" }, { id = 6, label = "Bundles" },
			} }),
			note = e(Text, { style = "caption", color = "text.secondary", layoutOrder = 3,
				text = "More than 4 tabs on Phone -> scrolling chip row" }),
		}),
		panels = section("Panel", 6, { r = row(panels, 1) }),
		bars = section("Bar", 7, bars),
		cards = section("Card", 8, { r = row(cards, 1) }),
		pills = section("CurrencyPill", 9, { r = row(pills, 1) }),
		overlays = section("Modal / Window", 10, { r = overlays }),
	}

	return e(UIScaleRoot.Local, { name = "Showcase", zIndex = Theme.Z.windowOver }, {
		backdrop = e("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = R.surface.base,
			BackgroundTransparency = 0.02, BorderSizePixel = 0, Active = true, ZIndex = 1,
		}),
		safe = e(SafeArea, { zIndex = 2 }, {
			top = e("Frame", {
				Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = R.surface.raised, BorderSizePixel = 0, ZIndex = 2,
			}, {
				title = e(Text, { style = "title", text = "UI Showcase (dev)", position = UDim2.fromOffset(16, 14), size = UDim2.new(1, -96, 0, 28), zIndex = 3 }),
				close = e(IconButton, { icon = "close", variant = "danger", anchorPoint = Vector2.new(1, 0.5),
					position = UDim2.new(1, -8, 0.5, 0), zIndex = 3, tooltip = "Hide the showcase",
					onActivated = function() setOpen(false) end }),
			}),
			scroll = e("ScrollingFrame", {
				Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 1, -56),
				BackgroundTransparency = 1, BorderSizePixel = 0,
				CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarThickness = Theme.Metrics.scrollBar, ScrollBarImageColor3 = R.text.secondary,
				ZIndex = 2,
			}, body),
		}),
		modal = showModal and e(Modal, {
			title = "Spend 500 Essence?",
			onDismiss = function() setShowModal(false) end,
			zIndex = 50,
			actions = {
				{ variant = "ghost", label = "Cancel", onActivated = function() setShowModal(false) end },
				{ variant = "primary", label = "Confirm", onActivated = function() setShowModal(false) end },
			},
		}, {
			msg = e(Text, { style = "body", wrap = true, color = "text.secondary",
				text = "Modal: scrim tap / ✕ dismisses. The primary CTA is the only orange element." }),
		}) or nil,
		window = showWindow and e(AppWindow, {
			variant = showWindow, title = "Window " .. showWindow, icon = "settings",
			onClose = function() setShowWindow(nil) end, zIndex = 60,
			headerContent = e(CurrencyPill, { currency = "merits", value = 4200,
				anchorPoint = Vector2.new(1, 0.5), position = UDim2.fromScale(1, 0.5) }),
		}, {
			pad = e("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingTop = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
			t = e(Text, { style = "body", wrap = true,
				text = "variant = \"" .. showWindow .. "\" on " .. ff.kind .. ". Auto = sheet on Phone, windowed elsewhere." }),
		}) or nil,
		tooltips = tooltipHost,
	})
end

return Showcase
