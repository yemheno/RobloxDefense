-- shared/StarterPlayerScripts/UI/KeybindSettings.lua
--[[
    Keybind Settings Overlay

    Full-screen panel that lets the player reassign keyboard bindings for all
    named actions that have a Keyboard default.

    • Click a key badge → "listening" mode → press any key → binding applied.
    • Changes are applied immediately via InputSystem.SetBinding and persisted
      to the server via SaveKeybindings.
    • "Reset All" restores every action to its default key and clears the
      server-side override table.
    • Renders inside BattleClassUI's ScreenGui (ZIndex stacked above the badge).

    Props:
      onClose  function()   called when the player closes the panel
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local e         = React.createElement
local useState  = React.useState
local useEffect = React.useEffect

local LocalPlayer   = Players.LocalPlayer
local SharedModules = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")

local InputSystem    = require(SharedModules:WaitForChild("InputSystem"))
local InputActions   = require(SharedModules:WaitForChild("InputSystem"):WaitForChild("InputActions"))
-- §AGX/UI-P3: PanelStack hooks, nil-safe (no-ops without UI/Shell or
-- outside a PanelHost, so Wave 1 behaves exactly as before).
local PanelStackHooks = { useCloseHandler = function(_fn) end, useModalPresence = function(_k, _v) end }
do
	local shell = script.Parent:FindFirstChild("Shell")
	local mod = shell and shell:FindFirstChild("PanelStack")
	if mod then
		local ok, PanelStack = pcall(require, mod)
		if ok and type(PanelStack) == "table" then
			PanelStackHooks.useCloseHandler  = PanelStack.useCloseHandler or PanelStackHooks.useCloseHandler
			PanelStackHooks.useModalPresence = PanelStack.useModalPresence or PanelStackHooks.useModalPresence
		end
	end
end

-- ── Palette ───────────────────────────────────────────────
local C = {
	overlay      = Color3.fromRGB(8,  8,  14),
	panel_bg     = Color3.fromRGB(18, 18, 30),
	row_bg       = Color3.fromRGB(26, 26, 42),
	row_hover    = Color3.fromRGB(34, 34, 56),
	key_bg       = Color3.fromRGB(40, 100, 200),
	key_listen   = Color3.fromRGB(220, 150, 30),
	header_bg    = Color3.fromRGB(14, 14, 22),
	text         = Color3.fromRGB(220, 220, 235),
	text_dim     = Color3.fromRGB(140, 140, 165),
	text_muted   = Color3.fromRGB(90,  90,  120),
	border       = Color3.fromRGB(55,  55,  90),
	reset_bg     = Color3.fromRGB(180, 60,  60),
	close_bg     = Color3.fromRGB(55,  55,  90),
	category_bg  = Color3.fromRGB(22,  22,  38),
}

-- ── Action order for display ──────────────────────────────
-- Categories to show, and preferred display order within each.
local DISPLAY_ORDER = {
	{ category = "Combat", actions = { "Attack", "Dash", "Skill1", "Skill2", "Skill3", "Skill4" } },
	{ category = "Lobby",  actions = { "Interact", "EmoteWheel" } },
}

-- ── Keys that are blocked from being bound (modifier / system keys) ────────
local BLOCKED_KEYS = {
	[Enum.KeyCode.LeftShift]    = true,
	[Enum.KeyCode.RightShift]   = true,
	[Enum.KeyCode.LeftControl]  = true,
	[Enum.KeyCode.RightControl] = true,
	[Enum.KeyCode.LeftAlt]      = true,
	[Enum.KeyCode.RightAlt]     = true,
	[Enum.KeyCode.CapsLock]     = true,
	[Enum.KeyCode.Escape]       = true,
}

-- §AGX/UI-P1: minimum tap target (V1: close was ~8x1 px at 1080p).
local MIN_TAP_PX = 44

-- §AGX/UI-P1: transparent hit box at least 44x44, centred on a small visual
-- button. The visual keeps its size; only the clickable area grows.
local function hitArea(onActivated, zIndex)
	return e("TextButton", {
		Name                   = "HitArea",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text                   = "",
		ZIndex                 = zIndex,
		[React.Event.Activated] = onActivated,
	}, {
		minSize = e("UISizeConstraint", { MinSize = Vector2.new(MIN_TAP_PX, MIN_TAP_PX) }),
	})
end

-- ── Save helper ───────────────────────────────────────────
local function saveToServer()
	local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
	NetworkManager.FireServer("SaveKeybindings", InputSystem.GetAllBindings())
end

-- ═══════════════════════════════════════════════════════════
-- SUB-COMPONENT: single action row
-- ═══════════════════════════════════════════════════════════

local function ActionRow(props)
	local actionName   = props.actionName
	local isListening  = props.isListening
	local onClickKey   = props.onClickKey
	local ver          = props.ver   -- triggers re-read of binding

	local def          = InputActions.Definitions[actionName]
	if not def then return nil end

	local keyLabel = InputSystem.GetBindingDisplayName(actionName, "Keyboard")
	local isCustom  = InputSystem.GetBinding(actionName, "Keyboard") ~= def.defaults["Keyboard"]

	local keyColor = isListening and C.key_listen or C.key_bg

	return e("Frame", {
		Size                   = UDim2.new(1, 0, 0, 38),
		BackgroundColor3       = C.row_bg,
		BackgroundTransparency = 0.2,
		BorderSizePixel        = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),

		-- Action display name (left)
		ActionName = e("TextLabel", {
			Position               = UDim2.fromOffset(12, 0),
			Size                   = UDim2.new(1, -100, 1, 0),
			BackgroundTransparency = 1,
			Text                   = def.displayName,
			TextColor3             = C.text,
			TextXAlignment         = Enum.TextXAlignment.Left,
			Font                   = Enum.Font.Gotham,
			TextSize               = 14,
		}),

		-- Custom-binding indicator dot
		CustomDot = isCustom and e("Frame", {
			AnchorPoint      = Vector2.new(1, 0.5),
			Position         = UDim2.new(1, -76, 0.5, 0),
			-- §AGX/UI-P1: V1: was fromScale(0.003, 0.006) of the row (sub-pixel).
			Size             = UDim2.fromOffset(6, 6),
			BackgroundColor3 = C.key_listen,
			BorderSizePixel  = 0,
		}, { Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }) }) or nil,

		-- Key badge / listening button (right)
		KeyBtn = e("TextButton", {
			AnchorPoint            = Vector2.new(1, 0.5),
			Position               = UDim2.new(1, -10, 0.5, 0),
			-- §AGX/UI-P1: V1: was fromScale(0.030, 0.024) of the row (~11x1 px).
			-- The dot at (1,-76) implies the intended 60 px width.
			Size                   = UDim2.fromOffset(60, 26),
			BackgroundColor3       = keyColor,
			BackgroundTransparency = isListening and 0 or 0.2,
			BorderSizePixel        = 0,
			Text                   = isListening and "…" or keyLabel,
			TextColor3             = Color3.new(1, 1, 1),
			Font                   = Enum.Font.GothamBold,
			TextSize               = 13,
			[React.Event.Activated] = onClickKey,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 5) }),
			hit = hitArea(onClickKey),  -- §AGX/UI-P1: 44 px hit box
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- MAIN COMPONENT
-- ═══════════════════════════════════════════════════════════

