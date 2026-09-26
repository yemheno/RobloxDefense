-- UI/HUD/ComboRegion.lua
--[[
    §AGX/UI-P5: personal combo counter, shown
    at >= 3 hits. Bottom-centre: above the safe edge on touch (kept left of
    the SkillPad footprint), above the ActionBar on desktop / console.
    props: layout (L), combo (number?), visible
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common = script.Parent.Parent:WaitForChild("Common")
local Theme  = require(Common:WaitForChild("Theme"))
local Text   = require(Common:WaitForChild("Text"))

local e = React.createElement
local R = Theme.Roles

local GOLD      = Color3.fromRGB(255, 200, 50)
local GOLD_TEXT = Color3.fromRGB(255, 210, 60)

local function ComboRegion(props)
	local combo = props.combo
	if not props.visible or combo == nil or combo < 3 then return nil end
	local r = props.layout.combo
	return e("Frame", {
		Name                   = "Combo",
		AnchorPoint            = r.anchorPoint,
		Position               = r.position,
		Size                   = r.size,
		BackgroundColor3       = R.surface.base,
		BackgroundTransparency = 0.25,
		BorderSizePixel        = 0,
		ZIndex                 = 3,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.Radius.lg }),
		stroke = e("UIStroke", { Color = GOLD, Thickness = Theme.Stroke.strong }),
		label = e(Text, {
			style  = "heading",
			text   = tostring(combo) .. "x  COMBO",
			color  = GOLD_TEXT,
			align  = "center",
			size   = UDim2.fromScale(1, 1),
			fit    = true,
			zIndex = 4,
		}),
	})
end

return ComboRegion
