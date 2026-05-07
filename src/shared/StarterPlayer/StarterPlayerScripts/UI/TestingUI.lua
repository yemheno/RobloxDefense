-- UI/TestingUI.lua
--[[
    Admin Testing Panel.
    Visible ONLY to the game creator (UserId == game.CreatorId).
    All requests are re-validated server-side — no trust given to the client.

    Features:
      • Reset all player data (level 1, zero currencies)
      • Set level directly
      • Add XP / Merits / Essence
      • Add bonus talent points
      • Force respawn
      • Max equipped weapon (T12 +15) for quick gear tests
      • Set gender (Male / Female) — re-applies template on respawn

    Network:
      Client → "AdminAction", actionName, ...args
      Server → "AdminActionResult", { ok=bool, message=string }
]]

local Players           = game:GetService("Players")
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local React             = require(ReplicatedStorage.Packages.React)

local Modules        = script.Parent.Parent:WaitForChild("Modules")
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

local player = Players.LocalPlayer

-- Show the panel if we are the game creator OR a listed developer OR in Studio.
-- (game.CreatorId returns 0 for unpublished games, so the Studio bypass is required.)
local ADMIN_IDS = {
	[4700259512] = true,  -- AstralitoCL (developer)
}
local function isAdmin()
	if player.UserId == game.CreatorId then return true end
	if ADMIN_IDS[player.UserId] then return true end
	return RunService:IsStudio()
end

-- ── Palette ─────────────────────────────────────────────────────────
local C = {
	bg         = Color3.fromRGB(14, 14, 20),
	panel      = Color3.fromRGB(22, 22, 32),
	section    = Color3.fromRGB(28, 28, 42),
	border     = Color3.fromRGB(60, 60, 90),
	btn        = Color3.fromRGB(55, 115, 200),
	btn_hover  = Color3.fromRGB(70, 140, 240),
	btn_danger = Color3.fromRGB(180, 50,  50),
	btn_green  = Color3.fromRGB(50,  150, 80),
	btn_gold   = Color3.fromRGB(200, 160, 40),
	toggle     = Color3.fromRGB(200, 150, 20),
	text       = Color3.fromRGB(220, 220, 230),
	text_dim   = Color3.fromRGB(140, 140, 160),
	text_ok    = Color3.fromRGB(90,  210, 130),
	text_err   = Color3.fromRGB(230, 100, 100),
	input_bg   = Color3.fromRGB(18,  18,  30),
	white      = Color3.fromRGB(255, 255, 255),
}

-- ── Helper: create a section header ─────────────────────────────────
-- §UI-T4: hardcoded heights (20-66 px) replaced with scale Y so the
-- whole panel breathes proportionally to viewport.
local function SectionHeader(lo, label)
	return React.createElement("TextLabel", {
		LayoutOrder      = lo,
		Size             = UDim2.fromScale(1, 0.04),
		BackgroundColor3 = C.section,
		BorderSizePixel  = 0,
		Text             = "  " .. label,
		TextColor3       = C.text_dim,
		TextScaled       = true,
		Font             = Enum.Font.GothamBold,
		TextXAlignment   = Enum.TextXAlignment.Left,
	})
end

