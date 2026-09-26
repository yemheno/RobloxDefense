# Backlog

Every **open** item, once. Closed items are one line each in [HISTORY.md](HISTORY.md#closed-items). Numbers live in [BALANCE_NUMBERS.md](BALANCE_NUMBERS.md).

Merged on 2026-09-26 (HEAD `24c4d7e`) from `docs/TODO.md`, `Audit_4.7.md` §6–§7, `AGENCY_CHECKS.md`, `AUDIT_FINDINGS.md`, `CODEBASE_REVIEW.md` §4/§6 and `SCALING_AUDIT.md` "Deferred" (all now in [`docs/history/`](history/)). Each status was re-checked against the code.

## How to use this file

- **Priority:** `P0` ship-blocker · `P1` visible bug or needed before alpha · `P2` quality / future-proofing · `P3` nice to have · `??` design decision needed · `🚀` post-alpha · `📝` monitoring / doc-only.
- **Ids are stable.** Keep the original id (`§T0P2-MASTERY`, `G20`, `§AGX/X46-GUARD`, …). A new item gets a `§`-prefixed id and is tagged in code with it.
- **Closing an item:** delete its row here and add one line to [HISTORY.md](HISTORY.md#closed-items) with the closing commit.
- **Code `TODO` comments** must cite an id from this file.
- Ids that were untagged in `TODO.md` got a new id here; they are marked *new id*.

**Contents:** [Needs Pablo](#needs-pablo) · [P0](#p0) · [P1](#p1) · [P2](#p2) · [P3](#p3) · [📝 Monitoring](#-monitoring) · [🚀 Post-alpha](#-post-alpha) · [Pre-release checklist](#pre-release-checklist)

---

## Needs Pablo

Design calls and actions only Pablo can take. Agents don't implement these without his answer.

### Actions only Pablo can do

| Id | Item | Where | Next step |
|---|---|---|---|
| `§T10/ICONS` | Import the delivered icon set (27 assets in `assets/ui/`) and paste ids. **Plus** 4 icons with no art yet (`play`, `leave`, `emote`, `menu`) and an `appearance` slot | `UI/Common/Theme.lua` (`Theme.Icons` ×16, `Theme.Images` ×11; 34 `rbxassetid://0` today) | Studio → Asset Manager → Bulk Import; add the 5 missing icons to [CLAUDE_DESIGN_BRIEF.md](CLAUDE_DESIGN_BRIEF.md) |
| `G22` | Game-mode icons are `rbxassetid://0` | `GameModeConfig.lua:21,48,75` | Same import pass as `§T10/ICONS` |
| `G20` | Rotate the Open Cloud key (the folder was shared with audit sessions) | `.env` (tools read `ROBLOX_OPEN_CLOUD_KEY`, §AGX/X49) | Rotate in the Creator Dashboard |
| `§AGX/X40-PRODUCTS` *(new id; split from X40-BUNDLES)* | Create the real DevProducts and the VIP GamePass, paste ids; every Premium entry is `enabled = false`, id `0` | `ShopConfig.lua` Premium, `MonetizationService.lua` | Follow [BALANCE_NUMBERS § Monetization](BALANCE_NUMBERS.md#monetization-robux) and commit `1c6e333`. Bundles also need `§AGX/X40-BUNDLES` (P1) first |
| `§AGX/X4-LIVE` | Reserved-server live test (Studio can't reserve servers) | `TeleportDataReader.lua`, `TeleportManager.lua` | After publishing: one reserved server per party; public combat server bounces to Lobby; X14 `TeleportInitFailed` retry. [STUDIO_TEST_PLAN](STUDIO_TEST_PLAN.md) §3 "Live test" |

### Open design questions

| Id | Question | Context | Options |
|---|---|---|---|
| `§AGX/X11-CALM` *(new id)* | **Calm Under Fire** keystone rule: OK to write it? | Only unimplemented keystone whose stats are all readable now. The agent's edit was permission-denied, so it waits on Pablo's OK. `TalentTreeConfig.lua:746` | Approve as specified in the node text, or change the effect |
| `§AGX/STATS-MS` *(new id)* | **MovementSpeed only in combat places.** Hunter +8%, Swiftness and talent move speed apply only where `DeathSystem` runs (Lane, Horde, CentralBoss), not in Lobby/SocialPlaza | `DeathSystem` owns `BaseWalkSpeed` | Keep (combat stat), or also apply in hubs |
| `§AGX/D-FIX2-RSV` *(new id)* | **RSV/MAG ResourceMax scaling.** Classes declare `ResourceMax = { RSV = …, MAG = … }`, but the resource bar reads only the `ResourceMax` bonus and the class resource key, not the derived stat | `ClassConfig.lua:121,170,212,258`; `ResourceManager.lua:97-115` | Wire the derived stat into the bar (bigger bars for RSV/MAG builds), or drop the coefficients |
| `§AEGIS-BB-ALLY` *(new id)* | **Battle Beast ally protection.** The code gives allies in the cone a flat **100% uncapped damage reduction for 6 s** (full invulnerability; comment: "no cap applies to ultimates"). BALANCE_NUMBERS said allies get 70% of self DR, and `allyDrFraction = 0.70` is computed but unused | `ClassSkills/AegisSkills.lua` `BattleBeastExec` | Keep full ally invulnerability (the tank's signature moment), or apply 70% of self DR (≈35% at the 100 minimum) |
| `§AGX/X11-AURA` *(new id)* | **Fortune Favors / Patron Saint owner exclusion.** The owner gets no share of their own aura; only party members do | `StatsManager/PartyAura.lua` | Keep, or give the owner a share too |
| `§AGX/X11-RHYTHM` *(new id)* | **Spell Rhythm has no price** (every other keystone trades something away) | `KeystoneRules.lua`; [Spell Rhythm](BALANCE_NUMBERS.md#spell-rhythm) | Add a penalty, or accept |
| `§AGX/D7-ROT` *(new id)* | **D7 rotation choices** made by the agent: Consumables 3 of 6 every 6 h, Cosmetics 4 of 7 every 24 h, staples/Premium fixed, refresh 5/10/20 Essence capped 3/day, per-player deterministic stock | `ShopConfig.lua:314-328`; [rotation](BALANCE_NUMBERS.md#shop-rotation-and-paid-refresh) | Confirm or retune |
| `§AGX/X18-FLAG` *(new id)* | **X18 appearance flag.** Re-creation is gated by `CharacterData.appearanceChangeUnlocked` (granted by the free Veteran token or a paid change) | `CharacterManager.lua:687-776` | Confirm the flow: free at 50, then 49 R$ |
| `§AGX/X28-NEXT` *(new id)* | **Boss next steps.** Iron Warden is a runtime placeholder rig; CentralBoss stays `available = false` | `Mobs/IronWarden.lua`, `GameModeConfig.lua:49-51`, `lobby/.../MainMenu.lua:54-56` | Real model, Studio test ([test plan](STUDIO_TEST_PLAN.md) §4), flip the two FLIP HERE switches, arena dressing, telemetry. Then bosses 2–4 unlock the other medals |
| `§ULT-LEVEL` *(new id)* | **Ultimate unlock level: 10 or 30?** Pablo chose level 10 (§EASY/E1), but every ultimate also has `unlockLevel = 30`, which is checked first, so 30 wins | `SkillManager/init.lua:532-553`; skill configs | Pick one and delete the other gate |
| `§T1P2-PEN-CAP` *(new id)* | **Flat Penetration is now capped at 60**, but Pablo decided flat penetration stays uncapped and only a future %-penetration gets the 60 cap (T1P2-DQ-T1C) | `DamageSystem.lua:133` (§AGX/BAL) | Keep the clamp (and revise DQ-T1C), or drop it and cap only `§T1P2-PEN` |
| `§T1.3-DQ1` | `FlatAttack` placement in the damage pipeline (acts like BonusDamage today) | `DamageSystem.GetBaseDamage` | Keep / post-multiplier flat add / replace with weapon Penetration |
| `§T1.3-DQ2` 🚀 | Split `HealingPower` into its own derived stat (heals read the Damage stat today) | `HealingSystem.lua:53-54` | Forward-compatible refactor for PvP |
| `§6-BOUNTY` *(new id; TODO §6)* | BountyBoard: `meritScalar +1.0` for 30 s makes 2× Merits. Intended? | `CardRegistry` | Confirm |
| `§4-WAVE13` *(new id; TODO §4)* | Wave 13+ procedural path is untested; Lane stops at 12 so nothing uses it | `WaveConfig` | Supported state, or cap waves |
| `§14-POWER` *(new id; TODO §14)* | Power vs engagement: Power only refreshes on setup and level-up (gear/talent changes lag), and there's no "Mastery/Class score" | `PlayerDataManager.RefreshPowerScore` (`init.lua:939`), `GearRating` | Decide the formula and display; then refresh at every gear change |
| `§T1P2-STACKS` | Which debuffs get `maxStacks > 1` (only Sundering stacks) | `SkillEffects`, skill configs | Balance call; mechanism done (§T2/Z9) |

---

## P0

| Id | Area | Item | Where | Next step |
|---|---|---|---|---|
| `§AGX/STUDIO` | All | **Nothing since `0e6d15e` has run in Studio** (now through `24c4d7e`). Includes the VEM-DEDUPE 1× check, the X45 physics profile and the `§CFG-UI` equipment smoke test | [STUDIO_TEST_PLAN.md](STUDIO_TEST_PLAN.md) | Run it top to bottom; §0 first (X16 fails boot hard) |
| `§16-ANIM` *(new id)* | Content | 3 of 4 classes share the placeholder attack animation `rbxassetid://128777973` | `AnimationConfig.Player.Classes` | Author per-class attack animations |
| `§16-MOBS` *(new id)* | Content | 3 wave mob types; Zombie is the only weighted spawn in all 12 waves | `WaveConfig.lua:26-29` | 2–3 new mob types with element variety |
| `§16-SFX` *(new id)* | Content | 33 sounds point at `rbxassetid://0` | client `Modules/SoundManager.lua` | At least 11 SFX: hit, cast, mob death, player damage, level up, vote start/end, pickup, UI open/close, click, victory |

## P1

| Id | Area | Item | Where | Next step |
|---|---|---|---|---|
| `§AGX/X40-BUNDLES` | Monetization | The 3 class bundles (99 R$) contain cosmetics also sold for Merits/Essence, so `MonetizationService` refuses to prompt them | `ShopConfig.lua` Premium, `MonetizationService.lua` | Author Robux-only cosmetics and point the bundles at them (product ids: `§AGX/X40-PRODUCTS`) |
| `§DISC/D5` | Progression | Achievement-driven stat bonuses + gates: (a) chapter cap at each 50 needs the chapter boss achievement; (b) class unlocks behind achievements | `BonusManager` "achievement" source (reserved), `ChapterConfig`, `PlayerClassSystem` | Don't land (a) while CentralBoss is hidden, or progression blocks at 50 |
| `§2.6` | Shop | ShopManager review: atomic spend and server `enabled` are done; stock/rotation now exist (§AGX/D7) and need the review | `ShopManager.lua` | Review the D7 rotation/refresh paths |
| `§SCALE-D1` *(new id; SCALING Deferred #1)* | Performance | Mobs parent to `workspace` root, so every AttackShapes query scans all root children | `MobSpawnHelper`, spawners, `AttackShapes.lua:59-70` | Parent mobs to `workspace.Mobs`; scan only it for mob queries. **Keep** the root scan for player targets |
| `§V2-ART` *(new id; TODO §9)* | Art | Per-class armor models (`<Class>_a<slot>`); `DefaultArmor` stub is the fallback | `ServerStorage.Models.Armors` | Author models |
| `§16-HEADGEAR` *(new id; TODO §9/§16)* | Cosmetics | Headgear `visual.type == "model"` has no implementation | `ApplyHeadgearVisual()` | Implement when accessory models exist |

## P2

| Id | Area | Item | Where | Next step |
|---|---|---|---|---|
| `§2.4d` | Death | `data.respawnCount` is tracked but nothing reads it | `DeathSystem.lua:887` | End-of-run panel; "Die N times" / deathless achievements |
| `§T1.1-CC3` | UI | Gendered class titles exist but UI hard-codes the masculine form | `CharacterManager.GetClassTitle`; ClassMenu, StatsMenu, ClassReferencePanel, leaderboard | Use `GetClassTitle` everywhere |
| `§T1.1-AE1` | Equipment | Extract the hair-accessory weld sequence into a shared helper and route VEM + CosmeticManager through it. **Keep every step** ([ARCHITECTURE § Decided against](ARCHITECTURE.md#decided-against)) | `CharacterManager.ApplyTemplate` | New `Modules/AccessoryWelder.lua` |
| `§PDM-D11` | UI | Confirm stat allocation during combat (client prompt, 1-min cooldown) | StatsMenu | Pure UI |
| `§13-ULTDIM` *(new id; TODO §13)* | UI | SkillPad/ActionBar dim by cost and cooldown only, not by the ultimate level gate | `UI/Common/SkillPad.lua`, `ActionBar.lua` | Dim/lock slot 4 below the unlock level (see `§ULT-LEVEL`) |
| `§T0P2-MASTERY` | Progression | Class Mastery has config and data fields but no XP source (`AddClassMasteryXP` deleted) | `ClassMasteryConfig.lua`, `ClassDataTemplate` | Remove + deprecated-key sweep, or keep as a documented seam |
| `§T0P2-DEALLOC` | Progression | Single-point stat deallocation (seam: `PlayerDataManager.DeallocateStat`) | — | Remote + manifest + UI + cost decision; pairs with `§AGX/UI-P2-REFUND` |
| `§AGX/UI-P2-REFUND` | Talents | Single-talent refund: UI has it disabled (`INDIVIDUAL_REFUND_ENABLED = false`), server has no handler | `TalentTreeUI.lua:132`, `TalentClient.lua:139-141`, `TalentManager.lua` | Remote, leaf-only server refund, cost decision, flip the flag |
| `§AGX/X11-RULES` | Talents | 2 keystone rules still "(coming soon)": Arc Saturation and Eye of the Storm need a per-cast hit-count hook (AoESize is readable since §AGX/STATS). Calm Under Fire waits on Pablo (`§AGX/X11-CALM`) | `StatsManager/KeystoneRules.lua`, `TalentTreeConfig.IMPLEMENTED_RULES` | Add the hook in `SkillManager`/`BaseSkills`, then add each name to the set |
| `§T0P2-EVENTSLIM` | Network | Every place registers all manifest events and loads broad module lists | `NetworkManager` manifest | Per-place subsets, or accept and document |
| `§T0P2-RESPEC-SCROLL` | Economy | Remaining: boss drop sources for scrolls and the acquisition curve | `DropTableConfig`, `CardRegistry` | Balance pass |
| `§T1P2-PEN` | Combat | Add %-penetration beside flat penetration, capped by `StatCaps.Penetration` (60) | `DamageSystem`, `BonusStats` | New BonusStat + pipeline step |
| `§T10/STACK` | UI | Archive the disabled legacy `StarterGui/AppGui` (AppRoot, Controllers, meta). The §EV12 wrong-event list lives there | `src/shared/StarterGui/AppGui` | Legacy-archive PR |
| `§T10/U2` | UI | Talent tree follow-ups: node icons per branch, allocate/refund sounds, keystone showcase panel | `UI/TalentTreeUI.lua` | — |
| `G8` | Teleport | A zero lobby id outside Studio only `warn`s and returns false | `ReturnTeleporter.lua:95-99` | Loud error at boot |
| `G21` | Ops | ~163 `print(` lines in server code; no leveled logger | `*/ServerScriptService` | Small leveled logger, or strip at release |
| `§SCALE-D2` *(new id; SCALING Deferred #2)* | Performance | `VitalsUpdate` sends a full P-entry snapshot to everyone at 1 Hz (O(P²)) | `PlaceLifecycle.lua:298` | HP to attributes + event-driven static fields; before any 30+ player mode |
| `§SCALE-D3` *(new id; SCALING Deferred #3)* | Performance | `AttackFired` goes to every other player per swing | `AttackHandler/init.lua:359-363` | Range-scope like §SCALE/S2 |
| `§SCALE-D4` *(new id; SCALING Deferred #4)* | Performance | Knockback creates/destroys a `LinearVelocity` per target per cast | `MobAI.lua:1120` | Pool one per character |
| `§DOCS/C11` *(new id)* | Network | Manifest says `readyGated = false` for `ServerReady` and `GameStateChanged`, which are ReadyGate-fired at boot (`PlaceLifecycle`, Horde late-join). The flag is informational (`IsReadyGated` has no callers) | `NetworkManager.lua:88,194` | Fix the flags/comments (comment pass) |
| `§DOCS/C12` *(new id)* | Stats | `BonusManager` header omits the `"keystone"` source that `KeystoneRules` writes; `SetupPlayer` omits `keystone`/`aura_*` (created on first write, so it works) | `BonusManager.lua:22-44,185-196`, `KeystoneRules.lua:582` | Add to the header (comment pass); init table optional |
| `G23` | Docs | Two comments cite the deleted `TODO_PARKING_LOT` | `ArmorManager/init.lua:166`, `LobbyNPCRegistry.lua:236` | Comment pass |

## P3

| Id | Area | Item | Where | Next step |
|---|---|---|---|---|
| `§SCALE-D6` *(new id; SCALING Deferred #6)* | Performance | MobAI 60 Hz loop over all mobs matters only above ~200 mobs | `MobAI.lua` | Only if the Humanoid wall is solved |
| `§SCALE-D7` *(new id; SCALING Deferred #7)* | Performance | `VoteUpdate` rebroadcasts on every cast | `VoteManager.lua:525` | 0.25 s debounce |
| `§OPS-CI` *(new id; CODEBASE_REVIEW §6)* | Ops | No CI, lint or tests: nothing blocks a broken build | repo | selene + stylua + GitHub Action running `rojo build` for all 5 places; TestEZ for pure modules |
| `§OPS-PERF` *(new id; CODEBASE_REVIEW §6)* | Ops | No performance baseline on any device | — | One Lane + one Horde run with the MicroProfiler |

## 📝 Monitoring

| Id | Item | Where | Next step |
|---|---|---|---|
| `§AGX/X46-GUARD` | **Tripwire:** before anything bought with Robux can roll a random result or be traded/auctioned, add PolicyService `ArePaidRandomItemsRestricted` / `IsPaidItemTradingAllowed` and reopen X46. `Account.Monetization.robuxSpent` stays private | `MonetizationService.lua` `ALLOWED_GRANTS` | Standing rule ([DESIGN_DECISIONS](DESIGN_DECISIONS.md#monetization)) |
| `§AM5` | `OnKill` evaluates achievements and calls `PersistNow` synchronously per kill | `AchievementManager.lua` | Watch telemetry in heavy waves |
| `§15-TELEMETRY` *(new id; TODO §15)* | Confirm `MonitoringSystem` records session length, wave reached, deaths, class, currency earned | `MonitoringSystem` | Before opening the alpha |

## 🚀 Post-alpha

| Id | Area | Item |
|---|---|---|
| `§17-CB1` (`§CB1`) | Modes | CentralBoss authored content: see `§AGX/X28-NEXT` |
| `§4-ENDLESS` *(new id; TODO §4)* | Modes | Endless Horde: a new place reusing `HordeModeSpawner` with `MaxWave = nil`, procedural curve past 12, reward pacing |
| `§SCALE-WALL` *(new id)* | Modes | Massive Horde (150–250 mobs) needs lightweight movers instead of Humanoids ([ARCHITECTURE § Scaling](ARCHITECTURE.md#scaling)) |
| `§7-MM` *(new id; TODO §7)* | Lobby | Cross-server matchmaking on `MemoryStoreService` (one queue per mode × difficulty, ReserveServer rendezvous, single-server fallback). ReserveServer for the local queue and the PLAY entry are done |
| `§EV6` | Social | List friends online in other servers (presence + follow design) |
| `§DISC/D2` | Party | Persistent parties across server hops (party id in teleport data) |
| `§AGX/X48` | UX | Onboarding: no tutorial or first-run flag; nothing points to Commander Vex. Parked by Pablo until modes are final |
| `§T1.2-MOD1` | Code | One folder per class: `Modules/Classes/<Name>/init.lua` with config, behavior, skills, weapons |
| `§T1.1-CC1` | Appearance | 3 body / 3 head / 3 hair models per gender (seams in `CharacterData`, `CharacterConfig`) |
| `§T1.1-CC2` | Appearance | Hair and clothing colour palettes (`CharacterConfig.HairColors`, `ClothingColors` are empty) |
| `§T1.1-CC4` | Monetization | Appearance preset pages (`AppearancePresets`), unlocked via shop/Robux |
| `§9-ACC2` *(new id; TODO §9)* | Equipment | Accessories v2: per-slot rarity, socketing, set-bonus UI in StatsMenu |
| `§9-BOSSACC` *(new id; TODO §9)* | Equipment | A unique accessory per boss (needs bosses, `AccessoryConfig` set, per-boss pools in `DropManager`) |

---

## Pre-release checklist

Before the first public alpha:

- [ ] `§AGX/STUDIO` passed.
- [ ] `§AGX/X4-LIVE` passed on a published build.
- [ ] `G20` key rotated.
- [ ] `§T10/ICONS` and `G22` imported.
- [ ] `§16-ANIM`, `§16-MOBS`, `§16-SFX` at least placeholder-free for the alpha modes.
- [ ] `§AGX/X40-PRODUCTS` created; `§AGX/X40-BUNDLES` done, or the bundles left disabled.
- [ ] BootProfiler `ENABLED = false` (**done**, `d5e052b`; keep it off).
- [ ] Admin/debug surface Studio-only (**done**, `d5e052b` §AGX/SEC).
