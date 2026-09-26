-- ReplicatedStorage/Shared/ShopConfig.lua
--[[
    Centralized shop catalog for the 3-tab shop system.

    ⚠ §DISC/D7 (Pablo): the CURRENT ITEMS ARE PLACEHOLDERS ("random
    nonsense objects") — don't balance-audit them. The real shop pass
    (curated catalog + rotation timer + paid Essence refresh) is
    tracked in docs/TODO.md §DISC/D7.

    Three tabs:
      Cosmetics    — headgear & outfits (unlocks, not consumable)
      Consumables  — potions, scrolls, buff items (stackable)
      Premium      — Robux items via DevProducts (future implementation)

    Each entry:
      itemId     string   References CosmeticConfig or ConsumableConfig
      tab        string   "Cosmetics" | "Consumables" | "Premium"
      price      number   Cost in currency
      currency   string   "Merits" | "Essence" (or "Robux" for premium)
      levelReq   number?  Minimum player level to purchase (nil = no req)
      enabled    boolean? false = hidden from shop UIs and rejected server-side.
                          §AGX/X10: Consumables derive it from
                          ConsumableConfig.IsUsable at load (see bottom).

    The shop pulls display info (name, desc, icon, rarity) from the
    underlying config module, not duplicated here.
]]

local ShopConfig = {}

-- ═══════════════════════════════════════════════════════════
-- COSMETICS TAB
-- ═══════════════════════════════════════════════════════════
-- References cosmetics defined in CosmeticConfig.lua
-- Only lists items that are purchasable (not starter/default).

ShopConfig.Cosmetics = {
    -- Headgear
    {
        itemId   = "hood_basic",
        tab      = "Cosmetics",
        price    = 200,
        currency = "Merits",
    },
    {
        itemId   = "helm_aegis",
        tab      = "Cosmetics",
        price    = 500,
        currency = "Merits",
        levelReq = 5,
    },
    {
        itemId   = "circlet_arcanist",
        tab      = "Cosmetics",
        price    = 500,
        currency = "Merits",
        levelReq = 5,
    },
    {
        itemId   = "mask_hunter",
        tab      = "Cosmetics",
        price    = 500,
        currency = "Merits",
        levelReq = 5,
    },
    -- Outfits (rare tier = Essence cost)
    {
        itemId   = "dark_knight",
        tab      = "Cosmetics",
        price    = 25,
        currency = "Essence",
        levelReq = 10,
    },
    {
        itemId   = "shadow_robes",
        tab      = "Cosmetics",
        price    = 25,
        currency = "Essence",
        levelReq = 10,
    },
    {
        itemId   = "forest_ranger",
        tab      = "Cosmetics",
        price    = 25,
        currency = "Essence",
        levelReq = 10,
    },
}

-- ═══════════════════════════════════════════════════════════
-- CONSUMABLES TAB
-- ═══════════════════════════════════════════════════════════
-- References consumables defined in ConsumableConfig.lua

ShopConfig.Consumables = {
    -- Cheap healing
    {
        itemId   = "health_potion",
        tab      = "Consumables",
        price    = 25,
        currency = "Merits",
    },
    {
        itemId   = "health_potion_large",
        tab      = "Consumables",
        price    = 100,
        currency = "Merits",
        levelReq = 5,
    },
    {
        itemId   = "health_elixir",
        tab      = "Consumables",
        price    = 5,
        currency = "Essence",
        levelReq = 10,
    },
    -- Resource restorers
    {
        itemId   = "mana_crystal",
        tab      = "Consumables",
        price    = 30,
        currency = "Merits",
    },
    {
        itemId   = "mana_crystal_large",
        tab      = "Consumables",
        price    = 120,
        currency = "Merits",
        levelReq = 5,
    },
    -- Buff items
    {
        itemId   = "power_scroll",
        tab      = "Consumables",
        price    = 150,
        currency = "Merits",
        levelReq = 5,
    },
    {
        itemId   = "iron_skin_potion",
        tab      = "Consumables",
        price    = 150,
        currency = "Merits",
        levelReq = 5,
    },
    {
        itemId   = "swiftness_elixir",
        tab      = "Consumables",
        price    = 100,
        currency = "Merits",
        levelReq = 3,
    },
    {
        itemId   = "fortune_incense",
        tab      = "Consumables",
        price    = 10,
        currency = "Essence",
        levelReq = 8,
    },
    {
        itemId   = "crit_oil",
        tab      = "Consumables",
        price    = 120,
        currency = "Merits",
        levelReq = 5,
    },
    -- Special
    {
        itemId   = "respec_scroll",
        tab      = "Consumables",
        price    = 50,
        currency = "Essence",
        levelReq = 10,
    },
}

-- ═══════════════════════════════════════════════════════════
-- PREMIUM TAB
-- ═══════════════════════════════════════════════════════════
-- Robux items — DevProduct IDs are placeholders (0)
-- until real products are created in the Roblox dashboard.

-- NOTE: set enabled = false on any item to hide it from the shop UI
-- and block purchases server-side until ready to ship.
ShopConfig.Premium = {
    {
        itemId       = "premium_essence_pack",
        tab          = "Premium",
        enabled      = false,
        name         = "Essence Pack (50)",
        desc         = "50 Essence delivered instantly.",
        icon         = "💰",
        price        = 99,   -- Robux
        currency     = "Robux",
        devProductId = 0,    -- placeholder
        grant        = { type = "Essence", amount = 50 },
    },
    {
        itemId       = "premium_merit_pack",
        tab          = "Premium",
        enabled      = false,
        name         = "Merit Bundle (5000)",
        desc         = "5000 Merits delivered instantly.",
        icon         = "🪙",
        price        = 49,
        currency     = "Robux",
        devProductId = 0,
        grant        = { type = "Merits", amount = 5000 },
    },
    {
        itemId       = "premium_respec_pack",
        tab          = "Premium",
        enabled      = false,
        name         = "Respec Token x3",
        desc         = "3 Respec Tokens delivered instantly.",
        icon         = "📋",
        price        = 79,
        currency     = "Robux",
        devProductId = 0,
        grant        = { type = "RespecToken", amount = 3 },
    },
}

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

--- Get a flat table of all shop entries for a given tab.
function ShopConfig.GetTab(tab)
    if tab == "Cosmetics"   then return ShopConfig.Cosmetics end
    if tab == "Consumables" then return ShopConfig.Consumables end
    if tab == "Premium"     then return ShopConfig.Premium end
    return {}
end

--- Find a shop entry by itemId across all tabs.
function ShopConfig.FindByItemId(itemId)
    for _, entry in ipairs(ShopConfig.Cosmetics) do
        if entry.itemId == itemId then return entry end
    end
    for _, entry in ipairs(ShopConfig.Consumables) do
        if entry.itemId == itemId then return entry end
    end
    for _, entry in ipairs(ShopConfig.Premium) do
        if entry.itemId == itemId then return entry end
    end
    return nil
end

--- Get all tab names.
function ShopConfig.GetTabNames()
    return { "Cosmetics", "Consumables", "Premium" }
end

-- §AGX/X10: consumables without a server-side use handler can't be bought.
-- Derive `enabled = false` from ConsumableConfig (single source of truth,
-- Audit §5.6) so GlobalShopUI hides them with no client change and
-- ShopManager rejects them. Flip `usable = true` in ConsumableConfig when a
-- use handler lands and the item reappears. An explicit `enabled` here wins.
do
    local consMod = script.Parent:WaitForChild("ConsumableConfig", 10)
    local ok, ConsumableConfig = false, nil
    if consMod then ok, ConsumableConfig = pcall(require, consMod) end
    for _, entry in ipairs(ShopConfig.Consumables) do
        if entry.enabled == nil then
            -- Fail closed: if ConsumableConfig can't load, nothing is sold.
            entry.enabled = (ok and ConsumableConfig and ConsumableConfig.IsUsable(entry.itemId)) or false
        end
    end
end

--- §AGX/X10/X34: server-side purchasability of a shop entry.
function ShopConfig.IsEnabled(entry)
    return entry ~= nil and entry.enabled ~= false
end

return ShopConfig
