-- centralboss/StarterPlayerScripts/CentralBossUI.client.lua
--[[
    CentralBoss UI mount point.
    Creates a ScreenGui and renders the CentralBossApp React root.
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

local CentralBossApp = require(script.Parent:WaitForChild("UI"):WaitForChild("CentralBossApp"))
root:render(React.createElement(CentralBossApp))

-- §RG1 fix-up: NetworkManager lives at PlayerScripts.Modules.
task.defer(function()
    task.wait(0.15)
    local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
    local Modules = PlayerScripts:WaitForChild("Modules")
    local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
    NetworkManager.FireServer("ClientReady")
end)
