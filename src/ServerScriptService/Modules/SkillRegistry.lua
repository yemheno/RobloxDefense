-- ServerScriptService/Modules/SkillRegistry

local SkillRegistry = {}

-- Auto-loaded class skill modules
local ClassSkillModules = {}  -- ["Aegis"] = AegisSkills module

-- Cache for quick lookups
local SkillCache = {}         -- [skillId] = { skill = data, class = "Aegis" }

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION (Auto-loads from ClassSkills folder)
-- ═══════════════════════════════════════════════════════════

function SkillRegistry.Init()
	local ClassSkillsFolder = script.Parent:FindFirstChild("ClassSkills")

	if not ClassSkillsFolder then
		warn("[SkillRegistry] ClassSkills folder not found!")
		return
	end

	-- Load all class skill modules (except BaseSkills)
	for _, module in ipairs(ClassSkillsFolder:GetChildren()) do
		if module:IsA("ModuleScript") and module.Name ~= "BaseSkills" then
			local success, result = pcall(function()
				return require(module)
			end)

			if success and result.CLASS then
				local className = result.CLASS
				ClassSkillModules[className] = result

				-- Cache all skills from this class
				SkillRegistry.CacheClassSkills(className, result)

				print("[SkillRegistry] Loaded:", className, "(" .. result.GetSkillCount() .. " skills)")

			elseif success and result.PLACEHOLDER then
				print("[SkillRegistry] Skipped placeholder:", module.Name)

			elseif success then
				warn("[SkillRegistry] Module missing CLASS identifier:", module.Name)
			else
				warn("[SkillRegistry] Failed to load:", module.Name, "-", result)
			end
		end
	end

	print("[SkillRegistry] Initialized -", SkillRegistry.GetTotalSkillCount(), "total skills")
end

function SkillRegistry.CacheClassSkills(className, classModule)
	local skills = classModule.GetAllSkills()

	for slot, skill in pairs(skills) do
		SkillCache[skill.id] = {
			skill = skill,
			class = className,
			slot = slot,
		}
	end
end

-- ═══════════════════════════════════════════════════════════
-- SKILL GETTERS
-- ═══════════════════════════════════════════════════════════

function SkillRegistry.GetSkill(skillId)
	local cached = SkillCache[skillId]
	return cached and cached.skill or nil
end

function SkillRegistry.GetSkillWithMeta(skillId)
	return SkillCache[skillId]  -- Returns { skill, class, slot }
end

function SkillRegistry.GetSkillBySlot(className, slot)
	local classModule = ClassSkillModules[className]
	if not classModule then return nil end

	return classModule.GetSkillBySlot(slot)
end

-- ═══════════════════════════════════════════════════════════
-- CLASS GETTERS
-- ═══════════════════════════════════════════════════════════

function SkillRegistry.GetClassSkills(className)
	local classModule = ClassSkillModules[className]
	if not classModule then return {} end

	return classModule.GetAllSkills()
end

function SkillRegistry.GetClassSkillIds(className)
	local classModule = ClassSkillModules[className]
	if not classModule then return {} end

	local ids = {}
	for slot, skill in pairs(classModule.GetAllSkills()) do
		ids[slot] = skill.id
	end

	return ids
end

function SkillRegistry.GetClassModule(className)
	return ClassSkillModules[className]
end

function SkillRegistry.GetAllClassNames()
	local names = {}
	for className, _ in pairs(ClassSkillModules) do
		table.insert(names, className)
	end
	return names
end

-- ═══════════════════════════════════════════════════════════
-- VALIDATION
-- ═══════════════════════════════════════════════════════════

function SkillRegistry.IsValidSkill(skillId)
	return SkillCache[skillId] ~= nil
end

function SkillRegistry.IsSkillForClass(skillId, className)
	local cached = SkillCache[skillId]
	return cached and cached.class == className
end

function SkillRegistry.HasClass(className)
	return ClassSkillModules[className] ~= nil
end

-- ═══════════════════════════════════════════════════════════
-- STATS
-- ═══════════════════════════════════════════════════════════

function SkillRegistry.GetTotalSkillCount()
	local count = 0
	for _ in pairs(SkillCache) do
		count = count + 1
	end
	return count
end

function SkillRegistry.GetClassCount()
	local count = 0
	for _ in pairs(ClassSkillModules) do
		count = count + 1
	end
	return count
end

-- ═══════════════════════════════════════════════════════════
-- EXECUTION (Routes to class module)
-- ═══════════════════════════════════════════════════════════

function SkillRegistry.ExecuteSkill(player, skill, inputData)
	local cached = SkillCache[skill.id]
	if not cached then
		warn("[SkillRegistry] Skill not found:", skill.id)
		return false
	end

	local classModule = ClassSkillModules[cached.class]
	if not classModule or not classModule.Execute then
		warn("[SkillRegistry] Class module missing Execute:", cached.class)
		return false
	end

	return classModule.Execute(player, skill, inputData)
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function SkillRegistry.GetDebugInfo()
	local classInfo = {}

	for className, classModule in pairs(ClassSkillModules) do
		if classModule.GetDebugInfo then
			classInfo[className] = classModule.GetDebugInfo()
		else
			classInfo[className] = { skillCount = classModule.GetSkillCount() }
		end
	end

	return {
		totalSkills = SkillRegistry.GetTotalSkillCount(),
		totalClasses = SkillRegistry.GetClassCount(),
		classes = classInfo,
	}
end

return SkillRegistry