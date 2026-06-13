# Audit_4.7 — Continuation Handoff

> **Purpose.** Single canonical handoff document for the Roblox Defense
> tier-by-tier audit. Designed to survive context compactification so any
> Claude instance can resume mid-stream without re-deriving project state.
> Read this top-to-bottom on resume.
>
> **Model / branch.** Claude Opus 4.7 (1M context). Repo: `RobloxDefense`,
> branch `dev`. Last canonical commit: **v0.5** (uncommitted T1 work
> staged in working tree).
>
> **Companion doc.** `docs/TODO.md` is the parking lot for every known
> issue / future-work item, organized by subsystem and tagged with
> priority. This document is the procedural / methodological handoff;
> TODO.md is the issue list. Both are needed.

---

## 1. Operating principles

These are Pablo's stated preferences that govern every decision:

1. **No spaghetti unless removal is risky.** When in doubt, simplify. Empty
   API stubs and documented seams stay; magic-number disconnect timers,
   duplicate event handlers, and dead branches die.
2. **One closed system per commit.** Pablo commits manually from his
   terminal at the end of a tier review — not after every micro-fix.
   Live-test happens before commit. We do NOT use `git commit` from this
   session; the sandbox filesystem has previously rejected git object
   writes on large files.
3. **Loud at boot over silent drift.** Catch typos / missing modules /
   schema mismatches with `warn` or `error` at module-load time so they
   surface in dev console rather than silently degrading gameplay.
4. **Single source of truth.** When two configs describe the same thing,
   derive one from the other. Examples landed in T1.2: `UnlockedClasses`
   and `ClassUnlockRequirements` both derive from `ClassConfig.Classes`.
5. **Pattern consistency.** When a new clean pattern lands in one module,
   port it everywhere it applies. The lazy-getter pattern, the Janitor
   primitive, the BonusManager source-isolation model — each was
   introduced once, then propagated.
6. **Modular by feature, not by file size.** Each subsystem has a name
   and a contract. When state belongs to system X, it lives in system X
   — even if another system happens to fire it. (T1.4/R6 example:
   ResourceManager registers on HitTracker's callback registry instead
   of HitTracker hardcoding a dispatcher to ResourceManager.)
7. **Pablo decides design; Claude decides code.** Implementation /
   refactor / structure are Claude's call when the resulting code is
   cleaner. Game balance / gameplay design / mechanic choices are
   Pablo's call. When uncertain whether something is design or
   implementation, surface it as a DQ (design question) rather than
   guessing.

---

## 2. Tier roadmap

The audit walks every subsystem tier-by-tier. Each tier produces:
- a Map (read end-to-end, trace public API + state)
- a Surface (findings sorted by severity, design questions called out)
- an Action set (Pablo confirms / overrides)
- Execution (file edits)
- Sanity check (paren / brace / keyword balance + stale-callsite grep)
- TODO updates (any deferred items)
- Live test by Pablo
- Commit by Pablo

| Tier | Subsystem                                  | Status      | Closed in audit |
|------|---------------------------------------------|-------------|------------------|
| T0   | Cross-cutting (bootstrap, network, ready, persistence) | ✅ Closed | v0.5 + **pass-2 (§T0P2, this commit)** |
| T1.1 | CharacterManager (+ Janitor primitive)      | ✅ Closed | this branch      |
| T1.2 | ClassManager + ClassConfig                  | ✅ Closed | this branch      |
| T1.3 | StatsManager + BonusManager                 | ✅ Closed | this branch      |
| T1.4 | ResourceManager + ClassBehaviors            | ✅ Closed | this branch      |
| T2   | Combat (AttackHandler, HitTracker pass-2, SkillManager)| ⏭ Pending |              |
| T3   | Mob (MobAI, MobSpawner, MobAssetLoader)     | ⏭ Pending  |                  |
| T4   | Death / Game flow (DeathSystem, GameStateManager) | ⏭ Pending |             |
| T5   | Vote / Run modifiers (VoteManager, CardRegistry, RunModifiers) | ⏭ Pending | |
| T6   | Equipment (Weapon/Armor managers, VEM, Registries, Refinement, Tier, BonusSystem) | ⏭ Pending | |
| T7   | Lobby (PartyManager, MatchmakingManager, SceneManager, TeleportManager) | ⏭ Pending | |
| T8   | Progression (PlayerLevelSystem, talent system, achievement, daily login) | ⏭ Pending | |
| T9   | Shop / NPC (ShopManager, NPC handlers, quest, lore) | ⏭ Pending |          |
| T10  | UI (every client React component, CombatApp, Lobby app, panels) | ⏭ Pending | |
| T11  | Cross-cutting follow-ups (Janitor leak audit, balance audit, hang-recovery UI) | ⏭ Pending | |

After T1, commit T1 as a single "T1 — Player state systems" upgrade once
Pablo signs off. Then re-evaluate priority for T2 vs T6 (Pablo may want
combat closed first).

---

## 3. Methodology — how a tier audit runs

This is the canonical procedure. Follow it for every new tier.

### 3.1 Setup

Before opening the first file:
- Create one master `TaskCreate` for the tier ("T1.x XYZ — Map + Surface for review").
- Confirm scope. T1.3 spans 5 files; T1.2 spans 4. Plan reading order.

### 3.2 Map step

Read EVERY file in scope end-to-end. Do not skim. Take notes on:
- Public API surface (every exported function name + signature)
- State holders (every module-scope `local x = {}` that holds runtime state)
- Network events registered (RemoteEvent names)
- PlayerAdded / PlayerRemoving / CharacterAdded handlers
- Module-scope `task.spawn` loops (regen ticks, vote loops, etc.)
- Lazy module references and their pattern (each is either clean or to-fix)
- Cross-module callsites — grep both directions

Use `Grep` aggressively. The codebase is multi-thousand-line Lua; reading
sequentially without cross-referencing misses callsite drift.

### 3.3 Cross-check

For each public function:
- Find every callsite via Grep
- Verify the callers' expectations match the implementation
- Identify dead public API (no callers anywhere)

