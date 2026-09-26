-- UI/Common/UIScaleRoot.lua
--[[
    §AGX/UI-P1v2: the D2 scale layer ("fixed px at phone scale + ONE UIScale
    per form factor", DESIGN_DECISIONS.md#ui-decisions UI-D2).

    WHY A LAYER AND NOT A UIScale DIRECTLY UNDER AppGui
      A UIScale scales Scale-sized children too, and AbsoluteSize /
      AbsolutePosition / GetGuiInset report SCREEN px. The legacy screens
      (HUD, TalentTree, ...) measure AbsoluteSize and write the result back
      as Offset; under a 1.333 UIScale that lands at 1.333 x the intended
      spot (the HUD's ⋮ toggle at 0.5 * 1080 = 540 px would render at 720).
      So the scale is a COMPENSATED layer: a Frame sized 1/s of its parent
      with a UIScale of s inside. Scale-sized children end up exactly where
      they were; Offset children (design px) are multiplied by s.

    EXPORTS
      UIScaleRoot.Root   { zIndex?, name?, children }
          Full-parent layer at the form factor's uiScale. App roots mount one
          per band that holds new-model UI (today: TooltipHost). Screens move
          INTO a Root when they are migrated (P3/P5/P6), never before.
      UIScaleRoot.Local  { zIndex?, name?, size?, position?, anchorPoint?, children }
          Applies only the scale still MISSING at this point of the tree
          (target / already applied). Inside a Root it is a plain Frame; in a
          legacy (unscaled) tree it scales. Window, Modal and _Showcase use it,
          so they are correct wherever a caller mounts them.
      UIScaleRoot.useUIScale() -> { target, applied, remaining, kind }
          target    = FormFactor uiScale for this device
          applied   = product of UIScales above this component
          remaining = target / applied
      UIScaleRoot.toLocal(screenPx, applied) -> design px
          Convert an AbsoluteSize / AbsolutePosition / inset (screen px) into
          this layer's units before writing it back as Offset.
      UIScaleRoot.Context  the React context (value = applied scale)

    SEPARATE ScreenGuis (SkillPadGui, ActionBarGui, NotifyGui) have no layer;
    they read FormFactor's pre-scaled `ff.tokens` instead (see FormFactor).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local useFormFactor = require(script.Parent:WaitForChild("useFormFactor"))

local e = React.createElement

local UIScaleRoot = {}

UIScaleRoot.Context = React.createContext(1)

function UIScaleRoot.useUIScale()
	local ff = useFormFactor()
	local applied = React.useContext(UIScaleRoot.Context) or 1
	local target = ff.uiScale or 1
	return {
		target    = target,
		applied   = applied,
		remaining = target / applied,
		kind      = ff.kind,
	}
end

function UIScaleRoot.toLocal(screenPx, applied)
	return screenPx / (applied or 1)   -- number or Vector2
end

-- Shared body: a compensated frame with `factor` UIScale and a provider
-- advertising `provided` to descendants.
local function scaledFrame(props, factor, provided)
	local isOne = math.abs(factor - 1) < 1e-3
	local inv = isOne and 1 or (1 / factor)
	local baseSize = props.size or UDim2.fromScale(1, 1)
	-- Scale parts compensate (1/s), Offset parts are design px and are
	-- multiplied by the UIScale like everything else inside.
	local size = UDim2.new(baseSize.X.Scale * inv, baseSize.X.Offset,
		baseSize.Y.Scale * inv, baseSize.Y.Offset)
	return e("Frame", {
		Name                   = props.name or "UIScaleRoot",
		-- Centre anchor: correct whether the engine scales about the anchor
		-- or the centre; the default placement fills the parent.
		AnchorPoint            = props.anchorPoint or Vector2.new(0.5, 0.5),
		Position               = props.position or UDim2.fromScale(0.5, 0.5),
		Size                   = size,
		BackgroundTransparency = 1,
		ZIndex                 = props.zIndex or 1,
		LayoutOrder            = props.layoutOrder,
	}, {
		scale = (not isOne) and e("UIScale", { Scale = factor }) or nil,
		content = e(UIScaleRoot.Context.Provider, { value = provided }, props.children),
	})
end

--- Full layer at the device's uiScale (use once per band in an App root).
function UIScaleRoot.Root(props)
	local s = UIScaleRoot.useUIScale()
	-- A Root nested in another scaled tree only adds what is missing.
	return scaledFrame(props, s.remaining, s.target)
end

--- Adds only the missing scale (no-op frame inside a Root).
function UIScaleRoot.Local(props)
	local s = UIScaleRoot.useUIScale()
	return scaledFrame(props, s.remaining, s.target)
end

return UIScaleRoot
