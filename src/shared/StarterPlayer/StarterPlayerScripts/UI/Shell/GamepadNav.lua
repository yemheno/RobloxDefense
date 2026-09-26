-- UI/Shell/GamepadNav.lua
--[[
    §AGX/UI-P7: gamepad navigation for PanelHost entries (docs/UI_REVAMP.md
    §5 P7, shell-spec §3.5). Used by PanelHost's EntryWrapper; every hook is
    unconditional and inert unless the entry is the visible top AND
    FormFactor input == "Gamepad", so mouse / touch behave exactly as before.

    GamepadNav.useEntryNav(frameRef, { enabled, entryId }) -> { hasTabs }
      • First focus: when the entry becomes top, select the panel's own
        useFirstFocus target if it set one, else GamepadFocus.findFirst on
        the wrapper (retried briefly while content mounts). A selection
        restored by PanelStack on pop (rec.restoreSelection) is kept.
      • Re-focus: if the selection drops to nil while this entry is top (the
        selected row was removed, a tab switch unmounted it), pick again.
      • LB / RB (CAS "RD_UITabs", High+1, only while a shown Tabs is inside
        the top entry): cycle tabs, skipping locked ones. If the focus was on
        a tab (or lost) it follows the new active tab.
      • Right stick (CAS "RD_UIScroll", High+1, while top): scroll the
        nearest scrollable ScrollingFrame around the selection; Pass when
        there is none (the camera keeps the stick). Nothing is bound while
        no panel is open, so combat twin-stick aim is untouched.
      Both CAS actions are unbound on pop / when the entry stops being top /
      on a switch away from the gamepad (owner-guarded, GamepadFocus.bindOwned).

    GuiService.AutoSelectGuiEnabled (the P7 decision, shell-spec §3.5): left at
    the engine default (on). The Select / View button still toggles the
    engine's selection mode over the HUD when no panel is open; while a
    panel is top, first focus and re-focus keep the pad inside it.

    GamepadNav.Hints{ tabs, side }   A Select · B Back (· LB/RB Tabs) strip
    GamepadNav.clearIfInside(gui)    clear GuiService.SelectedObject if it is
                                     inside `gui` or detached (all closed)
]]

local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local Players              = game:GetService("Players")
local GuiService           = game:GetService("GuiService")
local RunService           = game:GetService("RunService")
local UserInputService     = game:GetService("UserInputService")
local React = require(ReplicatedStorage.Packages.React)

local Common       = script.Parent.Parent:WaitForChild("Common")
local Theme        = require(Common:WaitForChild("Theme"))
local GamepadFocus = require(Common:WaitForChild("GamepadFocus"))

local Locale = nil
do
	local lp = Players.LocalPlayer
	local ps = lp and lp:FindFirstChild("PlayerScripts")
	local mods = ps and ps:FindFirstChild("Modules")
	local mod = mods and mods:FindFirstChild("Locale")
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then Locale = res end
	end
end

local e = React.createElement
local R = Theme.Roles

local CAS_TABS   = "RD_UITabs"
local CAS_SCROLL = "RD_UIScroll"
local CAS_PRIORITY = Enum.ContextActionPriority.High.Value + 1
local FOCUS_TRIES = 12   -- x 0.05 s

local GamepadNav = {}

local function loc(key, fallback)
	if Locale and type(Locale.Has) == "function" and Locale.Has(key) then
		return Locale.Get(key)
	end
	return fallback
end

-- Pick a first focus in the wrapper unless the selection is already inside.
local function focusInto(frame)
	local cur = GuiService.SelectedObject
	if cur and cur.Parent and GamepadFocus.isInside(cur, frame) then return true end
	local target = GamepadFocus.findFirst(frame)
	if target then
		GamepadFocus.select(target)
		return true
	end
	return false
end

function GamepadNav.clearIfInside(gui)
	task.defer(function()
		local cur = GuiService.SelectedObject
		if not cur then return end
		if cur.Parent == nil or (gui and cur:IsDescendantOf(gui)) then
			GamepadFocus.select(nil)
		end
	end)
end

