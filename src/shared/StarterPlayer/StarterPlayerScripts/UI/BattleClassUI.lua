-- shared/StarterPlayerScripts/UI/BattleClassUI.lua
--[[
    Battle Class UI — shared combat component.

	Compact badge showing the active class in combat.
	The full class reference is opened from the HUD Classes button.

    Read-only — no class switching during combat.
    Used by LaneDefense, CentralBoss, and HordeMode.

    §AGX/UI-P6: Theme v2 re-skin (docs/UI_REVAMP.md D1 Hybrid / D2).
      • Class reference (expanded = true, Registry "class" in Combat) is an
        AppWindow (auto: sheet on phone, windowed at panelScale x
        panelScaleY elsewhere). Its body is design px inside
        UIScaleRoot.Local, in one vertical ScrollingFrame. The hand-rolled
        panel, its 64x24 "Close" (V2) and the hitArea helper are gone.
      • Skill rows = Panel + Text; "Controls / Rebind Keys" = Button.
      • Desktop badge (HUD classBadge, showBadge = true): keeps its
        fromScale(0.13, 0.07) footprint, which HUD/Layout reserves
        (BADGE_SCALE), but its content is design px (UIScaleRoot.Local)
        with Theme type instead of TextScaled labels.
      • Private palette + CLASS_DISPLAY fromRGB colours -> Theme roles.
      • Kept: the A13 close-handler veto for the keybind overlay, the
        PlayerInfoUpdate / GetPlayerInfo contract, live key labels.
]]

local Players           = game:GetService("Players")
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local e          = React.createElement
local useState   = React.useState
local useEffect  = React.useEffect

local LocalPlayer   = Players.LocalPlayer
local SharedModules = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")

-- InputSystem: live key-binding display (already initialized by the bootstrap)
local InputSystem = require(SharedModules:WaitForChild("InputSystem"))
-- §AGX/UI-P3: PanelStack hooks, nil-safe (no-ops without UI/Shell or
-- outside a PanelHost, so Wave 1 behaves exactly as before).
local PanelStackHooks = { useCloseHandler = function(_fn) end, useModalPresence = function(_k, _v) end }
do
	local shell = script.Parent:FindFirstChild("Shell")
	local mod = shell and shell:FindFirstChild("PanelStack")
	if mod then
		local ok, PanelStack = pcall(require, mod)
		if ok and type(PanelStack) == "table" then
			PanelStackHooks.useCloseHandler  = PanelStack.useCloseHandler or PanelStackHooks.useCloseHandler
			PanelStackHooks.useModalPresence = PanelStack.useModalPresence or PanelStackHooks.useModalPresence
		end
	end
end

