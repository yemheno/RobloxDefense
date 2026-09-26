-- UI/Shell/Shell.lua
--[[
    §AGX/UI-P3: the one root every Place's App renders
    (docs/ui_audit/shell-spec.md §5). What is open is owned by
    PanelStack; which screens exist is owned by Registry; this file only
    mounts the always-on pieces for a place.

        Shell{ place = "Lobby" | "Plaza" | "Combat",
               topCentreSlot = element?   -- CentralBoss: BossHud{slotted=true}
               extras        = { [name] = element }? }
                 -- place-folder components the Shell can't require from
                 -- shared code without yielding (Lobby: MatchmakingUI,
                 -- PartyInviteToast). The App requires them and passes
                 -- elements; the Shell mounts them as-is.

    MOUNTS
      hud            HUD (UNSCALED: it applies its own UIScaleRoot.Local),
                     hudMode from PanelStack.useState(), railSlot = MenuSurface,
                     partyInHud + classBadge (the HUD owns TeammateVitals and
                     the BattleClassUI badge), legacyNav = false
      panelHost      PanelHost{place, externals=true}: every Registry panel,
                     plus NPCDialog / ShopUI / WeaponSmithUI in the Lobby
      notifyHost     Notify.Host (exactly once per place: CentralBossApp wraps
                     CombatApp, which renders this Shell once)
      tooltipLayer   Theme v2 TooltipHost in a UIScaleRoot.Root, in its
                     own ScreenGui "TooltipGui" (DisplayOrder.tooltip = 50)
      Lobby + Combat achievementToast, testingPanel
      Lobby + Plaza  emoteWheel (closed by PanelStack.onOpen)
      Combat         skillPad (touch) | actionBar, deathOverlay, voteOverlay.
                     No `hidden` prop: the "UI" input context PanelStack
                     pushes while anything is open hides them.
    HOOKS
      ServerOpen.useServerOpen(place)  character creation / daily login / death
      BadgeStore.init(place)
      PanelStack.onOpen(EmoteWheel.close)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")   -- §AGX/UI-FIX: 3
local React             = require(ReplicatedStorage.Packages.React)
local ReactRoblox       = require(ReplicatedStorage.Packages.ReactRoblox)   -- §AGX/UI-FIX: 3

local ShellFolder = script.Parent
local UI          = ShellFolder.Parent
local Common      = UI:WaitForChild("Common")

local Theme         = require(Common:WaitForChild("Theme"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))
local Tooltip       = require(Common:WaitForChild("Tooltip"))
local Notify        = require(Common:WaitForChild("Notify"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))

local PanelStack  = require(ShellFolder:WaitForChild("PanelStack"))
local Registry    = require(ShellFolder:WaitForChild("Registry"))
local PanelHost   = require(ShellFolder:WaitForChild("PanelHost"))
local ServerOpen  = require(ShellFolder:WaitForChild("ServerOpen"))
local BadgeStore  = require(ShellFolder:WaitForChild("BadgeStore"))
local MenuSurface = require(ShellFolder:WaitForChild("MenuSurface"))

local HUD            = require(UI:WaitForChild("HUD"))
local EmoteWheel     = require(UI:WaitForChild("EmoteWheel"))
local AchievementsUI = require(UI:WaitForChild("AchievementsUI"))
local TestingUI      = require(UI:WaitForChild("TestingUI"))

-- Combat-only components: required lazily, so the Lobby / Plaza never load
-- the combat input modules (SkillPad pulls SkillInput / JoystickAim).
-- CombatApp calls Shell.preload("Combat") at module load (it may yield
-- there); render only reads the cache (FindFirstChild fallback, a miss is
-- not cached).
local combatCache = nil
local function combatParts(wait)
	if combatCache then return combatCache end
	local function load(parent, name)
		local mod = parent:FindFirstChild(name)
		if not mod and wait then mod = parent:WaitForChild(name, 10) end
		return mod and require(mod) or nil
	end
	local parts = {
		SkillPad  = load(Common, "SkillPad"),
		ActionBar = load(Common, "ActionBar"),
		DeathUI   = load(UI, "DeathUI"),
		VoteUI    = load(UI, "VoteUI"),
	}
	if parts.SkillPad and parts.ActionBar and parts.DeathUI and parts.VoteUI then
		combatCache = parts
	end
	return parts
end

local e = React.createElement

local function Shell(props)
	local place  = props.place or "Lobby"
	local combat = place == "Combat"

	local stackState = PanelStack.useState()
	local ff = useFormFactor()   -- SkillPad vs ActionBar, live across input switches

	-- §AGX/UI-P3: server-opened entries (the only CharacterCreationRequired
	-- listener) + badge sources.
	ServerOpen.useServerOpen(place)
	React.useEffect(function()
		BadgeStore.init(place)
	end, { place })

	-- §AGX/UI-P3: the emote wheel gives way to any panel / menu.
	React.useEffect(function()
		if not combat and EmoteWheel and EmoteWheel.close then
			return PanelStack.onOpen(function()
				EmoteWheel.close()
			end)
		end
		return nil
	end, { combat })

	local onPlay = React.useCallback(function()
		PanelStack.open("play")
	end, {})
	local onEmote = React.useCallback(function()
		PanelStack.open("emotes")    -- action: closes the stack, toggles the wheel
	end, {})
	local onWardrobe = React.useCallback(function()
		PanelStack.open("wardrobe")
	end, {})

	-- §AGX/UI-FIX: 3 — PlayerGui for the tooltip ScreenGui portal.
	local lp = Players.LocalPlayer
	local tooltipGuiParent = lp and lp:FindFirstChildOfClass("PlayerGui") or nil

	local children = {
		hud = e(HUD, {
			place         = place,
			hudMode       = stackState.hudMode,
			railSlot      = e(MenuSurface, { place = place }),
			railCount     = #Registry.Groups,
			topCentreSlot = props.topCentreSlot,
			partyInHud    = true,
			classBadge    = true,
			legacyNav     = false,   -- §AGX/UI-P3
			onPlay        = (place == "Lobby") and onPlay or nil,
			onEmote       = (not combat) and onEmote or nil,
			onWardrobe    = (place == "Plaza") and onWardrobe or nil,
		}),

		panelHost = e(PanelHost, { place = place, externals = true }),

		-- §AGX/UI-P4: own ScreenGui above AppGui and PanelGui, below modals
		notifyHost = e(Notify.Host),

		-- §AGX/UI-P1v2, §AGX/UI-FIX: 3 — UIScale layer in its own ScreenGui at
		-- Theme.DisplayOrder.tooltip (50), above every window: inside AppGui (0)
		-- it would draw UNDER PanelGui (20) and hide panel-button tooltips.
		-- Same insets as PanelGui / NotifyGui.
		tooltipLayer = tooltipGuiParent and ReactRoblox.createPortal(e("ScreenGui", {
			Name           = "TooltipGui",
			ResetOnSpawn   = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder   = (Theme.DisplayOrder and Theme.DisplayOrder.tooltip) or 50,
			ScreenInsets   = Enum.ScreenInsets.DeviceSafeInsets,
		}, {
			layer = e(UIScaleRoot.Root, {
				name   = "TooltipLayer",
				zIndex = Theme.Z.tooltip,
			}, {
				host = e(Tooltip.Host),
			}),
		}), tooltipGuiParent) or nil,
	}

	if place ~= "Plaza" then
		-- Self-managed via AchievementClient
		children.achievementToast = e(AchievementsUI.Toast)
		-- Admin testing panel: Studio-only; renders nothing in live servers (§AGX/SEC)
		children.testingPanel = e(TestingUI)
	end

	if not combat then
		-- Q / DPadUp / the Emote quick button / the Social group's Emotes
		children.emoteWheel = e(EmoteWheel)
	end

	if combat then
		local c = combatParts()
		if ff.isTouch then
			children.skillPad = c.SkillPad and e(c.SkillPad.default) or nil
		else
			children.actionBar = c.ActionBar and e(c.ActionBar) or nil
		end
		children.deathOverlay = c.DeathUI and e(c.DeathUI) or nil
		children.voteOverlay  = c.VoteUI and e(c.VoteUI) or nil
	end

	if type(props.extras) == "table" then
		for name, element in pairs(props.extras) do
			children["extra_" .. tostring(name)] = element
		end
	end

	return e("Frame", {
		Name                   = "AppRoot",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, children)
end

-- Same export shape as MenuSurface / EmoteWheel: a component carrying a
-- module-level API (React accepts a memo type wherever a component goes).
local ShellExport = React.memo(Shell)
ShellExport.Component = Shell

--- May yield. Call from a place App's module scope, never from render.
function ShellExport.preload(place)
	if place == "Combat" then
		combatParts(true)
		-- §AGX/UI-FIX: 9 — warm the HUD's class-badge require here (may
		-- yield), so HUD's render-time pcall(require) returns at once.
		local mod = UI:WaitForChild("BattleClassUI", 10)
		if mod then
			local ok, err = pcall(require, mod)
			if not ok then warn("[Shell] BattleClassUI preload failed:", err) end
		end
	end
end

return ShellExport
