-- ServerScriptService/Modules/BonusExpSystem
--[[
    Tracks stacked XP multiplier bonuses per player.

    Each bonus source registers an additive percentage (0–1 scale).
    The final multiplier applied to raw XP is:
        1.0 + sum(all registered addends for that player)

    Sources (string keys):
        "party"    – calculated by PartyManager based on member count/friendship
        "event"    – time-limited server events (future)
        "premium"  – Robux perk (future)
        ... any module can register its own key

    Usage:
        BonusExpSystem.SetBonus(player, "party", 0.075)  -- +7.5%
        BonusExpSystem.RemoveBonus(player, "party")
        BonusExpSystem.GetMultiplier(player)             -- e.g. 1.075
        BonusExpSystem.GetBonusPercent(player)           -- e.g. 7.5  (for UI display)
]]

local BonusExpSystem = {}

-- [player] = { [source] = addend }
local bonuses = {}

-- ═══════════════════════════════════════════════════════════
-- API
-- ═══════════════════════════════════════════════════════════

-- §DISC/D4: per-source and total restraints. Server-side callers only,
-- so these are typo insurance, not anti-exploit (a stray SetBonus
-- (player, "party", 100) would otherwise mean +10,000% XP).
local MAX_ADDEND_PER_SOURCE = 1.0   -- any single source caps at +100%
local MAX_TOTAL_BONUS       = 2.0   -- total caps at +200% (3.0× multiplier)

--- Set (or replace) a named bonus source for a player.
--- addend is a decimal fraction: 0.05 = 5%
function BonusExpSystem.SetBonus(player, source, addend)
	if type(addend) ~= "number" then return end
	if addend < 0 or addend > MAX_ADDEND_PER_SOURCE then
		warn(string.format(
			"[BonusExpSystem] Addend %.2f for source '%s' clamped to [0, %.1f] (§DISC/D4)",
			addend, tostring(source), MAX_ADDEND_PER_SOURCE))
		addend = math.clamp(addend, 0, MAX_ADDEND_PER_SOURCE)
	end
	if not bonuses[player] then
		bonuses[player] = {}
	end
	bonuses[player][source] = addend
end

--- Remove a named bonus source for a player.
function BonusExpSystem.RemoveBonus(player, source)
	local p = bonuses[player]
	if p then
		p[source] = nil
	end
end

--- Remove ALL bonuses for a player (call on PlayerRemoving).
function BonusExpSystem.CleanupPlayer(player)
	bonuses[player] = nil
end

--- Returns the total XP multiplier: 1.0 + all addends (capped §DISC/D4).
function BonusExpSystem.GetMultiplier(player)
	local p = bonuses[player]
	if not p then return 1.0 end
	local total = 0
	for _, v in pairs(p) do
		total = total + v
	end
	return 1.0 + math.min(total, MAX_TOTAL_BONUS)
end

--- Returns the total bonus as a percent integer for UI display (e.g. 7 → "7%").
function BonusExpSystem.GetBonusPercent(player)
	return (BonusExpSystem.GetMultiplier(player) - 1.0) * 100
end

--- Returns a breakdown table for UI: { [source] = percentFloat }
function BonusExpSystem.GetBreakdown(player)
	local p = bonuses[player]
	local result = {}
	if p then
		for source, addend in pairs(p) do
			result[source] = addend * 100
		end
	end
	return result
end

-- ═══════════════════════════════════════════════════════════
-- INIT (wires cleanup)
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")

function BonusExpSystem.Init()
	Players.PlayerRemoving:Connect(BonusExpSystem.CleanupPlayer)
end

return BonusExpSystem
