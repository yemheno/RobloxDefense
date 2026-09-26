# RobloxDefense — Complete Game Documentation

> **Updated:** June 2025 · **Post Balance Rework (BALANCE_REWORK_SPEC.md — all 7 phases complete)**
> **Engine:** Roblox Studio (Luau)  
> **Toolchain:** Rojo 7.6.1 · Wally 0.3.2 · React-lua 17.0.2
>
> Companion documents: [COSMETICS.md](COSMETICS.md) · [REVISION_TRACKER.md](REVISION_TRACKER.md) · [BALANCE_NUMBERS.md](BALANCE_NUMBERS.md) · [FEATURE_TODO.md](FEATURE_TODO.md)

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Toolchain & Build Pipeline](#2-toolchain--build-pipeline)
3. [Architecture & Design Philosophy](#3-architecture--design-philosophy)
4. [Five-Place Architecture](#4-five-place-architecture)
5. [Bootstrap & Initialization](#5-bootstrap--initialization)
6. [Shared Constants & Enums](#6-shared-constants--enums)
7. [Network Layer](#7-network-layer)
8. [Player Data & Persistence](#8-player-data--persistence)
9. [Class System](#9-class-system)
10. [Stat System](#10-stat-system)
11. [Bonus & Aggregation System](#11-bonus--aggregation-system)
12. [Currency & Economy](#12-currency--economy)
13. [Weapon System](#13-weapon-system)
14. [Armor System](#14-armor-system)
15. [Combat Pipeline](#15-combat-pipeline)
16. [Skill System](#16-skill-system)
17. [Class Skills Reference](#17-class-skills-reference)
18. [Status Effects & Buffs](#18-status-effects--buffs)
19. [Elemental System](#19-elemental-system)
20. [Mob System](#20-mob-system)
21. [Wave & Defense Line](#21-wave--defense-line)
22. [Game State Machine](#22-game-state-machine)
23. [Kill Rewards & Drops](#23-kill-rewards--drops)
24. [Talent Tree](#24-talent-tree)
25. [Achievement System](#25-achievement-system)
26. [NPC System](#26-npc-system)
27. [Quest System](#27-quest-system)
28. [Shop & Inventory](#28-shop--inventory)
29. [Daily Login Rewards](#29-daily-login-rewards)
30. [Cosmetic & Visual System](#30-cosmetic--visual-system)
31. [Leaderboard System](#31-leaderboard-system)
32. [Party & Matchmaking](#32-party--matchmaking)
33. [Teleport System](#33-teleport-system)
34. [Client Systems](#34-client-systems)
35. [UI Components (React)](#35-ui-components-react)
36. [Sound System](#36-sound-system)
37. [Resource System](#37-resource-system)
38. [Difficulty System](#38-difficulty-system)
39. [Card & Event Vote System](#39-card--event-vote-system)
40. [Chapter System](#40-chapter-system)
40. [Chapter System](#40-chapter-system)
41. [Class Mastery System](#41-class-mastery-system)
42. [Auction & Economy Config](#42-auction--economy-config)
43. [Monitoring & Anti-Exploit](#43-monitoring--anti-exploit)
44. [XP & Leveling Formulas](#44-xp--leveling-formulas)
45. [Balance Numbers Reference](#45-balance-numbers-reference)
46. [Cross-System Data Flow](#46-cross-system-data-flow)
47. [File Tree Reference](#47-file-tree-reference)
48. [Debug Flags & Testing](#48-debug-flags--testing)

---

## 1. Project Overview

**RobloxDefense** is a cooperative lane-defense RPG built on Roblox (Luau). Players pick from four classes, allocate stats, equip weapons/armor, and defend against waves of mobs advancing down a lane. The game features deep character progression through talent trees, equipment upgrading (tiers, refinements, random bonuses), quests, achievements, cosmetics, and a party system.

### Core Gameplay Loop

1. **Lobby** — Create/customize character, browse NPCs (shops, quests, lore, forge), form parties, queue for matches.
2. **Teleport** — Party teleports from Lobby to a game mode place with match data (difficulty, party composition).
3. **LaneDefense** — Waves of mobs march down a lane toward a defense line. Players attack with basic attacks and skills. Mobs that reach the defense line deal damage based on their remaining stats. Survive all waves to win.
4. **CentralBoss** — Party fights a single boss in an arena. No lane or defense line. Players face a "BossPoint" in the center.
5. **HordeMode** — Waves of mobs attack from all directions in a top-down arcade view. Players face mouse/joystick. No defense line.
6. **SocialPlaza** — Non-combat social hub for cosmetics, emotes, wardrobe, and avatar preview. No enemies.
7. **Rewards** — XP (player + weapon + armor), currency (Merits + Essence), loot drops, quest/achievement progress.
8. **Return** — Teleport back to lobby for upgrades, respecs, shops, and the next run.

### Four Classes

| Class | Role | Attack Type | Resource | Theme |
|-------|------|-------------|----------|-------|
| **Aegis** | Tank | Melee Cone | Determination | Shield-and-sword frontliner; taunts, DR, party protection |
| **Arcanist** | Mage | Ranged AoE | Mana (Aether) | Area damage, crowd control, elemental nuking |
| **Hunter** | DPS | Ranged Pierce | Focus (Killer Instinct) | High crit, fast attacks, single-target burst |
| **LifeSteward** | Healer | Ranged Pierce | Life Energy | Ally healing, cleansing, revival support |

---

## 2. Toolchain & Build Pipeline

| Tool | Version | Purpose |
|------|---------|---------|
| **Rojo** | 7.6.1 | File-system → Roblox Studio sync. `*.project.json` maps local folders to Roblox service trees. |
| **Wally** | 0.3.2 | Package manager for Luau. Installs React + dependencies into `Packages/`. |
| **React (jsdotlua)** | 17.0.2 | Declarative UI framework used for all game interfaces. |
| **ReactRoblox** | 17.0.2 | React renderer for Roblox Instance tree (ScreenGui creation). |
| **Foreman** | — | Tool version manager (`foreman.toml` pins Rojo + Wally versions). |

### Build Commands

```bash
# Install Rojo + Wally
foreman install

# Install Luau packages (React etc.)
wally install

# Sync to Studio (pick one)
rojo serve lanedefense.project.json   # LaneDefense place
rojo serve lobby.project.json          # Lobby place
```

### Project Files

- `lanedefense.project.json` — Maps `src/lanedefense/` + `src/shared/` into the LaneDefense place.
- `lobby.project.json` — Maps `src/lobby/` + `src/shared/` into the Lobby place.
- Both projects include `Packages/` → `ReplicatedStorage.Packages`.

---

## 3. Architecture & Design Philosophy

### 10 Core Rules

1. **Modularity** — Every system is a ModuleScript returning a table of functions. No global state; all communication through explicit APIs.

2. **Init() Pattern** — Every module exposes `Init()` called manually by the bootstrap script in a deterministic order. This prevents race conditions from Roblox's non-deterministic `require()` order.

3. **Lazy Loading** — Circular dependencies are broken by lazy-requiring inside functions rather than at module scope. Common pattern: `local OtherModule; ... function M.SomeFunc() if not OtherModule then OtherModule = require(...) end ... end`.

4. **LateInit()** — For modules that depend on systems loaded later in the boot sequence. Called after all `Init()` calls complete. Used by `GameStateManager` (needs `MobSpawner`) and `DefenseLine` (needs `GameStateManager`).

5. **Shared Folder** — `src/shared/` contains code used by both places. Place-specific code goes in `src/lobby/` or `src/lanedefense/`.

6. **Place-Specific Folders** — Server modules under `src/{place}/ServerScriptService/Modules/`, client modules under `src/{place}/StarterPlayer/StarterPlayerScripts/`.

7. **React UI** — All user interfaces are built with React-lua. Each place has a root `App.lua` that composes all panels. Shared UI components live in `src/shared/StarterPlayer/StarterPlayerScripts/UI/`.

8. **Sub-Module Folders with init.lua** — Complex systems (PlayerDataManager, WeaponManager, SkillManager, etc.) use a folder with `init.lua` as the public API and child scripts as subsystems.

9. **No Hardcoded Place Logic** — Shared modules never check `game.PlaceId`. Place-specific behavior is achieved by what the bootstrap script loads and wires.

10. **Network Event Pre-Creation** — `NetworkManager.Init()` pre-creates ~60 RemoteEvents on the server so clients' `WaitForChild` never times out.

### Dependency Injection Patterns

| Pattern | Used By | Purpose |
|---------|---------|---------|
| `Init()` | ~90% of modules | Deterministic initialization |
| `LateInit()` | GameStateManager, DefenseLine | Post-all-init wiring |
| `Register(deps)` | SharedEventHandlers | DI without module-level requires |
| `InjectDataManager()` | BonusManager | Break `BonusManager ↔ PlayerDataManager ↔ PlayerBonusSystem` cycle |
| Lazy `require` via closure | CurrencyManager, ClassManager, TalentManager | On-demand loading |
| Parent back-reference | PlayerDataManager child systems | Parent sets a reference on the child at load time |

---

## 4. Five-Place Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         LOBBY PLACE                              │
│  PlaceId: 115774137563700                                        │
│  ServerScriptService/                                            │
│    LobbyMain.server.lua  ← bootstrap                            │
│    Modules/                                                      │
│      PartyManager, MatchmakingManager, SceneManager,             │
│      TeleportManager, LobbyNPCRegistry                           │
│  + ALL shared modules (data, economy, classes, equipment, NPC,   │
│    talents, achievements, cosmetics, inventory, shop)             │
│  - NO combat modules (no AttackHandler, MobAI, DefenseLine etc.) │
│                                                                  │
│  Client:                                                         │
│    LobbyClient.client.lua → LobbyApp.lua (React root)           │
│    + SceneController, NPCInteraction                             │
│    - NO PlayerAttack, SkillInput, DamageNumbers                  │
└──────────────────────────────────────────────────────────────────┘
                    ↓ TeleportService (with party/difficulty data)
┌──────────────────────────────────────────────────────────────────┐
│                      LANE DEFENSE PLACE                          │
│  PlaceId: 138768963731267                                        │
│  ServerScriptService/                                            │
│    LaneDefenseMain.server.lua  ← bootstrap                      │
│    Modules/                                                      │
│      TeleportDataReader, ReturnTeleporter                        │
│  + ALL shared modules (data, economy, classes, equipment,        │
│    combat, mobs, waves, defense line, NPC, talents, etc.)        │
│  • Card/Vote cadence: Tactical vote per wave start               │
│  • 12-wave run; RunModifiers applied per-run; reset on lobby     │
│                                                                  │
│  Client:                                                         │
│    LaneDefenseClient.client.lua → LaneDefenseApp.lua (React)    │
│    Camera: FixedIsometric (offset -12, 8, 0; lookAhead 20)      │
│    Movement: NoJump + FaceDirection (face right)                 │
│    + PlayerAttack, SkillInput, SkillVisuals, DamageNumbers       │
│    + VoteUI (tactical card selection overlay per wave)            │
└──────────────────────────────────────────────────────────────────┘
                    ↓ TeleportService (return to lobby)
┌──────────────────────────────────────────────────────────────────┐
│                      CENTRAL BOSS PLACE                          │
│  PlaceId: 100848838772974                                        │
│  ServerScriptService/                                            │
│    CentralBossMain.server.lua  ← bootstrap                      │
│  + ALL shared modules + full combat (same as LaneDefense)        │
│  - NO DefenseLine (no lane to defend)                            │
│  • "BossPoint" Part in Workspace for camera/facing targets       │
│                                                                  │
│  Client:                                                         │
│    CentralBossClient.client.lua → CentralBossApp.lua (React)    │
│    Camera: FixedBossView (offset -12, 8, 0; faces BossPoint)    │
│    Movement: NoJump + FacePoint (face BossPoint)                 │
│    + PlayerAttack, SkillInput, SkillVisuals, DamageNumbers       │
└──────────────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────────┐
│                       HORDE MODE PLACE                           │
│  PlaceId: 115735968204052                                        │
│  ServerScriptService/                                            │
│    HordeModeMain.server.lua  ← bootstrap                        │
│    Modules/                                                      │
│      HordeModeSpawner, HordePauseManager                         │
│  + ALL shared modules + full combat (same as CentralBoss)        │
│  - NO DefenseLine (no lane to defend)                            │
│  • TopDown camera, FaceMouse (PC) / JoystickAim (mobile)         │
│  • MobAI uses SetHordeModeTargeting(true) for 360° mob attacks   │
│  • Card/Vote cadence: one vote per 45s, alternating (7+7)        │
│  • Fixed run duration: 630s (10:30) → spawner stops → mob clear  │
│    → TriggerVictory → auto-return to lobby                       │
│  • RunModifiers applied per-run (HP/damage/armor/speed scalars,  │
│    spawn rate, danger bonus); reset on return to lobby            │
│                                                                  │
│  Client:                                                         │
│    HordeModeClient.client.lua → HordeModeApp.lua (React)        │
│    Camera: TopDown (arcade top-down view)                        │
│    Movement: NoJump + FaceMouse/JoystickAim                      │
│    + PlayerAttack, SkillInput, SkillVisuals, DamageNumbers       │
│    + VoteUI (supply/threat card selection overlay)                │
└──────────────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────────┐
│                      SOCIAL PLAZA PLACE                          │
│  PlaceId: 103512111921765                                        │
│  ServerScriptService/                                            │
│    SocialPlazaMain.server.lua  ← bootstrap                      │
│  + Shared core (data, character, network, currency)              │
│  + Cosmetic & animation systems only                             │
│  - NO combat, NO enemy AI, NO wave/defense systems               │
│                                                                  │
│  Client:                                                         │
│    SocialPlazaClient.client.lua → SocialPlazaApp.lua (React)    │
│    + EmoteWheel, AppearanceBar                                   │
│    - NO PlayerAttack, SkillInput, DamageNumbers                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 5. Bootstrap & Initialization

### LaneDefense Server Init Order (~50 steps)

```
 1. NetworkManager.Init()           — pre-creates ~60 RemoteEvents
 2. PlayerDataConfig (loaded)       — schema/constants only
 3. ClassConfig (loaded)
 4. CharacterConfig (loaded)
 5. WeaponConfig (loaded)
 6. ArmorConfig (loaded)
 7. AnimationConfig (loaded)
 8. ProjectileConfig (loaded)
 9. GameModeConfig.Init()
10. StatusEffectTypes (loaded)
11. CosmeticConfig (loaded)
12. WeaponRegistry.Init()           — auto-loads ClassWeapons/*
13. ArmorRegistry.Init()            — auto-loads ClassArmors/*
14. MobSkillRegistry.Init()         — auto-loads MobSkills/*
15. MobRegistry.Init()              — auto-loads Mobs/*
16. PlayerDataManager.Init()        — DataStore setup, child systems
17. BonusManager.Init()             — source-based bonus aggregation
18. BonusManager.InjectDataManager()
19. CurrencyManager (loaded)
20. ClassManager.Init()             — class switching orchestrator
21. StatsManager.Init()             — combined stat queries (via PDM)
22. ResourceManager.Init()          — per-class resource tick loop
23. AttackHandler.Init()            — basic attack pipeline
24. SkillRegistry.Init()            — auto-loads ClassSkills/*
25. SkillManager.Init()             — skill validation/execution
26. HitTracker.Init()               — combo + hit stats
27. KillRewardManager.Init()        — XP/loot on kill
28. DropManager.Init()              — loot rolling
29. EquipmentHandler.Init()         — equipment info requests
30. DefenseLine.Init()              — defense health/combo/detection
31. MobSpawner.Init()               — wave spawning
32. MobAI.Init()                    — mob state machines
33. GameStateManager.Init()         — game lifecycle FSM
34. GameStateManager.LateInit()     — wires MobSpawner
35. DefenseLine.LateInit()          — wires GameStateManager + MobAI
36. NPCManager.Init()               — NPC system (minimal in LaneDefense)
37. TalentManager.Init()            — talent allocation
38. TalentEffectAggregator.Init()
39. AchievementManager.Init()       — achievement hooks
40. CosmeticManager.Init()          — visual cosmetics
41. VisualEquipmentManager.Init()   — weapon model attachment
42. MonitoringSystem.Init()         — passive monitoring
43. InventoryManager.Init()         — accessory system
44. DailyLoginManager.Init()
45. ShopManager.Init()
46. LeaderboardManager.Init()
47. SharedEventHandlers.Register()  — common C→S event handlers
48. TeleportDataReader.Init()       — reads arriving player data
49. ReturnTeleporter.Init()         — return-to-lobby teleport
50. Wire state/wave/defense callbacks, start vitals loop
```

### Lobby Server Init Order (~37 steps)

Same shared module init minus combat systems (no AttackHandler, MobAI, MobSpawner, DefenseLine, GameStateManager combat wiring). Adds:

```
33. SceneManager.Init()             — per-player scene tracking
34. PartyManager.Init()             — party CRUD
35. MatchmakingManager.Init()       — queue/countdown/launch
36. TeleportManager.Init()          — lobby→defense teleport
37. NPCManager.Init({ npcs = LobbyNPCRegistry, SceneManager, MatchmakingManager })
```

### Client Init (LaneDefense)

```
1. NetworkManager.Init()
2. ResourceCache.Init()
3. AnimationSystem.Init()
4. CosmeticClient.Init()
5. AchievementClient.Init()
6. InputSystem.Init() → context "Combat"
7. CameraSystem.Init() → mode "FixedIsometric"
8. MovementSystem.Init() → enable "NoJump" + "FaceDirection"
9. PlayerAttack.Init()
10. SkillInput.Init()
11. SkillVisuals.Init()
12. MobVisuals.Init()
13. DamageNumbers.Init()
14. LootNotification.Init()
15. TalentClient.Init()
16. Locale.Init()
17. SoundManager.Init()
18. Mount React root (LaneDefenseApp)
```

### Client Init (Lobby)

```
1-6. Same shared client modules (NetworkManager through InputSystem)
7. SceneController.Init()
8. NPCInteraction.Init()
9. Mount React root (LobbyApp)
```

---

## 6. Shared Constants & Enums

`ReplicatedStorage.Shared.init.lua` exports:

| Constant | Values |
|----------|--------|
| `GameStates` | `IDLE`, `PREPARING`, `DEFENDING`, `VICTORY`, `DEFEAT` |
| `Scenes` | `VILLAGE`, `DEFENSE`, `BOSS`, `HORDE`, `PLAZA` |
| `ClassNames` | `Aegis`, `Arcanist`, `Hunter`, `LifeSteward` |
| `PrimaryStats` | `MIG`, `VIT`, `PRE`, `MAG`, `RSV` |
| `CurrencyTypes` | `ESSENCE`, `MERITS` |
| `GameModes` | `DEFENSE`, `CENTRAL_BOSS`, `HORDE_MODE`, `ARENA` (future), `RAID` (future), `EXPLORATION` (future) |
| `PlaceIds` | `Lobby` (115774137563700), `LaneDefense` (138768963731267), `CentralBoss` (100848838772974), `HordeMode` (115735968204052), `SocialPlaza` (103512111921765) |

---

## 7. Network Layer

### Server NetworkManager

Central RemoteEvent factory under `ReplicatedStorage.Events`.

| API | Description |
|-----|-------------|
| `Init()` | Creates Events folder, pre-registers ~90 events |
| `GetEvent(name)` | Get/create and cache RemoteEvent |
| `FireClient(player, name, ...)` | Fire to one client |
| `FireAllClients(name, ...)` | Fire to all clients |
| `OnClientEvent(name, callback)` | Listen for client→server events |

### Client NetworkManager

| API | Description |
|-----|-------------|
| `Init()` | Locates `Events` folder |
| `GetEvent(name)` | WaitForChild (3s timeout) + cache |
| `FireServer(name, ...)` | Fire to server |
| `OnServerEvent(name, callback)` | Listen for server→client events; returns connection |

### Network Event Reference

**Server → Client (S→C):**

| Event | Payload | Sent By |
|-------|---------|---------|
| `ServerReady` | `{}` | Bootstrap |
| `PlayerInfoUpdate` | `{level, class, xp, xpRequired, merits, essence, resource, maxResource}` | SharedEventHandlers |
| `StatsUpdate` | `{level, unallocated, allocated:{}, derived:{}}` | SharedEventHandlers |
| `CurrencyUpdate` | `{essence, merits}` | CurrencyManager |
| `ResourceUpdate` | `{current, max, percent, name, className}` | ResourceManager |
| `VitalsUpdate` | `{[userId]: {name, hp, maxHp, class, level}}` | LaneDefenseMain |
| `GameStateChanged` | `{state}` | GameStateManager |
| `CountdownUpdate` | `{seconds}` | GameStateManager |
| `CombatConfig` | `{isRanged, attackSpeed, animationId, projectile?, attackShape?, shapeParams?}` | AttackHandler |
| `AttackFired` | `{character, animationId, attackSpeed, isRanged, lookDirection, projectileConfig?}` | AttackHandler |
| `DamageNumber` | `{position, damage, wasCrit, critProcs, attackerUserId, attackElement, isDoT}` | DamageHandler |
| `MobDeath` | `{mobId, position, exp, tier}` | KillRewardManager |
| `LootDrop` | `{[{type, amount}]}` | DropManager |
| `MobBasicAttackCast` | `{attackCastId, mob, targetPlayer, animationId, damageDelay, attackRange}` | MobAI |
| `MobSkillCast` | `{skillCastId, mobId, skillId, position, ...}` | MobAI |
| `MobSkillHit` | `{skillCastId, targetUserId}` | MobAI |
| `DefenseLineUpdate` | `{health, maxHealth, percent}` | DefenseHealth |
| `DefenseLineDamaged` | `{damage, health, maxHealth, source, mobId}` | DefenseHealth |
| `DefenseLineCombo` | `{comboLevel, hitCount, multiplier}` | DefenseCombo |
| `ComboUpdate` | `{combo, bestCombo, damage}` | HitTracker |
| `ComboEnded` | `{finalCombo, damage}` | HitTracker |
| `SkillCooldownUpdate` | `{skillId, cooldown}` | SkillManager |
| `SkillActivated` | `{skillId, slot}` | SkillManager |
| `SkillFailed` | `{reason}` | SkillManager |
| `SkillCastStarted` | `{skillId, castTime}` | SkillManager |
| `SkillCastCompleted` | `{skillId}` | SkillManager |
| `SkillBuffApplied` | `{buffId, stat, duration}` | SkillManager |
| `SkillBuffRemoved` | `{buffId}` | SkillManager |
| `SkillVisual` | `{type, ...data}` | BaseSkills |
| `WeaponEquipped` | `{weaponId, name, attack}` | WeaponManager |
| `WeaponLevelUp` | `{weaponId, level}` | WeaponXPSystem |
| `WeaponXPGained` | `{xp, level, progress}` | WeaponXPSystem |
| `WeaponRefinementResult` | `{success, refinement, message}` | WeaponRefinement |
| `WeaponTierUp` | `{tier, bonusSlots, atkBonus}` | WeaponTierSystem |
| `WeaponRerollResult` | `{oldBonuses, newBonuses}` | WeaponBonusSystem |
| `ArmorEquipped` | (mirrors weapon) | ArmorManager |
| `TalentStateUpdate` | `{allocatedNodes, pointsSpent, pointsTotal, pointsAvailable}` | TalentManager |
| `AchievementUnlocked` | `{id, tier, rewards}` | AchievementManager |
| `AchievementsData` | `{stats, unlocked}` | AchievementManager |
| `WardrobeUpdate` | `{wardrobe, equipped}` | CosmeticManager |
| `CosmeticEquipped` | `{cosmeticId, slot}` | CosmeticManager |
| `InventoryUpdate` | `{items, equipped}` | InventoryManager |
| `DailyLoginResult` | `{success, rewards, streak}` | DailyLoginManager |
| `DailyLoginStatus` | `{canClaim, streak, totalDays}` | DailyLoginManager |
| `ShopResult` | `{success, message}` | ShopManager |
| `ShopState` | `{merits, essence, level, owned}` | ShopManager |
| `LeaderboardData` | `{board, entries}` | LeaderboardManager |
| `PlayerGearScore` | `{score}` | LeaderboardManager |
| `NPCDialogue` | `{npcId, npcName, type, dialogue/quests/destinations}` | NPCManager |
| `NPCShopOpen` | `{npcId, npcName, items}` | ShopHandler |
| `NPCQuestOffer` | `{npcId, npcName, quests}` | QuestHandler |
| `NPCTeleportOffer` | `{npcId, npcName, destinations}` | TeleportHandler |
| `NPCSmithOpen` | `{npcId, npcName, smithType, info}` | WeaponSmithHandler |
| `MatchmakingUpdate` | `{status, mode, seconds}` | MatchmakingManager |
| `SceneChanged` | `{scene, features}` | SceneManager |
| `PartyUpdate` | `{party, action}` | PartyManager |
| `PartyInvite` | `{from, partyId}` | PartyManager |
| `PartyError` | `{message}` | PartyManager |
| `PlayerListUpdate` | `{[{userId, name}]}` | PartyManager |
| `PlayerDeath` | `{mobId}` | MobAI |
| `DeathState` | `{state: "KnockedDown" \| "Dead" \| "Alive"}` | DeathSystem |
| `RespecResult` | `{success, message, method}` | SharedEventHandlers |

**Client → Server (C→S):**

| Event | Payload | Handler |
|-------|---------|---------|
| `AttackEvent` | `{lookDirection}` | AttackHandler |
| `PlayerHitReport` | `{target, damageMultiplier?}` | AttackHandler |
| `SkillRequest` | `{skillSlot, moveDirection, lookDirection, targetPosition}` | SkillManager |
| `MobSkillHitReport` | `{skillCastId}` | MobAI |
| `MobBasicAttackHitReport` | `{attackCastId}` | MobAI |
| `RequestRespawn` | `{}` | DeathSystem |
| `GetPlayerInfo` | `{}` | SharedEventHandlers |
| `GetStats` | `{}` | SharedEventHandlers |
| `AllocateStat` | `{statName, points}` | SharedEventHandlers |
| `RespecStats` | `{}` | SharedEventHandlers |
| `ModifySystemStat` | `{statName, value}` | SharedEventHandlers (admin) |
| `GetEquipmentInfo` | `{}` | EquipmentHandler |
| `AllocateTalent` | `{nodeId}` | TalentManager |
| `RespecTalents` | `{}` | TalentManager |
| `GetTalentState` | `{}` | TalentManager |
| `NPCInteract` | `{npcId}` | NPCManager |
| `NPCResponse` | `{npcId, action, ...data}` | NPCManager |
| `RequestStartGame` | `{}` | GameStateManager |
| `RequestNextWave` | `{}` | MobSpawner |
| `RequestReturnToLobby` | `{}` | ReturnTeleporter |
| `RequestClassSwitch` | `{className}` | ClassManager |
| `GetWardrobe` | `{}` | CosmeticManager |
| `EquipCosmetic` | `{cosmeticId}` | CosmeticManager |
| `UnequipCosmetic` | `{slot}` | CosmeticManager |
| `GetInventory` | `{}` | InventoryManager |
| `EquipAccessory` | `{itemId, slot}` | InventoryManager |
| `UnequipAccessory` | `{slot}` | InventoryManager |
| `ClaimDailyLogin` | `{}` | DailyLoginManager |
| `GetDailyLoginStatus` | `{}` | DailyLoginManager |
| `ShopPurchase` | `{tab, itemId, quantity}` | ShopManager |
| `GetShopState` | `{}` | ShopManager |
| `GetLeaderboard` | `{board}` | LeaderboardManager |
| `MatchmakingRequest` | `{action, mode}` | MatchmakingManager |
| `PartyRequest` | `{action, targetUserId?}` | PartyManager |
| `GetPartyState` | `{}` | PartyManager |
| `DebugCommand` | `{command, ...args}` | Bootstrap (admin) |

---

## 8. Player Data & Persistence

### PlayerDataManager

Central data authority with DataStore persistence. Orchestrates 4 child systems.

**Data Schema** (`PlayerDataConfig.AccountDefaults`):

```lua
{
    Account = {
        Merits = 0,
        Essence = 0,
        Level = 1,
        Experience = 0,
        ActiveClass = "Aegis",
        UnlockedClasses = { "Aegis" },
        BonusTalentPoints = 0,
        AllocatedTalents = {},
        TrinketId = nil,
        Ring1Id = nil,
        Ring2Id = nil,
        HighestWaveReached = 0,
        TotalPlayTime = 0,
        CharacterData = {
            isCreated = false,
            gender = "Male",
            preset = 1,
            head = "head_default",
            skins = {},
            equippedSkin = nil,
        },
        Wardrobe = {
            owned = {},     -- { [cosmeticId] = true }
            equipped = { headgear = "none", outfit = nil },
        },
        Achievements = {
            unlocked = {},  -- { [achId] = tierNumber }
            stats = {},     -- per-achievement stat tracking
        },
        Inventory = {},     -- { { itemId, quantity }, ... }
        RespecTokens = 0,
        DailyLogin = {
            lastClaimDate = "",
            streak = 0,
            totalDays = 0,
        },
        Quests = {
            active = {},      -- { [questId] = { objectives = { [objId] = progress } } }
            completed = {},   -- { [questId] = true }
        },
        Leaderboard = {
            EssenceSpent = 0,
            RobuxSpent = 0,
            GearScore = 0,
        },
        Bonus = {},  -- flat bonus stats (populated by BonusManager.Recalculate)
        LastClassSwitch = 0,
        BoundTokens = 0,  -- earned via Class Mastery milestones
    },
    Classes = {
        Aegis = {
            Allocated = { MIG = 0, VIT = 0, PRE = 0, MAG = 0, RSV = 0 },
            ArmorId = nil,
            EquippedWeapon = nil,   -- weapon instance table
            OwnedWeapons = {},      -- { [weaponId] = instance }
            ClassAchievements = {},
            MasteryXP = 0,          -- class mastery experience
            MasteryMilestones = {}, -- { [milestoneName] = true }
        },
        -- Hunter = { ... }, Arcanist = { ... } created on unlock
    },
}
```

**Persistence Mechanisms:**

| Feature | Detail |
|---------|--------|
| DataStore key | `"PlayerData_" .. player.UserId` |
| Save frequency | Auto-save every 300 seconds + `BindToClose` |
| Load retry | Up to 3 attempts with exponential backoff (2s, 4s) |
| Load failure | Player is kicked with error message |
| Deep merge | On load, saved data is merged onto fresh defaults → new fields auto-appear |
| `DEBUG_NO_SAVE` flag | Skips all DataStore ops for local testing |

### Child Systems

| System | File | Purpose |
|--------|------|---------|
| **PlayerLevelSystem** | `PlayerLevelSystem.lua` | XP gain (static + dynamic multipliers), level-up loop, auto-unlock classes |
| **PlayerStatSystem** | `PlayerStatSystem.lua` | Primary stat allocation per-class, derived stat computation, health sync |
| **PlayerClassSystem** | `PlayerClassSystem.lua` | Class unlock, switch (with cooldown), auto-unlock scanning |
| **PlayerBonusSystem** | `PlayerBonusSystem.lua` | Flat bonus management, weapon bonus application, BonusManager bridge |

---

## 9. Class System

### Class Definitions (ClassConfig)

| Property | Aegis | Arcanist | Hunter | LifeSteward |
|----------|-------|----------|--------|-------------|
| Attack Type | Melee | Ranged AoE | Ranged Pierce | Ranged Pierce |
| Shape | Cone (R=10, A=120°) | Circle (radius=8) | Pierce (maxHits=1) | Pierce (maxHits=1) |
| Base Attack Speed | 1.4/s | 1.0/s | 2.2/s | 0.85/s |
| Projectile Speed | — | 40 studs/s | 60 studs/s | 35 studs/s |
| Projectile Lifetime | — | 4s | 3s | 3s |
| Resource | Determination | Mana (Aether) | Focus (Killer Instinct) | Life Energy |

### Innate Bonuses

| Class | Bonus |
|-------|-------|
| Aegis | +10% HealthPercent, +5 DamageReduction |
| Arcanist | +10 BonusDamage, +15% DamagePercent |
| Hunter | +15 CritChance, +0.15 CritDamage, +10 MovementSpeed |
| LifeSteward | +15% HealingPercent, +10% HealthPercent |

### Stat Derivation Coefficients

Each primary stat point contributes to derived stats at class-specific rates:

**Aegis:**
| Primary → Derived | Coefficient |
|--------------------|-------------|
| VIT → Health | 15 |
| MIG → Damage | 3.0 |
| MIG → Armor | 1.0 |
| MIG → Penetration | 0.3 |
| PRE → CritChance | 0.22 |
| PRE → CritDamage | 0.006 |
| RSV → CooldownReduction | 0.5 |
| RSV → StatusResistance | 1.0 |
| RSV → ResourceMax | 2.0 |

**Arcanist:**
| Primary → Derived | Coefficient |
|--------------------|-------------|
| MAG → Damage | 4.0 |
| MAG → Penetration | 0.5 |
| MAG → CritDamage | 0.004 |
| MAG → ResourceMax | 3.0 |
| PRE → CritChance | 0.18 |
| PRE → CastTimeReduction | 0.4 |
| PRE → CritDamage | 0.006 |

**Hunter:**
| Primary → Derived | Coefficient |
|--------------------|-------------|
| MIG → Damage | 1.5 |
| PRE → Damage | 2.0 |
| PRE → CritChance | 0.65 |
| PRE → CritDamage | 0.012 |
| PRE → Penetration | 0.5 |

**LifeSteward:**
| Primary → Derived | Coefficient |
|--------------------|-------------|
| VIT → Health | 12 |
| MAG → Damage | 2.5 |
| MIG → Armor | 0.5 |
| MAG → Penetration | 0.3 |
| PRE → CritChance | 0.3 |
| PRE → CritDamage | 0.006 |
| PRE → CastTimeReduction | 0.3 |
| RSV → CooldownReduction | 0.7 |
| RSV → StatusResistance | 1.0 |
| MAG → ResourceMax | 2.0 |
| RSV → ResourceMax | 2.0 |

### Class Switching

- Managed by `ClassManager.SetClass(player, className)`
- Full side effects: resource reset, weapon/armor auto-equip, visual re-equip, cosmetic swap, innate bonus application
- Cooldown: `ClassSwitchCooldown` (currently 1 second)
- Blocked during combat (`GameStateManager.IsInGame()`)
- All classes unlocked by default (empty `ClassUnlockRequirements`)

---

## 10. Stat System

### Primary Stats

5 allocatable stats, starting at base 5 each:

| Stat | Abbreviation | Primary Role |
|------|-------------|--------------|
| Might | MIG | Physical damage, armor |
| Vitality | VIT | Health |
| Precision | PRE | Crit, attack refinement |
| Magic | MAG | Spell damage, mana |
| Resolve | RSV | Cooldowns, resistance, resource |

**Points per level:** 1 stat point per level.

### Derived Stat Formula

$$\text{DerivedStat} = \left(\text{DerivedBase} + \sum_{p \in \text{Primaries}} (p_{\text{base}} + p_{\text{allocated}}) \times \text{coefficient}_p + \text{FlatBonus}\right) \times \left(1 + \frac{\text{PercentBonus}}{100}\right)$$

### Derived Stat Baselines

| Stat | Base |
|------|------|
| Health | 100 |
| Damage | 10 |
| Armor | 0 |
| Penetration | 0 |
| CritChance | 5% |
| CritDamage | 1.5× |
| CastTimeReduction | 0 |
| CooldownReduction | 0 |
| StatusResistance | 0 |
| ResourceMax | 0 |

### Stat Caps

| Stat | Min | Max |
|------|-----|-----|
| CritChance | 0 | 200% |
| CritDamage | — | 1.80× |
| DamageReduction | 0 | 75% |
| CooldownReduction | 0 | 40% |
| CastTimeReduction | 0 | 40% |
| Lifesteal | 0 | 25% |
| AttackSpeed | 0 | 75% |
| StatusResistance | 0 | 60% |

---

## 11. Bonus & Aggregation System

### BonusManager — Source Isolation

BonusManager prevents different systems from clobbering each other's stat bonuses by isolating them into named sources:

| Source | Written By |
|--------|-----------|
| `weapon` | PlayerBonusSystem (weapon random bonuses) |
| `buff` | SkillManager (active skill buffs) |
| `talent` | TalentEffectAggregator (allocated talent nodes) |
| `achievement` | AchievementManager (unlock rewards) |
| `innate` | ClassManager (class innate bonuses) |
| `acc_trinket` | InventoryManager (equipped trinket) |
| `acc_ring1` | InventoryManager (equipped ring 1) |
| `acc_ring2` | InventoryManager (equipped ring 2) |
| `other` | SharedEventHandlers (admin debug stat modifications) |

### Recalculate Flow

```
Any source changes → BonusManager.Recalculate(player)
    → Sums all sources per stat
    → Writes totals to data.Bonus[statName]
    → PlayerStatSystem reads data.Bonus when computing derived stats
```

### BonusExpSystem

Additive XP multiplier from named sources:

$$\text{Multiplier} = 1.0 + \sum_{s \in \text{sources}} \text{addend}_s$$

Sources: `party` (from PartyManager), `event`, `premium` (future).

---

## 12. Currency & Economy

### Two Currencies

| Currency | Primary Source | Primary Sink |
|----------|---------------|--------------|
| **Merits** | Mob kills, quests, achievements, daily login | Weapon refinement, bonus reroll, shops |
| **Essence** | Miniboss kills (30%, 2–4) and boss kills (75%, 8–20), flat; the Scavenge / Essence Drop vote cards; quests; achievements; daily login | Tier upgrades, respec, paid wipe-revive, shops |

*Updated 2026-09-26 (§AGX/X25, X41, X42):* drops are personal (every eligible party member rolls on every party kill, §AGX/X44). A Lane Normal run gives ≈3.6 Essence from drops plus ≈11.7 from Scavenge if always taken. Fixed prices use one anchor, **1 Essence ≈ 250 Merits** (BALANCE_NUMBERS §33).

### CurrencyManager

| API | Description |
|-----|-------------|
| `AddMerits(player, amount)` | Applies `MeritBonus%` from talents/equipment, notifies clients + subscribers |
| `AddEssence(player, amount)` | Flat add, notifies clients |
| `SpendMerits(player, amount) → bool` | Deducts if affordable |
| `SpendEssence(player, amount) → bool` | Deducts if affordable |
| `OnMeritsAdded(callback)` | Subscribe to merit-earned events |

Merit bonus formula: `finalAmount = floor(amount × (1 + MeritBonus/100) + 0.5)`, minimum 1.

---

## 13. Weapon System

### Architecture

```
WeaponManager/
├── init.lua                 ← public API, equip/switch/stats
├── WeaponXPSystem.lua       ← mob kill XP, level-up
├── WeaponTierSystem.lua     ← tier I–XII upgrade
├── WeaponRefinementSystem.lua  ← +0 to +15 refinement
├── WeaponBonusSystem.lua    ← random stat bonus rolling/reroll
└── WeaponRegistry.lua       ← auto-loads ClassWeapons/*
```

### Weapon Instance

```lua
{
    weaponId = "SwordAndShield",
    level = 1,          -- weapon level (separate from player level)
    xp = 0,
    refinement = 0,     -- +0 to +15
    tier = 1,           -- I to XII
    bonuses = {         -- random stat bonuses
        { stat = "critChance", value = 3.5 },
        { stat = "flatAttack", value = 8.0 },
    },
}
```

### Attack Calculation

$$\text{Attack} = \left(\text{baseAttack} \times (1 + \text{SCALE\%})^{\lfloor \text{level}/10 \rfloor} + \text{refBonus} \times \text{refinement}\right) \times (1 + \text{tierAtkBonus})$$

Where:
- `SCALE%` = 5% per 10-level bracket
- `refBonus` = per-weapon refinement bonus (e.g., +2 ATK/level)
- `tierAtkBonus` = 0% (Tier I) to 60% (Tier XII)

### Weapon Level Cap

$$\text{maxWeaponLevel} = \max(1, \lfloor \text{accountLevel} / 10 \rfloor \times 10)$$

### Weapon XP

$$\text{XPRequired}(L) = \text{round}(80 + 8 \times L^2)$$

XP from kills: `baseXP × mobTypeMult × levelDiffScaling × (1 + XPBonus/100)`. Mob must be within ±10 levels.

### Tier System (I–XII)

*Updated 2026-09-26 (§AGX/X25): aligned to `GearUpgradeConfig.lua`. "Cost" and "Min Refine" are what it takes to reach this tier from the one before.*

| Tier | Bonus Slots | ATK Bonus | Value Mult | Pool Unlocks | Cost (Essence) | Min Refine |
|------|-------------|-----------|------------|--------------|----------------|------------|
| I | 2 | 0% | 1.0× | 3 | — | — |
| II | 2 | 5% | 1.1× | 4 | 10 | +1 |
| III | 3 | 10% | 1.2× | 5 | 15 | +3 |
| IV | 3 | 15% | 1.3× | 6 | 25 | +4 |
| V | 3 | 20% | 1.4× | 7 | 40 | +6 |
| VI | 4 | 25% | 1.5× | 8 | 60 | +7 |
| VII | 4 | 30% | 1.6× | 9 | 90 | +8 |
| VIII | 4 | 35% | 1.7× | 10 | 130 | +9 |
| IX | 5 | 40% | 1.8× | 11 | 180 | +10 |
| X | 5 | 45% | 1.9× | 12 | 250 | +11 |
| XI | 5 | 50% | 2.0× | 13 | 350 | +12 |
| XII | 5 | 60% | 2.2× | all | 500 | +13 |
| **Total** | | | | | **1,650** | |

> **On tier up:** Refinement resets to +0 and temper resets to 0. Tier caps are enforced by `ChapterConfig`.

### Refinement System (+0 to +15)

| Property | Value |
|----------|-------|
| Max refinement | +15 |
| Ceilings (safe points) | +0, +3, +6, +9, +12 |
| Downgrade on fail | By step inside the band: a fail at the ceiling or one above it loses nothing; a fail two above the ceiling (e.g. at +11) drops 1 level, never below the ceiling |
| Success rates | +0/+1/+2 → 100%, +3 → 90%, +4 → 80%, +5 → 70%, +6 → 60%, +7 → 50%, +8 → 40%, +9 → 30%, +10 → 22%, +11 → 20%, +12 → 18%, +13 → 14%, +14 → 10% |
| Currency | Merits (300 → 50,000 per attempt; see BALANCE_NUMBERS §10) |
| Chapter cap | Attempts at or above the chapter's max (+8 / +11 / +13 / +15) are refused |
| Refinement resets on tier up | Yes — refinement and temper reset to 0 on tier upgrade |

*Updated 2026-09-26 (§AGX/X23, X43):* success rates and pity now match the code. The +11 → +15 attempts were softened (were 15/10/6/3% at 40k/60k/90k/140k), cutting the Chapter 4 ladder per piece from ≈3.96M to ≈2.06M Merits; +0 → +11 is unchanged.

**Temper Pity System** (the code is canonical, `EquipmentRefinement.lua:156-192`):

- Each failed attempt adds temper by its **step inside the band**: +1 at the ceiling, +2 one above, +3 two above.
- On the failed attempt that brings temper to the band's threshold, the item **jumps straight to the next ceiling** (floor + 3). There is no "next attempt guaranteed" state.
- The jump is clamped to the chapter cap (§AGX/X9). When the clamp cuts it short, the item lands on the cap and **keeps** its temper for the next chapter.
- Temper resets to 0 when a normal success lands on a ceiling, when an unclamped pity fires, and on tier upgrade.

| Refinement Band | Temper Threshold |
|-----------------|------------------|
| +3 → +6 | 10 |
| +6 → +9 | 18 |
| +9 → +12 | 28 |
| +12 → +15 | 18 (was 36) |

### Random Bonuses

Each weapon has a `bonusPool` of ~12–14 stats ordered by priority. Tier unlocks determine how many pool entries are available. Bonus slots (2–5 based on tier) are filled with unique random stats from the available pool.

**Reroll cost:** `floor(300 × 1.46^(tier-1))` Merits. Replaces all bonuses.

### Weapon Definitions

| Class | Weapon | Base ATK | Speed | Shape | Unlock |
|-------|--------|----------|-------|-------|--------|
| Aegis | Sword & Shield | 14 | 1.4 | Cone (8, 120°) | Starter |
| Aegis | Tower Shield | 12 | 1.2 | Rectangle (10×12) | — |
| Arcanist | Apprentice Wand | 15 | 1.0 | Circle (6) | Starter |
| Arcanist | Arcane Focus | 26 | 0.9 | Circle (10) | classLevel 15 |
| Hunter | Short Bow | 10 | 2.2 | Pierce (1 hit) | Starter |
| Hunter | Hunting Bow | 22 | 1.8 | Pierce (3 hits, -15%/hit) | classLevel 15 |
| LifeSteward | Life Totem | 9 | 0.85 | Pierce (1 hit) | Starter |
| LifeSteward | Reincarnation Totem | 18 | 0.75 | Pierce (1 hit) | classLevel 15 |

---

## 14. Armor System

Mirrors the weapon system (same tier/refinement/bonus/temper structures):

### Architecture

```
ArmorManager/
├── init.lua
├── ArmorXPSystem.lua
├── ArmorTierSystem.lua
├── ArmorRefinementSystem.lua
├── ArmorBonusSystem.lua
└── ArmorRegistry.lua       ← auto-loads ClassArmors/*
```

### Defense Calculation

$$\text{Defense} = \left(\text{baseDef} \times (1 + \text{SCALE\%})^{\lfloor \text{level}/10 \rfloor} + \text{refBonus} \times \text{refinement}\right) \times (1 + \text{tierDefBonus})$$

### Armor Definitions

| Class | Armor | Base DEF | Base HP | Unlock |
|-------|-------|----------|---------|--------|
| Aegis | Plate Armor | 12 | 50 | Starter |
| Aegis | Fortress Armor | 18 | 80 | — |
| Arcanist | Silk Robe | 6 | 30 | Starter |
| Arcanist | Arcane Vestment | 9 | 45 | — |
| Hunter | Leather Armor | 8 | 35 | Starter |
| Hunter | Shadow Cloak | 5 | 25 | — |
| LifeSteward | Barkweave Vest | 7 | 40 | Starter |
| LifeSteward | Verdant Regalia | 10 | 55 | — |

---

## 15. Combat Pipeline

### Client-Authoritative Architecture

Basic attacks use a **client-authoritative** model: the attacking player's client plays animations instantly, detects hits locally, and reports verified hits to the server for damage application. This eliminates server round-trip latency for attack feedback.

### Outgoing Damage (Player → Mob)

```
Server: On spawn / class switch
    → AttackHandler.SendCombatConfig(player)
      → Fires "CombatConfig" to client: { isRanged, attackSpeed, animationId,
          projectile?, attackShape?, shapeParams? }

Client: Attack input (LMB)
    → PlayerAttack: instant attack animation via AnimationSystem.Play
    → FireServer("AttackEvent", { lookDirection })
    → Local hit detection:
        Melee → SharedGeometry.IsInShape(targetPos, origin, shape, params)
                for each mob in range → FireServer("PlayerHitReport", { target })
        Ranged → ClientProjectile.Fire(origin, direction, config)
                 → Heartbeat update loop → SharedGeometry.IsInCircle hit check
                 → On hit: FireServer("PlayerHitReport", { target, damageMultiplier })

Server: AttackHandler receives events
    → "AttackEvent" → Cooldown check → broadcasts "AttackFired" to other clients
                       (for visual replication: animation + projectile)
    → "PlayerHitReport" → Validates: mob alive, in range, rate-limited
                          → DamageHandler.DamageMob(mob, player, options)

DamageHandler.DamageMob(mob, player, options):
    1. Guard: humanoid.Health <= 0 → skip (double-kill protection)
    2. StatsManager.CalculateDamage(player):
        a. baseDamage = GetTotalStat("Damage")
        b. weaponAtk = WeaponManager.GetWeaponAttack(player)
        c. rawDamage = baseDamage + weaponAtk
        d. Action multiplier (from skill): rawDamage *= actionMultiplier
        e. Percent bonus: rawDamage *= (1 + DamagePercent/100)
        f. Armor (division): effectiveArmor = max(0, mobArmor - playerPen)
           damage = rawDamage * (100 / (100 + effectiveArmor))
        g. Critical roll → CritChance% → multi-crit geometric model:
           Guaranteed procs = floor(CritChance/100), overflow = CritChance%100
           Each proc: damage *= CritDamage. CritDamage capped at 1.80×.
           CritChance capped at 200% (max ~2.5 avg procs).
        h. Elemental multiplier: 1.25× (strong) / 0.85× (weak) / 1.0× (neutral)
        i. Vulnerability multiplier (from debuffs)
        j. damage = floor(damage)
    3. Apply damage to mob humanoid
    4. Send DamageNumber to clients
    5. Track in HitTracker (combo + stats)
    6. If kill → HandleMobDeath → KillRewardManager.ProcessKill
```

### Incoming Damage (Mob → Player)

Mob basic attacks also use a client-auth model:

```
Server: MobAI detects player in attack range
    → Fires "MobBasicAttackCast" to all clients:
      { attackCastId, mob, targetPlayer, animationId, damageDelay, attackRange }

Client (targeted player): MobVisuals.OnMobBasicAttackCast
    → Plays attack animation on mob via AnimationSystem
    → After damageDelay: checks if still in attackRange
      → If hit: FireServer("MobBasicAttackHitReport", { attackCastId })

Server: MobAI.HandleBasicAttackHitReport
    → Validates: attackCastId matches active cast, player was target
    → MobAI.DamagePlayer(player, baseDamage, mobData):
        1. StatsManager.CalculateDamageTaken(player, baseDamage):
            a. armor = GetTotalStat("Armor") for player
            b. damage = baseDamage * (100 / (100 + armor))
            c. DR = GetBonus("DamageReduction")
            d. damage *= (1 - DR/100)
        2. Apply to player Humanoid.Health
        3. Record in HitTracker
        4. Check death → DeathSystem.OnPlayerDied
```

Mob **skill** attacks remain server-authoritative (server broadcasts cast, clients report hits via `MobSkillHitReport`, server resolves damage).

### Death System (Two-Phase)

```
Trigger: Player HP reaches 0
    → DeathSystem.OnPlayerDied(player)

Phase 1 — Knocked Down (10 seconds):
    → Fires "DeathState" { state = "KnockedDown" } to client
    → Client shows red overlay, movement slowed (WalkSpeed = 4)
    → Skills/attacks disabled, resource drains −10/s
    → Can be revived by LifeSteward's Genesis skill

Phase 2 — Dead (after 10s if not revived):
    → Fires "DeathState" { state = "Dead" } to client
    → Client shows grayscale overlay + respawn button
    → On "RequestRespawn": restores HP, teleports to spawn, fires "Alive"
```

**Party-wipe revive** (*updated 2026-09-26, §AGX/X25; behaviour from §AGX/X40*): when everyone is down, the run pauses for a 15 s window. Each run has **free** wipe-revives by difficulty (**Normal 3, Hard 2, Nightmare 1**), then **one paid** revive (25 Essence, shown only to players who can afford it). Revived players get 3 s of invulnerability. With nothing left to offer, the run ends at once.

### Projectile Hit Types

| Type | Behavior |
|------|----------|
| **Single** | Destroys on first hit |
| **Pierce** | Passes through up to `maxHits` targets; damage reduces by `damageReduction` per hit (min 20%) |
| **AoE** | Explodes on first contact; primary target gets `primaryMultiplier`, others get 1.0×; uses configured shape |

---

## 16. Skill System

### Architecture

```
SkillManager/
├── init.lua         ← validation, cooldowns, buffs, cast-time, execution routing
└── SkillExecutor.lua ← bridge to class skill modules

SkillRegistry.lua    ← auto-discovers ClassSkills/* modules
SkillEffects.lua     ← status effects, DoTs, CC on mobs + buffs on players

ClassSkills/
├── BaseSkills.lua       ← shared utilities (DamageMob, GetTargets, Dash, visuals)
├── AegisSkills.lua      ← 5 Aegis skills
├── ArcanistSkills.lua   ← 5 Arcanist skills
├── HunterSkills.lua     ← 5 Hunter skills
└── LifeStewardSkills.lua ← 5 LifeSteward skills (healing, cleanse, revive)
```

### Skill Execution Flow

```
Client: SkillInput → "SkillRequest" (slot, moveDir, lookDir, targetPos)

Server: SkillManager.TryUseSkill(player, skillSlot, inputData)
    1. Resolve slot → skill ID via SkillRegistry
    2. Check: not casting
    3. Check: cooldown not active
    4. Check: sufficient resource
    5. Check: can act (not stunned)
    6. Deduct resource
    7. Start cooldown
    8. If skill.castTime > 0:
        → StartCasting: lock movement/skills/attacks, WalkSpeed=0
        → After castTime: CompleteCasting → SkillExecutor.Execute
    9. Else: immediate SkillExecutor.Execute
        → SkillRegistry routes to ClassModule.Execute(player, skill, inputData)
```

### Cast-Time Lock System

When a skill has `castTime > 0`:
- Sets player attributes: `IsCasting`, `CastingLockSkills`, `CastingLockAttack`
- Sets `WalkSpeed = 0`
- After cast completes: clears all attributes, restores WalkSpeed
- Can be interrupted: resource refunded, cooldown reset

### Buff Management

SkillManager tracks active buffs with expiry times. Each buff maps to a stat:

| Buff Type | Stat | Applied Via |
|-----------|------|-------------|
| DamageReduction | DamageReduction | BonusManager "buff" source |
| CritChanceUp | CritChance | BonusManager |
| AttackSpeedDown | AttackSpeed | BonusManager |
| DamageUp | BonusDamage | BonusManager |

Buffs auto-expire on `Heartbeat`. On removal, the bonus is reversed.

---

## 17. Class Skills Reference

### Aegis Skills

| Slot | Skill | Cast | CD | Resource | Description |
|------|-------|------|----|----------|-------------|
| 1 | **Shield Boomerang** | 0s | 6s | 15 | Projectile: Rectangle 40×8, two-pass (out 1.0× / return 0.75×) |
| 2 | **Taunt** | 0.5s | 12s | 30 | Circle 12: Pull + Taunt (5s, 25-stud range) |
| 3 | **Sundering Strikes** | 0.3s | 8s | 20 | Cone 10/120°: stacking DoT (0.1×/tick, max 5) + ArmorReduction (−5%/stack, max 5) |
| 4 | **Battle Beast** ★ | 1.0s | 30s | ALL (min 100) | Self DR: `R/(R+100)×100`%. Allies behind get 70%. 6s duration |
| 5 | **Rush** | 0s | 6s | 10 | Dash 18 studs, 0.25s, unstoppable |

### Arcanist Skills

| Slot | Skill | Cast | CD | Resource | Description |
|------|-------|------|----|----------|-------------|
| 1 | **Arcane Beam** | 0.3s | 5s | 20 | Rectangle 40×4, 1.2× damage |
| 2 | **Frost Bind** | 0.6s | 10s | 35 | Circle 14 at mouse (40 max): 0.6× + Slow 50%/3s + DoT 0.15×/tick/3s. Water element |
| 3 | **Arcane Surge** | 2.0s | 15s | 50 | Cone 30/90°: 3.5× + Knockback 30. Fire element. Channel |
| 4 | **Meteorite** ★ | 1.5s | 30s | ALL (min 100) | Circle 20 at mouse (50 max): dual Fire+Earth hits, damage scales `base × (1 + R/100)`, Vulnerability 1.5×/3s |
| 5 | **Space Jump** | 0s | 5s | 15 | Dash 25 studs, 0.15s |

### Hunter Skills

| Slot | Skill | Cast | CD | Resource | Description |
|------|-------|------|----|----------|-------------|
| 1 | **Swift Arrow** | 0s | 4s | 10 | Rectangle 60×2 pierce (3 targets, 1.2× base, −20%/pierce) |
| 2 | **Barrage** | 0s | 10s | 30 | 5 arrows (0.12s apart), Rectangle 50×3, successive +0.3×/hit on same mob |
| 3 | **Rain of Arrows** | 1.2s | 14s | 40 | Rectangle 30×12 at mouse (50 max): 2 waves × 0.8×, 0.25s apart. Wood element. Channel |
| 4 | **Eagle Eye** ★ | 0s | 25s | ALL (min 100) | +CritChance = `R × 0.5`, −AttackSpeed 40%, 6s |
| 5 | **Fast Steps** | 0s | 4s | 10 | Dash 22 studs, 0.2s |

### LifeSteward Skills

| Slot | Skill | Cast | CD | Resource | Description |
|------|-------|------|----|----------|-------------|
| 1 | **Mending Touch** | 0.4s | 3s | 8 | Single target (30 studs): Heal lowest-HP ally, 2.5× heal multiplier |
| 2 | **Verdant Bloom** | 0.6s | 8s | 15 | Circle 20: Heal all allies + HoT (0.08×/tick, 6s) |
| 3 | **Nature's Purge** | 0.5s | 12s | 12 | Range 25: Remove 1 debuff from all allies (Cleanse) |
| 4 | **Genesis** ★ | 2.0s | 60s | ALL (min 100) | Range 30: Revive knocked-down ally at 70% HP, 20% resource; if none: full-heal lowest-HP ally |
| 5 | **VineSlide** | 0s | 6s | 10 | Dash 22 studs, 0.15s |

**Life Energy Resource:**
- Max 100, start 30, base regen 4/s
- In-combat multiplier: 0.6×
- Proximity bonus: +3/s per wounded ally (≤40% HP) within 30 studs
- Kill bonus: +3 LE per kill
- Hit taken penalty: −1 LE

### Ultimate Mechanics

All ultimates (`slot 4`) have `usesAllResource = true`:
- Consumes ALL current resource (minimum threshold required)
- Resource amount passed to skill via `inputData.resourceUsed`
- Skill effect scales with amount consumed
- Currently `ultimateLocked = false` (testing; should be `true` for production)

---

## 18. Status Effects & Buffs

### StatusEffectTypes Registry

Centralized definitions for all buffs, debuffs, DoTs, and CC:

**Buffs (applied to players):**

| ID | Stat | Scaling | Stacking |
|----|------|---------|----------|
| DamageReduction | DamageReduction | Flat | — |
| CritChanceUp | CritChance | Flat | — |
| AttackSpeedDown | AttackSpeed | Percent | — |
| DamageUp | BonusDamage | Flat | — |

**Debuffs (applied to mobs):**

| ID | Stat/Effect | Scaling | Stacking |
|----|-------------|---------|----------|
| ArmorReduction | Armor | Percent | ×5 (refresh) |
| Vulnerability | DamageTaken | Flat | — |
| Slow | MoveSpeed | Percent | — |
| Mark | DamageTaken | Percent | — |

**Damage Over Time:**

| ID | Scaling | Stack | Note |
|----|---------|-------|------|
| GenericDoT | tick | ×5 | General purpose |
| SunderingDoT | tick | ×5 | Bleed (used by Aegis) |
| FrostDoT | tick | ×1 | Non-stackable |

**Crowd Control:**

| ID | Effect | Note |
|----|--------|------|
| Stun | Blocks all actions | Full CC |
| Immobilize | Blocks movement only | Can still attack |
| Silence | Blocks skills only | Can still move/attack |

### SkillEffects Module

Manages application and ticking of all mob effects:
- **DoT:** Ticks every 0.5s. Damage = `StatsManager.GetTotalDamage(player) × damagePerTick × stacks`
- **ArmorReduction:** Writes `mob:SetAttribute("ArmorReduction", total)` for the damage pipeline
- **Slow:** Directly modifies `humanoid.WalkSpeed`
- **Pull/Knockback:** TweenService-based root part movement
- **Taunt:** Sets `mobData.forcedTarget` in MobAI
- Auto-cleans dead/destroyed mobs from tracking

---

## 19. Elemental System

### 4-Element Advantage Cycle

```
Wood → beats Earth → beats Water → beats Fire → beats Wood
```

| Attacker↓ · Defender→ | Wood | Earth | Water | Fire | None |
|------------------------|------|-------|-------|------|------|
| **Wood** | 1.0× | **1.25×** | 0.85× | 1.0× | 1.0× |
| **Earth** | 0.85× | 1.0× | **1.25×** | 1.0× | 1.0× |
| **Water** | 1.0× | 0.85× | 1.0× | **1.25×** | 1.0× |
| **Fire** | **1.25×** | 1.0× | 0.85× | 1.0× | 1.0× |
| **None** | 1.0× | 1.0× | 1.0× | 1.0× | 1.0× |

### Element Sources
- **Basic attacks:** Derived from equipped weapon's `element` field
- **Skills:** Explicitly set in skill definition (`attackElement`)
- **Mobs:** `MobElement` attribute on mob model

---

## 20. Mob System

### Architecture

```
MobRegistry.lua        ← auto-loads Mobs/*, level scaling
MobSkillRegistry.lua   ← auto-loads MobSkills/*
MobAI.lua              ← FSM: Patrol → Chase → Attack → Skill → Dead
MobBehaviors/init.lua  ← pluggable (Enrage, etc.)
Mobs/
├── Zombie.lua         ← mobTier: "normal", element: Fire
├── Troll.lua          ← mobTier: "miniboss", element: Earth
└── Ogre.lua           ← mobTier: "miniboss", element: Water
MobSkills/
├── Enrage.lua
├── Roar.lua
└── GroundSlam.lua
```

### Mob Definitions

| Mob | Tier | HP | Damage | Armor | Speed | Element | Skills |
|-----|------|----|--------|-------|-------|---------|--------|
| Zombie | normal | 80 | 8 | 2 | 8 | Fire | — |
| Troll | miniboss | 400 | 25 | 10 | 6 | Earth | GroundSlam, Enrage |
| Ogre | miniboss | 600 | 35 | 15 | 5 | Water | GroundSlam, Roar |

### Level Scaling (Power Curve)

$$\text{Stat}(L) = \left\lfloor \text{BaseStat} \times \left(\frac{L + \text{POWER\_OFFSET}}{10}\right)^{\text{exp}} \right\rfloor$$

Where `POWER_OFFSET = 9`.

| Stat | Exponent |
|------|----------|
| Health | 1.28 |
| Damage | 1.15 |
| Armor | 1.05 |
| Speed | not scaled |

### Mob AI State Machine

```
       perception range
           ┌────┐
 Patrol ──→│Chase│──→ Attack ──→ Skill
   ↑       └────┘       │         │
   │                     │         │
   └─────── no target ←──┘─────←──┘
                    │
                  Dead (on 0 HP)
```

- **Patrol:** Moves in `-X` direction at walk speed
- **Chase:** `MoveTo` toward target player; range = perception range
- **Attack:** Basic attack (server-authoritative); tries skills first
- **Skill:** Hybrid client-auth model (server broadcasts cast, clients report hits, server resolves)
- **Target selection:** Prefers taunted/forced target, then closest player behind mob (X-axis)

### Mob Skills

| Skill | Type | Range | CD | Effect |
|-------|------|-------|----|--------|
| **GroundSlam** | Damage | 8 studs | 6s | AoE damage + Stun 1.5s |
| **Roar** | Buff | — | 10s | Self speed +30% for 5s |
| **Enrage** | Buff | — | 15s | Self damage +50% for 8s, triggered at <50% HP |

---

## 21. Wave & Defense Line

### Wave System

*Updated 2026-09-26 (§AGX/X25).* A Lane run is **12 hand-crafted waves** (`WaveConfig.lua:25-38`): 10, 12, 14 … 32 Zombies (+2 per wave), spawn interval 2.5 s → 1.3 s, with guaranteed minibosses on wave 4 (Troll), 7 (Troll), 10 (Ogre) and 12 (Ogre). That is **252 mobs** on Normal, including the 4 minibosses; difficulty `countMult` / `intervalMult` apply on top.

The procedural generator (5 mobs +1 per wave, max 30; a miniboss every 5 waves) is only used past wave 12, which Lane never reaches.

### Difficulty Multipliers

WaveConfig applies multipliers from DifficultyConfig when generating wave data (*updated 2026-09-26, §AGX/X25: aligned to `DifficultyConfig.lua`; Hard needs level 30, Nightmare level 80*):

| Multiplier | Normal | Hard | Nightmare |
|------------|--------|------|-----------|
| HP | 1.0× | 1.45× | 2.15× |
| Damage | 1.0× | 1.25× | 1.6× |
| Armor | 1.0× | 1.15× | 1.35× |
| Speed bonus | +0 | +1 | +2 |
| Mob count | 1.0× | 1.10× | 1.20× |
| Spawn interval | 1.0× | 0.95× | 0.90× |
| Merit reward | 1.0× | 1.25× | 1.75× |
| Essence reward | 1.0× | 1.25× | 2.0× |
| XP reward | 1.0× | 1.25× | 1.5× |

### Defense Line System

```
DefenseLine/
├── init.lua            ← orchestrator, damage formula
├── DefenseConfig.lua   ← tuning constants
├── DefenseHealth.lua   ← HP pool, regen, visual feedback
├── DefenseDetection.lua← X-axis mob proximity check
├── DefenseCombo.lua    ← consecutive-hit combo multiplier
└── DefenseAnimation.lua← mob death animations (Dissolve/Explode/Shrink/Fade)
```

### Defense Line Health
- **Max HP:** Chapter-based: 1,500 (Ch1) / 3,500 (Ch2) / 7,000 (Ch3) / 12,000 (Ch4)
- **Regen:** disabled by default (configurable)
- **Visual feedback:** Color lerps green → yellow (50%) → red (25%), semi-transparent on destruction

### Defense Damage Formula (Percentage-Based Breach)

When a mob reaches the defense line:

$$\text{Damage} = \text{MaxHP} \times \text{BasePct} \times \text{RemainingHpFactor} \times \text{ComboMult}$$

| Mob Tier | Base Pct |
|----------|----------|
| normal | 4% |
| elite | 8% |
| miniboss | 14% |
| boss | 24% |

`RemainingHpFactor` scales with the mob's remaining HP percentage.

### Combo System
- Window: 3 seconds between hits
- Each hit within window increments combo level (max 5)
- Multiplier: max 1.20× at combo level 5
- Decays at 1 level/second after window expires

---

## 22. Game State Machine

```
  IDLE → PREPARING → DEFENDING → VICTORY
    ↑                    │           │
    │                    ↓           │
    └──── DEFEAT ←───────┘           │
    └────────────────────────────────┘
```

| State | Trigger | Actions |
|-------|---------|---------|
| **IDLE** | Game start / post-match | Waiting for players |
| **PREPARING** | `RequestStart` + min players | Countdown (configurable) |
| **DEFENDING** | Countdown reaches 0 | Waves start, combat active |
| **VICTORY** | All waves completed / Horde run timer expires | Post-match summary, auto-return (10s) |
| **DEFEAT** | Defense line destroyed | Post-match summary, auto-return (10s) |

**API:** `GameStateManager.RequestStart(player)`, `SetState(newState)`, `TriggerDefeat()`, `TriggerVictory()`, `ResetGame()`, `OnStateChanged(callback)`, `OnReturnToLobby(callback)`.

---

## 23. Kill Rewards & Drops

### KillRewardManager Pipeline (6 steps per kill)

1. **Player XP** — shared across nearby party members (200-stud range)
2. **Weapon XP** — killer only
3. **Armor XP** — killer only
4. **Loot drops** — personal: every XP-eligible party member (and always the killer) rolls their own drop on each party kill, scaled by their **own** level (§AGX/X44; *updated 2026-09-26*)
5. **Kill callbacks** — subscribers (AchievementManager, etc.)
6. **Client MobDeath notification** — all clients

### Kill XP Formula

$$\text{XP} = \max(1, \text{round}(\text{XPRequired}(L_p) \times k \times \text{TierMult} \times \text{DeltaMult} \times \text{ModeMult}))$$

| Parameter | Value |
|-----------|-------|
| $k$ (base fraction) | 0.03 (3% of current level req) |
| TierMult: normal | 1 |
| TierMult: miniboss | 8 |
| TierMult: boss | 25 |
| DeltaMult | Delta-based table keyed on `mobLevel - playerLevel` (see BALANCE_NUMBERS.md §20) |
| ModeMult | 1.0× (Defense), 0.45× (HordeMode), 1.0× (CentralBoss) |

### Party XP Sharing
- XP pool divided equally among party members within 200 studs
- Party data source: `TeleportDataReader.GetPartyData()` → fallback `PartyManager.GetPartyMembers()`

### Drop Tables

Managed by `DropTableConfig`:

| Tier | Drops |
|------|-------|
| Normal | Merits 1–3 (100%) |
| Miniboss | Merits 8–15 (100%), Essence 2–4 (30%, no level scaling) |
| Boss | Merits 25–50 (100%), Essence 8–20 (75%, no level scaling) |

Currency drops scale +10% per level above 1 (unless `noScale` flag), using the recipient's own level `min(mob RewardLevel, max(5, own level))` (§AGX/X44). Mode, difficulty, BountyBoard and MeritBonus multipliers each apply once.

### Wave Completion XP

`15 + 15 × waveNumber` XP granted to all connected players.

### Danger Bonus (Card/Vote System)

When threat cards are chosen during a run, `RunModifiers` tracks the cumulative danger bonus. This bonus is applied as a multiplier on:

- **Kill XP** — `KillRewardManager.GetXPReward()` multiplies by `(1 + dangerBonus)`
- **Wave completion XP** — `LaneDefenseMain` multiplies by `(1 + dangerBonus)`
- **Merit drops** — `DropManager.GrantDrop()` scales merit amounts by the `meritScalar` modifier

---

## 24. Talent Tree

### Architecture

```
TalentTreeConfig.lua           ← node definitions (ReplicatedStorage)
TalentManager.lua              ← allocate/refund/respec (server)
TalentEffectAggregator.lua     ← sums → BonusManager "talent" source
TalentTreeValidator.lua        ← dev-time integrity checks
TalentClient.lua               ← client-side state sync
```

### Talent Points

$$\text{TotalPoints} = \sum \text{(levels of every owned weapon, all classes)} + \text{BonusTalentPoints}$$

*Updated 2026-09-26 (§AGX/X25):* matches `TalentManager.TalentPointProvider` (minimum 1). With 4 classes × 2 weapons × level 50, the endgame budget is **400** points.

### Tree Structure

4 branches (each with start → 8–10 nodes) + 4 cross-connectors:

| Branch | Theme | Key Stats |
|--------|-------|-----------|
| **Vanguard** | Tank/melee | Health, DamageReduction, Determination, Thorns |
| **Ranger** | Ranged DPS | CritChance, CritDamage, AttackSpeed, Focus |
| **Spellcaster** | Magic | BonusDamage, SkillDamage, Mana, CooldownReduction |
| **Support** | Utility | MeritBonus, XPBonus, Lifesteal, MovementSpeed |

### Node Types

| Type | Size | Typical Cost |
|------|------|-------------|
| **small** | Minor stat boost | 1 point |
| **notable** | Medium stat boost | 2 points |
| **keystone** | Powerful passive rule | 3 points |

### Allocation Rules
- Must start from branch start node
- New nodes must have ≥1 allocated neighbor (adjacency)
- Level requirement per node
- Prerequisite node check
- Refund: leaf-only removal (≤1 allocated neighbor), BFS connectivity verified as safety net

### Respec
- **Cost:** 1 Respec Scroll, otherwise **25 Essence** at any level (*updated 2026-09-26, §AGX/X42*: was 25 / 40 Essence "+" 20,000 / 50,000 Merits; the Merit part was never charged and has been removed)
- Respec Scroll: shop price 25 Essence; also from 4 fragments (Horde), the day-30 login reward and achievements
- Clears all nodes except start, rebuilds aggregator

### Keystone Examples

| Keystone | Branch | Effect |
|----------|--------|--------|
| Unbreakable Wall | Vanguard | Rule: `"UnbreakableWallPassive"` |
| Deadeye | Ranger | Rule: `"DeadeyePassive"` |
| Arcane Mastery | Spellcaster | Rule: `"ArcaneMasteryPassive"` |
| Lucky Finder | Support | Rule: `"LuckyFinderPassive"` |

Rules are queried at runtime by combat systems via `TalentEffectAggregator.HasRule(player, ruleName)`.

---

## 25. Achievement System

### AchievementManager

Server-side tracking with tiered unlock levels. Subscribes to hooks from:
- `AttackHandler.OnMobKilled` → kill stats
- `HitTracker.OnHitDealt/OnHitReceived` → hit/damage/crit stats
- `CurrencyManager.OnMeritsAdded` → merit collection
- `MobSpawner.OnWaveCompleted` → wave survival

### Tracked Stats

`totalKills`, `killsByMobId`, `killsByTier`, `hitsDelivered`, `hitsReceived`, `meritsCollected`, `wavesSurvived`, `highestWave`, `totalDamageDealt`, `totalDamageTaken`, `criticalHits`, `bestCombo`

### Achievement List

| ID | Name | Category | Tiers |
|----|------|----------|-------|
| kills | Slayer | Combat | 1, 50, 250, 1K, 5K, 25K, 100K |
| miniboss_slayer | Giant Slayer | Combat | 1, 5, 15, 50, 150, 500 |
| boss_slayer | Boss Hunter | Combat | 1, 5, 15, 50, 100, 300 |
| combo | On a Roll | Combat | 5, 10, 20, 35, 50, 75, 100 |
| crits | Precision Striker | Combat | 50, 250, 1K, 5K, 25K, 100K |
| damage | Heavy Hitter | Combat | 10K, 50K, 250K, 1M, 5M, 25M |
| waves | Defender | Survival | 1, 10, 25, 50, 100, 250, 500 |
| highest_wave | Highrise | Survival | 5, 15, 30, 60, 100 |
| tanky | Thick Skin | Survival | 5K, 25K, 100K, 500K, 2M |
| merits | Merit Earner | Collection | 500, 5K, 25K, 100K, 500K |
| hits_dealt | Relentless | Dedication | 100, 1K, 10K, 100K, 500K |
| hits_taken | Punching Bag | Dedication | 200, 1K, 5K, 25K, 100K |

### Rewards

Each tier grants escalating Merits + Essence. High tiers (5+) also grant RespecTokens.

---

## 26. NPC System

### Architecture

```
NPCManager/
├── init.lua               ← spawns NPCs, routes interactions
├── NPCRegistry.lua        ← data-driven registry (populated per-place)
├── ShopHandler.lua        ← purchase validation
├── QuestHandler.lua       ← quest state machine
├── LoreHandler.lua        ← dialogue trees
├── TeleportHandler.lua    ← in-place teleportation
├── MatchmakingHandler.lua ← queue via NPC
└── WeaponSmithHandler.lua ← forge actions
```

### Interaction Flow

```
Client: NPCInteraction detects proximity (12 studs)
    → "NPCInteract" { npcId }

Server: NPCManager.HandleInteraction(player, npcId)
    → Range check (12 studs)
    → Route to handler based on npcType:
        "Shop"         → ShopHandler.OnInteract
        "Quest"        → QuestHandler.OnInteract
        "Lore"         → LoreHandler.OnInteract
        "Teleport"     → TeleportHandler.OnInteract
        "Matchmaking"  → MatchmakingHandler.OnInteract
        "WeaponSmith"  → WeaponSmithHandler.OnInteract
```

### Lobby NPCs (10 total)

| NPC | Type | Function |
|-----|------|----------|
| Grimjaw (Blacksmith) | Shop | Sells weapons/items for Merits |
| Mirael (Enchantress) | Shop | Sells magical items for Essence |
| Captain Aldric | Quest | 2 quests: first_defense, veteran_defender |
| Elder Theron | Lore | Branching dialogue about the village |
| Lyris (Scholar) | Lore | Teaches elemental cycle |
| Warden Kael | Teleport | Future teleport destinations |
| Commander Vex | Matchmaking | Queues for Defense mode |
| Durgan (Refiner) | WeaponSmith | Weapon/armor refinement |
| Kaelen (Tier Smith) | WeaponSmith | Tier upgrades |
| Sylwen (Enchanter) | WeaponSmith | Bonus rerolls |

---

## 27. Quest System

### QuestHandler

Server-authoritative quest system with pluggable state provider.

### Quest Lifecycle

```
Available → Accept → InProgress → ReadyToTurnIn → TurnIn → Completed
                         ↑                                      │
                         └──── repeatable quests loop back ─────┘
```

### State Providers

| Provider | Backend | Persistence |
|----------|---------|-------------|
| `DataStoreStateProvider` (default) | `PlayerDataManager → data.Account.Quests` | Yes (survives rejoin) |
| `AttributeStateProvider` (fallback) | Player attributes | No (lost on rejoin) |

### Objective Tracking

Hooks into:
- `AttackHandler.OnMobKilled` → `IncrementObjective(player, "kill", mobId)`
- `MobSpawner.OnAllWavesCompleted` → `IncrementObjective(player, "completeWaves", nil)`

### Quest Rewards

Supports three XP formats:
- Flat: `{ type = "XP", amount = 2500 }`
- Percent of level requirement: `{ type = "XP", percent = 35 }`
- Levels worth: `{ type = "XP", levels = 0.5 }`

---

## 28. Shop & Inventory

### ShopManager (3 tabs)

| Tab | Currency | Delivery | Status |
|-----|----------|----------|--------|
| Cosmetics | Merits/Essence | `wardrobe.owned[id] = true` | Functional |
| Consumables | Merits/Essence | `InventoryManager.AddItem` | Functional |
| Premium | Robux (future) | — | Stub |

### InventoryManager

Server-authoritative inventory for accessories, consumables, and tokens.

**Data:** `data.Account.Inventory` — array of `{ itemId, quantity }` entries (stacking).

**Accessory Slots:**
- `TrinketId` → BonusManager source `"acc_trinket"`
- `Ring1Id` → BonusManager source `"acc_ring1"`
- `Ring2Id` → BonusManager source `"acc_ring2"`

Equipping an accessory pushes its stat bonuses to BonusManager; unequipping clears them.

---

## 29. Daily Login Rewards

### DailyLoginManager

*Updated 2026-09-26 (§AGX/X25; behaviour from §AGX/X47).* Data in `data.Account.DailyLogin` (`lastClaimDate`, `streak`, `totalDays`). One claim per UTC day pays two tracks:

- **Calendar:** the 30-day table below, indexed by **total days claimed** (`totalDays`). It never resets, so missing a day only delays it. Per 30 claims: 26,500 Merits, 228 Essence, 1 Respec Scroll.
- **Spree:** consecutive-day streak (`streak`); missing a UTC day resets it to 1. Bonus of **10 Merits × spree** (capped at 300/day) plus **+5 / +10 / +20 Essence** on spree days 7 / 14 / 30. A full 30-day spree adds 4,650 Merits and 35 Essence.
- **Claim check:** `today ≠ lastClaimDate` (UTC dates)

### Reward Schedule Highlights

| Day | Merits | Essence | Special |
|-----|--------|---------|---------|
| 1 | 100 | — | — |
| 7 | 1,000 | 10 | Weekly milestone |
| 14 | 2,000 | 20 | — |
| 21 | 3,000 | 30 | — |
| 30 | 10,000 | 100 | +1 Respec Scroll |

Days between milestones escalate gradually (100–800 Merits, Essence on about every other day).

---

## 30. Cosmetic & Visual System

> **Full cosmetic system documentation:** [COSMETICS.md](COSMETICS.md)

### Architecture

```
CosmeticManager/
├── init.lua                    ← orchestrator + network handlers
├── PlayerCosmeticManager.lua   ← wardrobe CRUD, visual application (R6 color/material)
└── MobCosmeticManager.lua      ← mob visual variants

CosmeticConfig.lua              ← all cosmetic definitions
VisualEquipmentManager.lua      ← weapon model attachment to characters
```

### Cosmetic Slots

| Slot | Default (none) | Effect |
|------|----------------|--------|
| **Headgear** | "none" | Changes head Color + Material |
| **Outfit** | Class default | Changes Torso/Arms/Legs Color + Material |

### Cosmetic Catalog

**Headgear:** none, hood_basic (Common/universal), helm_aegis (Uncommon/Aegis), circlet_arcanist (Uncommon/Arcanist), mask_hunter (Uncommon/Hunter)

**Outfits:** default_aegis/arcanist/hunter (Common/class-locked), peasant_garb (Common/universal), dark_knight (Rare/Aegis), shadow_robes (Rare/Arcanist), forest_ranger (Rare/Hunter)

**Starter Wardrobe:** none, hood_basic, peasant_garb, default_aegis, default_arcanist, default_hunter

### Head Presets (Character Creation)

| ID | Name | Visual |
|----|------|--------|
| head_default | Fair | Light skin tone |
| head_pale | Pale | Lighter |
| head_dark | Dark | Darker skin tone |
| head_scarred | Scarred | Fair + scar accessory |

### Mob Variants

| Mob | Variants | Features |
|-----|----------|----------|
| Zombie | default, decayed, frozen, burning | Color/material overrides, glow/fire/sparkles |
| Ogre | default, armored, enraged | — |
| Troll | default, elite, moss | — |

### Weapon Visual Attachment

`VisualEquipmentManager` clones weapon templates from `ServerStorage.Models.Weapons/` and welds them to the player's Right Arm with grip offset. Re-attaches on respawn/class switch.

---

## 31. Leaderboard System

### LeaderboardManager

3 OrderedDataStore-backed leaderboards, updated every 120 seconds.

| Board | DataStore | Source |
|-------|-----------|--------|
| GearScore | `Leaderboard_GearScore_v1` | `GearRating.Calculate(data)` |
| HighestWave | `Leaderboard_HighestWave_v1` | `data.Account.HighestWaveReached` |
| TotalPlayTime | `Leaderboard_TotalPlayTime_v1` | `data.Account.TotalPlayTime` |

**Name cache:** Prevents redundant `GetNameFromUserIdAsync` calls across updates.

---

## 32. Party & Matchmaking

### PartyManager (Lobby)

| Feature | Detail |
|---------|--------|
| Max party size | 5 |
| Invite timeout | 30 seconds |
| Leader actions | Create, Invite, Kick, Disband, Promote |
| Member actions | Accept/Decline invite, Leave |
| Auto-leadership | Transferred on leader disconnect |
| XP bonus | +5% per friend, +2.5% per non-friend (via BonusExpSystem) |

### MatchmakingManager (Lobby)

| Feature | Detail |
|---------|--------|
| Queue scope | Per-mode, party-as-unit |
| Countdown | 5 seconds |
| Cancellation | Available during queue and countdown |
| Launch | `TeleportManager.TeleportToGameMode(players, options)` |
| Solo handling | Auto-creates solo party via `PartyManager.EnsureParty()` |

---

## 33. Teleport System

### Lobby → Game Mode

`TeleportManager.TeleportToGameMode(players, options)`:
- Packages teleport data: `{ modeId, difficulty, partyData, lobbyPlaceId, timestamp }`
- Uses `TeleportService:TeleportAsync` with `TeleportOptions:SetTeleportData()`

### LaneDefense → Lobby

`ReturnTeleporter`:
- `GameStateManager.OnReturnToLobby` → `TeleportAllToLobby()`
- Individual return via `RequestReturnToLobby` event
- Reads `lobbyPlaceId` from teleport data; falls back to hardcoded ID

### Teleport Data Reader (LaneDefense)

Reads `Player:GetJoinData().TeleportData` on arrival:
- Stores party composition, difficulty, mode
- Falls back to defaults for Studio testing
- Applies class from teleport data if different from current

### Place IDs

| Place | ID |
|-------|-----|
| Lobby | 115774137563700 |
| LaneDefense | 138768963731267 |

---

## 34. Client Systems

### InputSystem

Centralized input dispatcher supporting keyboard, gamepad, and touch.

**Contexts:**
- `"Combat"` — Attack, Skill1–4, Dash active
- `"Lobby"` — Interact, EmoteWheel active
- `"UI"` — Suppresses game actions (typing in TextBoxes)

**Key bindings (keyboard defaults):**
- Attack: LMB
- Skill 1–4: Q, W, E, R
- Dash: Space
- Interact: F
- EmoteWheel: T

### CameraSystem

Mode-based camera controller:
- **Free:** Default Roblox camera (Lobby)
- **FixedIsometric:** Scriptable camera offset from player, following with look-ahead (LaneDefense: offset = Vector3(-12, 8, 0), lookAhead = 20)

### MovementSystem

Constraint-based:
- **Free:** No restrictions (Lobby)
- **NoJump:** Zeroes JumpPower/Height (LaneDefense)
- **FaceDirection:** Forces character to face a fixed direction + mouse-look rotation (LaneDefense: face +X / right)

### PlayerAttack (Client)

Client-authoritative basic attack module. Binds "Attack" input → plays attack animation instantly → spawns `ClientProjectile` for ranged classes → performs local hit detection via `SharedGeometry` → fires `PlayerHitReport { hitMobIds, lookDirection }` to server for validation. Melee classes detect hits in a shape around the player; ranged classes delegate detection to `ClientProjectile`.

### SkillInput (Client)

Binds `Skill1–4` + `Dash` → sends `SkillRequest` with slot, move direction, look direction, and target position. Tracks local cooldowns for UI display.

### AnimationSystem (Client)

Centralized animation controller with per-character track caching and category-based mutual exclusion. Categories: idle, movement, attack, skill, emote, death.

### DamageNumbers (Client)

Floating combat text. Supports: element coloring (White/Green/Gold/Blue/Orange), crit scaling (size + `!`/`!!`), own-vs-other desaturation, DoT style (smaller, shorter, offset).

### Other Client Modules

| Module | Purpose |
|--------|---------|
| SkillVisuals | Client-side VFX for skill effects (733 lines) |
| MobVisuals | Client-side mob animation + skill visuals; listens for `MobBasicAttackCast`; delegates geometry to `SharedGeometry` |
| LootNotification | Drop pickup toast |
| ResourceCache | Client-side stat/resource cache |
| SceneController | Client-side scene state toggling |
| NPCInteraction | Proximity-based NPC detection + prompt |
| CosmeticClient | Client-side wardrobe sync |
| TalentClient | Client-side talent state sync |
| AchievementClient | Client-side unlock display |
| ClientProjectile | Client-side projectile visual + hit detection for ranged basic attacks |
| SharedGeometry | Unified 2D XZ-plane point-in-shape math (Circle, Cone, Rectangle, Ring) shared by client + server |
| DeathUI | Two-phase death overlay: KnockedDown countdown (10s) + respawn button on Dead state |
| ClassCatalog | Client-side class display data |
| ClassDescriptions | Per-class flavor text and role summaries |
| Locale | i18n string table (English only) |

---

## 35. UI Components (React)

All UI is built with React-lua 17.0.2 (functional components + hooks).

### Shared UI Components

| Component | File | Description |
|-----------|------|-------------|
| **HUD** | `HUD.lua` | Health/resource bars, nav buttons (Stats/Equipment etc.), currency display, combo summary |
| **ClassMenu** | `ClassMenu.lua` | Class browser, class switching interface |
| **StatsMenu** | `StatsMenu.lua` | Primary stat allocation (+/−1), derived stat display |
| **TalentTreeUI** | `TalentTreeUI.lua` | Visual node graph, allocate/refund/respec buttons |
| **EquipmentUI** | `EquipmentUI.lua` | Weapon/armor stats, switch, progression display |
| **CharacterCreation** | `CharacterCreation.lua` | First-time class+head+gender selection |
| **WardrobeUI** | `WardrobeUI.lua` | Cosmetic equip/unequip (own ScreenGui) |
| **AchievementsUI** | `AchievementsUI.lua` | Achievement list, progress bars, unlock toasts |
| **GlobalShopUI** | `GlobalShopUI.lua` | 3-tab shop interface |
| **SettingsUI** | `SettingsUI.lua` | Volume sliders + mute toggle (SoundManager integration) |
| **TestingUI** | `TestingUI.lua` | Admin debug panel |

### Lobby-Only UI

| Component | File | Description |
|-----------|------|-------------|
| **LobbyApp** | `LobbyApp.lua` | Root React component for lobby |
| **MainMenu** | `MainMenu.lua` | Mode selection overlay |
| **MatchmakingUI** | `MatchmakingUI.lua` | Queue status bar |
| **NPCDialog** | `NPCDialog.lua` | Dialogue/quest/teleport overlay |
| **ShopUI** | `ShopUI.lua` | NPC shop purchase interface |
| **WeaponSmithUI** | `WeaponSmithUI.lua` | Forge actions (refine/tier/reroll) |
| **EmoteWheel** | `EmoteWheel.lua` | 4-emote radial selector |
| **SocialPanel** | `SocialPanel.lua` | Party management + player browser |
| **PartyInviteToast** | `PartyInviteToast.lua` | Incoming invite notification |

### LaneDefense-Only UI

| Component | File | Description |
|-----------|------|-------------|
| **LaneDefenseApp** | `LaneDefenseApp.lua` | Root React component for defense |
| **BattleClassUI** | `BattleClassUI.lua` | Active class badge |
| **TeammateVitals** | `TeammateVitals.lua` | Party HP bars |

---

## 36. Sound System

### SoundManager

3 SoundGroup categories under `SoundService`:

| Group | Volume Type | Usage |
|-------|-------------|-------|
| Music | Background | lobby_theme, combat_theme, boss_theme, victory/defeat |
| SFX | Fire-and-forget | Combat sounds, level-up, forge, equipment |
| UI | Fire-and-forget | Clicks, hovers, opens, errors, toasts |

**Features:**
- Per-group volume control (0–1)
- Master mute toggle
- Music crossfade (1.5s)
- All sound assets are currently placeholders (`rbxassetid://0`)

---

## 37. Resource System

### ResourceManager

Per-player class resource managed via behavior plugins:

| Class | Resource | Start | Max | Base Regen | Hit Generation |
|-------|----------|-------|-----|------------|----------------|
| Aegis | Determination | 25 | 100 | 1.0/s | +1/hit dealt, +2/hit received, +3/kill |
| Arcanist | Aether | 35 | 100 | 4.0/s (0.5× in-combat) | +6/kill, −3/hit received |
| Hunter | Killer Instinct | 15 | 100 | 3.0/s | +0.6/hit, +2/crit, +3/kill, −2/received |
| LifeSteward | Life Energy | 30 | 100 | 4.0/s (0.5× in-combat) | +2/s per wounded ally (range 35, ≤60% HP, max 3), +2/kill |

**Resource Max:** 100 base + RSV stat contributions

**Update loop:** Heartbeat-driven, throttled at 0.1s intervals. Polls class behavior's `GetResourceRate()` which factors in combat state, time since last hit, and stat bonuses.

**Callbacks:** `OnResourceFull()` and `OnResourceEmpty()` delegate to behavior modules for class-specific effects.

---

## 38. Difficulty System

### DifficultyConfig

3 difficulty tiers affecting the entire mob/wave system:

| Tier | Order | Description |
|------|-------|-------------|
| **Normal** | 1 | Base values, recommended for solo |
| **Hard** | 2 | +50% HP, +30% damage, +20% armor, faster spawns, +25% rewards |
| **Nightmare** | 3 | +150% HP, +80% damage, +50% armor, much faster spawns, +75-100% rewards |

**Integration chain:** `TeleportManager` → `TeleportDataReader` → `MobSpawner.SetDifficulty()` → `WaveConfig.GetWave(wave, difficulty)` → `MobRegistry.GetScaledMob(id, level, overrides)` → `MobAI.RegisterMob()`

---

## 39. Card & Event Vote System

A shared per-run modifier system where players collectively vote on cards that alter difficulty, rewards, and spawning parameters for the current game session.

### Architecture

```
CardRegistry.lua           ← 30 card definitions across 3 pools (server)
RunModifiers.lua           ← per-run scalars + danger bonus tracker (server)
VoteManager.lua            ← vote lifecycle: start → timer → resolve → apply (server)
VoteUI.lua                 ← 3-card selection overlay (client, React)
```

### Card Pools

| Pool | Mode | Count | Purpose |
|------|------|-------|---------|
| `hordeSupply` | Horde | ~10 | Beneficial: merit cache, potions, power surges, class recharges |
| `hordeThreat` | Horde | ~10 | Risk/reward: mob HP/damage/armor/speed up, extra spawns; increases danger bonus |
| `laneTactical` | Lane | ~10 | Per-wave modifiers: fortify defenses, supply drops, elite bounty, dense packs |

Each card has: `id`, `label`, `description`, `pool`, `rarity`, `applyEffect(runModifiers)`.

### RunModifiers (Per-Run State)

Tracks cumulative modifier scalars applied by voted cards. All scalars start at 1.0 (or 0 for flat bonuses).

| Modifier | Default | Used By |
|----------|---------|---------|
| `hpScalar` | 1.0 | `MobRegistry.GetScaledMob()` — scales mob HP |
| `damageScalar` | 1.0 | `MobRegistry.GetScaledMob()` — scales mob damage |
| `armorFlatBonus` | 0 | `MobRegistry.GetScaledMob()` — added to mob armor |
| `speedScalar` | 1.0 | `MobRegistry.GetScaledMob()` — scales mob speed |
| `spawnIntervalScalar` | 1.0 | `HordeModeSpawner` / `MobSpawner` — scales spawn delay |
| `normalMobCountScalar` | 1.0 | `HordeModeSpawner` / `MobSpawner` — scales mob count |
| `meritScalar` | 1.0 | `DropManager.GrantDrop()` — scales merit payouts |
| `dangerBonus` | 0 | `KillRewardManager.GetXPReward()` — XP multiplier |
| `minibossCharge` | 0 | `HordeModeSpawner` — consumed to spawn extra miniboss |

**API:** `RunModifiers.Get(key)`, `RunModifiers.Set(key, value)`, `RunModifiers.AddDangerBonus(pct)`, `RunModifiers.GetDangerBonus()`, `RunModifiers.ConsumeMinibossCharge()`, `RunModifiers.Reset()`.

`Reset()` is called in `OnReturnToLobby` callbacks in both `HordeModeMain` and `LaneDefenseMain` to prevent modifier leakage across runs.

### VoteManager (Server)

Orchestrates the vote lifecycle:

1. **`StartVote(pool)`** — Draws 3 random cards from the pool via `CardRegistry.DrawCards(pool, 3)`. Fires `VoteStarted` RemoteEvent to all clients with card data + timer.
2. **Timer (6s)** — Clients display `VoteUI` overlay. Players fire `CastVote` RemoteEvent with their chosen card index.
3. **`ResolveVote()`** — Tallies votes (majority wins, random tie-break). Fires `VoteResolved` to clients with the winning card.
4. **`ApplyCard(card)`** — Calls `card.applyEffect(RunModifiers)` to mutate per-run scalars.

**State API:** `VoteManager.IsVoteActive()` — used by MobSpawner pre-spawn hook to gate lane wave starts until vote completes.

**Run state context:** `VoteManager.SetRunState({ difficulty, elapsed, modeId })` — provides context for card UI tooltips.

### Vote Cadence

| Mode | Vote Type | Interval | Notes |
|------|-----------|----------|-------|
| **Horde** | Supply | Every 90s, first at 45s (7 per run) | Beneficial cards (economy, utility) |
| **Horde** | Threat | Every 90s, first at 90s (7 per run) | Risk/reward cards (mob buffs + danger bonus) |
| **Lane** | Tactical | Per wave start | Wave blocks on vote via pre-spawn hook |

### Horde Run Duration

Horde Mode runs have a fixed duration of **630 seconds (10:30)** of play time: one vote loop fires every 45 s and alternates supply/threat, so a run has **7 supply + 7 threat** votes (*updated 2026-09-26, §AGX/X25*).

**End-of-run sequence:**

```
RUN_DURATION (630s) elapses
  → hordeRunActive = false (vote loops exit)
  → HordeModeSpawner.Stop() (no new mobs)
  → Poll MobAI.IsAnyMobAlive() every 1s (players clear remaining mobs)
  → RunModifiers.Reset()
  → GameStateManager.TriggerVictory()
  → 10s delay → OnReturnToLobby callbacks → teleport to lobby
```

### Spawner Integration

Both `HordeModeSpawner` and `MobSpawner` (Lane) read RunModifiers at spawn time:

- **Spawn interval:** `baseInterval × spawnIntervalScalar`
- **Mob count:** `baseMobCount × normalMobCountScalar` (rounded)
- **Mob stats:** `MobRegistry.GetScaledMob()` applies `hpScalar`, `damageScalar`, `armorFlatBonus`, `speedScalar`
- **Miniboss injection:** `HordeModeSpawner` calls `ConsumeMinibossCharge()` to inject extra minibosses
- **Lane pre-spawn hook:** `MobSpawner.SetPreSpawnHook(fn)` — called before each wave; if the hook returns `false`, the wave waits (used to block on active votes)

---

## 40. Chapter System

### ChapterConfig

4 chapters govern gear progression caps:

| Chapter | Level Range | Max Refine | Max Tier | Ascension Crests |
|---------|-------------|------------|----------|------------------|
| 1 | 1–50 | +6 | IV | 0 |
| 2 | 51–100 | +9 | VII | 1 |
| 3 | 101–150 | +12 | X | 2 |
| 4 | 151–200 | +15 | XII | 3 |

**Helpers:** `GetChapter(level)`, `GetMaxRefine(level)`, `GetMaxTier(level)`, `GetAscensionCrests(level)`.

Chapter caps are enforced by `WeaponRefinement`, `ArmorRefinement`, `WeaponTierSystem`, and `ArmorTierSystem` before allowing upgrades.

---

## 41. Class Mastery System

### ClassMasteryConfig

When a player reaches the level cap for their current chapter, excess XP is converted to Class Mastery XP for the active class. 9 milestones from Initiate to Grandmaster.

| Milestone | XP Required | Reward |
|-----------|-------------|--------|
| Initiate | 0 | — |
| Apprentice | (configured) | Bound Token grant |
| Journeyman | (configured) | Bound Token grant |
| Adept | (configured) | Bound Token grant |
| Expert | (configured) | Bound Token grant |
| Master | (configured) | Bound Token grant |
| Grandmaster | (configured) | Bound Token grant + role seal |

**Second Weapon Gate:** Requires player level ≥ 60 AND reaching the appropriate mastery milestone to unlock the second weapon for a class.

**Role Seal Map:** Maps each class to a unique seal identifier used for cosmetic/title unlocks.

---

## 42. Auction & Economy Config

### AuctionConfig

Economy rules for the (not-yet-implemented) auction house:

| Property | Value |
|----------|-------|
| Listing Tax | 12% |
| Trade Level Gate | (configured per band) |
| New Account Caps | Limited listing count for new accounts |
| Essence Market Anchors | Per-tier base values for price estimation |

Auction bands define item value ranges. The config is ready; the runtime auction house system is not yet built (per BALANCE_REWORK_SPEC §52.3).

---

## 43. Monitoring & Anti-Exploit

### MonitoringSystem

Passive awareness system (non-intrusive, does not ban/kick):

| Feature | Description |
|---------|-------------|
| Dodge rate tracking | Flags players with >95% dodge rate (min 20 samples) |
| Hit report timing | Flags late hit reports (>3s) |
| Distance anomalies | Flags hits/buffs >10-stud buffer beyond expected range |
| Event logging | In-memory ring buffer (1000 events max) |
| Player flagging | Per-player flag list with timestamps |
| Configurable | Enable/disable toggle, output logging toggle |

---

## 44. XP & Leveling Formulas

### Player XP Required (Power Curve)

$$\text{XPRequired}(L) = \text{round}\left(120 \times 3.2^b \times (1 + 0.05p)^{1.9}\right)$$

Where $b = \lfloor(L-1)/10\rfloor$ (bracket) and $p = (L-1) \bmod 10$ (position within bracket).

| Level | XP Required |
|-------|-------------|
| 1 | 120 |
| 10 | 167 |
| 20 | 534 |
| 50 | 5,479 |
| 100 | 175,000 |
| 150 | 5,600,000 |
| 200 | 179,000,000 |

### XP Dual Multiplier

$$\text{ActualXP} = \text{BaseXP} \times (1 + \text{StaticBonus}/100) \times \text{DynamicMultiplier}$$

- **Static:** `data.Bonus.XPBonus` (from talents/equipment)
- **Dynamic:** `BonusExpSystem.GetMultiplier(player)` (party bonus, events)

### Kill XP Design Target

~30 kills/min × 3% per kill ≈ **1.8 levels/hour** at equal-level content.

### Weapon/Armor XP

$$\text{XPRequired}(L) = \text{round}(80 + 8 \times L^2)$$

---

## 45. Balance Numbers Reference

> **Full balance numbers are maintained in [BALANCE_NUMBERS.md](BALANCE_NUMBERS.md).** This section provides a pipeline summary only.

### Outgoing Damage Pipeline (8 Steps)

```
1. Base Damage = GetTotalStat("Damage") + WeaponAttack
2. Action Multiplier (from skill): damage *= actionMultiplier
3. Percent Bonus: damage *= (1 + DamagePercent/100)
4. Armor (division): effectiveArmor = max(0, mobArmor - playerPen)
   damage *= 100 / (100 + effectiveArmor)
5. Crit (geometric multi-crit, CritChance cap 200%, CritDamage cap 1.80×)
6. Elemental: 1.25× strong / 0.85× weak
7. Vulnerability multiplier
8. floor(damage)
```

### Incoming Damage Pipeline

```
Mob base damage (level-scaled)
→ Armor (division): damage *= 100 / (100 + playerArmor)
→ DR: damage *= (1 - DamageReduction/100)
→ Apply to Humanoid
```

---

## 46. Cross-System Data Flow

### Damage Pipeline Flow

```
PlayerAttack.lua (client)
  → Plays attack animation instantly (AnimationSystem)
  → Melee: local hit detection via SharedGeometry.IsPointInShape
  → Ranged: spawns ClientProjectile → detects hits along trajectory
  → "PlayerHitReport" { hitMobIds, lookDirection }
  → AttackHandler.HandlePlayerHitReport (server)
    → Validates: mob exists, distance ≤ shape range + buffer, player alive
    → For each valid mob:
      → DamageHandler.DamageMob
        → StatsManager: base damage + weapon ATK + crit + armor + element
        → HitTracker.RecordHitDealt (combo + stats)
        → ResourceManager.OnHitDealt (resource generation)
        → If kill:
          → KillRewardManager.ProcessKill
            → PlayerLevelSystem.AddExperience (party-shared)
            → WeaponXPSystem.AddMobKillXP
            → ArmorXPSystem.AddMobKillXP
            → DropManager.ProcessKill (loot)
            → Kill callbacks (AchievementManager)
          → Mob model destroyed
```

### Class Switch Flow

```
Client: ClassMenu → "RequestClassSwitch" { className }
Server: ClassManager.Init handler
  → PlayerClassSystem.CanSwitchClass (cooldown)
  → GameStateManager.IsInGame (blocked during combat)
  → ClassManager.SetClass(player, className)
    → PlayerDataManager.SetActiveClass
    → ResourceManager.OnClassChanged (reset resource)
    → WeaponManager.EnsureStarterWeapon
    → ArmorManager.EnsureStarterArmor
    → VisualEquipmentManager.AttachWeapon
    → CosmeticManager.OnClassSwitched (re-validate cosmetics)
    → BonusManager: apply innate bonuses to "innate" source
    → PlayerBonusSystem.ApplyWeaponBonuses to "weapon" source
    → StatsManager.RecalculateAll → health sync
  → Fire "ClassSwitchResult" to client
```

### Talent → Stats Flow

```
Client: TalentTreeUI → "AllocateTalent" { nodeId }
Server: TalentManager.AllocateNode
  → TalentTreeValidator checks (adjacency, cost, level, prereqs)
  → data.Account.AllocatedTalents[nodeId] = true
  → TalentEffectAggregator.OnNodeAllocated
    → BonusManager.ModifySourceBonus(player, "talent", stat, value)
    → BonusManager.Recalculate → data.Bonus updated
    → PlayerStatSystem reads updated Bonus for derived stats
```

### Wave Lifecycle

```
LaneDefense:
  GameStateManager: PREPARING → DEFENDING
    → MobSpawner.StartWave(1)
      → PreSpawnHook: wait if VoteManager.IsVoteActive()
      → WaveConfig.GetWave(1, difficulty)
      → For each mob: SpawnMob(mobId, level)
        → MobRegistry.GetScaledMob (level + difficulty + RunModifiers scaling)
        → Clone template, set attributes
        → MobAI.RegisterMob → FSM starts
        → CosmeticManager.ApplyMobVariant
      → WaitForWaveClear
        → MobAI.IsAnyMobAlive() polling
        → OnWaveCompleted callbacks
        → Auto-advance: StartNextWave
    → OnAllWavesCompleted
      → GameStateManager: DEFENDING → VICTORY
      → 10s delay → ReturnToLobby (RunModifiers.Reset) → TeleportAllToLobby

HordeMode:
  GameStateManager: PREPARING → DEFENDING
    → HordeModeSpawner.Start() (phase-based infinite spawning)
    → Vote loop: every 45s, alternating Supply / Threat (7 + 7)
    → RunModifiers accumulate from voted cards
    → RUN_DURATION (630s) elapses
      → hordeRunActive = false (vote loops exit)
      → HordeModeSpawner.Stop()
      → MobAI.IsAnyMobAlive() polling
      → RunModifiers.Reset()
      → GameStateManager.TriggerVictory()
      → 10s delay → ReturnToLobby → TeleportAllToLobby
```

### Teleport Flow

```
Lobby:
  MainMenu → MatchmakingHandler → MatchmakingManager.QueueForMode
    → TryFormMatch (enough players?)
    → StartCountdown (5s)
    → LaunchMatch
      → TeleportManager.TeleportToGameMode(players, { modeId, difficulty, partyData })
        → TeleportService:TeleportAsync (with TeleportData)

LaneDefense:
  Bootstrap → TeleportDataReader.ProcessPlayer(player)
    → Read TeleportData → store difficulty, party, mode
    → MobSpawner.SetDifficulty(tierName)

  Post-match → GameStateManager.ReturnToLobby
    → ReturnTeleporter.TeleportAllToLobby()
      → TeleportService:TeleportAsync back to lobby
```

---

## 47. File Tree Reference

```
RobloxDefense/
├── foreman.toml                    # Tool version pins (Rojo, Wally)
├── wally.toml                      # Package dependencies
├── lanedefense.project.json        # Rojo project: LaneDefense place
├── lobby.project.json              # Rojo project: Lobby place
├── sourcemap.json                  # Rojo sourcemap
│
├── docs/
│   ├── GAME_DOCUMENTATION.md       # This file — complete technical reference
│   ├── COSMETICS.md                # Cosmetic & animation system
│   ├── BALANCE_NUMBERS.md          # Canonical gameplay number reference
│   └── REVISION_TRACKER.md         # Open bugs, stubs, and design decisions
│
├── Packages/                       # Wally-installed dependencies
│   ├── React.lua
│   ├── ReactRoblox.lua
│   └── _Index/                     # Transitive dependencies
│
└── src/
    ├── shared/                     # Code shared by both places
    │   ├── ReplicatedStorage/
    │   │   └── Shared/
    │   │       ├── init.lua                # GameStates, Scenes, ClassNames, etc.
    │   │       ├── DifficultyConfig.lua
    │   │       ├── AchievementConfig.lua
    │   │       ├── TalentTreeConfig.lua
    │   │       ├── ShopConfig.lua
    │   │       ├── ConsumableConfig.lua
    │   │       ├── AccessoryConfig.lua
    │   │       ├── GearRating.lua
    │   │       ├── SharedGeometry.lua
    │   │       ├── ClassDescriptions.lua
    │   │       └── EmoteConfig.lua         # Canonical emote definitions (shared)
    │   │
    │   ├── ServerScriptService/
    │   │   └── Modules/
    │   │       ├── PlayerDataConfig.lua
    │   │       ├── ClassConfig.lua
    │   │       ├── CharacterConfig.lua
    │   │       ├── WeaponConfig.lua
    │   │       ├── ArmorConfig.lua
    │   │       ├── WaveConfig.lua
    │   │       ├── DropTableConfig.lua
    │   │       ├── StatusEffectTypes.lua
    │   │       ├── CosmeticConfig.lua
    │   │       ├── AnimationConfig.lua
    │   │       ├── ProjectileConfig.lua
    │   │       ├── GameModeConfig.lua
    │   │       ├── ChapterConfig.lua
    │   │       ├── ClassMasteryConfig.lua
    │   │       ├── AuctionConfig.lua
    │   │       ├── CardRegistry.lua            # 30 card definitions (3 pools)
    │   │       ├── RunModifiers.lua            # Per-run modifier scalars
    │   │       ├── VoteManager.lua             # Vote lifecycle server module
    │   │       │
    │   │       ├── NetworkManager/init.lua
    │   │       ├── PlayerDataManager/
    │   │       │   ├── init.lua
    │   │       │   ├── PlayerLevelSystem.lua
    │   │       │   ├── PlayerStatSystem.lua
    │   │       │   ├── PlayerClassSystem.lua
    │   │       │   └── PlayerBonusSystem.lua
    │   │       ├── BonusManager.lua
    │   │       ├── BonusExpSystem.lua
    │   │       ├── CurrencyManager.lua
    │   │       ├── ResourceManager.lua
    │   │       ├── ClassManager.lua
    │   │       ├── StatsManager/init.lua
    │   │       ├── GameStateManager.lua
    │   │       ├── SharedEventHandlers.lua
    │   │       ├── MonitoringSystem.lua
    │   │       ├── ElementalSystem.lua
    │   │       ├── EquipmentHandler.lua
    │   │       │
    │   │       ├── AttackHandler/
    │   │       │   ├── init.lua
    │   │       │   └── DamageHandler.lua
    │   │       ├── HitTracker.lua
    │   │       ├── KillRewardManager.lua
    │   │       ├── DropManager.lua
    │   │       │
    │   │       ├── SkillManager/
    │   │       │   ├── init.lua
    │   │       │   └── SkillExecutor.lua
    │   │       ├── SkillEffects.lua
    │   │       ├── SkillRegistry.lua
    │   │       ├── ClassSkills/
    │   │       │   ├── BaseSkills.lua
    │   │       │   ├── AegisSkills.lua
    │   │       │   ├── ArcanistSkills.lua
    │   │       │   ├── HunterSkills.lua
    │   │       │   └── LifeStewardSkills.lua
    │   │       ├── ClassBehaviors/
    │   │       │   ├── AegisBehavior.lua
    │   │       │   ├── ArcanistBehavior.lua
    │   │       │   ├── HunterBehavior.lua
    │   │       │   └── LifeStewardBehavior.lua
    │   │       │
    │   │       ├── WeaponManager/
    │   │       │   ├── init.lua
    │   │       │   ├── WeaponXPSystem.lua
    │   │       │   ├── WeaponTierSystem.lua
    │   │       │   ├── WeaponRefinementSystem.lua
    │   │       │   ├── WeaponBonusSystem.lua
    │   │       │   └── WeaponRegistry.lua
    │   │       ├── ClassWeapons/
    │   │       │   ├── AegisWeapon.lua
    │   │       │   ├── ArcanistWeapons.lua
    │   │       │   ├── HunterWeapons.lua
    │   │       │   └── LifeStewardWeapons.lua
    │   │       │
    │   │       ├── ArmorManager/
    │   │       │   ├── init.lua
    │   │       │   ├── ArmorXPSystem.lua
    │   │       │   ├── ArmorTierSystem.lua
    │   │       │   ├── ArmorRefinementSystem.lua
    │   │       │   ├── ArmorBonusSystem.lua
    │   │       │   └── ArmorRegistry.lua
    │   │       ├── ClassArmors/
    │   │       │   ├── AegisArmor.lua
    │   │       │   ├── ArcanistArmor.lua
    │   │       │   ├── HunterArmor.lua
    │   │       │   └── LifeStewardArmor.lua
    │   │       │
    │   │       ├── MobSpawner.lua
    │   │       ├── MobAI.lua
    │   │       ├── MobRegistry.lua
    │   │       ├── MobSkillRegistry.lua
    │   │       ├── Mobs/
    │   │       │   ├── Zombie.lua
    │   │       │   ├── Troll.lua
    │   │       │   └── Ogre.lua
    │   │       ├── MobBehaviors/init.lua
    │   │       ├── MobSkills/
    │   │       │   ├── Enrage.lua
    │   │       │   ├── Roar.lua
    │   │       │   └── GroundSlam.lua
    │   │       │
    │   │       ├── DefenseLine/
    │   │       │   ├── init.lua
    │   │       │   ├── DefenseConfig.lua
    │   │       │   ├── DefenseHealth.lua
    │   │       │   ├── DefenseDetection.lua
    │   │       │   ├── DefenseCombo.lua
    │   │       │   └── DefenseAnimation.lua
    │   │       │
    │   │       ├── NPCManager/
    │   │       │   ├── init.lua
    │   │       │   ├── NPCRegistry.lua
    │   │       │   ├── ShopHandler.lua
    │   │       │   ├── QuestHandler.lua
    │   │       │   ├── LoreHandler.lua
    │   │       │   ├── TeleportHandler.lua
    │   │       │   ├── MatchmakingHandler.lua
    │   │       │   └── WeaponSmithHandler.lua
    │   │       │
    │   │       ├── TalentManager.lua
    │   │       ├── TalentEffectAggregator.lua
    │   │       ├── TalentTreeValidator.lua
    │   │       ├── AchievementManager.lua
    │   │       ├── InventoryManager.lua
    │   │       ├── DailyLoginManager.lua
    │   │       ├── ShopManager.lua
    │   │       ├── LeaderboardManager.lua
    │   │       │
    │   │       ├── CosmeticManager/
    │   │       │   ├── init.lua
    │   │       │   ├── PlayerCosmeticManager.lua
    │   │       │   └── MobCosmeticManager.lua
    │   │       ├── VisualEquipmentManager.lua
    │   │       ├── DeathSystem.lua
    │   │       └── AdminTesting.lua
    │   │
    │   ├── ServerStorage/
    │   │   └── Models/
    │   │       └── Weapons/            # Weapon visual templates
    │   │
    │   └── StarterPlayer/
    │       └── StarterPlayerScripts/
    │           ├── Modules/
    │           │   ├── NetworkManager.lua       (client)
    │           │   ├── InputSystem/init.lua
    │           │   ├── CameraSystem/init.lua
    │           │   ├── MovementSystem/init.lua
    │           │   ├── PlayerAttack.lua
    │           │   ├── SkillInput.lua
    │           │   ├── SkillVisuals.lua
    │           │   ├── MobVisuals.lua
    │           │   ├── DamageNumbers.lua
    │           │   ├── AnimationSystem/init.lua
    │           │   ├── CosmeticClient.lua
    │           │   ├── TalentClient.lua
    │           │   ├── AchievementClient.lua
    │           │   ├── LootNotification.lua
    │           │   ├── ResourceCache.lua
    │           │   ├── SceneController.lua
    │           │   ├── NPCInteraction.lua
    │           │   ├── ClientProjectile.lua
    │           │   ├── ClassCatalog.lua
    │           │   ├── Locale.lua
    │           │   └── SoundManager.lua
    │           └── UI/
    │               ├── HUD.lua
    │               ├── ClassMenu.lua
    │               ├── StatsMenu.lua
    │               ├── TalentTreeUI.lua
    │               ├── EquipmentUI.lua
    │               ├── CharacterCreation.lua
    │               ├── WardrobeUI.lua
    │               ├── AchievementsUI.lua
    │               ├── GlobalShopUI.lua
    │               ├── SettingsUI.lua
    │               ├── TestingUI.lua
    │               ├── DeathUI.lua
    │               └── VoteUI.lua              # Card vote overlay (React)
    │
    ├── lobby/                          # Lobby-specific code
    │   ├── ServerScriptService/
    │   │   ├── LobbyMain.server.lua
    │   │   └── Modules/
    │   │       ├── PartyManager.lua
    │   │       ├── MatchmakingManager.lua
    │   │       ├── SceneManager.lua
    │   │       ├── TeleportManager.lua
    │   │       └── LobbyNPCRegistry.lua
    │   └── StarterPlayer/
    │       └── StarterPlayerScripts/
    │           ├── LobbyClient.client.lua
    │           └── UI/
    │               ├── LobbyApp.lua
    │               ├── MainMenu.lua
    │               ├── MatchmakingUI.lua
    │               ├── NPCDialog.lua
    │               ├── ShopUI.lua
    │               ├── WeaponSmithUI.lua
    │               ├── EmoteWheel.lua
    │               ├── SocialPanel.lua
    │               └── PartyInviteToast.lua
    │
    └── lanedefense/                    # LaneDefense-specific code
        ├── ServerScriptService/
        │   ├── LaneDefenseMain.server.lua
        │   └── Modules/
        │       ├── TeleportDataReader.lua
        │       └── ReturnTeleporter.lua
        └── StarterPlayer/
            └── StarterPlayerScripts/
                ├── LaneDefenseClient.client.lua
                └── UI/
                    ├── LaneDefenseApp.lua
                    ├── BattleClassUI.lua
                    └── TeammateVitals.lua

    ├── hordemode/                      # Horde Mode-specific code
    │   ├── ServerScriptService/
    │   │   ├── HordeModeMain.server.lua
    │   │   └── Modules/
    │   │       ├── HordeModeSpawner.lua
    │   │       └── HordePauseManager.lua
    │   └── StarterPlayer/
    │       └── StarterPlayerScripts/
    │           ├── HordeModeClient.client.lua
    │           └── UI/
    │               └── HordeModeApp.lua

    └── socialplaza/                    # Social Plaza-specific code
        ├── ServerScriptService/
        │   └── SocialPlazaMain.server.lua
        └── StarterPlayer/
            └── StarterPlayerScripts/
                ├── SocialPlazaClient.client.lua
                └── UI/
                    ├── SocialPlazaApp.lua
                    └── EmoteWheel.lua
```

---

> **Open issues, bugs, and design decisions** are tracked in [REVISION_TRACKER.md](REVISION_TRACKER.md).

---

## 48. Debug Flags & Testing

### Server-Side Debug Flags

| Flag | File | Default | Effect |
|------|------|---------|--------|
| `DEBUG_NO_SAVE` | PlayerDataManager/init.lua | `false` | Skips DataStore reads/writes |
| Admin allowlist | PlayerDataConfig.AdminUserIds | `{}` | UserIds that can use debug commands |

### Admin Debug Commands

Fired via `DebugCommand` RemoteEvent (admin-only):

| Command | Place | Effect |
|---------|-------|--------|
| `testDamage` | LaneDefense | `DefenseLine.TestDamage()` |
| `healLine` | LaneDefense | `DefenseLine.Heal(9999)` |
| `setLineHP` | LaneDefense | `DefenseLine.SetHealth(amount)` |
| `skipWave` | LaneDefense | `MobSpawner.ForceCompleteWave()` |
| `addXP` | Both | `PlayerLevelSystem.AddExperience(player, amount)` |

### Testing UI

`TestingUI.lua` — React component for admin panel, visible only to admin users. Provides buttons for common debug operations.

---

*End of documentation.*