-- §AGX/UI-P6: shared components
local Common      = script.Parent:WaitForChild("Common")
local Theme       = require(Common:WaitForChild("Theme"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local AppWindow   = require(Common:WaitForChild("AppWindow"))
local Text        = require(Common:WaitForChild("Text"))
local Button      = require(Common:WaitForChild("Button"))
local Panel       = require(Common:WaitForChild("Panel"))

local R  = Theme.Roles
local SP = Theme.Space

-- Class description data accessible on the client
local ClassDescriptions = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassDescriptions")
)

-- Class display data (matches ClassConfig names).
-- §AGX/UI-P6: colours are Theme role paths (were fromRGB literals).
local CLASS_DISPLAY = {
	Aegis       = { icon = "🛡️", color = "accent.secondary" },
	Arcanist    = { icon = "🔮", color = "rarity.epic" },
	Hunter      = { icon = "🏹", color = "state.success" },
	LifeSteward = { icon = "🌿", color = "vital.hp" },
}
local DEFAULT_DISPLAY = { icon = "⚔️", color = "accent.secondary" }

-- §AGX/UI-P6: layout in DESIGN px (phone scale).
local KEY_MIN_W   = 32
local KEY_H       = 28
local ICON_SIZE   = 36
local HEADER_H    = 44
local BADGE_ICON  = 40

-- ═══════════════════════════════════════════════════════════
-- SUB-COMPONENTS
-- ═══════════════════════════════════════════════════════════

local function SkillRow(props)
	local skill    = props.skill
	local accent   = props.accent
	-- live binding display from InputSystem. §AGX/UI-P6: "—" (no binding on
	-- this platform, e.g. touch; mobile.md) falls back to the slot number.
	local keyLabel = props.keyLabel
	if keyLabel == nil or keyLabel == "" or keyLabel == "—" then
		keyLabel = tostring(skill.slot)
	end
	local z = props.zIndex or 1

	return e(Panel, {
		elevation   = "raised",
		padding     = "sm",
		size        = UDim2.new(1, 0, 0, 0),
		autoSize    = "Y",
		layoutOrder = skill.slot,
		zIndex      = z,
	}, {
		-- Slot key badge (auto width for long names such as "LeftShift")
		Key = e("Frame", {
			Size             = UDim2.fromOffset(KEY_MIN_W, KEY_H),
			AutomaticSize    = Enum.AutomaticSize.X,
			BackgroundColor3 = accent,
			BorderSizePixel  = 0,
			ZIndex           = z + 1,
		}, {
			Corner = e("UICorner", { CornerRadius = Theme.Radius.sm }),
			Pad    = e("UIPadding", { PaddingLeft = UDim.new(0, SP.xs), PaddingRight = UDim.new(0, SP.xs) }),
			Label  = e(Text, {
				style    = "label",
				text     = keyLabel,
				color    = "text.onAccent",   -- ink on a bright class fill
				align    = "center",
				size     = UDim2.new(0, KEY_MIN_W - 2 * SP.xs, 1, 0),
				autoSize = "X",
				zIndex   = z + 2,
			}),
		}),

		-- Name + description column
		Info = e("Frame", {
			Position      = UDim2.fromOffset(KEY_MIN_W + SP.sm, 0),
			Size          = UDim2.new(1, -(KEY_MIN_W + SP.sm), 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex        = z + 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding       = UDim.new(0, SP.xxs),
				SortOrder     = Enum.SortOrder.LayoutOrder,
			}),
			Name = e(Text, {
				style       = "label",
				text        = skill.name,
				color       = skill.slot == 4 and "rarity.legendary" or "text.primary",
				wrap        = true,
				layoutOrder = 1,
				zIndex      = z + 2,
			}),
			Desc = e(Text, {
				style       = "caption",
				text        = skill.description,
				color       = "text.secondary",
				wrap        = true,
				layoutOrder = 2,
				zIndex      = z + 2,
			}),
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- MAIN COMPONENT
-- ═══════════════════════════════════════════════════════════
local function BattleClassUI(props)
	props = props or {}
	local activeClass, setActiveClass = useState("Aegis")
	local showKeybinds, setShowKeybinds = useState(false)

	-- §AGX/UI-P3: A13. Back closes the KeybindOverlay first (and vetoes the
	-- pop); the next Back closes the class reference. No-op for the badge
	-- instance and outside a PanelHost.
	local showKeybindsRef = React.useRef(false)
	showKeybindsRef.current = showKeybinds
	PanelStackHooks.useCloseHandler(function(reason)
		if showKeybindsRef.current and reason ~= "system" then
			setShowKeybinds(false)
			return false
		end
		return nil
	end)
	-- Incremented by OnBindingChanged so skill rows re-render with fresh key labels
	local _bindingsVer, setBindingsVer = useState(0)
	local topLeftInset = select(1, GuiService:GetGuiInset())
	local safeLeft = topLeftInset.X + 10
	local safeTop = topLeftInset.Y + 10
	local showBadge = props.showBadge ~= false
	local expanded = props.expanded == true

	useEffect(function()
		local mountedRef = { current = true }
		local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

		local conn = NetworkManager.OnServerEvent("PlayerInfoUpdate", function(data)
			if data and data.activeClass and mountedRef.current then
				setActiveClass(data.activeClass)
			end
		end)

		NetworkManager.FireServer("GetPlayerInfo")

		return function()
			mountedRef.current = false
			if conn and conn.Disconnect then conn:Disconnect() end
		end
	end, {})

	-- Re-render skill badges whenever the player rebinds a key
	useEffect(function()
		local disconnect = InputSystem.OnBindingChanged(function()
			setBindingsVer(function(v) return v + 1 end)
		end)
		return disconnect
	end, {})

	local display   = CLASS_DISPLAY[activeClass] or DEFAULT_DISPLAY
	local accent    = Theme.color(display.color)
	local classInfo = ClassDescriptions[activeClass]

	-- §LD-BC1/BC2: the Badge is built INLINE inside the return below (under
	-- BadgeWrap) so its `fromScale` footprint resolves against the full
	-- screen rather than against a narrower container.

	-- ── Expanded class reference (§AGX/UI-P6: AppWindow) ──────
	local panel = nil
	if expanded and classInfo then
		local z = Theme.Z.window + 2
		local skillRows = {
			_layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding       = UDim.new(0, SP.sm),
				SortOrder     = Enum.SortOrder.LayoutOrder,
			}),
		}
		for _, skill in ipairs(classInfo.skills) do
			skillRows["skill_" .. skill.slot] = e(SkillRow, {
				skill    = skill,
				accent   = accent,
				keyLabel = InputSystem.GetBindingDisplayName("Skill" .. skill.slot),
				zIndex   = z,
			})
		end

		local scrollChildren = {
			Pad = e("UIPadding", {
				PaddingLeft   = UDim.new(0, SP.lg),
				PaddingRight  = UDim.new(0, SP.lg),
				PaddingTop    = UDim.new(0, SP.md),
				PaddingBottom = UDim.new(0, SP.lg),
			}),
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding       = UDim.new(0, SP.sm),
				SortOrder     = Enum.SortOrder.LayoutOrder,
			}),

			-- Class header: icon, name (class colour), resource
			Header = e("Frame", {
				Size                   = UDim2.new(1, 0, 0, HEADER_H),
				BackgroundTransparency = 1,
				LayoutOrder            = 2,
				ZIndex                 = z,
			}, {
				IconShell = e("Frame", {
					AnchorPoint            = Vector2.new(0, 0.5),
					Position               = UDim2.fromScale(0, 0.5),
					Size                   = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
					BackgroundColor3       = accent,
					BackgroundTransparency = 0.78,
					BorderSizePixel        = 0,
					ZIndex                 = z,
				}, {
					Corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
					Icon   = e(Text, {
						style  = "heading",
						text   = display.icon,
						align  = "center",
						size   = UDim2.fromScale(1, 1),
						zIndex = z + 1,
					}),
				}),
				NameLbl = e(Text, {
					style    = "heading",
					text     = activeClass,
					color    = accent,
					position = UDim2.fromOffset(ICON_SIZE + SP.sm, 0),
					size     = UDim2.new(0.6, -(ICON_SIZE + SP.sm), 1, 0),
					zIndex   = z,
				}),
				ResLbl = e(Text, {
					style       = "label",
					text        = "* " .. (classInfo.resource or ""),
					color       = "rarity.legendary",
					align       = "right",
					anchorPoint = Vector2.new(1, 0),
					position    = UDim2.fromScale(1, 0),
					size        = UDim2.fromScale(0.4, 1),
					zIndex      = z,
				}),
			}),

			DescLbl = e(Text, {
				style       = "body",
				text        = classInfo.description,
				color       = "text.secondary",
				wrap        = true,
				layoutOrder = 3,
				zIndex      = z,
			}),

			PlaystyleLbl = e(Text, {
				style       = "label",
				text        = "> " .. (classInfo.playstyle or ""),
				color       = accent,
				wrap        = true,
				layoutOrder = 4,
				zIndex      = z,
			}),

			SkillsHeader = e(Text, {
				style       = "caption",
				text        = "SKILLS",
				color       = "text.secondary",
				layoutOrder = 5,
				zIndex      = z,
			}),

			SkillsContainer = e("Frame", {
				Size                   = UDim2.new(1, 0, 0, 0),
				AutomaticSize          = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder            = 6,
				ZIndex                 = z,
			}, skillRows),

			-- §AGX/UI-P1 T25 (44 px target) re-expressed: Button is 48 design px.
			RebindBtn = e(Button, {
				variant     = "secondary",
				label       = "Controls / Rebind Keys",
				width       = UDim.new(1, 0),
				layoutOrder = 7,
				zIndex      = z,
				onActivated = function()
					setShowKeybinds(true)
				end,
			}),
		}

		-- Close (✕), back and the phone sheet come from AppWindow. Registry
		-- passes panelScale 0.72 x panelScaleY 0.78 for the windowed size.
		panel = e(AppWindow, {
			variant = "auto",
			title   = props.panelTitle or "CLASSES",
			icon    = "classes",
			onClose = props.onClose,
			size    = UDim2.fromScale(props.panelScale or 0.72, props.panelScaleY or 0.78),
			zIndex  = Theme.Z.window,
		}, {
			content = e(UIScaleRoot.Local, { name = "ClassRefBody", zIndex = z }, {
				Scroll = e("ScrollingFrame", {
					Size                   = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel        = 0,
					CanvasSize             = UDim2.new(),
					AutomaticCanvasSize    = Enum.AutomaticSize.Y,
					ScrollBarThickness     = Theme.Metrics.scrollBar,
					ScrollBarImageColor3   = R.text.secondary,
					ScrollingDirection     = Enum.ScrollingDirection.Y,
					ElasticBehavior        = Enum.ElasticBehavior.Never,
					ZIndex                 = z,
				}, scrollChildren),
			}),
		})
	end

	-- §LD-BC2: the Badge and the class reference render directly under the
	-- top-level full-screen Frame so the badge's `fromScale` resolves
	-- against the actual viewport (HUD/Layout reserves 0.13 x 0.07 for it).
	local topLeftAnchor = props.anchorPoint or Vector2.new(0, 0)
	local topLeftPosition = props.position or UDim2.fromOffset(safeLeft, safeTop + 40)

	return e("Frame", {
		Name                   = "BattleClassUI",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = props.zIndex or 3,
	}, {
		BadgeWrap = showBadge and e("Frame", {
			AnchorPoint            = topLeftAnchor,
			Position               = topLeftPosition,
			Size                   = UDim2.fromScale(0.13, 0.07),
			BackgroundColor3       = R.surface.panel,
			BackgroundTransparency = 0.1,
			BorderSizePixel        = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
			Stroke = e("UIStroke", { Color = accent, Thickness = Theme.Stroke.base }),

			-- §AGX/UI-P6: design px content, scaled by the form factor.
			Badge = e(UIScaleRoot.Local, { name = "Badge" }, {
				Pad = e("UIPadding", {
					PaddingLeft  = UDim.new(0, SP.sm),
					PaddingRight = UDim.new(0, SP.sm),
				}),
				IconShell = e("Frame", {
					AnchorPoint            = Vector2.new(0, 0.5),
					Position               = UDim2.fromScale(0, 0.5),
					Size                   = UDim2.fromOffset(BADGE_ICON, BADGE_ICON),
					BackgroundColor3       = accent,
					BackgroundTransparency = 0.78,
					BorderSizePixel        = 0,
				}, {
					Corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
					Icon   = e(Text, {
						style = "heading",
						text  = display.icon,
						align = "center",
						size  = UDim2.fromScale(1, 1),
					}),
				}),
				ClassName = e(Text, {
					style       = "heading",
					text        = activeClass,
					anchorPoint = Vector2.new(0, 1),
					position    = UDim2.new(0, BADGE_ICON + SP.sm, 0.5, 2),
					size        = UDim2.new(1, -(BADGE_ICON + SP.sm), 0, Theme.Type.heading.lineHeight),
				}),
				Subtitle = e(Text, {
					style    = "caption",
					text     = (classInfo and classInfo.role or "Active Class"),
					color    = "text.secondary",
					position = UDim2.new(0, BADGE_ICON + SP.sm, 0.5, 2),
					size     = UDim2.new(1, -(BADGE_ICON + SP.sm), 0, Theme.Type.caption.lineHeight),
				}),
			}),
		}) or nil,

		PanelWrap = panel,

		-- Keybind settings overlay (full-screen, above everything)
		KeybindOverlay = showKeybinds and e(
			require(script.Parent:WaitForChild("KeybindSettings")),
			{ onClose = function() setShowKeybinds(false) end }
		) or nil,
	})
end

return BattleClassUI
