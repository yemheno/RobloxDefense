-- hordemode/ServerScriptService/Modules/HordeModeSpawner.lua
--[[
    HordeModeSpawner
    ────────────────
    Manages player-following spawn markers and infinite mob spawning
    for HordeMode.

    Design:
      • Each player gets NUM_SPAWNERS spawn markers (neon-red Parts),
        positioned at fixed orbit angles around the player.
      • Markers update their CFrame every Heartbeat to follow their player.
      • The spawner cycles through the markers each spawn interval,
        chooses a marker whose position is at least MIN_SPAWN_DIST from
        ALL living players, then drops a mob there.
      • A global mob cap (MAX_ALIVE_MOBS) prevents performance collapse.
      • Mob level climbs automatically over time (LEVEL_TICK_INTERVAL).

    Configuration block at the top — safe to tune without touching logic.
]]

local HordeModeSpawner = {}

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Late-injected via HordeModeSpawner.Setup(mobAI, mobRegistry)
local MobAI      = nil
local MobRegistry = nil

-- RunModifiers (lazy-loaded on first spawn)
local RunModifiers      = nil
local runModifiersLoaded = false

local function getRunModifiers()
	if not runModifiersLoaded then
		runModifiersLoaded = true
		local shared = game:GetService("ServerScriptService"):FindFirstChild("Modules")
		local rm = shared and shared:FindFirstChild("RunModifiers")
		if rm then RunModifiers = require(rm) end
	end
	return RunModifiers
end

-- Difficulty overrides (stacked: mode × difficulty tier).
-- Base values are read from GameModeConfig so there's a single source of truth;
-- SetDifficulty() multiplies the chosen tier on top.
local GameModeConfig = require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("GameModeConfig"))
local MobSpawnHelper = require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("MobSpawnHelper"))  -- §T3/W9
local _hordeModeCfg  = GameModeConfig.GetMode("HordeMode")
local _baseMobMults  = _hordeModeCfg and _hordeModeCfg.mobMultipliers or {}

local activeDifficultyOverrides = {
    hpMult     = _baseMobMults.hpMult     or 0.60,
    damageMult = _baseMobMults.damageMult or 0.85,
    armorMult  = _baseMobMults.armorMult  or 0.80,
    speedBonus = 0,
}

-- ─────────────────────────────────────────────────────────────────────
-- CONFIGURATION  (tune freely)
-- ─────────────────────────────────────────────────────────────────────
local CFG = {
    -- Number of spawn markers orbiting each player
    -- §HMS-DIR1: 8 spawn markers per player (was 4) so direction
    -- granularity is 45° instead of 90°. Combined with velocity-
    -- biased pick below this lets us spawn closer to the player's
    -- movement vector.
    NUM_SPAWNERS    = 8,

    -- Orbit radius (studs) — how far from the player the markers sit
    ORBIT_RADIUS    = 42,

    -- Minimum studs a spawn marker must be from ANY living player before
    -- a mob is allowed to spawn there (prevents mobs appearing on top of players)
    MIN_SPAWN_DIST  = 27,
    -- §HMS-DIR2: "in another player's face" radius. A marker whose
    -- position falls within this distance of ANY other player gets
    -- weight=0 in the velocity-biased draw. Larger than MIN_SPAWN_DIST
    -- on purpose: we want to actively avoid spawning near them, not
    -- just barely satisfy the safety check.
    OTHER_PLAYER_AVOID_DIST = 35,

    -- Height above the ground plane to place spawned mobs
    SPAWN_Y_OFFSET  = 3,

    -- Marker appearance
    MARKER_COLOR    = Color3.fromRGB(255, 30, 30),   -- Neon red
    MARKER_SIZE     = Vector3.new(2, 2, 2),
    MARKER_TRANSPARENCY = 1,           -- fully invisible

    -- Starting mob level (overridden by SetPartyAnchorLevel at runtime)
    START_LEVEL     = 1,

    -- How often (seconds) the mob level increments automatically
    LEVEL_TICK_INTERVAL = 75,

    -- Default auto-growth ceiling (overridden to anchorLevel+8 when party is anchored)
    MAX_AUTO_LEVEL  = 30,
}

