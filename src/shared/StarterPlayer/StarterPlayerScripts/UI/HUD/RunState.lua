-- UI/HUD/RunState.lua
--[[
    §AGX/UI-P5: run state as a MODULE-LEVEL store (shell-spec §4.1), moved
    out of HUD.lua (:253-273, 449-485, 488-497, 526-572, 596). The server
    events are subscribed ONCE, at first require, like Notify; a HUD that
    remounts (or is hidden) keeps gameState / runEnded / betweenWaves, which
    makes UX-02 structural instead of "never unmount the HUD".

    State (RunState.use() / RunState.get()):
        gameState     "Idle" | "Preparing" | "Defending" | "Defeat" | "Victory" | ...
        countdown     number? (seconds left in Preparing)
        runEnded      boolean (§AGX/X14: Return stays reachable in post-run Idle)
        betweenWaves  boolean
        defenseHP     { cur, max, pct }?   (Lane defense line; nil = no line)
        defCombo      { level, multiplier, hitCount }?
        combo         number? (personal hit combo; nil = hidden)
        startGate     { open, ready, expected, autoStart }? (§PB-D3; nil = ungated place)
        serverState   the server's real state; gameState reads "WaitingForParty"
                      while the server is Idle behind a closed start gate
                      (hides Start until the gate opens — §AGX/WC)

    Also owns the Notify output that used to live in the HUD effect:
    wave / run-state banners, the killfeed line and the combo summary
    toast (§AGX/UI-P4), and drains MobDeath (queue exhaustion).

    RunState.start(place)  fires RequestGameState once per client session,
                           outside the Lobby / Plaza (the HUD calls it).
]]

local Players = game:GetService("Players")

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local NetworkManager = require(PlayerScripts:WaitForChild("Modules"):WaitForChild("NetworkManager"))
local Notify         = require(PlayerScripts:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("Notify"))
local Store          = require(script.Parent:WaitForChild("Store"))

local RunState = {}

local store = Store.new({
	gameState    = "Idle",
	countdown    = nil,
	runEnded     = false,
	betweenWaves = false,
	defenseHP    = nil,
	defCombo     = nil,
	combo        = nil,
	startGate    = nil,     -- §AGX/WC: §PB-D3
	serverState  = "Idle",  -- §AGX/WC: §PB-D3
})

-- §AGX/WC: §PB-D3 — while the server sits in Idle behind a CLOSED start
-- gate, publish the pseudo-state "WaitingForParty" instead of "Idle": the
-- HUD only shows Start for "Idle", so the button appears once the gate
-- opens (Lane / CentralBoss) and never in auto-start places (Horde). A
-- sticky banner shows "Waiting for party (x/y)…" meanwhile.
local WAITING = "WaitingForParty"
local function refreshGate()
	local st = store.get()
	local g = st.startGate
	local waiting = g ~= nil and g.open ~= true and st.serverState == "Idle"
	local shown = waiting and WAITING or st.serverState
	if st.gameState ~= shown then
		store.set("gameState", shown)
	end
	if waiting then
		Notify.banner(string.format("Waiting for party (%d/%d)…", tonumber(g.ready) or 0, tonumber(g.expected) or 0), {
			key = "partyGate", priority = "runState", sticky = true,
			color = Color3.fromRGB(255, 200, 90),
		})
	else
		Notify.clearBanner("partyGate")
	end
end

-- ── Server events (once, at first require) ───────────────────────────────────

NetworkManager.OnServerEvent("GameStateChanged", function(data)
	data = data or {}
	-- §AGX/WC: §PB-D3 — raw state goes to serverState; refreshGate() below
	-- derives the published gameState (masked while the gate is closed).
	store.set("serverState", data.newState or "Lobby")
	if type(data.startGate) == "table" then
		store.set("startGate", data.startGate)
	end
	-- §AGX/X14: remember that a run ended so Return stays reachable in the
	-- post-run Idle state if the return teleport fails.
	if data.newState == "Defeat" or data.newState == "Victory" then
		store.set("runEnded", true)
	elseif data.newState == "Preparing" or data.newState == "Defending" then
		store.set("runEnded", false)
	end
	if data.newState ~= "Preparing" then
		store.set("countdown", nil)
	end
	-- §AGX/UI-P4: the sticky run-state banner ends when the place is back
	-- in Idle, or a new run starts (it outranks the wave banners).
	if data.newState == "Idle" or data.newState == "Preparing" then
		Notify.clearBanner("runState")
	end
	-- §AGX/UX-02: RequestGameState snapshots carry the flags that
	-- transitions alone can't rebuild (both optional).
	if data.runEnded ~= nil then
		store.set("runEnded", data.runEnded == true)
	end
	if data.betweenWaves ~= nil then
		store.set("betweenWaves", data.betweenWaves == true)
	end
	refreshGate()  -- §AGX/WC: §PB-D3
end)

