-- shared/StarterPlayerScripts/UI/EmoteWheel.lua
--[[
    Circular emote selection menu.

    • Press Q to open / close the wheel.
    • 4 emote buttons arranged radially (top, right, bottom, left).
    • Clicking an emote plays the animation and closes the wheel.
    • Uses Roblox default animation IDs — swap these for custom ones later.
    • Auto-closes if player starts moving.
    • §AGX/UI-P2: touch — EmoteWheel.open()/close()/toggle() for on-screen
      buttons (the HUD QuickButtons Emote button); closes on outside
      tap and on thumbstick movement (Humanoid.MoveDirection).
    • §AGX/UI-P6: Geometry stays in SCREEN px from wheelMetrics() (exported
      to MenuRadial); the wheel lives in the unscaled AppRoot, so text sizes
      are Theme.typeFor sizes pre-multiplied by ff.uiScale (Theme.Layout
      option (b), no scale-inside-scale). Colours are Theme roles. The centre
      is an IconButton (✕ on touch, the bound key elsewhere) that also closes
      the wheel.
]]

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React     = require(ReplicatedStorage.Packages.React)
local e         = React.createElement
local useState  = React.useState
local useEffect = React.useEffect
local useRef    = React.useRef

local LocalPlayer = Players.LocalPlayer

-- InputSystem loaded synchronously (Client has already required it before
-- the React tree mounts, so require() returns the cached module instantly).
local InputSystem = nil
do
	local modules = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
	local is = modules:FindFirstChild("InputSystem")
	if is then
		InputSystem = require(is)
	end
end

-- AnimationSystem loaded synchronously (same reasoning as InputSystem).
local AnimationSystem = nil
do
	local modules = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
	local as = modules:FindFirstChild("AnimationSystem")
	if as then
		AnimationSystem = require(as)
	end
end

-- ── Emote catalog (centralised in EmoteConfig) ───────────
local EmoteConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EmoteConfig"))
local EMOTES = EmoteConfig.Emotes

-- §AGX/UI-P2: M3 — wheel is sized in pixels from the viewport's short side,
-- so it stays square and its buttons stay tappable. See wheelMetrics() below.
local WHEEL_SHORT_FRAC = 0.62   -- wheel diameter as a share of the short side
local WHEEL_MIN, WHEEL_MAX = 220, 320
local BTN_MIN          = 56     -- >= 48 px touch target
local MOVE_CLOSE_EPS   = 0.1    -- Humanoid.MoveDirection magnitude that closes it

-- §AGX/UI-P3: exported (EmoteWheel.wheelMetrics) for MenuRadial, B6.
-- `opts` overrides the wheel's own numbers: { shortFrac, min, max, btnMin }
-- (screen px, like the defaults). No opts = the emote wheel.
local function wheelMetrics(viewport, opts)
	opts = opts or {}
	local short = math.min(viewport.X, viewport.Y)
	if short <= 0 then short = 720 end
	local wheel  = math.clamp(math.floor(short * (opts.shortFrac or WHEEL_SHORT_FRAC)),
		opts.min or WHEEL_MIN, opts.max or WHEEL_MAX)
	local btn    = math.max(opts.btnMin or BTN_MIN, math.floor(wheel * 0.26))
	local radius = math.floor(wheel / 2 - btn / 2 - 6)
	return wheel, btn, radius
end
-- §AGX/UI-P2: M3 — imperative open/close so touch UI (the HUD
-- QuickButtons Emote button, via the Shell) can open the wheel.
-- AppearanceBar Emote button, a later HUD button) can open the wheel.
-- Every mounted wheel registers its setter here.
local visibilitySetters = {}

local function setAllVisible(fnOrValue)
	for setter in pairs(visibilitySetters) do
		setter(fnOrValue)
	end
end

