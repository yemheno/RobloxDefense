-- UI/Common/useFormFactor.lua
--[[
    §AGX/UI-P2: React hook over Modules/FormFactor (mobile.md §2.7).

        local ff = useFormFactor()
        -- ff.kind, ff.input, ff.isTouch, ff.viewport, ff.short,
        -- ff.topbar, ff.tokens (= Theme.Layout[ff.kind]), ff.uiScale

    Re-renders the caller whenever FormFactor.Changed fires.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local FormFactor = require(
	Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules"):WaitForChild("FormFactor")
)

local function useFormFactor()
	local ff, setFF = React.useState(FormFactor.Get())
	React.useEffect(function()
		-- §AGX/UI-P2: catch a change that landed between render and effect.
		setFF(FormFactor.Get())
		return FormFactor.Changed(setFF)
	end, {})
	return ff
end

return useFormFactor
