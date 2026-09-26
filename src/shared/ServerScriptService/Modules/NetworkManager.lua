-- ServerScriptService/Modules/NetworkManager
--[[
    NetworkManager (server)
    =======================
    Centralised RemoteEvent factory + rate limiter.

    Why this exists
    ---------------
    The whole event surface is created from code (NOT in Studio) so that
    every event has one declarative source of truth and the modules can
    ship cleanly across places. Studio-authored events are easy to forget,
    impossible to lint, and silently differ between places. Code wins.

    The manifest (§NM-D4)
    ---------------------
    `EVENTS` below is the single declarative list of every RemoteEvent
    the game uses. Each entry carries:

      • rateLimit  — calls/sec/player allowed via OnClientEvent.
                     `nil`  → fall back to DEFAULT_LIMIT (30).
      • studioOnly — §AGX/SEC (§T0P2-ADMIN): the event exists ONLY in
                     Studio. Outside Studio it is never created (Init
                     skips it, GetEvent refuses it and returns nil), so
                     live servers expose no admin/debug remote at all.
      • readyGated — informational. `true` means the producer side should
                     fire it via ReadyGate.FireClient instead of plain
                     NetworkManager.FireClient. We don't auto-route
                     because that'd circular-require ReadyGate; the flag
                     is here so the manifest is self-documenting and a
                     future lint pass can catch drift.

    Adding a new event
    ------------------
    Append it to EVENTS with the right metadata. NetworkManager.Init will
    pre-register it before any client WaitForChild can race the server.
    No PRE_REGISTER list to forget.

    Rate-limit philosophy (§NM-D1)
    ------------------------------
    Combat is fast. A late-game Aegis swinging into a dense pack of mobs
    can legitimately fire ~50 PlayerHitReports/sec; a Hunter with a
    3-pierce + skill burst lands ~30. The old uniform 30/sec cap dropped
    legit hits and the player saw "I swung but no damage." Per-event
    limits sit on top of the AttackHandler ticket system (which already
    bounds maxHits-per-attack and per-target dedup), so even the higher
    caps still block exploit floods.

    Public API
    ----------
      NetworkManager.Init()
      NetworkManager.GetEvent(name)            – cached; creates if missing
      NetworkManager.FireClient(player, name, ...)
      NetworkManager.FireAllClients(name, ...)
      NetworkManager.OnClientEvent(name, callback)   – rate-limited
]]

local NetworkManager = {}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

-- §AGX/SEC: studioOnly manifest entries exist only when this is true.
local IS_STUDIO = RunService:IsStudio()

local eventsFolder = nil
local remoteEvents = {}

-- ─────────────────────────────────────────────────────────────────────
-- RATE LIMITER
-- ─────────────────────────────────────────────────────────────────────
-- Fixed 1 s window. Reset when window expires.
local RATE_WINDOW   = 1
local DEFAULT_LIMIT = 30

-- rateBuckets[eventName][player] = { count, start, lastAccess }
local rateBuckets   = {}
local BUCKET_CLEANUP_INTERVAL = 60
local BUCKET_MAX_AGE          = 60

