-- StarterPlayerScripts/Modules/SkillInput

local SkillInput = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Dependencies (set during init)
local NetworkManager = nil
local KeybindManager = nil

-- Cooldown display (local)
local skillCooldowns = {}  -- [skillId] = endTime

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function SkillInput.Init()
	local Modules = script.Parent
	NetworkManager = require(Modules:WaitForChild("NetworkManager"))
	KeybindManager = require(Modules:WaitForChild("KeybindManager"))

	-- Listen for key presses
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		-- Check if this key is bound to a skill slot
		local slot = KeybindManager.GetSlotForKey(input.KeyCode)
		if slot then
			SkillInput.TryUseSkill(slot)
		end
	end)

	-- Listen for cooldown updates
	NetworkManager.OnServerEvent("SkillCooldownUpdate", function(data)
		if data.skillId then
			skillCooldowns[data.skillId] = data.endTime
		end
	end)

	-- Listen for skill activation (for local feedback)
	NetworkManager.OnServerEvent("SkillActivated", function(data)
		print("[SkillInput] Skill activated:", data.skillId)
	end)

	-- Listen for failures
	NetworkManager.OnServerEvent("SkillFailed", function(data)
		warn("[SkillInput] Skill failed:", data.skillId, "-", data.reason)
	end)

	print("[SkillInput] Initialized")
end

-- ═══════════════════════════════════════════════════════════
-- SKILL USAGE
-- ═══════════════════════════════════════════════════════════

function SkillInput.TryUseSkill(slot)
	local moveDirection = SkillInput.GetMoveDirection()

	NetworkManager.FireServer("SkillRequest", "slot_" .. slot, {
		slot = slot,
		moveDirection = moveDirection,
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

-- ═══════════════════════════════════════════════════════════
-- COOLDOWN CHECKING (For UI)
-- ═══════════════════════════════════════════════════════════

function SkillInput.GetCooldownRemaining(skillId)
	local endTime = skillCooldowns[skillId]
	if not endTime then return 0 end

	local remaining = endTime - tick()
	return math.max(0, remaining)
end

function SkillInput.IsOnCooldown(skillId)
	return SkillInput.GetCooldownRemaining(skillId) > 0
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS (For UI)
-- ═══════════════════════════════════════════════════════════

function SkillInput.GetKeybindManager()
	return KeybindManager
end

return SkillInput