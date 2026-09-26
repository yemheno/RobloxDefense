-- UI/DeathUI.lua
--[[
    Death Overlay UI
    ================
    Two-phase overlay driven by the server "DeathState" event:
      Phase 1 — KnockedDown: red-tinted overlay with countdown timer
      Phase 2 — Dead: grayscale overlay with respawn button

    Mounted in CombatApp; renders nothing when state == "Alive".
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")
local React             = require(ReplicatedStorage.Packages.React)

local Modules        = script.Parent.Parent:WaitForChild("Modules")
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- ═══════════════════════════════════════════════════════════
-- PALETTE
-- ═══════════════════════════════════════════════════════════

local C = {
	knockdownTint   = Color3.fromRGB(180,  30,  30),
	deadGray        = Color3.fromRGB( 50,  50,  50),
	white           = Color3.fromRGB(255, 255, 255),
	text            = Color3.fromRGB(230, 230, 230),
	textDim         = Color3.fromRGB(160, 160, 170),
	btnBg           = Color3.fromRGB( 60, 180,  80),
	btnBgHover      = Color3.fromRGB( 80, 210, 100),
	btnText         = Color3.fromRGB(255, 255, 255),
	timerText       = Color3.fromRGB(255, 200, 200),
	headerKnockdown = Color3.fromRGB(255,  80,  80),
	headerDead      = Color3.fromRGB(180, 180, 180),
}

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

	-- Nothing to render when alive
	if deathState == "Alive" then
		return nil
	end

	-- ── KNOCKED DOWN ─────────────────────────────────────
	if deathState == "KnockedDown" then
		return React.createElement("Frame", {
			Name                   = "DeathOverlay",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex                 = 100,
		}, {
			-- Semi-transparent red vignette
			vignette = React.createElement("Frame", {
				Size                   = UDim2.fromScale(1, 1),
				BackgroundColor3       = C.knockdownTint,
				BackgroundTransparency = 0.75,
				BorderSizePixel        = 0,
			}),

			-- Center text
			centerPanel = React.createElement("Frame", {
				Size                   = UDim2.fromScale(0.4, 0.2),
				Position               = UDim2.fromScale(0.5, 0.35),
				AnchorPoint            = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
			}, {
				layout = React.createElement("UIListLayout", {
					SortOrder         = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding           = UDim.new(0, 8),
				}),

				header = React.createElement("TextLabel", {
					Size                   = UDim2.new(1, 0, 0, 40),
					BackgroundTransparency = 1,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
					TextColor3             = C.headerKnockdown,
					TextStrokeTransparency = 0.3,
					TextStrokeColor3       = Color3.new(0, 0, 0),
					Text                   = "KNOCKED DOWN",
					LayoutOrder            = 1,
				}),

				timer = React.createElement("TextLabel", {
					Size                   = UDim2.new(1, 0, 0, 50),
					BackgroundTransparency = 1,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
					TextColor3             = C.timerText,
					TextStrokeTransparency = 0.3,
					TextStrokeColor3       = Color3.new(0, 0, 0),
					Text                   = string.format("%.1f", math.max(0, knockdownTimer)),
					LayoutOrder            = 2,
				}),

				subtitle = React.createElement("TextLabel", {
					Size                   = UDim2.new(1, 0, 0, 24),
					BackgroundTransparency = 1,
					Font                   = Enum.Font.Gotham,
					TextScaled             = true,
					TextColor3             = C.textDim,
					TextStrokeTransparency = 0.5,
					TextStrokeColor3       = Color3.new(0, 0, 0),
					Text                   = "An ally can still revive you...",
					LayoutOrder            = 3,
				}),
			}),
		})
	end

	-- ── DEAD ─────────────────────────────────────────────
	if deathState == "Dead" then
		return React.createElement("Frame", {
			Name                   = "DeathOverlay",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex                 = 100,
		}, {
			-- Dark overlay
			overlay = React.createElement("Frame", {
				Size                   = UDim2.fromScale(1, 1),
				BackgroundColor3       = C.deadGray,
				BackgroundTransparency = 0.5,
				BorderSizePixel        = 0,
			}),

			-- Center panel
			centerPanel = React.createElement("Frame", {
				Size                   = UDim2.fromScale(0.35, 0.3),
				Position               = UDim2.fromScale(0.5, 0.4),
				AnchorPoint            = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
			}, {
				layout = React.createElement("UIListLayout", {
					SortOrder         = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding           = UDim.new(0, 12),
				}),

				header = React.createElement("TextLabel", {
					Size                   = UDim2.new(1, 0, 0, 50),
					BackgroundTransparency = 1,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
					TextColor3             = C.headerDead,
					TextStrokeTransparency = 0.3,
					TextStrokeColor3       = Color3.new(0, 0, 0),
					Text                   = wipeOffer and "PARTY WIPED" or "YOU DIED",
					LayoutOrder            = 1,
				}),

				-- §DISC/D3b: during a wipe window the free respawn is gone;
				-- the paid revive is the only out.
				wipeTimerLbl = wipeOffer and React.createElement("TextLabel", {
					Size                   = UDim2.new(1, 0, 0, 40),
					BackgroundTransparency = 1,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
					TextColor3             = C.timerText,
					TextStrokeTransparency = 0.3,
					TextStrokeColor3       = Color3.new(0, 0, 0),
					Text                   = string.format("%.0f", math.max(0, wipeTimer)),
					LayoutOrder            = 2,
				}) or nil,

				-- §AGX/X40: neutral wording; no button when there's nothing
				-- this player can use (they wait on the party instead).
				waitLbl = (wipeOffer and wipeOffer.kind == "none") and React.createElement("TextLabel", {
					Size                   = UDim2.new(1, 0, 0, 30),
					BackgroundTransparency = 1,
					Font                   = Enum.Font.Gotham,
					TextScaled             = true,
					TextColor3             = Color3.fromRGB(220, 220, 220),
					TextStrokeTransparency = 0.5,
					TextStrokeColor3       = Color3.new(0, 0, 0),
					Text                   = "Waiting for your party…",
					LayoutOrder            = 3,
				}) or nil,

				reviveBtn = (wipeOffer and wipeOffer.kind ~= "none") and React.createElement("TextButton", {
					-- §T10/LIVE2 sizing: offset height, generous width.
					Size                   = UDim2.new(0.8, 0, 0, 46),
					BackgroundColor3       = Color3.fromRGB(45, 175, 95),
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
					TextColor3             = Color3.fromRGB(255, 255, 255),
					Text                   = (wipeOffer.kind == "free")
						and string.format("REVIVE  —  FREE (%d left)", wipeOffer.freeLeft)
						or ("REVIVE  —  " .. tostring(wipeOffer.cost) .. " ♦"),
					LayoutOrder            = 3,
					AutoButtonColor        = true,
					[React.Event.Activated] = function()
						NetworkManager.FireServer("WipeReviveAccept")
					end,
				}, {
					corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				}) or nil,

				deniedLbl = (wipeOffer and wipeOffer.denied) and React.createElement("TextLabel", {
					Size                   = UDim2.new(1, 0, 0, 24),
					BackgroundTransparency = 1,
					Font                   = Enum.Font.Gotham,
					TextScaled             = true,
					TextColor3             = Color3.fromRGB(255, 120, 120),
					TextStrokeTransparency = 0.5,
					TextStrokeColor3       = Color3.new(0, 0, 0),
					Text                   = wipeOffer.denied,
					LayoutOrder            = 4,
				}) or nil,

				-- Respawn button (hidden during the wipe window)
				-- §T10/LIVE2: old size was 0.115×0.046 of a 0.35×0.3 panel
				-- ≈ 50×10 px — another of the "incredibly small" buttons.
				respawnBtn = (not wipeOffer) and React.createElement("TextButton", {
					Size                   = UDim2.new(0.6, 0, 0, 44),
					BackgroundColor3       = C.btnBg,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
					TextColor3             = C.btnText,
					Text                   = "RESPAWN",
					LayoutOrder            = 2,
					AutoButtonColor        = true,
					[React.Event.Activated] = function()
						NetworkManager.FireServer("RequestRespawn")
					end,
				}, {
					corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
					padding = React.createElement("UIPadding", {
						PaddingLeft   = UDim.new(0, 12),
						PaddingRight  = UDim.new(0, 12),
						PaddingTop    = UDim.new(0, 6),
						PaddingBottom = UDim.new(0, 6),
					}),
				}) or nil,
			}),
		})
	end

	return nil
end

return DeathUI
