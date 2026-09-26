# T1 Pass-2 — Surface (player-state re-audit)

> **STATUS: EXECUTED (2026-06-12).** Landed under `§T1.4/Y<n>` /
> `§T1.3/Y<n>` / `§T1P2/Y2` tags: Y2 (interim Vulnerability clamp ≤3.0),
> Y3, Y4, Y5, Y7, Y8, Y11, Y12. Verification corrected two of my own
> surface calls — **Y10 NOT changed** (synchronous validate() would
> re-enter a circular require: ClassConfig loads *during* PlayerDataConfig's
> load; task.spawn is load-bearing). **Y9 left as-is** (dead appearance
> getters are pending features — TODO §9b, confirmed). **Y6** CLOSED as
> won't-fix (Pablo): no dynamic subscribers will ever need teardown since
> all durable hit data lives in dedicated achievement / gear-XP tables;
> the once-at-boot callback dispatch stays as-is.
>
> **Design decisions (Pablo):** DQ-T1A → interim clamp now, full
> max-stacks system at T2 (TODO §T1P2-STACKS). DQ-T1C/Y1 → penetration:
> keep flat as-is (uncapped); add a separate %-pen stat with the 60 cap
> later (TODO §T1P2-PEN) — no code change needed now. Deferred to T2:
> §T1P2-STACKS, §T1P2-HITTRACKER (Y6 + Y5 confirmation).
>
> Smoke tests for the landed batch: LifeSteward regen still scales near
> wounded allies (Y3 cache); rename a behavior module to force a load
> failure → class boots with a zero-regen fallback + loud warn, not a
> broken class (Y4); combos + achievements still track after the
> HitTracker stat-block removal (Y5); cast a card buff twice → refreshes
> (Y8). Pablo live-tests, then commits.
>
> Fresh-eyes re-read of the T1 tier (CharacterManager+Config+Janitor,
> ClassManager+Config, StatsManager/*, BonusManager, ResourceManager,
> ClassBehaviors/*, HitTracker). Parallel Map fan-out, then every
> high-severity candidate verified against real code + callsite greps.
> IDs `Y1…Y12`. Severity 🚨 bug > 🟡 spaghetti/robustness > 🟢 minor > ❓ DQ.
> **No edits made. Respond per item: `Y1. Yes / No / discuss`.**
>
> **Headline: T1 is in good shape.** It's the most recently audited tier
> (T1.1–1.4 this branch) and it shows — no Critical, nothing in the
> save-corruption class that T0's X1 was. Pass-2 found four Medium
> polish/robustness items and a handful of Low cleanups. I also
> *down-graded three findings the Map agents flagged as Critical/High*
> after verifying them (noted in §"Verified / calibrated down").

---

## 🟡 Medium — worth fixing

### Y1. Penetration cap defined but never enforced — **T1.3**
`PlayerDataConfig.StatCaps.Penetration = { min=0, max=60 }` exists, but
the damage pipeline applies raw player penetration with no clamp:
`ArmorSystem.lua:37` `math.max(0, armor - attackerPenetration)` and
`DamageSystem.lua:125` `… - playerPenetration`. CritChance / CritDamage /
DamageReduction all read their caps (CriticalSystem, DamageSystem:195);
Penetration is the one that doesn't. Gear/talents stacking past 60 pen
silently exceed the intended ceiling.
**Fix shape:** clamp `ArmorSystem.GetPenetration` (and the player-pen
read in DamageSystem) to `StatCaps.Penetration`, mirroring the crit
clamps. (Source of penetration is gear → also relevant at T6, but the
clamp belongs in the pipeline.) → DQ-T1C.

### Y2. Vulnerability multiplier unclamped — **T1.3 (+ T2 stacking)**
`DamageSystem.lua:148-150`: `damage = damage * vulnerability` where
`vulnerability = targetMob:GetAttribute("Vulnerability")`, no upper
bound. It's a **server-set mob attribute** (Arcanist Meteorite,
currently 1.25× per `ArcanistSkills.lua:251`), so not client-exploitable
today — but there's no clamp and the stacking behavior of two debuffs on
one mob is unverified (SetAttribute overwrite vs additive). A future
skill or a stacking bug pushes damage arbitrarily.
**Fix shape:** clamp to a configured max (e.g. `≤ 2.0`) at read time.
Stacking semantics → verify at T2 (skills). → DQ-T1A.

### Y3. LifeSteward proximity scan runs every resource tick — **T1.4**
`LifeStewardBehavior.GetResourceRate:74` calls `CalculateProximityBonus`
(`:87-118`) which loops `Players:GetPlayers()` with nested
FindFirstChild every call — and `ResourceManager.Update` calls
GetResourceRate at 10 Hz per player. Fine at this game's party sizes
(≤8, plus a 3-wounded-ally early break), so **not** the "quadratic
server-staller" the Map flagged — but it's needless per-tick work for a
value that changes slowly.
**Fix shape:** compute proximity on a slower cadence (~1 Hz) or cache it
and refresh on hit/heartbeat-throttle. Pure perf polish, no behavior
change.

### Y4. ResourceManager behavior-load failure is silent-ish, no fallback — **T1.4**
`ResourceManager.lua:104-117`: each ClassBehavior is `pcall(require)`'d
at Init; on failure it only `warn`s and that class gets **no entry in
ClassBehaviors** → no resource regen for the whole server, with just a
console warn (violates principle #3, loud-at-boot). A behavior with a
syntax error ships a class that silently can't build resource.
**Fix shape:** on load failure, either `error()` loudly at boot, or map
the class to a documented no-op fallback behavior so the failure is
visible without killing the place.

---

## 🟢 Low / cleanup

### Y5. HitTracker `lifetime` stats are accumulated but orphaned — **T2 (flag now)**
`CreatePlayerStats` builds a `lifetime` block (`HitTracker.lua:90`) that
`RecordHitDealt` updates every hit (`:177-188`), but: nothing reads it
externally (grep: zero readers), and `SaveLifetimeStats` (`:143-149`) is
a `print` stub under a misleading "Persist lifetime stats" comment. The
*real* persisted kill/hit lifetime stats live in AchievementManager
(`totalKills`/`hitsDelivered` in PlayerData). So this is dead
accumulation, not data loss.
**Fix shape:** delete the `lifetime` block + the stub (AchievementManager
owns persistence), OR wire SaveLifetimeStats into PlayerData if you want
HitTracker to own a per-run summary. → DQ-T1B. (Belongs to the T2
HitTracker pass-2; flagged here for the decision.)

### Y6. HitTracker callback registry has no dedup/removal — *(known, T2)*
`OnHitDealt/OnHitReceived/OnComboUpdated` are append-only
(`HitTracker.lua:33-43`). Already captured as G11 / Audit_4.7 §6.1 for
the T2 HitTracker pass-2. Confirmed still open; no new action — listed
so it's not re-discovered.

### Y7. BonusManager.Recalculate correctness rides an unstated invariant — **T1.3**
`BonusManager.lua` Pass-2 writes `defaultValue + agg` for every
`cfg.BonusStats` entry. Its header comment promises this fixes the
"stale-after-clear" bug — but that only holds because **every BonusStats
default is 0**. If a future stat gets a non-zero default, a cleared
source silently keeps the default instead of zeroing the contribution.
**Fix shape:** one-line assert at Init that all BonusStats defaults are
0, or a comment on the BonusStats table stating the invariant. Cheap
guard against a subtle future regression.

### Y8. AddTimedBonus expire-thread not error-isolated — **T1.3**
`BonusManager.lua:247-252`: the `task.delay` expiry callback calls
`ClearSource` without a pcall. If ClearSource ever throws, the buff
never clears and the thread ref lingers in `timedThreads` until
PlayerRemoving. Low likelihood, trivial guard.
**Fix shape:** wrap the expiry body in pcall + warn.

### Y9. CharacterManager dead appearance getters — **T1.1**
`GetHeadModel/GetHairModel/GetHairColorId/GetClothingColorId`
(`CharacterManager.lua:622-643`) return CharacterData fields that are
never written (always nil); zero callers. Already slated for v0.7 per
the §CC-LEGACY plan.
**Fix shape:** delete now, or leave with a `-- §CC-LEGACY` tag. Your call
— they're harmless (nil-safe).

### Y10. ClassConfig.validate() warns after boot, not at load — **T1.2**
`ClassConfig.lua:368` runs the statDerivation validator via
`task.spawn(validate)`, so a missing-required-stat warning prints *after*
the module is already in use rather than at load. Principle #3 leans
loud-at-boot.
**Fix shape:** call `validate()` synchronously (it only reads config;
the deferred require concern it was avoiding is gone now that
PlayerDataConfig is fully populated before ClassConfig loads). Minor.

### Y11. HunterBehavior MultiCritBonus branch is dead — **T1.4**
`HunterBehavior.lua` adds `MultiCritBonus * (critProcs-1)` but
`CONFIG.MultiCritBonus = 0`, so the branch is inert. Keep as a tuning
knob (comment it) or delete.

### Y12. Boot `print` noise in the hot-path modules — **T1.4/T2**
`ResourceManager` "Loaded behavior: X" per class, `HitTracker` "Setup
complete for <player>" per join. Same family as the X21/X24 noise sweep.
Demote to a single summary line or drop.

---

## ❓ Design questions

- **DQ-T1A (Y2).** Vulnerability: cap it (suggest ≤2.0), and should two
  vulnerability debuffs on one mob overwrite or stack? (I'll verify the
  actual SetAttribute behavior at T2; this is the intended-design half.)
- **DQ-T1B (Y5).** HitTracker `lifetime` block: delete it (Achievement-
  Manager already owns persisted lifetime stats), or wire it into
  PlayerData as a distinct per-run/lifetime combat summary?
- **DQ-T1C (Y1).** Enforce the Penetration 60 cap in the pipeline now, or
  is uncapped penetration an intentional gear-chase lever? (Crit/DR/etc.
  are all capped, so enforcing is the consistent choice.)

---

## ✅ Verified / calibrated down (Map agents over-weighted these)

- **LifeSteward proximity = "Critical quadratic staller"** → reality:
  ≤8-player co-op with a 3-ally early break; Low/Med perf polish (Y3).
- **HitTracker SaveLifetimeStats = "High data loss"** → reality: the
  block is never read and AchievementManager owns the persisted stats;
  it's orphaned dead data (Y5), not loss.
- **Vulnerability = exploitable** → reality: server-set mob attribute
  from skill config, not client input; latent not active (Y2).

## ✅ Confirmed solid (no action)

Damage/crit/heal math is correct end-to-end (pipeline order, crit
multi-proc geometric cap, heal zero-clamp, armor division never /0);
BonusManager single-pass Recalculate + write-time stat validation +
timed-thread cancel-on-leave all correct; CriticalSystem/DamageReduction
read caps from StatCaps; Janitor Add/Remove/Destroy/LinkToInstance
verified (idempotent destroy, no double-free, cleanup-after-destroy
handled); ClassManager 7 lazy getters boot-race safe; RequestClassSwitch
validation intact (re-confirmed from T0); all 4 classes pass the
statDerivation catalog; CharacterManager weak-table + explicit-cleanup
belt-and-suspenders and the hair-weld pipeline are correct (untouched).

---

## Proposed action set

Smaller than T0 — this tier is mostly polish. Suggested grouping:

- **Batch A — pipeline correctness (Y1, Y2, Y7):** clamp Penetration +
  Vulnerability, assert the BonusStats-zero invariant. All in
  StatsManager/* + BonusManager + a DamageSystem clamp. One smoke test
  (stack penetration gear, hit an armored mob; cast Meteorite twice).
- **Batch B — robustness (Y4, Y8):** loud behavior-load failure,
  pcall the timed-bonus expiry.
- **Batch C — cleanup (Y3, Y9, Y10, Y11, Y12):** proximity throttle,
  dead getters, sync validate, dead MultiCritBonus, print noise.
- **Defer:** Y5 + Y6 → T2 HitTracker pass-2 (with DQ-T1B answered).

Reply per item or per batch (e.g. "A yes, B yes, C yes except Y9 keep;
DQ-T1A cap 2.0 + overwrite, DQ-T1B delete, DQ-T1C enforce").
