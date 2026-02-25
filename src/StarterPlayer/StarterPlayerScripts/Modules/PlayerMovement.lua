-- StarterPlayerScripts/Modules/PlayerMovement

local PlayerMovement = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

function PlayerMovement.Init()
	local function SetupCharacter(character)
		local humanoid = character:WaitForChild("Humanoid")

		-- Disable jumping
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end

	-- Setup existing character
	if player.Character then
		SetupCharacter(player.Character)
	end

	-- Setup future characters
	player.CharacterAdded:Connect(SetupCharacter)

	-- Always face +X
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		if not character then return end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end

		local pos = rootPart.Position
		rootPart.CFrame = CFrame.new(pos, pos + Vector3.new(1, 0, 0))
	end)

	print("[PlayerMovement] Initialized - No jump, always faces +X")
end

return PlayerMovement