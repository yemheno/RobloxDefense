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
-- §AGX/UI-P2: M12 — mapped onto the shared Theme tokens (minimal restyle;
-- the P3 re-skin replaces this whole panel).
local Theme = require(script.Parent:WaitForChild("Common"):WaitForChild("Theme"))
local T = Theme.Colors
local C = {
	Overlay  = T.dim,
	Panel    = T.panel,
	Card     = T.panelAlt,
	Selected = T.accent2,
	Confirm  = T.good,
	Text     = T.text,
	SubText  = T.textDim,
	Error    = T.bad,
}

-- §AGX/UI-P2: M12 — touch-size tokens (px). 48 = minimum touch target.
local TOUCH_H    = 48
local SWATCH     = 64   -- grid cell (>= 48 px, room for a 12 px name)
local GAP        = 8
local PAD        = 12
local TITLE_H    = 28
local LABEL_H    = 16
local ERROR_H    = 16
local MIN_TEXT   = 12

local GuiService = game:GetService("GuiService")

local function textSize(maxSize)
	return React.createElement("UITextSizeConstraint", {
		MinTextSize = MIN_TEXT,
		MaxTextSize = maxSize,
	})
end

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

	-- §AGX/UI-P2: M12 — size comes from the parent UIGridLayout CellSize
	-- (64x64 px). The old fromScale(0.031,0.056) resolved against the grid
	-- and was ignored anyway; children are now pixel-sized so they don't
	-- collapse on phones.
	return React.createElement("TextButton", {
		Name             = entry.id,
		LayoutOrder      = props.order,
		BackgroundColor3 = isSelected and C.Selected or C.Card,
		Text             = "",
		BorderSizePixel  = 0,
		AutoButtonColor  = false,
		ZIndex           = 13,
		[React.Event.Activated] = function()
			props.onSelect(entry.id)
		end,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
		stroke = isSelected and React.createElement("UIStroke", {
			Color     = C.Text,
			Thickness = 2,
		}) or nil,
		swatch = React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0),
			Position         = UDim2.new(0.5, 0, 0, 6),
			Size             = UDim2.fromOffset(30, 30),
			BackgroundColor3 = entry.color,
			BorderSizePixel  = 0,
			ZIndex           = 14,
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
			ZIndex              = 14,
		}, {
			tsc = textSize(14),
		}),
	})
end

local function GenderButton(props)
	local label = props.gender == "Male" and "\226\153\130  Male" or "\226\153\128  Female"
	local isSelected = props.gender == props.selected
	-- §AGX/UI-P2: M12 — was fromScale(0.109,0.041) of the panel = 23x6 px on
	-- iPhone. Now half the column wide and TOUCH_H (48 px) tall.
	return React.createElement("TextButton", {
		Name             = props.gender,
		Size             = UDim2.new(0.5, -GAP / 2, 0, TOUCH_H),
		Position         = props.position,
		BackgroundColor3 = isSelected and C.Selected or C.Card,
		Text             = label,
		TextColor3       = C.Text,
		TextScaled       = true,
		Font             = Enum.Font.GothamBold,
		BorderSizePixel  = 0,
		AutoButtonColor  = false,
		ZIndex           = 13,
		[React.Event.Activated] = function()
			props.onSelect(props.gender)
		end,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
		pad    = React.createElement("UIPadding", {
			PaddingTop    = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft   = UDim.new(0, 6),
			PaddingRight  = UDim.new(0, 6),
		}),
		tsc    = textSize(22),
		stroke = isSelected and React.createElement("UIStroke", {
			Color     = C.Text,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}) or nil,
	})
end

-- ── Main component ─────────────────────────────────────────

