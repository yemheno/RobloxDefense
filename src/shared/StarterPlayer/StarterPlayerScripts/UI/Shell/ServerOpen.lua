-- UI/Shell/ServerOpen.lua
--[[
    §AGX/UI-P3: server-opened and auto-opened entries
    (docs/ui_audit/shell-spec.md §3.6). One hook the Shell calls once:

        ServerOpen.useServerOpen(place)     -- place = "Lobby" | "Plaza" | "Combat"

    1. Character creation: subscribe to CharacterCreationRequired, THEN fire
       RequestCharacterStatus (same race-safe order as LobbyApp.lua:76-88),
       then PanelStack.open("characterCreation"). Replaces the three copies
       in the Apps (W2 deletes them).
    2. Daily login (D14, Lobby only): fire GetDailyLoginStatus on mount (not
       ready-gated); on DailyLoginStatus{canClaim=true}, at most once per
       client session, PanelStack.openWhenIdle("dailyLogin"), so it waits
       for CharacterCreation. ❓ Strict "first lobby join of the day" needs a
       profile field (Pablo's call); this is the canClaim rule.
    3. Death: LocalPlayer DeathState in { KnockedDown, Dead } ->
       PanelStack.setPresence("death", "system", true). DeathUI is untouched.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React = require(ReplicatedStorage.Packages.React)

local PanelStack = require(script.Parent:WaitForChild("PanelStack"))

local ServerOpen = {}

local DEAD_STATES = { KnockedDown = true, Dead = true }

-- Once per client session (module state survives remounts).
local dailyAutoOpened = false

local function getNetworkManager()
	local ok, nm = pcall(function()
		return require(Players.LocalPlayer:WaitForChild("PlayerScripts")
			:WaitForChild("Modules"):WaitForChild("NetworkManager"))
	end)
	return ok and nm or nil
end

function ServerOpen.useServerOpen(place)
	-- 1 + 2: network-driven opens
	React.useEffect(function()
		local NetworkManager = getNetworkManager()
		if not NetworkManager then return nil end
		local conns = {}

		table.insert(conns, NetworkManager.OnServerEvent("CharacterCreationRequired", function()
			PanelStack.open("characterCreation", nil, "server")
		end))
		-- Listener first, then ask (the server may have fired before mount).
		NetworkManager.FireServer("RequestCharacterStatus")

		if place == "Lobby" then
			table.insert(conns, NetworkManager.OnServerEvent("DailyLoginStatus", function(data)
				if type(data) ~= "table" or not data.canClaim then return end
				if dailyAutoOpened then return end
				dailyAutoOpened = true
				PanelStack.openWhenIdle("dailyLogin")
			end))
			NetworkManager.FireServer("GetDailyLoginStatus")
		end

		return function()
			for _, c in ipairs(conns) do
				if c and c.Disconnect then c:Disconnect() end
			end
		end
	end, { place })

	-- 3: death = system presence (suspends every panel, blocks new opens)
	React.useEffect(function()
		local lp = Players.LocalPlayer
		local function sync()
			PanelStack.setPresence("death", "system", DEAD_STATES[lp:GetAttribute("DeathState")] == true)
		end
		sync()
		local conn = lp:GetAttributeChangedSignal("DeathState"):Connect(sync)
		return function()
			conn:Disconnect()
			PanelStack.setPresence("death", "system", false)
		end
	end, {})
end

ServerOpen.use = ServerOpen.useServerOpen

return ServerOpen
