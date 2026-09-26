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
      variant = "side"        §AGX/UI-P3: D7 right sheet (combat, Tablet/Desktop):
                              min(0.46 W, 640 design px) wide, full height below
                              the topbar, NO dim; only the sheet sinks input.
      variant = "dialog"      §AGX/UI-P3: small window. Phone = bottom sheet at
                              45 % height; elsewhere the `size` passed in.

    §AGX/UI-P3: PRESENTATION FROM THE SHELL (A8, shell-spec §3.8)
      Inside a PanelHost entry, PanelStack.usePresentation() ("windowed" |
      "side" | "sheet" | "fullscreen" | "dialog") OVERRIDES props.variant, so
      the registry, not each panel, decides how a panel is presented. Outside
      PanelHost props.variant applies exactly as before.
      • The backdrop and the Panel are Active (UX-06 / UX-14 click-through).
      • When the entry is dismissable (D8, registry dismissOnBackdrop) the
        backdrop is a TextButton calling props.onBackdrop or the stack's
        back("backdrop"). Outside PanelHost, passing props.onBackdrop opts in.

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

    Back (Backspace / gamepad B):
      §AGX/UI-P3: there is ONE back handler, PanelStack's (InputActions
      UIBack + a CAS sink on B, debounced). Inside a PanelHost entry the
      stack pops the window on Back by itself; closeOnBack is not needed.
      Outside PanelHost, closeOnBack = true registers this window with
      PanelStack.pushBackHandler (newest window wins; it holds the "UI"
      context while mounted, so B means Back, not Dash). onClose is then
      called with "back" (the ✕ passes "close"). Esc is NOT bound: the Roblox
      system menu owns it (shell-spec §3.3; 2e3fdf5 bound Escape here).

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
            closeOnBack = false,           -- §AGX/UI-P1v2 (§AGX/UI-P3: via PanelStack)
            onBackdrop = fn?,              -- §AGX/UI-P3: D8 click-outside (dismissable)
            scroll  = false,               -- §AGX/UI-P1v2: body is a vertical ScrollingFrame
        }, bodyChildrenTable)
]]

local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local TextService          = game:GetService("TextService")
local Workspace            = game:GetService("Workspace")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))
local IconButton    = require(Common:WaitForChild("IconButton"))

-- §AGX/UI-P3: PanelStack (UI/Shell) is optional at load: AppWindow must work
-- in any tree, and the hooks below stay unconditional either way.
local PanelStack = nil
do
	local shell = Common.Parent:FindFirstChild("Shell")
	local mod = shell and shell:FindFirstChild("PanelStack")
	if mod then
		local ok, res = pcall(require, mod)
		if ok then PanelStack = res end
	end
end
local EntryContext = (PanelStack and PanelStack.EntryContext) or React.createContext(nil)

local e = React.createElement
local R = Theme.Roles
local S = Theme.Speed
local MW = Theme.Metrics.window

