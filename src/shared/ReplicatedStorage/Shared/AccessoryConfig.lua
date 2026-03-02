-- ReplicatedStorage/Shared/AccessoryConfig.lua
--[[
    Defines all accessories (trinkets and rings) that can drop from bosses
    and be stored in the player's Inventory.

    Each accessory has:
      id        string   Unique snake_case identifier
      name      string   Display name
      desc      string   Short description
      rarity    string   "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
      slot      string   "Trinket" | "Ring"
      bonuses   { {stat, value} }  Stat modifiers applied when equipped
      source    string   Where it drops from (e.g. "boss_skeleton_king")
      icon      string   Emoji/icon identifier for UI

    Equip slots:
      TrinketId   — one trinket slot
      Ring1Id     — ring slot 1
      Ring2Id     — ring slot 2

    Rarity colours (for UI):
      Common    = white
      Uncommon  = green
      Rare      = blue
      Epic      = purple
      Legendary = gold/orange
]]

local AccessoryConfig = {}

-- ── Rarity Definitions ─────────────────────────────────────────────────────
AccessoryConfig.Rarities = {
    Common    = { order = 1, color = {200, 200, 200} },
    Uncommon  = { order = 2, color = { 80, 200,  80} },
    Rare      = { order = 3, color = { 60, 120, 255} },
    Epic      = { order = 4, color = {180,  60, 255} },
    Legendary = { order = 5, color = {255, 180,  40} },
}

-- ── Accessory Definitions ──────────────────────────────────────────────────
AccessoryConfig.Accessories = {

    -- ═══ Common Trinkets ═══
    {
        id      = "bone_charm",
        name    = "Bone Charm",
        desc    = "A charm carved from fallen foes.",
        rarity  = "Common",
        slot    = "Trinket",
        bonuses = { { stat = "Health", value = 20 } },
        source  = "boss_any",
        icon    = "🦴",
    },
    {
        id      = "iron_pendant",
        name    = "Iron Pendant",
        desc    = "A sturdy pendant that boosts defense.",
        rarity  = "Common",
        slot    = "Trinket",
        bonuses = { { stat = "Armor", value = 5 } },
        source  = "boss_any",
        icon    = "🔗",
    },

    -- ═══ Common Rings ═══
    {
        id      = "copper_band",
        name    = "Copper Band",
        desc    = "A simple ring with minor enchantment.",
        rarity  = "Common",
        slot    = "Ring",
        bonuses = { { stat = "Damage", value = 3 } },
        source  = "boss_any",
        icon    = "💍",
    },
    {
        id      = "focus_ring",
        name    = "Focus Ring",
        desc    = "Sharpens the mind, improving precision.",
        rarity  = "Common",
        slot    = "Ring",
        bonuses = { { stat = "CritChance", value = 2 } },
        source  = "boss_any",
        icon    = "🔮",
    },

    -- ═══ Uncommon Trinkets ═══
    {
        id      = "wolf_fang",
        name    = "Wolf Fang Talisman",
        desc    = "The fang of an alpha wolf; boosts attack power.",
        rarity  = "Uncommon",
        slot    = "Trinket",
        bonuses = { { stat = "Damage", value = 8 }, { stat = "CritDamage", value = 0.1 } },
        source  = "boss_wolf_alpha",
        icon    = "🐺",
    },
    {
        id      = "guardian_sigil",
        name    = "Guardian Sigil",
        desc    = "A protective symbol that reduces damage taken.",
        rarity  = "Uncommon",
        slot    = "Trinket",
        bonuses = { { stat = "DamageReduction", value = 3 }, { stat = "Health", value = 40 } },
        source  = "boss_golem",
        icon    = "🛡",
    },

    -- ═══ Uncommon Rings ═══
    {
        id      = "swiftfoot_ring",
        name    = "Swiftfoot Ring",
        desc    = "Enhances movement speed.",
        rarity  = "Uncommon",
        slot    = "Ring",
        bonuses = { { stat = "MovementSpeed", value = 5 } },
        source  = "boss_any",
        icon    = "💨",
    },
    {
        id      = "ember_ring",
        name    = "Ember Ring",
        desc    = "Burns with inner fire, boosting damage.",
        rarity  = "Uncommon",
        slot    = "Ring",
        bonuses = { { stat = "Damage", value = 6 }, { stat = "Penetration", value = 3 } },
        source  = "boss_fire_elemental",
        icon    = "🔥",
    },

    -- ═══ Rare ═══
    {
        id      = "dragon_scale",
        name    = "Dragon Scale Amulet",
        desc    = "A scale from an ancient dragon; massive defense boost.",
        rarity  = "Rare",
        slot    = "Trinket",
        bonuses = { { stat = "Armor", value = 15 }, { stat = "DamageReduction", value = 5 }, { stat = "Health", value = 80 } },
        source  = "boss_dragon",
        icon    = "🐉",
    },
    {
        id      = "assassin_signet",
        name    = "Assassin's Signet",
        desc    = "The mark of a master assassin.",
        rarity  = "Rare",
        slot    = "Ring",
        bonuses = { { stat = "CritChance", value = 8 }, { stat = "CritDamage", value = 0.25 } },
        source  = "boss_shadow_lord",
        icon    = "🗡",
    },

    -- ═══ Epic ═══
    {
        id      = "lich_heart",
        name    = "Lich's Heart",
        desc    = "Pulsing with dark energy; greatly boosts magic power.",
        rarity  = "Epic",
        slot    = "Trinket",
        bonuses = { { stat = "Damage", value = 25 }, { stat = "CooldownReduction", value = 8 } },
        source  = "boss_lich",
        icon    = "💀",
    },
    {
        id      = "stormcaller_ring",
        name    = "Stormcaller Ring",
        desc    = "Channels the fury of storms.",
        rarity  = "Epic",
        slot    = "Ring",
        bonuses = { { stat = "Damage", value = 18 }, { stat = "Penetration", value = 10 }, { stat = "CritChance", value = 5 } },
        source  = "boss_storm_titan",
        icon    = "⚡",
    },

    -- ═══ Legendary ═══
    {
        id      = "crown_of_ages",
        name    = "Crown of Ages",
        desc    = "An ancient crown of unimaginable power.",
        rarity  = "Legendary",
        slot    = "Trinket",
        bonuses = { { stat = "Health", value = 200 }, { stat = "Damage", value = 30 }, { stat = "Armor", value = 20 }, { stat = "CritChance", value = 5 } },
        source  = "boss_final",
        icon    = "👑",
    },
    {
        id      = "eternity_band",
        name    = "Eternity Band",
        desc    = "A ring forged at the dawn of time.",
        rarity  = "Legendary",
        slot    = "Ring",
        bonuses = { { stat = "Damage", value = 20 }, { stat = "CritDamage", value = 0.5 }, { stat = "CooldownReduction", value = 10 }, { stat = "MovementSpeed", value = 8 } },
        source  = "boss_final",
        icon    = "✨",
    },
}

