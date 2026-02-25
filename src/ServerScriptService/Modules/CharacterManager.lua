-- ServerScriptService/Modules/CharacterManager
--[[
    CharacterManager
    ================
    Orchestrates the one-time character creation flow for new players
    and manages character template application throughout the session.

    Flow:
        1. Player joins → server checks CharacterData.isCreated
        2. If false  → fires "CharacterCreationRequired" to that client
        3. Client shows creation screen (gender + preset)
        4. Client fires "CharacterCreationComplete" with { gender, preset }
        5. Server validates, saves to PlayerData, calls ApplyTemplate
        6. CharacterData.isCreated = true → never shown again

    Character Templates:
        Models named "<PresetName>_<Gender>" live in
        ReplicatedStorage/CharacterTemplates.
        Missing templates are handled gracefully (default avatar is kept).
        Once actual models exist, drop them into that folder — no code change.
]]

local CharacterManager = {}

local Players        = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules           = script.Parent
local NetworkManager    = require(Modules:WaitForChild("NetworkManager"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
local CharacterConfig   = require(Modules:WaitForChild("CharacterConfig"))

-- ═══════════════════════════════════════════════════════════
-- TEMPLATE FOLDER (optional — system works without it)
-- ═══════════════════════════════════════════════════════════

local TEMPLATES_FOLDER_NAME = "CharacterTemplates"

local function GetTemplatesFolder()
	return ReplicatedStorage:FindFirstChild(TEMPLATES_FOLDER_NAME)
end

-- ═══════════════════════════════════════════════════════════
-- TEMPLATE APPLICATION
-- ═══════════════════════════════════════════════════════════

--[[
    ApplyTemplate(player)
    Loads the character model that matches the player's saved preset+gender.
    Safe to call at any point after CharacterData is set.
    Does nothing and returns false if the template model doesn't exist yet.
]]
function CharacterManager.ApplyTemplate(player)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.Account or not data.Account.CharacterData then return false end

	local cd = data.Account.CharacterData
	if not cd.isCreated then return false end

	local templateName = CharacterConfig.GetTemplateName(cd.preset, cd.gender)
	local folder = GetTemplatesFolder()

	if not folder then
		-- Templates folder not set up yet — log once, keep default avatar
		print("[CharacterManager] CharacterTemplates folder not found — using default avatar for", player.Name)
		return false
	end

	local template = folder:FindFirstChild(templateName)
	if not template then
		print("[CharacterManager] Template '" .. templateName .. "' not found — using default avatar for", player.Name)
		return false
	end

	--[[
	    TODO: Swap the player's character with the template model.
	    Two options depending on your mesh setup:

	    Option A — Custom HumanoidDescription (avatar accessories override):
	        local hd = template:FindFirstChildOfClass("HumanoidDescription")
	        if hd then player:LoadCharacterWithHumanoidDescription(hd) end

	    Option B — Full custom character model:
	        local clone = template:Clone()
	        clone.Name = player.Name
	        player.Character = clone
	        clone.Parent = workspace

	    Uncomment / adapt once models are production-ready.
	]]
	print("[CharacterManager] Template found for", player.Name, "→", templateName, "(application pending model setup)")
	return true
end

-- ═══════════════════════════════════════════════════════════
-- GENDERED CLASS TITLE
-- ═══════════════════════════════════════════════════════════

--[[
    GetClassTitle(player, className)
    Returns the display name for a class, respecting the player's gender.
    Falls back to the masculine form for players who haven't completed
    character creation yet.
]]
function CharacterManager.GetClassTitle(player, className)
	local data = PlayerDataManager.GetData(player)
	local gender = data and data.Account and data.Account.CharacterData and data.Account.CharacterData.gender
	return CharacterConfig.GetClassTitle(className, gender)
end

-- ═══════════════════════════════════════════════════════════
-- CHARACTER CREATION SAVE
-- ═══════════════════════════════════════════════════════════

local function SaveCharacterCreation(player, gender, preset)
	local data = PlayerDataManager.GetData(player)
	if not data then
		warn("[CharacterManager] No data for", player.Name)
		return false
	end

	-- Validate
	if not CharacterConfig.IsValidGender(gender) then
		warn("[CharacterManager] Invalid gender from", player.Name, ":", tostring(gender))
		return false
	end
	if not CharacterConfig.IsValidPreset(preset) then
		warn("[CharacterManager] Invalid preset from", player.Name, ":", tostring(preset))
		return false
	end

	-- Save
	data.Account.CharacterData.gender    = gender
	data.Account.CharacterData.preset    = preset
	data.Account.CharacterData.isCreated = true

	print("[CharacterManager]", player.Name, "→ Character created:", gender, "Preset", preset)
	NetworkManager.FireClient(player, "CharacterCreationSaved", {
		gender = gender,
		preset = preset,
	})

	CharacterManager.ApplyTemplate(player)
	return true
end

-- ═══════════════════════════════════════════════════════════
-- FIRST-LOGIN CHECK
-- ═══════════════════════════════════════════════════════════

local function CheckFirstLogin(player)
	-- Wait a moment so PlayerDataManager finishes initialising the player
	task.wait(0.5)

	local data = PlayerDataManager.GetData(player)
	if not data then return end

	if not data.Account.CharacterData or not data.Account.CharacterData.isCreated then
		print("[CharacterManager]", player.Name, "→ First login, requesting character creation")
		NetworkManager.FireClient(player, "CharacterCreationRequired", {
			presets = CharacterConfig.Presets,
			genders = CharacterConfig.Genders,
		})
	else
		-- Returning player — re-apply their template on each session
		CharacterManager.ApplyTemplate(player)
	end
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function CharacterManager.Init()
	-- Pre-create network events this module owns
	NetworkManager.GetEvent("CharacterCreationRequired")  -- Server → Client
	NetworkManager.GetEvent("CharacterCreationSaved")     -- Server → Client (confirm)
	NetworkManager.GetEvent("CharacterCreationComplete")  -- Client → Server

	-- Listen for client submission
	NetworkManager.OnClientEvent("CharacterCreationComplete", function(player, payload)
		if type(payload) ~= "table" then return end
		SaveCharacterCreation(player, payload.gender, payload.preset)
	end)

	-- Check new players
	Players.PlayerAdded:Connect(function(player)
		CheckFirstLogin(player)
	end)

	-- Seed already-connected players (rare but possible during hot-reload in Studio)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(CheckFirstLogin, player)
	end

	print("[CharacterManager] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC GETTERS
-- ═══════════════════════════════════════════════════════════

function CharacterManager.GetCharacterData(player)
	local data = PlayerDataManager.GetData(player)
	return data and data.Account and data.Account.CharacterData
end

function CharacterManager.IsCreated(player)
	local cd = CharacterManager.GetCharacterData(player)
	return cd ~= nil and cd.isCreated == true
end

function CharacterManager.GetGender(player)
	local cd = CharacterManager.GetCharacterData(player)
	return cd and cd.gender
end

function CharacterManager.GetPreset(player)
	local cd = CharacterManager.GetCharacterData(player)
	return cd and cd.preset
end

return CharacterManager