-- ─────────────────────────────────────────────────────────────────────
-- PHASE TABLE  (Hard-difficulty baseline)
-- Phases are evaluated by elapsed seconds since Start().
-- The last phase repeats indefinitely.
-- ─────────────────────────────────────────────────────────────────────
-- Weights: Zombie-only phase 1 → Trolls added phase 2 → Ogres added phase 3.
-- Miniboss share: 0% → ~4% → ~10%  (vs old flat 23.1%)
local PHASES = {
    -- 0:00 – 4:00  pure Zombies, forgiving ramp
    { afterSeconds = 0,   interval = 3.2, aliveCap = 40, weights = { Zombie = 1 },                       speedMult = 1.6  },
    -- 4:00 – 7:00  Trolls introduced, density rises
    { afterSeconds = 240, interval = 2.7, aliveCap = 56, weights = { Zombie = 24, Troll = 1 },            speedMult = 1.75 },
    -- 7:00+        Ogres appear, full pressure
    { afterSeconds = 420, interval = 2.3, aliveCap = 72, weights = { Zombie = 18, Troll = 1, Ogre = 1 },  speedMult = 1.9  },
}

-- ─────────────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────────────────────────────
local running          = false
local currentLevel     = CFG.START_LEVEL
local rewardLevel      = nil             -- fixed at run start for XP delta; nil = use currentLevel
local sessionStartTime = 0                -- set when Start() is first called
local maxAutoLevel     = CFG.MAX_AUTO_LEVEL  -- dynamic cap; overridden by SetPartyAnchorLevel()
local levelTickGeneration = 0              -- bumped on each Start() to kill stale tick loops

-- playerSpawners[player] = { markers = {Part,...}, nextIndex = 1, heartbeatConn, spawnThread }
local playerSpawners = {}

local heartbeatConn      = nil   -- single shared Heartbeat for all marker movement
local playerAddedConn    = nil   -- reusable PlayerAdded connection
local playerRemovingConn = nil   -- reusable PlayerRemoving connection

-- ─────────────────────────────────────────────────────────────────────
-- PHASE HELPER
-- ─────────────────────────────────────────────────────────────────────

--- Returns the active PHASES entry based on elapsed session time.
local function getPhase()
    local elapsed = os.clock() - sessionStartTime
    local active  = PHASES[1]
    for _, p in ipairs(PHASES) do
        if elapsed >= p.afterSeconds then
            active = p
        end
    end
    return active
end

-- ─────────────────────────────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────────────────────────────

