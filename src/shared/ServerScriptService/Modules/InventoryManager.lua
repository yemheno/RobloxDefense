-- ServerScriptService/Modules/InventoryManager.lua
--[[
    Server-authoritative inventory system.

    Manages player inventories: accessories, consumables, and tokens.
    
    Data lives in data.Account.Inventory  = { { itemId, quantity, metadata? }, ... }
    Equipped accessories live in data.Account.TrinketId / Ring1Id / Ring2Id

    Network events:
      Client → Server    "GetInventory"        → triggers InventoryUpdate
      Client → Server    "EquipAccessory"      → { itemId, slot }
      Client → Server    "UnequipAccessory"    → { slot }
      Server → Client    "InventoryUpdate"     → { items = {...}, equipped = {...} }

    Public API (for other server modules):
      InventoryManager.Init()
      InventoryManager.AddItem(player, itemId, quantity)
      InventoryManager.ConsumeItem(player, itemId, quantity) → bool
      InventoryManager.HasItem(player, itemId, minQty) → bool
      InventoryManager.GetItemCount(player, itemId) → number
      InventoryManager.EquipAccessory(player, itemId, slot) → bool, string
      InventoryManager.UnequipAccessory(player, slot) → bool
      InventoryManager.SendInventory(player)

    Auto-conversion:
      Every 4 respec_fragment items auto-combine into 1 respec_scroll at the
      inventory layer. Triggered inside AddItem after the quantity update,
      before SendInventory fires.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryManager = {}
local Modules = script.Parent

-- Lazily loaded
local NetworkManager    = nil
local PlayerDataManager = nil
local BonusManager      = nil
local AccessoryConfig   = nil

local function getNet()
    if not NetworkManager then
        NetworkManager = require(Modules:WaitForChild("NetworkManager"))
    end
    return NetworkManager
end

local function getDataManager()
    if not PlayerDataManager then
        PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
    end
    return PlayerDataManager
end

local function getBonusManager()
    if not BonusManager then
        BonusManager = require(Modules:WaitForChild("BonusManager"))
    end
    return BonusManager
end

local function getAccessoryConfig()
    if not AccessoryConfig then
        AccessoryConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AccessoryConfig"))
    end
    return AccessoryConfig
end

-- Valid equip slots for accessories
local EQUIP_SLOTS = {
    Trinket = "TrinketId",
    Ring1   = "Ring1Id",
    Ring2   = "Ring2Id",
}

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

local function getInventory(player)
    local dm   = getDataManager()
    local data = dm.GetData(player)
    if not data or not data.Account then return nil end
    if not data.Account.Inventory then
        data.Account.Inventory = {}
    end
    return data.Account.Inventory
end

--- Find index of an item in the inventory array by itemId.
local function findItem(inventory, itemId)
    for i, entry in ipairs(inventory) do
        if entry.itemId == itemId then
            return i, entry
        end
    end
    return nil, nil
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function InventoryManager.Init()
    local net = getNet()

    net.GetEvent("GetInventory")
    net.GetEvent("EquipAccessory")
    net.GetEvent("UnequipAccessory")
    net.GetEvent("InventoryUpdate")

    -- Client requests full inventory
    net.OnClientEvent("GetInventory", function(player)
        InventoryManager.SendInventory(player)
    end)

    -- Client equips an accessory
    net.OnClientEvent("EquipAccessory", function(player, itemId, slot)
        if type(itemId) ~= "string" or type(slot) ~= "string" then return end
        local ok, msg = InventoryManager.EquipAccessory(player, itemId, slot)
        if not ok then
            warn("[InventoryManager] EquipAccessory failed for", player.Name, ":", msg)
        end
        InventoryManager.SendInventory(player)
    end)

    -- Client unequips an accessory
    net.OnClientEvent("UnequipAccessory", function(player, slot)
        if type(slot) ~= "string" then return end
        InventoryManager.UnequipAccessory(player, slot)
        InventoryManager.SendInventory(player)
    end)

    print("[InventoryManager] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- ITEM MANAGEMENT
-- ═══════════════════════════════════════════════════════════

--- Auto-convert 4 respec_fragments → 1 respec_scroll.
--- Does NOT call SendInventory itself; the caller is responsible for that.
local function tryAutoConvert(player)
    local inv = getInventory(player)
    if not inv then return end
    while true do
        local _, frag = findItem(inv, "respec_fragment")
        if not frag or frag.quantity < 4 then break end
        frag.quantity = frag.quantity - 4
        if frag.quantity <= 0 then
            -- Remove empty stack
            for i = #inv, 1, -1 do
                if inv[i] == frag then
                    table.remove(inv, i)
                    break
                end
            end
        end
        local _, scroll = findItem(inv, "respec_scroll")
        if scroll then
            scroll.quantity = scroll.quantity + 1
        else
            table.insert(inv, { itemId = "respec_scroll", quantity = 1 })
        end
    end
end

--- Add quantity of an item to the player's inventory.
---
--- §2.5a: AddItem intentionally does NOT enforce ConsumableConfig.maxStack.
--- maxStack is a *display* hint for the client UI (slot rendering, shop
--- previews); the server collapses every item id into a single inventory
--- entry with an unbounded `quantity` field. This is what lets the respec
--- fragment hoarding work and what makes merit/shop awards never fail due
--- to stack limits. If we ever want a real per-slot cap, it has to be
--- implemented here, not at the config level.
---
--- §2.5b: quantity is not validated for sign or integer-ness. Callers are
--- trusted; a negative quantity will decrement (and can go below zero),
--- and a fractional quantity will be preserved verbatim. All in-tree call
--- sites pass positive integers today, but keep this in mind when wiring
--- new systems (loot tables, shop rollbacks, etc.).
function InventoryManager.AddItem(player, itemId, quantity)
    local inv = getInventory(player)
    if not inv then return end
    quantity = quantity or 1

    local _, entry = findItem(inv, itemId)
    if entry then
        entry.quantity = entry.quantity + quantity
    else
        table.insert(inv, { itemId = itemId, quantity = quantity })
    end

    -- Auto-combine fragments → scrolls.
    tryAutoConvert(player)

    -- Replicate to client once per AddItem call (handles the auto-convert too).
    InventoryManager.SendInventory(player)
end

--- Consume (decrement) quantity of an item. Returns true on success, false
--- if the player doesn't have enough.
---
--- §2.5b: like AddItem, quantity is not sign-checked. A negative quantity
--- would pass the `entry.quantity < quantity` check (since any number is
--- >= a negative) and effectively *add* inventory. All known callers pass
--- positive integers; add a guard here if that ever changes.
function InventoryManager.ConsumeItem(player, itemId, quantity)
    local inv = getInventory(player)
    if not inv then return false end
    quantity = quantity or 1

    local idx, entry = findItem(inv, itemId)
    if not entry or entry.quantity < quantity then return false end

    entry.quantity = entry.quantity - quantity
    if entry.quantity <= 0 then
        table.remove(inv, idx)
    end

    InventoryManager.SendInventory(player)
    return true
end

--- Check if the player has at least minQty of an item.
function InventoryManager.HasItem(player, itemId, minQty)
    local inv = getInventory(player)
    if not inv then return false end
    minQty = minQty or 1

    local _, entry = findItem(inv, itemId)
    return entry ~= nil and entry.quantity >= minQty
end

--- Get the quantity of an item the player owns.
function InventoryManager.GetItemCount(player, itemId)
    local inv = getInventory(player)
    if not inv then return 0 end

    local _, entry = findItem(inv, itemId)
    return entry and entry.quantity or 0
end

-- ═══════════════════════════════════════════════════════════
-- ACCESSORY EQUIP / UNEQUIP
-- ═══════════════════════════════════════════════════════════

--- Equip an accessory to a slot. The item must be in inventory.
--- slot: "Trinket" | "Ring1" | "Ring2"
function InventoryManager.EquipAccessory(player, itemId, slot: string)
    local dataKey = EQUIP_SLOTS[slot]
    if not dataKey then return false, "Invalid slot: " .. tostring(slot) end

    -- Verify item exists in inventory
    if not InventoryManager.HasItem(player, itemId) then
        return false, "Item not in inventory"
    end

    -- Verify item is a valid accessory and matches the slot type
    local cfg = getAccessoryConfig()
    local accDef = cfg.GetById(itemId)
    if not accDef then return false, "Unknown accessory: " .. tostring(itemId) end

    -- Slot validation: Trinket → Trinket slot, Ring → Ring1 or Ring2
    if accDef.slot == "Trinket" then
        if slot ~= "Trinket" then
            return false, "Trinket can only go in Trinket slot"
        end
    elseif accDef.slot == "Ring" then
        if slot ~= "Ring1" and slot ~= "Ring2" then
            return false, "Ring can only go in Ring1 or Ring2"
        end
    end

    -- Can't equip the same ring in both slots
    local dm   = getDataManager()
    local data = dm.GetData(player)
    if not data then return false, "No player data" end

    if accDef.slot == "Ring" then
        local otherSlot = (slot == "Ring1") and "Ring2Id" or "Ring1Id"
        if data.Account[otherSlot] == itemId then
            return false, "Already equipped in other ring slot"
        end
    end

    -- §2.5c: pcall the bonus swap with rollback. If Apply fails after we've
    -- already removed the previous accessory's bonuses, the player ends up
    -- with neither active, which is a silent balance bug. Rollback restores
    -- the prior equipped item and its bonuses on any error.
    local currentId = data.Account[dataKey]
    local removedOk = true
    if currentId then
        local ok, err = pcall(InventoryManager.RemoveAccessoryBonuses, player, currentId, slot)
        if not ok then
            warn("[InventoryManager] EquipAccessory: RemoveAccessoryBonuses failed for " ..
                tostring(currentId) .. " in " .. tostring(slot) .. ": " .. tostring(err))
            removedOk = false
        end
    end
    if not removedOk then
        return false, "Internal error removing previous accessory bonuses"
    end

    -- Tentatively set equipment, then apply bonuses.
    data.Account[dataKey] = itemId
    local okApply, errApply = pcall(InventoryManager.ApplyAccessoryBonuses, player, itemId, slot)
    if not okApply then
        warn("[InventoryManager] EquipAccessory: ApplyAccessoryBonuses failed for " ..
            tostring(itemId) .. " in " .. tostring(slot) .. ": " .. tostring(errApply) ..
            " — rolling back to previous item.")
        data.Account[dataKey] = currentId  -- restore prior equip
        if currentId then
            -- Best-effort re-apply of the prior bonuses so the player isn't
            -- left with nothing in this slot.
            pcall(InventoryManager.ApplyAccessoryBonuses, player, currentId, slot)
        end
        return false, "Failed to apply accessory bonuses"
    end

    return true, "OK"
end

--- Unequip the accessory in the given slot.
function InventoryManager.UnequipAccessory(player, slot)
    local dataKey = EQUIP_SLOTS[slot]
    if not dataKey then return false end

    local dm   = getDataManager()
    local data = dm.GetData(player)
    if not data then return false end

    local currentId = data.Account[dataKey]
    if not currentId then return false end

    InventoryManager.RemoveAccessoryBonuses(player, currentId, slot)
    data.Account[dataKey] = nil

    return true
end

-- ═══════════════════════════════════════════════════════════
-- BONUS APPLICATION
-- ═══════════════════════════════════════════════════════════

-- Map equip slot names → BonusManager source names
local SLOT_TO_SOURCE = {
    Trinket = "acc_trinket",
    Ring1   = "acc_ring1",
    Ring2   = "acc_ring2",
}

--- Apply the stat bonuses of an equipped accessory via BonusManager.
function InventoryManager.ApplyAccessoryBonuses(player, itemId, slot)
    local cfg = getAccessoryConfig()
    local accDef = cfg.GetById(itemId)
    if not accDef or not accDef.bonuses then return end

    local bm = getBonusManager()
    local source = SLOT_TO_SOURCE[slot]
    if not source then return end

    local bonuses = {}
    for _, b in ipairs(accDef.bonuses) do
        bonuses[b.stat] = (bonuses[b.stat] or 0) + b.value
    end

    bm.SetSourceBonuses(player, source, bonuses)
end

--- Remove the stat bonuses of an unequipped accessory.
function InventoryManager.RemoveAccessoryBonuses(player, _itemId, slot)
    local bm = getBonusManager()
    local source = SLOT_TO_SOURCE[slot]
    if not source then return end
    bm.ClearSource(player, source)
end

--- Reapply all equipped accessory bonuses (call on player join).
function InventoryManager.SetupPlayer(player)
    local dm   = getDataManager()
    local data = dm.GetData(player)
    if not data then return end

    for slot, dataKey in pairs(EQUIP_SLOTS) do
        local itemId = data.Account[dataKey]
        if itemId then
            InventoryManager.ApplyAccessoryBonuses(player, itemId, slot)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- SEND STATE TO CLIENT
-- ═══════════════════════════════════════════════════════════

function InventoryManager.SendInventory(player)
    local dm   = getDataManager()
    local data = dm.GetData(player)
    if not data then return end

    local inv = data.Account.Inventory or {}

    getNet().FireClient(player, "InventoryUpdate", {
        items = inv,
        equipped = {
            Trinket = data.Account.TrinketId,
            Ring1   = data.Account.Ring1Id,
            Ring2   = data.Account.Ring2Id,
        },
    })
end

return InventoryManager
