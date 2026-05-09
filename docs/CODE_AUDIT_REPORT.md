# Code Audit Report - Roblox Defense

**Date:** March 31, 2026
**Scope:** Full codebase audit with focus on recent changes, dead code, duplicate functions, module splitting remnants, and redirection functions.

---

## Critical Issues

### 1. KillRewardManager Never Loaded in Any Place Bootstrap

**Files:** LaneDefenseMain.server.lua, CentralBossMain.server.lua, HordeModeMain.server.lua
**Impact:** Kill rewards (XP, merits from mob kills) are completely non-functional.

All three combat place bootstraps reference `loaded["KillRewardManager"]` for weapon XP wiring, but none of them actually call `Load(SharedModules, "KillRewardManager")`. The module exists but is never initialized.

**Fix:** Add `Load(SharedModules, "KillRewardManager")` before the wiring section in all three place bootstrap scripts.

---

### 2. BonusManager vs PlayerBonusSystem Race Condition

**Files:** PlayerBonusSystem.lua, BonusManager.lua
**Impact:** Buff/talent bonuses can be silently deleted when weapon stats refresh.

`BonusManager` was built to prevent different bonus sources (weapons, buffs, talents) from clobbering each other by tracking per-source bonus tables. However, `PlayerBonusSystem.ApplyWeaponBonuses()` bypasses BonusManager entirely and writes directly to `data.Bonus`, zeroing out all stats before re-adding weapon bonuses. If a buff or talent modifier is active on the same stat at that moment, it gets silently deleted.

Additionally, `PlayerBonusSystem.GetBonus()`, `SetBonus()`, and `ModifyBonus()` never consult BonusManager — they always do raw reads/writes to `data.Bonus`.

**Fix:** Route all bonus writes through `BonusManager.SetSourceBonuses()` to prevent race conditions. Have PlayerBonusSystem delegate to BonusManager rather than writing directly.

---

### 3. Duplicate XP Logic: WeaponXPSystem vs EquipmentXPSystem

**Files:** WeaponXPSystem.lua, EquipmentXPSystem.lua
**Impact:** Two separate XP systems with different feature sets for the same concept.

`WeaponXPSystem` is a standalone 271-line implementation with class-role awareness (DPS/Tank/Healer/Support), role-gated XP grants, and specialized methods. `EquipmentXPSystem` is a generic factory with no role awareness. Both implement identical level-up loops and network event firing. ArmorXPSystem uses the factory; WeaponXPSystem does not.

**Fix:** Decide on one approach — either enhance the EquipmentXPSystem factory to support roles, or deprecate it and use dedicated systems for each equipment type.

---

### 4. ArmorManager Data Not in PlayerDataConfig Template

**Files:** PlayerDataConfig.lua, ArmorManager/init.lua
**Impact:** Data template is misleading and could cause issues with data migration or defaults.

ArmorManager stores armor in `classData.EquippedArmor` and `classData.OwnedArmors`, but PlayerDataConfig.ClassDataTemplate does not include these keys. It does include a vestigial `ArmorId = nil` field that nothing reads or writes.

**Fix:** Add `EquippedArmor` and `OwnedArmors` to ClassDataTemplate. Remove unused `ArmorId`.

---

## Medium Issues

### 5. Duplicate Kill Hook Logic (AttackHandler + DamageHandler)

**Files:** AttackHandler/init.lua (lines 39-48), DamageHandler.lua (lines 23-33)

Both modules implement identical `OnMobKilled()` functions with the same KillRewardManager wait-loop pattern. Callers can't tell which is the canonical entry point.

**Fix:** Remove one and route all callers through the other.

---

### 6. SkillExecutor.Execute() Is a Pure Redirect

**File:** SkillManager/SkillExecutor.lua (lines 83-85)

```lua
function SkillExecutor.Execute(player, skill, inputData)
    return SkillRegistry.ExecuteSkill(player, skill, inputData)
end
```

This adds no validation, logging, or transformation — it just forwards the call.

**Fix:** Have callers invoke `SkillRegistry.ExecuteSkill()` directly, or add actual logic to this wrapper.

---

### 7. Identical Skill Getter Functions Across All 4 Class Modules

**Files:** AegisSkills.lua, HunterSkills.lua, ArcanistSkills.lua, LifeStewardSkills.lua

Each class module implements identical copies of `GetSkillBySlot()`, `GetSkillById()`, `GetAllSkills()`, and `GetSkillCount()`.

**Fix:** Extract into a shared base helper or factory function in BaseSkills.lua.

---

### 8. TeleportDataReader.ApplyDifficulty() Is an Empty Stub

**File:** TeleportDataReader.lua (lines 100-101)

Function is defined but completely empty, and never called anywhere in the codebase.

**Fix:** Remove it or implement actual difficulty-application logic.

---

### 9. Dual XP Bonus Tracking Systems

**Files:** BonusExpSystem.lua, WeaponXPSystem.lua, PlayerLevelSystem.lua

