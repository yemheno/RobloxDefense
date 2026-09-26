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
local RunService = game:GetService("RunService")
local SharedModules = SSS:WaitForChild("Modules")

-- §AGX/SEC: §T0P2-ADMIN — the whole remote admin surface (DebugCommand,
-- AdminAction, ModifySystemStat, AdminTesting, TestingUI) exists ONLY in
-- Studio. Live servers never create those remotes, so a custom client
-- has nothing to fire at. Read once: IsStudio() can't change at runtime.
PlaceBootstrap.IS_STUDIO = RunService:IsStudio()

-- §PERF/BP: boot timeline — every Load (require + Init) is timed here,
-- which covers the entire module boot of all five places.
local BootProfiler = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootProfiler"))

-- Admin allowlist is centralised in PlayerDataConfig.AdminUserIds.
local _AdminCfg = require(SharedModules:WaitForChild("PlayerDataConfig"))

--- §AGX/SEC: §T0P2-ADMIN + X16 — the single admin guard (AdminTesting
--- uses it too). Always false outside Studio, so even a stray handler
--- can't grant anything in a live server. Inside Studio a player is
--- admin when they are:
---   • in PlayerDataConfig.AdminUserIds, or
---   • the owner of a USER-owned universe. X16: for a group-owned game
---     game.CreatorId is the GROUP id, so comparing it to a UserId both
---     locks the owner out and admits whoever's UserId equals the group id.
---   • a Studio local-server test account (Player1, Player2, … have
---     UserId <= 0; they only exist in Studio's "Start" test servers).
function PlaceBootstrap.IsAdmin(player)
    if not PlaceBootstrap.IS_STUDIO then return false end
    if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
    local userId = player.UserId
    if _AdminCfg.AdminUserIds and _AdminCfg.AdminUserIds[userId] == true then return true end
    if game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0
        and userId == game.CreatorId then
        return true
    end
    return userId <= 0
end

--- Build a per-place bootstrap context. The returned table exposes:
---   • loaded         — `[moduleName] = moduleTable` of every Load'd module
---   • Load(parent, name)    — pcall-require, runs Init() if present, returns the module
---   • RequireLoaded(name)   — hard-error if `name` isn't in `loaded`
---   • IsAdmin(player)        — Studio-only (§AGX/SEC)
---   • IsStudio               — gate for every admin/debug remote (§AGX/SEC)
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
        IsStudio      = PlaceBootstrap.IS_STUDIO,  -- §AGX/SEC: gate DebugCommand wiring
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
        -- must not crash the whole place boot on the `result.Init` index.
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