--- Weighted random pick from the current phase's weight table
--- §T3/W9: delegates to the shared helper (was a verbatim copy of
--- MobSpawner.GetRandomMobId's algorithm).
local function pickMobId()
    return MobSpawnHelper.PickWeightedId(getPhase().weights)
end

--- Returns true if `pos` is at least MIN_SPAWN_DIST from every living player.
local function isSafeSpawnPosition(pos)
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local d = (hrp.Position - pos).Magnitude
            if d < CFG.MIN_SPAWN_DIST then
                return false
            end
        end
    end
    return true
end

--- Build the four orbit offsets (evenly spread around the player, flat).
--- Returns a table of Vector3 offsets; index 1–NUM_SPAWNERS.
local function buildOrbitOffsets()
    local offsets = {}
    for i = 1, CFG.NUM_SPAWNERS do
        local angle = (2 * math.pi / CFG.NUM_SPAWNERS) * (i - 1)
        offsets[i] = Vector3.new(
            math.cos(angle) * CFG.ORBIT_RADIUS,
            0,
            math.sin(angle) * CFG.ORBIT_RADIUS
        )
    end
    return offsets
end

--- Create one neon-red marker Part in the workspace.
local function createMarkerPart(name)
    local part = Instance.new("Part")
    part.Name         = name
    part.Size         = CFG.MARKER_SIZE
    part.Color        = CFG.MARKER_COLOR
    part.Material     = Enum.Material.Neon
    part.Transparency = CFG.MARKER_TRANSPARENCY
    part.Anchored     = true
    part.CanCollide   = false
    part.CanQuery     = false
    part.CastShadow   = false
    part.Parent       = workspace
    return part
end

--- Spawn a single mob at a CFrame position using MobAI + MobRegistry directly.
--- Returns the spawned mob Model or nil.
local function spawnMobAt(spawnCFrame)
    if not MobAI or not MobRegistry then return nil end

    local rm = getRunModifiers()

    -- Cap check (phase-based alive limit, scaled by normalMobCountScalar)
    local baseCap = getPhase().aliveCap
    if rm then
        baseCap = math.ceil(baseCap * (1 + rm.GetModifier("normalMobCountScalar")))
    end
    if MobAI.GetActiveMobCount() >= baseCap then
        return nil
    end

    -- Check for extra-miniboss charge before normal pick
    local mobId
    if rm and rm.ConsumeMinibossCharge() then
        -- Force an elite spawn; pick a heavier mob type if available
        local weights = getPhase().weights
        if weights.Ogre then mobId = "Ogre"
        elseif weights.Troll then mobId = "Troll"
        else mobId = pickMobId() end
    else
        mobId = pickMobId()
    end

    -- §HMS2: use the Mobs folder cached at Setup. We hard-errored at
    -- Setup if it was missing, so this read is guaranteed live.
    local mobsFolder = HordeModeSpawner._mobsFolder
    if not mobsFolder then
        -- Defensive: should be impossible given the Setup-time hard-error.
        error("[HordeModeSpawner] _mobsFolder cache is nil — Setup() never ran or failed silently.", 2)
    end

    -- Build effective overrides: base difficulty × RunModifiers scalars
    local effectiveOverrides = activeDifficultyOverrides
    if rm then
        local hpS = rm.GetModifier("hpScalar")
        local dmgS = rm.GetModifier("damageScalar")
        local armS = rm.GetModifier("armorFlatBonus")
        if hpS ~= 0 or dmgS ~= 0 or armS ~= 0 then
            effectiveOverrides = {
                hpMult     = activeDifficultyOverrides.hpMult     * (1 + hpS),
                damageMult = activeDifficultyOverrides.damageMult * (1 + dmgS),
                armorMult  = activeDifficultyOverrides.armorMult,
                speedBonus = activeDifficultyOverrides.speedBonus,
                armorFlatBonus = armS,
            }
        end
    end

    local mobData = MobRegistry.GetScaledMob(mobId, currentLevel, effectiveOverrides)
    if not mobData then
        warn("[HordeModeSpawner] Unknown mobId:", mobId)
        return nil
    end

    local templateName = mobData.template or "MobTemplate"
    local template = mobsFolder:FindFirstChild(templateName)
    if not template then
        warn("[HordeModeSpawner] Missing template:", templateName, "in ReplicatedStorage.Mobs")
        return nil
    end

    -- §HMS1: Clone() MUST succeed every time. Per the design, a missed
    -- spawn would create a gameplay gap (and possibly an exploit window
    -- where players could "starve" the spawner). We pcall with infinite
    -- retry + exponential backoff capped at 1s. If Clone is failing
    -- repeatedly, that's an environmental issue (corrupted template,
    -- memory pressure) — we still keep trying because a permanently
    -- silent spawner is worse than a delayed one. The retry yields, so
    -- the per-player spawn loop's task.wait timing is preserved on the
    -- happy path; only failures incur extra wait.
    -- §T3/W9a: shared never-fail clone (this module's semantics won —
    -- retry forever with backoff, abort only when the spawner stops).
    local mob = MobSpawnHelper.CloneTemplate(template, mobId, "[HordeModeSpawner]",
        function() return not running end)
    if not mob then return nil end

    mob.Name = mobData.name or mobId
    mob:SetAttribute("IsMob", true)
    mob:SetAttribute("MobId", mobId)
    mob:SetAttribute("MobTier", mobData.mobTier or "normal")
    mob:SetAttribute("Level", currentLevel)
    mob:SetAttribute("RewardLevel", rewardLevel or currentLevel)
    mob:SetAttribute("MobElement", mobData.element or "None")
    mob:SetAttribute("Armor", mobData.armor or 0)

    local humanoid = mob:FindFirstChild("Humanoid")
    if humanoid then
        humanoid.MaxHealth = mobData.health
        humanoid.Health    = mobData.health
    end

    -- Parent first so the physics assembly is established,
    -- then PivotTo so all parts move relative to PrimaryPart.
    mob.Parent = workspace
    mob:PivotTo(spawnCFrame)

    -- Register with MobAI; speed override applied via SPEED_MULT after registration
    local registeredData = MobAI.RegisterMob(mob, mobId, currentLevel)

    if registeredData and humanoid then
        -- Apply phase-based speed boost + RunModifiers speedScalar
        local speedMult = getPhase().speedMult
        if rm then
            speedMult = speedMult * (1 + rm.GetModifier("speedScalar"))
        end
        local finalSpeed = math.max(humanoid.WalkSpeed, mobData.speed * speedMult)
        humanoid.WalkSpeed = finalSpeed
        -- Record as this mob's base speed so speed escalation can scale from it
        registeredData.baseSpeed = finalSpeed
    end

    return mob
