-- socialplaza/StarterPlayerScripts/UI/SocialPlazaApp.lua
--[[
    Root React component for the Social Plaza place.

    §AGX/UI-P3 (W2): a thin wrapper around the shared Shell
    (UI/Shell/Shell.lua) with place = "Plaza". Appearance-centric: no
    combat HUD, matchmaking or class bars. The Shell mounts the HUD (rail /
    ☰ menu, and on touch the Emote + Wardrobe quick buttons), PanelHost (Wardrobe, CharacterCreation, the
    leave confirm and every other Plaza entry in Shell/Registry), the
    EmoteWheel (Q), Notify.Host and the TooltipHost.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local SharedUI = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI")
local Shell    = require(SharedUI:WaitForChild("Shell"):WaitForChild("Shell"))

local function SocialPlazaApp()
	return React.createElement(Shell, { place = "Plaza" })
end

return SocialPlazaApp
