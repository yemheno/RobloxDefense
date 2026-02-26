-- ServerScriptService/Modules/NPCManager/NPCRegistry
--[[
    Generic NPC registry — holds whatever list of NPCs the current place provides.

    This module contains NO hardcoded NPCs.
    Each place supplies its own NPC definitions when calling NPCManager.Init():

        NPCManager.Init({ npcs = require(LobbyNPCRegistry) })

    This means:
      • Lobby loads LobbyNPCRegistry    → village NPCs appear
      • LaneDefense loads nothing       → no NPCs spawn
      • Future modes load their own registry as needed

    NPC definition schema:
      id          — unique string  (e.g. "blacksmith")
      name        — display name
      title       — sub-title      (e.g. "Blacksmith")
      npcType     — "Shop" | "Quest" | "Lore" | "Teleport"
      scene       — scene tag for filtering (e.g. "Village")
      position    — Vector3 spawn position
      rotation    — (optional) Y-axis rotation in degrees
      color       — (optional) BrickColor for placeholder model
      (+ type-specific fields: shopItems / quests / dialogue / destinations)
]]

local NPCRegistry = {}

local npcs  = {}   -- populated by SetNPCs()
local byId  = {}

-- ═══════════════════════════════════════════════════════════
-- SETUP (called by NPCManager.Init)
-- ═══════════════════════════════════════════════════════════

function NPCRegistry.SetNPCs(list)
	npcs  = list or {}
	byId  = {}
	for _, npc in ipairs(npcs) do
		byId[npc.id] = npc
	end
	print("[NPCRegistry] Loaded", #npcs, "NPC definitions")
end

-- ═══════════════════════════════════════════════════════════
-- QUERIES
-- ═══════════════════════════════════════════════════════════

function NPCRegistry.GetAll()
	return npcs
end

function NPCRegistry.Get(npcId)
	return byId[npcId]
end

function NPCRegistry.GetByScene(sceneName)
	local result = {}
	for _, npc in ipairs(npcs) do
		if npc.scene == sceneName then
			table.insert(result, npc)
		end
	end
	return result
end

function NPCRegistry.GetByType(npcType)
	local result = {}
	for _, npc in ipairs(npcs) do
		if npc.npcType == npcType then
			table.insert(result, npc)
		end
	end
	return result
end

function NPCRegistry.GetCount()
	return #npcs
end

return NPCRegistry
