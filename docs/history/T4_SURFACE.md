# T4 Death / Game flow — Surface

> **STATUS: EXECUTED (2026-06-12)** under the standing rule. Landed
> under `§T4/V<n>` tags. One design question open (DQ-T4A, bottom).
> Map: 2 parallel deep-reads (DeathSystem+GameStateManager,
> DefenseLine stack); every High/Critical map claim verified before
> action — most were inflated (details below).

---

## Landed fixes

- **V1** (§14b) DeathSystem's per-player `CharacterAdded` connection is
  now stored in `playerStates` and disconnected in `CleanupPlayer`
  (previously only `diedConnection` was cleaned — one leaked closure
  per leaver). Type annotation updated to match.
- **V2** `HandleRespawnRequest` dedup: spamming RequestRespawn while
  dead used to queue one delayed respawn thread per packet (each
  full-healing when it fired, and the delayed body never re-checked
  state). One queued respawn at a time now; flag clears when it fires.
- **V3** (X9 family) `DefenseHealth.SendStateToPlayer` — the
  late-joiner defense-bar push fired from the data-ready boot window
  via raw FireClient; now ReadyGate-routed (lazy getter, NetworkManager
  fallback), matching the T0P2/X9 pattern.

## Verified / calibrated down (map agents flagged, checks cleared)

- **"CRITICAL: DefenseLine Heartbeat never disconnected"** — one
  connection per server lifetime in a one-run place; identical to every
  other system's Heartbeat. Non-issue.
- **"CRITICAL: DefenseAnimation tweens leak"** — tweens run on parts of
  mobs that are destroyed moments later; Roblox cancels/collects tweens
  on destroyed instances. `animatingMobs` already dedups double-plays.
  Non-issue at this game's scale.
- **"HIGH: callback registries grow across rounds"**
  (DefenseHealth/DefenseCombo/MobSpawner) — registered once at boot,
  one-run servers. Non-issue.
- **"MEDIUM-HIGH: GetAllMobData may traverse workspace"** — verified in
  T3: it returns the `activeMobs` registry table directly, O(1). The
  detection loop is 0.2 s-throttled over a registry. Fine.
- **"MEDIUM: damage callbacks race IsDestroyed"** — `onDamagedCallbacks`
  has zero registrants. Moot.
- **"CHAPTER_MAX_HEALTH hardcoded"** — it lives in DefenseConfig, which
  IS the config home for line tuning. Non-issue.
- **RequestRespawn validation** — state==Dead gate confirmed present
  (the spam vector it did have is V2).
- **§G2 ReturnToLobby idempotency, §D2 LateInit idempotency, §LD-DS3/4/5
  in-place respawn ordering, knockdown state machine, bleed-out timer
  single-thread, HP-pin loop** — all held up on re-read.

## 🟢 Notes (no action)

- DefenseCombo fires a client update per line-hit (≤5/s) — payload
  carries per-hit count the UI shows; debouncing would change UX. Leave.
- Knockdown/bleed-out durations are named CONFIG at the top of
  DeathSystem — fine as-is.

---

## ❓ DQ-T4A — party-wipe behavior (needs Pablo)

There is **no all-players-dead handling anywhere**. Current reality:
- Players who die can respawn freely via the death UI (RequestRespawn,
  1 s delay, no cost/limit/cooldown beyond the knockdown→bleed-out→dead
  cycle itself).
- LaneDefense: a full wipe just means the line tanks alone until it
  breaks → Defeat fires from line destruction. Coherent-ish.
- HordeMode: a full wipe changes nothing — the run timer keeps
  counting, and if nobody clicks respawn the server happily reaches
  **TriggerVictory with everyone dead**.

Options: (a) keep free respawns and accept it (deaths already cost
knockdown time; wipe-victory is an edge case nobody will see), (b) on
full wipe → TriggerDefeat immediately (classic horde rules), (c) limit
respawns per run (lives system) — bigger design change, post-alpha.
My lean: (b) for HordeMode only — it's ~10 lines in the DeathSystem
death path (count Alive/KnockedDown players; all Dead → GameStateManager
.TriggerDefeat), and Lane keeps its line-death semantics.

---

Smoke: leave-and-rejoin during knockdown (V1 — no stale handlers);
mash the respawn button (V2 — exactly one respawn); late-join a Lane
run → defense bar correct immediately (V3).