For each persistent field on a module:
- Verify PlayerRemoving cleanup exists (or the table is weak-keyed `__mode = "k"`)
- Verify writes don't fight reads from elsewhere

For schema fields:
- Cross-reference `PlayerDataConfig.AccountDefaults` with `PlayerDataManager/init.lua`
  freshSpawn skeleton — these MUST match key-for-key.
- Cross-reference `DEPRECATED_KEY_PATHS` list to ensure removed fields are
  swept from old saves.

### 3.4 Surface

Write the findings up for Pablo in a single response. Format:

- Sort by severity (🚨 bug > 🟡 spaghetti > 🟢 minor > ❓ design question)
- Each finding gets an ID: `D1`, `D2`, … or `B1`, `B2`, … etc. — letter
  varies per tier (D for CharacterManager, B for BonusManager,
  R for ResourceManager — first letter of the dominant module name).
- Each finding has: title, location (file:line), one-paragraph
  explanation, proposed fix shape.
- Design questions at the bottom as DQ1, DQ2, …
- Proposed action set at the very bottom listing which items to land.

Pablo will respond per-item with `D1. Yes / No / discuss`. Never ASSUME a
finding is uncontroversial; always wait for sign-off before executing.

### 3.5 Execute

After sign-off:
- Create per-item TaskCreate entries (`T1.x.a D1 — …`, `T1.x.b D2 — …`)
- Mark each in_progress when starting, completed when done
- Make the actual edits via `Edit` / `Write`
- Use the established patterns (Janitor for lifetimes, lazy-getter for
  module refs, etc. — see §5)

### 3.6 Sanity check

Always run:
- Paren / brace / function-end balance check on every touched file
  (the python script in §5.7 is the canonical one)
- Grep for any removed-field name to confirm zero stale callsites

### 3.7 TODO updates

Anything deferred goes into `docs/TODO.md`:
- New section per closure tier (e.g. §14d for T1.3)
- Update the section index
- Tag items `[P0]` `[P1]` `[P2]` `[??]` `[🚀]` `[📝]`
- Add a `§<tier>-<short>` ID for traceability
- If an item closes an old TODO entry, mark it `*(closed by §X)*`

### 3.8 Live test + commit

When the tier is closed and sanity-clean, tell Pablo:
- What landed (per-finding summary)
- Suggested smoke-test paths
- Ready-for-commit signal

Pablo runs live test, then commits from his terminal.

---

## 4. What's already landed (T0 + T1.1 + T1.2 + T1.3 + T1.4)

This is the closed work. Use it as both a reference and a pattern library.

### 4.1 T0 — Closed, committed v0.5

Cross-cutting bootstrap, network, persistence. From session summary (pre-T1):

**New modules:**
- `Modules/PlaceBootstrap.lua` — `ctx.Load`, `ctx.RequireLoaded`,
  `ctx.IsAdmin`, `ctx.MakeContext`. Every place Main uses these to
  eliminate the 400-line copy-paste across the 5 place Main scripts.
- `Modules/PlaceLifecycle.lua` — `WireOnPlayerReady(ctx, opts)` and
  `StartVitalsLoop(ctx)`. Per-player setup chain (talents, accessories,
  stats push, ServerReady) lives here once. NOTE: as of T1.2/D1, class
  innate-bonus apply was REMOVED from this chain — ClassManager owns it
  via its own OnPlayerDataReady subscription.
- `Modules/GearUpgradeConfig.lua` — shared refine/tier/reroll tables for
  weapons + armor (was 22 byte-identical entries split across two files).

**Rewrites:**
- `Modules/NetworkManager.lua` server + client — single EVENTS manifest
  with rateLimit + readyGated. Client uses deferred-listener pattern;
  server has periodic stale-bucket cleanup.
- `Modules/ReadyGate.lua` — per-player message queue. Server-fires-before-
  client-subscribes race solved here. `markReady` is module-local;
  `OnReady(cb)` is the public seam (currently no callers — reserved for
  loading-screen wire).
- `Modules/PlayerDataManager/init.lua` and sub-modules — DEBUG_NO_SAVE
  removed, RefreshPowerScore added, freshSpawn flag for health apply,
  Class Mastery overflow XP path removed, integer enforcement on
  AllocateStat/DeallocateStat, leaderstats=Level+Power, BonusManager
  routing for "other" source.
- All 5 `*Main.server.lua` scripts (Lobby, SocialPlaza, LaneDefense,
  HordeMode, CentralBoss) — bootstrap via PlaceBootstrap + PlaceLifecycle.
- `WeaponConfig.lua` + `ArmorConfig.lua` — trimmed to weapon-/armor-
  specific only; shared upgrade tables moved to GearUpgradeConfig.

**ReadyGate migration (T0 + T0-followup):**
- WeaponManager.WeaponEquipped pushed via ReadyGate
- ArmorManager.ArmorEquipped pushed via ReadyGate
- AchievementManager unlock toast via ReadyGate
- CharacterManager.CharacterCreationRequired via ReadyGate (T1.1)

### 4.2 T0 follow-ups (post-v0.5, on this branch)

These landed during the T1.1 leak audit:

**L1** — `WeaponManager/init.lua`: per-player Janitor introduced,
`CharacterAdded:Connect` tracked, torn down on PlayerRemoving. No more
dangling per-player CharacterAdded conn closure refs.

**L2** — `PlayerDataManager/init.lua`: `CharacterAdded:Connect` (for
HP-on-spawn) tracked through per-player Janitor.

**L3** — `PlayerDataManager.RemovePlayer`: clears `setupInProgress[player]`
so player-leaves-during-DataStore-load doesn't leak a strong Player ref
indefinitely.

**L4** — `LobbyMain.server.lua` + `SocialPlazaMain.server.lua`: removed
duplicate `Players.PlayerRemoving:Connect(DataManager.RemovePlayer)`
binding. PlayerDataManager.Init already binds it; the second binding
tripped "in-memory data is nil" warn on every disconnect in those two
places.

### 4.3 T1.1 — CharacterManager

