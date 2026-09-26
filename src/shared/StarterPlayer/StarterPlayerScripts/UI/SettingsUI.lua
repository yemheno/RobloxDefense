-- UI/SettingsUI.lua
--[[
    Settings panel with tabbed audio and input testing.

    Tabs:
      • Audio    — Music / SFX / UI volume and mute toggle
      • Skills   — rebind Skill1-4 for quick testing
      • Controls — rebind Attack / Dash / Interact / EmoteWheel

    Props:
      onClose  function  — callback to close the panel
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules = PlayerScripts:WaitForChild("Modules")

local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
local SoundManager   = require(SharedModules:WaitForChild("SoundManager"))
local AppWindow      = require(script.Parent:WaitForChild("Common"):WaitForChild("AppWindow"))  -- §T10/U3
local InputSystem    = require(SharedModules:WaitForChild("InputSystem"))
local InputActions   = require(SharedModules:WaitForChild("InputSystem"):WaitForChild("InputActions"))

local C = {
    bg           = Color3.fromRGB(18, 18, 24),
    section      = Color3.fromRGB(26, 26, 38),
    section_alt  = Color3.fromRGB(30, 30, 44),
    text         = Color3.fromRGB(220, 220, 230),
    text_dim     = Color3.fromRGB(140, 140, 160),
    text_muted   = Color3.fromRGB(100, 100, 120),
    accent       = Color3.fromRGB(105, 190, 255),
    slider_bg    = Color3.fromRGB(40, 40, 55),
    slider_fill  = Color3.fromRGB(80, 170, 255),
    slider_knob  = Color3.fromRGB(255, 255, 255),
    btn_active   = Color3.fromRGB(60, 180, 100),
    btn_muted    = Color3.fromRGB(180, 60, 60),
    close_bg     = Color3.fromRGB(80, 36, 36),
    close_text   = Color3.fromRGB(245, 100, 100),
    white        = Color3.fromRGB(255, 255, 255),
    tab_on       = Color3.fromRGB(50, 80, 150),
    tab_off      = Color3.fromRGB(34, 34, 48),
    key_bg       = Color3.fromRGB(70, 120, 220),
    key_listen   = Color3.fromRGB(220, 160, 50),
    reset_bg     = Color3.fromRGB(170, 70, 70),
}

local BLOCKED_KEYS = {
    [Enum.KeyCode.LeftShift] = true,
    [Enum.KeyCode.RightShift] = true,
    [Enum.KeyCode.LeftControl] = true,
    [Enum.KeyCode.RightControl] = true,
    [Enum.KeyCode.LeftAlt] = true,
    [Enum.KeyCode.RightAlt] = true,
    [Enum.KeyCode.CapsLock] = true,
}

local TAB_ORDER = {
    { id = "Audio", label = "Audio" },
    { id = "Skills", label = "Skills" },
    { id = "Controls", label = "Controls" },
}

local TAB_ACTIONS = {
    Skills = { "Skill1", "Skill2", "Skill3", "Skill4" },
    Controls = { "Attack", "Dash", "Interact", "EmoteWheel" },
}

-- §AGX/UI-P1: minimum tap target. T8 and V1: the window is 0.48x0.68 of the
-- screen, so tabs were 15 px tall and slider rows 24 px on a phone, and the
-- knob was invisible everywhere (0.007x0.013 of the track). On touch devices
-- the tab bar and rows use 44 px pixel heights (content scrolls if needed);
-- desktop keeps its scale layout.
local MIN_TAP_PX        = 44
local IS_TOUCH          = UserInputService.TouchEnabled
local TOUCH_CONTENT_TOP = 4 + MIN_TAP_PX + 4   -- below the 44 px tab bar
local TOUCH_FOOTER_H    = 22                   -- version footer

-- §AGX/UI-P1: transparent hit box at least minSize (default 44x44), centred on
-- the visual. The visual keeps its size; only the clickable area grows.
local function hitArea(onActivated, minSize)
    return React.createElement("TextButton", {
        Name                   = "HitArea",
        AnchorPoint            = Vector2.new(0.5, 0.5),
        Position               = UDim2.fromScale(0.5, 0.5),
        Size                   = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text                   = "",
        [React.Event.Activated] = onActivated,
    }, {
        minSize = React.createElement("UISizeConstraint", {
            MinSize = minSize or Vector2.new(MIN_TAP_PX, MIN_TAP_PX),
        }),
    })
end

-- §AGX/UI-P1: M11: TextScaled labels get a readable floor on phones.
local function minText()
    return React.createElement("UITextSizeConstraint", { MinTextSize = 12 })
end

local function VolumeSlider(props)
    local label = props.label
    local value = props.value or 0.5
    local onChange = props.onChange
    local sliderRef = React.useRef(nil)

    local function onInputBegan(_, input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local frame = sliderRef.current
        if not frame then return end

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

    return React.createElement("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }, {
        label = React.createElement("TextLabel", {
            Position = UDim2.fromScale(0, 0),
            Size = UDim2.fromScale(0.30, 1),
            BackgroundTransparency = 1,
            Text = label,
            TextColor3 = C.text,
            Font = Enum.Font.GothamBold,
            TextScaled = true,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
        track = React.createElement("Frame", {
            ref = sliderRef,
            Position = UDim2.fromScale(0.32, 0.30),
            Size = UDim2.fromScale(0.52, 0.40),
            BackgroundColor3 = C.slider_bg,
            BorderSizePixel = 0,
            -- §AGX/UI-P1: InputBegan moved to the `grab` band below, which
            -- covers the whole track (avoids a double handler).
        }, {
            corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
            fill = React.createElement("Frame", {
                Position = UDim2.fromScale(0, 0),
                Size = UDim2.fromScale(value, 1),
                BackgroundColor3 = C.slider_fill,
                BorderSizePixel = 0,
            }, {
                corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
            }),
            knob = React.createElement("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(value, 0.5),
                -- §AGX/UI-P1: V1: was fromScale(0.007, 0.013) of the track
                -- (sub-pixel, invisible). Now a circle 1.2x the track height,
                -- at least 16 px.
                Size = UDim2.fromScale(1.2, 1.2),
                SizeConstraint = Enum.SizeConstraint.RelativeYY,
                BackgroundColor3 = C.slider_knob,
                BorderSizePixel = 0,
                ZIndex = 2,
            }, {
                corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
                minSize = React.createElement("UISizeConstraint", { MinSize = Vector2.new(16, 16) }),
            }),
            -- §AGX/UI-P1: V1: invisible grab band, at least 44 px tall and
            -- 22 px past each end of the track, so the knob can be grabbed at
            -- 0 % and 100 %. Same handler as the track (values are measured
            -- against the track via sliderRef).
            grab = React.createElement("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.new(1, MIN_TAP_PX, 1, 0),
                BackgroundTransparency = 1,
                ZIndex = 3,
                [React.Event.InputBegan] = onInputBegan,
            }, {
                minSize = React.createElement("UISizeConstraint", { MinSize = Vector2.new(0, MIN_TAP_PX) }),
            }),
        }),
        pct = React.createElement("TextLabel", {
            Position = UDim2.fromScale(0.86, 0),
            Size = UDim2.fromScale(0.14, 1),
            BackgroundTransparency = 1,
            Text = tostring(math.floor(value * 100)) .. "%",
            TextColor3 = C.accent,
            Font = Enum.Font.GothamBold,
            TextScaled = true,
        }, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
    })
end

local function TabButton(props)
    local isActive = props.isActive
    return React.createElement("TextButton", {
        Size = UDim2.fromScale(0.31, 1),
        BackgroundColor3 = isActive and C.tab_on or C.tab_off,
        BorderSizePixel = 0,
        Text = props.label,
        TextColor3 = isActive and C.white or C.text_dim,
        Font = Enum.Font.GothamBold,
        TextScaled = true,
        LayoutOrder = props.order,
        [React.Event.Activated] = props.onActivate,
    }, {
        corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
        minText = minText(),  -- §AGX/UI-P1: M11 text floor
    })
end

local function BindingRow(props)
    local actionName = props.actionName
    local isListening = props.isListening
    local onActivate = props.onActivate
    local definition = InputActions.Definitions[actionName]
    if not definition then
        return nil
    end

    return React.createElement("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = C.section,
        BorderSizePixel = 0,
        LayoutOrder = props.order,
    }, {
        corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
        label = React.createElement("TextLabel", {
            Position = UDim2.fromScale(0.03, 0),
            Size = UDim2.fromScale(0.58, 1),
            BackgroundTransparency = 1,
            Text = definition.displayName,
            TextColor3 = C.text,
            Font = Enum.Font.GothamBold,
            TextScaled = true,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
        keyBtn = React.createElement("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(0.97, 0.5),
            Size = UDim2.fromScale(0.24, 0.68),
            BackgroundColor3 = isListening and C.key_listen or C.key_bg,
            BorderSizePixel = 0,
            Text = isListening and "Press key..." or InputSystem.GetBindingDisplayName(actionName, "Keyboard"),
            TextColor3 = C.white,
            Font = Enum.Font.GothamBold,
            TextScaled = true,
            [React.Event.Activated] = onActivate,
        }, {
            corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
            minText = minText(),  -- §AGX/UI-P1: M11 text floor
            -- §AGX/UI-P1: 30 px tall key button; 44 px hit box (row is 44).
            hit = hitArea(onActivate, Vector2.new(MIN_TAP_PX, MIN_TAP_PX)),
        }),
    })
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
    local activeTab, setActiveTab = React.useState("Audio")
    local listeningFor, setListeningFor = React.useState(nil)
    local bindingsVersion, setBindingsVersion = React.useState(0)

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
                if key == Enum.KeyCode.Escape then
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
            NetworkManager.FireServer("SaveKeybindings", InputSystem.GetAllBindings())
        end)

        return function()
            conn:Disconnect()
        end
    end, { listeningFor })

    local tabButtons = {
        layout = React.createElement("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0.02, 0),
        }),
    }
    for index, tab in ipairs(TAB_ORDER) do
        tabButtons[tab.id] = React.createElement(TabButton, {
            label = tab.label,
            isActive = activeTab == tab.id,
            order = index,
            onActivate = function()
                setListeningFor(nil)
                setActiveTab(tab.id)
            end,
        })
    end

    local content = nil
    if activeTab == "Audio" then
        local sliderHeight = 0.16
        -- §AGX/UI-P1: shared pieces for the desktop (scale) and touch
        -- (44 px list) layouts below.
        local musicInner = React.createElement(VolumeSlider, {
            label = "Music",
            value = musicVol,
            onChange = changeMusicVol,
        })
        local sfxInner = React.createElement(VolumeSlider, {
            label = "SFX",
            value = sfxVol,
            onChange = changeSfxVol,
        })
        local uiInner = React.createElement(VolumeSlider, {
            label = "UI",
            value = uiVol,
            onChange = changeUiVol,
        })
        local function muteButton(position, size, order)
            return React.createElement("TextButton", {
                Position = position,
                Size = size,
                BackgroundColor3 = muted and C.btn_muted or C.btn_active,
                BorderSizePixel = 0,
                Text = muted and "Unmute All" or "Mute All",
                TextColor3 = C.white,
                Font = Enum.Font.GothamBold,
                TextScaled = true,
                LayoutOrder = order,
                [React.Event.Activated] = toggleMute,
            }, {
                corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.15, 0) }),
                minText = minText(),  -- §AGX/UI-P1: M11 text floor
            })
        end

        if IS_TOUCH then
            -- §AGX/UI-P1: touch: 44 px rows in a scroll frame (at a 29 px
            -- row pitch a 44 px grab band would overlap the next slider).
            -- The hint row is dropped; the footer says the same thing.
            local rowSize = UDim2.new(1, -6, 0, MIN_TAP_PX)
            content = React.createElement("ScrollingFrame", {
                Position = UDim2.new(0.04, 0, 0, TOUCH_CONTENT_TOP),
                Size = UDim2.new(0.92, 0, 1, -(TOUCH_CONTENT_TOP + TOUCH_FOOTER_H)),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ScrollBarThickness = 4,
                CanvasSize = UDim2.fromScale(0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollingDirection = Enum.ScrollingDirection.Y,
                ZIndex = 12,
            }, {
                layout = React.createElement("UIListLayout", {
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 4),
                }),
                musicSlider = React.createElement("Frame", {
                    Size = rowSize, BackgroundTransparency = 1, LayoutOrder = 1,
                }, { inner = musicInner }),
                sfxSlider = React.createElement("Frame", {
                    Size = rowSize, BackgroundTransparency = 1, LayoutOrder = 2,
                }, { inner = sfxInner }),
                uiSlider = React.createElement("Frame", {
                    Size = rowSize, BackgroundTransparency = 1, LayoutOrder = 3,
                }, { inner = uiInner }),
                muteBtn = muteButton(UDim2.new(), rowSize, 4),
            })
        else
            content = React.createElement("Frame", {
                Position = UDim2.fromScale(0.04, 0.22),
                Size = UDim2.fromScale(0.92, 0.68),
                BackgroundTransparency = 1,
                ZIndex = 12,
            }, {
                musicSlider = React.createElement("Frame", {
                    Position = UDim2.fromScale(0, 0),
                    Size = UDim2.fromScale(1, sliderHeight),
                    BackgroundTransparency = 1,
                }, {
                    inner = musicInner,
                }),
                sfxSlider = React.createElement("Frame", {
                    Position = UDim2.fromScale(0, sliderHeight + 0.04),
                    Size = UDim2.fromScale(1, sliderHeight),
                    BackgroundTransparency = 1,
                }, {
                    inner = sfxInner,
                }),
                uiSlider = React.createElement("Frame", {
                    Position = UDim2.fromScale(0, (sliderHeight + 0.04) * 2),
                    Size = UDim2.fromScale(1, sliderHeight),
                    BackgroundTransparency = 1,
                }, {
                    inner = uiInner,
                }),
                muteBtn = muteButton(UDim2.fromScale(0, 0.62), UDim2.fromScale(1, 0.12), nil),
                hint = React.createElement("TextLabel", {
                    Position = UDim2.fromScale(0, 0.80),
                    Size = UDim2.fromScale(1, 0.08),
                    BackgroundTransparency = 1,
                    Text = "Audio values update immediately.",
                    TextColor3 = C.text_dim,
                    Font = Enum.Font.Gotham,
                    TextScaled = true,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
            })
        end
    else
        local rows = {
            layout = React.createElement("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 6),
            }),
        }

        local actions = TAB_ACTIONS[activeTab] or {}
        for index, actionName in ipairs(actions) do
            rows[actionName] = React.createElement(BindingRow, {
                actionName = actionName,
                isListening = listeningFor == actionName,
                order = index,
                version = bindingsVersion,
                onActivate = function()
                    setListeningFor(function(current)
                        if current == actionName then
                            return nil
                        end
                        return actionName
                    end)
                end,
            })
        end

        -- §AGX/UI-P1: touch: pixel geometry below the 44 px tab bar, and a
        -- 44 px Reset button; desktop keeps the scale layout.
        content = React.createElement("Frame", {
            Position = IS_TOUCH and UDim2.new(0.04, 0, 0, TOUCH_CONTENT_TOP) or UDim2.fromScale(0.04, 0.22),
            Size = IS_TOUCH and UDim2.new(0.92, 0, 1, -(TOUCH_CONTENT_TOP + TOUCH_FOOTER_H))
                or UDim2.fromScale(0.92, 0.68),
            BackgroundTransparency = 1,
            ZIndex = 12,
        }, {
            hint = React.createElement("TextLabel", {
                Position = UDim2.fromScale(0, 0),
                Size = IS_TOUCH and UDim2.new(1, 0, 0, 20) or UDim2.fromScale(1, 0.10),
                BackgroundTransparency = 1,
                Text = "Click a binding, then press a key or mouse button. Esc cancels.",
                TextColor3 = C.text_dim,
                Font = Enum.Font.Gotham,
                TextScaled = true,
                TextXAlignment = Enum.TextXAlignment.Left,
            }, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
            scroll = React.createElement("ScrollingFrame", {
                Position = IS_TOUCH and UDim2.fromOffset(0, 22) or UDim2.fromScale(0, 0.12),
                Size = IS_TOUCH and UDim2.new(1, 0, 1, -(22 + MIN_TAP_PX + 4)) or UDim2.fromScale(1, 0.72),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ScrollBarThickness = 4,
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                CanvasSize = UDim2.fromScale(0, 0),
            }, rows),
            resetBtn = React.createElement("TextButton", {
                AnchorPoint = Vector2.new(0.5, 1),
                Position = UDim2.fromScale(0.5, 1),
                Size = IS_TOUCH and UDim2.new(0.50, 0, 0, MIN_TAP_PX) or UDim2.fromScale(0.50, 0.12),
                BackgroundColor3 = C.reset_bg,
                BorderSizePixel = 0,
                Text = "Reset All Keybinds",
                TextColor3 = C.white,
                Font = Enum.Font.GothamBold,
                TextScaled = true,
                [React.Event.Activated] = function()
                    InputSystem.ResetAllBindings()
                    setListeningFor(nil)
                    NetworkManager.FireServer("SaveKeybindings", InputSystem.GetAllBindings())
                end,
            }, {
                corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.15, 0) }),
                minText = minText(),  -- §AGX/UI-P1: M11 text floor
            }),
        })
    end

    -- §T10/U3: chrome owned by AppWindow (close also clears key-listen state).
    return React.createElement(AppWindow, {
        variant = "windowed",
        title   = "Settings",
        icon    = "settings",
        onClose = function()
            setListeningFor(nil)
            onClose()
        end,
        size    = UDim2.fromScale(0.48, 0.68),
        -- §AGX/UI-P1: on touch, let AppWindow grow the window (it clamps to
        -- the screen below the topbar). 1080p (922x734) is already larger.
        minSize = IS_TOUCH and Vector2.new(560, 400) or nil,
        zIndex  = 10,
    }, {
            tabBar = React.createElement("Frame", {
                -- §AGX/UI-P1: T8: 44 px tabs on touch (were 15 px on a phone).
                Position = IS_TOUCH and UDim2.new(0.04, 0, 0, 4) or UDim2.fromScale(0.04, 0.13),
                Size = IS_TOUCH and UDim2.new(0.92, 0, 0, MIN_TAP_PX) or UDim2.fromScale(0.92, 0.07),
                BackgroundTransparency = 1,
                ZIndex = 12,
            }, tabButtons),
            content = content,
            version = React.createElement("TextLabel", {
                AnchorPoint = Vector2.new(0.5, 1),
                Position = UDim2.fromScale(0.5, 0.97),
                -- §AGX/UI-P1: 18 px on touch so the 12 px text floor fits.
                Size = IS_TOUCH and UDim2.new(0.90, 0, 0, 18) or UDim2.fromScale(0.90, 0.04),
                BackgroundTransparency = 1,
                Text = activeTab == "Audio" and "Audio settings update immediately." or "Bindings save through SaveKeybindings for testing.",
                TextColor3 = C.text_muted,
                Font = Enum.Font.Gotham,
                TextScaled = true,
                ZIndex = 12,
            }, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor
    })
end

return SettingsUI
