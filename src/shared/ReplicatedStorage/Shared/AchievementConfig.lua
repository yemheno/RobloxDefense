-- ReplicatedStorage/Shared/AchievementConfig.lua
--[[
    Single source of truth for all achievement definitions.
    Placed in ReplicatedStorage/Shared so both server (AchievementManager)
    and client (AchievementsUI) can require it.

    TIERED FORMAT — each achievement has exactly 10 unlock tiers.

    Achievement table fields:
      id        string   Unique snake_case identifier
      name      string   Display name (shown as "Name  Lv N / 10")
      desc      string   One-line description
      icon      string   Emoji or short symbol
      category  string   "Combat" | "Survival" | "Healer" | "Collection"
                         | "Dedication" | "Weapon" | "Medals" | "Mastery"
      stat      string?  Key in the stats table to check (e.g. "totalKills")
      statFn    fn?      function(stats) → number  (for nested / computed stats)
      tiers     {number} Threshold per tier level; always exactly 10 entries
      rewards   {{type,amount}[]}  One reward list per tier.
                Supported types: "Merits", "Essence", "RespecToken"

    Exactly ONE of `stat` or `statFn` must be provided.

    Stats tracked (AchievementManager):
      totalKills, killsByMobId { [id] = count }
      killsByTier { normal, miniboss, boss }
      hitsDelivered, hitsReceived
      meritsCollected, essenceEarned
      wavesSurvived, highestWave
      totalDamageDealt, totalDamageTaken
      criticalHits, bestCombo
      healingDone, revivesDone
      weaponLevelMax
      talentNodesAllocated
      capMasteryKills { cap50, cap100, cap150, cap200 }

    Boss medal mob IDs (update when bosses are added to MobRegistry):
      "iron_warden"        — Tier 1 boss, designed for ~level 50 players
      "void_harbinger"     — Tier 2 boss, designed for ~level 100 players
      "pale_colossus"      — Tier 3 boss, designed for ~level 150 players
      "abyssal_sovereign"  — Tier 4 boss, designed for ~level 200 players

    Cap Mastery logic (AchievementManager.OnKill):
      cap50  incremented when iron_warden is killed while player.Level ≤ 50
      cap100 incremented when void_harbinger is killed while player.Level ≤ 100
      cap150 incremented when pale_colossus is killed while player.Level ≤ 150
      cap200 incremented when abyssal_sovereign is killed while player.Level ≤ 200

    REWARD PHILOSOPHY (balanced against BALANCE_NUMBERS.md)
    ═══════════════════════════════════════════════════════
    Economy anchors:
      • 99 Robux  = 50 Essence  (Essence is premium)
      • Weapon tier ladder I→XII = ~1,650 Essence total
      • Respec = 25 Essence flat (§AGX/X42)
      • Daily login = 2–10 Essence/day; day-30 bonus = 100 Essence
      • 12-wave Lane run ≈ 542 × (1 + 0.1(L−1)) Merits on Normal (§AGX/X25)
      • Old achievement lifetime cap ≈ 100K Merits + 500–600 Essence + 2 Respecs

    Reward bands (tier 10 cap per band):
      Standard  — 125K Merits / 125 Essence / 1 Respec   (common combat / survival)
      Elevated  — 200–250K Merits / 175–200 Essence / 2 Respecs  (boss / healer / weapon)
      Premium   — 300–400K Merits / 250–350 Essence / 3 Respecs  (boss medals)
      Mastery   — 350–500K Merits / 325–400 Essence / 3 Respecs  (cap mastery)

    Cross-rewards: merit_earner (M collector) rewards Essence only.
                   essence_hoarder (E collector) rewards Merits only.
]]

local AchievementConfig = {}

-- ── Utility ──────────────────────────────────────────────────────────────────

--- Format large numbers: 1234567 → "1.23M", 1234 → "1,234"
function AchievementConfig.FormatNumber(n)
	if n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e3 then
		-- Insert comma separators
		local s = tostring(math.floor(n))
		local result = ""
		local len = #s
		for i = 1, len do
			if i > 1 and (len - i + 1) % 3 == 0 then
				result = result .. ","
			end
			result = result .. s:sub(i, i)
		end
		return result
	else
		return tostring(n)
	end
end

-- ── Achievement Definitions ───────────────────────────────────────────────────

