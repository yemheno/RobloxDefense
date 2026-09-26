-- UI/Common/GamepadFocus.lua
--[[
    §AGX/UI-P7: gamepad focus primitives (docs/UI_REVAMP.md §5 P7,
    shell-spec §3.5, structure-and-flow UX-15). Everything here only changes
    behaviour while GuiService.SelectedObject is in use (gamepad selection),
    so mouse and touch never see it.

    ── Focus ring ─────────────────────────────────────────────────────────
    GamepadFocus.ring(radius?) -> Frame
        A shared, unparented Frame (UIStroke Theme border.focus, Stroke.focus
        + 0.5, UICorner Theme.Radius[radius]) for GuiObject.SelectionImageObject.
        The engine draws it only around the SELECTED object, so it is
        invisible to mouse / touch. Button / IconButton / Tabs / Card /
        CurrencyPill set it; installDefault() makes it the PlayerGui default
        so legacy raw TextButtons get the same ring.
    GamepadFocus.installDefault()   idempotent; PlayerGui.SelectionImageObject

    ── Queries ────────────────────────────────────────────────────────────
    GamepadFocus.isGamepad()                 FormFactor input == "Gamepad"
    GamepadFocus.canSelect(obj, root?)       Selectable + shown + non-zero size
    GamepadFocus.findFirst(root, prefer?)    prefer = { "Name", ... } first;
                                             else top-left, content before tabs
                                             before the close button
    GamepadFocus.isInside(obj, root)
    GamepadFocus.select(obj)                 pcall'd GuiService.SelectedObject

    ── Tabs registry (LB / RB) ────────────────────────────────────────────
    GamepadFocus.registerTabs({ getRoot, cycle(dir) -> newId? }) -> unregister
    GamepadFocus.tabsIn(root) -> handle?     a shown Tabs inside root
    GamepadFocus.onTabsChanged(cb) -> unsub

    ── Owned ContextActionService binds ──────────────────────────────────
    GamepadFocus.bindOwned(name, owner, fn, priority, ...keys)
    GamepadFocus.unbindOwned(name, owner)    only if `owner` still holds it,
                                             so an outgoing top can't unbind
                                             the incoming top's action

    ── Scrolling (right stick) ────────────────────────────────────────────
    GamepadFocus.scrollTarget(root?) -> ScrollingFrame?   nearest scrollable
                                             ancestor of the selection
    GamepadFocus.scrollBy(sf, stick, dt)     + reselect when the selection
                                             leaves the window

    ── React ──────────────────────────────────────────────────────────────
    GamepadFocus.useGamepad() -> boolean
    GamepadFocus.useAutoSelect(rootRef, key, { prefer?, steal? })
        While `key` is truthy AND the input is Gamepad: select the preferred
        (or first) selectable under rootRef. A new key re-selects. When key
        goes falsy / unmounts, clears the selection if it is still ours.
        steal = false (default) leaves an existing selection (an open panel)
        alone.
    GamepadFocus.useTabsIn(rootRef, enabled) -> boolean
]]

local Players              = game:GetService("Players")
local GuiService           = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local FormFactor    = require(
	Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules"):WaitForChild("FormFactor")
)

local GamepadFocus = {}

local SCROLL_SPEED = 1100     -- canvas px / s at full stick
local STICK_DEADZONE = 0.2
local AUTOSELECT_TRIES = 12   -- x 0.05 s: content that mounts a frame late

-- ═══════════════════════════════════════════════════════════
-- FOCUS RING
-- ═══════════════════════════════════════════════════════════

local rings = {}

function GamepadFocus.ring(radius)
	radius = radius or "md"
	local cached = rings[radius]
	if cached then return cached end
	local f = Instance.new("Frame")
	f.Name = "FocusRing_" .. tostring(radius)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Radius[radius] or Theme.Radius.md
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Roles.border.focus
	stroke.Thickness = Theme.Stroke.focus + 0.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f
	rings[radius] = f
	return f
end

