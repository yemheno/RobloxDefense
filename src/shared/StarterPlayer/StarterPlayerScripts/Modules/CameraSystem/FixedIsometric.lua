-- CameraSystem/FixedIsometric
--[[
    Isometric / fixed-angle camera that follows the player.

    Config (passed to Start):
        offset    : Vector3  — camera offset from player  (default: -12, 8, 0)
        lookAhead : number   — units to look ahead on +X  (default: 20)
]]

local FixedIsometric = {}

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player  = Players.LocalPlayer
local camera  = workspace.CurrentCamera

-- ── Defaults ──────────────────────────────────────────────
local DEFAULT_OFFSET    = Vector3.new(-12, 8, 0)
local DEFAULT_LOOK_AHEAD = 20

local offset    = DEFAULT_OFFSET
local lookAhead = DEFAULT_LOOK_AHEAD
local connection  = nil
local charConn    = nil

-- ── Internal ──────────────────────────────────────────────
local function updateCamera()
	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local pos      = rootPart.Position
	local camPos   = pos + offset
	local lookAt   = pos + Vector3.new(lookAhead, 0, 0)

	camera.CFrame = CFrame.new(camPos, lookAt)
end

local function setupCamera()
	camera.CameraType = Enum.CameraType.Scriptable
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC
-- ═══════════════════════════════════════════════════════════

function FixedIsometric.Start(config)
	config = config or {}
	offset    = config.offset    or DEFAULT_OFFSET
	lookAhead = config.lookAhead or DEFAULT_LOOK_AHEAD

	setupCamera()

	if connection then connection:Disconnect() end
	connection = RunService.RenderStepped:Connect(updateCamera)

	if charConn then charConn:Disconnect() end
	charConn = player.CharacterAdded:Connect(function()
		task.wait(0.1)
		setupCamera()
	end)
end

function FixedIsometric.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if charConn then
		charConn:Disconnect()
		charConn = nil
	end
	camera.CameraType = Enum.CameraType.Custom
end

return FixedIsometric
