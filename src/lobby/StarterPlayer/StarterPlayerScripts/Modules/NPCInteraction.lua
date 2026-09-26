-- StarterPlayerScripts/Modules/NPCInteraction
--[[
    Client-side NPC interaction.

    §AGX/UI-P2: M2/D5 — the custom "[E] Talk" billboard and the 0.25 s
    proximity scan are retired. Each NPC now carries a native ProximityPrompt
    ("NPCPrompt", created server-side by NPCManager.CreateNPCModel), which
    gives touch, gamepad and keyboard with Roblox's own UI.

    • Prompts are enabled locally only while CurrentScene == "Village"
      (same gate the old scan used).
    • The prompt's keyboard key follows the player's "Interact" binding
      (default E), so rebinding in KeybindSettings still works.
    • PromptTriggered fires "NPCInteract" { npcId } to the server — the exact
      remote/payload the old E action fired, so dialogs, shops and smiths
      open unchanged and the server INTERACT_RANGE check still applies.
]]

local NPCInteraction = {}

local Players                = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer

local SharedModules  = player:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local NetworkManager = nil
local InputSystem    = nil

local PROMPT_NAME = "NPCPrompt"

-- ── State ─────────────────────────────────────────────────
local connections        = {}
local unbindBindingChange = nil
local folderConns        = {}

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

local function isNPCPrompt(prompt)
	if not prompt or prompt.Name ~= PROMPT_NAME then return false end
	local parent = prompt.Parent
	return parent ~= nil and parent:GetAttribute("IsNPC") == true
end

local function inVillage()
	return player:GetAttribute("CurrentScene") == "Village"
end

-- §AGX/UI-P2: keyboard key mirrors the Interact binding (default E).
local function interactKeyCode()
	local keys = InputSystem and InputSystem.GetBinding("Interact", "Keyboard") or {}
	local key = keys[1]
	if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
		return key
	end
	return Enum.KeyCode.E
end

local function applyToPrompt(prompt)
	if not isNPCPrompt(prompt) then return end
	-- Local-only property writes on a replicated instance.
	prompt.Enabled = inVillage()
	prompt.KeyboardKeyCode = interactKeyCode()
end

local function applyAll()
	local npcFolder = workspace:FindFirstChild("NPCs")
	if not npcFolder then return end
	for _, d in ipairs(npcFolder:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			applyToPrompt(d)
		end
	end
end

local function watchFolder(npcFolder)
	for _, c in ipairs(folderConns) do c:Disconnect() end
	folderConns = {}
	table.insert(folderConns, npcFolder.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			-- Name/parent are set before replication, but defer one frame to be safe.
			task.defer(applyToPrompt, d)
		end
	end))
	applyAll()
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function NPCInteraction.Init()
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
	InputSystem    = require(SharedModules:WaitForChild("InputSystem"))

	-- §AGX/UI-P2: the InputSystem "Interact" callback is intentionally NOT
	-- bound any more — the prompt's own KeyboardKeyCode handles E, and binding
	-- both would fire NPCInteract twice per key press.

	table.insert(connections, ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
		if triggeringPlayer ~= player then return end
		if not isNPCPrompt(prompt) then return end
		if not inVillage() then return end
		local npcId = prompt.Parent:GetAttribute("NPCId")
		if npcId then
			-- Same remote + payload as the pre-P2 Interact action.
			NetworkManager.FireServer("NPCInteract", { npcId = npcId })
		end
	end))

	table.insert(connections, player:GetAttributeChangedSignal("CurrentScene"):Connect(applyAll))

	unbindBindingChange = InputSystem.OnBindingChanged(applyAll)

	local npcFolder = workspace:FindFirstChild("NPCs")
	if npcFolder then
		watchFolder(npcFolder)
	end
	table.insert(connections, workspace.ChildAdded:Connect(function(child)
		if child.Name == "NPCs" and child:IsA("Folder") then
			watchFolder(child)
		end
	end))
end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════

function NPCInteraction.Stop()
	for _, c in ipairs(connections) do c:Disconnect() end
	connections = {}
	for _, c in ipairs(folderConns) do c:Disconnect() end
	folderConns = {}
	if unbindBindingChange then unbindBindingChange(); unbindBindingChange = nil end
end

return NPCInteraction
