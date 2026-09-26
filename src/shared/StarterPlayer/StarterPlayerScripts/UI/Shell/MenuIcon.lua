-- UI/Shell/MenuIcon.lua
--[[
    §AGX/UI-P3: menu icon, menu tile and the menu model shared by every menu
    surface (shell-spec §2.1-§2.3, §4.5; B3). Rail, Flyout, Sheet and Radial
    all read the menu through this file, so they can never disagree about
    what is locked, what it says, or what a tap does.

    MenuIcon.Icon{ icon, glyph?, size = 28, dim = false, color?, zIndex?,
                   position?, anchorPoint?, layoutOrder? }
        Theme.GetIcon(icon) art when pasted; otherwise Theme.Glyphs[icon]
        (emoji/symbol, dimmed with TextTransparency); otherwise `glyph`
        (a short word such as "CHAR", >= 12 px, body-accent blue).

    MenuIcon.Tile{ item, size = Vector2(96,72), badge = 0, onActivated,
                   layoutOrder?, zIndex?, tileRef? }
        The 96x72 (Desktop 88x64) menu tile: Card's language (raised navy,
        12 px radius, subtle hairline, blue focus ring) with the icon on top,
        the label under it and, when locked, "🔒 <reason>" on a third line.
        A locked tile stays tappable: the tap explains why (toast).
        (Card itself is a left-thumbnail list row and does not fit 96x72.)

    MenuIcon.Model
        .placeFromScripts()        "Lobby" | "Plaza" | "Combat" (folder probe)
        .groups(place)             normalized Registry.forPlace:
            { { id, label, icon, glyph, flyout, items = { item... } } }
            item = { id, entry, kind, label, icon, glyph, available,
                     reasonKey, badgeKey }
        .reason(item, long?)       localized lock reason
        .activate(item, place, { from = "rail"|"menu", props? }) -> ok
            locked  -> toast with the long reason
            action  -> PanelStack.open(id) (= closeAll("self") + entry.run)
            panel   -> menu: PanelStack.replace(id); rail: open(id), or
                       close(id, "toggle") when it is already open
        .resolvePlace(prop, entryCtx) / .useEntry()
        .useStack()                PanelStack.useState() or an empty default
        .topOf(state)              -> topId, topProps
        .PanelStack() / .Registry()   nil-safe lazy requires (Agent A)
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local UIFolder      = script.Parent.Parent
local Common        = UIFolder:WaitForChild("Common")
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local Text          = require(Common:WaitForChild("Text"))
local Tooltip       = require(Common:WaitForChild("Tooltip"))
local Locale        = require(PlayerScripts:WaitForChild("Modules"):WaitForChild("Locale"))
local Badge         = require(script.Parent:WaitForChild("Badge"))

local e = React.createElement
local R = Theme.Roles
local MM = Theme.Metrics.menu

local MenuIcon = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Icon
-- ═══════════════════════════════════════════════════════════════════════════
function MenuIcon.Icon(props)
	local size = props.size or MM.tileIcon
	local icon = props.icon
	local dim = props.dim == true
	local z = props.zIndex or 1

	local imageId = nil
	if type(icon) == "string" then
		imageId = (string.sub(icon, 1, 13) == "rbxassetid://") and icon or Theme.GetIcon(icon)
	end

	local common = {
		Name                   = "Icon",
		AnchorPoint            = props.anchorPoint,
		Position               = props.position,
		Size                   = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		LayoutOrder            = props.layoutOrder,
		ZIndex                 = z,
	}

	if imageId then
		common.Image = imageId
		common.ImageColor3 = dim and R.text.disabled or Color3.new(1, 1, 1)
		common.ImageTransparency = dim and 0.45 or 0
		common.ScaleType = Enum.ScaleType.Fit
		return e("ImageLabel", common)
	end

	local symbol = type(icon) == "string" and Theme.Glyphs[icon] or nil
	if symbol then
		-- Emoji / symbol: colour emoji ignore TextColor3, so dim by alpha.
		common.Text = symbol
		common.TextColor3 = dim and R.text.disabled or (props.color and Theme.color(props.color) or R.text.primary)
		common.TextTransparency = dim and 0.5 or 0
		common.FontFace = Theme.FontFaces.bold
		common.TextSize = math.floor(size * 0.86)
		common.TextXAlignment = Enum.TextXAlignment.Center
		common.TextYAlignment = Enum.TextYAlignment.Center
		return e("TextLabel", common)
	end

	-- Word fallback (spec §2.1 "CHAR", "PROG" ...): >= 12 px, blue body accent.
	local word = props.glyph or (type(icon) == "string" and string.upper(string.sub(icon, 1, 4))) or "?"
	common.Size = UDim2.fromOffset(math.max(size, 40), size)
	common.Text = word
	common.TextColor3 = dim and R.text.disabled or R.accent.secondary
	common.FontFace = Theme.FontFaces.heavy
	common.TextScaled = true
	return e("TextLabel", common, {
		tsize = e("UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = math.max(12, math.floor(size * 0.6)) }),
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Model
-- ═══════════════════════════════════════════════════════════════════════════
local Model = {}
MenuIcon.Model = Model

-- Lazy, nil-safe requires of Agent A's modules. The result (including "not
-- there") is cached on first use so hook usage stays stable per session.
local depCache = {}
local function dep(name)
	local cached = depCache[name]
	if cached ~= nil then return cached or nil end
	local mod = script.Parent:FindFirstChild(name)
	local result = false
	if mod then
		local ok, value = pcall(require, mod)
		if ok and type(value) == "table" then
			result = value
		else
			warn("[MenuIcon] could not load Shell." .. name .. ": " .. tostring(value))
		end
	end
	depCache[name] = result
	return result or nil
end
function Model.PanelStack() return dep("PanelStack") end
function Model.Registry()   return dep("Registry") end

-- Registry.Groups fallback metadata (spec §2.1 table). Registry wins when it
-- carries the same fields.
local GROUP_META = {
	play      = { icon = "play",         glyph = "PLAY", label = "nav_group_play" },
	character = { icon = "classes",      glyph = "CHAR", label = "nav_group_character" },
	progress  = { icon = "achievements", glyph = "PROG", label = "nav_group_progress" },
	social    = { icon = "social",       glyph = "SOC",  label = "nav_group_social" },
	store     = { icon = "shop",         glyph = "SHOP", label = "nav_group_store" },
	system    = { icon = "settings",     glyph = "SET",  label = "nav_group_system" },
}
Model.GROUP_META = GROUP_META

local function loc(key, fallback)
	if type(key) ~= "string" or key == "" then return fallback or "" end
	if Locale.Has and Locale.Has(key) then return Locale.Get(key) end
	if Locale.Has then return fallback or key end   -- raw text passes through
	return Locale.Get(key)
end
Model.loc = loc

function Model.placeFromScripts()
	if PlayerScripts:FindFirstChild("Lobby") then return "Lobby" end
	if PlayerScripts:FindFirstChild("SocialPlaza") then return "Plaza" end
	return "Combat"
end

local function groupId(g)
	if type(g) == "string" then return g end
	if type(g) == "table" then
		local inner = g.group
		if type(inner) == "string" then return inner end
		if type(inner) == "table" then return inner.id or inner.name end
		return g.id or g.name
	end
	return nil
end

local function groupField(g, field)
	if type(g) ~= "table" then return nil end
	if type(g.group) == "table" and g.group[field] ~= nil then return g.group[field] end
	return g[field]
end

--- Normalized groups for a place (spec §2.3 Registry.forPlace). Empty when
--- the Registry has not landed.
function Model.groups(place)
	local reg = Model.Registry()
	if not reg or type(reg.forPlace) ~= "function" then return {} end
	local ok, raw = pcall(reg.forPlace, place)
	if not ok or type(raw) ~= "table" then
		if not ok then warn("[MenuIcon] Registry.forPlace failed: " .. tostring(raw)) end
		return {}
	end

	local out = {}
	for _, g in ipairs(raw) do
		local gid = groupId(g)
		local meta = GROUP_META[gid] or {}
		local items = {}
		for _, it in ipairs((type(g) == "table" and g.entries) or {}) do
			local entry = (type(it) == "table" and it.entry) or it
			if type(entry) == "table" and entry.id and entry.rail ~= false then
				local available = true
				if it.available ~= nil then available = it.available == true end
				local reasonKey = it.lockedReason
				if reasonKey == nil and type(entry.lockedReason) == "table" then
					reasonKey = entry.lockedReason[place]
				end
				if available then reasonKey = nil end
				items[#items + 1] = {
					id        = entry.id,
					entry     = entry,
					kind      = entry.kind or "panel",
					label     = loc(entry.label or ("nav_" .. entry.id), entry.id),
					icon      = entry.icon,
					glyph     = entry.glyph,
					available = available,
					reasonKey = reasonKey,
					badgeKey  = entry.badge,
				}
			end
		end
		if gid and #items > 0 then
			-- The play group's face is its (only) entry: PLAY in the Lobby,
			-- the exit door elsewhere.
			local face = (gid == "play") and items[1] or nil
			local labelKey = groupField(g, "label") or meta.label
			if gid == "play" and face and face.id ~= "play" then labelKey = "nav_group_exit" end
			out[#out + 1] = {
				id     = gid,
				label  = loc(labelKey, gid),
				icon   = (face and face.icon) or groupField(g, "icon") or meta.icon,
				glyph  = (face and face.glyph) or groupField(g, "glyph") or meta.glyph,
				-- D3 (Pablo): flyouts only for Character and Progress.
				flyout = (MM.flyoutGroups[gid] == true) and #items > 1,
				items  = items,
			}
		end
	end
	return out
end

function Model.availableCount(group)
	local n = 0
	for _, it in ipairs(group.items) do
		if it.available then n += 1 end
	end
	return n
end

function Model.badgeKeys(items)
	local keys = {}
	for _, it in ipairs(items) do
		if it.badgeKey and it.available then keys[#keys + 1] = it.badgeKey end
	end
	return keys
end

function Model.reason(item, long)
	local key = item.reasonKey or "nav_locked"
	if long and type(key) == "string" and Locale.Has and Locale.Has(key .. "_long") then
		return Locale.Get(key .. "_long")
	end
	return loc(key, loc("nav_locked_generic", "Locked"))
end

local function toast(text)
	local mod = Common:FindFirstChild("Notify")
	if not mod then return end
	local ok, Notify = pcall(require, mod)
	if ok and type(Notify) == "table" and Notify.toast then
		Notify.toast("info", text, { key = "nav_locked" })
	end
end
Model.toast = toast

-- Fallback actions for when PanelStack is absent (it normally runs
-- entry.run itself: open(id) on an action = closeAll("self") then run).
local ACTIONS = {}

function ACTIONS.emotes()
	local mod = UIFolder:FindFirstChild("EmoteWheel")
	if not mod then return false end
	local ok, EmoteWheel = pcall(require, mod)
	if ok and type(EmoteWheel) == "table" and EmoteWheel.toggle then
		EmoteWheel.toggle()
		return true
	end
	return false
end
-- `leave` has no fallback on purpose: never leave without the confirm,
-- and the confirm is a PanelStack modal (Registry `leaveConfirm`).
Model.ACTIONS = ACTIONS

function Model.activate(item, place, opts)
	opts = opts or {}
	if not item then return false end
	if not item.available then
		toast(Model.reason(item, true))
		return false
	end

	local PS = Model.PanelStack()
	if not PS then
		local fn = (item.kind == "action") and ACTIONS[item.id] or nil
		return fn ~= nil and fn(place) ~= false
	end

	-- Actions: PanelStack.open/replace run closeAll("self") then entry.run.
	if item.kind == "action" then
		return PS.open(item.id, opts.props) ~= false
	end
	-- Menu surfaces give way to the chosen panel (§3.2 rule 1).
	if opts.from == "menu" and type(PS.replace) == "function" then
		return PS.replace(item.id, opts.props) ~= false
	end
	-- Rail: a second tap on the open entry closes it.
	if type(PS.isOpen) == "function" and PS.isOpen(item.id) and type(PS.close) == "function" then
		PS.close(item.id, "toggle")
		return true
	end
	return PS.open(item.id, opts.props) ~= false
end

--- Place for a menu surface: explicit prop > PanelHost entry > PanelStack >
--- PlayerScripts probe.
function Model.resolvePlace(propPlace, entryCtx)
	if propPlace then return propPlace end
	if type(entryCtx) == "table" and entryCtx.place then return entryCtx.place end
	local PS = Model.PanelStack()
	if PS and type(PS.getPlace) == "function" then
		local p = PS.getPlace()
		if p then return p end
	end
	return Model.placeFromScripts()
end

--- PanelHost entry context ({ id, presentation, dismissable, onBackdrop,
--- top, place }) or nil outside a PanelHost. Stable hook (the PanelStack
--- lookup is cached for the session).
function Model.useEntry()
	local PS = Model.PanelStack()
	if PS and type(PS.useEntry) == "function" then return PS.useEntry() end
	return nil
end

local EMPTY_STATE = { stack = {}, top = nil, blocked = false, suspended = false, hudMode = "full" }
function Model.useStack()
	local PS = Model.PanelStack()
	if PS and type(PS.useState) == "function" then
		return PS.useState() or EMPTY_STATE
	end
	return EMPTY_STATE
end

--- -> top id, top props (PanelStack snapshot: top = id, stack[i] = { id, entry, props }).
function Model.topOf(state)
	local top = state and state.top
	if type(top) == "table" then return top.id, top.props end
	local list = state and state.stack
	local rec = type(list) == "table" and list[#list] or nil
	return top, (type(rec) == "table" and rec.id == top) and rec.props or nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Tile
-- ═══════════════════════════════════════════════════════════════════════════
function MenuIcon.Tile(props)
	local ff = useFormFactor()
	local item = props.item
	local locked = not item.available
	local size = props.size or Vector2.new(96, 72)
	local tip = Tooltip.use(locked and Model.reason(item, true) or nil)
	local pressed, setPressed = React.useState(false)
	local focused, setFocused = React.useState(false)
	local z = props.zIndex or 1

	local labelTy = Theme.typeFor("label", ff.kind)
	local iconSize = (size.Y >= 72) and MM.tileIcon or 24
	local compact = locked   -- three lines: icon, label, reason
	local iconY = compact and 5 or math.floor((size.Y - iconSize - 18 - 4) / 2)
	local labelH = (size.Y >= 72) and math.min(labelTy.size + 3, 18) or 15
	local labelY = iconY + iconSize + (compact and 1 or 4)

	local fill = R.surface.raised
	if locked then fill = R.surface.sunken elseif pressed then fill = Theme.Palette.navy650 end

	return e("TextButton", {
		Name                   = "Tile_" .. tostring(item.id),
		Size                   = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3       = fill,
		BackgroundTransparency = 0,
		BorderSizePixel        = 0,
		AutoButtonColor        = false,
		Active                 = true,
		Selectable             = true,
		Text                   = "",
		LayoutOrder            = props.layoutOrder,
		ZIndex                 = z,
		[React.Ref]            = props.tileRef,
		[React.Event.InputBegan] = function(rbx, input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then setPressed(true) end
			tip.onInputBegan(rbx, input)
		end,
		[React.Event.InputEnded] = function(_rbx, input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then setPressed(false) end
		end,
		[React.Event.MouseEnter] = function(rbx) setFocused(true); tip.onMouseEnter(rbx) end,
		[React.Event.MouseLeave] = function(rbx) setFocused(false); setPressed(false); tip.onMouseLeave(rbx) end,
		[React.Event.SelectionGained] = function(rbx) setFocused(true); tip.onSelectionGained(rbx) end,
		[React.Event.SelectionLost]   = function(rbx) setFocused(false); tip.onSelectionLost(rbx) end,
		[React.Event.Activated] = tip.wrapActivated(props.onActivated),
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.lg }),
		stroke = e("UIStroke", {
			Color           = focused and R.border.focus or R.border.subtle,
			Transparency    = focused and 0 or (locked and 0.6 or 0.35),
			Thickness       = focused and Theme.Stroke.focus or Theme.Stroke.base,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		icon = e(MenuIcon.Icon, {
			icon        = item.icon,
			glyph       = item.glyph,
			size        = iconSize,
			dim         = locked,
			anchorPoint = Vector2.new(0.5, 0),
			position    = UDim2.new(0.5, 0, 0, iconY),
			zIndex      = z + 1,
		}),
		label = e(Text, {
			style  = "label",
			text   = item.label,
			color  = locked and "text.secondary" or "text.primary",
			align  = "center",
			fit    = true,
			size   = UDim2.new(1, -8, 0, labelH),
			anchorPoint = Vector2.new(0.5, 0),
			position    = UDim2.new(0.5, 0, 0, labelY),
			zIndex = z + 1,
		}),
		-- `label` style: its per-form-factor floor is 12 px (spec §4.5 >= 12);
		-- the 14 px box keeps TextScaled at 12-13.
		reason = locked and e(Text, {
			style  = "label",
			text   = Theme.Glyphs.lock .. " " .. Model.reason(item, false),
			color  = "text.secondary",
			align  = "center",
			fit    = true,
			size   = UDim2.new(1, -6, 0, 14),
			anchorPoint = Vector2.new(0.5, 1),
			position    = UDim2.new(0.5, 0, 1, -4),
			zIndex = z + 1,
		}) or nil,
		badge = (not locked) and e(Badge.View, { count = props.badge or 0, zIndex = z + 3 }) or nil,
	})
end

return MenuIcon
