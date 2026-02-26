-- MovementSystem/Free
--[[
    No-op constraint — represents the absence of movement restrictions.
    Useful as a named mode so callers can explicitly request "free movement".
]]

local Free = {}

function Free.Start(_config)
	-- Default Roblox movement; nothing to override.
end

function Free.Stop()
	-- Nothing to tear down.
end

return Free
