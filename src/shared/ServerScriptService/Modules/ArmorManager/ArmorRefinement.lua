-- ServerScriptService/Modules/ArmorManager/ArmorRefinement
--[[
    Refinement system for armor.
    Thin wrapper around the shared EquipmentRefinement factory.
    §CFG-D1: refinement tables live in GearUpgradeConfig (shared with weapons).
]]

local Modules = script.Parent.Parent
local GearUpgradeConfig = require(Modules:WaitForChild("GearUpgradeConfig"))
local CreateRefinementSystem = require(Modules:WaitForChild("EquipmentRefinement"))

return CreateRefinementSystem(GearUpgradeConfig, "armor")