**New module:** `Modules/Janitor.lua` — per-scope lifetime primitive.
Handles `RBXScriptConnection`, `Instance`, `thread`, `function`, and
tables with `:Destroy()` or `:Disconnect()`. Supports keyed slots,
`LinkToInstance(instance)` for auto-destroy on AncestryChanged,
graceful cleanup of resources added after `:Destroy()`.

API:
```
Janitor.new()                          → janitor
jan:Add(value, key?)                   → tracked, returns the value
jan:Remove(key)                        → clean one slot
jan:Destroy()                          → tear down all in reverse-add
jan:LinkToInstance(instance)           → auto-destroy on AncestryChanged
jan:IsDestroyed()                      → bool
```

**CharacterManager.lua — full rewrite:**
- D7: `CharacterCreationRequired` routed through `ReadyGate.FireClient`
  (was the suspected cause of "creation panel sometimes doesn't appear").
- D4 + D5 + D6: single per-player entry via
  `PlayerDataManager.OnPlayerDataReady`. Removed the polling loop, the
  duplicate PlayerAdded+for-existing-players setup, the double
  ApplyTemplate at first spawn.
- D1: dead `cd.skinId` armor-overlay block deleted.
- D3: `RequestCharacterCreationCheck` collapsed into `RequestCharacterStatus`.
- D8 + D9: `playerConnections[player]` table + magic `task.delay` disposers
  replaced with per-player + per-character Janitors. `LinkToInstance` cleans
  on respawn automatically.
- D11: unused `ApplyTemplate` return value removed.
- D12 PRESERVED: hair-accessory weld dance INTACT, with a comment
  forbidding "simplification" (this is the staff-fix pipeline).

**CharacterConfig.lua — trimmed:**
- Removed `Skins` table, `_skinById`, `GetSkin` (armor-as-part-replacement
  abandoned).
- Empty `HairColors` + `ClothingColors` seams for future palettes.
- `BodyModelCount` / `HeadModelCount` / `HairModelCount` + validators for
  the planned 3-models-per-gender system.
- Kept gendered class titles + `Presets` legacy helper.

**Schema:** `PlayerDataConfig.AccountDefaults.CharacterData` now declares
`isCreated, gender, bodyModel, headModel, hairModel, skinColor,
hairColor, clothingColor, preset (legacy)`. PlayerDataManager freshSpawn
skeleton mirrors exactly. `skins` + `equippedSkin` added to
`DEPRECATED_KEY_PATHS`.

**Network:** `RequestCharacterCreationCheck` removed from manifest.

**Files touched:** Janitor.lua (new), CharacterManager.lua,
CharacterConfig.lua, PlayerDataConfig.lua,
PlayerDataManager/init.lua, NetworkManager.lua, SocialPlazaApp.lua.

### 4.4 T1.2 — ClassManager

**ClassManager.lua — full rewrite:**
- D1: `ApplyInnateBonus` owned solely by ClassManager.Init's
  OnPlayerDataReady hook; removed from PlaceLifecycle's chain.
- D2: six `task.spawn(require())` Init fan-outs replaced with seven lazy
  getters (`getWeaponManager`, `getArmorManager`, `getResourceManager`,
  `getVisualEquipmentManager`, `getCosmeticManager`, `getGameStateManager`,
  plus pre-existing `getBonusManager`). No more boot race on early
  class-switch.
- D3: `GetClassConfig` deleted (zero external callers).
- D7: class-side fallback chains dropped in `GetAttackShape` /
  `GetShapeParams` / `GetAttackSpeed`. WeaponManager owns these.
- D8: comment explaining GameStateManager silent-pass in Lobby /
  SocialPlaza.

**ClassConfig.lua — full rewrite:**
- Dropped `attackShape`, `shapeParams`, `baseAttackSpeed` from every
  class (stale pre-weapon-system fields per DQ4).
- Dropped `resource = "..."` from every class (DQ5 — ClassBehavior.CONFIG
  is canonical for resource name).
- Each class declares `default = true` + `unlockRequirements = {}`.
- New `GetDefaultUnlockedClasses()` and `GetUnlockRequirementsMap()`
  helpers — single source of truth.
- New `validate()` task-spawned at module load: walks each class's
  `statDerivation` against `PlayerDataConfig.DerivedStats`, warns
  loudly on missing-required or unknown stats.

**PlayerDataConfig.lua:**
- New `DerivedStats` catalog with `required` boolean per stat.
  `CastTimeReduction = { required = false }` (caster-only per DQ1).
  `HpRegen` and `FlatHpRegen` listed as optional so a future class can
  opt in without tripping the validator.
- `AccountDefaults.UnlockedClasses` and `ClassUnlockRequirements` both
  `nil`-initialized at definition and populated at the bottom of the
  file from `ClassConfig.GetDefaultUnlockedClasses()` and
  `ClassConfig.GetUnlockRequirementsMap()`. Downstream readers see
  identical tables.

**PlayerClassSystem.lua (D4):** Hardcoded `or className == "Aegis"`
carveout removed from UnlockClass.

**PlaceLifecycle.lua (D1):** Step 1 (Class innate bonuses) removed from
`WireOnPlayerReady`. Steps 2–6 renumbered 1–5.

### 4.5 T1.3 — StatsManager + BonusManager

**BonusManager.lua — single-pass refactor (B1) + AddTimedBonus fix (B8):**
- Single-pass `Recalculate`: walk every source's keys once into an
  `aggregate[stat]` map, then walk `cfg.BonusStats` and write each
  catalog entry (using `defaultValue + aggregate[stat]` or just
  `defaultValue` when no source has the stat). Eliminates the previous
  quadratic dual-loop AND fixes the stale-after-clear bug where a
  stat dropped from every source kept its last non-zero total forever.
- Write-time validation: every Set/Modify/AddTimedBonus checks the stat
  name against `cfg.BonusStats`. Unknown names get warned-once and
  rejected. Typos surface immediately instead of silently aggregating
  into a key nobody reads.
