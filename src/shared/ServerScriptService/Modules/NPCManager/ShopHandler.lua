-- ServerScriptService/Modules/NPCManager/ShopHandler
--[[
    Handles Shop-type NPC interactions.
    
    When a player interacts with a Shop NPC:
      1. Server sends the shop inventory to the client (NPCShopOpen).
      2. Client displays the shop UI.
      3. Player picks an item → fires NPCResponse { action = "Buy", itemId }.
      4. Server validates currency, deducts, grants item, sends confirmation.
]]

local ShopHandler = {}

local NPCManager    = nil
local NetworkManager = nil

-- Cached module references (resolved in Init)
local _ShopManager = nil

function ShopHandler.Init(npcMgr, netMgr)
	NPCManager    = npcMgr
	NetworkManager = netMgr

	local Mods = script.Parent.Parent
	local smMod = Mods:FindFirstChild("ShopManager")
	if smMod then _ShopManager = require(smMod) end

	print("[ShopHandler] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- INTERACTION
-- ═══════════════════════════════════════════════════════════

function ShopHandler.OnInteract(player, def)
	-- Send shop data to client
	local shopData = {
		npcId    = def.id,
		npcName  = def.name,
		items    = def.shopItems or {},
	}

	NetworkManager.FireClient(player, "NPCShopOpen", shopData)
	print("[ShopHandler]", player.Name, "opened shop:", def.name)
end

-- ═══════════════════════════════════════════════════════════
-- RESPONSE (purchase attempt)
-- ═══════════════════════════════════════════════════════════

function ShopHandler.OnResponse(player, def, data)
	if data.action == "Buy" then
		ShopHandler.HandlePurchase(player, def, data.itemId, data.quantity or 1)
	elseif data.action == "Close" then
		-- Client closed shop — nothing to do server-side
	end
end

function ShopHandler.HandlePurchase(player, def, itemId, quantity)
	-- Validate quantity is a positive integer
	if type(quantity) ~= "number" or quantity < 1 or quantity ~= math.floor(quantity) then
		quantity = 1
	end
	quantity = math.min(quantity, 99) -- cap to prevent absurd purchases

	-- Find the item in the NPC shop to verify it's actually stocked
	local item = nil
	for _, shopItem in ipairs(def.shopItems or {}) do
		if shopItem.itemId == itemId then
			item = shopItem
			break
		end
	end

	if not item then
		NetworkManager.FireClient(player, "NPCDialogue", {
			npcId   = def.id,
			type    = "ShopError",
			message = "Item not found.",
		})
		return
	end

	-- Route through the central ShopManager for full validation
	-- (level checks, stack limits, class restrictions, currency, grant).
	-- §NM3: guard against missing ShopManager (place that doesn't load it).
	if not _ShopManager then
		warn("[ShopHandler] ShopManager not loaded in this place — purchase rejected")
		NetworkManager.FireClient(player, "NPCDialogue", {
			npcId   = def.id,
			type    = "ShopError",
			message = "Shop unavailable in this scene.",
		})
		return
	end

	local ok, message
	local tab = item.tab or "Consumables"

	if tab == "Cosmetics" then
		ok, message = _ShopManager.PurchaseCosmetic(player, itemId)
	else
		ok, message = _ShopManager.PurchaseConsumable(player, itemId, quantity)
	end

	if ok then
		NetworkManager.FireClient(player, "NPCDialogue", {
			npcId   = def.id,
			type    = "ShopSuccess",
			message = message or ("Purchased " .. quantity .. "x " .. (item.name or itemId) .. "!"),
			itemId  = itemId,
		})
	else
		NetworkManager.FireClient(player, "NPCDialogue", {
			npcId   = def.id,
			type    = "ShopError",
			message = message or "Purchase failed.",
		})
	end
end

return ShopHandler
