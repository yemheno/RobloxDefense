-- UI/Common/AppWindow.lua
--[[
    AppWindow = the Window component  (§T10/U3; v2 §AGX/UI-P1v2)
    =============================================================
    THE window of the game. Every menu renders inside one of these; no menu
    draws its own backdrop/title/close chrome anymore.

      variant = "auto"        §AGX/UI-P1v2 (default): "sheet" on Phone,
                              "windowed" on Tablet / Desktop / Console.
      variant = "windowed"    dim backdrop + centered panel (default
                              0.88 × 0.82). Unchanged behaviour.
      variant = "fullscreen"  fills the viewport. Big experiences
                              (Talent Tree, Character Creation).
      variant = "sheet"       §AGX/UI-P1v2: full-bleed dim, panel fills the
                              safe area under the Roblox topbar (mobile.md §2.6).

    Shared chrome (D1 Hybrid: the anime identity lives HERE):
      • slanted ORANGE ribbon behind an UPPERCASE title (ink text, 10:1)
      • motion-line accents trailing the ribbon
      • optional icon slot (Theme.Icons) left of the title
      • `headerContent` slot on the right (counters, action buttons)
      • close = IconButton "danger", Layout[kind].close design px (>= 44)
      • body = your children, in a frame below the header (NOT scaled:
        legacy Scale-based bodies render exactly as before)

    Sizing (§AGX/UI-P1v2, D2): the header height and everything inside it
    are fixed DESIGN px (Theme.Layout[kind].header / .close) and scaled by
    the form factor's uiScale through UIScaleRoot.Local, so the chrome is
    right whether the caller is a legacy (unscaled) screen or already lives
    inside a UIScaleRoot. Panel geometry (size / minSize) keeps the caller's
    units: Scale, or Offset px of the tree the caller lives in.

    Back / Esc / gamepad B (hook point for the P3 shell):
      closeOnBack = true binds Escape + ButtonB through ContextActionService
      at high priority while the window is mounted; the newest window wins.
      onClose is then called with "back" (the ✕ passes "close"). OFF by
      default until the shell phase turns it on (Dash is still on B, P7).

    Usage (unchanged contract):
        local AppWindow = require(script.Parent:WaitForChild("Common"):WaitForChild("AppWindow"))
        return React.createElement(AppWindow, {
            variant = "windowed",
            title   = Locale.Get("menu_classes_title"),
            icon    = "classes",           -- Theme.Icons key (optional)
            onClose = onClose,             -- onClose(reason?) reason = "close"|"back"
            headerContent = element?,      -- optional right-side slot
            size    = UDim2.fromScale(0.88, 0.82),  -- windowed only
            minSize = Vector2.new(360, 260),         -- windowed only, px (§AGX/UI-P1)
            zIndex  = 10,
            closeOnBack = false,           -- §AGX/UI-P1v2
            scroll  = false,               -- §AGX/UI-P1v2: body is a vertical ScrollingFrame
        }, bodyChildrenTable)
]]

local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local TextService          = game:GetService("TextService")
local Workspace            = game:GetService("Workspace")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))
local IconButton    = require(Common:WaitForChild("IconButton"))

local e = React.createElement
local R = Theme.Roles
local S = Theme.Speed
local MW = Theme.Metrics.window

-- §AGX/UI-P1v2: Theme.Layout[kind].header / .close replace the old
-- MIN_HEADER_PX / MIN_CLOSE_PX floors (48 / 44).
local TOPBAR_GAP_PX = MW.topGap   -- breathing room below Roblox's topbar
local RIBBON_TAIL   = 28          -- ribbon past the title's end (design px)
local CHROME_PAD    = 16

local backCounter = 0

-- §AGX/UI-P1: fallback before the first AbsoluteSize measurement.
local function viewportSize()
	local cam = Workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end

