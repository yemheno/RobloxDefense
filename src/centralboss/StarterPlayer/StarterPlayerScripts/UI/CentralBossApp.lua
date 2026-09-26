-- centralboss/StarterPlayerScripts/UI/CentralBossApp.lua
-- Shared CombatApp HUD + the CentralBoss-only boss HP bar (§AGX/X28).
-- §AGX/UI-P5 (W2): the boss bar renders in the HUD's top-centre slot
-- (BossHud slotted mode), so the HUD's Layout owns UI_TopCentreReservedPx
-- and pushes Start / Next Wave / Return below it. CombatApp renders the
-- Shell (and so Notify.Host / the TooltipHost) exactly once.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local SharedUI  = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI")
local CombatApp = require(SharedUI:WaitForChild("CombatApp"))
local BossHud   = require(script.Parent:WaitForChild("BossHud"))

local function CentralBossApp()
	return React.createElement(CombatApp, {
		topCentreSlot = React.createElement(BossHud, { slotted = true }),
	})
end

return CentralBossApp
