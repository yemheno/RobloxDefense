-- ServerScriptService/Modules/NPCManager/MatchmakingHandler.lua
--[[
    Handles "Matchmaking" type NPCs.

    On interact   → sends NPCTeleportOffer  to the client,
                     reusing the existing destinations UI to list game modes.
    On response   → receives NPCResponse { action="Teleport", destinationId=modeId }
                     and calls MatchmakingManager.QueueForMode(player, modeId).

    MatchmakingManager is injected via Init() and may be nil in places that
    don't load it (e.g. LaneDefense) — the handler is silently inert in that case.
]]

local MatchmakingHandler = {}

local _NPCManager        = nil
local NetworkManager     = nil
local MatchmakingMgr     = nil   -- lobby-only; nil in LaneDefense

function MatchmakingHandler.Init(npcMgr, netMgr, matchmakingManager)
	_NPCManager    = npcMgr
	NetworkManager = netMgr
	MatchmakingMgr = matchmakingManager  -- may be nil
	print("[MatchmakingHandler] Initialized (MatchmakingManager:",
		MatchmakingMgr ~= nil and "present" or "absent", ")")
end

-- ═══════════════════════════════════════════════════════════
-- INTERACTION  (player presses E near this NPC)
-- ═══════════════════════════════════════════════════════════

function MatchmakingHandler.OnInteract(player, def)
	local modes = def.modes or {}

	-- Build destination list — reuse NPCTeleportOffer UI.
	-- Each "destination" is a playable game mode.
	local destinations = {}
	for _, mode in ipairs(modes) do
		table.insert(destinations, {
			id          = mode.id,
			name        = mode.name        or mode.id,
			description = mode.description or "",
		})
	end

	NetworkManager.FireClient(player, "NPCTeleportOffer", {
		npcId        = def.id,
		npcName      = def.name,
		destinations = destinations,
	})

	print("[MatchmakingHandler]", player.Name, "opened mode select from", def.name)
end

-- ═══════════════════════════════════════════════════════════
-- RESPONSE  (player picks a destination in the UI)
-- ═══════════════════════════════════════════════════════════

function MatchmakingHandler.OnResponse(player, def, data)
	if data.action ~= "Teleport" then return end

	local modeId = data.destinationId
	if not modeId then return end

	if not MatchmakingMgr then
		warn("[MatchmakingHandler] MatchmakingManager not available — ignoring queue request from", player.Name)
		return
	end

	print("[MatchmakingHandler]", player.Name, "requested queue for mode:", modeId)
	MatchmakingMgr.QueueForMode(player, modeId)
end

return MatchmakingHandler
