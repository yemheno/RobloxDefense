-- ServerScriptService/Modules/VoteManager
--[[
    Server-side vote lifecycle engine for the card/event system.

    Usage (from mode bootstrap):
        VoteManager.Setup({ NetworkManager, CardRegistry, RunModifiers, ... })
        VoteManager.StartVote("supply", { difficulty = "Normal", ... })

    Two flows live side-by-side:

      SHARED   (threat / tactical)  ── one trio for everyone, highest votes wins,
                                       one card applies to everyone.

      PERSONAL (supply)              ── each player gets their own trio and
                                       picks freely. Their choice applies only
                                       to them. No vote tally, no broadcast.
                                       A 10 % roll per player per vote injects
                                       a "RespecFragment" card into the trio,
                                       capped at one fragment pre-roll per
                                       player per run.

    The shared and personal flows do NOT share state — a shared vote can still
    be "active" (voteActive = true) while each player independently resolves
    their personal card. The manager will treat both kinds of votes as one
    active vote at a time from the caller's perspective (IsVoteActive()).
]]

local VoteManager = {}

local Players = game:GetService("Players")

-- ─────────────────────────────────────────────────────────────────────
-- DEPENDENCIES  (injected via Setup)
-- ─────────────────────────────────────────────────────────────────────
local NetworkManager    = nil
local CardRegistry      = nil
local RunModifiers      = nil
local PlayerDataManager = nil
local BonusManager      = nil
local ResourceManager   = nil
local CurrencyManager   = nil

-- Optional (mode-specific, set via SetModeDeps)
local modeDeps = {}

-- ─────────────────────────────────────────────────────────────────────
-- CONFIG
-- ─────────────────────────────────────────────────────────────────────
local VOTE_TIMER_SEC = 10

-- §VG3: lazy SkillManager require so we can interrupt active casts
-- when a vote starts. Lazy because SkillManager loads after VoteManager
-- in some places and we don't want a top-level circular require.
local _SkillManager = nil
local function getSkillManager()
	if _SkillManager then return _SkillManager end
	local mod = script.Parent:FindFirstChild("SkillManager")
	if mod then
		local ok, sm = pcall(require, mod)
		if ok and sm then _SkillManager = sm end
	end
	return _SkillManager
end
-- §VG4: post-resolve timing has two phases.
--   1) DISPLAY: cards stay on screen showing the winner.
--   2) COUNTDOWN: cards leave, a 'Get ready!' countdown counts down
--      while the world is still paused.
-- World unfreezes only after both phases finish. HordeMode is twitchy:
-- giving the player a brief countdown to re-orient is the difference
-- between fair and frustrating.
local VOTE_RESULT_DISPLAY_SEC   = 2
local VOTE_RESULT_COUNTDOWN_SEC = 3
local VOTE_RESULT_GRACE_SEC     = VOTE_RESULT_DISPLAY_SEC + VOTE_RESULT_COUNTDOWN_SEC
local CARDS_PER_VOTE = 3
local FRAGMENT_ROLL_CHANCE = 0.10  -- 10% per supply vote, per player
local FRAGMENT_CARD_ID     = "RespecFragment"

-- ─────────────────────────────────────────────────────────────────────
-- STATE — SHARED VOTE (threat / tactical)
-- ─────────────────────────────────────────────────────────────────────
local voteActive       = false
-- §AGX/X30b: set once _Resolve runs; voteActive stays true through the
-- result grace window, and a late VoteCast used to re-run _Resolve and
-- apply a SECOND card.
local voteResolved     = false
local voteOptions      = {}     -- { cardId, cardId, cardId }
local voteCounts       = {}     -- { [1]=N, [2]=N, [3]=N }
local playersVoted     = {}     -- { [Player]=true }
local eligiblePlayers  = {}     -- { Player, ... }
local voteExpiration   = 0
local voteResolveThread = nil
local voteListenerConn  = nil
local voteListenerConnPersonal = nil

