-- ServerScriptService/Modules/WeaponManager/WeaponRefinement
--[[
    Refinement system for weapons.
    Thin wrapper around the shared EquipmentRefinement factory.
]]

local Modules = script.Parent.Parent
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local CreateRefinementSystem = require(Modules:WaitForChild("EquipmentRefinement"))

return CreateRefinementSystem(WeaponConfig, "weapon")