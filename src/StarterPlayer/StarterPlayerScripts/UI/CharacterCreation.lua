--[[
    UI/CharacterCreation.lua
    ──────────────────────────────────────────────────────────
    React component shown to new players at first login.
    Driven by the server event "CharacterCreationRequired".
    On confirm it fires "CharacterCreationComplete" to the server.
    Dismisses itself when it receives "CharacterCreationSaved".

    Props:
        onDismiss  function()  -- called after the server confirms the save
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React        = require(ReplicatedStorage.Packages.React)
local NetworkManager = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("NetworkManager"))

-- ── Palette ───────────────────────────────────────────────
local C = {
	Overlay  = Color3.new(0, 0, 0),
	Panel    = Color3.fromRGB( 20,  20,  30),
	Card     = Color3.fromRGB( 30,  30,  45),
	Selected = Color3.fromRGB( 60, 200, 120),
	Confirm  = Color3.fromRGB( 80, 200, 120),
	Text     = Color3.fromRGB(230, 230, 240),
	SubText  = Color3.fromRGB(160, 160, 180),
	Error    = Color3.fromRGB(255, 100, 100),
}

-- ── Preset definitions ─────────────────────────────────────
local PRESETS = {
	{ id = 1, name = "Athletic", description = "Lean and agile." },
	{ id = 2, name = "Balanced", description = "Reliable all-rounder." },
	{ id = 3, name = "Brawny",   description = "Built to endure." },
}

-- ── Sub-components ─────────────────────────────────────────

local function GenderButton(props)
	local label = props.gender == "Male" and "\226\153\130  Male" or "\226\153\128  Female"
	local isSelected = props.gender == props.selected
	return React.createElement("TextButton", {
		Name             = props.gender,
		Size             = UDim2.new(0, 210, 0, 44),
		Position         = props.position,
		BackgroundColor3 = isSelected and C.Selected or C.Card,
		Text             = label,
		TextColor3       = C.Text,
		TextScaled       = true,
		Font             = Enum.Font.GothamBold,
		BorderSizePixel  = 0,
		AutoButtonColor  = false,
		ZIndex           = 3,
		[React.Event.Activated] = function()
			props.onSelect(props.gender)
		end,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
	})
end

local function PresetCard(props)
	local preset     = props.preset
	local isSelected = preset.id == props.selected
	local cardW      = 140   -- (440 - 2*10) / 3 = 140
	local xOff       = (preset.id - 1) * (cardW + 10)

	return React.createElement("TextButton", {
		Name             = "Preset" .. preset.id,
		Size             = UDim2.new(0, cardW, 1, 0),
		Position         = UDim2.new(0, xOff, 0, 0),
		BackgroundColor3 = isSelected and C.Selected or C.Card,
		Text             = "",
		BorderSizePixel  = 0,
		AutoButtonColor  = false,
		ZIndex           = 3,
		[React.Event.Activated] = function()
			props.onSelect(preset.id)
		end,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
		name   = React.createElement("TextLabel", {
			Size                = UDim2.new(1, -8, 0, 28),
			Position            = UDim2.new(0, 4, 0, 6),
			BackgroundTransparency = 1,
			Text                = preset.name,
			TextColor3          = C.Text,
			TextScaled          = true,
			Font                = Enum.Font.GothamBold,
			ZIndex              = 4,
		}),
		desc   = React.createElement("TextLabel", {
			Size                = UDim2.new(1, -8, 0, 36),
			Position            = UDim2.new(0, 4, 0, 36),
			BackgroundTransparency = 1,
			Text                = preset.description,
			TextColor3          = isSelected and C.Text or C.SubText,
			TextWrapped         = true,
			TextScaled          = false,
			TextSize            = 12,
			Font                = Enum.Font.Gotham,
			ZIndex              = 4,
		}),
	})
end

-- ── Main component ─────────────────────────────────────────

local function CharacterCreation(props)
	local selectedGender, setGender = React.useState(nil)
	local selectedPreset, setPreset = React.useState(nil)
	local errorMsg,        setError  = React.useState(nil)

	-- Dismiss when server confirms the save
	React.useEffect(function()
		local conn = NetworkManager.OnServerEvent("CharacterCreationSaved", function()
			if props.onDismiss then
				props.onDismiss()
			end
		end)
		return function()
			if conn then conn:Disconnect() end
		end
	end, {})

	local function handleConfirm()
		if not selectedGender then
			setError("Please choose a gender first.")
			return
		end
		if not selectedPreset then
			setError("Please choose a body type.")
			return
		end
		setError(nil)
		NetworkManager.FireServer("CharacterCreationComplete", {
			gender = selectedGender,
			preset = selectedPreset,
		})
	end

	-- Build preset card children
	local presetCards = { layout = React.createElement("UIListLayout", {
		FillDirection       = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding             = UDim.new(0, 10),
	}) }
	for _, preset in ipairs(PRESETS) do
		presetCards["preset" .. preset.id] = React.createElement(PresetCard, {
			preset   = preset,
			selected = selectedPreset,
			onSelect = function(id)
				setPreset(id)
				setError(nil)
			end,
		})
	end

	return React.createElement("Frame", {
		Name                = "CharacterCreationOverlay",
		Size                = UDim2.fromScale(1, 1),
		BackgroundColor3    = C.Overlay,
		BackgroundTransparency = 0.35,
		ZIndex              = 10,
	}, {
		panel = React.createElement("Frame", {
			Name             = "Panel",
			Size             = UDim2.new(0, 480, 0, 380),
			Position         = UDim2.new(0.5, -240, 0.5, -190),
			BackgroundColor3 = C.Panel,
			BorderSizePixel  = 0,
			ZIndex           = 11,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 16) }),

			-- Title
			title = React.createElement("TextLabel", {
				Size                = UDim2.new(1, -40, 0, 40),
				Position            = UDim2.new(0, 20, 0, 16),
				BackgroundTransparency = 1,
				Text                = "Choose Your Character",
				TextColor3          = C.Text,
				TextScaled          = true,
				Font                = Enum.Font.GothamBold,
				ZIndex              = 12,
			}),

			-- Gender section
			genderLabel = React.createElement("TextLabel", {
				Size                = UDim2.new(1, -40, 0, 20),
				Position            = UDim2.new(0, 20, 0, 68),
				BackgroundTransparency = 1,
				Text                = "GENDER",
				TextColor3          = C.SubText,
				TextXAlignment      = Enum.TextXAlignment.Left,
				TextScaled          = true,
				Font                = Enum.Font.Gotham,
				ZIndex              = 12,
			}),
			genderMale = React.createElement(GenderButton, {
				gender   = "Male",
				selected = selectedGender,
				position = UDim2.new(0, 20, 0, 96),
				onSelect = function(g) setGender(g) setError(nil) end,
			}),
			genderFemale = React.createElement(GenderButton, {
				gender   = "Female",
				selected = selectedGender,
				position = UDim2.new(0, 250, 0, 96),
				onSelect = function(g) setGender(g) setError(nil) end,
			}),

			-- Body type section
			bodyLabel = React.createElement("TextLabel", {
				Size                = UDim2.new(1, -40, 0, 20),
				Position            = UDim2.new(0, 20, 0, 160),
				BackgroundTransparency = 1,
				Text                = "BODY TYPE",
				TextColor3          = C.SubText,
				TextXAlignment      = Enum.TextXAlignment.Left,
				TextScaled          = true,
				Font                = Enum.Font.Gotham,
				ZIndex              = 12,
			}),
			presetsContainer = React.createElement("Frame", {
				Name                = "Presets",
				Size                = UDim2.new(0, 440, 0, 80),
				Position            = UDim2.new(0, 20, 0, 188),
				BackgroundTransparency = 1,
				ZIndex              = 12,
			}, presetCards),

			-- Error message (conditional)
			errorLabel = errorMsg and React.createElement("TextLabel", {
				Size                = UDim2.new(1, -40, 0, 20),
				Position            = UDim2.new(0, 20, 0, 288),
				BackgroundTransparency = 1,
				Text                = errorMsg,
				TextColor3          = C.Error,
				TextXAlignment      = Enum.TextXAlignment.Center,
				TextScaled          = true,
				Font                = Enum.Font.Gotham,
				ZIndex              = 12,
			}) or nil,

			-- Confirm button
			confirm = React.createElement("TextButton", {
				Name             = "Confirm",
				Size             = UDim2.new(0, 200, 0, 44),
				Position         = UDim2.new(0.5, -100, 1, -58),
				BackgroundColor3 = C.Confirm,
				Text             = "Confirm",
				TextColor3       = C.Text,
				TextScaled       = true,
				Font             = Enum.Font.GothamBold,
				BorderSizePixel  = 0,
				AutoButtonColor  = false,
				ZIndex           = 12,
				[React.Event.Activated] = handleConfirm,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
			}),
		}),
	})
end

return CharacterCreation
