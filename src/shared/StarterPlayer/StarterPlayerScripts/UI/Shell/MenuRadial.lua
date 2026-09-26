-- UI/Shell/MenuRadial.lua
--[[
    §AGX/UI-P3: radial menu (class menu; Console, or any Gamepad input;
    shell-spec §4.5, B6). Opened by MenuSurface: open("menuRadial", { place }).

    Stage 1: the 6 groups clockwise from 12 o'clock (Registry.Groups order).
    Stage 2: the chosen group's entries (up to 6). A group with ONE entry
             (Play/Exit, Store, System) runs it straight from stage 1.
    Geometry: EmoteWheel.wheelMetrics(viewport, { shortFrac 0.62, min 320,
              max 560 }) in SCREEN px (like the emote wheel), converted to
              design px; buttons >= 64 design px.
    Input (ContextActionService at High+2, Sink while open *(verify in
    Studio)*):
        Left stick     highlight by direction (deadzone 0.5); the sink also
                       keeps the character from walking
        DPad L / R     step the highlight
        A              confirm
        B              stage 2 -> stage 1; stage 1 -> close. B is NOT bound
                       here: PanelStack owns Back (UIBack + its CAS sink,
                       debounced) and this menu vetoes a "back" close while
                       in stage 2 (useCloseHandler), stepping back instead.
        DPadDown       hold >= 0.25 s (the press that opened the menu), move
                       the stick, release -> confirm the highlighted wedge.
                       A plain tap-release does nothing; a second press is
                       MenuToggle -> closeAll (MenuSurface).
    Mouse / touch also work: hover highlights, click confirms.
    Centre disc: highlighted name, then its lock reason (long) or badge.
]]

local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService     = game:GetService("UserInputService")
local React = require(ReplicatedStorage.Packages.React)

local UIFolder      = script.Parent.Parent
local Common        = UIFolder:WaitForChild("Common")
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))
local Text          = require(Common:WaitForChild("Text"))
local Badge         = require(script.Parent:WaitForChild("Badge"))
local MenuIcon      = require(script.Parent:WaitForChild("MenuIcon"))

local e = React.createElement
local R = Theme.Roles
local MM = Theme.Metrics.menu
local Model = MenuIcon.Model

local CAS_NAME = "RD_MenuRadial"
local CAS_PRIORITY = Enum.ContextActionPriority.High.Value + 2
local DEFAULT_RADIAL = { min = 320, max = 560, btnMin = 64 }

-- EmoteWheel.wheelMetrics (B6 export), with a local copy as the fallback.
local wheelMetrics = nil
do
	local mod = UIFolder:FindFirstChild("EmoteWheel")
	if mod then
		local ok, EW = pcall(require, mod)
		if ok and type(EW) == "table" and type(EW.wheelMetrics) == "function" then
			wheelMetrics = EW.wheelMetrics
		end
	end
	if not wheelMetrics then
		wheelMetrics = function(viewport, opts)
			local short = math.min(viewport.X, viewport.Y)
			if short <= 0 then short = 720 end
			local wheel = math.clamp(math.floor(short * opts.shortFrac), opts.min, opts.max)
			local btn = math.max(opts.btnMin, math.floor(wheel * 0.26))
			return wheel, btn, math.floor(wheel / 2 - btn / 2 - 6)
		end
	end
end

--- Clockwise-from-12 index (1..n) for a stick vector (x right, y up).
local function indexFromStick(x, y, n)
	local deg = math.deg(math.atan2(x, y)) % 360
	local step = 360 / n
	return (math.floor((deg + step / 2) / step) % n) + 1
end

