-- lanedefense/StarterPlayerScripts/LaneDefenseUI.client.lua
--[[
    LaneDefense UI mount point.
    Creates a ScreenGui and renders the LaneDefenseApp React root.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React       = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local existingGui = playerGui:FindFirstChild("AppGui")
if existingGui then
    existingGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name             = "AppGui"
screenGui.ResetOnSpawn     = false
screenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset   = true
screenGui.Parent           = playerGui

local root = ReactRoblox.createRoot(screenGui)

local LaneDefenseApp = require(script.Parent:WaitForChild("UI"):WaitForChild("LaneDefenseApp"))
root:render(React.createElement(LaneDefenseApp))

-- §RG1 fix-up: signal ClientReady so the server's ReadyGate drains any
-- queued boot-time events. See lobby/.../LobbyUI.client.lua for protocol
-- details. The shared NetworkManager module lives at
-- PlayerScripts.Modules.NetworkManager (NOT under the place subfolder),
-- per the Rojo layout used by LaneDefenseClient.client.lua.
task.defer(function()
    task.wait(0.15)
    local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
    local Modules = PlayerScripts:WaitForChild("Modules")
    local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
    NetworkManager.FireServer("ClientReady")
    -- §PERF/BP: handshake landmark on the client timeline.
    require(game:GetService("ReplicatedStorage")
        :WaitForChild("Shared"):WaitForChild("BootProfiler")).Mark("ClientReady fired")
end)
