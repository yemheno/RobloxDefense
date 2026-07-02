-- UI/ClassMenu.lua
--
-- React component: four-column class selection panel.
-- All sizes are %-based (Scale) so the layout adapts to any screen, including mobile.
-- Strings are resolved through Locale so the menu can be translated.
--
-- Data flow:
--   ① On mount  →  FireServer("GetPlayerInfo")
--   ② Server    →  "PlayerInfoUpdate" { level, activeClass, unlockedClasses }
--   ③ Player clicks "Switch"  →  FireServer("RequestClassSwitch", className)
--   ④ Server    →  "ClassSwitchResult" (ok, payload)
--                  on success: re-request PlayerInfoUpdate for clean refresh

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Modules        = script.Parent.Parent:WaitForChild("Modules")
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local Locale         = require(Modules:WaitForChild("Locale"))
local ClassCatalog   = require(Modules:WaitForChild("ClassCatalog"))
local AppWindow      = require(script.Parent:WaitForChild("Common"):WaitForChild("AppWindow"))  -- §T10/U3

-- ── Colour palette ────────────────────────────────────────────────────────────
local C = {
	bg_dark   = Color3.fromRGB( 18,  18,  24),   -- panel & main backdrop fill
	bg_col    = Color3.fromRGB( 24,  24,  33),   -- individual column background
	bg_header = Color3.fromRGB( 30,  30,  44),   -- column header strip
	bg_slot   = Color3.fromRGB( 40,  40,  55),   -- filled class slot card
	bg_empty  = Color3.fromRGB( 26,  26,  36),   -- placeholder slot card
	accent    = Color3.fromRGB(105, 190, 255),   -- column header text
	btn_avail  = Color3.fromRGB( 60, 135, 235),  -- available   → blue
	btn_active = Color3.fromRGB( 45, 175,  95),  -- active      → green
	btn_locked = Color3.fromRGB( 58,  58,  78),  -- locked      → muted
	text       = Color3.fromRGB(225, 225, 230),
	text_dim   = Color3.fromRGB(140, 140, 160),
	text_lock  = Color3.fromRGB(110, 110, 132),
	white      = Color3.fromRGB(255, 255, 255),
	close_bg   = Color3.fromRGB( 80,  36,  36),
	close_text = Color3.fromRGB(245, 100, 100),
}

-- ── Slot layout constants (all scale, relative to the column Frame) ───────────
--   Header:    Y 0.000 → 0.095
--   Slots:     first slot Y starts at 0.110, each slot is 0.205 tall,
--              step is 0.225 (includes a 0.020 gap)
local SLOT_Y_START = 0.110
local SLOT_Y_STEP  = 0.225
local SLOT_H       = 0.205
local SLOT_X       = 0.04     -- inset from column left edge
local SLOT_W       = 0.92     -- fraction of column width

-- ── Helper ───────────────────────────────────────────────────────────────────
local function getSlotState(entry, playerInfo)
	if playerInfo.activeClass == entry.id then
		return "active"
	end
	if playerInfo.level < entry.requiredLevel then
		return "locked"
	end
	if not table.find(playerInfo.unlockedClasses, entry.id) then
		return "locked"
	end
	return "available"
end

