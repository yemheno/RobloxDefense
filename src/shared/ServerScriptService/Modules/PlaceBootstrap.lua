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
local SharedModules = SSS:WaitForChild("Modules")

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
        IsAdmin       = PlaceBootstrap.IsAdmin,
    }

    --- Load a module under `parent` by name. Silent on success (loud
    --- on-success prints removed per §PB-D4); warns on missing-module and
    --- on require errors. Runs `.Init()` on the module if present.
    function ctx.Load(parent, name)
        local mod = parent:FindFirstChild(name)
        if not mod then
            warn(string.format("[%sMain] Module not found: %s", placeName, tostring(name)))
            return nil
        end
        local ok, result = pcall(require, mod)
        if not ok then
            warn(string.format("[%sMain] Failed to load %s: %s", placeName, tostring(name), tostring(result)))
            return nil
        end
        ctx.loaded[name] = result
        if type(result.Init) == "function" then
            local initOk, initErr = pcall(result.Init)
            if not initOk then
                warn(string.format("[%sMain] %s.Init() errored: %s", placeName, tostring(name), tostring(initErr)))
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
        return ctx.loaded[name]
    end

    return ctx
end

return PlaceBootstrap
