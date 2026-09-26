-- UI/HUD/RunControlsRegion.lua
--[[
    §AGX/UI-P5: Start / Countdown / Next Wave / Return (moved from
    HUD.lua:880-918, 998-1044), now Theme v2 Buttons in the top-centre slot
    below the boss reserve (Layout L.run). Return sits one row lower in the
    post-run Idle, under Start (§AGX/X14).

    Publishes UI_TopCentreButtonsBottomPx (screen px, nil when no button is
    visible) so Notify's banner sits below the column.
    props: layout (L), run (RunState state), visible
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local React = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local NetworkManager = require(PlayerScripts:WaitForChild("Modules"):WaitForChild("NetworkManager"))
local Common = script.Parent.Parent:WaitForChild("Common")
local Theme  = require(Common:WaitForChild("Theme"))
local Button = require(Common:WaitForChild("Button"))
local Text   = require(Common:WaitForChild("Text"))
local Layout = require(script.Parent:WaitForChild("Layout"))
local GamepadFocus = require(Common:WaitForChild("GamepadFocus"))   -- §AGX/UI-P7

local e = React.createElement
local R = Theme.Roles

--- Which buttons show, and the column bottom (design px), for a run state.
local function resolve(L, run, visible)
	local gs = run.gameState
	local show = {
		start     = visible and gs == "Idle",
		countdown = visible and run.countdown ~= nil,
		nextWave  = visible and gs == "Defending" and run.betweenWaves == true,
		returnBtn = visible and (gs == "Defeat" or gs == "Victory" or (gs == "Idle" and run.runEnded == true)),
	}
	local top = L.run.y
	local returnY = (gs == "Idle") and L.runReturnIdleY or top
	local bottom = nil
	if show.start or show.countdown or show.nextWave then bottom = top + L.run.h end
	if show.returnBtn then bottom = math.max(bottom or 0, returnY + L.run.h) end
	return show, returnY, bottom
end

local function RunControlsRegion(props)
	local L, run = props.layout, props.run
	local show, returnY, bottom = resolve(L, run, props.visible)

	local px = bottom and math.floor(bottom * L.scale + 0.5) or nil
	React.useEffect(function()
		ReplicatedStorage:SetAttribute(Layout.ATTR.topCentreButtons, px)
	end, { px or -1 })
	React.useEffect(function()
		return function()
			ReplicatedStorage:SetAttribute(Layout.ATTR.topCentreButtons, nil)
		end
	end, {})

	-- §AGX/UI-P7: gamepad only: select Start / Next Wave / Return when it
	-- appears (a new key per button). Never steals from an open panel; B
	-- (engine) drops the selection and the stick drives the character again.
	local rootRef = React.useRef(nil)
	-- §AGX/UI-P7: Next Wave is NOT auto-focused — between waves the player
	-- is still fighting/moving, and a selected button steals the left stick.
	local focusKey = (show.start and "start")
		or (show.returnBtn and "return") or nil
	GamepadFocus.useAutoSelect(rootRef, focusKey,
		{ prefer = { "StartGame", "NextWave", "ReturnToLobby" }, steal = false })

	local r = L.run
	local function btn(name, label, variant, y, onActivated)
		return e(Button, {
			name        = name,
			variant     = variant,
			size        = L.runSize,
			label       = label,
			width       = r.w,
			anchorPoint = Vector2.new(0.5, 0),
			position    = UDim2.new(0.5, r.position.X.Offset, 0, y),
			zIndex      = 3,
			onActivated = onActivated,
		})
	end

	return e("Frame", {
		Name                   = "RunControls",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = 3,
		ref                    = rootRef,   -- §AGX/UI-P7
	}, {
		start = show.start and btn("StartGame", "▶ Start Game", "primary", r.y, function()
			NetworkManager.FireServer("RequestStartGame")
		end) or nil,

		countdown = show.countdown and e("Frame", {
			Name                   = "Countdown",
			AnchorPoint            = Vector2.new(0.5, 0),
			Position               = UDim2.new(0.5, 0, 0, r.y),
			Size                   = UDim2.fromOffset(r.w, r.h),
			BackgroundColor3       = R.state.warning,
			BorderSizePixel        = 0,
			ZIndex                 = 3,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
			label = e(Text, {
				style  = "label",
				text   = "Starting in " .. tostring(run.countdown) .. "...",
				color  = "text.onAccent",
				align  = "center",
				size   = UDim2.fromScale(1, 1),
				zIndex = 4,
			}),
		}) or nil,

		nextWave = show.nextWave and btn("NextWave", "Next Wave >>", "primary", r.y, function()
			NetworkManager.FireServer("RequestNextWave")
		end) or nil,

		returnBtn = show.returnBtn and btn("ReturnToLobby", "Return to Lobby", "danger", returnY, function()
			NetworkManager.FireServer("RequestReturnToLobby")
		end) or nil,
	})
end

return RunControlsRegion
