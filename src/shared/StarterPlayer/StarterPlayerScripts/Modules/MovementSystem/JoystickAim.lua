-- MovementSystem/JoystickAim
--[[
    Mobile aiming constraint — uses a virtual joystick UI to control
    the direction the character faces.

    Only activates on touch devices (TouchEnabled).
    On PC, Start() is a no-op — FaceMouse handles PC aiming.

    The joystick UI element is created and managed by this module.
    When the player drags on the joystick area, the character faces
    the direction indicated by the drag vector.

    When touch ends, AutoRotate is re-enabled so WASD/thumbstick
    movement works naturally until the player aims again.

    Config (passed to Start):
        joystickParent : Instance  — ScreenGui or Frame to parent the joystick into.
                                     If nil, a ScreenGui is created automatically.
        position       : UDim2     — joystick base position
                                     (default: bottom-right corner)
        size           : number    — joystick base diameter in pixels (default: 120)

    §AGX/UI-P2 (mobile.md §2.4 D11, M10):
      • The aim follows the ONE touch that started it (another finger
        lifting, e.g. the movement thumb, never cancels it).
      • Twin-stick: when the touch SkillPad is mounted it calls
        SetExternalControl(true); this module's own stick is then hidden and
        the SkillPad's Attack button drives facing via AimDelta()/EndAim()
        (same screen->world maths as the stick).
      • The stick is only shown while FormFactor says the device is in touch
        use (a touch laptop on its mouse doesn't get it).
      • IsActive()/OnActiveChanged() tell the SkillPad whether this Place
        uses joystick aiming (HordeMode enables it; Lane/Boss don't).

    Reference: User-provided joystick script
        direction = (inputPosition - center).Unit
        CFrame.new(pos, pos + Vector3.new(direction.Y, 0, -direction.X))
]]

local JoystickAim = {}

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- §AGX/UI-P2: live touch-vs-mouse state (mobile.md §2.7 consumers).
local FormFactor = require(script.Parent.Parent:WaitForChild("FormFactor"))

local player     = Players.LocalPlayer
local isMobile   = false

-- Internal state
local screenGui    = nil
local joystickBase = nil
local joystickKnob = nil
local aimConnection = nil
local endConnection = nil
local charConn      = nil
local isAiming      = false
-- §AGX/UI-P2 (M10): the InputObject of the touch that owns the aim.
local aimTouch      = nil
local beganConnection = nil
local ffDisconnect    = nil
-- §AGX/UI-P2: twin-stick hand-off state.
local active          = false  -- Start() ran on a touch device
local externalCount   = 0      -- SkillPads currently driving the aim
local activeListeners = {}
local activeNextId    = 1
local MIN_DRAG        = 10     -- px, jitter floor

-- Config defaults
local DEFAULT_SIZE     = 120
local DEFAULT_POSITION = UDim2.new(1, -160, 1, -160)

local baseSize = DEFAULT_SIZE

local function disableAutoRotate(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
	end
end

local function enableAutoRotate(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
	end
end

-- §AGX/UI-P2: screen-space delta -> character facing. Shared by the built-in
-- stick and the SkillPad twin-stick (AimDelta). Returns the unit direction
-- used, or nil when the delta is inside the jitter floor.
local function faceScreenDelta(delta)
	local character = player.Character
	if not character then return nil end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil end

	-- Require minimum drag distance to avoid jitter
	if delta.Magnitude < MIN_DRAG then return nil end

	local dir = delta.Unit

	-- Map 2D screen direction to 3D world direction
	-- Screen Y ↓ = world -Z, Screen X → = world +X
	-- Using the reference formula: Vector3(direction.Y, 0, -direction.X)
	-- but correcting for screen Y being inverted (down = positive)
	local worldDir = Vector3.new(dir.X, 0, -dir.Y)
	if worldDir.Magnitude < 0.01 then return nil end

	local pos = rootPart.Position
	rootPart.CFrame = CFrame.new(pos, pos + worldDir)
	return dir
end

local function updateFacing(inputPosition)
	if not joystickBase then return end
	local center = joystickBase.AbsolutePosition + joystickBase.AbsoluteSize / 2
	local delta  = inputPosition - center
	local dir = faceScreenDelta(delta)
	if not dir then return end

	-- Move knob visual to indicate direction
	if joystickKnob then
		local maxDist = baseSize * 0.35
		local clampedDist = math.min(delta.Magnitude, maxDist)
		local knobOffset = dir * clampedDist
		joystickKnob.Position = UDim2.new(
			0.5, knobOffset.X - baseSize * 0.15,
			0.5, knobOffset.Y - baseSize * 0.15
		)
	end
end

local function createJoystickUI(config)
	local pos  = config.position or DEFAULT_POSITION
	local size = config.size     or DEFAULT_SIZE
	baseSize   = size

	-- ScreenGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name             = "JoystickAimGui"
	screenGui.ResetOnSpawn     = false
	screenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset   = false
	screenGui.DisplayOrder     = 5
	screenGui.Parent           = player:WaitForChild("PlayerGui")

	-- Base circle (semi-transparent background)
	joystickBase = Instance.new("Frame")
	joystickBase.Name                   = "JoystickBase"
	joystickBase.AnchorPoint            = Vector2.new(0.5, 0.5)
	joystickBase.Position               = pos
	joystickBase.Size                   = UDim2.fromOffset(size, size)
	joystickBase.BackgroundColor3       = Color3.fromRGB(40, 40, 60)
	joystickBase.BackgroundTransparency = 0.6
	joystickBase.BorderSizePixel        = 0
	joystickBase.Parent                 = screenGui

	local baseCorner = Instance.new("UICorner")
	baseCorner.CornerRadius = UDim.new(0.5, 0)
	baseCorner.Parent       = joystickBase

	local baseStroke = Instance.new("UIStroke")
	baseStroke.Color     = Color3.fromRGB(100, 100, 140)
	baseStroke.Thickness = 2
	baseStroke.Parent    = joystickBase

	-- Knob (inner circle)
	local knobSize = math.floor(size * 0.3)
	joystickKnob = Instance.new("Frame")
	joystickKnob.Name                   = "JoystickKnob"
	joystickKnob.AnchorPoint            = Vector2.new(0.5, 0.5)
	joystickKnob.Position               = UDim2.fromScale(0.5, 0.5)
	joystickKnob.Size                   = UDim2.fromOffset(knobSize, knobSize)
	joystickKnob.BackgroundColor3       = Color3.fromRGB(160, 160, 200)
	joystickKnob.BackgroundTransparency = 0.3
	joystickKnob.BorderSizePixel        = 0
	joystickKnob.Parent                 = joystickBase

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(0.5, 0)
	knobCorner.Parent       = joystickKnob
end

-- §AGX/UI-P2: the built-in stick shows only while nobody drives the aim
-- externally and the device is in touch use.
local function refreshStickVisibility()
	if screenGui then
		screenGui.Enabled = externalCount == 0 and FormFactor.Get().isTouch
	end
end

local function pointInBase(pos)
	if not joystickBase or not screenGui or not screenGui.Enabled then return false end
	local basePos   = joystickBase.AbsolutePosition
	local baseSize2 = joystickBase.AbsoluteSize
	return pos.X >= basePos.X and pos.X <= basePos.X + baseSize2.X
		and pos.Y >= basePos.Y and pos.Y <= basePos.Y + baseSize2.Y
end

local function endStickAim()
	aimTouch = nil
	if isAiming then
		isAiming = false
		local char = player.Character
		if char then enableAutoRotate(char) end
	end
	if joystickKnob then
		joystickKnob.Position = UDim2.fromScale(0.5, 0.5)
	end
end

local function setActive(value)
	if active == value then return end
	active = value
	for _, cb in pairs(activeListeners) do
		task.spawn(cb, value)
	end
end

local function destroyJoystickUI()
	if screenGui then
		screenGui:Destroy()
		screenGui    = nil
		joystickBase = nil
		joystickKnob = nil
	end
end

function JoystickAim.Start(config)
	config = config or {}

	-- Only run on touch devices
	isMobile = UserInputService.TouchEnabled
	if not isMobile then
		print("[JoystickAim] Not a touch device — skipping (use FaceMouse)")
		return
	end

	createJoystickUI(config)
	-- §AGX/UI-P2: hide if a SkillPad already owns the aim, and follow
	-- touch <-> mouse switches.
	refreshStickVisibility()
	if ffDisconnect then ffDisconnect() end
	ffDisconnect = FormFactor.Changed(refreshStickVisibility)

	local character = player.Character
	if character then
		disableAutoRotate(character)
	end

	if charConn then charConn:Disconnect() end
	charConn = player.CharacterAdded:Connect(function(newChar)
		task.wait()
		-- On respawn, don't force disable — let touch start re-disable
	end)

	-- Listen to touch input
	-- §AGX/UI-P2 (M10): claim the touch that starts on the stick (or first
	-- drags into it) and follow only that touch until it lifts, even if the
	-- finger slides off the base. Other fingers (movement thumb) are ignored.
	local function claim(input)
		aimTouch = input
		if not isAiming then
			isAiming = true
			local char = player.Character
			if char then disableAutoRotate(char) end
		end
	end

	if beganConnection then beganConnection:Disconnect() end
	beganConnection = UserInputService.TouchStarted:Connect(function(input, _gameProcessed)
		if externalCount > 0 or aimTouch then return end
		local inputPos = Vector2.new(input.Position.X, input.Position.Y)
		if pointInBase(inputPos) then
			claim(input)
			updateFacing(inputPos)
		end
	end)

	if aimConnection then aimConnection:Disconnect() end
	aimConnection = UserInputService.TouchMoved:Connect(function(input, _gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if externalCount > 0 then return end

		local inputPos = Vector2.new(input.Position.X, input.Position.Y)

		if aimTouch == nil and pointInBase(inputPos) then
			claim(input)
		end
		if input == aimTouch then
			updateFacing(inputPos)
		end
	end)

	if endConnection then endConnection:Disconnect() end
	endConnection = UserInputService.TouchEnded:Connect(function(input, _gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if input == aimTouch then
			endStickAim()
		end
	end)

	setActive(true)
end

function JoystickAim.Stop()
	-- §AGX/UI-P2: M10 / twin-stick connections.
	if beganConnection then
		beganConnection:Disconnect()
		beganConnection = nil
	end
	if ffDisconnect then
		ffDisconnect()
		ffDisconnect = nil
	end
	aimTouch = nil
	if aimConnection then
		aimConnection:Disconnect()
		aimConnection = nil
	end
	if endConnection then
		endConnection:Disconnect()
		endConnection = nil
	end
	if charConn then
		charConn:Disconnect()
		charConn = nil
	end
	isAiming = false
	local character = player.Character
	if character then
		enableAutoRotate(character)
	end
	destroyJoystickUI()
	setActive(false)
end

-- ═══════════════════════════════════════════════════════════
-- TWIN-STICK API (§AGX/UI-P2, D11)
-- ═══════════════════════════════════════════════════════════

--- True while joystick aiming is enabled in this Place (touch device).
function JoystickAim.IsActive()
	return active
end

--- cb(isActive) when Start/Stop change it. Returns a disconnect function.
function JoystickAim.OnActiveChanged(callback)
	local id = activeNextId
	activeNextId = activeNextId + 1
	activeListeners[id] = callback
	return function()
		activeListeners[id] = nil
	end
end

--- A SkillPad takes over (true) or hands back (false) the aim. Counted, so
--- nested mounts are safe. While taken, the built-in stick is hidden.
function JoystickAim.SetExternalControl(enabled)
	if enabled then
		externalCount = externalCount + 1
		endStickAim()
	else
		externalCount = math.max(0, externalCount - 1)
	end
	refreshStickVisibility()
end

--- Face along a screen-space drag vector (from the twin-stick's centre).
--- Returns true when facing was applied (outside the jitter floor).
function JoystickAim.AimDelta(delta)
	if not active then return false end
	local char = player.Character
	if not char then return false end
	if not isAiming then
		isAiming = true
		disableAutoRotate(char)
	end
	return faceScreenDelta(delta) ~= nil
end

--- End a twin-stick aim: AutoRotate back on, as when the stick is released.
function JoystickAim.EndAim()
	if aimTouch then return end  -- the built-in stick owns the aim
	if isAiming then
		isAiming = false
		local char = player.Character
		if char then enableAutoRotate(char) end
	end
end

return JoystickAim
