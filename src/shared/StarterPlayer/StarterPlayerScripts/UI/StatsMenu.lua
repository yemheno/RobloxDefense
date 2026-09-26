-- UI/StatsMenu.lua
--
-- Stats allocation panel.
-- Shows the 5 primary stats (MIG/VIT/PRE/MAG/RSV) with +/- buttons,
-- the number of unallocated points, and a live preview of derived stats.
--
-- Data flow:
--   On mount    → FireServer("GetStats")
--   Server      → "StatsUpdate" { level, unallocated, allocated, derived }
--   Player [+]  → FireServer("AllocateStat", statName, 1)
--   Player [-]  → FireServer("AllocateStat", statName, -1)
--   Server      → "StatsUpdate" (fresh snapshot after every allocation)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")  -- §AGX/UI-P1
local React = require(ReplicatedStorage.Packages.React)

local Modules        = script.Parent.Parent:WaitForChild("Modules")
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local AppWindow      = require(script.Parent:WaitForChild("Common"):WaitForChild("AppWindow"))  -- §T10/U3

-- ── Palette ───────────────────────────────────────────────────────────────────
local C = {
	bg         = Color3.fromRGB( 18,  18,  24),
	section    = Color3.fromRGB( 26,  26,  38),
	row_alt    = Color3.fromRGB( 30,  30,  44),
	btn_add    = Color3.fromRGB( 45, 140,  80),
	btn_sub    = Color3.fromRGB(140,  55,  55),
	btn_dis    = Color3.fromRGB( 40,  40,  55),
	points     = Color3.fromRGB(245, 195,  60),
	text       = Color3.fromRGB(220, 220, 230),
	text_dim   = Color3.fromRGB(140, 140, 160),
	text_val   = Color3.fromRGB(105, 190, 255),
	accent     = Color3.fromRGB(105, 190, 255),
	close_bg   = Color3.fromRGB( 80,  36,  36),
	close_text = Color3.fromRGB(245, 100, 100),
	white      = Color3.fromRGB(255, 255, 255),
}

-- §AGX/UI-P1: minimum tap target. T11: "+" was 34x17 px on a phone because
-- rows are 0.115 of a scaled panel. On touch devices rows get a 44 px pixel
-- height (in a scroll frame); desktop keeps the scale layout unchanged.
local MIN_TAP_PX = 44
local IS_TOUCH   = UserInputService.TouchEnabled

-- §AGX/UI-P1: hold-to-repeat on "+": first point on press, then after
-- HOLD_DELAY_S one point every 1/HOLD_RATE_HZ s. Still one AllocateStat
-- event per point; the server limit for AllocateStat is the NetworkManager
-- default (30/s/player), so 8/s stays well under it.
local HOLD_DELAY_S = 0.4
local HOLD_RATE_HZ = 8

-- §AGX/UI-P1: transparent hit box at least minSize (default 44x44), centred
-- on a visual unless anchor/position are given. The visual keeps its size.
local function hitArea(opts)
	return React.createElement("TextButton", {
		Name                   = "HitArea",
		AnchorPoint            = opts.anchor or Vector2.new(0.5, 0.5),
		Position               = opts.position or UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text                   = "",
		AutoButtonColor        = false,
		[React.Event.Activated]  = opts.onActivated,
		[React.Event.InputBegan] = opts.onInputBegan,
	}, {
		minSize = React.createElement("UISizeConstraint", {
			MinSize = opts.minSize or Vector2.new(MIN_TAP_PX, MIN_TAP_PX),
		}),
	})
end

-- §AGX/UI-P1: M11: TextScaled labels get a readable floor on phones.
local function minText()
	return React.createElement("UITextSizeConstraint", { MinTextSize = 12 })
