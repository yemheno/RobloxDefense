-- ServerScriptService/Modules/MobAssetLoader
--[[
    Clones mob and projectile template folders from ServerStorage → ReplicatedStorage
    so MobSpawner and ProjectileSystem can find them at runtime.

    Uses Clone instead of reparent so Rojo live-sync doesn't fight
    the moved instances and recreate empty folders.

    Call MobAssetLoader.Load() BEFORE MobSpawner.Init() and
    ProjectileSystem.Init().

    The clones remain in ReplicatedStorage for the lifetime of the server
    instance (no need to unload between rounds in a single-place server).
]]

local MobAssetLoader = {}

local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- { ssPath = table of child names from ServerStorage, rsName = destination name }
local MANIFEST = {
    { ssPath = { "Models", "Mobs" },        rsName = "Mobs" },
    { ssPath = { "Models", "Projectiles" }, rsName = "Projectiles" },
}

local function resolvePath(root, path, timeout)
    local current = root
    for _, name in ipairs(path) do
        local child = current:WaitForChild(name, timeout or 5)
        if not child then
            warn("[MobAssetLoader] Missing child:", name, "under", current:GetFullName())
            return nil
        end
        current = child
    end
    return current
end

function MobAssetLoader.Init()
    -- No-op Init so the Load() helper in bootstraps can call it generically.
    -- The actual loading is triggered explicitly via MobAssetLoader.Load().
end

function MobAssetLoader.Load()
    for _, entry in ipairs(MANIFEST) do
        -- Skip if already in ReplicatedStorage (guard against double-call)
        if ReplicatedStorage:FindFirstChild(entry.rsName) then
            print("[MobAssetLoader] Already exists:", entry.rsName, "— skipping")
            continue
        end

        local source = resolvePath(ServerStorage, entry.ssPath)
        if not source then
            warn("[MobAssetLoader] Source not found for:", table.concat(entry.ssPath, "/"))
            continue
        end

        -- Clone rather than reparent: Rojo live-sync owns ServerStorage,
        -- moving its children causes it to recreate empty folders.
        local clone = source:Clone()
        clone.Name   = entry.rsName
        clone.Parent = ReplicatedStorage

        local childCount = #clone:GetChildren()
        print("[MobAssetLoader]", entry.rsName, "→ cloned", childCount, "children to ReplicatedStorage")
    end

    print("[MobAssetLoader] Assets loaded →  ReplicatedStorage")
end

return MobAssetLoader
