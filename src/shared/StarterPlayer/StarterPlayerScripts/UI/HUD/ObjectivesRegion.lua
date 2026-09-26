-- UI/HUD/ObjectivesRegion.lua
--[[
    §AGX/UI-P5: defense-line bar (under the vitals, Layout L.defense) +
    defense-combo badge (above the combo counter, Layout L.defCombo).
    props: layout (L), run (RunState state), showBar, showCombo
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common    = script.Parent.Parent:WaitForChild("Common")
local Theme     = require(Common:WaitForChild("Theme"))
local Text      = require(Common:WaitForChild("Text"))
local StatusBar = require(script.Parent:WaitForChild("StatusBar"))

local e = React.createElement
local C = Theme.Colors

local DEFENSE_COLOR = Color3.fromRGB(210, 80, 80)
local COMBO_TEXT    = Color3.fromRGB(255, 180, 80)
local COMBO_BG      = Color3.fromRGB(30, 20, 40)

local function ObjectivesRegion(props)
	local L, run = props.layout, props.run
	local def = run.defenseHP
	local defCombo = run.defCombo
	local bar, badge = L.defense, L.defCombo

	return e("Frame", {
		Name                   = "Objectives",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = 3,
	}, {
		defenseBar = (props.showBar and def ~= nil) and e("Frame", {
			Name                   = "DefenseBar",
			AnchorPoint            = bar.anchorPoint,
			Position               = bar.position,
			Size                   = bar.size,
			BackgroundColor3       = C.panel,
			BackgroundTransparency = 0.30,
			BorderSizePixel        = 0,
			ZIndex                 = 3,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
			pad = e("UIPadding", {
				PaddingLeft = UDim.new(0, Theme.Space.xs), PaddingRight = UDim.new(0, Theme.Space.xs),
			}),
			bar = e(StatusBar.default, {
				label   = "Defense",
				current = def.cur,
				max     = def.max,
				color   = DEFENSE_COLOR,
				columns = (bar.w < 300) and StatusBar.NARROW_COLUMNS or nil,
			}),
		}) or nil,

		defCombo = (props.showCombo and defCombo ~= nil and defCombo.level >= 1) and e("Frame", {
			Name                   = "DefenseCombo",
			AnchorPoint            = badge.anchorPoint,
			Position               = badge.position,
			Size                   = badge.size,
			BackgroundColor3       = COMBO_BG,
			BackgroundTransparency = 0.20,
			BorderSizePixel        = 0,
			ZIndex                 = 3,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
			label = e(Text, {
				style  = "label",
				text   = "Defense Combo Lv" .. tostring(defCombo.level)
					.. "  x" .. string.format("%.1f", defCombo.multiplier),
				color  = COMBO_TEXT,
				align  = "center",
				size   = UDim2.fromScale(1, 1),
				fit    = true,
				zIndex = 4,
			}),
		}) or nil,
	})
end

return ObjectivesRegion
