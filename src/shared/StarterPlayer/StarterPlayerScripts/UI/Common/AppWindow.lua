-- UI/Common/AppWindow.lua
--[[
    AppWindow  (§T10/U3 — window standardization)
    =============================================
    THE two window types of the game. Every menu renders inside one of
    these; no menu draws its own backdrop/title/close chrome anymore.

      variant = "windowed"    dim backdrop + centered panel (default
                              0.88 × 0.82). Most menus.
      variant = "fullscreen"  fills the viewport. Big experiences
                              (Talent Tree, Character Creation).

    Shared chrome (the anime/speed identity):
      • slanted accent ribbon behind an UPPERCASE title
      • motion-line accents trailing the ribbon
      • optional icon slot (Theme.Icons) left of the title
      • `headerContent` slot on the right (counters, action buttons)
      • standard close button
      • body = your children, in a padded content frame below the header

    Usage:
        local AppWindow = require(script.Parent:WaitForChild("Common"):WaitForChild("AppWindow"))
        return React.createElement(AppWindow, {
            variant = "windowed",
            title   = Locale.Get("menu_classes_title"),
            icon    = "classes",           -- Theme.Icons key (optional)
            onClose = onClose,
            headerContent = element?,      -- optional right-side slot
            size    = UDim2.fromScale(0.88, 0.82),  -- windowed only
            zIndex  = 10,
        }, bodyChildrenTable)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors
local F = Theme.Fonts
local S = Theme.Speed

local HEADER_H = 0.085  -- header fraction of the window height

local function AppWindow(props)
	local variant = props.variant or "windowed"
	local zBase   = props.zIndex or 10
	local iconId  = props.icon and Theme.GetIcon(props.icon) or nil

	-- ── Header (shared chrome) ────────────────────────────────────────────────
	local motionLines = {}
	for i = 1, S.lineCount do
		motionLines["line" .. i] = React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0, 0.5),
			Position         = UDim2.fromScale(0.30 + i * 0.045, 0.35 + (i % 2) * 0.3),
			Size             = UDim2.fromScale(0.06 - i * 0.012, 0.06),
			BackgroundColor3 = C.accent,
			BackgroundTransparency = 0.25 + i * 0.2,
			BorderSizePixel  = 0,
			Rotation         = S.lineSlantDeg,
			ZIndex           = zBase + 3,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		})
	end

	local header = React.createElement("Frame", {
		Name                   = "Header",
		Size                   = UDim2.fromScale(1, HEADER_H),
		BackgroundColor3       = C.panelAlt,
		BorderSizePixel        = 0,
		ZIndex                 = zBase + 2,
	}, {
		-- Slanted speed ribbon behind the title
		ribbon = React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0, 0.5),
			Position         = UDim2.fromScale(-0.01, 0.5),
			Size             = UDim2.fromScale(0.30, 1.25),
			BackgroundColor3 = C.accent,
			BorderSizePixel  = 0,
			Rotation         = S.slantDeg,
			ZIndex           = zBase + 2,
		}, {
			grad = React.createElement("UIGradient", {
				Color = ColorSequence.new(C.accent, C.accent2),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 0.45),
				}),
			}),
		}),

		-- §T10/LIVE2: with RelativeYY, BOTH scale axes multiply the parent
		-- HEIGHT — the old X scales (0.032 / 0.05) produced slivers a few
		-- pixels wide. Square elements sized from height use equal scales.
		icon = iconId and React.createElement("ImageLabel", {
			AnchorPoint            = Vector2.new(0, 0.5),
			Position               = UDim2.fromScale(0.015, 0.5),
			Size                   = UDim2.fromScale(0.75, 0.75),
			SizeConstraint         = Enum.SizeConstraint.RelativeYY,
			BackgroundTransparency = 1,
			Image                  = iconId,
			ZIndex                 = zBase + 4,
		}) or nil,

		title = React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0, 0.5),
			Position               = UDim2.fromScale(iconId and 0.055 or 0.02, 0.5),
			Size                   = UDim2.fromScale(0.28, 0.75),
			BackgroundTransparency = 1,
			Text                   = string.upper(props.title or ""),
			TextColor3             = C.textOnAccent,
			Font                   = F.title,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
			ZIndex                 = zBase + 4,
		}),

		lines = React.createElement("Frame", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex                 = zBase + 3,
		}, motionLines),

		-- Right-side content slot (counters, action buttons)
		slot = props.headerContent and React.createElement("Frame", {
			AnchorPoint            = Vector2.new(1, 0.5),
			Position               = UDim2.fromScale(0.935, 0.5),
			Size                   = UDim2.fromScale(0.45, 0.8),
			BackgroundTransparency = 1,
			ZIndex                 = zBase + 4,
		}, { content = props.headerContent }) or nil,

		close = React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0.5),
			Position         = UDim2.fromScale(0.99, 0.5),
			-- §T10/LIVE2: square from header height (see icon note above).
			Size             = UDim2.fromScale(0.78, 0.78),
			SizeConstraint   = Enum.SizeConstraint.RelativeYY,
			BackgroundColor3 = C.bad,
			BorderSizePixel  = 0,
			Text             = "✕",
			TextColor3       = C.text,
			Font             = F.title,
			TextScaled       = true,
			ZIndex           = zBase + 4,
			[React.Event.Activated] = props.onClose,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
			stroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(255, 120, 120), Thickness = 1, Transparency = 0.4,
			}),
		}),
	})

	-- ── Body (caller's children) ──────────────────────────────────────────────
	local body = React.createElement("Frame", {
		Name                   = "Body",
		Position               = UDim2.fromScale(0, HEADER_H),
		Size                   = UDim2.fromScale(1, 1 - HEADER_H),
		BackgroundTransparency = 1,
		ClipsDescendants       = true,
		ZIndex                 = zBase + 1,
	}, props.children)

	-- ── Variants ──────────────────────────────────────────────────────────────
	if variant == "fullscreen" then
		return React.createElement("Frame", {
			Name                   = props.title or "AppWindow",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = C.bg,
			BackgroundTransparency = 0.05,
			BorderSizePixel        = 0,
			ZIndex                 = zBase,
		}, {
			header = header,
			body   = body,
		})
	end

	-- windowed (default)
	return React.createElement("Frame", {
		Name                   = (props.title or "AppWindow") .. "Backdrop",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundColor3       = C.dim,
		BackgroundTransparency = 0.42,
		BorderSizePixel        = 0,
		ZIndex                 = zBase,
	}, {
		panel = React.createElement("Frame", {
			Name             = "Panel",
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = UDim2.fromScale(0.5, 0.5),
			Size             = props.size or UDim2.fromScale(0.88, 0.82),
			BackgroundColor3 = C.panel,
			BorderSizePixel  = 0,
			ClipsDescendants = true,
			ZIndex           = zBase + 1,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.015, 0) }),
			stroke = React.createElement("UIStroke", {
				Color = C.accent, Thickness = 1.5, Transparency = 0.55,
			}),
			header = header,
			body   = body,
		}),
	})
end

return AppWindow
