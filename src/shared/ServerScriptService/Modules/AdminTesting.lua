-- ServerScriptService/Modules/AdminTesting
--[[
    Admin-only testing and debugging panel server handler.

    §T0P2/X25: ALL requests are validated server-side — the player must be
    the game creator OR be in PlayerDataConfig.AdminUserIds (single source
    of truth). Client-side UI is purely cosmetic — no trust is given.

    ⚠ §T0P2/X16 (parked in docs/TODO.md): this whole module + the
    AdminAction/DebugCommand remote surface is scheduled for REMOVAL
    before public release — admin tooling moves to Studio runtime
    console commands. Any remote admin surface is attack surface for
    custom clients, even gated.

    Supported actions (sent via "AdminAction" RemoteEvent):
        "ResetData"          – Wipe account progression to defaults (level 1, 0 currencies)
        "WipeAndKick"        – Hard-delete saved data from the DataStore, then kick
        "SetLevel"      N    – Jump to level N (1–9999)
        "AddXP"         N    – Grant N XP (uses the canonical AddExperience path)
        "AddMerits"     N    – Grant N Merits
        "AddEssence"    N    – Grant N Essence
        "AddTalentPts"  N    – Grant N bonus talent points (BonusTalentPoints field)
        "Respawn"            – Force-respawn the player's character
        "MaxWeapon"          – Set weapon to max refinement (+15) and tier 12 (debug convenience)
        "SetGender"     S    – Set gender to "Male" or "Female" and respawn to re-apply template
        "SetClass"      S    – Switch to a class by name (bypasses cooldowns/unlock requirements)
        "ResetCooldowns"     – Reset all skill cooldowns instantly

    Server replies with "AdminActionResult" { ok=bool, message=string }.
]]

local AdminTesting = {}

local _Players = game:GetService("Players")  -- reserved for future use
local Modules = script.Parent

-- Lazy-load to avoid circular deps
local NetworkManager    = nil
local PlayerDataManager = nil
local CurrencyManager   = nil
local PlayerDataConfig  = nil
local CharacterManager  = nil

local function getNet()
	if not NetworkManager then
		NetworkManager = require(Modules:WaitForChild("NetworkManager"))
	end
	return NetworkManager
end

local function getPDM()
	if not PlayerDataManager then
		PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
	end
	return PlayerDataManager
end

local function getCurrency()
	if not CurrencyManager then
		CurrencyManager = require(Modules:WaitForChild("CurrencyManager"))
	end
	return CurrencyManager
end

local function getConfig()
	if not PlayerDataConfig then
		PlayerDataConfig = require(Modules:WaitForChild("PlayerDataConfig"))
	end
	return PlayerDataConfig
end

local function getCharMgr()
	if not CharacterManager then
		CharacterManager = require(Modules:WaitForChild("CharacterManager"))
	end
	return CharacterManager
end

-- ═══════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════

-- Developer allowlist is centralised in PlayerDataConfig.AdminUserIds.
-- Do NOT maintain a separate local ADMIN_IDS copy here.
local function isAdmin(player)
	if not player then return false end
	if player.UserId == game.CreatorId then return true end
	local cfg = getConfig()
	return cfg.AdminUserIds and cfg.AdminUserIds[player.UserId] == true
end

local function reply(player, ok, message)
	getNet().FireClient(player, "AdminActionResult", { ok = ok, message = message })
end

-- ═══════════════════════════════════════════════════════════
-- ACTION HANDLERS
-- ═══════════════════════════════════════════════════════════

local actions = {}

