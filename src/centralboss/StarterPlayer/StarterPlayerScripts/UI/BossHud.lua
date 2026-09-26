-- centralboss/StarterPlayerScripts/UI/BossHud.lua
--[[
    §AGX/X28: top-of-screen boss HP bar + phase banner (CentralBoss only).
    §AGX/UI-P4: the phase banner is a Notify banner ("bossPhase", the top
    priority) now; this component renders only the HP bar.

    Display-only: the server (BossEncounter) owns HP and phases and pushes
        BossStateUpdate  { active, name, hp, maxHp, phase, phaseCount, phaseName, ... }
        BossPhaseChanged { phase, name, text, final? }
    Sits where the Start button lives in Idle (hidden then, since the boss
    only exists while Defending).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")
-- §AGX/UI-P4: Workspace (banner height from the viewport) no longer needed.
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local NetworkManager = require(PlayerScripts:WaitForChild("Modules"):WaitForChild("NetworkManager"))
local Notify         = require(PlayerScripts:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("Notify"))  -- §AGX/UI-P4

local BANNER_SECONDS = 3.5

-- §AGX/UI-P1: M9: BossHud owns its own top-centre slot directly under the
-- topbar (safeTop). It publishes how many px below safeTop it uses as a
-- client-local ReplicatedStorage attribute; HUD.lua pushes Start / Next Wave
-- / Return below that (they collided at safeTop+30..88), and Notify puts
-- its banner below both. §AGX/UI-P4: only the HP bar is reserved now; the
-- phase banner lives in Notify's banner slot.
-- TODO(FormFactor): becomes the "top-centre banner" region in P5.
local ATTR_TOP_CENTRE = "UI_TopCentreReservedPx"
local BAR_H      = 46
local SLOT_GAP   = 8

-- Bar colour per phase (index clamps to the last entry).
local PHASE_COLORS = {
	Color3.fromRGB(200, 60, 60),
	Color3.fromRGB(230, 120, 40),
	Color3.fromRGB(170, 50, 200),
}

local function formatNumber(n)
	local s = tostring(math.floor(n or 0))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local function BossHud()
	local state, setState   = React.useState(nil)

	React.useEffect(function()
		local stateConn = NetworkManager.OnServerEvent("BossStateUpdate", function(data)
			if type(data) == "table" then
				setState(data)
			end
		end)
		-- §AGX/UI-P4: was local banner state + a 3.5 s token timer. Same
		-- text and colour; "bossPhase" outranks (preempts) a wave banner,
		-- and a newer phase replaces an older one via the key.
		local phaseConn = NetworkManager.OnServerEvent("BossPhaseChanged", function(data)
			if type(data) ~= "table" then return end
			Notify.banner(tostring(data.text or data.name or ""), {
				key      = "bossPhase",
				priority = "bossPhase",
				duration = BANNER_SECONDS,
				color    = data.final and Color3.fromRGB(255, 215, 90)
					or PHASE_COLORS[math.clamp(tonumber(data.phase) or 1, 1, #PHASE_COLORS)],
			})
		end)
		return function()
			if stateConn then stateConn:Disconnect() end
			if phaseConn then phaseConn:Disconnect() end
		end
	end, {})

	-- §AGX/UI-P1: roots use ScreenInsets = DeviceSafeInsets now; in landscape
	-- its top inset is 0, so GetGuiInset().Y (topbar) is not double-counted.
	local topInset = select(1, GuiService:GetGuiInset())
	local safeTop  = topInset.Y + 10

	local showBar = state ~= nil and state.active == true and (state.maxHp or 0) > 0

	-- §AGX/UI-P1: slot geometry (px below safeTop).
	-- §AGX/UI-P4: reserves the HP bar only; the phase banner is Notify's.
	local reserved = 0
	if showBar then reserved = BAR_H + SLOT_GAP end

	React.useEffect(function()
		ReplicatedStorage:SetAttribute(ATTR_TOP_CENTRE, reserved > 0 and reserved or nil)
	end, { reserved })
	React.useEffect(function()
		return function()
			ReplicatedStorage:SetAttribute(ATTR_TOP_CENTRE, nil)
		end
	end, {})
	local fraction = showBar and math.clamp(state.hp / state.maxHp, 0, 1) or 0
	local phase = showBar and (state.phase or 1) or 1
	local barColor = PHASE_COLORS[math.clamp(phase, 1, #PHASE_COLORS)]

	local title = ""
	if showBar then
		title = string.upper(state.name or "Boss")
		if (state.phaseCount or 1) > 1 then
			title ..= string.format("   ·   Phase %d/%d", phase, state.phaseCount)
			if state.phaseName then title ..= " — " .. state.phaseName end
		end
	end

	return React.createElement("Frame", {
		Name                   = "BossHud",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		-- Sibling ZIndex: render as a group BELOW CombatApp's AppRoot (1),
		-- so fullscreen menus cover the bar. AppRoot is transparent.
		ZIndex                 = 0,
	}, {
		bar = showBar and React.createElement("Frame", {
			AnchorPoint            = Vector2.new(0.5, 0),
			-- §AGX/UI-P1: own slot at safeTop (was safeTop+30, on top of the
			-- HUD's Start/Next Wave at safeTop+34). 0.36 wide (was 0.42) so it
			-- stays clear of the HUD's top-right currency strip (from 0.695 W).
			Position               = UDim2.new(0.5, 0, 0, safeTop),
			Size                   = UDim2.new(0.36, 0, 0, BAR_H),
			BackgroundTransparency = 1,
			ZIndex                 = 4,
		}, {
			title = React.createElement("TextLabel", {
				Size                   = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Text                   = title,
				TextColor3             = Color3.fromRGB(245, 235, 220),
				TextStrokeTransparency = 0.4,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				ZIndex                 = 4,
			}, {
				minText = React.createElement("UITextSizeConstraint", { MinTextSize = 12 }),  -- §AGX/UI-P1
			}),
			track = React.createElement("Frame", {
				Position         = UDim2.new(0, 0, 0, 22),
				Size             = UDim2.new(1, 0, 0, 22),
				BackgroundColor3 = Color3.fromRGB(25, 20, 28),
				BorderSizePixel  = 0,
				ZIndex           = 4,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
				stroke = React.createElement("UIStroke", {
					Color = Color3.fromRGB(0, 0, 0), Thickness = 1.5, Transparency = 0.2,
				}),
				fill = React.createElement("Frame", {
					Size             = UDim2.fromScale(fraction, 1),
					BackgroundColor3 = barColor,
					BorderSizePixel  = 0,
					ZIndex           = 5,
				}, {
					corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
				}),
				hpText = React.createElement("TextLabel", {
					Size                   = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text                   = formatNumber(state.hp) .. " / " .. formatNumber(state.maxHp),
					TextColor3             = Color3.fromRGB(255, 255, 255),
					TextStrokeTransparency = 0.3,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
					ZIndex                 = 6,
				}, {
					minText = React.createElement("UITextSizeConstraint", { MinTextSize = 12 }),  -- §AGX/UI-P1
					pad = React.createElement("UIPadding", {
						PaddingTop = UDim.new(0.15, 0), PaddingBottom = UDim.new(0.15, 0),
					}),
				}),
			}),
		}) or nil,

		-- §AGX/UI-P4: phase banner removed (Notify.banner, see above).
	})
end

return BossHud
