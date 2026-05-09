-- UI/TalentTreeUI.lua
--[[
    React component: full-window talent tree viewer.

    Features:
      • Visual grid-based node layout (positions from TalentTreeConfig x/y)
      • Edge lines between connected nodes
      • Node states: allocated (bright), allocatable (glow outline), locked (dim)
      • Click to allocate / right-click (or hold-click) to refund
      • Points counter  (Spent / Available / Total)
      • Respec All button
      • Tooltip on hover
      • Close button (top-right)

    Architecture:
      Reads tree topology from TalentTreeConfig (ReplicatedStorage.Shared).
      Reads player state via TalentClient (subscribe pattern).
      Sends actions via TalentClient (fire-and-forget → server responds).
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local TalentClient   = require(SharedModules:WaitForChild("TalentClient"))
local TreeConfig     = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TalentTreeConfig"))

-- ── Layout constants ──────────────────────────────────────────────────────────
local GRID_CELL   = 42    -- pixels per grid unit (node x/y are in grid units)
local NODE_SIZE   = 36    -- pixels (diameter)
local CENTER_X    = 0.5   -- fractional X anchor of the canvas
local CENTER_Y    = 0.45  -- fractional Y anchor (slightly above mid for top branch room)

-- ── Palette ───────────────────────────────────────────────────────────────────
local C = {
	bg           = Color3.fromRGB( 12,  12,  18),
	panel        = Color3.fromRGB( 18,  18,  26),
	allocated    = Color3.fromRGB( 80, 210, 120),   -- green glow
	allocatable  = Color3.fromRGB(120, 180, 255),   -- blue pulse
	locked       = Color3.fromRGB( 55,  55,  70),   -- dim grey
	keystone_bg  = Color3.fromRGB(200, 170,  50),   -- gold
	notable_bg   = Color3.fromRGB(100, 130, 200),   -- blue-ish
	small_bg     = Color3.fromRGB( 80,  80, 100),
	text         = Color3.fromRGB(220, 220, 230),
	text_dim     = Color3.fromRGB(140, 140, 160),
	line         = Color3.fromRGB( 45,  45,  65),
	line_active  = Color3.fromRGB( 60, 180, 100),
	btn_bg       = Color3.fromRGB( 35,  35,  52),
	btn_text     = Color3.fromRGB(105, 190, 255),
	btn_stroke   = Color3.fromRGB( 60, 100, 180),
	close_bg     = Color3.fromRGB(180,  50,  50),
	tooltip_bg   = Color3.fromRGB( 22,  22,  32),
}

-- Pre-compute node map once
local nodeMap = TreeConfig.GetNodeMap()

-- ── Helper: node visual color based on state ─────────────────────────────────
local function getNodeColor(nodeDef, isAllocated, isAllocatable)
	if isAllocated then return C.allocated end
	if isAllocatable then return C.allocatable end
	-- Locked — show type tint but dimmed
	return C.locked
end

local function getNodeBorderColor(nodeDef, isAllocated, isAllocatable)
	if nodeDef.type == "keystone" then return C.keystone_bg end
	if nodeDef.type == "notable"  then return C.notable_bg  end
	if isAllocated then return C.allocated end
	if isAllocatable then return C.allocatable end
	return C.small_bg
end

local function getNodeSizeMultiplier(nodeDef)
	if nodeDef.type == "keystone" then return 1.45 end
	if nodeDef.type == "notable"  then return 1.2  end
	return 1.0
end

-- ═══════════════════════════════════════════════════════════
-- TalentNode  (single clickable node)
-- ═══════════════════════════════════════════════════════════

local function TalentNode(props)
	local nodeDef       = props.nodeDef
	local isAllocated   = props.isAllocated
	local isAllocatable = props.isAllocatable
	local canRefund     = props.canRefund
	local onAllocate    = props.onAllocate
	local onRefund      = props.onRefund
	local onHover       = props.onHover
	local onLeave       = props.onLeave
	local canvasSize    = props.canvasSize   -- Vector2 (pixel dims of canvas)

	local sizeMul = getNodeSizeMultiplier(nodeDef)
	local px      = NODE_SIZE * sizeMul
	local drag    = props.dragOffset or Vector2.new(0, 0)

	-- Convert grid x/y to pixel position (center-anchored + pan offset)
	local pixelX = canvasSize.X * CENTER_X + nodeDef.x * GRID_CELL + drag.X
	local pixelY = canvasSize.Y * CENTER_Y + nodeDef.y * GRID_CELL + drag.Y

	local bgColor     = getNodeColor(nodeDef, isAllocated, isAllocatable)
	local borderColor = getNodeBorderColor(nodeDef, isAllocated, isAllocatable)

	return React.createElement("TextButton", {
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.fromOffset(pixelX, pixelY),
		Size             = UDim2.fromOffset(px, px),
		BackgroundColor3 = bgColor,
		BorderSizePixel  = 0,
		Text             = "",
		AutoButtonColor  = isAllocatable or canRefund,
		ZIndex           = 5,
		[React.Event.Activated] = function()
			if isAllocatable and not isAllocated then
				onAllocate(nodeDef.id)
			elseif isAllocated and canRefund then
				onRefund(nodeDef.id)
			end
		end,
		[React.Event.MouseEnter] = function()
			if onHover then onHover(nodeDef) end
		end,
		[React.Event.MouseLeave] = function()
			if onLeave then onLeave() end
		end,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		stroke = React.createElement("UIStroke", {
			Color     = borderColor,
			Thickness = (nodeDef.type == "keystone") and 3 or 2,
		}),
		label = React.createElement("TextLabel", {
			Size                   = UDim2.fromScale(0.85, 0.85),
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			Text                   = string.sub(nodeDef.name, 1, 5),
			TextColor3             = C.text,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			ZIndex                 = 6,
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- EdgeLine  (simple frame rotated between two points)
-- ═══════════════════════════════════════════════════════════

local function EdgeLine(props)
	local x1, y1 = props.x1, props.y1
	local x2, y2 = props.x2, props.y2
	local color  = props.color or C.line

	local dx = x2 - x1
	local dy = y2 - y1
	local length   = math.sqrt(dx * dx + dy * dy)
	local angle    = math.atan2(dy, dx)
	local midX     = (x1 + x2) / 2
	local midY     = (y1 + y2) / 2

	return React.createElement("Frame", {
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromOffset(midX, midY),
		Size                   = UDim2.fromOffset(length, 2),
		BackgroundColor3       = color,
		BorderSizePixel        = 0,
		Rotation               = math.deg(angle),
		ZIndex                 = 2,
	})
end

-- ═══════════════════════════════════════════════════════════
-- Tooltip  (floating info panel)
-- ═══════════════════════════════════════════════════════════

local function Tooltip(props)
	local nodeDef = props.nodeDef
	if not nodeDef then return nil end

	-- Build effects text.
	-- Effects use either { stat = "...", value = N } or { primary = "MIG"|..., value = N }.
	local lines = {}
	for _, eff in ipairs(nodeDef.effects or {}) do
		local label = eff.stat or eff.primary or "?"
		if eff.rule then
			table.insert(lines, "★ " .. label .. " (passive)")
		elseif eff.value ~= nil then
			local sign = eff.value >= 0 and "+" or ""
			table.insert(lines, sign .. tostring(eff.value) .. " " .. label)
		end
	end
	local effectsText = table.concat(lines, "\n")

	local typeLabel = string.upper(nodeDef.type or "")
	local costLabel = (nodeDef.cost or 1) > 0 and ("Cost: " .. (nodeDef.cost or 1) .. " point") or "Free"

	return React.createElement("Frame", {
		AnchorPoint      = Vector2.new(0.5, 0),
		Position         = UDim2.fromScale(0.5, 0.82),
		Size             = UDim2.fromScale(0.30, 0.16),
		BackgroundColor3 = C.tooltip_bg,
		BorderSizePixel  = 0,
		ZIndex           = 20,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.04, 0) }),
		stroke = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1 }),
		pad    = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0.02, 0), PaddingRight = UDim.new(0.02, 0),
			PaddingTop  = UDim.new(0.05, 0), PaddingBottom = UDim.new(0.05, 0),
		}),
		layout = React.createElement("UIListLayout", {
			FillDirection     = Enum.FillDirection.Vertical,
			SortOrder         = Enum.SortOrder.LayoutOrder,
			Padding           = UDim.new(0.02, 0),
		}),
		nameLbl = React.createElement("TextLabel", {
			Size               = UDim2.fromScale(1, 0.28),
			BackgroundTransparency = 1,
			Text               = nodeDef.name .. "  [" .. typeLabel .. "]",
			TextColor3         = C.text,
			Font               = Enum.Font.GothamBold,
			TextScaled         = true,
			TextXAlignment     = Enum.TextXAlignment.Left,
			LayoutOrder        = 1,
		}),
		descLbl = React.createElement("TextLabel", {
			Size               = UDim2.fromScale(1, 0.30),
			BackgroundTransparency = 1,
			Text               = nodeDef.description or "",
			TextColor3         = C.text_dim,
			Font               = Enum.Font.Gotham,
			TextScaled         = true,
			TextXAlignment     = Enum.TextXAlignment.Left,
			TextWrapped        = true,
			LayoutOrder        = 2,
		}),
		effectsLbl = React.createElement("TextLabel", {
			Size               = UDim2.fromScale(1, 0.25),
			BackgroundTransparency = 1,
			Text               = effectsText,
			TextColor3         = C.allocated,
			Font               = Enum.Font.GothamBold,
			TextScaled         = true,
			TextXAlignment     = Enum.TextXAlignment.Left,
			TextWrapped        = true,
			LayoutOrder        = 3,
		}),
		costLbl = React.createElement("TextLabel", {
			Size               = UDim2.fromScale(1, 0.15),
			BackgroundTransparency = 1,
			Text               = costLabel,
			TextColor3         = C.text_dim,
			Font               = Enum.Font.Gotham,
			TextScaled         = true,
			TextXAlignment     = Enum.TextXAlignment.Left,
			LayoutOrder        = 4,
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- TalentTreeUI  (root component)
-- ═══════════════════════════════════════════════════════════

local function TalentTreeUI(props)
	local onClose = props.onClose

	-- Talent state from server (subscribed)
	local talentState, setTalentState = React.useState(TalentClient.GetState())
	local hoveredNode, setHoveredNode = React.useState(nil)

	-- Pan / drag state
	local dragOffset, setDragOffset   = React.useState(Vector2.new(0, 0))
	local isDragging        = React.useRef(false)
	local dragStartMouse    = React.useRef(Vector2.new(0, 0))
	local offsetAtDragStart = React.useRef(Vector2.new(0, 0))
	local latestDragOffset  = React.useRef(Vector2.new(0, 0))  -- mirrors state without stale closures

	-- Canvas size (we need absolute pixels for positioning)
	local canvasRef   = React.useRef(nil)
	local canvasSize, setCanvasSize = React.useState(Vector2.new(1200, 800))

	React.useEffect(function()
		local unsub = TalentClient.Subscribe(function(newState)
			setTalentState({
				allocatedNodes  = newState.allocatedNodes,
				pointsSpent     = newState.pointsSpent,
				pointsTotal     = newState.pointsTotal,
				pointsAvailable = newState.pointsAvailable,
			})
		end)
		return function()
			if unsub then unsub() end
		end
	end, {})

	-- ── Global mouse-move / release for drag ─────────────────────────────────
	React.useEffect(function()
		local moveConn = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
			if not isDragging.current then return end
			local pos    = input.Position
			local delta  = Vector2.new(pos.X, pos.Y) - dragStartMouse.current
			local newOff = offsetAtDragStart.current + delta
			latestDragOffset.current = newOff
			setDragOffset(newOff)
		end)

		local endConn = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				isDragging.current = false
			end
		end)

		return function()
			moveConn:Disconnect()
			endConn:Disconnect()
		end
	end, {})

	-- Measure canvas on mount
	React.useEffect(function()
		task.defer(function()
			local canvas = canvasRef.current
			if canvas then
				setCanvasSize(Vector2.new(canvas.AbsoluteSize.X, canvas.AbsoluteSize.Y))
			end
		end)
	end, {})

	local allocated      = talentState.allocatedNodes or {}
	local allocatableSet = {}
	for _, id in ipairs(TalentClient.GetAllocatableNodes()) do
		allocatableSet[id] = true
	end

	-- ── Build node elements ───────────────────────────────────────────────────
	local children = {}

	-- Edges first (lower ZIndex)
	for i, edge in ipairs(TreeConfig.Edges) do
		local n1 = nodeMap[edge[1]]
		local n2 = nodeMap[edge[2]]
		if n1 and n2 then
			local x1 = canvasSize.X * CENTER_X + n1.x * GRID_CELL + dragOffset.X
			local y1 = canvasSize.Y * CENTER_Y + n1.y * GRID_CELL + dragOffset.Y
			local x2 = canvasSize.X * CENTER_X + n2.x * GRID_CELL + dragOffset.X
			local y2 = canvasSize.Y * CENTER_Y + n2.y * GRID_CELL + dragOffset.Y

			-- Highlight edge if both ends are allocated
			local lineColor = (allocated[edge[1]] and allocated[edge[2]]) and C.line_active or C.line

			children["edge_" .. i] = React.createElement(EdgeLine, {
				x1 = x1, y1 = y1, x2 = x2, y2 = y2, color = lineColor,
			})
		end
	end

	-- Nodes
	for _, nodeDef in ipairs(TreeConfig.Nodes) do
		local isAlloc  = allocated[nodeDef.id] == true
		local isAvail  = allocatableSet[nodeDef.id] == true
		local refundOk = isAlloc and TalentClient.CanRefund(nodeDef.id)

		children["node_" .. nodeDef.id] = React.createElement(TalentNode, {
			nodeDef       = nodeDef,
			isAllocated   = isAlloc,
			isAllocatable = isAvail,
			canRefund     = refundOk,
			canvasSize    = canvasSize,
			dragOffset    = dragOffset,
			onAllocate    = function(id) TalentClient.AllocateNode(id) end,
			onRefund      = function(id) TalentClient.RefundNode(id) end,
			onHover       = function(nd) setHoveredNode(nd) end,
			onLeave       = function() setHoveredNode(nil) end,
		})
	end

	-- ── Tooltip ───────────────────────────────────────────────────────────────
	children.tooltip = React.createElement(Tooltip, { nodeDef = hoveredNode })

	-- ── Root layout ───────────────────────────────────────────────────────────
	return React.createElement("Frame", {
		Name               = "TalentTreeUI",
		Size               = UDim2.fromScale(1, 1),
		BackgroundColor3   = C.bg,
		BackgroundTransparency = 0.05,
		BorderSizePixel    = 0,
		ZIndex             = 10,
	}, {
		-- Header bar
		header = React.createElement("Frame", {
			Size             = UDim2.fromScale(1, 0.07),
			BackgroundColor3 = C.panel,
			BorderSizePixel  = 0,
			ZIndex           = 12,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 0) }),
			title = React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.02, 0),
				Size                   = UDim2.fromScale(0.30, 1),
				BackgroundTransparency = 1,
				Text                   = "Talent Tree",
				TextColor3             = C.text,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
				ZIndex                 = 13,
			}),
			points = React.createElement("TextLabel", {
				AnchorPoint            = Vector2.new(0.5, 0.5),
				Position               = UDim2.fromScale(0.5, 0.5),
				Size                   = UDim2.fromScale(0.30, 0.7),
				BackgroundTransparency = 1,
				Text                   = string.format(
					"Points: %d / %d   (Available: %d)",
					talentState.pointsSpent or 0,
					talentState.pointsTotal or 0,
					talentState.pointsAvailable or 0
				),
				TextColor3 = C.btn_text,
				Font       = Enum.Font.GothamBold,
				TextScaled = true,
				ZIndex     = 13,
			}),
			-- Respec uses 1 Respec Token if owned, otherwise 500 Essence
			respecBtn = React.createElement("TextButton", {
				AnchorPoint      = Vector2.new(1, 0.5),
				Position         = UDim2.fromScale(0.88, 0.5),
				Size             = UDim2.fromScale(0.16, 0.65),
				BackgroundColor3 = Color3.fromRGB(140, 50, 50),
				BorderSizePixel  = 0,
				Text             = "Respec  (Token / 500 ♦)",
				TextColor3       = C.btn_text,
				Font             = Enum.Font.GothamBold,
				TextScaled       = true,
				ZIndex           = 13,
				[React.Event.Activated] = function()
					TalentClient.RespecAll()
				end,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
				stroke = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1 }),
			}),
			closeBtn = React.createElement("TextButton", {
				AnchorPoint      = Vector2.new(1, 0.5),
				Position         = UDim2.fromScale(0.995, 0.5),
				Size             = UDim2.fromScale(0.04, 0.65),
				BackgroundColor3 = C.close_bg,
				BorderSizePixel  = 0,
				Text             = "✕",
				TextColor3       = C.text,
				Font             = Enum.Font.GothamBold,
				TextScaled       = true,
				ZIndex           = 13,
				[React.Event.Activated] = onClose,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
			}),
		}),

		-- Canvas (absolute layout for nodes + edges)
		canvas = React.createElement("Frame", {
			Position               = UDim2.fromScale(0, 0.07),
			Size                   = UDim2.fromScale(1, 0.93),
			BackgroundTransparency = 1,
			ClipsDescendants       = true,
			ZIndex                 = 11,
			ref                    = canvasRef,
			-- Drag starts when pressing the canvas background (node buttons consume
			-- their own InputBegan, so this only fires on empty-space clicks).
			[React.Event.InputBegan] = function(_, input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					isDragging.current        = true
					dragStartMouse.current    = Vector2.new(input.Position.X, input.Position.Y)
					offsetAtDragStart.current = latestDragOffset.current
				end
			end,
		}, children),

		-- Legend (bottom-left)
		legend = React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0, 1),
			Position         = UDim2.fromScale(0.01, 0.98),
			Size             = UDim2.fromScale(0.18, 0.08),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.3,
			BorderSizePixel  = 0,
			ZIndex           = 15,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.15, 0) }),
			pad    = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0.03, 0), PaddingRight = UDim.new(0.03, 0),
			}),
			lbl = React.createElement("TextLabel", {
				Size               = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text               = "Click = Allocate  |  Drag background = Pan",
				TextColor3         = C.text_dim,
				Font               = Enum.Font.Gotham,
				TextScaled         = true,
				ZIndex             = 16,
			}),
		}),
	})
end

return TalentTreeUI
