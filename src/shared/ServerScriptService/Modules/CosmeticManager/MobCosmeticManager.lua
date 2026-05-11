-- ServerScriptService/Modules/CosmeticManager/MobCosmeticManager.lua
--[[
    MobCosmeticManager
    ==================
    Sub-module of CosmeticManager. Handles mob visual variant application.
    
    Mobs are R6-ish templates stored in ServerStorage.Models. Rather than
    welding accessories (expensive at scale), we recolour the existing
    BaseParts and optionally add a simple glow to give variety.

    Usage:
        MobCosmeticManager.ApplyVariant(mobModel, "Zombie", "decayed")
    This will look up CosmeticConfig.MobVariants.Zombie.decayed and
    apply color / material / features to every BasePart in the model.
]]

local MobCosmeticManager = {}

-- Dependencies injected via Init()
local CosmeticConfig = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function MobCosmeticManager.Init(deps)
	CosmeticConfig = deps.CosmeticConfig
end

-- ═══════════════════════════════════════════════════════════
-- VARIANT APPLICATION
-- ═══════════════════════════════════════════════════════════

--- Apply a visual variant to a mob model.
--- @param mob Model – the mob character model (already cloned)
--- @param mobId string – e.g. "Zombie", "Ogre"
--- @param variantName string|nil – e.g. "decayed", "mossy". nil = random
function MobCosmeticManager.ApplyVariant(mob, mobId, variantName)
	if not CosmeticConfig then
		warn("[MobCosmeticManager] Not initialised – CosmeticConfig missing")
		return
	end

	-- Resolve variant config
	local variant = nil

	if variantName then
		variant = CosmeticConfig.GetMobVariant(mobId, variantName)
	end

	-- If nil or not found, pick a random variant
	if not variant then
		variant = MobCosmeticManager.PickRandomVariant(mobId)
	end

	if not variant then return end -- no variants configured for this mob

	-- Apply
	MobCosmeticManager.RecolourModel(mob, variant)

	if variant.features then
		MobCosmeticManager.ApplyFeatures(mob, variant.features)
	end

	-- Tag with the variant for debugging / networking
	mob:SetAttribute("CosmeticVariant", variantName or "random")
end

--- Pick a random variant from the mob's variant table.
function MobCosmeticManager.PickRandomVariant(mobId)
	local mobVariants = CosmeticConfig.MobVariants[mobId]
	if not mobVariants then return nil end

	local keys = {}
	for name, _ in pairs(mobVariants) do
		table.insert(keys, name)
	end

	if #keys == 0 then return nil end
	local pick = keys[math.random(1, #keys)]
	return mobVariants[pick]
end

--- Recolour all BaseParts in a model.
function MobCosmeticManager.RecolourModel(mob, variant)
	local color    = variant.bodyColor
	local material = variant.material

	for _, part in ipairs(mob:GetDescendants()) do
		if part:IsA("BasePart") then
			if color then
				part.Color = color
			end
			if material then
				part.Material = material
			end
		end
	end
end

--- Apply optional feature effects (glow, fire, sparkles, etc.).
function MobCosmeticManager.ApplyFeatures(mob, features)
	local primaryPart = mob.PrimaryPart or mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Torso")
	if not primaryPart then return end

	for feature, enabled in pairs(features) do
		if not enabled then continue end

		if feature == "glow" then
			local light = Instance.new("PointLight")
			light.Name = "CosmeticGlow"
			light.Color = Color3.new(0.6, 1, 0.6)
			light.Brightness = 0.8
			light.Range = 8
			light.Parent = primaryPart

		elseif feature == "fire" then
			local fire = Instance.new("Fire")
			fire.Name = "CosmeticFire"
			fire.Size = 3
			fire.Heat = 5
			fire.Parent = primaryPart

		elseif feature == "sparkles" then
			local sparkles = Instance.new("Sparkles")
			sparkles.Name = "CosmeticSparkles"
			sparkles.SparkleColor = Color3.new(0.9, 0.3, 0.9)
			sparkles.Parent = primaryPart

		elseif feature == "dark_aura" then
			local particles = Instance.new("ParticleEmitter")
			particles.Name = "CosmeticAura"
			particles.Color = ColorSequence.new(Color3.new(0.2, 0, 0.3))
			particles.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(1, 0),
			})
			particles.Lifetime = NumberRange.new(0.5, 1)
			particles.Rate = 20
			particles.Speed = NumberRange.new(0.5, 1.5)
			particles.Parent = primaryPart
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP  (optional: remove cosmetic effects from a mob)
-- ═══════════════════════════════════════════════════════════

function MobCosmeticManager.CleanupMob(mob)
	for _, desc in ipairs(mob:GetDescendants()) do
		if desc.Name:sub(1, 8) == "Cosmetic" then
			desc:Destroy()
		end
	end
end

return MobCosmeticManager
