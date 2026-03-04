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

    Reference: User-provided joystick script
        direction = (inputPosition - center).Unit
        CFrame.new(pos, pos + Vector3.new(direction.Y, 0, -direction.X))
]]

local JoystickAim = {}

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

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

local function updateFacing(inputPosition)
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local center = joystickBase.AbsolutePosition + joystickBase.AbsoluteSize / 2
	local delta  = inputPosition - center

	-- Require minimum drag distance to avoid jitter
	if delta.Magnitude < 10 then return end

	local dir = delta.Unit

	-- Map 2D screen direction to 3D world direction
	-- Screen Y ↓ = world -Z, Screen X → = world +X
	-- Using the reference formula: Vector3(direction.Y, 0, -direction.X)
	-- but correcting for screen Y being inverted (down = positive)
	local worldDir = Vector3.new(dir.X, 0, -dir.Y)
	if worldDir.Magnitude < 0.01 then return end

	local pos = rootPart.Position
	rootPart.CFrame = CFrame.new(pos, pos + worldDir)

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
	if aimConnection then aimConnection:Disconnect() end
	aimConnection = UserInputService.TouchMoved:Connect(function(input, gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end

		local inputPos = Vector2.new(input.Position.X, input.Position.Y)

		-- Check if touch is within joystick area
		if not joystickBase then return end
		local basePos  = joystickBase.AbsolutePosition
		local baseSize2 = joystickBase.AbsoluteSize
		if inputPos.X >= basePos.X and inputPos.X <= basePos.X + baseSize2.X
			and inputPos.Y >= basePos.Y and inputPos.Y <= basePos.Y + baseSize2.Y then

			if not isAiming then
				isAiming = true
				local char = player.Character
				if char then disableAutoRotate(char) end
			end
			updateFacing(inputPos)
		end
	end)

	if endConnection then endConnection:Disconnect() end
	endConnection = UserInputService.TouchEnded:Connect(function(input, gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if isAiming then
			isAiming = false
			local char = player.Character
			if char then enableAutoRotate(char) end
			-- Reset knob to center
			if joystickKnob then
				joystickKnob.Position = UDim2.fromScale(0.5, 0.5)
			end
		end
	end)
end

function JoystickAim.Stop()
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
end

return JoystickAim
