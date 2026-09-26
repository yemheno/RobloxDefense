-- UI/HUD/init.lua
--[[
    Always-visible heads-up display, split into regions (§AGX/UI-P5,
    docs/ui_audit/shell-spec.md §4). Rojo keeps the folder's ModuleScript
    name "HUD", so callers use `SharedUI:WaitForChild("HUD")`.

      Layout.lua             layout table (§4.2), rail band (§4.4), attributes (§4.3)
      RunState.lua           module-level run store (+ wave/run banners, killfeed)
      PlayerInfo.lua         module-level vitals / wallet store
      VitalsRegion.lua       HP/Res/XP ("full") or Level+XP ("chip")
      CurrencyRegion.lua     Essence / Merits / Power pills
      RunControlsRegion.lua  Start / Countdown / Next Wave / Return
      ObjectivesRegion.lua   defense-line bar + defense combo
      ComboRegion.lua        personal combo counter
      PartyRegion.lua        TeammateVitals in a rect (partyInHud)
      PlayCta.lua            Lobby PLAY
      QuickButtons.lua       touch Emote / Wardrobe (Lobby, Plaza)
      (The Shell's railSlot = MenuSurface is the only menu entry point.)
      StatusBar.lua, Store.lua

    SCALE LAYER (D2 / F7)
      The root Frame fills the parent (the safe-area AppGui) UNSCALED and
      measures its AbsoluteSize; that screen size is converted with
      UIScaleRoot.toLocal, and every region renders inside a
      UIScaleRoot.Local in DESIGN px (phone points). Nothing measured is
      written back as an Offset without the conversion. The BattleClassUI
      badge is legacy screen-px code and sits OUTSIDE the layer. Mount the
      HUD unscaled (not inside a UIScaleRoot.Root): it applies its own scale.

    PROPS
      place          "Combat" | "Lobby" | "Plaza"
                     (default: hideStartButton and "Lobby" or "Combat")
      hudMode        "full" | "combatSide" | "none"  (default: hidden and "none" or "full")
      railSlot       element; cloned with { collapsed, rect, band, place } where
                     rect is a Layout RECT in design px of a full-screen parent
                     under the HUD's UIScale (collapsed = the menu-button rect)
      railCount      number of rail groups (default 6)
      topCentreSlot  element (CentralBoss BossHud{slotted=true}); cloned with
                     { onActiveChanged(bool) } and rendered filling the boss slot
      partyInHud     bool: mount TeammateVitals in the party region
      classBadge     true: render the BattleClassUI badge where the layout has
                     one (desktop / console combat); false: none;
                     nil: the App mounts it, the layout keeps clear
      onPlay, onEmote, onWardrobe   functions (PLAY CTA / quick buttons)
      hidden, hideStartButton   (legacy fallbacks for hudMode / place)
      §AGX/UI-P3: no legacyNav / on*Click drawer props; menus open through
      PanelStack / the railSlot.
]]

local GuiService        = game:GetService("GuiService")  -- legacy topbar inset (class badge)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local UI            = script.Parent
local Common        = UI:WaitForChild("Common")
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))

local Layout            = require(script:WaitForChild("Layout"))
local RunState          = require(script:WaitForChild("RunState"))
local PlayerInfo        = require(script:WaitForChild("PlayerInfo"))
local VitalsRegion      = require(script:WaitForChild("VitalsRegion"))
local CurrencyRegion    = require(script:WaitForChild("CurrencyRegion"))
local RunControlsRegion = require(script:WaitForChild("RunControlsRegion"))
local ObjectivesRegion  = require(script:WaitForChild("ObjectivesRegion"))
local ComboRegion       = require(script:WaitForChild("ComboRegion"))
local PartyRegion       = require(script:WaitForChild("PartyRegion"))
local PlayCta           = require(script:WaitForChild("PlayCta"))
local QuickButtons      = require(script:WaitForChild("QuickButtons"))

local e = React.createElement

-- BattleClassUI is only needed when the HUD owns the class badge;
-- required lazily and without yielding, so the Lobby never loads it.
-- §AGX/UI-FIX: 9 — pcall'd (a require error never throws out of the
-- HUD's render), and Shell.preload("Combat") warms the require so this
-- render-time call does not yield. A missing module is not cached (it may
-- replicate later); a failed require is cached as false.
local battleClassUI = nil
local function getBattleClassUI()
	if battleClassUI == nil then
		local mod = UI:FindFirstChild("BattleClassUI")
		if not mod then return nil end
		local ok, res = pcall(require, mod)
		if not ok then
			warn("[HUD] BattleClassUI require failed:", res)
			battleClassUI = false
		else
			battleClassUI = res or false
		end
	end
	return battleClassUI or nil
end

