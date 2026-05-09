# Sanity Check Report — V3

Coverage of the parts the V1/V2 audits skipped: lobby place, lane defense
place, central boss place, shared client UI, HordeModeSpawner, and
VoteManager internals. Severity tags follow V2 conventions:

- **P0** — game-breaking; fix before any next playtest.
- **P1** — likely visible bug or correctness issue; fix before alpha.
- **P2** — quality issue / future-proofing; fix when convenient.
- **Doc** — clarification or comment, no code change required.

Each item maps to a stable id of the form `§<area><n>` for cross-reference.

---

## §L — Lobby (`src/lobby/ServerScriptService/`)

### §L1 (P1) — `OnPlayerReady` polls instead of using `OnPlayerDataReady`
`LobbyMain.server.lua:249-260` retries `GetData` 20× at 0.5s intervals.
We have `PlayerDataManager.OnPlayerDataReady(cb)` (used in HordeMode after
the §3.1 fix). Replace polling with the callback so behaviour matches and
worst-case startup time goes from "10s timeout" to "as soon as data
arrives." Same fix applies to `LaneDefenseMain.server.lua:482-492` and
`CentralBossMain.server.lua:346-356`.

### §L2 (P1) — Bootstrap has no `RequireLoaded` validation
`LobbyMain.server.lua` does not hard-fail when a critical module (e.g.
PartyManager, MatchmakingManager) fails to load. HordeMode now does this
via the §3.4 `RequireLoaded` helper. Port the same helper here for at
least: PartyManager, MatchmakingManager, TeleportManager, NetworkManager,
PlayerDataManager, SharedEventHandlers.

### §L3 (P1) — PartyManager allows self-invite
`PartyManager.lua:104-118, 156-169` does not verify `target ~= leader`.
A leader inviting themselves by name overwrites their own
`pendingInvites[leader]` slot and produces inconsistent UI state.
Add `if target == leader then SendError; return false end`.

### §L4 (P0) — PartyManager AcceptInvite size check is racy
`PartyManager.lua:369-390`: between `#party.members >= party.maxSize` and
`table.insert(party.members, player)` two concurrent AcceptInvite calls
can both pass the size check and both insert, putting the party at
`maxSize + 1`. With `UpdatePartyBonuses` running async after
BroadcastUpdate, this interleaving is real. Re-check `#party.members <
party.maxSize` immediately before the insert.

### §L5 (P2) — PromoteLeader doesn't reject self-promote
`PartyManager.lua:481-497`: promoting yourself silently no-ops. Add an
explicit error for clearer UX.

### §L6 (P0) — MatchmakingManager IsQueued only checks the leader
`MatchmakingManager.lua:168` calls `IsQueued(player)` for the queueing
player only. A non-leader party member who is somehow already in queue
(via a packet replay or a malicious client) is not detected. Iterate
`PartyManager.GetPartyMembers(player)` and check each.

### §L7 (P1) — MatchmakingManager LaunchMatch doesn't re-validate min size
`MatchmakingManager.lua:332-350`: filters disconnected players but
teleports any non-zero remainder, even if the result is below
`mode.minPlayers`. A 5-player party where 4 disconnect during the 5s
countdown teleports a single solo player into a mode requiring 5. Add a
re-check; cancel the launch if below minPlayers.

### §L8 (P2) — MatchmakingManager queue captures live party member list
`MatchmakingManager.lua:182`: `queue[id].players = members` aliases the
party's live member array. If the party adds a member during the queue
wait, the queued list silently includes them. Use `table.clone(members)`
or copy explicitly.

### §L9 (P1) — TeleportManager fails silently — no requeue
`TeleportManager.lua:115-124`: when `TeleportAsync` fails, players see an
error but their MatchmakingManager state still says "Launching." They're
stuck until they manually cancel. Wire `TeleportManager` to call
`MatchmakingManager.CancelQueue` on failure so the state machine resets.

### §L10 (P1) — TeleportManager reads Level from Player attribute
`TeleportManager.lua:79`: falls back to `player:GetAttribute("Level") or
1`. If the attribute hasn't replicated when this runs, a high-level
player fakes as level 1, defeating the level-gap check at
`ValidateParty`. Use `PlayerDataManager.GetAccountData` for the
authoritative read, like PartyManager does.

