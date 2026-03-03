-- MovementSystem/FacePoint
--[[
    Forces the character to always face a fixed world-space point every frame.
    Designed for the CentralBoss place where players always face the boss.

    Config (passed to Start):
        bossPoint : Vector3  — world position to face  (optional)
                               If nil, reads a Part named "BossPoint" from
                               Workspace, or falls back to Vector3.zero.
]]

local FacePoint = {}

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player     = Players.LocalPlayer
local connection = nil
local charConn   = nil

-- Cached target; updated each Start() and on respawn.
local targetPoint = Vector3.zero

-- ── Helper: resolve the boss world position ───────────────
local function resolvePoint(config)
    if config and config.bossPoint then
        return config.bossPoint
    end
    local part = workspace:FindFirstChild("BossPoint")
    if part and part:IsA("BasePart") then
        return part.Position
    end
    return Vector3.zero
end

-- ── Internal helpers ──────────────────────────────────────
local function disableAutoRotate(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.AutoRotate = false
    end
end

local function update()
    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    -- Live-track the BossPoint part if it exists (boss can move)
    local livePart = workspace:FindFirstChild("BossPoint")
    local target = (livePart and livePart:IsA("BasePart"))
        and livePart.Position
        or targetPoint

    local pos = rootPart.Position

    -- Only rotate on the horizontal plane (Y stays unchanged)
    local flatDir = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
    if flatDir.Magnitude < 0.01 then return end

    rootPart.CFrame = CFrame.new(pos, pos + flatDir)
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC
-- ═══════════════════════════════════════════════════════════

function FacePoint.Start(config)
    config = config or {}
    targetPoint = resolvePoint(config)

    -- Disable AutoRotate on the current character
    local character = player.Character
    if character then
        disableAutoRotate(character)
    end

    -- Disable AutoRotate on every future respawn
    if charConn then charConn:Disconnect() end
    charConn = player.CharacterAdded:Connect(function(newChar)
        task.wait()
        disableAutoRotate(newChar)
        targetPoint = resolvePoint(config)
    end)

    if connection then connection:Disconnect() end
    connection = RunService.RenderStepped:Connect(update)
end

function FacePoint.Stop()
    if connection then
        connection:Disconnect()
        connection = nil
    end

    if charConn then
        charConn:Disconnect()
        charConn = nil
    end

    -- Re-enable AutoRotate on current character
    local character = player.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.AutoRotate = true end
    end
end

return FacePoint
