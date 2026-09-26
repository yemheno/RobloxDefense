-- shared/StarterPlayerScripts/UI/KeybindSettings.lua
--[[
    §AGX/UI-P6: UX-13. Thin wrapper: the ONE keybind editor is SettingsUI's
    Controls tab. This module keeps the contract so BattleClassUI's
    "Controls / Rebind Keys" (and the Registry "keybinds" entry) keep working:

        e(KeybindSettings, { onClose = fn })

    It renders SettingsUI opened on "Controls". The capture veto (A11) lives
    in SettingsUI's useCloseHandler: rendered here it registers on the
    enclosing entry (BattleClassUI's "class"), and being newer than
    BattleClassUI's own A13 handler it still runs first, so Back while a
    key is being captured cancels the capture and vetoes the pop.

    Inside a PanelHost entry the window would otherwise inherit the class
    panel's presentation (e.g. "side"); the wrapper re-provides the entry
    context with no presentation / no backdrop dismiss, so AppWindow uses
    "auto" (sheet on phone, windowed elsewhere). The entry id is kept, so the
    close handler still registers on the right entry.

    Props:
      onClose  function()   called when the player closes the panel
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local Theme      = require(script.Parent:WaitForChild("Common"):WaitForChild("Theme"))
local SettingsUI = require(script.Parent:WaitForChild("SettingsUI"))

-- §AGX/UI-P3: PanelStack is optional (nil-safe without UI/Shell).
local EntryContext = nil
do
	local shell = script.Parent:FindFirstChild("Shell")
	local mod = shell and shell:FindFirstChild("PanelStack")
	if mod then
		local ok, PanelStack = pcall(require, mod)
		if ok and type(PanelStack) == "table" then
			EntryContext = PanelStack.EntryContext
		end
	end
end
EntryContext = EntryContext or React.createContext(nil)

local e = React.createElement

local function KeybindSettings(props)
	local onClose = props.onClose
	local ctx = React.useContext(EntryContext)

	-- Same entry (id / top) minus the presentation override and D8 backdrop.
	local wrapped = React.useMemo(function()
		if ctx == nil then return nil end
		local copy = table.clone(ctx)
		copy.presentation = nil
		copy.dismissable  = false
		copy.onBackdrop   = nil
		return copy
	end, { ctx })

	local panel = e(SettingsUI, {
		initialTab = "Controls",
		-- Above the BattleClassUI panel it is mounted beside.
		zIndex     = Theme.Z.windowOver,
		onClose    = function()
			if onClose then onClose() end
		end,
	})

	if wrapped == nil then
		return panel
	end
	return e(EntryContext.Provider, { value = wrapped }, panel)
end

return KeybindSettings
