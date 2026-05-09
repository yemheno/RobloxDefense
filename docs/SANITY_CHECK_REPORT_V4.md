# Sanity Check Report — V4 (Phase A + Phase B)

V4 picks up where V3 left off: this pass swept the modules V1/V2/V3 only
grazed. Phase A covered Skills, Talents, GameStateManager, DefenseLine,
ShopManager, DropManager, and AttackHandler. Phase B covered Cosmetics,
Achievements, DailyLogin, HordeModeMain end-to-end, lobby support
modules (SceneManager, LobbyNPCRegistry, NPCManager and its handlers),
the Equipment refinement / tier / reroll path, and the remaining client
UI files.

Severity tags follow V2/V3 conventions:

- **P0** ship-blocker — game-breaking; fix before any next playtest.
- **P1** likely visible bug or correctness issue; fix before alpha.
- **P2** quality / future-proofing.
- **Doc** — clarification or comment, no code change required.

Each item has a stable id of the form `§<area><n>` for cross-reference.

═══════════════════════════════════════════════════════════════════════
PHASE A — combat / data / state
═══════════════════════════════════════════════════════════════════════

## §S — SkillManager

### §S1 (P0) — atomic per-player request lock
`TryUseSkill` performed cooldown + casting checks before deducting
resource and starting cooldown. Two `SkillRequest` packets in the same
network frame would both pass the checks and both spend resource —
duplicated cast worth real damage. Added a per-player
`skillRequestLock` that rejects reentrant calls outright.

### §S2 (P1) — UpdateCasting iteration safety
`pairs(playerCasting)` while `CompleteCasting` set
`playerCasting[player] = nil` is undefined for hash mutation. Switched
to the same two-pass collect-then-mutate pattern UpdateBuffs already
uses.

### §S3 (P1) — knockdown during cast → interrupt
`CompleteCasting` had no `CanPlayerAct` check. A player knocked down
mid-cast would still execute the skill on cast-time expiry. Now routes
through `InterruptCasting`.

### §S4 + §S5 (P1) — Parent guards on Complete/Interrupt
`SetAttribute` on a leaving Player throws. Added `if not player.Parent`
short-circuits in both functions.

### §S7 (Doc)
`BUFF_STAT_MAP` aliases `AttackSpeedDown → AttackSpeed`; callsites are
expected to pass a negative `amount`. Document only.

---

## §T — TalentManager

### §T1 (P0) — respec deduct-first
`RespecAll` cleared the talent table BEFORE consuming the
scroll/essence. Any failure in the deduct left the player with zero
talents AND zero charge taken. Reordered: deduct first, abort on
failure, only respec once the cost is locked in.

### §T2 (P1) — atomic AllocateNode lock
Same race shape as §S1 — two `AllocateTalent` packets could both pass
the points check before either mutated the allocated table. Added
per-player `allocateLock`.

### §T4 (Doc) — `BonusTalentPoints` dead branch
Already noted in `TODO_PARKING_LOT.md`. Confirmed: no code grants it.

---

## §G — GameStateManager

### §G2 (P1) — idempotent ReturnToLobby
Both auto-return delays (Victory and Defeat fire at 10s) and any manual
caller could queue multiple teleport sweeps + double reset. Added
`_returnInFlight` latch released after a 2-second tail.

### §G4 (Doc) — ResetGame timing
`ReturnToLobby` fires teleport callbacks on `task.spawn` and immediately
calls `SetState(IDLE)` → `ResetGame` which destroys mobs and heals
players. Remaining-on-server players see the cleanup happen before
their teleport-out animation completes. Cosmetic; document.

### §G5 (P1, deferred) — late joiner state sync
A player who joins during Victory/Defeat misses the GameStateChanged
event. Phase A noted this; HUD-side fix lives in `TODO_PARKING_LOT.md`.

---

## §D — DefenseLine

### §D2 (P1) — LateInit idempotency
`Init` task.defers a LateInit, but place bootstraps explicitly call
LateInit too — running twice. Added `_lateInitDone` latch.

### §D1 (Doc) — animation-callback safety
`OnMobReachedLine` runs an async hit-animation. If the line is destroyed
mid-animation, the callback still fires `TakeDamage`.
`DefenseHealth.IsDestroyed` guard inside should catch it; verified.

---

## §Sh — ShopManager

