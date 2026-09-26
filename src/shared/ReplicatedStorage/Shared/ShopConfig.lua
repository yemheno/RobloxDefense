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
      Premium      — Robux: cosmetics / appearance change / VIP only (§AGX/X40)

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
    -- §AGX/X10b: potions, crystals and buffs are sold again — `enabled` is
    -- derived from ConsumableConfig.usable (bottom of file), now true for
    -- all but swiftness_elixir (no move-speed system yet; stays hidden).
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
    -- §AGX/X42: 50 → 25 Essence. It cost 2× a direct respec (25), so no
    -- one had a reason to buy it. Now equal: the scroll is a prepaid,
    -- stackable respec usable for talents OR stats (PlayerDataConfig
    -- RESPEC_COSTS).
    {
        itemId   = "respec_scroll",
        tab      = "Consumables",
        price    = 25,
        currency = "Essence",
        levelReq = 10,
    },
}

-- ═══════════════════════════════════════════════════════════
-- PREMIUM TAB  (§AGX/X40 monetization decision, 2026-09-26)
-- ═══════════════════════════════════════════════════════════
-- §AGX/X40: Robux buys cosmetics, appearance changes and non-power
-- convenience ONLY. Gameplay currency (Merits, Essence) and anything
-- that converts into it (respec scrolls, consumables, gear, refine /
-- reroll / tier-up) is never sold. The old Essence / Merit packs and the
-- "Respec Token x3" pack were DELETED, not disabled: a respec scroll is
-- worth 25 Essence (BALANCE_NUMBERS §33), so selling it was an indirect
-- Essence sale. MonetizationService refuses to register any entry whose
-- grant.type is not in its allowlist (AppearanceChange / Cosmetics /
-- GamePass), so a currency pack re-added here can't be prompted.
--
-- Entry fields (on top of the common ones above):
--   kind          "DevProduct" (consumable, ProcessReceipt) | "GamePass" (permanent)
--   devProductId  number  DevProduct id (0 = not created yet → never prompted)
--   gamePassId    number  GamePass id   (0 = not created yet → never prompted)
--   price         number  Robux. Display only — Roblox charges what the
--                         Creator Dashboard says; keep the two in sync.
--   grant         table   { type = "AppearanceChange" }
--                         { type = "Cosmetics", items = { cosmeticId, ... } }
--                         { type = "GamePass", attribute = "VIP", perks = {...} }
--
-- Every entry stays `enabled = false` until Pablo creates the product in
-- the Creator Dashboard and pastes its id here. `enabled = false` hides
-- it in GlobalShopUI and ShopManager/MonetizationService refuse the
-- prompt; a receipt for an already-paid product is still honoured.
ShopConfig.Premium = {
    {
        itemId       = "premium_appearance_change",
        tab          = "Premium",
        enabled      = false,
        kind         = "DevProduct",
        name         = "Appearance Change",
        desc         = "Change your character's body, gender and skin once. Gear and stats are not affected.",
        icon         = "🪞",
        price        = 49,
        currency     = "Robux",
        devProductId = 0,    -- placeholder
        grant        = { type = "AppearanceChange" },
    },
    -- Cosmetic bundles. The ids below are the only non-starter cosmetics
    -- that exist today (CosmeticConfig, all placeholders per §DISC/D7).
    -- They are also sold for Merits/Essence in the Cosmetics tab, and
    -- MonetizationService blocks a Robux bundle that overlaps an
    -- earn-currency listing (buying it for Robux would free up gameplay
    -- currency). Replace them with Robux-exclusive cosmetics in the D7
    -- shop pass, or take them out of the Cosmetics tab.
    {
        itemId       = "premium_bundle_vanguard",
        tab          = "Premium",
        enabled      = false,
        kind         = "DevProduct",
        name         = "Vanguard Look (Aegis)",
        desc         = "Aegis helm + Dark Knight outfit. Cosmetic only, no stats.",
        icon         = "🛡️",
        price        = 99,
        currency     = "Robux",
        devProductId = 0,
        grant        = { type = "Cosmetics", items = { "helm_aegis", "dark_knight" } },
    },
    {
        itemId       = "premium_bundle_arcanum",
        tab          = "Premium",
        enabled      = false,
        kind         = "DevProduct",
        name         = "Arcanum Look (Arcanist)",
        desc         = "Arcanist circlet + Shadow Robes. Cosmetic only, no stats.",
        icon         = "🔮",
        price        = 99,
        currency     = "Robux",
        devProductId = 0,
        grant        = { type = "Cosmetics", items = { "circlet_arcanist", "shadow_robes" } },
    },
    {
        itemId       = "premium_bundle_wildwood",
        tab          = "Premium",
        enabled      = false,
        kind         = "DevProduct",
        name         = "Wildwood Look (Hunter)",
        desc         = "Hunter mask + Forest Ranger outfit. Cosmetic only, no stats.",
        icon         = "🏹",
        price        = 99,
        currency     = "Robux",
        devProductId = 0,
        grant        = { type = "Cosmetics", items = { "mask_hunter", "forest_ranger" } },
    },
    -- VIP GamePass: social / cosmetic perks only. No XP, drop, Merit,
    -- Essence, revive or stat bonus, ever. The perks are exposed as a
    -- player attribute ("VIP") for the nameplate / chat tag to read;
    -- nothing consumes it yet.
    {
        itemId       = "premium_vip",
        tab          = "Premium",
        enabled      = false,
        kind         = "GamePass",
        name         = "VIP",
        desc         = "VIP nameplate and chat tag. Social perks only, no gameplay advantage.",
        icon         = "⭐",
        price        = 199,
        currency     = "Robux",
        gamePassId   = 0,    -- placeholder
        grant        = { type = "GamePass", attribute = "VIP", perks = { "nameplate_tag", "chat_tag" } },
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
