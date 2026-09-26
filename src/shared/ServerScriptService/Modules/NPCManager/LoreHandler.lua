-- ServerScriptService/Modules/NPCManager/LoreHandler
--[[
    Handles Lore/Dialogue-type NPC interactions.
    
    Dialogue is a simple node graph:
      Each node has { speaker, text, choices }.
      A choice has { label, next } where `next` is the 1-based index of the
      next dialogue node, or 0 / nil to end the conversation.
    
    The entire dialogue tree is sent to the client on interaction.
    The client drives navigation locally; "NPCResponse" with action="Close"
    is sent when the player exits.
]]

local Players = game:GetService("Players")

local LoreHandler = {}

local NPCManager    = nil
local NetworkManager = nil

-- §AGX/WC: lazy PlayerDataManager (same pattern as QuestHandler) so lore
-- flags persist in data.Account.LoreFlags instead of attributes only.
local _PlayerDataManager = nil
local function getPlayerDataManager()
	if not _PlayerDataManager then
		local Mods = script.Parent.Parent
		local ok, pdm = pcall(require, Mods:WaitForChild("PlayerDataManager", 5))
		if ok then _PlayerDataManager = pdm end
	end
	return _PlayerDataManager
end

--- Returns data.Account.LoreFlags for the player (creating it if a legacy
--- save somehow lacks it), or nil if data isn't loaded.
local function getLoreFlags(player)
	local pdm = getPlayerDataManager()
	if not pdm then return nil end
	local data = pdm.GetData(player)
	if not data or not data.Account then return nil end
	if type(data.Account.LoreFlags) ~= "table" then
		data.Account.LoreFlags = {}
	end
	return data.Account.LoreFlags
end

-- §AGX/WC: re-apply persisted flags as TalkedTo_<id> attributes (idempotent).
local function restoreAttributes(player)
	local flags = getLoreFlags(player)
	if not flags then return end
	for npcId, talked in pairs(flags) do
		if talked == true then
			player:SetAttribute("TalkedTo_" .. tostring(npcId), true)
		end
	end
end

function LoreHandler.Init(npcMgr, netMgr)
	NPCManager    = npcMgr
	NetworkManager = netMgr

	-- §AGX/WC: restore lore flags when a player's data loads, plus any
	-- players whose data was already ready before this Init ran.
	local pdm = getPlayerDataManager()
	if pdm and pdm.OnPlayerDataReady then
		pdm.OnPlayerDataReady(restoreAttributes)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		restoreAttributes(player)
	end
end

-- ═══════════════════════════════════════════════════════════
-- INTERACTION
-- ═══════════════════════════════════════════════════════════

function LoreHandler.OnInteract(player, def)
	local dialogue = def.dialogue or {}

	if #dialogue == 0 then
		-- No dialogue defined; send a placeholder
		dialogue = {
			{
				speaker = def.name,
				text    = "...",
				choices = {},
			},
		}
	end

	NetworkManager.FireClient(player, "NPCDialogue", {
		npcId    = def.id,
		npcName  = def.name,
		type     = "Dialogue",
		dialogue = dialogue,
	})

	print("[LoreHandler]", player.Name, "talking to", def.name)
end

-- ═══════════════════════════════════════════════════════════
-- RESPONSE
-- ═══════════════════════════════════════════════════════════

function LoreHandler.OnResponse(player, def, data)
	-- Dialogue navigation is client-driven.
	-- The server only cares about "Close" or special triggers.
	if data.action == "Close" then
		-- Could track "has spoken to" for quest prerequisites
		player:SetAttribute("TalkedTo_" .. def.id, true)
		-- §AGX/WC: persist in data.Account.LoreFlags (saved with the profile).
		local flags = getLoreFlags(player)
		if flags then
			flags[tostring(def.id)] = true  -- string keys only (DataStore-safe)
		end
	end
end

return LoreHandler
