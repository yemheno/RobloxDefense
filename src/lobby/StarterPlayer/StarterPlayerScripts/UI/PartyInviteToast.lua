-- UI/PartyInviteToast.lua
--
-- Self-managed floating toast that appears when the server sends a
-- "PartyInvite" event. Dismisses automatically after 30 s (matches
-- server INVITE_TIMEOUT) or when the player accepts/declines.
--
-- Network events consumed:
--   PartyInvite  { inviterName, inviterUserId }  → show toast
--   PartyUpdate  (any)                            → hide toast (invite resolved)
-- Network events fired:
--   PartyRequest  { action = "AcceptInvite"  }
--   PartyRequest  { action = "DeclineInvite" }
--
-- §AGX/UI-P6: Theme v2 re-skin. Panel surface, Text, a Bar countdown,
-- Button Accept (the one primary CTA) / Decline, IconButton ✕; design px
-- under UIScaleRoot.Local (T19: every target >= 44). The private palette
-- and the hand-rolled buttons are gone. Same events, same timer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local Players          = game:GetService("Players")
local PlayerScripts    = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules    = PlayerScripts:WaitForChild("Modules")
local NetworkManager   = require(SharedModules:WaitForChild("NetworkManager"))

-- §AGX/UI-P6: shared components.
local Common      = PlayerScripts:WaitForChild("UI"):WaitForChild("Common")
local Theme       = require(Common:WaitForChild("Theme"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local Text        = require(Common:WaitForChild("Text"))
local Button      = require(Common:WaitForChild("Button"))
local IconButton  = require(Common:WaitForChild("IconButton"))
local Panel       = require(Common:WaitForChild("Panel"))
local Bar         = require(Common:WaitForChild("Bar"))

local e  = React.createElement
local SP = Theme.Space

local INVITE_TIMEOUT = 30  -- seconds – matches PartyManager.INVITE_TIMEOUT

-- §AGX/UI-P6: design px.
local TOAST_W  = 400
local TAP      = Theme.Metrics.button.sm   -- 44
local BTN_W    = 150

local function PartyInviteToast()
	-- nil = hidden; { inviterName, inviterUserId } = visible
	local invite, setInvite = React.useState(nil)
	-- countdown seconds remaining
	local timeLeft, setTimeLeft = React.useState(INVITE_TIMEOUT)
	-- §AGX/UI-P6: the countdown's full length (for the Bar).
	local durationRef = React.useRef(INVITE_TIMEOUT)

	-- Ref to cancel the auto-dismiss task
	local timerThread = React.useRef(nil)

	local function hideToast()
		setInvite(nil)
		setTimeLeft(INVITE_TIMEOUT)
		if timerThread.current then
			task.cancel(timerThread.current)
			timerThread.current = nil
		end
	end

	local function startTimer(duration)
		duration = duration or INVITE_TIMEOUT
		durationRef.current = duration
		if timerThread.current then
			task.cancel(timerThread.current)
		end
		setTimeLeft(duration)
		timerThread.current = task.spawn(function()
			for remaining = duration - 1, 0, -1 do
				task.wait(1)
				setTimeLeft(remaining)
				if remaining <= 0 then
					hideToast()
					return
				end
			end
		end)
	end

	React.useEffect(function()
		local connInvite = NetworkManager.OnServerEvent("PartyInvite", function(data)
			setInvite(data)
			startTimer(data.timeout or INVITE_TIMEOUT)
		end)

		-- If party is updated (accepted elsewhere, etc.) auto-hide
		local connParty = NetworkManager.OnServerEvent("PartyUpdate", function()
			hideToast()
		end)

		return function()
			if connInvite then connInvite:Disconnect() end
			if connParty  then connParty:Disconnect()  end
			if timerThread.current then
				task.cancel(timerThread.current)
			end
		end
	end, {})

	-- Nothing to render when not visible
	if not invite then
		return e("Frame", {
			Size                   = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
		})
	end

	local inviterName = invite.from or invite.inviterName or "Someone"
	local urgent = timeLeft <= 10
	local z = Theme.Z.toast

	return e(UIScaleRoot.Local, { name = "PartyInviteToast", zIndex = z }, {
		toast = e(Panel, {
			name        = "Toast",
			elevation   = "raised",
			radius      = "lg",
			padding     = "md",
			layout      = "vertical",
			gap         = "sm",
			accent      = "border.focus",
			autoSize    = "Y",
			anchorPoint = Vector2.new(0.5, 1),
			position    = UDim2.fromScale(0.5, 0.94),
			size        = UDim2.new(0.92, 0, 0, 0),
			zIndex      = z,
		}, {
			maxW = e("UISizeConstraint", { MaxSize = Vector2.new(TOAST_W, math.huge) }),
			-- Row 1: message + ✕
			head = e("Frame", {
				LayoutOrder            = 1,
				Size                   = UDim2.new(1, 0, 0, TAP),
				BackgroundTransparency = 1,
			}, {
				msg = e(Text, {
					style = "label",
					text  = inviterName .. " invited you to their party!",
					wrap  = false,
					size  = UDim2.new(1, -(TAP + SP.sm), 1, 0),
				}),
				dismiss = e(IconButton, {
					name        = "Dismiss",
					icon        = "close",
					variant     = "ghost",
					size        = "sm",
					anchorPoint = Vector2.new(1, 0.5),
					position    = UDim2.fromScale(1, 0.5),
					onActivated = hideToast,
				}),
			}),
			-- Row 2: countdown
			timer = e(Text, {
				style       = "caption",
				text        = string.format("Expires in %ds", timeLeft),
				color       = urgent and "state.warning" or "text.secondary",
				layoutOrder = 2,
				size        = UDim2.new(1, 0, 0, 18),
			}),
			bar = e(Bar, {
				value       = timeLeft,
				max         = math.max(1, durationRef.current),
				kind        = "progress",
				height      = 6,
				layoutOrder = 3,
				size        = UDim2.new(1, 0, 0, 6),
			}),
			-- Row 3: actions
			actions = e("Frame", {
				LayoutOrder            = 4,
				Size                   = UDim2.new(1, 0, 0, TAP),
				BackgroundTransparency = 1,
			}, {
				layout = e("UIListLayout", {
					FillDirection       = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
					SortOrder           = Enum.SortOrder.LayoutOrder,
					Padding             = UDim.new(0, SP.sm),
				}),
				accept = e(Button, {
					name        = "Accept",
					variant     = "primary",
					size        = "sm",
					width       = BTN_W,
					label       = Theme.Glyphs.check .. " Accept",
					layoutOrder = 1,
					onActivated = function()
						NetworkManager.FireServer("PartyRequest", { action = "AcceptInvite" })
						hideToast()
					end,
				}),
				decline = e(Button, {
					name        = "Decline",
					variant     = "secondary",
					size        = "sm",
					width       = BTN_W,
					label       = "Decline",
					layoutOrder = 2,
					onActivated = function()
						NetworkManager.FireServer("PartyRequest", { action = "DeclineInvite" })
						hideToast()
					end,
				}),
			}),
		}),
	})
end

return PartyInviteToast