-- ─────────────────────────────────────────────────────────────────────
-- EVENT MANIFEST  (§NM-D4)
-- ─────────────────────────────────────────────────────────────────────
-- Single declarative table. Each entry: rateLimit + readyGated.
-- Order matters only for legibility, not behavior.
local EVENTS = {
    -- ── Server lifecycle ─────────────────────────────────────────────
    ServerReady            = { rateLimit = nil,  readyGated = false },
    ClientReady            = { rateLimit = 2,    readyGated = false }, -- one per session, anti-spam

    -- ── Player data / info ───────────────────────────────────────────
    PlayerInfoUpdate       = { rateLimit = nil,  readyGated = false }, -- BYPASS in ReadyGate
    StatsUpdate            = { rateLimit = nil,  readyGated = false }, -- BYPASS in ReadyGate
    CurrencyUpdate         = { rateLimit = nil,  readyGated = false }, -- BYPASS in ReadyGate
    ResourceUpdate         = { rateLimit = nil,  readyGated = false }, -- BYPASS in ReadyGate
    VitalsUpdate           = { rateLimit = nil,  readyGated = false }, -- BYPASS in ReadyGate
    CharacterCreationRequired = { rateLimit = nil, readyGated = true },
    CharacterCreationSaved    = { rateLimit = nil, readyGated = false },
    ClassSwitchResult      = { rateLimit = nil,  readyGated = false },
    GetPlayerInfo          = { rateLimit = nil,  readyGated = false },
    GetStats               = { rateLimit = nil,  readyGated = false },
    RequestCharacterStatus = { rateLimit = nil,  readyGated = false },
    CharacterCreationComplete  = { rateLimit = nil, readyGated = false },
    UseAppearanceChange    = { rateLimit = 1,    readyGated = false }, -- §AGX/X18b: menu "Change appearance"; one tap spends a free token
    RequestClassSwitch     = { rateLimit = nil,  readyGated = false },
    AllocateStat           = { rateLimit = nil,  readyGated = false },

    -- ── Equipment ────────────────────────────────────────────────────
    -- EquipmentInfo is pure request/response (GetEquipmentInfo →
    -- EquipmentInfo); the client subscribes before firing the request,
    -- so no boot race. Not ready-gated.
    EquipmentInfo          = { rateLimit = nil,  readyGated = false },
    WeaponEquipped         = { rateLimit = nil,  readyGated = true  }, -- §NM-D2
    ArmorEquipped          = { rateLimit = nil,  readyGated = true  }, -- §NM-D2
    WeaponLevelUp          = { rateLimit = nil,  readyGated = false },
    WeaponXPGained         = { rateLimit = nil,  readyGated = false },
    WeaponRefinementResult = { rateLimit = nil,  readyGated = false },
    ArmorRefinementResult  = { rateLimit = nil,  readyGated = false },
    WeaponTierUp           = { rateLimit = nil,  readyGated = false },
    ArmorTierUp            = { rateLimit = nil,  readyGated = false },
    WeaponRerollResult     = { rateLimit = nil,  readyGated = false },
    ArmorRerollResult      = { rateLimit = nil,  readyGated = false },
    GetEquipmentInfo       = { rateLimit = nil,  readyGated = false },

    -- ── NPC ──────────────────────────────────────────────────────────
    NPCDialogue            = { rateLimit = nil,  readyGated = false },
    NPCQuestOffer          = { rateLimit = nil,  readyGated = false },
    NPCTeleportOffer       = { rateLimit = nil,  readyGated = false },
    NPCShopOpen            = { rateLimit = nil,  readyGated = false },
    NPCResponse            = { rateLimit = nil,  readyGated = false },
    NPCSmithOpen           = { rateLimit = nil,  readyGated = false },
    -- §SCALE/S6: menu-rate cap — each NPCInteract triggers server work;
    -- the 30/s default let one client force 900 handler runs/s at P=30.
    NPCInteract            = { rateLimit = 4,    readyGated = false },

    -- ── Talents & Skills ─────────────────────────────────────────────
    TalentStateUpdate      = { rateLimit = nil,  readyGated = true  }, -- TalentManager.SendState already migrated
    SkillActivated         = { rateLimit = nil,  readyGated = false }, -- caster-only since §AGX/X21, fast-path
    SkillVisual            = { rateLimit = nil,  readyGated = false },
    SkillCooldownUpdate    = { rateLimit = nil,  readyGated = false },
    SkillFailed            = { rateLimit = nil,  readyGated = false },
    SkillCastStarted       = { rateLimit = nil,  readyGated = false },
    SkillCastCompleted     = { rateLimit = nil,  readyGated = false },
    SkillCastInterrupted   = { rateLimit = nil,  readyGated = false },
    SkillRequest           = { rateLimit = 10,   readyGated = false }, -- skills don't fire fast; tight cap catches exploit
    BuffApplied            = { rateLimit = nil,  readyGated = false },
    BuffRemoved            = { rateLimit = nil,  readyGated = false },
    GetTalentState         = { rateLimit = nil,  readyGated = false },
    RespecTalents          = { rateLimit = nil,  readyGated = false },
    AllocateTalent         = { rateLimit = nil,  readyGated = false },
    RespecResult           = { rateLimit = nil,  readyGated = false },

    -- ── Combat (HOT PATH — high rate caps) ───────────────────────────
    AttackEvent            = { rateLimit = 60,   readyGated = false }, -- ~4/s peak Hunter; 15× headroom
    AttackFired            = { rateLimit = nil,  readyGated = false }, -- broadcast to others
    CombatConfig           = { rateLimit = nil,  readyGated = false }, -- request-driven, retry loop on client
    RequestCombatConfig    = { rateLimit = nil,  readyGated = false },
    PlayerHitReport        = { rateLimit = 250,  readyGated = false }, -- ~50/s peak Aegis AoE; 5× headroom
    DamageNumber           = { rateLimit = nil,  readyGated = false },
    -- §PERF/F5: Tibia-style 0.1 s damage-number batching (array payload).
    DamageNumberBatch      = { rateLimit = nil,  readyGated = false },
    -- §SCALE/S5: batched DoT/HoT number windows (array payloads).
    HealNumberBatch        = { rateLimit = nil,  readyGated = false },

    -- ── Mob events ───────────────────────────────────────────────────
    MobSkillCast           = { rateLimit = nil,  readyGated = false },
    MobSkillHit            = { rateLimit = nil,  readyGated = false },
    MobSkillHitReport      = { rateLimit = 250,  readyGated = false }, -- mirror of PlayerHitReport
    MobBasicAttackHitReport= { rateLimit = 250,  readyGated = false },
    MobBasicAttackCast     = { rateLimit = nil,  readyGated = false },
    LootDrop               = { rateLimit = nil,  readyGated = false },
    MobDeath               = { rateLimit = nil,  readyGated = false },

    -- ── Combo / wave ─────────────────────────────────────────────────
    ComboUpdate            = { rateLimit = nil,  readyGated = false },
    WaveStarted            = { rateLimit = nil,  readyGated = false },
    WaveCompleted          = { rateLimit = nil,  readyGated = false },
    AllWavesCompleted      = { rateLimit = nil,  readyGated = false },
    DefenseLineUpdate      = { rateLimit = nil,  readyGated = false },
    DefenseLineDamaged     = { rateLimit = nil,  readyGated = false },
    DefenseLineDestroyed   = { rateLimit = nil,  readyGated = false },
    DefenseLineCombo       = { rateLimit = nil,  readyGated = false },
    PlayerDeath            = { rateLimit = nil,  readyGated = false },
    ComboEnded             = { rateLimit = nil,  readyGated = false },
    -- §AGX/X28: CentralBoss encounter (server → client only; BossEncounter).
    -- Late joiners get a snapshot via ReadyGate.OnReady, so not gated.
    BossStateUpdate        = { rateLimit = nil,  readyGated = false },
    BossPhaseChanged       = { rateLimit = nil,  readyGated = false },

    -- ── Scene / matchmaking / state ──────────────────────────────────
    SceneChanged           = { rateLimit = nil,  readyGated = false },
    RequestSceneInfo       = { rateLimit = nil,  readyGated = false },
    MatchmakingUpdate      = { rateLimit = nil,  readyGated = false },
    GameStateChanged       = { rateLimit = nil,  readyGated = false },
    CountdownUpdate        = { rateLimit = nil,  readyGated = false },
    -- §AGX/WC: §PB-D3 start-gate progress (server → client; late HUDs get
    -- it in the RequestGameState snapshot, so not gated).
    StartGateUpdate        = { rateLimit = nil,  readyGated = false },
    -- §SCALE/S6: these trigger P-amplified rebroadcasts (party fan-outs)
    -- — cap at menu rate instead of the 30/s default.
    MatchmakingRequest     = { rateLimit = 4,    readyGated = false },
    PlayerListRequest      = { rateLimit = 4,    readyGated = false },
    GetPartyState          = { rateLimit = 4,    readyGated = false },

    -- ── Social ───────────────────────────────────────────────────────
    PartyUpdate            = { rateLimit = nil,  readyGated = false },
    PartyInvite            = { rateLimit = nil,  readyGated = false },
    PartyError             = { rateLimit = nil,  readyGated = false },
    PlayerListUpdate       = { rateLimit = nil,  readyGated = false },
    PartyRequest           = { rateLimit = nil,  readyGated = false },

    -- ── Combat requests (client→server) ──────────────────────────────
    -- §SCALE/S6: state-machine triggers — 2/s is generous for a button.
    RequestStartGame       = { rateLimit = 2,    readyGated = false },
    RequestNextWave        = { rateLimit = 2,    readyGated = false },
    RequestReturnToLobby   = { rateLimit = 2,    readyGated = false },
    -- §AGX/UX-02: HUD asks for a state snapshot on mount (reply = GameStateChanged).
    RequestGameState       = { rateLimit = 2,    readyGated = false },

    -- ── Stats / respec ───────────────────────────────────────────────
    RespecStats            = { rateLimit = nil,  readyGated = false },
    SaveKeybindings        = { rateLimit = nil,  readyGated = false },

    -- ── Cosmetics ────────────────────────────────────────────────────
    -- WardrobeUpdate is also pure request/response (GetWardrobe →
    -- WardrobeUpdate); no boot race. Not ready-gated.
    WardrobeUpdate         = { rateLimit = nil,  readyGated = false },
    CosmeticEquipped       = { rateLimit = nil,  readyGated = false },
    GetWardrobe            = { rateLimit = nil,  readyGated = false },
    EquipCosmetic          = { rateLimit = nil,  readyGated = false },
    UnequipCosmetic        = { rateLimit = nil,  readyGated = false },

    -- ── Achievements ─────────────────────────────────────────────────
    AchievementsData       = { rateLimit = nil,  readyGated = true  }, -- request-driven, but we also push
    AchievementUnlocked    = { rateLimit = nil,  readyGated = true  }, -- §NM-D2: toast push
    GetAchievements        = { rateLimit = nil,  readyGated = false },

    -- ── Shop ─────────────────────────────────────────────────────────
    ShopState              = { rateLimit = nil,  readyGated = false },
    ShopResult             = { rateLimit = nil,  readyGated = false },
    ShopPurchase           = { rateLimit = nil,  readyGated = false },
    GetShopState           = { rateLimit = nil,  readyGated = false },

    -- ── Inventory ────────────────────────────────────────────────────
    GetInventory           = { rateLimit = nil,  readyGated = false },
    EquipAccessory         = { rateLimit = nil,  readyGated = false },
    UnequipAccessory       = { rateLimit = nil,  readyGated = false },
    InventoryUpdate        = { rateLimit = nil,  readyGated = false },
    UseConsumable          = { rateLimit = 4,    readyGated = false }, -- §AGX/X10b: InventoryUI Use → ConsumableEffects (reply: NotifyService.Inline)

    -- ── Daily login ──────────────────────────────────────────────────
    ClaimDailyLogin        = { rateLimit = nil,  readyGated = false },
    GetDailyLoginStatus    = { rateLimit = nil,  readyGated = false },
    DailyLoginResult       = { rateLimit = nil,  readyGated = false },
    DailyLoginStatus       = { rateLimit = nil,  readyGated = false },

    -- ── Leaderboard ──────────────────────────────────────────────────
    GetLeaderboard         = { rateLimit = nil,  readyGated = false },
    LeaderboardData        = { rateLimit = nil,  readyGated = false },
    PlayerGearScore        = { rateLimit = nil,  readyGated = false },

    -- ── Vote system ──────────────────────────────────────────────────
    VoteStart              = { rateLimit = nil,  readyGated = false },
    VoteUpdate             = { rateLimit = nil,  readyGated = false },
    VoteResult             = { rateLimit = nil,  readyGated = false },
    VotePending            = { rateLimit = nil,  readyGated = false },
    VoteCountdown          = { rateLimit = nil,  readyGated = false },
    VoteRewardGranted      = { rateLimit = nil,  readyGated = false },
    VoteCast               = { rateLimit = 4,    readyGated = false }, -- one per phase; 4× headroom
    VoteStartPersonal      = { rateLimit = nil,  readyGated = false },
    VoteCastPersonal       = { rateLimit = 4,    readyGated = false },
    VoteResultPersonal     = { rateLimit = nil,  readyGated = false },

    -- ── Admin (§AGX/SEC: §T0P2-ADMIN — Studio only, never created live) ──
    AdminAction            = { rateLimit = nil,  readyGated = false, studioOnly = true },
    AdminActionResult      = { rateLimit = nil,  readyGated = false, studioOnly = true },
    DebugCommand           = { rateLimit = nil,  readyGated = false, studioOnly = true },
    ModifySystemStat       = { rateLimit = nil,  readyGated = false, studioOnly = true }, -- §T0P2/X10: was created ad-hoc by SharedEventHandlers

    -- ── §T0P2/X10: previously used but missing from the manifest ─────
    -- These were created ad-hoc via GetEvent AFTER the pre-register
    -- pass, undocumented and invisible to the planned lint pass.
    DeathState             = { rateLimit = nil,  readyGated = false }, -- DeathSystem push
    RequestRespawn         = { rateLimit = 4,    readyGated = false }, -- DeathSystem; one per death, 4× headroom
    WipeReviveOffer        = { rateLimit = nil,  readyGated = false }, -- §DISC/D3b: wipe grace window opened
    WipeReviveResolved     = { rateLimit = nil,  readyGated = false }, -- §DISC/D3b: revived or defeat
    WipeReviveAccept       = { rateLimit = 4,    readyGated = false }, -- §DISC/D3b: client buys the revive
    HordePaused            = { rateLimit = nil,  readyGated = false }, -- HordePauseManager broadcast
    NPCProximity           = { rateLimit = nil,  readyGated = false }, -- NPCManager proximity push

    -- ── Notify ───────────────────────────────────────────────────────
    -- §AGX/UI-P4: the one server→client feedback push (NotifyService:
    -- toast / banner / feed / inline). No server listener, so rateLimit
    -- only caps a spoofed client fire; NotifyService throttles outgoing
    -- sends per player. Not ready-gated: producers answer client actions.
    Notify                 = { rateLimit = 1,    readyGated = false },
}

