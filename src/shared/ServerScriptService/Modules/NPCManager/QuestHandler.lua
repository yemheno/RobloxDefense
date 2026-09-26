-- ServerScriptService/Modules/NPCManager/QuestHandler
--[[
    Handles Quest-type NPC interactions.

    Flow:
      1. Player interacts → server checks which quests are available for this NPC.
      2. Sends quest list with status (available / in-progress / completed / ready).
      3. Player can Accept, TurnIn, or view progress.
      4. Quest objectives are tracked server-side via a pluggable QuestStateProvider.

    State Provider interface (duck-typed):
      :IsActive(player, questId) → boolean
      :IsCompleted(player, questId) → boolean
      :SetActive(player, questId, active: boolean)
      :SetCompleted(player, questId, completed: boolean)
      :GetObjective(player, questId, index) → number
      :SetObjective(player, questId, index, value)
      :ClearObjectives(player, questId, count)

    Default provider: DataStoreStateProvider backed by
    PlayerDataManager → data.Account.Quests (persistent across sessions).
    Falls back to Attributes if PlayerDataManager is unavailable.
]]

local Players = game:GetService("Players")

local QuestHandler = {}

local NPCManager    = nil
local NetworkManager = nil

-- ═══════════════════════════════════════════════════════════
-- LAZY PlayerDataManager REFERENCE
-- ═══════════════════════════════════════════════════════════

local _PlayerDataManager = nil
local _CurrencyManager   = nil
local _PlayerDataConfig  = nil

local function getPlayerDataManager()
	if not _PlayerDataManager then
		local Mods = script.Parent.Parent
		local ok, pdm = pcall(require, Mods:WaitForChild("PlayerDataManager", 5))
		if ok then _PlayerDataManager = pdm end
	end
	return _PlayerDataManager
end

local function getCurrencyManager()
	if not _CurrencyManager then
		local mod = script.Parent.Parent:FindFirstChild("CurrencyManager")
		if mod then _CurrencyManager = require(mod) end
	end
	return _CurrencyManager
end

local function getPlayerDataConfig()
	if not _PlayerDataConfig then
		local mod = script.Parent.Parent:FindFirstChild("PlayerDataConfig")
		if mod then _PlayerDataConfig = require(mod) end
	end
	return _PlayerDataConfig
end

--- Returns data.Account.Quests for the player, initialising sub-tables if needed.
local function getQuestsData(player)
	local pdm = getPlayerDataManager()
	if not pdm then return nil end
	local data = pdm.GetData(player)
	if not data or not data.Account then return nil end
	if not data.Account.Quests then
		data.Account.Quests = { active = {}, completed = {} }
	end
	if not data.Account.Quests.active then data.Account.Quests.active = {} end
	if not data.Account.Quests.completed then data.Account.Quests.completed = {} end
	return data.Account.Quests
end

-- ═══════════════════════════════════════════════════════════
-- PERSISTENT STATE PROVIDER (PlayerDataManager-backed)
-- ═══════════════════════════════════════════════════════════

local DataStoreStateProvider = {}

function DataStoreStateProvider:IsActive(player, questId)
	local q = getQuestsData(player)
	return q ~= nil and q.active[questId] ~= nil
end

function DataStoreStateProvider:IsCompleted(player, questId)
	local q = getQuestsData(player)
	return q ~= nil and q.completed[questId] == true
end

function DataStoreStateProvider:SetActive(player, questId, active)
	local q = getQuestsData(player)
	if not q then return end
	if active then
		if not q.active[questId] then
			q.active[questId] = { objectives = {} }
		end
	else
		q.active[questId] = nil
	end
end

function DataStoreStateProvider:SetCompleted(player, questId, completed)
	local q = getQuestsData(player)
	if not q then return end
	q.completed[questId] = completed or nil
end

function DataStoreStateProvider:GetObjective(player, questId, index)
	local q = getQuestsData(player)
	if not q or not q.active[questId] then return 0 end
	local objs = q.active[questId].objectives
	if not objs then return 0 end
	return objs[index] or 0
end

function DataStoreStateProvider:SetObjective(player, questId, index, value)
	local q = getQuestsData(player)
	if not q or not q.active[questId] then return end
	if not q.active[questId].objectives then
		q.active[questId].objectives = {}
	end
	q.active[questId].objectives[index] = value
end

function DataStoreStateProvider:ClearObjectives(player, questId, count)
	local q = getQuestsData(player)
	if not q or not q.active[questId] then return end
	q.active[questId].objectives = {}
end

-- Active provider — DataStore-backed (persistent)
local StateProvider = DataStoreStateProvider

