# Roblox Defense — Sanity Check Report **V2**

**Date:** 2026-04-23 (overnight scheduled run)
**Scope:** Deep-dive on modules V1 didn't cover, cross-module integration,
data/persistence, un-wired events, economy/balance follow-ups, and a
prioritized action list.
**Previous audit:** `docs/SANITY_CHECK_REPORT.md` (V1) — still valid; this
report is a second pass that does **not** repeat V1's findings.

---

## 0. TL;DR

Phase 1 of this run landed the **personal supply-vote + respec-fragment
economy** cleanly — all the hot `data.Account.RespecTokens` writes have
been migrated to `respec_scroll` inventory items, auto-combine works,
and `RespecTokens` is now only present as a legacy field in
`PlayerDataConfig`. See §1 for the diff.

The V2 deep-dive on the modules V1 didn't cover found **one real
BLOCKER** (mob-spawner start races player data load in Horde mode) and
**two HIGH** bugs (skill-hit resolution can race mob death; VoteManager
bootstrap is asymmetric between places). The rest is MEDIUM/LOW
cleanup. Data-persistence via `DeepMerge` is actually in good shape —
old saves gain the new `Inventory` table without code changes.

Top recommendations for the morning, in order:

1. Defer `HordeModeSpawner.Start()` until at least one player's data has
   loaded (§3.1 P0).
2. Add a `state == DEAD` guard before `ResolveSkillHits` applies damage
   (§3.2 P0).
3. Normalize `VoteManager.Setup → SetRunState → SetModeDeps` ordering
   across both combat places (§3.3 P1).
4. Wire the remaining `DEBUG_MOB_AI` / `DEBUG_DAMAGE` flags that V1
   flagged but nobody landed (§2.1 P1).
5. Low-severity: cache `HitTracker` in `ResourceManager.Init()`; add a
   `ConsumeItem` header note clarifying auto-convert is AddItem-only;
   add currency overflow caps.

Content/balance follow-ups are still the same as V1 (mob variety,
sound, animations). This audit does **not** re-raise them — they
dominate V1's priority matrix and remain the real alpha blockers.

---

## 1. Changes Since V1 — Phase 1 of This Run

All changes are unstaged; please review before staging.

### 1.1 Vote system split — shared vs personal

- `src/shared/ServerScriptService/Modules/VoteManager.lua` — full rewrite
  (still ~550 lines). Supply votes now branch into a **per-player**
  flow (`VoteStartPersonal` / `VoteCastPersonal` / `VoteResultPersonal`).
  Each player rolls their own 3-card trio. Threat and tactical votes
  keep the existing shared pipeline untouched.
- Per-player fragment pre-roll: 10 % per supply vote, **capped at one
  pre-roll per player per run** via `fragmentRolledThisRun[player]`.
  When the roll hits, one of the 3 card slots is replaced by
  `RespecFragment`.
- Per-player cooldowns (`personalCooldowns[player][cooldownKey]`) so
  one player's pick doesn't gate another player's trio.
- `Reset()` now clears the personal state table and
  `fragmentRolledThisRun`.

### 1.2 New card: `RespecFragment`

- `src/shared/ServerScriptService/Modules/CardRegistry.lua` — appended
  the `RespecFragment` supply card (id, name, description, no
  cooldown, no eligibility gate — gating lives in VoteManager).
  Both `pickCards` and `pickCardsPersonal` filter it out of the
  normal pool so it can **only** appear via the 10 % roll.

### 1.3 Inventory items

- `src/shared/ReplicatedStorage/Shared/ConsumableConfig.lua`:
  - New `respec_fragment` item (`maxStack = 99`, effect type `None` —
    pure collectible, not directly consumable).
  - `respec_scroll` bumped from `maxStack = 5` → `99`, description
    updated to "Consume to reset your talents without spending
    Essence."

### 1.4 Inventory auto-combine

- `src/shared/ServerScriptService/Modules/InventoryManager.lua`:
  - New internal `tryAutoConvert(player)` loops 4 `respec_fragment` →
    1 `respec_scroll`.
  - New public `ConsumeItem(player, itemId, quantity) → bool`.
  - `AddItem` now calls `tryAutoConvert` then `SendInventory` once at
    the end.

