-- UI/StatsMenu.lua
--
-- Stats allocation panel.
-- Shows the 5 primary stats (MIG/VIT/PRE/MAG/RSV) with + buttons,
-- the number of unallocated points, and a live preview of derived stats.
--
-- Data flow:
--   On mount    → FireServer("GetStats")
--   Server      → "StatsUpdate" { level, unallocated, allocated, derived }
--   Player [+]  → FireServer("AllocateStat", statName, 1)
--   Server      → "StatsUpdate" (fresh snapshot after every allocation)
--
-- §AGX/UI-P6: Theme v2 re-skin (docs/UI_REVAMP.md D1 Hybrid / D2).
--   • Chrome = AppWindow; body = design px inside UIScaleRoot.Local
--     (PanelHost has no UIScale), in one vertical ScrollingFrame.
--   • Two columns when the body is >= WIDE_MIN design px wide, stacked
--     otherwise (phone sheet, combat side sheet).
--   • "+" = IconButton (48 design px, blue secondary) with the §AGX/UI-P1
--     hold-to-repeat kept; Respec = danger Button + essence CurrencyPill.
--   • Private palette table, fromRGB literals, the hitArea helper and the
--     TextScaled labels are gone (Theme roles + Text).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")  -- §AGX/UI-P1
local GuiService        = game:GetService("GuiService")        -- §AGX/UI-FIX: R3
local React = require(ReplicatedStorage.Packages.React)

