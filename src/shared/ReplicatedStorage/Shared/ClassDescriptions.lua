-- ReplicatedStorage/Shared/ClassDescriptions.lua
--[[
    Read-only display data accessible by both server and client.
    Contains class descriptions and skill summaries for UI panels.

    Keep this in sync with ClassConfig and ClassSkills when adding new classes.
]]

return {
	Aegis = {
		description = "A sturdy frontline protector with high health and defense. "
			.. "Uses Determination to power devastating defensive abilities.",
		role        = "Vanguard",
		resource    = "Determination",
		playstyle   = "Close-range melee — wade into the fray and shield your team.",
		skills = {
			{ slot = 1, name = "Shield Boomerang",  description = "Hurl your shield forward, damaging enemies on the way out and back." },
			{ slot = 2, name = "Taunt",              description = "Stomp the ground, pulling nearby enemies and forcing distant ones to target you." },
			{ slot = 3, name = "Sundering Strikes",  description = "Rend your foes with a vicious strike. Each stack shreds armor and applies a bleed (max 5)." },
			{ slot = 4, name = "Battle Beast ★",     description = "Channel all your Determination into an unbreakable defensive stance, shielding yourself and every ally behind you." },
		},
	},

	Arcanist = {
		description = "A powerful spellcaster who bends elemental forces to obliterate foes. "
			.. "Channels Aether to fuel area-of-effect devastation.",
		role        = "Spellcaster",
		resource    = "Aether",
		playstyle   = "Mid-range AoE — control zones and melt groups with arcane fire.",
		skills = {
			{ slot = 1, name = "Arcane Beam",   description = "Fire a beam of concentrated arcane energy in a straight line, scorching all enemies in its path." },
			{ slot = 2, name = "Frost Bind",    description = "Conjure a glacial field at the target location that slows enemies and deals sustained frost damage." },
			{ slot = 3, name = "Arcane Surge",  description = "Channel all arcane power into a devastating explosion that obliterates everything in front of you." },
			{ slot = 4, name = "Meteorite ★",   description = "Call down a cataclysmic meteor that strikes with fire and earth, leaving shattered foes vulnerable." },
		},
	},

	Hunter = {
		description = "A deadly marksman who fells enemies with precision and speed. "
			.. "Manages Focus to unleash critical precision strikes.",
		role        = "Ranged DPS",
		resource    = "Focus",
		playstyle   = "Long-range pierce — stay mobile and pick off targets with precision.",
		skills = {
			{ slot = 1, name = "Swift Arrow",     description = "Fire a piercing arrow in an instant. Critical hits reward extra Focus." },
			{ slot = 2, name = "Barrage",         description = "Unleash a rapid volley of five arrows. Each successive hit on the same target deals escalating damage." },
			{ slot = 3, name = "Rain of Arrows",  description = "Lock on to a target area and unleash a volley of arrows that fall over a wide zone." },
			{ slot = 4, name = "Eagle Eye ★",     description = "Enter a hyper-focused state. Critical hits become devastating, but attack speed is reduced." },
		},
	},

	LifeSteward = {
		description = "A devoted healer who channels nature's essence to restore allies. "
			.. "Generates Life Energy faster when wounded allies are nearby.",
		role        = "Healer",
		resource    = "Life Energy",
		playstyle   = "Support — stay near your team, heal the injured, and cleanse ailments.",
		skills = {
			{ slot = 1, name = "Mending Touch",   description = "Channel nature's essence to restore vitality to the most wounded ally in range." },
			{ slot = 2, name = "Verdant Bloom",    description = "Call upon the forest's power to heal all nearby allies and leave a lingering regeneration." },
			{ slot = 3, name = "Nature's Purge",  description = "Purify the battlefield with nature's cleansing wind, removing harmful effects from all allies." },
			{ slot = 4, name = "Genesis ★",        description = "Channel the primal force of nature to pull a fallen ally back from the brink." },
		},
	},
}
