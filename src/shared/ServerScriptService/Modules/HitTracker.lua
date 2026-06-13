-- ServerScriptService/Modules/HitTracker

local HitTracker = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════

local CONFIG = {
	ComboDecayTime = 3.0,       -- Seconds before combo resets
	ComboUpdateRate = 0.1,      -- How often to check combo decay
	MinComboForNotify = 3,      -- Minimum combo to notify client
}

-- ═══════════════════════════════════════════════════════════
-- INTERNAL STORAGE
-- ═══════════════════════════════════════════════════════════

local playerStats = {}
local lastComboCheck = 0

-- Event callback lists
local hitDealtCallbacks    = {}
local hitReceivedCallbacks = {}
local comboCallbacks       = {}

function HitTracker.OnHitDealt(callback)
	table.insert(hitDealtCallbacks, callback)
end

function HitTracker.OnHitReceived(callback)
	table.insert(hitReceivedCallbacks, callback)
end

function HitTracker.OnComboUpdated(callback)
	table.insert(comboCallbacks, callback)
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS: Create Default Structures
-- ═══════════════════════════════════════════════════════════

-- §T1.4/Y5: CreateTierStats / CreateReceivedTierStats / CreateStatsBlock
-- removed with the lifetime/session blocks they fed (see below).
--
-- §T1.4/Y5: the lifetime/session dealt+received accumulation blocks were
-- removed. They were written every hit but never read anywhere, and they
-- DUPLICATED the authoritative lifetime stats that AchievementManager
-- keeps in PlayerData (via the OnHitDealt callback below). HitTracker now
-- owns only what's actually consumed: live combo state + combat
-- timestamps (for ResourceManager's in-combat checks).
local function CreatePlayerStats()
	return {
		combo = {
			current = 0,
			best = 0,
			bestLifetime = 0,
			lastHitTime = 0,
			damageInCombo = 0,
			critsInCombo = 0,
		},
		combat = {
			lastHitDealtTime = 0,
			lastHitReceivedTime = 0,
		},
	}
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function HitTracker.Init()
	-- Create network events
	NetworkManager.GetEvent("ComboUpdate")
	NetworkManager.GetEvent("ComboEnded")

	-- Player connections
	Players.PlayerAdded:Connect(HitTracker.SetupPlayer)
	Players.PlayerRemoving:Connect(HitTracker.RemovePlayer)

	-- Setup existing players
	for _, player in ipairs(Players:GetPlayers()) do
		HitTracker.SetupPlayer(player)
	end

	-- Combo decay check loop
	RunService.Heartbeat:Connect(function(dt)
		HitTracker.UpdateCombos(dt)
	end)

end

function HitTracker.SetupPlayer(player)
	playerStats[player] = CreatePlayerStats()
end

function HitTracker.RemovePlayer(player)
	-- §T1.4/Y5: no lifetime-stats persist step — AchievementManager owns
	-- the persisted lifetime stats (PlayerData) via the OnHitDealt hook.
	playerStats[player] = nil
end

-- ═══════════════════════════════════════════════════════════
-- RECORDING: Hits Dealt
-- ═══════════════════════════════════════════════════════════

--[[
    Called by DamageHandler when player hits a mob
    
    hitData = {
        mobTier = "normal" / "miniboss" / "boss",
        damage = number,
        isCrit = boolean,
        critProcs = number,
        isKill = boolean,
    }
]]
function HitTracker.RecordHitDealt(player, hitData)
	local stats = playerStats[player]
	if not stats then return end

	local now = os.clock()

	-- §T1.4/Y5: per-hit stat accumulation removed — AchievementManager
	-- consumes hitData via the OnHitDealt callback below and persists the
	-- authoritative totals. HitTracker keeps only combat timing + combo.

	-- Update combat timestamp
	stats.combat.lastHitDealtTime = now

	-- Update combo
	HitTracker.UpdateComboOnHit(player, hitData, now)

	-- §T1.4/R6: ResourceManager now registers via OnHitDealt() like every
	-- other consumer. No bespoke dispatcher path required here.
	for _, cb in ipairs(hitDealtCallbacks) do
		task.spawn(cb, player, hitData)
	end
end

-- ═══════════════════════════════════════════════════════════
-- RECORDING: Hits Received
-- ═══════════════════════════════════════════════════════════

--[[
    Called by MobAI when player takes damage
    
    hitData = {
        mobTier = "normal" / "miniboss" / "boss",
        damage = number,
    }
]]
function HitTracker.RecordHitReceived(player, hitData)
	local stats = playerStats[player]
	if not stats then return end

	local now = os.clock()

	-- §T1.4/Y5: per-hit stat accumulation removed (AchievementManager owns
	-- persisted totals via OnHitReceived). Combat timing only.

	-- Update combat timestamp
	stats.combat.lastHitReceivedTime = now

	-- §T1.4/R6: ResourceManager + AchievementManager + future per-hit
	-- consumers all dispatch through the single callback list.
	for _, cb in ipairs(hitReceivedCallbacks) do
		task.spawn(cb, player, hitData)
	end
end

-- ═══════════════════════════════════════════════════════════
-- COMBO SYSTEM
-- ═══════════════════════════════════════════════════════════

function HitTracker.UpdateComboOnHit(player, hitData, now)
	local stats = playerStats[player]
	if not stats then return end

	local combo = stats.combo
	local timeSinceLastHit = now - combo.lastHitTime

	-- Check if combo should continue or reset
	if combo.lastHitTime == 0 or timeSinceLastHit <= CONFIG.ComboDecayTime then
		-- Continue combo
		combo.current = combo.current + 1
		combo.damageInCombo = combo.damageInCombo + (hitData.damage or 0)
		if hitData.isCrit then
			combo.critsInCombo = combo.critsInCombo + (hitData.critProcs or 1)
		end
	else
		-- Start new combo
		combo.current = 1
		combo.damageInCombo = hitData.damage or 0
		combo.critsInCombo = hitData.isCrit and (hitData.critProcs or 1) or 0
	end

	combo.lastHitTime = now

	-- Update best combo (session)
	if combo.current > combo.best then
		combo.best = combo.current
	end

	-- Update best combo (lifetime)
	if combo.current > combo.bestLifetime then
		combo.bestLifetime = combo.current
		-- Notify combo listeners (AchievementManager, etc.)
		for _, cb in ipairs(comboCallbacks) do
			task.spawn(cb, player, combo.current)
		end
	end

	-- Notify client
	if combo.current >= CONFIG.MinComboForNotify then
		NetworkManager.FireClient(player, "ComboUpdate", {
			current = combo.current,
			damage = combo.damageInCombo,
			crits = combo.critsInCombo,
			best = combo.best,
		})
	end
end

function HitTracker.UpdateCombos(dt)
	local now = os.clock()

	-- Throttle check rate
	if now - lastComboCheck < CONFIG.ComboUpdateRate then
		return
	end
	lastComboCheck = now

	for player, stats in pairs(playerStats) do
		local combo = stats.combo

		-- Check for combo decay
		if combo.current > 0 then
			local timeSinceLastHit = now - combo.lastHitTime

			if timeSinceLastHit > CONFIG.ComboDecayTime then
				-- Combo ended!
				local endedCombo = combo.current
				local endedDamage = combo.damageInCombo
				local endedCrits = combo.critsInCombo

				-- Reset combo
				combo.current = 0
				combo.damageInCombo = 0
				combo.critsInCombo = 0

				-- Notify client if it was a notable combo
				if endedCombo >= CONFIG.MinComboForNotify then
					NetworkManager.FireClient(player, "ComboEnded", {
						finalCombo = endedCombo,
						totalDamage = endedDamage,
						totalCrits = endedCrits,
						best = combo.best,
					})
				end
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- SESSION RESET
-- ═══════════════════════════════════════════════════════════

function HitTracker.ResetSession(player)
	local stats = playerStats[player]
	if not stats then return end

	-- §T1.4/Y5: only combo session state remains to reset (the session
	-- stat block was removed). Lifetime-best combo is preserved.
	stats.combo.current = 0
	stats.combo.best = 0
	stats.combo.damageInCombo = 0
	stats.combo.critsInCombo = 0
	stats.combo.lastHitTime = 0
end

function HitTracker.ResetAllSessions()
	for player, _ in pairs(playerStats) do
		HitTracker.ResetSession(player)
	end
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS: Combat Timing
-- ═══════════════════════════════════════════════════════════

function HitTracker.GetTimeSinceLastHitDealt(player)
	local stats = playerStats[player]
	if not stats then return math.huge end

	if stats.combat.lastHitDealtTime == 0 then
		return math.huge
	end

	return os.clock() - stats.combat.lastHitDealtTime
end

function HitTracker.GetTimeSinceLastHitReceived(player)
	local stats = playerStats[player]
	if not stats then return math.huge end

	if stats.combat.lastHitReceivedTime == 0 then
		return math.huge
	end

	return os.clock() - stats.combat.lastHitReceivedTime
end

-- §T1.4/R6: HitTracker.NotifyResourceManager removed. Per-hit consumers
-- (ResourceManager, AchievementManager, future achievement / rune /
-- proc-on-hit systems) register through HitTracker.OnHitDealt and
-- HitTracker.OnHitReceived. One dispatch path; no per-hit
-- FindFirstChild + require lookup.

return HitTracker