local installed = false
function GamepadFocus.installDefault()
	if installed then return end
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	installed = true
	pcall(function()
		if pg.SelectionImageObject == nil then
			pg.SelectionImageObject = GamepadFocus.ring("md")
		end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- QUERIES
-- ═══════════════════════════════════════════════════════════

function GamepadFocus.isGamepad()
	local ok, ff = pcall(FormFactor.Get)
	return ok and ff ~= nil and ff.input == "Gamepad"
end

function GamepadFocus.isInside(obj, root)
	if not obj or not root then return false end
	return obj == root or obj:IsDescendantOf(root)
end

-- Visible up to `root` (or up to an enabled ScreenGui when root is nil).
local function isShown(obj, root)
	local cur = obj
	while cur do
		if cur:IsA("GuiObject") and not cur.Visible then return false end
		if cur == root then return true end
		if cur:IsA("LayerCollector") then return cur.Enabled end
		cur = cur.Parent
	end
	return false
end

function GamepadFocus.canSelect(obj, root)
	if not obj or not obj:IsA("GuiObject") or not obj.Selectable then return false end
	local size = obj.AbsoluteSize
	if size.X < 2 or size.Y < 2 then return false end
	return isShown(obj, root)
end

-- Content first, then tabs (LB / RB reach them anyway), the close ✕ last.
local function rank(obj)
	local n = obj.Name
	if n == "Close" or string.sub(n, 1, 16) == "IconButton_close" then return 3 end
	if string.sub(n, 1, 4) == "Tab_" then return 2 end
	return 1
end

function GamepadFocus.findFirst(root, prefer)
	if not root then return nil end
	if prefer then
		for _, name in ipairs(prefer) do
			local o = root:FindFirstChild(name, true)
			if o and GamepadFocus.canSelect(o, root) then return o end
		end
	end
	local best, bestRank, bestY, bestX = nil, math.huge, math.huge, math.huge
	for _, o in ipairs(root:GetDescendants()) do
		if GamepadFocus.canSelect(o, root) then
			local r = rank(o)
			local p = o.AbsolutePosition
			local y = math.floor(p.Y / 4)   -- same row within 4 px
			if r < bestRank or (r == bestRank and (y < bestY or (y == bestY and p.X < bestX))) then
				best, bestRank, bestY, bestX = o, r, y, p.X
			end
		end
	end
	return best
end

function GamepadFocus.select(obj)
	pcall(function() GuiService.SelectedObject = obj end)
end

-- ═══════════════════════════════════════════════════════════
-- TABS REGISTRY
-- ═══════════════════════════════════════════════════════════

local tabs = {}
local tabsSeq = 0
local tabsListeners = {}
local tabsListenerSeq = 0

local function fireTabsChanged()
	for _, cb in pairs(tabsListeners) do task.spawn(cb) end
end

function GamepadFocus.registerTabs(handle)
	tabsSeq += 1
	local id = tabsSeq
	tabs[id] = handle
	fireTabsChanged()
	return function()
		if tabs[id] then
			tabs[id] = nil
			fireTabsChanged()
		end
	end
end

function GamepadFocus.onTabsChanged(cb)
	tabsListenerSeq += 1
	local id = tabsListenerSeq
	tabsListeners[id] = cb
	return function() tabsListeners[id] = nil end
end

--- The shown Tabs bar inside root (newest registration wins).
function GamepadFocus.tabsIn(root)
	if not root then return nil end
	local found, foundId = nil, -1
	for id, h in pairs(tabs) do
		local r = h.getRoot and h.getRoot()
		if r and GamepadFocus.isInside(r, root) and isShown(r, root) and id > foundId then
			found, foundId = h, id
		end
	end
	return found
end

-- ═══════════════════════════════════════════════════════════
-- OWNED CAS BINDS
-- ═══════════════════════════════════════════════════════════

local casOwners = {}

function GamepadFocus.bindOwned(name, owner, fn, priority, ...)
	casOwners[name] = owner
	ContextActionService:BindActionAtPriority(name, fn, false, priority, ...)
end

function GamepadFocus.unbindOwned(name, owner)
	if casOwners[name] ~= owner then return end
	casOwners[name] = nil
	ContextActionService:UnbindAction(name)
end

-- ═══════════════════════════════════════════════════════════
-- RIGHT-STICK SCROLLING
-- ═══════════════════════════════════════════════════════════

local function canScroll(sf)
	if not sf.ScrollingEnabled then return false end
	local canvas, win = sf.AbsoluteCanvasSize, sf.AbsoluteWindowSize
	return canvas.Y > win.Y + 1 or canvas.X > win.X + 1
end

function GamepadFocus.scrollTarget(root)
	local sel = GuiService.SelectedObject
	if not sel or not sel.Parent then return nil end
	if root and not GamepadFocus.isInside(sel, root) then return nil end
	local cur = sel:IsA("ScrollingFrame") and sel or sel.Parent
	while cur and cur ~= root do
		if cur:IsA("ScrollingFrame") and canScroll(cur) then return cur end
		cur = cur.Parent
	end
	return nil
end

local function inWindow(obj, sf)
	local p, s = obj.AbsolutePosition, obj.AbsoluteSize
	local wp, ws = sf.AbsolutePosition, sf.AbsoluteWindowSize
	local cx, cy = p.X + s.X / 2, p.Y + s.Y / 2
	return cx >= wp.X and cx <= wp.X + ws.X and cy >= wp.Y and cy <= wp.Y + ws.Y
end

-- Keep the selection on screen: if the stick scrolled it out of the window,
-- move it to the selectable nearest the window centre.
local function reselectInView(sf)
	local sel = GuiService.SelectedObject
	if sel and sel.Parent and inWindow(sel, sf) then return end
	local wp, ws = sf.AbsolutePosition, sf.AbsoluteWindowSize
	local centre = Vector2.new(wp.X + ws.X / 2, wp.Y + ws.Y / 2)
	local best, bestD = nil, math.huge
	for _, o in ipairs(sf:GetDescendants()) do
		if GamepadFocus.canSelect(o, sf) and inWindow(o, sf) then
			local c = o.AbsolutePosition + o.AbsoluteSize / 2
			local d = (c - centre).Magnitude
			if d < bestD then best, bestD = o, d end
		end
	end
	if best then GamepadFocus.select(best) end
end

function GamepadFocus.scrollBy(sf, stick, dt)
	if stick.Magnitude < STICK_DEADZONE then return end
	local dir = sf.ScrollingDirection
	local step = SCROLL_SPEED * dt
	local cp = sf.CanvasPosition
	local x, y = cp.X, cp.Y
	if dir ~= Enum.ScrollingDirection.Y then x += stick.X * step end
	if dir ~= Enum.ScrollingDirection.X then y -= stick.Y * step end   -- stick up = scroll up
	-- The engine clamps the far end; clamp the near end here.
	sf.CanvasPosition = Vector2.new(math.max(0, x), math.max(0, y))
	reselectInView(sf)
end

-- ═══════════════════════════════════════════════════════════
-- REACT
-- ═══════════════════════════════════════════════════════════

function GamepadFocus.useGamepad()
	local ff = useFormFactor()
	return ff.input == "Gamepad"
end

function GamepadFocus.useAutoSelect(rootRef, key, opts)
	local gamepad = GamepadFocus.useGamepad()
	local mine = React.useRef(nil)
	local optsRef = React.useRef(opts)
	optsRef.current = opts
	local activeKey = (key ~= nil and key ~= false) and key or false

	React.useEffect(function()
		if activeKey == false or not gamepad then return nil end
		GamepadFocus.installDefault()
		local alive = true
		task.spawn(function()
			for _ = 1, AUTOSELECT_TRIES do
				if not alive then return end
				local root = rootRef.current
				if root then
					local o = optsRef.current or {}
					local cur = GuiService.SelectedObject
					if cur and cur.Parent then
						if GamepadFocus.isInside(cur, root) then
							mine.current = cur
							return
						end
						if not o.steal then return end
					end
					local target = GamepadFocus.findFirst(root, o.prefer)
					if target then
						GamepadFocus.select(target)
						mine.current = target
						return
					end
				end
				task.wait(0.05)
			end
		end)
		return function()
			alive = false
			local cur = GuiService.SelectedObject
			local root = rootRef.current
			if cur and (cur == mine.current or (root and GamepadFocus.isInside(cur, root))) then
				GamepadFocus.select(nil)
			end
			mine.current = nil
		end
	end, { activeKey, gamepad } :: { any })
end

function GamepadFocus.useTabsIn(rootRef, enabled)
	local has, setHas = React.useState(false)
	React.useEffect(function()
		if not enabled then
			setHas(false)
			return nil
		end
		local alive = true
		local function check()
			if not alive then return end
			local root = rootRef.current
			setHas(root ~= nil and GamepadFocus.tabsIn(root) ~= nil)
		end
		task.defer(check)
		local unsub = GamepadFocus.onTabsChanged(function() task.defer(check) end)
		return function()
			alive = false
			unsub()
		end
	end, { enabled == true })
	return has
end

return GamepadFocus
