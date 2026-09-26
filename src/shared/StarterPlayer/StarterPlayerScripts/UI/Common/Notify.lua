-- UI/Common/Notify.lua
--[[
    §AGX/UI-P4: Notify, the ONE player-feedback system (UI_REVAMP §3 "Notify",
    docs/ui_audit/structure-and-flow.md UX-11 / §3.4). It replaces the five
    ad-hoc mechanisms (inline timers, HUD transient labels, the achievement
    toast queue, LootNotification's own ScreenGui, and server `warn`-only
    rejections) with four kinds, each with ONE screen region and ONE timing:

      kind     region                timing                     use for
      ───────  ────────────────────  ─────────────────────────  ────────────────────────────
      toast    top-right stack       3.5 s, max 3 visible,      action results, rejections
                                     rest queued, ✕ dismiss
      banner   top-centre, 1 slot    priority queue; stale      wave / boss phase / vote /
                                     entries are dropped        run state / achievement
      feed     right, under toasts   4 s, stacking + fading,    killfeed, loot counters
                                     same key = update in place
      inline   inside the panel      UI/Common/useRequest.lua   "Purchasing…" → ok / err

    CLIENT API (any LocalScript / ModuleScript, React or not):
        Notify.toast(kind, text, opts?)        kind = "info"|"success"|"warning"|"error"
            opts.key       coalesce: same key updates the visible toast (×N)
            opts.duration  seconds (default 3.5)
          -> id
        Notify.banner(text, opts?)
            opts.subtitle, opts.color (Color3), opts.key (same key replaces)
            opts.priority  number or Notify.Priority name (default "info")
            opts.duration  seconds (default 3); opts.sticky = true stays until
                           Notify.clearBanner(key) or a same-key replacement
            opts.staleAfter seconds a queued banner may wait (default 6)
          -> id
        Notify.clearBanner(key)
        Notify.feed(text, opts?)
            opts.key (same key = update + pulse), opts.color, opts.duration (4)
          -> id
        Notify.dismiss(id)                     remove a toast now
        Notify.onInline(cb) -> unsubscribe     server "inline" replies (useRequest)
        Notify.subscribe(cb) -> unsubscribe    raw store snapshots
        Notify.getState()

    SERVER: NotifyService.Toast/Banner/Feed/Inline(player | "all" | {players}, …)
    push the same shapes over the one "Notify" RemoteEvent; this module
    listens to it once, at first require.

    COMPONENTS: mount `Notify.Host` exactly ONCE per place (CombatApp covers
    LaneDefense/HordeMode/CentralBoss; LobbyApp; SocialPlazaApp). It renders
    its own ScreenGui ("NotifyGui", DeviceSafeInsets) holding ToastHost,
    BannerHost and FeedHost. Queued notifications raised before the host
    mounts are kept in the store and appear once it does.

    STYLE: D1 (visual direction) is pending, so colours and fonts come only
    from Theme.Colors / Theme.Fonts, sizes from Theme.Layout[formFactor]
    (via useFormFactor), and every Notify-specific number lives in GEOMETRY
    below. Restyling = editing that one table.
]]

local Notify = {}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local React       = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local e = React.createElement

local player        = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")
local Modules       = PlayerScripts:WaitForChild("Modules")
local Common        = script.Parent

local Theme          = require(Common:WaitForChild("Theme"))
local useFormFactor  = require(Common:WaitForChild("useFormFactor"))
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

local C = Theme.Colors
local F = Theme.Fonts