-- §T0P2/X10 → §T0P2-ORPHANS (§AGX/SEC): the four equipment events are
-- NOT orphans — fired by name (EquipmentRefinement / EquipmentTierSystem
-- `eventName`). HealNumber (never fired; heals use HealNumberBatch) and
-- its dead client listener were removed.

-- ─────────────────────────────────────────────────────────────────────
-- RATE LIMITER (per-event)
-- ─────────────────────────────────────────────────────────────────────

local function getLimit(eventName)
    local entry = EVENTS[eventName]
    if entry and entry.rateLimit then return entry.rateLimit end
    return DEFAULT_LIMIT
end

local function isRateLimited(eventName, player)
    local buckets = rateBuckets[eventName]
    if not buckets then
        buckets = {}
        rateBuckets[eventName] = buckets
    end

    local now = os.clock()
    local bucket = buckets[player]
    if not bucket or (now - bucket.start) >= RATE_WINDOW then
        buckets[player] = { count = 1, start = now, lastAccess = now }
        return false
    end

    bucket.count = bucket.count + 1
    bucket.lastAccess = now
    if bucket.count > getLimit(eventName) then
        return true
    end
    return false
end

local function cleanupStaleBuckets()
    local now = os.clock()
    for eventName, buckets in pairs(rateBuckets) do
        for player, bucket in pairs(buckets) do
            if (now - bucket.lastAccess) > BUCKET_MAX_AGE then
                buckets[player] = nil
            end
        end
        if next(buckets) == nil then
            rateBuckets[eventName] = nil
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────
-- INIT
-- ─────────────────────────────────────────────────────────────────────