### §L11 (P2) — `MAX_LEVEL_GAP = 10` duplicated
Both `PartyManager.lua:42` and `TeleportManager.lua:31` hard-code `10`.
Hoist to `PlayerDataConfig` or a new `MatchmakingConfig` module so they
can't drift.

### §L12 (Doc) — BroadcastPlayerList is unbounded
`PartyManager.lua:87-90`: every PlayerAdded fires a 1s-delayed
broadcast. N rapid joins → N broadcasts. Probably fine at our player
count; flag for telemetry if we ever grow.

---

## §LD — Lane Defense (`src/lanedefense/ServerScriptService/`)

### §LD1 (P0) — Same antipattern as §3.1: party-anchor before data ready
`LaneDefenseMain.server.lua:196-211` reads player levels after
`task.wait(0)` — exactly the bug §3.1 fixed in HordeMode. Apply the
same `OnPlayerDataReady`-gated approach.

### §LD2 (P1) — No `RequireLoaded` validation
Same as §L2; mirror the HordeMode §3.4 helper here for MobSpawner,
DefenseLine, VoteManager, GameStateManager, NetworkManager,
PlayerDataManager.

### §LD3 (P1) — Vitals broadcast applies HP regen on the broadcast tick
`LaneDefenseMain.server.lua:441-477`: HP regen uses
`VITALS_INTERVAL` as the tick. Bumping broadcast frequency would
accelerate regen. Decouple: regen on its own loop (or via DataManager
hooks); broadcast separately. Same finding for CentralBoss §CB2.

### §LD4 (P2) — `require` inside the broadcast loop
`LaneDefenseMain.server.lua:449`: `require(... GearRating)` lives inside
`while true do`. Hoist outside.

### §LD5 (P1) — VoteManager.Setup runs before `_hordeDifficulty` equivalent
`LaneDefenseMain.server.lua:249-271`: `Setup → SetModeDeps →
SetRunState`. The `SetRunState` call uses `laneDifficulty` derived via
`pcall(function() … TeleportDataReader.GetDifficulty() …)` which can
silently fall to "Normal" if the pcall fails. Surface a warn instead of
a silent default — same logic as the LD `_hordeDifficulty` block.

---

## §CB — Central Boss (`src/centralboss/ServerScriptService/`)

### §CB1 (P0) — No boss is ever spawned
`CentralBossMain.server.lua` loads MobSpawner and registers
OnWaveStarted/OnWaveCompleted callbacks but **never calls
`MobSpawner.Start()` or any boss-spawn logic.** A player teleporting in
sees an empty map and zero feedback. Either:
  - (a) wire to `MobSpawner.Start()` on `Defending` state-change like
    LaneDefense, with a placeholder boss wave;
  - (b) print a clear "[CentralBoss] Mode unauthored — no boss will
    spawn" warning so testers don't think it's a network problem.

This matches the TODO doc parking-lot entry. Recommend at least the
warn-on-load mitigation now so it's discoverable.

### §CB2 (P1) — Same vitals-tied regen issue as §LD3
Identical code at `CentralBossMain.server.lua:303-341`.

### §CB3 (P1) — Same OnPlayerReady polling antipattern as §L1

### §CB4 (P2) — Vote system not loaded
No `VoteManager` / `RunModifiers` / `CardRegistry` requires. Probably
intentional (boss fights have their own rules), but worth a comment in
the bootstrap explaining the omission.

---

## §U — Shared client UI (`src/shared/StarterGui/AppGui` and `StarterPlayerScripts/UI`)

### §U1 (P2) — `GlobalShopUI` bypasses `formatCurrency`
`GlobalShopUI.lua:332`: `tostring(shopState.merits)` and
`tostring(shopState.essence)` build the currency bar text. Late-game
this overflows. Replace with the new `UIUtils.formatCurrency`.

### §U2 (Doc) — HUD passes `data.score` (power) through `setCurrencyPill`
`HUD.client.lua:150`: power level shows up with currency-pill
formatting (k/M tiers). Probably fine; flag if ever revisited.

### §U3 (P0/none observed) — Connection management is clean
HUD's effect cleanup (`HUD.lua:389-410`) properly disconnects on
unmount and re-wires HumanoidConnection on `CharacterAdded`. No leaks
identified in the audited UI files.

