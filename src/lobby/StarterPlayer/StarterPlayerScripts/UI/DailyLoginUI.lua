-- lobby/UI/DailyLoginUI.lua
--[[
    Minimal Daily Login panel.
    On mount: requests current status from server.
    Claim button calls ClaimDailyLogin.

    Props:
      onClose  function
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
local AppWindow      = require(PlayerScripts:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("AppWindow"))  -- §T10/U3
local useRequest     = require(PlayerScripts:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("useRequest"))  -- §AGX/UI-P4

local C = {
	bg     = Color3.fromRGB(18, 18, 24),
	panel  = Color3.fromRGB(26, 26, 38),
	text   = Color3.fromRGB(220, 220, 230),
	dim    = Color3.fromRGB(140, 140, 160),
	gold   = Color3.fromRGB(255, 200, 60),
	green  = Color3.fromRGB(50, 170, 80),
	grey   = Color3.fromRGB(60, 60, 75),
	close  = Color3.fromRGB(180, 50, 50),
}

local function DailyLoginUI(props)
	local onClose = props.onClose or function() end

	local status, setStatus       = React.useState(nil)

	-- §AGX/UI-P4: the claim result is useRequest's inline state (was a
	-- resultMsg + DailyLoginResult listener + 3 s clear timer). Same texts,
	-- same 3 s hold, status re-fetched after every result. New: "Claiming…"
	-- while pending, a timeout error after 4 s, and the button is inert
	-- while a claim is in flight.
	local claimReq = useRequest("ClaimDailyLogin", {
		reply       = "DailyLoginResult",
		pendingText = "Claiming…",
		holdFor     = 3,
		match       = function(data)
			if type(data) ~= "table" then return nil end
			if data.ok then
				return true, "Claimed!  +" .. table.concat(data.rewards or {}, ",  ")
			end
			return false, data.reason or "Failed."
		end,
		onResult    = function()
			NetworkManager.FireServer("GetDailyLoginStatus")
		end,
	})
	local resultMsg = claimReq.message

	React.useEffect(function()
		local mounted = true
		NetworkManager.FireServer("GetDailyLoginStatus")

		local conn1 = NetworkManager.OnServerEvent("DailyLoginStatus", function(data)
			if mounted then setStatus(data) end
		end)

		return function()
			mounted = false
			if conn1 then conn1:Disconnect() end
		end
	end, {})

	-- §AGX/X47: calendar (casual, never resets) + spree (consecutive days).
	local streakText  = status and string.format("Calendar day %d/30  ·  Spree: %d day%s",
		status.calendarDay or 1, status.streak or 0, (status.streak == 1) and "" or "s") or "Loading…"
	local rewardText  = (status and status.nextReward) and table.concat(status.nextReward, ",  ") or "—"
	local canClaim    = status and status.canClaim == true

	-- §T10/U3: chrome owned by AppWindow. (The old close button here was
	-- 0.018×0.031 scale ≈ a dozen pixels — the "incredibly small" one.)
	return React.createElement(AppWindow, {
		variant = "windowed",
		title   = "Daily Login",
		icon    = "dailyLogin",
		onClose = onClose,
		size    = UDim2.fromScale(0.38, 0.46),
		-- §AGX/UI-P1: T7: 0.38x0.46 is 320x179 on an iPhone; with the 48 px
		-- header floor the body would be ~130 px. Pixel floor for phones;
		-- 1080p (730x497) is above it, so desktop is unchanged. The 12x12
		-- close is fixed centrally in AppWindow (44x44 floor).
		minSize = Vector2.new(360, 260),
		zIndex  = 10,
	}, {
			streakLbl = React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.05, 0.22),
				Size                   = UDim2.fromScale(0.90, 0.13),
				BackgroundTransparency = 1,
				Text                   = streakText,
				TextColor3             = C.text,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
				ZIndex                 = 12,
			}, {
				minText = React.createElement("UITextSizeConstraint", { MinTextSize = 12 }),  -- §AGX/UI-P1: 12 px text floor
			}),

			rewardCaption = React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.05, 0.38),
				Size                   = UDim2.fromScale(0.90, 0.09),
				BackgroundTransparency = 1,
				Text                   = "Today's reward:",
				TextColor3             = C.dim,
				Font                   = Enum.Font.Gotham,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
				ZIndex                 = 12,
			}, {
				minText = React.createElement("UITextSizeConstraint", { MinTextSize = 12 }),  -- §AGX/UI-P1: 12 px text floor
			}),

			rewardValue = React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.05, 0.47),
				Size                   = UDim2.fromScale(0.90, 0.12),
				BackgroundTransparency = 1,
				Text                   = rewardText,
				TextColor3             = C.gold,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
				ZIndex                 = 12,
			}, {
				minText = React.createElement("UITextSizeConstraint", { MinTextSize = 12 }),  -- §AGX/UI-P1: 12 px text floor
			}),

			feedback = resultMsg and React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.05, 0.60),
				Size                   = UDim2.fromScale(0.90, 0.09),
				BackgroundTransparency = 1,
				Text                   = resultMsg,
				-- §AGX/UI-P4: colour follows the request state (was always green).
				TextColor3             = (claimReq.state == "err") and Color3.fromRGB(255, 110, 110)
					or (claimReq.state == "pending") and C.dim
					or Color3.fromRGB(100, 220, 120),
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Center,
				ZIndex                 = 12,
			}, {
				minText = React.createElement("UITextSizeConstraint", { MinTextSize = 12 }),  -- §AGX/UI-P1: 12 px text floor
			}) or nil,

			claimBtn = React.createElement("TextButton", {
				AnchorPoint      = Vector2.new(0.5, 1),
				Position         = UDim2.fromScale(0.5, 0.94),
				Size             = UDim2.fromScale(0.55, 0.14),
				BackgroundColor3 = canClaim and C.green or C.grey,
				BorderSizePixel  = 0,
				Text             = canClaim and "Claim Reward" or "Already Claimed",
				TextColor3       = Color3.fromRGB(255, 255, 255),
				Font             = Enum.Font.GothamBold,
				TextScaled       = true,
				Active           = canClaim,
				ZIndex           = 12,
				[React.Event.Activated] = function()
					if canClaim and not claimReq.pending then  -- §AGX/UI-P4: no double claim
						claimReq.send()  -- §AGX/UI-P4: fires ClaimDailyLogin
					end
				end,
			}, {
				-- §AGX/UI-P1: 44 px tap floor (0.14 of a phone body was ~30 px).
				minSize = React.createElement("UISizeConstraint", { MinSize = Vector2.new(0, 44) }),
				minText = React.createElement("UITextSizeConstraint", { MinTextSize = 12 }),
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
			}),
	})
end

return DailyLoginUI
