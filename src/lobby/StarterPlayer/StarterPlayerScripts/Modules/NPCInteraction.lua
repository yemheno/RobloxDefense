-- StarterPlayerScripts/Modules/NPCInteraction
--[[
    Client-side NPC proximity detection and interaction.
    
    • Scans for nearby NPCs every 0.25 s.
    • Shows an "[E] Talk" prompt when within range.
    • On key press, fires "NPCInteract" to the server.
    • Only active in Village scene (checks player attribute).
]]

local NPCInteraction = {}

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")

local player = Players.LocalPlayer

local SharedModules  = player:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local NetworkManager = nil
local InputSystem    = nil

-- ── Settings ──────────────────────────────────────────────
local INTERACT_RANGE = 12
local SCAN_INTERVAL  = 0.25

-- ── State ─────────────────────────────────────────────────
local nearestNPC  = nil   -- { model, npcId, npcName }
local promptGui   = nil   -- BillboardGui instance (reused)
local scanConn    = nil
local inputBindId = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function NPCInteraction.Init()
	NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
	InputSystem    = require(SharedModules:WaitForChild("InputSystem"))

	-- Create the reusable prompt billboard
	promptGui = NPCInteraction.CreatePromptGui()

	-- Start scanning
	local lastScan = 0
	scanConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastScan < SCAN_INTERVAL then return end
		lastScan = now

		-- Only scan in Village
		if player:GetAttribute("CurrentScene") ~= "Village" then
			NPCInteraction.ClearNearestNPC()
			return
		end

		NPCInteraction.ScanForNearbyNPC()
	end)

	-- Input (via centralized InputSystem)
	inputBindId = InputSystem.BindAction("Interact", function(_actionName, inputState)
		if inputState ~= "Began" then return end
		if nearestNPC then
			NetworkManager.FireServer("NPCInteract", { npcId = nearestNPC.npcId })
		end
	end)

end

-- ═══════════════════════════════════════════════════════════
-- SCANNING
-- ═══════════════════════════════════════════════════════════

function NPCInteraction.ScanForNearbyNPC()
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local playerPos = rootPart.Position

	local npcFolder = workspace:FindFirstChild("NPCs")
	if not npcFolder then
		NPCInteraction.ClearNearestNPC()
		return
	end

	local closestDist = INTERACT_RANGE
	local closestModel = nil
	local closestId = nil
	local closestName = nil

	for _, model in ipairs(npcFolder:GetChildren()) do
		local npcRoot = model:FindFirstChild("HumanoidRootPart")
		if npcRoot and npcRoot:GetAttribute("IsNPC") then
			local dist = (playerPos - npcRoot.Position).Magnitude
			if dist < closestDist then
				closestDist  = dist
				closestModel = model
				closestId    = npcRoot:GetAttribute("NPCId")
				closestName  = npcRoot:GetAttribute("NPCName")
			end
		end
	end

	if closestModel then
		NPCInteraction.SetNearestNPC(closestModel, closestId, closestName)
	else
		NPCInteraction.ClearNearestNPC()
	end
end

function NPCInteraction.SetNearestNPC(model, npcId, npcName)
	if nearestNPC and nearestNPC.model == model then
		return  -- already showing
	end

	nearestNPC = { model = model, npcId = npcId, npcName = npcName }

	-- Show prompt above the NPC's head
	local head = model:FindFirstChild("Head")
	if head then
		promptGui.Adornee = head
		promptGui.Enabled = true
	end
end

function NPCInteraction.ClearNearestNPC()
	if not nearestNPC then return end
	nearestNPC = nil
	promptGui.Enabled = false
	promptGui.Adornee = nil
end

-- ═══════════════════════════════════════════════════════════
-- PROMPT GUI
-- ═══════════════════════════════════════════════════════════

function NPCInteraction.CreatePromptGui()
	local gui = Instance.new("BillboardGui")
	gui.Name        = "NPCPrompt"
	gui.Size        = UDim2.new(0, 120, 0, 40)
	gui.StudsOffset = Vector3.new(0, 3.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance  = INTERACT_RANGE + 5
	gui.Enabled     = false
	gui.Parent      = player:WaitForChild("PlayerGui")

	local bg = Instance.new("Frame")
	bg.Size                   = UDim2.fromScale(1, 1)
	bg.BackgroundColor3       = Color3.fromRGB(20, 20, 30)
	bg.BackgroundTransparency = 0.2
	bg.BorderSizePixel        = 0
	bg.Parent                 = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent       = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color     = Color3.fromRGB(255, 220, 100)
	stroke.Thickness = 1.5
	stroke.Parent    = bg

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text                   = "[" .. (InputSystem and InputSystem.GetBindingDisplayName("Interact") or "E") .. "]  Talk"
	label.TextColor3             = Color3.fromRGB(255, 220, 100)
	label.Font                   = Enum.Font.GothamBold
	label.TextScaled             = true
	label.Parent                 = bg

	return gui
end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════

function NPCInteraction.Stop()
	if scanConn then scanConn:Disconnect(); scanConn = nil end
	if inputBindId then InputSystem.UnbindAction("Interact", inputBindId); inputBindId = nil end
	NPCInteraction.ClearNearestNPC()
end

return NPCInteraction