AchievementConfig.Achievements = {

	-- ════════════════════════════════════════════════════════
	-- COMBAT
	-- ════════════════════════════════════════════════════════

	--[[  KILLS  ]]
	{
		id       = "kills",
		name     = "Slayer",
		desc     = "Defeat enemies.",
		icon     = "⚔",
		category = "Combat",
		stat     = "totalKills",
		tiers    = { 50, 250, 1000, 4000, 12000, 35000, 100000, 275000, 700000, 2000000 },
		rewards  = {
			{ {"Merits", 25} },
			{ {"Merits", 75} },
			{ {"Merits", 200} },
			{ {"Merits", 600},    {"Essence", 2} },
			{ {"Merits", 2000},   {"Essence", 5} },
			{ {"Merits", 6000},   {"Essence", 10} },
			{ {"Merits", 15000},  {"Essence", 20} },
			{ {"Merits", 35000},  {"Essence", 40} },
			{ {"Merits", 75000},  {"Essence", 75},  {"RespecToken", 1} },
			{ {"Merits", 125000}, {"Essence", 125}, {"RespecToken", 1} },
		},
	},

	--[[  MINIBOSS KILLS  ]]
	{
		id       = "miniboss_slayer",
		name     = "Elite Hunter",
		desc     = "Defeat miniboss enemies.",
		icon     = "🏹",
		category = "Combat",
		statFn   = function(s) return s.killsByTier and s.killsByTier.miniboss or 0 end,
		tiers    = { 5, 25, 75, 200, 500, 1200, 3000, 7000, 15000, 35000 },
		rewards  = {
			{ {"Merits", 50} },
			{ {"Merits", 150} },
			{ {"Merits", 450} },
			{ {"Merits", 1200},   {"Essence", 3} },
			{ {"Merits", 3000},   {"Essence", 8} },
			{ {"Merits", 8000},   {"Essence", 18} },
			{ {"Merits", 20000},  {"Essence", 35} },
			{ {"Merits", 50000},  {"Essence", 70} },
			{ {"Merits", 110000}, {"Essence", 125}, {"RespecToken", 1} },
			{ {"Merits", 200000}, {"Essence", 175}, {"RespecToken", 2} },
		},
	},

	--[[  BOSS KILLS  ]]
	{
		id       = "boss_slayer",
		name     = "Boss Breaker",
		desc     = "Defeat boss enemies.",
		icon     = "💀",
		category = "Combat",
		statFn   = function(s) return s.killsByTier and s.killsByTier.boss or 0 end,
		tiers    = { 1, 5, 15, 40, 100, 250, 600, 1500, 3500, 8000 },
		rewards  = {
			{ {"Merits", 100} },
			{ {"Merits", 350} },
			{ {"Merits", 1000} },
			{ {"Merits", 3000},   {"Essence", 5} },
			{ {"Merits", 8000},   {"Essence", 15} },
			{ {"Merits", 20000},  {"Essence", 30} },
			{ {"Merits", 50000},  {"Essence", 60} },
			{ {"Merits", 100000}, {"Essence", 100} },
			{ {"Merits", 175000}, {"Essence", 150}, {"RespecToken", 1} },
			{ {"Merits", 250000}, {"Essence", 200}, {"RespecToken", 2} },
		},
	},

	--[[  CRITICAL HITS  ]]
	{
		id       = "critical_striker",
		name     = "Precision",
		desc     = "Land critical hits.",
		icon     = "🎯",
		category = "Combat",
		stat     = "criticalHits",
		tiers    = { 25, 150, 600, 2000, 6000, 18000, 50000, 130000, 320000, 800000 },
		rewards  = {
			{ {"Merits", 20} },
			{ {"Merits", 60} },
			{ {"Merits", 175} },
			{ {"Merits", 500},    {"Essence", 1} },
			{ {"Merits", 1500},   {"Essence", 4} },
			{ {"Merits", 4500},   {"Essence", 8} },
			{ {"Merits", 12000},  {"Essence", 16} },
			{ {"Merits", 30000},  {"Essence", 35} },
			{ {"Merits", 65000},  {"Essence", 65},  {"RespecToken", 1} },
			{ {"Merits", 125000}, {"Essence", 115}, {"RespecToken", 1} },
		},
	},

	--[[  DAMAGE DEALT  ]]
	{
		id       = "destroyer",
		name     = "Destroyer",
		desc     = "Deal total damage.",
		icon     = "💥",
		category = "Combat",
		stat     = "totalDamageDealt",
		tiers    = { 5000, 30000, 150000, 600000, 2000000, 7000000, 25000000, 80000000, 250000000, 1000000000 },
		rewards  = {
			{ {"Merits", 20} },
			{ {"Merits", 60} },
			{ {"Merits", 175} },
			{ {"Merits", 500},    {"Essence", 1} },
			{ {"Merits", 1500},   {"Essence", 4} },
			{ {"Merits", 4500},   {"Essence", 8} },
			{ {"Merits", 12000},  {"Essence", 16} },
			{ {"Merits", 30000},  {"Essence", 35} },
			{ {"Merits", 65000},  {"Essence", 65},  {"RespecToken", 1} },
			{ {"Merits", 125000}, {"Essence", 115}, {"RespecToken", 1} },
		},
	},

	--[[  BEST COMBO  ]]
	{
		id       = "combo_king",
		name     = "Combo King",
		desc     = "Reach a high hit combo.",
		icon     = "🔥",
		category = "Combat",
		stat     = "bestCombo",
		tiers    = { 10, 25, 50, 100, 150, 200, 250, 300, 400, 500 },
		rewards  = {
			{ {"Merits", 25} },
			{ {"Merits", 75} },
			{ {"Merits", 200} },
			{ {"Merits", 600},    {"Essence", 2} },
			{ {"Merits", 1800},   {"Essence", 5} },
			{ {"Merits", 5000},   {"Essence", 10} },
			{ {"Merits", 12000},  {"Essence", 18} },
			{ {"Merits", 28000},  {"Essence", 32} },
			{ {"Merits", 60000},  {"Essence", 60},  {"RespecToken", 1} },
			{ {"Merits", 125000}, {"Essence", 100}, {"RespecToken", 1} },
		},
	},

	--[[  HITS DELIVERED  ]]
	{
		id       = "relentless",
		name     = "Relentless",
		desc     = "Land hits on enemies.",
		icon     = "👊",
		category = "Combat",
		stat     = "hitsDelivered",
		tiers    = { 500, 2500, 10000, 40000, 120000, 350000, 1000000, 3000000, 8000000, 25000000 },
		rewards  = {
			{ {"Merits", 15} },
			{ {"Merits", 50} },
			{ {"Merits", 150} },
			{ {"Merits", 450},    {"Essence", 1} },
			{ {"Merits", 1500},   {"Essence", 3} },
			{ {"Merits", 4000},   {"Essence", 7} },
			{ {"Merits", 10000},  {"Essence", 15} },
			{ {"Merits", 25000},  {"Essence", 30} },
			{ {"Merits", 55000},  {"Essence", 60},  {"RespecToken", 1} },
			{ {"Merits", 100000}, {"Essence", 100}, {"RespecToken", 1} },
		},
	},

	-- ════════════════════════════════════════════════════════
	-- SURVIVAL
	-- ════════════════════════════════════════════════════════

	--[[  WAVES SURVIVED  ]]
	{
		id       = "survivor",
		name     = "Survivor",
		desc     = "Survive waves of enemies.",
		icon     = "🛡",
		category = "Survival",
		stat     = "wavesSurvived",
		tiers    = { 10, 50, 150, 400, 900, 2000, 5000, 12000, 30000, 75000 },
		rewards  = {
			{ {"Merits", 30} },
			{ {"Merits", 100} },
			{ {"Merits", 300} },
			{ {"Merits", 800},    {"Essence", 2} },
			{ {"Merits", 2500},   {"Essence", 6} },
			{ {"Merits", 7000},   {"Essence", 14} },
			{ {"Merits", 18000},  {"Essence", 28} },
			{ {"Merits", 45000},  {"Essence", 55} },
			{ {"Merits", 100000}, {"Essence", 100}, {"RespecToken", 1} },
			{ {"Merits", 200000}, {"Essence", 175}, {"RespecToken", 2} },
		},
	},

	--[[  HIGHEST WAVE  ]]
	{
		id       = "wave_master",
		name     = "Wave Master",
		desc     = "Reach a high wave number in a single run.",
		icon     = "🌊",
		category = "Survival",
		stat     = "highestWave",
		tiers    = { 10, 25, 50, 75, 100, 125, 150, 175, 200, 250 },
		rewards  = {
			{ {"Merits", 50} },
			{ {"Merits", 200} },
			{ {"Merits", 600} },
			{ {"Merits", 1500},   {"Essence", 4} },
			{ {"Merits", 4000},   {"Essence", 10} },
			{ {"Merits", 10000},  {"Essence", 22} },
			{ {"Merits", 25000},  {"Essence", 45} },
			{ {"Merits", 60000},  {"Essence", 85} },
			{ {"Merits", 130000}, {"Essence", 145}, {"RespecToken", 1} },
			{ {"Merits", 250000}, {"Essence", 200}, {"RespecToken", 2} },
		},
	},

	--[[  DAMAGE TANKED  ]]
	{
		id       = "thick_skin",
		name     = "Thick Skin",
		desc     = "Absorb total damage taken.",
		icon     = "🧱",
		category = "Survival",
		stat     = "totalDamageTaken",
		tiers    = { 2500, 15000, 75000, 300000, 1000000, 4000000, 15000000, 50000000, 150000000, 500000000 },
		rewards  = {
			{ {"Merits", 20} },
			{ {"Merits", 60} },
			{ {"Merits", 175} },
			{ {"Merits", 500},    {"Essence", 1} },
			{ {"Merits", 1500},   {"Essence", 3} },
			{ {"Merits", 4000},   {"Essence", 7} },
			{ {"Merits", 10000},  {"Essence", 14} },
			{ {"Merits", 25000},  {"Essence", 28} },
			{ {"Merits", 55000},  {"Essence", 55},  {"RespecToken", 1} },
			{ {"Merits", 100000}, {"Essence", 100}, {"RespecToken", 1} },
		},
	},

	-- ════════════════════════════════════════════════════════
	-- HEALER
	-- ════════════════════════════════════════════════════════

	--[[  HEALING DONE  ]]
	{
		id       = "life_giver",
		name     = "Life Giver",
		desc     = "Heal allies.",
		icon     = "💚",
		category = "Healer",
		stat     = "healingDone",
		tiers    = { 1000, 10000, 50000, 200000, 700000, 2000000, 7000000, 20000000, 60000000, 200000000 },
		rewards  = {
			{ {"Merits", 50} },
			{ {"Merits", 175} },
			{ {"Merits", 500} },
			{ {"Merits", 1500},   {"Essence", 4} },
			{ {"Merits", 4500},   {"Essence", 10} },
			{ {"Merits", 12000},  {"Essence", 22} },
			{ {"Merits", 30000},  {"Essence", 45} },
			{ {"Merits", 70000},  {"Essence", 85} },
			{ {"Merits", 150000}, {"Essence", 145}, {"RespecToken", 1} },
			{ {"Merits", 250000}, {"Essence", 200}, {"RespecToken", 2} },
		},
	},

	--[[  REVIVES  ]]
	{
		id       = "revivalist",
		name     = "Revivalist",
		desc     = "Revive fallen allies.",
		icon     = "✨",
		category = "Healer",
		stat     = "revivesDone",
		tiers    = { 1, 5, 15, 35, 75, 150, 300, 600, 1200, 2500 },
		rewards  = {
			{ {"Merits", 75} },
			{ {"Merits", 250} },
			{ {"Merits", 750} },
			{ {"Merits", 2000},   {"Essence", 5} },
			{ {"Merits", 6000},   {"Essence", 12} },
			{ {"Merits", 15000},  {"Essence", 25} },
			{ {"Merits", 40000},  {"Essence", 50} },
			{ {"Merits", 90000},  {"Essence", 95} },
			{ {"Merits", 170000}, {"Essence", 155}, {"RespecToken", 1} },
			{ {"Merits", 250000}, {"Essence", 200}, {"RespecToken", 2} },
		},
	},

	-- ════════════════════════════════════════════════════════
	-- COLLECTION
	-- ════════════════════════════════════════════════════════

	--[[  MERITS COLLECTED — cross-rewards Essence to avoid feedback loop  ]]
	{
		id       = "merit_earner",
		name     = "Merit Earner",
		desc     = "Accumulate Merits (lifetime total).",
		icon     = "🪙",
		category = "Collection",
		stat     = "meritsCollected",
		tiers    = { 5000, 25000, 100000, 350000, 1000000, 3000000, 8000000, 20000000, 50000000, 150000000 },
		rewards  = {
			{ {"Essence", 2} },
			{ {"Essence", 5} },
			{ {"Essence", 10} },
			{ {"Essence", 18} },
			{ {"Essence", 30} },
			{ {"Essence", 45} },
			{ {"Essence", 65} },
			{ {"Essence", 85},  {"RespecToken", 1} },
			{ {"Essence", 105}, {"RespecToken", 1} },
			{ {"Essence", 125}, {"RespecToken", 2} },
		},
	},

	--[[  ESSENCE COLLECTED — cross-rewards Merits to avoid feedback loop  ]]
	{
		id       = "essence_hoarder",
		name     = "Essence Hoarder",
		desc     = "Accumulate Essence (lifetime total).",
		icon     = "💎",
		category = "Collection",
		stat     = "essenceEarned",
		tiers    = { 50, 150, 400, 1000, 2500, 6000, 15000, 35000, 80000, 200000 },
		rewards  = {
			{ {"Merits", 150} },
			{ {"Merits", 500} },
			{ {"Merits", 1500} },
			{ {"Merits", 5000} },
			{ {"Merits", 15000} },
			{ {"Merits", 40000} },
			{ {"Merits", 90000} },
			{ {"Merits", 175000} },
			{ {"Merits", 300000} },
			{ {"Merits", 500000} },
		},
	},

	-- ════════════════════════════════════════════════════════
	-- DEDICATION
	-- ════════════════════════════════════════════════════════

	--[[  HITS RECEIVED  ]]
	{
		id       = "battle_hardened",
		name     = "Battle Hardened",
		desc     = "Be struck by enemy attacks.",
		icon     = "🩸",
		category = "Dedication",
		stat     = "hitsReceived",
		tiers    = { 250, 1500, 7000, 30000, 100000, 300000, 850000, 2500000, 7000000, 20000000 },
		rewards  = {
			{ {"Merits", 15} },
			{ {"Merits", 50} },
			{ {"Merits", 150} },
			{ {"Merits", 400},    {"Essence", 1} },
			{ {"Merits", 1200},   {"Essence", 3} },
			{ {"Merits", 3500},   {"Essence", 6} },
			{ {"Merits", 9000},   {"Essence", 12} },
			{ {"Merits", 22000},  {"Essence", 25} },
			{ {"Merits", 50000},  {"Essence", 50},  {"RespecToken", 1} },
			{ {"Merits", 100000}, {"Essence", 90},  {"RespecToken", 1} },
		},
	},

	-- ════════════════════════════════════════════════════════
	-- WEAPON
	-- ════════════════════════════════════════════════════════

	--[[  MAX WEAPON LEVEL  ]]
	{
		id       = "arms_master",
		name     = "Arms Master",
		desc     = "Reach high weapon levels.",
		icon     = "⚡",
		category = "Weapon",
		stat     = "weaponLevelMax",
		tiers    = { 4, 8, 12, 16, 20, 24, 28, 32, 36, 40 },
		rewards  = {
			{ {"Merits", 200} },
			{ {"Merits", 600} },
			{ {"Merits", 1500},   {"Essence", 3} },
			{ {"Merits", 4000},   {"Essence", 8} },
			{ {"Merits", 10000},  {"Essence", 18} },
			{ {"Merits", 22000},  {"Essence", 35} },
			{ {"Merits", 50000},  {"Essence", 60} },
			{ {"Merits", 100000}, {"Essence", 100} },
			{ {"Merits", 175000}, {"Essence", 150}, {"RespecToken", 1} },
			{ {"Merits", 250000}, {"Essence", 200}, {"RespecToken", 2} },
		},
	},

	--[[  TALENT NODES ALLOCATED  ]]
	{
		id       = "talent_seeker",
		name     = "Talent Seeker",
		desc     = "Allocate talent nodes.",
		icon     = "🌟",
		category = "Weapon",
		stat     = "talentNodesAllocated",
		tiers    = { 3, 8, 15, 24, 35, 50, 70, 95, 125, 160 },
		rewards  = {
			{ {"Merits", 100} },
			{ {"Merits", 350} },
			{ {"Merits", 1000},   {"Essence", 2} },
			{ {"Merits", 2500},   {"Essence", 5} },
			{ {"Merits", 6000},   {"Essence", 12} },
			{ {"Merits", 15000},  {"Essence", 25} },
			{ {"Merits", 35000},  {"Essence", 50} },
			{ {"Merits", 75000},  {"Essence", 85} },
			{ {"Merits", 150000}, {"Essence", 135}, {"RespecToken", 1} },
			{ {"Merits", 250000}, {"Essence", 175}, {"RespecToken", 2} },
		},
	},

	-- ════════════════════════════════════════════════════════
	-- BOSS MEDALS
	-- ════════════════════════════════════════════════════════
	--[[
	    Each medal tracks total kills of a specific boss.
	    Boss IDs must match MobRegistry entries when added.
	    Rewards scale with boss difficulty (later bosses = more premium).
	    Medal tier 10 = ~300–400K Merits / 275–350 Essence / 3 Respecs.
	]]

	--[[  IRON WARDEN MEDAL  (Tier 1 boss, ~lv50 content)  ]]
	{
		id       = "medal_iron_warden",
		name     = "Iron Warden Medal",
		desc     = "Defeat the Iron Warden.",
		icon     = "🔩",
		category = "Medals",
		statFn   = function(s) return s.killsByMobId and (s.killsByMobId["iron_warden"] or 0) or 0 end,
		tiers    = { 1, 3, 7, 15, 30, 60, 110, 185, 300, 500 },
		rewards  = {
			{ {"Merits", 200} },
			{ {"Merits", 600},    {"Essence", 3} },
			{ {"Merits", 1800},   {"Essence", 8} },
			{ {"Merits", 5000},   {"Essence", 18} },
			{ {"Merits", 12000},  {"Essence", 35} },
			{ {"Merits", 28000},  {"Essence", 65} },
			{ {"Merits", 65000},  {"Essence", 110} },
			{ {"Merits", 130000}, {"Essence", 170}, {"RespecToken", 1} },
			{ {"Merits", 225000}, {"Essence", 230}, {"RespecToken", 2} },
			{ {"Merits", 300000}, {"Essence", 275}, {"RespecToken", 3} },
		},
	},

	--[[  VOID HARBINGER MEDAL  (Tier 2 boss, ~lv100 content)  ]]
	{
		id       = "medal_void_harbinger",
		name     = "Void Harbinger Medal",
		desc     = "Defeat the Void Harbinger.",
		icon     = "🌌",
		category = "Medals",
		statFn   = function(s) return s.killsByMobId and (s.killsByMobId["void_harbinger"] or 0) or 0 end,
		tiers    = { 1, 3, 7, 15, 30, 55, 100, 175, 280, 450 },
		rewards  = {
			{ {"Merits", 300} },
			{ {"Merits", 900},    {"Essence", 5} },
			{ {"Merits", 2500},   {"Essence", 12} },
			{ {"Merits", 7000},   {"Essence", 25} },
			{ {"Merits", 17000},  {"Essence", 48} },
			{ {"Merits", 40000},  {"Essence", 85} },
			{ {"Merits", 85000},  {"Essence", 140} },
			{ {"Merits", 170000}, {"Essence", 205}, {"RespecToken", 1} },
			{ {"Merits", 275000}, {"Essence", 265}, {"RespecToken", 2} },
			{ {"Merits", 350000}, {"Essence", 300}, {"RespecToken", 3} },
		},
	},

	--[[  PALE COLOSSUS MEDAL  (Tier 3 boss, ~lv150 content)  ]]
	{
		id       = "medal_pale_colossus",
		name     = "Pale Colossus Medal",
		desc     = "Defeat the Pale Colossus.",
		icon     = "🦴",
		category = "Medals",
		statFn   = function(s) return s.killsByMobId and (s.killsByMobId["pale_colossus"] or 0) or 0 end,
		tiers    = { 1, 3, 6, 12, 25, 50, 90, 155, 250, 400 },
		rewards  = {
			{ {"Merits", 400} },
			{ {"Merits", 1200},   {"Essence", 7} },
			{ {"Merits", 3500},   {"Essence", 16} },
			{ {"Merits", 9000},   {"Essence", 33} },
			{ {"Merits", 22000},  {"Essence", 62} },
			{ {"Merits", 52000},  {"Essence", 108} },
			{ {"Merits", 110000}, {"Essence", 170} },
			{ {"Merits", 210000}, {"Essence", 240}, {"RespecToken", 1} },
			{ {"Merits", 320000}, {"Essence", 300}, {"RespecToken", 2} },
			{ {"Merits", 375000}, {"Essence", 325}, {"RespecToken", 3} },
		},
	},

	--[[  ABYSSAL SOVEREIGN MEDAL  (Tier 4 boss, ~lv200 content)  ]]
	{
		id       = "medal_abyssal_sovereign",
		name     = "Abyssal Sovereign Medal",
		desc     = "Defeat the Abyssal Sovereign.",
		icon     = "👁",
		category = "Medals",
		statFn   = function(s) return s.killsByMobId and (s.killsByMobId["abyssal_sovereign"] or 0) or 0 end,
		tiers    = { 1, 3, 6, 12, 24, 45, 80, 135, 220, 350 },
		rewards  = {
			{ {"Merits", 500} },
			{ {"Merits", 1500},   {"Essence", 9} },
			{ {"Merits", 4500},   {"Essence", 20} },
			{ {"Merits", 12000},  {"Essence", 42} },
			{ {"Merits", 28000},  {"Essence", 78} },
			{ {"Merits", 65000},  {"Essence", 130} },
			{ {"Merits", 135000}, {"Essence", 200} },
			{ {"Merits", 250000}, {"Essence", 275}, {"RespecToken", 1} },
			{ {"Merits", 360000}, {"Essence", 330}, {"RespecToken", 2} },
			{ {"Merits", 400000}, {"Essence", 350}, {"RespecToken", 3} },
		},
	},

	-- ════════════════════════════════════════════════════════
	-- CAP MASTERY
	-- ════════════════════════════════════════════════════════
	--[[
	    These achievements are only earned by players who kill boss X
	    while still at or below the intended level cap for that boss.
	    They reward players who grind equipment/weapon levels at the cap
	    rather than rushing to higher levels.

	    stat keys: capMasteryKills.cap50 / .cap100 / .cap150 / .cap200
	    AchievementManager.OnKill gated by CapMasteryMap lookup + player.Level check.

	    Rewards scale up as the mastery content becomes harder to achieve.
	    Tier 10 = 350–500K Merits / 325–400 Essence / 3 Respecs.
	]]

	--[[  CAP 50 MASTERY  (kill iron_warden at level ≤ 50)  ]]
	{
		id       = "mastery_cap50",
		name     = "Iron Devotee",
		desc     = "Defeat the Iron Warden while at or below level 50.",
		icon     = "🔒",
		category = "Mastery",
		statFn   = function(s) return s.capMasteryKills and (s.capMasteryKills.cap50 or 0) or 0 end,
		tiers    = { 1, 3, 7, 15, 30, 60, 110, 185, 300, 500 },
		rewards  = {
			{ {"Merits", 500} },
			{ {"Merits", 2000},   {"Essence", 8} },
			{ {"Merits", 6000},   {"Essence", 20} },
			{ {"Merits", 15000},  {"Essence", 42} },
			{ {"Merits", 35000},  {"Essence", 80} },
			{ {"Merits", 75000},  {"Essence", 135} },
			{ {"Merits", 150000}, {"Essence", 200} },
			{ {"Merits", 250000}, {"Essence", 265}, {"RespecToken", 1} },
			{ {"Merits", 310000}, {"Essence", 305}, {"RespecToken", 2} },
			{ {"Merits", 350000}, {"Essence", 325}, {"RespecToken", 3} },
		},
	},

	--[[  CAP 100 MASTERY  (kill void_harbinger at level ≤ 100)  ]]
	{
		id       = "mastery_cap100",
		name     = "Void Devotee",
		desc     = "Defeat the Void Harbinger while at or below level 100.",
		icon     = "🌑",
		category = "Mastery",
		statFn   = function(s) return s.capMasteryKills and (s.capMasteryKills.cap100 or 0) or 0 end,
		tiers    = { 1, 3, 7, 15, 30, 55, 100, 175, 280, 450 },
		rewards  = {
			{ {"Merits", 700} },
			{ {"Merits", 2500},   {"Essence", 10} },
			{ {"Merits", 7500},   {"Essence", 26} },
			{ {"Merits", 20000},  {"Essence", 55} },
			{ {"Merits", 45000},  {"Essence", 100} },
			{ {"Merits", 95000},  {"Essence", 165} },
			{ {"Merits", 185000}, {"Essence", 235} },
			{ {"Merits", 285000}, {"Essence", 295}, {"RespecToken", 1} },
			{ {"Merits", 360000}, {"Essence", 345}, {"RespecToken", 2} },
			{ {"Merits", 400000}, {"Essence", 365}, {"RespecToken", 3} },
		},
	},

	--[[  CAP 150 MASTERY  (kill pale_colossus at level ≤ 150)  ]]
	{
		id       = "mastery_cap150",
		name     = "Colossus Devotee",
		desc     = "Defeat the Pale Colossus while at or below level 150.",
		icon     = "⛰",
		category = "Mastery",
		statFn   = function(s) return s.capMasteryKills and (s.capMasteryKills.cap150 or 0) or 0 end,
		tiers    = { 1, 3, 6, 12, 25, 50, 90, 155, 250, 400 },
		rewards  = {
			{ {"Merits", 900} },
			{ {"Merits", 3000},   {"Essence", 13} },
			{ {"Merits", 9000},   {"Essence", 33} },
			{ {"Merits", 24000},  {"Essence", 68} },
			{ {"Merits", 55000},  {"Essence", 120} },
			{ {"Merits", 115000}, {"Essence", 195} },
			{ {"Merits", 220000}, {"Essence", 265} },
			{ {"Merits", 325000}, {"Essence", 320}, {"RespecToken", 1} },
			{ {"Merits", 400000}, {"Essence", 368}, {"RespecToken", 2} },
			{ {"Merits", 450000}, {"Essence", 390}, {"RespecToken", 3} },
		},
	},

	--[[  CAP 200 MASTERY  (kill abyssal_sovereign at level ≤ 200)  ]]
	{
		id       = "mastery_cap200",
		name     = "Sovereign Devotee",
		desc     = "Defeat the Abyssal Sovereign while at or below level 200.",
		icon     = "👁‍🗨",
		category = "Mastery",
		statFn   = function(s) return s.capMasteryKills and (s.capMasteryKills.cap200 or 0) or 0 end,
		tiers    = { 1, 3, 6, 12, 24, 45, 80, 135, 220, 350 },
		rewards  = {
			{ {"Merits", 1200} },
			{ {"Merits", 4000},   {"Essence", 16} },
			{ {"Merits", 12000},  {"Essence", 40} },
			{ {"Merits", 30000},  {"Essence", 82} },
			{ {"Merits", 70000},  {"Essence", 145} },
			{ {"Merits", 145000}, {"Essence", 225} },
			{ {"Merits", 265000}, {"Essence", 300} },
			{ {"Merits", 375000}, {"Essence", 355}, {"RespecToken", 1} },
			{ {"Merits", 450000}, {"Essence", 390}, {"RespecToken", 2} },
			{ {"Merits", 500000}, {"Essence", 400}, {"RespecToken", 3} },
		},
	},
}

