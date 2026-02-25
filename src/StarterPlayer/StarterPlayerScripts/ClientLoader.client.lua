-- ClientLoader

local Modules = script.Parent:WaitForChild("Modules")

-- Load in specific order
-- NOTE: CharacterCreationUI is intentionally omitted — the React App (UiClient.client.lua)
-- handles all UI including first-login character creation.
local LOAD_ORDER = {
	"NetworkManager",
	"KeybindManager",
	"CameraController",
	"PlayerMovement",
	"PlayerAttack",
	"SkillInput",
	"SkillVisuals",
	"MobVisuals",
	"DamageNumbers",
}

local loadedModules = {}

-- Load modules
for _, moduleName in ipairs(LOAD_ORDER) do
	local moduleScript = Modules:FindFirstChild(moduleName)
	if moduleScript then
		local success, result = pcall(function()
			return require(moduleScript)
		end)

		if success then
			loadedModules[moduleName] = result

			if type(result.Init) == "function" then
				result.Init()
			end

			print("[ClientLoader] Loaded:", moduleName)
		else
			warn("[ClientLoader] Failed to load", moduleName, ":", result)
		end
	else
		warn("[ClientLoader] Module not found:", moduleName)
	end
end

print("[ClientLoader] All modules loaded!")

-- Listen for server ready (for future loading screen)
local NetworkManager = loadedModules["NetworkManager"]
NetworkManager.OnServerEvent("ServerReady", function()
	print("[ClientLoader] Server is ready!")
	-- Future: Hide loading screen here
end)