-- MovementSystem/FaceDirection
--[[
    Forces the character to face a fixed world direction every frame.

    Config (passed to Start):
        direction : Vector3  — unit direction to face (default: +X = 1,0,0)
]]

local FaceDirection = {}

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player     = Players.LocalPlayer
local direction  = Vector3.new(1, 0, 0)
local connection = nil
local charConn   = nil   -- PlayerCharacterAdded connection

local function disableAutoRotate(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
	end
end

local function update()
	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local pos = rootPart.Position
	rootPart.CFrame = CFrame.new(pos, pos + direction)
end

function FaceDirection.Start(config)
	config = config or {}
	direction = config.direction or Vector3.new(1, 0, 0)

	-- Disable AutoRotate on the current character
	local character = player.Character
	if character then
		disableAutoRotate(character)
	end

	-- Also disable AutoRotate on every future character (respawns)
	if charConn then charConn:Disconnect() end
	charConn = player.CharacterAdded:Connect(function(newChar)
		-- Wait one frame so the Humanoid has fully initialised before we touch it
		task.wait()
		disableAutoRotate(newChar)
	end)

	if connection then connection:Disconnect() end
	connection = RunService.RenderStepped:Connect(update)
end

function FaceDirection.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end

	if charConn then
		charConn:Disconnect()
		charConn = nil
	end

	-- Re-enable AutoRotate on current character
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.AutoRotate = true end
	end
end

return FaceDirection
