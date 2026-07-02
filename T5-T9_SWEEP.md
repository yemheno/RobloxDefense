# T5–T9 Full Sweep — landed fixes + discussion batch

> **STATUS: EXECUTED (2026-06-12)** under the standing rule. Five
> parallel deep-maps (Vote/Cards, Equipment, Lobby, Progression,
> Shop/NPC — ~10,800 lines), every High/Critical claim verified, direct
> fixes landed under `§T5-T9/S<n>` + `§T7/G4` tags (all HEAD+patch
> AST-verified). Discussion items collected at the bottom — answer in
> one batch whenever.

---

## Landed fixes

- **S1** VoteManager: `PlayerRemoving` cleanup for `playersVoted`,
  `personalVote`, `personalCooldowns`, `fragmentRolledThisRun` — the
  long-known mid-run leaver leak, finally closed. (Verified: rejoiners
  get a new Player instance, so the stale entries never *blocked*
  anyone — pure leak.)
- **S2** VoteManager: nil-guard on the winning card in `_Resolve`. A
  registry miss used to crash mid-resolve and leave `voteActive` stuck
  true — vote system deadlocked for the rest of the run. Now resolves
  with a stub result (UI closes, no reward) and a loud warn.
- **S3** MatchmakingManager: `requiredLevel` is now enforced on
  EXPLICIT difficulty picks. A hand-crafted packet with a *valid* tier
  name ("Nightmare") skipped the auto-select branch — the only place
  requiredLevel was checked — so a level-1 party could queue Nightmare.
  Explicit picks below the tier's floor are now rejected with a clear
  message.
