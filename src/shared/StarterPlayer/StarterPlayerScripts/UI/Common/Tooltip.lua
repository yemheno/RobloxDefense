-- UI/Common/Tooltip.lua
--[[
    §AGX/UI-P1v2: Tooltip + TooltipHost (visual-system.md §4.2, mobile.md §2.6).
    Hover on PC, long-press (0.35 s) on touch, selection on gamepad, all via
    usePressHold. ONE TooltipHost per App root renders the bubble above
    everything (Theme.Z.tooltip), clamped to the screen.

    1) Wrap any element:
        e(Tooltip, { text = "Costs 50 Essence", placement = "auto", target = e(IconButton, {...}) })
       (the target's own InputBegan/MouseEnter/... props are replaced; for
        elements that need those, use the hook.)
    2) Hook, for components that own their events (Button/IconButton `tooltip` prop):
        local tip = Tooltip.use(text, { placement = "auto" })
        -- tip.events -> merge into the element props
        -- tip.wrapActivated(fn) -> swallows the tap that ends a long-press
    3) Host (App roots, inside a UIScaleRoot.Root at Theme.Z.tooltip):
        e(Tooltip.Host)
       §AGX/UI-FIX: 3 — mount it in its OWN ScreenGui at
       Theme.DisplayOrder.tooltip (50), as Shell.lua does ("TooltipGui"):
       inside AppGui (0) the bubble renders under PanelGui (20). Target and
       host positions are both AbsolutePosition, so any ScreenGui with the
       same ScreenInsets as the targets' works.

    Imperative: Tooltip.show(rbx, text, opts) -> token; Tooltip.hide(token).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent
local Theme         = require(Common:WaitForChild("Theme"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local usePressHold  = require(Common:WaitForChild("usePressHold"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))

local e  = React.createElement
local R  = Theme.Roles
local TT = Theme.Metrics.tooltip

-- ── Store ────────────────────────────────────────────────────────────────────
local current   = nil     -- { token, text, pos, size, placement } (screen px)
local listeners = {}
local nextToken = 0

local function emit()
	for _, cb in pairs(listeners) do task.spawn(cb, current) end
end

local Tooltip = {}

function Tooltip.show(rbx, text, opts)
	if not rbx or not text or text == "" then return nil end
	nextToken += 1
	current = {
		token     = nextToken,
		text      = text,
		pos       = rbx.AbsolutePosition,
		size      = rbx.AbsoluteSize,
		placement = (opts and opts.placement) or "auto",
	}
	emit()
	return nextToken
end

function Tooltip.hide(token)
	if current and (token == nil or current.token == token) then
		current = nil
		emit()
	end
end

function Tooltip.subscribe(cb)
	local key = {}
	listeners[key] = cb
	return function() listeners[key] = nil end
end

-- ── Hook ─────────────────────────────────────────────────────────────────────
function Tooltip.use(text, opts)
	local tokenRef = React.useRef(nil)
	local textRef  = React.useRef(text)
	textRef.current = text
	local hold = usePressHold({
		onHold = function(rbx)
			if textRef.current then
				tokenRef.current = Tooltip.show(rbx, textRef.current, opts)
			end
		end,
		onRelease = function()
			Tooltip.hide(tokenRef.current)
			tokenRef.current = nil
		end,
		holdTime = TT.holdTime,
		moveCancel = TT.moveCancel,
	})
	-- Hide if the owner unmounts while its tooltip is up.
	React.useEffect(function()
		return function()
			if tokenRef.current then Tooltip.hide(tokenRef.current) end
		end
	end, {})
	return hold
end

-- ── Wrapper component ────────────────────────────────────────────────────────
function Tooltip.Tooltip(props)
	local tip = Tooltip.use(props.text, { placement = props.placement })
	if not props.target then return nil end
	return React.cloneElement(props.target, tip.events)
end

-- ── Host ─────────────────────────────────────────────────────────────────────
function Tooltip.Host(props)
	local ff = useFormFactor()
	local scale = UIScaleRoot.useUIScale()
	local tip, setTip = React.useState(current)
	local hostRef = React.useRef(nil)

	React.useEffect(function()
		setTip(current)
		return Tooltip.subscribe(setTip)
	end, {})

	local ty = Theme.typeFor("caption", ff.kind)
	local host = hostRef.current
	local bubble = nil
	if tip and host then
		-- Everything in this layer's units (design px under a Root).
		local applied = scale.applied
		local origin  = host.AbsolutePosition
		local hostW   = host.AbsoluteSize.X / applied
		local hostH   = host.AbsoluteSize.Y / applied
		local ax = (tip.pos.X - origin.X) / applied
		local ay = (tip.pos.Y - origin.Y) / applied
		local aw = tip.size.X / applied
		local ah = tip.size.Y / applied

		local estH = ty.lineHeight * 2 + 2 * TT.pad
		local above = tip.placement ~= "below"
			and (tip.placement == "above" or ay - TT.offset - estH >= 0)
		local half = TT.maxWidth / 2
		local cx = math.clamp(ax + aw / 2, half + TT.pad, math.max(half + TT.pad, hostW - half - TT.pad))
		local y = above and (ay - TT.offset) or math.min(ay + ah + TT.offset, hostH - estH)

		bubble = e("Frame", {
			Name                   = "Tooltip",
			AnchorPoint            = Vector2.new(0.5, above and 1 or 0),
			Position               = UDim2.fromOffset(cx, y),
			Size                   = UDim2.fromOffset(0, 0),
			AutomaticSize          = Enum.AutomaticSize.XY,
			BackgroundColor3       = R.surface.raised,
			BackgroundTransparency = 0.02,
			BorderSizePixel        = 0,
			ZIndex                 = Theme.Z.tooltip,
		}, {
			corner  = e("UICorner", { CornerRadius = Theme.Radius.md }),
			stroke  = e("UIStroke", { Color = R.border.focus, Thickness = Theme.Stroke.base, Transparency = 0.2 }),
			padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, TT.pad), PaddingRight = UDim.new(0, TT.pad),
				PaddingTop = UDim.new(0, TT.pad / 2), PaddingBottom = UDim.new(0, TT.pad / 2),
			}),
			limit   = e("UISizeConstraint", { MaxSize = Vector2.new(TT.maxWidth, math.huge) }),
			text    = e("TextLabel", {
				Size                   = UDim2.fromOffset(0, 0),
				AutomaticSize          = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Text                   = tip.text,
				TextColor3             = R.text.primary,
				FontFace               = ty.font,
				TextSize               = ty.size,
				TextWrapped            = true,
				ZIndex                 = Theme.Z.tooltip + 1,
			}, {
				limit = e("UISizeConstraint", { MaxSize = Vector2.new(TT.maxWidth - 2 * TT.pad, math.huge) }),
				tsize = e("UITextSizeConstraint", { MinTextSize = ty.min, MaxTextSize = ty.max }),
			}),
		})
	end

	return e("Frame", {
		Name                   = "TooltipHost",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = (props and props.zIndex) or Theme.Z.tooltip,
		ref                    = hostRef,
	}, { bubble = bubble })
end

-- Module is a table (AchievementsUI style); `Tooltip.Tooltip` is the
-- wrapper component, `Tooltip.Host` the host.
return Tooltip
