-- ServerScriptService/Modules/Mobs/Zombie

return {
	id = "Zombie",
	name = "Zombie",
	description = "A slow, shambling undead creature.",

	mobTier = "normal",
	template = "Zombie",
	element = "Earth",	-- Wood attacks deal 2x; Water attacks deal 0.5x

	-- Base Stats
	health = 100,
	damage = 10,
	armor  = 2,
	knockbackResist = 0,

	-- Fixed Stats
	speed = 5,
	attackRange = 4,
	attackCooldown = 1.5,
	perceptionRange = 25,

	-- Basic Attack Animation
	animations = {
		attack = "rbxassetid://507768375",
	},
	attackDuration = 0.5,
	damageDelay = 0.25,

	-- No skills
	skills = nil,
	skillPriority = nil,
}