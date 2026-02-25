-- ServerScriptService/Modules/MobSkillRegistry

local MobSkillRegistry = {}

--[[
    ═══════════════════════════════════════════════════════════
    MOB SKILL REGISTRY
    ═══════════════════════════════════════════════════════════
    
    Auto-loads all mob skill definitions from Modules/MobSkills/
    Skills are REUSABLE across multiple mobs.
    
    Adding a new skill:
    1. Create Modules/MobSkills/[SkillName] ModuleScript
    2. Return skill data table
    3. Any mob can now reference it by ID!
    
    ═══════════════════════════════════════════════════════════
]]

local registeredSkills = {}
local skillsByType = {}
local initialized = false

function MobSkillRegistry.Init()
	if initialized then return end

	MobSkillRegistry.LoadAllSkills()
	initialized = true

	local count = 0
	for _ in pairs(registeredSkills) do count = count + 1 end
	print("[MobSkillRegistry] Initialized -", count, "skills loaded")
end

function MobSkillRegistry.LoadAllSkills()
	local SkillsFolder = script.Parent:FindFirstChild("MobSkills")

	if not SkillsFolder then
		warn("[MobSkillRegistry] MobSkills folder not found! Creating...")
		SkillsFolder = Instance.new("Folder")
		SkillsFolder.Name = "MobSkills"
		SkillsFolder.Parent = script.Parent
		return
	end

	for _, skillModule in ipairs(SkillsFolder:GetChildren()) do
		if skillModule:IsA("ModuleScript") then
			MobSkillRegistry.LoadSkill(skillModule)
		end
	end
end

function MobSkillRegistry.LoadSkill(skillModule)
	local success, skillData = pcall(function()
		return require(skillModule)
	end)

	if not success then
		warn("[MobSkillRegistry] Failed to load skill:", skillModule.Name, "-", skillData)
		return
	end

	if not skillData.id then
		warn("[MobSkillRegistry] Skill missing 'id':", skillModule.Name)
		return
	end

	local skillId = skillData.id
	registeredSkills[skillId] = skillData

	local skillType = skillData.skillType or "Damage"
	if not skillsByType[skillType] then
		skillsByType[skillType] = {}
	end
	table.insert(skillsByType[skillType], skillId)

	print("[MobSkillRegistry] Loaded skill:", skillId, "(" .. skillType .. ")")
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS
-- ═══════════════════════════════════════════════════════════

function MobSkillRegistry.GetSkill(skillId)
	return registeredSkills[skillId]
end

function MobSkillRegistry.GetAllSkills()
	return registeredSkills
end

function MobSkillRegistry.GetSkillIds()
	local ids = {}
	for id, _ in pairs(registeredSkills) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function MobSkillRegistry.IsValidSkill(skillId)
	return registeredSkills[skillId] ~= nil
end

function MobSkillRegistry.GetSkillsByType(skillType)
	return skillsByType[skillType] or {}
end

function MobSkillRegistry.ResolveSkills(skillIds)
	if not skillIds then return {} end

	local resolved = {}
	for _, skillId in ipairs(skillIds) do
		local skill = registeredSkills[skillId]
		if skill then
			resolved[skillId] = skill
		else
			warn("[MobSkillRegistry] Unknown skill:", skillId)
		end
	end
	return resolved
end

function MobSkillRegistry.ValidateSkillList(skillIds)
	if not skillIds then return true, {} end

	local missing = {}
	for _, skillId in ipairs(skillIds) do
		if not registeredSkills[skillId] then
			table.insert(missing, skillId)
		end
	end

	return #missing == 0, missing
end

function MobSkillRegistry.GetDebugInfo()
	local info = {
		totalSkills = 0,
		byType = {},
	}

	for _, _ in pairs(registeredSkills) do
		info.totalSkills = info.totalSkills + 1
	end

	for skillType, skills in pairs(skillsByType) do
		info.byType[skillType] = #skills
	end

	return info
end

return MobSkillRegistry