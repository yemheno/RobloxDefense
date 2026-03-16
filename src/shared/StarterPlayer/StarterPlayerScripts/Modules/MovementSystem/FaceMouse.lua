-- MovementSystem/FaceMouse
--[[
    Forces the character to face the mouse cursor position every frame.
    Only activates on PC (MouseEnabled and NOT TouchEnabled).
    On mobile/touch devices, Start() is a no-op — the companion
    JoystickAim constraint handles mobile aiming.

    The character rotates on the XZ plane only (Y is flattened).

    Config (passed to Start):
        (none currently)

    Reference: OldScripts.rbxmx AimPC module
        Root.CFrame = CFrame.new(RootPos, Vector3.new(mousePos.X, RootPos.Y, mousePos.Z))
]]

local FaceMouse = {}

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player     = Players.LocalPlayer
local camera     = workspace.CurrentCamera
local connection = nil
local charConn   = nil
local isPC       = false

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

	local rootPos  = rootPart.Position
	local mouseLocation = UserInputService:GetMouseLocation()
	local viewRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	-- Project ray onto the Y-plane of the character root
	local t = (rootPos.Y - viewRay.Origin.Y) / viewRay.Direction.Y
	if t ~= t or math.abs(t) > 10000 then return end -- NaN / parallel guard
	local worldHit = viewRay.Origin + viewRay.Direction * t
	local flatTarget = Vector3.new(worldHit.X, rootPos.Y, worldHit.Z)
	local dir = flatTarget - rootPos
	if dir.Magnitude < 0.01 then return end

	rootPart.CFrame = CFrame.new(rootPos, flatTarget)
end

function FaceMouse.Start(config)
	-- Only run on PC (mouse enabled, not touch)
	isPC = UserInputService.MouseEnabled and not UserInputService.TouchEnabled
	if not isPC then
		print("[FaceMouse] Touch device detected — skipping (use JoystickAim)")
		return
	end

	local character = player.Character
	if character then
		disableAutoRotate(character)
	end

	if charConn then charConn:Disconnect() end
	charConn = player.CharacterAdded:Connect(function(newChar)
		task.wait()
		disableAutoRotate(newChar)
	end)

	if connection then connection:Disconnect() end
	connection = RunService.RenderStepped:Connect(update)
end

function FaceMouse.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if charConn then
		charConn:Disconnect()
		charConn = nil
	end
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.AutoRotate = true end
	end
end

return FaceMouse