-- ── ClassSlot ─────────────────────────────────────────────────────────────────
--   props: entry, state, switching, onSwitch, yPos, readOnly
local function ClassSlot(props)
	local entry      = props.entry
	local state      = props.state
	local switching  = props.switching
	local onSwitch   = props.onSwitch
	local yPos       = props.yPos
	local readOnly   = props.readOnly  -- when true, class change is blocked

	local isPending   = (switching == entry.id)
	-- readOnly blocks the switch button regardless of unlock state
	local isClickable = (state == "available") and (switching == nil) and (not readOnly)

	local btnBg = (state == "active" and C.btn_active)
		or (state == "locked" and C.btn_locked)
		or C.btn_avail

	local btnText = (state == "active"  and Locale.Get("class_active"))
		or (readOnly and state == "available" and Locale.Get("class_locked_match") or nil)
		or (state == "locked"  and Locale.Get("class_locked", entry.requiredLevel))
		or (isPending          and "…")
		or Locale.Get("class_switch")

	return React.createElement("Frame", {
		Position         = UDim2.fromScale(SLOT_X, yPos),
		Size             = UDim2.fromScale(SLOT_W, SLOT_H),
		BackgroundColor3 = C.bg_slot,
		BorderSizePixel  = 0,
	}, {
		corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0.05, 0),
		}),

		-- Class name (bold, top third)
		className = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.05, 0.06),
			Size                   = UDim2.fromScale(0.90, 0.32),
			BackgroundTransparency = 1,
			Text                   = Locale.Get(entry.localeKey .. "_name"),
			TextColor3             = C.text,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}),

		-- Short description (small, middle)
		desc = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.05, 0.38),
			Size                   = UDim2.fromScale(0.90, 0.27),
			BackgroundTransparency = 1,
			Text                   = Locale.Get(entry.localeKey .. "_desc"),
			TextColor3             = C.text_dim,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}),

		-- Action button (bottom-right).
		-- §LD-CM1 fix: was 55 % × 27 % of slot which felt oversized
		-- relative to the class-name and description rows above it
		-- ("too big / overflowing" per playtest). Trimmed to a more
		-- compact 40 % × 20 % pill shape, anchored bottom-right via
		-- AnchorPoint so it stays glued to the corner regardless of
		-- the slot's aspect ratio.
		btn = React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 1),
			Position         = UDim2.fromScale(0.94, 0.92),
			Size             = UDim2.fromScale(0.40, 0.20),
			BackgroundColor3 = btnBg,
			BorderSizePixel  = 0,
			AutoButtonColor  = isClickable,
			Text             = btnText,
			TextColor3       = C.white,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			[React.Event.Activated] = isClickable and onSwitch or nil,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
			-- §LD-CM1: clamp the visible label to 70 % of the button
			-- height so even long localised strings ("On cooldown (3s)",
			-- "Class is locked while in defense") don't render edge-to-
			-- edge inside the pill.
			pad = React.createElement("UIPadding", {
				PaddingTop    = UDim.new(0.15, 0),
				PaddingBottom = UDim.new(0.15, 0),
				PaddingLeft   = UDim.new(0.10, 0),
				PaddingRight  = UDim.new(0.10, 0),
			}),
		}),
	})
end

-- ── PlaceholderSlot ───────────────────────────────────────────────────────────
--   props: yPos
local function PlaceholderSlot(props)
	return React.createElement("Frame", {
		Position         = UDim2.fromScale(SLOT_X, props.yPos),
		Size             = UDim2.fromScale(SLOT_W, SLOT_H),
		BackgroundColor3 = C.bg_empty,
		BorderSizePixel  = 0,
	}, {
		corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0.05, 0),
		}),
		lbl = React.createElement("TextLabel", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text                   = Locale.Get("class_empty"),
			TextColor3             = C.text_lock,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
		}),
	})
end

-- ── CategoryColumn ────────────────────────────────────────────────────────────
--   props: category, playerInfo, switching, onSwitch, readOnly, LayoutOrder
local function CategoryColumn(props)
	local category   = props.category
	local playerInfo = props.playerInfo
	local switching  = props.switching
	local onSwitch   = props.onSwitch
	local readOnly   = props.readOnly

	local children = {}

	-- Header strip
	children.header = React.createElement("Frame", {
		Position         = UDim2.fromScale(0, 0),
		Size             = UDim2.fromScale(1, 0.095),
		BackgroundColor3 = C.bg_header,
		BorderSizePixel  = 0,
	}, {
		lbl = React.createElement("TextLabel", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text                   = Locale.Get(category.headerKey),
			TextColor3             = C.accent,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
		}),
	})

	-- Real class slots
	for i, entry in ipairs(category.classes) do
		local yPos = SLOT_Y_START + (i - 1) * SLOT_Y_STEP
		children["slot_" .. i] = React.createElement(ClassSlot, {
			entry     = entry,
			state     = getSlotState(entry, playerInfo),
			switching = switching,
			yPos      = yPos,
			readOnly  = readOnly,
			onSwitch  = function()
				onSwitch(entry.id)
			end,
		})
	end

	-- Placeholders to fill remaining slots
	for i = #category.classes + 1, ClassCatalog.SlotsPerColumn do
		local yPos = SLOT_Y_START + (i - 1) * SLOT_Y_STEP
		children["ph_" .. i] = React.createElement(PlaceholderSlot, {
			yPos = yPos,
		})
	end

	return React.createElement("Frame", {
		Size             = UDim2.fromScale(0.244, 0.98),
		BackgroundColor3 = C.bg_col,
		BorderSizePixel  = 0,
		LayoutOrder      = props.LayoutOrder,
	}, children)
