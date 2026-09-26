-- UI/Shell/ConfirmDialog.lua
--[[
    §AGX/UI-P3: small confirm dialog (shell-spec §2.2 `leaveConfirm`, B7).
    A Theme v2 Modal (D8: tap outside = cancel), two actions, right-aligned:
    cancel (secondary) then confirm (danger when destructive).

    Props
        preset       = "leave" | nil   -- built-in texts + behaviour
        place        = "Plaza" | "Combat" | ...   (leave: picks the body text)
        title, body  = string?         -- override the preset
        confirmLabel, cancelLabel = string?
        danger       = true            -- confirm uses the danger variant
        onConfirm    = function()?     -- non-preset confirm; the dialog closes after
        onCancel / onClose = function(reason?)   -- PanelHost wires both to
                                                 -- close("leaveConfirm", "self")

    Preset "leave" (Registry `leave` action -> open("leaveConfirm", { preset
    = "leave", place })): confirm fires NetworkManager "RequestReturnToLobby"
    (ReturnTeleporter, loaded in the Plaza by B9) and keeps the dialog up in a
    "Travelling…" state; the teleport tears the client down. If nothing
    happened after LEAVE_TIMEOUT (Studio skips the teleport; a failure is
    retried server-side once) the buttons come back with a failure line.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local Modules       = PlayerScripts:WaitForChild("Modules")
local Common        = script.Parent.Parent:WaitForChild("Common")
local Theme         = require(Common:WaitForChild("Theme"))
local Modal         = require(Common:WaitForChild("Modal"))
local Text          = require(Common:WaitForChild("Text"))
local Locale        = require(Modules:WaitForChild("Locale"))

local e = React.createElement

local LEAVE_TIMEOUT = 10   -- s; ReturnTeleporter retries once after 2 s

-- PanelStack (Agent A) is optional: used only to veto Back while travelling.
local PanelStack = nil
do
	local mod = script.Parent:FindFirstChild("PanelStack")
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then PanelStack = res end
	end
end

local function fireLeave()
	local mod = Modules:FindFirstChild("NetworkManager")
	if not mod then return false end
	local ok, NetworkManager = pcall(require, mod)
	if not ok or type(NetworkManager) ~= "table" or not NetworkManager.FireServer then return false end
	NetworkManager.FireServer("RequestReturnToLobby")
	return true
end

local PRESETS = {
	leave = function(props)
		return {
			title        = Locale.Get("nav_leave_confirm_title"),
			body         = Locale.Get((props.place == "Combat") and "nav_leave_confirm_body_combat" or "nav_leave_confirm_body"),
			confirmLabel = Locale.Get("nav_leave_confirm_yes"),
			cancelLabel  = Locale.Get("nav_leave_confirm_no"),
			danger       = true,
			waits        = true,      -- stays up until the teleport happens
			confirm      = fireLeave,
		}
	end,
}

local function ConfirmDialog(props)
	local pending, setPending = React.useState(false)
	local failed, setFailed = React.useState(false)

	-- The pending timeout; cleaned up on unmount (the teleport unmounts us).
	React.useEffect(function()
		if not pending then return nil end
		local alive = true
		task.delay(LEAVE_TIMEOUT, function()
			if alive then
				setPending(false)
				setFailed(true)
			end
		end)
		return function() alive = false end
	end, { pending })

	-- While travelling, Back / B / backdrop must not dismiss the dialog
	-- (the request is already on its way). Stable hook: PanelStack is
	-- resolved once at load.
	local pendingRef = React.useRef(false)
	pendingRef.current = pending
	if PanelStack and PanelStack.useCloseHandler then
		PanelStack.useCloseHandler(function()
			if pendingRef.current then return false end
			return nil
		end)
	end

	local preset = PRESETS[props.preset or ((props.title == nil and props.onConfirm == nil) and "leave" or "")]
	local cfg = preset and preset(props) or {}
	local title        = props.title or cfg.title
	local body         = props.body or cfg.body
	local confirmLabel = props.confirmLabel or cfg.confirmLabel or "OK"
	local cancelLabel  = props.cancelLabel or cfg.cancelLabel or Locale.Get("nav_leave_confirm_no")
	local danger       = props.danger
	if danger == nil then danger = cfg.danger ~= false end

	local function cancel()
		if pending then return end
		local fn = props.onCancel or props.onClose
		if fn then fn("x") end
	end

	local function confirm()
		if pending then return end
		setFailed(false)
		if cfg.confirm and props.onConfirm == nil then
			local ok = cfg.confirm()
			if cfg.waits and ok then
				setPending(true)
				return
			end
			if not ok then setFailed(true); return end
		elseif props.onConfirm then
			props.onConfirm()
		end
		if props.onClose then props.onClose("self") end
	end

	return e(Modal, {
		title       = title,
		dismissible = not pending,
		onDismiss   = cancel,
		width       = 400,
		actions     = {
			{ variant = "secondary", label = cancelLabel, disabled = pending, onActivated = cancel },
			{
				variant     = danger and "danger" or "primary",
				label       = confirmLabel,
				loading     = pending,   -- "…", not tappable
				onActivated = confirm,
			},
		},
	}, {
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0, Theme.Space.sm),
		}),
		body = body and e(Text, {
			style       = "body",
			text        = body,
			color       = "text.secondary",
			wrap        = true,
			size        = UDim2.fromScale(1, 0),
			layoutOrder = 1,
		}) or nil,
		pending = pending and e(Text, {
			style       = "label",
			text        = Locale.Get("nav_leave_confirm_pending"),
			color       = "text.link",
			layoutOrder = 2,
		}) or nil,
		failed = failed and e(Text, {
			style       = "label",
			text        = Locale.Get("nav_leave_confirm_failed"),
			color       = "state.danger",
			wrap        = true,
			size        = UDim2.fromScale(1, 0),
			layoutOrder = 3,
		}) or nil,
	})
end

return ConfirmDialog
