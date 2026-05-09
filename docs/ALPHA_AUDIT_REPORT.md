# Alpha Code Audit Report

> Full codebase audit of 225 Lua files across 5 game modes. March 2026.

---

## Executive Summary

The codebase is architecturally sound with good modular design, clean React UI patterns, and thoughtful systems. However, there are **production-blocking issues** that must be fixed before alpha release: memory leaks in core combat loops, race conditions in player initialization, duplicate code that will cause maintenance nightmares, and several dead/placeholder systems that should be removed or completed.

**Verdict: NOT READY for alpha without fixing Critical and High issues below.**

---

## Issues by Severity

### CRITICAL — Must fix before any player testing

#### C1. Memory leaks in MobAI & SkillEffects
**Files:** `MobAI.lua`, `SkillEffects.lua`
- `pendingSkillHits` and `pendingBasicAttacks` in MobAI auto-clean after 5s via `task.delay`, but if delay fails or server lags, entries accumulate. Over a 10-minute horde run this will degrade performance.
- `mobBaseSpeeds` in SkillEffects captures base speed per mob but never cleans up dead mobs. `activeMobEffects` cleanup doesn't touch `mobBaseSpeeds`.
- **Fix:** Add explicit cleanup when mobs die (in `UnregisterMob`). Periodic sweep for stale entries.

#### C2. NetworkManager rate bucket leak
**File:** `NetworkManager.lua`
- `rateBuckets` grows unbounded. Cleanup on `PlayerRemoving` only clears known events, but new events created at runtime persist. Long-running servers accumulate dead entries.
- **Fix:** Add periodic timestamp-based bucket purge or use weak tables.

#### C3. GameStateManager task leak
**File:** `GameStateManager.lua`
- `StartCountdown()` spawns a `task.spawn()` thread. If state changes before countdown completes, the thread continues running silently and fires events on a stale state.
- **Fix:** Track the countdown thread and cancel it on state transitions.

#### C4. CharacterManager connection leaks
**File:** `CharacterManager.lua`
- Multiple `task.delay()` calls to disconnect connections (15s timeouts) but no cleanup if player leaves before delay fires. Connections persist as zombies.
- **Fix:** Register all connections per-player and clean up on `PlayerRemoving`.

#### C5. ShopManager non-atomic purchases
**File:** `ShopManager.lua`
- Currency is deducted (line 158) BEFORE the cosmetic is granted (line 168). If granting fails, merits are lost.
- **Fix:** Wrap in a transaction: deduct only after grant succeeds, or use a two-phase approach.

#### C6. TalentManager respec token loss
**File:** `TalentManager.lua`
- Respec token is deducted BEFORE the respec executes. If respec fails or player disconnects mid-operation, token is gone but points aren't refunded.
- **Fix:** Deduct token as the last step, after respec is confirmed complete.

#### C7. DefenseLine.LateInit() never called
**File:** `DefenseLine/init.lua`
- `LateInit()` is defined but never called. This means `MobAI` reference stays nil at first-frame `Update()` calls. Mobs reaching the defense line won't be unregistered properly.
- **Fix:** Call `LateInit()` from the game mode bootstrap after all modules are loaded.

#### C8. MobSpawner race conditions
**File:** `MobSpawner.lua`
- `spawnPoint` is lazily resolved. If the first mob spawns before `workspace.MobSpawn` exists, nil reference crash.
- `preSpawnHook` has no timeout — if it never resolves, `SpawnWave` hangs forever.
- **Fix:** Validate spawnPoint at Init time. Add timeout to preSpawnHook.

---

### HIGH — Should fix before alpha, will cause visible bugs

#### H1. AttackHandler double PlayerAdded connection
**File:** `AttackHandler/init.lua`
- `PlayerAdded` event registered twice (lines 85 and 92). Combat config is sent to client twice on join.
- **Fix:** Remove one of the two registrations.

#### H2. ArmorManager & WeaponManager duplicate player initialization
**Files:** `ArmorManager/init.lua`, `WeaponManager/init.lua`
- Both have `PlayerAdded` hook AND a manual loop over existing players, both calling `task.spawn`. Race condition between the two paths.
- **Fix:** Use a single initialization path with deduplication guard.

#### H3. AchievementManager recursive evaluation risk
**File:** `AchievementManager.lua`
- `Unlock` → `AddMerits` → `OnMeritsAdded` → `Evaluate` → `Unlock` again. Guard prevents re-unlock but deep recursion can stack overflow with many achievements.
- **Fix:** Queue unlocks instead of recursive evaluation.

#### H4. KillRewardManager stale difficulty cache
**File:** `KillRewardManager.lua`
- `cachedDiffTier` is set once and never refreshed. If difficulty changes mid-session, rewards are wrong.
- **Fix:** Refresh cache on difficulty change events.

