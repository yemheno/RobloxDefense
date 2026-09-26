-- ServerScriptService/Modules/ShopManager.lua
--[[
    Server-authoritative shop system.

    Handles purchases from the 3-tab shop (Cosmetics, Consumables, Premium).
    Validates currency, level requirements, and grants items.

    Network events:
      Client → Server    "ShopPurchase"    → { tab, itemId, quantity? }
      Client → Server    "GetShopState"    → triggers ShopState
      Server → Client    "ShopResult"      → { ok, message, itemId }
      Server → Client    "ShopState"       → { merits, essence, level, owned,
                                               rotation, refresh }  (§AGX/D7)
      Client → Server    "ShopRefresh"     → { tab, period, roll }  (§AGX/D7)
                                             reply: NotifyService.Inline("ShopRefresh")
                                             + a fresh ShopState

    Public API:
      ShopManager.Init()
      ShopManager.PurchaseCosmetic(player, itemId) → bool, string
      ShopManager.PurchaseConsumable(player, itemId, qty) → bool, string
      ShopManager.PurchasePremium(player, itemId) → bool, string  (§AGX/X40: opens the Robux dialog)
      ShopManager.GetRotationInfo(player, tab) → { items, endsIn, period, roll, canRefresh }?  (§AGX/D7)
      ShopManager.IsInRotation(player, entryOrItemId) → bool, string?  (§AGX/D7)
      ShopManager.RefreshRotation(player, tab, expect) → bool, string  (§AGX/D7)
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

-- §AGX/D7: NotifyService for the ShopRefresh inline reply. Optional
-- (false = not in this Place / failed to load): the refresh still works.
local NotifyService = nil
local function getNotify()
    if NotifyService == nil then
        local mod = Modules:FindFirstChild("NotifyService")
        local ok, m = false, nil
        if mod then ok, m = pcall(require, mod) end
        NotifyService = ok and m or false
    end
    return NotifyService or nil
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
-- §AGX/D7: ROTATION  (§DISC/D7, BALANCE_NUMBERS.md#shop-rotation-and-paid-refresh)
-- ═══════════════════════════════════════════════════════════
-- A rotating tab's stock is a pure function of
--   (UserId, tab, periodIndex, roll)
-- where periodIndex = floor(os.time() / period) (UTC-epoch aligned, so all
-- servers agree) and `roll` is how many paid refreshes this tab had in this
-- period. Only `roll` + the daily refresh counter are stored
-- (Account.ShopRotation); the rotation itself needs no DataStore write and
-- can't be re-rolled by rejoining or hopping servers. The draw runs here
-- only (server), never on the client.

local TWO32   = 4294967296
local DAY     = 86400
local MAX_ROLL = 16        -- recursion bound; the daily cap keeps real rolls ≤ 3
local MAX_REDRAW = 8       -- tries to make a paid re-roll differ from the last set

-- §AGX/D7: FNV-1a 32-bit. 16777619 = 2^24 + 403, split so no product
-- exceeds 2^53 (doubles stay exact).
local function fnv1a(str)
    local h = 2166136261
    for i = 1, #str do
        h = bit32.bxor(h, string.byte(str, i))
        h = (bit32.lshift(h, 24) + h * 403) % TWO32
    end
    return h
end

-- §AGX/D7: xorshift32 step → new state, float in [0, 1). Own PRNG (not
-- Random.new) so the sequence can never change under an engine update.
local function nextRand(x)
    x = bit32.bxor(x, bit32.lshift(x, 13))
    x = bit32.bxor(x, bit32.rshift(x, 17))
    x = bit32.bxor(x, bit32.lshift(x, 5))
    return x, x / TWO32
end

-- One deterministic draw of `slots` itemIds from the tab's pool.
-- Returns (ordered list, set).
local function drawSet(tab, userId, periodIdx, roll, attempt)
    local shopCfg = getShopConfig()
    local cfg  = shopCfg.GetRotation(tab)
    local pool = shopCfg.GetRotationPool(tab)
    local n    = #pool
    local slots = math.min(cfg and cfg.slots or 0, n)

    local ids = table.create(n)
    for i, entry in ipairs(pool) do ids[i] = entry.itemId end

    local state = fnv1a(string.format("D7|%d|%s|%d|%d|%d", userId, tab, periodIdx, roll, attempt))
    if state == 0 then state = 1 end
    for _ = 1, 4 do state = nextRand(state) end   -- decorrelate close seeds

    local list, set = table.create(slots), {}
    for i = 1, slots do
        local r
        state, r = nextRand(state)
        local j = i + math.floor(r * (n - i + 1))
        ids[i], ids[j] = ids[j], ids[i]
        list[i] = ids[i]
        set[ids[i]] = true
    end
    return list, set
end

local function sameSet(a, b)
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
end

-- The rotation shown for `roll`. A paid re-roll (roll ≥ 1) always shows at
-- least one item the previous roll did not (redraw up to MAX_REDRAW times).
local function rotationFor(tab, userId, periodIdx, roll)
    roll = math.clamp(math.floor(tonumber(roll) or 0), 0, MAX_ROLL)
    local list, set = drawSet(tab, userId, periodIdx, roll, 0)
    if roll == 0 then return list, set end
    local _, prevSet = rotationFor(tab, userId, periodIdx, roll - 1)
    local attempt = 0
    while sameSet(set, prevSet) and attempt < MAX_REDRAW do
        attempt += 1
        list, set = drawSet(tab, userId, periodIdx, roll, attempt)
    end
    return list, set
end

-- Read-only view of Account.ShopRotation (nil-safe; never writes).
local function readRotationState(data)
    local st = data and data.Account and data.Account.ShopRotation
    return type(st) == "table" and st or nil
end

-- Paid re-rolls this tab had in `periodIdx` (0 when none / other period).
local function rollFor(st, tab, periodIdx)
    local r = st and type(st.rolls) == "table" and st.rolls[tab]
    if type(r) == "table" and r.period == periodIdx and type(r.n) == "number" then
        return r.n
    end
    return 0
end

-- Paid refreshes already used on UTC day `day`.
local function refreshesUsed(st, day)
    if st and st.day == day and type(st.refreshes) == "number" then
        return st.refreshes
    end
    return 0
end

--- §AGX/D7: the player's current rotation for a tab, or nil if the tab
--- doesn't rotate. { items = {itemId...}, endsIn = s, period, roll, canRefresh }
function ShopManager.GetRotationInfo(player, tab)
    local shopCfg = getShopConfig()
    local cfg = shopCfg.GetRotation(tab)
    if not cfg then return nil end
    local data = getDataManager().GetData(player)
    local st   = readRotationState(data)
    local now  = os.time()
    local periodIdx = math.floor(now / cfg.period)
    local roll = rollFor(st, tab, periodIdx)
    local list = rotationFor(tab, player.UserId, periodIdx, roll)
    local endsIn = (periodIdx + 1) * cfg.period - now
    return {
        items      = list,
        endsIn     = endsIn,
        period     = periodIdx,
        roll       = roll,
        -- UI hint only; RefreshRotation re-checks everything.
        canRefresh = #shopCfg.GetRotationPool(tab) > cfg.slots
            and endsIn >= shopCfg.Refresh.minRemaining,
    }
end

--- §AGX/D7: server gate — is this entry for sale to this player right now?
--- Staples and non-rotating tabs always are. A rotating item is sold while
--- it is in the current rotation, or in the previous period's rotation for
--- `Refresh.grace` seconds after the flip (a click on the last second).
function ShopManager.IsInRotation(player, entry)
    local shopCfg = getShopConfig()
    if type(entry) == "string" then entry = shopCfg.FindByItemId(entry) end  -- itemId form (NPC ShopHandler)
    if type(entry) ~= "table" then return false, "Unknown item." end
    local cfg = shopCfg.GetRotation(entry.tab)
    if not cfg or entry.staple then return true end

    local data = getDataManager().GetData(player)
    if not data or not data.Account then return false, "Player data not loaded." end
    local st  = readRotationState(data)
    local now = os.time()
    local periodIdx = math.floor(now / cfg.period)

    local _, set = rotationFor(entry.tab, player.UserId, periodIdx, rollFor(st, entry.tab, periodIdx))
    if set[entry.itemId] then return true end

    if now - periodIdx * cfg.period < shopCfg.Refresh.grace then
        local prev = periodIdx - 1
        local _, prevSet = rotationFor(entry.tab, player.UserId, prev, rollFor(st, entry.tab, prev))
        if prevSet[entry.itemId] then return true end
    end
    return false, "Not in stock right now. The shop rotated."
end

--- §AGX/D7: paid "Refresh now" for one rotating tab. `expect` = { period,
--- roll } of the rotation the client is looking at: a replayed or
--- double-clicked request doesn't match after the first one lands, so
--- it is refused WITHOUT charging (idempotent). Shares the per-player
--- purchase lock (§Sh2 / EquipmentRefinement attemptLock pattern), so a
--- refresh can't interleave with a purchase. Spend first, then write.
function ShopManager.RefreshRotation(player, tab, expect)
    return withPurchaseLock(player, function()
        local shopCfg = getShopConfig()
        local cfg = shopCfg.GetRotation(tab)
        if not cfg then return false, "This section doesn't rotate." end
        if #shopCfg.GetRotationPool(tab) <= cfg.slots then
            return false, "Everything in this section is already on sale."
        end

        local data = getDataManager().GetData(player)
        if not data or not data.Account then return false, "Player data not loaded." end
        local st = readRotationState(data)

        local now = os.time()
        local periodIdx = math.floor(now / cfg.period)
        local roll = rollFor(st, tab, periodIdx)
        if type(expect) ~= "table" or expect.period ~= periodIdx or expect.roll ~= roll then
            return false, "The shop already changed. Check the new stock."
        end

        local endsIn = (periodIdx + 1) * cfg.period - now
        if endsIn < shopCfg.Refresh.minRemaining then
            return false, "Free rotation in under 5 minutes. Wait for it."
        end

        local day   = math.floor(now / DAY)
        local used  = refreshesUsed(st, day)
        local price = shopCfg.GetRefreshPrice(used)
        if not price then
            return false, "No refreshes left today (resets 00:00 UTC)."
        end
        if not canAfford(player, price, "Essence") then
            return false, "Not enough Essence (" .. price .. " needed)."
        end

        -- Spend BEFORE the write (§Sh1) and check the result.
        if not spendCurrency(player, price, "Essence") then
            return false, "Payment failed."
        end

        -- Build the new state first, then assign in one step, so a throw
        -- can't leave half a write behind before the refund.
        local wrote, writeErr = pcall(function()
            local rolls = {}
            local oldRolls = st and type(st.rolls) == "table" and st.rolls or {}
            for otherTab, r in pairs(oldRolls) do
                -- keep only other tabs' still-current entries (no growth)
                local oc = shopCfg.GetRotation(otherTab)
                if oc and type(r) == "table" and r.period == math.floor(now / oc.period) then
                    rolls[otherTab] = { period = r.period, n = r.n }
                end
            end
            rolls[tab] = { period = periodIdx, n = roll + 1 }
            data.Account.ShopRotation = { day = day, refreshes = used + 1, rolls = rolls }
        end)
        if not wrote then
            warn("[ShopManager] RefreshRotation write failed for", player.Name, "-", writeErr,
                "— refunding", price, "Essence")
            getCurrencyManager().AddEssence(player, price, { raw = true })  -- §AGX/D-FIX: refunds skip earn listeners
            return false, "Internal error — refunded."
        end

        print("[ShopManager]", player.Name, "refreshed", tab, "rotation (#" .. (used + 1) .. " today) for", price, "Essence")
        local left = shopCfg.Refresh.dailyCap - (used + 1)
        return true, "New stock! " .. left .. " refresh" .. (left == 1 and "" or "es") .. " left today."
    end)
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
        -- §AGX/D7: only this player's current rotation is for sale.
        local inStock, stockMsg = ShopManager.IsInRotation(player, entry)
        if not inStock then return false, stockMsg end

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

        -- §Sh1: DEDUCT FIRST, then grant. A spend can fail (e.g. a
        -- concurrent spend racing the same balance); granting first would
        -- hand out free items.
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
        -- §AGX/X10, §AGX/X10b, §AGX/D-FIX2: only consumables with a
        -- server-side use handler (ConsumableEffects, respec_scroll) are
        -- sold. ShopConfig derives `enabled` from ConsumableConfig.usable;
        -- both are checked so a hand-set `enabled = true` on an unusable item
        -- still can't be bought. Covers the global shop AND the NPC
        -- ShopHandler path, which both land here.
        if entry.enabled == false or not getConsumableConfig().IsUsable(itemId) then
            return false, "Coming soon!"
        end
        -- §AGX/D7: staples always pass; rotating buffs only while in stock.
        -- Covers the NPC ShopHandler route too (it lands here).
        local inStock, stockMsg = ShopManager.IsInRotation(player, entry)
        if not inStock then return false, stockMsg end

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

        -- §Sh1: DEDUCT FIRST.
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

    -- §AGX/X40: MonetizationService re-checks enabled, the placeholder id
    -- (0), the no-P2W grant allowlist and per-product "already owned /
    -- unused" rules before prompting.
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

    -- §AGX/D7: per-tab rotation + today's refresh price (nil = cap reached).
    local shopCfg  = getShopConfig()
    local rotation = {}
    for _, tab in ipairs(shopCfg.GetTabNames()) do
        rotation[tab] = ShopManager.GetRotationInfo(player, tab)
    end
    local used = refreshesUsed(readRotationState(data), math.floor(os.time() / DAY))

    getNet().FireClient(player, "ShopState", {
        merits   = cm.GetMerits(player),
        essence  = cm.GetEssence(player),
        level    = data.Account.Level or 1,
        owned    = wardrobe.owned or {},
        rotation = rotation,
        refresh  = {
            used  = used,
            cap   = shopCfg.Refresh.dailyCap,
            price = shopCfg.GetRefreshPrice(used),
        },
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

    -- §AGX/D7: paid rotation refresh. Reply = NotifyService.Inline (the
    -- client's useRequest("ShopRefresh")), then fresh state either way so
    -- a stale client catches up. (§AGX/D-FIX2: declared in NetworkManager's
    -- manifest.) GetEvent creates the remote here regardless.
    net.GetEvent("ShopRefresh")
    net.OnClientEvent("ShopRefresh", function(player, payload)
        if type(payload) ~= "table" or type(payload.tab) ~= "string" then return end
        local ok, msg = ShopManager.RefreshRotation(player, payload.tab, payload)
        local notify = getNotify()
        if notify then notify.Inline(player, "ShopRefresh", ok, msg) end
        ShopManager.SendShopState(player)
    end)

end

return ShopManager
