-- ServerScriptService/Modules/SkillManager/SkillExecutor

local SkillExecutor = {}

local SkillManager = nil
local SkillRegistry = nil
local BaseSkills = nil
local SkillEffects = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function SkillExecutor.Init(manager)
	SkillManager = manager

	local Modules = script.Parent.Parent
	SkillRegistry = require(Modules:WaitForChild("SkillRegistry"))

	-- Load shared modules
	local ClassSkillsFolder = Modules:FindFirstChild("ClassSkills")

	-- Load BaseSkills
	local baseModule = ClassSkillsFolder:FindFirstChild("BaseSkills")
	if baseModule then
		BaseSkills = require(baseModule)
	end

	-- Load SkillEffects
	local effectsModule = Modules:FindFirstChild("SkillEffects")
	if effectsModule then
		SkillEffects = require(effectsModule)
	end

	-- Get DamageHandler from AttackHandler
	local AttackHandler = require(Modules:WaitForChild("AttackHandler"))
	local DamageHandler = AttackHandler.GetSystems().Damage

	-- Build dependencies
	local dependencies = {
		AttackShapes = require(Modules:WaitForChild("AttackShapes")),
		StatsManager = require(Modules:WaitForChild("StatsManager")),
		NetworkManager = require(Modules:WaitForChild("NetworkManager")),
		DamageHandler = DamageHandler,
		MobAI = nil,
		SkillManager = SkillManager,
	}

	-- Create visual event
	dependencies.NetworkManager.GetEvent("SkillVisual")

	-- Initialize shared modules
	if BaseSkills then BaseSkills.Init(dependencies) end
	if SkillEffects then SkillEffects.Init(dependencies) end

	-- Initialize all class skill modules
	for _, className in ipairs(SkillRegistry.GetAllClassNames()) do
		local classModule = SkillRegistry.GetClassModule(className)
		if classModule and classModule.Init then
			classModule.Init(BaseSkills, SkillEffects)
		end
	end

	-- Load MobAI after delay
	task.spawn(function()
		task.wait(1)
		local mobAIModule = Modules:FindFirstChild("MobAI")
		if mobAIModule then
			local MobAI = require(mobAIModule)
			dependencies.MobAI = MobAI
			if BaseSkills then BaseSkills.MobAI = MobAI end
			if SkillEffects then SkillEffects.MobAI = MobAI end
		end
	end)

	print("[SkillExecutor] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- EXECUTE (Routes through SkillRegistry)
-- ═══════════════════════════════════════════════════════════

function SkillExecutor.Execute(player, skill, inputData)
	return SkillRegistry.ExecuteSkill(player, skill, inputData)
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS
-- ═══════════════════════════════════════════════════════════

function SkillExecutor.GetBaseSkills()
	return BaseSkills
end

function SkillExecutor.GetSkillEffects()
	return SkillEffects
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function SkillExecutor.GetDebugInfo()
	return {
		baseSkillsLoaded = BaseSkills ~= nil,
		skillEffectsLoaded = SkillEffects ~= nil,
		registryInfo = SkillRegistry.GetDebugInfo(),
	}
end

return SkillExecutor