-- shared/StarterPlayerScripts/UI/DailyLoginUI.lua  (§AGX/UI-P3 W4: moved from lobby/UI; its manager loads in every place)
--[[
    Minimal Daily Login panel.
    On mount: requests current status from server.
    Claim button calls ClaimDailyLogin.

    Props:
      onClose  function

    §AGX/UI-P6: Theme v2 re-skin. AppWindow variant "dialog" (the Registry
    presents it as a dialog: phone = bottom sheet). Body = design px inside
    UIScaleRoot.Local, one vertical list in a ScrollingFrame (the phone
    sheet body is ~120 design px, so it scrolls instead of clipping).
    Rewards "100 Merits" / "2 Essence" render as CurrencyPills; the claim
    is the ONE primary (orange) Button ("Already Claimed" = locked,
    "…" while pending). Kept: useRequest, the §AGX/X47 calendar + spree
    line, the 360x260 windowed floor (T7). Private palette gone.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
-- §AGX/UI-P6: shared components
local Common       = PlayerScripts:WaitForChild("UI"):WaitForChild("Common")
local AppWindow    = require(Common:WaitForChild("AppWindow"))   -- §T10/U3
local useRequest   = require(Common:WaitForChild("useRequest"))  -- §AGX/UI-P4
local Theme        = require(Common:WaitForChild("Theme"))
local UIScaleRoot  = require(Common:WaitForChild("UIScaleRoot"))
local Text         = require(Common:WaitForChild("Text"))
local Button       = require(Common:WaitForChild("Button"))
local CurrencyPill = require(Common:WaitForChild("CurrencyPill"))

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

local CLAIM_W = 240   -- design px

-- "100 Merits" -> "merits", 100 (a Theme.Currency key), else nil.
local function parseCurrency(entry)
	local amount, name = string.match(tostring(entry), "^%s*(%-?%d+)%s+(%a+)%s*$")
	local key = name and string.lower(name)
	if key and Theme.Currency[key] then
		return key, tonumber(amount)
	end
	return nil
end

local function DailyLoginUI(props)
	local onClose = props.onClose or function() end

	local status, setStatus       = React.useState(nil)

	-- §AGX/UI-P4: the claim result is useRequest's inline state (was a
	-- resultMsg + DailyLoginResult listener + 3 s clear timer). Same texts,
	-- same 3 s hold, status re-fetched after every result. New: "Claiming…"
	-- while pending, a timeout error after 4 s, and the button is inert
	-- while a claim is in flight.
	local claimReq = useRequest("ClaimDailyLogin", {
		reply       = "DailyLoginResult",
		pendingText = "Claiming…",
		holdFor     = 3,
		match       = function(data)
			if type(data) ~= "table" then return nil end
			if data.ok then
				return true, "Claimed!  +" .. table.concat(data.rewards or {}, ",  ")
			end
			return false, data.reason or "Failed."
		end,
		onResult    = function()
			NetworkManager.FireServer("GetDailyLoginStatus")
		end,
	})
	local resultMsg = claimReq.message

	React.useEffect(function()
		local mounted = true
		NetworkManager.FireServer("GetDailyLoginStatus")

		local conn1 = NetworkManager.OnServerEvent("DailyLoginStatus", function(data)
			if mounted then setStatus(data) end
		end)

		return function()
			mounted = false
			if conn1 then conn1:Disconnect() end
		end
	end, {})

	-- §AGX/X47: calendar (casual, never resets) + spree (consecutive days).
	local streakText  = status and string.format("Calendar day %d/30  ·  Spree: %d day%s",
		status.calendarDay or 1, status.streak or 0, (status.streak == 1) and "" or "s") or "Loading…"
	local canClaim    = status and status.canClaim == true

	-- Today's reward: currencies as CurrencyPills (§AGX/UI-P6), anything
	-- else as text; "—" when the server sent nothing.
	local rewardRow = {
		layout = e("UIListLayout", {
			FillDirection     = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder         = Enum.SortOrder.LayoutOrder,
			Padding           = UDim.new(0, SP.sm),
			Wraps             = true,
		}),
		caption = e(Text, {
			style       = "caption",
			text        = "Today's reward:",
			color       = "text.secondary",
			size        = UDim2.fromOffset(0, Theme.Metrics.pill.height),
			autoSize    = "X",
			layoutOrder = 0,
		}),
	}
	local rewards = (status and status.nextReward) or {}
	if #rewards == 0 then
		rewardRow.none = e(Text, {
			style = "label", text = "—", size = UDim2.fromOffset(16, Theme.Metrics.pill.height), layoutOrder = 1,
		})
	end
	for i, entry in ipairs(rewards) do
		local key, amount = parseCurrency(entry)
		rewardRow["r" .. i] = key and e(CurrencyPill, {
			currency    = key,
			value       = amount,
			showLabel   = true,
			layoutOrder = i,
		}) or e(Text, {
			style       = "label",
			text        = tostring(entry),
			color       = "rarity.legendary",
			size        = UDim2.fromOffset(0, Theme.Metrics.pill.height),
			autoSize    = "X",
			layoutOrder = i,
		})
	end

	-- §AGX/UI-P4: colour follows the request state (was always green).
	local feedbackColor = (claimReq.state == "err") and "state.danger"
		or (claimReq.state == "pending") and "text.secondary"
		or "state.success"

	-- §T10/U3: chrome owned by AppWindow (44 px close there).
	return e(AppWindow, {
		variant = "dialog",
		title   = "Daily Login",
		icon    = "dailyLogin",
		onClose = onClose,
		size    = UDim2.fromScale(0.38, 0.46),
		-- §AGX/UI-P1: T7 pixel floor for small windows (1080p is above it).
		minSize = Vector2.new(360, 260),
		zIndex  = Theme.Z.window,
	}, {
		content = e(UIScaleRoot.Local, { name = "DailyLoginBody", zIndex = Theme.Z.window + 2 }, {
			scroll = e("ScrollingFrame", {
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				CanvasSize             = UDim2.new(),
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
				ScrollingDirection     = Enum.ScrollingDirection.Y,
				ScrollBarThickness     = Theme.Metrics.scrollBar,
				ScrollBarImageColor3   = R.text.secondary,
			}, {
				pad = e("UIPadding", {
					PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
					PaddingTop = UDim.new(0, SP.sm), PaddingBottom = UDim.new(0, SP.md),
				}),
				layout = e("UIListLayout", {
					SortOrder           = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding             = UDim.new(0, SP.sm),
				}),

				streakLbl = e(Text, {
					style       = "label",
					text        = streakText,
					wrap        = true,
					layoutOrder = 1,
				}),

				rewardRow = e("Frame", {
					Name                   = "Reward",
					Size                   = UDim2.fromScale(1, 0),
					AutomaticSize          = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					LayoutOrder            = 2,
				}, rewardRow),

				feedback = resultMsg and e(Text, {
					style       = "label",
					text        = resultMsg,
					color       = feedbackColor,
					align       = "center",
					wrap        = true,
					layoutOrder = 3,
				}) or nil,

				claimBtn = e(Button, {
					variant     = "primary",
					size        = "md",
					width       = CLAIM_W,
					label       = canClaim and "Claim Reward" or "Already Claimed",
					disabled    = not canClaim,
					loading     = claimReq.pending == true,
					layoutOrder = 4,
					onActivated = function()
						if canClaim and not claimReq.pending then  -- §AGX/UI-P4: no double claim
							claimReq.send()  -- §AGX/UI-P4: fires ClaimDailyLogin
						end
					end,
				}),
			}),
		}),
	})
end

return DailyLoginUI
