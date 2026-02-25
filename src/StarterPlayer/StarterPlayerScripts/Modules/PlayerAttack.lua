-- StarterPlayerScripts/Modules/PlayerAttack

local PlayerAttack = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- Animation tracking
local currentAttackTrack = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function PlayerAttack.Init()
	-- Input handling
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.MouseButton1 then
			NetworkManager.FireServer("AttackEvent")
		end
	end)

	-- Listen for attack confirmation from server
	NetworkManager.OnServerEvent("AttackActivated", function(data)
		PlayerAttack.OnAttackActivated(data)
	end)

	print("[PlayerAttack] Initialized - Click or Space to attack")
end

-- ═══════════════════════════════════════════════════════════
-- ATTACK FEEDBACK
-- ═══════════════════════════════════════════════════════════

function PlayerAttack.OnAttackActivated(data)
	local animationId = data.animationId
	local attackSpeed = data.attackSpeed or 1.5

	if not animationId then return end

	-- Play animation on local character
	PlayerAttack.PlayAttackAnimation(animationId, attackSpeed)
end

function PlayerAttack.PlayAttackAnimation(animationId, attackSpeed)
	local character = LocalPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Stop previous attack animation if still playing
	if currentAttackTrack and currentAttackTrack.IsPlaying then
		currentAttackTrack:Stop(0.1)
	end

	-- Create and play animation
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if success and track then
		-- Adjust animation speed based on attack speed
		-- Higher attack speed = faster animation
		local animationSpeedMultiplier = attackSpeed / 1.5  -- Normalized to 1.5 as baseline
		track:AdjustSpeed(animationSpeedMultiplier)

		track:Play()
		currentAttackTrack = track

		-- Clean up animation instance after loaded
		animation:Destroy()
	else
		warn("[PlayerAttack] Failed to load animation:", animationId)
		animation:Destroy()
	end
end

return PlayerAttack