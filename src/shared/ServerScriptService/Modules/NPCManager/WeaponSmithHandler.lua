-- ServerScriptService/Modules/NPCManager/WeaponSmithHandler
--[[
    Handles weapon/armor improvement NPC interactions.

    NPC subtypes (set via def.smithType):
      "Refinement"  — weapon/armor refinement attempts
      "TierUpgrade" — weapon/armor tier upgrades
      "BonusReroll" — weapon/armor random bonus rerolling

    Flow:
      1. Player interacts → server sends current equipment info + relevant costs
         via "NPCSmithOpen".
      2. Client displays the appropriate forge UI.
      3. Player picks action → fires NPCResponse { action = "RefineWeapon" | ... }
      4. Server validates, executes, sends result event.
]]

local WeaponSmithHandler = {}

local NPCManager     = nil
local NetworkManager = nil
local WeaponManager  = nil
local ArmorManager   = nil

function WeaponSmithHandler.Init(npcMgr, netMgr)
	NPCManager    = npcMgr
	NetworkManager = netMgr

	local SSS           = game:GetService("ServerScriptService")
	local SharedModules = SSS:WaitForChild("Modules")
	WeaponManager = require(SharedModules:WaitForChild("WeaponManager"))
	ArmorManager  = require(SharedModules:WaitForChild("ArmorManager"))

	-- Create event for smith UI
	NetworkManager.GetEvent("NPCSmithOpen")

end

-- ═══════════════════════════════════════════════════════════
-- BUILD INFO PAYLOAD
-- ═══════════════════════════════════════════════════════════

local function GetSmithInfo(player, smithType)
	local weaponSystems = WeaponManager.GetSystems()
	local armorSystems  = ArmorManager.GetSystems()

	local info = {
		smithType = smithType,
	}

	-- Weapon instance data
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if weaponInstance then
		local wDef = WeaponManager.GetEquippedWeaponDef(player)
		info.weapon = {
			name       = wDef and wDef.name or weaponInstance.weaponId,
			weaponId   = weaponInstance.weaponId,
			level      = weaponInstance.level,
			refinement = weaponInstance.refinement,
			tier       = weaponInstance.tier,
			bonuses    = weaponInstance.bonuses,
		}
	end

	-- Armor instance data
	local armorInstance = ArmorManager.GetEquippedArmor(player)
	if armorInstance then
		local aDef = ArmorManager.GetEquippedArmorDef(player)
		info.armor = {
			name       = aDef and aDef.name or armorInstance.armorId,
			armorId    = armorInstance.armorId,
			level      = armorInstance.level,
			refinement = armorInstance.refinement,
			tier       = armorInstance.tier,
			bonuses    = armorInstance.bonuses,
		}
	end

	-- Type-specific info
	if smithType == "Refinement" then
		info.weaponRefInfo = weaponSystems.Refinement.GetInfo(player)
		info.armorRefInfo  = armorSystems.Refinement.GetInfo(player)
	elseif smithType == "TierUpgrade" then
		info.weaponTierInfo = weaponSystems.Tier.GetInfo(player)
		info.armorTierInfo  = armorSystems.Tier.GetInfo(player)
	elseif smithType == "BonusReroll" then
		info.weaponRerollInfo = weaponSystems.Bonus.GetRerollInfo(player)
		info.armorRerollInfo  = armorSystems.Bonus.GetRerollInfo(player)
	end

	return info
end

-- ═══════════════════════════════════════════════════════════
-- INTERACTION (player walks up to NPC)
-- ═══════════════════════════════════════════════════════════

function WeaponSmithHandler.OnInteract(player, def)
	local smithType = def.smithType or "Refinement"

	local info = GetSmithInfo(player, smithType)
	info.npcId   = def.id
	info.npcName = def.name

	NetworkManager.FireClient(player, "NPCSmithOpen", info)
	print("[WeaponSmithHandler]", player.Name, "opened", smithType, "smith:", def.name)
end

-- ═══════════════════════════════════════════════════════════
-- RESPONSE (player picked an action)
-- ═══════════════════════════════════════════════════════════

function WeaponSmithHandler.OnResponse(player, def, data)
	if type(data) ~= "table" then return end
	local action = data.action
	if not action then return end

	local weaponSystems = WeaponManager.GetSystems()
	local armorSystems  = ArmorManager.GetSystems()

	if action == "RefineWeapon" then
		weaponSystems.Refinement.Attempt(player)
	elseif action == "RefineArmor" then
		armorSystems.Refinement.Attempt(player)
	elseif action == "TierWeapon" then
		weaponSystems.Tier.Upgrade(player)
	elseif action == "TierArmor" then
		armorSystems.Tier.Upgrade(player)
	elseif action == "RerollWeapon" then
		weaponSystems.Bonus.Reroll(player)
	elseif action == "RerollArmor" then
		armorSystems.Bonus.Reroll(player)
	elseif action == "Refresh" then
		-- Just re-send info
		local smithType = def.smithType or "Refinement"
		local info = GetSmithInfo(player, smithType)
		info.npcId   = def.id
		info.npcName = def.name
		NetworkManager.FireClient(player, "NPCSmithOpen", info)
	elseif action == "Close" then
		-- Nothing to do
	end
end

return WeaponSmithHandler
