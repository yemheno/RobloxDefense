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

-- §PERF/BP: client boot timeline (see BootProfiler for the dump contract)
local BootProfiler = require(game:GetService("ReplicatedStorage")
	:WaitForChild("Shared"):WaitForChild("BootProfiler"))
BootProfiler.SetContext("SocialPlazaClient")

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
	local doneRequire = BootProfiler.Begin("require " .. name)
	local ok, result = pcall(require, mod)
	doneRequire()
	if not ok then
		warn("[SocialPlazaClient] Failed to load", name, ":", result)
		return nil
	end
	loadedModules[name] = result
	if type(result.Init) == "function" then
		local doneInit = BootProfiler.Begin(name .. ".Init")
		result.Init()
		doneInit()
	end
	return result
end

-- ───────────────────────────────────────────────────────────
-- SHARED CLIENT MODULES
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "LoadingScreen")    -- §T10/U1: overlay up FIRST, dismissed on ServerReady
Load(SharedModules, "NetworkManager")
Load(SharedModules, "ResourceCache")    -- early listener — prevents ResourceUpdate queue exhaustion
Load(SharedModules, "VipTag")           -- §AGX/UI-FREE: X40-VIP [VIP] chat tag (cosmetic, client-only)
Load(SharedModules, "AnimationSystem")  -- centralized animation controller (emotes, idles, custom)
Load(SharedModules, "CosmeticClient")   -- cosmetic cache + wardrobe request/sync
Load(SharedModules, "InputSystem")      -- centralized input dispatcher (BEFORE UI mounts)
Load(SharedModules, "SoundManager")
Load(SharedModules, "MovementSystem")   -- standard Roblox movement behaviour
Load(SharedModules, "CameraSystem")     -- camera controller (avatar-preview mode planned)
-- §AGX/UI-P3: the shell exposes Talents + Achievements in every Place;
-- without these client caches the Plaza panels show 0 points / no data.
Load(SharedModules, "AchievementClient")
Load(SharedModules, "TalentClient")

-- ───────────────────────────────────────────────────────────
-- SERVER READY HANDSHAKE
-- ───────────────────────────────────────────────────────────
local NetworkManager = loadedModules["NetworkManager"]
if NetworkManager then
	NetworkManager.OnServerEvent("ServerReady", function()
		BootProfiler.Mark("ServerReady received")  -- §PERF/BP
		-- §T10/U1: dismiss the loading screen. (Appearance systems
		-- listen for their own events; nothing else needed here.)
		local ls = loadedModules["LoadingScreen"]
		if ls then ls.Dismiss() end
		BootProfiler.Mark("LoadingScreen dismissed")
	end)
end