-- ── Lookup by ID ───────────────────────────────────────────────────────────
AccessoryConfig.ById = {}
for _, acc in ipairs(AccessoryConfig.Accessories) do
    AccessoryConfig.ById[acc.id] = acc
end

-- ── Helpers ────────────────────────────────────────────────────────────────

function AccessoryConfig.GetById(id)
    return AccessoryConfig.ById[id]
end

function AccessoryConfig.GetByRarity(rarity)
    local out = {}
    for _, acc in ipairs(AccessoryConfig.Accessories) do
        if acc.rarity == rarity then
            table.insert(out, acc)
        end
    end
    return out
end

function AccessoryConfig.GetBySlot(slot)
    local out = {}
    for _, acc in ipairs(AccessoryConfig.Accessories) do
        if acc.slot == slot then
            table.insert(out, acc)
        end
    end
    return out
end

function AccessoryConfig.GetBySource(source)
    local out = {}
    for _, acc in ipairs(AccessoryConfig.Accessories) do
        if acc.source == source then
            table.insert(out, acc)
        end
    end
    return out
end

--- Returns the GearScore contribution of an accessory.
--- Used by the leaderboard / gear rating system.
function AccessoryConfig.GetAccessoryScore(id)
    local acc = AccessoryConfig.ById[id]
    if not acc then return 0 end
    local rarityScores = { Common = 5, Uncommon = 15, Rare = 30, Epic = 60, Legendary = 100 }
    return rarityScores[acc.rarity] or 0
end

return AccessoryConfig
