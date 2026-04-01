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

-- ── Skin color definitions (must mirror CharacterConfig.SkinColors) ──
local SKIN_COLORS = {
	{ id = "skin_fair",      name = "Fair",      color = Color3.fromRGB(234, 184, 146) },
	{ id = "skin_pale",      name = "Pale",      color = Color3.fromRGB(255, 220, 200) },
	{ id = "skin_tan",       name = "Tan",       color = Color3.fromRGB(210, 160, 110) },
	{ id = "skin_brown",     name = "Brown",     color = Color3.fromRGB(160, 105,  70) },
	{ id = "skin_dark",      name = "Dark",      color = Color3.fromRGB(100,  65,  45) },
	{ id = "skin_lavender",  name = "Lavender",  color = Color3.fromRGB(180, 155, 210) },
	{ id = "skin_violet",    name = "Violet",    color = Color3.fromRGB(145, 110, 185) },
	{ id = "skin_cyan",      name = "Cyan",      color = Color3.fromRGB(130, 200, 210) },
	{ id = "skin_mint",      name = "Mint",      color = Color3.fromRGB(150, 210, 175) },
	{ id = "skin_rose",      name = "Rose",      color = Color3.fromRGB(210, 150, 160) },
	{ id = "skin_ash",       name = "Ash",       color = Color3.fromRGB(155, 155, 165) },
	{ id = "skin_gold",      name = "Gold",      color = Color3.fromRGB(210, 185, 130) },
}

-- ── Sub-components ─────────────────────────────────────────

local function SkinColorSwatch(props)
	local entry      = props.entry
	local isSelected = entry.id == props.selected

	return React.createElement("TextButton", {
		Name             = entry.id,
		Size             = UDim2.fromScale(0.031, 0.056),
		BackgroundColor3 = isSelected and C.Selected or C.Card,
		Text             = "",
		BorderSizePixel  = 0,
		AutoButtonColor  = false,
		ZIndex           = 3,
		[React.Event.Activated] = function()
			props.onSelect(entry.id)
		end,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
		swatch = React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0),
			Position         = UDim2.new(0.5, 0, 0, 5),
			Size             = UDim2.fromScale(0.017, 0.030),
			BackgroundColor3 = entry.color,
			BorderSizePixel  = 0,
			ZIndex           = 4,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}),
		label = React.createElement("TextLabel", {
			Size                = UDim2.new(1, -4, 0, 16),
			Position            = UDim2.new(0, 2, 1, -20),
			BackgroundTransparency = 1,
			Text                = entry.name,
			TextColor3          = isSelected and C.Text or C.SubText,
			TextScaled          = true,
			Font                = Enum.Font.GothamBold,
			ZIndex              = 4,
		}),
	})
end

local function GenderButton(props)
	local label = props.gender == "Male" and "\226\153\130  Male" or "\226\153\128  Female"
	local isSelected = props.gender == props.selected
	return React.createElement("TextButton", {
		Name             = props.gender,
		Size             = UDim2.fromScale(0.109, 0.041),
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

-- ── Main component ─────────────────────────────────────────

local function CharacterCreation(props)
	local selectedGender,    setGender    = React.useState(nil)
	local selectedSkinColor, setSkinColor = React.useState(nil)
	local errorMsg,          setError     = React.useState(nil)

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
		if not selectedSkinColor then
			setError("Please choose a skin color.")
			return
		end
		setError(nil)
		NetworkManager.FireServer("CharacterCreationComplete", {
			gender    = selectedGender,
			preset    = 1,
			skinColor = selectedSkinColor,
		})
	end

	-- Build skin color swatch grid
	local skinSwatches = { layout = React.createElement("UIGridLayout", {
		CellSize                = UDim2.new(0, 60, 0, 60),
		CellPadding             = UDim2.new(0, 8, 0, 8),
		FillDirection           = Enum.FillDirection.Horizontal,
		HorizontalAlignment     = Enum.HorizontalAlignment.Left,
		SortOrder               = Enum.SortOrder.LayoutOrder,
	}) }
	for i, entry in ipairs(SKIN_COLORS) do
		skinSwatches["skin_" .. entry.id] = React.createElement(SkinColorSwatch, {
			entry    = entry,
			selected = selectedSkinColor,
			onSelect = function(id)
				setSkinColor(id)
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
			Size             = UDim2.fromScale(0.25, 0.389),
			Position         = UDim2.fromScale(0.5, 0.5),
			AnchorPoint      = Vector2.new(0.5, 0.5),
			BackgroundColor3 = C.Panel,
			BorderSizePixel  = 0,
			ZIndex           = 11,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 16) }),

			-- Title
			title = React.createElement("TextLabel", {
				Size                = UDim2.new(1, -40, 0, 40),
				Position            = UDim2.fromScale(0, 0.038),
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
				Position            = UDim2.fromScale(0, 0.162),
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
				position = UDim2.fromScale(0, 0.229),
				onSelect = function(g) setGender(g) setError(nil) end,
			}),
			genderFemale = React.createElement(GenderButton, {
				gender   = "Female",
				selected = selectedGender,
				position = UDim2.fromScale(0.5, 0.229),
				onSelect = function(g) setGender(g) setError(nil) end,
			}),

			-- Skin color section
			skinLabel = React.createElement("TextLabel", {
				Size                = UDim2.new(1, -40, 0, 20),
				Position            = UDim2.fromScale(0, 0.381),
				BackgroundTransparency = 1,
				Text                = "SKIN COLOR",
				TextColor3          = C.SubText,
				TextXAlignment      = Enum.TextXAlignment.Left,
				TextScaled          = true,
				Font                = Enum.Font.Gotham,
				ZIndex              = 12,
			}),
			skinContainer = React.createElement("ScrollingFrame", {
				Name                    = "SkinColors",
				Size                    = UDim2.fromScale(0.917, 0.333),
				Position                = UDim2.fromScale(0, 0.448),
				BackgroundTransparency  = 1,
				ScrollBarThickness      = 4,
				CanvasSize              = UDim2.new(0, 0, 0, 0),
				AutomaticCanvasSize     = Enum.AutomaticSize.Y,
				ScrollingDirection      = Enum.ScrollingDirection.Y,
				ZIndex                  = 12,
			}, skinSwatches),

			-- Error message
			errorLabel = errorMsg and React.createElement("TextLabel", {
				Size                = UDim2.new(1, -40, 0, 20),
				Position            = UDim2.fromScale(0, 0.81),
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
				Size             = UDim2.fromScale(0.417, 0.105),
				Position         = UDim2.new(0.5, 0, 1, -58),
				AnchorPoint      = Vector2.new(0.5, 0),
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
