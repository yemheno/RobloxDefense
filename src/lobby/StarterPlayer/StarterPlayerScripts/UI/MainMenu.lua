-- UI/MainMenu.lua
--[[
    The main game menu overlay.
    Opened from a burger-style button in the upper-left corner.
    
    Shows:
      • Game mode cards (Defense available, 3 future modes grayed out)
      • "Play" button on available modes → fires MatchmakingRequest
      • Close button
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React = require(ReplicatedStorage.Packages.React)

local Shared         = require(ReplicatedStorage:WaitForChild("Shared"))
local SharedModules  = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

local DifficultyConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DifficultyConfig"))

-- ── Palette ───────────────────────────────────────────────
local C = {
	overlay     = Color3.fromRGB( 10,  10,  16),
	card_bg     = Color3.fromRGB( 26,  26,  38),
	card_locked = Color3.fromRGB( 20,  20,  28),
	accent      = Color3.fromRGB(105, 190, 255),
	green       = Color3.fromRGB( 50, 180,  80),
	red         = Color3.fromRGB(180,  50,  50),
	orange      = Color3.fromRGB(220, 150,  40),
	purple      = Color3.fromRGB(160,  60, 200),
	text        = Color3.fromRGB(220, 220, 230),
	text_dim    = Color3.fromRGB(100, 100, 120),
	white       = Color3.fromRGB(255, 255, 255),
	locked_text = Color3.fromRGB( 70,  70,  90),
}

-- Difficulty tier display info
local DIFFICULTY_TIERS = {
	{ key = "Normal",    label = "Normal",    color = C.green,  order = 1 },
	{ key = "Hard",      label = "Hard",      color = C.orange, order = 2 },
	{ key = "Nightmare", label = "Nightmare", color = C.purple, order = 3 },
}

-- ── Mode card definitions ─────────────────────────────────
local MODES = {
	{ id = "Defense",     name = "Defense",     desc = "Defend the line against waves.",              available = true,  order = 1 },
	-- §AGX/X19: hidden until the boss arena has content (TODO §17 / §CB1) —
	-- players could queue into an empty arena with no way back.
	-- §AGX/X28: core fight now exists. FLIP HERE (and GameModeConfig.lua
	-- CentralBoss.available) to `true` after Studio testing.
	{ id = "CentralBoss", name = "Central Boss", desc = "Collaborate to take down a central boss.",   available = false, order = 2 },
	{ id = "HordeMode",   name = "Horde Mode",   desc = "Survive endless waves of enemies.",          available = true,  order = 3 },
	{ id = "Arena",       name = "Arena",        desc = "PvP Arena — Coming soon.",                   available = false, order = 4 },
	{ id = "Raid",        name = "Raid",         desc = "Cooperative boss raids — Coming soon.",      available = false, order = 5 },
	{ id = "Exploration", name = "Exploration",  desc = "Open-world zones — Coming soon.",            available = false, order = 6 },
}

-- ── Mode Card ─────────────────────────────────────────────
local function ModeCard(props)
	local mode      = props.mode
	local isAvail   = mode.available
	local bg        = isAvail and C.card_bg or C.card_locked
	local textColor = isAvail and C.text or C.locked_text
	local descColor = isAvail and C.text_dim or C.locked_text
	local selectedDifficulty = props.difficulty or "Normal"
	local onDifficultyChange = props.onDifficultyChange
	local onPlay = props.onPlay

	-- Build difficulty picker buttons (only for available modes)
	local diffChildren = {}
	if isAvail then
		diffChildren.layout = React.createElement("UIListLayout", {
			FillDirection       = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment   = Enum.VerticalAlignment.Center,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Padding             = UDim.new(0.02, 0),
		})
		for i, tier in ipairs(DIFFICULTY_TIERS) do
			local isSelected = (tier.key == selectedDifficulty)
			diffChildren["diff" .. i] = React.createElement("TextButton", {
				Size             = UDim2.fromScale(0.30, 0.85),
				BackgroundColor3 = isSelected and tier.color or C.card_locked,
				BorderSizePixel  = 0,
				Text             = tier.label,
				TextColor3       = isSelected and C.white or C.text_dim,
				Font             = Enum.Font.GothamBold,
				TextScaled       = true,
				LayoutOrder      = tier.order,
				[React.Event.Activated] = function()
					if onDifficultyChange then
						onDifficultyChange(tier.key)
					end
				end,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
			})
		end
	end

	return React.createElement("Frame", {
		Size             = UDim2.fromScale(1, 1),
		BackgroundColor3 = bg,
		BorderSizePixel  = 0,
		LayoutOrder      = mode.order,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.08, 0) }),
		stroke = isAvail and React.createElement("UIStroke", {
			Color     = C.accent,
			Thickness = 1,
		}) or nil,

		pad = React.createElement("UIPadding", {
			PaddingLeft   = UDim.new(0.04, 0),
			PaddingRight  = UDim.new(0.04, 0),
			PaddingTop    = UDim.new(0.04, 0),
			PaddingBottom = UDim.new(0.04, 0),
		}),

		title = React.createElement("TextLabel", {
			Size                   = UDim2.fromScale(0.50, 0.35),
			Position               = UDim2.fromScale(0, 0),
			BackgroundTransparency = 1,
			Text                   = mode.name,
			TextColor3             = textColor,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}),

		desc = React.createElement("TextLabel", {
			Size                   = UDim2.fromScale(0.50, 0.25),
			Position               = UDim2.fromScale(0, 0.35),
			BackgroundTransparency = 1,
			Text                   = mode.desc,
			TextColor3             = descColor,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
			TextWrapped            = true,
		}),

		-- Difficulty picker row (bottom-left for available modes)
		diffRow = isAvail and React.createElement("Frame", {
			Position               = UDim2.fromScale(0, 0.65),
			Size                   = UDim2.fromScale(0.60, 0.32),
			BackgroundTransparency = 1,
		}, diffChildren) or nil,

		-- Play button (right side)
		playBtn = isAvail and React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0.5),
			Position         = UDim2.fromScale(1, 0.5),
			Size             = UDim2.fromScale(0.22, 0.55),
			BackgroundColor3 = C.green,
			BorderSizePixel  = 0,
			Text             = "Play",
			TextColor3       = C.white,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			[React.Event.Activated] = function()
				NetworkManager.FireServer("MatchmakingRequest", {
					action     = "Queue",
					mode       = mode.id,
					difficulty = selectedDifficulty,
				})
				if onPlay then
					onPlay(mode.id, selectedDifficulty)
				end
			end,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
		}) or React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(1, 0.5),
			Position               = UDim2.fromScale(1, 0.5),
			Size                   = UDim2.fromScale(0.24, 0.5),
			BackgroundTransparency = 1,
			Text                   = "Locked",
			TextColor3             = C.locked_text,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
		}),
	})
