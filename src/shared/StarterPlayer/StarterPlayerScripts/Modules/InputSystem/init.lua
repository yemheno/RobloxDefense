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
	  -- §AGX/UI-P2: they call InputSystem.FireAction(name, "Began"/"Ended")
	  -- (UI/Common/SkillPad.lua), which applies the same context gate as
	  -- physical input.

	─── Active device ───────────────────────────────────────
	  -- §AGX/UI-P2: GetActiveInputType() -> "Keyboard" | "Gamepad" | "Touch",
	  -- live (from Modules/FormFactor), and OnInputTypeChanged(cb).

	─── Contexts ────────────────────────────────────────────
	  "Combat"  — lane-defense gameplay (Attack, Skill1-4)
	  "Lobby"   — village / social (Interact, EmoteWheel)
	  "UI"      — full-screen menus (all game actions suppressed)

	  Set via InputSystem.SetContext("Combat").

	  -- §AGX/UI-P3: base / override split (shell-spec §3.4, D6).
	  SetContext(name) sets the BASE context (place clients, SceneController,
	  the Horde vote pause). PushUIContext() -> release() adds a ref-counted
	  "UI" override (the PanelStack holds one while any panel/menu is open).
	  GetContext() and every dispatch gate use the EFFECTIVE context:
	      effective = (uiOverride > 0) and "UI" or base
	  OnContextChanged fires only when the effective value changes, so a base
	  change under an open menu is silent until the menu closes, and closing
	  a menu can't un-pause a paused Horde (its base stays "UI").

	─── Rebinding ───────────────────────────────────────────
	  InputSystem.SetBinding("Attack", "Keyboard", { Enum.KeyCode.X })
	  InputSystem.ResetAllBindings()
]]

local InputSystem = {}

local UserInputService = game:GetService("UserInputService")

local InputActions = require(script:WaitForChild("InputActions"))
-- §AGX/UI-P2: live device detection lives in FormFactor (mobile.md §2.7/M5).
local FormFactor   = require(script.Parent:WaitForChild("FormFactor"))

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local activeContext   = "Lobby"      -- EFFECTIVE context: "Lobby" | "Combat" | "UI"
-- §AGX/UI-P3: base context (SetContext) + ref-counted UI override (PushUIContext).
local baseContext     = "Lobby"
local uiOverride      = 0
local activeInputType = "Keyboard"   -- "Keyboard" | "Gamepad" | "Touch"

-- §AGX/UI-P2: input-type and context change listeners, plus the actions whose
-- "Began" went out through FireAction (so their "Ended" is always delivered,
-- even if the context changed mid-hold; otherwise a hold would stick).
local inputTypeCallbacks = {}
local contextCallbacks   = {}
local signalNextId       = 1
local firedHeld          = {}

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

-- §AGX/UI-P2: replaces the detect-once DetectPlatform(). FormFactor's
-- "KeyboardMouse" maps to this module's historical "Keyboard" platform key.
local function MapInputType(ffInput)
	if ffInput == "Touch" or ffInput == "Gamepad" then return ffInput end
	return "Keyboard"
end

local function AddListener(list, callback)
	local id = signalNextId
	signalNextId = signalNextId + 1
	list[id] = callback
	return function()
		list[id] = nil
	end
end

local function SyncInputType(ff)
	local newType = MapInputType(ff.input)
	if newType == activeInputType then return end
	activeInputType = newType
	for _, cb in pairs(inputTypeCallbacks) do
		task.spawn(cb, newType)
	end
end

activeInputType = MapInputType(FormFactor.Get().input)
FormFactor.Changed(SyncInputType)

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

	-- §AGX/UI-P2: activeInputType now follows FormFactor (see SyncInputType).
	SyncInputType(FormFactor.Get())
	RebuildKeyMap()

	-- ── InputBegan ────────────────────────────────────────
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		-- §AGX/UI-P2: active-device tracking moved to FormFactor (debounced,
		-- and it also sees gameProcessed input, which this handler skips).

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

	-- §AGX/UI-P2: the GamepadConnected override is gone; plugging a pad in
	-- no longer claims "Gamepad" until it is actually used (FormFactor).

end

-- ═══════════════════════════════════════════════════════════
-- VIRTUAL INPUT (§AGX/UI-P2)
-- ═══════════════════════════════════════════════════════════

--- Fire a named action from UI (e.g. the touch SkillPad), with the same
--- context gate physical input gets. inputState: "Began" (default) | "Ended".
--- Returns true when the action was dispatched.
function InputSystem.FireAction(actionName, inputState)
	local def = InputActions.Definitions[actionName]
	if not def then
		warn("[InputSystem] FireAction: unknown action:", actionName)
		return false
	end
	inputState = inputState or "Began"

	if inputState == "Ended" then
		-- Always close a hold we opened, whatever the context is now.
		if firedHeld[actionName] then
			firedHeld[actionName] = nil
			FireCallbacks(actionName, "Ended", nil)
			return true
		end
		if not def.contexts[activeContext] then return false end
		FireCallbacks(actionName, "Ended", nil)
		return true
	end

	-- Same gate as InputBegan: suppressed outside the action's contexts,
	-- which includes the "UI" context (D6: no skills behind menus).
	if not def.contexts[activeContext] then return false end
	firedHeld[actionName] = true
	FireCallbacks(actionName, inputState, nil)
	return true
end

-- ═══════════════════════════════════════════════════════════
-- ACTIVE INPUT TYPE (§AGX/UI-P2)
-- ═══════════════════════════════════════════════════════════

--- "Keyboard" | "Gamepad" | "Touch", live. Same keys GetBinding uses.
function InputSystem.GetActiveInputType()
	return activeInputType
end

--- cb(newType) whenever the active input type changes. Returns a disconnect.
function InputSystem.OnInputTypeChanged(callback)
	return AddListener(inputTypeCallbacks, callback)
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

-- §AGX/UI-P3: recompute the effective context; notify only on a real change.
local function UpdateEffectiveContext()
	local effective = (uiOverride > 0) and "UI" or baseContext
	if effective == activeContext then return end
	activeContext = effective
	-- §AGX/UI-P2: notify listeners (SkillPad hides outside "Combat").
	for _, cb in pairs(contextCallbacks) do
		task.spawn(cb, effective)
	end
end

--- Sets the BASE context (§AGX/UI-P3). While a UI override is held the
--- effective context stays "UI" and listeners hear nothing until release.
function InputSystem.SetContext(contextName)
	if contextName == baseContext then return end
	baseContext = contextName
	UpdateEffectiveContext()
end

-- §AGX/UI-P2: read the current (§AGX/UI-P3: effective) context.
function InputSystem.GetContext()
	return activeContext
end

-- §AGX/UI-P3: the base context under any UI override (diagnostics / shell).
function InputSystem.GetBaseContext()
	return baseContext
end

--- §AGX/UI-P3: push a ref-counted "UI" override (D6: no skills, dash, NPC
--- prompts or emote key behind an open menu). Returns release(); calling it
--- more than once is a no-op.
function InputSystem.PushUIContext()
	uiOverride += 1
	UpdateEffectiveContext()
	local released = false
	return function()
		if released then return end
		released = true
		uiOverride = math.max(0, uiOverride - 1)
		UpdateEffectiveContext()
	end
end

-- §AGX/UI-P2: cb(contextName) on every context change. Returns a disconnect.
function InputSystem.OnContextChanged(callback)
	return AddListener(contextCallbacks, callback)
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
