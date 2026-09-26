-- CurrencyManager

local CurrencyManager = {}

local Modules = script.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))
local DataManager = require(Modules:WaitForChild("PlayerDataManager"))

-- Lazy require to avoid circular dependency (NetworkManager requires nothing from us)
local NetworkManager = nil

-- Merit-added callbacks — subscribe via CurrencyManager.OnMeritsAdded(fn)
local meritCallbacks = {}

function CurrencyManager.OnMeritsAdded(callback)
	table.insert(meritCallbacks, callback)
end

-- Essence-added callbacks — subscribe via CurrencyManager.OnEssenceAdded(fn)
local essenceCallbacks = {}

function CurrencyManager.OnEssenceAdded(callback)
	table.insert(essenceCallbacks, callback)
end
local function getNet()
	if not NetworkManager then
		NetworkManager = require(Modules:WaitForChild("NetworkManager"))
	end
	return NetworkManager
end

local function fireCurrencyUpdate(player, data)
	local net = getNet()
	if net then
		net.FireClient(player, "CurrencyUpdate", {
			essence = data.Account.Essence or 0,
			merits  = data.Account.Merits  or 0,
		})
	end
end


-- UPDATE LEADERSTATS
local function UpdateLeaderstat(player, name, value)
	local leaderstats = DataManager.GetLeaderstats(player)
	if leaderstats then
		local stat = leaderstats:FindFirstChild(name)
		if stat then
			stat.Value = value
		end
	end
end


-- GETTERS
function CurrencyManager.GetMerits(player)
	local data = DataManager.GetData(player)
	return data and data.Account.Merits or 0
end

function CurrencyManager.GetEssence(player)
	local data = DataManager.GetData(player)
	return data and data.Account.Essence or 0
end


-- ADD CURRENCIES
-- §AGX/X32: optional `opts` table. `{ raw = true }` credits the exact
-- amount: no MeritBonus multiplier and no merit-earned callbacks. Use it
-- for money the player already owned (shop refunds), which is not income.
-- Every existing caller passes no opts and keeps the old behaviour.
function CurrencyManager.AddMerits(player, amount, opts)
	local data = DataManager.GetData(player)
	if not data then return end

	-- §2.8b: early return on non-positive amounts. A zero/negative grant
	-- shouldn't fire UI updates, leaderstat writes, or merit callbacks.
	-- Negative amounts are a bug (use SpendMerits instead); loud-warn so it
	-- surfaces during testing.
	if type(amount) ~= "number" or amount ~= amount then  -- NaN check
		warn("[CurrencyManager] AddMerits called with non-numeric/NaN amount: " .. tostring(amount))
		return
	end
	if amount <= 0 then
		if amount < 0 then
			warn("[CurrencyManager] AddMerits called with negative amount (" ..
				tostring(amount) .. ") for " .. player.Name .. "; use SpendMerits instead.")
		end
		return
	end

	-- §AGX/X32: refunds (opts.raw) return the exact amount spent.
	local raw = type(opts) == "table" and opts.raw == true

	-- Apply MeritBonus from talents / equipment (stored as percentage, e.g. 10 = +10%)
	local finalAmount = amount
	if not raw then
		local meritBonus = DataManager.GetBonus(player, "MeritBonus") or 0
		finalAmount = math.floor(amount * (1 + meritBonus / 100) + 0.5)
		if finalAmount < 1 and amount > 0 then finalAmount = 1 end
	end

	data.Account.Merits = data.Account.Merits + finalAmount
	UpdateLeaderstat(player, "Merits", data.Account.Merits)
	fireCurrencyUpdate(player, data)

	-- Notify merit listeners (AchievementManager, etc.)
	-- Pass finalAmount (after bonus), not the raw pre-bonus amount
	-- §AGX/X32: a raw credit (refund) is not "earned", so listeners skip it.
	if not raw then
		for _, cb in ipairs(meritCallbacks) do
			task.spawn(cb, player, finalAmount)
		end
	end

	print("[CurrencyManager]", player.Name, "+", finalAmount, "Merits (raw:", amount, raw and ", refund)" or ")")