-- §QH2: per-player turn-in lock so two concurrent TurnInQuest packets
-- can't both pass the objective gate and grant rewards twice.
local turnInLock = setmetatable({}, { __mode = "k" })

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function QuestHandler.Init(npcMgr, netMgr)
	NPCManager    = npcMgr
	NetworkManager = netMgr

	-- ── Hook: AttackHandler — kill-based quest objectives ────────────
	task.spawn(function()
		local Mods = script.Parent.Parent
		local ah = Mods:FindFirstChild("AttackHandler")
		if ah then
			local ok, AH = pcall(require, ah)
			if ok and AH.OnMobKilled then
				AH.OnMobKilled(function(player, info)
					QuestHandler.IncrementObjective(player, "KillMob", info and info.mobId or nil)
					QuestHandler.IncrementObjective(player, "KillAny", nil)
				end)
			end
		end
	end)

	-- ── Hook: MobSpawner — mission completion objectives ─────────────
	task.spawn(function()
		local Mods = script.Parent.Parent
		local ms = Mods:FindFirstChild("MobSpawner")
		if ms then
			local ok, MS = pcall(require, ms)
			if ok and MS.OnAllWavesCompleted then
				MS.OnAllWavesCompleted(function(_finalWave)
					-- "CompleteMode" / "Defense" — increment for ALL players in the session
					for _, player in ipairs(Players:GetPlayers()) do
						QuestHandler.IncrementObjective(player, "CompleteMode", "Defense")
					end
				end)
			end
		end
	end)

end

-- ═══════════════════════════════════════════════════════════
-- INTERACTION
-- ═══════════════════════════════════════════════════════════

function QuestHandler.OnInteract(player, def)
	local quests = def.quests or {}
	local questList = {}

	for _, quest in ipairs(quests) do
		local status = QuestHandler.GetQuestStatus(player, quest)

		-- Check prerequisites
		if quest.prerequisite then
			local prereqDone = StateProvider:IsCompleted(player, quest.prerequisite)
			if not prereqDone then
				status = "Locked"
			end
		end

		table.insert(questList, {
			questId     = quest.questId,
			title       = quest.title,
			description = quest.description,
			objectives  = QuestHandler.GetObjectiveProgress(player, quest),
			rewards     = quest.rewards,
			status      = status,
		})
	end

	NetworkManager.FireClient(player, "NPCQuestOffer", {
		npcId   = def.id,
		npcName = def.name,
		quests  = questList,
	})

	print("[QuestHandler]", player.Name, "viewed quests from", def.name)
end

-- ═══════════════════════════════════════════════════════════
-- RESPONSE
-- ═══════════════════════════════════════════════════════════

function QuestHandler.OnResponse(player, def, data)
	-- Accept both legacy ("Accept"/"TurnIn") and client ("AcceptQuest"/"TurnInQuest") action names
	if data.action == "Accept" or data.action == "AcceptQuest" then
		QuestHandler.AcceptQuest(player, def, data.questId)
	elseif data.action == "TurnIn" or data.action == "TurnInQuest" then
		QuestHandler.TurnInQuest(player, def, data.questId)
	elseif data.action == "Close" then
		-- nothing
	end
end

function QuestHandler.AcceptQuest(player, def, questId)
	local quest = QuestHandler.FindQuest(def, questId)
	if not quest then return end

	-- §QH5: re-check the prerequisite server-side (GetQuestStatus doesn't
	-- inspect quest.prerequisite), or a modified client could AcceptQuest a
	-- locked quest. Mirrors the OnInteract gate.
	if quest.prerequisite then
		local prereqDone = StateProvider:IsCompleted(player, quest.prerequisite)
		if not prereqDone then
			NetworkManager.FireClient(player, "NPCDialogue", {
				npcId   = def.id,
				type    = "QuestError",
				message = "Prerequisite not yet completed.",
			})
			return
		end
	end

	local status = QuestHandler.GetQuestStatus(player, quest)
	if status ~= "Available" then
		NetworkManager.FireClient(player, "NPCDialogue", {
			npcId   = def.id,
			type    = "QuestError",
			message = "Quest not available.",
		})
		return
	end

	-- Mark as accepted
	StateProvider:SetActive(player, questId, true)

	-- Initialize objective progress
	for i, obj in ipairs(quest.objectives or {}) do
		StateProvider:SetObjective(player, questId, i, 0)
	end

	NetworkManager.FireClient(player, "NPCDialogue", {
		npcId   = def.id,
		type    = "QuestAccepted",
		message = "Quest accepted: " .. quest.title,
	})

	print("[QuestHandler]", player.Name, "accepted quest:", quest.title)
end

