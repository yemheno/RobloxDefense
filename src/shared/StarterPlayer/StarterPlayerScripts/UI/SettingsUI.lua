-- UI/SettingsUI.lua
--[[
    Settings panel: audio and the ONE keybind editor.

    Tabs:
      • Audio    — Music / SFX / UI volume and mute toggle
      • Controls — rebind every keyboard action (Combat: Attack, Dash,
                   Skill1-4; Lobby: Interact, EmoteWheel)

    §AGX/UI-P6: UX-13. The old "Skills" tab and the separate KeybindSettings
    overlay are merged into the Controls tab. KeybindSettings is now a thin
    wrapper that renders this panel on the Controls tab (BattleClassUI's
    "Controls / Rebind Keys" keeps working).

    Props:
      onClose     function  — callback to close the panel
      initialTab  "Audio"|"Controls"?  §AGX/UI-P6 (default "Audio"; "Skills" = "Controls")
      zIndex      number?   §AGX/UI-P6 (default Theme.Z.window)
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")   -- §AGX/UI-P7
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules = PlayerScripts:WaitForChild("Modules")

local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
local SoundManager   = require(SharedModules:WaitForChild("SoundManager"))
local InputSystem    = require(SharedModules:WaitForChild("InputSystem"))
local InputActions   = require(SharedModules:WaitForChild("InputSystem"):WaitForChild("InputActions"))

-- §AGX/UI-P6: Theme v2 + shared components (the private palette is gone).
local Common      = script.Parent:WaitForChild("Common")
local Theme       = require(Common:WaitForChild("Theme"))
local AppWindow   = require(Common:WaitForChild("AppWindow"))  -- §T10/U3
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local Text        = require(Common:WaitForChild("Text"))
local Button      = require(Common:WaitForChild("Button"))
local Panel       = require(Common:WaitForChild("Panel"))
local Tabs        = require(Common:WaitForChild("Tabs"))
local GamepadFocus = require(Common:WaitForChild("GamepadFocus"))   -- §AGX/UI-P7

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

local e = React.createElement
local R = Theme.Roles
local SP = Theme.Space

local BLOCKED_KEYS = {
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.RightShift] = true,
	[Enum.KeyCode.LeftControl] = true,
	[Enum.KeyCode.RightControl] = true,
	[Enum.KeyCode.LeftAlt] = true,
	[Enum.KeyCode.RightAlt] = true,
	[Enum.KeyCode.CapsLock] = true,
}

-- §AGX/UI-P6: UX-13: two tabs; Controls lists every action the two editors
-- listed (Settings' Skills + Controls, KeybindSettings' DISPLAY_ORDER).
local TAB_ITEMS = {
	{ id = "Audio",    label = "Audio" },
	{ id = "Controls", label = "Controls" },
}

local CONTROL_SECTIONS = {
	{ category = "Combat", actions = { "Attack", "Dash", "Skill1", "Skill2", "Skill3", "Skill4" } },
	{ category = "Lobby",  actions = { "Interact", "EmoteWheel" } },
}

-- §AGX/UI-P6: design px (phone scale; UIScaleRoot.Local applies the uiScale).
local ROW_H       = 52                          -- slider / binding rows (>= 44)
local TAP         = Theme.Metrics.button.sm     -- 44
local LABEL_W     = 96                          -- slider label column
local PCT_W       = 56                          -- slider value column
local TRACK_H     = 8
local KNOB        = 20
local KEY_W       = 128                         -- key badge button

local function saveBindings()
	NetworkManager.FireServer("SaveKeybindings", InputSystem.GetAllBindings())
end

-- ── Volume slider ─────────────────────────────────────────────────────────────
-- §AGX/UI-P6: same input handling as before (§AGX/UI-P1 grab band, touch and
-- mouse), re-expressed in design px with Theme roles.
local function VolumeSlider(props)
	local label = props.label
	local value = props.value or 0.5
	local onChange = props.onChange
	local sliderRef = React.useRef(nil)

	-- §AGX/UI-P7: gamepad: the grab band is selectable; while it is the
	-- selected object D-pad Left / Right step the value by 5 % (Left / Right
	-- navigation is pinned to itself, Up / Down still move between rows).
	-- Mouse / touch never select it, so they are unaffected.
	local grabRef = React.useRef(nil)
	local valueRef = React.useRef(value)
	valueRef.current = value
	local changeRef = React.useRef(onChange)
	changeRef.current = onChange
	React.useEffect(function()
		local grab = grabRef.current
		if not grab then return nil end
		grab.NextSelectionLeft = grab
		grab.NextSelectionRight = grab
		local conn = UserInputService.InputBegan:Connect(function(input)
			if GuiService.SelectedObject ~= grab then return end
			local k = input.KeyCode
			local d = (k == Enum.KeyCode.DPadRight and 1) or (k == Enum.KeyCode.DPadLeft and -1) or 0
			local f = changeRef.current
			if d ~= 0 and f then
				f(math.clamp((math.floor((valueRef.current or 0) * 20 + 0.5) + d) / 20, 0, 1))
			end
		end)
		return function() conn:Disconnect() end
	end, {})

	local function onInputBegan(_, input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local frame = sliderRef.current
		if not frame then return end

		-- AbsolutePosition / AbsoluteSize / input.Position are all screen px,
		-- so the ratio is scale-independent.
		local function updateValue(posX)
			local absPos = frame.AbsolutePosition.X
			local absSize = frame.AbsoluteSize.X
			if absSize <= 0 then return end
			local pct = math.clamp((posX - absPos) / absSize, 0, 1)
			if onChange then onChange(pct) end
		end

		updateValue(input.Position.X)

		local moveConn, releaseConn
		moveConn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.Change then
				updateValue(input.Position.X)
			end
		end)
		releaseConn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				if moveConn then moveConn:Disconnect() end
				if releaseConn then releaseConn:Disconnect() end
			end
		end)
	end

	return e(Panel, {
		name        = "Slider_" .. label,
		size        = UDim2.new(1, 0, 0, ROW_H),
		elevation   = "raised",
		padding     = "md",
		layoutOrder = props.order,
	}, {
		label = e(Text, {
			style = "label", text = label,
			size  = UDim2.new(0, LABEL_W, 1, 0),
		}),
		track = e("Frame", {
			ref              = sliderRef,
			AnchorPoint      = Vector2.new(0, 0.5),
			Position         = UDim2.new(0, LABEL_W + SP.md, 0.5, 0),
			Size             = UDim2.new(1, -(LABEL_W + PCT_W + 2 * SP.md), 0, TRACK_H),
			BackgroundColor3 = R.surface.track,
			BorderSizePixel  = 0,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
			fill = e("Frame", {
				Size             = UDim2.fromScale(value, 1),
				BackgroundColor3 = R.accent.secondary,
				BorderSizePixel  = 0,
			}, {
				corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
			}),
			knob = e("Frame", {
				AnchorPoint      = Vector2.new(0.5, 0.5),
				Position         = UDim2.fromScale(value, 0.5),
				Size             = UDim2.fromOffset(KNOB, KNOB),
				BackgroundColor3 = R.text.primary,
				BorderSizePixel  = 0,
				ZIndex           = 2,
			}, {
				corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
				stroke = e("UIStroke", { Color = R.accent.secondary, Thickness = Theme.Stroke.strong }),
			}),
			-- §AGX/UI-P1: invisible grab band, 44 px tall and 22 px past each
			-- end of the track, so the knob can be grabbed at 0 % and 100 %.
			grab = e("Frame", {
				AnchorPoint            = Vector2.new(0.5, 0.5),
				Position               = UDim2.fromScale(0.5, 0.5),
				Size                   = UDim2.new(1, TAP, 0, TAP),
				BackgroundTransparency = 1,
				ZIndex                 = 3,
				ref                    = grabRef,                       -- §AGX/UI-P7
				Selectable             = true,
				SelectionImageObject   = GamepadFocus.ring("pill"),
				[React.Event.InputBegan] = onInputBegan,
			}),
		}),
		pct = e(Text, {
			style       = "numeric",
			text        = tostring(math.floor(value * 100)) .. "%",
			color       = "accent.secondary",
			align       = "right",
			anchorPoint = Vector2.new(1, 0),
			position    = UDim2.fromScale(1, 0),
			size        = UDim2.new(0, PCT_W, 1, 0),
		}),
	})
