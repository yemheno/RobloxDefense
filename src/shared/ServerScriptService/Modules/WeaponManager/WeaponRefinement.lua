-- ServerScriptService/Modules/WeaponManager/WeaponRefinement
--[[
    Refinement system for weapons.
    Thin wrapper around the shared EquipmentRefinement factory.
    §CFG-D1: refinement tables live in GearUpgradeConfig (shared with armor).
]]

local Modules = script.Parent.Parent
local GearUpgradeConfig = require(Modules:WaitForChild("GearUpgradeConfig"))
local CreateRefinementSystem = require(Modules:WaitForChild("EquipmentRefinement"))

return CreateRefinementSystem(GearUpgradeConfig, "weapon")
