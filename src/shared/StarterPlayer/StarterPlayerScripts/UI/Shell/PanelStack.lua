-- UI/Shell/PanelStack.lua
--[[
    §AGX/UI-P3: PanelStack, the single owner of "what panel is open"
    (docs/ui_audit/shell-spec.md §3). A module-level store (like Notify,
    usable from non-React code) plus React hooks. Entries come from
    Shell/Registry.

    ── Store API ────────────────────────────────────────────────────────
    PanelStack.open(id, props?, reason?) -> ok
        REPLACE: runs the close handlers of every menu/panel entry top-down
        with "replace" (a veto aborts and returns false), then pushes id.
        A "modal" entry opens OVER the panels (they are suspended, not
        closed). kind="action" entries: closeAll("self") then entry.run.
    PanelStack.push(id, props?) -> ok     sub-panel; only if entry.subOf == top().id
    PanelStack.pop(reason?) -> ok         close the top entry
    PanelStack.replace(id, props?) -> ok  swap the top entry only (menu -> panel)
    PanelStack.close(id, reason?) -> ok   close id and everything above it
    PanelStack.closeAll(reason?) -> ok    "system" ignores vetoes
    PanelStack.forceRemove(key) -> ok     §AGX/UI-FIX: 6 — drop a record by key
                                          (ignores closable / vetoes; PanelHost
                                          uses it when a module fails to load)
    PanelStack.back(reason?) -> ok        pop(reason or "back"), debounced 0.15 s
    PanelStack.openWhenIdle(id, props?)   fires when the stack is empty and no
                                          modal/system presence exists (D14)
    PanelStack.setPresence(key, class, present)   class = "modal" | "system"
    PanelStack.isOpen(id?) / top() / depth() / getState() / subscribe(cb) -> unsub
    PanelStack.onOpen(cb) -> unsub        cb(id, entry) after every open/push/replace
    PanelStack.presentationFor(entry) -> "windowed"|"side"|"sheet"|"fullscreen"|"dialog"|...
    PanelStack.pushBackHandler(fn) -> release
        §AGX/UI-P3: the ONE back route for windows OUTSIDE the stack
        (AppWindow closeOnBack in a legacy tree). While any handler is held
        the "UI" context is held too, so Backspace / B reach UIBack; the
        newest handler wins when the stack itself is empty.

    ── React ────────────────────────────────────────────────────────────
    PanelStack.useState() -> { stack, top, blocked, suspended, hudMode, depth }
    PanelStack.useCloseHandler(fn)   inside a panel: fn(reason) -> false vetoes
                                     (ignored for "system" / "self" / "blocked")
    PanelStack.useExternal(id, isOpen, closeFn)   self-managed panels (NPC)
    PanelStack.useModalPresence(key, visible)     VoteUI
    PanelStack.useFirstFocus(ref)                 P7 hook (Gamepad only, §3.5)
    PanelStack.usePresentation() -> presentation | nil (nil = not in PanelHost)
    PanelStack.useEntry() -> { id, presentation, dismissable, onBackdrop, top } | nil
    PanelStack.EntryContext           provided by PanelHost around each entry

    ── Close reasons ────────────────────────────────────────────────────
    "x" "self" "back" "backdrop" "replace" "toggle" "distance" "blocked" "system"
      • "self": the component already cleaned up; its handlers are not run
        and an external's closeFn is not called again.
      • vetoes are honoured for "x" "back" "backdrop" "replace" "toggle".

    ── Attach gate ──────────────────────────────────────────────────────
    Side effects (the UI context token, the CAS B-sink, UI_HudMode, NPC
    self-registration through useExternal) only run while a PanelHost is
    mounted (PanelStack.attach). Without one, every hook in the panels is a
    no-op.
]]

local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local Players              = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local GuiService           = game:GetService("GuiService")
local RunService           = game:GetService("RunService")   -- §AGX/UI-FIX: 1

local React = require(ReplicatedStorage.Packages.React)

local PanelStack = {}

