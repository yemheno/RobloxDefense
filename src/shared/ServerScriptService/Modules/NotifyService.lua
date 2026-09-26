-- ServerScriptService/Modules/NotifyService
--[[
    §AGX/UI-P4: server side of Notify (ARCHITECTURE.md#notify, P4;
    structure-and-flow UX-11 / §3.4). One server→client push event,
    "Notify", so a player-facing rejection is SEEN instead of only
    `warn`ed (closes the §DISC/D8 "no server→client feedback channel" gap).

    API (target = a Player, "all", or an array of Players):
        NotifyService.Toast(target, kind, text, opts?)
            kind = "info"|"success"|"warning"|"error"; opts.key, opts.duration
        NotifyService.Banner(target, text, opts?)
            opts.subtitle, opts.priority ("bossPhase"|"runState"|"vote"|"wave"|
            "matchmaking"|"achievement"|number), opts.key, opts.duration,
            opts.sticky, opts.color (Color3)
        NotifyService.Feed(target, text, opts?)
            opts.key (same key updates the line), opts.color, opts.duration
        NotifyService.Inline(player, requestEventName, ok, text)
            answers a client useRequest(requestEventName) in-panel

    Client: UI/Common/Notify.lua renders all of these.

    Contract for callers: every function is fire-and-forget and NEVER
    throws (pcall-wrapped), so adding a call next to an existing `return`
    can't change that code path's logic. No Init needed; the "Notify"
    event is pre-registered by the NetworkManager manifest.

    Rate limiting (server-side, per player, 1 s window): the client never
    fires this event, so the manifest's OnClientEvent limiter doesn't apply;
    instead each kind has an outgoing budget, and an identical toast text
    within DEDUPE_WINDOW is dropped (the client also coalesces by key).
    Not ready-gated: every current producer answers a client action, so the
    client is already listening; a boot-time push would just be missed.
]]

local NotifyService = {}

local Players = game:GetService("Players")

local Modules        = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

local EVENT_NAME    = "Notify"
local MAX_TEXT      = 200
local WINDOW        = 1       -- s
local DEDUPE_WINDOW = 0.75    -- s: same toast text to the same player
local BUDGET = {              -- sends / player / WINDOW
	toast  = 4,
	banner = 3,
	feed   = 12,
	inline = 8,
}
local TOAST_KINDS = { info = true, success = true, warning = true, error = true }

-- buckets[player][kind] = { start, count }; lastToast[player] = { text, t }
local buckets   = {}
local lastToast = {}

Players.PlayerRemoving:Connect(function(player)
	buckets[player]   = nil
	lastToast[player] = nil
end)

local function allow(player, kind)
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local b = perPlayer[kind]
	if not b or (now - b.start) >= WINDOW then
		perPlayer[kind] = { start = now, count = 1 }
		return true
	end
	b.count += 1
	return b.count <= (BUDGET[kind] or 4)
end

local function clampText(text)
	local s = tostring(text or "")
	if #s > MAX_TEXT then s = string.sub(s, 1, MAX_TEXT - 1) .. "…" end
	return s
end

local function isPlayer(v)
	return typeof(v) == "Instance" and v:IsA("Player") and v.Parent == Players
end

local function resolveTargets(target)
	if target == "all" then return Players:GetPlayers() end
	if isPlayer(target) then return { target } end
	if type(target) == "table" then
		local list = {}
		for _, p in ipairs(target) do
			if isPlayer(p) then table.insert(list, p) end
		end
		return list
	end
	return {}
end

local function push(target, payload)
	local ok, err = pcall(function()
		for _, player in ipairs(resolveTargets(target)) do
			local send = allow(player, payload.kind)
			if send and payload.kind == "toast" then
				local now, last = os.clock(), lastToast[player]
				if last and last.text == payload.text and (now - last.t) < DEDUPE_WINDOW then
					send = false
				else
					lastToast[player] = { text = payload.text, t = now }
				end
			end
			if send then
				NetworkManager.FireClient(player, EVENT_NAME, payload)
			end
		end
	end)
	if not ok then
		warn("[NotifyService] push failed:", err)
	end
end

function NotifyService.Toast(target, kind, text, opts)
	opts = opts or {}
	push(target, {
		kind     = "toast",
		level    = TOAST_KINDS[kind] and kind or "info",
		text     = clampText(text),
		key      = opts.key,
		duration = opts.duration,
	})
end

function NotifyService.Banner(target, text, opts)
	opts = opts or {}
	push(target, {
		kind     = "banner",
		text     = clampText(text),
		subtitle = opts.subtitle and clampText(opts.subtitle) or nil,
		priority = opts.priority,
		key      = opts.key,
		duration = opts.duration,
		sticky   = opts.sticky,
		color    = opts.color,
	})
end

function NotifyService.Feed(target, text, opts)
	opts = opts or {}
	push(target, {
		kind     = "feed",
		text     = clampText(text),
		key      = opts.key,
		color    = opts.color,
		duration = opts.duration,
	})
end

function NotifyService.Inline(player, request, ok, text)
	push(player, {
		kind    = "inline",
		request = tostring(request),
		ok      = ok ~= false,
		text    = clampText(text),
	})
end

--- Loader compatibility (PlaceBootstrap Load() calls Init when present).
function NotifyService.Init() end

return NotifyService