-- ═══════════════════════════════════════════════════════════
-- GEOMETRY (§AGX/UI-P4: the one table to restyle once D1 lands)
-- ═══════════════════════════════════════════════════════════
-- Offset pixels unless noted. Form-factor sizes (edge, fonts, minTarget)
-- come from Theme.Layout via useFormFactor(); these are Notify's own.
local GEOMETRY = {
	-- ScreenGui band. AppGui = 0, CombatControls = 1 (Theme.Layout),
	-- JoystickAim/legacy 5, SkillVisuals 8. Modals are reserved >= 40
	-- (structure-and-flow §3.3 "Layers"), LoadingScreen = 1000.
	displayOrder = 30,

	minText    = 12,    -- absolute text floor (mobile.md §1.3)
	minDismiss = 44,    -- absolute tap-target floor for ✕
	topGap     = 10,    -- px below the Roblox topbar (matches HUD safeTop)
	rightEdge  = 8,     -- px from the safe-area right edge (TeammateVitals)
	gap        = 8,     -- between stacked items / regions
	radius     = 8,
	stroke     = 1.5,

	-- Client-local layout attributes the HUD/BossHud publish on
	-- ReplicatedStorage (HUD.lua ATTR_*), so Notify stays clear of them.
	attrTopRightBottom = "UI_TopRightBottomPx",
	attrTopCentre      = "UI_TopCentreReservedPx",

	toast = {
		duration      = 3.5,
		maxVisible    = 3,
		maxPending    = 12,     -- oldest pending dropped beyond this
		width         = 340,
		maxWidthScale = 0.40,   -- of the safe-area width (phones)
		minHeight     = 48,
		accentBar     = 4,
		glyphW        = 22,
		pad           = 8,
		bgTransparency = 0.06,
		strokeTransparency = 0.35,
	},

	banner = {
		duration      = 3.0,
		staleAfter    = 6,      -- a queued banner older than this is dropped
		minTop        = 88,     -- px below safeTop: clears HUD Start/Next (HUD.lua bannerY)
		width         = 460,
		maxWidthScale = 0.56,
		pad           = 8,
		stroke        = 2,
		bgTransparency = 0.12,
	},

	feed = {
		duration      = 4.0,    -- LootNotification DISPLAY_TIMEOUT / HUD killfeed
		fade          = 0.5,
		maxBuffer     = 6,
		maxLines      = { Phone = 3, Tablet = 4, Desktop = 5, Console = 4 },
		lineHeight    = 26,
		width         = 260,
		maxWidthScale = 0.32,
		pad           = 8,
		pulseScale    = 1.12,
		pulseTime     = 0.12,
		bgTransparency = 0.35,
	},
}
Notify.GEOMETRY = GEOMETRY

-- Toast kinds → Theme colour + glyph (glyph so colour is never the only cue).
local TOAST_KINDS = {
	info    = { color = C.accent2, glyph = "i" },
	success = { color = C.good,    glyph = "✓" },
	warning = { color = C.warn,    glyph = "!" },
	error   = { color = C.bad,     glyph = "×" },
}

-- Banner priorities, highest wins (structure-and-flow §3.4:
-- boss phase > run state > wave > matchmaking > achievement; vote alerts
-- sit between run state and wave). Read from BossHud (BossPhaseChanged,
-- 3.5 s), HUD (Wave N / cleared 3 s, all-cleared + defense destroyed
-- sticky), VoteUI and the old achievement toast (4 s).
Notify.Priority = {
	bossPhase   = 50,
	runState    = 40,
	vote        = 35,
	wave        = 30,
	matchmaking = 20,
	achievement = 10,
	info        = 10,
}

-- ═══════════════════════════════════════════════════════════
-- STORE
-- ═══════════════════════════════════════════════════════════
-- Items are immutable tables; an update replaces the table, so React can
-- compare by reference. Every mutation ends in emit().

local toasts       = {}   -- visible, oldest first
local pendingToast = {}   -- FIFO
local banner       = nil  -- current banner item
local bannerQueue  = {}
local feedLines    = {}   -- oldest first

local nextId    = 0
local listeners = {}
local listenerSeq = 0
local inlineListeners = {}

local function newId()
	nextId += 1
	return nextId
end

local function snapshot()
	return {
		toasts  = table.clone(toasts),
		pending = #pendingToast,
		banner  = banner,
		feed    = table.clone(feedLines),
	}
end

local function emit()
	local snap = snapshot()
	for _, cb in pairs(listeners) do
		task.spawn(cb, snap)
	end
end

local function toText(v)
	if v == nil then return "" end
	return tostring(v)
end

-- ── Toasts ────────────────────────────────────────────────
local removeToast   -- forward decl (scheduleToast ↔ removeToast)

