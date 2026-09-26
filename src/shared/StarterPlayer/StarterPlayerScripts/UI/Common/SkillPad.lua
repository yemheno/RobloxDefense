-- UI/Common/SkillPad.lua
--[[
    §AGX/UI-P2: touch combat controls (docs/ui_audit/mobile.md M1, §2.4, §2.5;
    structure-and-flow.md UX-04). Mounted by CombatApp only when
    FormFactor.isTouch.

      • Attack (96 px phone / 112 tablet) in the bottom-right corner.
      • Skill1-4 (60 / 72 px) on the arc around it (180°, 210°, 240°, 270°).
      • Dash (52 / 60 px) left of Skill1.
      • Radial cooldown wipe + seconds on Skill1-4 and Dash
        (SkillInput.GetCooldown / OnCooldownChanged).
      • Skills dim when unaffordable (D10, SkillInput.IsAffordable).
      • Every button calls InputSystem.FireAction(action, "Began"/"Ended"),
        so the input context gate applies (D6: suppressed in "UI").
      • Hidden while a fullscreen menu is open (`hidden` prop), outside the
        "Combat" context (e.g. the Horde vote pause) and while knocked
        down / dead.
      • HordeMode (JoystickAim active): Attack is a twin-stick (D11). Press =
        attack, drag = aim (JoystickAim.AimDelta), hold = repeat. The
        separate JoystickAim stick is hidden while the pad is mounted.

    Styling is neutral (Theme.Colors / Theme.Fonts). Every size and position
    comes from Theme.Layout[kind] via FormFactor tokens; nothing is hard-coded
    here, so D1/D2 can restyle it from Theme.lua.

    Rendered through a portal into its own ScreenGui with
    ScreenInsets = DeviceSafeInsets, so the notch / home indicator are
    respected.

    §AGX/UI-P5 (C5): publishes its footprint as client-local
    ReplicatedStorage attributes (screen px, from the safe area's bottom /
    right edges; shell-spec §4.3), nil while not visible:
      UI_SkillPadTopPx   top of the arc (Skill 4) / Dash
      UI_SkillPadLeftPx  left of the Dash button
    The HUD layout (rail band, combo) and Notify (column cap) read them.

    Module exports (AchievementsUI-style table):
      .default            the SkillPad component
      .CooldownWipe       radial wipe overlay, reused by ActionBar
      .useControlsVisible hook: hidden prop + context + death state
      .skillLabel(slot)   short label for a slot's skill (class initials)
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local React       = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local e = React.createElement

local player        = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")
local Modules       = PlayerScripts:WaitForChild("Modules")
local Common        = script.Parent

local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local InputSystem   = require(Modules:WaitForChild("InputSystem"))
local SkillInput    = require(Modules:WaitForChild("SkillInput"))
local JoystickAim   = require(Modules:WaitForChild("MovementSystem"):WaitForChild("JoystickAim"))

local ClassDescriptions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassDescriptions"))
-- §AGX/UI-P5: footprint maths shared with the HUD layout and Notify.
local HudLayout = require(PlayerScripts:WaitForChild("UI"):WaitForChild("HUD"):WaitForChild("Layout"))

local C = Theme.Colors
local F = Theme.Fonts
local ControlsLayout = Theme.Layout.CombatControls

local DASH_SLOT = 5   -- SkillInput's slot for the Dash action

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

local function round(n)
	return math.floor(n + 0.5)
end

--- Short label for a slot: initials of the active class's skill name
--- ("Shield Boomerang" -> "SB"), else the slot number.
local function skillLabel(slot)
	local className = SkillInput.GetActiveClass()
	local info = className and ClassDescriptions[className]
	if info and info.skills then
		for _, skill in ipairs(info.skills) do
			if skill.slot == slot and type(skill.name) == "string" then
				local initials = ""
				for word in string.gmatch(skill.name, "%a+") do
					initials ..= string.upper(string.sub(word, 1, 1))
				end
				if #initials > 0 then return string.sub(initials, 1, 3) end
			end
		end
	end
	return tostring(slot)
end

local function isDownState()
	local s = player:GetAttribute("DeathState")
	return s == "KnockedDown" or s == "Dead"
end

--- Visible = not hidden by a menu, in the "Combat" context, and alive.
local function useControlsVisible(hidden)
	local context, setContext = React.useState(InputSystem.GetContext())
	local down, setDown = React.useState(isDownState())

	React.useEffect(function()
		setContext(InputSystem.GetContext())
		setDown(isDownState())
		local disconnectCtx = InputSystem.OnContextChanged(setContext)
		local deathConn = player:GetAttributeChangedSignal("DeathState"):Connect(function()
			setDown(isDownState())
		end)
		return function()
			disconnectCtx()
			deathConn:Disconnect()
		end
	end, {})

	return (not hidden) and context == "Combat" and not down
end

-- ═══════════════════════════════════════════════════════════
-- COOLDOWN WIPE
-- ═══════════════════════════════════════════════════════════

-- Two half-clips, each holding a full-size dark disc whose UIGradient has a
-- hard edge through the centre. Rotating the gradients sweeps a sector
-- clockwise from 12 o'clock; the sector size is remaining / total.
local RIGHT_SEQ = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 1),
	NumberSequenceKeypoint.new(1, 1),
})
local LEFT_SEQ = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(0.501, 0),
	NumberSequenceKeypoint.new(1, 0),
})