-- §AGX/UI-P1v2: Theme.Layout[kind].header / .close replace the old
-- MIN_HEADER_PX / MIN_CLOSE_PX floors (48 / 44).
local TOPBAR_GAP_PX = MW.topGap   -- breathing room below Roblox's topbar
local SIDE_WIDTH_SCALE = 0.46     -- §AGX/UI-P3: D7 side sheet
local SIDE_MAX_W       = 640      -- design px
local DIALOG_PHONE_H   = 0.45     -- §AGX/UI-P3: phone dialog = bottom sheet
local RIBBON_TAIL   = 28          -- ribbon past the title's end (design px)
local CHROME_PAD    = 16

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

	-- §AGX/UI-P3: the shell's presentation wins over props.variant.
	local entryCtx = React.useContext(EntryContext)
	local presentation = entryCtx and entryCtx.presentation or nil
	local variant = presentation or props.variant or "auto"
	if variant == "auto" then
		variant = (ff.kind == "Phone") and "sheet" or "windowed"
	end
	if variant == "dialog" then
		variant = (ff.kind == "Phone") and "dialogSheet" or "windowed"
	elseif variant ~= "windowed" and variant ~= "fullscreen"
		and variant ~= "sheet" and variant ~= "side" then
		variant = "windowed"   -- menu presentations etc. never reach AppWindow
	end

	-- §AGX/UI-P3: D8 click-outside.
	local onBackdrop = nil
	if entryCtx then
		if entryCtx.dismissable then
			onBackdrop = props.onBackdrop or entryCtx.onBackdrop
		end
	else
		onBackdrop = props.onBackdrop
	end

	-- §AGX/UI-P1: measure the window root (fills its parent, normally the
	-- whole AppGui). Hook is unconditional. §AGX/UI-P1v2: AbsoluteSize is
	-- SCREEN px; divide by the applied scale to get this tree's Offset units.
	local rootAbs, setRootAbs = React.useState(viewportSize)
	local onRootSize = React.useCallback(function(rbx)
		local sz = rbx.AbsoluteSize
		if sz.X > 0 and sz.Y > 0 then setRootAbs(sz) end
	end, {})

	-- §AGX/UI-P1v2 / §AGX/UI-P3: back routing (see header comment). Inside a
	-- PanelHost entry the stack owns Back; outside, register with the one
	-- PanelStack back route instead of binding a second CAS action.
	local onCloseRef = React.useRef(props.onClose)
	onCloseRef.current = props.onClose
	local closeOnBack = props.closeOnBack == true and entryCtx == nil
	React.useEffect(function()
		if not closeOnBack or not PanelStack then return nil end
		return PanelStack.pushBackHandler(function()
			if onCloseRef.current then onCloseRef.current("back") end
		end)
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
	local sideTop   = topInset + TOPBAR_GAP_PX
	if variant == "side" then
		-- §AGX/UI-P3: D7, right-anchored, full height below the topbar.
		panelW = math.min(SIDE_WIDTH_SCALE * rootSize.X, SIDE_MAX_W * r)
	elseif variant == "windowed" then
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
	elseif variant ~= "side" then
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

	-- §AGX/UI-P3: a dim backdrop that sinks clicks; a TextButton when the
	-- entry is dismissable (D8), a Frame otherwise.
	local function backdrop(children)
		local base = {
			Name                   = (props.title or "AppWindow") .. "Backdrop",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = R.surface.scrim,
			BackgroundTransparency = Theme.Elevation.overlay.scrim,
			BorderSizePixel        = 0,
			Active                 = true,   -- §AGX/UI-P1v2: clicks no longer fall through to the HUD/world
			ZIndex                 = zBase,
			[React.Change.AbsoluteSize] = onRootSize,
		}
		if onBackdrop then
			base.Text            = ""
			base.AutoButtonColor = false
			base.Selectable      = false
			base[React.Event.Activated] = function() onBackdrop() end
			return e("TextButton", base, children)
		end
		return e("Frame", base, children)
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
		return backdrop({
			panel = e("Frame", {
				Name             = "Panel",
				Position         = UDim2.fromOffset(0, top),
				Size             = UDim2.new(1, 0, 1, -top),
				BackgroundColor3 = R.surface.panel,
				BorderSizePixel  = 0,
				ClipsDescendants = true,
				Active           = true,   -- §AGX/UI-P3: UX-06/UX-14
				ZIndex           = zBase + 1,
			}, {
				corner = e("UICorner", { CornerRadius = Theme.Radius.lg }),
				header = header,
				body   = body,
			}),
		})
	end

	if variant == "dialogSheet" then
		-- §AGX/UI-P3: phone dialog = bottom sheet at 45 % of the height.
		return backdrop({
			panel = e("Frame", {
				Name             = "Panel",
				AnchorPoint      = Vector2.new(0, 1),
				Position         = UDim2.fromScale(0, 1),
				Size             = UDim2.new(1, 0, DIALOG_PHONE_H, math.max(0, headerPx * 3 - DIALOG_PHONE_H * rootSize.Y)),
				BackgroundColor3 = R.surface.panel,
				BorderSizePixel  = 0,
				ClipsDescendants = true,
				Active           = true,
				ZIndex           = zBase + 1,
			}, {
				corner = e("UICorner", { CornerRadius = Theme.Radius.lg }),
				header = header,
				body   = body,
			}),
		})
	end

	if variant == "side" then
		-- §AGX/UI-P3: D7. No dim and no input sink outside the sheet, so the
		-- HUD vitals stay visible (hudMode "combatSide").
		return e("Frame", {
			Name                   = (props.title or "AppWindow") .. "Side",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex                 = zBase,
			[React.Change.AbsoluteSize] = onRootSize,
		}, {
			panel = e("Frame", {
				Name                   = "Panel",
				AnchorPoint            = Vector2.new(1, 0),
				Position               = UDim2.new(1, 0, 0, sideTop),
				Size                   = UDim2.new(0, panelW, 1, -sideTop),
				BackgroundColor3       = R.surface.panel,
				BackgroundTransparency = 0.08,   -- D7 translucent
				BorderSizePixel        = 0,
				ClipsDescendants       = true,
				Active                 = true,
				ZIndex                 = zBase + 1,
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

	-- windowed
	return backdrop({
		panel = e("Frame", {
			Name             = "Panel",
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = panelPos,
			Size             = panelSize,
			BackgroundColor3 = R.surface.panel,
			BorderSizePixel  = 0,
			ClipsDescendants = true,
			Active           = true,   -- §AGX/UI-P3: UX-06/UX-14
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