#### H5. DropManager lazy-load caching bug
**File:** `DropManager.lua`
- When `getDiffMults()` fails, result is cached as `false` forever. Even if the config loads later, it's never retried.
- **Fix:** Only cache successful loads.

#### H6. HordeModeMain pause time not excluded
**File:** `HordeModeMain.server.lua`
- `elapsed = os.clock() - hordeStartTime` includes pause time. Vote cadence and run duration are corrupted during pauses.
- **Fix:** Track cumulative pause duration and subtract from elapsed.

#### H7. Countdown loops in UI spawn duplicates
**Files:** `HUD.lua`, `DeathUI.lua`, `VoteUI.lua`
- Timer loops spawned in `useEffect` without proper ref guards. If the effect re-runs, multiple concurrent loops fire `setState` simultaneously.
- **Fix:** Track loop task in a ref and cancel before spawning a new one.

#### H8. Geometric crit stacking extreme burst
**File:** `StatsManager/CriticalSystem.lua`
- At 200% crit chance with 1.80× multiplier, damage can hit `1.80^3 = 5.83×`. No post-crit damage ceiling.
- **Recommendation:** This is a balance concern — decide if this is intentional. If not, add a damage cap or reduce multi-crit scaling.

#### H9. Vulnerability has no cap
**File:** `StatsManager/DamageSystem.lua`
- Vulnerability multiplier applied with no maximum. Combined with crits, damage spikes can be extreme.
- **Recommendation:** Add a cap (e.g., max 2.0× vulnerability).

---

### MEDIUM — Should fix before beta, causes maintenance pain

#### M1. Massive code duplication: WeaponManager mirrors ArmorManager
**Files:** `WeaponRefinement.lua` ↔ `ArmorRefinement.lua`, `WeaponTierSystem.lua` ↔ `ArmorTierSystem.lua`, `WeaponXPSystem.lua` ↔ `ArmorXPSystem.lua`
- Three pairs of files are near-identical copies. Any bug fix must be applied twice.
- **Recommendation:** Extract shared `EquipmentRefinement`, `EquipmentTierSystem`, `EquipmentXPSystem` base modules.

#### M2. Game mode bootstrap duplication
**Files:** `LaneDefenseMain.server.lua`, `HordeModeMain.server.lua`, `CentralBossMain.server.lua`
- Vitals broadcast loop, module loading pattern, VoteManager wiring, and HP regen logic are copy-pasted across all three.
- Same for client bootstraps: `LaneDefenseClient.client.lua`, `HordeModeClient.client.lua`, `CentralBossClient.client.lua` all share identical `Load()` functions.
- **Recommendation:** Extract to `SharedGameBootstrap` server/client modules.

#### M3. EmoteWheel duplicated
**Files:** `lobby/.../EmoteWheel.lua`, `socialplaza/.../EmoteWheel.lua`
- Exact same file in two places. Bug fixes require patching both.
- **Recommendation:** Move to shared UI components.

#### M4. SharedEventHandlers does too many things
**File:** `SharedEventHandlers.lua`
- Handles 5 distinct event types (GetPlayerInfo, AllocateStat, RespecStats, ModifySystemStat, SaveKeybindings) in one file.
- **Recommendation:** Split into one handler file per event group.

#### M5. CharacterManager too large
**File:** `CharacterManager.lua` (612 lines)
- Handles template application, head mesh, armor, accessories, skin color, and watcher setup.
- **Recommendation:** Split into `CharacterTemplate` and `CharacterAppearance` modules.

#### M6. MobAI is a god module
**File:** `MobAI.lua` (939 lines)
- Handles state machine, AI decisions, attack execution, skill resolution, effect application, networking, damage calculation, and client authentication.
- **Recommendation:** Split into `MobStateMachine`, `MobCombat`, `MobNetworking`.

#### M7. CardRegistry too large
**File:** `CardRegistry.lua` (619 lines)
- 27 card definitions inline with scattered magic numbers.
- **Recommendation:** Split by card lane (Supply, Greed, Control, Relief, Tactical).

#### M8. QuestHandler O(n²) per kill
**File:** `NPCManager/QuestHandler.lua`
- `IncrementObjective` iterates ALL quests from ALL NPCs on every mob kill.
- **Recommendation:** Build an index by objective type at init time.

---

### LOW — Quality of life, fix when convenient

#### L1. AnimationConfig uses identical placeholder IDs
**File:** `AnimationConfig.lua`
- Aegis, Arcanist, and Hunter all share `rbxassetid://128777973` for basicAttack. Obviously unfinished.

#### L2. SoundManager all placeholder IDs
**File:** `SoundManager.lua`
- Every sound in `SOUND_LIBRARY` is `rbxassetid://0`. No audio will play.

#### L3. DailyLoginManager diagnostic prints left in
**File:** `DailyLoginManager.lua`
- Lines 172-183 print full diagnostic state on every claim. Comment says "remove once streak issue is resolved."

