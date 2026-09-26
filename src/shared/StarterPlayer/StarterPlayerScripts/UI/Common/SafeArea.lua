-- UI/Common/SafeArea.lua
--[[
    §AGX/UI-P1v2: SafeArea (visual-system.md §4.2, mobile.md §2.3).
    The App ScreenGuis already use ScreenInsets = DeviceSafeInsets (notch,
    rounded corners, home bar). What that does NOT clear is Roblox's own
    topbar, so SafeArea pads the top by FormFactor's topbar height (converted
    to this layer's units, so it is right inside or outside a UIScaleRoot),
    plus an optional edge margin from Theme.Layout.

    SafeArea{
        topbar  = true,     -- clear the Roblox topbar
        margin  = false,    -- add Layout[kind].edge on all four sides
        gap     = 4,        -- extra px under the topbar (design px)
        zIndex, name, children
    }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common        = script.Parent
local useFormFactor = require(Common:WaitForChild("useFormFactor"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))

local e = React.createElement

local function SafeArea(props)
	local ff = useFormFactor()
	local scale = UIScaleRoot.useUIScale()

	local edge = props.margin and (ff.design.edge or 16) or 0
	-- topbar is screen px; this frame's Offsets are multiplied by `applied`.
	local top = (props.topbar ~= false)
		and (UIScaleRoot.toLocal(ff.topbar or 0, scale.applied) + (props.gap or 4)) or 0

	local children = {
		padding = e("UIPadding", {
			PaddingTop    = UDim.new(0, math.max(top, edge)),
			PaddingLeft   = UDim.new(0, edge),
			PaddingRight  = UDim.new(0, edge),
			PaddingBottom = UDim.new(0, edge),
		}),
	}
	if props.children then
		for k, v in pairs(props.children) do children[k] = v end
	end

	return e("Frame", {
		Name                   = props.name or "SafeArea",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = props.zIndex,
	}, children)
end

return SafeArea