Player-level XP uses `BonusExpSystem.GetMultiplier()` (party/event/premium multipliers), while weapon XP uses `PlayerDataManager.GetBonus("XPBonus")` (flat percent bonus from data.Bonus). Two different bonus paths for the same concept.

**Fix:** Consolidate into a single XP bonus system.

---

### 10. HordeMode Config Overlap

**Files:** GameModeConfig.lua (lines 89-99), HordeModeSpawner.lua (lines 48-53)

HordeMode difficulty multipliers are defined in both GameModeConfig and hardcoded in HordeModeSpawner, with divergent values.

**Fix:** Remove hardcoded multipliers from HordeModeSpawner and read from GameModeConfig.

---

### 11. HordeMode MobSpawner Ghost Events

**File:** HordeModeMain.server.lua

HordeMode sets `suppressWaveStart = true` and uses HordeModeSpawner for all spawning, but MobSpawner callbacks (OnWaveStarted, OnWaveCompleted) are still registered and may fire spurious events.

**Fix:** Add guards to MobSpawner callbacks to check if they should fire in HordeMode.

---

### 12. Three Competing Sources of Truth for Projectile Config

**Files:** ClassConfig.lua, ProjectileConfig.lua, ClassWeapon files

Class projectile settings are fragmented across three locations with no clear hierarchy for which is authoritative.

**Fix:** Consolidate into a single ProjectileRegistry or document the precedence order.

---

### 13. MatchmakingManager Re-requires TeleportManager at Runtime

**File:** MatchmakingManager.lua (line 351)

TeleportManager is re-required inside `LaunchMatch()` even though it was already loaded during LobbyMain bootstrap. Should be passed as a dependency.

**Fix:** Accept TeleportManager as a dependency during Init() and use the cached reference.

---

## Low Issues

### 14. Unused Imports in SkillManager

**File:** SkillManager/init.lua — `AttackShapes` and `BonusManager` are lazy-loaded but never referenced.

### 15. Speed Restoration Logic in SkillEffects

**File:** SkillEffects.lua (lines 427-455) — Scans active effects twice and doesn't handle stacking slows correctly. Multiple slows should apply the strongest, not the first found.

### 16. Buff Effect Mapping Duplication

**File:** SkillManager/init.lua — `ApplyBuffEffect()` and `RemoveBuffEffect()` manually map buff types to stat names. New buff types must be added to both functions.

### 17. Redundant SetAutoAdvance Call

**File:** GameStateManager.lua (line 79) — `MobSpawner.SetAutoAdvance(true)` is redundant since MobSpawner already defaults to true.

### 18. NetworkManager PRE_REGISTER Bloat

**File:** NetworkManager.lua (lines 69-153) — 150+ events pre-registered on all places, including DefenseLine events in SocialPlaza where they're irrelevant.

### 19. Hardcoded Place IDs

**File:** Shared/init.lua (lines 68-74) — Place IDs hardcoded with no update mechanism or environment fallback.

### 20. TeleportHandler Falls Through to LoreHandler

**File:** NPCManager/TeleportHandler.lua — A Teleport NPC with no destinations but with dialogue is silently treated as Lore. This behavior is undocumented and re-requires LoreHandler at runtime.

---

## Clean Areas (No Issues Found)

- **UI Layer:** Very clean. All components properly mounted, no orphaned references to deleted modules (KeybindManager, PartyPanel, CharacterCreationUI). Thin wrappers for multi-place structure (LaneDefenseApp, CentralBossApp, HordeModeApp redirecting to CombatApp) are legitimate and well-documented.
- **EmoteWheel Pattern:** Lobby and SocialPlaza versions correctly redirect to the shared implementation.
- **NPC System:** Excellent separation of concerns with NPCManager routing to type-specific handlers.
- **Party System:** Solid implementation with auto-disband, leadership transfer, and level-gap validation.
- **Matchmaking Flow:** Clear state machine with Queue > Countdown > Launch flow.
- **Scene Management:** Proper separation between server-side SceneManager and client-side SceneController.
- **Tombstone files:** Already deleted (confirmed removed from working tree).
- **Project.json files:** All checked paths exist and are correctly referenced.

---

## Priority Action Items

1. **CRITICAL:** Load KillRewardManager in all combat place bootstraps
2. **CRITICAL:** Fix BonusManager/PlayerBonusSystem race condition
3. **CRITICAL:** Resolve XP system duplication and decide on canonical approach
4. **CRITICAL:** Update PlayerDataConfig template for armor data
5. **MEDIUM:** Remove duplicate OnMobKilled hook (pick one entry point)
6. **MEDIUM:** Remove or implement SkillExecutor.Execute redirect
7. **MEDIUM:** Extract shared skill getters to BaseSkills
8. **MEDIUM:** Consolidate XP bonus systems
9. **MEDIUM:** Unify HordeMode config source
10. **LOW:** Clean up unused imports, redundant calls, and add missing validation
