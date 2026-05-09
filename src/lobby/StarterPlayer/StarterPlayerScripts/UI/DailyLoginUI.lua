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
	local resultMsg, setResultMsg = React.useState(nil)

	React.useEffect(function()
		local mounted = true
		NetworkManager.FireServer("GetDailyLoginStatus")

		local conn1 = NetworkManager.OnServerEvent("DailyLoginStatus", function(data)
			if mounted then setStatus(data) end
		end)

		local conn2 = NetworkManager.OnServerEvent("DailyLoginResult", function(data)
			if not mounted then return end
			if data.ok then
				setResultMsg("Claimed!  +" .. table.concat(data.rewards or {}, ",  "))
			else
				setResultMsg(data.reason or "Failed.")
			end
			NetworkManager.FireServer("GetDailyLoginStatus")
			task.delay(3, function()
				if mounted then setResultMsg(nil) end
			end)
		end)

		return function()
			mounted = false
			if conn1 then conn1:Disconnect() end
			if conn2 then conn2:Disconnect() end
		end
	end, {})

	local streakText  = status and ("Day " .. tostring(status.streak) .. "  ·  Total days: " .. tostring(status.totalDays)) or "Loading…"
	local rewardText  = (status and status.nextReward) and table.concat(status.nextReward, ",  ") or "—"
	local canClaim    = status and status.canClaim == true

	return React.createElement("Frame", {
		Name                   = "DailyLoginBackdrop",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundColor3       = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.42,
		ZIndex                 = 10,
	}, {
		panel = React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = UDim2.fromScale(0.5, 0.5),
			Size             = UDim2.fromScale(0.38, 0.46),
			BackgroundColor3 = C.bg,
			BorderSizePixel  = 0,
			ZIndex           = 11,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),

			titleLbl = React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.05, 0.04),
				Size                   = UDim2.fromScale(0.80, 0.12),
				BackgroundTransparency = 1,
				Text                   = "📅  Daily Login",
				TextColor3             = C.gold,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
				ZIndex                 = 12,
			}),

			closeBtn = React.createElement("TextButton", {
				AnchorPoint      = Vector2.new(1, 0),
				Position         = UDim2.fromScale(0.97, 0.04),
				Size             = UDim2.fromScale(0.018, 0.031),
				BackgroundColor3 = C.close,
				BorderSizePixel  = 0,
				Text             = "✕",
				TextColor3       = Color3.fromRGB(255, 255, 255),
				Font             = Enum.Font.GothamBold,
				TextScaled       = true,
				ZIndex           = 12,
				[React.Event.Activated] = onClose,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			}),

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
			}),

			feedback = resultMsg and React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.05, 0.60),
				Size                   = UDim2.fromScale(0.90, 0.09),
				BackgroundTransparency = 1,
				Text                   = resultMsg,
				TextColor3             = Color3.fromRGB(100, 220, 120),
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Center,
				ZIndex                 = 12,
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
					if canClaim then
						NetworkManager.FireServer("ClaimDailyLogin")
					end
				end,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
			}),
		}),
	})
end

return DailyLoginUI