-- ── Helper: a row with a label, text input, and action button ────────
-- Pure function -- state is managed by the parent (TestingUI).
-- §UI-T3 fix: InputRow used hardcoded pixel positions (122 px box offset,
-- 218 px button offset, 32 px row height) which collapsed at higher
-- resolutions. Switched to a scale-based 3-column flex layout so the
-- label / textbox / button stay legible on every viewport.
local function InputRow(lo, label, val, setVal, btnLabel, btnColor, action)
	return React.createElement("Frame", {
		LayoutOrder            = lo,
		Size                   = UDim2.fromScale(1, 0.06),
		BackgroundTransparency = 1,
	}, {
		lbl = React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0, 0.5),
			Position               = UDim2.fromScale(0, 0.5),
			Size                   = UDim2.fromScale(0.42, 0.85),
			BackgroundTransparency = 1,
			Text                   = label,
			TextColor3             = C.text,
			TextScaled             = true,
			Font                   = Enum.Font.Gotham,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}),
		box = React.createElement("TextBox", {
			AnchorPoint            = Vector2.new(0, 0.5),
			Position               = UDim2.fromScale(0.43, 0.5),
			Size                   = UDim2.fromScale(0.27, 0.85),
			BackgroundColor3       = C.input_bg,
			BorderSizePixel        = 1,
			BorderColor3           = C.border,
			Text                   = val,
			TextColor3             = C.white,
			TextScaled             = true,
			Font                   = Enum.Font.Code,
			ClearTextOnFocus       = false,
			[React.Event.Changed]  = function(rbx) setVal(rbx.Text) end,
		}, { React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }) }),
		btn = React.createElement("TextButton", {
			AnchorPoint            = Vector2.new(0, 0.5),
			Position               = UDim2.fromScale(0.72, 0.5),
			Size                   = UDim2.fromScale(0.27, 0.85),
			BackgroundColor3       = btnColor,
			BorderSizePixel        = 0,
			Text                   = btnLabel,
			TextColor3             = C.white,
			TextScaled             = true,
			Font                   = Enum.Font.GothamBold,
			AutoButtonColor        = true,
			[React.Event.Activated] = function() action(val) end,
		}, { React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }) }),
	})
end

-- ── Helper: a simple action button ──────────────────────────────────
-- §UI-T1 fix: was 0.073 × 0.026 (= ~140 × 28 px on 1080p), too small
-- to click reliably. Now scale-relative to its parent ROW so the
-- button fills the row height vertically. The legacy `w` arg is a
-- pixel hint (140, 155, 180, …) — convert it to a scale fraction of
-- the row width (the panel is ~420 px wide on 1080p, so divide by 420
-- to map "pixels at 1080p" → row-width scale).
local function ActionButton(label, color, onActivated, w)
	local scaleWidth = math.clamp((w or 140) / 420, 0.15, 1)
	return React.createElement("TextButton", {
		Size             = UDim2.fromScale(scaleWidth, 1),
		BackgroundColor3 = color,
		BorderSizePixel  = 0,
		Text             = label,
		TextColor3       = C.white,
		TextScaled       = true,
		Font             = Enum.Font.GothamBold,
		AutoButtonColor  = true,
		[React.Event.Activated] = onActivated,
	}, { React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }) })
end

