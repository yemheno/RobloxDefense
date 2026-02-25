-- CameraController

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraController = {}

-- Settings
local CAMERA_OFFSET = Vector3.new(-12, 8, 0) -- Changed from (0, 8, -12)
local LOOK_AHEAD = 20


local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local connection = nil

local function updateCamera()
	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local playerPos = rootPart.Position
	local cameraPos = playerPos + CAMERA_OFFSET
	local lookAtPos = playerPos + Vector3.new(LOOK_AHEAD, 0, 0)

	camera.CFrame = CFrame.new(cameraPos, lookAtPos)
end

local function setupCamera()
	camera.CameraType = Enum.CameraType.Scriptable
end

function CameraController.Init()
	setupCamera()

	connection = RunService.RenderStepped:Connect(updateCamera)

	player.CharacterAdded:Connect(function()
		task.wait(0.1)
		setupCamera()
	end)
end

function CameraController.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	camera.CameraType = Enum.CameraType.Custom
end

return CameraController