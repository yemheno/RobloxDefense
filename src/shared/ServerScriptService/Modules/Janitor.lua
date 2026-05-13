-- ServerScriptService/Modules/Janitor
--[[
    Janitor
    =======
    Per-scope resource tracker. Lifetime management for connections,
    threads, Instances, callbacks, and any value with :Destroy() or
    :Disconnect().

    Why it exists
    -------------
    Until v0.5 we tracked per-player cleanups with hand-rolled tables and
    bare `task.delay(N, conn.Disconnect)` calls scattered across modules.
    Three problems with that pattern:
      • Magic-number expiry timers — if Roblox's avatar loader takes
        longer than expected the conn never fires; if shorter, the conn
        leaks until PlayerRemoving.
      • The cleanup tables grew without bound — old entries were
        disconnected by `task.delay` but never removed from the list, so
        long sessions accumulated dead conn refs.
      • Each module reinvented the same pattern slightly differently.

    Janitor is the single primitive. Replace `table.insert + task.delay`
    pairs with `:Add(value, key)` + `:Remove(key)` or `:Destroy()`.

    Public API
    ----------
      Janitor.new()                          → new janitor instance
      jan:Add(value, key?)                   → tracked, returns the value
      jan:Remove(key)                        → clean one slot
      jan:Destroy()                          → tear down all in reverse-add
      jan:LinkToInstance(instance)           → auto-destroy on AncestryChanged
      jan:IsDestroyed()                      → bool

    Supported value types
    ---------------------
      • RBXScriptConnection   → :Disconnect()
      • Instance              → :Destroy()
      • function              → invoked with no args (pcall-wrapped)
      • thread                → task.cancel()
      • table with :Destroy() → :Destroy()  (e.g. nested Janitor)
      • table with :Disconnect() (e.g. some signal libraries)

    Common patterns
    ---------------
      -- Player-scoped lifetime
      local jan = Janitor.new()
      jan:Add(humanoid.HealthChanged:Connect(onHealth))
      jan:Add(character.ChildAdded:Connect(onChild))
      Players.PlayerRemoving:Once(function(p) if p == player then jan:Destroy() end end)

      -- Keyed slot — re-adding the same key auto-cleans the previous one
      jan:Add(connA, "ambient")
      jan:Add(connB, "ambient")   -- connA disconnected here

      -- Bound to an Instance — Janitor auto-destroys when the Instance does
      local jan = Janitor.new()
      jan:LinkToInstance(character)
      jan:Add(character.ChildAdded:Connect(...))
]]

local Janitor = {}
Janitor.__index = Janitor

-- ─────────────────────────────────────────────────────────────────────
-- INTERNALS
-- ─────────────────────────────────────────────────────────────────────

local function detectKind(value)
    local t = typeof(value)
    if t == "RBXScriptConnection" then return "conn" end
    if t == "Instance"            then return "inst" end
    if t == "thread"              then return "thread" end
    if t == "function"            then return "fn" end
    if t == "table" then
        if type(value.Destroy)    == "function" then return "destroyable"    end
        if type(value.Disconnect) == "function" then return "disconnectable" end
    end
    return nil
end

local function cleanup(kind, value)
    if kind == "conn" then
        local ok, err = pcall(value.Disconnect, value)
        if not ok then warn("[Janitor] Disconnect errored: " .. tostring(err)) end

    elseif kind == "inst" then
        local ok, err = pcall(value.Destroy, value)
        if not ok then warn("[Janitor] Destroy errored: " .. tostring(err)) end

    elseif kind == "thread" then
        pcall(task.cancel, value)

    elseif kind == "fn" then
        local ok, err = pcall(value)
        if not ok then warn("[Janitor] cleanup fn errored: " .. tostring(err)) end

    elseif kind == "destroyable" then
        local ok, err = pcall(value.Destroy, value)
        if not ok then warn("[Janitor] :Destroy() errored: " .. tostring(err)) end

    elseif kind == "disconnectable" then
        local ok, err = pcall(value.Disconnect, value)
        if not ok then warn("[Janitor] :Disconnect() errored: " .. tostring(err)) end
    end
end

-- ─────────────────────────────────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────────────────────────────────

function Janitor.new()
    return setmetatable({
        _items     = {},   -- ordered list of { kind, value, key? } or false (tombstone)
        _byKey     = {},   -- key → index in _items
        _destroyed = false,
    }, Janitor)
end

--- Add a tracked resource. Returns the resource so calls can chain:
---     local conn = jan:Add(signal:Connect(...))
--- If `key` is provided, a previous resource at the same key is
--- cleaned up first (useful for "replace, don't accumulate").
function Janitor:Add(value, key)
    if value == nil then return nil end

    local kind = detectKind(value)
    if not kind then
        warn(string.format("[Janitor] unsupported value type: %s", typeof(value)))
        return value
    end

    -- If already destroyed, honour the contract by cleaning the value
    -- immediately so the caller can't accidentally leak.
    if self._destroyed then
        cleanup(kind, value)
        return value
    end

    -- Keyed slot replacement
    if key ~= nil then
        local existingIdx = self._byKey[key]
        if existingIdx then
            local entry = self._items[existingIdx]
            if entry then cleanup(entry.kind, entry.value) end
            self._items[existingIdx] = { kind = kind, value = value, key = key }
            return value
        end
    end

    local idx = #self._items + 1
    self._items[idx] = { kind = kind, value = value, key = key }
    if key ~= nil then self._byKey[key] = idx end
    return value
end

--- Clean up a single keyed slot without tearing down the rest.
function Janitor:Remove(key)
    if self._destroyed then return end
    local idx = self._byKey[key]
    if not idx then return end
    local entry = self._items[idx]
    if entry then cleanup(entry.kind, entry.value) end
    self._items[idx] = false   -- tombstone, preserves indices
    self._byKey[key] = nil
end

--- Tear down all tracked resources in reverse-add order.
--- Idempotent: subsequent calls are no-ops.
function Janitor:Destroy()
    if self._destroyed then return end
    self._destroyed = true

    for i = #self._items, 1, -1 do
        local entry = self._items[i]
        if entry then cleanup(entry.kind, entry.value) end
    end
    self._items = {}
    self._byKey = {}
end

--- Bind this Janitor to an Instance's lifetime. When the Instance's
--- AncestryChanged fires with `parent == nil` (i.e. it's destroyed or
--- removed from the DataModel), Destroy() is invoked automatically.
--- The AncestryChanged connection itself is also tracked for cleanup.
function Janitor:LinkToInstance(instance)
    if self._destroyed then return end

    local conn
    conn = instance.AncestryChanged:Connect(function(_, parent)
        if not parent then
            self:Destroy()
        end
    end)
    table.insert(self._items, { kind = "conn", value = conn })

    -- If the Instance was already destroyed before LinkToInstance ran,
    -- short-circuit. instance.Parent is nil for destroyed instances.
    if not instance.Parent and instance ~= game then
        self:Destroy()
    end
end

function Janitor:IsDestroyed()
    return self._destroyed
end

return Janitor
