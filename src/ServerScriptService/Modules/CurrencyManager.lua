-- CurrencyManager

local CurrencyManager = {}

local Modules = script.Parent
local Config = require(Modules:WaitForChild("PlayerDataConfig"))
local DataManager = require(Modules:WaitForChild("PlayerDataManager"))


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
	return data and data.Currency.Merits or 0
end

function CurrencyManager.GetEssence(player)
	local data = DataManager.GetData(player)
	return data and data.Currency.Essence or 0
end

function CurrencyManager.GetExperience(player)
	local data = DataManager.GetData(player)
	return data and data.Currency.Experience or 0
end

function CurrencyManager.GetLevel(player)
	local data = DataManager.GetData(player)
	return data and data.Currency.Level or 1
end


-- ADD CURRENCIES
function CurrencyManager.AddMerits(player, amount)
	local data = DataManager.GetData(player)
	if not data then return end

	data.Currency.Merits = data.Currency.Merits + amount
	UpdateLeaderstat(player, "Merits", data.Currency.Merits)

	print("[CurrencyManager]", player.Name, "+", amount, "Merits")
end

function CurrencyManager.AddEssence(player, amount)
	local data = DataManager.GetData(player)
	if not data then return end

	data.Currency.Essence = data.Currency.Essence + amount

	print("[CurrencyManager]", player.Name, "+", amount, "Essence")
end

function CurrencyManager.AddExperience(player, amount)
	local data = DataManager.GetData(player)
	if not data then return end

	data.Currency.Experience = data.Currency.Experience + amount

	-- Check for level ups
	local xpNeeded = Config.GetXPForLevel(data.Currency.Level)
	while data.Currency.Experience >= xpNeeded do
		data.Currency.Experience = data.Currency.Experience - xpNeeded
		data.Currency.Level = data.Currency.Level + 1
		xpNeeded = Config.GetXPForLevel(data.Currency.Level)
		print("[CurrencyManager]", player.Name, "LEVEL UP!", data.Currency.Level)
	end

	UpdateLeaderstat(player, "Level", data.Currency.Level)
end


-- SPEND CURRENCIES
function CurrencyManager.SpendMerits(player, amount)
	local data = DataManager.GetData(player)
	if not data then return false end

	if data.Currency.Merits >= amount then
		data.Currency.Merits = data.Currency.Merits - amount
		UpdateLeaderstat(player, "Merits", data.Currency.Merits)
		print("[CurrencyManager]", player.Name, "-", amount, "Merits")
		return true
	end

	return false
end

function CurrencyManager.SpendEssence(player, amount)
	local data = DataManager.GetData(player)
	if not data then return false end

	if data.Currency.Essence >= amount then
		data.Currency.Essence = data.Currency.Essence - amount
		print("[CurrencyManager]", player.Name, "-", amount, "Essence")
		return true
	end

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