-- shared/StarterPlayerScripts/UI/EmoteWheel.lua
--[[
    Circular emote selection menu.

    • Press Q to open / close the wheel.
    • 4 emote buttons arranged radially (top, right, bottom, left).
    • Clicking an emote plays the animation and closes the wheel.
    • Uses Roblox default animation IDs — swap these for custom ones later.
    • Auto-closes if player starts moving.
    • §AGX/UI-P2: touch — EmoteWheel.open()/close()/toggle() for on-screen
      buttons (SocialPlaza AppearanceBar Emote button); closes on outside
      tap and on thumbstick movement (Humanoid.MoveDirection).
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

-- §AGX/UI-P2: M3 — wheel is sized in pixels from the viewport's short side
-- (was fromScale(0.121,0.215) = 102x84 px on iPhone, not square, and the
-- buttons were scale-of-wheel = ~4 px). See wheelMetrics() below.
local WHEEL_SHORT_FRAC = 0.62   -- wheel diameter as a share of the short side
local WHEEL_MIN, WHEEL_MAX = 220, 320
local BTN_MIN          = 56     -- >= 48 px touch target
local MOVE_CLOSE_EPS   = 0.1    -- Humanoid.MoveDirection magnitude that closes it

-- §AGX/UI-P3: exported (EmoteWheel.wheelMetrics) for MenuRadial, B6.
-- `opts` overrides the wheel's own numbers: { shortFrac, min, max, btnMin }
-- (screen px, like the defaults). No opts = the emote wheel, unchanged.
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

-- §AGX/UI-P2: M3 — imperative open/close so touch UI (SocialPlaza
-- AppearanceBar Emote button, a later HUD button) can open the wheel.
-- Every mounted wheel registers its setter here.
local visibilitySetters = {}

local function setAllVisible(fnOrValue)
	for setter in pairs(visibilitySetters) do
		setter(fnOrValue)
	end
end

-- ── Palette ───────────────────────────────────────────────
-- §AGX/UI-P2: minimal restyle onto shared Theme tokens.
local Theme = require(script.Parent:WaitForChild("Common"):WaitForChild("Theme"))
local T = Theme.Colors
local C = {
	wheel_bg   = T.panel,
	btn_bg     = T.panelAlt,
	btn_hover  = T.track,
	btn_border = T.locked,
	label      = T.text,
	label_sub  = T.textDim,
	accent     = T.accent2,
	overlay    = T.dim,
}

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

	return e("TextButton", {
		-- §AGX/UI-P2: M3 — pixel size (>= 56 px) instead of a scale of the wheel.
		Size              = UDim2.fromOffset(props.size, props.size),
		AnchorPoint       = Vector2.new(0.5, 0.5),
		Position          = props.position,
		BackgroundColor3  = hovered and C.btn_hover or C.btn_bg,
		BorderSizePixel   = 0,
		AutoButtonColor   = false,
		Text              = "",
		ZIndex            = 3,
		[React.Event.Activated]       = function() onSelect(emote) end,
		[React.Event.MouseEnter]      = function() setHovered(true) end,
		[React.Event.MouseLeave]      = function() setHovered(false) end,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),

		Stroke = e("UIStroke", {
			Color     = hovered and C.accent or C.btn_border,
			Thickness = hovered and 2 or 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),

		-- Emoji / icon (large)
		Icon = e("TextLabel", {
			Size             = UDim2.fromScale(0.8, 0.5),
			AnchorPoint      = Vector2.new(0.5, 0),
			Position         = UDim2.fromScale(0.5, 0.1),
			BackgroundTransparency = 1,
			Text             = emote.icon,
			TextColor3       = C.accent,  -- §AGX/UI-P2: was default black on dark bg
			TextScaled       = true,
			Font             = Enum.Font.GothamBold,
			ZIndex           = 4,
		}),

		-- Label
		Label = e("TextLabel", {
			Size             = UDim2.new(0.9, 0, 0, 14),
			AnchorPoint      = Vector2.new(0.5, 1),
			Position         = UDim2.new(0.5, 0, 1, -6),
			BackgroundTransparency = 1,
			Text             = emote.label,
			TextColor3       = C.label,
			TextScaled       = true,
			Font             = Enum.Font.Gotham,
			ZIndex           = 4,
		}, {
			-- §AGX/UI-P2: readable floor
			Tsc = e("UITextSizeConstraint", { MinTextSize = 10, MaxTextSize = 14 }),
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- WHEEL ROOT
-- ═══════════════════════════════════════════════════════════
local function EmoteWheel()
	local visible, setVisible = useState(false)
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
			-- in Humanoid.MoveDirection; W/A/S/D kept as before.
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

	if not visible then
		return nil
	end

	local wheelPx, btnPx, radius = wheelMetrics(viewport)
	local centerPx = math.max(40, math.floor(wheelPx * 0.18))

	-- Cardinal directions: top=270°, right=0°, bottom=90°, left=180°
	local angles   = { 270, 0, 90, 180 }
	local children = {
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),

		CenterLabel = e("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			-- §AGX/UI-P2: M3 — pixel size (was a scale of the wheel).
			Size                   = UDim2.fromOffset(centerPx, centerPx),
			BackgroundColor3       = C.btn_bg,
			BackgroundTransparency = 0.2,
			BorderSizePixel        = 0,
			Text                   = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
				and "\u{2715}"
				or (InputSystem and InputSystem.GetBindingDisplayName("EmoteWheel") or "Q"),
			TextColor3             = C.label_sub,
			TextScaled             = true,
			Font                   = Enum.Font.GothamBold,
			ZIndex                 = 3,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Pad    = e("UIPadding", {
				PaddingTop = UDim.new(0.22, 0), PaddingBottom = UDim.new(0.22, 0),
				PaddingLeft = UDim.new(0.22, 0), PaddingRight = UDim.new(0.22, 0),
			}),
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

	local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local hintText = isTouch
		and "Tap an emote  \u{2022}  tap outside or move to close"
		or ("[" .. (InputSystem and InputSystem.GetBindingDisplayName("EmoteWheel") or "Q") .. "] Close  \u{2022}  Click to emote")

	return e("Frame", {
		Name                   = "EmoteWheel",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = 30,
	}, {
		-- §AGX/UI-P2: M3 — the dim overlay is now a button: tap/click outside
		-- the wheel closes it.
		Overlay = e("TextButton", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = C.overlay,
			BackgroundTransparency = 0.75,
			BorderSizePixel        = 0,
			AutoButtonColor        = false,
			Text                   = "",
			ZIndex                 = 1,
			[React.Event.Activated] = function() setVisible(false) end,
		}),

		-- §AGX/UI-P2: M3 — square, pixel-sized; Active so taps on the wheel's
		-- empty area don't fall through to the overlay and close it.
		Wheel = e("Frame", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			Size                   = UDim2.fromOffset(wheelPx, wheelPx),
			BackgroundColor3       = C.wheel_bg,
			BackgroundTransparency = 0.4,
			BorderSizePixel        = 0,
			Active                 = true,
			ZIndex                 = 2,
		}, children),

		Hint = e("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0),
			Position               = UDim2.new(0.5, 0, 0.5, math.floor(wheelPx / 2) + 6),
			Size                   = UDim2.fromOffset(math.max(wheelPx, 280), 18),
			BackgroundTransparency = 1,
			Text                   = hintText,
			TextColor3             = C.label_sub,
			TextScaled             = true,
			Font                   = Enum.Font.Gotham,
			ZIndex                 = 2,
		}, {
			Tsc = e("UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = 16 }),  -- §AGX/UI-P2
		}),
	})
end

-- §AGX/UI-P2: M3 — public API. Exported as a React.memo element type (a
-- plain table React accepts wherever a component is expected, so
-- `React.createElement(EmoteWheel)` in LobbyApp/SocialPlazaApp is
-- unchanged) carrying imperative open/close/toggle for touch buttons.
local EmoteWheelExport = React.memo(EmoteWheel)
EmoteWheelExport.open   = function() setAllVisible(true) end
EmoteWheelExport.close  = function() setAllVisible(false) end
EmoteWheelExport.toggle = function() setAllVisible(function(v) return not v end) end
EmoteWheelExport.Component = EmoteWheel
EmoteWheelExport.wheelMetrics = wheelMetrics   -- §AGX/UI-P3: MenuRadial geometry (B6)

return EmoteWheelExport
