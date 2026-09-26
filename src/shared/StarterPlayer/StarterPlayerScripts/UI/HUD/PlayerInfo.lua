-- UI/HUD/PlayerInfo.lua
--[[
    §AGX/UI-P5: player vitals + wallet as a MODULE-LEVEL store (shell-spec
    §4.1). Subscribed once, at first require.

    State (PlayerInfo.use()):
        hp          { cur, max }           Humanoid (pure client)
        deathState  "Alive" | "KnockedDown" | "Dead"   (§HUD-HP1 cosmetic 0 HP)
        res         { cur, max, name }     ResourceCache (+ PlayerInfoUpdate seed)
        xp          { cur, max, level }    PlayerInfoUpdate
        currency    { essence, merits }    PlayerInfoUpdate + CurrencyUpdate
        power       number                 PlayerGearScore

    PlayerInfo.start()  fires GetPlayerInfo + PlayerGearScore once per session.
]]

local Players = game:GetService("Players")

local LocalPlayer    = Players.LocalPlayer
local Modules        = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local ResourceCache  = require(Modules:WaitForChild("ResourceCache"))
local Store          = require(script.Parent:WaitForChild("Store"))

local PlayerInfo = {}

local store = Store.new({
	hp         = { cur = 100, max = 100 },
	deathState = LocalPlayer:GetAttribute("DeathState") or "Alive",
	-- Seeded from ResourceCache so the bar is never empty on mount.
	res        = ResourceCache.GetLatest(),
	xp         = { cur = 0, max = 100, level = 1 },
	currency   = { essence = 0, merits = 0 },
	power      = 0,
})

-- ── Subscriptions (once, at first require) ───────────────────────────────────

ResourceCache.Subscribe(function(data)
	store.set("res", {
		cur  = data.cur or 0,
		max  = data.max or 100,
		name = data.name or "Resource",
	})
end)

NetworkManager.OnServerEvent("PlayerInfoUpdate", function(data)
	data = data or {}
	if data.xp ~= nil then
		store.set("xp", {
			cur   = data.xp or 0,
			max   = data.xpNeeded or 100,
			level = data.level or 1,
		})
	end
	if data.essence ~= nil or data.merits ~= nil then
		store.set("currency", { essence = data.essence or 0, merits = data.merits or 0 })
	end
	-- Seed the resource before the first ResourceUpdate tick arrives.
	if data.resource ~= nil then
		store.set("res", {
			cur  = data.resource or 0,
			max  = data.maxResource or 100,
			name = data.resourceName or "Resource",
		})
	end
end)

NetworkManager.OnServerEvent("CurrencyUpdate", function(data)
	data = data or {}
	store.set("currency", { essence = data.essence or 0, merits = data.merits or 0 })
end)

NetworkManager.OnServerEvent("PlayerGearScore", function(data)
	if data and data.score then
		store.set("power", data.score)
	end
end)

-- Health straight from the Humanoid; reconnect on respawn.
local hpConn, maxHpConn = nil, nil

local function connectHumanoid(character)
	if hpConn then hpConn:Disconnect(); hpConn = nil end
	if maxHpConn then maxHpConn:Disconnect(); maxHpConn = nil end
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid or character ~= LocalPlayer.Character then return end
	store.set("hp", { cur = humanoid.Health, max = humanoid.MaxHealth })
	hpConn = humanoid.HealthChanged:Connect(function(newHp)
		store.set("hp", { cur = newHp, max = humanoid.MaxHealth })
	end)
	-- MaxHealth changes too (VIT stats applied).
	maxHpConn = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		store.set("hp", { cur = humanoid.Health, max = humanoid.MaxHealth })
	end)
end

LocalPlayer.CharacterAdded:Connect(connectHumanoid)
if LocalPlayer.Character then
	task.spawn(connectHumanoid, LocalPlayer.Character)
end

-- §HUD-HP1: the engine pins Health=1 while knocked down (§LD-DS5); the UI
-- shows 0 HP when not Alive.
LocalPlayer:GetAttributeChangedSignal("DeathState"):Connect(function()
	store.set("deathState", LocalPlayer:GetAttribute("DeathState") or "Alive")
end)

-- ── API ──────────────────────────────────────────────────────────────────────

local started = false

function PlayerInfo.start()
	if started then return end
	started = true
	NetworkManager.FireServer("GetPlayerInfo")
	NetworkManager.FireServer("PlayerGearScore")
end

function PlayerInfo.get()
	return store.get()
end

function PlayerInfo.use()
	return Store.use(store)
end

PlayerInfo.store = store

return PlayerInfo
