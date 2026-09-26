-- UI/Shell/Badge.lua
--[[
    §AGX/UI-P3: menu badges (shell-spec §3.7 "Rendering", B3).

    Badge.View{ count, zIndex?, position?, anchorPoint?, size? }
        A circle (16 design px, Phone 18) whose centre sits at the parent's
        top-right corner inset 4 px (AnchorPoint 0.5,0.5 at UDim2.new(1,-4,0,4)).
        count <= 0 renders nothing, 1 renders a dot, > 1 renders the number
        ("9+" above 9). Text is >= 12 px.
        Colour: state.dangerFill + text.onDanger (5.5:1). Theme v2 reserves
        orange for ribbons / primary CTAs / vitals, and IconButton's built-in
        badge already uses this red, so every badge in the game matches.
        (Deviation from the spec's `Theme.Colors.accent`: Theme v2 wins.)

    Badge.useBadges() -> get(key) -> number
        Subscribes ONCE to BadgeStore (UI/Shell/BadgeStore) and re-renders on
        any change. `get` is nil-safe: no store, no key, or a store error all
        read as 0, so menus always render.

    Badge.sum(get, keys) -> number    OR of several keys (group / ☰ badge)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent.Parent:WaitForChild("Common")
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))

local e = React.createElement
local R = Theme.Roles
local MM = Theme.Metrics.menu

local Badge = {}

-- ── BadgeStore (lazy, nil-safe) ──────────────────────────────────────────────
local store, storeTried = nil, false
local function getStore()
	if storeTried then return store end
	storeTried = true
	local mod = script.Parent:FindFirstChild("BadgeStore")
	if mod then
		local ok, result = pcall(require, mod)
		if ok and type(result) == "table" then store = result end
	end
	return store
end

local function unsubscribe(handle)
	if type(handle) == "function" then
		handle()
	elseif handle ~= nil then   -- a connection (or a { Disconnect } table)
		pcall(function() handle:Disconnect() end)
	end
end

function Badge.useBadges()
	local _, setTick = React.useState(0)
	React.useEffect(function()
		local s = getStore()
		if not s or type(s.subscribe) ~= "function" then return nil end
		local handle = s.subscribe(function()
			setTick(function(n) return n + 1 end)
		end)
		return function() unsubscribe(handle) end
	end, {})
	return function(key)
		if key == nil then return 0 end
		local s = getStore()
		if not s or type(s.get) ~= "function" then return 0 end
		local ok, n = pcall(s.get, key)
		return (ok and tonumber(n)) or 0
	end
end

function Badge.sum(get, keys)
	local total = 0
	for _, key in ipairs(keys or {}) do
		total += math.max(0, get(key))
	end
	return total
end

--- Clear a badge key (e.g. achievements on open). Nil-safe.
function Badge.clear(key)
	local s = getStore()
	if key and s and type(s.clear) == "function" then pcall(s.clear, key) end
end

-- ── View ─────────────────────────────────────────────────────────────────────
function Badge.View(props)
	local ff = useFormFactor()
	local count = tonumber(props.count) or 0
	if count <= 0 then return nil end

	local side = props.size or ((ff.kind == "Phone") and MM.badgePhone or MM.badge)
	local showNumber = count > 1
	local z = props.zIndex or 1

	return e("TextLabel", {
		Name                   = "Badge",
		AnchorPoint            = props.anchorPoint or Vector2.new(0.5, 0.5),
		Position               = props.position or UDim2.new(1, -4, 0, 4),
		Size                   = UDim2.fromOffset(showNumber and side or math.floor(side * 0.72), showNumber and side or math.floor(side * 0.72)),
		AutomaticSize          = showNumber and Enum.AutomaticSize.X or nil,
		BackgroundColor3       = R.state.dangerFill,
		BorderSizePixel        = 0,
		Text                   = showNumber and ((count > 9) and "9+" or tostring(count)) or "",
		TextColor3             = R.text.onDanger,
		FontFace               = Theme.FontFaces.bold,
		TextSize               = math.max(12, side - 5),
		ZIndex                 = z,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
		-- navy ring so the badge separates from any tile / icon behind it
		ring   = e("UIStroke", {
			Color = R.surface.base, Thickness = Theme.Stroke.strong,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		pad    = showNumber and e("UIPadding", {
			PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
		}) or nil,
	})
end

return Badge
