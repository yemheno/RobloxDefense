--[[
    UI/App.lua
    Root React component. Acts as the top-level UI container.
    Add child panels here as the UI grows (HUD, menus, shop, upgrades, etc.).
    All network-driven UI is mounted / unmounted from this component.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local NetworkManager    = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("NetworkManager"))
local CharacterCreation = require(script.Parent:WaitForChild("CharacterCreation"))

local function App()
	local showCharCreate, setShowCharCreate = React.useState(false)

	-- Listen for the server requesting character creation
	React.useEffect(function()
		local conn = NetworkManager.OnServerEvent("CharacterCreationRequired", function()
			setShowCharCreate(true)
		end)
		return function()
			if conn then conn:Disconnect() end
		end
	end, {})

	-- Root frame fills the whole screen with no background.
	-- Individual panel components are nested here as the game grows.
	return React.createElement("Frame", {
		Name                = "AppRoot",
		Size                = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		characterCreation = showCharCreate
			and React.createElement(CharacterCreation, {
				onDismiss = function()
					setShowCharCreate(false)
				end,
			})
			or nil,
	})
end

return App