local function HUD(props)
	local ff = useFormFactor()
	local sc = UIScaleRoot.useUIScale()
	local place = props.place or (props.hideStartButton and "Lobby" or "Combat")
	local hudMode = props.hudMode or (props.hidden and "none" or "full")

	-- Measured root size (DeviceSafeInsets makes it smaller than the camera
	-- viewport on notched phones); the viewport is the first-frame fallback.
	local guiSize, setGuiSize = React.useState(nil)
	local onRootSize = React.useCallback(function(rbx)
		local sz = rbx.AbsoluteSize
		if sz.X > 0 and sz.Y > 0 then setGuiSize(sz) end
	end, {})
	local screen = guiSize or ff.viewport or Vector2.new(1280, 720)
	local s = sc.target
	local design = UIScaleRoot.toLocal(screen, s)   -- §AGX/UI-P5: screen px -> design px

	local run  = RunState.use()
	local info = PlayerInfo.use()
	React.useEffect(function()
		RunState.start(place)
		PlayerInfo.start()
	end, { place })

	local bossActive, setBossActive = React.useState(false)
	local attrs = Layout.useAttrs()

	local legacyTopbar = select(1, GuiService:GetGuiInset()).Y
	local L = Layout.useHudLayout(place, ff, hudMode, {
		W = design.X, H = design.Y, scale = s, attrs = attrs,
		legacyNav        = false,   -- §AGX/UI-P3: no LegacyNav
		hasRail          = props.railSlot ~= nil,
		railCount        = props.railCount,
		classBadge       = props.classBadge,
		legacyTopbar     = legacyTopbar,
		hasTopCentreSlot = props.topCentreSlot ~= nil,
		bossActive       = bossActive,
		defense          = run.defenseHP ~= nil,
		partyInHud       = props.partyInHud,
	})
	local show = L.show

	-- ── Design-px regions (inside the scale layer) ───────────────────────
	local regions = {
		vitals = e(VitalsRegion, {
			rect = L.vitals, variant = L.vitalsVariant, info = info, visible = show.vitals,
		}),
		currencies = e(CurrencyRegion, {
			rect = L.currencies, currency = info.currency, power = info.power,
			visible = show.currencies,
		}),
		objectives = e(ObjectivesRegion, {
			layout = L, run = run, showBar = show.defense, showCombo = show.combo,
		}),
		combo = e(ComboRegion, { layout = L, combo = run.combo, visible = show.combo }),
		runControls = (place == "Combat") and e(RunControlsRegion, {
			layout = L, run = run, visible = show.topCentre,
		}) or nil,
		-- §AGX/UI-FIX: 7 — mounted whenever the HUD owns the party (combat +
		-- partyInHud) and only hidden otherwise, so opening a panel never
		-- unmounts TeammateVitals (and drops its VitalsUpdate state).
		party = e(PartyRegion, {
			layout  = L,
			mounted = place == "Combat" and props.partyInHud == true,
			visible = show.party,
		}),
		play = e(PlayCta, { layout = L, onPlay = props.onPlay, visible = show.play }),
		quick = e(QuickButtons, {
			layout = L, onEmote = props.onEmote, onWardrobe = props.onWardrobe, visible = show.quick,
		}),
	}

	if props.topCentreSlot and L.bossSlot then
		-- Stays mounted while hidden so the slot keeps its subscriptions.
		regions.bossSlot = e("Frame", {
			Name                   = "TopCentreSlot",
			AnchorPoint            = L.bossSlot.anchorPoint,
			Position               = L.bossSlot.position,
			Size                   = L.bossSlot.size,
			BackgroundTransparency = 1,
			Visible                = show.topCentre,
			ZIndex                 = 4,
		}, {
			slot = React.cloneElement(props.topCentreSlot, { onActiveChanged = setBossActive }),
		})
	end

	if props.railSlot then
		regions.rail = e("Frame", {
			Name                   = "RailSlot",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible                = show.rail,
			ZIndex                 = 5,
		}, {
			rail = React.cloneElement(props.railSlot, {
				collapsed = L.railCollapsed,
				rect      = L.rail,
				band      = L.band,
				place     = place,
			}),
		})
	end

	-- ── Screen-px legacy pieces (outside the scale layer) ────────────────
	-- §AGX/UI-FIX: 7 — the badge stays mounted wherever the layout has one
	-- (L.classBadge) and is hidden with Visible when show.classBadge is off
	-- (panel open), instead of being unmounted and remounted.
	local classBadge = nil
	local BattleClassUI = L.classBadge and getBattleClassUI() or nil
	if BattleClassUI then
		-- design -> this frame's units (screen px / scale already applied above)
		local k = sc.remaining
		classBadge = e("Frame", {
			Name                   = "ClassBadgeHost",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex                 = 3,   -- BattleClassUI's own default root ZIndex
			Visible                = show.classBadge == true,
		}, {
			badge = e(BattleClassUI, {
				showBadge   = true,
				anchorPoint = Vector2.new(0, 0),
				position    = UDim2.fromOffset(L.classBadge.x * k, L.classBadge.y * k),
			}),
		})
	end

	return e("Frame", {
		Name                   = "HUD",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible                = hudMode ~= "none",  -- §AGX/UX-02: hide, don't unmount
		[React.Change.AbsoluteSize] = onRootSize,
	}, {
		scaled = e(UIScaleRoot.Local, { name = "HUDScale", zIndex = 1 }, regions),
		classBadge = classBadge,
	})
end

return HUD