end

-- ── Binding row ───────────────────────────────────────────────────────────────
local function BindingRow(props)
	local actionName = props.actionName
	local isListening = props.isListening
	local definition = InputActions.Definitions[actionName]
	if not definition then
		return nil
	end
	-- §AGX/UI-P6: UX-13: KeybindSettings' "custom binding" dot, kept.
	local defaults = definition.defaults and definition.defaults.Keyboard
	local isCustom = InputSystem.GetBinding(actionName, "Keyboard") ~= defaults

	return e(Panel, {
		name        = "Bind_" .. actionName,
		size        = UDim2.new(1, 0, 0, ROW_H),
		elevation   = "raised",
		padding     = "sm",
		accent      = isListening and "border.focus" or nil,
		layoutOrder = props.order,
	}, {
		label = e(Text, {
			style    = "body",
			text     = definition.displayName,
			position = UDim2.fromOffset(SP.xs, 0),
			size     = UDim2.new(1, -(KEY_W + SP.xl + SP.xs), 1, 0),
		}),
		customDot = isCustom and e("Frame", {
			AnchorPoint      = Vector2.new(1, 0.5),
			Position         = UDim2.new(1, -(KEY_W + SP.sm), 0.5, 0),
			Size             = UDim2.fromOffset(8, 8),
			BackgroundColor3 = R.accent.secondary,
			BorderSizePixel  = 0,
		}, { corner = e("UICorner", { CornerRadius = Theme.Radius.pill }) }) or nil,
		keyBtn = e(Button, {
			name        = "KeyBtn",
			size        = "sm",
			width       = KEY_W,
			anchorPoint = Vector2.new(1, 0.5),
			position    = UDim2.fromScale(1, 0.5),
			selected    = isListening,
			label       = isListening and "Press key…" or InputSystem.GetBindingDisplayName(actionName, "Keyboard"),
			onActivated = props.onActivate,
		}),
	})
