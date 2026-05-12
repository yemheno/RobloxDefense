# RobloxDefense — TODO

> Single canonical task list. Consolidated 2026-05-09 (post v0.5 commit) from
> ALPHA_AUDIT_REPORT, CODE_AUDIT_REPORT, REVISION_TRACKER, TODO_PARKING_LOT,
> SANITY_CHECK_REPORT V1-V4 (+ Phase A), and SYNTAX_DAMAGE_REPORT.
>
> History of those source documents lives in git — search the dev branch
> ancestry for `docs/SANITY_CHECK_REPORT*` etc.

---

## How to read this

- Items are grouped by **subsystem** so we can revise the codebase one system
  at a time. Within each section, items are sorted by priority.
- **Priority tags:**
  - `[P0]` ship-blocker — game-breaking; fix before any next playtest.
  - `[P1]` likely-visible bug or correctness issue; fix before alpha.
  - `[P2]` quality / future-proofing.
  - `[??]` open design decision — answer required before implementation.
  - `[🚀]` strategic / post-alpha scope.
  - `[📝]` doc-only / monitoring / audit.
- **Stable IDs:** `§<short-prefix><n>` from the original audit docs are
  preserved so the lineage is traceable. New items inherit fresh IDs.
- **Workflow:** when starting a section pass, mark its items `[in-progress]`
  in this file, work them, then mark `[done]` with a 1-line resolution note.
  Commit at the end of each section.

---

## Index

