-- ReplicatedStorage/Shared/ConsumableConfig.lua
--[[
    Defines all consumable items that can be purchased, dropped, or stored.

    Each consumable has:
      id         string   Unique snake_case identifier
      name       string   Display name
      desc       string   Short description
      icon       string   Emoji/icon identifier for UI
      maxStack   number   Maximum quantity per inventory slot (default 99)
      cooldown   number   Seconds between uses (0 = no cooldown)
      effect     { type, ... }  Server-side effect definition
      usable     boolean? §AGX/X10: true only when server code actually consumes
                          the item (a use handler exists). Anything else is
                          not purchasable and is hidden from the shops.

    Effect types:
      HealHP      { type = "HealHP",     amount = 50 }
      HealPercent { type = "HealPercent", percent = 0.25 }   -- 25% max HP
      RestoreRes  { type = "RestoreRes",  amount = 30 }      -- class resource
      BuffStat    { type = "BuffStat",    stat = "Damage", value = 10, duration = 30 }
      RespecToken { type = "RespecToken" }                    -- grants 1 token
]]

local ConsumableConfig = {}

ConsumableConfig.Consumables = {

    -- §48: Consumable Rework — percentage-based healing, revised values

    -- ═══ Potions ═══
    {
        id       = "health_potion",
        name     = "Health Potion",
        desc     = "Restores 18% of max HP over 2 seconds.",
        icon     = "🧪",
        maxStack = 20,
        cooldown = 12,
        effect   = { type = "HealPercent", percent = 0.18, duration = 2 },
    },
    {
        id       = "health_potion_large",
        name     = "Greater Health Potion",
        desc     = "Restores 35% of max HP over 2 seconds.",
        icon     = "🧪",
        maxStack = 10,
        cooldown = 20,
        effect   = { type = "HealPercent", percent = 0.35, duration = 2 },
    },
    {
        id       = "health_elixir",
        name     = "Vitality Elixir",
        desc     = "Restores 25% of max HP instantly.",
        icon     = "💚",
        maxStack = 5,
        cooldown = 30,
        effect   = { type = "HealPercent", percent = 0.25 },
    },

    -- ═══ Resource Restorers ═══
    {
        id       = "mana_crystal",
        name     = "Mana Crystal",
        desc     = "Restores 25 class resource.",
        icon     = "💎",
        maxStack = 20,
        cooldown = 15,
        effect   = { type = "RestoreRes", amount = 25 },
    },
    {
        id       = "mana_crystal_large",
        name     = "Greater Mana Crystal",
        desc     = "Restores 50 class resource.",
        icon     = "💎",
        maxStack = 10,
        cooldown = 25,
        effect   = { type = "RestoreRes", amount = 50 },
    },

    -- ═══ Buff Items ═══
    {
        id       = "power_scroll",
        name     = "Power Scroll",
        desc     = "+8% damage for 45 seconds.",
        icon     = "📜",
        maxStack = 10,
        cooldown = 60,
        effect   = { type = "BuffStat", stat = "DamagePercent", value = 8, duration = 45 },
    },
    {
        id       = "iron_skin_potion",
        name     = "Ironskin Potion",
        desc     = "+12% armor-derived mitigation for 45 seconds.",
        icon     = "🛡",
        maxStack = 10,
        cooldown = 60,
        effect   = { type = "BuffStat", stat = "ArmorPercent", value = 12, duration = 45 },
    },
    {
        id       = "swiftness_elixir",
        name     = "Swiftness Elixir",
        desc     = "+10% movement speed for 30 seconds.",
        icon     = "💨",
        maxStack = 10,
        cooldown = 45,
        effect   = { type = "BuffStat", stat = "MovementSpeedPercent", value = 10, duration = 30 },
    },
    {
        id       = "fortune_incense",
        name     = "Fortune Incense",
        desc     = "+15% merit gain for 120 seconds.",
        icon     = "🪔",
        maxStack = 5,
        cooldown = 120,
        effect   = { type = "BuffStat", stat = "MeritBonus", value = 15, duration = 120 },
    },
    {
        id       = "crit_oil",
        name     = "Crit Oil",
        desc     = "+8% crit chance for 45 seconds.",
        icon     = "🗡",
        maxStack = 10,
        cooldown = 60,
        effect   = { type = "BuffStat", stat = "CritChance", value = 8, duration = 45 },
    },

    -- ═══ Special ═══
    {
        id       = "respec_fragment",
        name     = "Respec Fragment",
        desc     = "A shard of reflection. Combine 4 to form a Respec Scroll.",
        icon     = "🔹",
        maxStack = 99,
        cooldown = 0,
        effect   = { type = "None" },  -- passive collectible; auto-combines
    },
    {
        id       = "respec_scroll",
        name     = "Respec Scroll",
        desc     = "Consume to reset your talents without spending Essence.",
        icon     = "📋",
        maxStack = 99,
        cooldown = 0,
        effect   = { type = "RespecToken" },
        -- §AGX/X10: the only consumable with a use path today
        -- (TalentManager respec / SharedEventHandlers consume it).
        usable   = true,
    },
}

-- ── Lookup by ID ───────────────────────────────────────────────────────────
ConsumableConfig.ById = {}
for _, item in ipairs(ConsumableConfig.Consumables) do
    ConsumableConfig.ById[item.id] = item
end

-- ── Helpers ────────────────────────────────────────────────────────────────

function ConsumableConfig.GetById(id)
    return ConsumableConfig.ById[id]
end

function ConsumableConfig.GetAll()
    return ConsumableConfig.Consumables
end

function ConsumableConfig.IsConsumable(id)
    return ConsumableConfig.ById[id] ~= nil
end

--- §AGX/X10: true only for consumables with a server-side use handler.
-- ShopManager rejects purchases of anything else; ShopConfig derives
-- `enabled = false` from this so the shops hide them.
function ConsumableConfig.IsUsable(id)
    local def = ConsumableConfig.ById[id]
    return def ~= nil and def.usable == true
end

return ConsumableConfig