local Modules        = script.Parent.Parent:WaitForChild("Modules")
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- §AGX/UI-P6: shared components
local Common        = script.Parent:WaitForChild("Common")
local AppWindow     = require(Common:WaitForChild("AppWindow"))  -- §T10/U3
local Theme         = require(Common:WaitForChild("Theme"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))
local Text          = require(Common:WaitForChild("Text"))
local Button        = require(Common:WaitForChild("Button"))
local IconButton    = require(Common:WaitForChild("IconButton"))
local Panel         = require(Common:WaitForChild("Panel"))
local CurrencyPill  = require(Common:WaitForChild("CurrencyPill"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local GamepadFocus  = require(Common:WaitForChild("GamepadFocus"))   -- §AGX/UI-FIX: R3

-- §AGX/UI-FIX: R3: PanelStack.useFirstFocus, nil-safe (no-op outside a
-- PanelHost / without UI/Shell).
local useFirstFocus = function(_ref) end
do
	local shell = script.Parent:FindFirstChild("Shell")
	local mod = shell and shell:FindFirstChild("PanelStack")
	if mod then
		local ok, PanelStack = pcall(require, mod)
		if ok and type(PanelStack) == "table" and type(PanelStack.useFirstFocus) == "function" then
			useFirstFocus = PanelStack.useFirstFocus
		end
	end
end

local e = React.createElement
local R = Theme.Roles
local SP = Theme.Space

-- §AGX/UI-P6: layout in DESIGN px (phone scale).
local WIDE_MIN    = 600   -- body width for the two-column layout
local STAT_ROW_H  = 64
local DERIVED_ROW = 30
local PLUS_SIZE   = Theme.Metrics.iconButton.md   -- 48 (>= 44, §AGX/UI-P1 T11)
local ID_W        = 52

-- §AGX/UI-P6: the old label read "500 ♦", but the server charges
-- PlayerDataConfig.RESPEC_COSTS.*.essence = 25 (§AGX/X42), or 1 Respec
-- Scroll first. Display only; the server decides.
local RESPEC_ESSENCE = 25

-- §AGX/UI-P1: hold-to-repeat on "+": first point on press, then after
-- HOLD_DELAY_S one point every 1/HOLD_RATE_HZ s. Still one AllocateStat
-- event per point; the server limit for AllocateStat is the NetworkManager
-- default (30/s/player), so 8/s stays well under it.
local HOLD_DELAY_S = 0.4
local HOLD_RATE_HZ = 8

local function isPointer(input)
	return input ~= nil and (input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch)
end

-- ── Static metadata for each primary stat ─────────────────────────────────────
local STAT_META = {
	{ id = "MIG", name = "Might",      affects = "Damage / Armor" },
	{ id = "VIT", name = "Vitality",   affects = "Max Health" },
	{ id = "PRE", name = "Precision",  affects = "Penetration / Crit Chance" },
	{ id = "MAG", name = "Magic",      affects = "Magic Damage / Resource" },
	{ id = "RSV", name = "Resolve",    affects = "Cooldown Reduction / Status Resist" },
}

-- ── Derived stats shown in the right panel ────────────────────────────────────
local DERIVED_DISPLAY = {
	{ key = "Health",           label = "Max HP" },
	{ key = "Damage",           label = "Damage" },
	{ key = "Armor",            label = "Armor" },
	{ key = "Penetration",      label = "Penetration" },
	{ key = "CritChance",       label = "Crit Chance",         suffix = "%" },
	{ key = "CritDamage",       label = "Crit Damage",         suffix = "×",  fmt = "%.2f" },
	{ key = "CooldownReduction",label = "CDR",                 suffix = "%" },
	{ key = "StatusResistance", label = "Status Resistance",   suffix = "%" },
}

-- ── Helper: round a number for display ───────────────────────────────────────
local function fmtVal(v, fmt, suffix)
	if not v then return "—" end
	local formatted = string.format(fmt or "%.0f", v)
	return formatted .. (suffix or "")
end

-- ── StatRow ───────────────────────────────────────────────────────────────────
-- Renders one primary stat: [ID] [name/affects] [allocated] [+]
local function StatRow(props)
	local meta       = props.meta
	local allocated  = props.allocated  or 0
	local canAdd     = props.canAdd     -- bool
	local onAdd      = props.onAdd

	-- §AGX/UI-P1: hold-to-repeat state. Hooks are unconditional; refs let the
	-- repeat thread see the latest props without re-subscribing.
	local holdTokenRef   = React.useRef(0)
	local canAddRef      = React.useRef(canAdd)
	local onAddRef       = React.useRef(onAdd)
	local unallocatedRef = React.useRef(props.unallocated or 0)
	local plusHostRef    = React.useRef(nil)   -- §AGX/UI-P6: wraps the IconButton
	canAddRef.current      = canAdd
	onAddRef.current       = onAdd
	unallocatedRef.current = props.unallocated or 0

	local function addOnce()
		if canAddRef.current and onAddRef.current then
			onAddRef.current()
		end
	end

	local function onAddInputBegan(_rbx, input)
		if not isPointer(input) or not canAddRef.current then return end
		if input.UserInputState ~= Enum.UserInputState.Begin then return end
		holdTokenRef.current += 1
		local token = holdTokenRef.current
		-- Never send more points than were unallocated at press time.
		local budget = unallocatedRef.current
		local function fire()
			if budget <= 0 or not canAddRef.current then return false end
			budget -= 1
			addOnce()
			return true
		end
		fire()

		local endConn
		endConn = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
			local st = input.UserInputState
			if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
				if holdTokenRef.current == token then
					holdTokenRef.current += 1
				end
				endConn:Disconnect()
			end
		end)

		task.delay(HOLD_DELAY_S, function()
			while holdTokenRef.current == token do
				-- Safety net in case the mouse release never reaches `input`.
				if input.UserInputType == Enum.UserInputType.MouseButton1
					and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
					break
				end
				if not fire() then break end
				task.wait(1 / HOLD_RATE_HZ)
			end
		end)
	end
	local inputBeganRef = React.useRef(onAddInputBegan)
	inputBeganRef.current = onAddInputBegan

	-- §AGX/UI-P6: IconButton owns its InputBegan (pressed look + tooltip), so
	-- the hold-to-repeat press listener is connected on its instance.
	React.useEffect(function()
		local host = plusHostRef.current
		local btn = host and host:FindFirstChildWhichIsA("GuiButton")
		local conn = btn and btn.InputBegan:Connect(function(input)
			inputBeganRef.current(btn, input)
		end)
		return function()
			if conn then conn:Disconnect() end
			holdTokenRef.current += 1  -- cancel any running repeat on unmount
		end
	end, {})

	-- §AGX/UI-FIX: R3: gamepad first focus for the panel. Row 1 publishes
	-- its "+" (points to spend) or, with 0 points (the "+" is disabled and
	-- not selectable), its PlusHost frame, which is then a selectable
	-- no-op stop showing the focus ring on the row; never Respec. When the
	-- points arrive / run out while row 1 is focused, the focus moves
	-- between the two. SelectedObject is only ever set by the gamepad, so
	-- mouse / touch never see this.
	local isFirst = props.focusRef ~= nil
	React.useEffect(function()
		if not isFirst then return end
		local host = plusHostRef.current
		if not host then return end
		local btn = host:FindFirstChild("Add_" .. meta.id)
		props.focusRef.current = (canAdd and btn) or host
		local sel = GuiService.SelectedObject
		if canAdd and btn and sel == host then
			GamepadFocus.select(btn)
		elseif not canAdd and btn and sel == btn then
			GamepadFocus.select(host)
		end
	end)

	-- Pointer presses are handled on InputBegan above; Activated only covers
	-- gamepad / keyboard activation so a click doesn't add two points.
	local function onAddActivated(_rbx, input)
		if isPointer(input) then return end
		addOnce()
	end

	return e(Panel, {
		elevation   = "raised",
		padding     = "sm",
		size        = UDim2.new(1, 0, 0, STAT_ROW_H),
		layoutOrder = props.layoutOrder,
	}, {
		id = e(Text, {
			style    = "heading",
			text     = meta.id,
			color    = "accent.secondary",
			size     = UDim2.new(0, ID_W, 1, 0),
		}),
		name = e(Text, {
			style    = "label",
			text     = meta.name,
			position = UDim2.fromOffset(ID_W + SP.xs, 2),
			size     = UDim2.new(1, -(ID_W + SP.xs + 56 + PLUS_SIZE + SP.sm), 0, 22),
		}),
		aff = e(Text, {
			style    = "caption",
			text     = meta.affects,
			color    = "text.secondary",
			position = UDim2.fromOffset(ID_W + SP.xs, 24),
			size     = UDim2.new(1, -(ID_W + SP.xs + 56 + PLUS_SIZE + SP.sm), 0, 20),
		}),
		-- Allocated count (no minus button; use Full Respec)
		count = e(Text, {
			style       = "numeric",
			text        = tostring(allocated),
			color       = "accent.secondary",
			align       = "center",
			anchorPoint = Vector2.new(1, 0.5),
			position    = UDim2.new(1, -(PLUS_SIZE + SP.sm), 0.5, 0),
			size        = UDim2.fromOffset(56, 24),
		}),
		plus = e("Frame", {
			Name                   = "PlusHost",
			AnchorPoint            = Vector2.new(1, 0.5),
			Position               = UDim2.fromScale(1, 0.5),
			Size                   = UDim2.fromOffset(PLUS_SIZE, PLUS_SIZE),
			BackgroundTransparency = 1,
			ref                    = plusHostRef,
			-- §AGX/UI-FIX: R3: gamepad-only placeholder stop (row 1, 0 points).
			Selectable             = isFirst and not canAdd,
			SelectionImageObject   = GamepadFocus.ring("md"),
		}, {
			btn = e(IconButton, {
				name        = "Add_" .. meta.id,
				icon        = "plus",
				variant     = "secondary",
				size        = PLUS_SIZE,
				disabled    = not canAdd,
				onActivated = onAddActivated,
			}),
		}),
	})
end

-- ── DerivedRow ────────────────────────────────────────────────────────────────
local function DerivedRow(props)
	return e("Frame", {
		Name                   = "Derived_" .. props.label,
		Size                   = UDim2.new(1, 0, 0, DERIVED_ROW),
		BackgroundColor3       = R.surface.sunken,
		BackgroundTransparency = props.alt and 0.4 or 1,
		BorderSizePixel        = 0,
		LayoutOrder            = props.layoutOrder,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.sm }),
		pad = e("UIPadding", { PaddingLeft = UDim.new(0, SP.sm), PaddingRight = UDim.new(0, SP.sm) }),
		lbl = e(Text, {
			style = "body",
			text  = props.label,
			color = "text.secondary",
			size  = UDim2.fromScale(0.62, 1),
		}),
		val = e(Text, {
			style       = "numeric",
			text        = props.value,
			color       = "accent.secondary",
			align       = "right",
			anchorPoint = Vector2.new(1, 0),
			position    = UDim2.fromScale(1, 0),
			size        = UDim2.fromScale(0.38, 1),
		}),
	})
