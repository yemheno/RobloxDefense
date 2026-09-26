# Repo-Wide Audit Surface — reconciled with Audit_4.7

> **What this is.** A fresh repo-wide pass (2026-06-12, Claude Fable 5)
> reconciled against the tier-by-tier audit state in `Audit_4.7.md` and
> the parking lot in `docs/TODO.md`. Findings are ID'd `G1…G25`
> (G = global pass), sorted 🚨 bug > 🟡 spaghetti > 🟢 minor > ❓ DQ,
> each mapped to its owning tier. **Nothing here has been executed.**
> Respond per-item (`G1. Yes / No / discuss`) per §3.4 convention.
>
> **Reconciliation honesty:** four candidate findings from this pass were
> checked against the code and REJECTED (see §"Verified good" at bottom).
> Items already parked in TODO.md / Audit_4.7 §6 are marked *(known)*.

---

## 🚨 Bugs / dangers

### G1. 29 `src/` `.rbxmx` source assets are not in version control — **repo, pre-tier**
**Status (2026-09-26):** ✅ **Won't fix (by design).** Pablo's decision: `.rbxmx` assets are place-managed, and `*.rbxmx` in `.gitignore` is correct (CODEBASE_REVIEW.md:57). 0 tracked today.
`.gitignore`'s blanket `*.rbxmx` rule (meant for root export artifacts)
also excludes everything under `src/`: all of `StarterGui/AppGui/`
(wiring + 27 backdrops), `ServerStorage/CharacterTemplates/`, every
mob/weapon/projectile model. `git ls-files` shows **zero** tracked
`.rbxmx`. A fresh clone cannot build any of the five places; a disk
failure loses the GUI tree permanently.
**Fix shape:** change the rule to `/*.rbxmx` (root-anchored), then
`git add src/**/*.rbxmx` — **from your terminal, not this session**
(per Audit_4.7 §10 sandbox-git rule). Exact commands in Action Set A.

### G2. TeleportData trusted unvalidated — **T7**
**Status (2026-09-26):** ✅ **Resolved.** Difficulty is validated against DifficultyConfig (§T0P2/X2, 0b1f84f; `TeleportDataReader.lua:189-192`). The place's own modeId wins and requiredLevel is re-checked on arrival (§AGX/X6, 2329bbd; `:95-120,143,178`). Combat places only accept reserved-server arrivals (§AGX/X4; `:24-32`). The partyData residual was accepted at T7 (T5-T9_SWEEP D2). Pending Studio and the live test.
`Modules/TeleportDataReader.lua:50-57` — `teleportData.difficulty` and
`teleportData.partyData` are consumed straight from `GetJoinData()`.
Teleport data transits the client and is spoofable: fake difficulty
(easy scaling, high-tier `rewardLevel`), fake party composition.
**Fix shape:** validate difficulty against `DifficultyConfig`; rebuild
party/level data server-side from `PlayerDataManager`. Long-term this
merges with TODO §7's MemoryStore rendezvous plan (reserved-server key
as the trust anchor). Worth a minimal validation patch at T7 open.

### G3. Infinite `WaitForChild("Modules")` in all five place Mains — **T0 pass-2, small**
**Status (2026-09-26):** ✅ **Resolved.** `WaitForChild("Modules", 10) or error(...)` in all five Mains (0b1f84f, T0 pass-2 batch 3; e.g. `LobbyMain.server.lua:21-26`).
No-timeout waits in the boot path: `LobbyMain:19-20`,
`LaneDefenseMain:19`, `HordeModeMain:23-24`, `CentralBossMain:20`,
`SocialPlazaMain:25`. A broken folder structure hangs the server
silently — the opposite of operating principle #3 (*loud at boot*).
**Fix shape:** `WaitForChild("Modules", 10)` + `error()` on nil, in all
five Mains. Server-side twin of the parked §NM-D6 client hang-recovery
item. Small enough to land pre-alpha outside tier order.

### G4. `TeleportAsync` has no retry — **T7**
**Status (2026-09-26):** ✅ **Resolved.** §T7/G4 retries 3× with backoff (b291a39). §AGX/X14 added TeleportInitFailed handling, a launch timeout and Retry (2329bbd; `TeleportManager.lua:255`).
`lobby/Modules/TeleportManager.lua` (~152-165): pcall-warn only.
Transient teleport-service failures permanently strand a matched party
in "Launching".
**Fix shape:** 2–3 retries with backoff, then return party to queue
with a client notification.

### G5. ReadyGate overflow drops oldest queued events — **T0 pass-2** *(+ DQ3)*
**Status (2026-09-26):** ✅ **Resolved.** DQ3/DQ-A = kick on overflow, never evict (§T0P2/X8, 0b1f84f; `ReadyGate.lua:97,211-216`).
`Modules/ReadyGate.lua` (~165-175): per-player queue cap 200, overflow
evicts the **oldest** entry — on a slow client that is exactly the
boot-critical payload. Player loads half-initialized with only a
server-side warn.
**Fix shape:** depends on DQ3 (undroppable flag vs kick-and-resync).