-- Reset account progression to level-1 defaults
function actions.ResetData(player, _)
	local pdm = getPDM()
	local data = pdm.GetData(player)
	if not data then
		return false, "No data found"
	end

	-- Reset the fields we can safely touch at runtime
	data.Account.Level      = 1
	data.Account.Experience = 0
	data.Account.Merits     = 0
	data.Account.Essence    = 0
	data.Account.AllocatedTalents = {}
	data.Account.BonusTalentPoints = 0

	-- Reset stat allocations for all classes
	for _, classData in pairs(data.Classes or {}) do
		if classData.Allocated then
			for stat, _ in pairs(classData.Allocated) do
				classData.Allocated[stat] = 0
			end
		end
	end

	-- §T0P2/X18: the old reset zeroed the DATA but left the APPLIED
	-- state live — talent bonuses stayed in BonusManager's "talent"
	-- source and max HP stayed inflated until rejoin, polluting test
	-- results on exactly the accounts used for tier live-tests.
	do
		local taMod = Modules:FindFirstChild("TalentEffectAggregator")
		if taMod then
			local ok, ta = pcall(require, taMod)
			if ok and ta and ta.Rebuild then
				ta.Rebuild(player, {})  -- empty allocation set → clears "talent" source
			end
		end
		local tmMod = Modules:FindFirstChild("TalentManager")
		if tmMod then
			local ok, tm = pcall(require, tmMod)
			if ok and tm and tm.SendState then tm.SendState(player) end
		end
		if player.Character then
			pdm.ApplyHealthToCharacter(player, player.Character)
		end
	end

	-- Force leaderstats update
	pdm.SetAccountData(player, "Merits", 0)
	pdm.SetAccountData(player, "Level", 1)

	-- Push fresh currency + player info to client
	getCurrency()  -- ensure loaded
	local net = getNet()
	net.FireClient(player, "CurrencyUpdate", { merits = 0, essence = 0 })
	net.FireClient(player, "PlayerInfoUpdate", {
		level    = 1,
		xp       = 0,
		xpNeeded = getConfig().GetXPForLevel(1),
	})

	print("[AdminTesting] Reset data for", player.Name)
	return true, "Data reset to level 1 defaults"
end

-- Set player level directly
function actions.SetLevel(player, args)
	local level = math.clamp(math.floor(tonumber(args[1]) or 1), 1, 9999)
	local pdm   = getPDM()
	local data  = pdm.GetData(player)
	if not data then return false, "No data found" end

	data.Account.Level      = level
	data.Account.Experience = 0
	pdm.SetAccountData(player, "Level", level)

	-- §T0P2/X18: unlock any level-gated classes at the new level — the
	-- natural level-up path does this; SetLevel used to skip it.
	pdm.CheckUnlockEligibleClasses(player)

	local cfg = getConfig()
	getNet().FireClient(player, "PlayerInfoUpdate", {
		level    = level,
		xp       = 0,
		xpNeeded = cfg.GetXPForLevel(level),
	})

	print("[AdminTesting] Set level", level, "for", player.Name)
	return true, "Level set to " .. level
end

-- Add XP (uses canonical path — applies XPBonus + BonusExpSystem)
function actions.AddXP(player, args)
	local amount = math.max(1, math.floor(tonumber(args[1]) or 100))
	getPDM().AddExperience(player, amount)
	print("[AdminTesting] Added", amount, "XP to", player.Name)
	return true, "+" .. amount .. " XP granted"
end

-- Add Merits
function actions.AddMerits(player, args)
	local amount = math.max(1, math.floor(tonumber(args[1]) or 1000))
	getCurrency().AddMerits(player, amount)
	print("[AdminTesting] Added", amount, "Merits to", player.Name)
	return true, "+" .. amount .. " Merits granted"
end

-- Add Essence
function actions.AddEssence(player, args)
	local amount = math.max(1, math.floor(tonumber(args[1]) or 50))
	getCurrency().AddEssence(player, amount)
	print("[AdminTesting] Added", amount, "Essence to", player.Name)
	return true, "+" .. amount .. " Essence granted"
end

-- Add bonus talent points (separate from level-based points)
function actions.AddTalentPts(player, args)
	local amount = math.max(1, math.floor(tonumber(args[1]) or 10))
	local pdm    = getPDM()
	local data   = pdm.GetData(player)
	if not data then return false, "No data found" end

	data.Account.BonusTalentPoints = (data.Account.BonusTalentPoints or 0) + amount
	print("[AdminTesting] Added", amount, "bonus talent points to", player.Name)

	-- Reload TalentManager to push fresh state
	local TalentManagerMod = Modules:FindFirstChild("TalentManager")
	if TalentManagerMod then
		local ok, TalentManager = pcall(require, TalentManagerMod)
		if ok and TalentManager and TalentManager.SendState then
			TalentManager.SendState(player)
		end
	end

	return true, "+" .. amount .. " bonus talent points granted"
end

-- Wipe ALL saved data from the DataStore then kick the player.
-- On rejoin they go through the full first-login character creation flow.
function actions.WipeAndKick(player, _)
	local pdm = getPDM()
	local ok, err = pdm.WipeData(player)
	if not ok then
		return false, "DataStore wipe failed: " .. tostring(err)
	end
	-- Brief delay so the client receives the success response before being kicked.
	task.delay(0.5, function()
		player:Kick("🗑  Your data was wiped by an admin. Rejoin to start fresh.")
	end)
	print("[AdminTesting] WipeAndKick:", player.Name)
	return true, "Data wiped — kicking player now…"