-- ── Cap Mastery Lookup ─────────────────────────────────────────────────────────
--[[
    AchievementManager.OnKill uses this to check whether a boss kill
    at the player's current level should increment a cap mastery stat.

    Format: bossId → { statKey = "cap##", levelCap = ## }
]]
AchievementConfig.CapMasteryMap = {
	["iron_warden"]       = { statKey = "cap50",  levelCap = 50  },
	["void_harbinger"]    = { statKey = "cap100", levelCap = 100 },
	["pale_colossus"]     = { statKey = "cap150", levelCap = 150 },
	["abyssal_sovereign"] = { statKey = "cap200", levelCap = 200 },
}

-- ── Quick-lookup by id ─────────────────────────────────────────────────────────
AchievementConfig.ById = {}
for _, ach in ipairs(AchievementConfig.Achievements) do
	AchievementConfig.ById[ach.id] = ach
end

-- ── Category list (insertion-ordered, deduped) ────────────────────────────────
-- AchievementsUI iterates this to build its tab bar.
do
	local seen = {}
	AchievementConfig.Categories = {}
	for _, ach in ipairs(AchievementConfig.Achievements) do
		if ach.category and not seen[ach.category] then
			seen[ach.category] = true
			table.insert(AchievementConfig.Categories, ach.category)
		end
	end
end

-- ── Helper: total tier count across all achievements ─────────────────────────
-- Used by AchievementsUI to display "X / Y tiers earned".
function AchievementConfig.TotalTiers()
	local count = 0
	for _, ach in ipairs(AchievementConfig.Achievements) do
		count = count + #ach.tiers
	end
	return count
end

-- ── Helper: return all achievements (full list, no filter) ───────────────────
-- Used by AchievementManager.Evaluate and any system iterating all achievements.
function AchievementConfig.GetAll()
	return AchievementConfig.Achievements
end

-- ── Helper: return achievements filtered to a category ───────────────────────
-- Passing nil or "All" returns the full list.
function AchievementConfig.GetByCategory(category)
	if not category or category == "All" then
		return AchievementConfig.Achievements
	end
	local result = {}
	for _, ach in ipairs(AchievementConfig.Achievements) do
		if ach.category == category then
			table.insert(result, ach)
		end
	end
	return result
end

-- ── Helper: resolve the current stat value for an achievement ────────────────
-- statsMap: the stats table from the server (AchievementManager.GetStats or equivalent).
-- Returns a number (0 if stats are unavailable or achievement has no stat mapping).
function AchievementConfig.GetStatValue(ach, statsMap)
	if not statsMap then return 0 end
	if ach.stat then
		return tonumber(statsMap[ach.stat]) or 0
	elseif ach.statFn then
		local ok, val = pcall(ach.statFn, statsMap)
		return (ok and tonumber(val)) or 0
	end
	return 0
end

return AchievementConfig
