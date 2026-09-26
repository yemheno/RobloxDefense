-- UI/Shell/PanelHost.lua
--[[
    §AGX/UI-P3: renders the PanelStack (docs/ui_audit/shell-spec.md §3.2.6).

        PanelHost{ place = "Lobby" | "Plaza" | "Combat", externals = true }

    • Own ScreenGui "PanelGui" (portal into PlayerGui), DisplayOrder
      Theme.DisplayOrder.panels (20): above SkillPad/ActionBar (1), JoystickAim
      (5) and the cast bar (8), below NotifyGui (30) so toasts stay readable
      over panels. ScreenInsets = DeviceSafeInsets only (like NotifyGui: the
      legacy IgnoreGuiInset flag rewrites ScreenInsets and React sets props in
      no fixed order), which gives the same geometry as AppGui.
    • NO UIScale here (F7): legacy Scale-sized panels would overflow. Panels
      that use AppWindow / Modal scale their own chrome (UIScaleRoot.Local).
    • Two layer Frames at Theme.Z.window (10) and Theme.Z.modal (40). With
      ZIndexBehavior.Sibling each panel's hard-coded ZIndex (10–21, 100–103)
      becomes relative to its layer, so no panel file needs a ZIndex edit.
    • One wrapper Frame per entry: Visible = not suspended (hidden, still
      mounted), SelectionGroup + SelectionBehavior* = Stop (P7 focus trap),
      the D8 scrim (dismissOnBackdrop -> back("backdrop")), an optional
      non-dismissing dim (entry.dim) and PanelStack.EntryContext (id,
      presentation, dismissable, onBackdrop, top) read by AppWindow.
    • mount="always" externals (NPCDialog, ShopUI, WeaponSmithUI) are mounted
      here permanently when `externals ~= false`; they register themselves
      through PanelStack.useExternal. Wave 2 removes them from LobbyApp.
    • Attaches to PanelStack on mount (enables the UI context token, the B
      sink and UI_HudMode) and preloads every entry module of the place, so
      render never yields on a require.
    • §AGX/UI-P7: gamepad (Shell/GamepadNav, inert unless FormFactor input
      == "Gamepad"): the visible top entry gets first focus (its own
      useFirstFocus target, else the first selectable), re-focus when the
      selection is lost, LB/RB tab cycling, right-stick scrolling and the
      A/B(/LB-RB) hint strip. PanelStack restores the pre-push selection on
      pop; when the stack empties a selection left inside PanelGui is
      cleared, so the pad goes back to the character.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React       = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local UI         = script.Parent.Parent
local Theme      = require(UI:WaitForChild("Common"):WaitForChild("Theme"))
local PanelStack = require(script.Parent:WaitForChild("PanelStack"))
local Registry   = require(script.Parent:WaitForChild("Registry"))
-- §AGX/UI-P7: gamepad focus / tabs / scroll / hints for the top entry.
local GamepadNav   = require(script.Parent:WaitForChild("GamepadNav"))
local GamepadFocus = require(UI:WaitForChild("Common"):WaitForChild("GamepadFocus"))

local e = React.createElement

-- Theme v2 bands; fall back to the spec numbers until B1 adds the keys.
local DISPLAY_ORDER = (Theme.DisplayOrder and Theme.DisplayOrder.panels) or 20
local Z_PANEL = (Theme.Z and Theme.Z.window) or (Theme.Layers and Theme.Layers.panel) or 10
local Z_MODAL = (Theme.Z and Theme.Z.modal) or (Theme.Layers and Theme.Layers.modal) or 40
local SCRIM_COLOR = (Theme.Roles and Theme.Roles.surface and Theme.Roles.surface.scrim) or Color3.new(0, 0, 0)

local function closePropsFor(entry, id)
	local out = {}
	for _, name in ipairs(entry.closeProps or { "onClose" }) do
		out[name] = function()
			PanelStack.close(id, "self")
		end
	end
	return out
end

local function mergedProps(entry, place, recProps, id)
	local _, staticProps = Registry.spec(entry, place)
	local props = {}
	if staticProps then
		for k, v in pairs(staticProps) do props[k] = v end
	end
	if recProps then
		for k, v in pairs(recProps) do props[k] = v end
	end
	for k, v in pairs(closePropsFor(entry, id)) do
		-- Keep a caller's own callback (e.g. ConfirmDialog onConfirm) and
		-- close afterwards.
		local own = props[k]
		if type(own) == "function" then
			props[k] = function(...)
				own(...)
				v()
			end
		else
			props[k] = v
		end
	end
	return props
end

local function onBackdropFor(id)
	return function()
		if PanelStack.top() == id then
			PanelStack.back("backdrop")
		end
	end
end

-- One stacked entry (or an always-mounted external).
local function EntryWrapper(props)
	local entry, id, place = props.entry, props.id, props.place
	local component = props.component
	local _, _, dim = Registry.spec(entry, place)

	-- §AGX/UI-P7: hooks stay unconditional; they are inert unless this is the
	-- visible top stacked entry and the input is Gamepad.
	local frameRef = React.useRef(nil)
	local gamepad = GamepadFocus.useGamepad()
	local navOn = gamepad and props.inStack == true and props.isTop == true and props.visible ~= false
	local nav = GamepadNav.useEntryNav(frameRef, { enabled = navOn, entryId = id })

	local ctx = {
		id           = id,
		presentation = props.presentation,
		dismissable  = entry.dismissOnBackdrop == true,
		onBackdrop   = onBackdropFor(id),
		top          = props.isTop == true,
		place        = place,
	}

	return e("Frame", {
		Name                   = id,
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = props.zIndex or 1,
		Visible                = props.visible ~= false,
		ref                    = frameRef,   -- §AGX/UI-P7
		SelectionGroup         = true,
		SelectionBehaviorUp    = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown  = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft  = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, {
		-- Non-dismissing dim for entries without a backdrop (combat class ref).
		dim = (props.inStack and type(dim) == "number") and e("Frame", {
			Name                   = "Dim",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = SCRIM_COLOR,
			BackgroundTransparency = dim,
			BorderSizePixel        = 0,
			Active                 = true,
			ZIndex                 = 0,
		}) or nil,
		-- D8 scrim: only dialogs / flyouts / menu sheets.
		scrim = (props.inStack and entry.dismissOnBackdrop) and e("TextButton", {
			Name                   = "Scrim",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			AutoButtonColor        = false,
			Text                   = "",
			Selectable             = false,
			ZIndex                 = 0,
			[React.Event.Activated] = ctx.onBackdrop,
		}) or nil,
		content = component and e(PanelStack.EntryContext.Provider, { value = ctx },
			e(component, props.componentProps)) or nil,
		-- §AGX/UI-P7: A Select · B Back (· LB/RB Tabs), gamepad only. The
		-- radial draws its own hint under the wheel.
		gamepadHints = (navOn and id ~= "menuRadial") and e(GamepadNav.Hints, {
			tabs   = nav.hasTabs,
			side   = props.presentation == "side",
			zIndex = 1000,
		}) or nil,
	})
end

local function PanelHost(props)
	local place = props.place or "Lobby"
	local mountExternals = props.externals ~= false
	local state = PanelStack.useState()
	local loadedVersion, setLoadedVersion = React.useState(0)

	-- Attach (enables side effects) + preload every module of this place.
	React.useEffect(function()
		local detach = PanelStack.attach({ place = place })
		local alive = true
		task.spawn(function()
			for _, entry in ipairs(Registry.entriesForPlace(place)) do
				if not alive then return end
				Registry.load(entry, place)
			end
			if alive then setLoadedVersion(function(v) return v + 1 end) end
		end)
		return function()
			alive = false
			detach()
		end
	end, { place })

	-- Late loads (a module that was missing at preload, e.g. another agent's
	-- Shell file): load it off-render and re-render.
	React.useEffect(function()
		local alive = true
		for _, rec in ipairs(state.stack) do
			if rec.entry and not Registry.resolve(rec.entry, place) then
				task.spawn(function()
					if Registry.load(rec.entry, place) and alive then
						setLoadedVersion(function(v) return v + 1 end)
					end
				end)
			end
		end
		return function() alive = false end
	end, { state, place } :: { any })

	local panelChildren = {}
	local modalChildren = {}
	local stackIndex = {}
	for i, rec in ipairs(state.stack) do stackIndex[rec.id] = i end

	for i, rec in ipairs(state.stack) do
		local entry = rec.entry
		if entry and entry.mount ~= "always" then
			local cls = entry.class or "panel"
			local target = (cls == "modal" or cls == "system") and modalChildren or panelChildren
			target[rec.key] = e(EntryWrapper, {
				entry          = entry,
				id             = rec.id,
				place          = place,
				component      = Registry.resolve(entry, place),
				componentProps = mergedProps(entry, place, rec.props, rec.id),
				presentation   = PanelStack.presentationFor(entry),
				zIndex         = i,
				visible        = not state.suspended[rec.id],
				isTop          = state.top == rec.id,
				inStack        = true,
			})
		end
	end

	if mountExternals then
		for _, entry in ipairs(Registry.entriesForPlace(place)) do
			if entry.mount == "always" then
				local i = stackIndex[entry.id]
				local rec = i and state.stack[i] or nil
				panelChildren["ext_" .. entry.id] = e(EntryWrapper, {
					entry          = entry,
					id             = entry.id,
					place          = place,
					component      = Registry.resolve(entry, place),
					componentProps = mergedProps(entry, place, rec and rec.props, entry.id),
					presentation   = PanelStack.presentationFor(entry),
					zIndex         = i or 0,
					visible        = not state.suspended[entry.id],
					isTop          = state.top == entry.id,
					inStack        = i ~= nil,
				})
			end
		end
	end

	local _ = loadedVersion   -- re-render trigger only

	-- §AGX/UI-P7: everything closed -> drop a selection left in PanelGui so
	-- the gamepad drives the character again (a selection PanelStack
	-- restored outside PanelGui, e.g. a HUD button, is kept).
	local guiRef = React.useRef(nil)
	React.useEffect(function()
		if state.depth == 0 then
			GamepadNav.clearIfInside(guiRef.current)
		end
	end, { state.depth })

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return nil end

	return e(PanelStack.HostContext.Provider, { value = true },
		ReactRoblox.createPortal(e("ScreenGui", {
			Name           = "PanelGui",
			ResetOnSpawn   = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder   = DISPLAY_ORDER,
			ScreenInsets   = Enum.ScreenInsets.DeviceSafeInsets,
			ref            = guiRef,   -- §AGX/UI-P7
		}, {
			Panels = e("Frame", {
				Name                   = "PanelLayer",
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex                 = Z_PANEL,
			}, panelChildren),
			Modals = e("Frame", {
				Name                   = "ModalLayer",
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex                 = Z_MODAL,
			}, modalChildren),
		}), playerGui))
end

return PanelHost