end

-- ─────────────────────────────────────────────────────────────────────
-- PER-PLAYER SPAWNER LIFECYCLE
-- ─────────────────────────────────────────────────────────────────────

local ORBIT_OFFSETS = buildOrbitOffsets()

-- §MEM/M5: hoisted — was rebuilt per marker per Heartbeat
-- (8 markers × N players × 60 Hz of identical Vector3.new allocations).
local SPAWN_Y_VEC = Vector3.new(0, CFG.SPAWN_Y_OFFSET, 0)

-- §AGX/X1: forward-declared — createPlayerSpawner's spawn loop calls it,
-- but the definition lives further down (§SCALE/S1). Without this the
-- calls resolved to a nil global and every spawner thread died on tick 1.
local positionMarkers

local function createPlayerSpawner(player)
    if playerSpawners[player] then return end   -- guard

    -- Build marker Parts
    local markers = {}
    for i = 1, CFG.NUM_SPAWNERS do
        local marker = createMarkerPart("HordeSpawnMarker_" .. player.Name .. "_" .. i)
        markers[i] = marker
    end

    local spawnerData = {
        markers   = markers,
        nextIndex = 1,
        -- §HMS1 spawn-rate accounting:
        -- spawnDebt = number of intervals where we couldn't place a mob
        -- (party clustering meant every marker was within MIN_SPAWN_DIST).
        -- The next intervals consume this debt by spawning extra mobs
        -- (still subject to the safety check) so the long-term mobs/
        -- minute rate stays consistent regardless of party movement.
        -- Capped at MAX_SPAWN_DEBT so we don't drop a wall of mobs after
        -- a long stationary fight.
        spawnDebt = 0,
    }
    playerSpawners[player] = spawnerData

    local MAX_SPAWN_DEBT = 5  -- cap; spec: consistent rate, not punishing burst

    -- Per-player infinite spawn loop
    local spawnThread = task.spawn(function()
        while running and player.Parent do
            local interval = getPhase().interval
            local rm = getRunModifiers()
            if rm then
                interval = interval * (1 + rm.GetModifier("spawnIntervalScalar"))
            end
            task.wait(math.max(0.5, interval))
            if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then continue end

            -- §HMS1: how many spawns to attempt this tick:
            --   1 (the regular one) + min(spawnDebt, MAX_SPAWN_DEBT)
            -- Each attempt that fails to find a safe position re-adds to
            -- the debt; each successful spawn reduces remaining attempts.
            local attempts = 1 + math.min(spawnerData.spawnDebt, MAX_SPAWN_DEBT)
            local spawnedThisTick = 0

            -- §HMS-DIR1: build a velocity-weighted picking order.
            -- If the player is moving, markers in the direction of
            -- their velocity get higher weight — they're more likely
            -- to spawn the next mob. Stationary players see uniform
            -- random picks (so camping doesn't reveal a quiet zone).
            -- The weight curve: dot(unitVelocity, unitOffset) maps to
            -- [-1..1]; we shift to [0.1..1.9] so even back markers
            -- have non-zero chance (otherwise a moving player would
            -- never see anything from behind, which feels exploit-
            -- able for circle-strafing).
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            -- §SCALE/S1: markers follow the player on demand (spawn tick),
            -- not per Heartbeat.
            if hrp then
                positionMarkers(spawnerData, hrp.Position)
            end
            local vel = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
            local flatVel = Vector3.new(vel.X, 0, vel.Z)
            local moving = flatVel.Magnitude > 4   -- stud/s threshold
            local velDir = moving and flatVel.Unit or nil

            local function pickMarkerOrder()
                -- Returns an array of marker indices in randomized,
                -- velocity-weighted order. Each call rebuilds it so
                -- successive picks (when one fails the safety check)
                -- come from a fresh weighted draw.
                --
                -- §HMS-DIR2: markers within OTHER_PLAYER_AVOID_DIST of
                -- ANY other player are weighted to 0 — they don't compete
                -- in the draw at all. Otherwise a clustered party would
                -- have Player A's spawner pick a forward marker that
                -- happens to spawn directly into Player B, even though
                -- the marker is technically "a valid spawn for A".
                -- The isSafeSpawnPosition check below is still the
                -- final safety net for markers that pass weight > 0.
                local selfHrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                local weights = {}
                local totalW = 0
                for i = 1, CFG.NUM_SPAWNERS do
                    local off = ORBIT_OFFSETS[i]
                    local w
                    if velDir then
                        local d = (off.Unit):Dot(velDir)  -- [-1..1]
                        w = 0.1 + (d + 1) * 0.9            -- [0.1..1.9]
                    else
                        w = 1                              -- uniform
                    end
                    -- §HMS-DIR2: zero markers near other players. The
                    -- marker position is computed from the spawner's
                    -- live position (player HRP) plus the orbit offset.
                    if selfHrp and w > 0 then
                        local markerPos = selfHrp.Position + off
                        for _, other in ipairs(Players:GetPlayers()) do
                            if other ~= player then
                                local oc = other.Character
                                local oh = oc and oc:FindFirstChild("HumanoidRootPart")
                                if oh and (oh.Position - markerPos).Magnitude < CFG.OTHER_PLAYER_AVOID_DIST then
                                    w = 0
                                    break
                                end
                            end
                        end
                    end
                    weights[i] = w
                    totalW = totalW + w
                end
                -- §HMS-DIR3: if EVERY marker is zeroed (party fully
                -- envelops this player's orbit — 8 markers makes this
                -- nearly impossible but "nearly" isn't "never" at 1 B
                -- players, especially with elite spawns we don't want
                -- to drop), DON'T fall back to uniform on our own
                -- markers. The outer loop will try ally markers instead.
                if totalW <= 0 then
                    return {}  -- empty order → outer loop falls through
                end
                -- Weighted-random sampling without replacement
                local order = {}
                local remaining = {}
                for i = 1, CFG.NUM_SPAWNERS do remaining[i] = i end
                while #remaining > 0 do
                    local r = math.random() * totalW
                    local acc = 0
                    local pickedAt = 1
                    for k, idx in ipairs(remaining) do
                        acc = acc + weights[idx]
                        if r <= acc then pickedAt = k; break end
                    end
                    local idx = remaining[pickedAt]
                    table.insert(order, idx)
                    totalW = totalW - weights[idx]
                    table.remove(remaining, pickedAt)
                end
                return order
            end

            for attemptN = 1, attempts do
                -- Walk the velocity-weighted order until we find a safe spot.
                local placedThisAttempt = false
                local order = pickMarkerOrder()
                for _, idx in ipairs(order) do

                    local marker = markers[idx]
                    if not marker or not marker.Parent then continue end

                    local spawnPos = marker.Position
                    if isSafeSpawnPosition(spawnPos) then
                        -- §T3/W9b: uniform scatter across the marker part
                        -- (was the exact marker point). Resize markers in
                        -- Studio to widen the area. Keeps the §LD-MS1
                        -- 3-stud ground-clip lift.
                        local spawnCFrame = MobSpawnHelper.GetSpawnCFrame(marker, 3)
                        local mob = spawnMobAt(spawnCFrame)
                        if mob then
                            spawnedThisTick = spawnedThisTick + 1
                            placedThisAttempt = true
                            -- Consume one debt unit if we just paid one back.
                            if attemptN > 1 and spawnerData.spawnDebt > 0 then
                                spawnerData.spawnDebt = spawnerData.spawnDebt - 1
                            end
                        end
                        break   -- one mob per attempt
                    end
                end
                if not placedThisAttempt then
                    -- §HMS-DIR3: own-marker pick failed (orbit blocked).
                    -- Try teammate markers as a fallback. We collect every
                    -- marker from every OTHER player's spawner that still
                    -- passes isSafeSpawnPosition, then random-pick one.
                    -- Velocity-bias is intentionally dropped here — we're
                    -- already making the best of a degenerate cluster, no
                    -- need to overcomplicate the fallback.
                    local viable = {}
                    for ally, allySpawnerData in pairs(playerSpawners) do
                        if ally ~= player and ally.Parent and allySpawnerData and allySpawnerData.markers then
                            -- §SCALE/S1: refresh the ally's markers on demand
                            -- before testing them (they no longer follow via
                            -- Heartbeat). Rare path — only when own orbit is
                            -- fully blocked.
                            local allyChar = ally.Character
                            local allyHrp = allyChar and allyChar:FindFirstChild("HumanoidRootPart")
                            if allyHrp then
                                positionMarkers(allySpawnerData, allyHrp.Position)
                                for _, marker in ipairs(allySpawnerData.markers) do
                                    if marker and marker.Parent and isSafeSpawnPosition(marker.Position) then
                                        table.insert(viable, marker)  -- §T3/W9b: keep the part, not just its position
                                    end
                                end
                            end
                        end
                    end
                    if #viable > 0 then
                        -- §T3/W9b: uniform scatter across the picked marker part.
                        local spawnCFrame = MobSpawnHelper.GetSpawnCFrame(viable[math.random(#viable)], 3)
                        local mob = spawnMobAt(spawnCFrame)
                        if mob then
                            spawnedThisTick = spawnedThisTick + 1
                            placedThisAttempt = true
                            if attemptN > 1 and spawnerData.spawnDebt > 0 then
                                spawnerData.spawnDebt = spawnerData.spawnDebt - 1
                            end
                        end
                    end
                end

                if not placedThisAttempt then
                    -- All own markers AND all ally markers blocked. Accept
                    -- the spawn debt and try again next tick. Only the
                    -- BASE attempt adds debt (catch-up attempts that fail
                    -- just stop trying this tick to avoid busy-looping).
                    if attemptN == 1 then
                        if spawnerData.spawnDebt < MAX_SPAWN_DEBT then
                            spawnerData.spawnDebt = spawnerData.spawnDebt + 1
                        end
                    end
                    break
                end
            end
        end
    end)

    spawnerData.spawnThread = spawnThread
end

local function destroyPlayerSpawner(player)
    local spawnerData = playerSpawners[player]
    if not spawnerData then return end

    -- Cancel spawn loop
    if spawnerData.spawnThread then
        task.cancel(spawnerData.spawnThread)
    end

    -- Destroy marker Parts
    for _, marker in ipairs(spawnerData.markers) do
        if marker and marker.Parent then
            marker:Destroy()
        end
    end

    playerSpawners[player] = nil
end

-- ─────────────────────────────────────────────────────────────────────
-- HEARTBEAT: move all markers to follow their players
-- ─────────────────────────────────────────────────────────────────────

-- §SCALE/S1: the old version moved every marker every Heartbeat —
-- 8 markers × P players × 60 Hz = 480·P anchored-Part position writes/s,
-- each REPLICATED to all clients (at P=30 that's ~240 invisible parts
-- streaming CFrame updates: ~100 KB/s of pure waste, plus 8·P extra
-- workspace-root children inflating every AttackShapes scan).
-- Markers are only READ at spawn time (once per ~2.5 s tick), so we
-- position them on demand instead. The Parts themselves stay — §T3/W9b:
-- Pablo resizes them in Studio to widen the scatter area.
function positionMarkers(spawnerData, basePos)
    for i, marker in ipairs(spawnerData.markers) do
        if marker and marker.Parent then
            marker.Position = basePos + ORBIT_OFFSETS[i] + SPAWN_Y_VEC
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────
-- LEVEL TICK
-- ─────────────────────────────────────────────────────────────────────

local function startLevelTick()
    -- Capture current generation so stale loops from a previous Start()
    -- exit cleanly instead of double-incrementing currentLevel.
    local gen = levelTickGeneration
    task.spawn(function()
        while running and gen == levelTickGeneration do
            task.wait(CFG.LEVEL_TICK_INTERVAL)
            if not running or gen ~= levelTickGeneration then break end
            if currentLevel < maxAutoLevel then
                currentLevel = currentLevel + 1
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────────────────────────────────

---Initialize the spawner. Call after MobAI and MobRegistry are loaded.
---@param mobAI       any  Loaded MobAI module
---@param mobRegistry any  Loaded MobRegistry module
function HordeModeSpawner.Setup(mobAI, mobRegistry)
    MobAI      = mobAI
    MobRegistry = mobRegistry

    -- §HMS2: cache the Mobs folder reference at Setup. The previous
    -- per-spawn FindFirstChild was (a) wasted lookups on every spawn and
    -- (b) hid load-order bugs because it re-checked instead of asserting.
    -- We hard-error if the folder is missing because spawning without
    -- templates is unrecoverable for this place — HordeModeMapLoader
    -- always runs before this.
    local mobsFolder = ReplicatedStorage:WaitForChild("Mobs", 10)
    if not mobsFolder then
        error("[HordeModeSpawner] ReplicatedStorage/Mobs not found after 10s — " ..
            "HordeModeMapLoader must populate it before HordeModeSpawner.Setup. " ..
            "Cannot continue without templates.", 2)
    end
    HordeModeSpawner._mobsFolder = mobsFolder

end

---Start spawning — creates spawners for all current players and
---subscribes to future joins/leaves.
function HordeModeSpawner.Start()
    if running then return end
    running = true

    -- Only initialise session clock and level on the very first Start().
    -- Subsequent Start() calls (e.g. pause→resume) continue from where they left off.
    if sessionStartTime == 0 then
        sessionStartTime = os.clock()
        currentLevel     = CFG.START_LEVEL
        maxAutoLevel     = CFG.MAX_AUTO_LEVEL
    end

    -- Kill any stale level-tick loop from a previous Start() before spawning a new one
    levelTickGeneration = levelTickGeneration + 1

    -- §SCALE/S1: marker-follow Heartbeat removed — markers are positioned
    -- on demand inside each spawn tick.
    startLevelTick()

    -- §FRENZY1: speed escalation is now PER MOB and lives in MobAI.Update.
    -- Each mob accelerates from its own spawn time (10 s grace, +5 % every
    -- 5 s, capped at +60 %) so killing the old wave returns to base speed
    -- without punishing the player. The old global session-time multiplier
    -- is intentionally removed — having two competing speed systems would
    -- compound multipliers in surprising ways.

    -- Connect PlayerAdded / PlayerRemoving only once (guard against pause→resume leak)
    if not playerAddedConn then
        playerAddedConn = Players.PlayerAdded:Connect(function(player)
            if running then
                task.spawn(function()
                    -- §AGX/X38: bounded wait — a bare CharacterAdded:Wait()
                    -- never returned if the player left first (thread leak).
                    if not player.Character then
                        local timeout = os.clock() + 60
                        repeat task.wait(0.25)
                        until player.Character or not player.Parent or os.clock() > timeout
                    end
                    if not player.Character then return end
                    task.wait(1) -- brief settle time
                    -- §HMS4: re-check `running` after the settle wait.
                    -- Stop() may have fired during that 1s window; without
                    -- this guard we would create a stranded spawner that
                    -- the next Start() would fail to overwrite.
                    if not running then return end
                    if not player.Parent then return end
                    createPlayerSpawner(player)
                end)
            end
        end)
    end

    if not playerRemovingConn then
        playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
            destroyPlayerSpawner(player)
        end)
    end

    -- Create spawners for any players already in the game
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            createPlayerSpawner(player)
        else
            task.spawn(function()
                -- §AGX/X38: bounded wait (see PlayerAdded path above).
                local timeout = os.clock() + 60
                repeat task.wait(0.25)
                until player.Character or not player.Parent or os.clock() > timeout
                if not player.Character then return end
                task.wait(1)
                if running and player.Parent then
                    createPlayerSpawner(player)
                end
            end)
        end
    end


end

---Stop all spawning and clean up every spawner + marker.
function HordeModeSpawner.Stop()
    running = false

    -- Reset speed escalation so mobs don't retain boosted speeds after the session
    if MobAI then
        MobAI.SetHordeGlobalSpeedMult(1.0)
    end

    if heartbeatConn then  -- §SCALE/S1: legacy guard, no longer connected
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end

    for player in pairs(playerSpawners) do
        destroyPlayerSpawner(player)
    end
end

---Apply a difficulty tier on top of the HordeMode base multipliers.
---@param tierName string  "Normal", "Hard", or "Nightmare"
function HordeModeSpawner.SetDifficulty(tierName)
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local dcMod  = shared and shared:FindFirstChild("DifficultyConfig")
    if not dcMod then
        warn("[HordeModeSpawner] DifficultyConfig not found")
        return
    end
    local DifficultyConfig = require(dcMod)
    if not DifficultyConfig.IsValid(tierName) then
        warn("[HordeModeSpawner] Invalid difficulty:", tierName)
        return
    end
    local diff = DifficultyConfig.GetDifficulty(tierName)
    -- Stack: HordeMode base × difficulty tier.
    -- §T3/W2: base multipliers come from GameModeConfig (_baseMobMults,
    -- cached at module load) — the old hardcoded 0.60/0.85/0.80 here
    -- silently diverged whenever GameModeConfig.mobMultipliers changed.
    activeDifficultyOverrides = {
        hpMult     = (_baseMobMults.hpMult     or 0.60) * diff.hpMult,
        damageMult = (_baseMobMults.damageMult or 0.85) * diff.damageMult,
        armorMult  = (_baseMobMults.armorMult  or 0.80) * diff.armorMult,
        speedBonus = diff.speedBonus or 0,
    }
    print("[HordeModeSpawner] Difficulty set to:", tierName,
        "| effective HP mult:", string.format("%.2f", activeDifficultyOverrides.hpMult))
end

---Force-set the current mob level (e.g. for admin testing).
function HordeModeSpawner.SetLevel(level)
    currentLevel = math.clamp(level, 1, maxAutoLevel)
end

---Returns the current mob level.
function HordeModeSpawner.GetLevel()
    return currentLevel
end

--- Anchor the starting mob level to the party's highest player level.
--- Auto-growth cap is set to anchorLevel+8 so the session stays inside
--- the useful XP delta band for a full 10-minute run.
--- RewardLevel is frozen here (min 5) for the entire run.
--- Must be called AFTER Setup() and BEFORE (or shortly after) Start().
function HordeModeSpawner.SetPartyAnchorLevel(level)
    level        = math.max(1, level or 1)
    currentLevel = level
    rewardLevel  = math.max(5, level)   -- frozen for XP delta; min 5 so lv1-10 all get full XP
    maxAutoLevel = level + 8
    -- Reset session clock so phases start fresh from this anchor
    if sessionStartTime ~= 0 then
        sessionStartTime = os.clock()
    end
    print("[HordeModeSpawner] Party anchor:", level, "| RewardLevel:", rewardLevel, "| Auto-growth cap:", maxAutoLevel)
end

---Returns the CFG table so server code can read/adjust settings at runtime.
function HordeModeSpawner.GetConfig()
    return CFG
end

return HordeModeSpawner
