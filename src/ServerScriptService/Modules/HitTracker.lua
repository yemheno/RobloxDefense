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

-- ═══════════════════════════════════════════════════════════
-- HELPERS: Create Default Structures
-- ═══════════════════════════════════════════════════════════

local function CreateTierStats()
	return {
		hits = 0,
		crits = 0,
		damage = 0,
		kills = 0,
	}
end

local function CreateReceivedTierStats()
	return {
		hits = 0,
		damage = 0,
	}
end

local function CreateStatsBlock()
	return {
		dealt = {
			normal = CreateTierStats(),
			miniboss = CreateTierStats(),
			boss = CreateTierStats(),
		},
		received = {
			normal = CreateReceivedTierStats(),
			miniboss = CreateReceivedTierStats(),
			boss = CreateReceivedTierStats(),
		},
		totals = {
			hitsDealt = 0,
			hitsReceived = 0,
			damageDealt = 0,
			damageReceived = 0,
			kills = 0,
			crits = 0,
		},
	}
end

local function CreatePlayerStats()
	return {
		lifetime = CreateStatsBlock(),
		session = CreateStatsBlock(),
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
	NetworkManager.GetEvent("HitStatsUpdate")

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

	print("[HitTracker] Initialized")
end

function HitTracker.SetupPlayer(player)
	playerStats[player] = CreatePlayerStats()
	print("[HitTracker] Setup complete for", player.Name)
end

function HitTracker.RemovePlayer(player)
	-- TODO: Save lifetime stats to DataStore before removing
	HitTracker.SaveLifetimeStats(player)
	playerStats[player] = nil
end

function HitTracker.SaveLifetimeStats(player)
	local stats = playerStats[player]
	if not stats then return end

	-- TODO: Integrate with PlayerDataManager for DataStore saving
	print("[HitTracker] Would save lifetime stats for", player.Name)
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

	local now = tick()
	local tier = hitData.mobTier or "normal"
	local damage = hitData.damage or 0
	local isCrit = hitData.isCrit or false
	local critProcs = hitData.critProcs or 0
	local isKill = hitData.isKill or false

	-- Update lifetime stats
	local lifetimeTier = stats.lifetime.dealt[tier]
	lifetimeTier.hits = lifetimeTier.hits + 1
	lifetimeTier.damage = lifetimeTier.damage + damage
	if isCrit then
		lifetimeTier.crits = lifetimeTier.crits + critProcs
	end
	if isKill then
		lifetimeTier.kills = lifetimeTier.kills + 1
	end

	-- Update lifetime totals
	local lifetimeTotals = stats.lifetime.totals
	lifetimeTotals.hitsDealt = lifetimeTotals.hitsDealt + 1
	lifetimeTotals.damageDealt = lifetimeTotals.damageDealt + damage
	if isCrit then
		lifetimeTotals.crits = lifetimeTotals.crits + critProcs
	end
	if isKill then
		lifetimeTotals.kills = lifetimeTotals.kills + 1
	end

	-- Update session stats (same structure)
	local sessionTier = stats.session.dealt[tier]
	sessionTier.hits = sessionTier.hits + 1
	sessionTier.damage = sessionTier.damage + damage
	if isCrit then
		sessionTier.crits = sessionTier.crits + critProcs
	end
	if isKill then
		sessionTier.kills = sessionTier.kills + 1
	end

	local sessionTotals = stats.session.totals
	sessionTotals.hitsDealt = sessionTotals.hitsDealt + 1
	sessionTotals.damageDealt = sessionTotals.damageDealt + damage
	if isCrit then
		sessionTotals.crits = sessionTotals.crits + critProcs
	end
	if isKill then
		sessionTotals.kills = sessionTotals.kills + 1
	end

	-- Update combat timestamp
	stats.combat.lastHitDealtTime = now

	-- Update combo
	HitTracker.UpdateComboOnHit(player, hitData, now)

	-- Notify ResourceManager (if exists)
	HitTracker.NotifyResourceManager(player, "HitDealt", hitData)
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

	local now = tick()
	local tier = hitData.mobTier or "normal"
	local damage = hitData.damage or 0

	-- Update lifetime stats
	local lifetimeTier = stats.lifetime.received[tier]
	lifetimeTier.hits = lifetimeTier.hits + 1
	lifetimeTier.damage = lifetimeTier.damage + damage

	local lifetimeTotals = stats.lifetime.totals
	lifetimeTotals.hitsReceived = lifetimeTotals.hitsReceived + 1
	lifetimeTotals.damageReceived = lifetimeTotals.damageReceived + damage

	-- Update session stats
	local sessionTier = stats.session.received[tier]
	sessionTier.hits = sessionTier.hits + 1
	sessionTier.damage = sessionTier.damage + damage

	local sessionTotals = stats.session.totals
	sessionTotals.hitsReceived = sessionTotals.hitsReceived + 1
	sessionTotals.damageReceived = sessionTotals.damageReceived + damage

	-- Update combat timestamp
	stats.combat.lastHitReceivedTime = now

	-- Notify ResourceManager (if exists)
	HitTracker.NotifyResourceManager(player, "HitReceived", hitData)
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
		-- Achievement opportunity!
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
	local now = tick()

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

function HitTracker.GetCombo(player)
	local stats = playerStats[player]
	if not stats then return 0 end
	return stats.combo.current
end

function HitTracker.GetBestCombo(player, lifetime)
	local stats = playerStats[player]
	if not stats then return 0 end

	if lifetime then
		return stats.combo.bestLifetime
	end
	return stats.combo.best
end

-- ═══════════════════════════════════════════════════════════
-- SESSION RESET
-- ═══════════════════════════════════════════════════════════

function HitTracker.ResetSession(player)
	local stats = playerStats[player]
	if not stats then return end

	-- Reset session stats
	stats.session = CreateStatsBlock()

	-- Reset session combo best (keep lifetime)
	stats.combo.current = 0
	stats.combo.best = 0
	stats.combo.damageInCombo = 0
	stats.combo.critsInCombo = 0
	stats.combo.lastHitTime = 0

	print("[HitTracker] Session reset for", player.Name)
end

function HitTracker.ResetAllSessions()
	for player, _ in pairs(playerStats) do
		HitTracker.ResetSession(player)
	end
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS: Full Stats
-- ═══════════════════════════════════════════════════════════

function HitTracker.GetStats(player)
	return playerStats[player]
end

function HitTracker.GetLifetimeStats(player)
	local stats = playerStats[player]
	return stats and stats.lifetime or nil
end

function HitTracker.GetSessionStats(player)
	local stats = playerStats[player]
	return stats and stats.session or nil
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS: Specific Stats
-- ═══════════════════════════════════════════════════════════

function HitTracker.GetDealtStats(player, tier, useSession)
	local stats = playerStats[player]
	if not stats then return nil end

	local block = useSession and stats.session or stats.lifetime

	if tier then
		return block.dealt[tier]
	end
	return block.dealt
end

function HitTracker.GetReceivedStats(player, tier, useSession)
	local stats = playerStats[player]
	if not stats then return nil end

	local block = useSession and stats.session or stats.lifetime

	if tier then
		return block.received[tier]
	end
	return block.received
end

function HitTracker.GetTotals(player, useSession)
	local stats = playerStats[player]
	if not stats then return nil end

	local block = useSession and stats.session or stats.lifetime
	return block.totals
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

	return tick() - stats.combat.lastHitDealtTime
end

function HitTracker.GetTimeSinceLastHitReceived(player)
	local stats = playerStats[player]
	if not stats then return math.huge end

	if stats.combat.lastHitReceivedTime == 0 then
		return math.huge
	end

	return tick() - stats.combat.lastHitReceivedTime
end

function HitTracker.GetLastHitDealtTime(player)
	local stats = playerStats[player]
	return stats and stats.combat.lastHitDealtTime or 0
end

function HitTracker.GetLastHitReceivedTime(player)
	local stats = playerStats[player]
	return stats and stats.combat.lastHitReceivedTime or 0
end

function HitTracker.IsInCombat(player, threshold)
	threshold = threshold or 5  -- Default 5 seconds

	local timeSinceDealt = HitTracker.GetTimeSinceLastHitDealt(player)
	local timeSinceReceived = HitTracker.GetTimeSinceLastHitReceived(player)

	return math.min(timeSinceDealt, timeSinceReceived) < threshold
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS: Specific Counts (Shortcuts)
-- ═══════════════════════════════════════════════════════════

function HitTracker.GetKills(player, tier, useSession)
	local dealt = HitTracker.GetDealtStats(player, tier, useSession)
	if not dealt then return 0 end

	if tier then
		return dealt.kills or 0
	end

	-- Sum all tiers
	local total = 0
	for _, tierData in pairs(dealt) do
		total = total + (tierData.kills or 0)
	end
	return total
end

function HitTracker.GetCrits(player, tier, useSession)
	local dealt = HitTracker.GetDealtStats(player, tier, useSession)
	if not dealt then return 0 end

	if tier then
		return dealt.crits or 0
	end

	local total = 0
	for _, tierData in pairs(dealt) do
		total = total + (tierData.crits or 0)
	end
	return total
end

function HitTracker.GetHitsDealt(player, tier, useSession)
	local dealt = HitTracker.GetDealtStats(player, tier, useSession)
	if not dealt then return 0 end

	if tier then
		return dealt.hits or 0
	end

	local total = 0
	for _, tierData in pairs(dealt) do
		total = total + (tierData.hits or 0)
	end
	return total
end

function HitTracker.GetHitsReceived(player, tier, useSession)
	local received = HitTracker.GetReceivedStats(player, tier, useSession)
	if not received then return 0 end

	if tier then
		return received.hits or 0
	end

	local total = 0
	for _, tierData in pairs(received) do
		total = total + (tierData.hits or 0)
	end
	return total
end

-- ═══════════════════════════════════════════════════════════
-- RESOURCE MANAGER INTEGRATION
-- ═══════════════════════════════════════════════════════════

function HitTracker.NotifyResourceManager(player, eventType, hitData)
	local ResourceManager = Modules:FindFirstChild("ResourceManager")
	if not ResourceManager then return end

	local rm = require(ResourceManager)

	if eventType == "HitDealt" and rm.OnHitDealt then
		rm.OnHitDealt(player, hitData)
	elseif eventType == "HitReceived" and rm.OnHitReceived then
		rm.OnHitReceived(player, hitData)
	end
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════

function HitTracker.GetDebugInfo(player)
	local stats = playerStats[player]
	if not stats then return "No stats for player" end

	local lt = stats.lifetime.totals
	local st = stats.session.totals
	local combo = stats.combo

	local lines = {
		"=== HitTracker Debug ===",
		"--- Lifetime ---",
		"Hits Dealt: " .. lt.hitsDealt,
		"Damage Dealt: " .. math.floor(lt.damageDealt),
		"Kills: " .. lt.kills,
		"Crits: " .. lt.crits,
		"Hits Received: " .. lt.hitsReceived,
		"Damage Received: " .. math.floor(lt.damageReceived),
		"--- Session ---",
		"Hits Dealt: " .. st.hitsDealt,
		"Kills: " .. st.kills,
		"--- Combo ---",
		"Current: " .. combo.current,
		"Best (Session): " .. combo.best,
		"Best (Lifetime): " .. combo.bestLifetime,
		"--- Combat ---",
		"In Combat: " .. tostring(HitTracker.IsInCombat(player)),
		"Time Since Hit: " .. string.format("%.1f", HitTracker.GetTimeSinceLastHitDealt(player)) .. "s",
	}

	return table.concat(lines, "\n")
end

return HitTracker