-- Width of the title at its design size (legacy Font twin of FontFaces.heavy).
local function titleWidth(text, size)
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, Theme.Fonts.title, Vector2.new(4096, 4096)).X
	end)
	return ok and v or (#text * size * 0.7)
end

-- ── Chrome (design px, scaled by UIScaleRoot.Local) ──────────────────────────
local function Chrome(props)
	local ff = props.ff
	local D = ff.design
	local H = D.header
	local chromeW = props.chromeW          -- header width in design px
	local zBase = props.zBase
	local closeSize = math.max(Theme.Metrics.iconButton.sm, D.close)
	local ty = Theme.typeFor("title", ff.kind)
	-- window titles are one step up from `title` (26 design px: 35 px at 1080p)
	local titleSize = math.clamp(MW.titleSize, ty.min, ty.max)
	local iconId = props.icon and Theme.GetIcon(props.icon) or nil
	local iconSize = math.floor(H * 0.7)

	local title = string.upper(props.title or "")
	local titleX = CHROME_PAD + (iconId and (iconSize + Theme.Space.sm) or 0)
	local reserved = closeSize + CHROME_PAD + (props.headerContent and chromeW * 0.45 or 0)
	local maxTitleW = math.max(60, chromeW - reserved - titleX - RIBBON_TAIL - CHROME_PAD)
	local tw = math.min(titleWidth(title, titleSize) + 4, maxTitleW)
	local ribbonW = titleX + tw + RIBBON_TAIL

	local motionLines = {}
	for i = 1, S.lineCount do
		motionLines["line" .. i] = e("Frame", {
			AnchorPoint      = Vector2.new(0, 0.5),
			Position         = UDim2.new(0, ribbonW + 6 + i * 14, 0.35 + (i % 2) * 0.3, 0),
			Size             = UDim2.fromOffset(30 - i * 6, 3),
			BackgroundColor3 = R.accent.primary,
			BackgroundTransparency = 0.25 + i * 0.2,
			BorderSizePixel  = 0,
			Rotation         = S.lineSlantDeg,
			ZIndex           = zBase + 3,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
		})
	end

	return {
		-- Slanted speed ribbon behind the title (orange identity only)
		ribbon = e("Frame", {
			AnchorPoint      = Vector2.new(0, 0.5),
			Position         = UDim2.new(0, -12, 0.5, 0),
			Size             = UDim2.new(0, ribbonW + 12, 1.3, 0),
			BackgroundColor3 = R.accent.primary,
			BorderSizePixel  = 0,
			Rotation         = S.slantDeg,
			ZIndex           = zBase + 2,
		}, {
			grad = e("UIGradient", {
				-- §AGX/UI-P1v2: orange -> deep orange (was orange -> blue, the
				-- "orange header over blue body" clash of the audit).
				Color = ColorSequence.new(R.accent.primary, R.accent.primaryDeep),
			}),
		}),
		icon = iconId and e("ImageLabel", {
			AnchorPoint            = Vector2.new(0, 0.5),
			Position               = UDim2.new(0, CHROME_PAD, 0.5, 0),
			Size                   = UDim2.fromOffset(iconSize, iconSize),
			BackgroundTransparency = 1,
			Image                  = iconId,
			ZIndex                 = zBase + 4,
		}) or nil,
		title = e("TextLabel", {
			AnchorPoint            = Vector2.new(0, 0.5),
			Position               = UDim2.new(0, titleX, 0.5, 0),
			Size                   = UDim2.new(0, tw, 0, titleSize + 8),
			BackgroundTransparency = 1,
			Text                   = title,
			TextColor3             = R.text.onAccent,
			FontFace               = ty.font,
			TextSize               = titleSize,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			TextXAlignment         = Enum.TextXAlignment.Left,
			ZIndex                 = zBase + 4,
		}, {
			tsize = e("UITextSizeConstraint", { MinTextSize = ty.min, MaxTextSize = ty.max }),
		}),
		lines = e("Frame", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex                 = zBase + 3,
		}, motionLines),
		-- Right-side content slot (counters, action buttons): 45 % wide as before
		slot = props.headerContent and e("Frame", {
			AnchorPoint            = Vector2.new(1, 0.5),
			Position               = UDim2.new(1, -(closeSize + CHROME_PAD), 0.5, 0),
			Size                   = UDim2.fromScale(0.45, 0.8),
			BackgroundTransparency = 1,
			ZIndex                 = zBase + 4,
		}, { content = props.headerContent }) or nil,
		close = e(IconButton, {
			name        = "Close",
			icon        = "close",
			variant     = "danger",
			size        = closeSize,
			anchorPoint = Vector2.new(1, 0.5),
			position    = UDim2.new(1, -MW.closeInset, 0.5, 0),
			zIndex      = zBase + 4,
			onActivated = props.onCloseButton,
		}),
		-- identity hairline under the header
		underline = e("Frame", {
			AnchorPoint            = Vector2.new(0, 1),
			Position               = UDim2.fromScale(0, 1),
			Size                   = UDim2.new(1, 0, 0, Theme.Stroke.strong),
			BackgroundColor3       = R.border.identity,
			BackgroundTransparency = 0.55,
			BorderSizePixel        = 0,
			ZIndex                 = zBase + 3,
		}),
	}
