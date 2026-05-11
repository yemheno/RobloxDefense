-- ServerScriptService/Modules/DefenseLine/DefenseDetection

local DefenseDetection = {}

-- References (set by parent)
DefenseDetection.Config = nil
DefenseDetection.DefensePart = nil
DefenseDetection.MobAI = nil
DefenseDetection.OnMobReached = nil  -- Callback function

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local processedMobs = {}
local animatingMobs = {}
local lastCheckTime = 0

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DefenseDetection.Init()
	DefenseDetection.Reset()
end

-- ═══════════════════════════════════════════════════════════
-- UPDATE (Called every frame)
-- ═══════════════════════════════════════════════════════════

function DefenseDetection.Update(dt)
	if not DefenseDetection.DefensePart then return end
	if not DefenseDetection.MobAI then return end

	local config = DefenseDetection.Config.Detection
	local now = os.clock()

	-- Throttle checks
	if now - lastCheckTime < config.CheckInterval then
		return
	end
	lastCheckTime = now

	DefenseDetection.CheckMobsAtLine()
end

-- ═══════════════════════════════════════════════════════════
-- MOB DETECTION
-- ═══════════════════════════════════════════════════════════

function DefenseDetection.CheckMobsAtLine()
	local config = DefenseDetection.Config.Detection
	local lineX = DefenseDetection.DefensePart.Position.X

	local allMobs = DefenseDetection.MobAI.GetAllMobData()

	for mob, mobData in pairs(allMobs) do
		-- Skip already processed or animating
		if processedMobs[mob] or animatingMobs[mob] then
			continue
		end

		local rootPart = mob:FindFirstChild("HumanoidRootPart")
		if not rootPart then continue end

		local mobX = rootPart.Position.X
		local distance = math.abs(mobX - lineX)
		local passedLine = mobX <= lineX

		if distance <= config.Range or passedLine then
			DefenseDetection.OnMobDetected(mob, mobData)
		end
	end
end

function DefenseDetection.OnMobDetected(mob, mobData)
	-- Mark as processed immediately
	processedMobs[mob] = true
	animatingMobs[mob] = true

	-- Stop the mob
	local humanoid = mob:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
	end

	-- Call parent handler
	if DefenseDetection.OnMobReached then
		DefenseDetection.OnMobReached(mob, mobData)
	end
end

-- ═══════════════════════════════════════════════════════════
-- MOB TRACKING
-- ═══════════════════════════════════════════════════════════

function DefenseDetection.ClearMob(mob)
	processedMobs[mob] = nil
	animatingMobs[mob] = nil
end

-- ═══════════════════════════════════════════════════════════
-- RESET
-- ═══════════════════════════════════════════════════════════

function DefenseDetection.Reset()
	processedMobs = {}
	animatingMobs = {}
	lastCheckTime = 0
end

return DefenseDetection