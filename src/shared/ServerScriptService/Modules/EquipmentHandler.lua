-- ServerScriptService/Modules/EquipmentHandler.lua
--[[
    Handles the "GetEquipmentInfo" client request.
    
    Assembles a combined snapshot of the player's currently equipped
    weapon and armor, then fires "EquipmentInfo" back to the client.
    
    Used by the EquipmentUI shared panel.
]]

local EquipmentHandler = {}

local SSS            = game:GetService("ServerScriptService")
local SharedModules  = SSS:WaitForChild("Modules")

local NetworkManager = nil
local WeaponManager  = nil
local ArmorManager   = nil
local WeaponRegistry = nil
local ArmorRegistry  = nil
local WeaponConfig   = nil
local ArmorConfig    = nil

function EquipmentHandler.Init()
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
	WeaponManager  = require(SharedModules:WaitForChild("WeaponManager"))
	ArmorManager   = require(SharedModules:WaitForChild("ArmorManager"))
	WeaponRegistry = require(SharedModules:WaitForChild("WeaponRegistry"))
	ArmorRegistry  = require(SharedModules:WaitForChild("ArmorRegistry"))
	WeaponConfig   = require(SharedModules:WaitForChild("WeaponConfig"))
	ArmorConfig    = require(SharedModules:WaitForChild("ArmorConfig"))

	-- Create events
	NetworkManager.GetEvent("GetEquipmentInfo")
	NetworkManager.GetEvent("EquipmentInfo")

	-- Listen for requests
	NetworkManager.OnClientEvent("GetEquipmentInfo", function(player)
		local payload = EquipmentHandler.BuildSnapshot(player)
		NetworkManager.FireClient(player, "EquipmentInfo", payload)
	end)

end

function EquipmentHandler.BuildSnapshot(player)
	local payload = { weapon = nil, armor = nil }

	-- ── Weapon snapshot ──────────────────────────────────
	local wInst = WeaponManager.GetEquippedWeapon(player)
	if wInst then
		local wDef = WeaponManager.GetEquippedWeaponDef(player)
		local wStats = WeaponManager.GetCalculatedStats(player)
		local wXP = WeaponManager.GetSystems().XP.GetXPProgress(player)

		payload.weapon = {
			name        = wDef and wDef.name or wInst.weaponId,
			weaponId    = wInst.weaponId,
			level       = wInst.level,
			xp          = wXP and wXP.xp or wInst.xp or 0,
			required    = wXP and wXP.required or 0,
			maxLevel    = wXP and wXP.maxLevel or WeaponConfig.XP_MAX_LEVEL or 50,
			refinement  = wInst.refinement or 0,
			tier        = wInst.tier or 1,
			attack      = wStats and wStats.attack or 0,
			attackSpeed = wDef and wDef.baseAttackSpeed or 1,
			attackShape = wDef and wDef.attackShape or "Cone",
			bonuses     = wInst.bonuses or {},
		}
	end

	-- ── Armor snapshot ───────────────────────────────────
	-- §EH1: armor has NO XP system — `ArmorManager.GetSystems()` only
	-- returns { Refinement, Tier, Bonus } (no `.XP`). Read the level/xp
	-- fields directly off the armor instance; an XP-progress lookup would
	-- index nil and break the GetEquipmentInfo reply.
	local aInst = ArmorManager.GetEquippedArmor(player)
	if aInst then
		local aDef   = ArmorManager.GetEquippedArmorDef(player)
		local aStats = ArmorManager.GetCalculatedStats(player)

		payload.armor = {
			name        = aDef and aDef.name or aInst.armorId,
			armorId     = aInst.armorId,
			level       = aInst.level or 1,
			xp          = aInst.xp or 0,
			required    = 0,                                            -- armor doesn't level up
			maxLevel    = aInst.level or 1,                              -- pin at current level so UI doesn't show a bar
			refinement  = aInst.refinement or 0,
			tier        = aInst.tier or 1,
			defense     = aStats and aStats.defense or 0,
			bonusHealth = aStats and aStats.bonusHealth or 0,
			bonuses     = aInst.bonuses or {},
		}
	end

	return payload
end

return EquipmentHandler
