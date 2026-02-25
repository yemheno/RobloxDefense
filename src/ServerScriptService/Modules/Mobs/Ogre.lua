-- ServerScriptService/Modules/Mobs/Ogre

return {
	id = "Ogre",
	name = "Ogre",
	description = "A massive, powerful miniboss with devastating attacks.",

	mobTier = "miniboss",
	template = "MobTemplate",
	element = "Fire",	-- Water attacks deal 2x; Earth attacks deal 0.5x

	health = 500,
	damage = 40,

	speed = 3,
	attackRange = 6,
	attackCooldown = 3.0,
	perceptionRange = 35,

	animations = {
		attack = "rbxassetid://507768375",
	},
	attackDuration = 0.8,
	damageDelay = 0.4,

	-- Just list skill IDs! Clean and simple.
	skills = { "GroundSlam", "Roar" },
	skillPriority = { "GroundSlam", "Roar" },

	-- At 30% HP the Ogre enters a rage, moving faster and hitting harder.
	behaviors = {
		{ type = "Enrage", hpThreshold = 0.30, speedBonus = 4, damageBonus = 1.6 },
	},
}