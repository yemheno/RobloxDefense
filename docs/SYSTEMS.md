# Systems

How each gameplay system works. **No tunable numbers here:** each section links to its values in [BALANCE_NUMBERS.md](BALANCE_NUMBERS.md), in the same order. Architecture, patterns and the network/persistence layer are in [ARCHITECTURE.md](ARCHITECTURE.md).

Rebuilt on 2026-09-26 from `GAME_DOCUMENTATION.md`, `COSMETICS.md`, `AchievementMap.md` and `TALENT_TREE_PROPOSAL.md` (now in [`history/`](history/)), and re-checked against `src/` at `24c4d7e` where the old text had drifted.

**Contents:** [Game loop](#game-loop) · [Economy](#economy) · [Progression & respec](#progression--respec) · [Stats](#stats) · [Damage & healing](#damage--healing) · [Classes, skills & resources](#classes-skills--resources) · [Status effects & elements](#status-effects--elements) · [Gear](#gear) · [Mobs](#mobs) · [Waves, modes & game state](#waves-modes--game-state) · [Defense line](#defense-line) · [Death & regen](#death--regen) · [Rewards](#rewards) · [Cards, votes & run modifiers](#cards-votes--run-modifiers) · [Quests & NPCs](#quests--npcs) · [Achievements](#achievements) · [Talents](#talents) · [Shop, inventory & consumables](#shop-inventory--consumables) · [Monetization](#monetization) · [Chapters & class mastery](#chapters--class-mastery) · [Party, matchmaking & teleport](#party-matchmaking--teleport) · [Leaderboards & Power](#leaderboards--power) · [Cosmetics & animation](#cosmetics--animation) · [Client systems](#client-systems) · [Sound](#sound)

---

## Game loop

1. **Lobby:** create a character, visit NPCs (shops, smiths, quests, lore), form a party, pick a mode and difficulty.
2. **Teleport** to a reserved combat server with match data (mode, difficulty, party).
3. **Combat place:**
   - **LaneDefense:** hand-crafted waves march down a lane toward a defense line. Win by clearing every wave; lose when the line breaks or the party wipes.
   - **HordeMode:** top-down arena; mobs spawn around each player; a fixed run timer; alternating supply/threat votes.
   - **CentralBoss:** a party boss fight (Iron Warden placeholder); hidden from the menu until tested.
4. **Rewards:** player XP, weapon XP, Merits and Essence drops, quest and achievement progress.
5. **Return** to the Lobby to upgrade, respec and queue again.

**SocialPlaza** is a non-combat hub for wardrobe, emotes and avatar preview.

Four classes: **Aegis** (melee tank, Determination), **Arcanist** (ranged AoE caster, Aether), **Hunter** (ranged pierce DPS, Killer Instinct), **Life Steward** (healer, Life Energy). All four are unlocked from the start.

---

## Economy

Two currencies. **Merits** are the common currency (drops from every mob). **Essence** is the scarce one (minibosses/bosses, Essence cards, quests, achievements, daily login). Neither is ever sold for Robux ([DESIGN_DECISIONS § Monetization](DESIGN_DECISIONS.md#monetization)). Fixed prices derive from one Merit:Essence anchor.

`CurrencyManager`:

- `AddMerits` applies the player's `MeritBonus`; refunds pass `raw = true` and skip it (§AGX/X32).
- `AddEssence` is flat.
- `SpendMerits` / `SpendEssence` reject negative, NaN and infinite amounts; zero is a successful no-op (§AGX/X33).
- Every purchase-like path **deducts before it grants**, under a per-player lock, and refunds if the grant fails.

Values: [BALANCE § Economy](BALANCE_NUMBERS.md#economy).

## Progression & respec

- **Account level** from XP. The XP curve resets its steepness at the start of each 50-level chapter.
- **Stat points:** one per level, allocated per class (`AllocateStat`, integers only).
- **Respec** (stats or talents) costs one Respec Scroll, else a flat Essence price. Scrolls come from the shop, the day-30 login reward, achievements, and **fragments** (a per-player roll on Horde supply votes, once per run; fragments auto-combine into a scroll in `InventoryManager.AddItem`).
- **Class switch** (`ClassManager.SetClass`): has a cooldown, is blocked mid-run, and resets the resource, equips the starter weapon/armor, re-applies visuals and cosmetics, innate bonuses and weapon bonuses, then recalculates stats. Arriving with a party-picked class skips the cooldown once.
- **Class Mastery** exists as config and data fields but has no XP source (`§T0P2-MASTERY`).

Values: [BALANCE § Progression & respec](BALANCE_NUMBERS.md#progression--respec).

## Stats

**Primary stats** (allocated): Might (MIG), Vitality (VIT), Precision (PRE), Magical Attunement (MAG), Resolve (RSV). Each starts at a base value.

**Derived stats** are computed per class:

```
Derived = (DerivedBase + Σ (primaryBase + allocated) × classCoefficient + FlatBonus) × (1 + PercentBonus/100)
```

Each class declares its coefficients in `ClassConfig.statDerivation`; `PlayerDataConfig.DerivedStats` lists which derived stats are required, and `ClassConfig.validate()` warns at boot on a missing or unknown one.

**Bonus stats** come from `BonusManager`, which keeps each writer (weapon, armor, talents, buffs, innates, accessories, consumables, auras, keystones) in its own source table and sums them into `data.Bonus` ([ARCHITECTURE § BonusManager sources](ARCHITECTURE.md#bonusmanager-sources)).

**Caps:** one `StatCaps` table; every reader clamps through `PlayerDataConfig.CapStat`. Since §AGX/STATS every bonus stat has a reader:

| Stat | Reader | Effect |
|---|---|---|
| MovementSpeed | `DeathSystem` base walk speed | slows, stuns, cast lock and knockdown all work from this base; combat places only |
| AttackSpeed | `ClassManager.GetAttackSpeed` | attack cadence; the client is re-sent its config, and the server accepts the faster of old/new cadence briefly |
| AoESize | `SkillManager` per-cast shape view | scales skill shape range/width/inner radius (not angle, not cast distance) |
| CooldownReduction | `SkillManager.StartCooldown` | cooldowns; the reduced value is sent to the client |
| CastTimeReduction | `SkillManager` cast start | cast time on server and client bar |
| StatusResistance | `MobAI.ApplyEffectToPlayer` | mob stun/slow duration (not slow strength) |
| Resource max bonuses | `ResourceManager` effective max | see [Resources](#resources) |

Values: [BALANCE § Stats & caps](BALANCE_NUMBERS.md#stats--caps).

## Damage & healing

**Outgoing (player → mob), `DamageSystem`:**

1. Base = player Damage + weapon attack + FlatAttack.
2. × skill action multiplier.
3. × (1 + DamagePercent).
4. Armor, division-based: effective armor = mob armor × (1 − shred) − penetration (shred and penetration are capped); damage × 100 / (100 + effective armor). Never reaches zero.
5. **Multi-crit:** crit chance above 100% guarantees a proc; the remainder rolls for another. Each proc multiplies by CritDamage. Procs are capped.
6. × element multiplier.
7. × vulnerability (strongest application wins; capped).
8. Floor, minimum 1.

Keystone hooks (`KeystoneRules`) add conditional damage, penetration or crit on top.

**Incoming (mob → player):** armor mitigation with the attacker's penetration, then × (1 − DamageReduction), floor, minimum 1.

**Healing, `HealingSystem`:** base = the healer's **Damage** stat (MAG-derived, by design) + flat HealingPower, × skill heal multiplier, × (1 + HealingPercent), then the **same multi-crit pipeline as damage**. Heal-over-time ticks use the heal pipeline without crits. Overheal only matters to the Shared Grace keystone.

**Hit authority:** basic-attack hits are detected on the attacker's client and reported; the server validates the attack ticket, cooldown, range (server positions) and target state before applying damage. Mob basic attacks and skills are cast by the server; the targeted client reports the hit; the server validates it.

Values: [BALANCE § Damage & healing](BALANCE_NUMBERS.md#damage--healing).

## Classes, skills & resources

### Classes

`ClassConfig.Classes` owns identity, derivation coefficients, innate bonuses, `default` and `unlockRequirements`. Resources are **not** defined there; they belong to `ClassBehaviors/<Class>Behavior.CONFIG`. Attack shape and speed belong to the weapon.

### Skills

Each class has five skills (`ClassSkills/<Class>Skills.lua`): three actives, an **ultimate** (slot 4) and a **dash** (slot 5). `SkillRegistry` auto-discovers the modules; `SkillManager` validates and runs a cast:

1. Resolve slot → skill; reject if already casting, on cooldown, stunned, or the world is paused (Horde vote).
2. Check the resource. Ultimates consume **all** current resource above a minimum, and scale with what was spent; they also have a level gate (`§ULT-LEVEL`).
3. Deduct the resource and start the cooldown (CDR applied).
4. If the skill has a cast time, lock movement/skills/attacks for the (reduced) cast time, then execute; an interrupt refunds and resets.
5. Execute through the class module; `BaseSkills` provides targeting (`GetTargetsInShape`, `GetCastDirection`), dashes and visuals.

Skill visuals are range-scoped; only the caster receives `SkillActivated` (§AGX/X21). Buffs from skills go to the BonusManager `buff` source and expire on a tick.

### Resources

`ResourceManager` ticks each player's class resource through the class behavior:

- **Aegis — Determination:** gained from hits dealt, hits taken, kills and crits; passive trickle.
- **Arcanist — Aether:** regenerates, slower in combat; bonus on kills (more on minibosses/bosses); lost when hit.
- **Hunter — Killer Instinct:** gained per hit and crit, and on kills; lost when hit.
- **Life Steward — Life Energy:** regenerates, slower in combat; bonus per wounded ally nearby; kill bonus.

Effective max = class base + the `ResourceMax` bonus + the class's own resource bonus key (talent nodes like "+5 Aether" and gear rolls; §AGX/D-FIX2). The RSV/MAG `ResourceMax` derivation is computed but not read by the bar (`§AGX/D-FIX2-RSV`). Updates are pushed only when the value or the max changes (§AGX/X20). Regen pauses during Horde votes.

Values: [BALANCE § Classes, skills & resources](BALANCE_NUMBERS.md#classes-skills--resources).

## Status effects & elements

`StatusEffectTypes` defines player buffs (DamageReduction, CritChanceUp, AttackSpeedDown, DamageUp), mob debuffs (ArmorReduction, Vulnerability, Slow, Mark), damage over time (generic, Sundering bleed, Frost) and crowd control (Stun, Immobilize, Silence).

`SkillEffects` applies and ticks mob effects:

- DoTs tick on an interval and scale with the caster's damage; numbers are batched (§SCALE/S5).
- ArmorReduction is written to a mob attribute that the damage pipeline reads.
- Slow changes WalkSpeed; pull/knockback move the root part; Taunt sets the mob's forced target.
- At max stacks, a re-apply refreshes only if the new duration is longer; Vulnerability keeps the stronger multiplier.
- Dead or destroyed mobs are cleaned up; DoT and Thorns kills go through the normal death path (§AGX/X12).

Player stun and slow from mobs are recomputed from per-effect expiry attributes and a stamped base walk speed (§AGX/X13), so overlapping effects restore correctly; knockdown clears them.

**Elements:** a four-element cycle (Wood → Earth → Water → Fire → Wood). Strong and weak matchups multiply damage; None is neutral. Basic attacks use the weapon's element, skills their own, mobs a `MobElement` attribute.

Values: [BALANCE § Elements](BALANCE_NUMBERS.md#elements).

---

## Gear

Weapons and armor share one progression model, built from shared factories (`EquipmentRefinement`, `EquipmentTierSystem`, `EquipmentBonusSystem`) over `GearUpgradeConfig`.

- **Weapon:** base attack scales by level bracket, plus refinement and a tier bonus. Weapon level is capped by account level. Weapon XP comes from kills near the weapon's level (armor XP was removed).
- **Armor:** base defense and health, same scaling.
- **Random bonuses:** each item has a bonus pool ordered by priority; the tier decides how many pool entries unlock and how many slots are filled. Rolls map onto BonusManager stats (`mana`→Aether, `focus`→KillerInstinct, `lifeEnergy`→LifeEnergy, healing and status-resist rolls live since §AGX/D-FIX2). **Reroll** replaces all bonuses for Merits.
- **Refinement** (+0 → +15): per-step success chance and Merit cost; safe ceilings every three steps; failures can drop a level but never below the ceiling. **Temper pity** fills per failed attempt by the step inside the band; reaching the band threshold jumps straight to the next ceiling, clamped to the chapter cap (the temper is kept when the clamp cuts it short, §AGX/X9). Chapter caps refuse attempts beyond the chapter's max.
- **Tier** (I → XII): costs Essence and a minimum refinement; resets refinement and temper; capped per chapter.
- **Visuals:** `VisualEquipmentManager` clones weapon/armor models from `ServerStorage.Models` and welds them; it re-attaches on respawn and class switch, wired once per player.
- **Accessories:** one Trinket and two Rings (`InventoryManager`, BonusManager `acc_*` sources). Boss drops; more design is post-alpha.

Values: [BALANCE § Gear](BALANCE_NUMBERS.md#gear).

## Mobs

- **Registry:** `MobRegistry` auto-loads `Mobs/*` and scales stats by level with a power curve; difficulty multipliers apply after level scaling, run modifiers on top. `GetScaledMob` clamps bad overrides.
- **Mobs today:** Zombie (normal), Troll and Ogre (minibosses, with Enrage), Iron Warden (boss, CentralBoss only, phase-based with adds).
- **Mob skills:** `MobSkillRegistry` auto-loads `MobSkills/*` (GroundSlam, Roar); `MobBehaviors` adds pluggable behaviors (Enrage, BossPhases).
- **AI (`MobAI`):** a state machine (patrol → chase → attack/skill); in Horde, 360° targeting. Target choice prefers a taunt, then the closest valid player. One shared per-frame snapshot serves every mob (§PERF/F1). Mob cast events go only to nearby clients. Mob physics is server-owned (§AGX/X45).
- **Frenzy:** mobs that stay alive too long speed up (`§FRENZY1`); bosses opt out.

Values: [BALANCE § Mobs, waves & modes](BALANCE_NUMBERS.md#mobs-waves--modes).

## Waves, modes & game state

**Difficulty:** Normal / Hard / Nightmare, with a level requirement. Chosen in the Lobby, validated on arrival, fixed for the run. It scales mob HP/damage/armor/speed, counts and intervals, and rewards.

**Game state machine (`GameStateManager`):** Idle → Preparing → Defending → Victory / Defeat. The **start gate** waits until every roster player's client is ready **and** their data has loaded, or a timeout that starts once players are present; Horde then auto-starts, Lane and CentralBoss show Start. Victory/Defeat return everyone to the Lobby after a delay. Late joiners ask for the state on mount (§AGX/UX-02); Horde also pushes it through ReadyGate.

**LaneDefense (`MobSpawner`):** a fixed list of hand-crafted waves with guaranteed minibosses; each wave's mob level follows the party anchor level (re-anchored whenever a player's data loads). A tactical vote runs at each wave start and the wave waits for it. Clients can't start waves before the game starts (§AGX/X5). Past the last wave a procedural generator exists but is unused.

**HordeMode (`HordeModeSpawner`):** each player carries a ring of spawn markers (resizable Parts, positioned on demand). Spawns pick a marker far enough from every player, respecting an alive cap and a phase table (interval, weights, speed) that advances with time; the mob level climbs on a timer. A run lasts a fixed amount of **play time** (votes pause it); then the spawner stops, the arena must be cleared, and Victory fires. HighestWave counts levels **completed**.

**CentralBoss (`BossEncounter`):** spawns the boss on Defending; health scales with player count; phases change skills, speed and damage and summon adds; the kill credits the whole eligible party.

**Game modes** are defined in `GameModeConfig` (availability, player counts, Horde mob and reward multipliers); matchmaking re-checks availability on the server.

Values: [BALANCE § Mobs, waves & modes](BALANCE_NUMBERS.md#mobs-waves--modes).

## Defense line

Lane only (`DefenseLine/*`): `DefenseDetection` checks mob distance on the X axis; when a mob reaches the line, `DefenseHealth` takes a **percentage of max HP** based on mob tier and its remaining HP, times the combo multiplier (`DefenseCombo`: consecutive breaches within a window stack up to a cap, then decay). Max HP depends on the chapter. The line changes colour as it drops; regen exists but is off. Breach dissolves play on the client (§AGX/X35). The line only takes damage while Defending.

Values: [BALANCE § Defense line](BALANCE_NUMBERS.md#defense-line).

## Death & regen

**Two phases (`DeathSystem`):**

1. **Knocked down:** crawl speed, no skills or attacks, the resource drains, a Life Steward's Genesis can revive.
2. **Dead:** respawn button; one queued respawn at a time.

**Party wipe:** when everyone is down, the run pauses for a decision window. Each run has free wipe-revives by difficulty, then one paid in Essence, offered only to players who can afford it; revived players get brief invulnerability. With nothing left, the run ends in Defeat. No vote or pause runs over the Defeat/Victory screen.

**HP regen** in combat places is a small percentage of max HP per vitals tick.

Values: [BALANCE § Death & regen](BALANCE_NUMBERS.md#death--regen).

## Rewards

**On each kill, `KillRewardManager`:**

1. Player XP, shared equally by eligible party members in range. Dead players get none; knocked-down players do. XP depends on the player's own level requirement, mob tier, the level gap, mode and danger bonus.
2. Weapon XP for the killer.
3. **Personal drops:** every eligible party member (and always the killer) rolls the mob's drop table, scaled by **their own** level (§AGX/X44).
4. Kill callbacks (achievements, quests).
5. `MobDeath` to nearby clients (death VFX).

Wave completion also grants XP. Merit amounts scale with level and the mob-vs-player level gap; Essence drops are flat. Mode, difficulty, Bounty Board and MeritBonus each apply once. XP HUD and weapon-XP pushes are batched.

Values: [BALANCE § Rewards](BALANCE_NUMBERS.md#rewards).

## Cards, votes & run modifiers

`CardRegistry` defines three card types: **supply** (Horde, beneficial), **threat** (Horde, risk for reward; each vote draws one card from each lane: Greed, Control, Relief) and **tactical** (Lane, per wave). Some cards are limited to certain waves or have cooldowns.

`VoteManager` runs a vote: draw three cards, show `VoteUI`, close early when everyone has voted, majority wins with a random tie-break, apply the card. It validates the vote index and voter eligibility and never resolves twice (§AGX/X30). Personal votes exist for per-player rewards (e.g. the respec-fragment roll). Horde votes pause the world server-side (§AGX/X7).

`RunModifiers` holds per-run scalars (mob HP/damage/armor/speed, spawn interval, mob count, Merit scalar, danger bonus, extra minibosses) with timed entries and hard caps; it resets on return to the Lobby. The **danger bonus** raises XP for accepting threats.

Values: [BALANCE § Cards and votes](BALANCE_NUMBERS.md#cards-and-votes).

## Quests & NPCs

**NPCs (`NPCManager`)** are data-driven per place (`LobbyNPCRegistry`). Interaction goes through a native `ProximityPrompt` (UI-D5); the server range-checks every `NPCInteract` and `NPCResponse` and routes by type:

| Type | Lobby NPCs | Handler |
|---|---|---|
| Shop | Grimjaw (Blacksmith), Mirael (Enchantress) | `ShopHandler` (items from `ShopConfig`) |
| Quest | Captain Aldric | `QuestHandler` |
| Lore | Elder Theron, Lyris | `LoreHandler` (flags persist in `data.Account.LoreFlags`) |
| Teleport | Warden Kael | `TeleportHandler` |
| Matchmaking | Commander Vex | `MatchmakingHandler` |
| WeaponSmith | Durgan (refine), Kaelen (tier), Sylwen (reroll) | `WeaponSmithHandler` |

NPC panels register with the PanelStack and close when the player walks away (`useNpcDistanceClose`).

**Quests (`QuestHandler`):** Available → Accept → In progress → Ready to turn in → Completed (repeatables loop). Progress persists in `data.Account.Quests`. Objectives hook kills and completed runs. Turn-in is atomic. Rewards: Merits, Essence, and XP as a flat amount, a percent of the level requirement, or levels' worth.

Values: [BALANCE § Quests](BALANCE_NUMBERS.md#quests).

## Achievements

`AchievementManager` tracks per-player stats and unlocks tiered achievements from `AchievementConfig`.

- **Stats tracked:** kills (total, by mob id, by tier), hits dealt/received, Merits collected, Essence earned, waves survived, highest wave, damage dealt/taken, crits, best combo, healing done, revives, highest weapon level, talent nodes allocated, cap-mastery boss kills, account level.
- **Hooks:** kills, `HitTracker` per-hit callbacks, currency adds, wave/level completion (Lane waves and Horde levels).
- **Tiers:** 10 per achievement (one-shot `veteran`: 1). Categories: Combat, Survival, Healer, Collection, Dedication, Weapon, Medals, Mastery.
- **Rewards:** Merits, Essence, `RespecToken` (grants a `respec_scroll` item), `AppearanceChange` (banks a free change), `TalentPoint` (+1 permanent bonus point, ledger-guarded and back-paid on login).
- **Boss medals and cap mastery:** medals count kills of each tier boss; cap mastery counts a boss kill at or below its design level (`iron_warden` ≤ 50, then 100/150/200). Only the Iron Warden exists.
- Unlock toasts go through ReadyGate and show as Notify banners. Each kill evaluates synchronously (`§AM5`).

Values: [BALANCE § Achievements](BALANCE_NUMBERS.md#achievements).

## Talents

**Tree:** one shared web of 300 allocatable nodes plus a free Origin (`TalentTreeConfig`), class-agnostic by rules but class-biased by geography: an inner attribute ring, a middle hybrid ring and outer mastery branches, 15 branches in total, each ending in a **keystone**.

Design pillars (from the proposal, now implemented):

- Small nodes are mostly travel power; notables are mini-payoffs; keystones change how you play rather than adding raw numbers.
- Economy nodes (XP, Merits) sit on outer utility branches so pure combat builds never need them.
- The point budget can't fill the tree, so builds must specialise.

**Points** come from the sum of owned weapon levels (all classes) plus bonus points from achievements.

**Allocation (`TalentManager`):** start from the Origin, each new node needs an allocated neighbour, level requirements apply, under a per-player lock. **Refund** of a single node isn't implemented on the server yet (`§AGX/UI-P2-REFUND`); **respec** clears everything.

**Effects:** `TalentEffectAggregator` writes stat nodes to the BonusManager `talent` source. **Keystone rules** run in `StatsManager/KeystoneRules` (combat hooks) and `StatsManager/PartyAura` (Patron Saint, Fortune Favors). A keystone whose rule isn't implemented yet shows "(coming soon)" and its penalty is skipped (`TalentTreeConfig.IMPLEMENTED_RULES`, shared with the client). `TalentTreeValidator` checks stat names at first require.

**UI:** radial layout transform over the config grid, per-branch tints, pan/zoom, touch select-then-Allocate (UI-D12).

Values: [BALANCE § Talents](BALANCE_NUMBERS.md#talents).

## Shop, inventory & consumables

**Global shop (`ShopManager`, `GlobalShopUI`):** three tabs.

- **Cosmetics** and **Consumables** are bought with Merits or Essence under a per-player purchase lock, deduct-first. Unusable items are refused on the server. Refunds are raw.
- **Rotation (§AGX/D7):** buffs and cosmetics rotate per player on fixed UTC periods; staples never rotate. The stock is a deterministic draw from `(UserId, tab, period, roll)`, so rejoining can't re-roll it and nothing is saved when it flips. The server refuses items outside the player's current rotation (with a short grace after a flip), in the global shop and the NPC route. **Refresh now** re-rolls one tab for Essence, with a daily cap, a guaranteed change, and stale-request protection.
- **Premium** (Robux) routes through `MonetizationService` ([Monetization](#monetization)).

**Inventory (`InventoryManager`):** stacking items in `data.Account.Inventory` (consumables, respec fragments and scrolls), plus the accessory slots.

**Consumables (`ConsumableEffects`):** used from the Inventory **in combat places only**. The server checks ownership, alive state, the Horde pause and a per-item cooldown; refuses wasteful uses (full HP, full resource); then consumes the item and applies the effect. Heals tick over a short time and stop on knockdown, death or leave, and pause during Horde votes. Buffs are timed BonusManager sources that **refresh** instead of stacking and end on leave or teleport.

Values: [BALANCE § Shop & monetization](BALANCE_NUMBERS.md#shop--monetization).

## Monetization

`MonetizationService` owns `ProcessReceipt`, the GamePass cache and prompts, in all five places. It registers only grants of type AppearanceChange, Cosmetics or GamePass, and refuses to prompt a bundle that contains an item also sold for Merits/Essence. Every Premium entry is disabled until Pablo creates the products. VIP adds a chat tag in every place (`Modules/VipTag.lua`).

Rules: [DESIGN_DECISIONS § Monetization](DESIGN_DECISIONS.md#monetization). Prices: [BALANCE § Monetization](BALANCE_NUMBERS.md#monetization-robux).

## Chapters & class mastery

`ChapterConfig` splits levels into four 50-level chapters. Each chapter caps refinement and tier, and names the Ascension Crest needed to advance. The planned gate "clear the chapter boss achievement to level past each 50" is `§DISC/D5` (not wired). `ClassMasteryConfig` (milestones, second-weapon gate, role seals) is dormant.

Values: [BALANCE § Chapters](BALANCE_NUMBERS.md#chapters).

## Party, matchmaking & teleport

- **PartyManager (Lobby):** create, invite (with timeout), kick, promote, leave, disband; leadership passes on disconnect; parties grant an XP bonus through `BonusExpSystem` (more for friends). Level-gap checks live in the shared `PartyRequirements`, used at invite **and** at launch.
- **MatchmakingManager:** per-mode queues with the party as a unit; solo players get a party automatically; a countdown, then launch. Leaving, kicking, joining or disbanding during the countdown cancels the queue (§AGX/X15). Difficulty level floors are enforced on explicit picks.
- **TeleportManager:** reserves a server per match and sends mode, difficulty and party data; retries with backoff; handles `TeleportInitFailed` with a timeout and Retry (§AGX/X14).
- **TeleportDataReader** (combat places): public servers bounce players to the Lobby; the place's own mode wins over the payload; level floors are re-checked; difficulty resolves once. Applies the party-picked class if it's unlocked.
- **ReturnTeleporter:** sends everyone back to `Shared.PlaceIds.Lobby` with a return reason (shown as a toast in the Lobby).

Values: [BALANCE § Party](BALANCE_NUMBERS.md#party), [§ Matchmaking](BALANCE_NUMBERS.md#matchmaking).

## Leaderboards & Power

- **LeaderboardManager:** OrderedDataStore boards (Power, HighestWave, TotalPlayTime), persisted per player on a long staggered interval and on leave; reads are cached per board; the viewer's own row is substituted live.
- **Power (`GearRating`):** a weighted score over level, weapon, armor, accessories, talents and mastery, with a prestige multiplier from achievement tiers and highest wave. It's the `Power` leaderstat. It refreshes on setup and level-up only (`§14-POWER`).

Values: [BALANCE § Gear rating](BALANCE_NUMBERS.md#gear-rating-power), [§ Leaderboards](BALANCE_NUMBERS.md#leaderboards).

## Cosmetics & animation

**Server (`CosmeticManager/`):**

- `init.lua` orchestrates: wires `GetWardrobe` / `EquipCosmetic` / `UnequipCosmetic`, sets up each player once (per-player Janitor), and re-applies visuals after each spawn.
- `PlayerCosmeticManager`: wardrobe ownership, equip with ownership and class-lock checks, and visual application. The server applies visuals so they replicate to everyone.
- `MobCosmeticManager`: mob variant skins (colour/material overrides, effects).

**Catalog (`CosmeticConfig`):** two slots, **headgear** and **outfit**. Outfits use `visual.type = "color"` (recolour R6 parts); `"model"` is a stub (`§16-HEADGEAR`). Items have rarity and an optional class lock; class defaults and a small starter wardrobe are owned from the start. Wardrobe data: `data.Account.Wardrobe { owned, equipped }`. Mob variants exist for Zombie, Ogre and Troll.

**Client:** `CosmeticClient` caches the wardrobe and sends equip requests; UI subscribes to its change events. `WardrobeUpdate` is request/response (not ReadyGate-routed, by design).

**Character appearance (`CharacterManager`):** character creation on first login (gender, body/head/hair models, skin/hair/clothing colours), routed through ReadyGate. Templates fan out by gender and body model; the hair-accessory weld sequence is deliberately intricate ([ARCHITECTURE § Decided against](ARCHITECTURE.md#decided-against)). Re-creation needs an unlocked appearance change (free at level 50, then paid).

**Animation:** `AnimationConfig` holds the ids (players per class, mobs, emotes). The client `AnimationSystem` owns playback: per-character track cache and category-based exclusion (idle, movement, attack, skill, emote, death). The server never plays animations directly. Class attack animations are placeholders (`§16-ANIM`).

## Client systems

| Module | Job |
|---|---|
| `NetworkManager` (client) | Deferred listeners; the `ServerReady` watchdog and Rejoin banner |
| `InputSystem` | Keyboard, gamepad and touch; contexts `Combat`, `Lobby`, `UI`; rebinding in Settings → Controls |
| `CameraSystem` | Per-place modes: free (Lobby), fixed isometric (Lane), boss view, top-down (Horde) |
| `MovementSystem` | Constraints: no jump, face direction/point/mouse, joystick aim |
| `PlayerAttack`, `ClientProjectile`, `SharedGeometry` | Instant attack animation and local hit detection; shape math shared with the server |
| `SkillInput`, `SkillVisuals`, `MobVisuals` | Skill requests; client VFX for skills and mob casts |
| `DamageNumbers` | Pooled, batched floating numbers (own vs ally budgets, crit/DoT styles) |
| `LoadingScreen` | Imperative overlay before React mounts; dismissed on `ServerReady` or a failsafe |
| `TalentClient`, `AchievementClient`, `ResourceCache`, `SceneController`, `Locale` | State caches and helpers (Locale is English only) |

UI structure: [ARCHITECTURE § UI](ARCHITECTURE.md#ui).

## Sound

`SoundManager` (client) has Music, SFX and UI groups with per-group volume, master mute and music crossfade. Every sound id is still a placeholder (`§16-SFX`).
