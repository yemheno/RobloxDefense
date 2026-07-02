# T3 Mob — Surface

> **STATUS: EXECUTED (2026-06-12)** under Pablo's standing rule
> ("unmentioned = fix; direct no-functionality-change fixes apply
> directly"). Landed under `§T3/W<n>` tags. ONE item needs a decision
> (W9, bottom). Map: 2 parallel deep-reads (MobAI 1053 lines solo;
> spawners + registries + behaviors), then self-verification of every
> High claim. All patches AST-verified via HEAD+patch in-memory.

---

## Landed fixes

- **W1** `MobSpawner.Reset` now clears `partyAnchorLevel`/`rewardLevel`
  (stale-anchor trap if a server ever reruns; near-moot on one-run
  servers but 2 lines of insurance).
- **W2** `HordeModeSpawner.SetDifficulty` reads the HordeMode base
  multipliers from GameModeConfig (`_baseMobMults`) instead of the
  hardcoded 0.60/0.85/0.80 that silently diverged from config changes.
  Confirmed drift trap — module init already did it right; SetDifficulty
  didn't.
- **W3** `pendingSkillHits`/`pendingBasicAttacks` entries are deleted
  eagerly on resolution (were flag-and-wait-for-reaper, lingering ≤15 s
  each; reaper stays as fallback). Closes the last of G13.
- **W4** (§14b) per-mob `Died`/`AncestryChanged` connections tracked in
  `mobData.connections`, disconnected in `UnregisterMob`.
- **W5** `MobAI.Init` run-once guard (second Init would duplicate the
  Heartbeat, network handlers, and reaper thread).
- **W6** WalkSpeed writer unification: `SetPaused` restore and
  `SetHordeGlobalSpeedMult` now preserve `frenzyMult` (resume used to
  drop frenzy speed ≤5 s); the frenzy tick includes the horde global
  mult; noted that `SetHordeGlobalSpeedMult` is only ever called with
  1.0 today (kept as a seam).
- **W7** `MobRegistry.GetScaledMob` clamps health ≥1, damage ≥0,
  armor ≥0 against bad overrides.
- **W8** (carried G6, closes it) LaneDefense re-anchors the party level
  on EVERY player's data-ready, mirroring Horde — the old once-flag
  anchored to whichever player loaded first, so a later-loading
  higher-level player never counted and all waves under-scaled.

## Refuted / resolved this pass

- **G7 / DQ2 CLOSED — refuted.** Mob skills and basic attacks BOTH
  route through `StatsManager.CalculateDamageTaken` (armor after
  multipliers), the same order as the player pipeline (§42.1
  multipliers → armor). Skills just carry one extra multiplier
  (skill.damageMultiplier), which is correct. No inconsistency exists.
- **"HordeModeSpawner leaks PlayerAdded conns per pause cycle"
  (map-agent HIGH)** — refuted: the connections have create-once guards
  (`if not playerAddedConn then`); pause/resume cycles reuse them.
- **"MobAssetLoader vs HordeModeMapLoader collision" (map-agent
  HIGH)** — refuted by architecture: Defense and HordeMode are separate
  PLACES (separate servers); the two loaders never share a session.
- **Mob hit-report client trust** — verified server-authoritative:
  resolution iterates server-computed `playersInRange` with a server
  distance re-check; client reports are advisory telemetry only. A
  client can neither dodge by silence nor take-hit by spoof.
- **T0 §2.1a-d death races** — all four held up on re-read (corpse-cast
  guard, reference-equality cleanup, TTL reaper, debug gate).
- G13 residual (player refs inside `reportedHits` ≤15 s) — documented,
  negligible, no code.

## 🟢 Notes (no action)

- Wave-count HUD can overstate if guaranteed spawns exhaust their
  requeue budget (rare clone failures) — cosmetic; revisit if clone
  failures ever show up in logs.
- MobSkillRegistry has no orphaned-skill reverse audit — cleanliness
  only; both current skills (GroundSlam, Roar) are referenced.
- FindTarget's per-mob `Players:GetPlayers()` at 5 Hz is fine at this
  game's scale (≤8 players); revisit only if mob caps grow 4×.

---

## W9 — EXECUTED (decisions: never-fail clone, uniform-over-part scatter)

New shared module **`Modules/MobSpawnHelper.lua`** (§T3/W9), wired into
both spawners:

- **W9a never-fail clone** (Pablo: "mob spawner must never fail — no
  lucky runs skip mobs"): `CloneTemplate` retries forever with backoff;
  the only exits are success or spawner stop/reset. MobSpawner's old
  3-tries-then-drop is gone. Missing-template/unknown-mobId remain loud
  config errors (retry can't fix a typo) — the requeue "UNRECOVERABLE"
  warns now say so and stay silent on reset-abort.
- **W9b uniform scatter** (Pablo: "uniform along the whole object, I
  adjust the size manually"): `GetSpawnCFrame(part, yOffset)` spawns
  uniformly across the part's full X/Z footprint, orientation preserved,
  §LD-MS1 3-stud lift kept. Replaces MobSpawner's fixed-X ±5-Z line AND
  HordeMode's exact-marker-point spawns (both marker paths, incl. the
  ally fallback which now carries the marker part instead of a raw
  position). Resize spawn parts/markers in Studio to reshape areas.
- **Weighted pick** deduped into `PickWeightedId` (both spawners
  delegate; MobSpawner.GetRandomMobId kept as a thin public wrapper).
- Difficulty stacking intentionally NOT consolidated (real per-mode
  semantics, see W2).

Smoke: LaneDefense wave spawns spread across the whole spawn pad;
horde mobs no longer stack on marker centers; a wave with a miniboss
never comes up short.

---

## ~~❓ W9 — the one decision: spawner consolidation (DQ-T3A)~~ (answered above)

MobSpawner and HordeModeSpawner duplicate four helpers:
weighted-random mob pick (verbatim ~20 lines), difficulty-override
stacking, template clone-retry, spawn-position math. Pure spaghetti BUT
the copies have real behavioral differences that consolidation must
reconcile — which makes it a design call, not a direct fix:

- clone retry: MobSpawner gives up after 3 tries (drops the spawn);
  HordeModeSpawner retries forever with backoff (never drops, can stall
  a marker). Which semantic should the shared helper have?
- spawn scatter: MobSpawner randomizes Z ±5; Horde spawns exactly at
  the marker. Intentional per-mode, or should scatter be a parameter?

**Options:** (a) build `MobSpawningHelper.lua` now (~150 lines, both
spawners touched, needs a combat live-test of both modes), (b) park it
for the balance/content pass when spawn tuning happens anyway,
(c) consolidate only the verbatim weighted-pick (zero behavior
difference) and leave the rest.

My lean: **(c) now, (a) later** — take the free dedup, defer the
semantic reconciliation to when you're tuning spawning anyway.

---

Smoke tests: pause/resume a horde run mid-frenzy → mob speed identical
before/after (W6); two-player Lane run where the higher-level player
loads second → wave 2+ mobs scale to them (W8); change
GameModeConfig.mobMultipliers.hpMult → horde difficulty follows (W2).