- **G4** (carried since audit #1, finally landed) TeleportManager:
  `TeleportAsync` retries 3× with backoff, drops leavers from the batch
  between attempts, and only then falls back to the §L9
  error-and-requeue path.
- **S4** LeaderboardManager: 30 s per-board TTL cache on
  `GetSortedAsync` — every client request used to be a raw
  OrderedDataStore hit (quota burn). The §LB3 live-viewer-row
  substitution still runs per request.
- **S5** TalentTreeValidator: new stat-name integrity check (every node
  effect's `stat` must exist in BonusStats, `primary` in PrimaryStats)
  — a config typo used to silently void the node's effect at runtime
  (BonusManager warn-once rejection). Validator now also RUNS at first
  require (was defined but never called at boot).
- **S6** VisualEquipmentManager: found and fixed the ROOT CAUSE of the
  long-standing §VEM-DEDUPE double-attach — a player present during
  Init got CharacterAdded wired from BOTH the PlayerAdded handler and
  the existing-players loop → every respawn ran ReattachAll twice.
  Single wire-per-player now, connections tracked + disconnected on
  leave (closes the §14b VEM candidate too).

## Refuted / verified this sweep (highlights)

- **"Weapons roll mana/focus with no stat mapping" (T6 agent CRITICAL)**
  — zero matches in either registry; hallucinated (second time this
  claim family died — first was T1's X23).
- **Shop purchase atomicity** (the deferred V4-A4 concern) — verified
  SAFE: per-player purchase lock + deduct-first + refund-on-grant-fail
  (§Sh1 held). Quest turn-in lock (§QH2), currency guards, prereq
  re-checks (§QH5) all held.
- **PartyManager/MatchmakingManager lifecycle** — invite validation,
  leader migration, §L4/L6/L7/L8 race fixes all verified present. The
  lobby stack is in good shape.
- **RunModifiers "O(N²) pruning"** — entry counts are dozens per run,
  not thousands. Non-issue.
- **Vote "late cast during resolve" race** — late casts mutate tables
  that are already consumed/discarded; harmless.
- **AdminTesting currency bypass** — already mitigated by T0P2/X18's
  pushes; Merits isn't a leaderstat anymore. Non-issue.
- Talent §T1/T2 deduct-first, achievement §AM1/AM7 locks, DailyLogin
  §DL1-DL3 atomic claim — all held on re-read.

---

## 💬 DISCUSSION BATCH — ANSWERED + EXECUTED (2026-06-12)

Pablo's calls and what landed:

- **D1** shop path suffices; mission sources later → TODO updated,
  §T0P2-RESPEC-SCROLL closed.
- **D2** party = everyone in the battle map, no hardening needed. NEW
  strategic feature parked: persistent parties with a unique party ID
  surviving server hops (§DISC/D2 in TODO, pairs with the MemoryStore
  matchmaking plan).
- **D3 LANDED** (`§DISC/D3`, DeathSystem.CheckPartyWipe): all players
  Dead → pause (HordePauseManager where present) → TriggerDefeat →
  lobby. ⚠ NOTE FOR LIVE TEST: this makes a SOLO death end the run
  immediately (no teammate to outlive) — respawn now only matters while
  a teammate is up. Shout if that's not what you want solo.
- **D4 LANDED** (`§DISC/D4`): BonusExpSystem clamps — any single source
  ≤ +100%, total ≤ +200% (3.0× multiplier cap), warn on clamp.
- **D5** achievement source affirmed CORE (stat bonuses + feature gates
  like the chapter-50 boss unlock) → seam kept, BonusManager doc
  updated, §DISC/D5 [P1/Core] TODO entry with the ChapterConfig wiring
  note.
- **D6** G9 closed as accepted; patch only if it drifts.
- **D7** shop rotation + paid Essence refresh → §DISC/D7 [P1/Content]
  TODO entry.
- **D8** the sites that could warn already warn; the real gap is a
  server→client feedback channel (NPCResponse is client→server only) —
  that's UI-tier work, parked as §DISC/D8 [P2/UI] for T10.

Original batch below for lineage.

## 💬 DISCUSSION BATCH (answer these together)

**D1 — respec_scroll: actually resolved?** The sweep found it IS
purchasable: ShopConfig sells it (50 Essence, lvl 10), ConsumableConfig
defines it, InventoryManager accepts it, and Essence flows from daily
login/achievements. So the §T0P2-RESPEC-SCROLL "nothing grants it"
concern reduces to: is shop-only acquisition the intended design, or do
you also want it as a quest/boss drop? (If shop-only is fine, I'll
close the TODO entry.)

**D2 — partyData trust (the last of G2).** TeleportData's `partyData`
(name/class/level) is server-built at the source but transits the
client, so it's spoofable in flight. Current blast radius is small:
XP-share matches names against players actually in the server, and the
TeleportClass consumer doesn't exist yet (and must validate unlocks
per its §T0P2-TPCLASS note). Options: (a) accept residual risk for
alpha (my lean — reserved servers make everyone present "the party"
anyway), (b) have TeleportDataReader rebuild partyData entirely from
present players' attributes and ignore the payload copy.

**D3 — DQ-T4A carried: party wipe.** Still open from T4: all-dead in
HordeMode lets the timer run to a victory over corpses. My lean: horde
wipe → TriggerDefeat (~10 lines in DeathSystem's death path); Lane
keeps line-death semantics. Confirm and I'll land it.

**D4 — BonusExpSystem trusts callers.** Any module can set any XP
multiplier (no cap). Server-side only, so not exploitable — cap it
anyway (e.g. total multiplier ≤ 3×) as typo insurance, or leave?

**D5 — "achievement" bonus source is a dormant seam.** BonusManager
reserves it; nothing writes it (achievement rewards go through
currency/inventory instead). Keep the seam for future stat-granting
achievements, or delete it from SetupPlayer? (Costs nothing either
way; your call on intent.)

**D6 — G9 closing rationale.** The MaxLevelGap VALUE is single-sourced
(§L11 PlayerDataConfig) and both modules read it; what remains
duplicated is two 10-line loader blocks + two validation sites
(invite-time and launch-time — arguably a feature, defense in depth).
I propose closing G9 as "accepted: duplication is structural, source
of truth is single" rather than forcing a shared helper across lobby
module load order. Veto if you disagree.

**D7 — no shop rotation exists.** ShopConfig is a static catalog; no
rotation timer anywhere. If "rotating stock" is on the roadmap it's a
feature to build, not a bug — flag for the content pass?

**D8 — client feedback nits (bundle).** NPC out-of-range interactions
fail silently (server warn only); SceneManager missing-spawn falls back
silently; CardRegistry skips rewards silently if a dependency is
missing (client still sees "granted!"). All cosmetic-ish server-side —
worth a small "feedback pass" batch later, or leave for the UI tier?

---

Smoke tests for the landed batch: leave mid-vote → no console residue
(S1); queue "Nightmare" under-leveled via UI → clean rejection (S3);
kill teleport service in Studio (offline test) → three retry warns then
requeue (G4); open leaderboard repeatedly → one DataStore hit per 30 s
(S4); respawn repeatedly → exactly ONE weapon attach per respawn (S6 —
the old double-attach should be gone from the console entirely).