function NetworkManager.Init()
    -- Create Events folder
    eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    if not eventsFolder then
        eventsFolder = Instance.new("Folder")
        eventsFolder.Name = "Events"
        eventsFolder.Parent = ReplicatedStorage
    end

    -- §NM-D4: pre-register every manifest entry so client WaitForChild
    -- never times out during boot.
    local count = 0
    for name, entry in pairs(EVENTS) do
        if entry.studioOnly and not IS_STUDIO then
            -- §AGX/SEC: never create a Studio-only remote in a live
            -- server, and drop any copy a place file might carry.
            local stale = eventsFolder:FindFirstChild(name)
            if stale then stale:Destroy() end
        else
            NetworkManager.GetEvent(name)
            count = count + 1
        end
    end

    -- Clean up rate-limit buckets when players leave
    Players.PlayerRemoving:Connect(function(player)
        for _, buckets in pairs(rateBuckets) do
            buckets[player] = nil
        end
    end)

    -- Periodic cleanup of stale rate-limit buckets
    task.spawn(function()
        while true do
            task.wait(BUCKET_CLEANUP_INTERVAL)
            cleanupStaleBuckets()
        end
    end)

end

-- ─────────────────────────────────────────────────────────────────────
-- GET / FIRE
-- ─────────────────────────────────────────────────────────────────────

