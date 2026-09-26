--[[
    UI/CharacterCreation.lua
    ──────────────────────────────────────────────────────────
    React component shown to new players at first login.
    Driven by the server event "CharacterCreationRequired".
    On confirm it fires "CharacterCreationComplete" to the server.
    Dismisses itself when it receives "CharacterCreationSaved".

    §AGX/UI-P6: Theme v2 re-skin. Not closable (Registry closable=false), so
    it keeps its own non-dismissible surface instead of AppWindow (which
    always draws a ✕). The §AGX/UI-P2 phone layout and defaults are kept:
    two columns inside the safe area, capped at 620x440 design px, 48 px
    gender tiles, 64 px swatches, Confirm pinned to the bottom. Now in design
    px under UIScaleRoot.Local. Selected state = navy650 fill + blue focus
    ring + primary text (+ ✓ on gender) (was blue fill + white text, 1.7:1).

    Props:
        onDismiss  function()  -- called after the server confirms the save
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")
local React        = require(ReplicatedStorage.Packages.React)
local NetworkManager = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("NetworkManager"))

-- §AGX/UI-P6: Theme roles + shared components (the palette table is gone).
local Common      = script.Parent:WaitForChild("Common")
local Theme       = require(Common:WaitForChild("Theme"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local Text        = require(Common:WaitForChild("Text"))
local Button      = require(Common:WaitForChild("Button"))
local Card        = require(Common:WaitForChild("Card"))
local Panel       = require(Common:WaitForChild("Panel"))

local e  = React.createElement
local R  = Theme.Roles

-- §AGX/UI-P2: M12 — touch-size tokens, now DESIGN px (§AGX/UI-P6).
local TOUCH_H    = Theme.Metrics.button.md   -- 48
local SWATCH     = 64   -- grid cell (>= 48 px, room for a 12 px name)
local GAP        = Theme.Space.sm            -- 8
local PAD        = Theme.Space.md            -- 12
local TITLE_H    = 28
local LABEL_H    = 18
local ERROR_H    = 18
local PANEL_MAX  = Vector2.new(620, 440)

-- ── Skin color definitions (must mirror CharacterConfig.SkinColors) ──
-- These are character data (the avatar's skin), not UI colours.
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

	-- §AGX/UI-P2: M12 — size comes from the parent UIGridLayout CellSize.
	-- §AGX/UI-P6: selected = Card-style selection (navy650 + focus ring),
	-- label text.primary on navy650 (>= 12:1); unselected text.secondary.
	return e("TextButton", {
		Name             = entry.id,
		LayoutOrder      = props.order,
		BackgroundColor3 = isSelected and Theme.Palette.navy650 or R.surface.raised,
		Text             = "",
		BorderSizePixel  = 0,
		AutoButtonColor  = false,
		[React.Event.Activated] = function()
			props.onSelect(entry.id)
		end,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
		stroke = e("UIStroke", {
			Color           = isSelected and R.border.focus or R.border.subtle,
			Thickness       = isSelected and Theme.Stroke.focus or Theme.Stroke.hair,
			Transparency    = isSelected and 0 or 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		swatch = e("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0),
			Position         = UDim2.new(0.5, 0, 0, 6),
			Size             = UDim2.fromOffset(30, 30),
			BackgroundColor3 = entry.color,
			BorderSizePixel  = 0,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
		}),
		label = e(Text, {
			style    = "caption",
			text     = entry.name,
			align    = "center",
			color    = isSelected and "text.primary" or "text.secondary",
			position = UDim2.new(0, 2, 1, -22),
			size     = UDim2.new(1, -4, 0, 18),
		}),
	})
end

local function GenderButton(props)
	local label = props.gender == "Male" and "\226\153\130  Male" or "\226\153\128  Female"
	local isSelected = props.gender == props.selected
	-- §AGX/UI-P2: M12 — half the column wide and >= 48 px tall.
	-- §AGX/UI-P6: a tappable Card (selected = focus ring), fixed 48 px row.
	return e("Frame", {
		Name                   = props.gender,
		Size                   = UDim2.new(0.5, -GAP / 2, 0, TOUCH_H),
		Position               = props.position,
		BackgroundTransparency = 1,
	}, {
		card = e(Card, {
			title       = (isSelected and (Theme.Glyphs.check .. " ") or "") .. label,
			selected    = isSelected,
			size        = UDim2.fromScale(1, 1),
			onActivated = function()
				props.onSelect(props.gender)
			end,
		}),
	})
end

-- ── Main component ─────────────────────────────────────────

local function CharacterCreation(props)
	local scale = UIScaleRoot.useUIScale()

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
		layout = e("UIGridLayout", {
			CellSize                = UDim2.fromOffset(SWATCH, SWATCH),
			CellPadding             = UDim2.fromOffset(GAP, GAP),
			FillDirection           = Enum.FillDirection.Horizontal,
			HorizontalAlignment     = Enum.HorizontalAlignment.Left,
			SortOrder               = Enum.SortOrder.LayoutOrder,
		}),
		-- §AGX/UI-P2: keep cells clear of the scrollbar (and the focus ring).
		pad = e("UIPadding", {
			PaddingRight  = UDim.new(0, 10),
			PaddingTop    = UDim.new(0, 3),
			PaddingLeft   = UDim.new(0, 3),
			PaddingBottom = UDim.new(0, 3),
		}),
	}
	for i, entry in ipairs(SKIN_COLORS) do
		skinSwatches["skin_" .. entry.id] = e(SkinColorSwatch, {
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
	-- §AGX/UI-P6: the inset is SCREEN px; convert to this layer's design px.
	local insetTop = 0
	local okInset, topLeft = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if okInset and typeof(topLeft) == "Vector2" then
		insetTop = UIScaleRoot.toLocal(topLeft.Y, scale.target)
	end

	-- §AGX/UI-P2: M12 layout (landscape, D4). Two columns inside a panel
	-- that fills the safe area (capped by UISizeConstraint):
	--   title (full width)
	--   [ GENDER + two 48 px buttons ] | [ SKIN COLOR scroll grid ]
	--   error line (full width)
	--   Confirm, 48 px, anchored to the panel bottom
	-- The body region stops above the error/Confirm strip, so the swatch
	-- scroll can never overlap Confirm.
	local bottomStrip = ERROR_H + GAP + TOUCH_H
	local bodyTop     = TITLE_H + GAP
	local z           = Theme.Z.window

	return e(UIScaleRoot.Local, { name = "CharacterCreation", zIndex = z }, {
		overlay = e("Frame", {
			Name                   = "CharacterCreationOverlay",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = R.surface.scrim,
			BackgroundTransparency = Theme.Elevation.overlay.scrim,
			BorderSizePixel        = 0,
			Active                 = true,  -- §AGX/UI-P2: swallow taps behind the modal
			ZIndex                 = z,
		}, {
			safePad = e("UIPadding", {
				PaddingTop    = UDim.new(0, insetTop + GAP),
				PaddingBottom = UDim.new(0, GAP),
				PaddingLeft   = UDim.new(0, PAD),
				PaddingRight  = UDim.new(0, PAD),
			}),

			panel = e(Panel, {
				name        = "Panel",
				elevation   = "flat",
				radius      = "lg",
				padding     = 0,
				stroke      = false,
				size        = UDim2.fromScale(1, 1),
				position    = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
				zIndex      = z + 1,
			}, {
				-- §AGX/UI-P2: fills the safe area on phones, capped on PC/tablet.
				sizeCap = e("UISizeConstraint", { MinSize = Vector2.new(0, 0), MaxSize = PANEL_MAX }),
				-- identity hairline (same as the AppWindow frame)
				frame = e("UIStroke", {
					Color = R.border.identity, Thickness = Theme.Stroke.base, Transparency = 0.55,
				}),
				pad = e("UIPadding", {
					PaddingTop    = UDim.new(0, PAD),
					PaddingBottom = UDim.new(0, PAD),
					PaddingLeft   = UDim.new(0, PAD + 4),
					PaddingRight  = UDim.new(0, PAD + 4),
				}),

				-- Title
				title = e(Text, {
					style = "title",
					text  = "Choose Your Character",
					align = "center",
					size  = UDim2.new(1, 0, 0, TITLE_H),
				}),

				-- Left column: gender
				genderCol = e("Frame", {
					Name                   = "GenderColumn",
					Size                   = UDim2.new(0.42, -GAP, 1, -(bodyTop + bottomStrip + GAP)),
					Position               = UDim2.fromOffset(0, bodyTop),
					BackgroundTransparency = 1,
				}, {
					genderLabel = e(Text, {
						style = "caption", text = "GENDER", color = "text.secondary",
						size  = UDim2.new(1, 0, 0, LABEL_H),
					}),
					genderMale = e(GenderButton, {
						gender   = "Male",
						selected = selectedGender,
						position = UDim2.fromOffset(0, LABEL_H + 4),
						onSelect = function(g) setGender(g) setError(nil) end,
					}),
					genderFemale = e(GenderButton, {
						gender   = "Female",
						selected = selectedGender,
						position = UDim2.new(0.5, GAP / 2, 0, LABEL_H + 4),
						onSelect = function(g) setGender(g) setError(nil) end,
					}),
				}),

				-- Right column: skin color
				skinCol = e("Frame", {
					Name                   = "SkinColumn",
					AnchorPoint            = Vector2.new(1, 0),
					Size                   = UDim2.new(0.58, 0, 1, -(bodyTop + bottomStrip + GAP)),
					Position               = UDim2.new(1, 0, 0, bodyTop),
					BackgroundTransparency = 1,
				}, {
					skinLabel = e(Text, {
						style = "caption", text = "SKIN COLOR", color = "text.secondary",
						size  = UDim2.new(1, 0, 0, LABEL_H),
					}),
					skinContainer = e("ScrollingFrame", {
						Name                    = "SkinColors",
						Size                    = UDim2.new(1, 0, 1, -(LABEL_H + 4)),
						Position                = UDim2.fromOffset(0, LABEL_H + 4),
						BackgroundTransparency  = 1,
						BorderSizePixel         = 0,
						ScrollBarThickness      = Theme.Metrics.scrollBar,
						ScrollBarImageColor3    = R.text.secondary,
						CanvasSize              = UDim2.new(0, 0, 0, 0),
						AutomaticCanvasSize     = Enum.AutomaticSize.Y,
						ScrollingDirection      = Enum.ScrollingDirection.Y,
						ElasticBehavior         = Enum.ElasticBehavior.WhenScrollable,
						ClipsDescendants        = true,
					}, skinSwatches),
				}),

				-- Error message (slot always reserved so the layout never shifts)
				errorLabel = errorMsg and e(Text, {
					style       = "body",
					text        = errorMsg,
					color       = "state.danger",
					align       = "center",
					anchorPoint = Vector2.new(0.5, 1),
					position    = UDim2.new(0.5, 0, 1, -(TOUCH_H + GAP)),
					size        = UDim2.new(1, 0, 0, ERROR_H),
				}) or nil,

				-- Confirm — §AGX/UI-P2: 48 px tall, anchored to the bottom.
				-- §AGX/UI-P6: the screen's one primary (orange) CTA.
				confirm = e(Button, {
					name        = "Confirm",
					variant     = "primary",
					size        = "md",
					label       = "Confirm",
					width       = UDim.new(0.5, 0),
					anchorPoint = Vector2.new(0.5, 1),
					position    = UDim2.fromScale(0.5, 1),
					onActivated = handleConfirm,
				}),
			}),
		}),
	})
end

return CharacterCreation
