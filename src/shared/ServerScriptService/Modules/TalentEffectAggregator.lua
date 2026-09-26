-- ServerScriptService/Modules/TalentEffectAggregator
--[[
    Reads allocated talent nodes and pushes aggregated stat bonuses
    into BonusManager under the "talent" source.

    Keystone rules are stored separately and can be queried by other
    systems (e.g. DamageSystem checking "DeadeyePassive").

    API
    ═══
    TalentEffectAggregator.Rebuild(player, allocatedSet)
        Full rebuild — iterates ALL allocated nodes.

    TalentEffectAggregator.OnNodeAllocated(player, nodeDef, allocatedSet)
        Incremental add — faster than full rebuild.

    TalentEffectAggregator.OnNodeRefunded(player, nodeDef, allocatedSet)
        Incremental remove.

    TalentEffectAggregator.HasRule(player, ruleName) → boolean
        Check if a keystone rule is active for this player.
]]

local TalentEffectAggregator = {}

local Modules = script.Parent

-- Lazy-load
local BonusManager = nil
local TreeConfig   = nil

local function getBonusManager()
	if not BonusManager then BonusManager = require(Modules:WaitForChild("BonusManager")) end
	return BonusManager
end

local function getTreeConfig()
	if not TreeConfig then
		local RS = game:GetService("ReplicatedStorage")
		TreeConfig = require(RS:WaitForChild("Shared"):WaitForChild("TalentTreeConfig"))
	end
	return TreeConfig
end

-- ── §AGX/X11: unimplemented keystone penalties ─────────────
-- IMPLEMENTED_RULES is the set of keystone rule names with gameplay code
-- behind them. It is empty today. The canonical table lives in
-- TalentTreeConfig (shared, so the "(coming soon)" UI tag derives from
-- the same set); this is the same table, not a copy — add rule names
-- there. A node whose rule is NOT implemented has its negative `value`
-- effects skipped (positive ones, if any, still apply), so a keystone is a
-- neutral pick until its rule ships instead of a pure nerf. Skips are
-- applied identically in Rebuild / OnNodeAllocated / OnNodeRefunded so
-- incremental add/remove stays symmetric.
local IMPLEMENTED_RULES = nil
local function getImplementedRules()
	if not IMPLEMENTED_RULES then
		IMPLEMENTED_RULES = getTreeConfig().IMPLEMENTED_RULES or {}
	end
	return IMPLEMENTED_RULES
end

local function nodeRuleUnimplemented(nodeDef)
	local implemented = getImplementedRules()
	for _, eff in ipairs(nodeDef.effects) do
		if eff.rule and not implemented[eff.stat] then
			return true
		end
	end
	return false
end

--- §AGX/X11: should this value effect be skipped for this node?
local function isNeutralisedPenalty(eff, ruleUnimplemented)
	return ruleUnimplemented and type(eff.value) == "number" and eff.value < 0
end

-- ── Per-player rule set ───────────────────────────────────
-- playerRules[player] = { [ruleName] = true, ... }
local playerRules = {}

-- ═══════════════════════════════════════════════════════════
-- FULL REBUILD
-- ═══════════════════════════════════════════════════════════

function TalentEffectAggregator.Rebuild(player, allocatedSet)
	local cfg     = getTreeConfig()
	local nodeMap = cfg.GetNodeMap()

	local bonusTable = {}
	local rules = {}

	for nodeId, _ in pairs(allocatedSet) do
		local node = nodeMap[nodeId]
		if node and node.effects then
			local ruleUnimplemented = nodeRuleUnimplemented(node) -- §AGX/X11
			for _, eff in ipairs(node.effects) do
				if eff.rule then
					-- Keystone boolean flag
					rules[eff.stat] = true
				elseif isNeutralisedPenalty(eff, ruleUnimplemented) then
					-- §AGX/X11: penalty of a no-op keystone: skip it.
				elseif eff.primary then
					-- Primary stat bonus (e.g. { primary = "MIG", value = 1 })
					-- Stored as BonusMIG / BonusVIT / etc. so StatsManager can read them
					-- before deriving class stats.
					local key = "Bonus" .. eff.primary
					bonusTable[key] = (bonusTable[key] or 0) + eff.value
				elseif eff.value then
					bonusTable[eff.stat] = (bonusTable[eff.stat] or 0) + eff.value
				end
			end
		end
	end

	playerRules[player] = rules
	getBonusManager().SetSourceBonuses(player, "talent", bonusTable)
end

-- ═══════════════════════════════════════════════════════════
-- INCREMENTAL  — avoids full-walk on single node changes
-- ═══════════════════════════════════════════════════════════

function TalentEffectAggregator.OnNodeAllocated(player, nodeDef, _allocatedSet)
	if not nodeDef or not nodeDef.effects then return end

	local bm = getBonusManager()
	if not playerRules[player] then playerRules[player] = {} end

	local ruleUnimplemented = nodeRuleUnimplemented(nodeDef) -- §AGX/X11
	for _, eff in ipairs(nodeDef.effects) do
		if eff.rule then
			playerRules[player][eff.stat] = true
		elseif isNeutralisedPenalty(eff, ruleUnimplemented) then
			-- §AGX/X11: penalty of a no-op keystone: never applied.
		elseif eff.primary then
			bm.ModifySourceBonus(player, "talent", "Bonus" .. eff.primary, eff.value)
		elseif eff.value then
			bm.ModifySourceBonus(player, "talent", eff.stat, eff.value)
		end
	end
end

function TalentEffectAggregator.OnNodeRefunded(player, nodeDef, _allocatedSet)
	if not nodeDef or not nodeDef.effects then return end

	local bm = getBonusManager()
	if not playerRules[player] then playerRules[player] = {} end

	local ruleUnimplemented = nodeRuleUnimplemented(nodeDef) -- §AGX/X11
	for _, eff in ipairs(nodeDef.effects) do
		if eff.rule then
			playerRules[player][eff.stat] = nil
		elseif isNeutralisedPenalty(eff, ruleUnimplemented) then
			-- §AGX/X11: was never applied, so nothing to remove.
		elseif eff.primary then
			bm.ModifySourceBonus(player, "talent", "Bonus" .. eff.primary, -eff.value)
		elseif eff.value then
			bm.ModifySourceBonus(player, "talent", eff.stat, -eff.value)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- RULE QUERIES  (used by DamageSystem, SkillEffects, etc.)
-- ═══════════════════════════════════════════════════════════

--- Is a keystone passive rule active for this player?
function TalentEffectAggregator.HasRule(player, ruleName)
	local rules = playerRules[player]
	return rules ~= nil and rules[ruleName] == true
end

--- Get all active rules for a player → { [ruleName] = true }
function TalentEffectAggregator.GetActiveRules(player)
	return playerRules[player] or {}
end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════

function TalentEffectAggregator.CleanupPlayer(player)
	playerRules[player] = nil
end

function TalentEffectAggregator.Init()
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		TalentEffectAggregator.CleanupPlayer(player)
	end)
end

return TalentEffectAggregator
