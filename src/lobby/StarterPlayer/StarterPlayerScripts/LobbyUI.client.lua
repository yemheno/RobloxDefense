-- lobby/StarterPlayerScripts/LobbyUI.client.lua
--[[
    Lobby UI mount point.
    Creates a ScreenGui and renders the LobbyApp React root.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React     = require(ReplicatedStorage.Packages.React)
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

local LobbyApp = require(script.Parent:WaitForChild("UI"):WaitForChild("LobbyApp"))
root:render(React.createElement(LobbyApp))

-- §RG1: signal "ClientReady" to the server so it can drain any boot-time
-- events that were queued before our React useEffect subscriptions
-- registered. We defer one frame (task.defer) and add a small slack so
-- the React tree's first commit and useEffect mount have completed.
-- NetworkManager lives at PlayerScripts.Modules per the Rojo layout.
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
