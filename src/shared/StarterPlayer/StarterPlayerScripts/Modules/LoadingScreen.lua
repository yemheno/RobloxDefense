-- StarterPlayerScripts/Modules/LoadingScreen
--[[
    LoadingScreen  (§T10/U1)
    ========================
    The screen ReadyGate was built for. Covers the viewport from client
    boot until the server's ServerReady arrives (which ReadyGate
    guarantees is AFTER this client's ClientReady handshake — every
    boot-critical payload has already been drained by then).

    Flow:
      1. Place client Load()s this FIRST → overlay appears immediately.
      2. Place UI mount script fires ClientReady (existing §RG1 path).
      3. Server drains the ReadyGate queue, ServerReady arrives.
      4. Place client's ServerReady handler calls LoadingScreen.Dismiss().

    Failsafe (§NM-D6 spirit): if ServerReady never arrives
    (broken handshake, server hang), the screen self-dismisses after
    FAILSAFE_SECONDS with a loud client warn — a stuck loading screen
    is worse than a rough entrance.

    All geometry is Scale-based (mobile-safe), matching the
    generate_ui.lua conventions. Colors follow the HUD palette
    (35,35,50 tracks / 140,140,160 labels).

    Public API:
      LoadingScreen.Init()             – builds + shows the overlay
      LoadingScreen.SetStatus(text)    – swap the status line
      LoadingScreen.Dismiss()          – fade out + destroy (idempotent)
      LoadingScreen.IsShown() → bool
]]

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")

local LoadingScreen = {}

local FAILSAFE_SECONDS = 25
local FADE_SECONDS     = 0.6

local gui        = nil
local statusText = nil
local dismissed  = false
local dotsThread = nil

local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then inst.Parent = parent end
	return inst
end

function LoadingScreen.Init()
	if gui then return end
	dismissed = false

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	gui = mk("ScreenGui", {
		Name           = "LoadingScreen",
		DisplayOrder   = 1000,           -- above everything
		IgnoreGuiInset = true,
		ResetOnSpawn   = false,
	}, playerGui)

	local backdrop = mk("Frame", {
		Name                   = "Backdrop",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundColor3       = Color3.fromRGB(18, 18, 28),
		BorderSizePixel        = 0,
	}, gui)

	-- Title
	mk("TextLabel", {
		Name                   = "Title",
		Position               = UDim2.fromScale(0.5, 0.40),
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Size                   = UDim2.fromScale(0.6, 0.10),
		BackgroundTransparency = 1,
		Text                   = "ROBLOX DEFENSE",
		TextColor3             = Color3.fromRGB(255, 220, 100),
		Font                   = Enum.Font.GothamBold,
		TextScaled             = true,
	}, backdrop)

	-- Status line (animated dots)
	statusText = mk("TextLabel", {
		Name                   = "Status",
		Position               = UDim2.fromScale(0.5, 0.52),
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Size                   = UDim2.fromScale(0.5, 0.04),
		BackgroundTransparency = 1,
		Text                   = "Loading",
		TextColor3             = Color3.fromRGB(140, 140, 160),
		Font                   = Enum.Font.Gotham,
		TextScaled             = true,
	}, backdrop)

	-- Indeterminate shimmer bar
	local track = mk("Frame", {
		Name             = "Track",
		Position         = UDim2.fromScale(0.5, 0.58),
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Size             = UDim2.fromScale(0.34, 0.012),
		BackgroundColor3 = Color3.fromRGB(35, 35, 50),
		BorderSizePixel  = 0,
	}, backdrop)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, track)

	local shimmer = mk("Frame", {
		Name             = "Shimmer",
		Size             = UDim2.fromScale(0.25, 1),
		Position         = UDim2.fromScale(-0.25, 0),
		BackgroundColor3 = Color3.fromRGB(255, 220, 100),
		BorderSizePixel  = 0,
	}, track)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shimmer)

	-- Shimmer sweep + status dots animation
	dotsThread = task.spawn(function()
		local base = "Loading"
		local sweepTween = nil
		while not dismissed and gui do
			sweepTween = TweenService:Create(shimmer,
				TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Position = UDim2.fromScale(1, 0) })
			sweepTween:Play()
			for i = 0, 3 do
				if dismissed or not statusText then return end
				statusText.Text = base .. string.rep(".", i)
				task.wait(0.3)
			end
			if shimmer.Parent then
				shimmer.Position = UDim2.fromScale(-0.25, 0)
			end
		end
		if sweepTween then sweepTween:Cancel() end
	end)

	-- §T10/U1 failsafe: never trap the player behind a stuck overlay.
	task.delay(FAILSAFE_SECONDS, function()
		if not dismissed then
			warn(string.format(
				"[LoadingScreen] ServerReady never arrived after %d s — force-dismissing (handshake broken?)",
				FAILSAFE_SECONDS))
			LoadingScreen.Dismiss()
		end
	end)
end

function LoadingScreen.SetStatus(text)
	if statusText and not dismissed then
		statusText.Text = tostring(text)
	end
end

function LoadingScreen.IsShown()
	return gui ~= nil and not dismissed
end

function LoadingScreen.Dismiss()
	if dismissed or not gui then return end
	dismissed = true

	local backdrop = gui:FindFirstChild("Backdrop")
	if backdrop then
		-- Fade the whole overlay out, then destroy.
		local tween = TweenService:Create(backdrop,
			TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 })
		for _, child in ipairs(backdrop:GetDescendants()) do
			if child:IsA("TextLabel") then
				TweenService:Create(child, TweenInfo.new(FADE_SECONDS),
					{ TextTransparency = 1 }):Play()
			elseif child:IsA("Frame") then
				TweenService:Create(child, TweenInfo.new(FADE_SECONDS),
					{ BackgroundTransparency = 1 }):Play()
			end
		end
		tween:Play()
		tween.Completed:Once(function()
			if gui then gui:Destroy() end
			gui = nil
			statusText = nil
		end)
	else
		gui:Destroy()
		gui = nil
		statusText = nil
	end
end

return LoadingScreen
