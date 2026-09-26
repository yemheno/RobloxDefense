-- UI/HUD/Store.lua
--[[
    §AGX/UI-P5: tiny module-level store used by HUD/RunState and
    HUD/PlayerInfo (the Notify pattern: state lives in the module, not in a
    component, so a HUD remount never resets it — UX-02 made structural).

        local store = Store.new({ a = 1 })
        store.get()                 -> current state table (immutable snapshot)
        store.set(key, value)       -> replaces the snapshot (nil allowed), notifies
        store.subscribe(cb) -> unsubscribe
        Store.use(store)            -> React hook, re-renders on every change
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Store = {}

function Store.new(initial)
	local state = table.clone(initial or {})
	local listeners = {}
	local seq = 0

	local store = {}

	function store.get()
		return state
	end

	function store.set(key, value)
		if state[key] == value then return end
		local nextState = table.clone(state)
		nextState[key] = value
		state = nextState
		for _, cb in pairs(listeners) do
			task.spawn(cb, nextState)
		end
	end

	function store.subscribe(cb)
		seq += 1
		local id = seq
		listeners[id] = cb
		return function() listeners[id] = nil end
	end

	return store
end

function Store.use(store)
	local value, setValue = React.useState(store.get)
	React.useEffect(function()
		setValue(store.get())   -- catch a change between render and effect
		return store.subscribe(setValue)
	end, { store })
	return value
end

return Store
