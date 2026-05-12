-- ServerScriptService/Modules/MobRegistry

local MobRegistry = {}

--[[
    ═══════════════════════════════════════════════════════════
    MOB REGISTRY
    ═══════════════════════════════════════════════════════════
    
    Auto-loads all mob definitions from Modules/Mobs/ folder.
    Each mob is a submodule returning a data table.
    
    Adding a new mob:
    1. Create Modules/Mobs/[MobName] ModuleScript
    2. Return mob data table
    3. Done! MobRegistry auto-loads it.
    
    ═══════════════════════════════════════════════════════════
    LEVEL SCALING
    
    Mobs scale with level using compound growth:
    ScaledStat = BaseStat * (1 + SCALE_PERCENT)^(level - 1)
    
    Level 1  = 1.00x (base)
    Level 10 = ~1.84x
    Level 20 = ~3.62x
    Level 50 = ~29.5x
    
    ═══════════════════════════════════════════════════════════
]]

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

-- Mob scaling model
-- Old (dev): exponential 7%/level.
-- New: power curve that stays sane into level 400–2000+.
-- Multiplier(level, exp) = ((level + OFFSET) / (1 + OFFSET)) ^ exp
local POWER_OFFSET = 9
local STAT_EXPONENTS = {
	health = 1.28,
	damage = 1.15,
	armor  = 1.05,   -- armor scales gently so penetration stays meaningful
}

-- Stats that scale with level
local SCALING_STATS = {
	"health",
	"damage",
	"armor",
	-- "speed" intentionally NOT scaled (mobs shouldn't get too fast)
}

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local registeredMobs = {}  -- { [mobId] = mobData }
local mobsByTier = {}      -- { [tier] = { mobId, mobId, ... } }
local initialized = false

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function MobRegistry.Init()
	if initialized then return end

	MobRegistry.LoadAllMobs()
	initialized = true

	local count = 0
	for _ in pairs(registeredMobs) do count = count + 1 end
end

function MobRegistry.LoadAllMobs()
	local MobsFolder = script.Parent:FindFirstChild("Mobs")

	if not MobsFolder then
		warn("[MobRegistry] Mobs folder not found! Creating empty folder...")
		MobsFolder = Instance.new("Folder")
		MobsFolder.Name = "Mobs"
		MobsFolder.Parent = script.Parent
		return
	end

	for _, mobModule in ipairs(MobsFolder:GetChildren()) do
		if mobModule:IsA("ModuleScript") then
			MobRegistry.LoadMob(mobModule)
		end
	end
end

function MobRegistry.LoadMob(mobModule)
	local success, mobData = pcall(function()
		return require(mobModule)
	end)

	if not success then
		warn("[MobRegistry] Failed to load mob:", mobModule.Name, "-", mobData)
		return
	end

	if not mobData.id then
		warn("[MobRegistry] Mob missing 'id':", mobModule.Name)
		return
	end

	-- Validate skills exist (after MobSkillRegistry is loaded)
	if mobData.skills then
		local MobSkillRegistry = require(script.Parent:WaitForChild("MobSkillRegistry"))
		local valid, missing = MobSkillRegistry.ValidateSkillList(mobData.skills)
		if not valid then
			warn("[MobRegistry] Mob", mobData.id, "references missing skills:", table.concat(missing, ", "))
		end
	end

	-- Register mob
	local mobId = mobData.id
	registeredMobs[mobId] = mobData

	-- Index by tier
	local tier = mobData.mobTier or "normal"
	if not mobsByTier[tier] then
		mobsByTier[tier] = {}
	end
	table.insert(mobsByTier[tier], mobId)

	local skillCount = mobData.skills and #mobData.skills or 0
	print("[MobRegistry] Loaded mob:", mobId, "(" .. tier .. ")", 
		skillCount > 0 and ("| " .. skillCount .. " skills") or "")
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS: Basic
-- ═══════════════════════════════════════════════════════════

function MobRegistry.GetMob(mobId)
	return registeredMobs[mobId]
end

function MobRegistry.GetMobIds()
	local ids = {}
	for id, _ in pairs(registeredMobs) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS: By Tier
-- ═══════════════════════════════════════════════════════════

function MobRegistry.GetMobTier(mobId)
	local mob = registeredMobs[mobId]
	return mob and mob.mobTier or "normal"
end

-- ═══════════════════════════════════════════════════════════
-- LEVEL SCALING
-- ═══════════════════════════════════════════════════════════

--[[
    Calculate the scaling multiplier for a given level.
    
    Formula: ((level + POWER_OFFSET) / (1 + POWER_OFFSET)) ^ exponent
    
    Level 1  = 1.0x (no scaling)
    Level 50 = ~12.3x (health) / ~9.2x (damage)
    Level 100 = ~33.7x / ~22.4x
    Level 400 = ~289x / ~153x
]]
function MobRegistry.GetLevelMultiplier(level, exponent)
	level = math.max(1, level or 1)
	exponent = exponent or 1.0
	local scaled = (level + POWER_OFFSET) / (1 + POWER_OFFSET)
	return scaled ^ exponent
end

--[[
    Get mob stats scaled for a specific level, with optional difficulty overrides.

    Returns a NEW table with scaled values (doesn't modify base).
    Non-scaling stats (like speed, attackRange) stay at base.

    difficultyOverrides (optional): { hpMult=N, damageMult=N, armorMult=N, speedBonus=N }
    These are post-multiplied after level scaling.
]]
function MobRegistry.GetScaledMob(mobId, level, difficultyOverrides)
	local baseMob = registeredMobs[mobId]
	if not baseMob then
		warn("[MobRegistry] Unknown mob:", mobId)
		return nil
	end

	level = math.max(1, level or 1)

	-- Create deep copy so mutations don't corrupt the base template
	local function deepCopy(tbl)
		if type(tbl) ~= "table" then return tbl end
		local copy = {}
		for k, v in pairs(tbl) do
			copy[k] = deepCopy(v)
		end
		return copy
	end

	local scaledMob = deepCopy(baseMob)

	-- Apply scaling to specific stats
	for _, statName in ipairs(SCALING_STATS) do
		if scaledMob[statName] then
			local exp = STAT_EXPONENTS[statName] or 1.0
			local mult = MobRegistry.GetLevelMultiplier(level, exp)
			scaledMob[statName] = math.floor(scaledMob[statName] * mult)
		end
	end

	-- Apply difficulty overrides (post-level-scaling)
	if difficultyOverrides then
		if difficultyOverrides.hpMult and scaledMob.health then
			scaledMob.health = math.floor(scaledMob.health * difficultyOverrides.hpMult)
		end
		if difficultyOverrides.damageMult and scaledMob.damage then
			scaledMob.damage = math.floor(scaledMob.damage * difficultyOverrides.damageMult)
		end
		if difficultyOverrides.armorMult and scaledMob.armor then
			scaledMob.armor = math.floor(scaledMob.armor * difficultyOverrides.armorMult)
		end
		if difficultyOverrides.speedBonus and scaledMob.speed then
			scaledMob.speed = scaledMob.speed + difficultyOverrides.speedBonus
		end
		-- Flat armor bonus from RunModifiers (card: ThickSkins)
		if difficultyOverrides.armorFlatBonus and scaledMob.armor then
			scaledMob.armor = scaledMob.armor + difficultyOverrides.armorFlatBonus
		end
	end

	-- Store level info
	scaledMob.level = level
	-- For debugging/UI: expose health multiplier (most relevant)
	scaledMob.multiplier = MobRegistry.GetLevelMultiplier(level, STAT_EXPONENTS.health)

	return scaledMob
end

return MobRegistry