-- StarterPlayerScripts/Modules/SkillInput

local SkillInput = {}

local Players      = game:GetService("Players")
local StarterGui   = game:GetService("StarterGui")

local player = Players.LocalPlayer

-- Dependencies (set during init)
local NetworkManager = nil
local InputSystem    = nil

-- Cooldown display (local)
local skillCooldowns = {}  -- [skillId] = endTime

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

local initialized = false

function SkillInput.Init()
	if initialized then return end
	initialized = true

	local Modules = script.Parent
	NetworkManager = require(Modules:WaitForChild("NetworkManager"))
	InputSystem    = require(Modules:WaitForChild("InputSystem"))

	-- Bind each skill slot to the corresponding InputSystem action
	for slot = 1, 4 do
		InputSystem.BindAction("Skill" .. slot, function(_actionName, inputState)
			if inputState ~= "Began" then return end
			SkillInput.TryUseSkill(slot)
		end)
	end

	-- Bind Dash (slot 5) to the dedicated Dash action (Spacebar)
	InputSystem.BindAction("Dash", function(_actionName, inputState)
		if inputState ~= "Began" then return end
		SkillInput.TryUseSkill(5)
	end)

	-- Listen for cooldown updates
	NetworkManager.OnServerEvent("SkillCooldownUpdate", function(data)
		if data.skillId then
			skillCooldowns[data.skillId] = data.endTime
		end
	end)

	-- SkillActivated / SkillFailed: same late-loading issue as SkillVisuals.
	-- Use task.spawn + infinite WaitForChild to avoid the 3s timeout race.
	local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")

	-- §AGX/X21 (G21): removed the per-cast debug print on SkillActivated.

	task.spawn(function()
		Events:WaitForChild("SkillFailed").OnClientEvent:Connect(function(data)
			warn("[SkillInput] Skill failed:", data.skillId, "-", data.reason)
			-- Show a brief chat notification so it's visible in-game during testing
			pcall(function()
				StarterGui:SetCore("ChatMakeSystemMessage", {
					Text  = "[Skill] " .. tostring(data.reason or "Failed"),
					Color = Color3.fromRGB(255, 120, 80),
					Font  = Enum.Font.GothamBold,
				})
			end)
		end)
	end)

	-- Restore player's saved keybindings when the server sends PlayerInfoUpdate
	NetworkManager.OnServerEvent("PlayerInfoUpdate", function(data)
		if data and data.keybindings then
			InputSystem.LoadBindings(data.keybindings)
		end
	end)

end

-- ═══════════════════════════════════════════════════════════
-- SKILL USAGE
-- ═══════════════════════════════════════════════════════════

function SkillInput.TryUseSkill(slot)
	-- Scene gate: skills disabled in Village
	if player:GetAttribute("SkillsEnabled") == false then return end

	-- Block skills while knocked down or dead.
	-- §LD-PA1 follow-up: same first-spawn race as PlayerAttack — was
	-- `~= "Alive"` and treated nil as death. SkillManager's server-side
	-- check is strict, so the client only needs to suppress the
	-- explicit not-alive states.
	local deathState = player:GetAttribute("DeathState")
	if deathState == "KnockedDown" or deathState == "Dead" then return end

	local moveDirection = SkillInput.GetMoveDirection()
	local lookDirection = SkillInput.GetLookDirection()

	NetworkManager.FireServer("SkillRequest", "slot_" .. slot, {
		slot          = slot,
		moveDirection = moveDirection,
		lookDirection = lookDirection,   -- authoritative facing direction for projectile skills
	})
end

function SkillInput.GetMoveDirection()
	local character = player.Character
	if not character then return Vector3.zero end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return Vector3.zero end

	local moveDir = humanoid.MoveDirection

	if moveDir.Magnitude > 0.1 then
		return Vector3.new(moveDir.X, 0, moveDir.Z).Unit
	end

	return Vector3.zero
end

--- Returns the direction the character is currently FACING (flat Y=0, normalised).
--- Uses the client-side rootPart.CFrame which FaceDirection has already corrected,
--- making this the authoritative look direction to send to the server for projectile skills.
function SkillInput.GetLookDirection()
	local character = player.Character
	if not character then return Vector3.new(0, 0, -1) end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return Vector3.new(0, 0, -1) end

	local look = rootPart.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.001 then
		return flat.Unit
	end

	return Vector3.new(0, 0, -1)
end

return SkillInput