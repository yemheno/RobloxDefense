-- ServerScriptService/Modules/DefenseLine/DefenseAnimation

local DefenseAnimation = {}

local TweenService = game:GetService("TweenService")

-- References (set by parent)
DefenseAnimation.Config = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DefenseAnimation.Init()
end

-- ═══════════════════════════════════════════════════════════
-- MAIN ANIMATION FUNCTION
-- ═══════════════════════════════════════════════════════════

--[[
    Play hit animation on a mob before destroying it.
    
    Parameters:
    - mob: The mob model
    - onComplete: Function to call when animation finishes
]]
function DefenseAnimation.PlayHitAnimation(mob, onComplete)
	local config = DefenseAnimation.Config.Animation

	if not config.Enabled then
		if onComplete then onComplete() end
		return
	end

	local style = config.Style
	local duration = config.Duration

	-- Get all parts
	local parts = DefenseAnimation.GetMobParts(mob)

	-- Play animation based on style
	if style == "Dissolve" then
		DefenseAnimation.Dissolve(mob, parts, duration, onComplete)
	elseif style == "Explode" then
		DefenseAnimation.Explode(mob, parts, duration, onComplete)
	elseif style == "Shrink" then
		DefenseAnimation.Shrink(mob, parts, duration, onComplete)
	elseif style == "Fade" then
		DefenseAnimation.Fade(mob, parts, duration, onComplete)
	else
		DefenseAnimation.Fade(mob, parts, duration, onComplete)
	end
end

-- ═══════════════════════════════════════════════════════════
-- HELPER: Get all parts in mob
-- ═══════════════════════════════════════════════════════════

function DefenseAnimation.GetMobParts(mob)
	local parts = {}
	for _, part in ipairs(mob:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	return parts
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATION: Dissolve (Red fade)
-- ═══════════════════════════════════════════════════════════

function DefenseAnimation.Dissolve(mob, parts, duration, onComplete)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, part in ipairs(parts) do
		local tween = TweenService:Create(part, tweenInfo, {
			Transparency = 1,
			Color = Color3.fromRGB(255, 50, 50),
		})
		tween:Play()
	end

	DefenseAnimation.DisableHumanoid(mob)

	task.delay(duration, function()
		if onComplete then onComplete() end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATION: Explode (Parts fly outward)
-- ═══════════════════════════════════════════════════════════

function DefenseAnimation.Explode(mob, parts, duration, onComplete)
	local rootPart = mob:FindFirstChild("HumanoidRootPart")
	local center = rootPart and rootPart.Position or mob:GetPivot().Position

	-- Break joints first
	mob:BreakJoints()

	for _, part in ipairs(parts) do
		if part:IsA("BasePart") and not part.Anchored then
			-- Calculate outward direction
			local direction = (part.Position - center)
			if direction.Magnitude < 0.1 then
				direction = Vector3.new(math.random() - 0.5, 1, math.random() - 0.5)
			end
			direction = direction.Unit

			-- Apply velocity
			part.AssemblyLinearVelocity = direction * 30 + Vector3.new(0, 20, 0)
			part.AssemblyAngularVelocity = Vector3.new(
				math.random() * 10 - 5,
				math.random() * 10 - 5,
				math.random() * 10 - 5
			)
		end

		-- Fade out
		local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(part, tweenInfo, {
			Transparency = 1,
		})
		tween:Play()
	end

	task.delay(duration, function()
		if onComplete then onComplete() end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATION: Shrink (Implode)
-- ═══════════════════════════════════════════════════════════

function DefenseAnimation.Shrink(mob, parts, duration, onComplete)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.In)

	for _, part in ipairs(parts) do
		local originalSize = part.Size
		local tween = TweenService:Create(part, tweenInfo, {
			Size = originalSize * 0.01,
			Transparency = 1,
		})
		tween:Play()
	end

	DefenseAnimation.DisableHumanoid(mob)

	task.delay(duration, function()
		if onComplete then onComplete() end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATION: Fade (Simple transparency)
-- ═══════════════════════════════════════════════════════════

function DefenseAnimation.Fade(mob, parts, duration, onComplete)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)

	for _, part in ipairs(parts) do
		local tween = TweenService:Create(part, tweenInfo, {
			Transparency = 1,
		})
		tween:Play()
	end

	DefenseAnimation.DisableHumanoid(mob)

	task.delay(duration, function()
		if onComplete then onComplete() end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- HELPER: Disable humanoid
-- ═══════════════════════════════════════════════════════════

function DefenseAnimation.DisableHumanoid(mob)
	local humanoid = mob:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
		humanoid.WalkSpeed = 0
	end
	-- Anchor HumanoidRootPart to prevent any physics drift
	local root = mob:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
	end
end

return DefenseAnimation