-- §AGX/WC: §PB-D3 start-gate progress / open.
NetworkManager.OnServerEvent("StartGateUpdate", function(data)
	if type(data) ~= "table" then return end
	store.set("startGate", data)
	refreshGate()
end)

NetworkManager.OnServerEvent("CountdownUpdate", function(data)
	local remaining = data and data.remaining or 0
	store.set("countdown", (remaining > 0) and remaining or nil)
end)

-- Combo counter: auto-hide 3 s after the last hit (mirrors the server decay).
local comboTimeout = nil
NetworkManager.OnServerEvent("ComboUpdate", function(data)
	store.set("combo", (data and data.current) or 0)
	if comboTimeout then task.cancel(comboTimeout) end
	comboTimeout = task.delay(3, function()
		comboTimeout = nil
		store.set("combo", nil)
	end)
end)

-- §AGX/UI-P4: wave banners ("wave" priority, same key replaces).
NetworkManager.OnServerEvent("WaveStarted", function(data)
	data = data or {}
	store.set("betweenWaves", false)
	Notify.banner(
		"WAVE " .. tostring(data.wave or "?") .. "  (" .. tostring(data.mobCount or 0) .. " mobs)",
		{ key = "wave", priority = "wave", color = Color3.fromRGB(80, 210, 255), duration = 3 })
end)

NetworkManager.OnServerEvent("WaveCompleted", function(data)
	data = data or {}
	store.set("betweenWaves", true)
	Notify.banner("WAVE " .. tostring(data.wave or "?") .. " CLEARED!",
		{ key = "wave", priority = "wave", color = Color3.fromRGB(80, 255, 120), duration = 3 })
end)

-- Sticky "runState" banner; cleared by GameStateChanged -> Idle/Preparing.
NetworkManager.OnServerEvent("AllWavesCompleted", function(data)
	data = data or {}
	Notify.banner("ALL WAVES CLEARED!  (Wave " .. tostring(data.finalWave or "?") .. ")", {
		key = "runState", priority = "runState", sticky = true,
		color = Color3.fromRGB(255, 215, 0),
	})
end)

local function setDefense(data, zero)
	data = data or {}
	store.set("defenseHP", {
		cur = zero and 0 or (data.currentHealth or 0),
		max = data.maxHealth or 1,
		pct = zero and 0 or (data.percent or 0),
	})
end

NetworkManager.OnServerEvent("DefenseLineUpdate", function(data) setDefense(data, false) end)
NetworkManager.OnServerEvent("DefenseLineDamaged", function(data) setDefense(data, false) end)
NetworkManager.OnServerEvent("DefenseLineDestroyed", function(data)
	setDefense(data, true)
	Notify.banner("DEFENSE LINE DESTROYED!", {
		key = "runState", priority = "runState", sticky = true,
		color = Color3.fromRGB(255, 60, 60),
	})
end)

NetworkManager.OnServerEvent("DefenseLineCombo", function(data)
	data = data or {}
	if data.ended then
		store.set("defCombo", nil)
	else
		store.set("defCombo", {
			level      = data.level or 0,
			multiplier = data.multiplier or 1,
			hitCount   = data.hitCount or 0,
		})
	end
end)

-- §AGX/UI-P4: killfeed line and personal combo summary toast.
NetworkManager.OnServerEvent("PlayerDeath", function(data)
	data = data or {}
	Notify.feed((data.playerName or "???") .. " was slain by " .. (data.killerMob or "a mob"),
		{ color = Color3.fromRGB(255, 100, 100) })
end)

NetworkManager.OnServerEvent("ComboEnded", function(data)
	data = data or {}
	Notify.toast("info",
		tostring(data.finalCombo or 0) .. "x Combo!  "
		.. tostring(math.floor(data.totalDamage or 0)) .. " dmg  "
		.. tostring(data.totalCrits or 0) .. " crits",
		{ key = "comboSummary", duration = 4 })
end)

-- MobDeath: drain the queue; MobVisuals owns the death VFX.
NetworkManager.OnServerEvent("MobDeath", function(_data) end)

-- ── API ──────────────────────────────────────────────────────────────────────

local requested = false

--- Ask the server for a state snapshot (GameStateChanged only fires on
--- transitions, so a late join would otherwise sit in "Idle"). Once per
--- session, combat places only.
function RunState.start(place)
	if requested or place == "Lobby" or place == "Plaza" then return end
	requested = true
	NetworkManager.FireServer("RequestGameState")
end

function RunState.get()
	return store.get()
end

function RunState.use()
	return Store.use(store)
end

RunState.store = store

return RunState
