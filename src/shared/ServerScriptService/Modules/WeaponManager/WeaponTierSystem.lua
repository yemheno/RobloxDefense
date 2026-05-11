-- ServerScriptService/Modules/WeaponManager/WeaponTierSystem
--[[
    Tier upgrade system for weapons.
    Thin wrapper around the shared EquipmentTierSystem factory.
    §CFG-D1: tier tables live in GearUpgradeConfig (shared with armor).
]]

local Modules = script.Parent.Parent  -- ServerScriptService/Modules
local WeaponManager = script.Parent   -- ServerScriptService/Modules/WeaponManager

local GearUpgradeConfig = require(Modules:WaitForChild("GearUpgradeConfig"))
local CreateTierSystem  = require(Modules:WaitForChild("EquipmentTierSystem"))

-- Registry and BonusSystem are passed as ModuleScript instances (not
-- required tables) because EquipmentTierSystem calls require() on them
-- internally. BonusSystem lives inside WeaponManager/, not directly
-- under Modules/.
return CreateTierSystem(
    GearUpgradeConfig,
    Modules:WaitForChild("WeaponRegistry"),
    WeaponManager:WaitForChild("WeaponBonusSystem"),
    "weapon"
)