- `AddTimedBonus` now tracks `timedThreads[player][source] = thread`.
  Re-applying the same tag cancels the previous expire-thread and starts
  a fresh one — refresh-on-reapply for non-stacking buffs (PowerSurge,
  Sharpsight, Frenzy, SecondWind, WeaponOil, IronWall, RallyDmg,
  RallyCrit all benefit). PlayerRemoving cancels all pending threads.

**CriticalSystem.lua (B3+B4+B5):** Reads CritChance.max and
CritDamage.max from `PlayerDataConfig.StatCaps`. No magic numbers
inside the file. Balance audit can tune both caps in one place.

**HealingSystem.lua (B14 + B7 + B2):** Heals run through
`CriticalSystem.ApplyCrit` — same multi-crit pipeline as damage
(geometric procs, 1.80× per proc cap, max 2 procs). Previous single-
proc 1.50× cap REMOVED. Balance is done per-skill via `healMultiplier`
(NOT by capping heals separately). `math.max(0, math.floor(heal))`
final clamp. Header doc explains the Damage-as-MAG-healing-power
design intent.

**DamageSystem.lua (B10):** Single `getWeaponManager()` helper replaces
two divergent inline lazy-loads.

**ArmorSystem.lua (B6):** Removed redundant inner `math.max(1, ...)`
clamp. The single floor lives in
`DamageSystem.CalculateIncomingDamage`.

### 4.6 T1.4 — ResourceManager + ClassBehaviors

**ResourceManager.lua:**
- R1: HitTracker hot-path cache. `_hitTrackerTimers(player)` resolves
  once, then it's plain function calls. Was a `FindFirstChild + require`
  per tick per player.
- R3: NotifyClient hoists `effectiveMax` once, computes percent
  locally. Single getEffectiveMax per push.
- R6: Init now registers `OnHitDealt` / `OnHitReceived` callbacks via
  HitTracker's existing callback API instead of being hardcoded into
  HitTracker.NotifyResourceManager.
- R2: comment on `GetResourceRate` clarifying that behaviors see
  CLASS-BASE max (`data.max`), not effective max — so regen rates are
  intentionally absolute-per-second numbers, not percentage-of-pool.

**HitTracker.lua:** `NotifyResourceManager` function REMOVED. The two
callsites in `RecordHitDealt` and `RecordHitReceived` now only fire the
existing callback list. ResourceManager rides the same dispatch as any
future per-hit consumer (Achievements already does; Runes / proc-on-hit
will).

### 4.7 docs/TODO.md sections added

- §9b *Character Creation / Appearance* (T1.1)
- §14b *Memory & Lifetimes (Janitor audit)* (T1.1) — the big leak
  audit list. Known candidates: CosmeticManager (duplicate PlayerAdded
  loop), MobAI, MobSpawner, VoteManager, HordeModeSpawner, DeathSystem
  (CharacterAdded conn never disconnected), AttackHandler, SkillEffects
  (no PlayerRemoving handler at all), etc.
- §14c *Class system follow-ups (Tier 1.2)* — balance audit, per-class
  module unification.
- §14d *Stats / Damage / Healing follow-ups (Tier 1.3)* — heal
  multiplier rebalance post-crit-unification, FlatAttack pipeline
  placement question, HealingPower stat split.

---

## 5. Patterns and conventions

### 5.1 Per-player lifetime — use Janitor

```lua
local Janitor = require(Modules:WaitForChild("Janitor"))
local playerJanitors = setmetatable({}, { __mode = "k" })
local function getPlayerJanitor(player)
    local jan = playerJanitors[player]
    if not jan then
        jan = Janitor.new()
        playerJanitors[player] = jan
    end
    return jan
end

-- in SetupPlayer / Init:
local jan = getPlayerJanitor(player)
jan:Add(player.CharacterAdded:Connect(function(character)
    ...
end))

-- in PlayerRemoving:
local jan = playerJanitors[player]
if jan then
    jan:Destroy()
    playerJanitors[player] = nil
end
```

### 5.2 Per-character lifetime — `LinkToInstance`

```lua
local templateJanitors = setmetatable({}, { __mode = "k" })

-- on character apply:
local existing = templateJanitors[character]
if existing then existing:Destroy() end
local jan = Janitor.new()
jan:LinkToInstance(character)   -- auto-destroy when Character:Destroy fires
templateJanitors[character] = jan

jan:Add(humanoid:GetPropertyChangedSignal("AutomaticScalingEnabled"):Connect(...))
jan:Add(head.ChildAdded:Connect(...))
-- … all conns auto-disconnect on respawn / leave
```

### 5.3 Lazy-getter for sibling modules

```lua
local _WeaponManager
local function getWeaponManager()
    if _WeaponManager ~= nil then
        return _WeaponManager or nil
    end
    local mod = Modules:FindFirstChild("WeaponManager")
    if not mod then
        _WeaponManager = false
        warn("[Caller] WeaponManager not loaded.")
        return nil
    end
    local ok, result = pcall(require, mod)
    _WeaponManager = ok and result or false
    return _WeaponManager or nil
end
```

Use `false` as the "looked, not found" sentinel so subsequent calls
short-circuit. Used in ClassManager (7 getters), DamageSystem,
SkillEffects, KillRewardManager, etc.

### 5.4 Hot-path module-ref cache

For modules that are called inside a per-tick loop or per-hit hook:

```lua
local _htResolved = false
local _htFunc = nil
local function _hitTrackerCall(player)
    if not _htResolved then
        _htResolved = true
        local mod = Modules:FindFirstChild("HitTracker")
        if mod then
            local ok, ht = pcall(require, mod)
            if ok and ht then _htFunc = ht.SomeFunction end
        end
    end
    if _htFunc then return _htFunc(player) end
    return nil
end
```

Resolve ONCE; cache the FUNCTION REFERENCE (not just the module). Pure
table read after that. Used in ResourceManager (`_voteManagerCheck` and
`_hitTrackerTimers`).

### 5.5 ReadyGate-routed server pushes

