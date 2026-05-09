-- socialplaza/StarterPlayerScripts/SocialPlazaUI.client.lua
--[[
    Social Plaza UI mount point.
    Creates a ScreenGui and renders the SocialPlazaApp React root.
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
screenGui.Name           = "AppGui"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.Parent         = playerGui

local root = ReactRoblox.createRoot(screenGui)

local SocialPlazaApp = require(script.Parent:WaitForChild("UI"):WaitForChild("SocialPlazaApp"))
root:render(React.createElement(SocialPlazaApp))
