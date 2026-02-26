-- CameraSystem/Free
--[[
    Default / free-roam camera mode.

    Start() resets the camera to Roblox's default CameraType.Custom.
    Stop() is a no-op (the camera is already in its natural state).
]]

local Free = {}

local camera = workspace.CurrentCamera

function Free.Start(_config)
	camera.CameraType = Enum.CameraType.Custom
end

function Free.Stop()
	-- Nothing to tear down; the camera is already in default state.
end

return Free