end

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
-- Renders one primary stat: [name/affects] [allocated] [+]
local function StatRow(props)
	local meta       = props.meta
	local allocated  = props.allocated  or 0
	local canAdd     = props.canAdd     -- bool
	local onAdd      = props.onAdd
	local rowBg      = props.alt and C.row_alt or C.section

	local addBg = canAdd and C.btn_add or C.btn_dis

	-- §AGX/UI-P1: hold-to-repeat state. Hooks are unconditional; refs let the
	-- repeat thread see the latest props without re-subscribing.
	local holdTokenRef   = React.useRef(0)
	local canAddRef      = React.useRef(canAdd)
	local onAddRef       = React.useRef(onAdd)
	local unallocatedRef = React.useRef(props.unallocated or 0)
	canAddRef.current      = canAdd
	onAddRef.current       = onAdd
	unallocatedRef.current = props.unallocated or 0

	React.useEffect(function()
		return function()
			holdTokenRef.current += 1  -- cancel any running repeat on unmount
		end
	end, {})

	local function addOnce()
		if canAddRef.current and onAddRef.current then
			onAddRef.current()
		end
	end

	local function onAddInputBegan(_rbx, input)
		if not isPointer(input) or not canAddRef.current then return end
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

	-- Pointer presses are handled on InputBegan above; Activated only covers
	-- gamepad / keyboard activation so a click doesn't add two points.
	local function onAddActivated(_rbx, input)
		if isPointer(input) then return end
		addOnce()
	end

	return React.createElement("Frame", {
		Size             = UDim2.fromScale(1, 1),
		BackgroundColor3 = rowBg,
		BorderSizePixel  = 0,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.08, 0) }),

		-- Stat name + affects
		label = React.createElement("Frame", {
			Position               = UDim2.fromScale(0.02, 0),
			Size                   = UDim2.fromScale(0.56, 1),
			BackgroundTransparency = 1,
		}, {
			id = React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0, 0),
				Size                   = UDim2.fromScale(0.22, 1),
				BackgroundTransparency = 1,
				Text                   = meta.id,
				TextColor3             = C.accent,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
			}, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
			name = React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.22, 0),
				Size                   = UDim2.fromScale(0.40, 0.55),
				BackgroundTransparency = 1,
				Text                   = meta.name,
				TextColor3             = C.text,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
			}, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
			aff = React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.22, 0.52),
				Size                   = UDim2.fromScale(0.78, 0.48),
				BackgroundTransparency = 1,
				Text                   = meta.affects,
				TextColor3             = C.text_dim,
				Font                   = Enum.Font.Gotham,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
			}, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
		}),

		-- Allocated count (no minus button; use Full Respec)
		count = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.60, 0),
			Size                   = UDim2.fromScale(0.24, 1),
			BackgroundTransparency = 1,
			Text                   = tostring(allocated),
			TextColor3             = C.text_val,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
		}, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor

		-- Plus button
		btnAdd = React.createElement("TextButton", {
			Position         = UDim2.fromScale(0.86, 0.15),
			Size             = UDim2.fromScale(0.10, 0.70),
			BackgroundColor3 = addBg,
			BorderSizePixel  = 0,
			Text             = "+",
			TextColor3       = C.white,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			AutoButtonColor  = canAdd,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
			minText = minText(),  -- §AGX/UI-P1: M11 text floor
			-- §AGX/UI-P1: T11: 44x44 hit box (covers the visual), with
			-- hold-to-repeat.
			hit = hitArea({
				onActivated  = onAddActivated,
				onInputBegan = onAddInputBegan,
			}),
		}),
	})
end

-- ── DerivedRow ────────────────────────────────────────────────────────────────
local function DerivedRow(props)
	local bg = props.alt and C.row_alt or C.section
	return React.createElement("Frame", {
		Size             = UDim2.fromScale(1, 1),
		BackgroundColor3 = bg,
		BorderSizePixel  = 0,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.1, 0) }),
		lbl = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.04, 0),
			Size                   = UDim2.fromScale(0.58, 1),
			BackgroundTransparency = 1,
			Text                   = props.label,
			TextColor3             = C.text_dim,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
		val = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.62, 0),
			Size                   = UDim2.fromScale(0.38, 1),
			BackgroundTransparency = 1,
			Text                   = props.value,
			TextColor3             = C.text_val,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Right,
		}, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
	})
