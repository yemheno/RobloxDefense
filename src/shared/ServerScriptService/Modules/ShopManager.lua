-- ServerScriptService/Modules/ShopManager.lua
--[[
    Server-authoritative shop system.

    Handles purchases from the 3-tab shop (Cosmetics, Consumables, Premium).
    Validates currency, level requirements, and grants items.

    Network events:
      Client → Server    "ShopPurchase"    → { tab, itemId, quantity? }
      Client → Server    "GetShopState"    → triggers ShopState
      Server → Client    "ShopResult"      → { ok, message, itemId }
      Server → Client    "ShopState"       → { merits, essence, level, owned }

    Public API:
      ShopManager.Init()
      ShopManager.PurchaseCosmetic(player, itemId) → bool, string
      ShopManager.PurchaseConsumable(player, itemId, qty) → bool, string
      ShopManager.PurchasePremium(player, itemId) → bool, string  (§AGX/X40: opens the Robux dialog)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopManager = {}
local Modules = script.Parent

-- Lazily loaded
local NetworkManager    = nil
local PlayerDataManager = nil
local CurrencyManager   = nil
local InventoryManager  = nil
local ShopConfig        = nil
local CosmeticConfig    = nil
local ConsumableConfig  = nil

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

local function getCurrencyManager()
    if not CurrencyManager then
        CurrencyManager = require(Modules:WaitForChild("CurrencyManager"))
    end
    return CurrencyManager
end

local function getInventoryManager()
    if not InventoryManager then
        InventoryManager = require(Modules:WaitForChild("InventoryManager"))
    end
    return InventoryManager
end

local function getShopConfig()
    if not ShopConfig then
        ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopConfig"))
    end
    return ShopConfig
end

local function getCosmeticConfig()
    if not CosmeticConfig then
        CosmeticConfig = require(Modules:WaitForChild("CosmeticConfig"))
    end
    return CosmeticConfig
end

local function getConsumableConfig()
    if not ConsumableConfig then
        ConsumableConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ConsumableConfig"))
    end
    return ConsumableConfig
end

-- ═══════════════════════════════════════════════════════════
-- VALIDATION
-- ═══════════════════════════════════════════════════════════

local function getPlayerLevel(player)
    local dm   = getDataManager()
    local data = dm.GetData(player)
    if not data or not data.Account then return 1 end
    return data.Account.Level or 1
end

--- Try to spend currency. Returns true on success.
local function spendCurrency(player, amount, currencyName)
    local cm = getCurrencyManager()
    if currencyName == "Merits" then
        return cm.SpendMerits(player, amount)
    elseif currencyName == "Essence" then
        return cm.SpendEssence(player, amount)
    end
    return false
end

--- Check if player can afford.
local function canAfford(player, amount, currencyName)
    local cm = getCurrencyManager()
    if currencyName == "Merits" then
        return cm.CanAffordMerits(player, amount)
    elseif currencyName == "Essence" then
        return cm.CanAffordEssence(player, amount)
    end
    return false
end

-- ═══════════════════════════════════════════════════════════
-- §Sh2/§Sh3: per-player purchase lock so two ShopPurchase packets
-- in the same network frame can't double-grant or double-spend.
-- ═══════════════════════════════════════════════════════════
local purchaseLock = setmetatable({}, { __mode = "k" })

local function withPurchaseLock(player, fn)
    if purchaseLock[player] then
        return false, "Concurrent purchase request"
    end
    purchaseLock[player] = true
    local ok, a, b = pcall(fn)
    purchaseLock[player] = nil
    if not ok then
        warn("[ShopManager] Purchase function errored:", a)
        return false, "Internal error"
    end
    return a, b
end

-- ═══════════════════════════════════════════════════════════
-- COSMETIC PURCHASES
-- ═══════════════════════════════════════════════════════════

function ShopManager.PurchaseCosmetic(player, itemId)
    return withPurchaseLock(player, function()
        local shopCfg = getShopConfig()
        local entry   = shopCfg.FindByItemId(itemId)
        if not entry or entry.tab ~= "Cosmetics" then
            return false, "Item not in cosmetic shop."
        end
        -- §AGX/X34: `enabled = false` is enforced here, not only in the UI.
        if entry.enabled == false then
            return false, "Coming soon!"
        end

        -- Level check
        if entry.levelReq and getPlayerLevel(player) < entry.levelReq then
            return false, "Requires level " .. entry.levelReq .. "."
        end

        -- Already owned?
        local dm   = getDataManager()
        local data = dm.GetData(player)
        if not data or not data.Account then return false, "Player data not loaded." end

        local wardrobe = data.Account.Wardrobe
        if wardrobe and wardrobe.owned and wardrobe.owned[itemId] then
            return false, "Already owned."
        end

        -- Class restriction check
        local cc = getCosmeticConfig()
        local cosmeticDef = cc.GetCosmetic(itemId)
        if cosmeticDef and cosmeticDef.classRestriction then
            local activeClass = data.ActiveClass or "Aegis"
            if cosmeticDef.classRestriction ~= activeClass then
                return false, "Requires " .. cosmeticDef.classRestriction .. " class."
            end
        end

        -- Afford check
        if not canAfford(player, entry.price, entry.currency) then
            return false, "Not enough " .. entry.currency .. "."
        end

        -- §Sh1 fix: DEDUCT FIRST. The previous order granted ownership
        -- before charging, leaving the player free items if SpendMerits
        -- /SpendEssence ever returned false (e.g. concurrent spend in
        -- another shop tab racing the same balance).
        if not spendCurrency(player, entry.price, entry.currency) then
            return false, "Payment failed."
        end

        -- Now grant ownership. The deduct already succeeded; if anything
        -- below this throws, we credit the player to keep things fair.
        local granted, grantErr = pcall(function()
            if not wardrobe then
                data.Account.Wardrobe = { owned = {}, equipped = { headgear = "none", outfit = "none" } }
                wardrobe = data.Account.Wardrobe
            end
            if not wardrobe.owned then wardrobe.owned = {} end
            wardrobe.owned[itemId] = true
        end)
        if not granted then
            warn("[ShopManager] PurchaseCosmetic grant failed for", itemId, "-", grantErr,
                "— refunding", entry.price, entry.currency)
            local cm = getCurrencyManager()
            -- §AGX/X32: refund the exact price; MeritBonus must not multiply it.
            if entry.currency == "Merits" then cm.AddMerits(player, entry.price, { raw = true })
            elseif entry.currency == "Essence" then cm.AddEssence(player, entry.price) end
            return false, "Internal error — refunded."
        end

        print("[ShopManager]", player.Name, "purchased cosmetic:", itemId, "for", entry.price, entry.currency)
        return true, "Purchased!"
    end)
end

-- ═══════════════════════════════════════════════════════════
-- CONSUMABLE PURCHASES
-- ═══════════════════════════════════════════════════════════

function ShopManager.PurchaseConsumable(player, itemId, quantity)
    return withPurchaseLock(player, function()
        quantity = quantity or 1
        if type(quantity) ~= "number" or quantity < 1 or quantity ~= math.floor(quantity) then
            quantity = 1
        end
        quantity = math.min(quantity, 20)  -- cap per-purchase

        local shopCfg = getShopConfig()
        local entry   = shopCfg.FindByItemId(itemId)
        if not entry or entry.tab ~= "Consumables" then
            return false, "Item not in consumable shop."
        end
        -- §AGX/X10: only consumables with a server-side use handler are
        -- sold (today: respec_scroll). ShopConfig derives `enabled` from
        -- ConsumableConfig.usable; both are checked so a hand-set
        -- `enabled = true` on an unusable item still can't be bought. This
        -- covers the global shop AND the NPC ShopHandler path, which both
        -- land here.
        if entry.enabled == false or not getConsumableConfig().IsUsable(itemId) then
            return false, "Coming soon!"
        end

        -- Level check
        if entry.levelReq and getPlayerLevel(player) < entry.levelReq then
            return false, "Requires level " .. entry.levelReq .. "."
        end

        -- Stack limit check
        local consCfg = getConsumableConfig()
        local consDef = consCfg.GetById(itemId)
        if not consDef then return false, "Unknown consumable." end

        local im           = getInventoryManager()
        local currentQty   = im.GetItemCount(player, itemId)
        local maxStack     = consDef.maxStack or 99
        local canBuy       = math.min(quantity, maxStack - currentQty)
        if canBuy <= 0 then
            return false, "Inventory full (max " .. maxStack .. ")."
        end

        local totalCost = entry.price * canBuy

        -- Afford check
        if not canAfford(player, totalCost, entry.currency) then
            return false, "Not enough " .. entry.currency .. "."
        end

        -- §Sh1 fix: DEDUCT FIRST.
        if not spendCurrency(player, totalCost, entry.currency) then
            return false, "Payment failed."
        end

        -- Grant items now. If AddItem throws, refund.
        local granted, grantErr = pcall(im.AddItem, player, itemId, canBuy)
        if not granted then
            warn("[ShopManager] PurchaseConsumable grant failed for", itemId, "-", grantErr,
                "— refunding", totalCost, entry.currency)
            local cm = getCurrencyManager()
            -- §AGX/X32: refund the exact cost; MeritBonus must not multiply it.
            if entry.currency == "Merits" then cm.AddMerits(player, totalCost, { raw = true })
            elseif entry.currency == "Essence" then cm.AddEssence(player, totalCost) end
            return false, "Internal error — refunded."
        end

        print("[ShopManager]", player.Name, "purchased", canBuy, "x", itemId, "for", totalCost, entry.currency)
        return true, "Purchased " .. canBuy .. "x " .. (consDef.name or itemId) .. "!"
    end)
end

-- ═══════════════════════════════════════════════════════════
-- PREMIUM PURCHASES  (§AGX/X40: routed through MonetizationService)
-- ═══════════════════════════════════════════════════════════

-- §AGX/X40: the Robux prompt, receipts and GamePass cache live in
-- MonetizationService. Lazy require: it lazily requires us back.
local MonetizationService = nil
local function getMonetization()
    if not MonetizationService then
        MonetizationService = require(Modules:WaitForChild("MonetizationService"))
    end
    return MonetizationService
end

--- Opens the Roblox purchase dialog for a Premium entry. `true` means the
--- dialog opened, NOT that anything was bought: the grant happens later in
--- MonetizationService's ProcessReceipt (DevProduct) or GamePass handler.
function ShopManager.PurchasePremium(player, itemId)
    local shopCfg = getShopConfig()
    local entry   = shopCfg.FindByItemId(itemId)
    if not entry or entry.tab ~= "Premium" then
        return false, "Item not in premium shop."
    end

    -- §AGX/X34: honour `enabled = false` server-side (the UI hiding it is
    -- not a gate; a client can fire ShopPurchase for any itemId).
    if entry.enabled == false then
        return false, "Coming soon!"
    end

    -- §AGX/X40: was a hard `return false`. MonetizationService re-checks
    -- enabled, the placeholder id (0), the no-P2W grant allowlist and
    -- per-product "already owned / unused" rules before prompting.
    return withPurchaseLock(player, function()
        return getMonetization().PromptPurchase(player, itemId)
    end)
end

-- ═══════════════════════════════════════════════════════════
-- SEND SHOP STATE
-- ═══════════════════════════════════════════════════════════

function ShopManager.SendShopState(player)
    local dm   = getDataManager()
    local data = dm.GetData(player)
    if not data or not data.Account then return end

    local cm = getCurrencyManager()
    local wardrobe = data.Account.Wardrobe or {}

    getNet().FireClient(player, "ShopState", {
        merits  = cm.GetMerits(player),
        essence = cm.GetEssence(player),
        level   = data.Account.Level or 1,
        owned   = wardrobe.owned or {},
    })
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function ShopManager.Init()
    local net = getNet()

    -- §AGX/X40: every Place's Main loads ShopManager, so this sets
    -- ProcessReceipt in all five Places even before a Main loads
    -- MonetizationService itself. Its Init is idempotent. pcall: a broken
    -- monetization module must not take the Merit/Essence shop down.
    local monOk, monErr = pcall(function() getMonetization().Init() end)
    if not monOk then
        warn("[ShopManager] MonetizationService failed to init:", monErr)
    end

    net.GetEvent("ShopPurchase")
    net.GetEvent("GetShopState")
    net.GetEvent("ShopResult")
    net.GetEvent("ShopState")

    net.OnClientEvent("ShopPurchase", function(player, tab, itemId, quantity)
        if type(tab) ~= "string" or type(itemId) ~= "string" then return end

        local ok, msg
        if tab == "Cosmetics" then
            ok, msg = ShopManager.PurchaseCosmetic(player, itemId)
        elseif tab == "Consumables" then
            ok, msg = ShopManager.PurchaseConsumable(player, itemId, quantity)
        elseif tab == "Premium" then
            ok, msg = ShopManager.PurchasePremium(player, itemId)
        else
            ok, msg = false, "Unknown tab."
        end

        net.FireClient(player, "ShopResult", {
            ok      = ok,
            message = msg,
            itemId  = itemId,
        })

        -- Refresh client state after purchase
        if ok then
            ShopManager.SendShopState(player)
        end
    end)

    net.OnClientEvent("GetShopState", function(player)
        ShopManager.SendShopState(player)
    end)

end

return ShopManager
