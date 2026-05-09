-- StarterPlayerScripts/Modules/ResourceCache.lua
--[[
    Connects to the "ResourceUpdate" RemoteEvent as early as possible —
    specifically before any React component mounts — so Roblox's internal
    per-client event queue never accumulates unread messages.

    Design
    ──────
    • The module self-initialises the moment it is first required (via
      task.spawn) so it works whether the bootstrap or the UI script happens
      to require it first.
    • Calling Init() a second time is a no-op (idempotent).
    • Provides GetLatest() for initial UI state seeding and Subscribe() for
      live updates.
]]

local ResourceCache = {}

local Players = game:GetService("Players")

-- Always-fresh snapshot (safe defaults before first event)
local cached = { cur = 0, max = 100, name = "Resource" }

-- Lightweight pub-sub
local subscribers = {}

-- Guard against double-init
local initialised = false

-- ── Internal: wire up the actual listener ────────────────────────────────────

local function DoInit()
	if initialised then return end
	initialised = true

	-- Connect DIRECTLY to the RemoteEvent instead of going through
	-- NetworkManager.  This module can be required by the UI mount script
	-- before LobbyClient has called NetworkManager.Init(), so eventsFolder
	-- would be nil at that point.  Using WaitForChild on ReplicatedStorage
	-- is always safe regardless of init order.
	local RS = game:GetService("ReplicatedStorage")
	local eventsFolder = RS:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[ResourceCache] Events folder not found — ResourceUpdate listener not connected")
		return
	end

	local event = eventsFolder:WaitForChild("ResourceUpdate", 10)
	if not event then
		warn("[ResourceCache] ResourceUpdate event not found")
		return
	end

	event.OnClientEvent:Connect(function(data)
		cached = {
			cur  = data.current or 0,
			max  = data.max     or 100,
			name = data.name    or "Resource",
		}
		for _, cb in ipairs(subscribers) do
			cb(cached)
		end
	end)

	print("[ResourceCache] Initialized — ResourceUpdate listener connected early")
end

-- Self-initialise immediately when this module is first required.
-- task.spawn avoids blocking require() but still runs before the first
-- Roblox frame in which ResourceUpdate could arrive.
task.spawn(DoInit)

-- ── Public API ────────────────────────────────────────────────────────────────

--- Returns the most recent resource snapshot (or defaults before first event).
function ResourceCache.GetLatest()
	return {
		cur  = cached.cur,
		max  = cached.max,
		name = cached.name,
	}
end

--- Register a callback for every future update.
--- Returns an unsubscribe function.
function ResourceCache.Subscribe(callback)
	table.insert(subscribers, callback)
	return function()
		for i, cb in ipairs(subscribers) do
			if cb == callback then
				table.remove(subscribers, i)
				return
			end
		end
	end
end

--- Called by the bootstrap module loader (idempotent — DoInit already ran).
function ResourceCache.Init()
	DoInit()  -- no-op if already done
end

return ResourceCache