local function scheduleToast(item)
	task.delay(item.duration, function()
		removeToast(item.id, item.token)
	end)
end

local function promoteToasts()
	while #toasts < GEOMETRY.toast.maxVisible and #pendingToast > 0 do
		local item = table.remove(pendingToast, 1)
		table.insert(toasts, item)
		scheduleToast(item)
	end
end

removeToast = function(id, token)
	for i, item in ipairs(toasts) do
		if item.id == id and (token == nil or item.token == token) then
			table.remove(toasts, i)
			promoteToasts()
			emit()
			return
		end
	end
end

function Notify.toast(kind, text, opts)
	if text == nil then
		-- Notify.toast("message") shorthand
		text, kind = kind, "info"
	end
	if not TOAST_KINDS[kind] then kind = "info" end
	opts = opts or {}
	text = toText(text)
	local key = opts.key or (kind .. "|" .. text)
	local duration = tonumber(opts.duration) or GEOMETRY.toast.duration

	-- Same key visible: update in place, bump the count, restart its timer.
	for i, item in ipairs(toasts) do
		if item.key == key then
			local updated = table.clone(item)
			updated.kind, updated.text = kind, text
			updated.count    = item.count + 1
			updated.token    = item.token + 1
			updated.duration = duration
			toasts[i] = updated
			scheduleToast(updated)
			emit()
			return updated.id
		end
	end
	for i, item in ipairs(pendingToast) do
		if item.key == key then
			local updated = table.clone(item)
			updated.kind, updated.text = kind, text
			updated.count = item.count + 1
			pendingToast[i] = updated
			emit()
			return updated.id
		end
	end

	local item = {
		id = newId(), key = key, kind = kind, text = text,
		count = 1, token = 1, duration = duration,
	}
	if #toasts < GEOMETRY.toast.maxVisible then
		table.insert(toasts, item)
		scheduleToast(item)
	else
		table.insert(pendingToast, item)
		while #pendingToast > GEOMETRY.toast.maxPending do
			table.remove(pendingToast, 1)
		end
	end
	emit()
	return item.id
end

function Notify.dismiss(id)
	removeToast(id, nil)
end

-- ── Banner ────────────────────────────────────────────────
local showBanner  -- forward decl

local function nextBanner()
	local now = os.clock()
	table.sort(bannerQueue, function(a, b)
		if a.priority ~= b.priority then return a.priority > b.priority end
		return a.id < b.id
	end)
	while #bannerQueue > 0 do
		local item = table.remove(bannerQueue, 1)
		if now - item.queuedAt <= item.staleAfter then
			showBanner(item)
			return
		end
	end
	banner = nil
end

showBanner = function(item)
	banner = item
	if not item.sticky then
		task.delay(item.duration, function()
			if banner == item then
				nextBanner()
				emit()
			end
		end)
	end
end

local function resolvePriority(p)
	if type(p) == "number" then return p end
	if type(p) == "string" and Notify.Priority[p] then return Notify.Priority[p] end
	return Notify.Priority.info
end

function Notify.banner(text, opts)
	opts = opts or {}
	local item = {
		id         = newId(),
		key        = opts.key,
		text       = toText(text),
		subtitle   = opts.subtitle and toText(opts.subtitle) or nil,
		color      = typeof(opts.color) == "Color3" and opts.color or nil,
		priority   = resolvePriority(opts.priority),
		duration   = tonumber(opts.duration) or GEOMETRY.banner.duration,
		sticky     = opts.sticky == true,
		-- a sticky banner never goes stale while it waits behind a higher one
		staleAfter = tonumber(opts.staleAfter)
			or ((opts.sticky == true) and math.huge or GEOMETRY.banner.staleAfter),
		queuedAt   = os.clock(),
	}

	-- Same key: replace whatever is showing / queued under it.
	if item.key ~= nil then
		for i = #bannerQueue, 1, -1 do
			if bannerQueue[i].key == item.key then table.remove(bannerQueue, i) end
		end
		if banner and banner.key == item.key then
			showBanner(item)
			emit()
			return item.id
		end
	end

	if banner == nil then
		showBanner(item)
	elseif item.priority > banner.priority then
		-- Preempt. A transient banner is time-bound and is dropped; a
		-- sticky one (e.g. "ALL WAVES CLEARED") goes back in the queue.
		if banner.sticky then
			banner.queuedAt = os.clock()
			table.insert(bannerQueue, banner)
		end
		showBanner(item)
	else
		table.insert(bannerQueue, item)
	end
	emit()
	return item.id
