-- ServerScriptService/Modules/NPCManager/TeleportHandler
--[[
    Handles Teleport-type NPC interactions.
    
    Shows available destinations to the player.
    On selection, moves the player's character to the destination
    (within the same place) via SceneManager or direct CFrame move.
    
    Future: Could also trigger TeleportService for cross-place travel.
]]

local TeleportHandler = {}

local NPCManager    = nil
local NetworkManager = nil
local SceneManager  = nil  -- optional; provided only in places that use it (e.g. Lobby)

function TeleportHandler.Init(npcMgr, netMgr, sceneMgr)
	NPCManager    = npcMgr
	NetworkManager = netMgr
	SceneManager  = sceneMgr  -- may be nil in places that don't use scene switching
	print("[TeleportHandler] Initialized (SceneManager:", SceneManager ~= nil and "yes" or "no", ")")
end

-- ═══════════════════════════════════════════════════════════
-- INTERACTION
-- ═══════════════════════════════════════════════════════════

function TeleportHandler.OnInteract(player, def)
	local destinations = def.destinations or {}

	-- If no destinations, just show dialogue
	if #destinations == 0 and def.dialogue then
		-- Fall through to LoreHandler-style dialogue
		local LoreHandler = require(script.Parent:WaitForChild("LoreHandler"))
		LoreHandler.OnInteract(player, def)
		return
	end

	-- Build destination list for client
	local destList = {}
	for _, dest in ipairs(destinations) do
		table.insert(destList, {
			name  = dest.name,
			scene = dest.scene,
		})
	end

	NetworkManager.FireClient(player, "NPCTeleportOffer", {
		npcId        = def.id,
		npcName      = def.name,
		destinations = destList,
	})

	print("[TeleportHandler]", player.Name, "viewing teleport options from", def.name)
end

-- ═══════════════════════════════════════════════════════════
-- RESPONSE
-- ═══════════════════════════════════════════════════════════

function TeleportHandler.OnResponse(player, def, data)
	if data.action == "Teleport" then
		TeleportHandler.HandleTeleport(player, def, data.destinationIndex)
	elseif data.action == "Close" then
		-- nothing
	end
end

function TeleportHandler.HandleTeleport(player, def, destIndex)
	local destinations = def.destinations or {}
	local dest = destinations[destIndex]
	if not dest then
		warn("[TeleportHandler] Invalid destination index:", destIndex)
		return
	end

	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	-- If destination has a specific position, move there
	if dest.position then
		rootPart.CFrame = CFrame.new(dest.position) + Vector3.new(0, 3, 0)
		print("[TeleportHandler]", player.Name, "teleported to", dest.name)
	end

	-- If destination is a different scene, use SceneManager (if available in this place)
	if dest.scene then
		if SceneManager then
			SceneManager.SetScene(player, dest.scene)
		else
			warn("[TeleportHandler] dest.scene set but no SceneManager provided to Init — ignored")
		end
	end

	NetworkManager.FireClient(player, "NPCDialogue", {
		npcId   = def.id,
		type    = "TeleportComplete",
		message = "Arrived at " .. dest.name .. ".",
	})
end

return TeleportHandler
