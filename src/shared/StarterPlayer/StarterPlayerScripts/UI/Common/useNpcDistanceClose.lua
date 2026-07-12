-- UI/Common/useNpcDistanceClose.lua
--[[
    useNpcDistanceClose  (§DISC/D8, Pablo: "the UI should close when
    you move too far from the NPC")
    ==================================================================
    React hook: while an NPC panel is open, watch the distance between
    the local character and the NPC model; call onClose when the player
    walks away. Companion to the server's INTERACT_RANGE (12 studs) —
    the close threshold is slightly larger so the panel doesn't flicker
    at the boundary.

    Usage (inside a component):
        useNpcDistanceClose(npcId, isOpen, closeFn)
    npcId may be nil / isOpen false — the hook no-ops (hooks must be
    called unconditionally).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local DEFAULT_CLOSE_DISTANCE = 16
local POLL_SECONDS           = 0.3

return function(npcId, isOpen, onClose, maxDistance)
	maxDistance = maxDistance or DEFAULT_CLOSE_DISTANCE

	React.useEffect(function()
		if not isOpen or not npcId then return end

		local running = true
		task.spawn(function()
			local npcsFolder = workspace:FindFirstChild("NPCs")
			local model = npcsFolder and npcsFolder:FindFirstChild(npcId)
			local npcRoot = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
			if not npcRoot then return end  -- unknown NPC: leave manual close

			while running do
				local char = Players.LocalPlayer.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and npcRoot.Parent
					and (root.Position - npcRoot.Position).Magnitude > maxDistance then
					if running then onClose() end
					break
				end
				task.wait(POLL_SECONDS)
			end
		end)

		return function()
			running = false
		end
	end, { npcId, isOpen })
end