-- ═══════════════════════════════════════════════════════════
-- LAZY DEPENDENCIES (nil-safe: this module must load anywhere)
-- ═══════════════════════════════════════════════════════════

local function modulesFolder()
	local lp = Players.LocalPlayer
	local ps = lp and lp:FindFirstChild("PlayerScripts")
	return ps and ps:FindFirstChild("Modules")
end

local InputSystem = nil
local function getInputSystem()
	if InputSystem then return InputSystem end
	local m = modulesFolder()
	local mod = m and m:FindFirstChild("InputSystem")
	if mod then
		local ok, res = pcall(require, mod)
		if ok then InputSystem = res end
	end
	return InputSystem
end

local FormFactor = nil
local function getFormFactor()
	if FormFactor then return FormFactor end
	local m = modulesFolder()
	local mod = m and m:FindFirstChild("FormFactor")
	if mod then
		local ok, res = pcall(require, mod)
		if ok then FormFactor = res end
	end
	return FormFactor
end

local Registry = require(script.Parent:WaitForChild("Registry"))

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local CLASS_RANK = { menu = 1, panel = 2, modal = 3, system = 4 }
local VETO_REASONS = { x = true, back = true, backdrop = true, replace = true, toggle = true }
local BACK_DEBOUNCE = 0.15
local HUD_ATTR = "UI_HudMode"
local CAS_BACK = "RD_UIBack"

-- stack[i] = { id, entry, props, key }  (bottom = 1)
local stack = {}
local presences = {}          -- [key] = "modal" | "system"
local handlers = {}           -- [id] = { [n] = fn }  close handlers (newest = highest n)
local handlerSeq = 0
local externals = {}          -- [id] = { closeFn = fn }  registered useExternal
local pendingIdle = {}        -- { { id, props } }  openWhenIdle queue
local backHandlers = {}       -- [n] = fn  (pushBackHandler)
local backSeq = 0
local listeners = {}
local listenerSeq = 0
local openListeners = {}
local openSeq = 0
local keySeq = 0

local hosted = 0
local place = "Lobby"

local snapshot = nil          -- last published state table (by reference)
local lastBackAt = -math.huge
local uiRelease = nil         -- InputSystem.PushUIContext() release
local casBound = false
local uiBackBound = false
local flushScheduled = false
-- §AGX/UI-FIX: 1 — generation of the pending deferred UI-token release
-- (0 = none pending). Bumped to cancel.
local releaseGen = 0
local releaseSeq = 0

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

local function classOf(entry)
	return (entry and entry.class) or "panel"
end

local function presenceRank()
	local rank = 0
	for _, cls in pairs(presences) do
		rank = math.max(rank, CLASS_RANK[cls] or 0)
	end
	return rank
end

local function topIndexOfClass(cls)
	for i = #stack, 1, -1 do
		if classOf(stack[i].entry) == cls then return i end
	end
	return nil
end

local function indexOf(id)
	for i = #stack, 1, -1 do
		if stack[i].id == id then return i end
	end
	return nil
end

-- Which stack indices are suspended (hidden, still mounted).
local function computeSuspended()
	local suspended = {}
	local systemPresent = false
	for _, cls in pairs(presences) do
		if cls == "system" then systemPresent = true end
	end
	local modalPresence = false
	for _, cls in pairs(presences) do
		if cls == "modal" then modalPresence = true end
	end
	local topModal = topIndexOfClass("modal")
	for i, rec in ipairs(stack) do
		local cls = classOf(rec.entry)
		if systemPresent and cls ~= "system" then
			suspended[rec.id] = true
		elseif (cls == "panel" or cls == "menu") then
			if modalPresence or (topModal and i < topModal) then
				suspended[rec.id] = true
			end
		end
	end
	return suspended
end

local function ffNow()
	local F = getFormFactor()
	return F and F.Get() or { kind = "Desktop", input = "KeyboardMouse" }
end

--- Presentation for an entry at the current place / form factor (§2.1).
function PanelStack.presentationFor(entry, ff)
	if not entry then return "windowed" end
	ff = ff or ffNow()
	if ff.kind == "Phone" then
		return entry.phone or "sheet"
	end
	if place == "Combat" and entry.combatSide
		and (ff.kind == "Tablet" or ff.kind == "Desktop") then
		return "side"
	end
	return entry.presentation or "windowed"
