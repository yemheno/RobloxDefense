-- ServerScriptService/Modules/PlaceBootstrap
--[[
    PlaceBootstrap
    ==============
    Shared bootstrap helpers used by every place's Main server script.

    The five Main scripts (Lobby, LaneDefense, HordeMode, CentralBoss,
    SocialPlaza) all repeated the same Load helper + RequireLoaded helper
    + admin guard. Drift between copies bit us multiple times during
    audits (one place forgot to wrap a Load in pcall, another's loud-fail
    error string was stale, etc.). Single source of truth here.

    Each Main starts with:
        local Boot = require(SharedModules:WaitForChild("PlaceBootstrap"))
        local ctx  = Boot.MakeContext("HordeMode")

    Then uses ctx.Load(...), ctx.RequireLoaded(...), ctx.IsAdmin(...).
    The loaded modules live in ctx.loaded, indexed by name.

    Modules at will: each place's Main still lists its module loads
    explicitly. This module only owns the helpers, not the loadlist.
]]

local PlaceBootstrap = {}

local SSS = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedModules = SSS:WaitForChild("Modules")

-- §PERF/BP: boot timeline — every Load (require + Init) is timed here,
-- which covers the entire module boot of all five places.
local BootProfiler = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootProfiler"))

-- Admin allowlist is centralised in PlayerDataConfig.AdminUserIds.
local _AdminCfg = require(SharedModules:WaitForChild("PlayerDataConfig"))

--- Returns true if the player is the game creator OR is in the allowlist.
function PlaceBootstrap.IsAdmin(player)
    if not player then return false end
    if player.UserId == game.CreatorId then return true end
    return _AdminCfg.AdminUserIds and _AdminCfg.AdminUserIds[player.UserId] == true
end

--- Build a per-place bootstrap context. The returned table exposes:
---   • loaded         — `[moduleName] = moduleTable` of every Load'd module
---   • Load(parent, name)    — pcall-require, runs Init() if present, returns the module
---   • RequireLoaded(name)   — hard-error if `name` isn't in `loaded`
---   • IsAdmin(player)
---   • placeName              — the string passed in
---   • SharedModules          — reference to ServerScriptService.Modules
function PlaceBootstrap.MakeContext(placeName)
    assert(type(placeName) == "string", "PlaceBootstrap.MakeContext: placeName required")

    local ctx = {
        placeName     = placeName,
        SharedModules = SharedModules,
        loaded        = {},
        initFailed    = {},  -- §AGX/X16: name → Init() error
        IsAdmin       = PlaceBootstrap.IsAdmin,
    }

    BootProfiler.SetContext(placeName)
    BootProfiler.Mark("MakeContext " .. placeName)

    --- Load a module under `parent` by name. Silent on success (loud
    --- on-success prints removed per §PB-D4); warns on missing-module and
    --- on require errors. Runs `.Init()` on the module if present.
    function ctx.Load(parent, name)
        local mod = parent:FindFirstChild(name)
        if not mod then
            warn(string.format("[%sMain] Module not found: %s", placeName, tostring(name)))
            return nil
        end
        local doneRequire = BootProfiler.Begin("require " .. tostring(name))
        local ok, result = pcall(require, mod)
        doneRequire()
        if not ok then
            warn(string.format("[%sMain] Failed to load %s: %s", placeName, tostring(name), tostring(result)))
            return nil
        end
        -- §T0P2/X15: a module returning a non-table (stray `return true`)
        -- used to crash the whole place boot on the `result.Init` index.
        if type(result) ~= "table" then
            warn(string.format("[%sMain] %s returned a %s (expected table) — loaded without Init",
                placeName, tostring(name), typeof(result)))
            ctx.loaded[name] = result
            return result
        end
        ctx.loaded[name] = result
        if type(result.Init) == "function" then
            local doneInit = BootProfiler.Begin(tostring(name) .. ".Init")
            local initOk, initErr = pcall(result.Init)
            doneInit()
            if not initOk then
                warn(string.format("[%sMain] %s.Init() errored: %s", placeName, tostring(name), tostring(initErr)))
                -- §AGX/X16: remember it so RequireLoaded treats a
                -- half-initialised critical module as a boot failure.
                ctx.initFailed[name] = tostring(initErr)
            end
        end
        return result
    end

    --- Hard-error if a critical module isn't loaded. Use this AFTER all
    --- Load calls to validate the boot tree before any wiring runs.
    function ctx.RequireLoaded(name)
        if not ctx.loaded[name] then
            error(string.format(
                "[%sMain] CRITICAL: required module '%s' failed to load — cannot run %s. " ..
                "Check earlier warnings from Load() for the root cause.",
                placeName, tostring(name), placeName), 0)
        end
        if ctx.initFailed[name] then
            error(string.format(
                "[%sMain] CRITICAL: required module '%s' loaded but its Init() failed: %s",
                placeName, tostring(name), ctx.initFailed[name]), 0)
        end
        return ctx.loaded[name]
    end

    return ctx
end

return PlaceBootstrap
