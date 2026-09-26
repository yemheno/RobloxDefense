-- UI/HUD/PlayCta.lua
--[[
    §AGX/UI-P5: Lobby PLAY call-to-action (shell-spec §4.2). The one primary
    CTA of the Lobby HUD (D1 Hybrid: orange). Bottom-right, clear of the
    Roblox jump button on touch. Calls props.onPlay (the Shell passes
    PanelStack.open("play")); renders nothing without it.
    props: layout (L), onPlay, visible
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Button = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("Button"))

local function PlayCta(props)
	local r = props.layout.play
	if not props.visible or not props.onPlay or not r then return nil end
	return React.createElement(Button, {
		name        = "PlayCta",
		variant     = "primary",
		size        = "lg",   -- 56 design px
		label       = "▶ Play",
		width       = r.w,
		anchorPoint = r.anchorPoint,
		position    = r.position,
		zIndex      = 3,
		onActivated = props.onPlay,
	})
end

return PlayCta
