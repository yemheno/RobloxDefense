-- centralboss/StarterPlayerScripts/UI/CentralBossApp.lua
-- Shared CombatApp HUD + the CentralBoss-only boss HP bar (§AGX/X28).
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local SharedUI  = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI")
local CombatApp = require(SharedUI:WaitForChild("CombatApp"))
local BossHud   = require(script.Parent:WaitForChild("BossHud"))

local function CentralBossApp()
	return React.createElement(React.Fragment, nil, {
		combat  = React.createElement(CombatApp),
		bossHud = React.createElement(BossHud),
	})
end

return CentralBossApp