end

-- ── ClassMenu ─────────────────────────────────────────────────────────────────
local function ClassMenu(props)
	local onClose  = props.onClose
	local readOnly = props.readOnly  -- when true: view-only, class change blocked

	-- Server-provided player snapshot
	local playerInfo, setPlayerInfo = React.useState({
		level           = 1,
		activeClass     = "Aegis",
		unlockedClasses = { "Aegis" },
	})

	-- Class being switched to (nil when idle)
	local switching, setSwitching = React.useState(nil)

	-- Transient feedback toast message (nil = hidden)
	local feedback, setFeedback = React.useState(nil)

	-- Listeners ── mount once, tear down on unmount
	React.useEffect(function()
		-- Ask server for current snapshot
		NetworkManager.FireServer("GetPlayerInfo")

		local infoConn = NetworkManager.OnServerEvent("PlayerInfoUpdate", function(data)
			setPlayerInfo({
				level           = data.level           or 1,
				activeClass     = data.activeClass     or "Aegis",
				unlockedClasses = data.unlockedClasses or { "Aegis" },
			})
		end)

		local switchConn = NetworkManager.OnServerEvent("ClassSwitchResult", function(ok, payload)
			setSwitching(nil)
			if ok then
				-- payload is the new class name on success; refresh cleanly via server
				NetworkManager.FireServer("GetPlayerInfo")
				setFeedback(Locale.Get("switch_success"))
			else
				setFeedback(payload)
			end
			-- Clear toast after 2.5 s
			task.delay(2.5, function()
				setFeedback(nil)
			end)
		end)

		return function()
			if infoConn   then infoConn:Disconnect()   end
			if switchConn then switchConn:Disconnect() end
		end
	end, {})

	-- Switch handler (guards against double-firing)
	-- A 6-second safety timeout ensures the UI never stays permanently stuck
	-- if the server response is lost (e.g., event not yet replicated on connect).
	local function handleSwitch(className)
		if readOnly then
			setFeedback(Locale.Get("class_locked_match_feedback"))
			task.delay(2.5, function() setFeedback(nil) end)
			return
		end
		if switching then return end
		setSwitching(className)
		NetworkManager.FireServer("RequestClassSwitch", className)
		task.delay(6, function()
			setSwitching(nil)
		end)
	end

	-- Build the columns children table
	local colChildren = {
		layout = React.createElement("UIListLayout", {
			FillDirection       = Enum.FillDirection.Horizontal,
			VerticalAlignment   = Enum.VerticalAlignment.Center,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Padding             = UDim.new(0.006, 0),
		}),
	}
	for i, category in ipairs(ClassCatalog.Categories) do
		colChildren["col_" .. category.id] = React.createElement(CategoryColumn, {
			category    = category,
			playerInfo  = playerInfo,
			switching   = switching,
			onSwitch    = handleSwitch,
			readOnly    = readOnly,
			LayoutOrder = i,
		})
	end

	-- §T10/U3: chrome (backdrop, panel, title, close) is owned by
	-- AppWindow now — this table is only the window BODY.
	local panelChildren = {
		columns = React.createElement("Frame", {
			Position               = UDim2.fromScale(0, 0.01),
			Size                   = UDim2.fromScale(1, 0.98),
			BackgroundTransparency = 1,
		}, colChildren),
	}

	if feedback then
		panelChildren.toast = React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 1),
			Position               = UDim2.fromScale(0.5, 0.97),
			Size                   = UDim2.fromScale(0.55, 0.065),
			BackgroundColor3       = Color3.fromRGB(28, 28, 44),
			BackgroundTransparency = 0.10,
			BorderSizePixel        = 0,
			Text                   = feedback,
			TextColor3             = C.text,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
		})
	end

	-- §T10/U3: standard windowed chrome.
	return React.createElement(AppWindow, {
		variant = "windowed",
		title   = Locale.Get("menu_classes_title"),
		icon    = "classes",
		onClose = onClose,
		zIndex  = 10,
	}, panelChildren)
end

return ClassMenu
