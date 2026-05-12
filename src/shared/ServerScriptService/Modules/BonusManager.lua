-- ServerScriptService/Modules/BonusManager
--[[
    Central aggregation layer for all stat bonus sources.

    Problem it solves
    ═════════════════
    Before BonusManager, weapons, skill buffs, and (future) talents all
    wrote directly to data.Bonus[stat].  ApplyWeaponBonuses() would
    zero-out weapon stats and re-add them, silently clobbering any buff
    that happened to share the same stat key.

    Architecture
    ════════════
    Each source gets an isolated table of { [statName] = value }.
    When any source changes, BonusManager recomputes the aggregate and
    writes the total into data.Bonus — the existing stat pipeline
    (PlayerStatSystem.GetTotalStat, DamageSystem, etc.) keeps reading
    data.Bonus exactly as before.

    Registered sources (string keys):
        "weapon"       — random weapon bonus stats  (flat)
        "buff"         — active SkillManager buffs   (temporary, additive)
        "talent"       — talent tree passive bonuses  (persistent)
        "achievement"  — achievement bonuses          (persistent)
        "other"        — ad-hoc / debug / event       (anything else)

    New sources can be registered at runtime.

    API
    ═══
        BonusManager.Init()

        -- Source-level writes
        BonusManager.SetSourceBonuses(player, source, bonusTable)
            bonusTable = { CritChance = 5, FlatAttack = 10, ... }
            Replaces ALL entries for that source then recalculates.

        BonusManager.SetSourceBonus(player, source, stat, value)
            Set a single stat within a source, then recalculate.

        BonusManager.ModifySourceBonus(player, source, stat, delta)
            Add delta to a single stat within a source, then recalculate.

        BonusManager.ClearSource(player, source)
            Reset a source to {} then recalculate.

        -- Read helpers
        BonusManager.GetAggregatedBonus(player, stat) → number (sum of all sources)

        -- Full recalculate (writes into data.Bonus)
        BonusManager.Recalculate(player)
]]

local BonusManager = {}

local Modules = script.Parent

-- DataManager is injected via BonusManager.InjectDataManager() by the bootstrap
-- after both modules are loaded, breaking the static cyclic-require chain:
--   BonusManager -> PlayerDataManager -> PlayerBonusSystem -> BonusManager
local DataManager = nil
local Config      = nil

local function getDataManager()
	return DataManager
end

local function getConfig()
	if not Config then
		Config = require(Modules:WaitForChild("PlayerDataConfig"))
	end
	return Config
end

--- Called by the bootstrap after PlayerDataManager is loaded.
function BonusManager.InjectDataManager(dm)
	DataManager = dm
end

-- ── Per-player source tables ──────────────────────────────
-- playerBonuses[player][source][stat] = value
local playerBonuses = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function BonusManager.Init()
	local Players = game:GetService("Players")

	Players.PlayerAdded:Connect(function(player)
		BonusManager.SetupPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		playerBonuses[player] = nil
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		BonusManager.SetupPlayer(p)
	end

end

function BonusManager.SetupPlayer(player)
	if not playerBonuses[player] then
		playerBonuses[player] = {
			weapon      = {},
			armor       = {},   -- armor defense, bonusHealth, and random roll bonuses
			buff        = {},
			talent      = {},
			achievement = {},
			innate      = {},   -- class passives (HealthPercent, CritChance, etc.)
			acc_trinket = {},   -- equipped trinket bonuses
			acc_ring1   = {},   -- equipped ring 1 bonuses
			acc_ring2   = {},   -- equipped ring 2 bonuses
			other       = {},
		}
	end
end

-- ═══════════════════════════════════════════════════════════
-- SOURCE-LEVEL WRITES
-- ═══════════════════════════════════════════════════════════

--- Replace all bonuses for a source and recalculate.
function BonusManager.SetSourceBonuses(player, source, bonusTable)
	BonusManager.SetupPlayer(player)
	playerBonuses[player][source] = bonusTable or {}
	BonusManager.Recalculate(player)
end

--- Set one stat within a source and recalculate.
function BonusManager.SetSourceBonus(player, source, stat, value)
	BonusManager.SetupPlayer(player)
	if not playerBonuses[player][source] then
		playerBonuses[player][source] = {}
	end
	playerBonuses[player][source][stat] = value
	BonusManager.Recalculate(player)
end

--- Add delta to a single stat within a source, then recalculate.
function BonusManager.ModifySourceBonus(player, source, stat, delta)
	BonusManager.SetupPlayer(player)
	if not playerBonuses[player][source] then
		playerBonuses[player][source] = {}
	end
	local current = playerBonuses[player][source][stat] or 0
	playerBonuses[player][source][stat] = current + delta
	BonusManager.Recalculate(player)
end

--- Reset a source to empty.
function BonusManager.ClearSource(player, source)
	BonusManager.SetupPlayer(player)
	playerBonuses[player][source] = {}
	BonusManager.Recalculate(player)
end

--- Apply a temporary stat bonus that auto-expires after `durationSec`.
--- Uses a unique source key per tag so multiple timed buffs stack cleanly.
--- Called by the card/vote system (PowerSurge, Sharpsight, FrenzyBanner, etc.)
function BonusManager.AddTimedBonus(player, tagName, statName, value, durationSec)
	local source = "timed_" .. tagName
	BonusManager.SetSourceBonus(player, source, statName, value)
	task.delay(durationSec, function()
		-- Only clear if the player is still connected
		if player and player.Parent then
			BonusManager.ClearSource(player, source)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- READ HELPERS
-- ═══════════════════════════════════════════════════════════

--- Sum a single stat across ALL sources.
function BonusManager.GetAggregatedBonus(player, stat)
	local sources = playerBonuses[player]
	if not sources then return 0 end
	local total = 0
	for _, tbl in pairs(sources) do
		total = total + (tbl[stat] or 0)
	end
	return total
end

-- ═══════════════════════════════════════════════════════════
-- RECALCULATE  —  writes aggregated totals into data.Bonus
-- ═══════════════════════════════════════════════════════════

function BonusManager.Recalculate(player)
	local dm   = getDataManager()
	local cfg  = getConfig()
	local data = dm.GetData(player)
	if not data then return end

	-- Walk every stat declared in BonusStats config and sum sources
	for statName, defaultValue in pairs(cfg.BonusStats) do
		local total = defaultValue   -- almost always 0
		local sources = playerBonuses[player]
		if sources then
			for _, srcTable in pairs(sources) do
				total = total + (srcTable[statName] or 0)
			end
		end
		data.Bonus[statName] = total
	end

	-- Also handle percent-bonus keys that don't appear in BonusStats
	-- (e.g. HealthPercent, DamagePercent are already in BonusStats)
	-- This is future-safe: if a source sets a stat not in BonusStats,
	-- we still aggregate it.
	local sources = playerBonuses[player]
	if sources then
		for _, srcTable in pairs(sources) do
			for statName, value in pairs(srcTable) do
				if cfg.BonusStats[statName] == nil then
					-- Stat not in config — aggregate it anyway
					local total = 0
					for _, s in pairs(sources) do
						total = total + (s[statName] or 0)
					end
					data.Bonus[statName] = total
				end
			end
		end
	end
end

return BonusManager
