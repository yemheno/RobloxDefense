-- socialplaza/StarterPlayerScripts/SocialPlazaClient.client.lua
--[[
    Social Plaza client bootstrap.

    Loads only the client systems needed for appearance and social interaction.
    Combat modules (SkillInput, PlayerAttack, DamageNumbers, SkillVisuals)
    are intentionally NOT loaded — this place has no combat.
]]

local Players       = game:GetService("Players")
local LocalPlayer   = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local SharedModules = PlayerScripts:WaitForChild("Modules")

-- ───────────────────────────────────────────────────────────
-- MODULE LOADER
-- ───────────────────────────────────────────────────────────
local loadedModules = {}

local function Load(parent, name)
	local mod = parent:FindFirstChild(name)
	if not mod then
		warn("[SocialPlazaClient] Module not found:", name)
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[SocialPlazaClient] Failed to load", name, ":", result)
		return nil
	end
	loadedModules[name] = result
	if type(result.Init) == "function" then
		result.Init()
	end
	return result
end

-- ───────────────────────────────────────────────────────────
-- SHARED CLIENT MODULES
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "NetworkManager")
Load(SharedModules, "ResourceCache")    -- early listener — prevents ResourceUpdate queue exhaustion
Load(SharedModules, "AnimationSystem")  -- centralized animation controller (emotes, idles, custom)
Load(SharedModules, "CosmeticClient")   -- cosmetic cache + wardrobe request/sync
Load(SharedModules, "InputSystem")      -- centralized input dispatcher (BEFORE UI mounts)
Load(SharedModules, "SoundManager")
Load(SharedModules, "MovementSystem")   -- standard Roblox movement behaviour
Load(SharedModules, "CameraSystem")     -- camera controller (avatar-preview mode planned)

-- ───────────────────────────────────────────────────────────
-- SERVER READY HANDSHAKE
-- ───────────────────────────────────────────────────────────
local NetworkManager = loadedModules["NetworkManager"]
if NetworkManager then
	NetworkManager.OnServerEvent("ServerReady", function()
		-- All appearance systems listen for their own events.
		-- Nothing extra needed at the plaza client level for now.
	end)
end
