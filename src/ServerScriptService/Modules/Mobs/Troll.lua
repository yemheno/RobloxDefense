-- ServerScriptService/Modules/Mobs/Troll

return {
	id = "Troll",
	name = "Troll",
	description = "A regenerating brute that hurls rocks.",

	mobTier = "miniboss",
	template = "MobTemplate",
	element = "Water",	-- Earth attacks deal 2x; Wood attacks deal 0.5x

	health = 400,
	damage = 35,

	speed = 4,
	attackRange = 5,
	attackCooldown = 2.5,
	perceptionRange = 40,

	animations = {
		attack = "rbxassetid://507768375",
	},
	attackDuration = 0.7,
	damageDelay = 0.35,

	-- Reuses GroundSlam from Ogre! Plus unique ThrowRock
	skills = { "GroundSlam", "ThrowRock" },
	skillPriority = { "ThrowRock", "GroundSlam" },  -- Prefers throwing at range

	-- At 40% HP the Troll panics, pursuing more aggressively.
	behaviors = {
		{ type = "Enrage", hpThreshold = 0.40, speedBonus = 3, damageBonus = 1.4 },
	},

	-- Future: special properties
	-- passives = { "Regeneration" },
}