### 1.5 Respec flow migrated off `RespecTokens`

- `TalentManager.lua` — `RespecTalents` now checks
  `InventoryManager.HasItem(player, "respec_scroll", 1)` and consumes
  via `InventoryManager.ConsumeItem`. Essence remains the fallback.
- `SharedEventHandlers.lua` (`RespecStats`) — same migration.
- `DailyLoginManager.lua:195-201` and `AchievementManager.lua:512-518`
  — both paths now grant `respec_scroll` via `InventoryManager.AddItem`
  instead of incrementing `data.Account.RespecTokens`.
- `PlayerDataConfig.RespecTokens` field **intentionally left in place**
  for save-data compatibility (per task spec — deprecation/cleanup is
  a future migration concern).

### 1.6 Client

- `src/shared/StarterPlayer/StarterPlayerScripts/UI/VoteUI.lua`:
  - New `VoteStartPersonal` / `VoteResultPersonal` listeners.
  - `VoteCard` accepts a `hideVoteCount` flag; personal trios hide the
    tally badge.
  - Header renders "SUPPLY — YOUR PICK" on personal votes, "Chosen: X"
    on personal result.

### 1.7 Docs

- `docs/BALANCE_NUMBERS.md` — new section 47 ("Respec Economy")
  documenting the fragment loop, math (`P(≥1) ≈ 0.522`, `E[runs] ≈ 7.7`
  per full respec), and backwards-compatibility notes.

### 1.8 Post-Phase-1 grep — no hot `RespecTokens` references remain

```
$ grep -rn 'data\.Account\.RespecTokens' src/
src/shared/ServerScriptService/Modules/SharedEventHandlers.lua:54: -- (comment)
```

Only one hit, and it's a deprecation comment. ✓

---

## 2. Modules Not Deeply Covered in V1

I did full line-by-line passes on the modules below (V1 concentrated on
shared combat quality). Every finding cites `file:line` verified by
re-reading.

### 2.1 MobAI.lua (977 lines)

| # | Finding | Severity | Lines |
|---|---|---|---|
| 2.1a | **Skill-hit resolution races mob death.** `ResolveSkillHits()` iterates `pending.playersInRange` captured at cast time and applies damage without re-checking that the mob is still alive. `ResolveBasicAttack()` at line 793 does this check; skills don't. | **HIGH** | 653-706 |
| 2.1b | String-based pending-attack cleanup in `UnregisterMob` uses `string.find(castId, mobFullName, 1, true)` — a substring match. If two mobs have similar hierarchical names, the shorter name matches cast IDs of the longer one and incorrectly clears them. | MEDIUM | 264-273 |
| 2.1c | Pending skill-hit table has no wall-clock reaper — only per-cast cleanup via `task.delay`. A frozen client that never reports will leak entries forever. Slow leak, unlikely to OOM in a short alpha but should be closed. | MEDIUM | 547-706 |
| 2.1d | Log-spam on hot path — V1 flagged this; it still prints unconditionally. Lines 103, 140, 248-250, 947 fire on every register / unregister / paused state change. | LOW (V1 still unlanded) | 103, 140, 248-250, 947 |

**Recommended fix for 2.1a:**
```lua
-- in ResolveSkillHits, before line 682
if mobData.state == STATES.DEAD then
    pendingSkillHits[skillCastId] = nil
    return
end
```

### 2.2 MobSpawner.lua (522 lines)

| # | Finding | Severity | Lines |
|---|---|---|---|
| 2.2a | If `mobsFolder` fails to `WaitForChild` within 10 s, `Init()` still falls through and `CacheTemplates()` errors out on `FindFirstChild` against nil. `GetTemplateCount()` then masks the problem by returning 0. | MEDIUM | 79-84, 168 |
| 2.2b | `template:Clone()` on line 423 is not pcall-wrapped. If the clone fails, `SpawnMob` silently returns nil and the caller (`SpawnWave` at 331, 356) does not check the return value, so `mobsSpawnedThisWave` desyncs from actual count. | MEDIUM | 423, 331, 356 |
| 2.2c | `spawnPoint` is resolved lazily on first spawn (435-440). Luau assignment is atomic so the race is currently benign, but once anyone refactors spawnPoint to be a mutable struct this becomes a real bug. Move to `Init()`. | HIGH (latent) | 435-440 |
| 2.2d | `preSpawnHook` timeout loop waits up to 10 s; if the hook runs long, the loop exits and the spawner proceeds *without* re-checking `hookDone`. A hook that completes just after timeout will race the first spawn. | MEDIUM | 273-289 |
| 2.2e | `CONFIG.MaxWave` comparison halts the game at wave 13 — the codebase implies procedural waves exist but none are implemented. Document the hard limit. | LOW (docs) | 245-248 |

