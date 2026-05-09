# RobloxDefense — Revision Tracker

> **Created:** March 2026 · **Updated:** March 2026 (post-card/vote system)
> **Status key:** 🟠 High · 🔵 Stub/Future · ⚪ Design decision

---

## Table of Contents

1. [High Priority Fixes](#1-high-priority-fixes)
2. [Known Stubs & Future Work](#2-known-stubs--future-work)
3. [Open Design Decisions](#3-open-design-decisions)
4. [Dead Config & Orphaned Events](#4-dead-config--orphaned-events)
5. [Cosmetic System Gaps](#5-cosmetic-system-gaps)
6. [Pre-Production Checklist](#6-pre-production-checklist)
7. [Completed Items](#7-completed-items)

---

## 1. High Priority Fixes

> §1 Critical Bugs (1.1–1.4) and High Priority items 2.1–2.5, 2.8 are all **verified fixed** — see §7 for details.

### 1.1 🟠 Network Events Missing From PRE_REGISTER List

All events are created inside module `Init()` functions (which run before any client spawns). The 8-event bootstrap pre-register list covers only critical early events. Remaining events are safe because the server is fully initialized before `ServerReady` fires, but a proper audit of client `WaitForChild` calls vs. server-side timing has not been done.

**Fix:** Audit all `NetworkManager.GetEvent()` calls and confirm no client-side race. Add any at-risk events to the bootstrap block.

### 1.2 🟠 Dual Shop Purchase Codepaths

`ShopManager` and `NPCManager/ShopHandler` both implement independent purchase logic. `ShopHandler` lacks level restriction, stack limit, and class restriction checks that `ShopManager` enforces. Item delivery (`InventoryManager.AddItem`) is now wired.

**Fix:** Route all NPC shop purchases through `ShopManager.Purchase()`. `ShopHandler.HandlePurchase()` should delegate rather than re-implementing validation.

---

## 2. Known Stubs & Future Work

Intentional placeholders. Must be resolved before content launch.

### 2.1 🔵 All Attack Animations Are Placeholders

All four classes share the same `basicAttack` animation ID (`rbxassetid://128777973` — R6 Wave).

**Fix:** Author per-class attack animations; update `AnimationConfig.Player.Classes`.

### 2.2 🔵 Headgear "model" Visual Type Is Stub

`ApplyHeadgearVisual()` has no implementation for `visual.type == "model"`. Reserved for future accessory models.

### 2.3 🔵 gen_manifests_lua.py Doesn't Quote Dotted Keys

`tools/gen_manifests_lua.py` does not quote texture slot keys containing `.`. Invalid Lua syntax.

**Fix:** Add key guard: `if key:match("[^%w_]") then key = '["'..key..'"]' end`.

### 2.4 🔵 CharacterManager.ApplyTemplate() Visual Swap Stub

TODO — needs to swap the rig model when gendered/class-specific rigs are available.

### 2.5 🔵 TeammateVitals Uses Stat HP (Not Current HP)

`VitalsUpdate` loop uses `GetTotalHealth()` (stat-based max) for both `hp` and `maxHp`. Real current HP needs `DamageSystem` integration.

### 2.6 🔵 Ultimate Skills Are Unlocked in Testing

`ultimateLocked = false` in all four `ClassSkills/*.lua` files. Must be set to `true` before production; unlock logic to be wired into a mission system.

### 2.7 🔵 Quest & Lore Progress Not Persisted

Quest progress and lore flags (`TalkedTo_*`) are stored in player `Attributes` (lost on rejoin). Need migration to `PlayerDataManager`.

### 2.8 🔵 AllocateStat Allows Free Deallocation

`SharedEventHandlers.lua` — negative `points` value triggers `DeallocateStat` with no respec cost. Proper respec-token check needed.

### 2.9 🔵 HitTracker.SaveLifetimeStats Is a Stub

Prints stats but does not persist them to DataStore.

### 2.10 🔵 Projectile Animations Dead Write

`AnimationConfig.RegisterProjectileAnimations()` exists but no getter reads them. Either remove or add `GetProjectileAnim()`.

### 2.11 🔵 Rogue ScreenGuis

`WardrobeUI`, `EmoteWheel`, and `BattleClassUI` create their own `ScreenGui` instead of rendering into the App root. Inconsistent with the React architecture.

### 2.12 🔵 All Sound Assets Are Placeholders

`SoundManager` — all sound `rbxassetid://0` (silent). Replace with real audio assets.

### 2.13 🔵 Premium Shop Tab Is a Stub

Needs `MarketplaceService` / `DevProduct` integration.

### 2.14 🔵 Class Mastery & Chapter Progression UI

No client-side UI exists yet for viewing class mastery milestones, chapter progression, role seals, or ascension crests. Backend data is persisted but not surfaced to the player.

### 2.15 🔵 Tutorial / Onboarding System

No tutorial or guided onboarding flow exists. First-time players are dropped into the lobby with no guidance.

### 2.16 🔵 Infinite / Endless Horde Mode

Design consideration for a post-cap endless mode. Constraints: only unlock at hard caps (50/100/150 etc.), disable XP/merit gains after normal run duration, scale mob HP/damage exponentially to naturally cap survival time, leaderboard reward only.

---

## 3. Open Design Decisions

Require an explicit choice before they can be closed.

| # | Item | Location | Decision Needed |
|---|------|----------|-----------------|
| 1 | MatchmakingManager countdown cancel TOCTOU race | `MatchmakingManager` | Add retry or inform player on failed teleport |
| 2 | ClassSwitchCooldown = 1s | `PlayerDataConfig.lua` | Set production value (30–300s) |
| 3 | SkillEffects DoT bypasses DamageHandler | `SkillEffects.lua` | DoT deals damage without armor/resist/kill tracking. Intentional? |
| 4 | Slow stacking captures already-modified speed | `SkillEffects.lua` | Second slow stacks from already-reduced speed. Needs snapshot-on-first? |
| 5 | ResourceManager Heartbeat loop runs in Lobby | `LobbyMain.server.lua` | Ticking ClassBehaviors for no gameplay reason. Gate on game place |
| 6 | No PlayerRemoving save in Lobby bootstrap | `LobbyMain.server.lua` | Player data may not save on Lobby disconnect |
| 7 | Player instance as dictionary key | `PartyManager`, `SceneManager` | Reference may outlive session; use `player.UserId` |
| 8 | CritChance cap at 200% | `PlayerDataConfig` | Allows up to ~2.5 average crit procs. Monitor in playtesting |
| 9 | `tick()` used in ~15 files | Various | Should be `os.clock()` — low risk but inconsistent |
| 10 | Some `task.delay` callbacks not cancelled on React unmount | Various UI | Memory leak on unmount |
| 11 | Fixed pixel sizes in some UI components | Various UI | Should use `Scale` for resolution independence |
| 12 | Locale only has English | `Locale.lua` | i18n framework exists but unused |

---

## 4. Dead Config & Orphaned Events

Low-priority cleanup — no runtime breakage, just noise.

### Dead Config Tables

| Location | Item | Why Dead |
|---|---|---|
| `Shared/init.lua` | `Scenes` table | Never read by any module |
| `Shared/init.lua` | `GameModes` table | Never read by any module |
| `PlayerBonusSystem` | `BONUS_STAT_MAPPING.rage` | Maps to `"Rage"` which doesn't exist in BonusStats |

### Dead Network Events

| Event | Direction | Problem |
|---|---|---|
| `DebugCommand` | C→S | Server listens; no client sends it |
| `ModifySystemStat` | C→S | Server listens; no client sends it |
| `DailyLoginResult` | S→C | Server fires; no client listener |
| `DailyLoginStatus` | S→C | Server fires; no client listener |
| `LeaderboardData` | S→C | Server fires; no client listener |
| `PlayerGearScore` | S→C | Server fires; no client listener |
| `InventoryUpdate` | S→C | Server fires; no client listener |
| `ClaimDailyLogin` | C→S | Client should fire; never wired |
| `GetDailyLoginStatus` | C→S | Client should fire; never wired |
| `GetInventory` | C→S | Client should fire; never wired |
| `EquipAccessory` | C→S | Client should fire; never wired |
| `UnequipAccessory` | C→S | Client should fire; never wired |
| `GetLeaderboard` | C→S | Client should fire; never wired |

### Dead Module Sections

| Module | Dead Section |
|---|---|
| `QuestHandler.lua` | `AttributeStateProvider` class (lines 122–152) — never used |
| `TalentManager.lua` | `RefundNode` + helpers (`isLeaf`, `bfsReachable`) — individual node refund disabled |
| `AnimationConfig.lua` | `RegisterProjectileAnimations()` — no getter reads the registered data |

---

## 5. Cosmetic System Gaps

See [COSMETICS.md](COSMETICS.md) for full cosmetic architecture.

| # | Gap | Status |
|---|-----|--------|
| 1 | All player classes share the same attack animation ID | Not started |
| 2 | `visual.type == "model"` headgear path is stubbed | Not started |

---

## 6. Pre-Production Checklist

Critical flags and values that **must** be changed before public launch:

| Item | File | Current Value | Production Value |
|------|------|--------------|------------------|
| `ultimateLocked` | All 4 `ClassSkills/*.lua` | `false` | `true` |
| `ClassSwitchCooldown` | `PlayerDataConfig.lua` | `1` second | 30–300 seconds |
| All sound asset IDs | `SoundManager` / `AnimationConfig` | `rbxassetid://0` | Real audio assets |
| All animation asset IDs | `AnimationConfig.lua` | Placeholder `128777973` | Per-class animations |
| Admin allowlist | `PlayerDataConfig.AdminUserIds` | `{}` | Populated with admin IDs |

> **Previously flagged but now resolved:**
> - `REFINEMENT_COST` / `TIER_COST` — now populated with balanced cost tables per BALANCE_REWORK_SPEC §12/§13
> - Ultimate cooldowns — set to 60s ✅
> - `DEBUG_NO_SAVE` — already `false` ✅

---

## 7. Completed Items

### V0 Critical Bug Fixes ✅

All 4 critical bugs (§1.1–1.4) verified fixed: PlaceIds present, `Load()` auto-calls `Init()`, Vulnerability reads attribute and multiplies, `waveState` guards prevent race.

### V0 High Priority Fixes ✅

| Bug | Resolution |
|-----|-----------|
| 2.1 SkillExecutor nil guard | `assert(DamageHandler, ...)` after `AttackHandler.GetSystems().Damage` |
| 2.2 SkillExecutor hardcoded delay | `task.wait(1)` → `Modules:WaitForChild("MobAI", 10)` in `task.spawn` |
| 2.3 Unused StatusEffectTypes | Removed 6 dead definitions |
| 2.4 AttackSpeedDown misplaced | Moved from `Buffs` to `Debuffs` |
| 2.5 FindFirstChild in hot paths | `DamageHandler` `_WeaponManager` cached at module level |
| 2.8 Knockback attachment leak | Creates named attachment; `FindFirstChild` reuses it |

### V0 Stubs Resolved ✅

- **3.1** GI Cosmetic System — entire pipeline removed; future costumes use `.rbxmx` templates
- **3.9** TeleportDataReader.ApplyDifficulty — `MobSpawner.SetDifficulty()` wired in all 3 game bootstraps
- **3.12** Weapon/Armor upgrade costs — now populated (REFINEMENT_COST 300–140000, TIER_COST 10–500, REROLL_COST `floor(300×1.46^(t-1))`)
- **3.13** Shop purchases — `ShopHandler.HandlePurchase()` calls `_InventoryManager.AddItem()`
- **3.17** BonusExpSystem — loaded via `Load()` in all 4 bootstraps

### V0 Design Decisions Resolved ✅

- **#2** Client-auth combat — full rewrite with `PlayerHitReport`/`MobBasicAttackHitReport`, server validation, rate limiting
- **#6** BodyVelocity deprecation — already uses `LinearVelocity` throughout
- **#9** Rate limiting — `NetworkManager` `RATE_LIMIT = 30` per player/event/second
- **#12** Currency on refinement failure — consumed by design (per BALANCE_REWORK_SPEC §13)
- **#13** DefenseLine → TriggerDefeat — `OnDestroyedCallback` wired in LaneDefense bootstrap

### V0 Dead Code Cleanup ✅

~60–70 dead functions removed across ~40 files in 6 batches. Talent point off-by-one fixed (`Level + bonus` → `max(0, Level - 1) + bonus`).

### Post-V0: Client-Auth Combat & Systems Overhaul ✅

| Item | Summary |
|------|---------|
| Client-authoritative combat | `PlayerAttack` local hit → `PlayerHitReport` → server `AttackHandler` validates |
| LifeSteward (4th class) | Healer with Life Energy, 5 skills, full equipment |
| Two-phase DeathSystem | KnockedDown (10s) → Dead, with `DeathUI` overlay |
| Animation centralization | All `:LoadAnimation` via `AnimationSystem/init.lua` |
| SharedGeometry deduplication | Unified `IsPointInShape` for Circle, Cone, Rectangle, Ring |
| Dead code cleanup (Tier 1) | Removed `AttackActivated`/`MobAttack`, stub files |
| Rate limiting | 30 calls/player/event/second |

### Post-V0: Security & QoL Fixes ✅

| Item | Summary |
|------|---------|
| damageMultiplier exploit | Server computes damage; client value ignored |
| Flat 150-stud range cap | Per-class `GetMaxBasicAttackRange()` from weapon config |
| Negative derived stats | `math.max(0, ...)` clamp in `GetTotalStat` |
| WeaponManager stale bonuses | `RefreshWeaponStats()` on weapon switch |
| Resource name mismatch | Aether, Killer Instinct, Life Energy aligned |
| Placeholder skill cooldowns | All 12 skills tuned; ultimates 60s |
| LifeSteward equipment | LifeTotem/ReincarnationTotem + BarkweaveVest/VerdantRegalia |
| Genesis whiff fix | Dual-purpose: revive knocked-down OR full-heal lowest ally |
| SylvanStep → VineSlide | Renamed per design spec |
| Difficulty system | `MobSpawner.SetDifficulty()` wired in all 3 game bootstraps |
| Testing UI: Reset CDs | `SkillManager.ResetAllCooldowns()` + admin button |

### V0 Balance Concerns — RETIRED ✅

All balance concerns (§5.1–5.4 in original tracker) are addressed by the **BALANCE_REWORK_SPEC.md** implementation:
- Hunter Crit → CritChance cap reduced to 200%, CritDamage cap 1.80×
- Multi-Crit exponential → geometric model with 200% cap; max ~2.5 procs average
- Mob Armor scaling → armor exponent 1.05 with division-based formula `100/(100+armor)`
- High-tier reroll cost → `floor(300×1.46^(t-1))` with per-band Temper pity system {10, 18, 28, 36}

### BALANCE_REWORK_SPEC.md — All 7 Phases Complete ✅

Full implementation of the 52-section balance rework spec:

| Phase | Scope |
|-------|-------|
| 1 — Combat Formulas | ArmorSystem (division), DamageSystem (8-step pipeline), CriticalSystem (200%/1.80×), HealingSystem (100%/1.50×), ElementalSystem (1.25/0.85) |
| 2 — Config Values | ClassConfig (4 classes), PlayerDataConfig (stat caps, XP, respec), MobRegistry (exponents), Weapons/Armors, WeaponConfig/ArmorConfig (refinement, tiers), ClassBehaviors (resources), ClassSkills (costs/CDs) |
| 3 — Gear Progression | ChapterConfig (tier/refine caps), chapter-based enforcement in refinement + tier systems, projectile pierce/AoE wiring |
| 4 — Chapter Progression | Level caps, Class Mastery XP conversion, delta-based XP multipliers, mode-aware XP |
| 5 — Reward Pipeline | DropManager (delta/mode multipliers), GameModeConfig (HordeMode overrides, challenge modifiers), DefenseConfig (chapter HP, breach %), ConsumableConfig (percentage-based) |
| 6 — Class Mastery & Tokens | ClassMasteryConfig (9 milestones), MasteryXP/MasteryMilestones data, BoundTokens, ASCENSION_CRESTS |
| 7 — Economy & Config | AuctionConfig (bands, tax, level gate, caps) |

**Not yet implemented (per §52.3):** Auction house runtime, second weapon equip slot UI, 5-player content parity, challenge modifier selection UI, per-player participation qualification.

### Alpha Balance Runtime Audit — All 4 Phases Complete ✅

Implementation of all actionable findings from ALPHA_BALANCE_RUNTIME_AUDIT.md and BALANCE_CODE_AUDIT.md (10 issues across 4 phases):

| Phase | Changes |
|-------|---------|
| 1 — Crash + Stat Pipeline | DefenseHealth `onDamagedCallbacks`/`onHealedCallbacks` declared; armor wired into BonusManager (`armor` source) + PlayerBonusSystem (`ApplyArmorBonuses`) + all ArmorManager child systems (refine/tier/XP/reroll/switch/starter); `BonusHealth` feeds into `GetTotalStat("Health")`; starter weapon `RefreshWeaponStats` on first grant |
| 2 — Combat Trust | Attack ticket system (client-generated IDs, server `pendingAttacks` stores/validates/dedup/maxHits from class config); mob damage server-authoritative spatial validation (client reports advisory) |
| 3 — Dead Stat Activation | `SkillDamage` amplifies skill-sourced action multiplier; `Thorns` reflects % finalDamage back to mob in `DamagePlayer`; `Lifesteal` heals attacker % of damage in `DamageMob`; `TauntDuration` scales Taunt effect duration in `AegisSkills`; `ResourceMax` dynamic getter in ResourceManager (all clamping/notify respects bonus) |
| 4 — XP Fix + Cleanup | Party XP uses each recipient's own level for delta calculation; innate class bonuses applied via `OnPlayerDataReady` callback (replaces scattered game-mode calls); `RefundTalent` stale event removed from TalentManager |

**Deferred:** ChallengeBonus runtime caller (needs challenge modifier selection UI — tracked in FEATURE_TODO §3.6).

### Post-Alpha: Card & Event Vote System ✅

Full implementation of the shared card/vote modifier system across Horde Mode and Lane Defense:

| Item | Summary |
|------|---------|
| CardRegistry | 30 card definitions across 3 pools (hordeSupply, hordeThreat, laneTactical) |
| RunModifiers | Per-run modifier scalars (HP/damage/armor/speed, spawn rate, merit, danger bonus, miniboss charge); `Reset()` on lobby return |
| VoteManager | Server-side vote lifecycle: draw 3 cards → 6s timer → tally → apply effect |
| VoteUI | React client overlay for 3-card selection during votes |
| IronWall card stat key | Fixed `"FlatArmor"` → `"Armor"` in CardRegistry |
| HordeModeSpawner wiring | RunModifiers (spawnIntervalScalar, normalMobCountScalar, hpScalar, damageScalar, armorFlatBonus, speedScalar, ConsumeMinibossCharge) applied at spawn time |
| MobSpawner (Lane) wiring | Same RunModifiers integration + `SetPreSpawnHook()` API for vote gating |
| Lane wave vote gate | Pre-spawn hook polls `VoteManager.IsVoteActive()` to block wave start until vote resolves |
| Danger bonus → XP | `KillRewardManager.GetXPReward()` multiplied by `(1 + dangerBonus)` |
| Danger bonus → wave XP | `LaneDefenseMain` wave completion XP multiplied by `(1 + dangerBonus)` |
| BountyBoard true 2× merits | Moved meritScalar into `DropManager.GrantDrop()`; removed flat bonus from KillRewardManager |
| armorFlatBonus in MobRegistry | `GetScaledMob()` adds `armorFlatBonus` from RunModifiers to base mob armor |
| RunModifiers.Reset leak fix | `Reset()` called in `OnReturnToLobby` for both HordeModeMain and LaneDefenseMain |
| Horde run duration | 630s (10:30) fixed timer → stop spawner → mob clear → `TriggerVictory()` |
| GameStateManager.TriggerVictory | New API: transitions DEFENDING → VICTORY (mirrors TriggerDefeat) |

### Post-Alpha: Animation & Emote Wiring Fix ✅

| Item | Summary |
|------|---------|
| ClassConfig animation bypass | Replaced local `ANIM` table with `getAnim()` that reads from `AnimationConfig.Player.Classes` |
| EmoteConfig creation | New `ReplicatedStorage/Shared/EmoteConfig.lua` — canonical emote definitions shared by server and client |
| AnimationConfig emote delegation | `AnimationConfig.Emotes` now dynamically loaded from EmoteConfig at init time |
| EmoteWheel deduplication | Both lobby and socialplaza `EmoteWheel.lua` now read from `EmoteConfig.Emotes` instead of hardcoded arrays |
