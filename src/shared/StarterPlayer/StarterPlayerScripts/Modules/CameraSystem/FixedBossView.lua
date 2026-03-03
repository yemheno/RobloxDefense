-- CameraSystem/FixedBossView
--[[
    Isometric / fixed-angle camera that follows the player, but always
    looks toward a world-space "boss point" instead of a lane direction.

    Config (passed to Start):
        offset     : Vector3  — camera offset from player  (default: -12, 8, 0)
        bossPoint  : Vector3  — world position of the boss  (optional)
                                If nil, the module reads a Part named "BossPoint"
                                from Workspace, or falls back to Vector3.zero.
]]

local FixedBossView = {}

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player  = Players.LocalPlayer
local camera  = workspace.CurrentCamera

-- ── Defaults ──────────────────────────────────────────────
local DEFAULT_OFFSET = Vector3.new(-12, 8, 0)

local offset     = DEFAULT_OFFSET
local bossTarget = Vector3.zero   -- resolved each Start()
local connection = nil
local charConn   = nil

-- ── Helper: resolve the boss world position ───────────────
local function resolveBossPoint(config)
    -- 1. Explicit config value
    if config and config.bossPoint then
        return config.bossPoint
    end

    -- 2. A Part named "BossPoint" in Workspace
    local part = workspace:FindFirstChild("BossPoint")
    if part and part:IsA("BasePart") then
        return part.Position
    end

    -- 3. Fallback
    return Vector3.zero
end

-- ── Camera update ─────────────────────────────────────────
local function updateCamera()
    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    -- Apply offset relative to player's orientation
    local camPos = rootPart.CFrame * CFrame.new(offset)
    
    -- Look at a point slightly above the player's center
    local lookTarget = rootPart.Position + Vector3.new(0, 2, 0)
    
    camera.CFrame = CFrame.new(camPos.Position, lookTarget)
end

local function setupCamera()
    camera.CameraType = Enum.CameraType.Scriptable
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC
-- ═══════════════════════════════════════════════════════════

function FixedBossView.Start(config)
    config = config or {}
    offset     = config.offset or DEFAULT_OFFSET
    bossTarget = resolveBossPoint(config)

    setupCamera()

    if connection then connection:Disconnect() end
    connection = RunService.RenderStepped:Connect(updateCamera)

    if charConn then charConn:Disconnect() end
    charConn = player.CharacterAdded:Connect(function()
        task.wait(0.1)
        setupCamera()
        -- Re-resolve boss point on respawn (part may have moved)
        bossTarget = resolveBossPoint(config)
    end)
end

function FixedBossView.Stop()
    if connection then
        connection:Disconnect()
        connection = nil
    end
    if charConn then
        charConn:Disconnect()
        charConn = nil
    end
    camera.CameraType = Enum.CameraType.Custom
end

return FixedBossView
