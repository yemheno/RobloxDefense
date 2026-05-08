-- shared/StarterPlayerScripts/UI/BattleClassUI.lua
--[[
    Battle Class UI — shared combat component.

	Compact badge showing the active class in combat.
	The full class reference is opened from the HUD Classes button.

    Read-only — no class switching during combat.
    Used by LaneDefense, CentralBoss, and HordeMode.
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

-- Class description data accessible on the client
local ClassDescriptions = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassDescriptions")
)

-- ── Palette ───────────────────────────────────────────────
local C = {
	bg          = Color3.fromRGB(18, 18, 28),
	bg_panel    = Color3.fromRGB(22, 22, 38),
	bg_skill    = Color3.fromRGB(28, 28, 44),
	border      = Color3.fromRGB(70, 70, 100),
	text        = Color3.fromRGB(220, 220, 235),
	text_dim    = Color3.fromRGB(140, 140, 165),
	text_muted  = Color3.fromRGB(100, 100, 130),
	gold        = Color3.fromRGB(255, 210, 80),
	accent      = Color3.fromRGB(105, 190, 255),
}

-- Class display data (matches ClassConfig names)
local CLASS_DISPLAY = {
	Aegis       = { icon = "🛡️", color = Color3.fromRGB(80, 160, 220) },
	Arcanist    = { icon = "🔮", color = Color3.fromRGB(160, 80, 220) },
	Hunter      = { icon = "🏹", color = Color3.fromRGB(80, 200, 120) },
	LifeSteward = { icon = "🌿", color = Color3.fromRGB(100, 220, 80) },
}

-- ═══════════════════════════════════════════════════════════
-- SUB-COMPONENTS
-- ═══════════════════════════════════════════════════════════

local function SkillRow(props)
	local skill    = props.skill
	local accent   = props.accent
	local keyLabel = props.keyLabel   -- live binding display from InputSystem

	return e("Frame", {
		Size                   = UDim2.new(1, 0, 0, 0),
		AutomaticSize          = Enum.AutomaticSize.Y,
		BackgroundColor3       = C.bg_skill,
		BackgroundTransparency = 0.25,
		BorderSizePixel        = 0,
		LayoutOrder            = skill.slot,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Pad    = e("UIPadding", {
			PaddingLeft   = UDim.new(0, 8),
			PaddingRight  = UDim.new(0, 8),
			PaddingTop    = UDim.new(0, 5),
			PaddingBottom = UDim.new(0, 5),
		}),
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding       = UDim.new(0, 8),
			SortOrder     = Enum.SortOrder.LayoutOrder,
		}),

		-- Slot key badge
		Key = e("Frame", {
			Size            = UDim2.fromScale(0.011, 0.020),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			LayoutOrder     = 1,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Label  = e("TextLabel", {
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text                   = keyLabel or tostring(skill.slot),
				TextColor3             = C.text,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
			}),
		}),

		-- Name + description column
		Info = e("Frame", {
			Size          = UDim2.new(1, -30, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder   = 2,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding       = UDim.new(0, 2),
				SortOrder     = Enum.SortOrder.LayoutOrder,
			}),
			Name = e("TextLabel", {
				Size                   = UDim2.new(1, 0, 0, 16),
				AutomaticSize          = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text                   = skill.name,
				TextColor3             = skill.slot == 4 and C.gold or C.text,
				TextXAlignment         = Enum.TextXAlignment.Left,
				Font                   = Enum.Font.GothamBold,
				TextSize               = 13,
				TextWrapped            = true,
				LayoutOrder            = 1,
			}),
			Desc = e("TextLabel", {
				Size                   = UDim2.new(1, 0, 0, 0),
				AutomaticSize          = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text                   = skill.description,
				TextColor3             = C.text_dim,
				TextXAlignment         = Enum.TextXAlignment.Left,
				Font                   = Enum.Font.Gotham,
				TextSize               = 11,
				TextWrapped            = true,
				LayoutOrder            = 2,
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

	local display  = CLASS_DISPLAY[activeClass] or { icon = "⚔️", color = C.accent }
	local classInfo = ClassDescriptions[activeClass]

	-- §LD-BC1/BC2: Badge is now built INLINE inside the return below
	-- (under BadgeWrap) so its `fromScale` dimensions resolve against
	-- the full screen rather than against the panelScale-narrowed
	-- Container that used to wrap it. The previous local `badge` here
	-- has been removed; do not reintroduce it without also resizing
	-- its parent.

	-- ── Expanded info panel ────────────────────────────────
	local panel = nil
	if expanded and classInfo then
		local skillRows = {}
		for _, skill in ipairs(classInfo.skills) do
			skillRows["skill_" .. skill.slot] = e(SkillRow, {
				skill    = skill,
				accent   = display.color,
				keyLabel = InputSystem.GetBindingDisplayName("Skill" .. skill.slot),
			})
		end
		skillRows["_layout"] = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding       = UDim.new(0, 5),
			SortOrder     = Enum.SortOrder.LayoutOrder,
		})

		local panelChildren = {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Stroke = e("UIStroke", { Color = display.color, Thickness = 1.5 }),
			Pad    = e("UIPadding", {
				PaddingLeft   = UDim.new(0, 10),
				PaddingRight  = UDim.new(0, 10),
				PaddingTop    = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
			}),
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding       = UDim.new(0, 8),
				SortOrder     = Enum.SortOrder.LayoutOrder,
			}),
			-- §LD-BC3: minimum panel width so descriptions stay readable
			-- regardless of upstream container constraints. Without this,
			-- a narrow parent (or AutomaticSize cascade) collapses the
			-- panel and TextWrapped renders one character per line.
			-- §LD-BC4: outer Frame is now scale-bound + clipped, and
			-- the inner ScrollingFrame handles vertical overflow. The old
			-- MinSize cap is no longer needed (and would conflict with the
			-- fixed scale height).
		}

		panelChildren.WindowTitle = e("TextLabel", {
			Size = UDim2.new(1, -72, 0, 20),
			BackgroundTransparency = 1,
			Text = props.panelTitle or "CLASSES",
			TextColor3 = C.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			LayoutOrder = 1,
		})

		if props.onClose then
			panelChildren.CloseBtn = e("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 8),
				-- §LD-BC3: was fromScale(0.030, 0.026) which collapsed to
				-- ~9 × 23 px on a panel that's already ≤30 % screen wide,
				-- making it impossible to click. Pin to a fixed pixel size.
				Size = UDim2.fromOffset(64, 24),
				BackgroundColor3 = Color3.fromRGB(80, 36, 36),
				BorderSizePixel = 0,
				Text = "Close",
				TextColor3 = Color3.fromRGB(245, 100, 100),
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				ZIndex = (props.zIndex or 3) + 1,
				[React.Event.Activated] = props.onClose,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
			})
		end

		panelChildren.Header = e("Frame", {
				Size            = UDim2.new(1, 0, 0, 32),
				BackgroundTransparency = 1,
				LayoutOrder     = 2,
			}, {
				Layout = e("UIListLayout", {
					FillDirection     = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding           = UDim.new(0, 8),
					SortOrder         = Enum.SortOrder.LayoutOrder,
				}),
				IconLbl = e("TextLabel", {
					Size                   = UDim2.fromScale(0.015, 0.026),
					BackgroundTransparency = 1,
					Text                   = display.icon,
					TextScaled             = true,
					LayoutOrder            = 1,
				}),
				NameLbl = e("TextLabel", {
					Size                   = UDim2.new(1, -84, 1, 0),
					BackgroundTransparency = 1,
					Text                   = activeClass,
					TextColor3             = display.color,
					TextXAlignment         = Enum.TextXAlignment.Left,
					Font                   = Enum.Font.GothamBold,
					TextSize               = 16,
					LayoutOrder            = 2,
				}),
				ResLbl = e("TextLabel", {
					Size                   = UDim2.fromScale(0.042, 0.019),
					BackgroundTransparency = 1,
					Text                   = "* " .. (classInfo.resource or ""),
					TextColor3             = C.gold,
					TextXAlignment         = Enum.TextXAlignment.Right,
					Font                   = Enum.Font.GothamBold,
					TextSize               = 11,
					LayoutOrder            = 3,
				}),
			})

		panelChildren.DescLbl = e("TextLabel", {
				Size                   = UDim2.new(1, 0, 0, 0),
				AutomaticSize          = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text                   = classInfo.description,
				TextColor3             = C.text_dim,
				TextXAlignment         = Enum.TextXAlignment.Left,
				Font                   = Enum.Font.Gotham,
				TextSize               = 12,
				TextWrapped            = true,
				LayoutOrder            = 3,
			})

		panelChildren.PlaystyleLbl = e("TextLabel", {
				Size                   = UDim2.new(1, 0, 0, 0),
				AutomaticSize          = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text                   = "> " .. (classInfo.playstyle or ""),
				TextColor3             = display.color,
				TextXAlignment         = Enum.TextXAlignment.Left,
				Font                   = Enum.Font.GothamBold,
				TextSize               = 11,
				TextWrapped            = true,
				LayoutOrder            = 4,
			})

		panelChildren.SkillsHeader = e("TextLabel", {
				Size                   = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Text                   = "SKILLS",
				TextColor3             = C.text_muted,
				TextXAlignment         = Enum.TextXAlignment.Left,
				Font                   = Enum.Font.GothamBold,
				TextSize               = 10,
				LayoutOrder            = 5,
			})

		panelChildren.SkillsContainer = e("Frame", {
				Size            = UDim2.new(1, 0, 0, 0),
				AutomaticSize   = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder     = 6,
			}, skillRows)

		panelChildren.RebindBtn = e("TextButton", {
				Size                   = UDim2.new(1, 0, 0, 26),  -- keep pixel height
				BackgroundColor3       = C.bg_skill,
				BackgroundTransparency = 0.25,
				BorderSizePixel        = 0,
				Text                   = "Controls / Rebind Keys",
				TextColor3             = C.text_muted,
				Font                   = Enum.Font.Gotham,
				TextSize               = 12,
				LayoutOrder            = 7,
				[React.Event.Activated] = function()
					setShowKeybinds(true)
				end,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			})

		-- §LD-BC4: panel is now scale-bound (no AutomaticSize.Y) and
		-- its content lives in a ScrollingFrame so it can never overflow
		-- the viewport. Pablo's spec: every size in scale (0..1).
		local panelScaleY = props.panelScaleY or 0.78

		-- The Layout, Padding, and rich children that used to sit on the
		-- outer Frame all move to the ScrollingFrame so AutomaticCanvasSize
		-- can compute the scrollable extent from the children directly.
		local scrollChildren = {}
		for k, v in pairs(panelChildren) do scrollChildren[k] = v end
		-- The outer Frame keeps only the Corner + Stroke for the panel
		-- chrome; Layout/Padding/Inner content all sit inside the scroll.
		local outerCorner = scrollChildren.Corner
		local outerStroke = scrollChildren.Stroke
		scrollChildren.Corner = nil
		scrollChildren.Stroke = nil

		panel = e("Frame", {
			Position               = UDim2.fromOffset(0, showBadge and 50 or 0),
			Size                   = UDim2.new(props.panelScale or 0.22, 0, panelScaleY, 0),
			BackgroundColor3       = C.bg_panel,
			BackgroundTransparency = 0.08,
			BorderSizePixel        = 0,
			ClipsDescendants       = true,
		}, {
			Corner = outerCorner,
			Stroke = outerStroke,
			Scroll = e("ScrollingFrame", {
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				CanvasSize             = UDim2.new(),
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
				ScrollBarThickness     = 4,
				ScrollingDirection     = Enum.ScrollingDirection.Y,
				ElasticBehavior        = Enum.ElasticBehavior.Never,
			}, scrollChildren),
		})
	end

	-- §LD-BC2 fix: was a single Container at panelScale (0.22) wrapping
	-- the Badge — which made the Badge's `fromScale(0.13, 0.07)` evaluate
	-- against the Container's narrower bounds (0.13 × 0.22 = 2.86 % of
	-- screen wide, ≈ 55 px). Result: the Arcanist label collapsed back
	-- to nano-size in combat. Render the Badge and the expanded Panel
	-- directly under the top-level full-screen Frame so each one's
	-- `fromScale` resolves against the actual viewport.
	local topLeftAnchor = props.anchorPoint or Vector2.new(0, 0)
	local topLeftPosition = props.position or UDim2.fromOffset(safeLeft, safeTop + 40)

	-- Compute a panel anchor: when both badge and panel are present, the
	-- panel sits below the badge. Without an explicit position, that's
	-- ~7 % screen height (badge height) below the badge anchor.
	local panelPosition = topLeftPosition
	if showBadge then
		-- offset by badge height (0.07) using a UDim scale offset
		panelPosition = UDim2.new(
			topLeftPosition.X.Scale,
			topLeftPosition.X.Offset,
			topLeftPosition.Y.Scale + 0.075,
			topLeftPosition.Y.Offset
		)
	end

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
			BackgroundTransparency = 1,
		}, {
			Badge = e("Frame", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.bg,
				BackgroundTransparency = 0.1,
				BorderSizePixel  = 0,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0.12, 0) }),
				Stroke = e("UIStroke", { Color = display.color, Thickness = 1.5 }),

				IconShell = e("Frame", {
					Position         = UDim2.fromScale(0.04, 0.12),
					Size             = UDim2.fromScale(0.20, 0.76),
					BackgroundColor3 = display.color,
					BackgroundTransparency = 0.78,
					BorderSizePixel  = 0,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
					Icon   = e("TextLabel", {
						Size                   = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text                   = display.icon,
						TextScaled             = true,
					}),
				}),

				ClassName = e("TextLabel", {
					Position               = UDim2.fromScale(0.28, 0.06),
					Size                   = UDim2.fromScale(0.68, 0.50),
					BackgroundTransparency = 1,
					Text                   = activeClass,
					TextColor3             = C.text,
					TextXAlignment         = Enum.TextXAlignment.Left,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
				}),

				Subtitle = e("TextLabel", {
					Position               = UDim2.fromScale(0.28, 0.56),
					Size                   = UDim2.fromScale(0.68, 0.38),
					BackgroundTransparency = 1,
					Text                   = (classInfo and classInfo.role or "Active Class"),
					TextColor3             = C.text_dim,
					TextXAlignment         = Enum.TextXAlignment.Left,
					Font                   = Enum.Font.Gotham,
					TextScaled             = true,
				}),
			}),
		}) or nil,

		-- §LD-BC4: PanelWrap is now a fixed-scale viewport for the
		-- scrollable panel. No AutomaticSize anywhere — sizes are pure
		-- scale (0..1) of the screen so the panel can never overflow the
		-- visible viewport. Inner ScrollingFrame handles overflow.
		PanelWrap = panel and e("Frame", {
			AnchorPoint            = topLeftAnchor,
			Position               = panelPosition,
			Size                   = UDim2.new(props.panelScale or 0.22, 0, props.panelScaleY or 0.78, 0),
			BackgroundTransparency = 1,
		}, {
			Panel = panel,
		}) or nil,

		-- Keybind settings overlay (full-screen, above everything)
		KeybindOverlay = showKeybinds and e(
			require(script.Parent:WaitForChild("KeybindSettings")),
			{ onClose = function() setShowKeybinds(false) end }
		) or nil,
	})
end

return BattleClassUI
