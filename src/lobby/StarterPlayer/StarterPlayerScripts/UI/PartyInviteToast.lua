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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local Players          = game:GetService("Players")
local SharedModules    = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local NetworkManager   = require(SharedModules:WaitForChild("NetworkManager"))

local INVITE_TIMEOUT = 30  -- seconds – matches PartyManager.INVITE_TIMEOUT

local C = {
	bg        = Color3.fromRGB( 22,  28,  44),
	border    = Color3.fromRGB( 60, 100, 200),
	text      = Color3.fromRGB(225, 225, 230),
	text_dim  = Color3.fromRGB(140, 140, 160),
	btn_green = Color3.fromRGB( 45, 175,  95),
	btn_red   = Color3.fromRGB(185,  60,  60),
	btn_x     = Color3.fromRGB( 60,  60,  80),
	close_txt = Color3.fromRGB(180, 180, 200),
}

local function PartyInviteToast()
	-- nil = hidden; { inviterName, inviterUserId } = visible
	local invite, setInvite = React.useState(nil)
	-- countdown seconds remaining
	local timeLeft, setTimeLeft = React.useState(INVITE_TIMEOUT)

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
		return React.createElement("Frame", {
			Size                   = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
		})
	end

	local inviterName = invite.from or invite.inviterName or "Someone"

	return React.createElement("Frame", {
		Name             = "PartyInviteToast",
		AnchorPoint      = Vector2.new(0.5, 1),
		Position         = UDim2.fromScale(0.5, 0.94),
		Size             = UDim2.fromScale(0.34, 0.10),
		BackgroundColor3 = C.bg,
		BorderSizePixel  = 2,
		ZIndex           = 20,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.12, 0) }),

		-- Accent border stroke
		stroke = React.createElement("UIStroke", {
			Color     = C.border,
			Thickness = 2,
		}),

		-- Invite message
		msg = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.04, 0.06),
			Size                   = UDim2.fromScale(0.82, 0.38),
			BackgroundTransparency = 1,
			Text                   = inviterName .. " invited you to their party!",
			TextColor3             = C.text,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
			TextWrapped            = true,
		}),

		-- Timer label
		timerLabel = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.04, 0.46),
			Size                   = UDim2.fromScale(0.50, 0.26),
			BackgroundTransparency = 1,
			Text                   = string.format("Expires in %ds", timeLeft),
			TextColor3             = (timeLeft <= 10) and Color3.fromRGB(255, 120, 80) or C.text_dim,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}),

		-- Accept button
		acceptBtn = React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(0, 1),
			Position         = UDim2.fromScale(0.04, 0.96),
			Size             = UDim2.fromScale(0.38, 0.30),
			BackgroundColor3 = C.btn_green,
			BorderSizePixel  = 0,
			Text             = "✔ Accept",
			TextColor3       = Color3.fromRGB(255, 255, 255),
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			[React.Event.Activated] = function()
				NetworkManager.FireServer("PartyRequest", { action = "AcceptInvite" })
				hideToast()
			end,
		}, {
			React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
		}),

		-- Decline button
		declineBtn = React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(0, 1),
			Position         = UDim2.fromScale(0.45, 0.96),
			Size             = UDim2.fromScale(0.38, 0.30),
			BackgroundColor3 = C.btn_red,
			BorderSizePixel  = 0,
			Text             = "✘ Decline",
			TextColor3       = Color3.fromRGB(255, 255, 255),
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			[React.Event.Activated] = function()
				NetworkManager.FireServer("PartyRequest", { action = "DeclineInvite" })
				hideToast()
			end,
		}, {
			React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
		}),

		-- Dismiss (✕) button
		dismissBtn = React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0),
			Position         = UDim2.fromScale(0.97, 0.04),
			Size             = UDim2.fromScale(0.10, 0.32),
			BackgroundColor3 = C.btn_x,
			BorderSizePixel  = 0,
			Text             = "✕",
			TextColor3       = C.close_txt,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			[React.Event.Activated] = hideToast,
		}, {
			React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
		}),
	})
end

return PartyInviteToast