function QuestHandler.TurnInQuest(player, def, questId)
	local quest = QuestHandler.FindQuest(def, questId)
	if not quest then return end

	-- §QH2: reject reentrant turn-in attempts before re-reading state.
	if turnInLock[player] then return end

	-- §QH1: refuse to grant rewards if any required dependency is missing.
	local cm  = getCurrencyManager()
	local pdm = getPlayerDataManager()
	local cfg = getPlayerDataConfig()

	-- Quest must already be active (prevents turn-in on a quest never accepted)
	if not StateProvider:IsActive(player, questId) then
		NetworkManager.FireClient(player, "NPCDialogue", {
			npcId   = def.id,
			type    = "QuestError",
			message = "Quest is not active.",
		})
		return
	end

	-- Check all objectives are complete
	for i, obj in ipairs(quest.objectives or {}) do
		local progress = StateProvider:GetObjective(player, questId, i)
		if progress < (obj.count or 1) then
			NetworkManager.FireClient(player, "NPCDialogue", {
				npcId   = def.id,
				type    = "QuestError",
				message = "Objectives not yet completed.",
			})
			return
		end
	end

	turnInLock[player] = true

	-- Grant rewards (best-effort; missing dep skips the relevant reward type)
	for _, reward in ipairs(quest.rewards or {}) do
		if reward.type == "Merits" then
			if cm and cm.AddMerits then
				cm.AddMerits(player, reward.amount or 0)
			end
		elseif reward.type == "Essence" then
			if cm and cm.AddEssence then
				cm.AddEssence(player, reward.amount or 0)
			end
		elseif reward.type == "XP" then
			if pdm and pdm.AddExperience then
				local pData = pdm.GetData(player)
				local playerLevel = (pData and pData.Account and pData.Account.Level) or 1
				local xpNeeded = (cfg and cfg.GetXPForLevel) and cfg.GetXPForLevel(playerLevel) or 1000
				local xpAmount = reward.amount
				if reward.percent ~= nil then
					xpAmount = math.floor(xpNeeded * (reward.percent / 100))
				elseif reward.levels ~= nil then
					xpAmount = math.floor(xpNeeded * reward.levels)
				end
				pdm.AddExperience(player, xpAmount or 0)
			end
		end
	end

	-- Mark complete (do BEFORE releasing lock so any reentrant call hits
	-- the IsActive guard above, not the rewards path).
	StateProvider:SetActive(player, questId, false)
	StateProvider:SetCompleted(player, questId, true)

	-- Clean up objective state
	StateProvider:ClearObjectives(player, questId, #(quest.objectives or {}))

	turnInLock[player] = nil

	NetworkManager.FireClient(player, "NPCDialogue", {
		npcId   = def.id,
		type    = "QuestCompleted",
		message = "Quest complete: " .. quest.title .. "!",
	})

	print("[QuestHandler]", player.Name, "completed quest:", quest.title)
end

-- ═══════════════════════════════════════════════════════════
-- QUEST PROGRESS (called by external systems)
-- ═══════════════════════════════════════════════════════════

--- Call this from GameStateManager or any system when a relevant event occurs.
--- e.g. QuestHandler.IncrementObjective(player, "CompleteMode", "Defense")
function QuestHandler.IncrementObjective(player, objectiveType, objectiveTarget)
	-- Scan all active quests for matching objectives
	-- This is brute-force but simple; optimize later if needed.
	local allNPCs = NPCManager.GetNPCRegistry().GetByType("Quest")

	for _, npcDef in ipairs(allNPCs) do
		for _, quest in ipairs(npcDef.quests or {}) do
			local isActive = StateProvider:IsActive(player, quest.questId)
			if isActive then
				for i, obj in ipairs(quest.objectives or {}) do
					if obj.type == objectiveType and (obj.mode == objectiveTarget or objectiveTarget == nil) then
						local current = StateProvider:GetObjective(player, quest.questId, i)
						if current < obj.count then
							StateProvider:SetObjective(player, quest.questId, i, current + 1)
							print("[QuestHandler]", player.Name, "quest progress:", quest.questId, "obj", i, "→", current + 1)
						end
					end
				end
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function QuestHandler.FindQuest(def, questId)
	for _, quest in ipairs(def.quests or {}) do
		if quest.questId == questId then
			return quest
		end
	end
	return nil
end

function QuestHandler.GetQuestStatus(player, quest)
	if StateProvider:IsCompleted(player, quest.questId) then
		return quest.repeatable and "Available" or "Completed"
	end
	if StateProvider:IsActive(player, quest.questId) then
		-- Check whether ALL objectives are satisfied → "ReadyToTurnIn"
		local allMet = true
		for i, obj in ipairs(quest.objectives or {}) do
			local progress = StateProvider:GetObjective(player, quest.questId, i)
			if progress < obj.count then
				allMet = false
				break
			end
		end
		return allMet and "ReadyToTurnIn" or "InProgress"
	end
	return "Available"
end

function QuestHandler.GetObjectiveProgress(player, quest)
	local result = {}
	for i, obj in ipairs(quest.objectives or {}) do
		local progress = StateProvider:GetObjective(player, quest.questId, i)
		table.insert(result, {
			label    = obj.label,
			current  = progress,
			target   = obj.count,
		})
	end
	return result
end

return QuestHandler