### 2.3 DamageSystem / StatsManager suite

| # | Finding | Severity | Lines |
|---|---|---|---|
| 2.3a | `ElementalSystem.GetMultiplier()` return is used unguarded at `damage * elementMult`. If the elemental system is misconfigured and returns nil, this throws during any outgoing damage calc. One-line fix: `local m = Elem.GetMultiplier(...) or 1.0`. | MEDIUM | DamageSystem.lua:110-112 |
| 2.3b | `CriticalSystem` is declared as a sub-system reference populated by `StatsManager.Init()`. If wiring fails, `DamageSystem` silently skips crits (the `if self.CriticalSystem` guard passes nil). Add an `assert(CriticalSystem, "...")` in `StatsManager.Init()` so misconfig is loud. | MEDIUM | DamageSystem.lua:10, 103-105; StatsManager/init.lua:19 |
| 2.3c | `GetBaseDamage` lazy-loads WeaponManager with a silent fallback to 0 on failure. Defensive, but the first-load failure should `warn()` once so the operator sees it. | LOW | 34-40 |

### 2.4 DeathSystem.lua (451 lines)

| # | Finding | Severity | Lines |
|---|---|---|---|
| 2.4a | `HealthChanged` is connected once in `OnCharacterAdded` and can fire multiple times during the knockdown window (HP is pinned at 1 per frame, external systems can still mutate it). The re-entry guard at 199 prevents the logic bug but wastes work. Disconnect the listener when knockdown starts, reconnect on revive. | MEDIUM | 180-202, 361 |
| 2.4b | `EnterKnockdown()` schedules a crawl-loop animation via `task.delay(0.5, …)`. The callback re-fetches `currentData` but not the player's character. If the player respawned during that 0.5 s window, the crawl animation plays on the **new** character. | MEDIUM | 220-226 |
| 2.4c | `RevivePlayer` fetches the humanoid once at line 283 then assigns `Health`/`MaxHealth` at 288 without re-verifying the humanoid is still alive. Cheap nil-guard would close it. | MEDIUM | 283-288 |
| 2.4d | `HandleRespawnRequest` silently succeeds if the player leaves during the 1-s respawn delay. Not a bug, but impossible to post-mortem without a log. | LOW | 321-338 |

### 2.5 InventoryManager.lua (post-Phase-1)

| # | Finding | Severity | Lines |
|---|---|---|---|
| 2.5a | `tryAutoConvert` header comment says "does NOT call SendInventory"; `AddItem` now calls it after. Comment is accurate literally but misleading — update to say "called from AddItem, which sends inventory once at the end." | LOW | InventoryManager.lua (new helper block) |
| 2.5b | `ConsumeItem` does **not** call `tryAutoConvert`. Intentional (fragments are only produced, never directly consumed) but worth documenting. | LOW (docs) | ConsumeItem block |
| 2.5c | `EquipAccessory` removes old accessory bonuses before applying new ones. If `ApplyAccessoryBonuses` fails silently, the old bonuses are gone and new ones don't land — state is inconsistent until next re-equip. Guard with a pcall + rollback or verify config upfront. | LOW | ~260-280 |

### 2.6 ShopManager.lua

| # | Finding | Severity | Lines |
|---|---|---|---|
| 2.6a | `PurchasePremium` is still a stub (`MarketplaceService` not wired). V1 flagged the same; no regression. Treat as alpha-acceptable only if the launch is free-only. | LOW (known) | 232-245 |
| 2.6b | Level-gated prices read `data.Account.Level` in a check-then-act pattern. A level-up between the check and the grant means the player pays the pre-level-up price for a potentially post-level-up item. Low probability, closable by re-reading Level after the spend. | MEDIUM | 87-92, 128, 192 |
| 2.6c | Consumables are granted **before** currency is spent. If spend fails, the item stays. Intentional "optimistic" pattern per internal design, but it should be documented in the header. | LOW (docs) | 216-222 |

