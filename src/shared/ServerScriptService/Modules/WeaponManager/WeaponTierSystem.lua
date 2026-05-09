-- ServerScriptService/Modules/WeaponManager/WeaponTierSystem
--[[
    Tier upgrade system for weapons.
    Thin wrapper around the shared EquipmentTierSystem factory.
]]

local Modules = script.Parent.Parent  -- ServerScriptService/Modules
local WeaponManager = script.Parent   -- ServerScriptService/Modules/WeaponManager

local WeaponConfig     = require(Modules:WaitForChild("WeaponConfig"))
local CreateTierSystem = require(Modules:WaitForChild("EquipmentTierSystem"))

-- Registry and BonusSystem are passed as ModuleScript instances (not required tables)
-- because EquipmentTierSystem calls require() on them internally.
-- BonusSystem lives inside WeaponManager/, not directly under Modules/.
return CreateTierSystem(
    WeaponConfig,
    Modules:WaitForChild("WeaponRegistry"),
    WeaponManager:WaitForChild("WeaponBonusSystem"),
    "weapon"
)