local function CharacterCreation(props)
	-- §AGX/UI-P2: M12 — defaults so Confirm works on the first tap (the
	-- "choose first" validation below is kept for safety).
	local selectedGender,    setGender    = React.useState("Male")
	local selectedSkinColor, setSkinColor = React.useState(SKIN_COLORS[1].id)
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
		-- Payload unchanged (server validates in CharacterManager).
		NetworkManager.FireServer("CharacterCreationComplete", {
			gender    = selectedGender,
			preset    = 1,
			skinColor = selectedSkinColor,
		})
	end

	-- Build skin color swatch grid
	local skinSwatches = {
		layout = React.createElement("UIGridLayout", {
			CellSize                = UDim2.fromOffset(SWATCH, SWATCH),
			CellPadding             = UDim2.fromOffset(GAP, GAP),
			FillDirection           = Enum.FillDirection.Horizontal,
			HorizontalAlignment     = Enum.HorizontalAlignment.Left,
			SortOrder               = Enum.SortOrder.LayoutOrder,
		}),
		-- §AGX/UI-P2: keep cells clear of the scrollbar.
		pad = React.createElement("UIPadding", {
			PaddingRight  = UDim.new(0, 10),
			PaddingTop    = UDim.new(0, 2),
			PaddingLeft   = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 2),
		}),
	}
	for i, entry in ipairs(SKIN_COLORS) do
		skinSwatches["skin_" .. entry.id] = React.createElement(SkinColorSwatch, {
			entry    = entry,
			order    = i,
			selected = selectedSkinColor,
			onSelect = function(id)
				setSkinColor(id)
				setError(nil)
			end,
		})
	end

	-- §AGX/UI-P2: M12 — keep the panel inside the safe area: the ScreenGuis
	-- use IgnoreGuiInset=true, so pad the top by the CoreGui topbar inset.
	local insetTop = 0
	local okInset, topLeft = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if okInset and typeof(topLeft) == "Vector2" then
		insetTop = topLeft.Y
	end

	-- §AGX/UI-P2: M12 layout (landscape, D4). Two columns inside a panel
	-- that fills the safe area (capped by UISizeConstraint):
	--   title (full width)
	--   [ GENDER + two 48 px buttons ] | [ SKIN COLOR scroll grid ]
	--   error line (full width)
	--   Confirm, 48 px, anchored to the panel bottom
	-- The body region stops above the error/Confirm strip, so the swatch
	-- scroll can never overlap Confirm (old bug: Confirm at 1,-58 sat inside
	-- the swatches).
	local bottomStrip = ERROR_H + GAP + TOUCH_H
	local bodyTop     = TITLE_H + GAP

	return React.createElement("Frame", {
		Name                = "CharacterCreationOverlay",
		Size                = UDim2.fromScale(1, 1),
		BackgroundColor3    = C.Overlay,
		BackgroundTransparency = 0.35,
		Active              = true,  -- §AGX/UI-P2: swallow taps behind the modal
		ZIndex              = 10,
	}, {
		safePad = React.createElement("UIPadding", {
			PaddingTop    = UDim.new(0, insetTop + GAP),
			PaddingBottom = UDim.new(0, GAP),
			PaddingLeft   = UDim.new(0, 12),
			PaddingRight  = UDim.new(0, 12),
		}),

		panel = React.createElement("Frame", {
			Name             = "Panel",
			Size             = UDim2.fromScale(1, 1),
			Position         = UDim2.fromScale(0.5, 0.5),
			AnchorPoint      = Vector2.new(0.5, 0.5),
			BackgroundColor3 = C.Panel,
			BorderSizePixel  = 0,
			ZIndex           = 11,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 16) }),
			-- §AGX/UI-P2: fills the safe area on phones, capped on PC/tablet.
			sizeCap = React.createElement("UISizeConstraint", {
				MinSize = Vector2.new(0, 0),
				MaxSize = Vector2.new(620, 440),
			}),
			pad = React.createElement("UIPadding", {
				PaddingTop    = UDim.new(0, PAD),
				PaddingBottom = UDim.new(0, PAD),
				PaddingLeft   = UDim.new(0, PAD + 4),
				PaddingRight  = UDim.new(0, PAD + 4),
			}),

			-- Title
			title = React.createElement("TextLabel", {
				Size                = UDim2.new(1, 0, 0, TITLE_H),
				Position            = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text                = "Choose Your Character",
				TextColor3          = C.Text,
				TextScaled          = true,
				Font                = Enum.Font.GothamBold,
				ZIndex              = 12,
			}, {
				tsc = textSize(26),
			}),

			-- Left column: gender
			genderCol = React.createElement("Frame", {
				Name                   = "GenderColumn",
				Size                   = UDim2.new(0.42, -GAP, 1, -(bodyTop + bottomStrip + GAP)),
				Position               = UDim2.fromOffset(0, bodyTop),
				BackgroundTransparency = 1,
				ZIndex                 = 12,
			}, {
				genderLabel = React.createElement("TextLabel", {
					Size                = UDim2.new(1, 0, 0, LABEL_H),
					BackgroundTransparency = 1,
					Text                = "GENDER",
					TextColor3          = C.SubText,
					TextXAlignment      = Enum.TextXAlignment.Left,
					TextScaled          = true,
					Font                = Enum.Font.Gotham,
					ZIndex              = 12,
				}, {
					tsc = textSize(16),
				}),
				genderMale = React.createElement(GenderButton, {
					gender   = "Male",
					selected = selectedGender,
					position = UDim2.fromOffset(0, LABEL_H + 4),
					onSelect = function(g) setGender(g) setError(nil) end,
				}),
				genderFemale = React.createElement(GenderButton, {
					gender   = "Female",
					selected = selectedGender,
					position = UDim2.new(0.5, GAP / 2, 0, LABEL_H + 4),
					onSelect = function(g) setGender(g) setError(nil) end,
				}),
			}),

			-- Right column: skin color
			skinCol = React.createElement("Frame", {
				Name                   = "SkinColumn",
				AnchorPoint            = Vector2.new(1, 0),
				Size                   = UDim2.new(0.58, 0, 1, -(bodyTop + bottomStrip + GAP)),
				Position               = UDim2.new(1, 0, 0, bodyTop),
				BackgroundTransparency = 1,
				ZIndex                 = 12,
			}, {
				skinLabel = React.createElement("TextLabel", {
					Size                = UDim2.new(1, 0, 0, LABEL_H),
					BackgroundTransparency = 1,
					Text                = "SKIN COLOR",
					TextColor3          = C.SubText,
					TextXAlignment      = Enum.TextXAlignment.Left,
					TextScaled          = true,
					Font                = Enum.Font.Gotham,
					ZIndex              = 12,
				}, {
					tsc = textSize(16),
				}),
				skinContainer = React.createElement("ScrollingFrame", {
					Name                    = "SkinColors",
					Size                    = UDim2.new(1, 0, 1, -(LABEL_H + 4)),
					Position                = UDim2.fromOffset(0, LABEL_H + 4),
					BackgroundTransparency  = 1,
					BorderSizePixel         = 0,
					ScrollBarThickness      = 6,
					CanvasSize              = UDim2.new(0, 0, 0, 0),
					AutomaticCanvasSize     = Enum.AutomaticSize.Y,
					ScrollingDirection      = Enum.ScrollingDirection.Y,
					ElasticBehavior         = Enum.ElasticBehavior.WhenScrollable,
					ClipsDescendants        = true,
					ZIndex                  = 12,
				}, skinSwatches),
			}),

			-- Error message (slot always reserved so the layout never shifts)
			errorLabel = errorMsg and React.createElement("TextLabel", {
				AnchorPoint         = Vector2.new(0.5, 1),
				Size                = UDim2.new(1, 0, 0, ERROR_H),
				Position            = UDim2.new(0.5, 0, 1, -(TOUCH_H + GAP)),
				BackgroundTransparency = 1,
				Text                = errorMsg,
				TextColor3          = C.Error,
				TextXAlignment      = Enum.TextXAlignment.Center,
				TextScaled          = true,
				Font                = Enum.Font.Gotham,
				ZIndex              = 12,
			}, {
				tsc = textSize(16),
			}) or nil,

			-- Confirm button — §AGX/UI-P2: 48 px tall, anchored to the bottom.
			confirm = React.createElement("TextButton", {
				Name             = "Confirm",
				AnchorPoint      = Vector2.new(0.5, 1),
				Size             = UDim2.new(0.5, 0, 0, TOUCH_H),
				Position         = UDim2.fromScale(0.5, 1),
				BackgroundColor3 = C.Confirm,
				Text             = "Confirm",
				TextColor3       = T.textOnAccent,
				TextScaled       = true,
				Font             = Enum.Font.GothamBold,
				BorderSizePixel  = 0,
				AutoButtonColor  = true,
				ZIndex           = 12,
				[React.Event.Activated] = handleConfirm,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
				minW   = React.createElement("UISizeConstraint", {
					MinSize = Vector2.new(160, TOUCH_H),
				}),
				pad    = React.createElement("UIPadding", {
					PaddingTop    = UDim.new(0, 10),
					PaddingBottom = UDim.new(0, 10),
				}),
				tsc    = textSize(24),
			}),
		}),
	})
end

return CharacterCreation
