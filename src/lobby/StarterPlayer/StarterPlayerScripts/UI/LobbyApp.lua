-- lobby/StarterPlayerScripts/UI/LobbyApp.lua
--[[
    Root React component for the Lobby place.

    §AGX/UI-P3 (W2): a thin wrapper around the shared Shell
    (UI/Shell/Shell.lua). Which screens exist lives in Shell/Registry
    (Lobby: MainMenu "play", Class, Stats, Talents, Equipment, Wardrobe,
    Inventory, Achievements, Daily Login, Leaderboard, Party/SocialPanel,
    Emotes, Shop, Settings, CharacterCreation); what is open lives in
    Shell/PanelStack; PanelHost mounts NPCDialog / ShopUI / WeaponSmithUI.

    The Lobby-only always-on pieces live in this place's folder, so they
    are required here (shared code can't require them without yielding)
    and handed to the Shell as `extras`:
      • MatchmakingUI     queue status bar (self-manages via events)
      • PartyInviteToast  incoming invite popup (self-manages visibility)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local SharedUI = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI")
local LobbyUI  = script.Parent  -- lobby/StarterPlayerScripts/UI/

local Shell            = require(SharedUI:WaitForChild("Shell"):WaitForChild("Shell"))
local MatchmakingUI    = require(LobbyUI:WaitForChild("MatchmakingUI"))
local PartyInviteToast = require(LobbyUI:WaitForChild("PartyInviteToast"))

local e = React.createElement

local function LobbyApp()
	return e(Shell, {
		place  = "Lobby",
		extras = {
			matchmakingUI    = e(MatchmakingUI),
			partyInviteToast = e(PartyInviteToast),
		},
	})
end

return LobbyApp
