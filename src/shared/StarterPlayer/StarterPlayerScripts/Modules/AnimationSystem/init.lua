-- StarterPlayerScripts/Modules/AnimationSystem/init.lua
--[[
    AnimationSystem
    ===============
    Centralised client-side animation controller. Every module that
    needs to play an animation on ANY character (local player, other
    players, mobs) goes through this single API instead of creating
    its own Animation objects and caching tracks.

    Features:
      • Per-character track cache (auto-cleaned on destroy).
      • Category system so only one animation per category plays
        at a time (e.g. one attack, one skill, one emote).
      • Automatic AnimationPriority mapping per category.
      • One-call Play / Stop / StopAll.

    Categories (and their Roblox AnimationPriority):
      "idle"      -> Idle
      "movement"  -> Movement
      "attack"    -> Action      (player basic attacks)
      "skill"     -> Action2     (player/mob skills)
      "emote"     -> Action3     (emote wheel)

    Usage:
        local AnimationSystem = require(Modules:WaitForChild("AnimationSystem"))
        AnimationSystem.Init()

        local track = AnimationSystem.Play(character, animId, {
            category = "attack",
            speed    = 1.2,
            looped   = false,
            fadeIn   = 0.1,
            duration = 0.6,    -- auto-stop after 0.6s
        })
]]

local AnimationSystem = {}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════
-- CATEGORY → PRIORITY MAP
-- ═══════════════════════════════════════════════════════════

local PRIORITIES = {
	idle     = Enum.AnimationPriority.Idle,
	movement = Enum.AnimationPriority.Movement,
	attack   = Enum.AnimationPriority.Action,
	skill    = Enum.AnimationPriority.Action2,
	emote    = Enum.AnimationPriority.Action3,
	death    = Enum.AnimationPriority.Action4,
}

-- ═══════════════════════════════════════════════════════════
-- CHARACTER CACHE
-- [character] = {
--     animator = Animator,
--     tracks   = { [animId] = AnimationTrack },
-- }
-- ═══════════════════════════════════════════════════════════

local characterCache = {}

-- Active track by category per character:
-- [character] = { [category] = AnimationTrack }
local activeByCategory = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

local initialized = false

function AnimationSystem.Init()
	if initialized then return end
	initialized = true

	-- Track local player's character lifecycle
	local function onCharAdded(char)
		AnimationSystem.SetupCharacter(char)
	end

	LocalPlayer.CharacterAdded:Connect(onCharAdded)
	if LocalPlayer.Character then
		task.spawn(onCharAdded, LocalPlayer.Character)
	end

end

-- ═══════════════════════════════════════════════════════════
-- CHARACTER SETUP / CLEANUP
-- ═══════════════════════════════════════════════════════════

--- Ensure a character has a cached Animator reference.
--- Safe to call multiple times; idempotent.
function AnimationSystem.SetupCharacter(character)
	if characterCache[character] then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 5)
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	characterCache[character] = {
		animator = animator,
		tracks   = {},
	}
	activeByCategory[character] = {}

	-- Auto-cleanup when character is removed from the DataModel
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			AnimationSystem.CleanupCharacter(character)
		end
	end)
end

--- Remove all cached data for a character.
function AnimationSystem.CleanupCharacter(character)
	local cache = characterCache[character]
	if cache then
		for _, track in pairs(cache.tracks) do
			pcall(function()
				track:Stop(0)
			end)
		end
	end
	characterCache[character] = nil
	activeByCategory[character] = nil
end

-- ═══════════════════════════════════════════════════════════
-- TRACK MANAGEMENT
-- ═══════════════════════════════════════════════════════════

--- Get (or load) an AnimationTrack for a character + animId.
function AnimationSystem.GetOrLoadTrack(character, animId)
	-- Ensure setup
	if not characterCache[character] then
		AnimationSystem.SetupCharacter(character)
	end

	local cache = characterCache[character]
	if not cache then return nil end

	-- Return existing track
	if cache.tracks[animId] then
		return cache.tracks[animId]
	end

	-- Load new track
	local anim = Instance.new("Animation")
	anim.AnimationId = animId

	local ok, track = pcall(function()
		return cache.animator:LoadAnimation(anim)
	end)
	anim:Destroy()

	if ok and track then
		cache.tracks[animId] = track
		return track
	end

	warn("[AnimationSystem] Failed to load animation:", animId)
	return nil
end

-- ═══════════════════════════════════════════════════════════
-- PLAY / STOP API
-- ═══════════════════════════════════════════════════════════

--[[
    Play(character, animId, options?)
    options:
        category  string   "attack"|"skill"|"emote"|"idle"|"movement"  (default "attack")
        priority  AnimationPriority (overrides category default)
        looped    bool     (default false)
        speed     number   (default 1.0)
        fadeIn    number   seconds (default 0.1)
        fadeOut   number   seconds (default 0.1) — used with duration
        duration  number   seconds — auto-stop after this long (ignored if looped)
    Returns the AnimationTrack, or nil on failure.
]]
function AnimationSystem.Play(character, animId, options)
	if not character or not animId then return nil end
	options = options or {}

	local category = options.category or "attack"
	local priority = options.priority or PRIORITIES[category] or Enum.AnimationPriority.Action
	local looped   = options.looped == true
	local speed    = options.speed or 1.0
	local fadeIn   = options.fadeIn or 0.1
	local fadeOut  = options.fadeOut or 0.1
	local duration = options.duration

	local track = AnimationSystem.GetOrLoadTrack(character, animId)
	if not track then return nil end

	-- Stop any existing track in the same category
	AnimationSystem.Stop(character, category)

	-- Configure and play
	track.Priority = priority
	track.Looped = looped
	track:Play(fadeIn)
	track:AdjustSpeed(speed)

	-- Register as active
	local catTable = activeByCategory[character]
	if catTable then
		catTable[category] = track
	end

	-- Auto-stop after duration (non-looped only)
	if duration and not looped then
		task.delay(duration, function()
			if track and track.IsPlaying then
				track:Stop(fadeOut)
			end
			-- Clear from active
			if catTable and catTable[category] == track then
				catTable[category] = nil
			end
		end)
	end

	return track
end

--- Stop the active animation in a specific category.
function AnimationSystem.Stop(character, category)
	local catTable = activeByCategory[character]
	if not catTable then return end

	local track = catTable[category]
	if track then
		pcall(function()
			track:Stop(0.1)
		end)
		catTable[category] = nil
	end
end

--- Stop ALL active animations on a character.
function AnimationSystem.StopAll(character)
	local catTable = activeByCategory[character]
	if not catTable then return end
	for cat, track in pairs(catTable) do
		pcall(function()
			track:Stop(0.1)
		end)
		catTable[cat] = nil
	end
end

--- Check if a category is currently playing on a character.
function AnimationSystem.IsPlaying(character, category)
	local catTable = activeByCategory[character]
	if not catTable then return false end
	local track = catTable[category]
	return track ~= nil and track.IsPlaying
end

--- Get the active track for a category (or nil).
function AnimationSystem.GetActiveTrack(character, category)
	local catTable = activeByCategory[character]
	return catTable and catTable[category]
end

return AnimationSystem
