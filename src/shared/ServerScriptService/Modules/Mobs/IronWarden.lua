-- ServerScriptService/Modules/Mobs/IronWarden
--[[
    §AGX/X28: first boss-tier mob (CentralBoss place only).

    The id MUST stay "iron_warden": AchievementConfig keys the Tier-1 boss
    medal (medal_iron_warden) and the level-50 cap mastery (mastery_cap50,
    via CapMasteryMap) on this exact MobId. boss_slayer counts any
    mobTier == "boss" kill.

    Spawn pools: LaneDefense (WaveConfig) and HordeMode (HordeModeSpawner
    PHASES) pick mobs from explicit, hand-written weight tables (Zombie /
    Troll / Ogre). Nothing enumerates MobRegistry by tier, so a boss-tier
    mob is never selected there. Only BossEncounter (CentralBoss) spawns it.

    VISUALS: `template = "IronWarden"` — drop a Model with that name into
    ServerStorage/Models/Mobs (it needs a Humanoid + HumanoidRootPart, like
    every mob template) and BossEncounter uses it. Until then the runtime
    `placeholderRig` block golem below is built instead.

    TUNING: all fight knobs live in this file —
      • base stats (health / damage / armor / speed / attackCooldown)
      • `boss`     — player-count HP scaling, level offset, frenzy opt-out
      • `phases`   — HP thresholds, skills, speed / cadence / damage, adds
    Difficulty (DifficultyConfig) and level (party anchor) scaling are
    applied on top by MobRegistry.GetScaledMob, like every other mob.
]]

return {
	id = "iron_warden",
	name = "Iron Warden",
	description = "An ancient iron sentinel that guards the central arena.",

	mobTier = "boss",
	template = "IronWarden",   -- optional real model; see header
	element = "None",          -- untyped: every element deals 1x

	-- Base stats (level 1, Normal, 1 player). ~8x an Ogre's HP.
	health = 4000,
	damage = 30,
	armor  = 10,
	knockbackResist = 1.0,     -- immune to knockback / pull

	speed = 8,
	attackRange = 11,          -- measured from the (large) root part
	attackCooldown = 2.4,
	perceptionRange = 200,     -- informational: the place uses horde targeting

	-- No animations: the placeholder rig has no Motor6D joints.
	animations = {},
	attackDuration = 0.8,
	damageDelay = 0.5,

	-- Every skill any phase uses must be listed here (MobAI resolves them
	-- at registration). Which ones are ACTIVE is decided per phase.
	skills = { "GroundSlam", "Roar" },
	skillPriority = { "GroundSlam" },

	behaviors = {
		{ type = "BossPhases" },
	},

	-- ── Boss-only knobs (read by BossEncounter / BossPhases) ────────────
	boss = {
		-- MaxHP × (1 + hpPerExtraPlayer × (players − 1)). 4 players = 3.25x.
		hpPerExtraPlayer = 0.75,
		-- Boss level = highest player level + levelOffset (min 1).
		levelOffset = 0,
		-- Opt out of MobAI's per-mob alive-time speed ramp (§FRENZY1);
		-- the boss's pace comes from its phases instead.
		disableFrenzy = true,
	},

	-- Built at runtime when no "IronWarden" template exists.
	placeholderRig = {
		scale       = 3,
		bodyColor   = Color3.fromRGB(88, 92, 110),
		accentColor = Color3.fromRGB(255, 140, 40),
		label       = "IRON WARDEN\nBOSS (placeholder)",
	},

	--[[
	    Phases, in order. A phase starts when HP fraction <= enterAtHp and
	    never reverts (healing does not drop the boss back a phase).
	      skills             priority order of ACTIVE skills (ids from `skills`)
	      skillTuning        per-skill field overrides for this phase only
	                         (shallow; a `targeting` table replaces the whole
	                         default targeting table)
	      firstCastDelay     seconds before a skill unlocked by this phase can
	                         first fire (default 2)
	      attackCooldownMult × base attackCooldown  (lower = faster swings)
	      speedBonus         + WalkSpeed over base speed
	      damageMult         mob damage multiplier (basic attacks + skills)
	      announce           banner text sent to clients on phase entry
	      summon             adds (BossEncounter): every N s, spawn `count`
	                         mobs picked from `pool` (weights), capped at
	                         `maxAlive` living adds, `radius` studs from boss
	]]
	phases = {
		{
			name = "Awakening",
			enterAtHp = 1.0,
			skills = { "GroundSlam" },
			attackCooldownMult = 1.0,
			speedBonus = 0,
			damageMult = 1.0,
			announce = "The Iron Warden awakens!",
		},
		{
			name = "Enraged",
			enterAtHp = 0.66,
			skills = { "Roar", "GroundSlam" },
			skillTuning = {
				-- Stock Roar only fires below 50% HP; the boss roars from 66%.
				Roar = { targeting = { minRange = 0, maxRange = 999 }, cooldown = 16 },
			},
			firstCastDelay = 1.0,
			attackCooldownMult = 0.6,
			speedBonus = 3,
			damageMult = 1.15,
			announce = "The Iron Warden is ENRAGED!",
		},
		{
			name = "Desperation",
			enterAtHp = 0.33,
			skills = { "Roar", "GroundSlam" },
			skillTuning = {
				Roar       = { targeting = { minRange = 0, maxRange = 999 }, cooldown = 16 },
				GroundSlam = { cooldown = 8 },
			},
			attackCooldownMult = 0.5,
			speedBonus = 3,
			damageMult = 1.25,
			announce = "The Iron Warden calls for aid!",
			summon = {
				every     = 20,
				firstDelay = 1.5,
				count     = 2,
				maxAlive  = 4,
				pool      = { Troll = 1, Ogre = 1 },
				radius    = 18,
			},
		},
	},
}
