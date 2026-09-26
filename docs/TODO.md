# RobloxDefense — TODO

> Single canonical task list. Consolidated 2026-05-09 (post v0.5 commit) from
> ALPHA_AUDIT_REPORT, CODE_AUDIT_REPORT, REVISION_TRACKER, TODO_PARKING_LOT,
> SANITY_CHECK_REPORT V1-V4 (+ Phase A), and SYNTAX_DAMAGE_REPORT.
>
> History of those source documents lives in git — search the dev branch
> ancestry for `docs/SANITY_CHECK_REPORT*` etc.
>
> **Reconciled 2026-09-26** against the agency-checks session
> (`0e6d15e..b0bdbee`): resolved items were moved to "Already-resolved",
> partial ones carry a dated *(Partial …)* note, and the new follow-ups
> are in §20.

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
9b. [Character Creation / Appearance](#9b-character-creation--appearance-tier-1)
10. [Achievements / Leaderboard / Daily Login](#10-achievements--leaderboard--daily-login)
11. [Network / RemoteEvents](#11-network--remoteevents)
12. [Game State / Defense Line](#12-game-state--defense-line)
13. [NPC / Quest / Lore](#13-npc--quest--lore)
14. [Client UI](#14-client-ui)
14d. [Stats / Damage / Healing follow-ups (Tier 1.3)](#14d-stats--damage--healing-follow-ups-tier-13)
14c. [Class system follow-ups (Tier 1.2)](#14c-class-system-follow-ups-tier-12)
14b. [Memory & Lifetimes (Janitor audit)](#14b-memory--lifetimes-janitor-audit)
15. [Persistence / Telemetry](#15-persistence--telemetry)
16. [Content Gaps (alpha-blockers)](#16-content-gaps-alpha-blockers)
17. [Strategic / Post-alpha](#17-strategic--post-alpha)
18. [Open Design Decisions](#18-open-design-decisions)
19. [T0 Pass-2 follow-ups (§T0P2)](#19-t0-pass-2-follow-ups-t0p2)
20. [Agency-checks follow-ups (§AGX)](#20-agency-checks-follow-ups-agx-2026-09-26)

---

## 1. Combat (Attack / Damage)

- ~~§EV12~~ **MOOT (§EASY sweep):** all six wrong-name emitters live in
  the DISABLED legacy StarterGui controllers (§T10/STACK); the React UIs
  fire the correct names. Original list kept for the legacy-archive PR:
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
  *(2026-09-26 reconcile: stale. `AddClassMasteryXP` was DELETED by
  §T0P2/X21, see `PlayerLevelSystem.lua:101-104`; the data fields and
  `ClassMasteryConfig.lua` remain, tracked as §T0P2-MASTERY in §19.)*
  Decide the source: e.g.
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

- `[P2]` **§2.4d — Respawn counter: TRACKED (§EASY sweep), consumers
  pending.** `data.respawnCount` now increments in HandleRespawnRequest.
  Remaining: (a) end-of-run panel surfacing, (b) Achievements wire
  ("Die 100 times" / deathless-run). Note: the horde spawn-proximity
  failsafe Pablo associates with this is a DIFFERENT, working system
  (HordeModeSpawner spawnDebt).

## 6. Votes / Cards

- ~~§UI3~~ **DONE (§EASY sweep):** mountedRef guard added to both
  auto-dismiss delays in VoteUI.
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
  - *(Partial, 2026-09-26:)* the ReserveServer step exists for the
    server-local queue: `TeleportManager.lua:218`
    (`ShouldReserveServer = true`) and the public-server bounce in
    `TeleportDataReader.lua:24-32` (2329bbd, §AGX/X4). The Lobby also has
    a PLAY entry (MenuSheet, 52d7fb3) and one "Play <mode>" button in
    MainMenu (582dff1). Still to do: the cross-server MemoryStore queue
    itself.
- ~~§EV6~~ **SUPERSEDED (§EASY sweep):** those subscriptions belong to
  the disabled LEGACY panel. The React SocialPanel already does what
  Pablo asked (friends sorted first via IsFriendsWith + Invite button
  per row) for players IN the lobby. `[🚀]` future: list friends who
  are online in the experience but in OTHER servers (needs presence
  API + follow/teleport-to-friend design).

## 8. Shop / Currency

- `[P1]` **§2.6 ShopManager full review** — V2 audit noted the module but
  did not dig in. Open concerns:
  - Does purchase validate currency atomically? (race with SpendMerits)
  - Are stock limits enforced server-side?
  - Does the shop refresh snap to a server clock so players can't dodge
    rotation by reconnecting?
  - *(Partial, 2026-09-26:)* (1) is answered: there is a per-player
    purchase lock (`ShopManager.lua:118-129`) and the spend happens before
    the grant (`:183-189`, §Sh1). This session added server-side
    `enabled` (§AGX/X34, `:148-149`, `:314-316`), unusable consumables
    refused (§AGX/X10, `:233-239`) and raw-Merit refunds (§AGX/X32,
    `:205`, `:279`) in 36cd218, and routed Robux through
    `MonetizationService` (1c6e333). (2) and (3) have no code to review:
    `ShopConfig` has no stock or rotation state (grep finds none), so
    they belong to §DISC/D7. Still to do: re-review when D7 lands.

## 9. Inventory / Equipment / Cosmetics

- ~~§V2~~ **DONE (§EASY/E3, Pablo's #6):** AttachClassArmor now wired
  from ArmorManager.EnsureStarterArmor (both returning-player and
  starter-grant branches → covers login + class switch + respawn via
  ReattachAll). Root cause was a PATH bug: VEM looked up
  `ServerStorage.Armors` but assets live at `ServerStorage.Models.Armors`
  — fixed with fallback; per-class `<Class>_a<slot>` assets preferred,
  `DefaultArmor` stub as fallback. `[P1/Art]` author per-class armor
  models when ready.
- `[🚀]` **Headgear "model" visual type stub** —
  `ApplyHeadgearVisual()` has no implementation for `visual.type ==
  "model"`. Reserved for future accessory models.
- ~~§VEM-DEDUPE~~ **ROOT-CAUSED + FIXED (§T5-T9/S6):** the 2× was two
  CharacterAdded connections wired per player (PlayerAdded handler +
  existing-players loop both fired for Init-window joiners). Single
  wire-per-player now. Verify 1× in the next live test, then delete
  this entry. *(Still unverified as of 2026-09-26; nothing has run in
  Studio since. Check it during the §20 Studio pass.)*
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
  (a) CentralBoss authored content lands (partly done: Iron Warden
  placeholder, b19cec8, see §17), (b) AccessoryConfig grows the
  full boss-drop set, (c) DropManager learns about per-boss accessory
  pools.
- `[P2]` **§CFG-UI — Verify equipment UI after GearUpgradeConfig refactor**
  — the shared `EquipmentRefinement` / `EquipmentTierSystem` factories
  still build the same payload (`{ currency, cost, isCeiling,
  ceilingBelow, isMax, ... }`), and `EquipmentHandler.BuildSnapshot`
  still feeds the same data to the client. UI should be unaffected, but
  smoke-test the WeaponSmith + EquipmentUI panels (refine attempt
  display, tier upgrade gate, reroll cost) after the next playtest just
  to be sure no display field went stale. *(2026-09-26: EquipmentUI and
  WeaponSmithUI were re-skinned to Theme v2 in 05c1b9e and 582dff1, with
  the same payloads. Still a smoke test; it is covered by
  `docs/STUDIO_TEST_PLAN.md` §7.)*
- ~~§RG-MIGRATION (cosmetics + equipment)~~ **Resolved:** moved to
  "Already-resolved" (2026-09-26 reconcile).
- *(§T1.1/D7 closed — `CharacterCreationRequired` now routes through
  ReadyGate. Was the suspected cause of "character creation panel
  intermittently fails to appear on first join.")*

## 9b. Character Creation / Appearance (Tier 1)

- `[🚀]` **§T1.1-CC1 — 3 body / 3 head / 3 hair models per gender** —
  schema seams exist (`CharacterData.{bodyModel, headModel, hairModel}`
  and `CharacterConfig.{Body,Head,Hair}ModelCount`); only the default
  asset ships today. Author 6 body, 6 head, 6 hair templates (3 per
  gender). Update `CharacterConfig.GetTemplateName` to fan out by slot
  index. Hair models intended to use occlusion-only meshes paintable
  with any `Color3` via `CharacterData.hairColor`.
- `[🚀]` **§T1.1-CC2 — Hair & clothing color palettes** —
  `CharacterConfig.HairColors` and `ClothingColors` are empty seams.
  Populate when the corresponding models ship. CharacterCreation UI
  needs to pick them up the same way it picks up `SkinColors` today.
- `[P2]` **§T1.1-CC3 — Wire gendered class titles to UI** —
  `CharacterManager.GetClassTitle` returns "Huntress" / "Arcaness" /
  "Life Stewardess" for female players. Most UI panels still hard-code
  the masculine form. Audit ClassMenu, StatsMenu, ClassReferencePanel,
  leaderboard, leaderstats, etc.
- `[🚀]` **§T1.1-CC4 — Appearance Preset Pages (monetization)** —
  monetize saved appearance snapshots ("preset pages"). Each preset
  saves: gender, bodyModel, headModel, hairModel, skinColor, hairColor,
  clothingColor, plus equipped cosmetic loadout. New PlayerData field
  `AppearancePresets = { [pageId] = { ...snapshot } }`. UI: tab in the
  appearance menu, pages unlocked via shop/Robux. Distinct from the
  base CharacterData (which holds the "current" appearance).
- `[P2]` **§T1.1-AE1 — Standardize accessory equipment pipeline** — the
  hair-accessory weld dance in `CharacterManager.ApplyTemplate` (steps
  3–4) is the proven pattern that fixed both hair AND the held-weapon
  weld bug. Today it lives inline. Extract to a shared helper (e.g.
  `Modules/AccessoryWelder.lua`) and route VisualEquipmentManager +
  CosmeticManager through it. **Do not "simplify"** — the dance reads
  AccessoryWeld values BEFORE cloning, destroys pre-existing welds on
  the clone, parents, waits a frame for Roblox to inject its single
  weld, then over-writes Part0/Part1/C0/C1. Every step is load-bearing.

## 10. Achievements / Leaderboard / Daily Login

- ~~§AM4~~ and ~~§RG-MIGRATION (achievements)~~ **Resolved:** moved to
  "Already-resolved" (2026-09-26 reconcile). The Horde/Lane HighestWave
  off-by-one that came out of the §AM4 fix is in §20.
- `[📝]` **§AM5 — `OnKill` evaluates synchronously** — each kill calls
  `Evaluate` + `PersistNow` directly rather than going through
  `scheduleEvaluation`. Heavy waves do many writes per second.
  Acceptable for alpha; flag for telemetry.

## 11. Network / RemoteEvents

- ~~§RG-MIGRATION — boot-race push events~~ **Resolved:** moved to
  "Already-resolved" (2026-09-26 reconcile).
- `[📝]` **Per-remote rate-limit coverage audit** — V1 §3.7. NetworkManager
  has a 30/sec/event/player rate limiter; verify it's tuned
  appropriately for every legitimate spam-heavy event (combat hits, mob
  damage reports, etc.) and not too generous on cheap-to-replay events
  (votes, equips). [Closed by §NM-D1 in T0.1 sweep — per-event limits
  introduced; revisit if a new event surfaces a drop-bug.]
- ✅ *(Done 2026-09-26, §AGX/UI-FREE: 15 s ServerReady watchdog in client
  NetworkManager raises a sticky Notify banner with a Rejoin action; clears
  with a "Connected." toast.)* **§NM-D6 — Hang-recovery UI when client `WaitForChild` stalls** —
  the boot-race fix in client `NetworkManager` waits indefinitely for
  events. If the server is genuinely broken (crashed, bad deploy) the
  client just sits there. Add a threshold-based "Connection issue —
  retrying..." prompt + a retry button. Threshold needs UX care so we
  don't kick slow PCs/mobiles mid-load; suggested 30s as a starting
  point with the prompt being non-modal. *(Still open, 2026-09-26: the
  client `StarterPlayerScripts/Modules/NetworkManager.lua` has no timeout
  prompt. LoadingScreen's 25 s failsafe only dismisses the overlay. The
  new `Notify` banner (dfefb37) is the obvious place for the non-modal
  prompt.)*
- ~~OnReady → loading-screen dismiss~~ **DONE (§T10/U1):** LoadingScreen
  shipped; dismissal rides the ReadyGate-routed ServerReady in each
  place client (equivalent hook, client-side), 25 s failsafe included.
  ReadyGate.OnReady stays available as a server-side seam.

## 12. Game State / Defense Line

- ~~§G5 — Late joiner sees stale GameState~~ **Resolved:** moved to
  "Already-resolved" (2026-09-26 reconcile).
- *(§HM3-followup closed by T0.3 §PB-D3 — HordeMode's `SetState("Defending")`
  now fires AFTER the `OnStateChanged` callback is registered, so the
  first entry of the run is observed correctly by the reset closure.)*

## 13. NPC / Quest / Lore

- ~~Ultimate skills unlock~~ **DONE (§EASY/E1, Pablo: base level 10):**
  server gate in SkillManager's ultimate branch — below level 10 the
  cast is rejected with "Ultimate unlocks at level 10". (The old
  `ultimateLocked` flag never existed in the code — stale entry name.)
  `[P2/UI]` later: dim/lock the ultimate slot client-side pre-10.
  *(Still open, 2026-09-26: the new `UI/Common/SkillPad.lua` and
  `ActionBar.lua` (610f9ac) dim by cost and cooldown only, with no level
  check.)*
- `[P1]` **Quest & lore progress not persisted** — quest progress and
  lore flags (`TalkedTo_*`) live in player `Attributes` (lost on
  rejoin). Migrate to `PlayerDataManager`. *(Partial, 2026-09-26
  reconcile: quests ARE persisted in `data.Account.Quests`
  (`NPCManager/QuestHandler.lua:21,65-76`, since d862558). Still to do:
  lore only. `LoreHandler.lua:62` sets `TalkedTo_<id>` as an attribute,
  and nothing in `src/` reads it, so there is no visible bug today.
  Could drop to P2 until a lore reader exists.)*

## 14. Client UI

- ~~§UI1 — DailyLogin / CreateParty optimistic button text~~
  **Resolved:** moved to "Already-resolved" (2026-09-26 reconcile).
- ~~§UI2~~ **MOOT (§EASY sweep):** that wiring is the disabled LEGACY
  panel's. The React SocialPanel already renders Frame-per-player rows
  with Invite buttons, friends sorted first (Pablo's #5 confirmed
  in-place for in-server friends; cross-server listing parked under the
  §EV6 successor note above).
- *(§T1.1 closed — `CharacterManager.ApplyTemplate` now properly fans
  out by `bodyModel` / gender via `CharacterConfig.GetTemplateName`,
  with schema seams for headModel, hairModel, and the three color
  slots. Awaiting authored assets — see §T1.1-CC1.)*
- `[P2]` **§PDM-D11 — Combat-time stat allocation confirmation** — today
  nothing gates `AllocateStat` during knockdown / combat. A player can
  open the stats panel mid-fight and reassign points. Add a client-side
  "Are you sure? Allocate during combat?" confirmation prompt with a
  1-minute cooldown (after confirming, the prompt doesn't reappear for
  the next minute). Pure UI — server stays as-is.
- ~~Class unlock toast~~ **Resolved:** moved to "Already-resolved"
  (2026-09-26 reconcile).
- `[P1]` **"All players ready" gate before combat starts (§PB-D3)** — today
  HordeMode auto-transitions to `Defending` on bootstrap (so the HUD's
  manual "Start Game" button never appears). LaneDefense and CentralBoss
  follow a similar pattern. With multi-player parties this can land
  before slower clients have mounted their UI — they miss the first
  events / animations. Wire a per-combat-mode gate: server waits for
  every party member to fire `ClientReady` (or an explicit
  `RequestStartGame`), THEN transitions to Defending. Affects all three
  combat places. *(Still open, checked 2026-09-26: Horde still calls
  `GameStateManager.SetState("Defending")` at boot
  (`HordeModeMain.server.lua:363`). Lane and CentralBoss start on any
  single `RequestStartGame` (`GameStateManager.lua:71-72,216`).
  CentralBoss's BossEncounter now starts on Defending (b19cec8), so the
  gate applies there too.)*
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

## 14d. Stats / Damage / Healing follow-ups (Tier 1.3)

- `[P1]` **§T1.3-BAL1 — Heal multiplier rebalance after crit-pipeline
  unification** — heals now run through the same multi-crit pipeline as
  damage (geometric procs, 1.80× cap, max 2 procs). Pre-T1.3 they used
  a single-proc 1.50× cap, so realised healing-per-tick will jump under
  the new pipeline. Audit every `healMultiplier` in ClassSkills (and any
  card / consumable that produces healing) and reduce as needed to land
  back at intended target healing throughput. Bundle with the broader
  balance audit before alpha. *(Still open, 2026-09-26: the §AGX/X41-X43
  pass (78392c0) was economy only: Essence sources, the Merit:Essence
  anchor and refine costs. It did not touch combat or heal numbers.)*
- `[??]` **§T1.3-DQ1 — `FlatAttack` placement in the damage pipeline** —
  today `FlatAttack` enters via `DamageSystem.GetBaseDamage` and gets
  multiplied by both `actionMultiplier` (skill coefficient) and
  `DamagePercent` — functionally identical to `BonusDamage`. Pablo
  initially read this as a true-damage / bypass-pipeline candidate but
  questioned the design (small flat numbers go meaningless late-game).
  Decide: keep current (treat FlatAttack as flat-damage entering the
  pipeline like BonusDamage) OR move it post-multiplier as
  "guaranteed flat add" OR remove the stat in favour of a per-weapon
  Penetration property. Revisit at T6 equipment audit.
- `[🚀]` **§T1.3-DQ2 — Split `HealingPower` into a dedicated derived
  stat** — today `HealingSystem` reads the `Damage` stat as healing
  power (intentional — see HealingSystem.lua header). A future PvP
  pass will want damage-vs-heal scaling to diverge. Forward-compatible
  refactor: add `HealingPower` to `PlayerDataConfig.DerivedBase` +
  `DerivedStats`, LifeSteward declares `HealingPower = { MAG = X.X }`
  in its `statDerivation`, HealingSystem reads HealingPower instead of
  Damage. The `HealingPower` flat-bonus key in BonusStats is already
  consumed today.

## 14c. Class system follow-ups (Tier 1.2)

- `[P1]` **§T1.2-BAL1 — Crit-damage class scaling balance audit** — only
  Arcanist has a per-class scaling on CritDamage (`{ MAG = 0.001 }`).
  Aegis, Hunter, and LifeSteward all carry `CritDamage = {}` — class-base
  only (1.5×). Either every class needs a meaningful scaling formula or
  none of them do; current split is a balance carry-over from before the
  PRE-removed-from-crit redesign. Bundle with the broader balance audit
  before alpha. See ClassConfig.Classes[*].statDerivation, marked
  `§T1.2/DQ2`. *(Still open, 2026-09-26: `ClassConfig.lua:108,199,244`
  are `{}` and `:156` is `{ MAG = 0.001 }`. X41-X43 did not cover
  combat.)*
- `[🚀]` **§T1.2-MOD1 — Per-class module unification** — today a new
  class touches four files: `ClassConfig` (identity + scaling),
  `ClassBehaviors/<Name>Behavior.lua` (resource rules), 
  `ClassSkills/<Name>Skills.lua` (skill set), 
  `ClassWeapons/<Name>Weapons.lua` (starter weapon binding). Pablo's
  intent is "one folder per class, everything inside." Proposed:
  `Modules/Classes/<Name>/init.lua` exporting `{ config, behavior,
  skills, weapons }`. ClassConfig.Classes becomes an aggregator that
  reads each submodule's `.config`. ResourceManager + SkillManager +
  WeaponManager loadlist update accordingly. Sizeable refactor;
  schedule after we close T1 and ship the alpha.

## 14b. Memory & Lifetimes (Janitor audit)

- ✅ **§T1.1-JAN1 — Codebase-wide leak audit** (closed 2026-09-26,
  27ab36e §AGX/T11-JAN). Every module that owns a per-player, per-character,
  per-mob, per-run or per-cast lifetime was mapped and fixed with the house
  pattern (Audit_4.7 §5.1–5.2). The five `*Main.server.lua` scripts were
  covered by the §AGX/SEC pass (d5e052b).

  | Module | Lifetimes | Before | After |
  |---|---|---|---|
  | CosmeticManager/init | per-player CharacterAdded ×2 paths, 0.5 s/0.3 s apply threads | ❌ untracked, possible double wire | ✅ Janitor + guard (PlayerRemoving) |
  | PlayerCosmetic/MobCosmeticManager | none held (mob FX are children of the mob) | ✅ | ✅ |
  | PlayerStat/Level/Class/BonusSystem | no connections; data table owned by PDM init | ⚠️ unbounded Humanoid wait; toast not ReadyGate-routed | ✅ 10 s bound; toast via ReadyGate |
  | PlayerDataManager/init (frozen) | per-player CharacterAdded (Janitor), RemovePlayer | ✅ | ✅ (labelled) |
  | MobAI | per-mob Died/AncestryChanged; pending-cast tables (15 s cleanup loop); playerSlows (weak, prunes itself); module Heartbeat | ✅ tracked by hand; re-register orphaned connections | ✅ per-mob Janitor + re-register guard |
  | MobSpawner | per-run wave thread (hook, spawn loop, clear poll, auto-advance) | ❌ could outlive Reset | ✅ run generation |
  | MobAssetLoader | none | ✅ | ✅ |
  | DefenseLine (+Health/Combo/Detection/Animation) | module Heartbeat; per-breach task.delay; processed/animating mob tables | ⚠️ breach delay outlived Reset | ✅ run generation; tables cleared on breach and Reset |
  | GameStateManager | countdown thread (cancelled); Victory/Defeat return delay | ⚠️ timer could fire in a later run | ✅ stateEpoch |
  | AttackHandler/init | per-player CharacterAdded + DeathState (Janitor); ticket/cooldown tables | ⚠️ double wire on join race | ✅ guard + label |
  | DamageHandler | spectator attribute connection; batch tables (flushed each window); handledMobs (weak) | ⚠️ relied on Player being destroyed | ✅ Janitor on PlayerRemoving |
  | HitTracker | playerStats (cleared on RemovePlayer), module Heartbeat | ✅ | ✅ |
  | SkillManager | cooldown/buff/casting tables (RemovePlayer); lock (weak) | ⚠️ re-created after leave | ✅ Parent guard |
  | SkillEffects | mob effects (weak), player effects (cleans itself every 0.5 s), number batches | ✅ | ✅ |
  | VisualEquipmentManager | per-player CharacterAdded + reattach thread; per-accessory weld watcher (disconnects when the clone leaves) | ✅ ad hoc; thread untracked | ✅ Janitor, thread tracked |
  | WeaponManager (+XP/Bonus) | per-player CharacterAdded (Janitor), setup threads (end within 5 s), initializedPlayers; XP batch; reroll lock (weak) | ⚠️ double wire on join race | ✅ guard + label |
  | ArmorManager (+Bonus) | setup thread (ends within 5 s), initializedPlayers (cleared); reroll lock (weak) | ✅ | ✅ |
  | VoteManager | Player-keyed vote tables (PlayerRemoving); resolve thread (cancelled by Reset); post-resolve delays | ❌ delays outlived Reset | ✅ run Janitor; eligible list pruned |
  | HordeModeSpawner | per-player markers + spawn thread; level-tick generation; module-lifetime Added/Removing connections | ✅ ad hoc | ✅ Janitor |
  | HordePauseManager | none | ✅ | ✅ |
  | *Main.server.lua ×5 | inline connections, Studio-only debug hooks | — | ✅ covered by §AGX/SEC (d5e052b) |

  Follow-ups still open (Wave C): `SkillManager.SetupPlayer` fires
  `SkillCooldownUpdate` without ReadyGate; the Weapon/Armor `rerollLock`
  stays set if a reroll throws halfway.

- ✅ **§T1.1-JAN2 — Janitor leak-detection telemetry** (closed, 27ab36e).
  `Janitor.new(label)` tracks live counts per label; set
  `game:SetAttribute("JanitorTelemetry", true)` to print a snapshot every
  60 s (off by default). `Janitor.GetLiveCounts()` / `PrintSnapshot()` for
  ad-hoc checks. A `*.player` count that keeps climbing after players
  leave is a leak.

## 15. Persistence / Telemetry

- ~~HitTracker.SaveLifetimeStats stub~~ and ~~DataStore save reliability
  under disconnect~~ **Resolved:** moved to "Already-resolved" (2026-09-26
  reconcile).
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
  with elemental variety. *(Still open, 2026-09-26: `WaveConfig.lua:26-29`
  unchanged. The only new mob is the CentralBoss-only `Mobs/IronWarden.lua`
  boss (b19cec8, §AGX/X28), which adds no wave variety.)*
- `[P0]` **SoundManager — 33 entries pointing at `rbxassetid://0`**
  (was 28; recount 2026-09-26, in the client module
  `StarterPlayerScripts/Modules/SoundManager.lua`) —
  needs at minimum 11 SFX (basic attack hit, skill cast, mob death,
  player damage, level up, vote start/end, currency pickup, UI open/
  close, button click, victory).
- `[P1]` **Headgear "model" visual type stub** — see §9.

## 17. Strategic / Post-alpha

- `[🚀]` **CentralBoss authored content** — place loads modules but has
  no authored boss fight. Pick a boss, author phases, wire telemetry +
  rewards. Post-alpha; HordeMode is the alpha headline mode.
  *(Partial, 2026-09-26:)* the core fight exists. It is the Iron Warden
  placeholder (`Mobs/IronWarden.lua`, `MobBehaviors/BossPhases`,
  `centralboss/.../BossEncounter.lua`, BossHud), with party-wide kill
  credit, in b19cec8 and 25c6784 (§AGX/X28). Still to do: (a) a real
  `IronWarden` model to replace the runtime `PlaceholderRig`; (b) the
  Studio test in `docs/STUDIO_TEST_PLAN.md` §4; (c) the two FLIP HERE
  switches (`GameModeConfig.lua:49-51`, `lobby/.../MainMenu.lua:54-56`),
  which stay `available = false` until then; (d) arena dressing and
  telemetry.
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

## 19. T0 Pass-2 follow-ups (§T0P2)

Deferred items from the T0 pass-2 audit (Fable 5 session — full finding
list X1–X25 in `T0_PASS2_SURFACE.md`; landed fixes carry `§T0P2/X<n>`
tags in code).

- `[P0/Security]` **§T0P2-ADMIN — Remove the remote admin surface before
  release.** AdminTesting + the AdminAction / DebugCommand /
  ModifySystemStat RemoteEvents are attack surface for custom clients
  even though every handler is allowlist-gated. Plan (Pablo): delete the
  remote path entirely and replace with an admin module driven from the
  Studio runtime console (server-side function calls, no remotes).
  Includes removing the TestingUI client panel and the manifest entries.
  *(Still open, 2026-09-26: `AdminTesting.lua`, `UI/TestingUI.lua` and
  the manifest entries in `NetworkManager.lua` are all still present.
  Note that `docs/STUDIO_TEST_PLAN.md` §4 now uses
  `DebugCommand("bossHP", …)`, so the console-module replacement must
  keep a boss-HP command.)*
- `[P1]` **§T0P2-TPCLASS — Wire the TeleportClass consumer.**
  `TeleportDataReader.ApplyPlayerData` sets the `TeleportClass` player
  attribute (party-selected class) but nothing reads it yet. The new
  map's spawn flow should consume it — and MUST validate the class is
  unlocked for the player before applying.
- ~~§T0P2-RESPEC-SCROLL~~ **RESOLVED (§DISC/D1, confirmed 2×).** Full
  chain verified wired: RespecFragment final-card (10%/player/supply-
  vote, once per run — matches Pablo's spec exactly), fragments
  auto-combine 4→1 scroll (InventoryManager.tryAutoConvert), respec
  consumes scroll, shop fallback (now 25 Essence, and the direct respec
  is a flat 25 Essence, both since 78392c0 §AGX/X42;
  `PlayerDataConfig.lua:374-381`). `[P2/Balance]` remaining:
  boss drop sources + project the acquisition curve (not too hard, not
  too easy).
- ~~§DISC/D3b — Wipe-revive: Robux product~~ **Superseded (won't do):**
  moved to "Already-resolved" (2026-09-26 reconcile, X40 decision).
- `[P2]` **§T0P2-MASTERY — Sweep the dead Class Mastery system.** Class
  XP was superseded by gear XP (WeaponXPSystem). `AddClassMasteryXP` is
  deleted (§T0P2/X21); still present: `ClassMasteryConfig.lua`, the
  `MasteryXP` / `MasteryMilestones` fields in ClassDataTemplate, and any
  UI strings. Decide: full removal + DEPRECATED_KEY_PATHS sweep of
  `Classes.*.MasteryXP`, or keep as a future system behind a comment.
- `[P2]` **§T0P2-DEALLOC — Single-point stat deallocation feature.**
  `PlayerDataManager.DeallocateStat` is kept as a seam (§T0P2/X22).
  Feature: undo a misclicked point without a full respec. Needs:
  remote + manifest entry, UI affordance, and a design decision on cost.
- `[P2]` **§T0P2-EVENTSLIM — Per-place event/module slimming.** Pablo:
  "load only what is necessary in each mode." NetworkManager
  pre-registers all ~130 manifest events in every place. Options:
  per-place manifest subsets (`places = {...}` field per entry), or
  accept the cost (RemoteEvents are cheap) and document. Also covers
  trimming per-place module loadlists.
### T1 pass-2 (§T1P2)

- `[P2/Balance]` **§T1P2-STACKS — mostly CLOSED at T2 (§T2/Z9).** The
  mob-debuff side is done: SkillEffects' stacking path already had
  `maxStacks` + refresh; Z9 added Pablo's rule (at max stacks, refresh
  only if the new duration extends) and made Vulnerability re-applies
  keep the stronger multiplier + longer remaining duration. The
  DamageSystem ≤3.0 clamp stays as belt-and-suspenders. REMAINING
  (balance, not code): decide which debuffs get `maxStacks > 1`
  (only Sundering Strikes stacks today); player-side timed buffs
  (BonusManager.AddTimedBonus) stay refresh-only until a buff actually
  needs stacks.
- `[P2]` **§T1P2-PEN — Add %-penetration as a second stat.** Decision
  (Pablo): mirror the defense model — have BOTH flat penetration (current,
  `armor - flatPen`, stays as-is and uncapped) AND a percentage
  penetration (`armor * (1 - pct/100)`) capped by `StatCaps.Penetration`
  (60 = 60%). %-pen doesn't exist in the pipeline yet, so nothing to clamp
  today; this is a feature to add (new BonusStat + DamageSystem step +
  cap). → was Y1.
- ~~§T1P2-HITTRACKER — T2 HitTracker pass.~~ **CLOSED / won't-fix.** Y6
  (callback registry has no unsubscribe) needs no fix: the only consumers
  (AchievementManager, ResourceManager) register once at boot, and all
  durable hit data already lives in dedicated tables (achievement stats,
  gear/weapon XP), so no dynamic subscriber will ever need teardown. The
  Y5 dedup (HitTracker no longer accumulates duplicate lifetime stats)
  already settled the ownership question. The OnHitDealt/OnHitReceived
  dispatch itself stays — it's the live event path.

### T10 UI outcomes (§T10, 2026-06-12)

- **§T10/STACK — React-lua is canonical (Pablo).** The
  `StarterGui/AppGui` static stack (rbxmx backdrops + Controllers) was
  an abandoned React→instances migration that CONFLICTED at runtime
  with the React roots (both shipped; LobbyUI destroyed one copy but
  StarterGui re-copied per spawn → double UI stacks / dead
  controllers). Neutralized via meta.json (ScreenGui Enabled=false,
  controllers Disabled=true) — files kept for reference. `[P2]` archive
  the folder fully during final cleanup; §UI1/§UI2 above referenced the
  controller stack and are now MOOT for those files (re-check their
  React equivalents: DailyLoginUI + SocialPanel components). *(2026-09-26:
  the React equivalents were re-checked and §UI1 is resolved. The archive
  is still open: `src/shared/StarterGui/AppGui/{AppRoot,Controllers}`
  still exist.)*
- **§T10/U1 — LoadingScreen** landed: pre-app imperative overlay
  (deliberately NOT React — it covers the React mount itself), shown
  from each place client's first Load, dismissed on ReadyGate-routed
  ServerReady, 25 s failsafe. Restyle freely in code (Scale-based).
- **§T10/U2 — TalentTreeUI rework** landed: organic layout transform
  (config untouched — polar jitter/bloom over the grid blocks),
  per-branch hue tints from node tags, two-layer edges with
  next-step highlighting, wheel zoom + pan. `[P2]` follow-ups: node
  icons per branch, allocate/refund sounds, keystone showcase panel.

- `[P1/UI]` **§T10/U3 — Window standardization sweep.** Two window
  types now exist: `UI/Common/AppWindow.lua` (`variant = "windowed" |
  "fullscreen"`, anime/speed chrome: slanted accent ribbon, uppercase
  title, motion lines, icon slot, headerContent slot, standard close)
  + `UI/Common/Theme.lua` (single palette/fonts/icon registry).
  CONVERTED: ClassMenu (windowed exemplar), TalentTreeUI (fullscreen
  exemplar). Recipe per remaining menu: (1) require AppWindow;
  (2) delete the menu's own backdrop/panel/title/close chrome;
  (3) return AppWindow{variant, title, icon, onClose[, headerContent]}
  with the body children; (4) migrate hardcoded colors to Theme.Colors.
  CONVERTED (batch 2, §T10/U3): StatsMenu, SettingsUI, DailyLoginUI,
  LeaderboardUI (the last two had ~12-pixel close buttons — the
  "incredibly small" ones). REMAINING: EquipmentUI, WardrobeUI,
  AchievementsUI, GlobalShopUI, KeybindSettings, CharacterCreation
  (fullscreen), BattleClassUI, InventoryUI (shared since §AGX/UI-P3 W4,
  with DailyLoginUI and LeaderboardUI) + lobby: MainMenu, ShopUI,
  WeaponSmithUI, SocialPanel, MatchmakingUI, NPCDialog. (Toasts/wheels — EmoteWheel, PartyInviteToast, VoteUI,
  DeathUI, HUD, TeammateVitals — are NOT windows; leave as-is.)
  *(Mostly done, 2026-09-26 reconcile:)* the §AGX/UI-P6 re-skin
  (05c1b9e, 582dff1, 5718f59) put every screen in the REMAINING list on
  AppWindow + Theme v2 with no `Color3.fromRGB` literals, **except
  SocialPanel**. `lobby/.../UI/SocialPanel.lua` has no AppWindow, no Theme
  require, a private palette at `:36` (22 `Color3.fromRGB` literals) and a
  hand-rolled Scale-sized ✕ at `:701-711`. It is still reachable as the
  shell's "party" entry (`UI/Shell/Registry.lua:245-247`). MatchmakingUI is
  a banner and not a window, but it does use Theme/Button (582dff1).
  CharacterCreation's 12 literals are skin swatches (`:51-54`), not
  chrome. ~~Still to do: SocialPanel only.~~ SocialPanel re-skinned
  (AppWindow, Tabs, Theme v2, 44 px buttons; §AGX/UI-FREE). **U3 closed.**
- `[Done]` **§PERF/BP — Boot profiler (2026-07-16).** Shared
  `ReplicatedStorage/Shared/BootProfiler` (Mark/Begin spans). Hooks:
  PlaceBootstrap.Load (every require + Init, all 5 places),
  PlaceLifecycle OnPlayerReady + ServerReady, PlayerDataManager
  DataLoad span, ReadyGate ClientReady drain, 5 client bootstraps'
  Load + ServerReady/dismiss, 5 UI scripts' ClientReady fire.
  Report auto-dumps ~5 s after boot quiets: Output block +
  StringValue snapshots (ServerStorage.BootProfile_SERVER /
  PlayerGui.BootProfile_CLIENT). Flags: ⚠ SLOW ≥100 ms,
  ⚠ gap ≥350 ms silence, ⚠ UNFINISHED = span never closed (race/hang
  evidence). `[P1]` set `ENABLED = false` in BootProfiler before
  release (alpha keeps it on). *(Still `true`, checked 2026-09-26 at
  `Shared/BootProfiler.lua:41`.)*

- `[P1/Art]` **§T10/ICONS — Icon set (anime / speed): ART DELIVERED,
  ids pending.** Claude Design produced the full 27-asset drop
  (16 icons + 4 button plates + barFrame/barShine + 5 white particle
  sprites), QA'd (alpha, tintability, 24px readability, pBolt tiling)
  and stored in `assets/ui/` (527 KB — small enough for git, Pablo's
  call). Brief lives in `docs/CLAUDE_DESIGN_BRIEF.md`.
  REMAINING: Studio → Asset Manager → Bulk Import `assets/ui/`, then
  paste ids into `Theme.Icons` (16) and the new `Theme.Images` (11,
  slice rects pre-filled). All UI falls back gracefully until then.
  *(Still open, 2026-09-26: every id is still `rbxassetid://0` in
  `UI/Common/Theme.lua:351-376` and `:409-424`; `assets/ui/` holds all 27
  files. **Plus 4 missing icons** with no art delivered: `play`, `leave`,
  `emote` and `menu` (`Theme.lua:370-376`, §AGX/UI-P3; for now they render
  as glyphs from `Theme.Glyphs`). Also `appearance` (§AGX/X18b) has only a
  glyph and no `Theme.Icons` slot. Add all of them to
  `docs/CLAUDE_DESIGN_BRIEF.md`. Only Pablo can do the import.)*

- ~~§AGX/UI-P3/P5 W6 — Shell + HUD regions Studio pass~~ **Folded** into
  the §20 "Studio test pending" item. The W6 checklist is now
  `docs/STUDIO_TEST_PLAN.md` §5-§8, which also covers P6/P7 and the
  UI-FIX rounds (90e5985, e1524b9).

### Discussion-batch outcomes (§DISC, 2026-06-12)

- `[🚀]` **§DISC/D2 — Persistent parties.** Pablo: party = everyone in
  the battle map (no hardening needed — reserved servers make this
  true). FUTURE feature: party persistence across server hops — a
  unique party ID minted at party creation, carried in teleport data,
  re-associated in the lobby on return. Pairs naturally with the
  MemoryStore matchmaking plan (§7).
- `[P1/Core]` **§DISC/D5 — Achievement-driven bonuses + gates.**
  Achievements grant permanent stat bonuses via the reserved
  BonusManager "achievement" source, AND gate features: (a) the chapter
  hard-cap at each 50 requires that chapter's boss achievement to
  unlock further leveling (wire into ChapterConfig.GetChapterLevelCap
  / PlayerLevelSystem cap check); (b) **class unlocks** (round 2):
  future classes gated behind achievements — extend
  ClassConfig.unlockRequirements with `requiredAchievement` and teach
  PlayerClassSystem.CheckUnlockRequirements to read
  AchievementManager's unlocked set. Core element per Pablo.
  *(Still open, 2026-09-26: no `requiredAchievement` anywhere in `src/`,
  and the "achievement" BonusManager source is only reserved
  (`BonusManager.lua:27`). Change since then: a boss-tier mob exists
  (Iron Warden, b19cec8), so the 9 boss achievements can be earned once
  CentralBoss is enabled (AGENCY_CHECKS X28). Do not land gate (a) while
  CentralBoss is still `available = false`, or progression blocks at
  level 50. The one-shot `veteran` achievement (b0bdbee, §AGX/X18b) is
  the first reward that is not a stat.)*
- **§DISC/D6 — REVISED round 2, BUILT.** Pablo: folding more cap/gate
  features is common, worth the seam. New shared
  `Modules/PartyRequirements.lua` (MaxLevelGap/FitsLevelGap/CheckLevels)
  now backs BOTH PartyManager invite checks and TeleportManager launch
  validation — future gates (achievement locks §D5, class comp,
  per-difficulty floors) get added there once and apply at both gates.
- `[P1/Content]` **§DISC/D7 — Shop rotation + paid refresh.** Build:
  rotation timer (server-side, per catalog section), plus a manual
  "refresh now" costing Essence. ShopConfig is currently a static
  catalog — needs rotation state + UI. Content pass.
- **§DISC/D8 — REVISED round 2, BUILT (better design, Pablo's).**
  Instead of an error channel: NPC UIs auto-close when the player walks
  away. New `UI/Common/useNpcDistanceClose` hook (16-stud threshold vs
  the server's 12-stud INTERACT_RANGE, so no boundary flicker), wired
  into NPCDialog (dialogue/quest/teleport panels), ShopUI and
  WeaponSmithUI (done; the old "[P2] also wire into ShopUI +
  WeaponSmithUI" line was stale, UX-17). §AGX/UI-P3: ShopUI's distance
  path now sends `NPCResponse Close` like its ✕ (UX-17 nit), and all
  three NPC panels register with PanelStack (`useExternal`), mounted by
  PanelHost. Scene/card server warns stay as-is.

- `[P2]` **§T0P2-ORPHANS — Verify 5 unreferenced manifest events.**
  `ArmorRefinementResult`, `ArmorTierUp`, `WeaponRefinementResult`,
  `WeaponTierUp` (check at T6 — refine/tier flows may be missing their
  result pushes), `HealNumber` (check at T2 — heals may ride
  DamageNumber). Delete or wire. *(Partial, 2026-09-26 reconcile: the
  four equipment events are NOT orphans. They are fired by name through
  `eventName` in `EquipmentRefinement.lua:48,54` and
  `EquipmentTierSystem.lua:54,62`. Still to do: `HealNumber` only. The
  server sends only `HealNumberBatch` (`SkillEffects.lua:107-108`), while
  the single-event listener in `DamageNumbers.lua:289-290` and the
  manifest entry (`NetworkManager.lua:154`) are dead.)*

## 20. Agency-checks follow-ups (§AGX, 2026-09-26)

New open items created by the agency-checks session (`git log
0e6d15e..b0bdbee`; findings in `AGENCY_CHECKS.md`, UI plan in
`docs/UI_REVAMP.md`). Nothing from that session has run in Studio.

- `[P0]` **§AGX/STUDIO — Studio test pending for the whole round.** All 47
  commits since `0e6d15e` were only checked statically (luau-compile /
  luau-analyze, agent review, headless layout math). Run
  `docs/STUDIO_TEST_PLAN.md` top to bottom: §0 boot smoke (X16 now fails
  boot **hard** on a critical Init error), §1 session-locked saves
  (X2/X3/X3r/X8), §2 gameplay regressions, §4 CentralBoss, and §5-§8
  shell, mobile, Theme v2 and gamepad. §5-§8 replace the old W6
  checklist. Include the §9 VEM-DEDUPE 1× check and the X45 physics
  profile (flip `MobSpawnHelper.lua:135` `SERVER_OWNED_TIERS.normal` if
  a 72-mob Horde is over budget).
- `[P1]` **§AGX/X4-LIVE — Reserved-server live test (published build).**
  Studio cannot create reserved servers. After publishing, check that a
  match lands on a new reserved server per party and that joining a
  public combat server bounces you to the Lobby
  (`TeleportDataReader.lua:24-32,127-129`), plus the X14 TeleportInitFailed
  retry. See `STUDIO_TEST_PLAN.md` §3 "Live test".
- `[P1/Monetization]` **§AGX/X40-BUNDLES — Robux-exclusive cosmetics
  before the bundles can be enabled.** The three class bundles
  (`ShopConfig.lua` Premium, 99 R$ each, e.g. `mask_hunter` +
  `forest_ranger` at `:262-266`) contain items that are also sold for
  Merits/Essence. `MonetizationService` registers them but refuses to
  prompt them (`MonetizationService.lua:12-13`; BALANCE_NUMBERS §48).
  Author cosmetics that are only sold for Robux, then point the bundles
  at them. Also: create the real DevProducts and the GamePass, and paste
  their ids, because every Premium entry is still `enabled = false` with
  id `0`.
- `[P2]` **§AGX/UI-P2-REFUND — Single-talent refund not implemented on
  the server.** `TalentTreeUI.lua:132` has `INDIVIDUAL_REFUND_ENABLED =
  false`, so Refund renders disabled with the reason. `TalentClient.lua:139-141`
  `RefundNode` is a `warn` stub, and `TalentManager` only handles
  `AllocateTalent` and `RespecTalents` (`TalentManager.lua:216,235`).
  Needs: a remote plus manifest entry, a server refund (leaf-only, or
  dependency-checked), a cost decision (free, Essence, or part of a
  respec), then flip the flag. It pairs with §T0P2-DEALLOC.
- `[P2]` **§AGX/X27-OBO — Horde and Lane HighestWave differ by one.**
  Lane records the wave number **completed**
  (`LaneDefenseMain.server.lua:321-323`, `MobSpawner.OnWaveCompleted`).
  Horde records the level **reached** (`HordeModeMain.server.lua:326-337`:
  `lastLevel` after the increment, i.e. the level that just started). A
  run that dies in wave/level 5 records 4 on Lane and 5 on Horde, and
  both feed the same `Account.HighestWaveReached`, the HighestWave board
  and GearRating prestige. The same number feeds the `wavesSurvived` /
  `highestWave` achievements from Horde. Decide one meaning (probably
  "completed") and record `lastLevel - 1` on Horde, or keep separate
  per-mode stats.
- `[P1]` **§AGX/X11-RULES — 15 talent keystones say "(coming soon)".**
  Their penalties were neutralised (36cd218), but no rule is implemented:
  `TalentTreeConfig.IMPLEMENTED_RULES = {}` (`TalentTreeConfig.lua:735`,
  tagging at `:741-751`). Implement the rules one at a time and add each
  name to the set. Belongs with the talent pass (§3).
- ✅ *(Done 2026-09-26, §AGX/X10b: `ConsumableEffects.lua` + InventoryUI Use
  button; 8 of 9 items on. Remaining: Swiftness Elixir needs a move-speed
  hook in the X13 `BaseWalkSpeed` owners. Ironskin is flat Armor = 12% of
  current until an `ArmorPercent` bonus stat exists.)* **§AGX/X10-CONSUMABLES — only the respec scroll can be used.**
  Consumables with no server use handler are unbuyable and show "Coming
  soon" (`ConsumableConfig.lua:13,174-176`; `ShopManager.lua:233-239`).
  Write the use handlers (potions, buffs), then set `usable = true` per
  item.
- ✅ *(Done, §AGX/UI-FREE: LobbyClient shows it as a toast after the loading
  screen.)* **§AGX/X4-REASON — the return reason is never shown.**
  `ReturnTeleporter.lua:86-105` sends `returnReason` in TeleportData on a
  public-server bounce or a failure, but nothing in the Lobby reads it.
  Show it as a Notify toast on Lobby arrival.
- ✅ *(Chat half done, §AGX/UI-FREE: `Modules/VipTag.lua` adds a blue `[VIP]`
  chat prefix in every place. No nameplate exists to tag.)* **§AGX/X40-VIP — the VIP GamePass has no effect.** It sets a
  `VIP` player attribute that nothing reads (`ShopConfig.lua:268-271`).
  Add the nameplate/chat tag before enabling the pass. Social perks only.
- `[📝]` **§AGX/X46-GUARD — the PolicyService tripwire.** Before
  anything bought with Robux can roll a random result or be
  traded/auctioned, add `ArePaidRandomItemsRestricted` /
  `IsPaidItemTradingAllowed` and reopen X46. The code gate is
  `ALLOWED_GRANTS` in `MonetizationService.lua:54-58`. Never make
  `Account.Monetization.robuxSpent` public.
- `[🚀]` **§AGX/X48 — Onboarding.** Parked by Pablo until all modes are
  final. There is no tutorial or first-run flag, and nothing points new
  players to Commander Vex (AGENCY_CHECKS X48).
- `[P1/Ops]` **G20 — Rotate the Open Cloud key.** Still open. Only Pablo
  can do it. The tools now read `ROBLOX_OPEN_CLOUD_KEY` from the
  environment (668316b, §AGX/X49).
- `[P2]` **Repo hygiene leftovers (AUDIT_FINDINGS G16/G18/G24).**
  Checked 2026-09-26: `foreman.exe` (5.8 MB), `Leg.obj` and `Leg.mesh`
  are **still tracked** (`git ls-files`), which contradicts Audit_4.7
  §13.2 "Heavy binaries untracked". `.gitignore` still has no `.venv/`
  line. `sourcemap.json` is untracked (G17 done). This must be done from
  Pablo's terminal (Audit_4.7 §10).

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

### Reconciled 2026-09-26 (after the agency-checks session, `0e6d15e..b0bdbee`)

Each entry below was checked against the current code (file:line), not
only against commit messages. "Pending Studio" means the code is in place
but has not run yet (see §20 §AGX/STUDIO).

- **§AM4 HordeMode `wavesSurvived` / `highestWave`** (was `[P1]`, §10):
  option (a) landed. The Horde level watcher feeds
  `AchievementManager.OnWaveCompleted` for each level
  (`HordeModeMain.server.lua:316-339`, 28e7fd7 §EASY/E4), and since
  cc776f2 §AGX/X27 it also records `HighestWaveReached`. The off-by-one
  against Lane is in §20.
- **§RG-MIGRATION (cosmetics + equipment + achievements + boot-race
  umbrella)** (was three `[P2]` items, §9/§10/§11): `WeaponEquipped` and
  `ArmorEquipped` go through ReadyGate (`WeaponManager/init.lua:14-33`,
  `ArmorManager/init.lua:27-43`, §NM-D2, 66503b4). `AchievementUnlocked`
  goes through ReadyGate (`AchievementManager.lua:78-97`, 66503b4).
  `WardrobeUpdate` and `EquipmentInfo` are pure request/response, and the
  client subscribes before it asks (`NetworkManager.lua:101-104,215-217`;
  `CosmeticManager/init.lua:78-86`; `EquipmentHandler.lua:38-40`), so
  there is no boot race. The entries were stale before this session.
- **§G5 late joiner sees stale GameState** (was `[P1]`, §12): the
  "client asks on mount" option landed. The `RequestGameState` reply is
  at `GameStateManager.lua:75-93` (0c93026 §AGX/UX-02), and
  `UI/HUD/RunState.lua:177` fires it once per client session (moved there
  from HUD.lua in 8871472 §AGX/UI-P5). Horde late-joiners also get a
  ReadyGate-routed push (`HordeModeMain.server.lua:508`, §T0P2/X9).
  Pending Studio (`STUDIO_TEST_PLAN.md` §5 "UX-02").
- **§UI1 DailyLogin / CreateParty optimistic text** (was `[P2]`, §14):
  DailyLogin claim goes through `useRequest` and shows pending, ok,
  timeout or error inline (`UI/DailyLoginUI.lua:32,64-76`; dfefb37 and
  74b7ac8 §AGX/UI-P4). The React SocialPanel draws "+ Create Party" from
  party state and has no optimistic label (`SocialPanel.lua:443-459`).
- **Class unlock toast** (was `[P2]`, §14): `PlayerClassSystem.lua:140-151`
  fires an `AchievementUnlocked`-shaped "Class Unlocked!" toast
  (28e7fd7 §EASY/E6). Since b38a8a3 §AGX/UI-P4 it shows as a Notify banner.
  Routed through ReadyGate since 27ab36e §AGX/T11-JAN.
- **HitTracker.SaveLifetimeStats stub** (was `[P1]`, §15): the method and
  its session stat block are gone (§T1.4/Y5, b291a39; see
  `HitTracker.lua:277-288`). Lifetime data lives in achievement and
  gear-XP tables.
- **DataStore save reliability under disconnect** (was `[📝]`, §15):
  landed as session-locked `UpdateAsync` saves, a BindToClose drain,
  retry on the final save, and a 60 s autosave (09e4a5a §AGX/X2/X3), then
  hardened r1-r12 (8fd1301 §AGX/X3r). Pending Studio (§1 of the test plan).
- **§DISC/D3b wipe-revive Robux product** (was `[P1/Monetization]`, §19):
  **superseded, won't do.** Pablo's X40 decision (cdba264, 1c6e333):
  Robux never buys revives or currency (BALANCE_NUMBERS §48 "Not allowed"
  table). `MonetizationService.lua:54-58` `ALLOWED_GRANTS` only allows
  AppearanceChange, Cosmetics and GamePass. The revive is now 3/2/1 free
  by difficulty, then one paid in Essence (3b4d39d §AGX/X40).
