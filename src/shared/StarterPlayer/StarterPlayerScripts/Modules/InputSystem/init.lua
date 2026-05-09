-- InputSystem/init.lua
--[[
	Centralized input dispatcher.

	Abstracts keyboard / gamepad / touch into named game actions.
	Modules register callbacks for action names instead of listening
	to raw KeyCodes, making the game input-device-agnostic.

	─── Quick start ─────────────────────────────────────────
	  local InputSystem = require(Modules:WaitForChild("InputSystem"))

	  InputSystem.BindAction("Attack", function(actionName, inputState)
	      -- inputState: "Began" | "Ended"
	  end)

	─── Mobile ──────────────────────────────────────────────
	  On-screen buttons fire actions via touch UI callbacks.

	─── Contexts ────────────────────────────────────────────
	  "Combat"  — lane-defense gameplay (Attack, Skill1-4)
	  "Lobby"   — village / social (Interact, EmoteWheel)
	  "UI"      — full-screen menus (all game actions suppressed)

	  Set via InputSystem.SetContext("Combat").

	─── Rebinding ───────────────────────────────────────────
	  InputSystem.SetBinding("Attack", "Keyboard", { Enum.KeyCode.X })
	  InputSystem.ResetAllBindings()
]]

local InputSystem = {}

local UserInputService = game:GetService("UserInputService")

local InputActions = require(script:WaitForChild("InputActions"))

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local activeContext   = "Lobby"      -- "Lobby" | "Combat" | "UI"
local activeInputType = "Keyboard"   -- "Keyboard" | "Gamepad" | "Touch"

-- [actionName] = { [callbackId] = callback }
local actionCallbacks = {}
local nextCallbackId  = 1

-- Rebuilt on every rebind: [KeyCode/UserInputType] = { actionName, ... }
local keyToActions = {}

-- Player overrides: [actionName] = { Keyboard = {...}, Gamepad = {...} }
local playerBindings = {}

-- Callbacks fired when any binding changes (used by UI to re-render key badges)
local bindingChangedCallbacks = {}
local bindingChangedNextId    = 1

-- ═══════════════════════════════════════════════════════════
-- INTERNAL
-- ═══════════════════════════════════════════════════════════

local function DetectPlatform()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "Keyboard"
end

local function RebuildKeyMap()
	keyToActions = {}
	for actionName, def in pairs(InputActions.Definitions) do
		for _, platform in ipairs({ "Keyboard", "Gamepad", "Touch" }) do
			local overrides = playerBindings[actionName]
			local keys = (overrides and overrides[platform])
			           or def.defaults[platform]
			           or {}
			for _, key in ipairs(keys) do
				if not keyToActions[key] then
					keyToActions[key] = {}
				end
				table.insert(keyToActions[key], actionName)
			end
		end
	end
end

local function FireCallbacks(actionName, inputState, inputObject)
	local callbacks = actionCallbacks[actionName]
	if not callbacks then return end
	for _, cb in pairs(callbacks) do
		task.spawn(cb, actionName, inputState, inputObject)
	end
end

local function FireBindingChanged()
	for _, cb in pairs(bindingChangedCallbacks) do
		task.spawn(cb)
	end
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

local initialized = false

function InputSystem.Init()
	if initialized then return end
	initialized = true

	activeInputType = DetectPlatform()
	RebuildKeyMap()

	-- ── InputBegan ────────────────────────────────────────
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		-- Track active device
		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			activeInputType = "Gamepad"
		elseif input.UserInputType == Enum.UserInputType.Touch then
			activeInputType = "Touch"
		else
			activeInputType = "Keyboard"
		end

		-- Resolve key (MouseButton → UserInputType enum)
		local key = input.KeyCode
		if key == Enum.KeyCode.Unknown then
			key = input.UserInputType
		end

		local actions = keyToActions[key]
		if not actions then return end

		for _, actionName in ipairs(actions) do
			local def = InputActions.Definitions[actionName]
			if def and def.contexts[activeContext] then
				FireCallbacks(actionName, "Began", input)
			end
		end
	end)

	-- ── InputEnded ────────────────────────────────────────
	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		local key = input.KeyCode
		if key == Enum.KeyCode.Unknown then
			key = input.UserInputType
		end

		local actions = keyToActions[key]
		if not actions then return end

		for _, actionName in ipairs(actions) do
			local def = InputActions.Definitions[actionName]
			if def and def.contexts[activeContext] then
				FireCallbacks(actionName, "Ended", input)
			end
		end
	end)

	-- ── Gamepad hotplug ──────────────────────────────────
	UserInputService.GamepadConnected:Connect(function()
		activeInputType = "Gamepad"
	end)

	print("[InputSystem] Initialized — platform:", activeInputType, "context:", activeContext)
