-- ServerScriptService/Modules/ConsumableEffects.lua
--[[
    §AGX/X10b: server-side use path for inventory consumables
    (AGENCY_CHECKS X10). Before this, 9 of the 10 ConsumableConfig items
    could be bought but never used; X10 turned them off. This module applies
    the effect each ConsumableConfig entry already describes, so they are
    usable and buyable again.

    Flow
    ────
      Client (InventoryUI "Use") ── FireServer("UseConsumable", { itemId })
        → ConsumableEffects.Use(player, itemId)
            1. item is a ConsumableConfig.IsDirectUse item
            2. player is alive (not knocked down / dead), run not paused
            3. per-item cooldown (ConsumableConfig.cooldown, per player)
            4. owns ≥ 1 (InventoryManager.HasItem)
            5. effect precheck (full HP / full resource / no armor → the
               item is NOT spent)
            6. InventoryManager.ConsumeItem (same path respec_scroll uses)
            7. apply the effect; on an error the item is given back
        → NotifyService.Inline(player, "UseConsumable", ok, text)
          (the client's useRequest("UseConsumable") settles on it)

    Effects (ConsumableConfig effect.type)
    ──────────────────────────────────────
      HealHP       flat HP, instant.
      HealPercent  % of Humanoid.MaxHealth; with `duration` it is split
                   evenly over HOT_TICK ticks, and stops if the player is
                   knocked down / dies / leaves.
      RestoreRes   flat class resource via ResourceManager.ModifyResource.
      BuffStat     BonusManager.AddTimedBonus(player,
                   "consumable_<itemId>", stat, value, duration).
                   Stacking: re-use REFRESHES the duration (one buff per
                   item) unless the config sets `stacks = true`.
                   ArmorPercent: if PlayerDataConfig.BonusStats has an
                   `ArmorPercent` key (GetTotalStat already reads
                   data.Bonus[stat .. "Percent"]) it is used directly;
                   otherwise it is applied as a flat Armor bonus equal to
                   value% of the player's Armor at use time (the potion's
                   own previous contribution excluded, so a refresh does not
                   compound).

    Lifetime
    ────────
      Buffs are per-server: BonusManager drops every source on
      PlayerRemoving, so a buff ends on leave / teleport. A config with
      `persistAcrossTeleport = true` is not supported yet (warned at Init).
      Per-player state (cooldowns, HoT threads, expiry notices) lives in a
      Janitor destroyed on PlayerRemoving (Audit_4.7 §5.1).

    Network
    ───────
      "UseConsumable" (client → server) must be in the NetworkManager
      manifest (rateLimit 4). Reply: NotifyService.Inline + a Feed line
      when a buff wears off. InventoryManager.Init calls
      ConsumableEffects.Init, so no place Main needs a change.

    Public API
    ──────────
      ConsumableEffects.Init()
      ConsumableEffects.Use(player, itemId) → ok: boolean, message: string
      ConsumableEffects.GetCooldownRemaining(player, itemId) → seconds
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConsumableEffects = {}
local Modules = script.Parent

local REQUEST_EVENT = "UseConsumable"
local TAG_PREFIX    = "consumable_"   -- BonusManager source = "timed_consumable_<id>"
local HOT_TICK      = 0.25            -- s between heal-over-time ticks

-- ═══════════════════════════════════════════════════════════
-- LAZY MODULES  (Audit_4.7 §5 lazy getters)
-- ═══════════════════════════════════════════════════════════

local _net, _inv, _bonus, _data, _dataCfg, _cons, _janitor, _notify = nil, nil, nil, nil, nil, nil, nil, nil
local _rmResolved, _rm = false, nil

local function getNet()
	if not _net then _net = require(Modules:WaitForChild("NetworkManager")) end
	return _net
end

local function getInventory()
	if not _inv then _inv = require(Modules:WaitForChild("InventoryManager")) end
	return _inv
end

local function getBonus()
	if not _bonus then _bonus = require(Modules:WaitForChild("BonusManager")) end
	return _bonus
end

local function getData()
	if not _data then _data = require(Modules:WaitForChild("PlayerDataManager")) end
	return _data
end

local function getDataConfig()
	if not _dataCfg then _dataCfg = require(Modules:WaitForChild("PlayerDataConfig")) end
	return _dataCfg
end

local function getConsumableConfig()
	if not _cons then
		_cons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ConsumableConfig"))
	end
	return _cons
end

local function getJanitor()
	if not _janitor then _janitor = require(Modules:WaitForChild("Janitor")) end
	return _janitor
end

local function getNotify()
	if not _notify then _notify = require(Modules:WaitForChild("NotifyService")) end
	return _notify
end

-- ResourceManager is loaded in every place today; resolve once and cache
-- the miss too, so a place without it rejects RestoreRes cleanly.
local function getResourceManager()
	if not _rmResolved then
		_rmResolved = true
		local mod = Modules:FindFirstChild("ResourceManager")
		if mod then
			local ok, rm = pcall(require, mod)
			if ok then _rm = rm end
		end
	end
	return _rm
end

-- ═══════════════════════════════════════════════════════════
-- PER-PLAYER STATE
-- ═══════════════════════════════════════════════════════════

-- state[player] = { jan = Janitor, readyAt = { [itemId] = os.clock() }, stackSeq = n }
local state = {}

local function getState(player)
	local st = state[player]
	if not st then
		st = {
			jan      = getJanitor().new("ConsumableEffects.player"),
			readyAt  = {},
			stackSeq = 0,
		}
		state[player] = st
	end
	return st
end

local function cleanupPlayer(player)
	local st = state[player]
	if st then
		state[player] = nil
		st.jan:Destroy()   -- cancels HoT ticks + buff-expiry notices
	end
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

local function getHumanoid(player)
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

-- Alive = has a living Humanoid and DeathSystem doesn't have them downed.
-- DeathState is nil in places without DeathSystem (lobby) → alive.
local function isAlive(player)
	local hum = getHumanoid(player)
	if not hum or hum.Health <= 0 then return false end
	local ds = player:GetAttribute("DeathState")
	return ds == nil or ds == "Alive"
end

-- §AGX/X7 parity: nothing combat-relevant happens while the run is paused.
local function isPaused(player)
	return workspace:GetAttribute("HordePaused") == true
		or player:GetAttribute("HordePaused") == true
end

local function fmtSeconds(s)
	return tostring(math.max(1, math.ceil(s))) .. "s"
end

local function hasBonusStat(stat)
	local cfg = getDataConfig()
	return cfg.BonusStats ~= nil and cfg.BonusStats[stat] ~= nil
end

--- Resolve a BuffStat to the (stat, value) actually written, or nil + reason.
local function resolveBuff(player, def)
	local eff  = def.effect
	local stat = eff.stat
	local tag  = TAG_PREFIX .. def.id

	if hasBonusStat(stat) then
		return stat, eff.value
	end

	if stat == "ArmorPercent" then
		-- Fallback while PlayerDataConfig.BonusStats has no ArmorPercent:
		-- value% of current Armor, excluding this potion's own previous
		-- contribution so a refresh re-derives instead of compounding.
		local own   = getBonus().GetTimedBonus(player, tag, "Armor")
		local armor = (getData().GetTotalStat(player, "Armor") or 0) - own
		local flat  = math.floor(math.max(0, armor) * (eff.value / 100) + 0.5)
		if flat < 1 then
			return nil, "You have no armor for this to reinforce."
		end
		return "Armor", flat
	end

	return nil, "This item can't be used yet."
end

-- ═══════════════════════════════════════════════════════════
-- EFFECT HANDLERS
--   check(player, def) → ok, reason    (runs BEFORE the item is spent)
--   apply(player, def) → message        (runs AFTER; may error → refund)
-- ═══════════════════════════════════════════════════════════

local function healCheck(player)
	local hum = getHumanoid(player)
	if not hum then return false, "You can't use that right now." end
	if hum.Health >= hum.MaxHealth then return false, "You're already at full health." end
	return true
end

local function applyHeal(player, def, amount, duration)
	local hum = getHumanoid(player)
	if not hum then error("no humanoid") end

	if not duration or duration <= 0 then
		hum.Health = math.min(hum.Health + amount, hum.MaxHealth)
		return def.name .. " used."
	end

	-- Heal over time: evenly split, keyed per item so a second, different
	-- potion runs alongside instead of cancelling this one.
	local ticks   = math.max(1, math.floor(duration / HOT_TICK + 0.5))
	local perTick = amount / ticks
	local st      = getState(player)
	st.jan:Add(task.spawn(function()
		for _ = 1, ticks do
			task.wait(HOT_TICK)
			if not player.Parent or not isAlive(player) then return end
			local h = getHumanoid(player)
			if h ~= hum then return end   -- character replaced mid-heal
			h.Health = math.min(h.Health + perTick, h.MaxHealth)
		end
	end), "hot_" .. def.id)
	return def.name .. " used."
end

local HANDLERS = {}

HANDLERS.HealHP = {
	check = healCheck,
	apply = function(player, def)
		return applyHeal(player, def, def.effect.amount or 0, def.effect.duration)
	end,
}

HANDLERS.HealPercent = {
	check = healCheck,
	apply = function(player, def)
		local hum = getHumanoid(player)
		if not hum then error("no humanoid") end
		local amount = hum.MaxHealth * (def.effect.percent or 0)
		return applyHeal(player, def, amount, def.effect.duration)
	end,
}

HANDLERS.RestoreRes = {
	check = function(player)
		local rm = getResourceManager()
		if not rm then return false, "You can't use that here." end
		if rm.GetResource(player) >= rm.GetMaxResource(player) then
			return false, "Your " .. tostring(rm.GetResourceName(player)) .. " is already full."
		end
		return true
	end,
	apply = function(player, def)
		local rm = getResourceManager()
		if not rm or not rm.ModifyResource(player, def.effect.amount or 0) then
			error("ResourceManager has no state for player")
		end
		return def.name .. " used."
	end,
}

HANDLERS.BuffStat = {
	check = function(player, def)
		local stat, reason = resolveBuff(player, def)
		if not stat then return false, reason end
		return true
	end,
	apply = function(player, def)
		local eff = def.effect
		local stat, value = resolveBuff(player, def)
		if not stat then error("buff stat no longer resolvable") end

		local st  = getState(player)
		local tag = TAG_PREFIX .. def.id
		if def.stacks == true then
			-- Opt-in stacking: each use is its own BonusManager source.
			st.stackSeq += 1
			tag = tag .. "_" .. st.stackSeq
		end

		local bm = getBonus()
		bm.AddTimedBonus(player, tag, stat, value, eff.duration)
		if bm.GetTimedBonus(player, tag, stat) == 0 then
			error("BonusManager rejected stat " .. tostring(stat))
		end

		-- Expiry notice, keyed by tag: a refresh replaces (cancels) the old
		-- notice so "wore off" matches the refreshed duration.
		st.jan:Add(task.delay(eff.duration, function()
			if player.Parent then
				getNotify().Feed(player, def.name .. " wore off.", { key = "consumable_" .. def.id })
			end
		end), "buff_" .. tag)

		return string.format("%s active for %ds.", def.name, eff.duration)
	end,
}

-- ═══════════════════════════════════════════════════════════
-- USE
-- ═══════════════════════════════════════════════════════════

function ConsumableEffects.GetCooldownRemaining(player, itemId)
	local st = state[player]
	local readyAt = st and st.readyAt[itemId]
	if not readyAt then return 0 end
	return math.max(0, readyAt - os.clock())
end

function ConsumableEffects.Use(player, itemId)
	if type(itemId) ~= "string" then return false, "Invalid item." end

	local cc  = getConsumableConfig()
	local def = cc.GetById(itemId)
	if not def or not cc.IsDirectUse(itemId) then
		return false, "That item can't be used from the inventory."
	end
	local handler = HANDLERS[def.effect.type]
	if not handler then return false, "That item can't be used yet." end

	if not isAlive(player) then return false, "You can't use items while down." end
	if isPaused(player) then return false, "The game is paused." end

	local remaining = ConsumableEffects.GetCooldownRemaining(player, itemId)
	if remaining > 0 then
		return false, string.format("%s is on cooldown (%s).", def.name, fmtSeconds(remaining))
	end

	local inv = getInventory()
	if not inv.HasItem(player, itemId, 1) then
		return false, "You don't have any " .. def.name .. "."
	end

	local okCheck, reason = handler.check(player, def)
	if not okCheck then return false, reason or "You can't use that right now." end

	-- Spend first (ConsumeItem is the atomic decrement), then apply.
	if not inv.ConsumeItem(player, itemId, 1) then
		return false, "You don't have any " .. def.name .. "."
	end

	local okApply, result = pcall(handler.apply, player, def)
	if not okApply then
		warn("[ConsumableEffects] " .. itemId .. " apply failed for " .. player.Name ..
			": " .. tostring(result) .. " — item returned")
		inv.AddItem(player, itemId, 1)
		return false, "Something went wrong. The item was returned."
	end

	if (def.cooldown or 0) > 0 then
		getState(player).readyAt[itemId] = os.clock() + def.cooldown
	end
	return true, result
end

-- ═══════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════

local _initDone = false

function ConsumableEffects.Init()
	if _initDone then return end
	_initDone = true

	-- Config sanity: flag anything this module can't honour yet.
	local cc = getConsumableConfig()
	for _, def in ipairs(cc.GetAll()) do
		if def.persistAcrossTeleport == true then
			warn("[ConsumableEffects] " .. def.id .. " sets persistAcrossTeleport, which is not " ..
				"supported yet — the buff will still end on leave.")
		end
		if cc.IsDirectUse(def.id) and not HANDLERS[def.effect.type] then
			warn("[ConsumableEffects] " .. def.id .. " is usable but effect '" ..
				tostring(def.effect.type) .. "' has no handler.")
		end
	end

	Players.PlayerRemoving:Connect(cleanupPlayer)

	local net = getNet()
	net.GetEvent(REQUEST_EVENT)
	net.OnClientEvent(REQUEST_EVENT, function(player, payload)
		-- Accept { itemId = "…" } (useRequest payload) or a bare id string.
		local itemId = payload
		if type(payload) == "table" then itemId = payload.itemId end
		local ok, msg = ConsumableEffects.Use(player, itemId)
		getNotify().Inline(player, REQUEST_EVENT, ok, msg)
	end)
end

return ConsumableEffects
