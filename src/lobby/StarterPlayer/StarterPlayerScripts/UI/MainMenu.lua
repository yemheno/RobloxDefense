-- UI/MainMenu.lua
--[[
    The main game menu (mode select), the Lobby "play" panel.

    Shows:
      • Game mode cards (Defense / Horde available, the rest locked)
      • Difficulty picker (Normal / Hard / Nightmare)
      • "Play" → fires MatchmakingRequest { action = "Queue", mode, difficulty }
      • Close (AppWindow ✕)

    §AGX/UI-P6: Theme v2 re-skin. AppWindow chrome (auto: sheet on phone),
    Card per mode, one difficulty row and ONE primary Play CTA for the
    selected mode (was a green Play on every card). The private palette, the
    letter "X" close, the viewport measuring and the AbsoluteSize → Offset
    row floors are gone: everything is design px under UIScaleRoot.Local.
    Same event and payload as before; onPlay(modeId, difficulty) as before.

    Props:
      onClose  function
      onPlay   function(modeId, difficulty)?
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

-- §AGX/UI-P6: shared components.
local Common      = PlayerScripts:WaitForChild("UI"):WaitForChild("Common")
local Theme       = require(Common:WaitForChild("Theme"))
local AppWindow   = require(Common:WaitForChild("AppWindow"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local Button      = require(Common:WaitForChild("Button"))
local Card        = require(Common:WaitForChild("Card"))
local Panel       = require(Common:WaitForChild("Panel"))

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

-- Difficulty tiers
local DIFFICULTY_TIERS = {
	{ key = "Normal",    label = "Normal",    order = 1 },
	{ key = "Hard",      label = "Hard",      order = 2 },
	{ key = "Nightmare", label = "Nightmare", order = 3 },
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

local FIRST_AVAILABLE = "Defense"
for _, m in ipairs(MODES) do
	if m.available then FIRST_AVAILABLE = m.id; break end
end

-- §AGX/UI-P6: design px.
local BAR_H   = Theme.Metrics.button.md + 2 * SP.md   -- bottom action bar
local DIFF_W  = 108
local PLAY_W  = 208

local function MainMenu(props)
	local onClose = props.onClose
	local onPlay = props.onPlay
	local selectedDifficulty, setSelectedDifficulty = React.useState("Normal")
	local selectedMode, setSelectedMode = React.useState(FIRST_AVAILABLE)

	local modeName = selectedMode
	for _, m in ipairs(MODES) do
		if m.id == selectedMode then modeName = m.name end
	end

	local function play()
		NetworkManager.FireServer("MatchmakingRequest", {
			action     = "Queue",
			mode       = selectedMode,
			difficulty = selectedDifficulty,
		})
		if onPlay then
			onPlay(selectedMode, selectedDifficulty)
		end
	end

	-- Mode cards
	local cards = {
		layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding   = UDim.new(0, SP.sm),
		}),
		padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
			PaddingTop = UDim.new(0, SP.md), PaddingBottom = UDim.new(0, SP.md),
		}),
	}
	for _, mode in ipairs(MODES) do
		cards[mode.id] = e(Card, {
			title       = mode.name,
			subtitle    = mode.desc,
			locked      = not mode.available,
			badge       = (not mode.available) and "Soon" or nil,
			selected    = mode.available and mode.id == selectedMode,
			layoutOrder = mode.order,
			onActivated = mode.available and function()
				setSelectedMode(mode.id)
			end or nil,
		})
	end

	-- Difficulty segmented row
	local diffRow = {
		layout = e("UIListLayout", {
			FillDirection     = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder         = Enum.SortOrder.LayoutOrder,
			Padding           = UDim.new(0, SP.sm),
		}),
	}
	for _, tier in ipairs(DIFFICULTY_TIERS) do
		diffRow[tier.key] = e(Button, {
			name        = "Diff_" .. tier.key,
			variant     = "secondary",
			size        = "sm",
			width       = DIFF_W,
			label       = tier.label,
			selected    = tier.key == selectedDifficulty,
			layoutOrder = tier.order,
			onActivated = function()
				setSelectedDifficulty(tier.key)
			end,
		})
	end

	local z = Theme.Z.window

	return e(AppWindow, {
		variant = "auto",
		title   = "Game Modes",
		icon    = "play",
		onClose = onClose,
		size    = UDim2.fromScale(0.62, 0.84),
		minSize = Vector2.new(560, 420),
		zIndex  = z,
	}, {
		scaled = e(UIScaleRoot.Local, { name = "MainMenuBody", zIndex = z + 2 }, {
			list = e("ScrollingFrame", {
				Name                   = "Modes",
				Size                   = UDim2.new(1, 0, 1, -BAR_H),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				CanvasSize             = UDim2.new(0, 0, 0, 0),
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
				ScrollingDirection     = Enum.ScrollingDirection.Y,
				ScrollBarThickness     = Theme.Metrics.scrollBar,
				ScrollBarImageColor3   = R.text.secondary,
				VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
				ZIndex                 = z + 2,
			}, cards),
			-- Bottom action bar: difficulty + the one primary CTA.
			bar = e(Panel, {
				name        = "ActionBar",
				elevation   = "raised",
				radius      = "none",
				padding     = "md",
				stroke      = false,
				anchorPoint = Vector2.new(0, 1),
				position    = UDim2.fromScale(0, 1),
				size        = UDim2.new(1, 0, 0, BAR_H),
				zIndex      = z + 2,
			}, {
				difficulty = e("Frame", {
					Size                   = UDim2.new(1, -(PLAY_W + SP.md), 1, 0),
					BackgroundTransparency = 1,
				}, diffRow),
				play = e(Button, {
					name        = "Play",
					variant     = "primary",
					size        = "md",
					width       = PLAY_W,
					label       = "Play " .. modeName,
					anchorPoint = Vector2.new(1, 0.5),
					position    = UDim2.fromScale(1, 0.5),
					onActivated = play,
				}),
			}),
		}),
	})
end

return MainMenu