### 2.7 ResourceManager.lua

| # | Finding | Severity | Lines |
|---|---|---|---|
| 2.7a | `Update()` (Heartbeat) performs `Modules:FindFirstChild("HitTracker")` every frame per player. With 4-10 players this is 240-600 calls/sec that should be a one-time init cache. | MEDIUM | 260 |
| 2.7b | `OnClassChanged` assumes `ClassBehaviors[newClass]` exists. Missing class behavior silently resets the player's resource to 0/100 without notifying the client. Guard with warn + defaults. | MEDIUM | 327-346 |
| 2.7c | `EnsureClass` clamps to new max but never calls `NotifyClient` on shrink — player's UI shows stale value until next regen tick. | LOW | 132-148 |

### 2.8 CurrencyManager.lua

| # | Finding | Severity | Lines |
|---|---|---|---|
| 2.8a | No cap on `Merits` or `Essence`. Over a long session or a buggy achievement chain, accumulations could theoretically overflow. Clamp at a large sentinel (e.g. `9_999_999`). | MEDIUM | 77, 94, 112, 127 |
| 2.8b | `AddMerits(player, 0)` still fires the merit callbacks (min-1-merit rule produces 1). Guard with an early return on `amount <= 0`. | LOW | 73-86 |
| 2.8c | Spend failures return `false` silently — callers have no breadcrumb for post-mortem. Either `warn()` on failed spend or document that `CanAfford*` must be called first. | LOW | 111-134 |

### 2.9 BonusManager.lua — clean

No new findings on top of V1. The source-isolated bonus architecture is
solid; `InjectDataManager` correctly breaks the cyclic dep; timed bonuses
clean themselves up with `player.Parent` guards.

---

## 3. Cross-Module Integration Smells

### 3.1 [BLOCKER] HordeModeSpawner starts before player data is guaranteed loaded

`src/hordemode/ServerScriptService/HordeModeMain.server.lua:250` calls
`HordeModeSpawner.Start()` unconditionally. The first mobs can spawn
before any player's DataStore load has completed; the defensive fallback
at lines 266-285 reads `player:GetAttribute("Level")` which is only set
*after* data-ready, so for the first couple of seconds mobs scale to
level 1. Visible at the start of every horde match.

**Fix:** Either await at least one data-ready player before calling
`Start()`, or synchronously call `SetPartyAnchorLevel` after data-ready
and only then kick off the first spawn.

### 3.2 [HIGH] VoteManager bootstrap asymmetry between Horde and Lane

- **Lane** (`lanedefense/.../LaneDefenseMain.server.lua:254-270`) calls
  `Setup → SetModeDeps → SetRunState` before any vote fires.
- **Horde** (`hordemode/.../HordeModeMain.server.lua:298-310`) calls
  `Setup → SetModeDeps`, and defers `SetRunState` until inside the
  vote loop (line 529).

This is only safe because Horde's vote loop never fires before the
first call to `SetRunState`. But if the scheduler interleaves the
bootstrap with a stray `StartVote` (e.g. an admin tool), the Horde
path trips over an uninitialized `runState`. Fix by moving
`SetRunState({ difficulty, modeId = "HordeMode" })` into the bootstrap
before the vote-loop `task.spawn` begins.

### 3.3 [HIGH] Central Boss has no vote/modifier system at all

`src/centralboss/ServerScriptService/CentralBossMain.server.lua` does
not load `VoteManager`, `CardRegistry`, or `RunModifiers`. This may be
intentional — boss fights are bespoke — but any shared code that
consults `RunModifiers.GetTotalDangerBonus()` during a central-boss
fight will read against a module that was never initialized. Confirm
no shared damage/loot path assumes RunModifiers is wired in every
place, or add a lightweight `RunModifiers.Init(noOp = true)` for the
boss place so `Get*` calls return zeros rather than erroring.