### G6. HordeMode party anchor set from first-loaded player — **T3**
**Status (2026-09-26):** ✅ **Resolved.** Re-anchor on every player's data-ready: Horde §HM2 (`HordeModeMain.server.lua:486-495`), Lane §T3/W8 (b291a39).
`HordeModeMain.server.lua` (~301-312): `startSpawnerOnce` anchors party
level to the highest level *loaded at that moment*; later-loading
players (often the highest-level) don't count. Difficulty/reward
scaling silently wrong for the whole run.
**Fix shape:** wait for all present players' data (with timeout) before
anchoring, or re-anchor on late `OnPlayerDataReady`.

### G7. Mob-skill damage multiplier order diverges from player pipeline — **T3** *(+ DQ2)*
**Status (2026-09-26):** ✅ **Closed, refuted** at T3 (T3_SURFACE.md:43, "G7 / DQ2 CLOSED — refuted").
`MobAI.lua:726-734` applies `config.damage × skill.damageMultiplier ×
mobData.damageMultiplier` before armor; the player-side pipeline
(`DamageHandler`, post-T1.3) orders armor differently. Net effect: armor
undercounts against mob skills vs basic hits.
**Fix shape:** unify order with the T1.3 pipeline — but multiplier
semantics are a balance call → DQ2.

### G8. ReturnTeleporter silent-fail path — **T7**
**Status (2026-09-26):** 🟡 **Partial.** §AGX/X6 (2329bbd) removed the payload path: the lobby id is always `Shared.PlaceIds.Lobby` (`ReturnTeleporter.lua:28,78-81`), with one retry (§AGX/X14). Still open: a zero id outside Studio still only `warn`s and returns false (`:95-99`), with no loud boot error. Low risk while PlaceIds is populated.
`Modules/ReturnTeleporter.lua:48-56`: if no arriving player carried
`lobbyPlaceId` and the `Shared.PlaceIds` fallback failed to load,
`TeleportAllToLobby()` returns false silently → players stuck in the
game place post-run. (`Shared/init.lua:68-74` is populated with real
IDs, so this needs the fallback path to *also* fail loud, not a data
fix.)
**Fix shape:** hard `error()` at boot if fallback resolves to 0/nil.

---

## 🟡 Spaghetti / structure

### G9. `MAX_LEVEL_GAP` loaded + enforced twice — **T7**
**Status (2026-09-26):** ✅ **Resolved.** One shared `PartyRequirements` module backs both gates (§DISC/D6, b291a39; `PartyManager.lua:46`, `TeleportManager.lua:62`).
`PartyManager.lua:36-44` and `TeleportManager.lua:63-72` each lazy-load
`PlayerDataConfig.Matchmaking.MaxLevelGap` with independent fallbacks,
and validate independently. Direct violation of principle #4 (single
source of truth); drift means a party accepted at invite can fail at
launch.
**Fix shape:** one shared `ValidateLevelGap` (PartyManager owns it;
TeleportManager calls it), single config read.

### G10. `WireOnPlayerReady` double-call re-fires player setup — **T0 pass-2, small**
**Status (2026-09-26):** ✅ **Resolved.** Module-level `_wiredPlace` latch (§T0P2/X14, 0b1f84f; `PlaceLifecycle.lua:62-69`).
`Modules/PlaceLifecycle.lua` (~115-132): the `_onReadyFired` latch
guards per-player double-fire *within* one wiring, but a second
`WireOnPlayerReady` call wires a second chain. Today no Main calls it
twice — this is a tripwire for future place code.
**Fix shape:** module-level "already wired" latch + warn.

### G11. HitTracker callback registry has no unsubscribe/dedupe — **T2** *(extends T1.4/R6)*
**Status (2026-09-26):** ✅ **Won't fix.** Consumers register once at boot (TODO §19 §T1P2-HITTRACKER, closed).
`Modules/HitTracker.lua` (~31): `OnHitDealt`/`OnHitReceived` append-only.
T1.4/R6 made this registry the canonical per-hit dispatch (ResourceManager,
Achievements, future Runes/procs ride it) — so it now needs handles.
**Fix shape:** return an unsubscribe function/ID; document in the T2
HitTracker pass-2 already scoped in Audit_4.7 §6.1.

