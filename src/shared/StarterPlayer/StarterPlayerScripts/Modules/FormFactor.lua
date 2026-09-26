-- StarterPlayerScripts/Modules/FormFactor.lua
--[[
    §AGX/UI-P2: FormFactor, the single (non-React) source of truth for
    "what kind of device is this, and what is it using right now".
    Spec: docs/ui_audit/mobile.md §2.1 and §2.7. React code should use
    UI/Common/useFormFactor.lua instead of calling this directly.

    FormFactor.Get() -> {
        kind     = "Phone" | "Tablet" | "Desktop" | "Console",
        input    = "Touch" | "Gamepad" | "KeyboardMouse",  -- live
        isTouch  = boolean,          -- kind is Phone or Tablet
        viewport = Vector2,
        short    = number,           -- min(viewport.X, viewport.Y)
        topbar   = number,           -- GuiService.TopbarInset.Height, else GetGuiInset().Y
        tokens   = Theme.Layout[kind],
        uiScale  = number,           -- tokens.uiScale (recorded, not applied: D2)
    }
    The snapshot is a fresh, read-only-by-convention table per change, so
    React can compare it by reference.

    FormFactor.Changed(cb) -> disconnect()
        cb(snapshot) runs after any change of kind, input, viewport or topbar.

    Recomputes on:
      • CurrentCamera.ViewportSize (and a CurrentCamera swap)
      • UserInputService.LastInputTypeChanged, debounced (Theme.Layout
        .Breakpoints.inputDebounce = 0.25 s), so one stray key on a tablet
        doesn't flip the layout
      • GuiService TopbarInset changes
      • UserInputService.PreferredInput changes, ONLY if that property
        exists in this engine version (pcall feature check)
]]

local FormFactor = {}

local GuiService       = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

-- Modules/FormFactor -> PlayerScripts/UI/Common/Theme
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("Theme"))

local Breakpoints = Theme.Layout.Breakpoints

-- ═══════════════════════════════════════════════════════════
-- READERS
-- ═══════════════════════════════════════════════════════════

-- §AGX/UI-P2: PreferredInput is newer than this codebase; probe it with pcall
-- so an engine without it silently falls back to LastInputType.
local function readPreferredInput()
	local ok, value = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if not ok or typeof(value) ~= "EnumItem" then return nil end
	local name = value.Name
	if name == "Touch" then return "Touch" end
	if name == "Gamepad" then return "Gamepad" end
	if string.find(name, "Keyboard", 1, true) or string.find(name, "Mouse", 1, true) then
		return "KeyboardMouse"
	end
	return nil
end

local MOUSE_KEYBOARD_TYPES = {
	[Enum.UserInputType.Keyboard]       = true,
	[Enum.UserInputType.MouseButton1]   = true,
	[Enum.UserInputType.MouseButton2]   = true,
	[Enum.UserInputType.MouseButton3]   = true,
	[Enum.UserInputType.MouseMovement]  = true,
	[Enum.UserInputType.MouseWheel]     = true,
	[Enum.UserInputType.TextInput]      = true,
}

-- nil = "this input type says nothing about the device" (Focus, None, Gyro…)
local function inputFromType(inputType)
	if inputType == Enum.UserInputType.Touch then return "Touch" end
	if MOUSE_KEYBOARD_TYPES[inputType] then return "KeyboardMouse" end
	if typeof(inputType) == "EnumItem" and string.sub(inputType.Name, 1, 7) == "Gamepad" then
		return "Gamepad"
	end
	return nil
end

local function inputFromCapabilities()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "KeyboardMouse"
end

local lastKnownInput = nil

local function readInput()
	local preferred = readPreferredInput()
	if preferred then
		lastKnownInput = preferred
		return preferred
	end
	local fromLast = inputFromType(UserInputService:GetLastInputType())
	if fromLast then
		lastKnownInput = fromLast
		return fromLast
	end
	return lastKnownInput or inputFromCapabilities()
end

local function readViewport()
	local cam = workspace.CurrentCamera
	if cam then return cam.ViewportSize end
	return Vector2.new(1280, 720)
end

local function readTopbar()
	local ok, rect = pcall(function()
		return (GuiService :: any).TopbarInset
	end)
	if ok and typeof(rect) == "Rect" and rect.Height > 0 then
		return rect.Height
	end
	local inset = GuiService:GetGuiInset()
	return inset.Y
end

local function isTenFoot()
	local ok, result = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and result == true
end

-- mobile.md §2.7 classify()
local function classify(viewport, input)
	if isTenFoot() then return "Console" end
	if input == "Gamepad" and not UserInputService.TouchEnabled then return "Console" end
	if input == "Touch"
		or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and input ~= "Gamepad") then
		local short = math.min(viewport.X, viewport.Y)
		return (short <= Breakpoints.phoneMaxShort) and "Phone" or "Tablet"
	end
	return "Desktop"
end

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local current = nil
local listeners = {}
local nextListenerId = 1

local function build()
	local viewport = readViewport()
	local input    = readInput()
	local kind     = classify(viewport, input)
	local tokens   = Theme.Layout[kind]
	return {
		kind     = kind,
		input    = input,
		isTouch  = (kind == "Phone" or kind == "Tablet"),
		viewport = viewport,
		short    = math.min(viewport.X, viewport.Y),
		topbar   = readTopbar(),
		tokens   = tokens,
		uiScale  = tokens.uiScale or 1,
	}
end

local function differs(a, b)
	return a.kind ~= b.kind or a.input ~= b.input
		or a.viewport ~= b.viewport or a.topbar ~= b.topbar
end

local function recompute()
	local nextState = build()
	if current and not differs(current, nextState) then return end
	current = nextState
	for _, cb in pairs(listeners) do
		task.spawn(cb, nextState)
	end
end

-- ═══════════════════════════════════════════════════════════
-- SIGNAL WIRING (once, at first require)
-- ═══════════════════════════════════════════════════════════

local inputToken = 0
local function recomputeInputDebounced()
	inputToken += 1
	local myToken = inputToken
	task.delay(Breakpoints.inputDebounce, function()
		if myToken == inputToken then recompute() end
	end)
end

local viewportConn = nil
local function watchCamera()
	if viewportConn then viewportConn:Disconnect(); viewportConn = nil end
	local cam = workspace.CurrentCamera
	if cam then
		viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(recompute)
	end
	recompute()
end

current = build()

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

UserInputService.LastInputTypeChanged:Connect(recomputeInputDebounced)

pcall(function()
	(UserInputService :: any):GetPropertyChangedSignal("PreferredInput"):Connect(recomputeInputDebounced)
end)

-- TopbarInset may not exist on older engines; GetGuiInset has no signal, so
-- viewport changes (which also move the inset) cover that fallback.
pcall(function()
	(GuiService :: any):GetPropertyChangedSignal("TopbarInset"):Connect(recompute)
end)

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════

function FormFactor.Get()
	return current
end

--- Subscribe to changes. Returns a disconnect function.
function FormFactor.Changed(callback)
	local id = nextListenerId
	nextListenerId += 1
	listeners[id] = callback
	return function()
		listeners[id] = nil
	end
end

--- Called by bootstrap loaders that Init every module (idempotent no-op).
function FormFactor.Init() end

return FormFactor
