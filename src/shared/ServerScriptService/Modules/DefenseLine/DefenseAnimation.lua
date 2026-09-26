-- ServerScriptService/Modules/DefenseLine/DefenseAnimation

--[[
    §AGX/X35: the breach "hit animation" is CLIENT-side. Never tween the
    mob's parts on the SERVER: every property change replicates per part
    to every client.

    The server only:
      1. freezes the mob (PlatformStand, WalkSpeed 0, anchored root — the
         anchored root anchors the whole welded assembly),
      2. sets BreachStyle / BreachDuration / Breaching attributes and the
         BREACH_TAG CollectionService tag,
      3. calls onComplete (damage + Destroy) after Duration.
    Clients (MobVisuals, tag listener) play the style locally on their own
    copy of the parts. Nothing is written to the parts on the server, so
    no per-part replication happens.
]]

local DefenseAnimation = {}

local CollectionService = game:GetService("CollectionService")

-- Tag read by the client receiver (StarterPlayerScripts/Modules/MobVisuals).
DefenseAnimation.BREACH_TAG = "DefenseBreach"

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
    Freeze the mob, hand the visual to clients, then call onComplete
    (which applies the damage and Destroys the mob) after Duration.

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

	local duration = config.Duration

	DefenseAnimation.DisableHumanoid(mob)

	-- Style/duration first so the client sees them when the tag arrives.
	mob:SetAttribute("BreachStyle", config.Style or "Fade")
	mob:SetAttribute("BreachDuration", duration)
	mob:SetAttribute("Breaching", os.clock())
	CollectionService:AddTag(mob, DefenseAnimation.BREACH_TAG)

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
