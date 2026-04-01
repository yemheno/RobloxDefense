-- shared/StarterPlayerScripts/UI/EmoteWheel.lua
--[[
    Circular emote selection menu.

    • Press Q to open / close the wheel.
    • 4 emote buttons arranged radially (top, right, bottom, left).
    • Clicking an emote plays the animation and closes the wheel.
    • Uses Roblox default animation IDs — swap these for custom ones later.
    • Auto-closes if player starts moving.
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

local WHEEL_RADIUS  = 80  -- px from center

-- ── Palette ───────────────────────────────────────────────
local C = {
	wheel_bg   = Color3.fromRGB(18,  18,  26),
	btn_bg     = Color3.fromRGB(38,  38,  54),
	btn_hover  = Color3.fromRGB(60,  60,  90),
	btn_border = Color3.fromRGB(90,  90, 130),
	label      = Color3.fromRGB(220, 220, 235),
	label_sub  = Color3.fromRGB(140, 140, 160),
	accent     = Color3.fromRGB(105, 190, 255),
	overlay    = Color3.fromRGB( 0,   0,   0),
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
		Size              = UDim2.fromScale(0.038, 0.067),
		AnchorPoint       = Vector2.new(0.5, 0.5),
		Position          = props.position,
		BackgroundColor3  = hovered and C.btn_hover or C.btn_bg,
		BorderSizePixel   = 0,
		AutoButtonColor   = false,
		[React.Event.Activated]       = function() onSelect(emote) end,
		[React.Event.MouseEnter]      = function() setHovered(true) end,
		[React.Event.MouseLeave]      = function() setHovered(false) end,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),

		Stroke = e("UIStroke", {
			Color     = hovered and C.accent or C.btn_border,
			Thickness = hovered and 2 or 1,
		}),

		-- Emoji / icon (large)
		Icon = e("TextLabel", {
			Size             = UDim2.fromScale(1, 0.55),
			AnchorPoint      = Vector2.new(0.5, 0),
			Position         = UDim2.fromScale(0.5, 0.05),
			BackgroundTransparency = 1,
			Text             = emote.icon,
			TextScaled       = true,
			Font             = Enum.Font.GothamBold,
		}),

		-- Label
		Label = e("TextLabel", {
			Size             = UDim2.fromScale(1, 0.35),
			AnchorPoint      = Vector2.new(0.5, 1),
			Position         = UDim2.fromScale(0.5, 0.97),
			BackgroundTransparency = 1,
			Text             = emote.label,
			TextColor3       = C.label,
			TextScaled       = true,
			Font             = Enum.Font.Gotham,
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- WHEEL ROOT
-- ═══════════════════════════════════════════════════════════
local function EmoteWheel()
	local visible, setVisible = useState(false)

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

	-- Cardinal directions: top=270°, right=0°, bottom=90°, left=180°
	local angles   = { 270, 0, 90, 180 }
	local children = {
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),

		CenterLabel = e("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			Size                   = UDim2.fromScale(0.028, 0.050),
			BackgroundColor3       = C.btn_bg,
			BackgroundTransparency = 0.2,
			BorderSizePixel        = 0,
			Text                   = InputSystem and InputSystem.GetBindingDisplayName("EmoteWheel") or "Q",
			TextColor3             = C.label_sub,
			TextScaled             = true,
			Font                   = Enum.Font.GothamBold,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}),
	}

	for i, emote in ipairs(EMOTES) do
		local rad = math.rad(angles[i])
		local pos = UDim2.new(0.5, WHEEL_RADIUS * math.cos(rad), 0.5, WHEEL_RADIUS * math.sin(rad))
		children["Emote_" .. emote.id] = e(EmoteButton, {
			emote    = emote,
			position = pos,
			onSelect = onEmoteSelected,
		})
	end

	return e("Frame", {
		Name                   = "EmoteWheel",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = 30,
	}, {
		Overlay = e("Frame", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = C.overlay,
			BackgroundTransparency = 0.75,
			BorderSizePixel        = 0,
		}),

		Wheel = e("Frame", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			Size                   = UDim2.fromScale(0.121, 0.215),  -- 232x232 pixels
			BackgroundColor3       = C.wheel_bg,
			BackgroundTransparency = 0.4,
			BorderSizePixel        = 0,
		}, children),

		Hint = e("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0),
			Position               = UDim2.new(0.5, 0, 0.5, WHEEL_RADIUS + 46),
			Size                   = UDim2.fromScale(0.135, 0.024),
			BackgroundTransparency = 1,
			Text                   = "[" .. (InputSystem and InputSystem.GetBindingDisplayName("EmoteWheel") or "Q") .. "] Close  \u{2022}  Click to emote",
			TextColor3             = C.label_sub,
			TextScaled             = true,
			Font                   = Enum.Font.Gotham,
		}),
	})
end

return EmoteWheel