### 3.4 Smell — lazy requires create silent-disable ladders

Every place-level combat module uses lazy `require(Modules:WaitForChild(...))`
helpers. When a require fails, the calling code falls back to a nil check
and proceeds with reduced functionality (no crits, no resource regen, no
XP grant). There is no centralized post-Init assertion that everything
wired. A one-time `StatsManager.ValidateDependencies()` helper that
warns loudly on any nil sub-system would turn several invisible bugs
into diagnose-able ones.

### 3.5 Smell — `task.delay` cleanup footprints

Both `MobAI` (5 different delays for skill/basic cleanup) and
`DeathSystem` (knockdown animation, respawn) use per-entry
`task.delay`. In the failure mode where the callback throws, entries
leak. Consolidate into a single "reaper" thread per module that scans
the pending table every N seconds. Already called out in V2.2.1c.

---

## 4. Data / Persistence Risks

### 4.1 `DeepMerge` correctly backfills missing fields

`src/shared/ServerScriptService/Modules/PlayerDataManager/init.lua:106-119`
recursively merges `AccountDefaults` into a loaded save. Verified that
every field referenced by Phase-1 hot code is covered:

- `AllocatedTalents` → default `{}` ✓
- `BonusTalentPoints` → default `0` ✓
- `Inventory` → default `{}` ✓ (this is what makes the new respec
  scroll path safe for returning players)
- `RespecTokens` → default `0` (legacy; still present but no longer
  read by any hot path)
- `TrinketId` / `Ring1Id` / `Ring2Id` → default nil ✓

The merge runs *before* `dataReadyCallbacks` fire (line 215-224), so
any module that reads via `PlayerDataManager.GetData` during a normal
flow sees the full shape.

### 4.2 [MEDIUM] `DeepMerge` never removes deprecated keys

Left-over fields from earlier schemas accumulate in DataStore saves
forever. With `RespecTokens` now deprecated, long-running accounts
will carry a small amount of dead data indefinitely. Not a bug, but
worth a future cleanup-sweep task or an explicit "forever-orphan"
acceptance note in `PlayerDataConfig`.

### 4.3 [LOW] `SetupPlayer` cleans orphan *stat* keys but not *account* keys

`PlayerDataManager/init.lua:229-247` correctly strips stat keys that
are no longer in `Config.PrimaryStats`. The same sweep doesn't exist
for the Account table — e.g. a renamed cosmetic flag would linger.

---

## 5. Economy / Balance Follow-Ups (Not Decided Yet)

These are numbers/decisions that the user hasn't locked in and that
will bite the first serious play-testers if they ship unresolved.

1. **Respec scroll re-acquisition curve at endgame.** At ~7.7 runs/scroll,
   a player who has already cleared all 4 alpha classes' talent trees
   can still respec freely. Good. But if more classes ship, the fragment
   curve doesn't scale with class count. Consider a soft "N scrolls
   cap" stored in account data or a scroll-sink (trade for cosmetic).
2. **Merit inflation vs shop prices.** A clean run earns ~350-500 Merits
   (V1 §2.5). Shop consumable prices at 40-80 per potion mean a single
   run only refills ~6-10 consumables. Alpha-friendly; re-tune after
   player telemetry.
3. **Bonus talent point grants.** `BonusTalentPoints` exists but has no
   grant paths wired anywhere I could find. If the intent is to grant
   these from achievements, it should be in `AchievementManager` reward
   types. If it's dead, remove it from defaults.
4. **Central boss reward scaling.** No visible currency/XP emission from
   the central-boss place in the bootstrap — verify `KillRewardManager`
   is initialized there or boss runs grant nothing.
5. **Elite Bounty tactical card gating.** `CardRegistry.EliteBounty`
   `eligible = { [4]=true, [7]=true, [10]=true, [12]=true }` — wave 12
   is the last wave, and the card's effect is "next wave." On wave 12,
   is this a no-op? Quick win: remove wave 12 from the eligibility set.
6. **Fragment card stack rules.** At the boundary — player has 98
   `respec_fragment` and receives +1 from a vote. `AddItem` increments
   to 99, `tryAutoConvert` immediately consumes 4 into 1 scroll. Works.
   But if someone ever bumps `maxStack` down, the `AddItem` path has no
   cap check. Worth a one-line assertion against `ConsumableConfig.maxStack`.

