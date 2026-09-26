-- UI/Common/usePressHold.lua
--[[
    §AGX/UI-P1v2: usePressHold (docs/ui_audit/mobile.md §2.6): one hook for
    "hover on PC, long-press on touch, selection on gamepad".

        local hold = usePressHold({
            onHold      = function(rbx) ... end,  -- touch held holdTime s (or hover / gamepad select)
            onRelease   = function(fired) ... end, -- press/hover/selection ended
            holdTime    = 0.35,                    -- s (Theme.Metrics.tooltip.holdTime)
            moveCancel  = 10,                      -- px of finger travel that cancels
            hover       = true,                    -- MouseEnter/Leave also drive onHold/onRelease
            mouseHold   = false,                   -- long-press with the mouse too (Studio testing)
        })
        e("TextButton", {
            [React.Event.InputBegan]       = hold.onInputBegan,
            [React.Event.MouseEnter]       = hold.onMouseEnter,
            [React.Event.MouseLeave]       = hold.onMouseLeave,
            [React.Event.SelectionGained]  = hold.onSelectionGained,
            [React.Event.SelectionLost]    = hold.onSelectionLost,
            [React.Event.Activated]        = hold.wrapActivated(onActivated),
        })
        -- or merge hold.events into your props table.

    If a long-press fired, the Activated that follows the finger lifting is
    swallowed by wrapActivated (so "hold to inspect" never also buys/equips).
    Releases are tracked globally (UserInputService), so a finger that slides
    off the element still ends the hold; unmounting mid-press also releases.
    All hooks are unconditional.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local React = require(ReplicatedStorage.Packages.React)

local Theme = require(script.Parent:WaitForChild("Theme"))
local TT = Theme.Metrics.tooltip

local function usePressHold(opts)
	opts = opts or {}
	local optsRef = React.useRef(opts)
	optsRef.current = opts

	local pressRef  = React.useRef(nil)   -- { input, start, thread }
	local firedRef  = React.useRef(false) -- the last press became a hold
	local activeRef = React.useRef(false) -- onHold delivered, onRelease owed

	local function release()
		local press = pressRef.current
		if press and press.thread then
			pcall(task.cancel, press.thread)
		end
		pressRef.current = nil
		if activeRef.current then
			activeRef.current = false
			local o = optsRef.current
			if o.onRelease then o.onRelease(firedRef.current) end
		end
	end

	local function deliver(rbx)
		activeRef.current = true
		local o = optsRef.current
		if o.onHold then o.onHold(rbx) end
	end

	React.useEffect(function()
		local endConn = UserInputService.InputEnded:Connect(function(input)
			local press = pressRef.current
			if not press then return end
			local sameTouch = input == press.input
			local sameMouse = press.input.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1
			if sameTouch or sameMouse then release() end
		end)
		local moveConn = UserInputService.InputChanged:Connect(function(input)
			local press = pressRef.current
			if not press or activeRef.current then return end
			if input ~= press.input and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
			local p = Vector2.new(input.Position.X, input.Position.Y)
			local limit = optsRef.current.moveCancel or TT.moveCancel
			if (p - press.start).Magnitude > limit then
				if press.thread then pcall(task.cancel, press.thread) end
				pressRef.current = nil
			end
		end)
		return function()
			endConn:Disconnect()
			moveConn:Disconnect()
			release()
		end
	end, {})

	local onInputBegan = React.useCallback(function(rbx, input)
		local t = input.UserInputType
		local isTouch = t == Enum.UserInputType.Touch
		local isMouse = t == Enum.UserInputType.MouseButton1 and optsRef.current.mouseHold == true
		if not (isTouch or isMouse) then return end
		if input.UserInputState ~= Enum.UserInputState.Begin then return end
		if pressRef.current then return end
		firedRef.current = false
		local press = { input = input, start = Vector2.new(input.Position.X, input.Position.Y) }
		press.thread = task.delay(optsRef.current.holdTime or TT.holdTime, function()
			if pressRef.current ~= press then return end
			press.thread = nil
			firedRef.current = true
			deliver(rbx)
		end)
		pressRef.current = press
	end, {})

	local onMouseEnter = React.useCallback(function(rbx)
		if optsRef.current.hover == false then return end
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then return end
		deliver(rbx)
	end, {})

	local onMouseLeave = React.useCallback(function()
		if pressRef.current then return end  -- a touch hold owns the release
		release()
	end, {})

	local onSelectionGained = React.useCallback(function(rbx)
		if optsRef.current.hover == false then return end
		deliver(rbx)
	end, {})

	local onSelectionLost = React.useCallback(function()
		release()
	end, {})

	local wrapActivated = React.useCallback(function(fn)
		if not fn then return nil end
		return function(...)
			if firedRef.current then
				firedRef.current = false
				return
			end
			fn(...)
		end
	end, {})

	return {
		onInputBegan      = onInputBegan,
		onMouseEnter      = onMouseEnter,
		onMouseLeave      = onMouseLeave,
		onSelectionGained = onSelectionGained,
		onSelectionLost   = onSelectionLost,
		wrapActivated     = wrapActivated,
		events = {
			[React.Event.InputBegan]      = onInputBegan,
			[React.Event.MouseEnter]      = onMouseEnter,
			[React.Event.MouseLeave]      = onMouseLeave,
			[React.Event.SelectionGained] = onSelectionGained,
			[React.Event.SelectionLost]   = onSelectionLost,
		},
	}
end

return usePressHold
