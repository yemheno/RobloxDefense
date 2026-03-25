-- HordePauseManager
-- Server-side module that freezes / unfreezes the entire horde mode game:
--   • Stops (or resumes) the spawn system so no new mobs appear
--   • Freezes (or restores) all active mob AI via MobAI.SetPaused
--   • Broadcasts a "HordePaused" client event so clients can block input
--     and show an overlay (e.g. the upgrades screen)

local HordePauseManager = {}

local Players = game:GetService("Players")

-- Injected via Setup()
local MobAI            = nil
local HordeModeSpawner = nil
local NetworkManager   = nil

local paused = false

-- ───────────────────────────────────────────────────────────
-- SETUP
-- ───────────────────────────────────────────────────────────

--- Call once from HordeModeMain after all modules are loaded.
function HordePauseManager.Setup(deps)
	MobAI            = deps.MobAI
	HordeModeSpawner = deps.HordeModeSpawner
	NetworkManager   = deps.NetworkManager

	-- Ensure the event exists so clients can listen for it immediately
	NetworkManager.GetEvent("HordePaused")
end

-- ───────────────────────────────────────────────────────────
-- PUBLIC API
-- ───────────────────────────────────────────────────────────

function HordePauseManager.IsPaused()
	return paused
end

--- Freeze the game: stop spawning, freeze mob AI, block all player input.
function HordePauseManager.Pause()
	if paused then return end
	paused = true

	-- Stop spawning new mobs (markers disappear because MARKER_TRANSPARENCY = 1)
	if HordeModeSpawner then
		HordeModeSpawner.Stop()
	end

	-- Freeze all active mob AI + set WalkSpeed = 0
	if MobAI then
		MobAI.SetPaused(true)
	end

	-- Mark every player as paused (server attribute — blocks server-side actions)
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("HordePaused", true)
	end

	-- Tell all clients to freeze
	if NetworkManager then
		NetworkManager.FireAllClients("HordePaused", true)
	end

	print("[HordePauseManager] PAUSED")
end

--- Unfreeze the game: resume spawning, restore mob AI, unblock player input.
function HordePauseManager.Resume()
	if not paused then return end
	paused = false

	-- Resume spawning
	if HordeModeSpawner then
		HordeModeSpawner.Start()
	end

	-- Unfreeze mob AI + restore WalkSpeed from config
	if MobAI then
		MobAI.SetPaused(false)
	end

	-- Clear paused attribute on all players
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("HordePaused", false)
	end

	-- Tell all clients to unfreeze
	if NetworkManager then
		NetworkManager.FireAllClients("HordePaused", false)
	end

	print("[HordePauseManager] RESUMED")
end

--- Toggle between paused / running states.
function HordePauseManager.Toggle()
	if paused then
		HordePauseManager.Resume()
	else
		HordePauseManager.Pause()
	end
end

return HordePauseManager
