-- lobby/StarterPlayerScripts/UI/LobbyApp.lua
--[[
    Root React component for the Lobby place.
    
    Renders:
      • HUD (shared — currency, vitals, level)
      • ClassMenu (shared — change class)
      • StatsMenu (shared — allocate stats)
      • CharacterCreation (shared — first login)
      • SocialPanel (lobby — fullscreen Party+Guild window)
      • PartyInviteToast (lobby — incoming invite popup)
      • MainMenu (lobby — game mode selection)
      • MatchmakingUI (lobby — queue status)
      • NPCDialog (lobby — NPC dialogue/quest/teleport)
      • ShopUI (lobby — NPC shop)
      • Menu button (☰) in HUD triggers MainMenu
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules = PlayerScripts:WaitForChild("Modules")
local SharedUI      = PlayerScripts:WaitForChild("UI")
local LobbyUI       = script.Parent  -- lobby/StarterPlayerScripts/UI/

local NetworkManager    = require(SharedModules:WaitForChild("NetworkManager"))
local CharacterCreation = require(SharedUI:WaitForChild("CharacterCreation"))
local ClassMenu         = require(SharedUI:WaitForChild("ClassMenu"))
local HUD               = require(SharedUI:WaitForChild("HUD"))
local StatsMenu         = require(SharedUI:WaitForChild("StatsMenu"))
local TalentTreeUI      = require(SharedUI:WaitForChild("TalentTreeUI"))
local EquipmentUI       = require(SharedUI:WaitForChild("EquipmentUI"))
local WardrobeUI        = require(SharedUI:WaitForChild("WardrobeUI"))
local AchievementsUI    = require(SharedUI:WaitForChild("AchievementsUI"))
local TestingUI         = require(SharedUI:WaitForChild("TestingUI"))
local SettingsUI        = require(SharedUI:WaitForChild("SettingsUI"))
local GlobalShopUI      = require(SharedUI:WaitForChild("GlobalShopUI"))

local EmoteWheel        = require(LobbyUI:WaitForChild("EmoteWheel"))
local SocialPanel       = require(LobbyUI:WaitForChild("SocialPanel"))
local PartyInviteToast  = require(LobbyUI:WaitForChild("PartyInviteToast"))

local MainMenu      = require(LobbyUI:WaitForChild("MainMenu"))
local MatchmakingUI = require(LobbyUI:WaitForChild("MatchmakingUI"))
local NPCDialog     = require(LobbyUI:WaitForChild("NPCDialog"))
local ShopUI         = require(LobbyUI:WaitForChild("ShopUI"))
local WeaponSmithUI  = require(LobbyUI:WaitForChild("WeaponSmithUI"))
local DailyLoginUI  = require(LobbyUI:WaitForChild("DailyLoginUI"))
local LeaderboardUI = require(LobbyUI:WaitForChild("LeaderboardUI"))
local InventoryUI   = require(LobbyUI:WaitForChild("InventoryUI"))

local function LobbyApp()
	local showCharCreate, setShowCharCreate = React.useState(false)
	local showClassMenu,  setShowClassMenu  = React.useState(false)
	local showStatsMenu,  setShowStatsMenu  = React.useState(false)
	local showMainMenu,   setShowMainMenu   = React.useState(false)
	local showParty,      setShowParty      = React.useState(false)
	local showTalents,    setShowTalents    = React.useState(false)
	local showEquipment,  setShowEquipment  = React.useState(false)
	local showWardrobe,     setShowWardrobe     = React.useState(false)
	local showAchievements, setShowAchievements = React.useState(false)
	local showSettings,     setShowSettings     = React.useState(false)
	local showShop,         setShowShop         = React.useState(false)
	local showDailyLogin,   setShowDailyLogin   = React.useState(false)
	local showLeaderboard,  setShowLeaderboard  = React.useState(false)
	local showInventory,    setShowInventory    = React.useState(false)

	-- Listen for the server requesting character creation
	React.useEffect(function()
		local conn = NetworkManager.OnServerEvent("CharacterCreationRequired", function()
			setShowCharCreate(true)
		end)
		-- Ask the server for character status NOW that our listener is ready.
		-- This solves the race condition where the server fired the event
		-- before the React tree mounted.
		NetworkManager.FireServer("RequestCharacterStatus")
		return function()
			if conn then conn:Disconnect() end
		end
	end, {})

	local fullscreenOpen = showClassMenu or showCharCreate or showMainMenu or showParty or showTalents or showEquipment or showStatsMenu or showWardrobe or showAchievements or showSettings or showShop or showDailyLogin or showLeaderboard or showInventory

	return React.createElement("Frame", {
		Name                   = "AppRoot",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		-- HUD
		-- §AGX/UX-02: always mounted; `hidden` hides it while a menu is open
		-- (unmounting reset its local state and re-fetched everything).
		hud = React.createElement(HUD, {
			hidden          = fullscreenOpen,
			onClassesClick  = function() setShowClassMenu(true) end,
			onStatsClick    = function() setShowStatsMenu(true) end,
			onTalentsClick  = function() setShowTalents(true) end,
			onEquipClick    = function() setShowEquipment(true) end,
			onCosmeticsClick    = function() setShowWardrobe(true) end,
			onAchievementsClick = function() setShowAchievements(true) end,
			onSettingsClick     = function() setShowSettings(true) end,
			onShopClick         = function() setShowShop(true) end,
			onMenuClick         = function() setShowMainMenu(true) end,
			onPartyClick        = function() setShowParty(true) end,
			onDailyLoginClick  = function() setShowDailyLogin(true) end,
			onLeaderboardClick = function() setShowLeaderboard(true) end,
			onInventoryClick   = function() setShowInventory(true) end,
			hideStartButton = true,
		}),

		-- Character creation (first login)
		characterCreation = showCharCreate and React.createElement(CharacterCreation, {
			onDismiss = function() setShowCharCreate(false) end,
		}) or nil,

		-- Class selection
		classMenu = showClassMenu and React.createElement(ClassMenu, {
			onClose = function() setShowClassMenu(false) end,
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

		-- Main menu (game modes)
		mainMenu = showMainMenu and React.createElement(MainMenu, {
			onClose = function() setShowMainMenu(false) end,
			onPlay = function()
				setShowMainMenu(false)
			end,
		}) or nil,

		-- Social panel (fullscreen — opened via the Social button in HUD)
		socialPanel = showParty and React.createElement(SocialPanel, {
			onClose = function() setShowParty(false) end,
		}) or nil,

		-- Emote wheel (always mounted — self-manages visibility via Q keybind)
		emoteWheel = React.createElement(EmoteWheel),

		-- Invite toast (always mounted regardless of fullscreen, self-manages visibility)
		partyInviteToast = React.createElement(PartyInviteToast),

		-- NPC Dialog (self-manages via events)
		npcDialog = React.createElement(NPCDialog, { onClose = function() end }),

		-- Shop UI (self-manages via events)
		shopUI = React.createElement(ShopUI, { onClose = function() end }),

		-- Weapon Smith UI (self-manages via events)
		weaponSmithUI = React.createElement(WeaponSmithUI, { onClose = function() end }),

		-- Matchmaking status bar (self-manages via events)
		matchmakingUI = React.createElement(MatchmakingUI),

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

		-- Daily Login panel
		dailyLoginUI = showDailyLogin and React.createElement(DailyLoginUI, {
			onClose = function() setShowDailyLogin(false) end,
		}) or nil,

		-- Leaderboard panel
		leaderboardUI = showLeaderboard and React.createElement(LeaderboardUI, {
			onClose = function() setShowLeaderboard(false) end,
		}) or nil,

		-- Inventory panel
		inventoryUI = showInventory and React.createElement(InventoryUI, {
			onClose = function() setShowInventory(false) end,
		}) or nil,

		-- Admin testing panel (renders nothing for non-creator players)
		testingPanel = React.createElement(TestingUI),
	})
end

return LobbyApp
