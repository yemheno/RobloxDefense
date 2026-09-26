-- UI/Common/useRequest.lua
--[[
    §AGX/UI-P4: the "inline" Notify kind (UI_REVAMP §3, structure-and-flow
    §3.4). One hook for in-panel request feedback, replacing the per-panel
    "set label, task.delay(N), clear" timers (UX-11: 2 / 2.5 / 3 / 3.5 s).

        local req = useRequest("NPCResponse", {
            reply       = "NPCDialogue",          -- server event carrying the result
            match       = function(data, payload) -- nil = not ours; else ok, message
                if data.type == "ShopSuccess" then return true, data.message end
                if data.type == "ShopError"   then return false, data.message end
                return nil
            end,
            pendingText = "Purchasing…",
            holdFor     = 3,     -- s an ok/err result stays before going idle
            timeout     = 4,     -- s with no reply → err (default 4)
            onResult    = function(ok, data, payload) end,
        })
        req.send({ npcId = id, action = "Buy", itemId = itemId })
        -- req.state   "idle" | "pending" | "ok" | "err"
        -- req.message text for the current state (nil when idle)
        -- req.reset() back to idle; a late reply is then ignored

    Replies are accepted only while a request is pending. Besides `reply`,
    the hook always listens for NotifyService.Inline(player, eventName, ok,
    text), the generic server answer (closes the §DISC/D8 feedback gap for
    handlers that have no result event of their own).

    With no `match`, a `reply` payload is read as { ok|success, message|reason }.
    `send` while pending supersedes the earlier request (same as the old
    re-click behaviour of the panels it replaces).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local NetworkManager = require(PlayerScripts:WaitForChild("Modules"):WaitForChild("NetworkManager"))
local Notify         = require(script.Parent:WaitForChild("Notify"))

local DEFAULT_TIMEOUT      = 4
local DEFAULT_HOLD         = 3
local DEFAULT_TIMEOUT_TEXT = "No response. Please try again."

local IDLE = { state = "idle", message = nil }

local function defaultMatch(data)
	if type(data) ~= "table" then return nil end
	local ok = data.ok
	if ok == nil then ok = data.success end
	if ok == nil then return nil end
	return ok == true, data.message or data.reason
end

local function useRequest(eventName, opts)
	opts = opts or {}

	local status, setStatus = React.useState(IDLE)

	local optsRef    = React.useRef(opts)
	optsRef.current  = opts
	local eventRef   = React.useRef(eventName)
	eventRef.current = eventName

	local pendingRef = React.useRef(nil)   -- { token, payload }
	local tokenRef   = React.useRef(0)
	local timerRef   = React.useRef(nil)   -- timeout or hold timer thread
	local mountedRef = React.useRef(true)

	local clearTimer = React.useCallback(function()
		if timerRef.current then
			local thread = timerRef.current
			timerRef.current = nil
			if coroutine.status(thread) == "suspended" then
				task.cancel(thread)
			end
		end
	end, {})

	local setIfMounted = React.useCallback(function(value)
		if mountedRef.current then setStatus(value) end
	end, {})

	local settle = React.useCallback(function(ok, message, data)
		local pending = pendingRef.current
		if not pending then return end
		pendingRef.current = nil
		clearTimer()

		local o = optsRef.current
		if o.onResult then
			task.spawn(o.onResult, ok, data, pending.payload)
		end
		setIfMounted({ state = ok and "ok" or "err", message = message })

		local hold = o.holdFor
		if hold == nil then hold = DEFAULT_HOLD end
		if hold > 0 then
			timerRef.current = task.delay(hold, function()
				timerRef.current = nil
				if pendingRef.current == nil then setIfMounted(IDLE) end
			end)
		end
	end, {})

	local send = React.useCallback(function(payload)
		clearTimer()
		tokenRef.current += 1
		local token = tokenRef.current
		pendingRef.current = { token = token, payload = payload }

		local o = optsRef.current
		setIfMounted({ state = "pending", message = o.pendingText })

		timerRef.current = task.delay(o.timeout or DEFAULT_TIMEOUT, function()
			timerRef.current = nil
			local pending = pendingRef.current
			if pending and pending.token == token then
				settle(false, optsRef.current.timeoutText or DEFAULT_TIMEOUT_TEXT, nil)
			end
		end)

		NetworkManager.FireServer(eventRef.current, payload)
	end, {})

	local reset = React.useCallback(function()
		pendingRef.current = nil
		clearTimer()
		setIfMounted(IDLE)
	end, {})

	-- Reply listeners (re-subscribed only if the event names change).
	local replyEvent = opts.reply
	React.useEffect(function()
		local conn = nil
		if type(replyEvent) == "string" then
			conn = NetworkManager.OnServerEvent(replyEvent, function(data)
				local pending = pendingRef.current
				if not pending then return end
				local match = optsRef.current.match or defaultMatch
				local ok, message = match(data, pending.payload)
				if ok == nil then return end
				settle(ok == true, message, data)
			end)
		end
		local unsubInline = Notify.onInline(function(msg)
			if msg.request ~= eventRef.current or not pendingRef.current then return end
			settle(msg.ok ~= false, msg.text, msg)
		end)
		return function()
			if conn then conn:Disconnect() end
			unsubInline()
		end
	end, { replyEvent, eventName })

	React.useEffect(function()
		mountedRef.current = true
		return function()
			mountedRef.current = false
			pendingRef.current = nil
			clearTimer()
		end
	end, {})

	return {
		state   = status.state,
		message = status.message,
		pending = status.state == "pending",
		send    = send,
		reset   = reset,
	}
end

return useRequest
