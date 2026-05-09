-- ServerScriptService/Modules/MobSkills/GroundSlam

return {
	id = "GroundSlam",
	name = "Ground Slam",
	description = "Slam the ground, damaging and stunning nearby enemies.",
	skillType = "AoE",

	-- Cooldown
	cooldown = 12,
	startOnCooldown = true,

	-- Targeting (AI decision-making)
	targeting = {
		minRange = 0,
		maxRange = 10,
		healthThreshold = nil,
	},

	-- Animation
	animation = "rbxassetid://507770677",
	animationDuration = 1.0,

	-- Damage timing
	damageDelay = 0.6,        -- Visual warning time before damage
	damageWindow = 0.3,       -- How long clients have to report hits

	-- Damage
	damageMultiplier = 2.0,

	-- Area of Effect
	shape = "Circle",
	shapeParams = {
		range = 12,
	},

	-- Effects
	effects = {
		{
			type = "Stun",
			duration = 1.5,
		},
	},

	-- Client Visuals
	visual = {
		type = "GroundSlam",
		warningDuration = 0.6,  -- Show warning circle before hit
		impactDuration = 0.3,   -- Impact visual duration
		color = Color3.fromRGB(139, 90, 43),
		warningColor = Color3.fromRGB(255, 100, 100),
	},
}