local function KeybindSettings(props)
	local onClose = props.onClose

	-- Which action is awaiting a keypress (nil = none)
	local listeningFor, setListeningFor = useState(nil)

	-- §AGX/UI-P3: A11. Back while capturing cancels the capture and vetoes.
	-- Registered on the enclosing entry (BattleClassUI's "class"); it is
	-- newer than BattleClassUI's own handler, so it runs first (A13).
	local listeningRef = React.useRef(nil)
	listeningRef.current = listeningFor
	PanelStackHooks.useCloseHandler(function(_reason)
		if listeningRef.current then
			setListeningFor(nil)
			return false
		end
		return nil
	end)
	-- Version counter, incremented on each binding change → forces row re-reads
	local ver, setVer = useState(0)

	local function bumpVer()
		setVer(function(v) return v + 1 end)
	end

	-- Capture keypress while listening
	useEffect(function()
		if not listeningFor then return end

		local conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			-- Allow even if gameProcessed (we're running a modal UI)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			local key = input.KeyCode
			if BLOCKED_KEYS[key] then return end

			-- §AGX/UI-P3: Backspace (UIBack) cancels too instead of being bound.
			if key == Enum.KeyCode.Escape or key == Enum.KeyCode.Backspace then
				-- Escape cancels the listen without binding
				setListeningFor(nil)
				return
			end

			InputSystem.SetBinding(listeningFor, "Keyboard", { key })
			setListeningFor(nil)
			bumpVer()
			saveToServer()
		end)

		return function()
			conn:Disconnect()
		end
	end, { listeningFor })

	-- Build rows per category
	local rows = {}
	for _, section in ipairs(DISPLAY_ORDER) do
		-- Category separator
		table.insert(rows, e("TextLabel", {
			Size                   = UDim2.new(1, 0, 0, 22),
			BackgroundColor3       = C.category_bg,
			BackgroundTransparency = 0,
			BorderSizePixel        = 0,
			Text                   = "  " .. string.upper(section.category),
			TextColor3             = C.text_muted,
			TextXAlignment         = Enum.TextXAlignment.Left,
			Font                   = Enum.Font.GothamBold,
			TextSize               = 10,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
		}))

		for _, actionName in ipairs(section.actions) do
			local def = InputActions.Definitions[actionName]
			-- Only show actions that have a keyboard default (skip touch-only)
			if def and def.defaults and def.defaults.Keyboard and #def.defaults.Keyboard > 0 then
				table.insert(rows, e(ActionRow, {
					key          = actionName .. "_" .. tostring(ver),
					actionName   = actionName,
					isListening  = listeningFor == actionName,
					ver          = ver,
					onClickKey   = function()
						setListeningFor(function(prev)
							return prev == actionName and nil or actionName
						end)
					end,
				}))
			end
		end
	end

	-- Wrap rows in a scroll frame
	local rowsTable = {}
	rowsTable["_layout"] = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding       = UDim.new(0, 4),
		SortOrder     = Enum.SortOrder.Name,
	})
	rowsTable["_pad"] = e("UIPadding", {
		PaddingLeft   = UDim.new(0, 10),
		PaddingRight  = UDim.new(0, 10),
		PaddingTop    = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
	})
	for i, row in ipairs(rows) do
		rowsTable["r" .. i] = row
	end

	return e("Frame", {
		-- Full-screen overlay
		Size                   = UDim2.fromScale(1, 1),
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3       = C.overlay,
		BackgroundTransparency = 0.35,
		BorderSizePixel        = 0,
		ZIndex                 = 100,
	}, {
		-- Click outside panel to cancel current listen (not close)
		OverlayBtn = e("TextButton", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text                   = "",
			BorderSizePixel        = 0,
			[React.Event.Activated] = function()
				if listeningFor then
					setListeningFor(nil)
				end
			end,
		}),

		-- Centered settings panel
		Panel = e("Frame", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			Size                   = UDim2.fromScale(0.219, 0.481),
			BackgroundColor3       = C.panel_bg,
			BackgroundTransparency = 0,
			BorderSizePixel        = 0,
			ZIndex                 = 101,
		}, {
			-- §AGX/UI-P1: 118 px of fixed chrome is subtracted from this
			-- scale panel (185x188 on a phone -> 70 px list). Floor keeps
			-- the list >= 182 px and fits 800x360. 1080p (420x520) unchanged.
			MinSize = e("UISizeConstraint", { MinSize = Vector2.new(340, 300) }),
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 10) }),
			Stroke = e("UIStroke", { Color = C.border, Thickness = 1.5 }),

			-- Header
			Header = e("Frame", {
				Size             = UDim2.new(1, 0, 0, 44),  -- keep pixel height
				BackgroundColor3 = C.header_bg,
				BorderSizePixel  = 0,
				ZIndex           = 102,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 10) }),
				-- Cover bottom-rounded corners of header
				BottomFill = e("Frame", {
					AnchorPoint      = Vector2.new(0, 1),
					Position         = UDim2.fromScale(0, 1),
					Size             = UDim2.new(1, 0, 0, 8),
					BackgroundColor3 = C.header_bg,
					BorderSizePixel  = 0,
				}),
				Title = e("TextLabel", {
					Position               = UDim2.fromOffset(14, 0),
					Size                   = UDim2.new(1, -56, 1, 0),
					BackgroundTransparency = 1,
					Text                   = "⌨  Keybindings",
					TextColor3             = C.text,
					TextXAlignment         = Enum.TextXAlignment.Left,
					Font                   = Enum.Font.GothamBold,
					TextSize               = 16,
					ZIndex                 = 103,
				}),
				CloseBtn = e("TextButton", {
					AnchorPoint            = Vector2.new(1, 0.5),
					Position               = UDim2.new(1, -8, 0.5, 0),
					-- §AGX/UI-P1: V1: was fromScale(0.019, 0.026) of the header
					-- (~8x1 px at 1080p). 0.019x1920 / 0.026x1080 = 36x28 px.
					Size                   = UDim2.fromOffset(36, 28),
					BackgroundColor3       = C.close_bg,
					BackgroundTransparency = 0.2,
					BorderSizePixel        = 0,
					Text                   = "✕",
					TextColor3             = C.text_dim,
					Font                   = Enum.Font.GothamBold,
					TextSize               = 14,
					ZIndex                 = 103,
					[React.Event.Activated] = onClose,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
					hit = hitArea(onClose, 104),  -- §AGX/UI-P1: 44x44 hit box
				}),
			}),

			-- Hint text below header
			Hint = e("TextLabel", {
				Position               = UDim2.fromOffset(14, 48),
				Size                   = UDim2.new(1, -28, 0, 16),
				BackgroundTransparency = 1,
				Text                   = "Click a key badge, then press the key you want to assign. [Esc] cancels.",
				TextColor3             = C.text_muted,
				TextXAlignment         = Enum.TextXAlignment.Left,
				Font                   = Enum.Font.Gotham,
				TextSize               = 11,
				TextWrapped            = true,
				ZIndex                 = 102,
			}),

			-- Scrollable rows area
			Scroll = e("ScrollingFrame", {
				Position              = UDim2.fromOffset(0, 70),  -- keep offset for alignment
				Size                  = UDim2.new(1, 0, 1, -118),  -- keep offsets for padding
				BackgroundTransparency = 1,
				BorderSizePixel       = 0,
				ScrollBarThickness    = 4,
				ScrollBarImageColor3  = C.border,
				CanvasSize            = UDim2.new(1, 0, 0, 0),
				AutomaticCanvasSize   = Enum.AutomaticSize.Y,
				ZIndex                = 102,
			}, rowsTable),

			-- Footer: Reset All button
			Footer = e("Frame", {
				AnchorPoint      = Vector2.new(0, 1),
				Position         = UDim2.fromScale(0, 1),
				Size             = UDim2.new(1, 0, 0, 48),  -- keep pixel height
				BackgroundColor3 = C.header_bg,
				BorderSizePixel  = 0,
				ZIndex           = 102,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 10) }),
				TopFill = e("Frame", {
					Size             = UDim2.new(1, 0, 0, 8),
					BackgroundColor3 = C.header_bg,
					BorderSizePixel  = 0,
				}),
				ResetBtn = e("TextButton", {
					AnchorPoint            = Vector2.new(0.5, 0.5),
					Position               = UDim2.fromScale(0.5, 0.5),
					-- §AGX/UI-P1: V1: was fromScale(0.083, 0.028) of the footer
					-- (~35x1 px). Pixel size fits "Reset All to Default" at 13 pt.
					Size                   = UDim2.fromOffset(180, 30),
					BackgroundColor3       = C.reset_bg,
					BackgroundTransparency = 0.15,
					BorderSizePixel        = 0,
					Text                   = "↺  Reset All to Default",
					TextColor3             = Color3.new(1, 1, 1),
					Font                   = Enum.Font.Gotham,
					TextSize               = 13,
					ZIndex                 = 103,
					[React.Event.Activated] = function()
						InputSystem.ResetAllBindings()
						setListeningFor(nil)
						bumpVer()
						saveToServer()
					end,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
					hit = hitArea(function()  -- §AGX/UI-P1: 44 px tall hit box
						InputSystem.ResetAllBindings()
						setListeningFor(nil)
						bumpVer()
						saveToServer()
					end, 104),
				}),
			}),
		}),
	})
end

return KeybindSettings
