-- UI/HUD/PartyRegion.lua
--[[
    §AGX/UI-P5: mounts TeammateVitals in the HUD's party region (Layout
    L.party, design px) when the HUD has `partyInHud`. The standalone mount
    in CombatApp stays until W2 removes it.
    props: layout (L), mounted, visible
    §AGX/UI-FIX: 7 — `mounted` (default: visible) keeps TeammateVitals
    mounted; `visible` only toggles the wrapper's Visible, so a panel opening
    no longer unmounts it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local TeammateVitals = require(script.Parent.Parent:WaitForChild("TeammateVitals"))

local function PartyRegion(props)
	-- §AGX/UI-FIX: 7 — hide, don't unmount.
	local mounted = props.mounted
	if mounted == nil then mounted = props.visible end
	if not mounted then return nil end
	return React.createElement("Frame", {
		Name                   = "PartyRegion",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible                = props.visible == true,
	}, {
		vitals = React.createElement(TeammateVitals, { rect = props.layout.party }),
	})
end

return PartyRegion