end

function Notify.clearBanner(key)
	local changed = false
	for i = #bannerQueue, 1, -1 do
		if key == nil or bannerQueue[i].key == key then
			table.remove(bannerQueue, i)
			changed = true
		end
	end
	if banner and (key == nil or banner.key == key) then
		nextBanner()
		changed = true
	end
	if changed then emit() end
end

-- ── Feed ──────────────────────────────────────────────────
local function removeFeed(id, token)
	for i, line in ipairs(feedLines) do
		if line.id == id and line.token == token then
			table.remove(feedLines, i)
			emit()
			return
		end
	end
end

local function scheduleFeed(line)
	task.delay(line.duration, function()
		removeFeed(line.id, line.token)
	end)
end

function Notify.feed(text, opts)
	opts = opts or {}
	local duration = tonumber(opts.duration) or GEOMETRY.feed.duration
	local color = typeof(opts.color) == "Color3" and opts.color or nil

	if opts.key ~= nil then
		for i, line in ipairs(feedLines) do
			if line.key == opts.key then
				local updated = table.clone(line)
				updated.text     = toText(text)
				updated.color    = color or line.color
				updated.token    = line.token + 1
				updated.bump     = line.bump + 1
				updated.duration = duration
				feedLines[i] = updated
				scheduleFeed(updated)
				emit()
				return updated.id
			end
		end
	end

	local line = {
		id = newId(), key = opts.key, text = toText(text), color = color,
		token = 1, bump = 1, duration = duration,
	}
	table.insert(feedLines, line)
	while #feedLines > GEOMETRY.feed.maxBuffer do
		table.remove(feedLines, 1)
	end
	scheduleFeed(line)
	emit()
	return line.id
end

-- ── Subscriptions ─────────────────────────────────────────
function Notify.subscribe(cb)
	listenerSeq += 1
	local id = listenerSeq
	listeners[id] = cb
	return function() listeners[id] = nil end
end

function Notify.getState()
	return snapshot()
end

--- Server "inline" replies ({ request, ok, text }) for useRequest.
function Notify.onInline(cb)
	listenerSeq += 1
	local id = listenerSeq
	inlineListeners[id] = cb
	return function() inlineListeners[id] = nil end
end

-- ═══════════════════════════════════════════════════════════
-- SERVER PUSH ("Notify" RemoteEvent, NotifyService.lua)
-- ═══════════════════════════════════════════════════════════
-- Payload: { kind = "toast"|"banner"|"feed"|"inline", text, level?, key?,
--            subtitle?, priority?, duration?, sticky?, color?, request?, ok? }
local function onServerNotify(msg)
	if type(msg) ~= "table" then return end
	local kind = msg.kind
	if kind == "toast" then
		Notify.toast(msg.level or "info", msg.text, { key = msg.key, duration = msg.duration })
	elseif kind == "banner" then
		Notify.banner(msg.text, {
			subtitle = msg.subtitle, priority = msg.priority, key = msg.key,
			duration = msg.duration, sticky = msg.sticky, color = msg.color,
		})
	elseif kind == "feed" then
		Notify.feed(msg.text, { key = msg.key, color = msg.color, duration = msg.duration })
	elseif kind == "inline" then
		for _, cb in pairs(inlineListeners) do
			task.spawn(cb, msg)
		end
	end
end

-- Connected once, at first require (non-blocking: NetworkManager defers
-- the connection until the event exists).
NetworkManager.OnServerEvent("Notify", onServerNotify)

-- ═══════════════════════════════════════════════════════════
-- HOOKS
-- ═══════════════════════════════════════════════════════════

