-- ServerScriptService/Modules/PlaceLifecycle
--[[
    PlaceLifecycle
    ==============
    Shared per-player lifecycle + ambient-loop helpers used by every
    place's Main server script.

    Before this module:
      • LaneDefense + HordeMode + CentralBoss + SocialPlaza + Lobby all had
        a near-identical OnPlayerReady callback (~30 lines each).
      • LaneDefense + HordeMode + CentralBoss all had a near-identical
        Vitals broadcast + HP regen loop pair (~80 lines each).
      • Drift between them caused real bugs (Lane and CentralBoss got out
        of sync on multiple audits — §LD3, §CB3, §LD-RG1, §VG1, ...).

    After this module:
      • Common steps live here once.
      • Each place declares only its place-specific extras via a callback.

    Public API:
      PlaceLifecycle.WireOnPlayerReady(ctx, opts)
          opts.extras            — function(player, ctx) ... — place-specific steps
          opts.fireServerReady   — default true; fires the per-player
                                    "ServerReady" event at the end of the
                                    callback so the client knows it can
                                    start asking for state
          opts.onMissingDataAPI  — function(ctx, onReady) — fallback hook
                                    used if PlayerDataManager.OnPlayerDataReady
                                    is missing (shouldn't happen post v0.5)

      PlaceLifecycle.StartVitalsLoop(ctx, opts)
          opts.vitalsInterval  — broadcast cadence (default 1 s)
          opts.regenInterval   — regen tick cadence (default 1 s)

    Both depend only on the bootstrap context built by PlaceBootstrap.
]]

local PlaceLifecycle = {}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ═══════════════════════════════════════════════════════════
-- ON PLAYER READY
-- ═══════════════════════════════════════════════════════════

--- Wire the per-player "data is ready" callback chain. Always-applied
--- steps (in order):
---   1. Apply class innate bonuses
---   2. Initialise talent tree + send state to client
---   3. Re-apply equipped accessory bonuses
---   4. Push fresh StatsUpdate to client
---   5. opts.extras(player, ctx)  — place-specific
---   6. Fire ServerReady to client  (unless opts.fireServerReady == false)
function PlaceLifecycle.WireOnPlayerReady(ctx, opts)
    opts = opts or {}
    local DataManager    = ctx.RequireLoaded("PlayerDataManager")
    local NetworkManager = ctx.RequireLoaded("NetworkManager")

    local function onReady(player)
        if not player or not player.Parent then return end

        local data = DataManager.GetData(player)
        if not data then
            warn(string.format("[%s] OnPlayerReady fired with no data for %s",
                ctx.placeName, player.Name))
            return
        end

        -- 1. Class innate bonuses
        local ClassManager = ctx.loaded["ClassManager"]
        if ClassManager and ClassManager.ApplyInnateBonus then
            ClassManager.ApplyInnateBonus(player)
        end

        -- 2. Talent tree
        local TalentManager = ctx.loaded["TalentManager"]
        if TalentManager then
            if TalentManager.SetupPlayer then TalentManager.SetupPlayer(player) end
            if TalentManager.SendState   then TalentManager.SendState(player)   end
        end

        -- 3. Accessory bonuses
        local InventoryManager = ctx.loaded["InventoryManager"]
        if InventoryManager and InventoryManager.SetupPlayer then
            InventoryManager.SetupPlayer(player)
        end

        -- 4. Stats payload
        local SEH = ctx.loaded["SharedEventHandlers"]
        if SEH and SEH.PushStatsUpdate then
            SEH.PushStatsUpdate(player)
        end

        -- 5. Place-specific extras (e.g. TeleportDataReader.ProcessPlayer,
        --    DefenseLine.SendStateToPlayer, etc.)
        if opts.extras then
            local extrasOk, extrasErr = pcall(opts.extras, player, ctx)
            if not extrasOk then
                warn(string.format("[%s] OnPlayerReady extras errored for %s: %s",
                    ctx.placeName, player.Name, tostring(extrasErr)))
            end
        end

        -- 6. ServerReady signal
        if opts.fireServerReady ~= false then
            NetworkManager.FireClient(player, "ServerReady")
        end
    end

    -- Idempotency latch so the "register + scan-existing" pair below can't
    -- double-fire for the same player. The PlayerDataManager contract on
    -- OnPlayerDataReady says callbacks must be idempotent, but we still
    -- guard here so a deliberate double-trigger only does work once.
    local _onReadyFired = setmetatable({}, { __mode = "k" })
    local function fireOnce(player)
        if _onReadyFired[player] then return end
        _onReadyFired[player] = true
        onReady(player)
    end

    if DataManager.OnPlayerDataReady then
        DataManager.OnPlayerDataReady(fireOnce)
        -- Studio-race cover: if the server already loaded a player's data
        -- before this listener registered (common when running Studio with
        -- a dev player already in the session), the OnPlayerDataReady
        -- callback list was empty when SetupPlayer fired. Sweep existing
        -- players whose data is ready and trigger onReady for them.
        for _, player in ipairs(Players:GetPlayers()) do
            if DataManager.GetData(player) then
                task.spawn(fireOnce, player)
            end
        end
    elseif opts.onMissingDataAPI then
        opts.onMissingDataAPI(ctx, onReady)
    else
        -- Defensive fallback: poll for data, then fire. Shouldn't run in
        -- v0.5 since OnPlayerDataReady is always present, but we keep it
        -- as a belt-and-suspenders.
        warn(string.format("[%s] PlayerDataManager.OnPlayerDataReady missing — falling back to polling",
            ctx.placeName))
        local function pollPlayerReady(player)
            local data
            for _ = 1, 20 do
                data = DataManager.GetData(player)
                if data then break end
                task.wait(0.5)
            end
            if data then onReady(player) end
        end
        for _, player in ipairs(Players:GetPlayers()) do
            task.spawn(pollPlayerReady, player)
        end
        Players.PlayerAdded:Connect(function(player)
            task.spawn(pollPlayerReady, player)
        end)
    end
end

-- ═══════════════════════════════════════════════════════════
-- VITALS + HP REGEN LOOPS
-- ═══════════════════════════════════════════════════════════

local _GearRating = nil
local function getGearRating()
    if _GearRating then return _GearRating end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GearRating"))
    end)
    if ok then _GearRating = mod end
    return _GearRating
