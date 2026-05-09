-- StarterPlayerScripts/Modules/CameraSystem
--[[
    Modular camera system.

    Provides a mode-based API so each place can request the camera
    behaviour it needs without hard-coding anything.

    Usage:
        CameraSystem.Init()                          -- auto-registers built-in modes
        CameraSystem.SetMode("FixedIsometric", {     -- activate a mode with config
            offset   = Vector3.new(-12, 8, 0),
            lookAhead = 20,
        })
        CameraSystem.SetMode("Free")                 -- revert to default camera

    Built-in modes (auto-loaded from child ModuleScripts):
        • Free             – default Roblox camera, no overrides
        • FixedIsometric   – scriptable camera that follows the player
]]

local CameraSystem = {}

-- ── Internal state ────────────────────────────────────────
local modes      = {}   -- { [modeName] = modeModule }
local activeMode = nil  -- currently active mode module
local activeModeName = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function CameraSystem.Init()
	-- Auto-register every child ModuleScript as a mode
	for _, child in ipairs(script:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, modeModule = pcall(require, child)
			if ok and type(modeModule) == "table" then
				modes[child.Name] = modeModule
			else
				warn("[CameraSystem] Failed to load mode:", child.Name, modeModule)
			end
		end
	end

	print("[CameraSystem] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- MODE MANAGEMENT
-- ═══════════════════════════════════════════════════════════

--- Activate a camera mode by name, passing an optional config table.
function CameraSystem.SetMode(name, config)
	if activeMode and activeMode.Stop then
		activeMode.Stop()
	end

	local mode = modes[name]
	if not mode then
		warn("[CameraSystem] Unknown mode:", name)
		activeMode = nil
		activeModeName = nil
		return false
	end

	activeMode = mode
	activeModeName = name

	if mode.Start then
		mode.Start(config or {})
	end

	print("[CameraSystem] Mode set:", name)
	return true
end

return CameraSystem