--- §AGX/SEC: returns nil for a studioOnly event outside Studio (the
--- remote must not exist there); FireClient / FireAllClients /
--- OnClientEvent then no-op instead of creating it.
function NetworkManager.GetEvent(eventName)
    if remoteEvents[eventName] then
        return remoteEvents[eventName]
    end
    if not IS_STUDIO and NetworkManager.IsStudioOnly(eventName) then
        warn("[NetworkManager] Refusing to create Studio-only remote outside Studio: " .. tostring(eventName))
        return nil
    end

    local event = eventsFolder:FindFirstChild(eventName)
    if not event then
        event = Instance.new("RemoteEvent")
        event.Name = eventName
        event.Parent = eventsFolder
    end

    remoteEvents[eventName] = event
    return event
end

function NetworkManager.FireClient(player, eventName, ...)
    local event = NetworkManager.GetEvent(eventName)
    if not event then return end  -- §AGX/SEC: Studio-only event outside Studio
    event:FireClient(player, ...)
end

function NetworkManager.FireAllClients(eventName, ...)
    local event = NetworkManager.GetEvent(eventName)
    if not event then return end  -- §AGX/SEC: Studio-only event outside Studio
    event:FireAllClients(...)
end

--- §AGX/SEC: returns the RBXScriptConnection (nil when the event is
--- Studio-only and we're live) so callers can tear the listener down.
function NetworkManager.OnClientEvent(eventName, callback)
    local event = NetworkManager.GetEvent(eventName)
    if not event then return nil end  -- §AGX/SEC: Studio-only event outside Studio
    return event.OnServerEvent:Connect(function(player, ...)
        if isRateLimited(eventName, player) then
            return
        end
        callback(player, ...)
    end)
end

-- ─────────────────────────────────────────────────────────────────────
-- INTROSPECTION  (used by ReadyGate + future lint pass)
-- ─────────────────────────────────────────────────────────────────────

--- Returns true if the manifest marks this event as ready-gated.
--- ReadyGate-aware producers should consult this to decide whether to
--- queue or fire directly. (The flag is informational; routing is still
--- callsite-explicit to avoid circular requires.)
function NetworkManager.IsReadyGated(eventName)
    local entry = EVENTS[eventName]
    return entry ~= nil and entry.readyGated == true
end

--- §AGX/SEC: true if the manifest marks this event Studio-only.
function NetworkManager.IsStudioOnly(eventName)
    local entry = EVENTS[eventName]
    return entry ~= nil and entry.studioOnly == true
end

--- Returns the rate limit for an event (the resolved value, including
--- the default fallback). Useful for debug overlays.
function NetworkManager.GetRateLimit(eventName)
    return getLimit(eventName)
end

return NetworkManager
