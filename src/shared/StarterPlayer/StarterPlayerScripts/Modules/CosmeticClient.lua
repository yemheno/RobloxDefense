-- StarterPlayerScripts/Modules/CosmeticClient.lua
--[[
    CosmeticClient
    ==============
    Client-side cosmetic module. Caches the local player's wardrobe,
    sends equip / unequip requests to the server, and fires UI update
    signals when the server confirms changes.

    Usage:
        CosmeticClient.Init()
        CosmeticClient.RequestWardrobe()              -- fetch latest from server
        CosmeticClient.EquipCosmetic("dark_knight")   -- send equip request
        CosmeticClient.UnequipSlot("headgear")        -- send unequip request

        CosmeticClient.OnWardrobeUpdated(function(wardrobe) ... end)
        CosmeticClient.OnEquipResult(function(result) ... end)
]]

local CosmeticClient = {}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local Modules = PlayerScripts:WaitForChild("Modules")

local NetworkManager = nil

-- Cached wardrobe state
local cached = {
	owned     = {},    -- { [cosmeticId] = true }
	equipped  = {},    -- { headgear = "...", outfit = "..." }
	className = nil,   -- current class (affects what's wearable)
}

-- Subscriber callbacks
local wardrobeCallbacks = {}
local equipCallbacks    = {}

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function CosmeticClient.Init()
	NetworkManager = require(Modules:WaitForChild("NetworkManager"))

	-- Server pushes wardrobe state
	NetworkManager.OnServerEvent("WardrobeUpdate", function(data)
		cached.owned     = data.owned     or {}
		cached.equipped  = data.equipped  or {}
		cached.className = data.className or cached.className
		CosmeticClient.FireWardrobeUpdated()
	end)

	-- Server confirms equip / unequip
	NetworkManager.OnServerEvent("CosmeticEquipped", function(data)
		if data.success and data.equipped then
			cached.equipped = data.equipped
			CosmeticClient.FireWardrobeUpdated()
		end
		CosmeticClient.FireEquipResult(data)
	end)

	print("[CosmeticClient] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- REQUESTS
-- ═══════════════════════════════════════════════════════════

--- Fetch the current wardrobe from the server.
function CosmeticClient.RequestWardrobe()
	if NetworkManager then
		NetworkManager.FireServer("GetWardrobe")
	end
end

--- Request to equip a cosmetic.
function CosmeticClient.EquipCosmetic(cosmeticId)
	if NetworkManager then
		NetworkManager.FireServer("EquipCosmetic", cosmeticId)
	end
end

--- Request to unequip a slot.
function CosmeticClient.UnequipSlot(slot)
	if NetworkManager then
		NetworkManager.FireServer("UnequipCosmetic", slot)
	end
end

-- ═══════════════════════════════════════════════════════════
-- CACHED DATA ACCESSORS
-- ═══════════════════════════════════════════════════════════

function CosmeticClient.GetOwned()
	return cached.owned
end

function CosmeticClient.GetEquipped()
	return cached.equipped
end

function CosmeticClient.GetClassName()
	return cached.className
end

function CosmeticClient.OwnsCosmetic(cosmeticId)
	return cached.owned[cosmeticId] == true
end

-- ═══════════════════════════════════════════════════════════
-- SUBSCRIBER PATTERN
-- ═══════════════════════════════════════════════════════════

--- Register a callback that fires whenever the wardrobe data changes.
--- Returns an unsubscribe function.
function CosmeticClient.OnWardrobeUpdated(callback)
	table.insert(wardrobeCallbacks, callback)
	return function()
		for i, cb in ipairs(wardrobeCallbacks) do
			if cb == callback then
				table.remove(wardrobeCallbacks, i)
				break
			end
		end
	end
end

--- Register a callback that fires with equip results.
--- Returns an unsubscribe function.
function CosmeticClient.OnEquipResult(callback)
	table.insert(equipCallbacks, callback)
	return function()
		for i, cb in ipairs(equipCallbacks) do
			if cb == callback then
				table.remove(equipCallbacks, i)
				break
			end
		end
	end
end

function CosmeticClient.FireWardrobeUpdated()
	for _, cb in ipairs(wardrobeCallbacks) do
		task.spawn(cb, {
			owned     = cached.owned,
			equipped  = cached.equipped,
			className = cached.className,
		})
	end
end

function CosmeticClient.FireEquipResult(data)
	for _, cb in ipairs(equipCallbacks) do
		task.spawn(cb, data)
	end
end

return CosmeticClient
