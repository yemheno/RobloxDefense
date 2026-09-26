-- ServerScriptService/Modules/CosmeticManager/init.lua
--[[
    CosmeticManager
    ===============
    Server-side orchestrator for the entire cosmetic system.

    Responsibilities:
      • Initialises player wardrobe data on join.
      • Applies visual cosmetics to player R6 characters.
      • Applies visual variants to mobs after spawn.
      • Handles network events for wardrobe browsing / equipping.
      • Re-applies visuals on CharacterAdded (respawn).

    Sub-modules:
      PlayerCosmeticManager  — wardrobe CRUD, equip/unequip, player visuals.
      MobCosmeticManager     — mob variant application.

    Public API (used by other server modules):
      Init()
      ApplyPlayerVisuals(player)
      EquipCosmetic(player, cosmeticId)
      UnequipCosmetic(player, slot)
      UnlockCosmetic(player, cosmeticId)
      HasCosmetic(player, cosmeticId)
      GetWardrobe(player)
      GetEquipped(player)
      ApplyMobVariant(mob, mobId, variantName)
      OnClassSwitched(player, className)   — re-equips class defaults if needed
      (Skin color is handled by CharacterManager via BodyColors)
]]

local CosmeticManager = {}

local Players = game:GetService("Players")
local Modules = script.Parent  -- ServerScriptService/Modules

-- Sub-module references (loaded in Init)
local PlayerCosmeticManager = nil
local MobCosmeticManager    = nil

-- Lazy-loaded dependencies
local NetworkManager    = nil
local PlayerDataManager = nil
local CosmeticConfig    = nil

-- §AGX/T11-JAN: per-player Janitor (Audit_4.7 §5.1) for the CharacterAdded conn.
local Janitor = require(Modules:WaitForChild("Janitor"))
local playerJanitors = setmetatable({}, { __mode = "k" })

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function CosmeticManager.Init()
	NetworkManager    = require(Modules:WaitForChild("NetworkManager"))
	PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
	CosmeticConfig    = require(Modules:WaitForChild("CosmeticConfig"))

	-- Load sub-modules
	PlayerCosmeticManager = require(script:WaitForChild("PlayerCosmeticManager"))
	MobCosmeticManager    = require(script:WaitForChild("MobCosmeticManager"))

	PlayerCosmeticManager.Init({
		NetworkManager    = NetworkManager,
		PlayerDataManager = PlayerDataManager,
		CosmeticConfig    = CosmeticConfig,
	})

	MobCosmeticManager.Init({
		CosmeticConfig = CosmeticConfig,
	})

	-- ── Network events ────────────────────────────────────
	NetworkManager.GetEvent("GetWardrobe")        -- Client → Server
	NetworkManager.GetEvent("WardrobeUpdate")     -- Server → Client
	NetworkManager.GetEvent("EquipCosmetic")      -- Client → Server
	NetworkManager.GetEvent("UnequipCosmetic")    -- Client → Server
	NetworkManager.GetEvent("CosmeticEquipped")   -- Server → Client (confirm)

	-- Client requests wardrobe data
	NetworkManager.OnClientEvent("GetWardrobe", function(player)
		local wardrobe = CosmeticManager.GetWardrobe(player)
		local equipped  = CosmeticManager.GetEquipped(player)
		local className = PlayerDataManager.GetActiveClass(player)
		NetworkManager.FireClient(player, "WardrobeUpdate", {
			owned    = wardrobe,
			equipped = equipped,
			className = className,
		})
	end)

	-- Client equips a cosmetic
	NetworkManager.OnClientEvent("EquipCosmetic", function(player, cosmeticId)
		local ok, err = CosmeticManager.EquipCosmetic(player, cosmeticId)
		if ok then
			NetworkManager.FireClient(player, "CosmeticEquipped", {
				success    = true,
				cosmeticId = cosmeticId,
				equipped   = CosmeticManager.GetEquipped(player),
			})
		else
			NetworkManager.FireClient(player, "CosmeticEquipped", {
				success = false,
				error   = err,
			})
		end
	end)

	-- Client unequips a slot
	NetworkManager.OnClientEvent("UnequipCosmetic", function(player, slot)
		CosmeticManager.UnequipCosmetic(player, slot)
		NetworkManager.FireClient(player, "CosmeticEquipped", {
			success  = true,
			equipped = CosmeticManager.GetEquipped(player),
		})
	end)

	-- ── Player lifecycle ──────────────────────────────────
	-- §AGX/T11-JAN: §T1.1-JAN1. The PlayerAdded handler and the
	-- existing-players loop each wired an untracked CharacterAdded conn (and a
	-- player joining between the two got both). One wirePlayer, guarded by the
	-- per-player Janitor, owns the conn plus the in-flight settle thread;
	-- PlayerRemoving destroys it.
	local function reapplyAfterSpawn(player)
		task.wait(0.5)  -- wait for body parts + data to be ready
		CosmeticManager.SetupPlayer(player)  -- re-run now that data is loaded
		CosmeticManager.ApplyPlayerVisuals(player)
	end

	local function wirePlayer(player, isExisting)
		if playerJanitors[player] then return end
		local jan = Janitor.new("CosmeticManager.player")
		playerJanitors[player] = jan
		jan:Add(player.CharacterAdded:Connect(function()
			-- Keyed: a newer respawn replaces an older still-waiting pass
			-- (both would apply to player.Character anyway).
			jan:Add(task.spawn(reapplyAfterSpawn, player), "respawnApply")
		end))
		if isExisting then
			jan:Add(task.spawn(function()
				CosmeticManager.SetupPlayer(player)
				if player.Character then
					task.wait(0.3)
					CosmeticManager.ApplyPlayerVisuals(player)
				end
			end), "initialApply")
		else
			CosmeticManager.SetupPlayer(player)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		wirePlayer(player, false)
	end)

	-- Handle already-connected players
	for _, player in ipairs(Players:GetPlayers()) do
		wirePlayer(player, true)
	end

	Players.PlayerRemoving:Connect(function(player)
		local jan = playerJanitors[player]
		if jan then
			jan:Destroy()
			playerJanitors[player] = nil
		end
		PlayerCosmeticManager.CleanupPlayer(player)
	end)

