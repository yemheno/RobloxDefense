-- UI/Common/Notify.lua
--[[
    §AGX/UI-P4: Notify, the ONE player-feedback system (ARCHITECTURE.md#notify,
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
            opts.action    §AGX/UI-FREE: { label, onActivated } one button on
                           the banner's right (client-only; e.g. §NM-D6 Rejoin)
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

    STYLE: colours and fonts come only from Theme.Colors / Theme.Fonts
    (Theme v2 aliases), sizes from Theme.Layout[formFactor] (via
    useFormFactor), and every Notify-specific number lives in GEOMETRY
    below. Restyling = editing that one table.

    §AGX/UI-P5 (C4, shell-spec §4.2 / F2):
      SCALE  NotifyGui is its own UNSCALED ScreenGui, so every GEOMETRY length
             is a DESIGN px turned into screen px with FormFactor.px(n) in
             useNotifyLayout (and fonts / targets come from the pre-multiplied
             ff.tokens), so toasts scale with the device (D2).
      PLACE  Phone with a SkillPad (combat): toasts + feed live in the
             top-centre CORRIDOR under the banner slot (1 toast), capped
             above the Dash / combo (F2: a right column would sit on
             SkillPad's Skill 4 and its ✕ would take the ult's taps). Other
             form factors: right column, offset by the rail
             (UI_RightRailLeftPx), capped above SkillPad (UI_SkillPadTopPx).
      MODE   UI_HudMode (PanelStack): "none" hides the feed and pauses banners
             (they queue; staleAfter drops old ones). Toasts always show.
      Reads UI_TopRightBottomPx, UI_TopCentreReservedPx,
      UI_TopCentreButtonsBottomPx, UI_LeftColumnRightPx, UI_RightRailLeftPx,
      UI_SkillPadTopPx, UI_HudMode (all optional; nil = region absent).
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
-- §AGX/UI-P5: design px -> screen px for this unscaled ScreenGui.
local FormFactor     = require(Modules:WaitForChild("FormFactor"))

local C = Theme.Colors
local F = Theme.Fonts

-- ═══════════════════════════════════════════════════════════
-- GEOMETRY (§AGX/UI-P4: the one table to restyle)
-- ═══════════════════════════════════════════════════════════
-- DESIGN px unless noted (§AGX/UI-P5: useNotifyLayout multiplies every
-- length by the device uiScale via FormFactor.px; minText / minDismiss are
-- absolute floors). Form-factor sizes (edge, fonts, minTarget) come from
-- ff.tokens via useFormFactor(); these are Notify's own.
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
	-- ReplicatedStorage (HUD/Layout.lua ATTR), so Notify stays clear of them.
	attrTopRightBottom = "UI_TopRightBottomPx",
	attrTopCentre      = "UI_TopCentreReservedPx",
	-- §AGX/UI-P4: bottom of the HUD's visible Start / Next Wave / Return
	-- column (absolute px, like attrTopRightBottom; nil when none shows).
	attrTopCentreButtons = "UI_TopCentreButtonsBottomPx",
	-- §AGX/UI-P5 (shell-spec §4.3), all screen px from the safe-area origin:
	attrLeftColumnRight = "UI_LeftColumnRightPx",  -- right edge of the vitals/party column
	attrRightRailLeft   = "UI_RightRailLeftPx",    -- width taken by the rail / menu button (+edge)
	attrSkillPadTop     = "UI_SkillPadTopPx",      -- SkillPad footprint from the bottom (nil = hidden)
	attrHudMode         = "UI_HudMode",            -- "full" | "combatSide" | "none" (string)

	toast = {
		duration      = 3.5,
		maxVisible    = 3,      -- store cap; the layout lowers it (phone: 1)
		phoneVisible  = 1,
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
		-- px below safeTop: a floor that also clears the phone top-left
		-- vitals / top-right currency rows. §AGX/UI-P4: the banner also sits
		-- below the published Start / Next / Return column
		-- (attrTopCentreButtons): bannerY = max(safeTop + 88, columnBottom + gap).
		minTop        = 88,
		width         = 460,
		maxWidthScale = 0.56,
		minCorridor   = 240,    -- §AGX/UI-P5: narrowest banner / toast column
		actionW       = 110,    -- §AGX/UI-FREE: banner action button (design px)
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
-- sticky), VoteUI and achievements (4 s).
Notify.Priority = {
	connection  = 60,   -- §AGX/UI-FREE: §NM-D6 "Still connecting…" (Rejoin)
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

-- §AGX/UI-P5: live limits set by the Host from its layout.
local visibleCap   = GEOMETRY.toast.maxVisible  -- toasts shown at once
local bannerPaused = false                      -- UI_HudMode == "none"

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
	while #toasts < visibleCap and #pendingToast > 0 do
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
	if #toasts < visibleCap then
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

--- §AGX/UI-P5: how many toasts may show at once (the Host sets it from its
--- layout: 1 in the phone corridor, fewer when the column is capped).
--- Extra visible toasts go back to the FRONT of the queue (their timers
--- are invalidated and restart when they show again).
function Notify.setVisibleCap(n)
	n = math.clamp(math.floor(tonumber(n) or GEOMETRY.toast.maxVisible), 1, GEOMETRY.toast.maxVisible)
	if n == visibleCap then return end
	visibleCap = n
	local changed = false
	while #toasts > visibleCap do
		local item = table.remove(toasts)          -- newest first
		local demoted = table.clone(item)
		demoted.token = item.token + 1             -- its pending removeToast no longer matches
		table.insert(pendingToast, 1, demoted)
		changed = true
	end
	if #toasts < visibleCap and #pendingToast > 0 then
		promoteToasts()
		changed = true
	end
	if changed then emit() end
end

-- ── Banner ────────────────────────────────────────────────
local showBanner  -- forward decl

local function nextBanner()
	if bannerPaused then
		banner = nil
		return
	end
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
		-- §AGX/UI-FREE: optional single action button (functions never come
		-- from the server push, so only client callers can set one).
		action     = (type(opts.action) == "table" and type(opts.action.onActivated) == "function")
			and { label = toText(opts.action.label or "OK"), onActivated = opts.action.onActivated }
			or nil,
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

	if bannerPaused then
		table.insert(bannerQueue, item)   -- §AGX/UI-P5: shown when the HUD is back
	elseif banner == nil then
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

--- §AGX/UI-P5: pause banners while UI_HudMode is "none" (a panel covers
--- the HUD). The current banner goes back in the queue; on resume the
--- queue plays in priority order and stale entries are dropped.
function Notify.setBannerPaused(paused)
	paused = paused == true
	if paused == bannerPaused then return end
	bannerPaused = paused
	if paused then
		if banner then
			local item = table.clone(banner)
			if not item.sticky then item.queuedAt = os.clock() end
			table.insert(bannerQueue, item)
			banner = nil
		end
	else
		nextBanner()
	end
	emit()
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

local function useAttribute(instance, name, kind)
	local value, setValue = React.useState(function() return instance:GetAttribute(name) end)
	React.useEffect(function()
		setValue(instance:GetAttribute(name))
		local conn = instance:GetAttributeChangedSignal(name):Connect(function()
			setValue(instance:GetAttribute(name))
		end)
		return function() conn:Disconnect() end
	end, { instance, name })
	return (type(value) == kind) and value or nil
end

local function useNumberAttribute(instance, name)
	return useAttribute(instance, name, "number")
end

-- §AGX/UI-P5: the Host's measured ScreenGui size (DeviceSafeInsets makes it
-- smaller than the viewport on notched phones, and the attributes are
-- relative to the safe-area origin). Shared so Notify.useLayout callers
-- (MatchmakingUI) see the same numbers as the Host.
local hostSize = nil
local hostSizeListeners = {}
local function setHostSize(v)
	if hostSize == v then return end
	hostSize = v
	for _, cb in pairs(hostSizeListeners) do task.spawn(cb, v) end
end
local function useHostSize()
	local value, setValue = React.useState(hostSize)
	React.useEffect(function()
		setValue(hostSize)
		listenerSeq += 1
		local id = listenerSeq
		hostSizeListeners[id] = setValue
		return function() hostSizeListeners[id] = nil end
	end, {})
	return value
end

-- §AGX/UI-P5: Dash top (from the safe bottom) for the phone corridor cap.
-- HUD/Layout is a pure module (React + Theme), safe to require from here.
local hudLayoutModule = nil
local function dashTopPx(tokens)
	if hudLayoutModule == nil then
		local ui = PlayerScripts:FindFirstChild("UI")
		local hud = ui and ui:FindFirstChild("HUD")
		local mod = hud and hud:FindFirstChild("Layout")
		hudLayoutModule = mod and require(mod) or false
	end
	if not hudLayoutModule then return nil end
	local fp = hudLayoutModule.padFootprint(tokens.skillPad, tokens.attack, tokens.skill, tokens.dash)
	return fp and fp.dashTop or nil
end

-- The corridor exists for SkillPad (F2). A place that ever published the
-- SkillPad footprint is a touch-combat place for the rest of the session
-- (a teleport is a new client), so the column doesn't jump back to the
-- right while a menu hides the pad. The Lobby keeps the right column
-- (MatchmakingUI's controls sit under the banner there).
local sawSkillPad = false

-- Resolved per-render layout (form factor + HUD-published regions), in
-- SCREEN px for NotifyGui.
local function useNotifyLayout()
	local ff = useFormFactor()
	local measured     = useHostSize()
	local trBottom     = useNumberAttribute(ReplicatedStorage, GEOMETRY.attrTopRightBottom)
	local bossReserved = useNumberAttribute(ReplicatedStorage, GEOMETRY.attrTopCentre) or 0
	local tcButtons    = useNumberAttribute(ReplicatedStorage, GEOMETRY.attrTopCentreButtons)  -- §AGX/UI-P4
	-- §AGX/UI-P5 (C4)
	local leftColRight = useNumberAttribute(ReplicatedStorage, GEOMETRY.attrLeftColumnRight)
	local railLeft     = useNumberAttribute(ReplicatedStorage, GEOMETRY.attrRightRailLeft)
	local padTop       = useNumberAttribute(ReplicatedStorage, GEOMETRY.attrSkillPadTop)
	local hudMode      = useAttribute(ReplicatedStorage, GEOMETRY.attrHudMode, "string") or "full"

	local t    = ff.tokens
	local px   = FormFactor.px   -- design -> screen px (uiScale, same rounding as ff.tokens)
	local size = measured or ff.viewport
	local vpW, vpH = size.X, size.Y
	local gap  = px(GEOMETRY.gap)
	local safeTop = (ff.topbar or 0) + px(GEOMETRY.topGap)
	local TG, BG, FG = GEOMETRY.toast, GEOMETRY.banner, GEOMETRY.feed

	local body    = math.max(GEOMETRY.minText, t.font.body)
	local small   = math.max(GEOMETRY.minText, t.font.min)
	local dismiss = math.max(GEOMETRY.minDismiss, t.minTarget)
	local title   = math.max(GEOMETRY.minText, t.font.title)
	local bannerPad = px(BG.pad)

	local L = {
		kind      = ff.kind,
		hudMode   = hudMode,
		body      = body,
		small     = small,
		title     = title,
		dismiss   = dismiss,
		gap       = gap,
		radius    = px(GEOMETRY.radius),
		stroke    = px(GEOMETRY.stroke),
		toastPad  = px(TG.pad),
		accentBar = px(TG.accentBar),
		glyphW    = px(TG.glyphW),
		feedPad   = px(FG.pad),
		bannerPad = bannerPad,
		bannerStroke = px(BG.stroke),
		toastW    = math.min(px(TG.width), math.floor(vpW * TG.maxWidthScale)),
		toastH    = math.max(px(TG.minHeight), dismiss),
		feedW     = math.min(px(FG.width), math.floor(vpW * FG.maxWidthScale)),
		feedH     = math.max(px(FG.lineHeight), small + 2 * gap),
		feedMax   = FG.maxLines[ff.kind] or 4,
		-- §AGX/UI-P4: below BossHud's reserved slot AND the HUD button column.
		bannerY   = math.max(safeTop + px(BG.minTop),
			math.max(safeTop + bossReserved, tcButtons or 0) + gap),
		-- Height of a banner without subtitle (BannerHost's maths), so a
		-- caller can place its own controls under the banner slot
		-- (MatchmakingUI's Cancel / Retry / Close).
		bannerH   = (title + bannerPad) + bannerPad,
		bannerW   = math.min(px(BG.width), math.floor(vpW * BG.maxWidthScale)),
	}
	-- Extra height of a banner WITH a subtitle (the Host adds it while one shows).
	L.bannerSubExtra = small + bannerPad
	if padTop then sawSkillPad = true end

	-- Phone / tablet: the top-centre stack stays inside the corridor right
	-- of the vitals / party column (never narrower than minCorridor).
	local corridor = nil
	if (ff.kind == "Phone" or ff.kind == "Tablet") and leftColRight then
		corridor = math.max(px(BG.minCorridor), math.floor(2 * (vpW / 2 - (leftColRight + gap))))
		L.bannerW = math.min(L.bannerW, corridor)
	end

	if ff.kind == "Phone" and sawSkillPad then
		-- F2: the right column sat on Skill 4 (and its ✕ took the ult's
		-- taps). Toasts + feed go to the corridor under the banner slot,
		-- one toast, feed capped above the Dash button and the combo.
		local dashTop = padTop and dashTopPx(t) or nil
		local bottomReserve = math.max((t.edge or 16) + 44 + gap, dashTop or 0)
		L.placement   = "corridor"
		L.columnAnchor = Vector2.new(0.5, 0)
		L.columnTop   = L.bannerY + L.bannerH + gap
		L.columnPos   = UDim2.new(0.5, 0, 0, L.columnTop)
		L.columnW     = math.min(L.toastW, corridor or L.toastW)
		L.toastW      = L.columnW
		L.feedW       = L.columnW
		L.columnBottom = vpH - bottomReserve - gap
		L.toastMax    = TG.phoneVisible
	else
		local right = railLeft and (railLeft + gap) or px(GEOMETRY.rightEdge)
		local top = math.max(safeTop, trBottom or 0)
		L.placement   = "right"
		L.columnAnchor = Vector2.new(1, 0)
		L.columnPos   = UDim2.new(1, -right, 0, top)
		L.columnTop   = top
		L.columnW     = math.max(L.toastW, L.feedW)
		-- Cap above SkillPad (tablet); else the safe bottom edge.
		L.columnBottom = vpH - (padTop and (padTop + gap) or px(GEOMETRY.rightEdge))
		local fit = math.floor((L.columnBottom - top + gap) / (L.toastH + gap))
		L.toastMax = math.clamp(fit, 1, TG.maxVisible)
	end
	-- Legacy field (right column top).
	L.columnTopPx = L.columnTop
	return L
end

-- ═══════════════════════════════════════════════════════════
-- COMPONENTS
-- ═══════════════════════════════════════════════════════════

-- ── Toast ─────────────────────────────────────────────────
local function Toast(props)
	local item, L = props.item, props.layout
	local spec = TOAST_KINDS[item.kind] or TOAST_KINDS.info
	local G = GEOMETRY.toast
	local textLeft = L.accentBar + L.glyphW + L.toastPad
	local text = item.text
	if item.count > 1 then text = text .. "  ×" .. tostring(item.count) end

	return e("Frame", {
		Size             = UDim2.new(1, 0, 0, L.toastH),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = G.bgTransparency,
		BorderSizePixel  = 0,
		LayoutOrder      = item.id,
	}, {
		corner = e("UICorner", { CornerRadius = UDim.new(0, L.radius) }),
		stroke = e("UIStroke", {
			Color        = spec.color,
			Thickness    = L.stroke,
			Transparency = G.strokeTransparency,
		}),
		bar = e("Frame", {
			Size             = UDim2.new(0, L.accentBar, 1, 0),
			BackgroundColor3 = spec.color,
			BorderSizePixel  = 0,
		}),
		glyph = e("TextLabel", {
			Position               = UDim2.fromOffset(L.accentBar + 2, 0),
			Size                   = UDim2.new(0, L.glyphW, 1, 0),
			BackgroundTransparency = 1,
			Text                   = spec.glyph,
			TextColor3             = spec.color,
			Font                   = F.title,
			TextSize               = L.body,
		}),
		text = e("TextLabel", {
			Position               = UDim2.fromOffset(textLeft, L.toastPad / 2),
			Size                   = UDim2.new(1, -(textLeft + L.dismiss), 1, -L.toastPad),
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
			Padding             = UDim.new(0, L.gap or GEOMETRY.gap),
		}),
	}
	-- §AGX/UI-P5: never more than the layout's cap (the store follows it
	-- via Notify.setVisibleCap; this guards the frame before that lands).
	local cap = L.toastMax or GEOMETRY.toast.maxVisible
	for i, item in ipairs(state.toasts) do
		if i > cap then break end
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
		corner = e("UICorner", { CornerRadius = UDim.new(0, L.radius) }),
		scale  = e("UIScale", { ref = scaleRef, Scale = 1 }),
		text = e("TextLabel", {
			Position               = UDim2.fromOffset(L.feedPad, 0),
			Size                   = UDim2.new(1, -2 * L.feedPad, 1, 0),
			BackgroundTransparency = 1,
			Text                   = line.text,
			TextColor3             = line.color or C.text,
			Font                   = F.bold,
			TextSize               = L.small,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			-- §AGX/UI-P5: centred in the phone corridor, right-aligned in the column
			TextXAlignment         = (L.placement == "corridor") and Enum.TextXAlignment.Center
				or Enum.TextXAlignment.Right,
			RichText               = false,
		}),
	})
end

local function FeedHost(props)
	local state, L = props.state, props.layout
	local lineGap = math.floor((L.gap or GEOMETRY.gap) / 2)
	local children = {
		layout = e("UIListLayout", {
			FillDirection       = Enum.FillDirection.Vertical,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding             = UDim.new(0, lineGap),
		}),
	}
	local lines = state.feed
	local maxLines = props.maxLines or L.feedMax
	local first = math.max(1, #lines - maxLines + 1)  -- newest N, newest at the bottom
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
	local pad = L.bannerPad or G.pad
	local color = item.color or C.accent
	local hasSub = item.subtitle ~= nil and item.subtitle ~= ""
	local titleH = L.title + pad
	local subH   = hasSub and (L.small + pad) or 0
	local height = titleH + subH + pad
	-- §AGX/UI-FREE: action button on the right, a >= 44 px target
	-- (L.dismiss); the text column gives up its width.
	local action = item.action
	local actionW = action and math.max(2 * L.dismiss, FormFactor.px(GEOMETRY.banner.actionW)) or 0
	local textInset = action and (actionW + pad) or 0
	if action then height = math.max(height, L.dismiss + 2 * pad) end

	return e("Frame", {
		Name             = "Banner",
		AnchorPoint      = Vector2.new(0.5, 0),
		Position         = UDim2.new(0.5, 0, 0, L.bannerY),
		Size             = UDim2.fromOffset(L.bannerW, height),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = G.bgTransparency,
		BorderSizePixel  = 0,
	}, {
		corner = e("UICorner", { CornerRadius = UDim.new(0, L.radius or GEOMETRY.radius) }),
		stroke = e("UIStroke", { Color = color, Thickness = L.bannerStroke or G.stroke, Transparency = 0.2 }),
		title = e("TextLabel", {
			Position               = UDim2.fromOffset(pad, pad / 2),
			Size                   = UDim2.new(1, -2 * pad - textInset, 0, titleH),  -- §AGX/UI-FREE
			BackgroundTransparency = 1,
			Text                   = item.text,
			TextColor3             = color,
			Font                   = F.title,
			TextSize               = L.title,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			RichText               = false,
		}),
		subtitle = hasSub and e("TextLabel", {
			Position               = UDim2.fromOffset(pad, pad / 2 + titleH),
			Size                   = UDim2.new(1, -2 * pad - textInset, 0, subH),  -- §AGX/UI-FREE
			BackgroundTransparency = 1,
			Text                   = item.subtitle,
			TextColor3             = C.text,
			Font                   = F.body,
			TextSize               = L.small,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			RichText               = false,
		}) or nil,
		-- §AGX/UI-FREE: the banner's one action (primary CTA: orange + ink).
		action = action and e("TextButton", {
			Name                   = "Action",
			AnchorPoint            = Vector2.new(1, 0.5),
			Position               = UDim2.new(1, -pad, 0.5, 0),
			Size                   = UDim2.fromOffset(actionW, L.dismiss),
			BackgroundColor3       = Theme.Roles.accent.primary,
			BorderSizePixel        = 0,
			AutoButtonColor        = true,
			Text                   = string.upper(action.label),
			TextColor3             = Theme.Roles.text.onAccent,
			Font                   = F.title,
			TextSize               = L.body,
			TextTruncate           = Enum.TextTruncate.AtEnd,
			[React.Event.Activated] = function()
				task.spawn(action.onActivated)
			end,
		}, {
			corner = e("UICorner", { CornerRadius = UDim.new(0, L.radius or GEOMETRY.radius) }),
		}) or nil,
	})
end

-- ── Host ──────────────────────────────────────────────────
-- Own ScreenGui (portal into PlayerGui): DeviceSafeInsets, above AppGui,
-- below the modal band. Mount exactly once per place.
local function NotifyHost()
	local state  = Notify.useNotifyState()
	local layout = useNotifyLayout()

	-- §AGX/UI-P5: store limits follow the layout / HUD mode.
	local toastMax = layout.toastMax
	React.useEffect(function()
		Notify.setVisibleCap(toastMax)
	end, { toastMax })
	local paused = layout.hudMode == "none"
	React.useEffect(function()
		Notify.setBannerPaused(paused)
	end, { paused })
	React.useEffect(function()
		return function()
			Notify.setVisibleCap(GEOMETRY.toast.maxVisible)
			Notify.setBannerPaused(false)
			setHostSize(nil)
		end
	end, {})

	local onRootSize = React.useCallback(function(rbx)
		local sz = rbx.AbsoluteSize
		if sz.X > 0 and sz.Y > 0 then setHostSize(sz) end
	end, {})

	-- Corridor: step below a banner that carries a subtitle (taller).
	local columnTop, columnPos = layout.columnTop, layout.columnPos
	local b = state.banner
	if layout.placement == "corridor" and b and b.subtitle and b.subtitle ~= "" and not paused then
		columnTop += layout.bannerSubExtra
		columnPos = UDim2.new(columnPos.X.Scale, columnPos.X.Offset, 0, columnTop)
	end

	-- Feed lines that fit between the toasts and the column cap.
	local shownToasts = math.min(#state.toasts, layout.toastMax)
	local used = shownToasts * (layout.toastH + layout.gap)
	local lineGap = math.floor(layout.gap / 2)
	local room = layout.columnBottom - columnTop - used
	local feedLines = math.clamp(math.floor((room + lineGap) / (layout.feedH + lineGap)), 0, layout.feedMax)
	if paused then feedLines = 0 end   -- UI_HudMode "none": no feed over panels

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
		root = e("Frame", {
			Name                   = "Root",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			[React.Change.AbsoluteSize] = onRootSize,
		}, {
			-- Toasts, then feed lines directly under them: the right column,
			-- or the top-centre corridor on phones (§AGX/UI-P5).
			column = e("Frame", {
				Name                   = "Column",
				AnchorPoint            = layout.columnAnchor,
				Position               = columnPos,
				Size                   = UDim2.fromOffset(layout.columnW, 0),
				AutomaticSize          = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, {
				layout = e("UIListLayout", {
					FillDirection       = Enum.FillDirection.Vertical,
					SortOrder           = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = (layout.placement == "corridor") and Enum.HorizontalAlignment.Center
						or Enum.HorizontalAlignment.Right,
					Padding             = UDim.new(0, layout.gap),
				}),
				toasts = e(ToastHost, { state = state, layout = layout }),
				feed   = e(FeedHost,  { state = state, layout = layout, maxLines = feedLines }),
			}),
			banner = e(BannerHost, { state = state, layout = layout }),
		}),
	}), player:WaitForChild("PlayerGui"))
end

Notify.Host       = NotifyHost
Notify.ToastHost  = ToastHost
Notify.BannerHost = BannerHost
Notify.FeedHost   = FeedHost
Notify.useLayout  = useNotifyLayout

return Notify