-- §AGX/T11-JAN: run-scoped Janitor for the post-resolve timers (VoteCountdown
-- broadcast + the voteActive=false grace flip). They used to be bare
-- task.delays that outlived Reset(): a Reset followed by a new vote inside
-- VOTE_RESULT_GRACE_SEC let the OLD timer clear voteActive mid-vote
-- (unpausing the world) and send a stray VoteCountdown. Reset destroys it.
local Janitor = require(script.Parent:WaitForChild("Janitor"))
local runJanitor = Janitor.new("VoteManager.run")

local function schedulePostResolve()
    runJanitor:Add(task.delay(VOTE_RESULT_DISPLAY_SEC, function()
        NetworkManager.FireAllClients("VoteCountdown", {
            seconds = VOTE_RESULT_COUNTDOWN_SEC,
        })
    end))
    runJanitor:Add(task.delay(VOTE_RESULT_GRACE_SEC, function()
        voteActive = false
    end))
end

-- Cooldown tracking for SHARED votes: { [cooldownKey] = lastWinTimestamp }
local cooldowns = {}

-- ─────────────────────────────────────────────────────────────────────
-- STATE — PERSONAL VOTE (supply)
-- ─────────────────────────────────────────────────────────────────────
-- personalVote[player] = {
--     cards        = { cardId, cardId, cardId },  -- options
--     voted        = bool,
--     expireTime   = number (os.clock),
--     resolveThread = thread,
-- }
local personalVote = {}
-- Per-player cooldown tables for supply cards (parallel to the shared
-- `cooldowns` table, but scoped per-player so one player's pick does not
-- gate another player's trio).
local personalCooldowns = {}
-- { [player] = { [cooldownKey] = lastPickTimestamp } }

-- { [player] = true } — once a fragment pre-roll has fired for a player
-- this run (picked or not), no further rolls happen for that player until
-- Reset() is called.
local fragmentRolledThisRun = {}

-- Run state snapshot (set by caller before StartVote)
local runState = {
    difficulty  = "Normal",
    elapsed     = 0,
    waveNumber  = nil,
    modeId      = "Defense",
}

-- ─────────────────────────────────────────────────────────────────────
-- SETUP
-- ─────────────────────────────────────────────────────────────────────

function VoteManager.Setup(deps)
    NetworkManager    = deps.NetworkManager
    CardRegistry      = deps.CardRegistry
    RunModifiers      = deps.RunModifiers
    PlayerDataManager = deps.PlayerDataManager
    BonusManager      = deps.BonusManager
    ResourceManager   = deps.ResourceManager
    CurrencyManager   = deps.CurrencyManager

    -- Pre-register events  (shared flow)
    NetworkManager.GetEvent("VoteStart")
    NetworkManager.GetEvent("VoteUpdate")
    NetworkManager.GetEvent("VoteResult")
    NetworkManager.GetEvent("VoteRewardGranted")
    NetworkManager.GetEvent("VoteCast")
    NetworkManager.GetEvent("VotePending")
    NetworkManager.GetEvent("VoteCountdown")  -- §VG4: "Get ready!" timer after cards leave

    -- Pre-register events  (personal flow)
    NetworkManager.GetEvent("VoteStartPersonal")
    NetworkManager.GetEvent("VoteCastPersonal")
    NetworkManager.GetEvent("VoteResultPersonal")

    -- Listen for client votes
    voteListenerConn = NetworkManager.OnClientEvent("VoteCast", function(player, cardIndex)
        VoteManager._OnVoteCast(player, cardIndex)
    end)

    voteListenerConnPersonal = NetworkManager.OnClientEvent("VoteCastPersonal", function(player, cardIndex)
        VoteManager._OnVoteCastPersonal(player, cardIndex)
    end)

    -- §T5/S1: mid-run leaver cleanup. These four tables are Player-keyed
    -- and were only cleared by the between-run Reset(), so every mid-run
    -- leaver left entries behind for the rest of the run. (Rejoiners get
    -- a NEW Player instance, so stale entries never blocked anyone —
    -- pure leak, now closed at the source.)
    Players.PlayerRemoving:Connect(function(player)
        playersVoted[player]          = nil
        personalVote[player]          = nil
        personalCooldowns[player]     = nil
        fragmentRolledThisRun[player] = nil
        -- §AGX/T11-JAN: drop the leaver's ref from the vote snapshot too
        -- (every read already skips p.Parent == nil; this just releases it).
        local idx = table.find(eligiblePlayers, player)
        if idx then table.remove(eligiblePlayers, idx) end
    end)

end

--- Set mode-specific dependencies (defenseLine, mobSpawner, etc.)
function VoteManager.SetModeDeps(deps)
    modeDeps = deps or {}
end

--- Update run state snapshot before starting a vote.
function VoteManager.SetRunState(state)
    for k, v in pairs(state) do
        runState[k] = v
    end
end

-- ─────────────────────────────────────────────────────────────────────
-- CARD SELECTION
-- ─────────────────────────────────────────────────────────────────────

--- Shared-flow picker. Respects the shared `cooldowns` table.
local function pickCards(cardType, count)
    local pool
    if cardType == "threat" then
        -- One from each lane: greed, control, relief
        local greed   = CardRegistry.GetThreatLane("greed")
        local control = CardRegistry.GetThreatLane("control")
        local relief  = CardRegistry.GetThreatLane("relief")

        local function pickFromLane(lane)
            local now = os.clock()
            local eligible = {}
            for _, id in ipairs(lane) do
                local card = CardRegistry.GetCard(id)
                if card.cooldownKey and cooldowns[card.cooldownKey] then
                    if (now - cooldowns[card.cooldownKey]) < (card.cooldownSec or 90) then
                        continue
                    end
                end
                if card.eligible and not card.eligible(runState) then
                    continue
                end
                table.insert(eligible, id)
            end
            if #eligible == 0 then return lane[math.random(#lane)] end
            return eligible[math.random(#eligible)]
        end

        return { pickFromLane(greed), pickFromLane(control), pickFromLane(relief) }
    end

    -- supply / tactical — pick N from the full pool
    pool = CardRegistry.GetPool(cardType)

    -- Filter by cooldowns and eligibility
    local now = os.clock()
    local eligible = {}
    for _, id in ipairs(pool) do
        -- Never inject the fragment via normal picking — it is a
        -- special-case card gated by a per-player 10 % roll.
        if id == FRAGMENT_CARD_ID then
            continue
        end
        local card = CardRegistry.GetCard(id)
        if card.cooldownKey and cooldowns[card.cooldownKey] then
            if (now - cooldowns[card.cooldownKey]) < (card.cooldownSec or 90) then
                continue
            end
        end
        if card.eligible and not card.eligible(runState) then
            continue
        end
        table.insert(eligible, id)
    end

    -- Shuffle and take first N
    for i = #eligible, 2, -1 do
        local j = math.random(i)
        eligible[i], eligible[j] = eligible[j], eligible[i]
    end

    local result = {}
    for i = 1, math.min(count, #eligible) do
        table.insert(result, eligible[i])
    end

    -- Pad with random from full pool if not enough eligible
    while #result < count and #pool > 0 do
        local id = pool[math.random(#pool)]
        if id ~= FRAGMENT_CARD_ID then
            table.insert(result, id)
        end
    end

    return result
end

--- Personal-flow picker. Respects per-player cooldowns and skips the
--- fragment card (injected separately when the 10 % roll hits).
local function pickCardsPersonal(player, count)
    local pool = CardRegistry.GetPool("supply")
    local pcd  = personalCooldowns[player] or {}
    personalCooldowns[player] = pcd

    local now = os.clock()
    local eligible = {}
    for _, id in ipairs(pool) do
        if id == FRAGMENT_CARD_ID then
            continue
        end
        local card = CardRegistry.GetCard(id)
        if card.cooldownKey and pcd[card.cooldownKey] then
            if (now - pcd[card.cooldownKey]) < (card.cooldownSec or 90) then
                continue
            end
        end
        if card.eligible and not card.eligible(runState) then
            continue
        end
        table.insert(eligible, id)
    end

    for i = #eligible, 2, -1 do
        local j = math.random(i)
        eligible[i], eligible[j] = eligible[j], eligible[i]
    end

    local result = {}
    for i = 1, math.min(count, #eligible) do
        table.insert(result, eligible[i])
    end

    while #result < count and #pool > 0 do
        local id = pool[math.random(#pool)]
        if id ~= FRAGMENT_CARD_ID then
            table.insert(result, id)
        end
    end

    return result
end

-- ─────────────────────────────────────────────────────────────────────
-- VOTE LIFECYCLE
-- ─────────────────────────────────────────────────────────────────────

function VoteManager.IsVoteActive()
    return voteActive
end

--- Start a vote of the given type ("supply", "threat", "tactical").
--- Returns immediately; resolution happens async. Returns false if busy.
function VoteManager.StartVote(cardType)
    if voteActive then
        warn("[VoteManager] Vote already active, skipping", cardType)
        return false
    end

    -- Resolve eligible players (used by both flows)
    eligiblePlayers = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Parent then
            table.insert(eligiblePlayers, player)
        end
    end
    if #eligiblePlayers == 0 then return false end

    -- §VG3: interrupt any active casts on the eligible players. The
    -- vote pause already blocks regen + new attacks via DeathState-style
    -- gates, but a cast already in flight will complete on its own timer
    -- (CompleteCasting fires after castTime). Interrupting here forces
    -- the player to re-engage with the vote, not finish a free spell
    -- during the freeze.
    local sm = getSkillManager()
    if sm and sm.InterruptCasting then
        for _, p in ipairs(eligiblePlayers) do
            if sm.IsCasting and sm.IsCasting(p) then
                sm.InterruptCasting(p, "Vote started")
            end
        end
    end

    if cardType == "supply" then
        return VoteManager._StartVotePersonal()
    end

    return VoteManager._StartVoteShared(cardType)
end

--- Start a SHARED vote (threat / tactical).
function VoteManager._StartVoteShared(cardType)
    local cards = pickCards(cardType, CARDS_PER_VOTE)
    if #cards == 0 then
        warn("[VoteManager] No cards available for type:", cardType)
        return false
    end

    -- Init state
    voteActive   = true
    voteResolved = false
    voteOptions  = cards
    voteCounts   = {}
    playersVoted = {}
    for i = 1, #cards do
        voteCounts[i] = 0
    end

    voteExpiration = os.clock() + VOTE_TIMER_SEC

    -- Build client payload
    local clientCards = {}
    for i, cardId in ipairs(cards) do
        local card = CardRegistry.GetCard(cardId)
        clientCards[i] = {
            index       = i,
            id          = card.id,
            name        = card.name,
            description = card.description,
            cardType    = card.cardType,
            lane        = card.lane,
        }
    end

    NetworkManager.FireAllClients("VoteStart", {
        cards          = clientCards,
        timerSeconds   = VOTE_TIMER_SEC,
        voteType       = cardType,
        eligibleCount  = #eligiblePlayers,
    })

    -- Start timer
    voteResolveThread = task.spawn(function()
        task.wait(VOTE_TIMER_SEC)
        if voteActive then
            VoteManager._Resolve()
        end
    end)

    return true
end

--- Start a PERSONAL vote (supply). Each player sees their own trio.
function VoteManager._StartVotePersonal()
    voteActive   = true
    voteResolved = false
    personalVote = {}

    for _, player in ipairs(eligiblePlayers) do
        -- Roll fragment chance BEFORE picking — so we can substitute a card
        -- slot for the fragment if the roll hits.
        local injectFragment = false
        if not fragmentRolledThisRun[player] then
            if math.random() < FRAGMENT_ROLL_CHANCE then
                injectFragment = true
            end
            -- Mark as rolled regardless (this enforces the 1-per-run cap).
            fragmentRolledThisRun[player] = true
        end

        local cards = pickCardsPersonal(player, CARDS_PER_VOTE)
        if #cards < CARDS_PER_VOTE then
            -- Should never happen given the padding logic, but be defensive.
            warn("[VoteManager] Personal pick returned <3 cards for", player.Name)
        end

        if injectFragment and #cards > 0 then
            local slot = math.random(#cards)
            cards[slot] = FRAGMENT_CARD_ID
        end

        -- Build client payload
        local clientCards = {}
        for i, cardId in ipairs(cards) do
            local card = CardRegistry.GetCard(cardId)
            if card then
                clientCards[i] = {
                    index       = i,
                    id          = card.id,
                    name        = card.name,
                    description = card.description,
                    cardType    = card.cardType,
                    lane        = card.lane,
                }
            end
        end

        personalVote[player] = {
            cards        = cards,
            voted        = false,
            expireTime   = os.clock() + VOTE_TIMER_SEC,
            resolveThread = nil,
        }

        NetworkManager.FireClient(player, "VoteStartPersonal", {
            cards        = clientCards,
            timerSeconds = VOTE_TIMER_SEC,
            voteType     = "supply",
        })
    end

    -- Single expiry thread that resolves any un-picked players by auto-picking.
    voteResolveThread = task.spawn(function()
        task.wait(VOTE_TIMER_SEC)
        VoteManager._ResolvePersonalExpired()
    end)

    return true
end

-- ─────────────────────────────────────────────────────────────────────
-- CLIENT VOTE HANDLER — SHARED
-- ─────────────────────────────────────────────────────────────────────

function VoteManager._OnVoteCast(player, cardIndex)
    if not voteActive or voteResolved then return end
    if playersVoted[player] then return end  -- one vote per player

    -- §AGX/X30: integer index only (1.5 / NaN used to slip past the bounds
    -- check and burn the player's vote), and only eligible voters count.
    cardIndex = tonumber(cardIndex)
    if not cardIndex or cardIndex ~= math.floor(cardIndex)
        or cardIndex < 1 or cardIndex > #voteOptions then return end
    if not table.find(eligiblePlayers, player) then return end

    playersVoted[player] = true
    voteCounts[cardIndex] = (voteCounts[cardIndex] or 0) + 1

    -- Broadcast updated counts (anonymous)
    NetworkManager.FireAllClients("VoteUpdate", {
        counts     = voteCounts,
        totalVoted = VoteManager._CountVoted(),
    })

    -- §VM1 fix: count CURRENTLY-CONNECTED eligible players, not the
    -- snapshot taken at StartVote time. If a player leaves mid-vote the
    -- threshold should drop with them; otherwise the vote can never
    -- early-resolve and always runs to full timeout.
    local stillEligible = 0
    for _, p in ipairs(eligiblePlayers) do
        if p.Parent then stillEligible = stillEligible + 1 end
    end
    if VoteManager._CountVoted() >= stillEligible then
        if voteResolveThread then
            task.cancel(voteResolveThread)
        end
        VoteManager._Resolve()
    end
end

function VoteManager._CountVoted()
    local n = 0
    for _ in pairs(playersVoted) do n = n + 1 end
    return n
end

-- ─────────────────────────────────────────────────────────────────────
-- CLIENT VOTE HANDLER — PERSONAL
-- ─────────────────────────────────────────────────────────────────────

function VoteManager._OnVoteCastPersonal(player, cardIndex)
    local slot = personalVote[player]
    if not slot or slot.voted then return end

    cardIndex = tonumber(cardIndex)
    if not cardIndex or cardIndex < 1 or cardIndex > #slot.cards then return end

    -- §VM2 fix: guard against nil cardId. Bounds check above protects
    -- against client-side tampering on cardIndex, but `slot.cards` could
    -- be cleared by a concurrent Reset() right before this read.
    local cardId = slot.cards[cardIndex]
    if not cardId then
        warn(string.format(
            "[VoteManager] Personal vote: nil cardId at index %d for %s — slot may have been reset.",
            cardIndex, player.Name))
        return
    end

    slot.voted = true
    VoteManager._ApplyPersonalPick(player, cardId, cardIndex)

    -- If everyone has now voted, end the vote early (cancel timer).
    local anyWaiting = false
    for _, s in pairs(personalVote) do
        if not s.voted then
            anyWaiting = true
            break
        end
    end
    if not anyWaiting then
        if voteResolveThread then
            pcall(task.cancel, voteResolveThread)
            voteResolveThread = nil
        end
        VoteManager._ClosePersonal()
    end
end

--- Resolve any players who haven't picked by auto-selecting a random card.
function VoteManager._ResolvePersonalExpired()
    for player, slot in pairs(personalVote) do
        if not slot.voted and player.Parent then
            local idx = math.random(#slot.cards)
            slot.voted = true
            VoteManager._ApplyPersonalPick(player, slot.cards[idx], idx)
        end
    end
    VoteManager._ClosePersonal()
end

--- Apply one card to a single player (personal flow).
function VoteManager._ApplyPersonalPick(player, cardId, cardIndex)
    local card = CardRegistry.GetCard(cardId)
    if not card then
        warn("[VoteManager] Unknown personal card id:", cardId)
        return
    end

    -- Notify client of their result (for UI feedback only — no counts)
    NetworkManager.FireClient(player, "VoteResultPersonal", {
        winnerIndex = cardIndex,
        cardId      = card.id,
        cardName    = card.name,
        description = card.description,
    })

    local deps = {
        players         = { player },
        runModifiers    = RunModifiers,
        dataManager     = PlayerDataManager,
        currencyManager = CurrencyManager,
        networkMgr      = NetworkManager,
        bonusManager    = BonusManager,
        resourceManager = ResourceManager,
        difficulty      = runState.difficulty,
        elapsed         = runState.elapsed,
        waveNumber      = runState.waveNumber,
        -- Mode-specific
        defenseLine     = modeDeps.defenseLine,
        mobSpawner      = modeDeps.mobSpawner,
    }

    local ok, err = pcall(card.apply, deps)
    if not ok then
        warn("[VoteManager] Personal card apply failed:", card.id, "for", player.Name, "→", err)
        return  -- §VM3: don't burn the cooldown if apply failed
    end

    -- §VM3 fix: only record the cooldown AFTER a successful apply.
    -- Previously the cooldown was set before the pcall; an erroring
    -- apply left the player with a burned cooldown for a card they
    -- never actually received.
    if card.cooldownKey then
        local pcd = personalCooldowns[player] or {}
        pcd[card.cooldownKey] = os.clock()
        personalCooldowns[player] = pcd
    end
end

function VoteManager._ClosePersonal()
    -- §VG4: same orchestration as shared votes (DISPLAY then COUNTDOWN
    -- then unfreeze). Personal voters all see their own result card so
    -- the countdown event still uses FireAllClients — every player gets
    -- the same 'Get ready!' counter regardless of who picked first.
    personalVote = {}
    schedulePostResolve()  -- §AGX/T11-JAN: run-scoped (was two bare task.delays)
end

-- ─────────────────────────────────────────────────────────────────────
-- RESOLUTION — SHARED
-- ─────────────────────────────────────────────────────────────────────

function VoteManager._Resolve()
    if not voteActive or voteResolved then return end
    voteResolved = true
    -- §VG2: keep voteActive=true through the resolve + broadcast
    -- so the world stays paused while clients animate the result card.
    -- voteActive = false is deferred to the end of this function.

    -- Find winner
    local maxVotes  = 0
    local winners   = {}
    for i, count in ipairs(voteCounts) do
        if count > maxVotes then
            maxVotes = count
            winners  = { i }
        elseif count == maxVotes then
            table.insert(winners, i)
        end
    end

    -- If nobody voted, all cards are candidates
    if maxVotes == 0 then
        winners = {}
        for i = 1, #voteOptions do
            table.insert(winners, i)
        end
    end

    local winnerIndex = winners[math.random(#winners)]
    local winnerCardId = voteOptions[winnerIndex]
    local winnerCard   = CardRegistry.GetCard(winnerCardId)

    -- §T5/S2: nil-guard. voteOptions were valid at StartVote, but if the
    -- registry ever loses the card between start and resolve, the old
    -- code crashed here — leaving voteActive stuck true (vote system
    -- deadlocked for the run). Complete the lifecycle with a stub result
    -- instead: clients close their vote UI, no reward applies.
    if not winnerCard then
        warn("[VoteManager] Winner card missing from registry:", tostring(winnerCardId),
            "— resolving vote with no reward")
        winnerCard = {
            id = winnerCardId,
            name = "(unavailable)",
            description = "",
            apply = function() end,
        }
    end

    -- §VM3: cooldown is now recorded AFTER a successful apply (see below).

    -- Broadcast result
    NetworkManager.FireAllClients("VoteResult", {
        winnerIndex = winnerIndex,
        cardId      = winnerCard.id,
        cardName    = winnerCard.name,
        description = winnerCard.description,
        counts      = voteCounts,
    })

    -- Apply the card effect
    local activePlayers = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Parent then
            table.insert(activePlayers, player)
        end
    end

    local deps = {
        players         = activePlayers,
        runModifiers    = RunModifiers,
        dataManager     = PlayerDataManager,
        currencyManager = CurrencyManager,
        networkMgr      = NetworkManager,
        bonusManager    = BonusManager,
        resourceManager = ResourceManager,
        difficulty      = runState.difficulty,
        elapsed         = runState.elapsed,
        waveNumber      = runState.waveNumber,
        -- Mode-specific
        defenseLine     = modeDeps.defenseLine,
        mobSpawner      = modeDeps.mobSpawner,
    }

    local ok, err = pcall(winnerCard.apply, deps)
    if not ok then
        warn("[VoteManager] Card apply failed:", winnerCard.id, err)
    else
        -- §VM3: only record the cooldown AFTER a successful apply.
        if winnerCard.cooldownKey then
            cooldowns[winnerCard.cooldownKey] = os.clock()
        end
    end

    print("[VoteManager] Resolved:", winnerCard.name,
        "| votes:", table.concat(voteCounts, "/"),
        "| danger:", string.format("%.1f%%", RunModifiers.GetTotalDangerBonus() * 100))

    -- §VG4: orchestrated post-resolve timing.
    --   t=0       : cards visible (already broadcast above).
    --   t=DISPLAY : fire VoteCountdown so client dismisses cards and
    --              shows the 'Get ready!' counter.
    --   t=GRACE   : voteActive = false → world resumes.
    -- All three are scheduled deterministically; clients align off
    -- the same broadcast events.
    schedulePostResolve()  -- §AGX/T11-JAN: run-scoped (was two bare task.delays)
end

-- ─────────────────────────────────────────────────────────────────────
-- RESET
-- ─────────────────────────────────────────────────────────────────────

function VoteManager.Reset()
    voteActive            = false
    cooldowns             = {}
    personalVote          = {}
    personalCooldowns     = {}
    fragmentRolledThisRun = {}
    if voteResolveThread then
        pcall(task.cancel, voteResolveThread)
        voteResolveThread = nil
    end
    -- §AGX/T11-JAN: drop this run's pending post-resolve timers.
    runJanitor:Destroy()
    runJanitor = Janitor.new("VoteManager.run")
end

return VoteManager