-- ── Theme (§AGX/UI-P6: roles) ─────────
local Common        = script.Parent:WaitForChild("Common")
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local IconButton    = require(Common:WaitForChild("IconButton"))
-- §AGX/UI-FIX: R6 — gamepad first focus while the wheel is open.
local GamepadFocus  = require(Common:WaitForChild("GamepadFocus"))
local R = Theme.Roles

-- Text style scaled for this unscaled (screen px) tree.
local function scaledType(style, ff)
	local ty = Theme.typeFor(style, ff.kind)
	local s = ff.uiScale or 1
	return {
		font = ty.font,
		size = math.floor(ty.size * s + 0.5),
		min  = math.floor(ty.min * s + 0.5),
		max  = math.floor(ty.max * s + 0.5),
	}
end

-- ── Animation helper (plays anim, stops previous) ─────────
local function playEmote(emote)
	local character = LocalPlayer.Character
	if not character or not AnimationSystem then return end

	-- Skip placeholder animations (animId = rbxassetid://0 or empty)
	local animId = emote.animId
	if not animId or animId == "" or animId == "rbxassetid://0" then
		warn("[EmoteWheel] No animation set for emote '" .. tostring(emote.id)
			.. "'. Upload an R6 animation and update EmoteConfig.animId.")
		return
	end

	AnimationSystem.Play(character, animId, {
		category = "emote",
		looped   = emote.looped == true,
		fadeIn   = 0.1,
	})
end

-- ═══════════════════════════════════════════════════════════
-- EMOTE BUTTON
-- ═══════════════════════════════════════════════════════════
local function EmoteButton(props)
	local emote    = props.emote
	local onSelect = props.onSelect
	local hovered, setHovered = useState(false)
	local ff = useFormFactor()
	local ty = scaledType("caption", ff)

	return e("TextButton", {
		-- §AGX/UI-P2: M3 — pixel size (>= 56 px), not a scale of the wheel.
		Name              = "Emote_" .. tostring(emote.id),
		Size              = UDim2.fromOffset(props.size, props.size),
		AnchorPoint       = Vector2.new(0.5, 0.5),
		Position          = props.position,
		BackgroundColor3  = hovered and R.surface.track or R.surface.raised,
		BorderSizePixel   = 0,
		AutoButtonColor   = false,
		Text              = "",
		ZIndex            = 3,
		[React.Event.Activated]       = function() onSelect(emote) end,
		-- hover tint only (mobile.md M18: nothing is lost on touch)
		[React.Event.MouseEnter]      = function() setHovered(true) end,
		[React.Event.MouseLeave]      = function() setHovered(false) end,
		[React.Event.SelectionGained] = function() setHovered(true) end,
		[React.Event.SelectionLost]   = function() setHovered(false) end,
	}, {
		Corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),

		Stroke = e("UIStroke", {
			Color     = hovered and R.border.focus or R.border.subtle,
			Thickness = hovered and Theme.Stroke.strong or Theme.Stroke.hair,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),

		-- Emoji / icon (large; fills its box, TextScaled only for the glyph)
		Icon = e("TextLabel", {
			Size             = UDim2.fromScale(0.8, 0.5),
			AnchorPoint      = Vector2.new(0.5, 0),
			Position         = UDim2.fromScale(0.5, 0.1),
			BackgroundTransparency = 1,
			Text             = emote.icon,
			TextColor3       = R.accent.secondary,  -- §AGX/UI-P2: never default black on dark bg
			TextScaled       = true,
			FontFace         = Theme.FontFaces.bold,
			ZIndex           = 4,
		}),

		-- Label
		Label = e("TextLabel", {
			Size             = UDim2.new(0.9, 0, 0, ty.size + 2),
			AnchorPoint      = Vector2.new(0.5, 1),
			Position         = UDim2.new(0.5, 0, 1, -6),
			BackgroundTransparency = 1,
			Text             = emote.label,
			TextColor3       = R.text.primary,
			FontFace         = ty.font,
			TextSize         = ty.size,
			TextTruncate     = Enum.TextTruncate.AtEnd,
			ZIndex           = 4,
		}, {
			-- §AGX/UI-P2 readable floor = Theme.Type caption
			Tsc = e("UITextSizeConstraint", { MinTextSize = ty.min, MaxTextSize = ty.max }),
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- WHEEL ROOT
-- ═══════════════════════════════════════════════════════════
local function EmoteWheel()
	local visible, setVisible = useState(false)
	local ff = useFormFactor()   -- §AGX/UI-P6: type scale (unconditional hook)
	-- §AGX/UI-P2: M3 — track the viewport so the wheel stays square in px.
	local viewport, setViewport = useState(function()
		local cam = workspace.CurrentCamera
		return cam and cam.ViewportSize or Vector2.new(1280, 720)
	end)

	-- §AGX/UI-P2: M3 — register for the module-level open()/close()/toggle().
	useEffect(function()
		visibilitySetters[setVisible] = true
		return function()
			visibilitySetters[setVisible] = nil
		end
	end, {})

	-- §AGX/UI-P2: M3 — follow viewport size (rotation / window resize).
	useEffect(function()
		local camConn, vpConn
		local function hook()
			if vpConn then vpConn:Disconnect(); vpConn = nil end
			local cam = workspace.CurrentCamera
			if not cam then return end
			setViewport(cam.ViewportSize)
			vpConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				setViewport(cam.ViewportSize)
			end)
		end
		hook()
		camConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
		return function()
			if vpConn then vpConn:Disconnect() end
			camConn:Disconnect()
		end
	end, {})

	-- Toggle via InputSystem (bound to EmoteWheel action)
	useEffect(function()
		if not InputSystem then return end
		local id = InputSystem.BindAction("EmoteWheel", function(_name, state)
			if state ~= "Began" then return end
			setVisible(function(v) return not v end)
		end)
		return function()
			InputSystem.UnbindAction("EmoteWheel", id)
		end
	end, {})

	-- Auto-close when player moves
	useEffect(function()
		if not visible then return end

		local conn = RunService.RenderStepped:Connect(function()
			-- §AGX/UI-P2: M3 — thumbstick / gamepad / click-to-move all show up
			-- in Humanoid.MoveDirection; W/A/S/D too.
			local character = LocalPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.MoveDirection.Magnitude > MOVE_CLOSE_EPS then
				setVisible(false)
				return
			end
			local move = UserInputService:GetKeysPressed()
			for _, key in ipairs(move) do
				if key.KeyCode == Enum.KeyCode.W
					or key.KeyCode == Enum.KeyCode.A
					or key.KeyCode == Enum.KeyCode.S
					or key.KeyCode == Enum.KeyCode.D then
					setVisible(false)
					return
				end
			end
		end)
		return function() conn:Disconnect() end
	end, { visible })

	local function onEmoteSelected(emote)
		setVisible(false)
		task.defer(function()
			playEmote(emote)
		end)
	end

	-- §AGX/UI-FIX: R6 — on a pad, select the first emote while open
	-- (steal = false: an existing selection is left alone). Unconditional.
	local rootRef = useRef(nil)
	GamepadFocus.useAutoSelect(rootRef, visible, {
		steal  = false,
		prefer = EMOTES[1] and { "Emote_" .. tostring(EMOTES[1].id) } or nil,
	})

	if not visible then
		return nil
	end

	local wheelPx, btnPx, radius = wheelMetrics(viewport)
	local centerPx = math.max(40, math.floor(wheelPx * 0.18))

	local isTouch  = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local keyLabel = InputSystem and InputSystem.GetBindingDisplayName("EmoteWheel") or "Q"
	local hintTy   = scaledType("caption", ff)

	-- Cardinal directions: top=270°, right=0°, bottom=90°, left=180°
	local angles   = { 270, 0, 90, 180 }
	local children = {
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),

		-- §AGX/UI-P6: IconButton: ✕ on touch, the bound key elsewhere; tapping
		-- it closes the wheel like an outside tap.
		CenterLabel = e(IconButton, {
			name        = "Center",
			icon        = isTouch and "close" or nil,
			label       = keyLabel,
			variant     = "secondary",
			size        = math.max(Theme.Metrics.iconButton.sm, centerPx),
			anchorPoint = Vector2.new(0.5, 0.5),
			position    = UDim2.fromScale(0.5, 0.5),
			zIndex      = 3,
			onActivated = function() setVisible(false) end,
		}),
	}

	for i, emote in ipairs(EMOTES) do
		local angle = angles[i]
		if angle == nil then break end  -- §AGX/UI-P2: only 4 cardinal slots
		local rad = math.rad(angle)
		local pos = UDim2.new(0.5, math.floor(radius * math.cos(rad) + 0.5), 0.5, math.floor(radius * math.sin(rad) + 0.5))
		children["Emote_" .. emote.id] = e(EmoteButton, {
			emote    = emote,
			position = pos,
			size     = btnPx,
			onSelect = onEmoteSelected,
		})
	end

	local hintText = isTouch
		and "Tap an emote  \u{2022}  tap outside or move to close"
		or ("[" .. keyLabel .. "] Close  \u{2022}  Click to emote")

	return e("Frame", {
		Name                   = "EmoteWheel",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = Theme.Z.windowOver,   -- §AGX/UI-P6
		ref                    = rootRef,   -- §AGX/UI-FIX: R6
	}, {
		-- §AGX/UI-P2: M3 — the dim overlay is a button: tap/click outside the
		-- wheel closes it.
		Overlay = e("TextButton", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = R.surface.scrim,
			BackgroundTransparency = 0.75,
			BorderSizePixel        = 0,
			AutoButtonColor        = false,
			Text                   = "",
			Selectable             = false,   -- §AGX/UI-FIX: R6 — never a pad target
			ZIndex                 = 1,
			[React.Event.Activated] = function() setVisible(false) end,
		}),

		-- §AGX/UI-P2: M3 — square, pixel-sized; Active so taps on the wheel's
		-- empty area don't fall through to the overlay and close it.
		Wheel = e("Frame", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			Size                   = UDim2.fromOffset(wheelPx, wheelPx),
			BackgroundColor3       = R.surface.panel,
			BackgroundTransparency = 0.4,
			BorderSizePixel        = 0,
			Active                 = true,
			ZIndex                 = 2,
		}, children),

		Hint = e("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0),
			Position               = UDim2.new(0.5, 0, 0.5, math.floor(wheelPx / 2) + 6),
			Size                   = UDim2.fromOffset(math.max(wheelPx, 280), hintTy.size + 6),
			BackgroundTransparency = 1,
			Text                   = hintText,
			TextColor3             = R.text.secondary,
			FontFace               = hintTy.font,
			TextSize               = hintTy.size,
			TextWrapped            = true,
			ZIndex                 = 2,
		}, {
			Tsc = e("UITextSizeConstraint", { MinTextSize = hintTy.min, MaxTextSize = hintTy.max }),  -- §AGX/UI-P2
		}),
	})
end

-- §AGX/UI-P2: M3 — public API. Exported as a React.memo element type (a
-- plain table React accepts wherever a component is expected, so
-- `React.createElement(EmoteWheel)` works) carrying imperative
-- open/close/toggle for touch buttons.
local EmoteWheelExport = React.memo(EmoteWheel)
EmoteWheelExport.open   = function() setAllVisible(true) end
EmoteWheelExport.close  = function() setAllVisible(false) end
EmoteWheelExport.toggle = function() setAllVisible(function(v) return not v end) end
EmoteWheelExport.Component = EmoteWheel
EmoteWheelExport.wheelMetrics = wheelMetrics   -- §AGX/UI-P3: MenuRadial geometry (B6)

return EmoteWheelExport