end

-- ═══════════════════════════════════════════════════════════
-- PLAYER SETUP  (ensures wardrobe data exists)
-- ═══════════════════════════════════════════════════════════

function CosmeticManager.SetupPlayer(player)
	PlayerCosmeticManager.EnsureWardrobeData(player)
end

-- ═══════════════════════════════════════════════════════════
-- PLAYER WARDROBE API
-- ═══════════════════════════════════════════════════════════

function CosmeticManager.GetWardrobe(player)
	return PlayerCosmeticManager.GetWardrobe(player)
end

function CosmeticManager.GetEquipped(player)
	return PlayerCosmeticManager.GetEquipped(player)
end

function CosmeticManager.EquipCosmetic(player, cosmeticId)
	return PlayerCosmeticManager.EquipCosmetic(player, cosmeticId)
end

function CosmeticManager.UnequipCosmetic(player, slot)
	return PlayerCosmeticManager.UnequipCosmetic(player, slot)
end

function CosmeticManager.UnlockCosmetic(player, cosmeticId)
	return PlayerCosmeticManager.UnlockCosmetic(player, cosmeticId)
end

function CosmeticManager.HasCosmetic(player, cosmeticId)
	return PlayerCosmeticManager.HasCosmetic(player, cosmeticId)
end

-- ═══════════════════════════════════════════════════════════
-- PLAYER VISUALS
-- ═══════════════════════════════════════════════════════════

--- Apply headgear + outfit visuals to the player's current character.
function CosmeticManager.ApplyPlayerVisuals(player)
	PlayerCosmeticManager.ApplyVisuals(player)
end

--- Called by ClassManager when the player switches class.
--- Re-equips class defaults if the current outfit is class-restricted
--- to a different class.
function CosmeticManager.OnClassSwitched(player, newClassName)
	PlayerCosmeticManager.OnClassSwitched(player, newClassName)
	-- Re-apply visuals after the switch
	task.wait(0.1)
	CosmeticManager.ApplyPlayerVisuals(player)
end

-- ═══════════════════════════════════════════════════════════
-- MOB VISUALS
-- ═══════════════════════════════════════════════════════════

--- Apply a visual variant to a mob model after cloning.
function CosmeticManager.ApplyMobVariant(mob, mobId, variantName)
	MobCosmeticManager.ApplyVariant(mob, mobId, variantName)
end

return CosmeticManager