#### L4. KillRewardManager disabled weapon/armor XP
**File:** `KillRewardManager.lua`
- Weapon XP (lines 302-313) and Armor XP (lines 315-328) are commented out. Either complete or remove.

#### L5. LeaderboardManager side-effect in getter
**File:** `LeaderboardManager.lua`
- `getScores()` mutates player data as a side effect (persists PowerLevel). Getters should not write.

#### L6. `GetAccountData(player, "Level")` signature error
**Files:** `LaneDefenseMain.server.lua`, `HordeModeMain.server.lua`, `CentralBossMain.server.lua`
- Passes a second argument that the API doesn't accept. Currently appears to work by accident.

#### L7. TeleportManager orphaned functions
**File:** `TeleportManager.lua`
- `GetRecommendedDifficulty()` and `GetMaxDifficulty()` defined but never called.

#### L8. Shallow copy bug in WaveConfig
**File:** `WaveConfig.lua`
- Template copy only copies first level. Nested tables (spawnWeights, guaranteed) share references with the original. Mutating per-wave data corrupts the template.

#### L9. ArcanistWeapons comment/code mismatch
**File:** `ArcanistWeapons.lua`
- ArcaneFocus refinement bonus comment says +3.5 but code says +4.

#### L10. HunterBehavior dead config
**File:** `HunterBehavior.lua`
- `CostPerHit = 0` defined but never used in `OnHitDealt()`.

---

## Incomplete / Placeholder Systems

These exist in code but are not functional:

| System | Status | Notes |
|---|---|---|
| AuctionManager | Config only, no runtime | `AuctionConfig.lua` is complete but no manager exists |
| Arena mode | Config only | `GameModeConfig.lua` has `available = false` |
| Raid mode | Config only | Same |
| Exploration mode | Config only | Same |
| Premium Shop | Stub | `ShopManager.PurchasePremium` always returns false |
| Weapon/Armor XP on kill | Disabled | Commented out in KillRewardManager |
| Custom animations | Placeholder | 3/4 classes share same animation ID |
| Sound effects | Placeholder | All IDs are `rbxassetid://0` |
| SocialPlaza event handlers | Empty | `onPlayerAdded()` and `onPlayerRemoving()` are no-ops |

---

## Files That Need Splitting (Modularity)

| File | Current Lines | Recommended Split |
|---|---|---|
| MobAI.lua | 939 | MobStateMachine, MobCombat, MobNetworking |
| CharacterManager.lua | 612 | CharacterTemplate, CharacterAppearance |
| CardRegistry.lua | 619 | CardSupply, CardThreat, CardTactical |
| AchievementManager.lua | 474 | AchievementStatTracker, AchievementUnlockHandler |
| ResourceManager.lua | 452 | ResourceRegen, ClassBehaviorLoader |
| HitTracker.lua | 450 | (borderline, okay to keep) |
| MonitoringSystem.lua | 440 | (borderline, okay to keep) |

---

## Questions for You (Need Your Decision)

These are issues where I'm not sure of your intent:

1. **Geometric multi-crit (H8):** At 200% crit + 1.80× multiplier, damage can spike to 5.83×. Is this intentional burst design or should there be a cap?

2. **Vulnerability stacking (H9):** No cap on the vulnerability multiplier. Should there be a maximum (e.g., 2.0×)?

3. **HealingSystem uses Damage stat (File: HealingSystem.lua):** Healing power is calculated from the `"Damage"` stat, not a dedicated healing stat. Is this intentional (damage = magic power for healers)?

4. **BountyBoard card value:** `ApplyTimedModifier("meritScalar", 1.0, 30)` — the value 1.0 is additive, making total 2.0× (doubling). Is "2× merits for 30s" the intended behavior?

5. **ArmorReduction can zero out armor:** If ArmorReduction ≥ 100%, mob armor becomes 0. Should there be a minimum armor floor?

6. **Disabled weapon/armor XP (L4):** Comment says "scaling consequences not yet validated." Should this be completed for alpha or remain disabled?

7. **LifeSteward Genesis minimum resource (70 vs 80):** All other ultimate skills require min 80 resource but Genesis requires only 70. Intentional lower threshold for the healer?

8. **Wave 13+ untested procedural path:** WaveConfig has static definitions for waves 1-12, then procedural generation for 13+. Is the game intended to go beyond wave 12?

---

## Balance Numbers Update

Added 13 new sections to `docs/BALANCE_NUMBERS.md` (sections 34-46) covering daily login rewards, kill rewards, XP sharing, drop scaling, party system, leaderboards, networking limits, gear rating weights, run modifiers, horde mode timing, matchmaking, combo system, hit tracker, and HP regen.

---

*Audit performed on full codebase: 225 Lua files across src/shared, src/lobby, src/lanedefense, src/hordemode, src/centralboss, src/socialplaza.*
