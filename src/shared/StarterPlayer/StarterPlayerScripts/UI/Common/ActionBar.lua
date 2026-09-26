-- UI/Common/ActionBar.lua
--[[
    §AGX/UI-P2: desktop / console skill bar (UI_REVAMP §3 HUD regions,
    structure-and-flow.md §3.5 "action bar"). Mounted by CombatApp when
    FormFactor is NOT touch; the touch equivalent is SkillPad.

      • Bottom-centre bar: Skill1-4 plus a smaller Dash slot.
      • Key badge per slot from the CURRENT binding for the active device
        (InputSystem.GetBindingDisplayName, re-read on rebind and on
        keyboard <-> gamepad switches).
      • Radial cooldown wipe + seconds per slot (SkillPad.CooldownWipe over
        SkillInput.GetCooldown), so PC shows cooldowns for the first time.
      • Slots dim when unaffordable (D10).
      • Clicking a slot casts it through InputSystem.FireAction.
      • Hidden while a fullscreen menu is open, outside "Combat", and while
        knocked down / dead (same rule as SkillPad).

    Sizes/positions: Theme.Layout[kind].actionBar (via FormFactor tokens).

    §AGX/UI-P5 (C5): publishes UI_ActionBarTopPx (screen px from the safe
    area's bottom edge to the bar's top; nil while not visible) for the
    HUD's combo placement (shell-spec §4.3).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React       = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local e = React.createElement

local player  = Players.LocalPlayer
local Modules = player:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local Common  = script.Parent

local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local SkillPad      = require(Common:WaitForChild("SkillPad"))
local InputSystem   = require(Modules:WaitForChild("InputSystem"))
local SkillInput    = require(Modules:WaitForChild("SkillInput"))

local C = Theme.Colors
local F = Theme.Fonts
local ControlsLayout = Theme.Layout.CombatControls

-- §AGX/UI-P5: attribute names (HUD/Layout is a pure module: React + Theme).
local HudLayout = require(player:WaitForChild("PlayerScripts"):WaitForChild("UI"):WaitForChild("HUD"):WaitForChild("Layout"))

local CooldownWipe       = SkillPad.CooldownWipe
local useControlsVisible = SkillPad.useControlsVisible
local skillLabel         = SkillPad.skillLabel

local DASH_SLOT = 5

-- Gamepad names are long ("ButtonX", "ButtonL1"); badges want "X", "L1".
local function badgeText(actionName, platform)
	local name = InputSystem.GetBindingDisplayName(actionName, platform)
	if platform == "Gamepad" then
		name = string.gsub(name, "^Button", "")
		name = string.gsub(name, "^DPad", "D-")
	end
	return name
end

--- props: action, slot, size, label, keyText, dimmed, radius, badge,
---        stroke, fontBody, fontMin, fontTitle, order, isUlt
local function Slot(props)
	local corner = UDim.new(0, props.radius)
	return e("TextButton", {
		Name                   = props.action,
		LayoutOrder            = props.order,
		Size                   = UDim2.fromOffset(props.size, props.size),
		BackgroundColor3       = props.dimmed and C.locked or C.panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel        = 0,
		AutoButtonColor        = false,
		Active                 = true,
		Text                   = props.label,
		TextColor3             = props.dimmed and C.textDim or C.text,
		Font                   = F.bold,
		TextSize               = props.fontBody,
		ZIndex                 = 2,
		[React.Event.Activated] = function()
			InputSystem.FireAction(props.action, "Began")
			InputSystem.FireAction(props.action, "Ended")
		end,
	}, {
		corner = e("UICorner", { CornerRadius = corner }),
		stroke = e("UIStroke", {
			Color           = props.isUlt and C.gold or C.textDim,
			Thickness       = props.stroke,
			Transparency    = props.dimmed and 0.6 or 0.2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		wipe = e(CooldownWipe, {
			slot     = props.slot,
			corner   = corner,
			textSize = props.fontTitle,
			zIndex   = 3,
		}),
		key = e("TextLabel", {
			AnchorPoint            = Vector2.new(0, 0),
			Position               = UDim2.fromOffset(2, 2),
			Size                   = UDim2.fromOffset(props.badge * 2, props.badge),
			BackgroundTransparency = 1,
			Text                   = props.keyText,
			TextColor3             = C.accent2,
			TextStrokeTransparency = 0.5,
			TextXAlignment         = Enum.TextXAlignment.Left,
			Font                   = F.bold,
			TextSize               = props.fontMin,
			ZIndex                 = 5,
		}),
	})
end

--- props: hidden (true while a fullscreen menu is open)
local function ActionBar(props)
	local ff = useFormFactor()
	local visible = useControlsVisible(props.hidden)
	local _ver, setVer = React.useState(0)

	React.useEffect(function()
		local function bump()
			setVer(function(v) return v + 1 end)
		end
		local d1 = InputSystem.OnBindingChanged(bump)
		local d2 = InputSystem.OnInputTypeChanged(bump)
		local d3 = SkillInput.OnSkillStateChanged(bump)
		return function()
			d1(); d2(); d3()
		end
	end, {})

	local t = ff.tokens
	local bar = t.actionBar
	local playerGui = player:FindFirstChildOfClass("PlayerGui")

	-- §AGX/UI-P5 (C5): footprint attribute (before the early return: hooks
	-- stay unconditional).
	local barTop = (visible and bar) and (bar.bottom + bar.slot + 2 * bar.padding) or nil
	React.useEffect(function()
		ReplicatedStorage:SetAttribute(HudLayout.ATTR.actionBarTop, barTop)
	end, { barTop or -1 })
	React.useEffect(function()
		return function()
			ReplicatedStorage:SetAttribute(HudLayout.ATTR.actionBarTop, nil)
		end
	end, {})

	if not bar or not playerGui then return nil end

	local platform = InputSystem.GetActiveInputType()
	if platform == "Touch" then platform = "Keyboard" end

	local children = {
		layout = e("UIListLayout", {
			FillDirection       = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment   = Enum.VerticalAlignment.Bottom,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Padding             = UDim.new(0, bar.gap),
		}),
		padding = e("UIPadding", {
			PaddingLeft   = UDim.new(0, bar.padding),
			PaddingRight  = UDim.new(0, bar.padding),
			PaddingTop    = UDim.new(0, bar.padding),
			PaddingBottom = UDim.new(0, bar.padding),
		}),
	}

	local common = {
		radius    = bar.radius,
		badge     = bar.badge,
		stroke    = bar.stroke,
		fontBody  = t.font.body,
		fontMin   = t.font.min,
		fontTitle = t.font.title,
	}
	local function slotProps(extra)
		local p = table.clone(common)
		for k, v in pairs(extra) do p[k] = v end
		return p
	end

	for slot = 1, 4 do
		local action = "Skill" .. slot
		children[action] = e(Slot, slotProps({
			action  = action,
			slot    = slot,
			order   = slot,
			size    = bar.slot,
			label   = skillLabel(slot),
			keyText = badgeText(action, platform),
			dimmed  = not SkillInput.IsAffordable(slot),
			isUlt   = slot == 4,
		}))
	end
	children.Dash = e(Slot, slotProps({
		action   = "Dash",
		slot     = DASH_SLOT,
		order    = 5,
		size     = bar.dashSlot,
		label    = "DASH",
		keyText  = badgeText("Dash", platform),
		dimmed   = false,
		fontBody = t.font.min,
	}))

	children.corner = e("UICorner", { CornerRadius = UDim.new(0, bar.radius + bar.padding) })

	local width  = 4 * bar.slot + bar.dashSlot + 4 * bar.gap + 2 * bar.padding
	local height = bar.slot + 2 * bar.padding

	return ReactRoblox.createPortal(e("ScreenGui", {
		Name           = "ActionBarGui",
		ResetOnSpawn   = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder   = ControlsLayout.displayOrder,
		ScreenInsets   = Enum.ScreenInsets.DeviceSafeInsets,
		Enabled        = visible,
	}, {
		Bar = e("Frame", {
			AnchorPoint            = Vector2.new(0.5, 1),
			Position               = UDim2.new(0.5, 0, 1, -bar.bottom),
			Size                   = UDim2.fromOffset(width, height),
			BackgroundColor3       = C.bg,
			BackgroundTransparency = 0.45,
			BorderSizePixel        = 0,
		}, children),
	}), playerGui)
end

return ActionBar
