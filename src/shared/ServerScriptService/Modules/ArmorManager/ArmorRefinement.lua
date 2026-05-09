-- ServerScriptService/Modules/ArmorManager/ArmorRefinement
--[[
    Refinement system for armor.
    Thin wrapper around the shared EquipmentRefinement factory.
]]

local Modules = script.Parent.Parent
local ArmorConfig = require(Modules:WaitForChild("ArmorConfig"))
local CreateRefinementSystem = require(Modules:WaitForChild("EquipmentRefinement"))

return CreateRefinementSystem(ArmorConfig, "armor")