Any server `FireClient` that fires DURING boot (PlayerAdded path,
OnPlayerDataReady path, equipment setup) MUST route through
`ReadyGate.FireClient(player, eventName, ...)` instead of
`NetworkManager.FireClient`. Manifest flag `readyGated = true` is
documentation only — the manifest doesn't auto-route to avoid a
circular require. Already migrated: WeaponEquipped, ArmorEquipped,
AchievementUnlocked, CharacterCreationRequired.

Pending: WardrobeUpdate (CosmeticManager), EquipmentInfo
(EquipmentHandler), TalentStateUpdate (TalentManager — already
migrated by TalentManager).

### 5.6 Single source of truth for catalogs

Pattern: one module owns the catalog. Other modules read derived helpers.
Example: ClassConfig.Classes owns class definitions including `default`
and `unlockRequirements`. PlayerDataConfig at module-load bottom calls
`ClassConfig.GetDefaultUnlockedClasses()` and
`ClassConfig.GetUnlockRequirementsMap()` and assigns the results.
Consumers (PlayerClassSystem) keep reading
`PlayerDataConfig.ClassUnlockRequirements` — the surface API is
unchanged, only the source moved.

Apply this whenever two configs describe the same thing.

### 5.7 Sanity-check command

After any code edit, run paren / brace / function-end balance check:

```bash
cd /sessions/funny-jolly-hamilton/mnt/RobloxDefense && for f in <list>; do
echo "=== $f ==="; python3 -c "
import re
src = open('$f').read()
src = re.sub(r'--\[\[.*?\]\]', '', src, flags=re.S)
src = re.sub(r'--[^\n]*', '', src)
src = re.sub(r'\"([^\"\\\\]|\\\\.)*\"', '\"\"', src)
src = re.sub(r\"'([^'\\\\]|\\\\.)*'\", \"''\", src)
funcs  = len(re.findall(r'\bfunction\b', src))
ifs    = len(re.findall(r'\bif\b', src))
fors   = len(re.findall(r'\bfor\b', src))
whiles = len(re.findall(r'\bwhile\b', src))
dos    = len(re.findall(r'\bdo\b', src))
repeats= len(re.findall(r'\brepeat\b', src))
ends   = len(re.findall(r'\bend\b', src))
untils = len(re.findall(r'\buntil\b', src))
opens = funcs + ifs + fors + whiles + repeats + (dos - fors - whiles)
closes = ends + untils
print(f'  opens={opens} closes={closes} diff={opens-closes}')
print(f'  parens diff = {src.count(chr(40)) - src.count(chr(41))}')
print(f'  braces diff = {src.count(chr(123)) - src.count(chr(125))}')
"
done
```

`diff = 0` everywhere is the pass criterion. The paren/brace counts can
have a small offset from string-literal `%%` in `string.format` calls;
treat opens/closes as authoritative.

### 5.8 Stale-callsite grep

After deleting / renaming a field, grep the entire src/ for the old name:

```
Grep("cd\\.skinId|cd\\.skins|cd\\.equippedSkin", path="src", ...)
```

Zero matches outside the migration-deprecation list = pass.

### 5.9 Tag every fix with a §-marker

Comments referencing the audit get a §-marker so future grep can trace
lineage. Examples actually in the code:
`§T1.2/D1`, `§T1.3/B14`, `§T1.4/R6`, `§T0-FOLLOWUP/L1`, `§PERSIST1`,
`§NM-D4`, `§LD-CM2`, `§VG1`, `§HM3-followup`.

---

## 6. What's pending

### 6.1 T2 — Combat (next up if Pablo agrees)

Modules in scope:
- `AttackHandler/init.lua` + `AttackHandler/DamageHandler.lua`
- `HitTracker.lua` (pass 2 — first pass partially covered in T1.4/R6)
- `SkillManager/init.lua` and sibling skill modules
- `ClassSkills/<Class>Skills.lua` (4 files) + `ClassSkills/BaseSkills.lua`
- `SkillEffects.lua` — known to have NO PlayerRemoving handler;
  `activePlayerEffects[player]` is at risk (Janitor audit candidate)
- `KillRewardManager.lua`
- `ElementalSystem.lua`
- `ProjectileConfig.lua`

Known open questions for T2:
- `SkillManager.activeBuffs`: confirm PlayerRemoving cleanup is complete
- `SkillEffects.activePlayerEffects` + `activeMobEffects` + `mobBaseSpeeds`:
  audit per-mob cleanup paths; verify mob death always cleans these.
- AttackHandler ticket lifecycle (closed in T0 §A1-A4 but worth pass-2)

### 6.2 T3 — Mob

- `MobAI.lua` — Register/UnregisterMob, per-mob state, death races
  (largely closed in T0 §2.1a-d). Pass-2 verification.
- `MobSpawner.lua` — already cleaned in T0 §2.2a-e.
- `MobAssetLoader.lua` — has `Load()` function but no
  PlayerRemoving / lifetime story; verify it's load-once-at-boot only.

### 6.3 T4 — Death + Game flow

- `DeathSystem.lua` — known issue: per-character CharacterAdded:Connect
  not tracked via Janitor (TODO §T1.1-JAN1 candidate).
  `playerStates[player].diedConnection` IS disconnected on knockdown
  and on PlayerRemoving — clean for that conn.
- `GameStateManager.lua` (largely closed in T0 §G5 + V4-A3).
- `DefenseLine/init.lua` and sub-modules (closed in T0 V4-A3).

### 6.4 T5 — Vote / Run modifiers

- `VoteManager.lua` — NO PlayerRemoving handler at all! Player who
  leaves mid-vote leaks entries in `playersVoted`, `personalVote`,
  `personalCooldowns`, `fragmentRolledThisRun`. Reset() covers
  between-run, not mid-run leavers.
- `CardRegistry.lua` — uses `AddTimedBonus` which got fixed in T1.3/B8.
- `RunModifiers.lua` — `timedModifiers` cleanup story to verify.

### 6.5 T6 — Equipment (large)

- `WeaponManager/init.lua` + sub-systems (XPSystem, Refinement,
  TierSystem, BonusSystem) — touched in T0 + L1.