function Notify.useNotifyState()
	local state, setState = React.useState(snapshot)
	React.useEffect(function()
		setState(snapshot())  -- catch anything raised between render and effect
		return Notify.subscribe(setState)
	end, {})
	return state
end

local function useNumberAttribute(instance, name)
	local value, setValue = React.useState(function() return instance:GetAttribute(name) end)
	React.useEffect(function()
		setValue(instance:GetAttribute(name))
		local conn = instance:GetAttributeChangedSignal(name):Connect(function()
			setValue(instance:GetAttribute(name))
		end)
		return function() conn:Disconnect() end
	end, { instance, name })
	return (type(value) == "number") and value or nil
end

-- Resolved per-render layout (form factor + HUD-published regions).
local function useNotifyLayout()
	local ff = useFormFactor()
	local trBottom     = useNumberAttribute(ReplicatedStorage, GEOMETRY.attrTopRightBottom)
	local bossReserved = useNumberAttribute(ReplicatedStorage, GEOMETRY.attrTopCentre) or 0

	local t      = ff.tokens
	local vpW    = ff.viewport.X
	local safeTop = (ff.topbar or 0) + GEOMETRY.topGap

	local body  = math.max(GEOMETRY.minText, t.font.body)
	local small = math.max(GEOMETRY.minText, t.font.min)
	local dismiss = math.max(GEOMETRY.minDismiss, t.minTarget)

	return {
		kind        = ff.kind,
		body        = body,
		small       = small,
		title       = math.max(GEOMETRY.minText, t.font.title),
		dismiss     = dismiss,
		columnTop   = math.max(safeTop, trBottom or 0),
		toastW      = math.min(GEOMETRY.toast.width, math.floor(vpW * GEOMETRY.toast.maxWidthScale)),
		toastH      = math.max(GEOMETRY.toast.minHeight, dismiss),
		feedW       = math.min(GEOMETRY.feed.width, math.floor(vpW * GEOMETRY.feed.maxWidthScale)),
		feedH       = math.max(GEOMETRY.feed.lineHeight, small + 2 * GEOMETRY.gap),
		feedMax     = GEOMETRY.feed.maxLines[ff.kind] or 4,
		bannerY     = math.max(safeTop + GEOMETRY.banner.minTop, safeTop + bossReserved + GEOMETRY.gap),
		bannerW     = math.min(GEOMETRY.banner.width, math.floor(vpW * GEOMETRY.banner.maxWidthScale)),
	}
end

-- ═══════════════════════════════════════════════════════════
-- COMPONENTS
-- ═══════════════════════════════════════════════════════════

-- ── Toast ─────────────────────────────────────────────────
local function Toast(props)
	local item, L = props.item, props.layout
	local spec = TOAST_KINDS[item.kind] or TOAST_KINDS.info
	local G = GEOMETRY.toast
	local textLeft = G.accentBar + G.glyphW + G.pad
	local text = item.text
	if item.count > 1 then text = text .. "  ×" .. tostring(item.count) end

	return e("Frame", {
		Size             = UDim2.new(1, 0, 0, L.toastH),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = G.bgTransparency,
		BorderSizePixel  = 0,
		LayoutOrder      = item.id,
	}, {
		corner = e("UICorner", { CornerRadius = UDim.new(0, GEOMETRY.radius) }),
		stroke = e("UIStroke", {
			Color        = spec.color,
			Thickness    = GEOMETRY.stroke,
			Transparency = G.strokeTransparency,
		}),
		bar = e("Frame", {
			Size             = UDim2.new(0, G.accentBar, 1, 0),
			BackgroundColor3 = spec.color,
			BorderSizePixel  = 0,
		}),
		glyph = e("TextLabel", {
			Position               = UDim2.fromOffset(G.accentBar + 2, 0),
			Size                   = UDim2.new(0, G.glyphW, 1, 0),
			BackgroundTransparency = 1,
			Text                   = spec.glyph,
			TextColor3             = spec.color,
			Font                   = F.title,
			TextSize               = L.body,
		}),
		text = e("TextLabel", {
			Position               = UDim2.fromOffset(textLeft, G.pad / 2),
			Size                   = UDim2.new(1, -(textLeft + L.dismiss), 1, -G.pad),
			BackgroundTransparency = 1,
			Text                   = text,
			TextColor3             = C.text,
			Font                   = F.bold,
			TextSize               = L.body,
			TextWrapped            = true,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			TextXAlignment         = Enum.TextXAlignment.Left,
			TextYAlignment         = Enum.TextYAlignment.Center,
			RichText               = false,
		}),
		-- ✕ target: >= 44 px square (GEOMETRY.minDismiss / tokens.minTarget)
		dismiss = e("TextButton", {
			AnchorPoint            = Vector2.new(1, 0.5),
			Position               = UDim2.fromScale(1, 0.5),
			Size                   = UDim2.fromOffset(L.dismiss, L.dismiss),
			BackgroundTransparency = 1,
			Text                   = "✕",
			TextColor3             = C.textDim,
			Font                   = F.bold,
			TextSize               = L.body,
			[React.Event.Activated] = function() Notify.dismiss(item.id) end,
		}),
	})
