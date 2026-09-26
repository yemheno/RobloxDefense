-- centralboss/StarterPlayerScripts/UI/BossHud.lua
--[[
    §AGX/X28: top-of-screen boss HP bar + phase banner (CentralBoss only).

    Display-only: the server (BossEncounter) owns HP and phases and pushes
        BossStateUpdate  { active, name, hp, maxHp, phase, phaseCount, phaseName, ... }
        BossPhaseChanged { phase, name, text, final? }
    Sits where the Start button lives in Idle (hidden then, since the boss
    only exists while Defending).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local NetworkManager = require(PlayerScripts:WaitForChild("Modules"):WaitForChild("NetworkManager"))

local BANNER_SECONDS = 3.5

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
	local banner, setBanner = React.useState(nil)

	React.useEffect(function()
		local bannerToken = 0
		local stateConn = NetworkManager.OnServerEvent("BossStateUpdate", function(data)
			if type(data) == "table" then
				setState(data)
			end
		end)
		local phaseConn = NetworkManager.OnServerEvent("BossPhaseChanged", function(data)
			if type(data) ~= "table" then return end
			bannerToken += 1
			local myToken = bannerToken
			setBanner(data)
			task.delay(BANNER_SECONDS, function()
				if bannerToken == myToken then setBanner(nil) end
			end)
		end)
		return function()
			bannerToken += 1   -- orphan any pending banner timer
			if stateConn then stateConn:Disconnect() end
			if phaseConn then phaseConn:Disconnect() end
		end
	end, {})

	local topInset = select(1, GuiService:GetGuiInset())
	local safeTop  = topInset.Y + 10

	local showBar = state ~= nil and state.active == true and (state.maxHp or 0) > 0
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
			Position               = UDim2.new(0.5, 0, 0, safeTop + 30),
			Size                   = UDim2.new(0.42, 0, 0, 46),
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
					pad = React.createElement("UIPadding", {
						PaddingTop = UDim.new(0.15, 0), PaddingBottom = UDim.new(0.15, 0),
					}),
				}),
			}),
		}) or nil,

		banner = (banner ~= nil) and React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0),
			Position               = UDim2.new(0.5, 0, 0, safeTop + 84),
			Size                   = UDim2.fromScale(0.34, 0.055),
			BackgroundColor3       = Color3.fromRGB(30, 15, 20),
			BackgroundTransparency = 0.2,
			BorderSizePixel        = 0,
			Text                   = tostring(banner.text or banner.name or ""),
			TextColor3             = banner.final and Color3.fromRGB(255, 215, 90)
				or PHASE_COLORS[math.clamp(banner.phase or 1, 1, #PHASE_COLORS)],
			Font                   = Enum.Font.GothamBlack,
			TextScaled             = true,
			ZIndex                 = 4,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
		}) or nil,
	})
end

return BossHud
