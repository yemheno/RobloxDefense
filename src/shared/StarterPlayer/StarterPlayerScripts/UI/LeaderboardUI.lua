-- shared/StarterPlayerScripts/UI/LeaderboardUI.lua  (§AGX/UI-P3: shared, its manager loads in every place)
--[[
    Minimal Leaderboard panel.  Three tabs: GearScore, HighestWave, TotalPlayTime.
    Fires GetLeaderboard on mount and on tab switch.
    Also shows the local player's own Gear Score at the bottom.

    Props:
      onClose  function

    §AGX/UI-P6: AppWindow variant "auto" (sheet on phone); body = design px
    inside UIScaleRoot.Local: Common Tabs (blue underline, 44 px) over a
    scrolling list of Panel rows, then a "your score" footer. formatScore
    (§AGX/X27 play time).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
-- §AGX/UI-P6: shared components
local Common      = PlayerScripts:WaitForChild("UI"):WaitForChild("Common")
local AppWindow   = require(Common:WaitForChild("AppWindow"))  -- §T10/U3
local Theme       = require(Common:WaitForChild("Theme"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local Text        = require(Common:WaitForChild("Text"))
local Tabs        = require(Common:WaitForChild("Tabs"))
local Panel       = require(Common:WaitForChild("Panel"))

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

-- §AGX/UI-P6: layout in DESIGN px (phone scale).
local ROW_H    = 44
local RANK_W   = 56
local SCORE_W  = 120
local FOOTER_H = 32
local TABS_H   = Theme.Metrics.tabs.height   -- 44 (§AGX/UI-P1: tap target on a phone)

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

	local tabItems = {}
	for i, board in ipairs(BOARDS) do
		tabItems[i] = { id = board, label = BOARD_LABELS[board] or board }
	end
	local function selectBoard(board)
		if board == activeBoard then return end
		setEntries({})
		setActiveBoard(board)
	end

	-- Entry rows
	local rows = {}
	rows["layout"] = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding   = UDim.new(0, SP.xs),
	})

	if #entries == 0 then
		rows["empty"] = e(Text, {
			style       = "body",
			text        = "Loading…",
			color       = "text.secondary",
			align       = "center",
			size        = UDim2.new(1, 0, 0, 40),
			layoutOrder = 1,
		})
	else
		for i, entry in ipairs(entries) do
			local isSelf = entry.userId == localUserId
			rows["row_" .. i] = e(Panel, {
				name        = "Row_" .. i,
				elevation   = "raised",
				padding     = "none",
				accent      = isSelf and "accent.secondary" or nil,   -- you = blue ring
				size        = UDim2.new(1, 0, 0, ROW_H),
				layoutOrder = i,
			}, {
				rankLbl = e(Text, {
					style = "numeric",
					text  = "#" .. tostring(entry.rank),
					color = (entry.rank or 99) <= 3 and "rarity.legendary" or "text.secondary",
					align = "center",
					size  = UDim2.new(0, RANK_W, 1, 0),
				}),
				nameLbl = e(Text, {
					style    = "label",
					text     = entry.name or "Unknown",
					color    = isSelf and "accent.secondary" or "text.primary",
					position = UDim2.fromOffset(RANK_W, 0),
					size     = UDim2.new(1, -(RANK_W + SCORE_W + SP.md), 1, 0),
				}),
				scoreLbl = e(Text, {
					style       = "numeric",
					text        = formatScore(activeBoard, entry.score),
					align       = "right",
					anchorPoint = Vector2.new(1, 0),
					position    = UDim2.new(1, -SP.md, 0, 0),
					size        = UDim2.new(0, SCORE_W, 1, 0),
				}),
			})
		end
	end

	-- §AGX/UI-P6: the footer is always the local Gear Score (PlayerGearScore
	-- is the only score the server sends), labelled and formatted as such.
	local footerH = myScore and (FOOTER_H + SP.sm) or 0
	local listTop = TABS_H + SP.sm

	-- §T10/U3: chrome owned by AppWindow.
	return e(AppWindow, {
		variant = "auto",
		title   = "Leaderboard",
		icon    = "leaderboard",
		onClose = onClose,
		size    = UDim2.fromScale(0.50, 0.72),
		zIndex  = Theme.Z.window,
	}, {
		content = e(UIScaleRoot.Local, { name = "LeaderboardBody", zIndex = Theme.Z.window + 2 }, {
			pad = e("UIPadding", {
				PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
				PaddingTop = UDim.new(0, SP.sm), PaddingBottom = UDim.new(0, SP.md),
			}),

			tabBar = e(Tabs, {
				items    = tabItems,
				value    = activeBoard,
				onChange = selectBoard,
				size     = UDim2.new(1, 0, 0, TABS_H),
			}),

			listFrame = e("ScrollingFrame", {
				Name                   = "List",
				Position               = UDim2.fromOffset(0, listTop),
				Size                   = UDim2.new(1, 0, 1, -(listTop + footerH)),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				ScrollBarThickness     = Theme.Metrics.scrollBar,
				ScrollBarImageColor3   = R.text.secondary,
				ScrollingDirection     = Enum.ScrollingDirection.Y,
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
				CanvasSize             = UDim2.fromScale(0, 0),
			}, rows),

			myScoreLbl = myScore and e(Text, {
				style       = "label",
				text        = "Your " .. BOARD_LABELS.GearScore .. ": " .. formatScore("GearScore", myScore),
				color       = "accent.secondary",
				anchorPoint = Vector2.new(0, 1),
				position    = UDim2.fromScale(0, 1),
				size        = UDim2.new(1, 0, 0, FOOTER_H),
			}) or nil,
		}),
	})
end

return LeaderboardUI
