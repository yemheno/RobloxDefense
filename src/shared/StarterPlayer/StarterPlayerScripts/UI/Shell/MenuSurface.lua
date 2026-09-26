-- UI/Shell/MenuSurface.lua
--[[
    §AGX/UI-P3: the menu entry point (shell-spec §4.5 MenuSurface, B8). The
    Shell passes it to the HUD as `railSlot`; the HUD clones it with
    { collapsed, rect, band, place } where `rect` = { anchorPoint, position,
    size } in design px of a full-screen parent under the HUD's UIScale
    (collapsed -> the menu-button rect, else the rail rect).

    Renders
        expanded  -> MenuRail (Desktop everywhere, Tablet Lobby/Plaza)
        collapsed -> one ☰ button (48; Console 64 chip with a ▾ DPad hint)
                     with the OR of every badge
    Binds InputSystem "MenuToggle" (M / DPadDown; A2) while mounted.

    MenuSurface.toggle(place?)    (also what ☰ and MenuToggle do)
        anything open -> PanelStack.closeAll("toggle")
        else Gamepad input -> open("menuRadial", { place })
             otherwise     -> open("menuSheet",  { place })
        (the rail itself stays visible when not collapsed)
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local Modules       = PlayerScripts:WaitForChild("Modules")
local Common        = script.Parent.Parent:WaitForChild("Common")
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local IconButton    = require(Common:WaitForChild("IconButton"))
local Locale        = require(Modules:WaitForChild("Locale"))
local Badge         = require(script.Parent:WaitForChild("Badge"))
local MenuIcon      = require(script.Parent:WaitForChild("MenuIcon"))
local MenuRail      = require(script.Parent:WaitForChild("MenuRail"))
-- Required here (not only by the Registry on open) so MenuSheet's wallet
-- cache is subscribed from the moment the shell mounts.
require(script.Parent:WaitForChild("MenuSheet"))

local e = React.createElement
local R = Theme.Roles
local Model = MenuIcon.Model

local FormFactor = nil
do
	local mod = Modules:FindFirstChild("FormFactor")
	if mod then
		local ok, res = pcall(require, mod)
		if ok then FormFactor = res end
	end
end

local InputSystem = nil
local function getInputSystem()
	if InputSystem then return InputSystem end
	local mod = Modules:FindFirstChild("InputSystem")
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then InputSystem = res end
	end
	return InputSystem
end

local function toggle(place)
	local PS = Model.PanelStack()
	if not PS then return false end
	if PS.depth() > 0 then
		return PS.closeAll("toggle")
	end
	place = Model.resolvePlace(place, nil)
	local ff = FormFactor and FormFactor.Get() or nil
	local gamepad = ff ~= nil and (ff.input == "Gamepad" or ff.kind == "Console")
	return PS.open(gamepad and "menuRadial" or "menuSheet", { place = place })
end

local function MenuButton(props)
	local side = props.side
	local console = props.console
	return e("Frame", {
		Name                   = "MenuButton",
		AnchorPoint            = Vector2.new(1, 0),
		Position               = UDim2.fromScale(1, 0),
		Size                   = UDim2.fromOffset(side, side),
		BackgroundTransparency = 1,
		ZIndex                 = 3,
	}, {
		button = e(IconButton, {
			name        = "Menu",
			icon        = "menu",
			variant     = "secondary",
			size        = side,
			tooltip     = Locale.Get("nav_menu_title"),
			disabled    = props.blocked,
			zIndex      = 3,
			onActivated = props.onActivated,
		}),
		-- Console: which button opens it (DPadDown).
		hint = console and e("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 1),
			Position               = UDim2.new(0.5, 0, 1, -2),
			Size                   = UDim2.fromOffset(side, 14),
			BackgroundTransparency = 1,
			Text                   = "▾",
			TextColor3             = R.text.secondary,
			FontFace               = Theme.FontFaces.bold,
			TextSize               = 14,
			ZIndex                 = 5,
		}) or nil,
		badge = (not props.blocked) and e(Badge.View, { count = props.badge, zIndex = 6 }) or nil,
	})
end

local function MenuSurface(props)
	local ff = useFormFactor()
	local state = Model.useStack()
	local getBadge = Badge.useBadges()
	local place = Model.resolvePlace(props.place, nil)
	local groups = Model.useGroups(place)  -- §AGX/X18b: re-reads on gate changes

	-- MenuToggle (M / DPadDown), bound while mounted.
	local placeRef = React.useRef(place)
	placeRef.current = place
	React.useEffect(function()
		local IS = getInputSystem()
		if not IS or type(IS.BindAction) ~= "function" then return nil end
		local id = IS.BindAction("MenuToggle", function(_, inputState)
			if inputState ~= "Began" then return end
			toggle(placeRef.current)
		end)
		return function()
			if IS.UnbindAction then IS.UnbindAction("MenuToggle", id) end
		end
	end, {})

	local rail = ff.design.rail or {}
	local gamepad = ff.kind == "Console" or ff.input == "Gamepad"
	local collapsed = props.collapsed
	if collapsed == nil then collapsed = rail.collapsed == true end
	collapsed = collapsed or gamepad   -- radial on any gamepad (§4.5)
	local blocked = state.blocked == true

	local content
	if collapsed then
		local total = 0
		for _, g in ipairs(groups) do
			total += Badge.sum(getBadge, Model.badgeKeys(g.items))
		end
		content = e(MenuButton, {
			side        = rail.menuButton or (ff.kind == "Console" and 64 or 48),
			console     = gamepad,
			blocked     = blocked,
			badge       = total,
			onActivated = function() toggle(place) end,
		})
	else
		content = e(MenuRail, { place = place, blocked = blocked })
	end

	-- Placement: the HUD's Layout rect when given, else fill the parent.
	local rect = props.rect
	return e("Frame", {
		Name                   = "MenuSurface",
		AnchorPoint            = (type(rect) == "table" and rect.anchorPoint) or Vector2.zero,
		Position               = (type(rect) == "table" and rect.position) or UDim2.fromScale(0, 0),
		Size                   = (type(rect) == "table" and rect.size) or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = 2,
	}, { content = content })
end

-- Same export shape as EmoteWheel: a memo element type carrying the
-- imperative API (React accepts it wherever a component is expected).
local MenuSurfaceExport = React.memo(MenuSurface)
MenuSurfaceExport.toggle    = toggle
MenuSurfaceExport.Component = MenuSurface

return MenuSurfaceExport
