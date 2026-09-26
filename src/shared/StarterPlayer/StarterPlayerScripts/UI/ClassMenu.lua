-- UI/ClassMenu.lua
--
-- React component: four-column class selection panel.
-- §AGX/UI-P6: design px inside UIScaleRoot.Local; the columns wrap (4 / 2 / 1
-- per row) with the body width, so the layout adapts to phones.
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
-- §AGX/UI-P6: shared components (Theme v2, D1 Hybrid / D2).
--   • Body = design px inside UIScaleRoot.Local, one vertical ScrollingFrame;
--     1-4 category columns per row depending on the body width (phone sheet
--     wraps to 2+2 or 1 column instead of squeezing four).
--   • Class slot = Card (selected = active class, locked = level-locked) with
--     a full-width Button footer: success = active (ink on green; never
--     white on green, 2.8:1, V10), secondary = switch, locked = level / match.
local Common        = script.Parent:WaitForChild("Common")
local AppWindow     = require(Common:WaitForChild("AppWindow"))  -- §T10/U3
local Theme         = require(Common:WaitForChild("Theme"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))
local Text          = require(Common:WaitForChild("Text"))
local Button        = require(Common:WaitForChild("Button"))
local Panel         = require(Common:WaitForChild("Panel"))
local Card          = require(Common:WaitForChild("Card"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

-- §AGX/UI-P6: design px
local COL_MIN_W   = 190   -- narrowest category column
local COL_GAP     = SP.sm
local EMPTY_SLOT_H = 64

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
--   props: entry, state, switching, onSwitch, readOnly, layoutOrder
local function ClassSlot(props)
	local entry      = props.entry
	local state      = props.state
	local switching  = props.switching
	local onSwitch   = props.onSwitch
	local readOnly   = props.readOnly  -- when true, class change is blocked

	local isPending   = (switching == entry.id)
	-- readOnly blocks the switch button regardless of unlock state
	local isClickable = (state == "available") and (switching == nil) and (not readOnly)

	local btnText = (state == "active"  and Locale.Get("class_active"))
		or (readOnly and state == "available" and Locale.Get("class_locked_match") or nil)
		or (state == "locked"  and Locale.Get("class_locked", entry.requiredLevel))
		or (isPending          and "…")
		or Locale.Get("class_switch")

	-- §AGX/UI-P6: one Button per state.
	local variant = (state == "active" and "success")
		or ((state == "locked" or (readOnly and state == "available")) and "locked")
		or "secondary"

	return e(Card, {
		title       = Locale.Get(entry.localeKey .. "_name"),
		subtitle    = Locale.Get(entry.localeKey .. "_desc"),
		selected    = state == "active",
		locked      = state == "locked",
		layoutOrder = props.layoutOrder,
		footer      = e(Button, {
			name        = "Switch_" .. entry.id,
			variant     = variant,
			size        = "sm",
			width       = UDim.new(1, 0),
			label       = btnText,
			loading     = isPending,
			onActivated = isClickable and onSwitch or nil,
		}),
	})
end

-- ── PlaceholderSlot ───────────────────────────────────────────────────────────
local function PlaceholderSlot(props)
	return e(Panel, {
		elevation   = "sunken",
		padding     = "sm",
		size        = UDim2.new(1, 0, 0, EMPTY_SLOT_H),
		layoutOrder = props.layoutOrder,
	}, {
		lbl = e(Text, {
			style = "caption",
			text  = Locale.Get("class_empty"),
			color = "text.disabled",
			align = "center",
			size  = UDim2.fromScale(1, 1),
		}),
	})
end

-- ── CategoryColumn ────────────────────────────────────────────────────────────
--   props: category, playerInfo, switching, onSwitch, readOnly, LayoutOrder, width
local function CategoryColumn(props)
	local category   = props.category
	local playerInfo = props.playerInfo
	local switching  = props.switching
	local onSwitch   = props.onSwitch
	local readOnly   = props.readOnly

	local children = {
		-- Header (blue body accent, never orange)
		header = e(Text, {
			style       = "heading",
			text        = string.upper(Locale.Get(category.headerKey)),
			color       = "accent.secondary",
			align       = "center",
			layoutOrder = 0,
		}),
	}

	-- Real class slots
	for i, entry in ipairs(category.classes) do
		children["slot_" .. i] = e(ClassSlot, {
			entry       = entry,
			state       = getSlotState(entry, playerInfo),
			switching   = switching,
			readOnly    = readOnly,
			layoutOrder = i,
			onSwitch    = function()
				onSwitch(entry.id)
			end,
		})
	end

	-- Placeholders to fill remaining slots
	for i = #category.classes + 1, ClassCatalog.SlotsPerColumn do
		children["ph_" .. i] = e(PlaceholderSlot, { layoutOrder = i })
	end

	return e(Panel, {
		name        = "Col_" .. category.id,
		elevation   = "flat",
		padding     = "sm",
		layout      = "vertical",
		gap         = "sm",
		size        = UDim2.new(props.width, UDim.new(0, 0)),
		autoSize    = "Y",
		layoutOrder = props.LayoutOrder,
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

	-- §AGX/UI-P6: columns per row from the body width (design px).
	local ff = useFormFactor()
	local bodyW, setBodyW = React.useState(COL_MIN_W * 4)
	local onBodySize = React.useCallback(function(rbx)
		local w = rbx.AbsoluteSize.X
		if w > 0 then setBodyW(w / math.max(ff.uiScale or 1, 0.01)) end
	end, { ff.uiScale })
	local nCats = #ClassCatalog.Categories
	local inner = bodyW - 2 * SP.lg
	local perRow = math.clamp(math.floor((inner + COL_GAP) / (COL_MIN_W + COL_GAP)), 1, math.max(1, nCats))
	-- 3 would leave one orphan column: prefer 2 + 2
	if perRow == 3 and nCats == 4 then perRow = 2 end
	local colWidth = UDim.new(1 / perRow, -COL_GAP * (perRow - 1) / perRow)

	-- Build the columns children table
	local colChildren = {
		layout = e("UIListLayout", {
			FillDirection       = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment   = Enum.VerticalAlignment.Top,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Padding             = UDim.new(0, COL_GAP),
			Wraps               = true,
		}),
	}
	for i, category in ipairs(ClassCatalog.Categories) do
		colChildren["col_" .. category.id] = e(CategoryColumn, {
			category    = category,
			playerInfo  = playerInfo,
			switching   = switching,
			onSwitch    = handleSwitch,
			readOnly    = readOnly,
			LayoutOrder = i,
			width       = colWidth,
		})
	end

	-- §T10/U3, §AGX/UI-P6: chrome (backdrop, panel, title, close) is owned
	-- by AppWindow; this table is only the window BODY, in design px.
	local panelChildren = {
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
				PaddingTop = UDim.new(0, SP.md),
				-- room for the feedback toast over the last row
				PaddingBottom = UDim.new(0, SP.xxl + SP.xl),
			}),
			columns = e("Frame", {
				Name                   = "Columns",
				Size                   = UDim2.fromScale(1, 0),
				AutomaticSize          = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, colChildren),
		}),
	}

	if feedback then
		panelChildren.toast = e(Panel, {
			name        = "Feedback",
			elevation   = "raised",
			padding     = "sm",
			anchorPoint = Vector2.new(0.5, 1),
			position    = UDim2.new(0.5, 0, 1, -SP.md),
			size        = UDim2.fromOffset(0, 40),
			autoSize    = "X",
			accent      = "accent.secondary",
			zIndex      = 5,
		}, {
			minW = e("UISizeConstraint", { MinSize = Vector2.new(200, 40) }),
			lbl = e(Text, {
				style    = "label",
				text     = feedback,
				align    = "center",
				size     = UDim2.fromScale(0, 1),
				autoSize = "X",
				zIndex   = 6,
			}),
		})
	end

	-- §T10/U3: standard windowed chrome.
	return e(AppWindow, {
		variant = "windowed",
		title   = Locale.Get("menu_classes_title"),
		icon    = "classes",
		onClose = onClose,
		zIndex  = 10,
	}, {
		content = e(UIScaleRoot.Local, { name = "ClassBody" }, panelChildren),
	})
end

return ClassMenu
