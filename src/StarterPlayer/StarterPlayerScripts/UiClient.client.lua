--[[
    UiClient.client.lua
    React UI entry point. Creates a persistent ScreenGui and mounts the root App component.
    All game UI panels are rendered through this tree.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AppGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local root = ReactRoblox.createRoot(screenGui)

local App = require(script.Parent:WaitForChild("UI"):WaitForChild("App"))
root:render(React.createElement(App))
