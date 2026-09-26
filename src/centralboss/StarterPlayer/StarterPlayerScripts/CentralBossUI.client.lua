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
-- §AGX/UI-P1: M8/§2.3: keep interactive UI out of the notch / rounded
-- corners. Set AFTER IgnoreGuiInset (that legacy flag writes ScreenInsets:
-- true => None). DeviceSafeInsets does NOT avoid the Roblox topbar, so
-- the HUD's safeTop (GetGuiInset().Y) is still needed and is not
-- double-counted: in landscape (forced below) the device top inset is 0
-- and the notch only trims the left/right edges.
screenGui.ScreenInsets   = Enum.ScreenInsets.DeviceSafeInsets
screenGui.Parent           = playerGui

-- §AGX/UI-P1: D4 = landscape only. Every panel assumes a wide aspect; set
-- it on this client's PlayerGui (StarterGui.ScreenOrientation is only a
-- template and may be overridden by the place file).
playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

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
    -- §PERF/BP: handshake landmark on the client timeline.
    require(game:GetService("ReplicatedStorage")
        :WaitForChild("Shared"):WaitForChild("BootProfiler")).Mark("ClientReady fired")
end)