---

## 6. Un-Wired UI / Client Features

I cross-referenced every `NetworkManager.FireClient` / `FireAllClients`
call against the union of `NetworkManager.OnServerEvent` listeners.
Summary (not exhaustive — the shared UI folder is large):

- **Server fires, client never listens:** none definitively identified —
  but the following are fired with only place-specific listeners:
  `SkillActivated`, `SkillVisual` (fired by skill pipeline; likely
  consumed by a shared UI module in `StarterGui/AppGui/**`, but worth
  confirming nobody depends on a place-only listener).
- **Client listens, server never fires:** none identified — but
  `VotePending` is fired *only* by `HordeModeMain` and has no
  counterpart in `LaneDefenseMain`; the lane-mode vote UI will never
  show the "Vote starting in 2s" overlay. Cosmetic, not broken.
- **Client UI components without server events (dead modules):** none
  found; all the shipped UI components subscribe to live events.

Recommend a build-time check script that asserts every event declared
by `GetEvent` is either fired or listened to somewhere.

---

## 7. Prioritized Action List — Top 15

| # | Priority | Finding | File:Line |
|---|---|---|---|
| 1 | **P0** | Defer `HordeModeSpawner.Start()` until first player's data is ready | `HordeModeMain.server.lua:250, 266-285` |
| 2 | **P0** | Guard `ResolveSkillHits` against stale (dead) mobData | `MobAI.lua:653-706` |
| 3 | **P0** | Land the V1 log-spam gate (`DEBUG_MOB_AI`, `DEBUG_DAMAGE`) — still un-landed | `MobAI.lua:103,140,248-250,947` |
| 4 | **P1** | Normalize VoteManager `Setup`→`SetRunState`→`SetModeDeps` across Lane/Horde bootstraps | `HordeModeMain.server.lua:298-310` |
| 5 | **P1** | Nil-fallback `ElementalSystem.GetMultiplier()` in DamageSystem | `DamageSystem.lua:110-112` |
| 6 | **P1** | Assert `CriticalSystem` wired in `StatsManager.Init` | `StatsManager/init.lua:19` |
| 7 | **P1** | Cache `HitTracker` at init in `ResourceManager` (perf) | `ResourceManager.lua:260` |
| 8 | **P1** | Guard `OnClassChanged` against missing `ClassBehaviors[newClass]` | `ResourceManager.lua:327-346` |
| 9 | **P1** | Verify central-boss place's handling of absent `RunModifiers` | `centralboss/ServerScriptService/CentralBossMain.server.lua` |
| 10 | **P2** | Add wall-clock reaper for `pendingSkillHits` / `pendingBasics` | `MobAI.lua:547-706` |
| 11 | **P2** | pcall `template:Clone()` and nil-check return in `SpawnWave` | `MobSpawner.lua:423, 331, 356` |
| 12 | **P2** | Disconnect-on-knockdown / reconnect-on-revive for `HealthChanged` | `DeathSystem.lua:180-202` |
| 13 | **P2** | Verify character identity in post-delay animation callbacks | `DeathSystem.lua:220-226` |
| 14 | **P2** | Currency cap + `AddMerits(_, 0)` early return | `CurrencyManager.lua:73-94` |
| 15 | **P2** | Document `InventoryManager.ConsumeItem` vs `AddItem` auto-convert asymmetry in module header | `InventoryManager.lua` header |

**P0** = touch before any further play-test; **P1** = before alpha announcement;
**P2** = nice-to-have cleanup.

---

## 8. What I Did **Not** Verify (Scope Notes)

- Per-remote rate-limit coverage (V1 §3.7 already flagged).
- Full Shop UI flow (only server-side module audited).
- DataStore save reliability under disconnect — needs dedicated check.
- Central Boss gameplay loop — bootstrap audited, combat pacing not.
- Any lobby-specific social/quest code paths beyond PlayerData shape.

---

*Written 2026-04-23 as the V2 pass after the overnight respec-fragment
refactor. Continues V1's reward-for-effort framing.*
