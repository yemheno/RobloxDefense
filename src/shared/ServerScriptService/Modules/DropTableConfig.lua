-- ServerScriptService/Modules/DropTableConfig
--[[
    Drop tables for mob kills.

    Structure
    ═════════
    Each table entry has:
        type      – "Merits" | "Essence" | (future: item id)
        chance    – 0-1 probability (1 = guaranteed)
        min / max – random integer range for the amount

    Tables are resolved in order.  Every entry is rolled independently, so a
    mob can drop merits AND essence in the same kill if both hit.

    Priority: mobOverrides[mobId]  >  tierDefaults[mobTier]

    Future extension: add rarity tiers, weighted bags, item drops, etc.
]]

local DropTableConfig = {}

-- ───────────────────────────────────────────────────────────
-- PER-TIER DEFAULTS
-- ───────────────────────────────────────────────────────────

DropTableConfig.TierDefaults = {
	normal = {
		{ type = "Merits", chance = 1.0, min = 1, max = 3 },
	},

	miniboss = {
		{ type = "Merits",  chance = 1.0,  min = 8,  max = 15 },
		-- Essence is flat (noScale=true) — keeps it precious regardless of wave level
		{ type = "Essence", chance = 0.30, min = 2, max = 4, noScale = true },
	},

	boss = {
		{ type = "Merits",  chance = 1.0,  min = 25, max = 50 },
		{ type = "Essence", chance = 0.75, min = 8,  max = 20, noScale = true },
	},
}

-- ───────────────────────────────────────────────────────────
-- PER-MOB OVERRIDES  (takes full priority over tier table)
-- ───────────────────────────────────────────────────────────

DropTableConfig.MobOverrides = {
	-- [mobId] = { { type, chance, min, max, noScale? }, ... }  (same shape as TierDefaults)
}

-- ───────────────────────────────────────────────────────────
-- HELPERS
-- ───────────────────────────────────────────────────────────

--- Return the drop table for a given mob, falling back to tier defaults.
function DropTableConfig.GetDropTable(mobId, mobTier)
	if DropTableConfig.MobOverrides[mobId] then
		return DropTableConfig.MobOverrides[mobId]
	end
	return DropTableConfig.TierDefaults[mobTier] or DropTableConfig.TierDefaults.normal
end

return DropTableConfig