- `ArmorManager/init.lua` + sub-systems — touched in T0.
- `VisualEquipmentManager.lua` — KNOWN duplicate `PlayerAdded` +
  for-existing-players loop, CharacterAdded conn never disconnected.
  Janitor migration candidate.
- `WeaponRegistry.lua` + `ArmorRegistry.lua`
- `EquipmentRefinement.lua`, `EquipmentTierSystem.lua`,
  `EquipmentBonusSystem.lua` (factory pattern)
- `EquipmentHandler.lua`
- `InventoryManager.lua` (closed in T0 §2.5)
- `AccessoryConfig.lua`

T6 follow-up TODO items:
- §T1.3-DQ1 — `FlatAttack` pipeline placement
- §VEM-DEDUPE — AttachClassWeapon firing 2× (down from 3×, not 1×)
- §V2 — `AttachClassArmor` implemented but never wired
- Headgear "model" visual stub
- §T1.2-MOD1 — per-class module unification (touches ClassWeapons too)

### 6.6 T7 — Lobby

- `PartyManager.lua`, `MatchmakingManager.lua`, `SceneManager.lua`,
  `TeleportManager.lua` (all touched in T0 §P0c-P1g).
- Multi-server matchmaking queue (TODO §7 strategic).

### 6.7 T8 — Progression

- `PlayerLevelSystem.lua` (touched in T0 §PDM-D5).
- `TalentManager.lua` + `TalentEffectAggregator.lua` (closed in T0
  V4-A2; major redesign deferred to talent revision pass per TODO §3).
- `AchievementManager.lua` (closed in T0 §AM1-AM7).
- `DailyLoginManager.lua` (closed in T0 §DL1-DL3).
- `BonusExpSystem.lua`.

### 6.8 T9 — Shop / NPC

- `ShopManager.lua` — pass-2 needed (V4-A4 deferred). Concerns:
  atomic purchase / currency race, stock limits, server-clock rotation.
- `NPCManager/*.lua` (closed in T0 §NM3, §QH1-QH6).
- Quest + lore persistence migration to PlayerData (TODO §13).

### 6.9 T10 — UI

Every client React component. Many UI items are already in TODO
§14 (DailyLogin button race, SocialPanel invite-friend wiring stale,
combat-time stat allocation confirm, class unlock toast, all-players-
ready gate, player progression measurement, etc.).

### 6.10 T11 — Cross-cutting follow-ups

- **§T1.1-JAN1 — Janitor leak audit** (P0). Sweep every remaining
  module on TODO §14b's candidate list. CosmeticManager first (it has
  the same duplicate-PlayerAdded pattern we already fixed in
  CharacterManager).
- **§T1.1-JAN2** — telemetry: snapshot Janitor counts per system every
  60s, debug-only.
- Balance audit — bundles §T1.2-BAL1, §T1.3-BAL1, all `[??]` items.
- §NM-D6 — hang-recovery UI when client WaitForChild stalls.
- §RG-MIGRATION cosmetics + equipment push events.

---

## 7. Open design questions (carried)

These need Pablo's decision before the relevant module pass.

1. **FlatAttack pipeline placement** (§T1.3-DQ1) — true-damage vs current
   "scales with pipeline like BonusDamage" vs replace with per-weapon
   Penetration. Decide at T6.
2. **HealingPower as a dedicated derived stat** (§T1.3-DQ2) — split out
   for future PvP scaling divergence. Forward-compatible refactor.
3. **CritDamage class scaling balance** (§T1.2-BAL1, §T1.2-DQ2) — only
   Arcanist has per-class CritDamage scaling. Other 3 use class-base
   only. Coherent design needed for balance audit.
4. **Per-class module unification** (§T1.2-MOD1) — `Modules/Classes/<Name>/`
   bundling config + behavior + skills + weapons. Sizeable; post-alpha.
5. **HealingSystem multipliers rebalance** (§T1.3-BAL1) — heals now
   crit through the same multi-crit pipeline as damage; per-skill
   healMultipliers need to come down to match intended throughput.

---

## 8. Workflow conventions for next session

When resuming after compactification:

1. **Read this file end-to-end first.** Don't skip sections.
2. **Read `docs/TODO.md`** for the current backlog.
3. **Check git state** — `git status` will show any uncommitted T1 work;
   compare to "Files touched" lists in §4 above.
4. **Confirm tier in progress** with Pablo before opening files. The
   roadmap in §2 is the canonical plan but Pablo may want to reorder.
5. **Use the methodology in §3.** Don't shortcut Map → Surface → Execute.
   Pablo specifically values the surface-then-confirm step because it
   catches design vs implementation confusion early.
6. **Do NOT commit from this session.** Pablo commits manually per
   tier. Sandbox filesystem has previously rejected git object writes
   on large files; failed commits leave the index in a bad state and
   require `rm -f .git/index && git read-tree HEAD` to recover.
7. **Never amend; always create a new commit.** Pablo's stated git
   convention.
8. **TaskCreate / TaskUpdate liberally.** Pablo sees the task list as a
   progress widget. Each tier should have ~6–10 sub-tasks.
9. **Use Bash sparingly.** Prefer Edit / Read / Grep / Glob. Bash is
   for sanity checks, line counts, and git inspection only.

### 8.1 Things that will look weird if you didn't read this

- `ClassManager` has no resource definitions — `resource = "..."` was
  intentionally removed; ClassBehavior.CONFIG.ResourceName is the
  single source.
- `ClassConfig` has no `attackShape` / `shapeParams` / `baseAttackSpeed`
  fields — WeaponManager owns these.
- `PlayerDataConfig.AccountDefaults.UnlockedClasses = nil` at definition,
  but populated at the bottom of the same file via
  `ClassConfig.GetDefaultUnlockedClasses()`. Same for
  `ClassUnlockRequirements`. Don't "fix" the `nil` — it's intentional.
- `HealingSystem` uses the `Damage` stat as healing-power input. Design
  intent; not a bug. Comment says so.
- `BonusManager` warns on unknown stats. If a new stat write doesn't
  appear, check if it's in `PlayerDataConfig.BonusStats` (add it).
