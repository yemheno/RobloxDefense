-- CameraSystem/TopDown
--[[
    Top-down camera that follows the player from directly above with
    a configurable diagonal offset — replicating a classic arcade / horde
    survival perspective.

    Config (passed to Start):
        heightOffset : number   — height above the player          (default: 40)
        sideOffset   : Vector3  — horizontal shift from player pos (default: 5, 0, 0)
        cameraShift  : Vector3  — distance from player to camera   (default: 20, 0, 0)
        fov          : number   — field of view                    (default: 60)

    Reference: OldScripts.rbxmx FixedCamera module
        PlayerPosition = HRP.Position + Vector3(5, 0, 0)
        CameraPosition = PlayerPosition + Vector3(20, 40, 0)
        Camera looks at PlayerPosition from CameraPosition.
]]

local TopDown = {}

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player  = Players.LocalPlayer
local camera  = workspace.CurrentCamera

-- Defaults (matching RBXMX reference)
local DEFAULT_HEIGHT_OFFSET = 40
local DEFAULT_SIDE_OFFSET   = Vector3.new(5, 0, 0)
local DEFAULT_CAMERA_SHIFT  = Vector3.new(16, 0, 0)
local DEFAULT_FOV           = 60

local heightOffset = DEFAULT_HEIGHT_OFFSET
local sideOffset   = DEFAULT_SIDE_OFFSET
local cameraShift  = DEFAULT_CAMERA_SHIFT
local fov          = DEFAULT_FOV

local connection = nil
local charConn   = nil

local function updateCamera()
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local playerPos = rootPart.Position + sideOffset
	local camPos    = playerPos + cameraShift + Vector3.new(0, heightOffset, 0)
	camera.CFrame = CFrame.new(camPos, playerPos)
end

local function setupCamera()
	camera.CameraType   = Enum.CameraType.Scriptable
	camera.FieldOfView  = fov
end

function TopDown.Start(config)
	config = config or {}
	heightOffset = config.heightOffset or DEFAULT_HEIGHT_OFFSET
	sideOffset   = config.sideOffset   or DEFAULT_SIDE_OFFSET
	cameraShift  = config.cameraShift  or DEFAULT_CAMERA_SHIFT
	fov          = config.fov          or DEFAULT_FOV

	setupCamera()

	if connection then connection:Disconnect() end
	connection = RunService.RenderStepped:Connect(updateCamera)

	if charConn then charConn:Disconnect() end
	charConn = player.CharacterAdded:Connect(function()
		task.wait(0.1)
		setupCamera()
	end)
end

function TopDown.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if charConn then
		charConn:Disconnect()
		charConn = nil
	end
	camera.CameraType  = Enum.CameraType.Custom
	camera.FieldOfView = 70 -- Roblox default
end

return TopDown
