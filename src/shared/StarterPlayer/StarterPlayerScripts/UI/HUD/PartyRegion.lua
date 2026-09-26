-- UI/HUD/PartyRegion.lua
--[[
    §AGX/UI-P5: mounts TeammateVitals in the HUD's party region (Layout
    L.party, design px) when the HUD has `partyInHud`. The standalone mount
    in CombatApp stays until W2 removes it.
    props: layout (L), visible
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local TeammateVitals = require(script.Parent.Parent:WaitForChild("TeammateVitals"))

local function PartyRegion(props)
	if not props.visible then return nil end
	return React.createElement(TeammateVitals, { rect = props.layout.party })
end

return PartyRegion
