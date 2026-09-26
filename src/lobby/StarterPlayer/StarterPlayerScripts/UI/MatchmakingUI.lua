-- UI/MatchmakingUI.lua
--[[
    Matchmaking status indicator.
    
    Listens for "MatchmakingUpdate" from server and shows:
      • "Queued…"           — waiting for match
      • "Starting in N…"    — countdown in progress
      • "Launching…"        — about to transition
      • "Cancelled"         — match cancelled
      • "Error: …"          — something went wrong
    
    Cancel button fires "MatchmakingRequest" → { action = "Cancel" }.
    
    Shown as a small bar near the top of the screen. Self-hides
    when not matchmaking.

    §AGX/UI-P4: the status text is a sticky Notify banner ("matchmaking"
    priority, key "matchmaking"); this component keeps the state machine
    and renders only the Cancel / Retry / Close controls, directly under
    Notify's banner slot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local SharedModules  = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
local Notify         = require(Players.LocalPlayer:WaitForChild("PlayerScripts")
	:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("Notify"))  -- §AGX/UI-P4

-- ── Palette ───────────────────────────────────────────────
local C = {
	bg      = Color3.fromRGB( 18,  18,  24),
	accent  = Color3.fromRGB(105, 190, 255),
	green   = Color3.fromRGB( 50, 170,  80),
	red     = Color3.fromRGB(170,  50,  50),
	yellow  = Color3.fromRGB(255, 210,  60),
	text    = Color3.fromRGB(220, 220, 230),
	white   = Color3.fromRGB(255, 255, 255),
}

-- §AGX/X14: if the server never teleports us (TeleportInitFailed without
-- a follow-up, lost Error packet, …) "Launching" used to stick forever.
local LAUNCH_TIMEOUT = 20

local STATUS_COLORS = {
	Queued     = C.accent,
	Countdown  = C.yellow,
	Launching  = C.green,
	Cancelled  = C.red,
	Error      = C.red,
}

-- ── Main Component ────────────────────────────────────────
local function MatchmakingUI()
	local mmState, setMmState = React.useState(nil)
	-- mmState = { status, seconds, message, mode }

	React.useEffect(function()
		local mounted = true
		local conn = NetworkManager.OnServerEvent("MatchmakingUpdate", function(data)
			-- data = { status, seconds?, message?, mode? }
			if data.status == "Launched" or data.status == "Cancelled" then
				-- Show briefly, then hide
				setMmState(data)
				task.delay(2, function()
					if mounted then setMmState(nil) end
				end)
			else
				setMmState(data)
			end
		end)
		return function()
			mounted = false
			if conn then conn:Disconnect() end
		end
	end, {})

	-- §AGX/X14: client-side Launching timeout. Re-armed on every new
	-- server update (each is a fresh table); cleared when state changes.
	React.useEffect(function()
		if not mmState or mmState.status ~= "Launching" then return end
		local alive = true
		local launched = mmState
		task.delay(LAUNCH_TIMEOUT, function()
			if not alive then return end
			setMmState({
				status     = "Error",
				message    = "Teleport timed out.",
				mode       = launched.mode,
				difficulty = launched.difficulty,
			})
		end)
		return function() alive = false end
	end, { mmState })

	-- §AGX/UI-P4: controls go under Notify's banner slot (same maths).
	local L = Notify.useLayout()

	local status  = mmState and mmState.status or "Queued"
	local color   = STATUS_COLORS[status] or C.text
	local message = ""

	if not mmState then
		message = ""
	elseif status == "Queued" then
		message = "Queued for " .. tostring(mmState.mode or "match") .. "…"
	elseif status == "Countdown" then
		message = tostring(mmState.mode or "Match") .. " starts in " .. tostring(mmState.seconds or mmState.countdown or "?")  --[[ §AGX/X14: server sends `countdown` ]] .. "…"
	elseif status == "Launching" then
		message = "Launching " .. tostring(mmState.mode or "match") .. "!"
	elseif status == "Cancelled" then
		-- §AGX/X15: show the server's reason (e.g. "Party changed — queue cancelled.")
		message = mmState.message or "Matchmaking cancelled."
	elseif status == "Error" then
		message = mmState.message or "An error occurred."
	end

	-- §AGX/UI-P4: the status line is a Notify banner. Sticky while this
	-- state lasts (Launched/Cancelled still hide after 2 s, the Launching
	-- timeout still turns into an Error); an empty message (e.g. the
	-- "Launched" status, which used to show an empty bar) clears it.
	React.useEffect(function()
		if message ~= "" then
			Notify.banner(message, {
				key = "matchmaking", priority = "matchmaking", sticky = true, color = color,
			})
		else
			Notify.clearBanner("matchmaking")
		end
	end, { message, color })
	React.useEffect(function()
		return function() Notify.clearBanner("matchmaking") end
	end, {})

	if not mmState then
		return nil
	end

	local showCancel = (status == "Queued" or status == "Countdown")
	-- §AGX/X14: errors that carry a mode came from a failed/timed-out
	-- launch → offer Retry (re-queue same mode + tier). Every error gets a
	-- Close button; before this an Error banner could never be dismissed.
	local isError  = (status == "Error")
	local showRetry = isError and mmState.mode ~= nil
	if not (showCancel or isError) then
		return nil  -- §AGX/UI-P4: nothing to press; the banner says it all
	end

	-- §AGX/UI-P4: one row of controls centred under the banner slot, with
	-- the same fonts / tap floor as Notify (L.body, L.dismiss >= 44 px).
	local btnH = L.dismiss
	local btnW = math.max(96, 5 * L.body)
	local function controlBtn(order, text, bg, onActivated)
		return React.createElement("TextButton", {
			Size             = UDim2.fromOffset(btnW, btnH),
			BackgroundColor3 = bg,
			BorderSizePixel  = 0,
			Text             = text,
			TextColor3       = C.white,
			Font             = Enum.Font.GothamBold,
			TextSize         = L.body,
			LayoutOrder      = order,
			[React.Event.Activated] = onActivated,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
		})
	end

	return React.createElement("Frame", {
		Name                   = "MatchmakingUI",
		AnchorPoint            = Vector2.new(0.5, 0),
		Position               = UDim2.new(0.5, 0, 0, L.bannerY + L.bannerH + 8),
		Size                   = UDim2.fromOffset(L.bannerW, btnH),
		BackgroundTransparency = 1,
		ZIndex                 = 25,
	}, {
		layout = React.createElement("UIListLayout", {
			FillDirection       = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment   = Enum.VerticalAlignment.Center,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Padding             = UDim.new(0, 8),
		}),

		-- Cancel button
		cancelBtn = showCancel and controlBtn(1, "Cancel", C.red, function()
			NetworkManager.FireServer("MatchmakingRequest", { action = "Cancel" })
		end) or nil,

		-- §AGX/X14: Retry after a failed / timed-out launch. The server
		-- re-validates everything (leader, level, IsQueued/launching).
		retryBtn = showRetry and controlBtn(2, "Retry", C.green, function()
			NetworkManager.FireServer("MatchmakingRequest", {
				action     = "Queue",
				mode       = mmState.mode,
				difficulty = mmState.difficulty,
			})
		end) or nil,

		-- §AGX/X14: Close dismisses the error banner (and clears any stale
		-- queue entry server-side; Cancel is a no-op if there is none).
		closeBtn = isError and controlBtn(3, "Close", C.red, function()
			NetworkManager.FireServer("MatchmakingRequest", { action = "Cancel" })
			setMmState(nil)
		end) or nil,
	})
end

return MatchmakingUI
