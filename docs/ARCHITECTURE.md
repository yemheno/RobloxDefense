# Architecture

How the code is put together, the house patterns every change follows, and what was decided against. Mechanics per system are in [SYSTEMS.md](SYSTEMS.md); numbers in [BALANCE_NUMBERS.md](BALANCE_NUMBERS.md).

**Contents:** [Places and boot](#places-and-boot) · [Network](#network) · [ReadyGate events](#readygate-events) · [BonusManager sources](#bonusmanager-sources) · [House patterns](#house-patterns) · [Decided against](#decided-against) · [Data and persistence](#data-and-persistence) · [Scaling](#scaling) · [UI](#ui) · [Ownership map](#ownership-map) · [Data flow](#data-flow) · [File tree](#file-tree) · [Debug and admin](#debug-and-admin)

---

## Places and boot

Five Roblox places share `src/shared/`. Each has its own `<place>.project.json` and bootstrap script.

| Place | PlaceId | Bootstrap | Place-only modules | Combat? |
|---|---|---|---|---|
| Lobby | 115774137563700 | `lobby/.../LobbyMain.server.lua` | PartyManager, MatchmakingManager, SceneManager, TeleportManager, LobbyNPCRegistry | No |
| LaneDefense | 138768963731267 | `lanedefense/.../LaneDefenseMain.server.lua` | — (uses DefenseLine, MobSpawner) | Yes |
| HordeMode | 115735968204052 | `hordemode/.../HordeModeMain.server.lua` | HordeModeSpawner, HordePauseManager, HordeModeMapLoader | Yes |
| CentralBoss | 100848838772974 | `centralboss/.../CentralBossMain.server.lua` | BossEncounter, PlaceholderRig | Yes (hidden, §AGX/X19) |
| SocialPlaza | 103512111921765 | `socialplaza/.../SocialPlazaMain.server.lua` | — | No |

PlaceIds live once, in `ReplicatedStorage/Shared/init.lua` (`Shared.PlaceIds`).

**Boot rules**

- Every Main uses `PlaceBootstrap` (`ctx.Load`, `ctx.RequireLoaded`, `ctx.IsAdmin`, `ctx.MakeContext`) and `PlaceLifecycle` (`WireOnPlayerReady`, `StartVitalsLoop`). No copy-pasted boot code in Mains.
- Modules expose `Init()` (and `LateInit()` when they need modules loaded later). The Main calls them in a fixed order; nothing relies on `require` order.
- **Critical Init fails hard** (§AGX/X16): if a module loaded with `RequireLoaded` throws in `Init()`, boot errors. Don't wrap it back into a warning.
- `WaitForChild("Modules", 10) or error(...)` in every Main (G3): loud at boot, never a silent hang.
- `WireOnPlayerReady` has a module-level latch (§T0P2/X14). Class innate bonuses are **not** in that chain; `ClassManager.Init` owns them.
- Shared modules never check `game.PlaceId`. Place behaviour comes from what the Main loads.
- Combat places are **one run per server** (T0P2-DQ-C): reserved servers, no restartable loops.

## Network

- `NetworkManager` (server and client) owns one **EVENTS manifest**. Every RemoteEvent is declared there with a `rateLimit` and a `readyGated` flag. The manifest is the source of truth; don't document event payloads elsewhere.
- **Rate limits:** fixed 1 s window per player per event, default 30/s, per-event overrides (§NM-D1, §SCALE/S6). Values: [BALANCE § Networking](BALANCE_NUMBERS.md#networking-and-monitoring).
- **No RemoteFunctions, no `InvokeClient`.** Client input is advisory; the server re-checks range, cooldown, resource and state.
- **Client deferred listeners:** the client subscribes before the event exists and binds when it appears. A 15 s `ServerReady` watchdog shows a Rejoin banner (§NM-D6).
- **Studio-only events** (`AdminAction`, `DebugCommand`, `ModifySystemStat`): never created outside Studio (§AGX/SEC).
- `readyGated` is **documentation only**. The manifest can't auto-route (circular require), and `IsReadyGated` has no callers. Routing happens at the call site ([ReadyGate pushes](#readygate-pushes)).

## ReadyGate events

Source of truth: the `ReadyGate.FireClient` call sites, not the manifest flag (C11). Corrected list at `24c4d7e`:

| Event | Fired by | Manifest flag |
|---|---|---|
| `ServerReady` | `PlaceLifecycle` (loading-screen dismiss) | `false` ⚠ |
| `CharacterCreationRequired` | `CharacterManager` first-login check | — |
| `WeaponEquipped` / `ArmorEquipped` | `EnsureStarterWeapon` / `EnsureStarterArmor` | — |
| `AchievementUnlocked` | `AchievementManager`; also the class-unlock toast (`PlayerClassSystem`) | — |
| `TalentStateUpdate` | `TalentManager.SendState` | — |
| `SkillCooldownUpdate` | `SkillManager.SetupPlayer` initial push only; per-cast updates are plain `FireClient` | `true` |
| `GameStateChanged` | Horde late-join push (`HordeModeMain`) | `false` ⚠ |
| Defense-line state | `DefenseHealth.SendStateToPlayer` (§T4/V3) | — |

⚠ = flag disagrees with the call site; fix in the comment pass (`§DOCS/C11` in [BACKLOG](BACKLOG.md)).

**Not gated, by design:** `WardrobeUpdate` and `EquipmentInfo` are request/response (the client subscribes before it asks). **Bypass list** inside ReadyGate (high-frequency ticks): `VitalsUpdate`, `CurrencyUpdate`, `ResourceUpdate`, `StatsUpdate`, `PlayerInfoUpdate`. **Overflow** (queue cap) kicks the player for a resync (T0P2-DQ-A).

## BonusManager sources

Source of truth: the header of `BonusManager.lua`. Each source is an isolated `{ stat = value }` table; `Recalculate` sums them into `data.Bonus` in one pass. Writes to stats not in `PlayerDataConfig.BonusStats` are warned once and rejected.

| Source key | Written by | Cleared |
|---|---|---|
| `weapon`, `armor` | `PlayerBonusSystem.ApplyWeaponBonuses` / `ApplyArmorBonuses` | on re-apply |
| `buff` | `SkillManager` buff apply/expire | on expire |
| `talent` | `TalentEffectAggregator` | on respec/allocate |
| `achievement` | reserved (§DISC/D5, core-planned) | — |
| `innate` | `ClassManager.ApplyInnateBonus` | on class switch |
| `acc_trinket`, `acc_ring1`, `acc_ring2` | `InventoryManager` | on unequip |
| `other` | `PlayerBonusSystem.SetBonus` / `ModifyBonus` (ad-hoc, debug) | — |
| `timed_<tag>` | `BonusManager.AddTimedBonus` (card buffs); re-apply refreshes | auto-expire |
| `timed_consumable_<itemId>` | `ConsumableEffects` (§AGX/X10b) | auto-expire, leave |
| `aura_<UserId>` | `StatsManager/PartyAura` on a party **member**, keyed by the aura owner (§AGX/X11) | range/death/leave |
| `keystone` | `StatsManager/KeystoneRules` (Last Bastion move penalty) | when the condition ends |

`SetupPlayer` pre-creates the fixed keys; the others are created on first write. **Adding a key:** give it a documented owner and add it to the `BonusManager.lua` header (the header currently omits `keystone`: `§DOCS/C12`).

---

## House patterns

Pattern consistency is a rule: when a clean pattern lands in one module, port it everywhere it applies. Each pattern has a stable anchor; code comments cite `ARCHITECTURE.md#<anchor>`.

### Janitor per player

`Janitor` is the lifetime primitive (connections, instances, threads, functions, objects with `Destroy`/`Disconnect`; keyed slots; safe after `Destroy`). Per-player connections go in a weak-keyed map of Janitors, destroyed on `PlayerRemoving`. Give the Janitor a label (`Janitor.new("Module.player")`) so `JanitorTelemetry` can count it.

```lua
local playerJanitors = setmetatable({}, { __mode = "k" })
local function getPlayerJanitor(player)
    local jan = playerJanitors[player]
    if not jan then jan = Janitor.new("MyModule.player"); playerJanitors[player] = jan end
    return jan
end
-- setup:          getPlayerJanitor(player):Add(player.CharacterAdded:Connect(fn))
-- PlayerRemoving: local jan = playerJanitors[player]; if jan then jan:Destroy(); playerJanitors[player] = nil end
```

Guard against double wiring when a player joins during `Init` (both the `PlayerAdded` handler and the existing-players loop fire): that was the root cause of `§VEM-DEDUPE`.

### Janitor per character

Per-character state uses a fresh Janitor with `jan:LinkToInstance(character)`, so it tears itself down on respawn or leave.

### Lazy getter

Sibling modules are resolved lazily, once. `false` means "looked, not found" so later calls short-circuit.

```lua
local _WeaponManager
local function getWeaponManager()
    if _WeaponManager ~= nil then return _WeaponManager or nil end
    local mod = Modules:FindFirstChild("WeaponManager")
    local ok, result = false, nil
    if mod then ok, result = pcall(require, mod) end   -- two steps: see the pitfall below
    _WeaponManager = (ok and result) or false
    return _WeaponManager or nil
end
```

**Never** write `local ok, r = mod and pcall(require, mod)`: `and` truncates `pcall`'s results to one value, so `ok = true` and `r = nil`, and the getter returns nil forever. Eleven getters shipped like that (§AGX/D-FIX).

### Hot-path ref cache

For functions called per tick or per hit, resolve the module once and cache the **function reference**, not just the module. After that it's a plain call. Used in ResourceManager, KeystoneRules, SkillManager stat readers, MobAI `CapStat`.

### ReadyGate pushes

Any server push that can fire during boot (PlayerAdded, `OnPlayerDataReady`, equipment setup) goes through `ReadyGate.FireClient(player, event, ...)`, not `NetworkManager.FireClient`. Update the [ReadyGate list](#readygate-events) and the manifest flag in the same change.

### Single source of truth

One module owns a catalog; the others read derived helpers. Example: `ClassConfig.Classes` owns `default` and `unlockRequirements`; `PlayerDataConfig` fills `UnlockedClasses` / `ClassUnlockRequirements` from it at the bottom of the file (they are `nil` at definition on purpose). `PlaceIds`, `StatCaps`, `GearUpgradeConfig` and `ShopConfig` follow the same rule.

### Loud at boot

Typos, missing modules and schema mismatches `warn` or `error` at load time (ClassConfig `validate()`, BonusManager stat validation, TalentTreeValidator), never degrade silently at runtime.

### Stale-callsite grep

After deleting or renaming a field or function, grep all of `src/` for the old name. Zero hits outside `DEPRECATED_KEY_PATHS` is the pass criterion. Removed save fields go on the deprecated-key sweep in `PlayerDataManager/init.lua`.

### Schema parity

`PlayerDataConfig.AccountDefaults` and the fresh-spawn skeleton in `PlayerDataManager/init.lua` must match key for key.

### Tag every fix

Code comments carry a `§`-tag so lineage can be grepped: see [CLAUDE.md](../CLAUDE.md#tags) for the convention and [HISTORY § Tag index](HISTORY.md#tag-index) for where each family is explained.

---

## Decided against

Discussed and decided **against**. Don't reopen unless Pablo brings it up. From `Audit_4.7.md` §10, verbatim in substance, plus the seams kept on purpose.

- **Don't "simplify" the hair-accessory weld dance** in CharacterManager. The five-step pattern (read AccessoryWeld values BEFORE clone, destroy pre-existing welds, parent, wait a frame, overwrite Part0/Part1/C0/C1) is what made hair AND held weapons reliable. The comment in the file explicitly forbids modification.
- **Don't run `git commit`** from an agent session. Pablo commits from his terminal after testing in Studio.
- **Don't add a `Validate()` patch for `statDerivation`** without Pablo's preferred "expand the stats table" approach. The DerivedStats catalog lives in `PlayerDataConfig` with `required` booleans, and `ClassConfig.validate` consumes it.
- **Don't put per-class resource definitions into ClassConfig.** Resources are owned by `ClassBehavior.CONFIG`; the bare `resource = "..."` was removed from every ClassConfig entry.
- **Don't remove the empty `Init()` stubs in ClassBehaviors.** Pablo prefers documented seams over removal.

**Seams kept on purpose** (don't "clean up"):

- `PlayerDataManager.DeallocateStat` (§T0P2/X22): planned single-point dealloc (`§T0P2-DEALLOC`).
- The `TeleportClass` attribute path (§T0P2-TPCLASS), now consumed by `ClassManager.ApplyTeleportClass`.
- Empty client `ServerReady` handlers (loading-screen hook).
- `ReadyGate.OnReady` (server-side seam, no callers).
- The `"achievement"` BonusManager source (§DISC/D5).
- `SetHordeGlobalSpeedMult` (only called with 1.0; §T3/W6).
- `.rbxmx` assets are **place-managed**; `*.rbxmx` in `.gitignore` is correct (G1). Don't re-flag untracked models.
- The AttackShapes **workspace-root scan** finds player characters; it is load-bearing (also scan `workspace.Mobs` for mobs, never instead of root).
- Horde spawn markers are resizable Parts by design (§T3/W9b).
- `HealingSystem` reads the `Damage` stat as healing power (design intent; split tracked as `§T1.3-DQ2`).

---

## Data and persistence

- `PlayerDataManager` owns all player data (DataStore `PlayerData_v1`, key per UserId) with four child systems: `PlayerLevelSystem`, `PlayerStatSystem`, `PlayerClassSystem`, `PlayerBonusSystem`.
- **Session lock** (§AGX/X3): loads and saves use `UpdateAsync` with a `{ jobId, time }` lock. A load waits up to `LOCK_WAIT_MAX` for another live server's lock; a lock older than `LOCK_STALE_AFTER` may be taken over. Constants at the top of `PlayerDataManager/init.lua`.
- **Saves:** autosave every `AUTO_SAVE_INTERVAL`, a lock-releasing save on leave with retries, and a `BindToClose` drain that waits for in-flight leave-saves (§AGX/X2).
- **Load failure kicks** the player; they never play on defaults. Leaving mid-load is guarded (§T0P2/X3).
- **Defaults are deep-copied** per player (§T0P2/X1) and deep-merged onto the saved blob, so new fields appear automatically; removed fields go on `DEPRECATED_KEY_PATHS`.
- **Receipts** (Robux) are recorded in the same save as the grant ([DESIGN_DECISIONS § Monetization](DESIGN_DECISIONS.md#monetization)).
- **Difficulty** is owned by the Lobby, validated on arrival, resolved once from the first arrival and immutable after (T0P2-DQ-B).

## Scaling

From the §SCALE audit (future modes: world boss 20–30 players, massive horde 150–250 mobs, siege 30+ players).

- **Doctrine ("smart frames"):** every recurring cost is bounded by a **cap, a window or a budget**, never by how intense the fight is. Examples: DamageNumberBatch 0.1 s window (§PERF/F5), pooled and capped client numbers (§PERF/F6), one shared per-frame mob snapshot (§PERF/F1), DoT/HoT numbers batched every 0.25 s (§SCALE/S5), XP HUD pushes coalesced the same way (§AGX/X22), range-scoped mob casts and deaths (150 studs, §SCALE/S2–S3).
- **The hard wall:** each mob is a server-simulated Humanoid (~0.05–0.15 ms per frame each). The practical budget is ~100–150 live mobs; Horde's alive cap is tuned under it. A 250-mob mode needs lightweight custom movers for trash mobs (`§SCALE-WALL`). Mob physics is server-owned (§AGX/X45); if a full Horde is over budget, flip `MobSpawnHelper.SERVER_OWNED_TIERS.normal`.
- **Load-bearing detail:** SkillEffects keys direct effects so a second player's DoT overwrites instead of stacking. That keeps ticks O(mobs), not O(mobs × players). Remember it if stacking is ever redesigned.
- Open items: `§SCALE-D1…D7` in [BACKLOG](BACKLOG.md).

---

## UI

React-lua 17 is canonical (§T10/STACK). The old `StarterGui/AppGui` static stack is disabled via meta files and waits for an archive PR.

One shell, the same in every place (built in the UI revamp P0–P7; spec: [`ui_audit/shell-spec.md`](ui_audit/shell-spec.md)):

| Piece | Where | What it does |
|---|---|---|
| **Theme v2 tokens** | `UI/Common/Theme.lua` | Semantic colours (`surface.*`, `text.*`, `accent.*`, `state.*`), type scale with min/max, spacing, radii, strokes, fixed layers with DisplayOrder bands (HUD < windows < modals < toasts < tooltips), icon/image registry. No `Color3.fromRGB` literals in screens |
| **FormFactor / UIScale** | `UI/Common/useFormFactor.lua`, `UIScaleRoot.lua` | Phone / Tablet / Desktop / Console from the viewport and last input; fixed sizes at phone scale plus one root `UIScale` per form factor (UI-D2). Tap targets ≥44 px |
| **Components** | `UI/Common/*` | `Text`, `Button`, `IconButton`, `AppWindow` (sheet on phone, window elsewhere), `Panel`, `Tabs`, `Bar`, `Card`, `CurrencyPill`, `Modal`, `Tooltip` + `usePressHold`, `SafeArea`, `SkillPad`, `ActionBar`; `_Showcase` mounts them all |
| **Registry** | `UI/Shell/Registry.lua` | One menu table, same order in every place; entries that don't apply show locked, not hidden |
| **PanelStack** | `UI/Shell/PanelStack.lua`, `PanelHost.lua`, `ServerOpen.lua` | One panel open at a time; server-opened panels (NPCs, character creation) go through it; switches input to the `"UI"` context so skills don't fire behind menus; ✕ / Backspace / B close the top panel; the HUD is hidden, never unmounted |
| **Menu surfaces** | `UI/Shell/MenuRail`, `MenuSheet`, `MenuRadial`, `MenuFlyout` | Desktop icon rail + flyouts, phone ☰ sheet, gamepad radial (UI-D3) |
| **Input contexts** | client `InputSystem` | `Combat`, `Lobby`, `UI`; B = Dash in Combat, Back in UI |

### Notify

One feedback system, four kinds, each with one region and one timing: **toast** (top-right, queued), **banner** (top-centre, one slot, priority queue), **feed** (right side: killfeed, loot, keystone lines), **inline** (`useRequest`: pending/ok/timeout/error inside a panel). Client `UI/Common/Notify.lua`; server `NotifyService` pushes one `Notify` event. Never add a new ad-hoc toast.

### HUD regions

`UI/HUD/*` split `HUD.lua` into regions with one per-form-factor layout table (`HUD/Layout.lua`): vitals top-left; banner or boss bar top-centre; menu and currencies top-right; party left-middle; feeds and objectives right-middle; action bar bottom-centre (PC) or skill arc bottom-right (phone). Region state goes through `HUD/Store.lua` and a documented attribute contract (shell-spec §4.3).

### Gamepad

`UI/Common/GamepadFocus.lua` and `UI/Shell/GamepadNav.lua`: one focus ring, SelectionGroups per panel, first-focus hooks from PanelStack, LB/RB for tabs, right stick scrolls lists while a panel is open.

---

## Ownership map

Solo-owner project (Pablo). Boundaries follow the folder layout.

| Layer | Modules |
|---|---|
| Server core | PlayerDataManager, NetworkManager + manifest, ReadyGate, PlaceBootstrap/Lifecycle, Janitor |
| Stats | StatsManager (Damage, Armor, Critical, Healing, KeystoneRules, PartyAura), BonusManager, ClassManager, ResourceManager |
| Combat | AttackHandler, SkillManager, SkillEffects, ClassSkills, HitTracker, KillRewardManager, DropManager |
| Mobs | MobAI, MobSpawner (Lane), HordeModeSpawner, MobSpawnHelper, MobRegistry, BossEncounter |
| Game flow | DeathSystem, GameStateManager, DefenseLine, VoteManager, CardRegistry, RunModifiers |
| Meta | Shop, Currency, Talents, Achievements, Inventory, Consumables, DailyLogin, Leaderboard, Monetization |
| Lobby | PartyManager, PartyRequirements, MatchmakingManager, TeleportManager, SceneManager, NPCManager |
| Client UI | react-lua components, Shell, HUD regions, Theme v2 |
| Legacy (disabled) | `StarterGui/AppGui` |

## Data flow

**Basic attack.** Client `PlayerAttack` plays the animation and detects hits locally (`SharedGeometry` for melee, `ClientProjectile` for ranged) → `AttackEvent` + `PlayerHitReport` → server `AttackHandler` checks ticket, cooldown, server-side range and alive state → `DamageHandler.DamageMob` → `StatsManager` pipeline → `HitTracker` (combo, per-hit callbacks: ResourceManager, Achievements, KeystoneRules) → on kill `KillRewardManager` (party XP, weapon XP, personal drops, kill callbacks, range-scoped `MobDeath`).

**Mob attacks.** MobAI broadcasts a cast to nearby clients; the targeted client reports a hit after the damage delay; the server validates the cast id and target, then applies `CalculateIncomingDamage`.

**Class switch.** `RequestClassSwitch` → cooldown and in-combat checks → `ClassManager.SetClass` → resource reset, starter weapon/armor, visuals, cosmetics, innate bonuses, weapon bonuses, stat recalc.

**Talent allocate.** `AllocateTalent` → `TalentManager` checks (adjacency, cost, level) → `TalentEffectAggregator` writes the `talent` source → `BonusManager.Recalculate`.

**Lane run.** Start gate (all roster clients ready and data loaded, or timeout) → `Defending` → `MobSpawner` waves (pre-spawn hook waits on the tactical vote) → all waves → Victory → return. **Horde run:** gate → spawner + alternating vote loop (pauses the world) → run timer → mob clear → Victory → return.

**Teleport.** Lobby matchmaking → `TeleportManager` reserves a server and sends `{ modeId, difficulty, partyData }` → `TeleportDataReader` validates on arrival (place's own modeId wins, level floor re-checked, public servers bounced) → `ReturnTeleporter` back to `Shared.PlaceIds.Lobby`.

## File tree

Regenerated at `24c4d7e`: 301 `.lua` files. Directory level; counts are `.lua` files directly in the folder.

```
src/
├── shared/
│   ├── ReplicatedStorage/Shared/ (12)       configs shared with clients: Achievement, Talent, Shop,
│   │                                         Consumable, Accessory, Difficulty, Emote, GearRating,
│   │                                         SharedGeometry, BootProfiler, ClassDescriptions, init (PlaceIds)
│   ├── ServerScriptService/Modules/ (68)    server systems (depth 1)
│   │   ├── ArmorManager/ (4)  AttackHandler/ (2)  ClassArmors/ (4)  ClassBehaviors/ (4)
│   │   ├── ClassSkills/ (5)   ClassWeapons/ (4)   CosmeticManager/ (3)  DefenseLine/ (6)
│   │   ├── MobBehaviors/ (3)  MobSkills/ (2)      Mobs/ (4)            NPCManager/ (8)
│   │   ├── PlayerDataManager/ (5)  SkillManager/ (1)  StatsManager/ (7)  WeaponManager/ (5)
│   ├── StarterPlayer/StarterPlayerScripts/
│   │   ├── Modules/ (19) + AnimationSystem/ (1) CameraSystem/ (5) InputSystem/ (2) MovementSystem/ (7)
│   │   └── UI/ (20 screens) + Common/ (25) HUD/ (14) Shell/ (15)
│   └── StarterGui/AppGui/Controllers/ (4)   legacy, Disabled
├── lobby/        ServerScriptService (Main + 5 Modules), StarterPlayerScripts (2 + Modules 2 + UI 8)
├── lanedefense/  ServerScriptService (Main), StarterPlayerScripts (2 + UI 1)
├── hordemode/    ServerScriptService (Main + 3 Modules), StarterPlayerScripts (2 + UI 1)
├── centralboss/  ServerScriptService (Main + 2 Modules), StarterPlayerScripts (2 + UI 2)
└── socialplaza/  ServerScriptService (Main), StarterPlayerScripts (2 + UI 1)
```

Regenerate with `find src -type d | while read d; do echo "$d $(find "$d" -maxdepth 1 -name '*.lua' | wc -l)"; done`.

## Debug and admin

- **Admin/debug is Studio-only** (§AGX/SEC): `PlaceBootstrap.IsAdmin` is a single Studio check; `AdminTesting`, `ModifySystemStat` and every `DebugCommand` handler are gated on `IsStudio`; `TestingUI` renders nothing live. `DebugCommand("bossHP", …)` stays for the CentralBoss test.
- **BootProfiler** (`ReplicatedStorage/Shared/BootProfiler.lua`): `ENABLED = false` for shipping; flip it on locally to get the Output report and `BootProfile_SERVER` / `BootProfile_CLIENT` snapshots.
- **Janitor telemetry:** `game:SetAttribute("JanitorTelemetry", true)` prints live counts per label every 60 s. A `*.player` count that keeps climbing after players leave is a leak.
- **MonitoringSystem** logs suspicious patterns (dodge rate, late hit reports, range anomalies). It never kicks or bans; `SAMPLE_RATE` controls cost.