- `PlaceLifecycle.WireOnPlayerReady` does NOT apply class innate
  bonuses. ClassManager.Init owns that subscription.
- `CharacterManager` rebuilds a fresh per-character Janitor on every
  `ApplyTemplate` call — the hair-accessory weld dance is intentionally
  intricate (it's the staff-fix pipeline; comment forbids
  "simplification").

### 8.2 Stable file paths to remember

```
src/shared/ServerScriptService/Modules/
├── BonusManager.lua                  (T1.3 rewritten)
├── CharacterConfig.lua               (T1.1 rewritten)
├── CharacterManager.lua              (T1.1 rewritten)
├── ClassConfig.lua                   (T1.2 rewritten)
├── ClassManager.lua                  (T1.2 rewritten)
├── ClassBehaviors/                   (T1.4 reviewed, untouched)
│   ├── AegisBehavior.lua
│   ├── ArcanistBehavior.lua
│   ├── HunterBehavior.lua
│   └── LifeStewardBehavior.lua
├── HitTracker.lua                    (T1.4 modified — NotifyResourceManager removed)
├── Janitor.lua                       (T1.1 NEW)
├── NetworkManager.lua                (T0 + T1.1 modified)
├── PlaceBootstrap.lua                (T0 NEW)
├── PlaceLifecycle.lua                (T0 NEW + T1.2 modified)
├── PlayerDataConfig.lua              (T0 + T1.1 + T1.2 modified)
├── PlayerDataManager/
│   ├── init.lua                      (T0 + T1.1 + T0-FOLLOWUP modified)
│   ├── PlayerBonusSystem.lua         (T0 modified)
│   ├── PlayerClassSystem.lua         (T1.2 modified)
│   ├── PlayerLevelSystem.lua         (T0 modified)
│   └── PlayerStatSystem.lua          (T0 modified)
├── ReadyGate.lua                     (T0 rewritten)
├── ResourceManager.lua               (T1.4 modified)
├── StatsManager/
│   ├── init.lua                      (audited T1.3, untouched)
│   ├── ArmorSystem.lua               (T1.3 modified)
│   ├── CriticalSystem.lua            (T1.3 rewritten)
│   ├── DamageSystem.lua              (T1.3 modified)
│   └── HealingSystem.lua             (T1.3 rewritten)
├── WeaponConfig.lua                  (T0 trimmed)
├── WeaponManager/init.lua            (T0 + T0-FOLLOWUP/L1 modified)
└── ArmorManager/init.lua             (T0 modified)
```

Per-place Mains:
```
src/lobby/ServerScriptService/LobbyMain.server.lua          (T0 rewritten + T0-FOLLOWUP/L4)
src/socialplaza/ServerScriptService/SocialPlazaMain.server.lua  (T0 + T0-FOLLOWUP/L4)
src/lanedefense/ServerScriptService/LaneDefenseMain.server.lua  (T0 rewritten)
src/hordemode/ServerScriptService/HordeModeMain.server.lua      (T0 rewritten)
src/centralboss/ServerScriptService/CentralBossMain.server.lua  (T0 rewritten)
```

UI:
```
src/socialplaza/StarterPlayer/StarterPlayerScripts/UI/SocialPlazaApp.lua (T1.1 modified)
```

Docs:
```
docs/TODO.md                          (the parking lot)
Audit_4.7.md                          (this file)
```

---

## 9. Live-test ledger

After each tier closes, suggest specific smoke tests for Pablo. He
live-tests in Studio before committing. Recently suggested:

- T1.1: new save → confirm creation panel appears reliably in Lobby /
  SocialPlaza / combat places. Existing save → first spawn shows correct
  gender mesh + skin color (no flicker). AdminTesting SetGender →
  respawn with new template + hair + weapon survives. Print Janitor
  size during 50-respawn stress test.
- T1.2: fresh save → confirm 4 unlocked classes. Class switch in Lobby
  → silent GameStateManager pass works. Class switch in horde first
  second → lazy-getters fire WeaponManager hookup. Check dev console
  for `[ClassConfig] ... missing required derived stat` warns.
