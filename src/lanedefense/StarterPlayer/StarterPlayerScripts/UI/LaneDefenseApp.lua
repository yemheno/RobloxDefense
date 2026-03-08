-- lanedefense/StarterPlayerScripts/UI/LaneDefenseApp.lua
-- Thin wrapper: re-exports the shared CombatApp component.
local Players  = game:GetService("Players")
local SharedUI = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI")
return require(SharedUI:WaitForChild("CombatApp"))