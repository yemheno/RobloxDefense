-- shared/StarterPlayerScripts/UI/CombatApp.lua
--[[
    Shared root React component for all combat places
    (LaneDefense, CentralBoss, HordeMode).

    Renders the full combat HUD with:
      - HUD (currency, vitals, resource bars, combo counter)
      - BattleClassUI (compact read-only class badge)
      - StatsMenu, TalentTreeUI, EquipmentUI, WardrobeUI
      - CharacterCreation (first login edge case)
      - TeammateVitals (real-time HP bars for teammates)
      - AchievementsUI, SettingsUI, GlobalShopUI, TestingUI

    Each combat place re-exports this component from a thin wrapper.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules = PlayerScripts:WaitForChild("Modules")
local SharedUI      = PlayerScripts:WaitForChild("UI")

local NetworkManager    = require(SharedModules:WaitForChild("NetworkManager"))
local CharacterCreation = require(SharedUI:WaitForChild("CharacterCreation"))
local HUD               = require(SharedUI:WaitForChild("HUD"))
local StatsMenu         = require(SharedUI:WaitForChild("StatsMenu"))
local TalentTreeUI      = require(SharedUI:WaitForChild("TalentTreeUI"))
local EquipmentUI       = require(SharedUI:WaitForChild("EquipmentUI"))
local WardrobeUI        = require(SharedUI:WaitForChild("WardrobeUI"))
local AchievementsUI    = require(SharedUI:WaitForChild("AchievementsUI"))
local TestingUI         = require(SharedUI:WaitForChild("TestingUI"))
local SettingsUI        = require(SharedUI:WaitForChild("SettingsUI"))
local GlobalShopUI      = require(SharedUI:WaitForChild("GlobalShopUI"))

local BattleClassUI  = require(SharedUI:WaitForChild("BattleClassUI"))
local TeammateVitals = require(SharedUI:WaitForChild("TeammateVitals"))
local DeathUI        = require(SharedUI:WaitForChild("DeathUI"))
local VoteUI         = require(SharedUI:WaitForChild("VoteUI"))

local function CombatApp()
	local showCharCreate, setShowCharCreate = React.useState(false)
	local showClassReference, setShowClassReference = React.useState(false)
	local showStatsMenu,  setShowStatsMenu  = React.useState(false)
	local showTalents,    setShowTalents    = React.useState(false)
	local showEquipment,  setShowEquipment  = React.useState(false)
	local showWardrobe,     setShowWardrobe     = React.useState(false)
	local showAchievements, setShowAchievements = React.useState(false)
	local showSettings,     setShowSettings     = React.useState(false)
	local showShop,         setShowShop         = React.useState(false)

	-- Listen for character creation (edge case: first login on this place)
	React.useEffect(function()
		local conn = NetworkManager.OnServerEvent("CharacterCreationRequired", function()
			setShowCharCreate(true)
		end)
		NetworkManager.FireServer("RequestCharacterStatus")
		return function()
			if conn then conn:Disconnect() end
		end
	end, {})

	local fullscreenOpen = showCharCreate or showClassReference or showStatsMenu or showTalents or showEquipment
		or showWardrobe or showAchievements or showSettings or showShop

	return React.createElement("Frame", {
		Name                   = "AppRoot",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		-- HUD (no MainMenu button in combat places)
		-- §AGX/UX-02: always mounted; `hidden` hides it while a menu is open.
		-- Unmounting reset its run state (gameState/runEnded/betweenWaves),
		-- so closing Stats mid-wave showed "Start Game" and lost Next Wave.
		hud = React.createElement(HUD, {
			hidden              = fullscreenOpen,
			onClassesClick      = function() setShowClassReference(true) end,
			onStatsClick        = function() setShowStatsMenu(true) end,
			onTalentsClick      = function() setShowTalents(true) end,
			onEquipClick        = function() setShowEquipment(true) end,
			onCosmeticsClick    = function() setShowWardrobe(true) end,
			onAchievementsClick = function() setShowAchievements(true) end,
			onSettingsClick     = function() setShowSettings(true) end,
			onShopClick         = function() setShowShop(true) end,
		}),

		-- Battle class badge (compact, read-only)
		battleClass = (not fullscreenOpen) and React.createElement(BattleClassUI) or nil,

		-- Character creation (first login)
		characterCreation = showCharCreate and React.createElement(CharacterCreation, {
			onDismiss = function() setShowCharCreate(false) end,
		}) or nil,

		-- Combat class reference (current class only, no class switching)
		-- §LD-BC3 fix companion: use TextButton for the dim layer so
		-- click-outside-the-panel also closes (in addition to the now-
		-- clickable close button at top-right of the panel).
		-- §AGX/UX-14: the panel used to be a CHILD of the closing backdrop
		-- button and its Frames weren't Active, so a click on empty panel
		-- space fell through and closed it. Backdrop and panel are now
		-- siblings in a transparent holder, and BattleClassUI's expanded
		-- panel is Active (sinks input). Only clicks outside close it.
		classReference = showClassReference and React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 6,
		}, {
			backdrop = React.createElement("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 6,
				[React.Event.Activated] = function() setShowClassReference(false) end,
			}),
			reference = React.createElement(BattleClassUI, {
				showBadge = false,
				expanded = true,
				-- §LD-BC5: match StatsMenu's panel shape (0.72 x 0.78,
				-- centered). Pablo's spec: two window types in the game —
				-- this is the "Stats-style" 70 % overlay, not the full-screen
				-- "Talents-style". 0.30 was way too narrow.
				panelScale  = 0.72,
				panelScaleY = 0.78,
				position = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
				onClose = function() setShowClassReference(false) end,
				zIndex = 7,
			}),
		}) or nil,

		-- Stats allocation
		statsMenu = showStatsMenu and React.createElement(StatsMenu, {
			onClose = function() setShowStatsMenu(false) end,
		}) or nil,

		-- Talent tree
		talentTree = showTalents and React.createElement(TalentTreeUI, {
			onClose = function() setShowTalents(false) end,
		}) or nil,

		-- Equipment viewer
		equipmentUI = showEquipment and React.createElement(EquipmentUI, {
			onClose = function() setShowEquipment(false) end,
		}) or nil,

		-- Wardrobe (cosmetics browser)
		wardrobeUI = showWardrobe and React.createElement(WardrobeUI, {
			onClose = function() setShowWardrobe(false) end,
		}) or nil,

		-- Teammate vitals strip (right side)
		teammateVitals = (not fullscreenOpen) and React.createElement(TeammateVitals) or nil,

		-- Achievements panel
		achievementsUI = showAchievements and React.createElement(AchievementsUI.default, {
			onClose = function() setShowAchievements(false) end,
		}) or nil,

		-- Achievement toast (always mounted, self-manages via AchievementClient)
		achievementToast = React.createElement(AchievementsUI.Toast),

		-- Settings panel
		settingsUI = showSettings and React.createElement(SettingsUI, {
			onClose = function() setShowSettings(false) end,
		}) or nil,

		-- Global shop (3 tabs)
		globalShopUI = showShop and React.createElement(GlobalShopUI, {
			onClose = function() setShowShop(false) end,
		}) or nil,

		-- Admin testing panel (renders nothing for non-creator players)
		testingPanel = React.createElement(TestingUI),

		-- Death overlay (knocked down / dead states)
		deathOverlay = React.createElement(DeathUI),

		-- Card vote overlay (auto-shows when server starts a vote)
		voteOverlay = React.createElement(VoteUI),
	})
end

return CombatApp