local function formatSeconds(remaining)
	if remaining >= 10 then
		return tostring(math.ceil(remaining))
	end
	return string.format("%.1f", remaining)
end

--- props: slot, corner (UDim, default round), textSize, zIndex
local function CooldownWipe(props)
	local slot = props.slot
	local rootRef  = React.useRef(nil)
	local rightRef = React.useRef(nil)
	local leftRef  = React.useRef(nil)
	local labelRef = React.useRef(nil)

	React.useEffect(function()
		local hb = nil

		local function apply()
			local root = rootRef.current
			if not root then return false end
			local remaining, total = SkillInput.GetCooldown(slot)
			if remaining <= 0 or total <= 0 then
				root.Visible = false
				return false
			end
			root.Visible = true
			local deg = math.clamp(remaining / total, 0, 1) * 360
			if rightRef.current then rightRef.current.Rotation = math.clamp(deg, 0, 180) end
			if leftRef.current then leftRef.current.Rotation = math.clamp(deg - 180, 0, 180) end
			if labelRef.current then labelRef.current.Text = formatSeconds(remaining) end
			return true
		end

		local function start()
			if hb then
				apply()
				return
			end
			if not apply() then return end
			hb = RunService.Heartbeat:Connect(function()
				if not apply() and hb then
					hb:Disconnect()
					hb = nil
				end
			end)
		end

		local disconnect = SkillInput.OnCooldownChanged(function(changedSlot)
			if changedSlot == nil or changedSlot == slot then start() end
		end)
		start()

		return function()
			disconnect()
			if hb then hb:Disconnect() end
		end
	end, { slot })

	local corner = props.corner or UDim.new(0.5, 0)
	local z = props.zIndex or 3

	local function half(isRight)
		return e("Frame", {
			Size                   = UDim2.fromScale(0.5, 1),
			Position               = UDim2.fromScale(isRight and 0.5 or 0, 0),
			BackgroundTransparency = 1,
			ClipsDescendants       = true,
			ZIndex                 = z,
		}, {
			disc = e("Frame", {
				Size                   = UDim2.fromScale(2, 1),
				Position               = UDim2.fromScale(isRight and -1 or 0, 0),
				BackgroundColor3       = C.dim,
				BackgroundTransparency = 0.35,
				BorderSizePixel        = 0,
				ZIndex                 = z,
			}, {
				corner   = e("UICorner", { CornerRadius = corner }),
				gradient = e("UIGradient", {
					Transparency = isRight and RIGHT_SEQ or LEFT_SEQ,
					ref          = isRight and rightRef or leftRef,
				}),
			}),
		})
	end

	return e("Frame", {
		Name                   = "CooldownWipe",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible                = false,
		ZIndex                 = z,
		ref                    = rootRef,
	}, {
		right = half(true),
		left  = half(false),
		label = e("TextLabel", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text                   = "",
			TextColor3             = C.text,
			TextStrokeTransparency = 0.4,
			Font                   = F.bold,
			TextSize               = props.textSize or 16,
			ZIndex                 = z + 1,
			ref                    = labelRef,
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- PRESS TRACKING
-- ═══════════════════════════════════════════════════════════

-- Tracks ONE press (touch, or mouse in Studio / touch laptops) from the
-- button's InputBegan to that same input's end anywhere on screen, so a
-- finger that slides off the button still releases the hold. Unmounting
-- mid-press releases too (menu opened, pad hidden).
local function usePress(handlers)
	local pressRef = React.useRef(nil)
	local handlersRef = React.useRef(handlers)
	handlersRef.current = handlers

	React.useEffect(function()
		local function matches(input)
			local cur = pressRef.current
			if not cur then return false end
			if input == cur then return true end
			return cur.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1
		end

		local endConn = UserInputService.InputEnded:Connect(function(input)
			if matches(input) then
				pressRef.current = nil
				if handlersRef.current.onEnd then handlersRef.current.onEnd() end
			end
		end)

		local moveConn = UserInputService.InputChanged:Connect(function(input)
			local cur = pressRef.current
			if not cur then return end
			local isOwnTouch = input == cur
			local isMouseDrag = cur.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			if (isOwnTouch or isMouseDrag) and handlersRef.current.onMove then
				handlersRef.current.onMove(Vector2.new(input.Position.X, input.Position.Y))
			end
		end)

		return function()
			endConn:Disconnect()
			moveConn:Disconnect()
			if pressRef.current then
				pressRef.current = nil
				if handlersRef.current.onEnd then handlersRef.current.onEnd() end
			end
		end
	end, {})

	return function(_rbx, input)
		if pressRef.current then return end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
		if input.UserInputState ~= Enum.UserInputState.Begin then return end
		pressRef.current = input
		if handlersRef.current.onBegin then handlersRef.current.onBegin(input) end
	end
end

-- ═══════════════════════════════════════════════════════════
-- BUTTONS
-- ═══════════════════════════════════════════════════════════

--- props: action, slot (nil for Attack), size, position, label, textSize,
---        dimmed, strokeColor, strokeThickness, wipeTextSize, zIndex
local function PadButton(props)
	local onInputBegan = usePress({
		onBegin = function()
			InputSystem.FireAction(props.action, "Began")
		end,
		onEnd = function()
			InputSystem.FireAction(props.action, "Ended")
		end,
	})

	local z = props.zIndex or 2
	return e("TextButton", {
		Name                   = props.action,
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = props.position,
		Size                   = UDim2.fromOffset(props.size, props.size),
		BackgroundColor3       = props.dimmed and C.locked or C.panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel        = 0,
		AutoButtonColor        = false,
		Active                 = true,
		Text                   = props.label,
		TextColor3             = props.dimmed and C.textDim or C.text,
		Font                   = F.bold,
		TextSize               = props.textSize,
		ZIndex                 = z,
		[React.Event.InputBegan] = onInputBegan,
	}, {
		corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		stroke = e("UIStroke", {
			Color           = props.strokeColor or C.textDim,
			Thickness       = props.strokeThickness or 2,
			Transparency    = props.dimmed and 0.6 or 0.2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		wipe = props.slot and e(CooldownWipe, {
			slot     = props.slot,
			textSize = props.wipeTextSize,
			zIndex   = z + 1,
		}) or nil,
	})
end

--- Attack: plain press/hold-repeat, or a twin-stick when `twinStick`.
--- props: size, position, label, textSize, twinStick, deadzone, knob, stroke
local function AttackButton(props)
	local buttonRef = React.useRef(nil)
	local knobRef   = React.useRef(nil)
	local holdRef   = React.useRef(0)   -- press generation (bumped on begin and end)
	local twinRef   = React.useRef(props.twinStick)
	twinRef.current = props.twinStick

	local function resetKnob()
		if knobRef.current then
			knobRef.current.Position = UDim2.fromScale(0.5, 0.5)
			knobRef.current.Visible = false
		end
	end

	local onInputBegan = usePress({
		onBegin = function()
			holdRef.current += 1
			local generation = holdRef.current
			InputSystem.FireAction("Attack", "Began")
			-- Hold = repeat. PlayerAttack's own attack-speed gate throttles.
			task.spawn(function()
				while true do
					task.wait(ControlsLayout.attackRepeat)
					if holdRef.current ~= generation then break end
					InputSystem.FireAction("Attack", "Began")
				end
			end)
		end,
		onMove = function(pos)
			if not twinRef.current then return end
			local btn = buttonRef.current
			if not btn then return end
			local centre = btn.AbsolutePosition + btn.AbsoluteSize / 2
			local delta = pos - centre
			if delta.Magnitude < props.deadzone then return end
			JoystickAim.AimDelta(delta)
			local knob = knobRef.current
			if knob then
				local maxDist = btn.AbsoluteSize.X * 0.35
				local offset = delta.Unit * math.min(delta.Magnitude, maxDist)
				knob.Visible = true
				knob.Position = UDim2.new(0.5, round(offset.X), 0.5, round(offset.Y))
			end
		end,
		onEnd = function()
			holdRef.current += 1   -- new generation: stops the repeat loop
			InputSystem.FireAction("Attack", "Ended")
			if twinRef.current then JoystickAim.EndAim() end
			resetKnob()
		end,
	})

	return e("TextButton", {
		Name                   = "Attack",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = props.position,
		Size                   = UDim2.fromOffset(props.size, props.size),
		BackgroundColor3       = C.panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel        = 0,
		AutoButtonColor        = false,
		Active                 = true,
		Text                   = props.label,
		TextColor3             = C.text,
		Font                   = F.title,
		TextSize               = props.textSize,
		ZIndex                 = 2,
		ref                    = buttonRef,
		[React.Event.InputBegan] = onInputBegan,
	}, {
		corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		stroke = e("UIStroke", {
			Color           = C.accent,
			Thickness       = props.stroke,
			Transparency    = 0.1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		-- Twin-stick knob (HordeMode only), moved imperatively on drag.
		knob = props.twinStick and e("Frame", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			Size                   = UDim2.fromOffset(props.knob, props.knob),
			BackgroundColor3       = C.text,
			BackgroundTransparency = 0.5,
			BorderSizePixel        = 0,
			Visible                = false,
			ZIndex                 = 3,
			ref                    = knobRef,
		}, {
			corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		}) or nil,
	})
end

-- ═══════════════════════════════════════════════════════════
-- SKILL PAD
-- ═══════════════════════════════════════════════════════════

--- props: hidden (true while a fullscreen menu is open)
local function SkillPad(props)
	local ff = useFormFactor()
	local visible = useControlsVisible(props.hidden)
	local twinStick, setTwinStick = React.useState(JoystickAim.IsActive())
	local _stateVer, setStateVer = React.useState(0)

	-- Take over JoystickAim's stick for as long as the pad is mounted.
	React.useEffect(function()
		JoystickAim.SetExternalControl(true)
		setTwinStick(JoystickAim.IsActive())
		local disconnect = JoystickAim.OnActiveChanged(setTwinStick)
		return function()
			disconnect()
			JoystickAim.SetExternalControl(false)
		end
	end, {})

	-- Re-render for affordability / class / resource changes.
	React.useEffect(function()
		return SkillInput.OnSkillStateChanged(function()
			setStateVer(function(v) return v + 1 end)
		end)
	end, {})

	local t = ff.tokens
	local pad = t.skillPad
	local playerGui = player:FindFirstChildOfClass("PlayerGui")

	-- §AGX/UI-P5 (C5): footprint attributes (screen px; nil when hidden).
	local fp = (visible and pad) and HudLayout.padFootprint(pad, t.attack, t.skill, t.dash) or nil
	local fpTop  = fp and math.ceil(fp.top) or nil
	local fpLeft = fp and math.ceil(fp.left) or nil
	React.useEffect(function()
		ReplicatedStorage:SetAttribute(HudLayout.ATTR.skillPadTop, fpTop)
		ReplicatedStorage:SetAttribute(HudLayout.ATTR.skillPadLeft, fpLeft)
	end, { fpTop or -1, fpLeft or -1 })
	React.useEffect(function()
		return function()
			ReplicatedStorage:SetAttribute(HudLayout.ATTR.skillPadTop, nil)
			ReplicatedStorage:SetAttribute(HudLayout.ATTR.skillPadLeft, nil)
		end
	end, {})

	-- Tokens missing (non-touch kind mid-switch) or no PlayerGui: render nothing.
	if not pad or not playerGui then return nil end

	local ax, ay = pad.anchor.X, pad.anchor.Y
	local function at(dx, dy)
		return UDim2.new(1, round(-ax + dx), 1, round(-ay + dy))
	end

	local children = {}
	if visible then
		children.Attack = e(AttackButton, {
			size      = t.attack,
			position  = at(0, 0),
			label     = "ATK",
			textSize  = t.font.title,
			twinStick = twinStick,
			deadzone  = pad.aimDeadzone,
			knob      = pad.knob,
			stroke    = pad.ultStroke,
		})

		for slot = 1, 4 do
			local rad = math.rad(pad.arcAngles[slot])
			local affordable = SkillInput.IsAffordable(slot)
			children["Skill" .. slot] = e(PadButton, {
				action          = "Skill" .. slot,
				slot            = slot,
				size            = t.skill,
				position        = at(pad.arcRadius * math.cos(rad), pad.arcRadius * math.sin(rad)),
				label           = skillLabel(slot),
				textSize        = t.font.body,
				wipeTextSize    = t.font.title,
				dimmed          = not affordable,
				strokeColor     = slot == 4 and C.gold or nil,
				strokeThickness = slot == 4 and pad.ultStroke or pad.stroke,
			})
		end

		children.Dash = e(PadButton, {
			action          = "Dash",
			slot            = DASH_SLOT,
			size            = t.dash,
			position        = at(pad.dashOffset.X, pad.dashOffset.Y),
			label           = "DASH",
			textSize        = t.font.min,
			wipeTextSize    = t.font.body,
			strokeThickness = pad.stroke,
		})
	end

	return ReactRoblox.createPortal(e("ScreenGui", {
		Name           = "SkillPadGui",
		ResetOnSpawn   = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder   = ControlsLayout.displayOrder,
		ScreenInsets   = Enum.ScreenInsets.DeviceSafeInsets,
		Enabled        = visible,
	}, children), playerGui)
end

return {
	default            = SkillPad,
	CooldownWipe       = CooldownWipe,
	useControlsVisible = useControlsVisible,
	skillLabel         = skillLabel,
}