end

--- Spawn the two ambient loops every combat place needs:
---   • REGEN: HP regen tick (gated on Alive state + vote-not-active)
---   • BROADCAST: VitalsUpdate fan-out to all clients (read-only)
---
--- Both loops auto-skip during votes (§VG1) and for knocked-down / dead
--- players (§LD-RG1). Both use 1 s cadence by default — tunable via opts.
function PlaceLifecycle.StartVitalsLoop(ctx, opts)
    opts = opts or {}
    local VITALS_INTERVAL = opts.vitalsInterval or 1
    local REGEN_INTERVAL  = opts.regenInterval  or 1

    local NetworkManager = ctx.RequireLoaded("NetworkManager")
    local DataManager    = ctx.RequireLoaded("PlayerDataManager")
    local StatsManager   = ctx.RequireLoaded("StatsManager")

    -- §LD-RG1: regen loop independent of broadcast. Gates on Alive state
    -- so a knocked-down player doesn't fight DeathSystem's HP-pin
    -- heartbeat. §VG1: paused during votes.
    task.spawn(function()
        while true do
            task.wait(REGEN_INTERVAL)

            local vm = ctx.loaded["VoteManager"]
            if vm and vm.IsVoteActive and vm.IsVoteActive() then
                continue
            end

            for _, p in ipairs(Players:GetPlayers()) do
                local deathState = p:GetAttribute("DeathState")
                if deathState == "KnockedDown" or deathState == "Dead" then
                    continue
                end

                local maxHp = StatsManager.GetTotalHealth(p) or 100
                local char = p.Character
                local humanoid = char and char:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 and humanoid.Health < maxHp then
                    local regenPct  = DataManager.GetTotalStat(p, "HpRegen") or 0.5
                    local regenFlat = DataManager.GetTotalStat(p, "FlatHpRegen") or 0
                    humanoid.Health = math.min(
                        humanoid.Health + maxHp * (regenPct / 100) * REGEN_INTERVAL + regenFlat * REGEN_INTERVAL,
                        maxHp
                    )
                end
            end
        end
    end)

    -- §HUD-HP1: cosmetic 0 HP when knocked-down / dead (engine pins HP=1).
    -- §LD4: GearRating hoisted out of the broadcast loop.
    local gr = getGearRating()

    task.spawn(function()
        while true do
            task.wait(VITALS_INTERVAL)

            local allPlayers = Players:GetPlayers()
            if #allPlayers == 0 then continue end

            local vitals = {}
            for _, p in ipairs(allPlayers) do
                local maxHp = StatsManager.GetTotalHealth(p) or 100
                local char = p.Character
                local humanoid = char and char:FindFirstChildOfClass("Humanoid")

                local hp
                if p:GetAttribute("DeathState") ~= "Alive" then
                    hp = 0
                else
                    hp = humanoid and math.floor(humanoid.Health) or maxHp
                end

                local data = DataManager.GetData(p)
                vitals[tostring(p.UserId)] = {
                    name       = p.Name,
                    hp         = hp,
                    maxHp      = maxHp,
                    class      = data and data.ActiveClass or "Aegis",
                    level      = data and data.Account and data.Account.Level or 1,
                    powerLevel = (gr and data) and gr.GetDisplayPower(data) or 0,
                }
            end

            NetworkManager.FireAllClients("VitalsUpdate", vitals)
        end
    end)
end

return PlaceLifecycle