end

local function SectionHeader(props)
	return e(Text, {
		style       = "caption",
		text        = string.upper(props.text),
		color       = "text.secondary",
		size        = UDim2.new(1, 0, 0, 24),
		valign      = "bottom",
		layoutOrder = props.order,
	})
end

-- ── Panel ─────────────────────────────────────────────────────────────────────
local function normalizeTab(tab)
	if tab == "Skills" or tab == "Controls" then return "Controls" end
	return "Audio"
end

local function SettingsUI(props)
	local onClose = props.onClose

	local function safeVol(group, fallback)
		local value = SoundManager.GetVolume(group)
		if value ~= nil then
			return value
		end
		return fallback
	end

	local musicVol, setMusicVol = React.useState(safeVol("Music", 0.5))
	local sfxVol, setSfxVol = React.useState(safeVol("SFX", 0.8))
	local uiVol, setUiVol = React.useState(safeVol("UI", 0.7))
	local muted, setMuted = React.useState(SoundManager.IsMuted())
	-- §AGX/UI-P6: UX-13: initialTab lets KeybindSettings open on Controls.
	local activeTab, setActiveTab = React.useState(normalizeTab(props.initialTab))
	local listeningFor, setListeningFor = React.useState(nil)
	local bindingsVersion, setBindingsVersion = React.useState(0)

	-- §AGX/UI-P3: A11. Back / backdrop / replace while a key is being
	-- captured cancels the capture and vetoes the close ("system" ignores it).
	local listeningRef = React.useRef(nil)
	listeningRef.current = listeningFor
	PanelStackHooks.useCloseHandler(function(_reason)
		if listeningRef.current then
			setListeningFor(nil)
			return false
		end
		return nil
	end)

	local function changeMusicVol(value)
		setMusicVol(value)
		SoundManager.SetVolume("Music", value)
	end

	local function changeSfxVol(value)
		setSfxVol(value)
		SoundManager.SetVolume("SFX", value)
	end

	local function changeUiVol(value)
		setUiVol(value)
		SoundManager.SetVolume("UI", value)
	end

	local function toggleMute()
		local newMuted = not muted
		setMuted(newMuted)
		SoundManager.SetMasterMute(newMuted)
	end

	React.useEffect(function()
		local disconnect = InputSystem.OnBindingChanged(function()
			setBindingsVersion(function(version)
				return version + 1
			end)
		end)
		return disconnect
	end, {})

	React.useEffect(function()
		if not listeningFor then
			return
		end

		local conn = UserInputService.InputBegan:Connect(function(input)
			local key = nil
			if input.UserInputType == Enum.UserInputType.Keyboard then
				key = input.KeyCode
				-- §AGX/UI-P3: Backspace is the UIBack key: it cancels the
				-- capture (like Escape) instead of being bound.
				if key == Enum.KeyCode.Escape or key == Enum.KeyCode.Backspace then
					setListeningFor(nil)
					return
				end
				if BLOCKED_KEYS[key] then
					return
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.MouseButton2 then
				key = input.UserInputType
			else
				return
			end

			InputSystem.SetBinding(listeningFor, "Keyboard", { key })
			setListeningFor(nil)
			saveBindings()
		end)

		return function()
			conn:Disconnect()
		end
	end, { listeningFor })

	local content
	if activeTab == "Audio" then
		content = {
			music = e(VolumeSlider, { label = "Music", value = musicVol, onChange = changeMusicVol, order = 1 }),
			sfx   = e(VolumeSlider, { label = "SFX",   value = sfxVol,   onChange = changeSfxVol,   order = 2 }),
			ui    = e(VolumeSlider, { label = "UI",    value = uiVol,    onChange = changeUiVol,    order = 3 }),
			mute  = e(Button, {
				name        = "MuteBtn",
				variant     = muted and "danger" or "secondary",
				size        = "md",
				width       = UDim.new(1, 0),
				label       = muted and "Unmute All" or "Mute All",
				layoutOrder = 4,
				onActivated = toggleMute,
			}),
			hint = e(Text, {
				style = "caption", color = "text.secondary", wrap = true, layoutOrder = 5,
				text = "Audio settings update immediately.",
			}),
		}
	else
		content = {
			hint = e(Text, {
				style = "caption", color = "text.secondary", wrap = true, layoutOrder = 1,
				-- §AGX/UI-P6: touch-only devices cannot capture a key; say so.
				text = UserInputService.KeyboardEnabled
					and "Tap a binding, then press a key or mouse button. Esc or Backspace cancels."
					or "Connect a keyboard to rebind keys.",
			}),
		}
		local order = 2
		for _, section in ipairs(CONTROL_SECTIONS) do
			content["h_" .. section.category] = e(SectionHeader, { text = section.category, order = order })
			order += 1
			for _, actionName in ipairs(section.actions) do
				local def = InputActions.Definitions[actionName]
				-- Only actions with a keyboard default (skip touch-only).
				if def and def.defaults and def.defaults.Keyboard and #def.defaults.Keyboard > 0 then
					content[actionName] = e(BindingRow, {
						actionName  = actionName,
						isListening = listeningFor == actionName,
						order       = order,
						version     = bindingsVersion,
						onActivate  = function()
							setListeningFor(function(current)
								if current == actionName then
									return nil
								end
								return actionName
							end)
						end,
					})
					order += 1
				end
			end
		end
		content.reset = e(Button, {
			name        = "ResetBtn",
			variant     = "danger",
			size        = "md",
			width       = UDim.new(1, 0),
			label       = "Reset All Keybinds",
			layoutOrder = order + 1,
			onActivated = function()
				InputSystem.ResetAllBindings()
				setListeningFor(nil)
				saveBindings()
			end,
		})
		content.footer = e(Text, {
			style = "caption", color = "text.secondary", wrap = true, layoutOrder = order + 2,
			text = "Bindings save to your account.",
		})
	end
	content.layout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding   = UDim.new(0, SP.sm),
	})
	content.padding = e("UIPadding", {
		PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
		PaddingTop = UDim.new(0, SP.md), PaddingBottom = UDim.new(0, SP.lg),
	})

	local z = props.zIndex or Theme.Z.window

	-- §T10/U3: chrome owned by AppWindow (close also clears key-listen state).
	-- §AGX/UI-P6: variant "auto" (sheet on phone); the shell's presentation
	-- still wins inside a PanelHost. Body in design px via UIScaleRoot.Local.
	return e(AppWindow, {
		variant = "auto",
		title   = "Settings",
		icon    = "settings",
		onClose = function()
			setListeningFor(nil)
			onClose()
		end,
		size    = UDim2.fromScale(0.5, 0.74),
		minSize = Vector2.new(520, 420),
		zIndex  = z,
	}, {
		scaled = e(UIScaleRoot.Local, { name = "SettingsBody", zIndex = z + 2 }, {
			tabs = e(Tabs, {
				items    = TAB_ITEMS,
				value    = activeTab,
				zIndex   = z + 2,
				onChange = function(id)
					setListeningFor(nil)
					setActiveTab(id)
				end,
			}),
			content = e("ScrollingFrame", {
				Name                   = "Content",
				Position               = UDim2.fromOffset(0, Theme.Metrics.tabs.height),
				Size                   = UDim2.new(1, 0, 1, -Theme.Metrics.tabs.height),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				ScrollBarThickness     = Theme.Metrics.scrollBar,
				ScrollBarImageColor3   = R.text.secondary,
				CanvasSize             = UDim2.fromScale(0, 0),
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
				ScrollingDirection     = Enum.ScrollingDirection.Y,
				ZIndex                 = z + 2,
			}, content),
		}),
	})
end

return SettingsUI
