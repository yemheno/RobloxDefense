-- hordemode/ServerScriptService/Modules/HordeModeMapLoader.lua
--[[
    HordeModeMapLoader
    ──────────────────
    Implements the ServerStorage → ReplicatedStorage asset lifecycle.

    The design principle:
      • Templates (mobs, projectiles, etc.) live in ServerStorage so they
        are NEVER replicated to clients by default.
      • When HordeMode starts, LoadAssets() moves the needed folders into
        ReplicatedStorage so server-side systems (MobSpawner, ProjectileSystem)
        can find them — and clients can receive projectile visuals.
      • On shutdown / place-leave, UnloadAssets() moves them back so they
        are not left in RS between sessions.

    Current asset manifest
    ──────────────────────
    ServerStorage.Models.Mobs  →  ReplicatedStorage.Mobs
        Contains: MobTemplate (and any future mob model files)

    Extend ASSET_MANIFEST below when new asset folders are added.
]]

local HordeModeMapLoader = {}

local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─────────────────────────────────────────────────────────────────────
-- ASSET MANIFEST
-- Each entry: { sourcePath = {"parent", "child", ...}, destParent, destName }
--   sourcePath  : list of WaitForChild names descending from ServerStorage
--   destParent  : the Instance that will receive the moved folder
--   destName    : the Name the folder will have in its destination
-- ─────────────────────────────────────────────────────────────────────
local ASSET_MANIFEST = {
    {
        -- ServerStorage.Models.Mobs  →  ReplicatedStorage.Mobs
        sourcePath = { "Models", "Mobs" },
        destParent = ReplicatedStorage,
        destName   = "Mobs",
    },
    {
        -- ServerStorage.Models.Projectiles  →  ReplicatedStorage.Projectiles
        sourcePath = { "Models", "Projectiles" },
        destParent = ReplicatedStorage,
        destName   = "Projectiles",
    },
}

-- ─────────────────────────────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────────────────────────────

--- Walk a path of child names from `root`, waiting up to `timeout` each step.
--- Returns the final Instance, or nil on failure.
local function resolvePath(root, path, timeout)
    timeout = timeout or 5
    local current = root
    for _, name in ipairs(path) do
        local child = current:WaitForChild(name, timeout)
        if not child then
            warn("[HordeModeMapLoader] Could not find child:", name, "under", current:GetFullName())
            return nil
        end
        current = child
    end
    return current
end

-- ─────────────────────────────────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────────────────────────────────

---Load game assets: move folders from ServerStorage → ReplicatedStorage.
---Call this BEFORE MobSpawner.Init() so templates are available.
function HordeModeMapLoader.LoadAssets()

    for _, entry in ipairs(ASSET_MANIFEST) do
        -- Check if already in destination (guard against double-call)
        local existing = entry.destParent:FindFirstChild(entry.destName)
        if existing then
            warn("[HordeModeMapLoader] Asset already in destination, skipping:", entry.destName)
            continue
        end

        local source = resolvePath(ServerStorage, entry.sourcePath)
        if not source then
            warn("[HordeModeMapLoader] Source not found for:", table.concat(entry.sourcePath, "/"))
            continue
        end

        source.Name   = entry.destName
        source.Parent = entry.destParent
    end

    print("[HordeModeMapLoader] Assets loaded")
end

---Unload game assets: move folders back from ReplicatedStorage → ServerStorage.
---Call this on game end / all players left.
function HordeModeMapLoader.UnloadAssets()

    -- Walk manifest in reverse so dependencies unload after dependents
    for i = #ASSET_MANIFEST, 1, -1 do
        local entry = ASSET_MANIFEST[i]

        local asset = entry.destParent:FindFirstChild(entry.destName)
        if not asset then
            -- Not there; may have never loaded or already moved back
            continue
        end

        -- Restore original name (last element of sourcePath)
        asset.Name   = entry.sourcePath[#entry.sourcePath]

        -- Restore under the correct ServerStorage parent
        local destInSS = resolvePath(ServerStorage, { table.unpack(entry.sourcePath, 1, #entry.sourcePath - 1) })
        if destInSS then
            asset.Parent = destInSS
        else
            warn("[HordeModeMapLoader] Could not restore", entry.destName, ": parent path not found in ServerStorage")
        end
    end

    print("[HordeModeMapLoader] Assets unloaded")
end

return HordeModeMapLoader