end

-- ── StatsMenu ─────────────────────────────────────────────────────────────────
local function StatsMenu(props)
	local onClose = props.onClose
	local ff = useFormFactor()   -- §AGX/UI-P6

	-- Server snapshot
	local stats, setStats = React.useState({
		level       = 1,
		unallocated = 0,
		allocated   = { MIG = 0, VIT = 0, PRE = 0, MAG = 0, RSV = 0 },
		derived     = {},
	})

	-- §AGX/UI-P6: body width in design px -> one or two columns.
	local bodyW, setBodyW = React.useState(WIDE_MIN)
	local onBodySize = React.useCallback(function(rbx)
		local w = rbx.AbsoluteSize.X
		if w > 0 then setBodyW(w / math.max(ff.uiScale or 1, 0.01)) end
	end, { ff.uiScale })

	-- Wire up once on mount
	React.useEffect(function()
		NetworkManager.FireServer("GetStats")

		local conn = NetworkManager.OnServerEvent("StatsUpdate", function(data)
			setStats({
				level       = data.level       or 1,
				unallocated = data.unallocated  or 0,
				allocated   = data.allocated   or {},
				derived     = data.derived     or {},
			})
		end)

		return function()
			if conn then conn:Disconnect() end
		end
	end, {})

	-- Allocate helper (server validates everything; no client-side lock needed)
	local function allocate(statId)
		NetworkManager.FireServer("AllocateStat", statId, 1)
	end

	-- Full respec helper
	-- §AGX/UI-P6: the message keeps its ok flag for the success/danger colour.
	local respecMsg, setRespecMsg = React.useState({ text = "", ok = true })

	local function respecStats()
		NetworkManager.FireServer("RespecStats")
	end

	-- Listen for respec result
	React.useEffect(function()
		local mounted = true
		local conn = NetworkManager.OnServerEvent("RespecResult", function(data)
			if data.ok then
				setRespecMsg({ text = "Stats reset!", ok = true })
			else
				setRespecMsg({ text = data.reason or "Cannot respec", ok = false })
			end
			task.delay(3, function() if mounted then setRespecMsg({ text = "", ok = true }) end end)
		end)
		return function()
			mounted = false
			if conn then conn:Disconnect() end
		end
	end, {})

	-- §AGX/UI-FIX: R3: explicit gamepad first focus = row 1's "+" (or the
	-- row itself with 0 points), never the Respec danger button above it.
	local firstFocusRef = React.useRef(nil)
	useFirstFocus(firstFocusRef)

	local wide = bodyW >= WIDE_MIN
	local gap = SP.md

	-- ── Build stat rows ───────────────────────────────────────────────────────
	local statRows = {
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0, SP.sm),
		}),
	}
	for i, meta in ipairs(STAT_META) do
		statRows["row_" .. meta.id] = e(StatRow, {
			meta        = meta,
			focusRef    = (i == 1) and firstFocusRef or nil,   -- §AGX/UI-FIX: R3
			allocated   = stats.allocated[meta.id] or 0,
			canAdd      = stats.unallocated > 0,
			unallocated = stats.unallocated,  -- §AGX/UI-P1: hold budget
			onAdd       = function() allocate(meta.id) end,
			layoutOrder = i,
		})
	end

	-- ── Build derived stat rows ───────────────────────────────────────────────
	local derivedRows = {
		heading = e(Text, { style = "heading", text = "Derived Stats", layoutOrder = 0 }),
	}
	for i, entry in ipairs(DERIVED_DISPLAY) do
		derivedRows["d_" .. i] = e(DerivedRow, {
			label       = entry.label,
			value       = fmtVal(stats.derived[entry.key], entry.fmt, entry.suffix),
			alt         = (i % 2 == 0),
			layoutOrder = i,
		})
	end

	local colW = wide and UDim.new(0.5, -gap / 2) or UDim.new(1, 0)

	-- ── Points + respec strip ─────────────────────────────────────────────────
	local hasPoints = stats.unallocated > 0
	local topStrip = e(Panel, {
		elevation   = "raised",
		padding     = "sm",
		size        = UDim2.fromScale(1, 0),
		autoSize    = "Y",
		accent      = hasPoints and "accent.secondary" or nil,
		layoutOrder = 1,
	}, {
		wrap = e("UIListLayout", {   -- wraps onto a second line on narrow bodies
			FillDirection     = Enum.FillDirection.Horizontal,
			SortOrder         = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding           = UDim.new(0, SP.md),
			Wraps             = true,
		}),
		points = e("Frame", {
			LayoutOrder            = 1,
			Size                   = UDim2.fromOffset(200, Theme.Metrics.button.sm),
			BackgroundTransparency = 1,
		}, {
			lbl = e(Text, {
				style = "caption", text = "Unallocated points", color = "text.secondary",
				size = UDim2.new(1, 0, 0, 18),
			}),
			val = e(Text, {
				style = "heading", text = tostring(stats.unallocated),
				color = hasPoints and "accent.secondary" or "text.secondary",
				position = UDim2.fromOffset(0, 18), size = UDim2.new(1, 0, 0, 24),
			}),
		}),
		-- Full Respec button (uses 1 Respec Scroll if owned, otherwise Essence — §AGX/X42)
		respec = e(Button, {
			name        = "Respec",   -- §AGX/UI-FIX: R3: ranked last for gamepad focus
			variant     = "danger",
			size        = "sm",
			label       = "Respec",
			layoutOrder = 2,
			tooltip     = "Resets every allocated point. Uses a Respec Scroll if you own one, otherwise Essence.",
			onActivated = respecStats,
		}),
		cost = e("Frame", {
			LayoutOrder            = 3,
			Size                   = UDim2.fromOffset(0, Theme.Metrics.button.sm),
			AutomaticSize          = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
		}, {
			layout = e("UIListLayout", {
				FillDirection     = Enum.FillDirection.Horizontal,
				SortOrder         = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding           = UDim.new(0, SP.xs),
			}),
			pill = e(CurrencyPill, { currency = "essence", value = RESPEC_ESSENCE, cost = true, layoutOrder = 1 }),
			orScroll = e(Text, {
				style = "caption", text = "or 1 Respec Scroll", color = "text.secondary",
				size = UDim2.fromOffset(0, 18), autoSize = "X", layoutOrder = 2,
			}),
		}),
		-- Respec feedback
		feedback = respecMsg.text ~= "" and e(Text, {
			style       = "label",
			text        = respecMsg.text,
			color       = respecMsg.ok and "state.success" or "state.danger",
			size        = UDim2.fromOffset(0, 20),
			autoSize    = "X",
			layoutOrder = 4,
		}) or nil,
	})

	local columns = e("Frame", {
		Name                   = "Columns",
		LayoutOrder            = 2,
		Size                   = UDim2.fromScale(1, 0),
		AutomaticSize          = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		layout = e("UIListLayout", {
			FillDirection = wide and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0, gap),
		}),
		-- Left: primary stat rows
		left = e("Frame", {
			Name                   = "Primary",
			LayoutOrder            = 1,
			Size                   = UDim2.new(colW, UDim.new(0, 0)),
			AutomaticSize          = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, statRows),
		-- Right: derived stats
		right = e(Panel, {
			name        = "Derived",
			elevation   = "flat",
			padding     = "md",
			layout      = "vertical",
			gap         = "xxs",
			size        = UDim2.new(colW, UDim.new(0, 0)),
			autoSize    = "Y",
			layoutOrder = 2,
		}, derivedRows),
	})

	-- ── Assemble (§T10/U3: chrome owned by AppWindow) ─────────────────────────
	return e(AppWindow, {
		variant = "windowed",
		title   = "Stats — Lv. " .. tostring(stats.level),
		icon    = "stats",
		onClose = onClose,
		size    = UDim2.fromScale(0.72, 0.78),
		-- §AGX/UI-P1: on touch, let AppWindow grow the window to the
		-- tallest height that fits under the topbar (it clamps).
		minSize = ff.isTouch and Vector2.new(0, 400) or nil,
		zIndex  = 10,
	}, {
		-- §AGX/UI-P6: design px from here down.
		content = e(UIScaleRoot.Local, { name = "StatsBody" }, {
			scroll = e("ScrollingFrame", {
				Name                   = "Scroll",
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				CanvasSize             = UDim2.new(0, 0, 0, 0),
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
				ScrollingDirection     = Enum.ScrollingDirection.Y,
				ScrollBarThickness     = Theme.Metrics.scrollBar,
				ScrollBarImageColor3   = R.text.secondary,
				[React.Change.AbsoluteSize] = onBodySize,
			}, {
				pad = e("UIPadding", {
					PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
					PaddingTop = UDim.new(0, SP.md), PaddingBottom = UDim.new(0, SP.lg),
				}),
				layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder     = Enum.SortOrder.LayoutOrder,
					Padding       = UDim.new(0, gap),
				}),
				top     = topStrip,
				columns = columns,
			}),
		}),
	})
end

return StatsMenu