end

-- ═══════════════════════════════════════════════════════════
-- ACTION BINDING
-- ═══════════════════════════════════════════════════════════

--- Register a callback for a named action. Returns a disconnect id.
function InputSystem.BindAction(actionName, callback)
	if not InputActions.Definitions[actionName] then
		warn("[InputSystem] Unknown action:", actionName)
	end
	if not actionCallbacks[actionName] then
		actionCallbacks[actionName] = {}
	end
	local id = nextCallbackId
	nextCallbackId = nextCallbackId + 1
	actionCallbacks[actionName][id] = callback
	return id
end

--- Remove a specific callback by id.
function InputSystem.UnbindAction(actionName, id)
	if actionCallbacks[actionName] then
		actionCallbacks[actionName][id] = nil
	end
end

-- ═══════════════════════════════════════════════════════════
-- CONTEXT
-- ═══════════════════════════════════════════════════════════

function InputSystem.SetContext(contextName)
	activeContext = contextName
end

-- ═══════════════════════════════════════════════════════════
-- REBINDING
-- ═══════════════════════════════════════════════════════════

--- Change the binding for an action on a specific platform.
--- keys is an array of Enum.KeyCode / Enum.UserInputType values.
function InputSystem.SetBinding(actionName, platform, keys)
	if not playerBindings[actionName] then
		playerBindings[actionName] = {}
	end
	playerBindings[actionName][platform] = keys
	RebuildKeyMap()
	FireBindingChanged()
end

--- Get current binding for an action (player overrides fall back to defaults).
function InputSystem.GetBinding(actionName, platform)
	platform = platform or activeInputType
	local overrides = playerBindings[actionName]
	if overrides and overrides[platform] then
		return overrides[platform]
	end
	local def = InputActions.Definitions[actionName]
	if def then
		return def.defaults[platform] or {}
	end
	return {}
end

--- Human-readable name for the primary key of an action.
function InputSystem.GetBindingDisplayName(actionName, platform)
	local keys = InputSystem.GetBinding(actionName, platform)
	if #keys == 0 then return "—" end
	local key = keys[1]
	if typeof(key) == "EnumItem" then
		if key == Enum.UserInputType.MouseButton1 then return "LMB" end
		if key == Enum.UserInputType.MouseButton2 then return "RMB" end
		return key.Name
	end
	return tostring(key)
end

--- Reset all bindings to defaults.
function InputSystem.ResetAllBindings()
	playerBindings = {}
	RebuildKeyMap()
	FireBindingChanged()
end

--- Subscribe to any binding change. Returns a disconnect function.
function InputSystem.OnBindingChanged(callback)
	local id = bindingChangedNextId
	bindingChangedNextId = bindingChangedNextId + 1
	bindingChangedCallbacks[id] = callback
	return function()
		bindingChangedCallbacks[id] = nil
	end
end

--- Serialize only the player overrides (empty table = all defaults).
--- Values are EnumItem .Name strings, suitable for DataStore.
function InputSystem.GetAllBindings()
	local result = {}
	for actionName, platforms in pairs(playerBindings) do
		result[actionName] = {}
		for platform, keys in pairs(platforms) do
			if type(keys) == "table" and #keys > 0 then
				local key = keys[1]
				if typeof(key) == "EnumItem" then
					result[actionName][platform] = key.Name
				end
			end
		end
	end
	return result
end

--- Apply serialized bindings loaded from DataStore.
--- key names are EnumItem .Name strings (e.g. "Q", "Space", "MouseButton1").
--- Fires OnBindingChanged once when done.
function InputSystem.LoadBindings(serialized)
	if type(serialized) ~= "table" then return end
	local changed = false
	for actionName, platforms in pairs(serialized) do
		if not InputActions.Definitions[actionName] then continue end
		if type(platforms) ~= "table" then continue end
		for platform, keyName in pairs(platforms) do
			if type(keyName) ~= "string" then continue end
			-- Resolve EnumItem by name (KeyCode or UserInputType)
			local key = nil
			for _, kc in ipairs(Enum.KeyCode:GetEnumItems()) do
				if kc.Name == keyName then key = kc; break end
			end
			if not key then
				for _, uit in ipairs(Enum.UserInputType:GetEnumItems()) do
					if uit.Name == keyName then key = uit; break end
				end
			end
			if key then
				if not playerBindings[actionName] then
					playerBindings[actionName] = {}
				end
				playerBindings[actionName][platform] = { key }
				changed = true
			end
		end
	end
	if changed then
		RebuildKeyMap()
		FireBindingChanged()
	end
end

return InputSystem