end

-- Force respawn
function actions.Respawn(player, _)
	player:LoadCharacter()
	return true, "Respawned"
end

-- Max weapon: set to T12 and +15 refinement for quick gear testing
function actions.MaxWeapon(player, _)
	local pdm  = getPDM()
	local data = pdm.GetData(player)
	if not data then return false, "No data found" end

	local classData = data.Classes[data.ActiveClass]
	if not classData then return false, "No class data" end

	local weapon = classData.EquippedWeapon
	if not weapon then return false, "No weapon equipped" end

	weapon.tier       = 12
	weapon.refinement = 15
	weapon.level      = data.Account.Level

	print("[AdminTesting] Maxed weapon for", player.Name)
	return true, "Weapon set to T12 +15"
end

-- Set character gender and respawn so ApplyTemplate runs with the new gender
function actions.SetGender(player, args)
	local gender = args[1]
	if gender ~= "Male" and gender ~= "Female" then
		return false, "Invalid gender — 'Male' or 'Female' expected"
	end

	local pdm = getPDM()
	local data = pdm.GetData(player)
	if not data then return false, "No data found" end

	-- Ensure CharacterData exists and is marked created (ApplyTemplate gate)
	if not data.Account.CharacterData then
		data.Account.CharacterData = {
			gender    = gender,
			preset    = 1,
			skinColor = "skin_fair",
			isCreated = true,
		}
	else
		data.Account.CharacterData.gender    = gender
		data.Account.CharacterData.isCreated = true
	end

	-- LoadCharacter fires CharacterAdded → CharacterManager.ApplyTemplate runs automatically
	-- Works in both Studio and production (character:Destroy alone doesn't respawn in Studio)
	player:LoadCharacter()

	print("[AdminTesting] SetGender →", gender, "for", player.Name)
	return true, "Gender → " .. gender .. "  (respawning…)"
end

-- Reset all skill cooldowns instantly
function actions.ResetCooldowns(player, _)
	local SkillManager = require(Modules:WaitForChild("SkillManager"))
	SkillManager.ResetAllCooldowns(player)
	print("[AdminTesting] Reset all cooldowns for", player.Name)
	return true, "All cooldowns reset"
end

-- Switch class instantly (bypasses cooldowns and unlock requirements)
function actions.SetClass(player, args)

	local className = args[1]
	if not className or className == "" then
		return false, "Class name required"
	end

	local ClassManager = require(Modules:WaitForChild("ClassManager"))
	local ok, err = ClassManager.SetClass(player, className)
	if not ok then
		return false, err or "Failed to set class"
	end

	-- Push updated info to client
	local pdm = getPDM()
	local data = pdm.GetData(player)
	local cfg = getConfig()
	getNet().FireClient(player, "PlayerInfoUpdate", {
		level           = data.Account.Level,
		xp              = data.Account.Experience,
		xpNeeded        = cfg.GetXPForLevel(data.Account.Level),
		activeClass     = className,
		unlockedClasses = data.Account.UnlockedClasses,
	})

	player:LoadCharacter()
	print("[AdminTesting] SetClass →", className, "for", player.Name)
	return true, "Class → " .. className .. "  (respawning…)"
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function AdminTesting.Init()
	local net = getNet()

	net.GetEvent("AdminAction")
	net.GetEvent("AdminActionResult")

	net.OnClientEvent("AdminAction", function(player, actionName, ...)
		-- Gate: only the game creator can use this panel
		if not isAdmin(player) then
			warn("[AdminTesting] Blocked non-admin request from", player.Name)
			reply(player, false, "Access denied")
			return
		end

		local handler = actions[actionName]
		if not handler then
			reply(player, false, "Unknown action: " .. tostring(actionName))
			return
		end

		-- pcall captures both return values from the handler (success bool, message string)
		local args = { ... }
		local callOk, success, message = pcall(handler, player, args)

		if not callOk then
			warn("[AdminTesting] Error in action", actionName, ":", success)
			reply(player, false, "Server error: " .. tostring(success))
		else
			reply(player, success == true, message or "OK")
		end
	end)

end

return AdminTesting
