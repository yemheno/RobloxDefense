-- ServerScriptService/Modules/MonetizationService.lua
--[[
    §AGX/X40: the one Robux path for all five Places.

    Pablo's rule (2026-09-26): gameplay currency (Merits, Essence) is never
    sold for Robux, and nothing bought with Robux converts into it or into
    power. Robux buys cosmetics, appearance changes and non-power
    convenience only. This module enforces it:
      • The catalog is ShopConfig.Premium. An entry is registered only if
        its grant.type is in ALLOWED_GRANTS; anything else (Merits,
        Essence, RespecToken, items, …) is refused with a loud warn.
      • A Cosmetics bundle whose items are also sold for Merits/Essence in
        the Cosmetics tab can't be prompted (it would free up currency).

    Owns:
      • MarketplaceService.ProcessReceipt (assign it NOWHERE else — Roblox
        keeps only one callback per server).
      • A GamePass ownership cache (+ PromptGamePassPurchaseFinished).
      • MonetizationService.PromptPurchase(player, itemId): the only way to
        open a Robux prompt (ShopManager.PurchasePremium routes here).

    Receipt idempotency (AGENCY_CHECKS "Receipts checklist"):
      PlayerDataManager has no "update one field inside UpdateAsync" API,
      so the grant and the PurchaseId are written into the in-memory data
      together (no yield in between), then a forced SavePlayer writes both
      in the same UpdateAsync under the §AGX/X3 session lock. We return
      PurchaseGranted only when that save returns "ok"; anything else is
      NotProcessedYet and Roblox re-delivers the receipt. On re-delivery
      the PurchaseId is already in the data, so we only retry the save —
      never a second grant. If the save never lands, the grant and the id
      are lost together and the next delivery grants once.

    Grants are pure data writes. Side effects (opening the appearance
    screen, refreshing the shop, toasts) run only AFTER the save succeeds.

    Saved data (created lazily; not in PlayerDataConfig.AccountDefaults):
      data.Account.Monetization = {
          receipts          = { [PurchaseId] = os.time() },  -- bounded
          receiptOrder      = { PurchaseId, ... },           -- oldest first
          appearanceTokens  = 0,   -- paid appearance changes not yet applied
          robuxSpent        = 0,   -- private; never shown on a leaderboard (X46)
      }
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local MonetizationService = {}
local Modules = script.Parent

-- §AGX/X40: the ONLY grant types Robux may buy. Never add Merits,
-- Essence, items, XP, boosts or anything random here.
local ALLOWED_GRANTS = {
    AppearanceChange = true,
    Cosmetics        = true,
    GamePass         = true,
}

-- §AGX/X40: purchase ids kept per player. Roblox only re-delivers
-- receipts that were never acknowledged, so a bounded history is enough.
local RECEIPT_HISTORY_MAX = 100

-- Lazily loaded (avoid require cycles: ShopManager requires us).
local PlayerDataManager = nil
local ShopConfig        = nil
local CosmeticConfig    = nil
local CharacterManager  = nil
local NotifyService     = nil

local function getDataManager()
    if not PlayerDataManager then
        PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
    end
    return PlayerDataManager
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

local function getCharacterManager()
    if not CharacterManager then
        local mod = Modules:FindFirstChild("CharacterManager")
        if mod then
            local ok, m = pcall(require, mod)
            if ok then CharacterManager = m end
        end
    end
    return CharacterManager
end

local function toast(player, kind, text)
    if NotifyService == nil then
        local mod = Modules:FindFirstChild("NotifyService")
        local ok, m = false, nil
        if mod then ok, m = pcall(require, mod) end
        NotifyService = ok and m or false
    end
    if NotifyService then NotifyService.Toast(player, kind, text) end
end

-- ═══════════════════════════════════════════════════════════
-- CATALOG (built from ShopConfig.Premium at Init)
-- ═══════════════════════════════════════════════════════════

local entriesByItemId  = {}  -- [itemId] = entry  (every valid entry, enabled or not)
local productsById     = {}  -- [devProductId] = entry  (receipts are honoured even if disabled)
local passesById       = {}  -- [gamePassId]   = entry
local blockedFromPrompt = {} -- [itemId] = reason (e.g. overlaps an earn-currency listing)

-- §AGX/X40: cosmetic ids sold for Merits/Essence in the Cosmetics tab.
local function earnCurrencyCosmetics(shopCfg)
    local set = {}
    for _, e in ipairs(shopCfg.Cosmetics or {}) do
        if e.currency == "Merits" or e.currency == "Essence" then
            set[e.itemId] = true
        end
    end
    return set
end

local function buildCatalog()
    local shopCfg = getShopConfig()
    local cc      = getCosmeticConfig()
    local earnSet = earnCurrencyCosmetics(shopCfg)

    for _, entry in ipairs(shopCfg.Premium or {}) do
        local grant = entry.grant
        local gtype = type(grant) == "table" and grant.type or nil
        if not ALLOWED_GRANTS[gtype] then
            -- §AGX/X40 guard: currency packs (or anything else) can't be sold.
            warn(string.format("[MonetizationService] REFUSED Premium entry %q: grant type %q is not allowed for Robux (§AGX/X40 no-P2W rule)",
                tostring(entry.itemId), tostring(gtype)))
            continue
        end
        if gtype == "GamePass" and entry.kind ~= "GamePass" then
            warn("[MonetizationService] REFUSED", entry.itemId, "- GamePass grant needs kind = \"GamePass\"")
            continue
        end
        if gtype ~= "GamePass" and entry.kind ~= "DevProduct" then
            warn("[MonetizationService] REFUSED", entry.itemId, "- needs kind = \"DevProduct\"")
            continue
        end
        if gtype == "Cosmetics" then
            local items = grant.items
            local bad = type(items) ~= "table" or #items == 0
            if not bad then
                for _, id in ipairs(items) do
                    if cc.GetCosmetic(id) == nil then bad = true; break end
                    if earnSet[id] then
                        blockedFromPrompt[entry.itemId] = "cosmetic " .. id .. " is also sold for Merits/Essence"
                    end
                end
            end
            if bad then
                warn("[MonetizationService] REFUSED", entry.itemId, "- unknown or empty cosmetic list")
                continue
            end
        end

        entriesByItemId[entry.itemId] = entry
        if entry.kind == "DevProduct" and type(entry.devProductId) == "number" and entry.devProductId > 0 then
            if productsById[entry.devProductId] then
                warn("[MonetizationService] Duplicate devProductId", entry.devProductId, "on", entry.itemId)
            end
            productsById[entry.devProductId] = entry
        elseif entry.kind == "GamePass" and type(entry.gamePassId) == "number" and entry.gamePassId > 0 then
            passesById[entry.gamePassId] = entry
        end
    end

    for itemId, reason in pairs(blockedFromPrompt) do
        local e = entriesByItemId[itemId]
        if e and e.enabled ~= false then
            warn(string.format("[MonetizationService] %s is enabled but can't be prompted: %s (§AGX/X40)", itemId, reason))
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- SAVED STATE
-- ═══════════════════════════════════════════════════════════

local function getMonetizationData(data)
    local acc = data.Account
    local mon = acc.Monetization
    if type(mon) ~= "table" then
        mon = {}
        acc.Monetization = mon
    end
    if type(mon.receipts) ~= "table" then mon.receipts = {} end
    if type(mon.receiptOrder) ~= "table" then mon.receiptOrder = {} end
    if type(mon.appearanceTokens) ~= "number" then mon.appearanceTokens = 0 end
    if type(mon.robuxSpent) ~= "number" then mon.robuxSpent = 0 end
    return mon
end

local function recordReceipt(mon, purchaseId, robux)
    mon.receipts[purchaseId] = os.time()
    table.insert(mon.receiptOrder, purchaseId)
    while #mon.receiptOrder > RECEIPT_HISTORY_MAX do
        local oldest = table.remove(mon.receiptOrder, 1)
        mon.receipts[oldest] = nil
    end
    if type(robux) == "number" and robux > 0 then
        mon.robuxSpent += robux
    end
end

-- ═══════════════════════════════════════════════════════════
-- GRANTS (pure in-memory data writes; must not yield)
-- ═══════════════════════════════════════════════════════════

local GRANTERS = {}

-- One paid change is banked, then applied after the save (see applyBanked).
function GRANTERS.AppearanceChange(_player, data, mon, _grant)
    mon.appearanceTokens += 1
    return true
end

function GRANTERS.Cosmetics(_player, data, _mon, grant)
    local acc = data.Account
    if type(acc.Wardrobe) ~= "table" then
        acc.Wardrobe = { owned = {}, equipped = { headgear = "none", outfit = "none" } }
    end
    if type(acc.Wardrobe.owned) ~= "table" then acc.Wardrobe.owned = {} end
    for _, id in ipairs(grant.items) do
        acc.Wardrobe.owned[id] = true
    end
    return true
end

-- ═══════════════════════════════════════════════════════════
-- POST-SAVE SIDE EFFECTS
-- ═══════════════════════════════════════════════════════════

--- §AGX/X40: turn one banked paid appearance change into the §AGX/X18
--- flag via CharacterManager.GrantAppearanceChange (which also opens the
--- creation screen). Needs a created character and no unused flag.
local function applyBankedAppearance(player)
    local data = getDataManager().GetData(player)
    if not data or not data.Account then return end
    local mon = data.Account.Monetization
    if type(mon) ~= "table" or type(mon.appearanceTokens) ~= "number" or mon.appearanceTokens <= 0 then return end
    local cd = data.Account.CharacterData
    if not cd or not cd.isCreated or cd.appearanceChangeUnlocked then return end
    local cm = getCharacterManager()
    if not cm or type(cm.GrantAppearanceChange) ~= "function" then return end
    -- Decrement first: flag and counter change together in memory and are
    -- saved together by the next save.
    mon.appearanceTokens -= 1
    local ok, granted = pcall(cm.GrantAppearanceChange, player, "robux:premium_appearance_change")
    if not ok or not granted then
        mon.appearanceTokens += 1
    end
end

local function afterGranted(player, entry)
    local gtype = entry.grant.type
    if gtype == "AppearanceChange" then
        applyBankedAppearance(player)
    elseif gtype == "Cosmetics" then
        -- Refresh the shop's owned list (lazy require: ShopManager requires us).
        local mod = Modules:FindFirstChild("ShopManager")
        if mod then
            local ok, sm = pcall(require, mod)
            if ok and sm and sm.SendShopState then pcall(sm.SendShopState, player) end
        end
    end
    toast(player, "success", "Thank you! " .. tostring(entry.name or entry.itemId) .. " unlocked.")
end

-- ═══════════════════════════════════════════════════════════
-- PROCESS RECEIPT
-- ═══════════════════════════════════════════════════════════

local grantedThisSession = {}  -- [PurchaseId] = true once PurchaseGranted was returned

local function processReceipt(receipt)
    local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
    local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted

    local purchaseId = tostring(receipt.PurchaseId)
    if grantedThisSession[purchaseId] then return GRANTED end

    -- The buyer must be in THIS server with loaded data; otherwise Roblox
    -- re-delivers on their next join (in whichever Place that is).
    local player = Players:GetPlayerByUserId(receipt.PlayerId)
    if not player then return NOT_YET end
    local dm = getDataManager()
    local data = dm.GetData(player)
    if not data or type(data.Account) ~= "table" then return NOT_YET end

    local mon = getMonetizationData(data)
    local entry = productsById[receipt.ProductId]
    local isNew = mon.receipts[purchaseId] == nil

    if isNew then
        if not entry then
            warn("[MonetizationService] Receipt for unknown/refused product", receipt.ProductId,
                "from", player.Name, "- left unprocessed")
            return NOT_YET
        end
        local granter = GRANTERS[entry.grant.type]
        if not granter then return NOT_YET end
        -- Grant + record in one synchronous block (no yield between them).
        local ok, res = pcall(granter, player, data, mon, entry.grant)
        if not ok or res ~= true then
            warn("[MonetizationService] Grant failed for", entry.itemId, player.Name, ok and "" or res)
            return NOT_YET
        end
        recordReceipt(mon, purchaseId, receipt.CurrencySpent)
    end

    -- Persist grant + PurchaseId in one UpdateAsync (§AGX/X3 lock).
    local status = dm.SavePlayer(player, true)
    if status ~= "ok" then
        warn("[MonetizationService] Save after receipt", purchaseId, "returned", tostring(status),
            "- NotProcessedYet (Roblox will retry)")
        return NOT_YET
    end

    -- A re-delivery can race this call through the save; only the first
    -- one to finish runs the side effects.
    local first = not grantedThisSession[purchaseId]
    grantedThisSession[purchaseId] = true
    print("[MonetizationService]", player.Name, "purchase", purchaseId,
        entry and entry.itemId or ("product " .. tostring(receipt.ProductId)),
        isNew and "granted" or "re-acknowledged")
    if entry and first then
        task.spawn(afterGranted, player, entry)
    end
    return GRANTED
end

-- ═══════════════════════════════════════════════════════════
-- GAMEPASS OWNERSHIP CACHE
-- ═══════════════════════════════════════════════════════════

local passCache = {}  -- [userId] = { [gamePassId] = boolean }

local function applyPassPerks(player, entry)
    local attr = entry.grant.attribute
    if type(attr) == "string" and attr ~= "" then
        player:SetAttribute(attr, true)
    end
end

--- Cached ownership check. Yields on the first call per (player, pass).
function MonetizationService.OwnsPass(player, itemId)
    local entry = entriesByItemId[itemId]
    if not entry or entry.kind ~= "GamePass" then return false end
    local passId = entry.gamePassId
    if type(passId) ~= "number" or passId <= 0 then return false end
    local userCache = passCache[player.UserId]
    if not userCache then
        userCache = {}
        passCache[player.UserId] = userCache
    end
    if userCache[passId] == nil then
        local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
        if not ok then return false end  -- don't cache an API failure
        if player.Parent == nil then return owns == true end
        userCache[passId] = owns == true
    end
    return userCache[passId]
end

local function refreshPasses(player)
    for _, entry in pairs(passesById) do
        if MonetizationService.OwnsPass(player, entry.itemId) then
            applyPassPerks(player, entry)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- PROMPT HOOK
-- ═══════════════════════════════════════════════════════════

local promptOpen = {}  -- [player] = os.clock() when a prompt was opened
local PROMPT_REOPEN_AFTER = 30  -- s; safety valve if a Finished event is lost

--- Per-product checks that keep a player from paying for nothing.
local function canBuy(player, entry)
    local data = getDataManager().GetData(player)
    if not data or type(data.Account) ~= "table" then return false, "Player data not loaded." end
    local gtype = entry.grant.type
    if gtype == "AppearanceChange" then
        local cd = data.Account.CharacterData
        if not cd or not cd.isCreated then return false, "Create your character first." end
        local mon = data.Account.Monetization
        local banked = type(mon) == "table" and type(mon.appearanceTokens) == "number" and mon.appearanceTokens > 0
        if cd.appearanceChangeUnlocked or banked then
            return false, "You already have an unused appearance change."
        end
    elseif gtype == "Cosmetics" then
        local owned = data.Account.Wardrobe and data.Account.Wardrobe.owned or {}
        local missing = false
        for _, id in ipairs(entry.grant.items) do
            if not owned[id] then missing = true; break end
        end
        if not missing then return false, "Already owned." end
    elseif gtype == "GamePass" then
        if MonetizationService.OwnsPass(player, entry.itemId) then return false, "Already owned." end
    end
    return true
end

--- §AGX/X40: open the Roblox purchase dialog for a Premium entry.
--- Returns (true, message) when the dialog was opened, else (false, reason).
function MonetizationService.PromptPurchase(player, itemId)
    local entry = entriesByItemId[itemId]
    if not entry then return false, "Not available." end
    if entry.enabled == false then return false, "Coming soon!" end  -- §AGX/X34
    if blockedFromPrompt[itemId] then return false, "Coming soon!" end
    local id = if entry.kind == "GamePass" then entry.gamePassId else entry.devProductId
    if type(id) ~= "number" or id <= 0 then return false, "Coming soon!" end

    local opened = promptOpen[player]
    if opened and os.clock() - opened < PROMPT_REOPEN_AFTER then
        return false, "A purchase window is already open."
    end

    local ok, reason = canBuy(player, entry)
    if not ok then return false, reason end

    promptOpen[player] = os.clock()
    local pOk, err = pcall(function()
        if entry.kind == "GamePass" then
            MarketplaceService:PromptGamePassPurchase(player, id)
        else
            MarketplaceService:PromptProductPurchase(player, id)
        end
    end)
    if not pOk then
        promptOpen[player] = nil
        warn("[MonetizationService] Prompt failed for", itemId, err)
        return false, "Store unavailable, try again."
    end
    return true, "Opening purchase…"
end

function MonetizationService.GetEntry(itemId)
    return entriesByItemId[itemId]
end

-- ═══════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════

local initialized = false

local function onDataReady(player)
    -- Idempotent (PlayerDataManager contract).
    applyBankedAppearance(player)
    refreshPasses(player)
end

function MonetizationService.Init()
    -- §AGX/X40: idempotent — ShopManager.Init bootstraps it in every Place,
    -- and a Main may also ctx.Load it.
    if initialized then return end
    initialized = true

    buildCatalog()

    MarketplaceService.ProcessReceipt = processReceipt

    MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _productId, _isPurchased)
        local player = Players:GetPlayerByUserId(userId)
        if player then promptOpen[player] = nil end
    end)

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
        promptOpen[player] = nil
        if not wasPurchased then return end
        local entry = passesById[passId]
        if not entry then return end
        local userCache = passCache[player.UserId]
        if not userCache then
            userCache = {}
            passCache[player.UserId] = userCache
        end
        userCache[passId] = true
        applyPassPerks(player, entry)
        toast(player, "success", "Thank you! " .. tostring(entry.name or entry.itemId) .. " unlocked.")
    end)

    local dm = getDataManager()
    dm.OnPlayerDataReady(onDataReady)
    -- Players whose data loaded before we registered (Studio play-solo).
    for _, p in ipairs(Players:GetPlayers()) do
        if dm.GetData(p) then task.spawn(onDataReady, p) end
    end

    Players.PlayerRemoving:Connect(function(player)
        promptOpen[player] = nil
        passCache[player.UserId] = nil
    end)
end

return MonetizationService