end

-- ── StatsMenu ─────────────────────────────────────────────────────────────────
local function StatsMenu(props)
	local onClose = props.onClose

	-- Server snapshot
	local stats, setStats = React.useState({
		level       = 1,
		unallocated = 0,
		allocated   = { MIG = 0, VIT = 0, PRE = 0, MAG = 0, RSV = 0 },
		derived     = {},
	})

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
	local respecMsg, setRespecMsg = React.useState("")

	local function respecStats()
		NetworkManager.FireServer("RespecStats")
	end

	-- Listen for respec result
	React.useEffect(function()
		local mounted = true
		local conn = NetworkManager.OnServerEvent("RespecResult", function(data)
			if data.ok then
				setRespecMsg("Stats reset!")
			else
				setRespecMsg(data.reason or "Cannot respec")
			end
			task.delay(3, function() if mounted then setRespecMsg("") end end)
		end)
		return function()
			mounted = false
			if conn then conn:Disconnect() end
		end
	end, {})

	-- ── Build stat rows ───────────────────────────────────────────────────────
	local statRowHeight = 0.115  -- fraction of the left panel height per row
	local statRows = {}
	for i, meta in ipairs(STAT_META) do
		local allocated = stats.allocated[meta.id] or 0
		statRows["row_" .. meta.id] = React.createElement("Frame", {
			-- §AGX/UI-P1: T11: 44 px pixel rows on touch (in a scroll frame).
			Size        = IS_TOUCH and UDim2.new(1, -6, 0, MIN_TAP_PX) or UDim2.fromScale(1, statRowHeight),
			LayoutOrder = i,
		}, {
			inner = React.createElement(StatRow, {
				meta      = meta,
				allocated = allocated,
				canAdd    = stats.unallocated > 0,
				unallocated = stats.unallocated,  -- §AGX/UI-P1: hold budget
				alt       = (i % 2 == 0),
				onAdd     = function() allocate(meta.id) end,
			}),
		})
	end
	statRows.layout = React.createElement("UIListLayout", {
		FillDirection     = Enum.FillDirection.Vertical,
		SortOrder         = Enum.SortOrder.LayoutOrder,
		Padding           = IS_TOUCH and UDim.new(0, 4) or UDim.new(0.012, 0),  -- §AGX/UI-P1
	})

	-- ── Build derived stat rows ───────────────────────────────────────────────
	local derivedRows = {}
	local derivedH = 1 / (#DERIVED_DISPLAY + 1)
	for i, entry in ipairs(DERIVED_DISPLAY) do
		local raw = stats.derived[entry.key]
		derivedRows["d_" .. i] = React.createElement("Frame", {
			Size        = UDim2.fromScale(1, derivedH),
			LayoutOrder = i,
		}, {
			inner = React.createElement(DerivedRow, {
				label = entry.label,
				value = fmtVal(raw, entry.fmt, entry.suffix),
				alt   = (i % 2 == 0),
			}),
		})
	end
	derivedRows.layout = React.createElement("UIListLayout", {
		FillDirection   = Enum.FillDirection.Vertical,
		SortOrder       = Enum.SortOrder.LayoutOrder,
		Padding         = UDim.new(0.010, 0),
	})

	-- ── Assemble (§T10/U3: chrome owned by AppWindow) ─────────────────────────
	return React.createElement(AppWindow, {
		variant = "windowed",
		title   = "Stats — Lv. " .. tostring(stats.level),
		icon    = "stats",
		onClose = onClose,
		size    = UDim2.fromScale(0.72, 0.78),
		-- §AGX/UI-P1: on touch, let AppWindow grow the window to the
		-- tallest height that fits under the topbar (it clamps).
		minSize = IS_TOUCH and Vector2.new(0, 400) or nil,
		zIndex  = 10,
	}, {
			-- Points badge
			pointsBadge = React.createElement("Frame", {
				Position         = UDim2.fromScale(0.03, 0.11),
				Size             = UDim2.fromScale(0.34, 0.07),
				BackgroundColor3 = Color3.fromRGB(38, 32, 12),
				BorderSizePixel  = 0,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
				lbl = React.createElement("TextLabel", {
					Size                   = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text                   = "★  Unallocated:  " .. tostring(stats.unallocated),
					TextColor3             = C.points,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
				}, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
			}),

			-- Full Respec button (uses 1 Respec Scroll if owned, otherwise 25 Essence — §AGX/X42)
			respecBtn = React.createElement("TextButton", {
				Position         = UDim2.fromScale(0.39, 0.11),
				Size             = UDim2.fromScale(0.28, 0.07),
				BackgroundColor3 = Color3.fromRGB(140, 50, 50),
				BorderSizePixel  = 0,
				Text             = "Respec  (Token / 500 ♦)",
				TextColor3       = C.white,
				Font             = Enum.Font.GothamBold,
				TextScaled       = true,
				[React.Event.Activated] = respecStats,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
				minText = minText(),  -- §AGX/UI-P1: M11 text floor
				-- §AGX/UI-P1: 44 px tall hit box, grown upward into the empty
				-- band above so it never covers the first stat row's "+".
				hit = hitArea({
					onActivated = respecStats,
					anchor      = Vector2.new(0.5, 1),
					position    = UDim2.fromScale(0.5, 1),
					minSize     = Vector2.new(0, MIN_TAP_PX),
				}),
			}),

			-- Respec feedback
			respecFeedback = respecMsg ~= "" and React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.39, 0.185),
				Size                   = UDim2.fromScale(0.28, 0.03),
				BackgroundTransparency = 1,
				Text                   = respecMsg,
				TextColor3             = Color3.fromRGB(255, 200, 100),
				Font                   = Enum.Font.Gotham,
				TextScaled             = true,
			}, { minText = minText() }) or nil,  -- §AGX/UI-P1: M11 text floor

			-- Left: primary stat rows
			-- §AGX/UI-P1: T11: on touch, 5 x 44 px rows don't fit a phone-height
			-- panel, so it scrolls. Desktop keeps the plain Frame.
			leftPanel = IS_TOUCH and React.createElement("ScrollingFrame", {
				Position               = UDim2.fromScale(0.03, 0.20),
				Size                   = UDim2.fromScale(0.56, 0.76),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				ScrollBarThickness     = 4,
				CanvasSize             = UDim2.fromScale(0, 0),
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
				ScrollingDirection     = Enum.ScrollingDirection.Y,
			}, statRows) or React.createElement("Frame", {
				Position               = UDim2.fromScale(0.03, 0.20),
				Size                   = UDim2.fromScale(0.56, 0.76),
				BackgroundTransparency = 1,
			}, statRows),

			-- Right: derived stats
			rightPanel = React.createElement("Frame", {
				Position         = UDim2.fromScale(0.62, 0.20),
				Size             = UDim2.fromScale(0.35, 0.76),
				BackgroundColor3 = C.section,
				BorderSizePixel  = 0,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.03, 0) }),
				header = React.createElement("TextLabel", {
					Position               = UDim2.fromScale(0, 0),
					Size                   = UDim2.fromScale(1, 0.08),
					BackgroundTransparency = 1,
					Text                   = "Derived Stats",
					TextColor3             = C.accent,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
				}, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
				rows = React.createElement("Frame", {
					Position               = UDim2.fromScale(0.03, 0.09),
					Size                   = UDim2.fromScale(0.94, 0.88),
					BackgroundTransparency = 1,
				}, derivedRows),
			}),
	})
end

return StatsMenu