function GamepadNav.useEntryNav(frameRef, opts)
	local enabled = opts.enabled == true
	local hasTabs = GamepadFocus.useTabsIn(frameRef, enabled)

	-- First focus + re-focus while top.
	React.useEffect(function()
		if not enabled then return nil end
		GamepadFocus.installDefault()
		local alive = true
		local pending = false
		local function tryFocus()
			if pending then return end
			pending = true
			task.spawn(function()
				-- One frame first: the panel's own useFirstFocus (child effect)
				-- and PanelStack's pop-restore land before we look.
				task.wait()
				for _ = 1, FOCUS_TRIES do
					if not alive then break end
					local frame = frameRef.current
					if frame and focusInto(frame) then break end
					task.wait(0.05)
				end
				pending = false
			end)
		end
		tryFocus()
		local conn = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
			if GuiService.SelectedObject == nil and alive then
				task.delay(0.05, function()
					if alive and GuiService.SelectedObject == nil then tryFocus() end
				end)
			end
		end)
		return function()
			alive = false
			conn:Disconnect()
		end
	end, { enabled })

	-- LB / RB: cycle the top entry's tabs.
	local tabsOn = enabled and hasTabs
	React.useEffect(function()
		if not tabsOn then return nil end
		local owner = {}
		GamepadFocus.bindOwned(CAS_TABS, owner, function(_, state, input)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Sink
			end
			local frame = frameRef.current
			local handle = frame and GamepadFocus.tabsIn(frame)
			if not handle or type(handle.cycle) ~= "function" then
				return Enum.ContextActionResult.Pass
			end
			local dir = (input.KeyCode == Enum.KeyCode.ButtonL1) and -1 or 1
			local newId = handle.cycle(dir)
			if newId ~= nil then
				task.defer(function()
					local cur = GuiService.SelectedObject
					local lost = not cur or not cur.Parent or not GamepadFocus.isInside(cur, frame)
					local onTab = cur ~= nil and string.sub(cur.Name, 1, 4) == "Tab_"
					if lost or onTab then
						local root = handle.getRoot and handle.getRoot()
						local tab = root and root:FindFirstChild("Tab_" .. tostring(newId), true)
						if tab and GamepadFocus.canSelect(tab, frame) then
							GamepadFocus.select(tab)
						else
							focusInto(frame)
						end
					end
				end)
			end
			return Enum.ContextActionResult.Sink
		end, CAS_PRIORITY, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
		return function()
			GamepadFocus.unbindOwned(CAS_TABS, owner)
		end
	end, { tabsOn })

	-- Right stick: scroll the ScrollingFrame around the selection.
	React.useEffect(function()
		if not enabled then return nil end
		local owner = {}
		local stick = Vector2.zero
		GamepadFocus.bindOwned(CAS_SCROLL, owner, function(_, state, input)
			local frame = frameRef.current
			if not frame or not GamepadFocus.scrollTarget(frame) then
				stick = Vector2.zero
				return Enum.ContextActionResult.Pass
			end
			if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				stick = Vector2.zero
			else
				stick = Vector2.new(input.Position.X, input.Position.Y)
			end
			return Enum.ContextActionResult.Sink
		end, CAS_PRIORITY, Enum.KeyCode.Thumbstick2)
		local conn = RunService.Heartbeat:Connect(function(dt)
			if stick.Magnitude == 0 then return end
			local frame = frameRef.current
			local sf = frame and GamepadFocus.scrollTarget(frame)
			if sf then
				GamepadFocus.scrollBy(sf, stick, dt)
			else
				stick = Vector2.zero
			end
		end)
		return function()
			conn:Disconnect()
			GamepadFocus.unbindOwned(CAS_SCROLL, owner)
		end
	end, { enabled })

	return { hasTabs = hasTabs }
end

-- ── Button-hint strip ────────────────────────────────────

local function keyImage(keyCode)
	local ok, img = pcall(function()
		return UserInputService:GetImageForKeyCode(keyCode)
	end)
	if ok and type(img) == "string" and img ~= "" then return img end
	return nil
end

local function keyIcon(keyCode, order)
	local img = keyImage(keyCode)
	return img and e("ImageLabel", {
		LayoutOrder            = order,
		Size                   = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 1,
		Image                  = img,
	}) or nil
end

--- props: keys = { KeyCode, ... }, glyph (text when no key art), label, order
local function Hint(props)
	local children = {
		layout = e("UIListLayout", {
			FillDirection     = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder         = Enum.SortOrder.LayoutOrder,
			Padding           = UDim.new(0, 6),
		}),
		label = e("TextLabel", {
			LayoutOrder            = 10,
			Size                   = UDim2.fromOffset(0, 26),
			AutomaticSize          = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text                   = props.label,
			TextColor3             = R.text.secondary,
			FontFace               = Theme.FontFaces.bold,
			TextSize               = 16,
		}),
	}
	local anyArt = false
	for i, key in ipairs(props.keys) do
		local icon = keyIcon(key, i)
		if icon then
			anyArt = true
			children["k" .. i] = icon
		end
	end
	if not anyArt then
		children.glyph = e("TextLabel", {
			LayoutOrder            = 1,
			Size                   = UDim2.fromOffset(0, 26),
			AutomaticSize          = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text                   = props.glyph,
			TextColor3             = R.text.primary,
			FontFace               = Theme.FontFaces.bold,
			TextSize               = 18,
		})
	end
	return e("Frame", {
		Name                   = "Hint_" .. props.keys[1].Name,
		Size                   = UDim2.fromOffset(0, 28),
		AutomaticSize          = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder            = props.order,
	}, children)
end

--- props: tabs (boolean), side (boolean: right sheet), zIndex
function GamepadNav.Hints(props)
	return e("Frame", {
		Name                   = "GamepadHints",
		AnchorPoint            = props.side and Vector2.new(1, 1) or Vector2.new(0.5, 1),
		Position               = props.side and UDim2.new(1, -Theme.Space.lg, 1, -Theme.Space.sm)
			or UDim2.new(0.5, 0, 1, -Theme.Space.sm),
		Size                   = UDim2.fromOffset(0, 36),
		AutomaticSize          = Enum.AutomaticSize.X,
		BackgroundColor3       = R.surface.sunken,
		BackgroundTransparency = 0.15,
		BorderSizePixel        = 0,
		Active                 = false,
		Selectable             = false,
		ZIndex                 = props.zIndex or 1000,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
		pad = e("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.Space.md), PaddingRight = UDim.new(0, Theme.Space.md),
		}),
		layout = e("UIListLayout", {
			FillDirection     = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder         = Enum.SortOrder.LayoutOrder,
			Padding           = UDim.new(0, Theme.Space.lg),
		}),
		a = e(Hint, { keys = { Enum.KeyCode.ButtonA }, glyph = "Ⓐ", label = loc("hint_select", "Select"), order = 1 }),
		b = e(Hint, { keys = { Enum.KeyCode.ButtonB }, glyph = "Ⓑ", label = loc("hint_back", "Back"), order = 2 }),
		tabs = props.tabs and e(Hint, {
			keys = { Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1 },
			glyph = "LB/RB", label = loc("hint_tabs", "Tabs"), order = 3,
		}) or nil,
	})
end

return GamepadNav
