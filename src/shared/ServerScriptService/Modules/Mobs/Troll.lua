-- ServerScriptService/Modules/Mobs/Troll

return {
	id = "Troll",
	name = "Troll",
	description = "A regenerating brute that hurls rocks.",

	mobTier = "miniboss",
	template = "Troll",
	element = "Water",	-- Earth attacks deal 2x; Fire attacks deal 0.5x

	health = 400,
	damage = 35,
	armor  = 8,
	knockbackResist = 0.4,

	speed = 4,
	attackRange = 5,
	attackCooldown = 2.5,
	perceptionRange = 40,

	animations = {
		attack = "rbxassetid://507768375",
	},
	attackDuration = 0.7,
	damageDelay = 0.35,

	-- Reuses GroundSlam from Ogre! (ThrowRock planned — uses GroundSlam for now)
	skills = { "GroundSlam", "Roar" },
	skillPriority = { "Roar", "GroundSlam" },  -- Roar for range, GroundSlam up close

	-- At 40% HP the Troll panics, pursuing more aggressively.
	behaviors = {
		{ type = "Enrage", hpThreshold = 0.40, speedBonus = 3, damageBonus = 1.4 },
	},
}