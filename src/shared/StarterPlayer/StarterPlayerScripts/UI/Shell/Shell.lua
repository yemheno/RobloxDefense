-- UI/Shell/Shell.lua
--[[
    §AGX/UI-P3 (W1): the one root every Place's App renders
    (docs/ui_audit/shell-spec.md §5 "Wave 2"). What is open is owned by
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
                     the BattleClassUI badge), legacyNav = false (W3)
      panelHost      PanelHost{place, externals=true}: every Registry panel,
                     plus NPCDialog / ShopUI / WeaponSmithUI in the Lobby
      notifyHost     Notify.Host (exactly once per place: CentralBossApp wraps
                     CombatApp, which renders this Shell once)
      tooltipLayer   Theme v2 TooltipHost in a UIScaleRoot.Root (2e3fdf5)
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
local React             = require(ReplicatedStorage.Packages.React)

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

	-- §AGX/UI-P3: server-opened entries (replaces the Apps' three
	-- CharacterCreationRequired effects) + badge sources.
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

	local children = {
		hud = e(HUD, {
			place         = place,
			hudMode       = stackState.hudMode,
			railSlot      = e(MenuSurface, { place = place }),
			railCount     = #Registry.Groups,
			topCentreSlot = props.topCentreSlot,
			partyInHud    = true,
			classBadge    = true,
			legacyNav     = false,   -- §AGX/UI-P3 (W3)
			onPlay        = (place == "Lobby") and onPlay or nil,
			onEmote       = (not combat) and onEmote or nil,
			onWardrobe    = (place == "Plaza") and onWardrobe or nil,
		}),

		panelHost = e(PanelHost, { place = place, externals = true }),

		-- §AGX/UI-P4: own ScreenGui above AppGui and PanelGui, below modals
		notifyHost = e(Notify.Host),

		-- §AGX/UI-P1v2: UIScale layer at the tooltip band (above every window)
		tooltipLayer = e(UIScaleRoot.Root, {
			name   = "TooltipLayer",
			zIndex = Theme.Z.tooltip,
		}, {
			host = e(Tooltip.Host),
		}),
	}

	if place ~= "Plaza" then
		-- Self-managed via AchievementClient
		children.achievementToast = e(AchievementsUI.Toast)
		-- Admin testing panel (renders nothing for non-creator players)
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
	if place == "Combat" then combatParts(true) end
end

return ShellExport
