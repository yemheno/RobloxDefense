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

	-- §SR1 fix: SkillRegistry runs BEFORE SkillManager.Init in every place
	-- bootstrap (Lobby loads SkillRegistry but never loads SkillManager at
	-- all). The class skill modules expose their `GetAllSkills` /
	-- `GetSkillCount` / `GetSkillBySlot` functions only after
	-- BaseSkills.InjectGetters has been called from inside their own Init.
	-- That meant CacheClassSkills below would nil-deref on a fresh boot.
	-- Pre-load BaseSkills here and inject the getters ourselves so the
	-- registry is self-sufficient. Re-injection by SkillManager later is
	-- idempotent (it just rewrites the same closures).
	local baseModule = ClassSkillsFolder:FindFirstChild("BaseSkills")
	local BaseSkillsRef = nil
	if baseModule then
		local okBase, baseResult = pcall(require, baseModule)
		if okBase then
			BaseSkillsRef = baseResult
		else
			warn("[SkillRegistry] Failed to load BaseSkills:", baseResult)
		end
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

				-- §SR1: ensure the standard getters exist before caching.
				if BaseSkillsRef and BaseSkillsRef.InjectGetters
					and not result.GetAllSkills then
					BaseSkillsRef.InjectGetters(result)
				end

				-- Cache all skills from this class
				SkillRegistry.CacheClassSkills(className, result)

				local count = (result.GetSkillCount and result.GetSkillCount())
					or (result.Skills and (function()
						local n = 0
						for _ in pairs(result.Skills) do n = n + 1 end
						return n
					end)())
					or 0
				print("[SkillRegistry] Loaded:", className, "(" .. tostring(count) .. " skills)")

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
	-- §SR1 fix: tolerate missing GetAllSkills by falling back to the static
	-- `Skills` table that every class module declares at module-load time.
	local skills
	if classModule.GetAllSkills then
		skills = classModule.GetAllSkills()
	else
		skills = classModule.Skills
	end
	if not skills then
		warn("[SkillRegistry] CacheClassSkills: no skills table on", className)
		return
	end

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