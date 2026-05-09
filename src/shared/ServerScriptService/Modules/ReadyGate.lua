-- ServerScriptService/Modules/ReadyGate.lua
--[[
    ReadyGate
    =========
    Per-player handshake + outbound message queue.

    The races we keep hitting in playtests follow the same shape: the
    server fires a state event during boot (CombatConfig, AchievementsData,
    PartyState, etc.) BEFORE the client's matching `OnServerEvent` listener
    has registered. Roblox does NOT queue server→client events for missing
    listeners — the packet is dropped. We've patched several of these
    case-by-case with idempotent re-request loops; ReadyGate is the
    universal answer.

    Protocol
    --------
      • Server side: every place's bootstrap calls `ReadyGate.Init()` early.
      • Client side: every place's UI mount script (last to load) fires
        `ClientReady` to the server AFTER all React useEffect hooks have
        had a chance to run their first pass.
      • While the server has not yet seen `ClientReady` for a player, calls
        to `ReadyGate.FireClient(player, eventName, ...)` are queued in a
        per-player FIFO instead of being fired into the void.
      • Once `ClientReady` arrives, the queue is drained in order via the
        real `NetworkManager.FireClient`, then subsequent calls fire
        immediately as a passthrough.

    Bypass list
    -----------
    A handful of high-frequency state-broadcast events do NOT need
    queuing — they're fired on a tick (vitals, currency, resource bars)
    and self-correct on the next tick. Adding them to the queue would
    just balloon memory during boot. Listed in `BYPASS_EVENTS` below.

    Public API (server)
    -------------------
      ReadyGate.Init()
      ReadyGate.FireClient(player, eventName, ...)
      ReadyGate.FireAllClients(eventName, ...)
      ReadyGate.IsReady(player) → bool
      ReadyGate.OnReady(callback)        – callback(player) on each ready

    Migration
    ---------
    The migration is opt-in. Every place's existing `FireClient` calls
    KEEP WORKING (the underlying RemoteEvent is unchanged). To make a
    specific server-push race-proof, route it through ReadyGate instead
    of NetworkManager.FireClient. Useful targets first: CombatConfig,
    AchievementsData, EquipmentInfo, ServerReady, TalentState,
    WardrobeUpdate, and anything fired in response to PlayerAdded.
]]

local ReadyGate = {}

local Players = game:GetService("Players")

local NetworkManager = nil

-- [player] = true once we've received ClientReady from them
local ready = {}

-- Per-player FIFO queue of pending messages, weak-keyed so leavers GC.
-- Each entry: { event = "EventName", args = { ... } }
local queues = setmetatable({}, { __mode = "k" })

-- Server-side callbacks invoked the moment a player becomes ready.
local readyCallbacks = {}

-- Event names that bypass the queue entirely. These are high-frequency
-- broadcast events whose first packet is allowed to drop because the
-- next tick will overwrite it anyway.
local BYPASS_EVENTS = {
    VitalsUpdate    = true,
    CurrencyUpdate  = true,
    ResourceUpdate  = true,
    StatsUpdate     = true,
    PlayerInfoUpdate = true,
}

-- Defensive cap on per-player queue size. If ClientReady never fires
-- (broken client, tabbed-out, etc.) we don't want the queue to grow
-- unbounded. Drop oldest when over cap.
local MAX_QUEUE_SIZE = 200

-- ═══════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════

function ReadyGate.Init()
    NetworkManager = require(script.Parent:WaitForChild("NetworkManager"))

    NetworkManager.GetEvent("ClientReady")

    NetworkManager.OnClientEvent("ClientReady", function(player)
        ReadyGate.MarkReady(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        ready[player]  = nil
        queues[player] = nil
    end)

    print("[ReadyGate] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- READY STATE
-- ═══════════════════════════════════════════════════════════

function ReadyGate.IsReady(player)
    return ready[player] == true
end

function ReadyGate.OnReady(callback)
    table.insert(readyCallbacks, callback)
end

function ReadyGate.MarkReady(player)
    if not player or not player.Parent then return end
    if ready[player] then return end
    ready[player] = true

    -- Drain queue in FIFO order
    local q = queues[player]
    if q and #q > 0 then
        print(string.format("[ReadyGate] Draining %d queued events for %s", #q, player.Name))
        for _, msg in ipairs(q) do
            if player.Parent then
                NetworkManager.FireClient(player, msg.event, table.unpack(msg.args, 1, msg.argc))
            end
        end
    end
    queues[player] = nil

    -- Fire ready callbacks
    for _, cb in ipairs(readyCallbacks) do
        task.spawn(cb, player)
    end
end

-- ═══════════════════════════════════════════════════════════
-- FIRE (queues if not ready, sends immediately if ready/bypass)
-- ═══════════════════════════════════════════════════════════

function ReadyGate.FireClient(player, eventName, ...)
    if not player or not player.Parent then return end

    if ready[player] or BYPASS_EVENTS[eventName] then
        NetworkManager.FireClient(player, eventName, ...)
        return
    end

    -- Queue. Capture argc with select so trailing nils survive table.unpack.
    local q = queues[player]
    if not q then
        q = {}
        queues[player] = q
    end

    if #q >= MAX_QUEUE_SIZE then
        -- Drop oldest to make room. Warn once per drop so a runaway
        -- queue surfaces rather than silently leaking memory.
        warn(string.format("[ReadyGate] Queue overflow for %s (cap %d) — dropping oldest %s",
            player.Name, MAX_QUEUE_SIZE, q[1] and q[1].event or "?"))
        table.remove(q, 1)
    end

    local argc = select("#", ...)
    table.insert(q, {
        event = eventName,
        args  = { ... },
        argc  = argc,
    })
end

function ReadyGate.FireAllClients(eventName, ...)
    for _, player in ipairs(Players:GetPlayers()) do
        ReadyGate.FireClient(player, eventName, ...)
    end
end

return ReadyGate