### G12. AttackHandler ticket-flood headroom — **T2** *(pass-2 of T0 §A1-A4)*
**Status (2026-09-26):** ✅ **Closed, refuted** at T2: `CheckCooldown` gates ticket creation (T2_SURFACE.md:152-154).
`AttackHandler/init.lua` (~166-182, 319-321): range checks use server
positions (good) and per-ticket hit caps hold, but up to
`MAX_PENDING_TICKETS` fresh tickets coexist, each with its own hit
allowance — a modified client multiplies its effective hit rate.
**Fix shape:** rate-limit ticket *creation* per second, derived from
weapon attack speed.

### G13. MobAI pending-hit tables purged only by TTL — **T3** *(extends TODO §14b)*
**Status (2026-09-26):** ✅ **Resolved.** Eager deletion on resolution plus a mob-reference purge (§T3/W3, b291a39; `MobAI.lua:375-390`). The ≤15 s reportedHits residual is documented.
`MobAI.lua` (~197-209): `pendingSkillHits`/`pendingBasicAttacks` reaped
on a 15 s TTL; no `PlayerRemoving` purge. MobAI is already on the §14b
Janitor-audit candidate list — add these two tables explicitly.

### G14. KillRewardManager has no alive-state gate — **T2** *(+ DQ1)*
**Status (2026-09-26):** ✅ **Resolved.** DQ1 = Dead players earn no XP, KnockedDown still earns (§T2/Z2, b291a39; `KillRewardManager.lua:215`).
Verified: no alive/dead/state check anywhere in
`Modules/KillRewardManager.lua` before awarding XP. Whether downed
players should earn kill XP is design → DQ1; if "no", gate at T2.

### G15. VoteManager nil-deref risk on lazy SkillManager — **T5** *(VoteManager already known §6.4)*
**Status (2026-09-26):** ✅ **Resolved.** The call site is nil-guarded (`VoteManager.lua:346-347`, `if sm and sm.InterruptCasting`).
`Modules/VoteManager.lua:40-47`: `getSkillManager()` can return nil;
call sites invoke `.InterruptAll()` unguarded. Add to the already-known
T5 VoteManager work (no PlayerRemoving handler, Audit_4.7 §6.4).

### G16. `foreman.exe` (5.8 MB) tracked in git — **repo**
**Status (2026-09-26):** ⏳ **Open.** `foreman.exe` is still in `git ls-files` (checked 2026-09-26). Pablo's terminal only; see TODO §20.
Redundant (foreman.toml + `foreman install`) and bloats every clone
forever. Untrack; history rewrite optional/post-alpha.

### G17. `sourcemap.json` tracked despite ignore rule — **repo**
**Status (2026-09-26):** ✅ **Resolved.** `sourcemap.json` is untracked, and it no longer exists on disk.
Added before the rule existed; `git ls-files -i` confirms it's the only
tracked-but-ignored file. Untrack.

### G18. Root-level export leftovers, two of them tracked — **repo**
**Status (2026-09-26):** 🟡 **Partial.** No root `*.rbxmx` leftovers remain on disk. `Leg.obj` / `Leg.mesh` are **still tracked** (TODO §20).
`Batch1.rbxmx` (1.1 MB), `batch2.rbxmx`, `GUI.rbxmx` (2.5 MB),
`Female+Staff.rbxmx`, `MobTemplate.rbxmx`, `RuneArmor.rbxmx`,
`Sword.rbxmx`, `BasicProjectile.rbxmx`, `ServerLoader.rbxmx` (untracked
duplicates of `src/` content) + `Leg.obj` / `Leg.mesh` (**tracked**
binary blobs). Archive or delete; untrack the Leg pair.

### G19. `EmoteWheel.lua` exists in three copies — **T10**
**Status (2026-09-26):** ✅ **Resolved.** One copy, `src/shared/.../UI/EmoteWheel.lua`. The lobby/socialplaza re-export shims were deleted in beff2df (§AGX/UI-P3/P5).
`lobby/...UI/EmoteWheel.lua`, `socialplaza/...UI/EmoteWheel.lua`,
`shared/...UI/EmoteWheel.lua`. Principle #5 (pattern consistency):
consolidate to the shared copy at T10; diff the three first — they may
have drifted.

### G20. Open Cloud key in plaintext `.env` — **repo/ops**
**Status (2026-09-26):** ⏳ **Open (ops).** Rotate the key. The tools now read it from the environment (§AGX/X49, 668316b). TODO §20.
Verified: gitignored, never in git history, tools read it correctly.
But it sits in plaintext in a folder that has now been shared with at
least one audit session. **Rotate the key** at your convenience; it's
cheap insurance.

---

## 🟢 Minor

### G21. Debug `print()` noise across server modules — **T10/T11**
**Status (2026-09-26):** 🟡 **Partial.** Hot-path prints removed: per-cast SkillActivated (§AGX/X21) and per-breach (§AGX/X35), both cc776f2. About 163 `print(` lines remain under `*/ServerScriptService` (e.g. `HordeModeSpawner.lua:781,809`). The leveled logger has not been built.
e.g. `HordeModeSpawner.lua:777`, `MatchmakingManager.lua:308`,
`AdminTesting.lua` (many), `SceneManager`. Suggest a tiny leveled
logger (or strip at release); fits the T11 cross-cutting pass.