---

## §HMS — HordeModeSpawner (`src/hordemode/.../HordeModeSpawner.lua`)

### §HMS1 (P1) — `template:Clone()` not pcall-wrapped
`HordeModeSpawner.lua:271`. We just added pcall + retry to MobSpawner
(§2.2b); same pattern is needed here. Per-player spawner loops swallow
the nil and produce silent spawn-rate dips.

### §HMS2 (P1) — `mobsFolder` lookup per spawn instead of cached
`HordeModeSpawner.lua:235`: `ReplicatedStorage:FindFirstChild("Mobs")`
runs on every spawn. Cache at Setup time and hard-error if missing
(matching §2.2a).

### §HMS3 (Doc) — `SetPartyAnchorLevel` session-clock conditional reset
`HordeModeSpawner.lua:583-585`: `if sessionStartTime ~= 0 then
sessionStartTime = os.clock() end`. The conditional is correct (Start
sets it on first run; SetPartyAnchorLevel re-anchors on subsequent
calls) but the intent isn't obvious. Add a comment.

### §HMS4 (P2) — PlayerAdded settle-then-spawn ignores running flag
`HordeModeSpawner.lua:481-489`: after `task.wait(1)` the inner closure
calls `createPlayerSpawner(player)` without re-checking `running`. If
`Stop()` runs during the settle window, we still create a spawner.
Re-check `running` after the wait.

### §HMS5 (Doc) — Speed escalation resets on Start()
`HordeModeSpawner.lua:467-477`: each Start re-spawns the escalation
loop with `step = 0`. Pause→Resume effectively cancels the escalation
benefit. Probably intended; document.

---

## §VM — VoteManager (`src/shared/.../VoteManager.lua`)

### §VM1 (P1) — Early-resolve uses stale `eligiblePlayers` count
`VoteManager.lua:446`: `_CountVoted() >= #eligiblePlayers`. If a player
leaves mid-vote, eligible stays the same but they can never vote, so the
threshold is unreachable and the vote always runs to full timeout.
Re-filter `eligiblePlayers` by `player.Parent` before the comparison,
or drop them from the dict on PlayerRemoving.

### §VM2 (P1) — Personal vote: nil card lookup not guarded
`VoteManager.lua:464-472`: `slot.cards[cardIndex]` could be nil in a
race where Reset() clears `personalVote` between the bounds check and
the apply. Add an explicit nil check on the looked-up cardId before
calling `_ApplyPersonalPick`.

### §VM3 (P2) — Cooldown set before card.apply succeeds
`VoteManager.lua:512-516, 542-545`: `personalCooldowns[player][key] =
os.clock()` runs BEFORE the pcall. If `card.apply` errors, the
cooldown is already burned. Move the cooldown assignment to after a
successful pcall.

### §VM4 (Doc) — RespecFragment.apply uses `WaitForChild` inside hot path
`CardRegistry.lua:502`: lazy-required on every card invocation. Cache
at module scope behind a `local _InventoryManager = nil` lazy
guard, like other modules in the codebase.

### §VM5 (Doc) — Ties resolve via `math.random(#winners)`
`VoteManager.lua:581`: random tiebreak; deterministic replay isn't
possible without seed control. Document; not currently a problem.

---

## Recommended TODO ordering

The critical path before alpha is:

1. **§CB1** (P0) — make Central Boss either run something or warn loudly.
2. **§LD1** (P0) — port the §3.1 fix to LaneDefense's party-anchor.
3. **§L4** (P0) — race in PartyManager.AcceptInvite size check.
4. **§L6** (P0) — IsQueued check covering all party members.
5. **§HMS1**, **§HMS2** (P1) — port the V2 MobSpawner hardening to
   HordeModeSpawner.
6. **§L1 / §LD3 / §CB3** (P1) — replace polling with
   `OnPlayerDataReady`, then mirror across all three places.
7. **§L2 / §LD2** (P1) — port the `RequireLoaded` helper outside HordeMode.
8. **§VM1, §VM2** (P1) — VoteManager edge cases; small surface area.

Then everything else as P2/Doc cleanups.

---

_Last updated: V3 sweep, run on top of the V2 fixes from this session's
prior context._