### §Sh1 (P0) — purchase deduct-first
Both `PurchaseCosmetic` and `PurchaseConsumable` granted the item
BEFORE attempting `SpendMerits/SpendEssence`. If the spend ever
returned false (concurrent spend race, balance bug), the player kept
the item for free. Refactored to deduct-first; on grant failure,
refund the cost.

### §Sh2 + §Sh3 (P1) — concurrent purchase lock
Two `ShopPurchase` packets in the same frame could both pass
`canAfford` checks and both grant. Added `withPurchaseLock(player, fn)`
wrapper shared by all three Purchase* paths.

### §Sh4 (Doc)
Failed purchases no longer need a SendShopState refresh because nothing
mutated. Kept the behaviour as-is.

---

## §Dr — DropManager

### §Dr1 (P1) — Parent guard in ProcessKill
If the killer disconnected between damage hit and mob-death rewards,
`AddMerits` and `FireClient` ran on a leaving Player. Added early
`player.Parent` short-circuit.

### §Dr2 / §Dr3 (Doc)
RNG seed and difficulty cache documented; no fix needed.

---

## §A — AttackHandler

### §A1 (P1) — bounded ticket eviction
`pruneTickets` evicted at most one ticket per call. A flood of
`attackId`s in one frame could grow the table beyond the 5-ticket cap
until enough subsequent prunes ran. Now loops while over cap.

### §A2 / §A3 / §A4 (Doc)
Lifecycle is already correct; documented for memory.

═══════════════════════════════════════════════════════════════════════
PHASE B — cosmetics / achievements / horde / lobby / equipment / UI
═══════════════════════════════════════════════════════════════════════

## §C — Cosmetics layer (CosmeticManager + VisualEquipmentManager)

Coverage was full but the system is in good shape. Findings are mostly
defensive notes.

### §C1 (Doc) — Two CharacterAdded paths in `CosmeticManager.Init`
`PlayerAdded` registers a CharacterAdded for every new joiner and the
"already-connected players" loop registers another for every existing
joiner. Each player only goes through one of those paths in practice
(PlayerAdded does not fire for already-connected players), so there is
no leak. Documented for future maintainers.

### §C2 (Doc) — `ApplyVisuals` re-reads `player.Character`
`ApplyPlayerVisuals` and `ApplyVisuals` both re-fetch `player.Character`
inside the function body, so a respawn during the 0.5 s settle wait is
safe (the new character is the one we apply to). No code change.

### §V1 (Doc) — `VisualEquipmentManager.AttachClassWeapon`
`ClearWeapon` calls `:Destroy()` on the previously-attached accessory.
Roblox `:Destroy()` is safe on already-destroyed instances, so the
respawn path (where the old accessory dies with the old character) is
fine.

### §V2 (P2, defer) — Armor accessories not yet shipped
`AttachClassArmor` is implemented but no place wires it. Body
appearance is already handled via `CosmeticManager` material/color
swaps. Logged in TODO for the day armor accessories ship.

---

## §AM — AchievementManager

### §AM1 (P0) — `isUnlocking` was MODULE-level, not per-player
Two players hitting unlocks in the same frame meant whichever one took
the `isUnlocking = true` lock would silently no-op the other player's
unlock. Replaced the bool with `isUnlocking[player]`, cleared on
`SaveAndCleanup` and after each `Unlock` returns.

### §AM7 (P1) — polling SetupPlayer replaced with `OnPlayerDataReady`
`SetupPlayer` polled `GetData` 30× × 0.5 s — same antipattern §L1 fixed
in V3. Now subscribes via `PlayerDataManager.OnPlayerDataReady`. Init
also invokes `SetupPlayer` directly for already-loaded players, with an
idempotency guard so the player can't be set up twice.

### §AM4 (Doc) — `OnWaveCompleted` MobSpawner-only hook
HordeMode uses HordeModeSpawner, not MobSpawner — so the
`wavesSurvived`/`highestWave` counters never advance during a horde
run. See `TODO_PARKING_LOT.md` for the proposed wire-up. (Defense
players still get progress as before.)

### §AM5 (Doc) — `OnKill` evaluates synchronously
Each kill calls `Evaluate` + `PersistNow` directly rather than going
through `scheduleEvaluation`. Heavy waves do many writes per second.
Acceptable for alpha; flag for telemetry.

---

## §DL — DailyLoginManager