end

local function AppWindow(props)
	local ff = useFormFactor()
	local scale = UIScaleRoot.useUIScale()
	local zBase = props.zIndex or Theme.Z.window

	local variant = props.variant or "auto"
	if variant == "auto" then
		variant = (ff.kind == "Phone") and "sheet" or "windowed"
	end

	-- §AGX/UI-P1: measure the window root (fills its parent, normally the
	-- whole AppGui). Hook is unconditional. §AGX/UI-P1v2: AbsoluteSize is
	-- SCREEN px; divide by the applied scale to get this tree's Offset units.
	local rootAbs, setRootAbs = React.useState(viewportSize)
	local onRootSize = React.useCallback(function(rbx)
		local sz = rbx.AbsoluteSize
		if sz.X > 0 and sz.Y > 0 then setRootAbs(sz) end
	end, {})

	-- §AGX/UI-P1v2: Esc / B / back hook point (see header comment).
	local onCloseRef = React.useRef(props.onClose)
	onCloseRef.current = props.onClose
	local closeOnBack = props.closeOnBack == true
	React.useEffect(function()
		if not closeOnBack then return nil end
		backCounter += 1
		local actionName = "AppWindowBack_" .. backCounter
		ContextActionService:BindActionAtPriority(actionName, function(_, state)
			if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
			if onCloseRef.current then onCloseRef.current("back") end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
		return function()
			ContextActionService:UnbindAction(actionName)
		end
	end, { closeOnBack })

	local onCloseButton = React.useCallback(function()
		if onCloseRef.current then onCloseRef.current("close") end
	end, {})

	local applied  = scale.applied
	local r        = scale.remaining
	local rootSize = rootAbs / applied
	local topInset = UIScaleRoot.toLocal(ff.topbar or 0, applied)   -- Roblox topbar
	local headerPx = ff.design.header * r   -- header height in this tree's units

	-- §AGX/UI-P1: windowed panel geometry. Only deviates from the caller's
	-- scale size when (a) props.minSize grows it, or (b) its top would sit
	-- under the topbar. At 1080p neither applies, so the panel keeps its
	-- exact scale size.
	local panelSize = props.size or MW.windowedSize
	local panelPos  = UDim2.fromScale(0.5, 0.5)
	local panelW    = panelSize.X.Scale * rootSize.X + panelSize.X.Offset
	local panelHpx  = panelSize.Y.Scale * rootSize.Y + panelSize.Y.Offset
	if variant == "windowed" then
		local minSize  = props.minSize
		local wantW, wantH = panelW, panelHpx
		if minSize then
			wantW = math.max(wantW, minSize.X)
			wantH = math.max(wantH, minSize.Y)
		end
		-- §AGX/UI-P1v2: never shorter than the header plus 2 header heights of body.
		wantH = math.max(wantH, headerPx * 3)
		local safeTopPx = topInset + TOPBAR_GAP_PX
		local maxH = math.max(0, rootSize.Y - safeTopPx - TOPBAR_GAP_PX)
		wantW = math.min(wantW, rootSize.X)
		wantH = math.min(wantH, maxH)
		local topPx = (rootSize.Y - wantH) / 2
		if wantW ~= panelW or wantH ~= panelHpx or topPx < safeTopPx then
			panelSize = UDim2.fromOffset(wantW, wantH)
			panelPos  = UDim2.fromOffset(rootSize.X / 2,
				math.max(rootSize.Y / 2, safeTopPx + wantH / 2))
			panelW    = wantW
		end
	else
		panelW = rootSize.X
	end

	-- Fullscreen: the header starts below the topbar so its title ribbon is
	-- not under Roblox's menu/chat buttons (V3); the backdrop stays full-bleed.
	local headerTop = (variant == "fullscreen") and topInset or 0

	local header = e("Frame", {
		Name             = "Header",
		Position         = UDim2.fromOffset(0, headerTop),
		Size             = UDim2.new(1, 0, 0, headerPx),
		BackgroundColor3 = R.surface.raised,
		BorderSizePixel  = 0,
		ClipsDescendants = true,
		ZIndex           = zBase + 2,
	}, {
		chrome = e(UIScaleRoot.Local, { name = "Chrome", zIndex = zBase + 2 },
			Chrome({
				ff            = ff,
				chromeW       = panelW / r,
				zBase         = zBase,
				icon          = props.icon,
				title         = props.title,
				headerContent = props.headerContent,
				onCloseButton = onCloseButton,
			})),
	})

	-- ── Body (caller's children, NOT scaled) ─────────────────────────────────
	local bodyTop = headerTop + headerPx
	local body
	if props.scroll then
		body = e("ScrollingFrame", {
			Name                   = "Body",
			Position               = UDim2.fromOffset(0, bodyTop),
			Size                   = UDim2.new(1, 0, 1, -bodyTop),
			BackgroundTransparency = 1,
			BorderSizePixel        = 0,
			CanvasSize             = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize    = Enum.AutomaticSize.Y,
			ScrollingDirection     = Enum.ScrollingDirection.Y,
			ScrollBarThickness     = Theme.Metrics.scrollBar,
			ScrollBarImageColor3   = R.text.secondary,
			ElasticBehavior        = Enum.ElasticBehavior.WhenScrollable,
			ZIndex                 = zBase + 1,
		}, props.children)
	else
		body = e("Frame", {
			Name                   = "Body",
			Position               = UDim2.fromOffset(0, bodyTop),
			Size                   = UDim2.new(1, 0, 1, -bodyTop),
			BackgroundTransparency = 1,
			ClipsDescendants       = true,
			ZIndex                 = zBase + 1,
		}, props.children)
	end

	-- ── Variants ──────────────────────────────────────────────────────────────
	if variant == "fullscreen" then
		return e("Frame", {
			Name                   = props.title or "AppWindow",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = R.surface.base,
			BackgroundTransparency = 0.05,
			BorderSizePixel        = 0,
			Active                 = true,   -- §AGX/UI-P1v2: sink clicks
			ZIndex                 = zBase,
			[React.Change.AbsoluteSize] = onRootSize,
		}, {
			header = header,
			body   = body,
		})
	end

	if variant == "sheet" then
		local top = topInset + TOPBAR_GAP_PX
		return e("Frame", {
			Name                   = (props.title or "AppWindow") .. "Backdrop",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = R.surface.scrim,
			BackgroundTransparency = Theme.Elevation.overlay.scrim,
			BorderSizePixel        = 0,
			Active                 = true,
			ZIndex                 = zBase,
			[React.Change.AbsoluteSize] = onRootSize,
		}, {
			panel = e("Frame", {
				Name             = "Panel",
				Position         = UDim2.fromOffset(0, top),
				Size             = UDim2.new(1, 0, 1, -top),
				BackgroundColor3 = R.surface.panel,
				BorderSizePixel  = 0,
				ClipsDescendants = true,
				ZIndex           = zBase + 1,
			}, {
				corner = e("UICorner", { CornerRadius = Theme.Radius.lg }),
				header = header,
				body   = body,
			}),
		})
	end

	-- windowed
	return e("Frame", {
		Name                   = (props.title or "AppWindow") .. "Backdrop",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundColor3       = R.surface.scrim,
		BackgroundTransparency = Theme.Elevation.overlay.scrim,
		BorderSizePixel        = 0,
		Active                 = true,   -- §AGX/UI-P1v2: clicks no longer fall through to the HUD/world
		ZIndex                 = zBase,
		[React.Change.AbsoluteSize] = onRootSize,
	}, {
		panel = e("Frame", {
			Name             = "Panel",
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = panelPos,
			Size             = panelSize,
			BackgroundColor3 = R.surface.panel,
			BorderSizePixel  = 0,
			ClipsDescendants = true,
			ZIndex           = zBase + 1,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.lg }),
			stroke = e("UIStroke", {
				Color = R.border.identity, Thickness = Theme.Stroke.base, Transparency = 0.55,
			}),
			header = header,
			body   = body,
		}),
	})
end

return AppWindow
