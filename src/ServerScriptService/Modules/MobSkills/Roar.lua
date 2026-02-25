-- ServerScriptService/Modules/MobSkills/Roar

return {
	id = "Roar",
	name = "Intimidating Roar",
	description = "Let out a terrifying roar that slows all nearby enemies.",
	skillType = "AoE",

	cooldown = 20,
	startOnCooldown = true,

	targeting = {
		minRange = 0,
		maxRange = 999,
		healthThreshold = 50,  -- Only below 50% HP
	},

	animation = "rbxassetid://507770677",
	animationDuration = 1.2,

	damageDelay = 0.8,
	damageWindow = 0.2,

	damageMultiplier = 0,  -- No damage

	shape = "Circle",
	shapeParams = {
		range = 20,
	},

	effects = {
		{
			type = "Slow",
			duration = 3,
			amount = 50,
		},
	},

	visual = {
		type = "Roar",
		warningDuration = 0.8,
		impactDuration = 0.5,
		color = Color3.fromRGB(255, 100, 100),
		warningColor = Color3.fromRGB(255, 200, 100),
	},
}