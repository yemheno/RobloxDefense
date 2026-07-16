# Scaling Audit — §SCALE (2026-07-16)

Stress-proofing for three FUTURE modes: **A) World Boss** (1 boss + adds,
20-30 players), **B) Massive Horde** (150-250 mobs, 8 players),
**C) Siege** (30+ players, 100+ mobs, sustained AoE). Method: derive
calls/sec formulas per system (M = mobs, P = players), verify in code,
fix what's direct, document the walls.

Doctrine ("smart frames"): every recurring cost must be **bounded by a
cap, a window, or a budget** — never by "how intense the fight is".
Reference patterns already in the codebase: DamageNumberBatch 0.1 s
window (§PERF/F5), pooled+capped client numbers (§PERF/F6), per-frame
shared snapshot (§PERF/F1).

## The hard wall (architectural, not fixable in Lua)

**Server-side Humanoids.** Each mob is a full Humanoid simulated by the
engine (~0.05-0.15 ms each, every frame, regardless of our code).
Practical budget ≈ 100-150 live. Current horde aliveCap = 72 is tuned
correctly. **Scenario B at 250 mobs is NOT reachable with Humanoid
mobs** — it needs lightweight custom movers (CFrame lerp / single
BodyMover + health attribute) for trash, reserving Humanoids for
elites/bosses. Parked as the "massive horde" project — decide before
building that mode. World boss (A) is fine: few Humanoids, many players.

## Fixes applied this pass

- **§SCALE/S1 — Horde spawn markers** (HordeModeSpawner): the 60 Hz
  marker-follow Heartbeat moved 8 anchored Parts × P players every frame
  — 480·P replicated position writes/s (~100 KB/s of invisible-part
  traffic at P=30). Markers now position on demand inside each spawn
  tick (~once per 2.5 s). Parts kept — §T3/W9b resize-in-Studio scatter
  still works.
- **§SCALE/S2 — MobBasicAttackCast / MobSkillCast** (MobAI): were
  FireAllClients per swing/cast = O(casts·P) sends (~210 KB/s aggregate
  under C). Now range-scoped (150 studs) via `MobAI.FireNearbyClients`;
  the attack TARGET is always included (client-auth hit detection
  depends on it), characterless players included (cheap, safe).
- **§SCALE/S3 — MobDeath** (KillRewardManager): FireAllClients per kill
  (O(kills·P) during horde chains) → range-scoped 150 studs. Only live
  consumer is MobVisuals death VFX. If a global kill-feed is added
  later, use a NEW batched event; don't re-globalize this one.
- **§SCALE/S4 — MonitoringSystem**: RecordPotentialHit allocated a GUID
  string + a task.delay closure per (mob cast × player in range) —
  ~1500/s under C, pure GC pressure. Now: monotonic integer ids, one
  amortized 1 s sweep resolves dodges, and a `SAMPLE_RATE` dial (1 =
  full recording; raise for 20+-player modes — dodge rates stay
  unbiased since numerator and denominator sample together).
- **§SCALE/S5 — DoT/HoT/heal numbers** (SkillEffects): fired one
  RemoteEvent per tick per target, bypassing the F5 batch (one player
  DoT-ing 30 mobs = 30 events/s; AoE HoT over 6 allies = 12 events per
  tick). Now queued and flushed every 0.25 s as DamageNumberBatch /
  HealNumberBatch (new event; client handler added in DamageNumbers).
- **§SCALE/S6 — rate limits** (NetworkManager manifest): P-amplifying
  or state-machine client→server events dropped from the 30/s default:
  NPCInteract 4/s, MatchmakingRequest / PlayerListRequest /
  GetPartyState 4/s, RequestStartGame / RequestNextWave /
  RequestReturnToLobby 2/s.

## Verified scale-safe (formulas held)

MobAI FindTarget 5·M·P on cached snapshot (§F1); SkillEffects ticks
O(5·M) at 2 Hz — the `_direct` effect keys collapse the P dimension (a
second player's DoT overwrites, doesn't stack: load-bearing for scale,
remember this if effect stacking is ever redesigned); DamageNumberBatch
≤10 events/s/attacker; HitTracker combos 10·P/s throttled; SkillManager
buff/cast loops 60 Hz lazy-alloc (§M4); DeathSystem Update noop-for-
Alive; regen/vitals CPU O(P) at 1 Hz; projectiles fully client-side
(server simulates zero); pending-attack tables eager-delete + reaper;
horde spawn loop O(P²) per 2.5 s tick — fine at horde's P=8.

## Deferred (ranked, with reasons)

1. `[P1]` **Mobs → `workspace.Mobs` folder + AttackShapes folder-scan.**
   Both spawners parent mobs to workspace ROOT, so every AttackShapes
   query scans M + P characters + S map children (O(160k) FindFirstChild
   /s under C, bursty within single frames). Moving mobs to the folder
   and scanning only it for `IsMob` queries is the biggest remaining CPU
   win — but touches mob-parenting assumptions across MobAI/spawners/
   cleanup, so it needs its own verified pass. NOTE: the workspace-root
   scan must STAY for player-targeted queries (characters live at root).
2. `[P2]` **VitalsUpdate O(P²)** (PlaceLifecycle): full P-entry snapshot
   FireAllClients at 1 Hz = ~90 KB/s aggregate at P=30. Under budget per
   client (3 KB/s) but pure waste. Design choice: hp/maxHp → player
   attributes (native delta replication) + event-driven static fields.
   Do before any 30+ player mode.
3. `[P2]` **AttackFired scoping** (AttackHandler): per-swing loop to all
   other players (~1.7k sends/s at C). Same range-scope pattern as S2.
4. `[P2]` **Knockback LinearVelocity pooling** (MobAI): boss AoE
   knockback on 30 clustered players = 30 Attachment+LinearVelocity
   create/destroy per cast. Pool one per character.
5. `[P3]` **DefenseLineDamaged coalesce** (DefenseHealth): per-breach
   FireAllClients; largely redundant with DefenseLineUpdate HP
   broadcast — coalesce or move HP to an attribute.
6. `[P3]` **MobAI 60 Hz gating split**: the bare per-frame loop over M
   mobs (~4 property reads each) starts to matter at M ≳ 200 — only
   relevant if the Humanoid wall (above) is ever solved.
7. `[P3]` **VoteUpdate debounce** (VoteManager): rebroadcast per vote
   cast; 0.25 s window would bound it. Short-lived, low priority.