-- ── Main Component ────────────────────────────────────────────────────
local function TestingUI()
	-- All hooks must run unconditionally (React rules).
	-- We gate the returned JSX after hooks using isAdmin().
	local open,       setOpen       = React.useState(false)
	local feedback,   setFeedback   = React.useState("Ready.")
	local feedbackOk, setFeedbackOk = React.useState(true)

	-- Input field values (all managed here; InputRow is a pure helper)
	local levelVal,   setLevelVal   = React.useState("100")
	local xpVal,      setXpVal      = React.useState("1000")
	local meritsVal,  setMeritsVal  = React.useState("5000")
	local essenceVal, setEssenceVal = React.useState("100")
	local talentVal,  setTalentVal  = React.useState("20")

	-- Subscribe to server responses
	React.useEffect(function()
		local conn = NetworkManager.OnServerEvent("AdminActionResult", function(data)
			setFeedbackOk(data.ok == true)
			setFeedback(data.message or (data.ok and "OK" or "Error"))
		end)
		return function()
			if conn then conn:Disconnect() end
		end
	end, {})

	local function fire(action, ...)
		NetworkManager.FireServer("AdminAction", action, ...)
	end

	local feedbackColor = feedbackOk and C.text_ok or C.text_err
	local topLeftInset = select(1, GuiService:GetGuiInset())
	local safeLeft = topLeftInset.X + 8
	local safeTop = topLeftInset.Y + 8

	-- Non-admin players: render nothing (all hooks above have already run)
	if not isAdmin() then return nil end

	return React.createElement("Frame", {
		Name                   = "TestingUI",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = 100,
	}, {
		-- Toggle button — offset right of Roblox's default top-left system buttons.
		-- §UI-T2 fix: was 4.6% × 2.4% (≈ 88 × 26 px on 1080p), unclickable
		-- at higher resolutions. Bumped to 8% × 4.5% pure-scale.
		toggleBtn = React.createElement("TextButton", {
			Size             = UDim2.fromScale(0.08, 0.045),
			Position         = UDim2.fromScale(0.12, 0.005),
			BackgroundColor3 = open and C.btn_danger or C.toggle,
			BorderSizePixel  = 0,
			Text             = open and "✕ CLOSE" or "⚙ TESTING",
			TextColor3       = C.bg,
			TextScaled       = true,
			Font             = Enum.Font.GothamBold,
			ZIndex           = 101,
			AutoButtonColor  = true,
			[React.Event.Activated] = function()
				setOpen(not open)
			end,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
		}),

		-- Panel (shown when open). §UI-T2: pure-scale position so the panel
		-- tracks the toggleBtn instead of using GuiInset+pixel offsets.
		panel = open and React.createElement("ScrollingFrame", {
			Size               = UDim2.fromScale(0.22, 0.78),
			Position           = UDim2.fromScale(0.12, 0.06),
			BackgroundColor3   = C.panel,
			BorderSizePixel    = 1,
			BorderColor3       = C.border,
			ScrollBarThickness = 4,
			CanvasSize         = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ZIndex             = 102,
		}, {
			corner  = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
			padding = React.createElement("UIPadding", {
				PaddingTop    = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
				PaddingLeft   = UDim.new(0, 10),
				PaddingRight  = UDim.new(0, 10),
			}),
			layout = React.createElement("UIListLayout", {
				FillDirection       = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				SortOrder           = Enum.SortOrder.LayoutOrder,
				Padding             = UDim.new(0, 4),
			}),

			-- Title
			title = React.createElement("TextLabel", {
				LayoutOrder            = 1,
				Size                   = UDim2.fromScale(1, 0.05),
				BackgroundTransparency = 1,
				Text                   = "⚙  ADMIN TESTING PANEL",
				TextColor3             = C.toggle,
				TextScaled             = true,
				Font                   = Enum.Font.GothamBold,
				TextXAlignment         = Enum.TextXAlignment.Left,
			}),

			divider1 = React.createElement("Frame", {
				LayoutOrder      = 2,
				Size             = UDim2.fromScale(1, 0.005),
				BackgroundColor3 = C.border,
				BorderSizePixel  = 0,
			}),

			feedbackLabel = React.createElement("TextLabel", {
				LayoutOrder            = 3,
				Size                   = UDim2.fromScale(1, 0.04),
				BackgroundTransparency = 1,
				Text                   = "► " .. feedback,
				TextColor3             = feedbackColor,
				TextScaled             = true,
				Font                   = Enum.Font.Code,
				TextXAlignment         = Enum.TextXAlignment.Left,
				TextTruncate           = Enum.TextTruncate.AtEnd,
			}),

			-- ── DATA MANAGEMENT ──────────────────────────────────────
			secData = SectionHeader(4, "─── DATA MANAGEMENT ───"),

			resetRow = React.createElement("Frame", {
				LayoutOrder            = 5,
				Size                   = UDim2.fromScale(1, 0.06),
				BackgroundTransparency = 1,
			}, {
				btn  = ActionButton("⚠ Reset All Data", C.btn_danger, function() fire("ResetData") end, 155),
				note = React.createElement("TextLabel", {
					AnchorPoint            = Vector2.new(0, 0.5),
					Position               = UDim2.fromScale(0.40, 0.5),
					Size                   = UDim2.fromScale(0.58, 0.85),
					BackgroundTransparency = 1,
					Text                   = "Level 1 · 0 Merits · 0 Essence",
					TextColor3             = C.text_dim,
					TextScaled             = true,
					Font                   = Enum.Font.Gotham,
					TextXAlignment         = Enum.TextXAlignment.Left,
				}),
			}),

			-- Wipe ALL saved DataStore data then kick — player rejoins as brand new
			wipeRow = React.createElement("Frame", {
				LayoutOrder            = 5,  -- same section
				Size                   = UDim2.fromScale(1, 0.06),
				BackgroundTransparency = 1,
			}, {
				btn  = ActionButton("🗑 Wipe Data + Kick", Color3.fromRGB(150, 30, 30), function() fire("WipeAndKick") end, 175),
				note = React.createElement("TextLabel", {
					AnchorPoint            = Vector2.new(0, 0.5),
					Position               = UDim2.fromScale(0.45, 0.5),
					Size                   = UDim2.fromScale(0.53, 0.85),
					BackgroundTransparency = 1,
					Text                   = "Full DataStore wipe · tests first-login",
					TextColor3             = C.text_dim,
					TextScaled             = true,
					Font                   = Enum.Font.Gotham,
					TextXAlignment         = Enum.TextXAlignment.Left,
				}),
			}),

			-- ── PROGRESSION ──────────────────────────────────────────
			secProg = SectionHeader(6, "─── PROGRESSION ───"),
			levelRow   = InputRow(7,  "Set Level",     levelVal,   setLevelVal,   "Set", C.btn,       function(v) fire("SetLevel", v) end),
			xpRow      = InputRow(8,  "Add XP",        xpVal,      setXpVal,      "Add", C.btn_green, function(v) fire("AddXP", v) end),

			-- ── CURRENCY ─────────────────────────────────────────────
			secCurr = SectionHeader(9, "─── CURRENCY ───"),
			meritsRow  = InputRow(10, "Add Merits",    meritsVal,  setMeritsVal,  "Add", C.btn_gold,             function(v) fire("AddMerits", v) end),
			essenceRow = InputRow(11, "Add Essence",   essenceVal, setEssenceVal, "Add", Color3.fromRGB(140, 80, 200), function(v) fire("AddEssence", v) end),

			-- ── TALENTS ──────────────────────────────────────────────
			secTal = SectionHeader(12, "─── TALENTS ───"),
			talentRow  = InputRow(13, "Talent Pts",    talentVal,  setTalentVal,  "Add", Color3.fromRGB(60, 160, 180), function(v) fire("AddTalentPts", v) end),

			-- ── MISC ─────────────────────────────────────────────────
			secMisc = SectionHeader(14, "─── MISC ───"),

			miscRow = React.createElement("Frame", {
				LayoutOrder            = 15,
				Size                   = UDim2.fromScale(1, 0.06),
				BackgroundTransparency = 1,
			}, {
				layout = React.createElement("UIListLayout", {
					FillDirection     = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding           = UDim.new(0.02, 0),
				}),
				respawn   = ActionButton("Respawn",    C.btn,      function() fire("Respawn")   end, 90),
				maxWeapon = ActionButton("Max Weapon", C.btn_gold, function() fire("MaxWeapon") end, 110),
				resetCDs  = ActionButton("Reset CDs",  C.btn_green, function() fire("ResetCooldowns") end, 100),
			}),

			-- ── CLASS ─────────────────────────────────────────────
			secClass = SectionHeader(16, "─── CLASS ───"),

			classRow = React.createElement("Frame", {
				LayoutOrder            = 17,
				Size                   = UDim2.fromScale(1, 0.12),  -- two-row class grid
				BackgroundTransparency = 1,
			}, {
				layout = React.createElement("UIListLayout", {
					FillDirection     = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding           = UDim.new(0.015, 0),
					Wraps             = true,
				}),
				aegis    = ActionButton("🛡 Aegis",    C.btn,                            function() fire("SetClass", "Aegis")    end, 80),
				arcanist = ActionButton("🔮 Arcanist", Color3.fromRGB(130, 70, 200),     function() fire("SetClass", "Arcanist") end, 90),
				hunter   = ActionButton("🏹 Hunter",   Color3.fromRGB(60, 170, 100),     function() fire("SetClass", "Hunter")   end, 84),
				steward  = ActionButton("🌿 Steward",  Color3.fromRGB(80, 200, 80),      function() fire("SetClass", "LifeSteward") end, 84),
			}),

			-- ── CHARACTER ────────────────────────────────────────────
			secChar = SectionHeader(18, "─── CHARACTER ───"),

			genderRow = React.createElement("Frame", {
				LayoutOrder            = 19,
				Size                   = UDim2.fromScale(1, 0.06),
				BackgroundTransparency = 1,
			}, {
				layout = React.createElement("UIListLayout", {
					FillDirection     = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding           = UDim.new(0.02, 0),
				}),
				maleBtn   = ActionButton("♂ Male",   C.btn,                           function() fire("SetGender", "Male")   end, 88),
				femaleBtn = ActionButton("♀ Female", Color3.fromRGB(200, 80, 140),    function() fire("SetGender", "Female") end, 100),
			}),

		}) or nil,
	})
end

return TestingUI
