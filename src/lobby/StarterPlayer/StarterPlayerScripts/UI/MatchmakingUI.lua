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
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local SharedModules  = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

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

	if not mmState then
		return nil
	end

	local status  = mmState.status or "Queued"
	local color   = STATUS_COLORS[status] or C.text
	local message = ""

	if status == "Queued" then
		message = "Queued for " .. tostring(mmState.mode or "match") .. "…"
	elseif status == "Countdown" then
		message = tostring(mmState.mode or "Match") .. " starts in " .. tostring(mmState.seconds or "?") .. "…"
	elseif status == "Launching" then
		message = "Launching " .. tostring(mmState.mode or "match") .. "!"
	elseif status == "Cancelled" then
		message = "Matchmaking cancelled."
	elseif status == "Error" then
		message = mmState.message or "An error occurred."
	end

	local showCancel = (status == "Queued" or status == "Countdown")

	return React.createElement("Frame", {
		Name                   = "MatchmakingUI",
		AnchorPoint            = Vector2.new(0.5, 0),
		Position               = UDim2.fromScale(0.5, 0.03),
		Size                   = UDim2.fromScale(0.38, 0.065),
		BackgroundColor3       = C.bg,
		BackgroundTransparency = 0.08,
		BorderSizePixel        = 0,
		ZIndex                 = 25,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.25, 0) }),

		-- Status text
		statusLabel = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.04, 0),
			Size                   = UDim2.fromScale(showCancel and 0.62 or 0.92, 1),
			BackgroundTransparency = 1,
			Text                   = message,
			TextColor3             = color,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}),

		-- Cancel button
		cancelBtn = showCancel and React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0.5),
			Position         = UDim2.fromScale(0.96, 0.5),
			Size             = UDim2.fromScale(0.26, 0.65),
			BackgroundColor3 = C.red,
			BorderSizePixel  = 0,
			Text             = "Cancel",
			TextColor3       = C.white,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			[React.Event.Activated] = function()
				NetworkManager.FireServer("MatchmakingRequest", { action = "Cancel" })
			end,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
		}) or nil,
	})
end

return MatchmakingUI