end

local function ToastHost(props)
	local state, L = props.state, props.layout
	local children = {
		layout = e("UIListLayout", {
			FillDirection       = Enum.FillDirection.Vertical,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding             = UDim.new(0, GEOMETRY.gap),
		}),
	}
	for _, item in ipairs(state.toasts) do
		children["t" .. item.id] = e(Toast, { item = item, layout = L })
	end
	return e("Frame", {
		Name                   = "Toasts",
		Size                   = UDim2.new(0, L.toastW, 0, 0),
		AutomaticSize          = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder            = 1,
	}, children)
end

-- ── Feed ──────────────────────────────────────────────────
local function FeedLine(props)
	local line, L = props.line, props.layout
	local G = GEOMETRY.feed
	local groupRef = React.useRef(nil)
	local scaleRef = React.useRef(nil)

	-- Pulse on update (loot counter), then fade over the last G.fade s.
	React.useEffect(function()
		local group = groupRef.current
		if not group then return end
		group.GroupTransparency = 0
		local scale = scaleRef.current
		if scale and line.bump > 1 then
			scale.Scale = 1
			TweenService:Create(scale,
				TweenInfo.new(G.pulseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
				{ Scale = G.pulseScale }):Play()
		end
		local done = false
		local fadeThread = task.delay(math.max(0, line.duration - G.fade), function()
			done = true
			if group.Parent then
				TweenService:Create(group, TweenInfo.new(G.fade, Enum.EasingStyle.Linear),
					{ GroupTransparency = 1 }):Play()
			end
		end)
		return function()
			if not done then task.cancel(fadeThread) end
		end
	end, { line.bump, line.token })

	return e("CanvasGroup", {
		ref                    = groupRef,
		Size                   = UDim2.new(1, 0, 0, L.feedH),
		BackgroundColor3       = C.panel,
		BackgroundTransparency = G.bgTransparency,
		BorderSizePixel        = 0,
		LayoutOrder            = line.id,
	}, {
		corner = e("UICorner", { CornerRadius = UDim.new(0, GEOMETRY.radius) }),
		scale  = e("UIScale", { ref = scaleRef, Scale = 1 }),
		text = e("TextLabel", {
			Position               = UDim2.fromOffset(G.pad, 0),
			Size                   = UDim2.new(1, -2 * G.pad, 1, 0),
			BackgroundTransparency = 1,
			Text                   = line.text,
			TextColor3             = line.color or C.text,
			Font                   = F.bold,
			TextSize               = L.small,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			TextXAlignment         = Enum.TextXAlignment.Right,
			RichText               = false,
		}),
	})
end

local function FeedHost(props)
	local state, L = props.state, props.layout
	local children = {
		layout = e("UIListLayout", {
			FillDirection       = Enum.FillDirection.Vertical,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding             = UDim.new(0, math.floor(GEOMETRY.gap / 2)),
		}),
	}
	local lines = state.feed
	local first = math.max(1, #lines - L.feedMax + 1)  -- newest N, newest at the bottom
	for i = first, #lines do
		local line = lines[i]
		children["f" .. line.id] = e(FeedLine, { line = line, layout = L })
	end
	return e("Frame", {
		Name                   = "Feed",
		Size                   = UDim2.new(0, L.feedW, 0, 0),
		AutomaticSize          = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder            = 2,
	}, children)
end

-- ── Banner ────────────────────────────────────────────────
local function BannerHost(props)
	local state, L = props.state, props.layout
	local item = state.banner
	if item == nil then return nil end
	local G = GEOMETRY.banner
	local color = item.color or C.accent
	local hasSub = item.subtitle ~= nil and item.subtitle ~= ""
	local titleH = L.title + G.pad
	local subH   = hasSub and (L.small + G.pad) or 0
	local height = titleH + subH + G.pad

	return e("Frame", {
		Name             = "Banner",
		AnchorPoint      = Vector2.new(0.5, 0),
		Position         = UDim2.new(0.5, 0, 0, L.bannerY),
		Size             = UDim2.fromOffset(L.bannerW, height),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = G.bgTransparency,
		BorderSizePixel  = 0,
	}, {
		corner = e("UICorner", { CornerRadius = UDim.new(0, GEOMETRY.radius) }),
		stroke = e("UIStroke", { Color = color, Thickness = G.stroke, Transparency = 0.2 }),
		title = e("TextLabel", {
			Position               = UDim2.fromOffset(G.pad, G.pad / 2),
			Size                   = UDim2.new(1, -2 * G.pad, 0, titleH),
			BackgroundTransparency = 1,
			Text                   = item.text,
			TextColor3             = color,
			Font                   = F.title,
			TextSize               = L.title,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			RichText               = false,
		}),
		subtitle = hasSub and e("TextLabel", {
			Position               = UDim2.fromOffset(G.pad, G.pad / 2 + titleH),
			Size                   = UDim2.new(1, -2 * G.pad, 0, subH),
			BackgroundTransparency = 1,
			Text                   = item.subtitle,
			TextColor3             = C.text,
			Font                   = F.body,
			TextSize               = L.small,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			RichText               = false,
		}) or nil,
	})
end

-- ── Host ──────────────────────────────────────────────────
-- Own ScreenGui (portal into PlayerGui): DeviceSafeInsets, above AppGui,
-- below the modal band. Mount exactly once per place.
local function NotifyHost()
	local state  = Notify.useNotifyState()
	local layout = useNotifyLayout()

	return ReactRoblox.createPortal(e("ScreenGui", {
		Name           = "NotifyGui",
		ResetOnSpawn   = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder   = GEOMETRY.displayOrder,
		-- Not IgnoreGuiInset: that legacy flag rewrites ScreenInsets.
		-- DeviceSafeInsets does NOT clear the Roblox topbar, hence
		-- layout.* adds FormFactor.Get().topbar explicitly.
		ScreenInsets   = Enum.ScreenInsets.DeviceSafeInsets,
	}, {
		-- Right column: toasts, then feed lines directly under them.
		column = e("Frame", {
			Name                   = "RightColumn",
			AnchorPoint            = Vector2.new(1, 0),
			Position               = UDim2.new(1, -GEOMETRY.rightEdge, 0, layout.columnTop),
			Size                   = UDim2.fromOffset(math.max(layout.toastW, layout.feedW), 0),
			AutomaticSize          = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			layout = e("UIListLayout", {
				FillDirection       = Enum.FillDirection.Vertical,
				SortOrder           = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding             = UDim.new(0, GEOMETRY.gap),
			}),
			toasts = e(ToastHost, { state = state, layout = layout }),
			feed   = e(FeedHost,  { state = state, layout = layout }),
		}),
		banner = e(BannerHost, { state = state, layout = layout }),
	}), player:WaitForChild("PlayerGui"))
end

Notify.Host       = NotifyHost
Notify.ToastHost  = ToastHost
Notify.BannerHost = BannerHost
Notify.FeedHost   = FeedHost
Notify.useLayout  = useNotifyLayout

return Notify