end

-- ── Main Menu component ───────────────────────────────────
local function MainMenu(props)
	local onClose = props.onClose
	local onPlay = props.onPlay
	local selectedDifficulty, setSelectedDifficulty = React.useState("Normal")

	return React.createElement("Frame", {
		Name                   = "MainMenu",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundColor3       = C.overlay,
		BackgroundTransparency = 0.15,
		ZIndex                 = 10,
	}, {
		-- Title
		title = React.createElement("TextLabel", {
			AnchorPoint      = Vector2.new(0.5, 0),
			Position         = UDim2.fromScale(0.5, 0.06),
			Size             = UDim2.fromScale(0.3, 0.08),
			BackgroundTransparency = 1,
			Text             = "Game Modes",
			TextColor3       = C.accent,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			ZIndex           = 11,
		}),

		-- Close button
		closeBtn = React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0),
			Position         = UDim2.fromScale(0.96, 0.03),
			Size             = UDim2.fromScale(0.06, 0.06),
			BackgroundColor3 = C.red,
			BorderSizePixel  = 0,
			Text             = "X",
			TextColor3       = C.white,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			ZIndex           = 11,
			[React.Event.Activated] = onClose,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
		}),

		-- Mode cards container
		cardContainer = React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = UDim2.fromScale(0.5, 0.52),
			Size             = UDim2.fromScale(0.62, 0.84),
			BackgroundTransparency = 1,
			ZIndex           = 11,
		}, {
			layout = React.createElement("UIListLayout", {
				FillDirection     = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder         = Enum.SortOrder.LayoutOrder,
				Padding           = UDim.new(0.01, 0),
			}),

			-- Available game modes
			mode1 = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 0.145), LayoutOrder = 1, BackgroundTransparency = 1,
			}, { card = React.createElement(ModeCard, {
				mode = MODES[1],
				difficulty = selectedDifficulty,
				onDifficultyChange = setSelectedDifficulty,
				onPlay = onPlay,
			}) }),

			mode2 = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 0.145), LayoutOrder = 2, BackgroundTransparency = 1,
			}, { card = React.createElement(ModeCard, {
				mode = MODES[2],
				difficulty = selectedDifficulty,
				onDifficultyChange = setSelectedDifficulty,
				onPlay = onPlay,
			}) }),

			mode3 = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 0.145), LayoutOrder = 3, BackgroundTransparency = 1,
			}, { card = React.createElement(ModeCard, {
				mode = MODES[3],
				difficulty = selectedDifficulty,
				onDifficultyChange = setSelectedDifficulty,
				onPlay = onPlay,
			}) }),

			-- Coming-soon modes
			mode4 = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 0.145), LayoutOrder = 4, BackgroundTransparency = 1,
			}, { card = React.createElement(ModeCard, { mode = MODES[4] }) }),

			mode5 = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 0.145), LayoutOrder = 5, BackgroundTransparency = 1,
			}, { card = React.createElement(ModeCard, { mode = MODES[5] }) }),

			mode6 = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 0.145), LayoutOrder = 6, BackgroundTransparency = 1,
			}, { card = React.createElement(ModeCard, { mode = MODES[6] }) }),
		}),
	})
end

return MainMenu