end

-- §AGX/D-FIX: S4 — additive `opts` like AddMerits: `{ raw = true }` marks a
-- refund (Essence has no bonus multiplier; raw only skips the "earned"
-- callbacks). Callers without opts are unchanged.
function CurrencyManager.AddEssence(player, amount, opts)
	local data = DataManager.GetData(player)
	if not data then return end

	-- §2.8b: same guard as AddMerits.
	if type(amount) ~= "number" or amount ~= amount then
		warn("[CurrencyManager] AddEssence called with non-numeric/NaN amount: " .. tostring(amount))
		return
	end
	if amount <= 0 then
		if amount < 0 then
			warn("[CurrencyManager] AddEssence called with negative amount (" ..
				tostring(amount) .. ") for " .. player.Name .. "; use SpendEssence instead.")
		end
		return
	end

	data.Account.Essence = data.Account.Essence + amount
	fireCurrencyUpdate(player, data)

	-- Notify subscribers (e.g. AchievementManager.OnEssenceEarned)
	-- §AGX/D-FIX: S4 — a raw credit (refund) is not "earned"; skip listeners.
	local raw = type(opts) == "table" and opts.raw == true
	if not raw then
		for _, cb in ipairs(essenceCallbacks) do
			task.spawn(cb, player, amount)
		end
	end

	print("[CurrencyManager]", player.Name, "+", amount, "Essence", raw and "(refund)" or "")
end


-- SPEND CURRENCIES
function CurrencyManager.SpendMerits(player, amount)
	-- §AGX/X33: mirror the Add-side guard — a negative/NaN amount used to
	-- pass the `>=` check and MINT currency. Latent (no caller does it today).
	if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then
		warn("[CurrencyManager] SpendMerits rejected invalid amount:", tostring(amount))
		return false
	end
	if amount == 0 then return true end  -- free = no-op success (callers rely on it)
	local data = DataManager.GetData(player)
	if not data then return false end

	if data.Account.Merits >= amount then
		data.Account.Merits = data.Account.Merits - amount
		UpdateLeaderstat(player, "Merits", data.Account.Merits)
		fireCurrencyUpdate(player, data)
		print("[CurrencyManager]", player.Name, "-", amount, "Merits")
		return true
	end

	-- §2.8c: warn on failed spend so the caller (shop/respec/etc.) surfaces
	-- a real "insufficient funds" path instead of silently no-op'ing.
	warn(string.format(
		"[CurrencyManager] SpendMerits FAILED for %s: wanted %s, has %s.",
		player.Name, tostring(amount), tostring(data.Account.Merits)
	))
	return false
end

function CurrencyManager.SpendEssence(player, amount)
	-- §AGX/X33: mirror the Add-side guard — a negative/NaN amount used to
	-- pass the `>=` check and MINT currency. Latent (no caller does it today).
	if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then
		warn("[CurrencyManager] SpendEssence rejected invalid amount:", tostring(amount))
		return false
	end
	if amount == 0 then return true end  -- free = no-op success (callers rely on it)
	local data = DataManager.GetData(player)
	if not data then return false end

	if data.Account.Essence >= amount then
		data.Account.Essence = data.Account.Essence - amount
		fireCurrencyUpdate(player, data)
		print("[CurrencyManager]", player.Name, "-", amount, "Essence")
		return true
	end

	-- §2.8c: warn on failed spend.
	warn(string.format(
		"[CurrencyManager] SpendEssence FAILED for %s: wanted %s, has %s.",
		player.Name, tostring(amount), tostring(data.Account.Essence)
	))
	return false
end


-- CHECKS
function CurrencyManager.CanAffordMerits(player, amount)
	return CurrencyManager.GetMerits(player) >= amount
end

function CurrencyManager.CanAffordEssence(player, amount)
	return CurrencyManager.GetEssence(player) >= amount
end

return CurrencyManager