### §DL1 (P0) — atomic claim lock
`CheckAndClaim` re-read `CanClaim` then mutated `lastClaimDate`, but a
spammy client could fire two `ClaimDailyLogin` packets in the same
frame, both pass `CanClaim`, and both grant rewards. Added a per-player
`claimLock` that rejects reentrant calls before any state read. The
date / streak mutation happens BEFORE reward grant so any race-loser
that slips through observes "claimed today".

### §DL2 (P1) — pcall the reward grant
Wrapped the merits/essence/respec-scroll grant in a pcall so a
downstream error doesn't strand the lock taken (lock is released in a
finally-style block).

### §DL3 (P2) — `data.Account` nil-guard in `CanClaim`
Defensive: if PlayerData is partially loaded, `CanClaim` returns false
instead of nil-deref'ing on `data.Account.DailyLogin`.

---

## §HM — HordeModeMain (server bootstrap)

### §HM1 / §HM10 (P1) — pause-aware run timer
The header comment promised "RUN_DURATION seconds of *play time*" but
the timer used a flat `task.wait(630)` — wall-clock — so 14 vote pauses
× 12 s = ~168 s of pause time was eating the run budget. Replaced with
a polling loop that subtracts `totalPauseDuration` (and the live
`os.clock() - pauseStartedAt` while in a pause window) from elapsed.

### §HM2 (P1) — OnPlayerReady polling → OnPlayerDataReady
`OnPlayerReady` polled `GetData` 20× × 0.5 s. Now subscribed via
`DataManager.OnPlayerDataReady`; the function is idempotent
(`_onPlayerReadyFired[player]` guard) so the in-game-already loop and
PlayerAdded fallback can't invoke it twice.

