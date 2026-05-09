-- ServerScriptService/Modules/CosmeticManager/PlayerCosmeticManager.lua
--[[
    PlayerCosmeticManager
    =====================
    Sub-module of CosmeticManager. Handles all player-specific cosmetic
    operations: wardrobe data, equip/unequip, and visual application to
    R6 characters.

    Visual strategy:
      - Skin color is handled by CharacterManager via BodyColors (not here).
      - Outfit  → recolour + set material on Torso, Arms, Legs.
      - Headgear → recolour + set material on Head.
      - CharacterMesh overlay textures (clothing) come from the template.
        Future outfits will swap MeshId + OverlayTextureId on CharacterMesh.
]]

local PlayerCosmeticManager = {}

-- Dependencies injected via Init()
local NetworkManager    = nil
local PlayerDataManager = nil
local CosmeticConfig    = nil

-- R6 body part names affected by outfits
local OUTFIT_PARTS = { "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function PlayerCosmeticManager.Init(deps)
	NetworkManager    = deps.NetworkManager
	PlayerDataManager = deps.PlayerDataManager
	CosmeticConfig    = deps.CosmeticConfig
	print("[PlayerCosmeticManager] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- DATA LAYER — wardrobe lives inside Account.Wardrobe
-- ═══════════════════════════════════════════════════════════

--- Ensure the player data contains a Wardrobe section with starter items.
function PlayerCosmeticManager.EnsureWardrobeData(player)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.Account then return end

	if not data.Account.Wardrobe then
		data.Account.Wardrobe = {
			owned    = {},
			equipped = { headgear = "none", outfit = nil },
		}
	end

	local wardrobe = data.Account.Wardrobe

	-- Seed ownership from StarterWardrobe
	for _, cosmeticId in ipairs(CosmeticConfig.StarterWardrobe) do
		if not wardrobe.owned[cosmeticId] then
			wardrobe.owned[cosmeticId] = true
		end
	end

	-- If no outfit equipped, apply class default
	if not wardrobe.equipped.outfit then
		local className = PlayerDataManager.GetActiveClass(player)
		local defaults = CosmeticConfig.GetClassDefault(className)
		if defaults then
			wardrobe.equipped.headgear = wardrobe.equipped.headgear or defaults.headgear
			wardrobe.equipped.outfit   = defaults.outfit
		end
	end
end

--- Get the owned cosmetic table { [cosmeticId] = true, ... }.
function PlayerCosmeticManager.GetWardrobe(player)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.Account or not data.Account.Wardrobe then return {} end
	return data.Account.Wardrobe.owned
end

--- Get the equipped table { headgear = "...", outfit = "..." }.
function PlayerCosmeticManager.GetEquipped(player)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.Account or not data.Account.Wardrobe then
		return { headgear = "none", outfit = nil }
	end
	return data.Account.Wardrobe.equipped
end

-- ═══════════════════════════════════════════════════════════
-- EQUIP / UNEQUIP
-- ═══════════════════════════════════════════════════════════

--- Equip a cosmetic from the player's wardrobe.
--- Returns (true) on success or (false, errorString) on failure.
function PlayerCosmeticManager.EquipCosmetic(player, cosmeticId)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.Account or not data.Account.Wardrobe then
		return false, "No wardrobe data"
	end

	local wardrobe = data.Account.Wardrobe

	-- Must own it
	if not wardrobe.owned[cosmeticId] then
		return false, "You don't own this cosmetic"
	end

	-- Get slot
	local slot = CosmeticConfig.GetSlotForCosmetic(cosmeticId)
	if not slot then
		return false, "Unknown cosmetic"
	end

	-- Check class restriction
	local className = PlayerDataManager.GetActiveClass(player)
	if not CosmeticConfig.CanClassWear(cosmeticId, className) then
		return false, "Class restriction: not available for " .. className
	end

	-- Equip
	wardrobe.equipped[slot] = cosmeticId
	print("[PlayerCosmeticManager]", player.Name, "equipped", cosmeticId, "in slot", slot)

	-- Re-apply visuals
	PlayerCosmeticManager.ApplyVisuals(player)

	return true
end

--- Unequip a slot (set to default for that slot type).
function PlayerCosmeticManager.UnequipCosmetic(player, slot)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.Account or not data.Account.Wardrobe then return end

	local wardrobe = data.Account.Wardrobe

	if slot == CosmeticConfig.Slots.HEADGEAR then
		wardrobe.equipped.headgear = "none"
	elseif slot == CosmeticConfig.Slots.OUTFIT then
		-- Revert to class default
		local className = PlayerDataManager.GetActiveClass(player)
		local defaults = CosmeticConfig.GetClassDefault(className)
		wardrobe.equipped.outfit = defaults and defaults.outfit or nil
	end

	PlayerCosmeticManager.ApplyVisuals(player)
end

--- Unlock a cosmetic (add to owned).
function PlayerCosmeticManager.UnlockCosmetic(player, cosmeticId)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.Account or not data.Account.Wardrobe then return false end

	if CosmeticConfig.GetCosmetic(cosmeticId) == nil then
		return false
	end

	data.Account.Wardrobe.owned[cosmeticId] = true
	print("[PlayerCosmeticManager]", player.Name, "unlocked cosmetic:", cosmeticId)
	return true
end

--- Check ownership.
function PlayerCosmeticManager.HasCosmetic(player, cosmeticId)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.Account or not data.Account.Wardrobe then return false end
	return data.Account.Wardrobe.owned[cosmeticId] == true
end

-- ═══════════════════════════════════════════════════════════
-- CLASS SWITCH HANDLING
-- ═══════════════════════════════════════════════════════════

--- When the player switches class, check if current cosmetics are still compatible.
function PlayerCosmeticManager.OnClassSwitched(player, newClassName)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.Account or not data.Account.Wardrobe then return end

	local wardrobe = data.Account.Wardrobe
	local defaults = CosmeticConfig.GetClassDefault(newClassName)

	-- Check headgear
	local headgearId = wardrobe.equipped.headgear
	if headgearId and headgearId ~= "none" then
		if not CosmeticConfig.CanClassWear(headgearId, newClassName) then
			wardrobe.equipped.headgear = (defaults and defaults.headgear) or "none"
		end
	end

	-- Check outfit
	local outfitId = wardrobe.equipped.outfit
	if outfitId then
		if not CosmeticConfig.CanClassWear(outfitId, newClassName) then
			wardrobe.equipped.outfit = defaults and defaults.outfit or nil
		end
	else
		-- No outfit? Apply class default
		wardrobe.equipped.outfit = defaults and defaults.outfit or nil
	end
end

-- ═══════════════════════════════════════════════════════════
-- VISUAL APPLICATION
-- ═══════════════════════════════════════════════════════════

--- Apply all cosmetic visuals to the player's current character.
function PlayerCosmeticManager.ApplyVisuals(player)
	local character = player.Character
	if not character then return end

	local equipped = PlayerCosmeticManager.GetEquipped(player)

	-- Skin color is applied by CharacterManager (BodyColors) — not here.

	-- Apply headgear
	PlayerCosmeticManager.ApplyHeadgearVisual(character, equipped.headgear)

	-- Apply outfit
	PlayerCosmeticManager.ApplyOutfitVisual(character, equipped.outfit)
end

--- Apply headgear visual to a character.
function PlayerCosmeticManager.ApplyHeadgearVisual(character, headgearId)
	if not headgearId or headgearId == "none" then return end

	local cosmetic = CosmeticConfig.GetHeadgear(headgearId)
	if not cosmetic or not cosmetic.visual then return end

	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end

	local visual = cosmetic.visual

	if visual.type == "color" then
		if visual.headColor then
			head.Color = visual.headColor
		end
		if visual.headMaterial then
			head.Material = visual.headMaterial
		end
	elseif visual.type == "model" then
		-- Future: attach a cloned model to the head
		-- local template = HeadgearModelsFolder:FindFirstChild(cosmetic.modelId)
		-- clone, weld to head, etc.
	end
end

--- Apply outfit visual to a character.
function PlayerCosmeticManager.ApplyOutfitVisual(character, outfitId)
	if not outfitId then return end

	local cosmetic = CosmeticConfig.GetOutfit(outfitId)
	if not cosmetic or not cosmetic.visual then return end

	local visual = cosmetic.visual

	if visual.type == "color" then
		for partName, config in pairs(visual.parts) do
			local part = character:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				if config.color then
					part.Color = config.color
				end
				if config.material then
					part.Material = config.material
				end
			end
		end
	elseif visual.type == "model" then
		-- Future: replace body parts with model clones
		-- 1. Remove existing Shirt/Pants if any
		-- 2. Clone template model parts
		-- 3. Weld/parent to character
	end
end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════

function PlayerCosmeticManager.CleanupPlayer(_player)
	-- Currently nothing to clean up in memory; wardrobe is in PlayerData
end

return PlayerCosmeticManager
