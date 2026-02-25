-- ServerScriptService/Modules/AttackHandler/MeleeSystem

local MeleeSystem = {}

local Modules = script.Parent.Parent
local ClassManager = require(Modules:WaitForChild("ClassManager"))
local AttackShapes = require(Modules:WaitForChild("AttackShapes"))

-- Set by AttackHandler
MeleeSystem.DamageHandler = nil
MeleeSystem.GetAttackDirection = nil

--============================================
-- INITIALIZATION
--============================================
function MeleeSystem.Init()
	print("[MeleeSystem] Initialized")
end

--============================================
-- EXECUTE MELEE ATTACK
--============================================
function MeleeSystem.Execute(player, rootPart)
	local direction = MeleeSystem.GetAttackDirection(rootPart)
	local origin = rootPart.Position

	local shapeName = ClassManager.GetAttackShape(player)
	local shapeParams = ClassManager.GetShapeParams(player)

	-- DEBUG: What are we working with?
	print("[MeleeSystem DEBUG] Shape:", shapeName, "| Params:", shapeParams)
	print("[MeleeSystem DEBUG] Origin:", origin, "| Direction:", direction)

	local params = {
		origin = origin,
		direction = direction,
		filterAttribute = "IsMob",
	}

	for k, v in pairs(shapeParams) do
		params[k] = v
	end

	print("[MeleeSystem DEBUG] Final params keys:", table.concat((function()
		local keys = {}
		for k in pairs(params) do table.insert(keys, k) end
		return keys
	end)(), ", "))

	local targets = AttackShapes.GetTargetsInShape(shapeName, params)

	print("[MeleeSystem DEBUG] Targets found:", #targets)

	for _, target in ipairs(targets) do
		print("[MeleeSystem DEBUG] Hitting:", target.Name)
		MeleeSystem.DamageHandler.DamageMob(target, player)
	end

	return #targets
end

return MeleeSystem