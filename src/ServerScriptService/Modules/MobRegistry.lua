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

local SCALE_PERCENT = 0.07  -- 7% increase per level

-- Stats that scale with level
local SCALING_STATS = {
	"health",
	"damage",
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
	print("[MobRegistry] Initialized -", count, "mobs loaded")
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

function MobRegistry.GetAllMobs()
	return registeredMobs
end

function MobRegistry.GetMobIds()
	local ids = {}
	for id, _ in pairs(registeredMobs) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function MobRegistry.IsValidMob(mobId)
	return registeredMobs[mobId] ~= nil
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS: By Tier
-- ═══════════════════════════════════════════════════════════

function MobRegistry.GetMobsByTier(tier)
	return mobsByTier[tier] or {}
end

function MobRegistry.GetMobTier(mobId)
	local mob = registeredMobs[mobId]
	return mob and mob.mobTier or "normal"
end

function MobRegistry.IsBoss(mobId)
	return MobRegistry.GetMobTier(mobId) == "boss"
end

function MobRegistry.IsMiniboss(mobId)
	return MobRegistry.GetMobTier(mobId) == "miniboss"
end

function MobRegistry.IsBossOrMiniboss(mobId)
	local tier = MobRegistry.GetMobTier(mobId)
	return tier == "boss" or tier == "miniboss"
end

-- ═══════════════════════════════════════════════════════════
-- LEVEL SCALING
-- ═══════════════════════════════════════════════════════════

--[[
    Calculate the scaling multiplier for a given level.
    
    Formula: (1 + SCALE_PERCENT)^(level - 1)
    
    Level 1 = 1.0x (no scaling)
    Level 2 = 1.07x
    Level 10 = ~1.84x
    Level 20 = ~3.62x
]]
function MobRegistry.GetLevelMultiplier(level)
	level = math.max(1, level or 1)
	return (1 + SCALE_PERCENT) ^ (level - 1)
end

--[[
    Get mob stats scaled for a specific level.
    
    Returns a NEW table with scaled values (doesn't modify base).
    Non-scaling stats (like speed, attackRange) stay at base.
]]
function MobRegistry.GetScaledMob(mobId, level)
	local baseMob = registeredMobs[mobId]
	if not baseMob then
		warn("[MobRegistry] Unknown mob:", mobId)
		return nil
	end

	level = math.max(1, level or 1)
	local multiplier = MobRegistry.GetLevelMultiplier(level)

	-- Create scaled copy
	local scaledMob = {}
	for key, value in pairs(baseMob) do
		scaledMob[key] = value
	end

	-- Apply scaling to specific stats
	for _, statName in ipairs(SCALING_STATS) do
		if scaledMob[statName] then
			scaledMob[statName] = math.floor(scaledMob[statName] * multiplier)
		end
	end

	-- Store level info
	scaledMob.level = level
	scaledMob.multiplier = multiplier

	return scaledMob
end

--[[
    Get a specific stat scaled for level.
    Useful when you only need one value.
]]
function MobRegistry.GetScaledStat(mobId, statName, level)
	local baseMob = registeredMobs[mobId]
	if not baseMob then return nil end

	local baseValue = baseMob[statName]
	if not baseValue then return nil end

	-- Check if this stat should scale
	local shouldScale = false
	for _, scalingStat in ipairs(SCALING_STATS) do
		if scalingStat == statName then
			shouldScale = true
			break
		end
	end

	if shouldScale then
		local multiplier = MobRegistry.GetLevelMultiplier(level)
		return math.floor(baseValue * multiplier)
	else
		return baseValue
	end
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function MobRegistry.GetDebugInfo()
	local info = {
		totalMobs = 0,
		byTier = {},
	}

	for _, _ in pairs(registeredMobs) do
		info.totalMobs = info.totalMobs + 1
	end

	for tier, mobs in pairs(mobsByTier) do
		info.byTier[tier] = #mobs
	end

	return info
end

-- Preview scaling for a mob
function MobRegistry.PreviewScaling(mobId, maxLevel)
	maxLevel = maxLevel or 50
	local baseMob = registeredMobs[mobId]
	if not baseMob then return nil end

	local preview = {}
	for level = 1, maxLevel, 10 do
		local scaled = MobRegistry.GetScaledMob(mobId, level)
		preview[level] = {
			health = scaled.health,
			damage = scaled.damage,
			multiplier = string.format("%.2fx", scaled.multiplier),
		}
	end

	return preview
end

return MobRegistry