### G22. `GameModeConfig` placeholder icons `rbxassetid://0` — **T10/content**
**Status (2026-09-26):** ⏳ **Open.** `GameModeConfig.lua:21,48,75` are still `rbxassetid://0`. The menu icon import is in TODO §T10/ICONS.
Broken images in mode-select UI. Sibling of the TODO §16 SoundManager
placeholder item — consider adding to §16.

### G23. `LobbyNPCRegistry.lua` references `TODO_PARKING_LOT.md` — **doc nit**
**Status (2026-09-26):** ⏳ **Open.** `LobbyNPCRegistry.lua:236` still says `TODO_PARKING_LOT.md`, and so does `ArmorManager/init.lua:163`.
File doesn't exist; the parking lot is `docs/TODO.md`. One-line comment
fix.

### G24. `.venv/` missing from `.gitignore` — **repo**
**Status (2026-09-26):** ⏳ **Open.** There is still no `.venv/` line in `.gitignore` (TODO §20).
13 MB local venv currently untracked only by luck. One line.

### G25. Client NetworkManager deferred-listener can hang forever — *(known)*
**Status (2026-09-26):** ⏳ **Open (known).** Same as TODO §11 §NM-D6, which is still open.
If an awaited remote never materializes, the defer thread never exits.
Already covered by parked §NM-D6 hang-recovery; no new action, listed
for completeness.

---

## ❓ Design questions (need Pablo)

- **DQ1 (G14).** Should downed/dead players earn kill XP from proximity
  sharing? If no → alive-gate in KillRewardManager at T2.
- **DQ2 (G7).** Mob-skill damage: unify multiplier-vs-armor order with
  the player pipeline (mechanically consistent, mobs hit ~harder against
  low armor / softer against high), or keep current order as a deliberate
  mob-tuning lever and document it?
- **DQ3 (G5).** ReadyGate overflow policy: (a) flag boot-critical events
  undroppable and evict only droppable ones, or (b) treat overflow as a
  broken client → disconnect with resync message?
- **DQ4.** Sequencing: land Action Set A (repo hygiene) immediately after
  the pending T1 commit as its own commit, or defer to post-alpha?
  Recommended: immediately after — G1 protects everything else.

---

## ✅ Verified good (false alarms rejected this pass)

- Skill cooldowns ARE server-enforced — `SkillManager/init.lua:384-385`
  `CheckCooldown` + the duplicate-cast lock (comment at 331-333).
- Attack range checks use **server** positions, not client claims
  (`AttackHandler/init.lua:319-321`).
- The dirty working tree is the **staged T1 work** documented in
  Audit_4.7 — expected state, awaiting live test + your commit.
- MatchmakingManager snapshots member lists before async work (§L8
  already closed).
- `.env` never committed; all 9 tools load secrets from `.env`, none
  hardcoded.

---

## Proposed action set

**A — Repo hygiene (your terminal, after the T1 commit, one commit):**
```bash
# 1. scope the rbxmx ignore to root only:  *.rbxmx  →  /*.rbxmx   (edit .gitignore)
# 2. also add:  .venv/
git add .gitignore
git add src/                          # picks up the 29 now-unignored .rbxmx
git rm --cached foreman.exe sourcemap.json Leg.obj Leg.mesh
mkdir archive && git mv ... # optional: sweep root *.rbxmx leftovers into archive/ (untracked anyway)
git commit -m "repo hygiene — track src assets, untrack binaries (§G1,G16-G18,G24)"
```
Plus: rotate the Open Cloud key (G20) whenever convenient.

**B — Small cross-cutting code fixes, executable now on sign-off
(T0-owned modules, sanity-checked per §5.7, §-tagged per §5.9):**
- G3 — boot WaitForChild timeouts + loud error, 5 Mains
- G10 — WireOnPlayerReady double-wire latch
- G8 — ReturnTeleporter loud-fail on fallback=0
- G23 — doc-reference comment fix

**C — Tier-mapped (park in TODO.md on sign-off; execute when tier opens):**
- T2: G11, G12, G14(+DQ1) → TODO §1/§2
- T3: G6, G7(+DQ2), G13 → TODO §4 + §14b
- T5: G15 → TODO §6
- T7: G2, G4, G8-followups, G9 → TODO §7
- T10/T11: G19, G21, G22 → TODO §14/§16
- T0 pass-2: G5(+DQ3) → TODO §11

Reply per item or per group (e.g. "A. Yes, B. Yes except G10, C. Yes,
DQ1 no, DQ2 unify, DQ3 a, DQ4 now").
