-- shared/StarterPlayerScripts/UI/TeammateVitals.lua
--[[
    Teammate health display — shared combat component.

    Shows a compact strip of name + HP bar for every connected player
    except the local player. Positioned on the right side of the screen.
    Used by LaneDefense, CentralBoss, and HordeMode.

    Server broadcasts "VitalsUpdate" every ~1 s with a table keyed by
    userId → { name, hp, maxHp, class, level }.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local LocalPlayer   = Players.LocalPlayer
local SharedModules = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")

-- ── Palette ───────────────────────────────────────────────
local C = {
	panel_bg   = Color3.fromRGB(16, 16, 22),
	bar_bg     = Color3.fromRGB(40, 40, 56),
	bar_hp     = Color3.fromRGB(60, 190, 90),
	bar_low    = Color3.fromRGB(200, 60, 60),
	text       = Color3.fromRGB(210, 210, 225),
	text_dim   = Color3.fromRGB(130, 130, 150),
	stub_text  = Color3.fromRGB(100, 100, 130),
	power_c    = Color3.fromRGB(255, 180, 40),
}

-- ═══════════════════════════════════════════════════════════
-- VITAL BAR (per-teammate row)
-- ═══════════════════════════════════════════════════════════
local function TeammateMember(props)
	local teammate = props.teammate
	local hpFrac   = math.max(0, math.min(1, teammate.hp / math.max(teammate.maxHp, 1)))
	local isLow    = hpFrac < 0.30

	return React.createElement("Frame", {
		Size             = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = C.panel_bg,
		BackgroundTransparency = 0.25,
		BorderSizePixel  = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),

		-- Name + class label
		Label = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.03, 0.08),
			Size                   = UDim2.fromScale(0.94, 0.42),
			BackgroundTransparency = 1,
			Text                   = teammate.name .. "  [" .. (teammate.class or "?") .. "]",
			TextColor3             = C.text,
			TextXAlignment         = Enum.TextXAlignment.Left,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
		}),
		PowerBadge = (teammate.powerLevel and teammate.powerLevel > 0) and React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(1, 0),
			Position               = UDim2.fromScale(0.97, 0.08),
			Size                   = UDim2.fromScale(0.28, 0.42),
			BackgroundTransparency = 1,
			Text                   = "⚡" .. tostring(teammate.powerLevel),
			TextColor3             = C.power_c,
			TextXAlignment         = Enum.TextXAlignment.Right,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
		}) or nil,

		-- HP bar track
		BarBg = React.createElement("Frame", {
			Position         = UDim2.fromScale(0.03, 0.58),
			Size             = UDim2.fromScale(0.94, 0.30),
			BackgroundColor3 = C.bar_bg,
			BorderSizePixel  = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			-- Filled portion
			Fill = React.createElement("Frame", {
				Size             = UDim2.fromScale(hpFrac, 1),
				BackgroundColor3 = isLow and C.bar_low or C.bar_hp,
				BorderSizePixel  = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			}),
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- TEAMMATE VITALS PANEL
-- ═══════════════════════════════════════════════════════════
local function TeammateVitals()
	local teammates, setTeammates = React.useState({})

	-- Listen for VitalsUpdate from server
	React.useEffect(function()
		local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

		local conn = NetworkManager.OnServerEvent("VitalsUpdate", function(vitals)
			if not vitals then return end

			-- Filter out the local player, build array
			local list = {}
			local localId = tostring(LocalPlayer.UserId)
			for id, data in pairs(vitals) do
				if id ~= localId then
					table.insert(list, data)
				end
			end

			-- Sort alphabetically by name for stable ordering
			table.sort(list, function(a, b) return a.name < b.name end)

			setTeammates(list)
		end)

		return function()
			if conn and type(conn) == "table" and conn.Disconnect then
				conn:Disconnect()
			end
		end
	end, {})

	-- Nothing to show when solo
	if #teammates == 0 then
		if game:GetService("RunService"):IsStudio() then
			return React.createElement("TextLabel", {
				AnchorPoint            = Vector2.new(1, 0),
				Position               = UDim2.new(1, -8, 0, 120),
				Size                   = UDim2.fromScale(0.089, 0.020),
				BackgroundTransparency = 1,
				Text                   = "[TeammateVitals — waiting]",
				TextColor3             = C.stub_text,
				TextScaled             = true,
				Font                   = Enum.Font.Gotham,
			})
		end
		return nil
	end

	-- Build the rows
	local rows = {}
	for i, teammate in ipairs(teammates) do
		rows["member_" .. i] = React.createElement(TeammateMember, {
			teammate = teammate,
		})
	end
	rows.layout = React.createElement("UIListLayout", {
		SortOrder     = Enum.SortOrder.LayoutOrder,
		Padding       = UDim.new(0, 4),
		FillDirection = Enum.FillDirection.Vertical,
	})

	return React.createElement("Frame", {
		AnchorPoint      = Vector2.new(1, 0),
		Position         = UDim2.new(1, -8, 0, 120),
		Size             = UDim2.fromScale(0.099, math.clamp((#teammates * 42 + 8) / 1080, 0.05, 0.5)),  -- scale based on content
		BackgroundTransparency = 1,
		BorderSizePixel  = 0,
	}, rows)
end

return TeammateVitals