### §HM3 / §HM6 (P1) — local/global scope confusion
`OnStateChanged` was registered ABOVE the chunk's `local hordeStartTime
= os.clock()` declaration, which meant the closure's writes to
`hordeStartTime`/`totalPauseDuration`/`pauseStartedAt`/`hordeRunActive`
silently created GLOBALS instead of mutating the locals (vote loop /
run timer, declared later, captured the real locals). Net effect: the
"reset on entering Defending" branch was dead code. Hoisted the locals
above the OnStateChanged closure and converted the lower duplicate
declarations to plain assignments so the reset path now actually works.

### §HM11 (P1) — bounded mob-clear wait at run end
End-of-run loop spun `while MobAI.IsAnyMobAlive() do task.wait(1) end`
with no escape. A stuck mob would hang the entire end-of-run path
forever. Capped at 30 s with a warn before continuing to the lobby
teleport.

### §HM12 (P1) — don't `Resume()` after the run ended
The vote loop's pause-then-resume bracket called `HordePauseManager.
Resume()` unconditionally. If the run timer expired DURING a vote, the
end-of-run code already called `HordeModeSpawner.Stop()`; the vote
loop's tail Resume would call `Start()` again and spawn ghost mobs into
the mob-clear window. Now gates the Resume on `hordeRunActive`.

---

## §LN — LobbyNPCRegistry

### §LN1 (P0/P1) — alpha-launch matchmaking commander only had Defense
The "Commander Vex" matchmaking NPC's `modes = {...}` table only listed
`Defense`. Per Pablo's stated alpha plan ("teleport to correct mode
with right data"), Horde Mode is a launch headline mode and players
need to be able to queue for it from the lobby. Added a HordeMode
entry alongside Defense. CentralBoss is intentionally omitted — see
TODO_PARKING_LOT.md.

---

## §SC — SceneManager (lobby)

### §SC1 (Doc) — paired SetupPlayer paths
Same shape as §C1: PlayerAdded covers new joiners, the
already-connected loop covers existing. No double-connection.

---

## §NM / §QH / §SH — NPCManager + handlers

### §NM3 (P1) — ShopHandler nil-guards `_ShopManager`
`ShopHandler.HandlePurchase` called `_ShopManager.PurchaseCosmetic`
without checking that `_ShopManager` was non-nil. In any place that
loaded NPCManager but not ShopManager (LaneDefense currently does this
on the lobby path), the first shop purchase would nil-deref. Now
returns a clean "Shop unavailable in this scene" error.

### §QH1 (P1) — TurnInQuest dependency nil-guards
Reward grant blindly indexed `cm.AddMerits / pdm.AddExperience /
cfg.GetXPForLevel`. Each is now nil-checked; missing dep skips the
matching reward type rather than crashing.

### §QH2 (P1) — TurnInQuest atomic lock
Two simultaneous `TurnInQuest` packets could both pass the
"objectives complete" check and grant rewards twice. Added per-player
`turnInLock`. State mutation (SetActive false / SetCompleted true) now
happens BEFORE the lock release so any race-loser that slips through
trips the new "Quest is not active" guard.

### §QH5 (P0) — prerequisite bypass on AcceptQuest
`OnInteract` checked `quest.prerequisite` before sending the status to
the client, but `AcceptQuest` only consulted `GetQuestStatus`, which
does NOT inspect `quest.prerequisite`. Result: a malicious or replayed
client could send `AcceptQuest` for a locked quest and the server
would accept it. Mirror the prereq gate in `AcceptQuest`.

### §QH6 (P2) — `obj.count` nil-guard
`progress < obj.count` errors if a quest objective omits `count`.
Defaulted to 1 when missing.

---

## §ER / §ET — Equipment refinement & tier upgrade

These two factories are shared by both WeaponManager and ArmorManager
sub-systems, so each fix lands in two places at once.

### §ER1 (P0) — `SpendMerits` / `SpendEssence` return value ignored
`Attempt` called `CanAfford` then `Spend...` and *threw away the
return*. Concurrent attempts (or a balance race) would let the second
caller proceed to roll the refinement WITHOUT having paid (the second
spend returns false, but we ignored that). Fixed: abort with "Not
enough <currency>" when the spend returns false.

### §ER2 (P1) — Refinement attempt lock
Per-player `attemptLock` so two concurrent `Attempt` calls can't both
pass cost gates and both apply rolls. Released on every return path
including the success-pity, fail-stays, and fail-downgrade branches.

### §ET1 (P0) — same SpendMerits-return bug in `Upgrade`
Identical problem: `EquipmentTierSystem.Upgrade` ignored the spend
return value. Same fix.

### §ET2 (P1) — Tier upgrade attempt lock
`upgradeLock` per player.

---

## §WB / §AB — Weapon / Armor Bonus reroll

### §WB1 (P1) — Reroll lock missing
Two concurrent `Reroll` packets could both deduct merits and both
overwrite `weaponInstance.bonuses`. Player paid 2× for one set of
bonuses. Added `rerollLock`.

### §AB1 (P1) — same bug in ArmorBonusSystem
Identical fix mirrored.

---

## §UI — Client UI sweep

Most client UI is in good shape — `EquipmentUI`, `StatsMenu`,
`SettingsUI`, `KeybindSettings`, `EmoteWheel`, `TeammateVitals`,
`VoteUI`, `WardrobeUI`, `AchievementsUI`, `CombatApp`, `DeathUI`,
`ClassMenu`, `BattleClassUI`, `CharacterCreation` all properly
disconnect server-event subscriptions in `useEffect` cleanup and
cancel their refresh timers.

### §UI1 (P2) — Optimistic button text in `Overlays.client.lua` (Daily
Login `ClaimBtn`) and `SocialPanel.client.lua` (`CreatePartyBtn`)
The buttons set their label to "Claimed!" / "Party Created!" BEFORE
the server confirms. If the server rejects (e.g. already claimed
today) the UI still shows the success label. Defer until we wire a
proper `DailyLoginResult { ok = false }` UI path. Documented.

### §UI2 (P2/Doc) — `SocialPanel.client.lua` invite-button wiring is
dead
The `friendList.ChildAdded` handler expects `Frame` children with
`InviteBtn` descendants, but `populateFriendsList` only inserts
`TextLabel`s. The "invite friend" feature is not actually wired
through. Document; not on the critical path for alpha.

### §UI3 (P2) — `VoteUI` task.delay tasks not cancelled on unmount
The 3-second auto-dismiss `task.delay` chains in `VoteResult` and
`VoteResultPersonal` are not tracked by a ref and continue calling
`setVoteData` after unmount. React handles unmount-then-set-state
gracefully; minor warning at most.

### §U1 (closed) — `GlobalShopUI` already uses `formatCurrency`
The V3 §U1 fix is in place: `tostring(merits)` was replaced by
`formatCurrency(...)` in the currency badge.

---

## Files edited in V4 (Phase A + Phase B)

Phase A:
- `src/shared/ServerScriptService/Modules/SkillManager/init.lua`
- `src/shared/ServerScriptService/Modules/TalentManager.lua`
- `src/shared/ServerScriptService/Modules/GameStateManager.lua`
- `src/shared/ServerScriptService/Modules/DefenseLine/init.lua`
- `src/shared/ServerScriptService/Modules/ShopManager.lua`
- `src/shared/ServerScriptService/Modules/DropManager.lua`
- `src/shared/ServerScriptService/Modules/AttackHandler/init.lua`

Phase B:
- `src/shared/ServerScriptService/Modules/AchievementManager.lua`
- `src/shared/ServerScriptService/Modules/DailyLoginManager.lua`
- `src/hordemode/ServerScriptService/HordeModeMain.server.lua`
- `src/lobby/ServerScriptService/Modules/LobbyNPCRegistry.lua`
- `src/shared/ServerScriptService/Modules/NPCManager/ShopHandler.lua`
- `src/shared/ServerScriptService/Modules/NPCManager/QuestHandler.lua`
- `src/shared/ServerScriptService/Modules/EquipmentRefinement.lua`
- `src/shared/ServerScriptService/Modules/EquipmentTierSystem.lua`
- `src/shared/ServerScriptService/Modules/WeaponManager/WeaponBonusSystem.lua`
- `src/shared/ServerScriptService/Modules/ArmorManager/ArmorBonusSystem.lua`

---

## Pending / parking lot

See `docs/TODO_PARKING_LOT.md`. Notable V4 additions:

- **§AM4** — Wire HordeModeSpawner progression into AchievementManager
  (HordeMode currently doesn't increment `wavesSurvived` /
  `highestWave`).
- **§G5** — Late-joiner sees stale GameState (carried over from
  Phase A).
- **§D1** — Confirm `DefenseHealth.IsDestroyed` guard in TakeDamage
  for the post-destroy animation callback edge.
- **§HM3 (followup)** — The OnStateChanged "reset on Defending" branch
  is now functional, but in HordeMode the SetState("Defending") call
  happens before that callback is registered, so the FIRST entry
  isn't observed. Module-load assignment of the locals covers this in
  practice; flagged for future maintainers.
- **§UI1 / §UI2 / §UI3** — DailyLogin ClaimBtn pessimistic-confirm UX
  rewrite, SocialPanel invite-friend wiring, VoteUI task.delay
  cancellation.

---

_V4 Phase A: opened the combat / data / state surface that V1–V3
hadn't read fully. V4 Phase B: closed the cosmetics / achievements /
horde / lobby / equipment / UI surface. Alpha-blocking P0/P1 items
are now resolved across both phases._

═══════════════════════════════════════════════════════════════════════
LIVE-TEST FIXES (post-Phase B, on first lobby boot)
═══════════════════════════════════════════════════════════════════════

These were uncovered when Pablo did the first lobby playtest after V4.
Per his standing rule "when finding a bug, audit adjacent and connected
scripts" — each fix here was scoped to the immediate cause and to the
client/server pair it spans.

## §SR — SkillRegistry

### §SR1 (P0) — `CacheClassSkills` nil call on lobby boot
`SkillRegistry.Init` iterates `ClassSkills/*.lua`, requires each, and
called `classModule.GetAllSkills()` to populate the lookup cache.
That getter is INJECTED by `BaseSkills.InjectGetters(classModule)`,
which only runs from `classModule.Init(...)` — and that Init is only
called by `SkillManager.Init`, which the lobby place doesn't load at
all.
Effect: every lobby boot crashed at SkillRegistry:54 with
`attempt to call a nil value`, halting the lobby bootstrap.
Fix: have SkillRegistry require BaseSkills itself and call
`BaseSkills.InjectGetters(result)` before `CacheClassSkills`. Also
fall back to the class module's static `Skills` table if InjectGetters
isn't available, and made `GetSkillCount` resolution defensive.
Re-injection from SkillManager later is idempotent (it just rewrites
the same closures), so combat-place behaviour is unchanged.

## §EV — Client/server event-name drift (lobby)

Each of these caused a 3-second `WaitForChild` timeout on lobby boot
plus a "Event not found" warn — collectively ~18 s of needless boot
delay.

### §EV1 (P1) — `PartyInviteReceived` → `PartyInvite`
Server fires `PartyInvite` (PartyManager.lua:353); client subscription
in `Overlays.client.lua` used the legacy name.

### §EV2 (P1) — there is no `MatchFound` event
Client expected a separate `MatchFound` to hide the matchmaking bar.
Server only fires `MatchmakingUpdate` with `status ∈ {Queued,
Countdown, Launching, Cancelled, Error}`. Merged the bar-hide into the
MatchmakingUpdate handler when status is terminal.

### §EV3 (P1) — `OpenNPCDialog` / `CloseNPCDialog` → `NPCDialogue`
Server fires a single `NPCDialogue` with a `type` field (Dialogue,
ShopSuccess, ShopError, QuestAccepted, QuestCompleted, QuestError,
TeleportComplete). Client now reads the type and only opens the dialog
panel for actual dialogue payloads; transient outcomes hide it.

### §EV4 (P1) — `VoteStarted` / `VoteEnded` → `VoteStart` / `VoteResult`
Server emits `VoteStart` and `VoteResult`; the legacy names timed out.
The combat-place React VoteUI manages the inner panel itself; these
backdrop toggles cover the outer wrapper.

### §EV5 (P1) — `PartyUpdated` → `PartyUpdate`
SocialPanel.client.lua mismatch with `PartyManager.lua:618` and peers.

### §EV6 (P1) — `FriendsOnlineList` / `GetFriendsOnline` /
`GetPartyState` subscription guard
The friends pipeline is parking-lot work (no server emitter exists).
Wrapped the SocialPanel subscriptions and the on-visible refresh fires
in `Events:FindFirstChild(...)` checks so they no-op when the events
don't exist instead of hanging boot. Note: `GetPartyState` IS
registered in LobbyMain (line 240) and works as before — only the
friends-related events are gated out.

### §EV7 (P1) — `CreateParty` / `InviteToParty` → `PartyRequest` bus
Server routes party actions via a single `PartyRequest` event with an
`action` field (Create, Invite, AcceptInvite, DeclineInvite, Leave,
Kick, Promote, etc., per `PartyManager.HandleRequest`). Client was
firing legacy bare event names that the server doesn't listen on.

### §EV8 (P1) — `PartyInviteResponse` → `PartyRequest`
Same as §EV7 for the party-invite toast Accept/Decline buttons.
Now sends `{ action = "AcceptInvite" }` / `{ action = "DeclineInvite" }`.

### §EV9 (P1) — `CancelQueue` / `RequestJoinQueue` → `MatchmakingRequest`
Server routes matchmaking actions via `MatchmakingRequest` with
`action ∈ {Queue, Cancel}`. The PlayBtn handler also now translates
the displayed mode label ("Defense Mission", "Horde Mode") into the
canonical mode id the server expects, mirroring GameModeConfig.

### §EV10 (P1) — `RequestClassChange` → `RequestClassSwitch`
ClassManager.lua:93 listens on `RequestClassSwitch(player, className)`
where className is the second positional arg. The legacy client name
+ table payload silently no-op'd, so clicking a class switch button
in the lobby did nothing.

### §EV11 (P1) — `AllocateStat` payload shape
Server `SharedEventHandlers.lua:198` listens with the signature
`AllocateStat(player, statName, points)` and validates `type(statName)
== "string" and type(points) == "number"`. Client was firing a single
table payload (`{ stat = ... }`), which failed the type guard
silently. Now passes scalars.

### §EV12 (Doc) — outstanding click-time mismatches
The following client → server fires don't generate boot warnings (no
OnServerEvent subscription), but will silently fail when clicked:
`EquipItem` (server uses `EquipAccessory(player, itemId, slot)`),
`NPCDialogChoice` (server uses `NPCResponse` with `action` field),
`BuyShopItem` / `BuyGlobalShopItem` (server routes via `NPCResponse`
with `action = "Buy"` for NPC shops, or directly via `ShopPurchase`
for the global shop), `CastVote` (server uses `VoteCast`),
`ConfirmCharacterCreation` (no server emitter — feature wired by
`CharacterCreation.lua` differently). Logged for the next pass; not
boot-blockers, but the matching buttons in the lobby panels won't
work until aligned.

---

## §EH — EquipmentHandler (live-test, second lobby pass)

### §EH1 (P1) — `BuildSnapshot` nil index on armor XP
`EquipmentHandler.BuildSnapshot` did
`ArmorManager.GetSystems().XP.GetXPProgress(player)` to populate the
armor-side level / xp / required / maxLevel fields. But
`ArmorManager.GetSystems()` only returns
`{ Refinement, Tier, Bonus }` — armor was deliberately stripped of XP
(`init.lua:11`: "Armor XP was removed — only weapons level up").
Indexing `.XP` was nil and threw on every `GetEquipmentInfo` packet,
so the client EquipmentUI never received its snapshot. Now reads the
level / xp fields straight off the armor instance and pins
`required = 0`, `maxLevel = level` so the client UI's progress bar
collapses cleanly instead of showing a broken half-filled state.

## §UI — Lobby UI button sizing (Pablo: "nano buttons, can't click them")

Pablo's directive: every dimension must be in scale (%), not hardcoded
pixels. The HUD nav panel and the admin TestingUI both had pixel-sized
rows that collapsed to "nano" tap targets at higher resolutions.

### §UI-HUD1 / §UI-HUD2 — top-corner buttons
- Top-left ☰ menu button bumped from 3.5%×5% → 5%×7%.
- Right-side ⋮/✕ nav-toggle bumped from 5.5%×7.5% → 7%×9%.

### §UI-HUD3 — nav panel grid converted to pure-scale
The 12-button nav panel previously used
`AutomaticSize.Y` with a pixel-sized grid (`CellSize 0.47, -2, 0, 36`,
`CellPadding 0.02, 0, 0, 5`). On a 4K monitor that was a 36 px tall
button — unclickable. Now panel is `UDim2.fromScale(0.22, 0.62)`,
grid uses `CellSize fromScale(0.47, 0.135)` and
`CellPadding fromScale(0.02, 0.018)`, and each child button's Size
collapsed from `(1, 0, 0, 40)` to `fromScale(1, 1)` (the grid sizes
them anyway).

### §UI-T1 / §UI-T2 — TestingUI ActionButton + toggle
- `ActionButton`: was `Size = fromScale(w/1920, 0.026)` —
  ~140 × 28 px on 1080p, smaller on every other viewport. Now scaled
  relative to its parent ROW (Y=1), with X mapped to a fraction of
  row width via `clamp((w or 140)/420, 0.15, 1)`. `TextScaled = true`
  replaces the hardcoded `TextSize = 13`.
- TestingUI toggle button: was `0.046 × 0.024` with pixel-positioned
  offsets (210 px right of safe inset). Now `0.08 × 0.045` pure-scale
  with `fromScale(0.12, 0.005)` position; `TextScaled` enabled. Panel
  position aligned to the new toggle.

### §UI-T3 — InputRow re-laid in scale 3-column flex
`InputRow` (label / textbox / button) used hardcoded pixel positions
(`Position UDim2.new(0, 122, 0, 3)`, `0, 218, 0, 3`) and 32 px row
height, which made the input + button overlap at narrower viewports.
Now a 3-column scale layout: label 0–42%, textbox 43–70%, button
72–99%, all at 85% row height. Row Y bumped to `fromScale(1, 0.06)`.

### §UI-T4 — SectionHeader / Title / Divider / Feedback / row heights
All hardcoded heights (`UDim2.new(1, 0, 0, 20/22/28/34/66)`) replaced
with scale Y so the panel breathes proportionally:
section header 0.04, title 0.05, divider 0.005, feedback 0.04, row
0.06, classRow 0.12. Inline `note` labels in resetRow / wipeRow also
re-positioned in scale (40%/45% from left, 85% row height).
`UIListLayout.Padding` between class / misc / gender buttons changed
from `UDim.new(0, 8)` (8 px) to `UDim.new(0.02, 0)` (2% of row
width).

---

## Files edited (live-test pass)

First lobby pass:
- `src/shared/ServerScriptService/Modules/SkillRegistry.lua`
- `src/shared/StarterGui/AppGui/Controllers/Overlays.client.lua`
- `src/shared/StarterGui/AppGui/Controllers/SocialPanel.client.lua`

Second lobby pass:
- `src/shared/ServerScriptService/Modules/EquipmentHandler.lua`
- `src/shared/StarterPlayer/StarterPlayerScripts/UI/HUD.lua`
- `src/shared/StarterPlayer/StarterPlayerScripts/UI/TestingUI.lua`

