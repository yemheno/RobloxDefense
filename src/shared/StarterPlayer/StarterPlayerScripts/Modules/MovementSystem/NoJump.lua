-- MovementSystem/NoJump
--[[
    Disables jumping by zeroing JumpPower and JumpHeight.
    Restores defaults on Stop().
]]

local NoJump = {}

local Players = game:GetService("Players")
local player  = Players.LocalPlayer

local DEFAULT_JUMP_POWER  = 50
local DEFAULT_JUMP_HEIGHT = 7.2

local charConn = nil

local function applyNoJump(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.JumpPower  = 0
		humanoid.JumpHeight = 0
	end
end

local function restoreJump(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.JumpPower  = DEFAULT_JUMP_POWER
		humanoid.JumpHeight = DEFAULT_JUMP_HEIGHT
	end
end

function NoJump.Start(_config)
	if player.Character then
		applyNoJump(player.Character)
	end
	if charConn then charConn:Disconnect() end
	charConn = player.CharacterAdded:Connect(applyNoJump)
end

function NoJump.Stop()
	if charConn then
		charConn:Disconnect()
		charConn = nil
	end
	if player.Character then
		restoreJump(player.Character)
	end
end

return NoJump
