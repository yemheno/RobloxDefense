-- ServerScriptService/Modules/ArmorManager/ArmorTierSystem
--[[
    Tier upgrade system for armor.
    Thin wrapper around the shared EquipmentTierSystem factory.
]]

local Modules = script.Parent.Parent  -- ServerScriptService/Modules
local ArmorManager = script.Parent   -- ServerScriptService/Modules/ArmorManager

local ArmorConfig      = require(Modules:WaitForChild("ArmorConfig"))
local CreateTierSystem = require(Modules:WaitForChild("EquipmentTierSystem"))

-- Registry and BonusSystem are passed as ModuleScript instances (not required tables)
-- because EquipmentTierSystem calls require() on them internally.
-- BonusSystem lives inside ArmorManager/, not directly under Modules/.
return CreateTierSystem(
    ArmorConfig,
    Modules:WaitForChild("ArmorRegistry"),
    ArmorManager:WaitForChild("ArmorBonusSystem"),
    "armor"
)
