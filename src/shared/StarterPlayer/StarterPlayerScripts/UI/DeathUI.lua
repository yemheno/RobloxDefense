-- UI/DeathUI.lua
--[[
    Death Overlay UI
    ================
    Two-phase overlay driven by the server "DeathState" event:
      Phase 1 — KnockedDown: red-tinted overlay with countdown timer
      Phase 2 — Dead: grayscale overlay with respawn button

    Mounted in CombatApp; renders nothing when state == "Alive".

    §AGX/UI-P6: Theme v2 re-skin (docs/UI_REVAMP.md D1 Hybrid / D2).
      • Content = design px inside UIScaleRoot.Local (the Shell mounts this
        unscaled), on one raised card so the text reads over any world.
      • Revive is the ONE primary (orange) CTA; Respawn is secondary.
        The paid price is an essence CurrencyPill beside the button.
      • Private palette, TextScaled labels and hand-rolled buttons are gone
        (Theme roles + Text + Button). The Lighting ColorCorrection tints
        below are world effects, not UI colours, and keep their values.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")
local React             = require(ReplicatedStorage.Packages.React)

local Modules        = script.Parent.Parent:WaitForChild("Modules")
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- §AGX/UI-P6: shared components
local Common       = script.Parent:WaitForChild("Common")
local Theme        = require(Common:WaitForChild("Theme"))
local UIScaleRoot  = require(Common:WaitForChild("UIScaleRoot"))
local Text         = require(Common:WaitForChild("Text"))
local Button       = require(Common:WaitForChild("Button"))
local Panel        = require(Common:WaitForChild("Panel"))
local CurrencyPill = require(Common:WaitForChild("CurrencyPill"))
local GamepadFocus = require(Common:WaitForChild("GamepadFocus"))   -- §AGX/UI-P7

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

-- §AGX/UI-P6: layout in DESIGN px (phone scale).
local CARD_W      = 380
local BUTTON_W    = 260
local OVERLAY_Z   = Theme.Z.modal   -- was a literal 100

-- ═══════════════════════════════════════════════════════════
-- COLOR CORRECTION EFFECTS
-- ═══════════════════════════════════════════════════════════

local knockdownCC = nil
local deadCC      = nil

local function ApplyKnockdownEffect()
	if not knockdownCC then
		knockdownCC = Instance.new("ColorCorrectionEffect")
		knockdownCC.Name = "DeathSystem_Knockdown"
		knockdownCC.Parent = Lighting
	end
	knockdownCC.TintColor  = Color3.fromRGB(255, 120, 120)
	knockdownCC.Saturation = -0.3
	knockdownCC.Brightness = -0.1
	knockdownCC.Contrast   = 0.1
	knockdownCC.Enabled    = true

	-- Remove dead effect if present
	if deadCC then deadCC.Enabled = false end
end

local function ApplyDeadEffect()
	if not deadCC then
		deadCC = Instance.new("ColorCorrectionEffect")
		deadCC.Name = "DeathSystem_Dead"
		deadCC.Parent = Lighting
	end
	deadCC.TintColor  = Color3.fromRGB(255, 255, 255)
	deadCC.Saturation = -1       -- full grayscale
	deadCC.Brightness = -0.2
	deadCC.Contrast   = -0.1
	deadCC.Enabled    = true

	-- Remove knockdown effect
	if knockdownCC then knockdownCC.Enabled = false end
end

local function ClearEffects()
	if knockdownCC then knockdownCC.Enabled = false end
	if deadCC      then deadCC.Enabled = false end
end

-- ═══════════════════════════════════════════════════════════
-- COMPONENT
-- ═══════════════════════════════════════════════════════════

local function DeathUI()
	local deathState, setDeathState     = React.useState("Alive")
	local knockdownTimer, setKnockdownTimer = React.useState(0)
	local knockdownEndsAt = React.useRef(0)
	local countdownTaskRef = React.useRef(nil)

	-- §DISC/D3b: wipe-revive offer state ({cost, endsAt, denied?} or nil)
	local wipeOffer, setWipeOffer = React.useState(nil)
	local wipeTimer, setWipeTimer = React.useState(0)

	-- Listen for server events
	React.useEffect(function()
		local wipeConn = NetworkManager.OnServerEvent("WipeReviveOffer", function(data)
			-- §AGX/X40: kind = "free" | "paid" | "none" (paid only reaches
			-- players who can already afford it).
			setWipeOffer({
				kind     = data.kind or "paid",
				freeLeft = data.freeLeft or 0,
				cost     = data.cost or 0,
				endsAt   = os.clock() + (data.seconds or 10),
				denied   = data.denied,
			})
		end)
		local wipeDone = NetworkManager.OnServerEvent("WipeReviveResolved", function(_data)
			-- Either someone revived (combat resumes; the buyer's own
			-- DeathState flips to Alive separately) or the run is over
			-- (teleport to lobby imminent). Both close the offer.
			setWipeOffer(nil)
		end)

		local conn = NetworkManager.OnServerEvent("DeathState", function(data)
			local newState = data.state
			setDeathState(newState)

			if newState == "KnockedDown" then
				local duration = data.duration or 10
				knockdownEndsAt.current = os.clock() + duration
				setKnockdownTimer(duration)
				ApplyKnockdownEffect()
			elseif newState == "Dead" then
				knockdownEndsAt.current = 0
				setKnockdownTimer(0)
				ApplyDeadEffect()
			else
				knockdownEndsAt.current = 0
				setKnockdownTimer(0)
				ClearEffects()
			end
		end)

		return function()
			if conn then conn:Disconnect() end
			if wipeConn then wipeConn:Disconnect() end
			if wipeDone then wipeDone:Disconnect() end
			ClearEffects()
		end
	end, {})

	-- §DISC/D3b: countdown for the wipe window
	React.useEffect(function()
		if not wipeOffer then return end
		local running = true
		task.spawn(function()
			while running do
				local remaining = math.max(0, wipeOffer.endsAt - os.clock())
				setWipeTimer(remaining)
				if remaining <= 0 then break end
				task.wait(0.1)
			end
		end)
		return function() running = false end
	end, { wipeOffer })

	-- Countdown timer for knockdown
	React.useEffect(function()
		if deathState ~= "KnockedDown" then return end

		-- Cancel old countdown task if present
		if countdownTaskRef.current then
			task.cancel(countdownTaskRef.current)
		end

		-- Spawn new countdown task and store in ref
		countdownTaskRef.current = task.spawn(function()
			while deathState == "KnockedDown" do
				local remaining = math.max(0, knockdownEndsAt.current - os.clock())
				setKnockdownTimer(remaining)
				if remaining <= 0 then
					break
				end
				task.wait(0.1)
			end
		end)

		return function()
			if countdownTaskRef.current then
				task.cancel(countdownTaskRef.current)
				countdownTaskRef.current = nil
			end
		end
	end, { deathState })

	-- §AGX/UI-P7: gamepad only: select Revive (or Respawn) when it appears;
	-- the key changes when the wipe offer swaps Respawn for Revive. Steals
	-- from an open panel on purpose (death outranks menus).
	local overlayRef = React.useRef(nil)
	local hasButton = deathState == "Dead" and not (wipeOffer and wipeOffer.kind == "none")
	GamepadFocus.useAutoSelect(overlayRef,
		hasButton and ((wipeOffer and "revive") or "respawn") or nil,
		{ prefer = { "ReviveButton", "RespawnButton" }, steal = true })

	-- Nothing to render when alive
	if deathState == "Alive" then
		return nil
	end

	-- §AGX/UI-P6: shared overlay shell: full-bleed tint + a centred card.
	local function overlay(tint, tintT, cardY, cardChildren)
		local children = {
			layout = e("UIListLayout", {
				SortOrder           = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding             = UDim.new(0, SP.md),
			}),
		}
		for k, v in pairs(cardChildren) do children[k] = v end
		return e("Frame", {
			Name                   = "DeathOverlay",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex                 = OVERLAY_Z,
			-- §AGX/UI-P7: keep D-pad focus on the overlay's buttons.
			ref                    = overlayRef,
			SelectionGroup         = true,
			SelectionBehaviorUp    = Enum.SelectionBehavior.Stop,
			SelectionBehaviorDown  = Enum.SelectionBehavior.Stop,
			SelectionBehaviorLeft  = Enum.SelectionBehavior.Stop,
			SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
		}, {
			tint = e("Frame", {
				Name                   = "Tint",
				Size                   = UDim2.fromScale(1, 1),
				BackgroundColor3       = tint,
				BackgroundTransparency = tintT,
				BorderSizePixel        = 0,
				ZIndex                 = OVERLAY_Z,
			}),
			content = e(UIScaleRoot.Local, { name = "DeathContent", zIndex = OVERLAY_Z + 1 }, {
				card = e(Panel, {
					name         = "Card",
					elevation    = "raised",
					padding      = "lg",
					transparency = 0.12,
					anchorPoint  = Vector2.new(0.5, 0.5),
					position     = UDim2.fromScale(0.5, cardY),
					size         = UDim2.fromOffset(CARD_W, 0),
					autoSize     = "Y",
					zIndex       = OVERLAY_Z + 1,
				}, children),
			}),
		})
	end

	-- ── KNOCKED DOWN ─────────────────────────────────────
	if deathState == "KnockedDown" then
		return overlay(R.state.dangerFill, 0.75, 0.35, {
			header = e(Text, {
				style = "title", text = "KNOCKED DOWN", color = "state.danger",
				align = "center", layoutOrder = 1, zIndex = OVERLAY_Z + 2,
			}),
			timer = e(Text, {
				style = "display", text = string.format("%.1f", math.max(0, knockdownTimer)),
				align = "center", layoutOrder = 2, zIndex = OVERLAY_Z + 2,
			}),
			subtitle = e(Text, {
				style = "body", text = "An ally can still revive you...", color = "text.secondary",
				align = "center", wrap = true, layoutOrder = 3, zIndex = OVERLAY_Z + 2,
			}),
		})
	end

	-- ── DEAD ─────────────────────────────────────────────
	if deathState == "Dead" then
		-- §AGX/X40: the revive button's label keeps the neutral wording.
		local reviveRow = nil
		if wipeOffer and wipeOffer.kind ~= "none" then
			local isFree = wipeOffer.kind == "free"
			reviveRow = e("Frame", {
				Name                   = "ReviveRow",
				LayoutOrder            = 3,
				Size                   = UDim2.new(1, 0, 0, Theme.Metrics.button.lg),
				BackgroundTransparency = 1,
				ZIndex                 = OVERLAY_Z + 2,
			}, {
				layout = e("UIListLayout", {
					FillDirection       = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment   = Enum.VerticalAlignment.Center,
					SortOrder           = Enum.SortOrder.LayoutOrder,
					Padding             = UDim.new(0, SP.sm),
				}),
				btn = e(Button, {
					name        = "ReviveButton",
					variant     = "primary",
					size        = "lg",
					width       = isFree and BUTTON_W or nil,
					label       = isFree
						and string.format("REVIVE  —  FREE (%d left)", wipeOffer.freeLeft)
						or "REVIVE",
					layoutOrder = 1,
					zIndex      = OVERLAY_Z + 2,
					onActivated = function()
						NetworkManager.FireServer("WipeReviveAccept")
					end,
				}),
				-- Currency always via CurrencyPill (was "N ♦" in the label).
				cost = (not isFree) and e(CurrencyPill, {
					currency    = "essence",
					value       = wipeOffer.cost,
					layoutOrder = 2,
					zIndex      = OVERLAY_Z + 2,
				}) or nil,
			})
		end

		return overlay(R.surface.scrim, 0.5, 0.4, {
			header = e(Text, {
				style = "title", text = wipeOffer and "PARTY WIPED" or "YOU DIED",
				color = "text.secondary", align = "center", layoutOrder = 1, zIndex = OVERLAY_Z + 2,
			}),

			-- §DISC/D3b: during a wipe window the free respawn is gone;
			-- the paid revive is the only out.
			wipeTimerLbl = wipeOffer and e(Text, {
				style = "display", text = string.format("%.0f", math.max(0, wipeTimer)),
				color = "state.warning", align = "center", layoutOrder = 2, zIndex = OVERLAY_Z + 2,
			}) or nil,

			-- §AGX/X40: neutral wording; no button when there's nothing
			-- this player can use (they wait on the party instead).
			waitLbl = (wipeOffer and wipeOffer.kind == "none") and e(Text, {
				style = "body", text = "Waiting for your party…", color = "text.primary",
				align = "center", layoutOrder = 3, zIndex = OVERLAY_Z + 2,
			}) or nil,

			reviveBtn = reviveRow,

			deniedLbl = (wipeOffer and wipeOffer.denied) and e(Text, {
				style = "body", text = wipeOffer.denied, color = "state.danger",
				align = "center", wrap = true, layoutOrder = 4, zIndex = OVERLAY_Z + 2,
			}) or nil,

			-- Respawn button (hidden during the wipe window).
			-- §AGX/UI-P6: secondary (Revive owns the orange CTA), 56 design px.
			respawnBtn = (not wipeOffer) and e(Button, {
				name        = "RespawnButton",
				variant     = "secondary",
				size        = "lg",
				width       = BUTTON_W,
				label       = "RESPAWN",
				layoutOrder = 2,
				zIndex      = OVERLAY_Z + 2,
				onActivated = function()
					NetworkManager.FireServer("RequestRespawn")
				end,
			}) or nil,
		})
	end

	return nil
end

return DeathUI
