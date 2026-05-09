-- ServerScriptService/Modules/MobBehaviors
--[[
    Behavior loader: requires every ModuleScript child and
    exports them as MobBehaviors[BehaviorName] = module.

    Each behavior module must expose:
        Init(mobData, behaviorConfig)  -- called on mob registration
        Update(mobData, now)           -- called every AI tick

    Mob data files declare behaviors like:
        behaviors = {
            { type = "Enrage", hpThreshold = 0.3, speedBonus = 4, damageBonus = 1.6 },
        }
]]

local MobBehaviors = {}

for _, child in ipairs(script:GetChildren()) do
	if child:IsA("ModuleScript") then
		local ok, module = pcall(require, child)
		if ok then
			MobBehaviors[child.Name] = module
			print("[MobBehaviors] Loaded behavior:", child.Name)
		else
			warn("[MobBehaviors] Failed to load behavior:", child.Name, "-", module)
		end
	end
end

return MobBehaviors
