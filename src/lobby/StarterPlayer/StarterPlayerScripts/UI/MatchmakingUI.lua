-- UI/MatchmakingUI.lua
--[[
    Matchmaking status indicator.
    
    Listens for "MatchmakingUpdate" from server and shows:
      • "Queued…"           — waiting for match
      • "Starting in N…"    — countdown in progress
      • "Launching…"        — about to transition
      • "Cancelled"         — match cancelled
      • "Error: …"          — something went wrong
    
    Cancel button fires "MatchmakingRequest" → { action = "Cancel" }.
    
    Shown as a small bar near the top of the screen. Self-hides
    when not matchmaking.

    §AGX/UI-P4: the status text is a sticky Notify banner ("matchmaking"
    priority, key "matchmaking"); this component keeps the state machine
    and renders only the Cancel / Retry / Close controls, directly under
    Notify's banner slot.

    §AGX/UI-P6: controls are Common/Button (Retry = the primary CTA) in
    design px; Theme roles for the banner colours. Notify integration and
    the state machine are unchanged.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local SharedModules  = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
local Notify         = require(Players.LocalPlayer:WaitForChild("PlayerScripts")
	:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("Notify"))  -- §AGX/UI-P4

-- §AGX/UI-P6: Theme roles + Button (the private palette is gone).
local Common      = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI"):WaitForChild("Common")
local Theme       = require(Common:WaitForChild("Theme"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local Button      = require(Common:WaitForChild("Button"))
-- §AGX/UI-FIX: R6 — gamepad first focus on Retry / Cancel / Close.
local GamepadFocus = require(Common:WaitForChild("GamepadFocus"))
local ReactRoblox  = require(ReplicatedStorage.Packages.ReactRoblox)   -- §AGX/UI-FIX: 8

-- §AGX/UI-FIX: 8 — own ScreenGui ABOVE PanelGui (20) and below NotifyGui (30):
-- inside AppGui (0) the controls drew under any open panel.
local DISPLAY_ORDER = 25

local e = React.createElement
local R = Theme.Roles

-- §AGX/X14: if the server never teleports us (TeleportInitFailed without
-- a follow-up, lost Error packet, …) "Launching" used to stick forever.
local LAUNCH_TIMEOUT = 20

-- Banner colour per status (Notify.banner opts.color).
local STATUS_COLORS = {
	Queued     = R.accent.secondary,
	Countdown  = R.state.warning,
	Launching  = R.state.success,
	Cancelled  = R.state.danger,
	Error      = R.state.danger,
}

local BTN_W = 112   -- design px

-- ── Main Component ────────────────────────────────────────
local function MatchmakingUI()
	local mmState, setMmState = React.useState(nil)
	-- mmState = { status, seconds, message, mode }

	React.useEffect(function()
		local mounted = true
		local conn = NetworkManager.OnServerEvent("MatchmakingUpdate", function(data)
			-- data = { status, seconds?, message?, mode? }
			if data.status == "Launched" or data.status == "Cancelled" then
				-- Show briefly, then hide
				setMmState(data)
				task.delay(2, function()
					if mounted then setMmState(nil) end
				end)
			else
				setMmState(data)
			end
		end)
		return function()
			mounted = false
			if conn then conn:Disconnect() end
		end
	end, {})

	-- §AGX/X14: client-side Launching timeout. Re-armed on every new
	-- server update (each is a fresh table); cleared when state changes.
	React.useEffect(function()
		if not mmState or mmState.status ~= "Launching" then return end
		local alive = true
		local launched = mmState
		task.delay(LAUNCH_TIMEOUT, function()
			if not alive then return end
			setMmState({
				status     = "Error",
				message    = "Teleport timed out.",
				mode       = launched.mode,
				difficulty = launched.difficulty,
			})
		end)
		return function() alive = false end
	end, { mmState })

	-- §AGX/UI-P4: controls go under Notify's banner slot (same maths).
	local L = Notify.useLayout()
	-- §AGX/UI-P6: L is SCREEN px (NotifyGui); this tree may be scaled.
	local scale = UIScaleRoot.useUIScale()

	local status  = mmState and mmState.status or "Queued"
	local color   = STATUS_COLORS[status] or R.text.primary
	local message = ""

	if not mmState then
		message = ""
	elseif status == "Queued" then
		message = "Queued for " .. tostring(mmState.mode or "match") .. "…"
	elseif status == "Countdown" then
		message = tostring(mmState.mode or "Match") .. " starts in " .. tostring(mmState.seconds or mmState.countdown or "?")  --[[ §AGX/X14: server sends `countdown` ]] .. "…"
	elseif status == "Launching" then
		message = "Launching " .. tostring(mmState.mode or "match") .. "!"
	elseif status == "Cancelled" then
		-- §AGX/X15: show the server's reason (e.g. "Party changed — queue cancelled.")
		message = mmState.message or "Matchmaking cancelled."
	elseif status == "Error" then
		message = mmState.message or "An error occurred."
	end

	-- §AGX/UI-P4: the status line is a Notify banner. Sticky while this
	-- state lasts (Launched/Cancelled still hide after 2 s, the Launching
	-- timeout still turns into an Error); an empty message (e.g. the
	-- "Launched" status, which used to show an empty bar) clears it.
	React.useEffect(function()
		if message ~= "" then
			Notify.banner(message, {
				key = "matchmaking", priority = "matchmaking", sticky = true, color = color,
			})
		else
			Notify.clearBanner("matchmaking")
		end
	end, { message, color })
	React.useEffect(function()
		return function() Notify.clearBanner("matchmaking") end
	end, {})

	local showCancel = mmState ~= nil and (status == "Queued" or status == "Countdown")
	-- §AGX/X14: errors that carry a mode came from a failed/timed-out
	-- launch → offer Retry (re-queue same mode + tier). Every error gets a
	-- Close button; before this an Error banner could never be dismissed.
	local isError  = mmState ~= nil and (status == "Error")
	local showRetry = isError and mmState.mode ~= nil

	-- §AGX/UI-FIX: R6 — on a pad, focus Retry (else Close) while an Error
	-- row is shown. Not while Queued / Countdown: a GUI selection takes the
	-- left stick from the character, and the queue can last minutes of
	-- walking around the lobby (Cancel stays reachable by the pad's
	-- selection toggle). steal = false: an open panel's selection is left
	-- alone. Hook is unconditional (before any return).
	local rootRef = React.useRef(nil)
	local focusKey = isError and ((mmState and mmState.message) or status) or nil
	GamepadFocus.useAutoSelect(rootRef, focusKey, {
		steal  = false,
		prefer = { "RetryBtn", "CloseBtn" },
	})

	if not mmState then
		return nil
	end
	if not (showCancel or isError) then
		return nil  -- §AGX/UI-P4: nothing to press; the banner says it all
	end

	-- §AGX/UI-P4: one row of controls centred under the banner slot.
	-- §AGX/UI-P6: the row is placed from Notify's SCREEN px (converted to
	-- this tree's units); the Buttons inside are design px (44 tall) under
	-- UIScaleRoot.Local, so the row is 44 x uiScale tall like Notify's taps.
	-- §AGX/UI-FIX: 8 — portalled into an unscaled ScreenGui: this tree's
	-- units are screen px there (applied 1), and Local adds the full target.
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local applied = playerGui and 1 or scale.applied
	local rowH = Theme.Metrics.button.sm * (playerGui and scale.target or scale.remaining)
	local function controlBtn(order, text, variant, onActivated)
		return e(Button, {
			name        = text .. "Btn",
			variant     = variant,
			size        = "sm",
			width       = BTN_W,
			label       = text,
			layoutOrder = order,
			onActivated = onActivated,
		})
	end

	local row = e("Frame", {
		Name                   = "MatchmakingUI",
		AnchorPoint            = Vector2.new(0.5, 0),
		Position               = UDim2.new(0.5, 0, 0, UIScaleRoot.toLocal(L.bannerY + L.bannerH + 8, applied)),
		Size                   = UDim2.fromOffset(UIScaleRoot.toLocal(L.bannerW, applied), rowH),
		BackgroundTransparency = 1,
		ZIndex                 = 25,
		ref                    = rootRef,   -- §AGX/UI-FIX: R6
	}, {
		scaled = e(UIScaleRoot.Local, { name = "Controls", zIndex = 25 }, {
			layout = e("UIListLayout", {
				FillDirection       = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment   = Enum.VerticalAlignment.Center,
				SortOrder           = Enum.SortOrder.LayoutOrder,
				Padding             = UDim.new(0, Theme.Space.sm),
			}),

			-- Cancel button
			cancelBtn = showCancel and controlBtn(1, "Cancel", "secondary", function()
				NetworkManager.FireServer("MatchmakingRequest", { action = "Cancel" })
			end) or nil,

			-- §AGX/X14: Retry after a failed / timed-out launch. The server
			-- re-validates everything (leader, level, IsQueued/launching).
			retryBtn = showRetry and controlBtn(2, "Retry", "primary", function()
				NetworkManager.FireServer("MatchmakingRequest", {
					action     = "Queue",
					mode       = mmState.mode,
					difficulty = mmState.difficulty,
				})
			end) or nil,

			-- §AGX/X14: Close dismisses the error banner (and clears any stale
			-- queue entry server-side; Cancel is a no-op if there is none).
			closeBtn = isError and controlBtn(3, "Close", "secondary", function()
				NetworkManager.FireServer("MatchmakingRequest", { action = "Cancel" })
				setMmState(nil)
			end) or nil,
		}),
	})

	-- §AGX/UI-FIX: 8 — portal into an unscaled DeviceSafeInsets ScreenGui
	-- (same geometry as NotifyGui, whose screen-px layout L places the row).
	-- The UIScale context is reset to 1 because no ancestor UIScale applies
	-- inside the new ScreenGui; UIScaleRoot.Local then adds the full scale.
	if not playerGui then return row end
	return ReactRoblox.createPortal(e("ScreenGui", {
		Name           = "MatchmakingGui",
		ResetOnSpawn   = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder   = DISPLAY_ORDER,
		ScreenInsets   = Enum.ScreenInsets.DeviceSafeInsets,
	}, {
		scaleCtx = e(UIScaleRoot.Context.Provider, { value = 1 }, row),
	}), playerGui)
end

return MatchmakingUI
