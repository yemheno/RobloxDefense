-- StarterPlayerScripts/Modules/KeybindManager

local KeybindManager = {}

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Default keybinds (slot → keycode)
local DEFAULT_KEYBINDS = {
	[1] = Enum.KeyCode.Q,
	[2] = Enum.KeyCode.E,
	[3] = Enum.KeyCode.R,
	[4] = Enum.KeyCode.F,
}

-- Player's current keybinds
local currentKeybinds = {}  -- [slot] = KeyCode
local reverseMap = {}       -- [KeyCode] = slot

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function KeybindManager.Init()
	-- Load defaults
	for slot, keyCode in pairs(DEFAULT_KEYBINDS) do
		KeybindManager.SetKeybind(slot, keyCode)
	end

	print("[KeybindManager] Initialized - Q/E/R/T for slots 1/2/3/4")
end

-- ═══════════════════════════════════════════════════════════
-- KEYBIND MANAGEMENT
-- ═══════════════════════════════════════════════════════════

function KeybindManager.SetKeybind(slot, keyCode)
	-- Remove old reverse mapping
	local oldKey = currentKeybinds[slot]
	if oldKey then
		reverseMap[oldKey] = nil
	end

	-- Check if this key is already used by another slot
	local existingSlot = reverseMap[keyCode]
	if existingSlot and existingSlot ~= slot then
		-- Swap: give old slot the key we're replacing
		if oldKey then
			currentKeybinds[existingSlot] = oldKey
			reverseMap[oldKey] = existingSlot
		else
			currentKeybinds[existingSlot] = nil
		end
	end

	-- Set new keybind
	currentKeybinds[slot] = keyCode
	reverseMap[keyCode] = slot
end

function KeybindManager.GetKeybind(slot)
	return currentKeybinds[slot]
end

function KeybindManager.GetSlotForKey(keyCode)
	return reverseMap[keyCode]
end

function KeybindManager.GetAllKeybinds()
	return currentKeybinds
end

function KeybindManager.ResetToDefaults()
	currentKeybinds = {}
	reverseMap = {}

	for slot, keyCode in pairs(DEFAULT_KEYBINDS) do
		KeybindManager.SetKeybind(slot, keyCode)
	end

	print("[KeybindManager] Reset to defaults")
end

-- ═══════════════════════════════════════════════════════════
-- FOR UI DISPLAY
-- ═══════════════════════════════════════════════════════════

function KeybindManager.GetKeybindName(slot)
	local keyCode = currentKeybinds[slot]
	if not keyCode then return "?" end

	return keyCode.Name  -- Returns "Q", "E", etc.
end

function KeybindManager.GetDefaultKeybinds()
	return DEFAULT_KEYBINDS
end

return KeybindManager