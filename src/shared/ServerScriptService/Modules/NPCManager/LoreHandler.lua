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

local LoreHandler = {}

local NPCManager    = nil
local NetworkManager = nil

function LoreHandler.Init(npcMgr, netMgr)
	NPCManager    = npcMgr
	NetworkManager = netMgr
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
	end
end

return LoreHandler