1. [Combat (Attack / Damage)](#1-combat-attack--damage)
2. [Skills / Casting](#2-skills--casting)
3. [Talents](#3-talents)
4. [Mob / AI / Spawning](#4-mob--ai--spawning)
5. [Death / Respawn](#5-death--respawn)
6. [Votes / Cards](#6-votes--cards)
7. [Party / Matchmaking / Teleport](#7-party--matchmaking--teleport)
8. [Shop / Currency](#8-shop--currency)
9. [Inventory / Equipment / Cosmetics](#9-inventory--equipment--cosmetics)
10. [Achievements / Leaderboard / Daily Login](#10-achievements--leaderboard--daily-login)
11. [Network / RemoteEvents](#11-network--remoteevents)
12. [Game State / Defense Line](#12-game-state--defense-line)
13. [NPC / Quest / Lore](#13-npc--quest--lore)
14. [Client UI](#14-client-ui)
15. [Persistence / Telemetry](#15-persistence--telemetry)
16. [Content Gaps (alpha-blockers)](#16-content-gaps-alpha-blockers)
17. [Strategic / Post-alpha](#17-strategic--post-alpha)
18. [Open Design Decisions](#18-open-design-decisions)

---

## 1. Combat (Attack / Damage)

- `[P1]` **§EV12** — Six client→server event-name mismatches still silently
  no-op buttons:
  - `EquipItem` → server expects `EquipAccessory(player, itemId, slot)`;
    inventory list UI must thread the slot.
  - `NPCDialogChoice` → server expects `NPCResponse{ npcId, action="Choice" }`.
  - `BuyShopItem` → NPC route via `NPCResponse{ action="Buy", itemId,
    quantity }`.
  - `BuyGlobalShopItem` → server uses `ShopPurchase{ itemId, kind, ... }`.
  - `CastVote` → server expects `VoteCast(slot)` / `VoteCastPersonal(slot)`
    (positional).
  - `ConfirmCharacterCreation` → no server emitter; CharacterCreation flow
    wires differently.
- `[??]` **Geometric multi-crit cap** — at 200% crit chance × 1.80×
  multiplier damage spikes to 5.83×. Intentional burst design or cap?
- `[??]` **Vulnerability stacking cap** — no upper bound on the
  vulnerability multiplier. Add ceiling (e.g., 2.0×)?
- `[??]` **ArmorReduction floor** — if `ArmorReduction ≥ 100%` mob armor
  becomes 0. Should there be a minimum floor?

## 2. Skills / Casting

- `[??]` **LifeSteward Genesis resource cost** — Genesis requires 70 min
  resource; all other ultimates require 80. Intentional healer leniency?
- *(§SR2 closed by T0.3 — `SkillRegistry` dropped from Lobby and SocialPlaza
  loadlists. Combat places still load it because they need SkillManager.)*

## 3. Talents

- `[🚀]` **300-node talent tree redesign** — see
  `docs/TALENT_TREE_PROPOSAL.md`. Replaces the live 13-node tree. Pablo's
  intent: revisit when we do the dedicated talent revision pass.
- `[P1]` **BonusTalentPoints dead branch** — `TalentManager` reads
  `data.Account.BonusTalentPoints` but nothing grants it. Either wire a
  real grant path (achievement rewards, daily streaks, horde victory) +
  add UI, or strip the field and add to `PlayerDataManager` deprecated-
  keys list.
- `[??]` **Class Mastery XP source** — `AddClassMasteryXP` was previously
  fed by overflow XP at chapter cap (T0.2 §PDM-D5: removed, per design
  intent "at hard cap, player XP stops; mastery has its own earn path").
  The function still exists in `PlayerLevelSystem.lua` granting bound
  tokens on milestones, but nothing calls it. Decide the source: e.g.
  (a) class-specific kill counters, (b) class quests completed at cap,
  (c) class-specific achievement progress. Wire when the class-mastery
  UX is designed.

## 4. Mob / AI / Spawning

- `[??]` **Wave 13+ procedural path** — `WaveConfig` has static defs for
  waves 1-12 then procedural generation. Untested. Confirm it's a
  supported game state or add a wave cap.
- `[🚀]` **Endless Horde / Infinite Defense** — `MobSpawner.CONFIG.MaxWave
  = 12`. Wave loop supports `MaxWave = nil` (infinite) but nothing else
  is wired. Proposal: new `src/endlessmode/` place reusing
  `HordeModeSpawner` with `MaxWave = nil`, procedural difficulty curve
  past 12, rebalanced reward pacing.

## 5. Death / Respawn

- `[P1]` **§2.4d — Respawn counter** — `data.respawnCount` not tracked.
  Add `data.respawnCount = data.respawnCount + 1` in
  `DeathSystem.HandleRespawnRequest` so we can (a) surface deaths in the
  end-of-run panel and (b) feed Achievements ("Die 100 times" / "Die 0
  times per run"). Small wire-up in AchievementManager listener.

## 6. Votes / Cards

- `[P2]` **§UI3 — VoteUI auto-dismiss task.delay not cancelled on unmount**
  — `VoteResult` and `VoteResultPersonal` schedule `task.delay` chains
  that keep calling `setVoteData(nil)` after unmount. React handles
  unmount-then-set-state with a warning, not a crash. Track each delay
  in a ref and cancel in `useEffect` cleanup like the timer countdowns.
- `[??]` **BountyBoard intent** — `ApplyTimedModifier("meritScalar", 1.0,
  30)` is additive making total 2.0× (doubling) for 30s. Confirm
  "2× merits for 30s" is the intended effect.

## 7. Party / Matchmaking / Teleport

- `[🚀]` **Multi-server matchmaking queue** — current queue is
  server-local. A solo player in an empty lobby server queueing for a
  5-player mode waits forever even if another server has 4 queueing for
  the same mode. Build cross-server queue on `MemoryStoreService`:
  - One sorted MemoryStoreQueue per `(modeId, difficulty)`.
  - Add on Queue, peek-and-claim atomically when forming a match.
  - Use `TeleportService:ReserveServer` so multiple lobby servers can
    rendezvous parties into one game-mode server.
  - Fall back to single-server matcher when MemoryStore is rate-limited
    (60 calls/min/player).
  - Companion UI: clear "Find Match" button on the main lobby HUD that
    fires `MatchmakingRequest{ action="Queue" }` with the selected
    mode/difficulty. Reuses `PartyManager.EnsureParty` so solo players
    don't need to manually create a party first.
- `[P2/Doc]` **§EV6 Friends-online pipeline never wired** —
  `FriendsOnlineList`, `GetFriendsOnline` events have no server emitter.
  SocialPanel subscriptions guarded with `Events:FindFirstChild` so they
  no-op cleanly. Either wire a real friends-online provider or rip the
  client subscription.

## 8. Shop / Currency

- `[P1]` **§2.6 ShopManager full review** — V2 audit noted the module but
  did not dig in. Open concerns:
  - Does purchase validate currency atomically? (race with SpendMerits)
  - Are stock limits enforced server-side?
  - Does the shop refresh snap to a server clock so players can't dodge
    rotation by reconnecting?

## 9. Inventory / Equipment / Cosmetics

- `[P2]` **§V2 — AttachClassArmor implemented but never wired** —
  `VisualEquipmentManager.AttachClassArmor` works; no caller. Body
  appearance is currently CosmeticManager material/color swaps. When
  real armor visuals ship, also handle the `ServerStorage.Armors`
  lazy-load path.
- `[🚀]` **Headgear "model" visual type stub** —
  `ApplyHeadgearVisual()` has no implementation for `visual.type ==
  "model"`. Reserved for future accessory models.
- `[P2]` **§VEM-DEDUPE re-check** — T0 live test shows `AttachClassWeapon`
  still fires 2× on player spawn (down from 3× pre-§VEM-DEDUPE but not 1×
  as intended). Both attaches complete the clone+weld pipeline. The
  dedupe early-return condition (same class+slot already attached and
  clone still parented) isn't catching the second call. Investigate
  during Tier 6 equipment pass — likely a race between the first
  attach's parenting and the second call's dedup check.
- `[🚀]` **Accessories — post-alpha polish** — equip pcall + rollback
  already landed in §2.5c. Deeper:
  - Per-slot rarity tiers and how they stack with the 2×Ring constraint.
  - Socketing / gem system (currently a stub).
  - Client UI: show active-set bonuses in `StatsMenu` rather than just
    raw mods.
- `[🚀]` **Boss-drop accessories — design** — each boss in the game
  should drop a unique accessory so equipment stays relevant in late
  stages. Goal: each boss is independently meaningful, players grind
  bosses individually for their distinct accessory rewards. Wire after:
  (a) CentralBoss authored content lands, (b) AccessoryConfig grows the
  full boss-drop set, (c) DropManager learns about per-boss accessory
  pools.
- `[P2]` **§CFG-UI — Verify equipment UI after GearUpgradeConfig refactor**
  — the shared `EquipmentRefinement` / `EquipmentTierSystem` factories
  still build the same payload (`{ currency, cost, isCeiling,
  ceilingBelow, isMax, ... }`), and `EquipmentHandler.BuildSnapshot`
  still feeds the same data to the client. UI should be unaffected, but
  smoke-test the WeaponSmith + EquipmentUI panels (refine attempt
  display, tier upgrade gate, reroll cost) after the next playtest just
  to be sure no display field went stale.
- `[P2]` **§RG-MIGRATION (cosmetics + equipment)** — push events still
  bypass ReadyGate. Migrate (in order):
  1. CosmeticManager — `WardrobeUpdate` push during PlayerAdded.
  2. EquipmentHandler — `EquipmentInfo` reply.
  3. WeaponManager.EnsureStarterWeapon — `WeaponEquipped` during
     PlayerAdded; current symptom: "weapon icon not showing on first
     spawn" intermittent.
  4. ArmorManager.EnsureStarterArmor — `ArmorEquipped` same shape.

## 10. Achievements / Leaderboard / Daily Login

- `[P1]` **§AM4 — HordeMode never advances `wavesSurvived` /
  `highestWave`** — AchievementManager hooks `MobSpawner.OnWaveCompleted`,
  but HordeMode runs via `HordeModeSpawner` which has no equivalent
  event. Either (a) emit synthesised `OnWaveCompleted` from
  `HordeModeMain` whenever horde level increments
  (`HordeModeSpawner.GetLevel()` exists), or (b) add explicit
  `HordeModeSpawner.OnLevelUp(callback)` and rename the achievement
  stat to `wavesOrLevelsSurvived`. Option (a) is the cheaper retrofit.
- `[P2]` **§RG-MIGRATION (achievements)** — `AchievementManager.SendData`
  is request-driven, low risk; the unlock-toast push isn't and should
  migrate.
- `[📝]` **§AM5 — `OnKill` evaluates synchronously** — each kill calls
  `Evaluate` + `PersistNow` directly rather than going through
  `scheduleEvaluation`. Heavy waves do many writes per second.
  Acceptable for alpha; flag for telemetry.

## 11. Network / RemoteEvents

- `[P2]` **§RG-MIGRATION — boot-race push events** — five callsites still
  fire on PlayerAdded/CharacterAdded before client subscriptions exist.
  Listed under §9/§10. ResourceManager initial `ResourceUpdate` is
  already in `BYPASS_EVENTS` (fine).
- `[📝]` **Per-remote rate-limit coverage audit** — V1 §3.7. NetworkManager
  has a 30/sec/event/player rate limiter; verify it's tuned
  appropriately for every legitimate spam-heavy event (combat hits, mob
  damage reports, etc.) and not too generous on cheap-to-replay events
  (votes, equips). [Closed by §NM-D1 in T0.1 sweep — per-event limits
  introduced; revisit if a new event surfaces a drop-bug.]
- `[P1]` **§NM-D6 — Hang-recovery UI when client `WaitForChild` stalls** —
  the boot-race fix in client `NetworkManager` waits indefinitely for
  events. If the server is genuinely broken (crashed, bad deploy) the
  client just sits there. Add a threshold-based "Connection issue —
  retrying..." prompt + a retry button. Threshold needs UX care so we
  don't kick slow PCs/mobiles mid-load; suggested 30s as a starting
  point with the prompt being non-modal.
- `[P1]` **OnReady → loading-screen dismiss wiring** —
  `ReadyGate.OnReady(callback)` is the right hook to gate the
  loading-screen dismiss on "client + server both ready." When the
  loading screen ships, register an OnReady handler that fades the
  screen out; until then, OnReady is unused. Cross-references
  §NM-D5 (xpcall wrap landed in T0.1 so a callback failure can't strand
  the player on the loading screen).

## 12. Game State / Defense Line

- `[P1]` **§G5 — Late joiner sees stale GameState** — a player who joins
  during Victory/Defeat misses the `GameStateChanged` event (fired
  before they connected). HUD shows IDLE but server is in
  VICTORY/DEFEAT, so respawn / return-to-lobby UI is wrong. On
  `Players.PlayerAdded`, fire `GameStateChanged` addressed only to the
  new player with current state and elapsed time. Or: HUD client
  `RequestState` on mount and server replies.
- *(§HM3-followup closed by T0.3 §PB-D3 — HordeMode's `SetState("Defending")`
  now fires AFTER the `OnStateChanged` callback is registered, so the
  first entry of the run is observed correctly by the reset closure.)*

## 13. NPC / Quest / Lore

- `[P0]` **Ultimate skills `ultimateLocked = false` for testing** — all
  four `ClassSkills/*.lua` files have ultimates unlocked for testing.
  Set to `true` before production; wire unlock logic into a mission
  system.
- `[P1]` **Quest & lore progress not persisted** — quest progress and
  lore flags (`TalkedTo_*`) live in player `Attributes` (lost on
  rejoin). Migrate to `PlayerDataManager`.

## 14. Client UI

- `[P2]` **§UI1 — DailyLogin / CreateParty optimistic button text** —
  `Overlays.client.lua` (`ClaimBtn`) and `SocialPanel.client.lua`
  (`CreatePartyBtn`) swap to "Claimed! ✓" / "Party Created! ✓"
  immediately on click, before server confirms. A server-side rejection
  leaves the success label up. Move the success label change into the
  `DailyLoginResult{ ok=true }` / `PartyUpdated` handler; on
  `{ ok=false }` re-enable the button with the original label and
  display the reason.
- `[P2]` **§UI2 — SocialPanel invite-friend wiring is dead** —
  `SocialPanel.client.lua:107-115` watches the friend list for `Frame`
  children with `InviteBtn` descendants, but `populateFriendsList` only
  inserts `TextLabel`s. Either rebuild the list to use a Frame-per-
  friend layout with `InviteBtn`, or remove the dead handler. Defer
  until the party UX gets a polish pass.
- `[P1]` **CharacterManager.ApplyTemplate visual swap stub** — TODO needs
  the rig swap when gendered/class-specific rigs are available.
- `[P2]` **§PDM-D11 — Combat-time stat allocation confirmation** — today
  nothing gates `AllocateStat` during knockdown / combat. A player can
  open the stats panel mid-fight and reassign points. Add a client-side
  "Are you sure? Allocate during combat?" confirmation prompt with a
  1-minute cooldown (after confirming, the prompt doesn't reappear for
  the next minute). Pure UI — server stays as-is.
- `[P2]` **Class unlock toast** — `CheckAndUnlockEligibleClasses` fires
  on level-up and silently inserts into `data.Account.UnlockedClasses`.
  Player only sees the unlock when they open the class menu. Fire a
  `ClassUnlocked` push event (ReadyGate route) so the client can show
  a toast at the moment of unlock. Tier-10 UI work.
- `[P1]` **"All players ready" gate before combat starts (§PB-D3)** — today
  HordeMode auto-transitions to `Defending` on bootstrap (so the HUD's
  manual "Start Game" button never appears). LaneDefense and CentralBoss
  follow a similar pattern. With multi-player parties this can land
  before slower clients have mounted their UI — they miss the first
  events / animations. Wire a per-combat-mode gate: server waits for
  every party member to fire `ClientReady` (or an explicit
  `RequestStartGame`), THEN transitions to Defending. Affects all three
  combat places.
- `[??]` **Player progression measurement — Power vs. Engagement (design)**
   — Power Score (`GearRating.GetDisplayPower`) is the headline number
   players see (leaderstat, leaderboard ranking). Two design problems
   to solve together:
   1. **Wiring:** `PlayerDataManager.RefreshPowerScore` is currently
      only called from SetupPlayer + Level change. Equipment / refine /
      tier-up / talent / accessory changes don't refresh it yet, so the
      Power leaderstat lags behind real gear changes until the next
      level-up. Need a refresh call at every gear-changing site (or a
      BonusManager.OnRecalculated callback that we subscribe to).
   2. **Class development / engagement metric** — Power alone doesn't
      capture how *engaged* a player is with a class. Two players could
      have identical Power but one has 200 weapon levels + 80 class
      achievements while the other has cap-level gear and no
      achievements. Probably want a second visible number ("Mastery"
      or "Class Score") that combines:
       - weapon XP across the active class's weapons (or all weapons?)
       - class-specific achievement tier progression
       - talents allocated for this class
       - cap-mastery boss kills
      Decide the formula + display when we hit Tier 8 Progression.
      Note: GearRating already has a "M (mastery)" component from
      `data.Classes[c].MasteryXP` — currently zero because no source
      feeds it (TODO §3 "Class Mastery XP source"). Resolving that
      design unlocks this too.

## 15. Persistence / Telemetry

- `[P1]` **HitTracker.SaveLifetimeStats stub** — prints stats but does
  not persist to DataStore. Wire the save path or remove the method.
- `[📝]` **DataStore save reliability under disconnect** — never audited
  end-to-end. Add a check-and-retry path with a session-end log.
- `[📝]` **Telemetry confirmation for first-50-tester data** — confirm
  `MonitoringSystem` is wired for at least: session length, wave
  reached, deaths, class picked, currency earned. We'll want this data
  the moment we open the alpha.

## 16. Content Gaps (alpha-blockers)

- `[P0]` **Class basic-attack animations** — three of four classes share
  `rbxassetid://128777973` (R6 Wave) placeholder. Author per-class
  attack animations; update `AnimationConfig.Player.Classes`.
- `[P0]` **Mob variety** — three mob types total (Zombie/Troll/Ogre) with
  Zombie as the sole weighted spawn across all 12 waves. Troll/Ogre
  only appear as guaranteed miniboss injections. Wave 7 is mechanically
  identical to wave 1, just with bigger numbers. Add 2-3 new mob types
  with elemental variety.
- `[P0]` **SoundManager — 28 entries pointing at `rbxassetid://0`** —
  needs at minimum 11 SFX (basic attack hit, skill cast, mob death,
  player damage, level up, vote start/end, currency pickup, UI open/
  close, button click, victory).
- `[P1]` **Headgear "model" visual type stub** — see §9.

## 17. Strategic / Post-alpha

- `[🚀]` **CentralBoss authored content** — place loads modules but has
  no authored boss fight. Pick a boss, author phases, wire telemetry +
  rewards. Post-alpha; HordeMode is the alpha headline mode.
- `[🚀]` **Endless Horde mode** — see §4.
- `[🚀]` **Multi-server matchmaking queue** — see §7.
- `[🚀]` **Talent tree 300-node redesign** — see §3 + proposal doc.
- `[🚀]` **Accessories v2** — rarity, socketing, set-bonus UI, see §9.

## 18. Open Design Decisions

These are questions that need an answer before the relevant subsystem
revision pass. Each is also referenced in its system section above.

1. **Geometric multi-crit cap** — see §1.
2. **Vulnerability stacking cap** — see §1.
3. **HealingSystem uses Damage stat** — `HealingSystem.lua` calculates
   healing power from the `"Damage"` stat (not a dedicated healing
   stat). Intentional (damage = magic power for healers) or split into
   a dedicated `HealingPower` stat?
4. **BountyBoard 2× intent** — see §6.
5. **ArmorReduction floor** — see §1.
6. **Re-enable weapon/armor XP** — comment says "scaling consequences
   not yet validated." Complete for alpha or remain disabled? Note:
   armor XP was ultimately removed (`ArmorManager/init.lua:11`); re-add
   only if balance work is also done.
7. **LifeSteward Genesis resource cost** — see §2.
8. **Wave 13+ procedural support** — see §4.

---

## Already-resolved (kept here briefly so we don't re-audit)

The following clusters from V1-V4 + earlier work are confirmed closed in
v0.5 — listed only in case future work intersects them:

- §A1-A4 AttackHandler ticket lifecycle (incl. CharacterAdded reset and
  DeathState→Alive reset for in-place respawn).
- §S1-S5 SkillManager request-lock + cast-interrupt + leave guards.
- §T1-T2 Talent respec deduct-first + AllocateNode lock.
- §G2 GameStateManager idempotent ReturnToLobby.
- §D2 DefenseLine LateInit idempotency.
- §Sh1-Sh3 ShopManager deduct-first + concurrent-purchase lock.
- §Dr1 DropManager Parent guard.
- §AM1, §AM7 AchievementManager per-player unlock lock + OnPlayerDataReady.
- §DL1-DL3 DailyLoginManager atomic claim lock + pcall + nil-guard.
- §HM1-HM3, §HM6, §HM10-HM12 HordeModeMain pause-aware run timer + scope
  fixes + bounded mob-clear + post-run resume guard.
- §LN1 LobbyNPCRegistry Commander Vex Horde mode wiring.
- §NM3, §QH1-QH6 NPC handler guards + atomic quest turn-in + prereq fix.
- §ER1-ER2, §ET1-ET2, §WB1, §AB1 Equipment refinement / tier / reroll
  spend-return guards + locks.
- §SR1 SkillRegistry self-sufficient lobby boot.
- §EV1-EV11 Lobby client/server event-name drift fixes.
- §EH1 EquipmentHandler armor-XP nil-deref.
- §UI-T*, §UI-HUD*, §LD-BC*, §LD-DS5/DS6, §LD-PA1, §LD-VE3/6/7/8, §LD-W2,
  §LD-RG1, §LB2/LB3, §PERSIST1, §VG2/VG3/VG4/VG5, §HMS-DIR1-3, §FRENZY1,
  §NM-CLIENT-RACE, §A2/A3, §VEM-DEDUPE, all the live-test pass fixes.

Lineage of these resolutions lives in the v0.5 commit message and in
git history of the deleted audit reports.
