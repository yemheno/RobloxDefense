-- shared/StarterPlayerScripts/UI/CombatApp.lua
--[[
    Shared root React component for all combat places
    (LaneDefense, CentralBoss, HordeMode).

    §AGX/UI-P3: a thin wrapper around the shared Shell
    (UI/Shell/Shell.lua) with place = "Combat". The Shell mounts the HUD
    (which owns the BattleClassUI badge and TeammateVitals: classBadge /
    partyInHud), PanelHost (every Registry panel: class reference, Stats,
    Talents, Equipment, Wardrobe, Inventory, Achievements, Daily Login,
    Leaderboard, Shop, Settings, CharacterCreation, leave confirm),
    SkillPad / ActionBar, DeathUI, VoteUI, Notify.Host and the TooltipHost.

    props.topCentreSlot: an element for the HUD's top-centre slot
    (CentralBossApp passes BossHud{slotted=true}).

    Each combat place re-exports this component from a thin wrapper.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local SharedUI = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI")
local Shell    = require(SharedUI:WaitForChild("Shell"):WaitForChild("Shell"))

-- §AGX/UI-P3: load the combat-only modules (SkillPad / ActionBar / DeathUI /
-- VoteUI) here, where yielding is fine, so render never waits on them.
Shell.preload("Combat")

local function CombatApp(props)
	return React.createElement(Shell, {
		place         = "Combat",
		topCentreSlot = props and props.topCentreSlot or nil,
	})
end

return CombatApp
