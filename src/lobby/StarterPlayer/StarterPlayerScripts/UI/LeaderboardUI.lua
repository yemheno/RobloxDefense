-- lobby/UI/LeaderboardUI.lua
--[[
    Minimal Leaderboard panel.  Three tabs: GearScore, HighestWave, TotalPlayTime.
    Fires GetLeaderboard on mount and on tab switch.
    Also shows the local player's own Gear Score at the bottom.

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

local C = {
	bg      = Color3.fromRGB(18, 18, 24),
	row     = Color3.fromRGB(32, 32, 46),
	rowSelf = Color3.fromRGB(26, 40, 60),
	text    = Color3.fromRGB(220, 220, 230),
	dim     = Color3.fromRGB(140, 140, 160),
	gold    = Color3.fromRGB(255, 200, 60),
	blue    = Color3.fromRGB(80, 160, 255),
	tabOn   = Color3.fromRGB(60, 80, 120),
	tabOff  = Color3.fromRGB(30, 30, 42),
	close   = Color3.fromRGB(180, 50, 50),
}

local BOARDS = { "GearScore", "HighestWave", "TotalPlayTime" }

-- §AGX/X27: TotalPlayTime is stored in seconds — show it as hours/minutes.
local BOARD_LABELS = { GearScore = "Gear Score", HighestWave = "Highest Wave", TotalPlayTime = "Play Time" }
local function formatScore(board, score)
	score = tonumber(score) or 0
	if board == "TotalPlayTime" then
		local h = math.floor(score / 3600)
		local m = math.floor((score % 3600) / 60)
		return h > 0 and string.format("%dh %02dm", h, m) or string.format("%dm", m)
	end
	return tostring(score)
end
local localUserId = Players.LocalPlayer.UserId

local function LeaderboardUI(props)
	local onClose = props.onClose or function() end

	local activeBoard, setActiveBoard = React.useState("GearScore")
	local entries, setEntries         = React.useState({})
	local myScore, setMyScore         = React.useState(nil)

	React.useEffect(function()
		local mounted = true

		local conn1 = NetworkManager.OnServerEvent("LeaderboardData", function(data)
			if mounted and data.board == activeBoard then
				setEntries(data.entries or {})
			end
		end)

		local conn2 = NetworkManager.OnServerEvent("PlayerGearScore", function(data)
			if mounted then setMyScore(data.score) end
		end)

		NetworkManager.FireServer("GetLeaderboard", activeBoard)
		NetworkManager.FireServer("PlayerGearScore")

		return function()
			mounted = false
			if conn1 then conn1:Disconnect() end
			if conn2 then conn2:Disconnect() end
		end
	end, { activeBoard })

	-- Tab buttons
	local tabs = {}
	for i, board in ipairs(BOARDS) do
		local isActive = board == activeBoard
		tabs["tab_" .. i] = React.createElement("TextButton", {
			Size             = UDim2.fromScale(1 / #BOARDS, 1),
			BackgroundColor3 = isActive and C.tabOn or C.tabOff,
			BorderSizePixel  = 0,
			Text             = board,
			TextColor3       = isActive and C.blue or C.dim,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			LayoutOrder      = i,
			ZIndex           = 12,
			[React.Event.Activated] = function()
				setEntries({})
				setActiveBoard(board)
			end,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.15, 0) }),
		})
	end

	local tabBarChildren = {
		layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0.01, 0),
		}),
	}
	for key, value in pairs(tabs) do
		tabBarChildren[key] = value
	end

	-- Entry rows
	local rows = {}
	rows["layout"] = React.createElement("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding   = UDim.new(0, 3),
	})

	if #entries == 0 then
		rows["empty"] = React.createElement("TextLabel", {
			Size                   = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Text                   = "Loading…",
			TextColor3             = C.dim,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
			LayoutOrder            = 1,
		})
	else
		for i, entry in ipairs(entries) do
			local isSelf = entry.userId == localUserId
			rows["row_" .. i] = React.createElement("Frame", {
				Size             = UDim2.new(1, 0, 0, 34),
				BackgroundColor3 = isSelf and C.rowSelf or C.row,
				BorderSizePixel  = 0,
				LayoutOrder      = i,
			}, {
				corner   = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
				rankLbl  = React.createElement("TextLabel", {
					Position               = UDim2.fromScale(0.01, 0),
					Size                   = UDim2.fromScale(0.10, 1),
					BackgroundTransparency = 1,
					Text                   = "#" .. tostring(entry.rank),
					TextColor3             = (entry.rank or 99) <= 3 and C.gold or C.dim,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
				}),
				nameLbl  = React.createElement("TextLabel", {
					Position               = UDim2.fromScale(0.13, 0),
					Size                   = UDim2.fromScale(0.62, 1),
					BackgroundTransparency = 1,
					Text                   = entry.name or "Unknown",
					TextColor3             = isSelf and C.blue or C.text,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
					TextXAlignment         = Enum.TextXAlignment.Left,
				}),
				scoreLbl = React.createElement("TextLabel", {
					Position               = UDim2.fromScale(0.76, 0),
					Size                   = UDim2.fromScale(0.22, 1),
					BackgroundTransparency = 1,
					Text                   = formatScore(activeBoard, entry.score),
					TextColor3             = C.text,
					Font                   = Enum.Font.Gotham,
					TextScaled             = true,
					TextXAlignment         = Enum.TextXAlignment.Right,
				}),
			})
		end
	end

	-- §T10/U3: chrome owned by AppWindow (this file had the other
	-- ~12-pixel close button).
	return React.createElement(AppWindow, {
		variant = "windowed",
		title   = "Leaderboard",
		icon    = "leaderboard",
		onClose = onClose,
		size    = UDim2.fromScale(0.50, 0.72),
		zIndex  = 10,
	}, {
			myScoreLbl = myScore and React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.04, 0.91),
				Size                   = UDim2.fromScale(0.92, 0.06),
				BackgroundTransparency = 1,
				Text                   = "Your " .. (BOARD_LABELS[activeBoard] or activeBoard) .. ": " .. formatScore(activeBoard, myScore),
				TextColor3             = C.blue,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
				ZIndex                 = 12,
			}) or nil,

			tabBar = React.createElement("Frame", {
				Position               = UDim2.fromScale(0.04, 0.11),
				Size                   = UDim2.fromScale(0.92, 0.07),
				BackgroundTransparency = 1,
				ZIndex                 = 12,
			}, tabBarChildren),

			listFrame = React.createElement("ScrollingFrame", {
				Position              = UDim2.fromScale(0.04, 0.20),
				Size                  = UDim2.fromScale(0.92, myScore and 0.69 or 0.76),
				BackgroundTransparency = 1,
				BorderSizePixel       = 0,
				ScrollBarThickness    = 4,
				AutomaticCanvasSize   = Enum.AutomaticSize.Y,
				CanvasSize            = UDim2.fromScale(0, 0),
				ZIndex                = 12,
			}, rows),
	})
end

return LeaderboardUI