- T1.3: cast PowerSurge twice in a row → full second-cast duration
  (no early clear from first cast's expire-thread). Damage output
  unchanged; heal output may change due to multi-crit unification —
  watch for over-healing tells. Check console for any
  `[BonusManager] Rejected write to unknown stat` warns.
- T1.4: confirm regen still pauses during votes. Resource regen tick
  rate visibly unchanged after the FindFirstChild removal (should be
  perf-positive, not user-visible). Hit dealt → ResourceManager hook
  still fires (Arcanist +6 per kill, Hunter +0.6 per hit, etc.).

---

## 10. Things that explicitly should NOT be done

These have been discussed and decided AGAINST. Don't reopen unless Pablo
brings them up:

- **Don't "simplify" the hair-accessory weld dance** in CharacterManager.
  The five-step pattern (read AccessoryWeld values BEFORE clone, destroy
  pre-existing welds, parent, wait a frame, overwrite Part0/Part1/C0/C1)
  is what made hair AND held weapons reliable. The comment in the file
  explicitly forbids modification.
- **Don't run `git commit` from this session.** Sandbox FS has known
  failures on large files.
- **Don't add a `Validate()` patch for `statDerivation` without Pablo's
  preferred "expand the stats table" approach.** This is the route we
  took in T1.2/D6 — the DerivedStats catalog lives in PlayerDataConfig
  with `required` booleans, and ClassConfig.Validate consumes it. The
  patch would have been "iterate classes and warn"; the proper solution
  is the catalog.
- **Don't put per-class resource definitions into ClassConfig.** Pablo
  wants resources owned by ClassBehavior.CONFIG. The bare
  `resource = "..."` was removed from every ClassConfig entry in T1.2.
- **Don't remove the empty `Init()` stubs in ClassBehaviors.** Pablo
  prefers documented seams over removal.

---

## 11. Quick reference: BonusManager source keys

These are the canonical source keys. Don't invent new ones without a
named consumer:

```
"weapon"       — written by PlayerBonusSystem.ApplyWeaponBonuses
"armor"        — written by PlayerBonusSystem.ApplyArmorBonuses
"buff"         — written by SkillManager (per-skill buff apply/expire)
"talent"       — written by TalentEffectAggregator
"achievement"  — reserved; AchievementManager not yet wired here
"innate"       — written by ClassManager.ApplyInnateBonus
"acc_trinket"  — written by InventoryManager (Trinket slot)
"acc_ring1"    — written by InventoryManager (Ring1 slot)
"acc_ring2"    — written by InventoryManager (Ring2 slot)
"other"        — PlayerBonusSystem.SetBonus / ModifyBonus ad-hoc
"timed_<tag>"  — written by BonusManager.AddTimedBonus (card buffs etc.)
```

A new source key requires:
- adding it to the SetupPlayer init table in BonusManager.lua, AND
- a documented owner (which module writes it, when it's cleared)

---

## 12. Quick reference: ReadyGate-routed events

Events that fire DURING boot and need ReadyGate routing:

```
ServerReady            — §T0P2/X9: now ReadyGate-ROUTED (was wrongly
                         listed as BYPASS here while the code neither
                         bypassed nor gated it). Fired by PlaceLifecycle
                         via ReadyGate.FireClient; queued until the
                         client's ClientReady handshake. Reserved as the
                         loading-screen dismiss signal.
CharacterCreationRequired   — server push at first-login check (T1.1 migrated)
WeaponEquipped              — server push at EnsureStarterWeapon (T0 migrated)
ArmorEquipped               — server push at EnsureStarterArmor (T0 migrated)
AchievementUnlocked         — server push (T0 migrated)
TalentStateUpdate           — TalentManager.SendState (T0 migrated)
```

Pending migration (TODO §11):
```
WardrobeUpdate              — CosmeticManager.SetupPlayer
EquipmentInfo               — EquipmentHandler.SendState
```

Bypass list inside ReadyGate (high-frequency tick broadcasts):
```
VitalsUpdate
CurrencyUpdate
ResourceUpdate
StatsUpdate
PlayerInfoUpdate
```

---

## 13. Addendum — repo-wide pass (2026-06-12, Claude Fable 5 session)

A separate session ran a repo-wide danger/cleanup audit (parallel
subagent fan-out, then claim verification) and reconciled it against
this document. Output: **`AUDIT_FINDINGS.md`** at repo root — a Surface
in §3.4 format, findings `G1…G25`, each mapped to its owning tier, with
DQ1–DQ4 and a grouped action set awaiting Pablo's per-item sign-off.

Key points for any resuming session:

- **New scope discovered: repo hygiene (pre-tier).** The blanket
  `*.rbxmx` gitignore rule leaves 29 `src/` source assets (entire
  AppGui tree, character templates, mob/weapon models) UNTRACKED —
  zero `.rbxmx` in git. Also tracked-but-redundant: `foreman.exe`,
  `sourcemap.json`, `Leg.obj`, `Leg.mesh`. Fix commands are in
  AUDIT_FINDINGS.md Action Set A — **Pablo's terminal only** (§10
  sandbox-git rule holds).
- **Tier inputs:** G11/G12/G14→T2, G6/G7/G13→T3, G15→T5,
  G2/G4/G8/G9→T7, G19/G21/G22→T10/T11, G3/G5/G10→T0 pass-2. When a
  tier opens, fold its G-items into the Map step. On sign-off, park
  them in `docs/TODO.md` per §3.7 (none parked yet — awaiting Pablo).
- **Verified good this pass:** SkillManager server-side cooldowns,
  AttackHandler server-position range checks, §L8 matchmaking snapshot,
  `.env` never committed. Dirty tree = the staged T1 work in §4 (do
  not "rescue" it as a danger).
- **Ops:** Open Cloud key in `.env` should be rotated (folder has been
  shared with audit sessions).

Status: Surface delivered; awaiting Pablo's `G<N>. Yes/No/discuss`
responses before any execution.

### 13.1 T0 pass-2 (executed)

Pablo green-lit a fresh-eyes T0 re-read. Full Surface in
`T0_PASS2_SURFACE.md` (X1–X25 + DQ-A/B/C); Pablo signed off per-item
and ALL approved fixes are LANDED in the working tree under
`§T0P2/X<n>` tags (sanity-checked, not yet live-tested / committed).

Headline finds (all fixed): X1 CreateDefaultData shared nested default
tables → cross-player save contamination (DeepCopy now); X2 teleported
difficulty was read at boot before ProcessPlayer → every run played on
"Normal" (now: lobby-owned, validated, resolved once via
TeleportDataReader.OnDifficultyResolved — DQ-B); X3 leave-during-load
zombie playerDataStore entries; X4 natural level-ups never updated the
Level attribute / Power leaderstat (now routed through SetAccountData);
X5 vitals/regen loops died permanently on first error (pcall per tick);
X6 BindToClose saves parallelized; X7 data-ready callbacks now fire
AFTER leaderstats/attribute; X8 ReadyGate overflow now kicks for resync
(DQ-A = a); X9 ServerReady + Horde late-join GameStateChanged are
ReadyGate-routed (see §12 correction above).

Decisions recorded: DQ-A kick-on-overflow; DQ-B difficulty owned by
Lobby, first-arrival resolution, immutable thereafter; DQ-C Horde/Lane
servers are one-run (X13 deleted the dead re-arm closure).

Kept-as-seams (do NOT "clean up"): DeallocateStat (§T0P2/X22 —
planned single-point dealloc), TeleportClass attribute (§T0P2-TPCLASS),
empty client ServerReady handlers (loading-screen hook).

New TODO section: docs/TODO.md §19 (§T0P2-ADMIN remote-admin removal
[P0/Security], TPCLASS, RESPEC-SCROLL, MASTERY, DEALLOC, EVENTSLIM,
ORPHANS).

Next: Pablo live-test (suggested smoke tests in T0_PASS2_SURFACE.md
status header) → Pablo commits → resume tier roadmap at T2 (§6.1).

---

End of Audit_4.7.md.