local function Wedge(props)
	local w = props.wedge
	local z = props.zIndex
	local hi = props.highlighted
	local side = props.size
	return e("TextButton", {
		Name                   = "Wedge_" .. tostring(w.id),
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = props.position,
		Size                   = UDim2.fromOffset(side, side),
		BackgroundColor3       = hi and Theme.Palette.navy650 or (w.locked and R.surface.sunken or R.surface.raised),
		BorderSizePixel        = 0,
		AutoButtonColor        = false,
		Selectable             = false,   -- the stick drives the highlight, not GuiService
		Text                   = "",
		ZIndex                 = z,
		[React.Event.MouseEnter] = props.onHover,
		[React.Event.Activated]  = props.onActivated,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
		stroke = e("UIStroke", {
			Color           = hi and R.border.focus or R.border.subtle,
			Thickness       = hi and Theme.Stroke.focus + 0.5 or Theme.Stroke.base,
			Transparency    = hi and 0 or 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		scale = e("UIScale", { Scale = hi and 1.08 or 1 }),
		icon = e(MenuIcon.Icon, {
			icon        = w.icon,
			glyph       = w.glyph,
			size        = math.floor(side * 0.42),
			dim         = w.locked,
			anchorPoint = Vector2.new(0.5, 0.5),
			position    = UDim2.new(0.5, 0, 0.42, 0),
			zIndex      = z + 1,
		}),
		label = e(Text, {
			style       = "label",
			text        = w.label,
			color       = w.locked and "text.secondary" or "text.primary",
			align       = "center",
			fit         = true,
			size        = UDim2.new(0.86, 0, 0, 16),
			anchorPoint = Vector2.new(0.5, 0),
			position    = UDim2.new(0.5, 0, 0.66, 0),
			zIndex      = z + 1,
		}),
		badge = (not w.locked) and e(Badge.View, {
			count = w.badge, zIndex = z + 3,
			position = UDim2.new(0.85, 0, 0.15, 0),
		}) or nil,
	})
end

local function MenuRadial(props)
	local ff = useFormFactor()
	local scale = UIScaleRoot.useUIScale()
	local getBadge = Badge.useBadges()
	local entryCtx = Model.useEntry()
	local place = Model.resolvePlace(props.place, entryCtx)
	local groups = React.useMemo(function() return Model.groups(place) end, { place })
	local stage, setStage = React.useState(nil)   -- nil = groups, else a group id
	local hi, setHi = React.useState(1)

	-- Wedges for the current stage.
	local stageGroup = nil
	if stage then
		for _, g in ipairs(groups) do
			if g.id == stage then stageGroup = g end
		end
	end
	local wedges = {}
	if stageGroup then
		for _, it in ipairs(stageGroup.items) do
			if #wedges >= 6 then break end
			wedges[#wedges + 1] = {
				id = it.id, label = it.label, icon = it.icon, glyph = it.glyph,
				locked = not it.available,
				reason = (not it.available) and Model.reason(it, true) or nil,
				badge = getBadge(it.badgeKey), item = it,
			}
		end
	else
		for _, g in ipairs(groups) do
			local only = (#g.items == 1) and g.items[1] or nil
			local locked = Model.availableCount(g) == 0
			wedges[#wedges + 1] = {
				id = g.id,
				label = only and only.label or g.label,
				icon = g.icon, glyph = g.glyph,
				locked = locked,
				reason = (locked and g.items[1]) and Model.reason(g.items[1], true) or nil,
				badge = Badge.sum(getBadge, Model.badgeKeys(g.items)),
				group = g, item = only,
			}
		end
	end
	local n = #wedges

	-- Latest values for the input callbacks (bound once).
	local live = React.useRef({})
	live.current.wedges = wedges
	live.current.hi = hi
	live.current.stage = stage

	local function close(reason)
		if props.onClose then props.onClose(reason) end
	end

	local function confirm(i)
		local w = live.current.wedges[i]
		if not w then return end
		if w.item then
			-- A single-entry group or a stage-2 entry: run it (locked -> toast).
			Model.activate(w.item, place, { from = "menu" })
		elseif w.group then
			if w.locked then
				Model.toast(w.reason or Model.reason(w.group.items[1], true))
				return
			end
			setStage(w.group.id)
			setHi(1)
		end
	end

	local function back()
		local s = live.current.stage
		if s then
			local idx = 1
			for gi, g in ipairs(groups) do
				if g.id == s then idx = gi end
			end
			setStage(nil)
			setHi(idx)
		else
			close("back")
		end
	end

	local liveFns = React.useRef({})
	liveFns.current.confirm = confirm
	liveFns.current.back = back

	-- Back (B / Backspace) from PanelStack: stage 2 steps back to stage 1.
	local PS = Model.PanelStack()
	if PS and type(PS.useCloseHandler) == "function" then
		PS.useCloseHandler(function(reason)
			if reason == "back" and live.current.stage ~= nil then
				liveFns.current.back()
				return false
			end
			return nil
		end)
	end

	-- Gamepad input while open.
	React.useEffect(function()
		local stickMoved = false
		local openedAt = os.clock()
		local dpadHeld = false
		pcall(function()
			dpadHeld = UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.DPadDown)
		end)

		local function handler(_, state, input)
			local key = input.KeyCode
			if key == Enum.KeyCode.Thumbstick1 then
				local pos = input.Position
				if Vector2.new(pos.X, pos.Y).Magnitude >= MM.radialDeadzone then
					local count = #live.current.wedges
					if count > 0 then
						stickMoved = true
						local idx = indexFromStick(pos.X, pos.Y, count)
						if idx ~= live.current.hi then setHi(idx) end
					end
				end
				return Enum.ContextActionResult.Sink
			end
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Sink
			end
			if key == Enum.KeyCode.ButtonA then
				liveFns.current.confirm(live.current.hi)
			elseif key == Enum.KeyCode.DPadRight or key == Enum.KeyCode.DPadLeft then
				local count = #live.current.wedges
				if count > 0 then
					local d = (key == Enum.KeyCode.DPadRight) and 1 or -1
					setHi(((live.current.hi - 1 + d) % count) + 1)
				end
			end
			return Enum.ContextActionResult.Sink
		end
		ContextActionService:BindActionAtPriority(CAS_NAME, handler, false, CAS_PRIORITY,
			Enum.KeyCode.Thumbstick1, Enum.KeyCode.ButtonA,
			Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight)

		-- Hold-and-release DPadDown confirm (not bound in CAS: MenuToggle
		-- must keep seeing DPadDown presses).
		local endedConn = UserInputService.InputEnded:Connect(function(input)
			if input.KeyCode ~= Enum.KeyCode.DPadDown or not dpadHeld then return end
			dpadHeld = false
			if stickMoved and os.clock() - openedAt >= MM.holdConfirm then
				liveFns.current.confirm(live.current.hi)
			end
		end)

		return function()
			ContextActionService:UnbindAction(CAS_NAME)
			endedConn:Disconnect()
		end
	end, {})

	-- Geometry (design px).
	local target = scale.target
	local radial = (ff.design.rail and ff.design.rail.radial) or DEFAULT_RADIAL
	local wheelPx, btnPx = wheelMetrics(ff.viewport, {
		shortFrac = MM.radialShortFrac,
		min       = radial.min or DEFAULT_RADIAL.min,
		max       = radial.max or DEFAULT_RADIAL.max,
		btnMin    = math.floor((radial.btnMin or DEFAULT_RADIAL.btnMin) * target),
	})
	local wheel = wheelPx / target
	local btn = math.max(radial.btnMin or DEFAULT_RADIAL.btnMin, math.floor(btnPx / target))
	local radius = math.floor(wheel / 2 - btn / 2 - 6)
	local centreD = math.max(btn * 1.5, wheel - 2 * btn - 24)

	local wheelChildren = {
		corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
		stroke = e("UIStroke", {
			Color = R.border.subtle, Thickness = Theme.Stroke.base, Transparency = 0.2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	}
	for i, w in ipairs(wedges) do
		local rad = math.rad(-90 + (i - 1) * 360 / math.max(1, n))
		wheelChildren["w" .. i] = e(Wedge, {
			wedge       = w,
			size        = btn,
			highlighted = i == hi,
			zIndex      = 5,
			position    = UDim2.new(0.5, math.floor(radius * math.cos(rad) + 0.5),
				0.5, math.floor(radius * math.sin(rad) + 0.5)),
			onHover     = function() setHi(i) end,
			onActivated = function() setHi(i); confirm(i) end,
		})
	end

	local cur = wedges[hi]
	local sub = nil
	if cur then
		if cur.locked then
			sub = Theme.Glyphs.lock .. " " .. (cur.reason or "")
		elseif cur.badge and cur.badge > 0 then
			sub = "● " .. tostring(cur.badge)
		elseif cur.group and not cur.item then
			sub = "›"
		end
	end
	wheelChildren.centre = e("Frame", {
		Name             = "Centre",
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.fromScale(0.5, 0.5),
		Size             = UDim2.fromOffset(centreD, centreD),
		BackgroundColor3 = R.surface.sunken,
		BorderSizePixel  = 0,
		ZIndex           = 4,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
		layout = e("UIListLayout", {
			FillDirection       = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment   = Enum.VerticalAlignment.Center,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Padding             = UDim.new(0, Theme.Space.xs),
		}),
		crumb = stageGroup and e(Text, {
			style = "label", text = "‹ " .. stageGroup.label, upper = true,
			color = "text.link", align = "center",
			size = UDim2.new(0.8, 0, 0, 18), layoutOrder = 1, zIndex = 5,
		}) or nil,
		name = e(Text, {
			style = "heading", text = cur and cur.label or "", align = "center",
			color = (cur and cur.locked) and "text.secondary" or "text.primary",
			size = UDim2.new(0.8, 0, 0, 26), layoutOrder = 2, zIndex = 5,
		}),
		sub = sub and e(Text, {
			style = "label", text = sub, align = "center", wrap = true,
			color = (cur and cur.locked) and "text.secondary" or "text.link",
			size = UDim2.new(0.78, 0, 0, 0), layoutOrder = 3, zIndex = 5,
		}) or nil,
	})

	return e(UIScaleRoot.Local, { name = "MenuRadial", zIndex = 2 }, {
		-- Non-interactive dim: PanelHost's D8 scrim (behind) takes outside
		-- clicks; outside a PanelHost this dim is a button itself.
		dim = e((entryCtx == nil) and "TextButton" or "Frame", {
			Name                   = "Dim",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundColor3       = R.surface.scrim,
			BackgroundTransparency = Theme.Elevation.overlay.scrim,
			BorderSizePixel        = 0,
			ZIndex                 = 2,
			Text                   = (entryCtx == nil) and "" or nil,
			AutoButtonColor        = if entryCtx == nil then false else nil,
			[React.Event.Activated] = (entryCtx == nil) and function() close("backdrop") end or nil,
		}),
		wheel = e("Frame", {
			Name                   = "Wheel",
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			Size                   = UDim2.fromOffset(wheel, wheel),
			BackgroundColor3       = R.surface.panel,
			BackgroundTransparency = 0.1,
			BorderSizePixel        = 0,
			Active                 = true,
			ZIndex                 = 3,
		}, wheelChildren),
		hint = e(Text, {
			style       = "label",
			text        = Model.loc("nav_hint_radial", ""),
			color       = "text.secondary",
			align       = "center",
			anchorPoint = Vector2.new(0.5, 0),
			position    = UDim2.new(0.5, 0, 0.5, wheel / 2 + Theme.Space.md),
			size        = UDim2.fromOffset(math.max(wheel, 360), 22),
			zIndex      = 3,
		}),
	})
end

return MenuRadial
