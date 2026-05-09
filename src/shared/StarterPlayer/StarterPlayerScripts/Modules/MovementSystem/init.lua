-- StarterPlayerScripts/Modules/MovementSystem
--[[
    Modular movement-constraint system.

    Provides named constraint modules that can be activated / deactivated
    independently. Multiple constraints can be active at the same time
    (e.g. NoJump + FaceDirection).

    Usage:
        MovementSystem.Init()
        MovementSystem.Enable("NoJump")
        MovementSystem.Enable("FaceDirection", { direction = Vector3.new(1, 0, 0) })

    Built-in constraints (auto-loaded from child ModuleScripts):
        • NoJump         – sets JumpPower / JumpHeight to 0
        • FaceDirection  – forces the character to face a fixed world direction
        • Free           – no-op placeholder (default Roblox movement)
]]

local MovementSystem = {}

local constraints       = {}   -- { [name] = constraintModule }
local activeConstraints = {}   -- { [name] = true }

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function MovementSystem.Init()
	for _, child in ipairs(script:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, mod = pcall(require, child)
			if ok and type(mod) == "table" then
				constraints[child.Name] = mod
			else
				warn("[MovementSystem] Failed to load constraint:", child.Name, mod)
			end
		end
	end

	print("[MovementSystem] Initialized —", MovementSystem.GetConstraintCount(), "constraints registered")
end

-- ═══════════════════════════════════════════════════════════
-- CONSTRAINT MANAGEMENT
-- ═══════════════════════════════════════════════════════════

--- Enable a named constraint, optionally passing config.
function MovementSystem.Enable(name, config)
	local mod = constraints[name]
	if not mod then
		warn("[MovementSystem] Unknown constraint:", name)
		return false
	end

	if activeConstraints[name] then
		-- Already active — stop first so Start() re-applies cleanly
		if mod.Stop then mod.Stop() end
	end

	activeConstraints[name] = true
	if mod.Start then
		mod.Start(config or {})
	end

	print("[MovementSystem] Enabled:", name)
	return true
end

-- ═══════════════════════════════════════════════════════════
-- QUERIES
-- ═══════════════════════════════════════════════════════════

function MovementSystem.GetConstraintCount()
	local c = 0
	for _ in pairs(constraints) do c = c + 1 end
	return c
end

return MovementSystem
