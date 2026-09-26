-- lobby/StarterPlayerScripts/LobbyClient.client.lua
--[[
    Lobby client bootstrap.
    Loads shared client modules + lobby-specific modules.
    Combat modules (SkillInput, PlayerAttack, DamageNumbers, etc.)
    are loaded but will self-gate via player attributes.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local SharedModules = PlayerScripts:WaitForChild("Modules")
local LobbyModules  = PlayerScripts:WaitForChild("Lobby"):WaitForChild("Modules")

-- §PERF/BP: client boot timeline (see BootProfiler for the dump contract)
local BootProfiler = require(game:GetService("ReplicatedStorage")
	:WaitForChild("Shared"):WaitForChild("BootProfiler"))
BootProfiler.SetContext("LobbyClient")

-- ───────────────────────────────────────────────────────────
-- MODULE LOADER
-- ───────────────────────────────────────────────────────────
local loadedModules = {}

local function Load(parent, name)
	local mod = parent:FindFirstChild(name)
	if not mod then
		warn("[LobbyClient] Module not found:", name)
		return nil
	end
	local doneRequire = BootProfiler.Begin("require " .. name)
	local ok, result = pcall(require, mod)
	doneRequire()
	if not ok then
		warn("[LobbyClient] Failed to load", name, ":", result)
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
-- Lobby uses default Roblox camera and movement — CameraSystem
-- and MovementSystem are available but not configured here.
-- ───────────────────────────────────────────────────────────
Load(SharedModules, "LoadingScreen")   -- §T10/U1: overlay up FIRST, dismissed on ServerReady
Load(SharedModules, "NetworkManager")
Load(SharedModules, "ResourceCache")   -- early listener prevents ResourceUpdate queue exhaustion
Load(SharedModules, "AnimationSystem")  -- centralized animation controller
Load(SharedModules, "CosmeticClient")   -- cosmetic cache + wardrobe requests
Load(SharedModules, "AchievementClient") -- achievement cache + toast events
Load(SharedModules, "InputSystem")      -- centralized input dispatcher (BEFORE lobby modules)
Load(SharedModules, "TalentClient")
Load(SharedModules, "Locale")
Load(SharedModules, "SoundManager")
Load(SharedModules, "VipTag")           -- §AGX/UI-FREE: X40-VIP [VIP] chat tag (cosmetic, client-only)

-- ───────────────────────────────────────────────────────────
-- LOBBY CLIENT MODULES
-- ───────────────────────────────────────────────────────────
Load(LobbyModules, "SceneController")
Load(LobbyModules, "NPCInteraction")

-- ───────────────────────────────────────────────────────────
-- §AGX/UI-FREE: §AGX/X4-REASON: why were we sent back?
-- ReturnTeleporter puts `returnReason` in TeleportData on a bounce
-- (§AGX/X4/X6/X14). Read it ONCE on arrival; toast it after the loading
-- overlay is gone (a toast's 3.5 s timer runs even behind the overlay).
-- The server reasons are full sentences; known ones get a friendlier
-- line, unknown ones are shown as sent (it is our own server text).
-- ───────────────────────────────────────────────────────────
local RETURN_REASON_TEXT = {
	-- TeleportDataReader.PUBLIC_SERVER_REASON (§AGX/X4 public-server bounce)
	["Matches run on private servers — returning you to the lobby."] =
		"That match server wasn't open to join, so you're back in the Lobby. Queue up again to play.",
}
local RETURN_REASON_MAX_LEN = 160
local RETURN_TOAST_SECONDS  = 6

local returnReason = nil
do
	local ok, data = pcall(function()
		return game:GetService("TeleportService"):GetLocalPlayerTeleportData()
	end)
	if ok and type(data) == "table" and type(data.returnReason) == "string" and data.returnReason ~= "" then
		returnReason = data.returnReason
		print("[LobbyClient] Arrived with returnReason:", returnReason)
	end
end

local returnReasonShown = false
local function showReturnReason()
	if returnReasonShown or not returnReason then return end
	returnReasonShown = true
	local text = RETURN_REASON_TEXT[returnReason]
		or string.sub(returnReason, 1, RETURN_REASON_MAX_LEN)
	local ok, err = pcall(function()
		local Notify = require(PlayerScripts:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("Notify"))
		Notify.toast("info", text, { key = "return_reason", duration = RETURN_TOAST_SECONDS })
	end)
	if not ok then warn("[LobbyClient] return-reason toast failed:", err) end
end

-- Listen for server ready
-- §T10/U1: the loading-screen dismiss hook (the seam §T0P2/X25 reserved).
-- ServerReady is ReadyGate-routed (§T0P2/X9), so it reliably arrives
-- after this client's ClientReady handshake — i.e. after every queued
-- boot payload has been drained.
local NetworkManager = loadedModules["NetworkManager"]
if NetworkManager then
	NetworkManager.OnServerEvent("ServerReady", function()
		BootProfiler.Mark("ServerReady received")  -- §PERF/BP
		local ls = loadedModules["LoadingScreen"]
		if ls then ls.Dismiss() end
		BootProfiler.Mark("LoadingScreen dismissed")
		-- §AGX/UI-FREE: X4-REASON, after the overlay's fade (0.6 s).
		if returnReason then task.delay(0.8, showReturnReason) end
	end)
end

-- §AGX/UI-FREE: X4-REASON fallback when ServerReady never comes: the
-- LoadingScreen failsafe drops the overlay at 25 s; show it after that.
if returnReason then
	task.delay(26, function()
		local ls = loadedModules["LoadingScreen"]
		if not (ls and ls.IsShown and ls.IsShown()) then showReturnReason() end
	end)
end