end

local function computeHudMode(suspended)
	local visible = {}
	for _, rec in ipairs(stack) do
		if not suspended[rec.id] then table.insert(visible, rec) end
	end
	if #visible == 0 then return "full" end
	local ff = ffNow()
	local top = visible[#visible]
	local onlyMenus = true
	for _, rec in ipairs(visible) do
		if classOf(rec.entry) ~= "menu" then onlyMenus = false end
	end
	local pres = PanelStack.presentationFor(top.entry, ff)
	if onlyMenus and (ff.kind == "Desktop" or ff.kind == "Console") and pres ~= "sheet" then
		return "full"
	end
	if place == "Combat" and pres == "side" then
		return "combatSide"
	end
	return "none"
end

local function buildSnapshot()
	local suspended = computeSuspended()
	local rank = presenceRank()
	local topRec = stack[#stack]
	local list = table.clone(stack)
	local blocked = rank >= CLASS_RANK.modal or topIndexOfClass("modal") ~= nil
	return {
		stack     = list,
		top       = topRec and topRec.id or nil,
		depth     = #stack,
		blocked   = blocked,
		suspended = suspended,
		presences = table.clone(presences),
		hudMode   = computeHudMode(suspended),
		place     = place,
	}
end

-- ── side effects (only while hosted) ─────────────────────

local function wantUIContext()
	if next(backHandlers) ~= nil then return true end
	return hosted > 0 and #stack > 0
end

local function onCasBack(_, state)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	PanelStack.back("back")
	return Enum.ContextActionResult.Sink
end

local function gamepadBackKeys()
	local IS = getInputSystem()
	local keys = IS and IS.GetBinding("UIBack", "Gamepad") or {}
	if #keys == 0 then keys = { Enum.KeyCode.ButtonB } end
	return keys
end

local function syncSideEffects(snap)
	-- 1. "UI" input context (D6). Presence entries never hold one.
	-- §AGX/UI-FIX: 1 — the token is released on the NEXT Heartbeat, not in
	-- this call stack: when B closes the last panel (CAS handler or UIBack),
	-- the rest of that same press (InputBegan's ButtonB -> Dash) still sees
	-- "UI" and is suppressed. Re-wanting before then cancels the release (no
	-- flicker); the deferred callback re-checks wantUIContext(), and every
	-- change to backHandlers / hosted / stack goes through publish(), so a
	-- token that is no longer wanted is always released within one frame.
	local IS = getInputSystem()
	if wantUIContext() then
		releaseGen = 0
		if not uiRelease and IS and IS.PushUIContext then
			uiRelease = IS.PushUIContext()
		end
	elseif uiRelease and releaseGen == 0 then
		releaseSeq += 1
		local gen = releaseSeq
		releaseGen = gen
		RunService.Heartbeat:Once(function()
			if releaseGen ~= gen then return end   -- cancelled / superseded
			releaseGen = 0
			if wantUIContext() then return end     -- wanted again: keep it
			local release = uiRelease
			uiRelease = nil
			if release then release() end
			-- The CAS B-sink follows the token (step 3).
			if casBound then
				casBound = false
				ContextActionService:UnbindAction(CAS_BACK)
			end
		end)
	end

	-- 2. UIBack action (Backspace + B through InputSystem, context "UI").
	if IS and not uiBackBound and (hosted > 0 or next(backHandlers) ~= nil) then
		uiBackBound = true
		IS.BindAction("UIBack", function(_, inputState)
			if inputState == "Began" then PanelStack.back("back") end
		end)
	end

	-- 3. CAS B-sink: gamepad selection may consume B before InputBegan
	--    (verify in Studio); the debounce in back() prevents a double pop.
	-- §AGX/UI-FIX: 1 — bound while the token is held (incl. its deferred
	-- release frame) so a B arriving in that frame is still sunk; the
	-- Heartbeat callback above unbinds it together with the token.
	local wantCas = wantUIContext() or uiRelease ~= nil
	if wantCas and not casBound then
		casBound = true
		local keys = gamepadBackKeys()
		ContextActionService:BindActionAtPriority(CAS_BACK, onCasBack, false,
			Enum.ContextActionPriority.High.Value + 1, table.unpack(keys))
	elseif not wantCas and casBound then
		casBound = false
		ContextActionService:UnbindAction(CAS_BACK)
	end

	-- 4. UI_HudMode (client-local ReplicatedStorage attribute).
	if hosted > 0 then
		if ReplicatedStorage:GetAttribute(HUD_ATTR) ~= snap.hudMode then
			ReplicatedStorage:SetAttribute(HUD_ATTR, snap.hudMode)
		end
	end
end

local flushIdle -- forward

local function publish()
	snapshot = buildSnapshot()
	syncSideEffects(snapshot)
	for _, cb in pairs(listeners) do
		task.spawn(cb, snapshot)
	end
	if #pendingIdle > 0 and not flushScheduled then
		flushScheduled = true
		task.defer(function()
			flushScheduled = false
			flushIdle()
		end)
	end
end

local function fireOpen(id, entry)
	for _, cb in pairs(openListeners) do
		task.spawn(cb, id, entry)
	end
end

-- Run the close handlers of one record. Returns false on a veto.
local function runHandlers(rec, reason)
	if reason == "self" then return true end
	local list = handlers[rec.id]
	if not list then return true end
	local ids = {}
	for n in pairs(list) do table.insert(ids, n) end
	table.sort(ids, function(a, b) return a > b end)   -- newest first
	local vetoable = VETO_REASONS[reason] == true
	for _, n in ipairs(ids) do
		local fn = list[n]
		if fn then
			local ok, result = pcall(fn, reason)
			if not ok then
				warn("[PanelStack] close handler error:", rec.id, result)
			elseif result == false and vetoable then
				return false
			end
		end
	end
	return true
end

local function canClose(rec, reason)
	if rec.entry and rec.entry.closable == false and reason ~= "self" then
		return false
	end
	return true
end

-- Remove records [fromIndex..#stack] top-down. All-or-nothing on vetoes.
local function closeFrom(fromIndex, reason, targetReason)
	-- 1. Check (and run) handlers top-down; abort on the first veto.
	for i = #stack, fromIndex, -1 do
		local rec = stack[i]
		local r = (i == fromIndex) and (targetReason or reason) or reason
		if not canClose(rec, r) then return false end
		if not runHandlers(rec, r) then return false end
	end
	-- 2. Remove, then notify externals (so their onClose -> close(id,"self")
	--    finds nothing and can't re-enter).
	local removed = {}
	for i = #stack, fromIndex, -1 do
		table.insert(removed, { rec = table.remove(stack, i), reason = (i == fromIndex) and (targetReason or reason) or reason })
	end
	for _, item in ipairs(removed) do
		local rec, r = item.rec, item.reason
		local ext = externals[rec.id]
		if ext and ext.closeFn and r ~= "self" then
			local ok, err = pcall(ext.closeFn, r)
			if not ok then warn("[PanelStack] external close error:", rec.id, err) end
		end
		if rec.restoreSelection ~= nil then
			pcall(function()
				if rec.restoreSelection and rec.restoreSelection.Parent then
					GuiService.SelectedObject = rec.restoreSelection
				end
			end)
		end
	end
	return true
end

local function makeRecord(id, entry, props)
	keySeq += 1
	local rec = { id = id, entry = entry, props = props, key = id .. "_" .. keySeq }
	local ff = ffNow()
	if ff.input == "Gamepad" then
		rec.restoreSelection = GuiService.SelectedObject or false
	end
	return rec
end

-- ═══════════════════════════════════════════════════════════
-- STORE API
-- ═══════════════════════════════════════════════════════════

function PanelStack.open(id, props, reason)
	local entry = Registry.get(id)
	if not entry then
		warn("[PanelStack] open: unknown id", id)
		return false
	end

	if entry.kind == "action" then
		if entry.run then
			if #stack > 0 and not PanelStack.closeAll("self") then return false end
			local ok, err = pcall(entry.run, { PanelStack = PanelStack, place = place })
			if not ok then warn("[PanelStack] action error:", id, err) end
		end
		return true
	end

	local cls = classOf(entry)
	local rank = presenceRank()

	-- System present: nothing new opens.
	if rank >= CLASS_RANK.system and cls ~= "system" then return false end

	if cls == "modal" or cls == "system" then
		if indexOf(id) then
			local rec = stack[indexOf(id)]
			rec.props = props or rec.props
			publish()
			return true
		end
		table.insert(stack, makeRecord(id, entry, props))
		publish()
		fireOpen(id, entry)
		return true
	end

	-- panel / menu: rejected while a modal (entry or presence) is up.
	if rank >= CLASS_RANK.modal or topIndexOfClass("modal") then return false end

	local top = stack[#stack]
	if top and top.id == id and #stack == 1 then
		if props then top.props = props; publish() end
		return true
	end

	-- REPLACE: close every menu/panel entry (top-down), vetoes abort.
	if #stack > 0 then
		if not closeFrom(1, reason or "replace") then
			publish()
			return false
		end
	end
	table.insert(stack, makeRecord(id, entry, props))
	publish()
	fireOpen(id, entry)
	return true
end

function PanelStack.push(id, props)
	local entry = Registry.get(id)
	local top = stack[#stack]
	if not entry or not top or entry.subOf ~= top.id then
		return false
	end
	if presenceRank() >= CLASS_RANK.modal then return false end
	table.insert(stack, makeRecord(id, entry, props))
	publish()
	fireOpen(id, entry)
	return true
end

function PanelStack.pop(reason)
	local n = #stack
	if n == 0 then return false end
	local ok = closeFrom(n, reason or "back")
	publish()
	return ok
end

function PanelStack.replace(id, props)
	local entry = Registry.get(id)
	if not entry then return false end
	if entry.kind == "action" then
		return PanelStack.open(id, props)
	end
	if #stack == 0 then
		return PanelStack.open(id, props)
	end
	local cls = classOf(entry)
	if (cls == "panel" or cls == "menu") and presenceRank() >= CLASS_RANK.modal then
		return false
	end
	if not closeFrom(#stack, "replace") then
		publish()
		return false
	end
	table.insert(stack, makeRecord(id, entry, props))
	publish()
	fireOpen(id, entry)
	return true
end

function PanelStack.close(id, reason)
	local i = indexOf(id)
	if not i then return false end
	reason = reason or "x"
	-- Entries ABOVE the target close with "replace" when the target closed
	-- itself (they did not); the target keeps `reason`.
	local above = (reason == "self") and "replace" or reason
	local ok = closeFrom(i, above, reason)
	publish()
	return ok
end

function PanelStack.closeAll(reason)
	reason = reason or "system"
	-- "self" (menu surfaces before an action, §4.5) means "the caller is
	-- cleaning up", not "every entry already did": entries still get their
	-- handlers and externals their closeFn, as for a replace.
	if reason == "self" then reason = "replace" end
	if #stack == 0 then return true end
	-- Non-closable entries (characterCreation) stay; close everything above.
	local from = 1
	for i = #stack, 1, -1 do
		if stack[i].entry and stack[i].entry.closable == false then
			from = i + 1
			break
		end
	end
	if from > #stack then return false end
	local r = reason
	if reason == "system" then
		-- vetoes ignored: handlers still run for cleanup
		r = "system"
	end
	local ok = closeFrom(from, r)
	publish()
	return ok
end

--- §AGX/UI-FIX: 6 — remove the record with this `key` (and everything above
--- it) unconditionally: closable = false and vetoes are ignored. For a
--- stacked entry whose module failed to load (PanelHost): it would otherwise
--- keep the "UI" context and hudMode "none" with no way out on touch.
--- Handlers of the records above still run (reason "system") for cleanup.
--- Returns true when something was removed.
function PanelStack.forceRemove(key)
	local idx = nil
	for i = #stack, 1, -1 do
		if stack[i].key == key then idx = i; break end
	end
	if not idx then return false end
	for i = #stack, idx, -1 do
		runHandlers(stack[i], "system")   -- result ignored: "system" can't veto
	end
	for i = #stack, idx, -1 do
		local rec = table.remove(stack, i)
		local ext = externals[rec.id]
		if ext and ext.closeFn then
			local ok, err = pcall(ext.closeFn, "system")
			if not ok then warn("[PanelStack] external close error:", rec.id, err) end
		end
		if rec.restoreSelection then
			pcall(function()
				if rec.restoreSelection.Parent then
					GuiService.SelectedObject = rec.restoreSelection
				end
			end)
		end
	end
	publish()
	return true
end

function PanelStack.back(reason)
	local now = os.clock()
	if now - lastBackAt < BACK_DEBOUNCE then return false end
	lastBackAt = now
	reason = reason or "back"

	if #stack > 0 then
		-- Hidden panels under a modal/system presence don't pop.
		if presenceRank() >= CLASS_RANK.modal then return false end
		local top = stack[#stack]
		if top.entry and top.entry.closable == false then return false end
		return PanelStack.pop(reason)
	end

	-- Legacy windows (AppWindow closeOnBack outside PanelHost): newest wins.
	local newest = nil
	for n in pairs(backHandlers) do
		if not newest or n > newest then newest = n end
	end
	if newest then
		local ok, err = pcall(backHandlers[newest], reason)
		if not ok then warn("[PanelStack] back handler error:", err) end
		return true
	end
	return false
end

flushIdle = function()
	if #pendingIdle == 0 then return end
	if #stack > 0 or next(presences) ~= nil then return end
	local item = table.remove(pendingIdle, 1)
	PanelStack.open(item.id, item.props, "idle")
end

function PanelStack.openWhenIdle(id, props)
	for _, item in ipairs(pendingIdle) do
		if item.id == id then return end
	end
	table.insert(pendingIdle, { id = id, props = props })
	if not flushScheduled then
		flushScheduled = true
		task.defer(function()
			flushScheduled = false
			flushIdle()
		end)
	end
end

function PanelStack.setPresence(key, class, present)
	local want = present and class or nil
	if presences[key] == want then return end
	presences[key] = want
	-- An external that is open under a new blocker is closed with "blocked"
	-- only when it tries to open; already-open entries are suspended.
	publish()
end

function PanelStack.isOpen(id)
	if id == nil then return #stack > 0 end
	return indexOf(id) ~= nil
end

function PanelStack.top()
	local rec = stack[#stack]
	return rec and rec.id or nil
end

function PanelStack.depth()
	return #stack
end

function PanelStack.getState()
	if not snapshot then snapshot = buildSnapshot() end
	return snapshot
end

function PanelStack.subscribe(cb)
	listenerSeq += 1
	local id = listenerSeq
	listeners[id] = cb
	return function() listeners[id] = nil end
end

function PanelStack.onOpen(cb)
	openSeq += 1
	local id = openSeq
	openListeners[id] = cb
	return function() openListeners[id] = nil end
end

function PanelStack.pushBackHandler(fn)
	backSeq += 1
	local id = backSeq
	backHandlers[id] = fn
	publish()
	local released = false
	return function()
		if released then return end
		released = true
		backHandlers[id] = nil
		publish()
	end
end

-- ── host attachment (PanelHost only) ─────────────────────

--- Called by PanelHost on mount. Returns detach().
function PanelStack.attach(opts)
	hosted += 1
	place = (opts and opts.place) or place
	publish()
	local detached = false
	return function()
		if detached then return end
		detached = true
		hosted = math.max(0, hosted - 1)
		if hosted == 0 then
			ReplicatedStorage:SetAttribute(HUD_ATTR, nil)
		end
		publish()
	end
end

function PanelStack.isHosted()
	return hosted > 0
end

function PanelStack.getPlace()
	return place
end

-- Recompute presentation / hudMode when the form factor changes.
task.defer(function()
	local F = getFormFactor()
	if F and F.Changed then
		F.Changed(function()
			if hosted > 0 then publish() end
		end)
	end
end)

-- ═══════════════════════════════════════════════════════════
-- REACT
-- ═══════════════════════════════════════════════════════════

PanelStack.EntryContext = React.createContext(nil)
-- true under a PanelHost (it provides this around everything it mounts).
PanelStack.HostContext  = React.createContext(false)

function PanelStack.useState()
	local state, setState = React.useState(PanelStack.getState())
	React.useEffect(function()
		setState(PanelStack.getState())
		return PanelStack.subscribe(setState)
	end, {})
	return state
end

function PanelStack.useEntry()
	return React.useContext(PanelStack.EntryContext)
end

function PanelStack.usePresentation()
	local ctx = React.useContext(PanelStack.EntryContext)
	return ctx and ctx.presentation or nil
end

--- Inside a panel mounted by PanelHost: fn(reason) -> false vetoes.
--- Outside PanelHost (legacy mounts) it does nothing.
function PanelStack.useCloseHandler(fn)
	local ctx = React.useContext(PanelStack.EntryContext)
	local fnRef = React.useRef(fn)
	fnRef.current = fn
	local id = ctx and ctx.id or nil
	React.useEffect(function()
		if not id then return nil end
		handlerSeq += 1
		local n = handlerSeq
		handlers[id] = handlers[id] or {}
		handlers[id][n] = function(reason)
			local f = fnRef.current
			if f then return f(reason) end
			return nil
		end
		return function()
			if handlers[id] then
				handlers[id][n] = nil
				if next(handlers[id]) == nil then handlers[id] = nil end
			end
		end
	end, { id })
end

--- Self-managed panels (NPC): when isOpen flips true the stack runs
--- open(id) (replacing whatever is open); stack-initiated closes call
--- closeFn(reason). No-op until a PanelHost is attached.
function PanelStack.useExternal(id, isOpen, closeFn)
	local closeRef = React.useRef(closeFn)
	closeRef.current = closeFn
	-- Hosted = mounted by PanelHost (context, true on the FIRST render, before
	-- PanelHost's own attach effect runs) or any host attached already.
	local inHost = React.useContext(PanelStack.HostContext) == true
	local hostedNow = inHost or PanelStack.isHosted()

	React.useEffect(function()
		if not hostedNow then return nil end
		externals[id] = {
			closeFn = function(reason)
				local f = closeRef.current
				if f then f(reason) end
			end,
		}
		return function()
			externals[id] = nil
		end
	end, { id, hostedNow } :: { any })

	React.useEffect(function()
		if not hostedNow then return end
		if isOpen then
			if not PanelStack.isOpen(id) then
				local ok = PanelStack.open(id, nil, "external")
				if not ok then
					-- Blocked (modal/system) or vetoed: close it so the server
					-- still receives NPCResponse Close.
					local f = closeRef.current
					if f then task.defer(f, "blocked") end
				end
			end
		elseif PanelStack.isOpen(id) then
			PanelStack.close(id, "self")
		end
	end, { id, isOpen, hostedNow } :: { any })
end

--- Self-managed modal overlays (VoteUI). Module-level, works anywhere.
function PanelStack.useModalPresence(key, visible)
	React.useEffect(function()
		PanelStack.setPresence(key, "modal", visible == true)
		return function()
			PanelStack.setPresence(key, "modal", false)
		end
	end, { key, visible == true } :: { any })
end

--- P7 hook: when this entry is (or becomes) top and the input is Gamepad,
--- select ref.current. The previous selection is restored on pop.
function PanelStack.useFirstFocus(ref)
	local ctx = React.useContext(PanelStack.EntryContext)
	local isTop = ctx ~= nil and ctx.top == true
	React.useEffect(function()
		if not isTop then return end
		local ff = ffNow()
		if ff.input ~= "Gamepad" then return end
		local target = ref and ref.current
		if target then
			pcall(function() GuiService.SelectedObject = target end)
		end
	end, { isTop })
end

return PanelStack
