-- socialplaza/StarterPlayerScripts/UI/SocialPlazaApp.lua
--[[
    Root React component for the Social Plaza place.

    Appearance-centric layout — no combat HUD, no matchmaking, no class bars.
    Renders:
      • CharacterCreation  (shared)  — first-login outfit / head / gender wizard
      • WardrobeUI         (shared)  — browse + equip cosmetics at any time
      • EmoteWheel         (local)   — Q to open the radial emote menu
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules = PlayerScripts:WaitForChild("Modules")
local SharedUI      = PlayerScripts:WaitForChild("UI")
local SocialPlazaUI = script.Parent

local NetworkManager    = require(SharedModules:WaitForChild("NetworkManager"))
local CharacterCreation = require(SharedUI:WaitForChild("CharacterCreation"))
local WardrobeUI        = require(SharedUI:WaitForChild("WardrobeUI"))
local EmoteWheel        = require(SocialPlazaUI:WaitForChild("EmoteWheel"))
-- §AGX/UX-01: AppearanceBar existed but was never mounted, so setShowWardrobe
-- was never called with true and the Wardrobe was unreachable in the Plaza.
local AppearanceBar     = require(SocialPlazaUI:WaitForChild("AppearanceBar"))

local function SocialPlazaApp()
	local showCharCreate, setShowCharCreate = React.useState(false)
	local showWardrobe,   setShowWardrobe   = React.useState(false)

	-- Listen for the server requesting character creation (first-time players)
	React.useEffect(function()
		local conn = NetworkManager.OnServerEvent("CharacterCreationRequired", function()
			setShowCharCreate(true)
		end)
		-- Re-request status now the listener is ready — avoids join race condition
		NetworkManager.FireServer("RequestCharacterStatus")
		return function()
			if conn and type(conn.Disconnect) == "function" then
				conn:Disconnect()
			end
		end
	end, {})

	return React.createElement("Frame", {
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		CharacterCreation = showCharCreate and React.createElement(CharacterCreation, {
			onDismiss = function() setShowCharCreate(false) end,
		}),

		WardrobeUI = showWardrobe and React.createElement(WardrobeUI, {
			onClose = function() setShowWardrobe(false) end,
		}),

		-- §AGX/UX-01: Wardrobe entry point (hidden while a panel is open)
		AppearanceBar = not (showWardrobe or showCharCreate) and React.createElement(AppearanceBar, {
			onWardrobeOpen = function() setShowWardrobe(true) end,
		}) or nil,

		-- EmoteWheel manages its own visibility via the Q key
		EmoteWheel = React.createElement(EmoteWheel),
	})
end

return SocialPlazaApp
