# BALANCE NUMBERS — Complete Gameplay Reference

> Maintained reference for all gameplay numbers. Last updated March 2026 (post card/vote system).
>
> **Updated 2026-09-26 (§AGX):** economy pass X23/X25/X41/X42/X43. Sections touched: §1 Respec, §9 Difficulty, §10 Refinement + Temper Pity, §17 Waves, §18 Drops, §19 Death, §29 Cards/Quests, §30 Quests, §33 Economy Anchor, §34 Daily Login, §47 Respec Economy.

---

## Table of Contents

1. [Player Progression](#1-player-progression)
2. [Primary & Derived Stats](#2-primary--derived-stats)
3. [Stat Caps](#3-stat-caps)
4. [Class Definitions](#4-class-definitions)
5. [Class Skills](#5-class-skills)
6. [Class Resource Systems](#6-class-resource-systems)
7. [Elemental System](#7-elemental-system)
8. [Damage & Healing Formulas](#8-damage--healing-formulas)
9. [Difficulty Tiers](#9-difficulty-tiers)
10. [Weapon System](#10-weapon-system)
11. [Class Weapons](#11-class-weapons)
12. [Armor System](#12-armor-system)
13. [Class Armors](#13-class-armors)
14. [Mob Definitions](#14-mob-definitions)
15. [Mob Scaling](#15-mob-scaling)
16. [Mob Skills](#16-mob-skills)
17. [Wave Config](#17-wave-config)
18. [Drop Tables](#18-drop-tables)
19. [Death System](#19-death-system)
20. [Defense Line](#20-defense-line)
21. [Projectile Config](#21-projectile-config)
22. [Shop Prices](#22-shop-prices)
23. [Consumables](#23-consumables)
24. [Talent Tree](#24-talent-tree)
25. [Achievements](#25-achievements)
26. [Accessories](#26-accessories)
27. [Game Modes & Matchmaking](#27-game-modes--matchmaking)
28. [Horde Mode Spawner Phases](#28-horde-mode-spawner-phases)
29. [Card & Event Vote System](#29-card--event-vote-system)
30. [Quest Rewards (Lobby NPCs)](#30-quest-rewards-lobby-npcs)
31. [Chapter Config](#31-chapter-config)
32. [Class Mastery](#32-class-mastery)
33. [Auction Config](#33-auction-config)
34. [Daily Login Rewards](#34-daily-login-rewards)
35. [Kill Rewards & XP Sharing](#35-kill-rewards--xp-sharing)
36. [Drop Scaling](#36-drop-scaling)
37. [Party System](#37-party-system)
38. [Leaderboard System](#38-leaderboard-system)
39. [Networking & Anti-Cheat](#39-networking--anti-cheat)
40. [Gear Rating Weights](#40-gear-rating-weights)
41. [Run Modifiers & Danger System](#41-run-modifiers--danger-system)
42. [Horde Mode Timing](#42-horde-mode-timing)
43. [Matchmaking](#43-matchmaking)
44. [Combo System (Defense Line)](#44-combo-system-defense-line)
45. [Hit Tracker](#45-hit-tracker)
46. [HP Regen (Combat Modes)](#46-hp-regen-combat-modes)
47. [Respec Economy](#47-respec-economy)
48. [Monetization (Robux)](#48-monetization-robux)

---

## 1. Player Progression

**Source:** `PlayerDataConfig.lua`

| Parameter | Value |
|---|---|
| Points per Level | **1** stat point |
| Class Switch Cooldown | **30 s** |

### XP Curve

Formula: `XPRequired(L) = round(120 × 3.2^b × (1 + 0.05p)^1.9)`

Where `b = floor((Level - 1) / 50)` (chapter index) and `p = (Level - 1) % 50` (position within chapter).

Sample XP requirements:

| Level | XP Required |
|---|---|
| 1 | 120 |
| 2 | ~131 |
| 10 | ~226 |
| 25 | ~580 |
| 50 | ~2,183 |
| 51 | ~384 (chapter 2 reset) |
| 100 | ~6,986 |
| 150 | ~22,354 |
| 200 | ~71,533 |

### Respec Costs

*Updated 2026-09-26 (§AGX/X42).*

| Bracket | Cost |
|---|---|
| All levels | **25 Essence** or **1 Respec Scroll** |

- Was 25 / 40 Essence (below / from level 100) "or 20,000 / 50,000 Merits". The Merit option was never read by any code path and has been removed: Merit income rises ~10× from level 10 to 200, so a Merit price is a wall early and free late. Essence income is flat, so the level-100 step was dropped too.
- The Respec Scroll sells for the same 25 Essence (shop), so it is never worse than a direct respec. Free respec on each ascension boss clear.

### Class Unlock Requirements

All 4 classes are available from day one: Aegis, Hunter, Arcanist, LifeSteward.

---

## 2. Primary & Derived Stats

**Source:** `PlayerDataConfig.lua`

### Primary Stats (Player-Allocated)

All start at **5** base.

| Stat | Abbreviation | Role |
|---|---|---|
| Might | MIG | Physical Damage, Armor |
| Vitality | VIT | Max Health |
| Precision | PRE | Crit Chance; Mages: faster casting |
| Magical Attunement | MAG | Magic Damage, Healing Power, Resource Depth |
| Resolve | RSV | CDR, Status Resistance, Resource Max |

### Derived Stat Bases (Before Class Derivations)

| Derived Stat | Base Value |
|---|---|
| Health | **100** |
| Damage | **10** |
| Armor | **0** |
| Penetration | **0** |
| CritChance | **5%** |
| CritDamage | **1.5×** |
| CastTimeReduction | **0%** |
| CooldownReduction | **0%** |
| StatusResistance | **0%** |
| ResourceMax | **0** |

### Bonus Stat Defaults

All start at **0**: BonusDamage, DamagePercent, BonusHealth, HealthPercent, DamageReduction, CritChance, CritDamage, Armor, Penetration, AoESize, MovementSpeed, MeritBonus, XPBonus, FlatAttack, AttackSpeed, SkillDamage, Thorns, Lifesteal, CooldownReduction, HealingPower, HealingPercent, Determination, Aether, KillerInstinct, LifeEnergy, TauntDuration.

---

## 3. Stat Caps

**Source:** `PlayerDataConfig.lua`

| Stat | Min | Max |
|---|---|---|
| CritChance | 0% | **200%** |
| CritDamage | 1.0× | **1.80×** |
| DamageReduction | 0% | **75%** |
| CooldownReduction | 0% | **40%** |
| CastTimeReduction | 0% | **40%** |
| Lifesteal | 0% | **25%** |
| AttackSpeed | **-50%** | **+75%** |
| StatusResistance | 0% | **60%** |

---

## 4. Class Definitions

**Source:** `ClassConfig.lua`

### Aegis (Melee Tank)

| Parameter | Value |
|---|---|
| Ranged | No |
| Attack Shape | Cone (range=10, angle=120°) |
| Base Attack Speed | **1.4** atk/s |
| Resource | Determination |

**Innate Bonuses:** +10% HealthPercent, +5% DamageReduction

**Stat Derivation (per allocated point):**

| Derived Stat | Formula Coefficients |
|---|---|
| Health | VIT × 15.0 |
| Damage | MIG × 3.0 |
| Armor | MIG × 1.0 |
| Penetration | MIG × 0.25 |
| CritChance | PRE × 0.22 |
| CritDamage | PRE × 0.002 |
| CooldownReduction | RSV × 0.45 |
| StatusResistance | RSV × 1.0 |
| ResourceMax | RSV × 1.5 |

### Arcanist (AoE Ranged Mage)

| Parameter | Value |
|---|---|
| Ranged | Yes |
| Projectile Type | AoE (Circle, range=6.5) |
| Primary Multiplier | **1.2×** (direct hit) |
| Splash Multiplier | **0.8×** |
| Projectile Speed / Lifetime | 45 / 4s |
| Base Attack Speed | **1.0** atk/s |
| Resource | Aether |

**Innate Bonuses:** +10 BonusDamage, +15% DamagePercent

**Stat Derivation:**

| Derived Stat | Formula Coefficients |
|---|---|
| Health | VIT × 10.0 |
| Damage | MAG × 4.0 |
| Armor | MIG × 0.3 |
| Penetration | MAG × 0.45 |
| CritChance | PRE × 0.18 |
| CritDamage | PRE × 0.002, MAG × 0.001 |
| CastTimeReduction | PRE × 0.35 |
| CooldownReduction | RSV × 0.55 |
| StatusResistance | RSV × 0.8 |
| ResourceMax | MAG × 2.5, RSV × 1.0 |

### Hunter (Pierce Ranged DPS)

| Parameter | Value |
|---|---|
| Ranged | Yes |
| Projectile Type | Pierce (maxHits=3, reduction=0.15, minDamageFraction=0.70) |
| Projectile Speed / Lifetime | 70 / 3s |
| Base Attack Speed | **2.2** atk/s |
| Resource | Killer Instinct |

**Innate Bonuses:** +10% CritChance, +0.15× CritDamage, +8% MovementSpeed

**Stat Derivation:**

| Derived Stat | Formula Coefficients |
|---|---|
| Health | VIT × 10.0 |
| Damage | MIG × 1.5, PRE × 2.0 |
| Armor | MIG × 0.5 |
| Penetration | PRE × 0.4 |
| CritChance | PRE × 0.65 |
| CritDamage | PRE × 0.003 |
| CooldownReduction | RSV × 0.45 |
| StatusResistance | RSV × 0.7 |
| ResourceMax | RSV × 1.5 |

### Life Steward (Healer / Support)

| Parameter | Value |
|---|---|
| Ranged | Yes |
| Projectile Type | Pierce (maxHits=1, reduction=0) |
| Projectile Speed / Lifetime | 35 / 3s |
| Base Attack Speed | **0.85** atk/s |
| Resource | Life Energy |

**Innate Bonuses:** +15% HealingPercent, +10% HealthPercent

**Stat Derivation:**

| Derived Stat | Formula Coefficients |
|---|---|
| Health | VIT × 12.0 |
| Damage | MAG × 2.5 |
| Armor | MIG × 0.5 |
| Penetration | MAG × 0.25 |
| CritChance | PRE × 0.18 |
| CritDamage | PRE × 0.002 |
| CastTimeReduction | PRE × 0.25 |
| CooldownReduction | RSV × 0.65 |
| StatusResistance | RSV × 1.0 |
| ResourceMax | MAG × 1.5, RSV × 1.5 |

---

## 5. Class Skills

### Aegis Skills

| Slot | Skill | Cost | CD | Cast | Damage Mult | Shape | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Shield Boomerang | 8 res | 6s | 0s | 1.0× out / 0.7× return | Rect 25×6 | Travel 0.4s, return delay 0.1s |
| 2 | Taunt | 20 res | 12s | 0.5s | 0.45× | Circle r=12 | Pull (str=20, r=12) + Taunt (r=25, 5s) |
| 3 | Sundering Strikes | 16 res | 6s | 0.3s | 0.35× | Cone r=10, 120° | DoT: 0.1× dmg/tick, 1s interval, 6s, max 5 stacks. ArmorReduction: -5%/stack, 6s, max 5 |
| 4 | **Battle Beast** ★ | ALL (min 80) | 75s | 1.0s | 0 | — | DR% = R/(R+100)×100. Allies get 70% of self DR. 6s. Ally cone: r=20, 120°. Unlock lv30 |
| 5 | Rush (Dash) | 8 res | 5s | 0s | — | — | Distance=18, duration=0.25s, unstoppable=true |

### Arcanist Skills

| Slot | Skill | Cost | CD | Cast | Damage Mult | Shape | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Arcane Beam | 12 res | 4s | 0.3s | 1.2× | Rect 40×4 | Line/laser |
| 2 | Frost Bind | 20 res | 12s | 0.6s | 0.5× | Circle r=14 | Mouse-targeted (maxRange=40). Slow -50% 3s. DoT 0.15×/tick 1s for 3s. Element: Water |
| 3 | Arcane Surge | 30 res | 16s | 2.0s | 3.0× | Cone r=30, 90° | Knockback str=30. Element: Fire. Full channel required |
| 4 | **Meteorite** ★ | ALL (min 80) | 75s | 1.5s | base 1.0× | Circle r=20 | Mouse-targeted (maxRange=50). Two hits (Fire+Earth). hitMult = base × (1 + R/100). Vulnerability 1.25× for 3s. Unlock lv30 |
| 5 | Space Jump (Dash) | 10 res | 6s | 0s | — | — | Distance=25, duration=0.15s, unstoppable=false |

### Hunter Skills

| Slot | Skill | Cost | CD | Cast | Damage Mult | Shape | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Swift Arrow | 8 res | 3s | 0s | 1.2× | Pierce maxHits=3, -20%/target | Instant |
| 2 | Barrage | 16 res | 8s | 0s | 0.5× per arrow | Rect 50×3 | 5 arrows, 0.12s delay. Successive hit scaling: +0.25× per hit (1.0→1.25→1.50→1.75→2.0) |
| 3 | Rain of Arrows | 22 res | 14s | 1.2s | 0.8× per wave | Rect 30×12 | Mouse-targeted (maxRange=50). 2 waves, 0.25s delay. Element: Wood |
| 4 | **Eagle Eye** ★ | ALL (min 80) | 75s | 0s | 0 | — | CritChance bonus = R × 0.5. -30% AttackSpeed. 6s. Unlock lv30 |
| 5 | Fast Steps (Dash) | 8 res | 5s | 0s | — | — | Distance=22, duration=0.2s, unstoppable=false |

### Life Steward Skills

| Slot | Skill | Cost | CD | Cast | Heal/Damage | Shape | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Mending Touch | 8 res | 3s | 0.4s | 2.2× heal | r=30 (targeting) | Heals lowest-HP ally (or self). Can crit. Element: Wood |
| 2 | Verdant Bloom | 18 res | 8s | 0.6s | 1.3× AoE heal | r=20 | All allies. HoT: 0.08× per tick, 1s, 6s, max 2 stacks. Element: Wood |
| 3 | Nature's Purge | 14 res | 12s | 0.5s | — | r=25 | Cleanse 1 debuff from all allies. Priority: Stun > Slow > DoT |
| 4 | **Genesis** ★ | ALL (min 70) | 60s | 2.0s | Full heal/revive | r=30 | If knocked-down ally: revive at 70% HP, 20% resource. Else: heal lowest to 100%. Unlock lv30 |
| 5 | Vine Slide (Dash) | 8 res | 6s | 0s | — | — | Distance=22, duration=0.15s, unstoppable=false |

---

## 6. Class Resource Systems

**Source:** `ClassBehaviors/`

### Aegis — Determination

| Parameter | Value |
|---|---|
| Max Resource | **100** |
| Starting | **25** |
| Base Regen | **1.0/s** (always) |
| Gain per Hit Dealt | **+1** |
| Gain per Kill | **+3** |
| Gain per Hit Received | **+2** |
| Gain per Crit | **+0.5** per proc |
| Miniboss Hit Multiplier | **1.5×** |
| Boss Hit Multiplier | **2.0×** |
| Miniboss Received Mult | **1.5×** |
| Boss Received Mult | **2.0×** |

### Arcanist — Aether

| Parameter | Value |
|---|---|
| Max Resource | **100** |
| Starting | **35** |
| Base Regen | **4/s** (out of combat) |
| In-Combat Regen Multiplier | **0.5×** (= 2.0/s) |
| Combat Timeout | **3s** |
| Gain per Hit Dealt | **0** |
| Gain per Kill | **+6** |
| Miniboss Kill Bonus | **+15** |
| Boss Kill Bonus | **+30** |
| Loss per Hit Received | **-3** |

### Hunter — Killer Instinct

| Parameter | Value |
|---|---|
| Max Resource | **100** |
| Starting | **15** |
| Base Regen | **3/s** |
| Gain per Hit Dealt | **+0.6** |
| Gain per Crit | **+2** |
| Multi-Crit Bonus | **0** |
| Gain per Kill | **+3** |
| Loss per Hit Received | **-2** |

### Life Steward — Life Energy

| Parameter | Value |
|---|---|
| Max Resource | **100** |
| Starting | **30** |
| Base Regen | **4/s** (out of combat) |
| In-Combat Regen Multiplier | **0.5×** (= 2.0/s) |
| Combat Timeout | **3s** |
| Proximity Range | **35** studs |
| Proximity HP Threshold | **60%** |
| Proximity Bonus Per Ally | **+2/s** per wounded ally |
| Max Proximity Allies | **3** |
| Gain per Hit Dealt | **0** |
| Gain per Kill | **+2** |
| Miniboss Kill Bonus | **+6** |
| Boss Kill Bonus | **+15** |
| Loss per Hit Received | **0** |

---

## 7. Elemental System

**Source:** `ElementalSystem.lua`

Cycle: **Wood → Earth → Water → Fire → Wood**

| Matchup | Multiplier |
|---|---|
| Attacker beats Defender | **1.25×** (Strong) |
| Defender beats Attacker | **0.85×** (Weak) |
| Same element | **1.0×** (Neutral) |
| Either is None / unrelated pair | **1.0×** (Neutral) |

---

## 8. Damage & Healing Formulas

### Outgoing Damage Pipeline (Player → Mob)

**Source:** `DamageSystem.lua` — 8-step pipeline

```
1. BaseAttack    = PlayerDamage + WeaponAttack + FlatAttack
2. × ActionMultiplier       (skill coefficient, default 1.0)
3. × (1 + DamagePercent/100)  (percent damage bonus)
4. × ArmorMitigation        = 100 / (100 + effectiveArmor)
       effectiveArmor = max(0, mobArmor × (1 - armorReduction%/100) - playerPenetration)
5. × CriticalHit            (multi-crit system, see below)
6. × ElementalMultiplier    (1.25 / 1.0 / 0.85)
7. × VulnerabilityMultiplier (from debuffs on target)
8. floor, min 1
```

### Armor System

**Source:** `ArmorSystem.lua`

Division-based formula (NOT subtraction):
```
effectiveArmor = max(0, armor - attackerPenetration)
armorMultiplier = 100 / (100 + effectiveArmor)
reducedDamage = max(1, incomingDamage × armorMultiplier)
```

100 armor → 50% reduction. 200 armor → 33% reduction. Diminishing returns, never 100%.

### Critical Hit System

**Source:** `CriticalSystem.lua`

- **CritChance cap:** 200%
- **CritDamage cap:** 1.80×
- **Geometric multi-crit:**

```
guaranteedProcs = floor(critChance / 100)
overflowChance  = (critChance % 100) / 100
extraProc       = random < overflowChance ? 1 : 0
totalProcs      = guaranteedProcs + extraProc
finalMultiplier = critDamage ^ totalProcs
```

Example: 150% crit chance, 1.5× crit damage → 1 guaranteed proc + 50% chance of second → `1.5^1` or `1.5^2` = 1.5× or 2.25×.

### Incoming Damage (Mob → Player)

```
1. ArmorReduction = 100 / (100 + effectiveArmor)
     effectiveArmor = max(0, playerArmor - attackerPenetration)
2. × (1 - DamageReduction/100)   (capped at 75%)
3. floor, min 1
```

### Healing Formula

**Source:** `HealingSystem.lua`

```
baseHeal = MAG-derived Damage + flat HealingPower
heal = baseHeal × skillHealMultiplier
heal × (1 + HealingPercent / 100)
```

**Critical Heal (capped):**
- Max **100%** crit chance (no multi-crit for heals)
- CritDamage capped at **1.50×** for heals (vs 1.80× for damage)
- Single roll: `random(100) <= clampedChance`

---

## 9. Difficulty Tiers

**Source:** `DifficultyConfig.lua` · *Updated 2026-09-26 (§AGX/X25): mob multipliers aligned to the code.*

| Parameter | Normal | Hard | Nightmare |
|---|---|---|---|
| Required Level | — | **30** | **80** |
| HP Mult | 1.0 | **1.45** | **2.15** |
| Damage Mult | 1.0 | **1.25** | **1.6** |
| Armor Mult | 1.0 | **1.15** | **1.35** |
| Speed Bonus | 0 | **+1** | **+2** |
| Count Mult | 1.0 | **1.10** | **1.20** |
| Interval Mult | 1.0 | **0.95** | **0.90** |
| Merit Mult | 1.0 | **1.25** | **1.75** |
| Essence Mult | 1.0 | **1.25** | **2.0** |
| XP Mult | 1.0 | **1.25** | **1.5** |

---

## 10. Weapon System

**Source:** `WeaponConfig.lua`

### Level Scaling

- Scale percent: **5%** per 10 levels
- Formula: `multiplier = (1 + 0.05) ^ floor(level/10)`

### XP System

| Parameter | Value |
|---|---|
| XP Level Range | ±10 levels from weapon level |
| XP Base | **1** per kill |
| XP Mob Multipliers | Normal=1, Mini=5, Boss=10 |
| XP Required Formula | `round(80 + 8 × weaponLevel²)` |

Sample XP thresholds: Lv1→2: **88**, Lv10→11: **880**, Lv50→51: **20,080**

### Refinement System

**Source:** `GearUpgradeConfig.lua`, `EquipmentRefinement.lua` · *Updated 2026-09-26 (§AGX/X43): +11→+15 softened; +0→+11 unchanged.*

**Refinement resets to +0 on tier upgrade.** Temper also resets.

| Refinement | Success % | Cost (Merits) |
|---|---|---|
| +0 → +1 | 100% | 300 |
| +1 → +2 | 100% | 500 |
| +2 → +3 | 100% | 800 |
| +3 → +4 | 90% | 1,200 |
| +4 → +5 | 80% | 1,800 |
| +5 → +6 | 70% | 3,000 |
| +6 → +7 | 60% | 5,000 |
| +7 → +8 | 50% | 8,000 |
| +8 → +9 | 40% | 12,000 |
| +9 → +10 | 30% | 18,000 |
| +10 → +11 | 22% | 27,000 |
| +11 → +12 | **20%** (was 15%) | **30,000** (was 40,000) |
| +12 → +13 | **18%** (was 10%) | **36,000** (was 60,000) |
| +13 → +14 | **14%** (was 6%) | **42,000** (was 90,000) |
| +14 → +15 | **10%** (was 3%) | **50,000** (was 140,000) |

- **Max refinement:** +15
- **Ceilings (safe floors):** 0, 3, 6, 9, 12
- **Downgrade on fail:** Deterministic per step position — steps 1–2 above floor: no loss; step 3 above floor: lose 1 level (never below floor)
- **Chapter cap:** attempts at or above `ChapterConfig.MAX_REFINE` (+8 / +11 / +13 / +15) are refused. Only attempts from +11 up changed in §AGX/X43, and Chapter 2's last possible attempt is at +10, so Chapters 1–2 are identical to before.

**Expected Merits per climb from +0** (exact DP of the code rules, confirmed by a 40,000-trial Monte Carlo):

| Target | Before §AGX/X43 | After | p90 after |
|---|---|---|---|
| +8 | 34.5k | 34.5k | 52k |
| +11 | 253k | 253k | 419k |
| +12 | 494k | **454k** | 571k |
| +13 | 1.08M | **649k** | 918k |
| +15 | 2.39M | **960k** | 1.12M |
| **Chapter 4 per piece** (T10 to +12, T11 to +13, T12 to +15) | **3.96M** | **2.06M** | — |

Time per Chapter 4 piece at level 175 (542 × (1 + 0.1 × 174) ≈ 9,970 Merits per 12-wave run on Normal; runs ≈ 10 min, drops are personal so party play earns the same):

| Difficulty | Merits/run | Before | After |
|---|---|---|---|
| Normal | ≈10.0k | ≈66 h | **≈34 h** |
| Hard (×1.25 Merits × 1.10 count) | ≈13.7k | ≈48 h | **≈25 h** |
| Nightmare (×1.75 × 1.20) | ≈20.9k | ≈32 h | **≈16 h** |

Target: 15–25 h per endgame piece for a dedicated (Hard/Nightmare) player. The floor is the three re-climbs through +0…+11 (≈253k each, Chapter 1–2 costs), so going lower means changing `TIER_MIN_REFINE` or the reset-on-tier-up rule, which is a feel decision for Pablo.

### Temper Pity System

*Updated 2026-09-26 (§AGX/X23): rewritten to match the code, which is canonical (`EquipmentRefinement.lua:156-192`).*

1. **Gain per failed attempt, by step inside the band** (`TEMPER_GAIN_BY_STEP = {1, 2, 3}`): a fail from the ceiling itself (step 1, e.g. +9) adds **+1**, from one above (step 2, e.g. +10) adds **+2**, from two above (step 3, e.g. +11) adds **+3**. This is the same in every band.
2. **Pity fires on the failed attempt that reaches the band's threshold**: the item jumps straight to **floor + 3** (the next ceiling) on that same attempt. There is no "next attempt guaranteed" state.
3. **Chapter cap (§AGX/X9):** the jump is clamped to the chapter's max refinement. If the clamp cuts it short, the item lands **on the cap** and the temper bar is **kept** (it pays off once the next chapter raises the cap). If the item is already at the clamped target, the pity does nothing and the normal fail result applies.
4. **Reset:** temper goes to 0 when a normal success lands on a ceiling (+3/+6/+9/+12/+15), when an unclamped pity fires, and on tier upgrade. Successes that don't reach a ceiling keep the temper.
5. Band +0→+3 always succeeds (100%), so its fallback threshold (10) never matters.

| Ceiling Band | Threshold |
|---|---|
| +3 → +6 | **10** |
| +6 → +9 | **18** |
| +9 → +12 | **28** |
| +12 → +15 | **18** (was 36, §AGX/X43) |

The old text here ("next attempt guaranteed", per-band gain, reset on any success) would have cost ≈32.5M Merits to +15 against the code's 2.39M (now 0.96M).

### Tier System

| Tier | Bonus Slots | Value Mult | Pool Unlocks | ATK Bonus % |
|---|---|---|---|---|
| I | 2 | 1.0 | 3 | 0% |
| II | 2 | 1.1 | 4 | 5% |
| III | 3 | 1.2 | 5 | 10% |
| IV | 3 | 1.3 | 6 | 15% |
| V | 3 | 1.4 | 7 | 20% |
| VI | 4 | 1.5 | 8 | 25% |
| VII | 4 | 1.6 | 9 | 30% |
| VIII | 4 | 1.7 | 10 | 35% |
| IX | 5 | 1.8 | 11 | 40% |
| X | 5 | 1.9 | 12 | 45% |
| XI | 5 | 2.0 | 13 | 50% |
| XII | 5 | 2.2 | all | 60% |

### Tier Upgrade Costs (Essence)

**Refinement resets to +0 on tier upgrade.**

| From Tier | Cost | Min Refinement |
|---|---|---|
| I → II | 10 | +1 |
| II → III | 15 | +3 |
| III → IV | 25 | +4 |
| IV → V | 40 | +6 |
| V → VI | 60 | +7 |
| VI → VII | 90 | +8 |
| VII → VIII | 130 | +9 |
| VIII → IX | 180 | +10 |
| IX → X | 250 | +11 |
| X → XI | 350 | +12 |
| XI → XII | 500 | +13 |
| **Total I → XII** | **1,650** | |

Per chapter: Ch1 (I→V) 90, Ch2 (→VIII) 280, Ch3 (→X) 430, Ch4 (→XII) 850 Essence per piece.

### Reroll System

- Currency: **Merits**
- Base cost: **300**
- Tier multiplier: **1.46×**
- Formula: `floor(300 × 1.46^(tier-1))`
- Tier I: 300, II: 438, III: 639, VI: ~1,987

### Starter Weapons

| Class | Starter Weapon |
|---|---|
| Aegis | SwordAndShield |
| Arcanist | ApprenticeWand |
| Hunter | ShortBow |
| LifeSteward | LifeTotem |

---

## 11. Class Weapons

### Aegis Weapons

#### Sword & Shield (Starter)

| Param | Value |
|---|---|
| Base ATK | **14** |
| ATK Speed | **1.4** atk/s |
| Shape | Cone r=8, 120° |
| Refinement ATK/level | **+1.8** |
| Element | None |

**Bonus Pool:** critChance (1-10), critDamage (5-25), flatAttack (5-20), attackSpeed (1-8), determination (5-15), damageReduction (2-8), skillDamage (3-12), tauntDuration (5-20), lifesteal (1-5), aoeSize (3-10), movementSpeed (2-8), cooldownReduction (2-10), bonusHealth (50-200), thorns (5-15)

#### Tower Shield (Achievement Unlock)

| Param | Value |
|---|---|
| Base ATK | **12** |
| ATK Speed | **1.2** atk/s |
| Shape | Rectangle r=10, w=12 |
| Refinement ATK/level | **+1** |
| Element | None |

**Bonus Pool:** damageReduction (2-10), bonusHealth (30-100), flatAttack (3-15), determination (8-20), thorns (3-12), tauntDuration (8-25), lifesteal (1-4), critChance (1-8), aoeSize (5-15), skillDamage (2-8), cooldownReduction (3-12), critDamage (5-20), movementSpeed (1-5), attackSpeed (1-5)

### Arcanist Weapons

#### Apprentice Wand (Starter)

| Param | Value |
|---|---|
| Base ATK | **15** |
| ATK Speed | **1.0** atk/s |
| Explosion Range | **6** |
| Refinement ATK/level | **+2** |
| Element | None |

**Bonus Pool:** critChance (1-8), critDamage (5-20), flatAttack (4-14), skillDamage (2-10), mana (5-15), cooldownReduction (1-5), damageReduction (1-5), lifesteal (1-3), aoeSize (5-20)

#### Arcane Focus (classLevel 15 Unlock)

| Param | Value |
|---|---|
| Base ATK | **26** |
| ATK Speed | **0.9** atk/s |
| Explosion Range | **10** |
| Refinement ATK/level | **+4** |
| Element | None |

**Bonus Pool:** critChance (2-12), critDamage (8-35), flatAttack (8-22), skillDamage (4-16), mana (8-25), cooldownReduction (2-8), damageReduction (2-7), lifesteal (1-5), aoeSize (10-30)

### Hunter Weapons

#### Short Bow (Starter)

| Param | Value |
|---|---|
| Base ATK | **10** |
| ATK Speed | **2.2** atk/s |
| Pierce maxHits | **1** |
| Damage Reduction | **0** |
| Refinement ATK/level | **+1.6** |
| Element | None |

**Bonus Pool:** critChance (2-12), critDamage (8-30), flatAttack (3-12), attackSpeed (2-10), focus (3-10), skillDamage (2-10), movementSpeed (2-8), lifesteal (1-4), damageReduction (1-5)

#### Hunting Bow (classLevel 15 Unlock)

| Param | Value |
|---|---|
| Base ATK | **22** |
| ATK Speed | **1.8** atk/s |
| Pierce maxHits | **3** |
| Damage Reduction | **-15%** per target |
| Refinement ATK/level | **+3** |
| Element | None |

**Bonus Pool:** critChance (4-18), critDamage (10-40), flatAttack (6-20), attackSpeed (1-6), focus (5-15), skillDamage (4-14), movementSpeed (3-10), lifesteal (2-6), damageReduction (2-7)

### Life Steward Weapons

#### Life Totem (Starter)

| Param | Value |
|---|---|
| Base ATK | **9** |
| ATK Speed | **0.85** atk/s |
| Refinement ATK/level | **+1.2** |
| Element | **Wood** |

**Bonus Pool:** healingPower (5-20), healingPercent (3-12), cooldownReduction (2-10), bonusHealth (20-80), lifeEnergy (5-15), statusResistance (3-12), critChance (1-8), critDamage (3-15), skillDamage (2-8), damageReduction (1-5), movementSpeed (2-8), flatAttack (3-12), aoeSize (3-10), lifesteal (1-4)

#### Reincarnation Totem (Achievement Unlock)

| Param | Value |
|---|---|
| Base ATK | **10** |
| ATK Speed | **0.8** atk/s |
| Refinement ATK/level | **+1.5** |
| Element | **Wood** |

**Bonus Pool:** healingPower (8-30), healingPercent (5-18), cooldownReduction (3-14), lifeEnergy (8-20), bonusHealth (30-100), critChance (2-10), critDamage (5-20), statusResistance (4-15), damageReduction (2-8), skillDamage (3-12), lifesteal (1-5), flatAttack (5-18), movementSpeed (2-8), aoeSize (4-12)

---

## 12. Armor System

**Source:** `ArmorConfig.lua`

Identical structure to weapons. Shares refinement/tier/reroll systems.

### Key Differences from Weapons

| Param | Value |
|---|---|
| Level Scale Percent | **5%** per 10 levels |
| Refinement Max | **+15** |
| Tier Max | **XII** |
| Tier DEF Bonus % | Same table as weapon ATK bonus (0%→60%) |
| Refinement costs | Identical to weapons |
| Tier costs | Identical to weapons |
| Reroll base/mult | 300 Merits / 1.46× |
| XP Required | `round(80 + 8 × armorLevel²)` |

**Refinement resets to +0 on tier upgrade.** Temper also resets.

### Starter Armors

| Class | Starter Armor |
|---|---|
| Aegis | PlateArmor |
| Arcanist | SilkRobe |
| Hunter | LeatherArmor |
| LifeSteward | BarkweaveVest |

---

## 13. Class Armors

### Aegis Armors

#### Plate Armor (Starter)

| Param | Value |
|---|---|
| Base DEF | **12** |
| Base HP | **50** |
| Refinement DEF/level | **+2** |

**Bonus Pool:** damageReduction (2-8), bonusHealth (20-80), determination (3-12), thorns (2-10), statusResistance (3-12), lifesteal (1-4), cooldownReduction (2-8), movementSpeed (1-5), critChance (1-6), flatAttack (3-12), tauntDuration (5-15), skillDamage (2-8), aoeSize (3-10), critDamage (5-15)

#### Fortress Armor (Achievement Unlock)

| Param | Value |
|---|---|
| Base DEF | **18** |
| Base HP | **80** |
| Refinement DEF/level | **+3** |

**Bonus Pool:** damageReduction (4-12), bonusHealth (40-120), thorns (3-12), determination (5-18), statusResistance (4-15), tauntDuration (8-25), lifesteal (1-5), cooldownReduction (2-10), critChance (1-5), aoeSize (3-12), flatAttack (2-8), skillDamage (1-6), movementSpeed (1-3), critDamage (3-10)

### Arcanist Armors

#### Silk Robe (Starter)

| Param | Value |
|---|---|
| Base DEF | **6** |
| Base HP | **30** |
| Refinement DEF/level | **+1** |

**Bonus Pool:** cooldownReduction (2-10), skillDamage (3-12), bonusHealth (15-60), statusResistance (3-12), critChance (2-10), critDamage (5-20), damageReduction (1-5), movementSpeed (2-8), flatAttack (3-12), determination (3-10), aoeSize (3-12), lifesteal (1-4), thorns (2-8), attackSpeed (1-5)

#### Arcane Vestment (Achievement Unlock)

| Param | Value |
|---|---|
| Base DEF | **9** |
| Base HP | **45** |
| Refinement DEF/level | **+2** |

**Bonus Pool:** skillDamage (5-18), cooldownReduction (3-14), critDamage (8-25), critChance (3-12), statusResistance (4-15), bonusHealth (25-80), aoeSize (5-15), damageReduction (2-8), movementSpeed (2-7), flatAttack (4-15), lifesteal (2-6), determination (4-12), thorns (2-8), attackSpeed (1-4)

### Hunter Armors

#### Leather Armor (Starter)

| Param | Value |
|---|---|
| Base DEF | **8** |
| Base HP | **35** |
| Refinement DEF/level | **+1** |

**Bonus Pool:** critChance (3-12), movementSpeed (2-8), critDamage (5-20), attackSpeed (1-6), bonusHealth (15-50), statusResistance (2-10), damageReduction (1-5), skillDamage (3-12), flatAttack (3-12), cooldownReduction (2-8), lifesteal (1-4), determination (3-10), aoeSize (2-8), thorns (1-5)

#### Shadow Cloak (Achievement Unlock)

| Param | Value |
|---|---|
| Base DEF | **5** |
| Base HP | **25** |
| Refinement DEF/level | **+1** |

**Bonus Pool:** critChance (5-15), critDamage (8-30), movementSpeed (3-10), attackSpeed (2-8), skillDamage (4-15), flatAttack (5-18), lifesteal (2-6), cooldownReduction (3-12), statusResistance (2-8), bonusHealth (10-40), damageReduction (1-4), determination (2-8), aoeSize (2-8), thorns (1-4)

### Life Steward Armors

#### Barkweave Vest (Starter)

| Param | Value |
|---|---|
| Base DEF | **8** |
| Base HP | **40** |
| Refinement DEF/level | **+1** |

**Bonus Pool:** healingPower (5-18), bonusHealth (20-80), cooldownReduction (2-10), statusResistance (3-12), healingPercent (3-10), damageReduction (2-8), lifeEnergy (5-15), critChance (1-8), movementSpeed (2-8), critDamage (3-12), flatAttack (2-10), skillDamage (2-8), aoeSize (3-10), lifesteal (1-4)

#### Verdant Regalia (Achievement Unlock)

| Param | Value |
|---|---|
| Base DEF | **11** |
| Base HP | **55** |
| Refinement DEF/level | **+2** |

**Bonus Pool:** healingPower (8-28), healingPercent (5-16), bonusHealth (30-100), cooldownReduction (3-14), lifeEnergy (8-20), statusResistance (4-15), damageReduction (3-10), critChance (2-10), critDamage (5-18), movementSpeed (3-10), skillDamage (3-12), flatAttack (3-14), lifesteal (2-6), aoeSize (4-12)

---

## 14. Mob Definitions

**Source:** `Mobs/` folder

### Zombie (Normal)

| Stat | Base Value |
|---|---|
| Health | **100** |
| Damage | **10** |
| Armor | **2** |
| Knockback Resist | **0** |
| Speed | **5** |
| Attack Range | **4** |
| Attack Cooldown | **1.5s** |
| Perception Range | **25** |
| Attack Duration | **0.5s** |
| Damage Delay | **0.25s** |
| Element | **Earth** |
| Skills | None |

### Ogre (Miniboss)

| Stat | Base Value |
|---|---|
| Health | **500** |
| Damage | **40** |
| Armor | **12** |
| Knockback Resist | **0.6** |
| Speed | **3** |
| Attack Range | **6** |
| Attack Cooldown | **3.0s** |
| Perception Range | **35** |
| Attack Duration | **0.8s** |
| Damage Delay | **0.4s** |
| Element | **Fire** |
| Skills | GroundSlam, Roar |
| Enrage | At 30% HP: +4 speed, 1.6× damage |

### Troll (Miniboss)

| Stat | Base Value |
|---|---|
| Health | **400** |
| Damage | **35** |
| Armor | **8** |
| Knockback Resist | **0.4** |
| Speed | **4** |
| Attack Range | **5** |
| Attack Cooldown | **2.5s** |
| Perception Range | **40** |
| Attack Duration | **0.7s** |
| Damage Delay | **0.35s** |
| Element | **Water** |
| Skills | GroundSlam, Roar |
| Enrage | At 40% HP: +3 speed, 1.4× damage |

---

## 15. Mob Scaling

**Source:** `MobRegistry.lua`

Power curve formula: `Multiplier(level) = ((level + 9) / 10) ^ exponent`

| Stat | Exponent |
|---|---|
| Health | **1.28** |
| Damage | **1.15** |
| Armor | **1.05** |
| Speed | **Not scaled** |

POWER_OFFSET = **9**

### Sample Multipliers

| Level | Health Mult | Damage Mult | Armor Mult |
|---|---|---|---|
| 1 | 1.0× | 1.0× | 1.0× |
| 10 | ~1.76× | ~1.57× | ~1.16× |
| 20 | ~3.32× | ~2.67× | ~1.71× |
| 50 | ~10.6× | ~7.6× | ~4.1× |
| 100 | ~27.0× | ~17.5× | ~7.6× |
| 200 | ~69× | ~39× | ~14× |

Difficulty multipliers are applied **after** level scaling.

---

## 16. Mob Skills

**Source:** `MobSkills/` folder

### Ground Slam

| Param | Value |
|---|---|
| Cooldown | **12s** |
| Start on Cooldown | Yes |
| Targeting Range | 0–10 |
| Damage Multiplier | **2.0×** |
| Shape | Circle r=12 |
| Animation Duration | **1.0s** |
| Damage Delay | **0.6s** |
| Effect | Stun **1.5s** |

### Intimidating Roar

| Param | Value |
|---|---|
| Cooldown | **20s** |
| Start on Cooldown | Yes |
| Targeting Range | 0–999 |
| HP Threshold | Below **50%** |
| Damage Multiplier | **0** (no damage) |
| Shape | Circle r=20 |
| Animation Duration | **1.2s** |
| Damage Delay | **0.8s** |
| Effect | Slow **-50%** for **3s** |

---

## 17. Wave Config

**Source:** `WaveConfig.lua`, `MobSpawner.lua`

### Run Parameters (Lane Defense)

| Parameter | Value |
|---|---|
| Total Waves | **12** |
| Auto-Advance | Yes |
| Auto-Advance Delay | **7s** between waves |

### Hand-Crafted Waves

*Updated 2026-09-26 (§AGX/X25): all 12 Lane waves are hand-crafted (`WaveConfig.lua:25-38`). Counts are Normal; `countMult` and `intervalMult` from §9 apply on top.*

| Wave | Mob Count | Spawn Interval | Mobs | Guaranteed |
|---|---|---|---|---|
| 1 | 10 | 2.5s | Zombie | — |
| 2 | 12 | 2.4s | Zombie | — |
| 3 | 14 | 2.3s | Zombie | — |
| 4 | 16 | 2.1s | Zombie | **Troll** |
| 5 | 18 | 2.0s | Zombie | — |
| 6 | 20 | 1.9s | Zombie | — |
| 7 | 22 | 1.8s | Zombie | **Troll** |
| 8 | 24 | 1.7s | Zombie | — |
| 9 | 26 | 1.6s | Zombie | — |
| 10 | 28 | 1.5s | Zombie | **Ogre** |
| 11 | 30 | 1.4s | Zombie | — |
| 12 | 32 | 1.3s | Zombie | **Ogre** |
| **Total** | **252** | | | **4 minibosses** |

### Procedural Generation (Wave 13+, unused in Lane)

Lane runs stop at wave 12, so this generator only matters for other callers.

| Parameter | Value |
|---|---|
| Base Mob Count | **5** |
| Mob Count Per Wave | **+1** |
| Max Mob Count | **30** |
| Base Spawn Interval | **1.5s** |
| Min Spawn Interval | **0.5s** |
| Interval Decay | **-0.05s** per wave |
| Miniboss Interval | Every **5** waves (starting wave 5) |
| Available Mobs | Zombie |
| Available Minibosses | Ogre, Troll |

### Wave Mob Level Formula (Party Anchor)

When a party anchor level is set (via `TeleportDataReader`):

```
mobLevel = max(1, (partyAnchorLevel - 1) + floor((wave - 1) / 2))
```

| Wave | Level (party lv 10) |
|------|---------------------|
| 1 | 9 |
| 3 | 10 |
| 5 | 11 |
| 7 | 12 |
| 9 | 13 |
| 11 | 14 |

Fallback (no anchor): `mobLevel = waveData.level or waveNumber`

### EliteBounty Card Eligible Waves

Waves where the **EliteBounty** tactical card may appear: **4, 7, 10, 12** only.

---

## 18. Drop Tables

**Source:** `DropTableConfig.lua` + `DropManager.lua`

### Per-Tier Defaults

| Tier | Drop Type | Chance | Min | Max | Scales? |
|---|---|---|---|---|---|
| **Normal** | Merits | 100% | 1 | 3 | Yes |
| **Miniboss** | Merits | 100% | 8 | 15 | Yes |
| | Essence | 30% | 2 | 4 | **No** (flat) |
| **Boss** | Merits | 100% | 25 | 50 | Yes |
| | Essence | 75% | 8 | 20 | **No** (flat) |

### Level Scaling (Merits only)

Formula: `amount = base × (1 + (scaleLevel - 1) × 0.1)`

Essence drops have `noScale=true` — always flat amounts.

### Who Gets Drops

*Updated 2026-09-26 (§AGX/X44).* Drops are **personal, one roll per party member per party kill**: every XP-eligible party member (and always the killer) rolls the mob's drop table independently. Amounts scale with the recipient's **own** level, `scaleLevel = min(mob RewardLevel, max(5, own level))`, and the §36 delta window uses mob RewardLevel − own level. Mode, difficulty, BountyBoard and MeritBonus each apply once. Mob count does not scale with party size, so a party member earns about what a solo player does.

**Per-run budget (Lane, 12 waves, own level L):** Merits ≈ 542 × (1 + 0.1(L−1)) on Normal (≈1.0k at L10, 5.9k at L100, 11.3k at L200); Essence from drops ≈ 4 minibosses × 30% × 3 = **3.6** (×1.25 Hard, ×2 Nightmare).

---

## 19. Death System

**Source:** `DeathSystem.lua`

| Parameter | Value |
|---|---|
| Knockdown Duration | **10s** |
| Knockdown Speed | **4** (default WalkSpeed=16) |
| Resource Drain Rate | **-10/s** |
| Respawn Delay | **1s** |

**Phases:**
1. **Knocked Down** (10s) — crawl speed, no skills/attacks/resource gen, resource drains at -10/s, allies can revive
2. **Dead** — grayscale overlay, respawn button, teleport to spawn on respawn

### Party-Wipe Revive

*Updated 2026-09-26 (§AGX/X25, documents §AGX/X40).* When the whole party is down, the run pauses for a **15 s** decision window.

| Parameter | Value |
|---|---|
| Free wipe-revives per run | Normal **3**, Hard **2**, Nightmare **1** (unknown difficulty → 1) |
| Paid wipe-revives per run | **1**, after the free ones are used |
| Paid price | **25 Essence** (placeholder; ≈6,250 Merits at the §33 anchor) |
| Paid option shown | Only to players who can already afford it |
| Invulnerability after revive | **3 s** |
| Nothing left to offer | The run ends immediately |

---

## 20. Defense Line

**Source:** `DefenseConfig.lua`

### Chapter Max Health

| Chapter | Max HP |
|---|---|
| 1 | **1,500** |
| 2 | **3,500** |
| 3 | **7,000** |
| 4 | **12,000** |

### Breach Damage

Percentage-based formula:
```
BreachDamage = round(MaxHP × BasePct × RemainingHpFactor)
RemainingHpFactor = 0.5 + 0.5 × currentHpPercent
```

| Mob Type | Base % |
|---|---|
| Normal | **4%** |
| Elite | **8%** |
| Miniboss | **14%** |
| Boss | **24%** |

### Combo System

| Param | Value |
|---|---|
| Enabled | Yes |
| Window | **3.0s** |
| Factor | **1.20×** per combo level |
| Max Level | **5** |
| Decay Rate | **1** level/s |

### Detection

| Param | Value |
|---|---|
| Range | **5** studs |
| Check Interval | **0.2s** |

### Visual Thresholds

| State | Threshold |
|---|---|
| Critical | **25%** HP |
| Damaged | **50%** HP |

### Regen

Currently **disabled** (PerSecond=0, Delay=5s).

---

## 21. Projectile Config

**Source:** `ProjectileConfig.lua`

| Projectile | Speed | Lifetime | Hit Type | Params |
|---|---|---|---|---|
| Arrow | **60** | 3s | Single | — |
| Fireball | **40** | 4s | Circle | radius=8, AoE mult=0.75 |
| PiercingArrow | **70** | 3s | Pierce | maxHits=3, -20% per hit |
| FrostBolt | **50** | 3s | Single | mult=1.5 |
| ExplosiveShot | **45** | 3s | Cone | range=10, angle=60°, mult=0.6 |

**Class Defaults:** Arcanist=Fireball, Hunter=Arrow. Fallback=Arrow.

---

## 22. Shop Prices

**Source:** `ShopConfig.lua`

### Cosmetics Tab

| Item | Price | Currency | Level Req |
|---|---|---|---|
| hood_basic | **200** | Merits | — |
| helm_aegis | **500** | Merits | 5 |
| circlet_arcanist | **500** | Merits | 5 |
| mask_hunter | **500** | Merits | 5 |
| dark_knight | **25** | Essence | 10 |
| shadow_robes | **25** | Essence | 10 |
| forest_ranger | **25** | Essence | 10 |

### Consumables Tab

| Item | Price | Currency | Level Req |
|---|---|---|---|
| health_potion | **25** | Merits | — |
| health_potion_large | **100** | Merits | 5 |
| health_elixir | **5** | Essence | 10 |
| mana_crystal | **30** | Merits | — |
| mana_crystal_large | **120** | Merits | 5 |
| power_scroll | **150** | Merits | 5 |
| iron_skin_potion | **150** | Merits | 5 |
| swiftness_elixir *(off, see §23)* | 100 | Merits | 3 |
| fortune_incense | **10** | Essence | 8 |
| crit_oil | **120** | Merits | 5 |
| respec_scroll | **25** | Essence | 10 |

### Premium Tab (Robux)

*§AGX/X40 (2026-09-26):* the Essence Pack, Merit Bundle and Respec Token x3 were **deleted**. Robux no longer buys gameplay currency or anything that converts into it. The Premium catalog and the no-P2W rule are in [§48 Monetization](#48-monetization-robux).

---

## 23. Consumables

**Source:** `ConsumableConfig.lua` (effects, cooldowns), `ShopConfig.lua` (prices), `ConsumableEffects.lua` (use path). *§AGX/X10b (2026-09-26).*

X10 turned off every consumable without a use handler. X10b adds the handler, so these are usable **and** sold again. `ShopConfig` derives `enabled` from `ConsumableConfig.usable`, so the global shop and the NPC shop follow the same flag.

| Consumable | Effect | Duration | Price | Lvl | Cooldown | Max stack | Status |
|---|---|---|---|---|---|---|---|
| Health Potion | Heal **18% max HP** | over 2s | **25** Merits | — | 12s | 20 | ✅ live |
| Greater Health Potion | Heal **35% max HP** | over 2s | **100** Merits | 5 | 20s | 10 | ✅ live |
| Vitality Elixir | Heal **25% max HP** | instant | **5** Essence | 10 | 30s | 5 | ✅ live |
| Mana Crystal | **+25** class resource | instant | **30** Merits | — | 15s | 20 | ✅ live |
| Greater Mana Crystal | **+50** class resource | instant | **120** Merits | 5 | 25s | 10 | ✅ live |
| Power Scroll | **+8%** DamagePercent | 45s | **150** Merits | 5 | 60s | 10 | ✅ live |
| Ironskin Potion | **+12%** Armor ¹ | 45s | **150** Merits | 5 | 60s | 10 | ✅ live |
| Swiftness Elixir | +10% move speed | 30s | 100 Merits | 3 | 45s | 10 | ⛔ off ² |
| Fortune Incense | **+15%** MeritBonus | 120s | **10** Essence | 8 | 120s | 5 | ✅ live |
| Crit Oil | **+8** CritChance (points) | 45s | **120** Merits | 5 | 60s | 10 | ✅ live |
| Respec Scroll | 1 free respec (talents or stats) | — | **25** Essence | 10 | — | 99 | ✅ used from the respec panels |
| Respec Fragment | 4 auto-combine into 1 Respec Scroll | — | not sold | — | — | 99 | passive |

¹ Ironskin is +12% **Armor**. That is not +12% mitigation: armor mitigation is `100 / (100 + armor)`, so it gains less than 12%. While `PlayerDataConfig.BonusStats` has no `ArmorPercent` key, it's applied as a flat Armor bonus of 12% of the player's Armor at use time, excluding its own previous stack. If `ArmorPercent = 0` is added there, `GetTotalStat` applies it as a true percent and no code change is needed.
² No player move-speed modifier exists. The `MovementSpeed` bonus stat has no reader, and WalkSpeed is owned by DeathSystem, MobAI and SkillManager (the X13 `BaseWalkSpeed` contract). The item stays hidden and unbuyable until one of those has a speed hook.

### Use rules (server-side, `ConsumableEffects.Use`)

- **Validation:** the player must own the item, be alive (not knocked down or dead), and the run must not be paused (same gate as §AGX/X7). The item's per-player cooldown must also be clear.
- **No waste:** heals are refused at full HP, restores are refused at full resource, and Ironskin is refused with 0 Armor. A refused use doesn't spend the item.
- **Order:** checks → `InventoryManager.ConsumeItem` → effect. If the effect errors, the item is given back.
- **Cooldown:** one per item id, per player. Different items, like a Health Potion and a Greater Health Potion, don't share one.
- **Stacking:** using the same buff again **refreshes** its duration and doesn't add a second copy. The BonusManager source is `timed_consumable_<id>`. A config can opt in to `stacks = true`, and none do. Buffs from *different* items, or from a card with the same stat, do add up.
- **Heal over time:** the heal is split into 0.25s ticks. It stops if the player is knocked down, dies, leaves, or respawns into a new character.
- **Lifetime:** buffs last only for the current server and end when the player leaves or teleports (lobby → run included). No config sets `persistAcrossTeleport`, which isn't supported yet. Per-player threads live in a Janitor that's destroyed on `PlayerRemoving`.
- **Currency:** everything costs Merits or Essence. Consumables are never sold for Robux (§48, X40).

### Economy notes

- **Sinks:** consumables are a repeatable Merit sink, and Fortune Incense and the Elixir are repeatable Essence sinks. Their cost scales with how often they're used, not with level.
- **Fortune Incense:** 10 Essence for +15% Merits over 120s. It pays off only when 15% of the Merits earned in those 120s is worth more to the player than 10 Essence. It's meant for a dense Merit window, like a Horde wave. *Unspecified:* no Essence↔Merit rate is defined and there's no Merits-per-minute telemetry, so the break-even isn't known. Watch purchases to see whether it's bought at all.
- **Fortune Incense cap:** the +15% adds to talent and gear MeritBonus. Refunds (`raw = true`, X32) ignore it.

---

## 24. Talent Tree

**Source:** `TalentTreeConfig.lua`

All nodes cost **1** point. Start node costs **0** (auto-allocated).

### Vanguard Branch (Defense)

| Node | Type | Effect |
|---|---|---|
| Vitality I | Small | +15 Health |
| Iron Skin I | Small | +3 Armor |
| Vitality II | Small | +20 Health |
| Thick Hide | Small | +2% DR |
| Iron Skin II | Small | +5 Armor |
| **Stalwart** | Notable | +30 Health, +3% DR |
| Vitality III | Small | +3% Health |
| Hardened | Small | +3% DR |
| **Unbreakable** | Keystone | +5% DR, +5% Health. Below 30% HP: +15% DR |

### Ranger Branch (Crit / Attack Speed)

| Node | Type | Effect |
|---|---|---|
| Sharp Eye I | Small | +3% Crit Chance |
| Quick Hands I | Small | +3% Attack Speed |
| Sharp Eye II | Small | +4% Crit Chance |
| Deadly Aim I | Small | +0.1× Crit Damage |
| Quick Hands II | Small | +4% Attack Speed |
| **Eagle Eye** | Notable | +5% Crit Chance, +0.15× Crit Damage |
| Piercing Shot | Small | +5 Penetration |
| Deadly Aim II | Small | +0.15× Crit Damage |
| **Deadeye** | Keystone | +10% Crit Chance. Crits ignore 50% target Armor |

### Spellcaster Branch (Skill Damage / CDR)

| Node | Type | Effect |
|---|---|---|
| Arcane Force I | Small | +3% Skill Damage |
| Haste I | Small | +2% CDR |
| Arcane Force II | Small | +4% Skill Damage |
| Spell Power I | Small | +3% Damage |
| Haste II | Small | +3% CDR |
| **Overcharge** | Notable | +8% Skill Damage, +3% Damage |
| Arcane Mastery | Small | +5% Skill Damage |
| Temporal Flow | Small | +4% CDR |
| **Archmage** | Keystone | +10% Skill Damage, +5% CDR. Skills hitting 3+ targets deal 20% more |

### Support Branch (Utility / Sustain)

| Node | Type | Effect |
|---|---|---|
| Leech I | Small | +1% Lifesteal |
| Wisdom I | Small | +3% XP Bonus |
| Leech II | Small | +2% Lifesteal |
| Fortune I | Small | +5% Merit Bonus |
| Wisdom II | Small | +5% XP Bonus |
| **Prosperity** | Notable | +10% Merit Bonus, +5% XP Bonus |
| Siphon | Small | +3% Lifesteal |
| Fleet Foot | Small | +5% Movement Speed |
| **Paragon** | Keystone | +10% XP, +10% Merits. Party members in range gain 50% of your XP/Merit bonuses |

### Cross-Branch Connectors

| Node | Tags | Effect |
|---|---|---|
| Brutality | Vanguard/Ranger | +5 Flat Damage |
| Enduring | Vanguard/Spellcaster | +20 Health |
| Nimble | Ranger/Support | +3% Attack Speed |
| Channeling | Spellcaster/Support | +3% Skill Damage |

---

## 25. Achievements

**Source:** `AchievementConfig.lua`

### Combat Category

| Achievement | Tiers | Stat |
|---|---|---|
| Slayer | 1 / 50 / 250 / 1K / 5K / 25K / 100K | totalKills |
| Giant Slayer | 1 / 5 / 15 / 50 / 150 / 500 | killsByTier.miniboss |
| Boss Hunter | 1 / 5 / 15 / 50 / 100 / 300 | killsByTier.boss |
| On a Roll | 5 / 10 / 20 / 35 / 50 / 75 / 100 | bestCombo |
| Precision Striker | 50 / 250 / 1K / 5K / 25K / 100K | criticalHits |
| Heavy Hitter | 10K / 50K / 250K / 1M / 5M / 25M | totalDamageDealt |

### Survival Category

| Achievement | Tiers | Stat |
|---|---|---|
| Defender | 1 / 10 / 25 / 50 / 100 / 250 / 500 | wavesSurvived |
| Highrise | 5 / 15 / 30 / 60 / 100 | highestWave |
| Thick Skin | 5K / 25K / 100K / 500K / 2M | totalDamageTaken |

### Collection Category

| Achievement | Tiers | Stat |
|---|---|---|
| Merit Earner | 500 / 5K / 25K / 100K / 500K | meritsCollected |

### Dedication Category

| Achievement | Tiers | Stat |
|---|---|---|
| Relentless | 100 / 1K / 10K / 100K / 500K | hitsDelivered |
| Punching Bag | 200 / 1K / 5K / 25K / 100K | hitsReceived |
| Veteran (one-shot, §AGX/X18b) | 50 | accountLevel — reward: 1 free appearance change (§48) |

Rewards range from 25 Merits (low tiers) to 100K Merits + 500-600 Essence + 2 RespecTokens (max tiers).

---

## 26. Accessories

**Source:** `AccessoryConfig.lua`

Slots: 1 Trinket + 2 Rings. Drop from bosses.

| Accessory | Rarity | Slot | Bonuses | Source |
|---|---|---|---|---|
| Bone Charm | Common | Trinket | +20 Health | boss_any |
| Iron Pendant | Common | Trinket | +5 Armor | boss_any |
| Copper Band | Common | Ring | +3 Damage | boss_any |
| Focus Ring | Common | Ring | +2 CritChance | boss_any |
| Wolf Fang Talisman | Uncommon | Trinket | +8 Damage, +0.1× CritDamage | boss_wolf_alpha |
| Guardian Sigil | Uncommon | Trinket | *(see AccessoryConfig)* | — |

**Rarity Tiers:** Common → Uncommon → Rare → Epic → Legendary

---

## 27. Game Modes & Matchmaking

**Source:** `GameModeConfig.lua`, `MatchmakingManager.lua`

| Mode | Available | Min/Max Players | Solo? |
|---|---|---|---|
| **Defense** | Yes | 1–4 | Yes |
| **Central Boss** | Yes | 1–4 | Yes |
| **Horde Mode** | Yes | 1–4 | Yes |
| Arena | No (coming soon) | 2–4 | No |
| Raid | No (coming soon) | 4–4 | No |
| Exploration | No (coming soon) | 1–4 | Yes |

**Matchmaking Countdown:** **5 seconds** after match formation.

### Horde Mode Mob Multipliers

Applied on top of difficulty tier multipliers. Horde mobs are weaker at the mob level since the mode compensates with infinite waves and run modifiers.

| Stat | Multiplier |
|---|---|
| HP | **0.60×** |
| Damage | **0.85×** |
| Armor | **0.80×** |

### Horde Mode Reward Multipliers

| Reward | Multiplier |
|---|---|
| XP | **0.45×** |
| Merits | **0.50×** |
| Essence | **0.60×** |

### Challenge Modifier Bonuses (stackable, per modifier applied)

| Modifier | XP Bonus | Merits Bonus | Essence Bonus |
|---|---|---|---|
| Standard | **+8%** | **+10%** | **+4%** |
| Lethal | **+12%** | **+15%** | **+6%** |

### Challenge Modifier Caps (total across all stacked modifiers)

| Bonus Type | Cap |
|---|---|
| XP Bonus | **+40%** |
| Merits Bonus | **+50%** |
| Essence Bonus | **+20%** |

---

## 28. Horde Mode Spawner Phases

**Source:** `HordeModeSpawner.lua`

### Spawn Marker Setup

| Parameter | Value |
|---|---|
| Markers per player | **4** (orbit around player) |
| Orbit radius | **42** studs |
| Min spawn distance from any player | **27** studs |
| Spawn Y offset | **3** studs above ground |

### Level Progression

| Parameter | Value |
|---|---|
| Starting level | **1** |
| Level tick interval | **75s** — level increases by +1 every 75s |
| Max auto-level | **30** |

### Phases (Hard difficulty baseline)

| Phase | Start Time | Spawn Interval | Alive Cap | Spawn Weights | Speed Mult |
|---|---|---|---|---|---|
| 1 | 0:00 | **3.2s** | **10** | Zombie 100% | **1.6×** |
| 2 | 4:00 (240s) | **2.7s** | **14** | Zombie 96%, Troll 4% | **1.75×** |
| 3 | 7:00 (420s) | **2.3s** | **18** | Zombie ~90%, Troll ~5%, Ogre ~5% | **1.9×** |

Phase 3 continues indefinitely until the run timer expires.

### RunModifiers Integration

HordeModeSpawner applies timed modifiers from `RunModifiers.GetModifier()` at each spawn tick:

- Spawn interval: `phase.interval × (1 + spawnIntervalScalar)`
- Alive cap is unaffected by modifiers (hard safety cap)
- Speed is: `phase.speedMult × phase.speedScalar × RunModifiers` (mob-speed card)

---

## 29. Card & Event Vote System

**Source:** `CardRegistry.lua`, `VoteManager.lua`, `RunModifiers.lua`

### Vote Parameters

| Parameter | Value |
|---|---|
| Cards shown per vote | **3** |
| Vote duration | **10s** (or early close if all players vote) |
| Tie-break | Random among tied options |
| No-vote fallback | All 3 options equally likely |

### Horde Vote Cadence (Horde Mode only)

*Updated 2026-09-26 (§AGX/X25): one alternating loop (`HordeModeMain.server.lua:390-438`).*

| Parameter | Value |
|---|---|
| Loop | One vote every **45 s** of play time, alternating supply → threat |
| Supply votes | First at **45 s**, then every **90 s** → **7** per 630 s run |
| Threat votes | First at **90 s**, then every **90 s** → **7** per run |
| Total | **7 + 7** (was documented as 14 supply + 7 threat) |

### Tactical Vote Cadence (Lane Defense only)

| Parameter | Value |
|---|---|
| Trigger | Start of each wave |
| Total in 12-wave run | **12 votes** (one per wave) |
| Wave gate | Wave waits until vote resolves |

### Horde Run Duration

| Parameter | Value |
|---|---|
| Play time (paused excluded) | **630s (10:30)** |
| Wall-clock (approx) | ~13:18 (pauses count as ~168s supply + subset threat) |
| End condition | Timer expires → spawner stops → mob clear → TriggerVictory |
| Auto-return to lobby | **10s** after TriggerVictory |

### RunModifiers Caps (Hard Guardrails)

| Modifier | Cap |
|---|---|
| Danger bonus (max) | **+45%** |
| Danger bonus (min) | **-25%** |
| Spawn acceleration (max) | **-18%** (18% faster) |
| Speed reduction (max) | **-30%** |
| Per-wave danger cap | **±12%** |
| Total danger (combined) | **±45% / -25%** |

### Supply Cards (Horde Mode)

| Card | Effect | Special |
|---|---|---|
| **Merit Cache** | Grant merits (Normal: 60–90, Hard: 70–105, NM: 80–120) | — |
| **Class Battery** | Restore 20–35% class resource | — |
| **Power Surge** | Random buff: +8–12% DMG (20–25s) OR +6–10% CritChance (18–22s) OR +10–14% AtkSpd (15–18s) | — |
| **Emergency Pulse** | Instant heal 12–18% max HP | — |
| **Essence Drop** | Grant essence: base Normal 8–12, Hard 10–15, NM 16–24, **× Horde 0.6** → 5–7 / 6–9 / 10–14 | Personal cooldown **150 s** (at most every other supply vote) |
| **Second Wind** | +6–10% max HP for **45s** | — |
| **Weapon Oil** | +5–8% damage for **30s** | — |
| **Bounty Board** | 2× merits from kills for **30s** | Cooldown: **120s** |

### Threat Cards (Horde Mode) — 3 Lanes

Threat vote always draws **1 card from each lane** (Greed, Control, Relief).

**Greed Lane** (harder, bigger danger bonus):

| Card | Effect | Danger |
|---|---|---|
| **Blood Moon** | Spawn rate +4–6% faster for **60s** | +4–6% |
| **Hunting Horn** | Summon 1 elite (+6–9% danger) | +6–9%; Cooldown: **90s** |
| **Thick Skins** | Mob HP +8–12%, armor +2–4 flat for **60s** | +5–7% |
| **Corrupted Ground** | Mob damage +10–15% for **60s** | +6–8% |

**Control Lane** (balanced trade-off):

| Card | Effect | Danger |
|---|---|---|
| **Split Pack** | Normal mob count +8–12% for **60s** | +2–4% |
| **Marked Targets** | Elites take +8–12% dmg but move +4–6% faster for **60s** | +2–4% |
| **Reinforcements** | Spawn rate +5–8%, mob speed -3–5% for **60s** | +2–4% |

**Relief Lane** (easier, reduced danger bonus):

| Card | Effect | Danger |
|---|---|---|
| **Heavy Air** | Mob speed -6–9% for **60s** | -3–5% |
| **Thin Ranks** | Spawn rate -6–9% for **60s** | -4–6% |
| **Frozen Blood** | Elite attack -8–12%, speed -4–6% for **60s** | -3–4% |
| **Weak Spot** | Mob HP -8–12%, damage +4–6% for **60s** | -2–4% |

### Tactical Cards (Lane Defense)

| Card | Effect | Danger | Wave Restriction |
|---|---|---|---|
| **Supply Cart** | Grant 40–70 merits per player | — | Any wave |
| **Fortify** | Defense line +8–12% HP shield | -4–6% | Any wave |
| **Sharpsight** | +6–10% CritChance for **180s** | +0–2% | Any wave |
| **Elite Bounty** | Add 1 miniboss to wave | +8–11% | Waves **4, 7, 10, 12** only |
| **Slow March** | Enemy speed -6–10% for **180s** | -4–6% | Any wave |
| **Dense Pack** | Normal mob count +6–10% for **180s** | +4–7% | Any wave |
| **Repair Window** | Restore 6–10% defense-line HP | -5–7% | Any wave |
| **Frenzy Banner** | +8–12% attack speed for **180s** | +0–2% | Any wave |
| **Iron Wall** | +4–7% armor for **180s** | -2–4% | Any wave |
| **Rallying Cry** | +5–8% damage + +3–5% crit for **180s** | +2–4% | Any wave |
| **Scavenge** | Grant Essence (Normal: 8–12, Hard: 10–15, NM: 16–24) | +1–3% | Waves **3, 6, 9, 12** only |

### Essence Card Budget

*Updated 2026-09-26 (§AGX/X41).* Cards were ≈19× the Essence drops (Scavenge ≈70/run offered on any wave; Horde Essence Drop ≈52/run and skipping the Horde ×0.6). Target: cards are a **meaningful bonus (≈3× drops)**, and the whole Essence ladder is paced by, not ahead of, the Merit ladder.

| Source (always picked when offered) | Offers / run | Normal | Hard | Nightmare |
|---|---|---|---|---|
| Lane drops | — | 3.6 | 4.5 | 7.2 |
| Scavenge (waves 3/6/9/12: 3 × 3/10 + 3/11) | ≈1.17 | ≈11.7 | ≈14.6 | ≈23.4 |
| **Lane total** | | **≈15.3** | **≈19.1** | **≈30.6** |
| Horde Essence Drop (7 supply votes, 3 of 8 offered, cooldown) | ≈1.98 picks | ≈11.9 | ≈14.9 | ≈23.8 |

- Tier ladder (1,650 per piece) on Lane Normal: ≈108 runs per piece with cards (was ≈23), ≈458 with drops only.
- Per chapter and per piece, Essence needed vs Merit-ladder runs at Normal: Ch1 90 E (≈6 runs) vs ≈8 runs; Ch2 280 E (≈18) vs ≈28; Ch3 430 E (≈28) vs ≈53; Ch4 850 E (≈56) vs ≈207. So Essence never gates a single piece, still keeps up with a weapon **and** an armor piece in every chapter, and leaves room for respecs and the paid wipe-revive.
- Difficulty ratio 1.0 / 1.25 / 2.0 matches DifficultyConfig `essenceMult` (not applied twice).

---

**Source:** `LobbyNPCRegistry.lua`

| Quest | Rewards |
|---|---|
| A Line in the Sand (complete 1 defense) | **25 Essence**, 35% XP |
| Veteran Defender (complete 5 defenses) | **2,500 Merits**, **10 Essence** |

### NPC Shop Prices (Blacksmith)

| Item | Price | Currency |
|---|---|---|
| Iron Sword | 50 | Essence |
| Steel Shield | 75 | Essence |
| Health Potion | 10 | Essence |

### NPC Shop Prices (Enchantress)

| Item | Price | Currency |
|---|---|---|
| Arcane Focus | 100 | Essence |
| Mana Crystal | 15 | Essence |

---

## 30. Quest Rewards (Lobby NPCs)

**Source:** `LobbyNPCRegistry.lua`

### Captain Aldric Quests

| Quest ID | Title | Objectives | Rewards |
|---|---|---|---|
| `first_defense` | A Line in the Sand | Complete 1 Defense mission | 25 Essence, 35% XP |
| `veteran_defender` | Veteran Defender | Complete 5 Defense missions | 2,500 Merits, 10 Essence |

> Both quests are non-repeatable (one-time only).
>
> *Updated 2026-09-26 (§AGX/X41):* was 100 Essence and "10 Merits, 300 Essence" (400 Essence one-time ≈ 111 runs of drops; the second quest's amounts looked swapped). 25 Essence pays the first two tier-ups (10 + 15). 2,500 Merits ≈ 3 runs at the level you finish 5 runs, plus 10 Essence; ≈5,000 Merits of value at the §33 anchor.

---

## 31. Chapter Config

**Source:** `ChapterConfig.lua`

### Chapter Boundaries

| Chapter | Levels | Description |
|---|---|---|
| 1 | 1–50 | Tutorial & early game |
| 2 | 51–100 | Mid-game progression |
| 3 | 101–150 | Late-game push |
| 4 | 151–200 | Endgame mastery |

### Gear Caps by Chapter

| Chapter | Max Refinement | Max Tier |
|---|---|---|
| 1 | **+8** | **V** |
| 2 | **+11** | **VIII** |
| 3 | **+13** | **X** |
| 4 | **+15** | **XII** |

### Ascension Crests

Required to advance to the next chapter:

| Chapter Completed | Token Required |
|---|---|
| Chapter 1 → 2 | AscensionCrest_50 |
| Chapter 2 → 3 | AscensionCrest_100 |
| Chapter 3 → 4 | AscensionCrest_150 |

---

## 32. Class Mastery

**Source:** `ClassMasteryConfig.lua`

### Mastery Milestones

| ID | XP Required | Reward |
|---|---|---|
| mastery_1 | **2,000** | Title: "Initiate" |
| mastery_2 | **6,000** | Title: "Adept" |
| role_seal_1 | **12,000** | BoundToken: RoleSeal_1 |
| mastery_3 | **20,000** | Title: "Veteran" |
| second_weapon | **30,000** | Unlock: Second Weapon Path |
| role_seal_2 | **45,000** | BoundToken: RoleSeal_2 |
| mastery_4 | **65,000** | Title: "Master" |
| role_seal_3 | **90,000** | BoundToken: RoleSeal_3 |
| mastery_5 | **120,000** | Title: "Grandmaster" |

### Second Weapon Gate

| Requirement | Value |
|---|---|
| Min Account Level | **60** |
| Required Milestone | `second_weapon` (30,000 mastery XP) |

### Role Seal Map

| Class | Seal Token |
|---|---|
| Aegis | TankSeal |
| Hunter | DPSSeal |
| LifeSteward | HealerSeal |
| Arcanist | SupportSeal |

---

## 33. Auction Config

**Source:** `AuctionConfig.lua`

> **Note:** Config is complete but the runtime AuctionManager is not yet implemented (deferred per §52.3).

### Auction Bands

| Band | Levels |
|---|---|
| 1 | 1–50 |
| 2 | 51–100 |
| 3 | 101–150 |
| 4 | 151–200 |

### Trading Restrictions

| Parameter | Value |
|---|---|
| Min Trade Level | **20** |
| Listing Tax | **12%** |
| New Account Cap (first 7 days) | 3 listings/day, 5 purchases/day |

### Economy Anchor Rate (1 Essence = 250 Merits)

*Added 2026-09-26 (§AGX/X42).* Every fixed Merit↔Essence price derives from **1 Essence ≈ 250 Merits**. Why 250: it sat near the old (now deleted, §48) Robux packs' ≈ 202:1 and sits just above the auction's global floor (240), and it is the earn ratio of a mid-game player (Lane Normal ≈ 15 E and ≈ 3.7k M per run at level ≈ 60). Late-game players earn Merits faster, so the auction bands below rise with level on purpose.

| Price | Essence | Merit equivalent | Status |
|---|---|---|---|
| Respec (talents or stats) | 25 | 6,250 | Flat, all levels (was 25/40 E, or an unread 20k/50k M) |
| Respec Scroll (shop) | 25 | 6,250 | Was 50 E, 2× a direct respec |
| Wipe-revive (paid) | 25 | 6,250 | Unchanged |
| Veteran Defender quest | 10 + 2,500 M | ≈5,000 | Was 10 M + 300 E |
| Robux packs | — | — | Deleted (§AGX/X40): Robux never buys Merits or Essence, so no Robux:Merit rate exists. See §48 |

### Essence Market Anchor (Merits per Essence)

| Scope | Min | Max |
|---|---|---|
| Global | **240** | **340** |
| Band 1 | **300** | **420** |
| Band 2 | **350** | **500** |
| Band 3 | **420** | **600** |
| Band 4 | **500** | **750** |

---

## 34. Daily Login Rewards

**Source:** `DailyLoginManager.lua` · *Updated 2026-09-26 (§AGX/X25, documents §AGX/X47).*

Each claim (once per UTC day) pays **two tracks**:

1. **Calendar** (below): indexed by **total days claimed** (`totalDays`), cycling every 30. It never resets, so a missed day only delays it. Per 30 claims: **26,500 Merits, 228 Essence, 1 Respec Scroll**.
2. **Spree bonus**: consecutive-day streak (missing a UTC day resets it to 1). Pays **10 Merits × spree** (capped at 30 → 300/day) plus Essence milestones on spree day **7 (+5)**, **14 (+10)** and **30 (+20)**, repeating every 30. A full 30-day spree adds **4,650 Merits and 35 Essence** (≈+18% Merits).

Calendar table (Essence and day 27/28 amounts corrected to the code):

| Day | Merits | Essence | Special |
|---|---|---|---|
| 1 | 100 | — | — |
| 2 | 150 | — | — |
| 3 | 200 | 2 | — |
| 4 | 250 | — | — |
| 5 | 300 | 3 | — |
| 6 | 350 | — | — |
| **7** | **1,000** | **10** | Weekly bonus |
| 8 | 200 | — | — |
| 9 | 250 | 3 | — |
| 10 | 300 | — | — |
| 11 | 350 | 4 | — |
| 12 | 400 | — | — |
| 13 | 450 | 5 | — |
| **14** | **2,000** | **20** | Bi-weekly bonus |
| 15 | 300 | — | — |
| 16 | 350 | 4 | — |
| 17 | 400 | — | — |
| 18 | 450 | 5 | — |
| 19 | 500 | — | — |
| 20 | 550 | 6 | — |
| **21** | **3,000** | **30** | Three-week bonus |
| 22 | 400 | — | — |
| 23 | 450 | 5 | — |
| 24 | 500 | — | — |
| 25 | 550 | 6 | — |
| 26 | 600 | — | — |
| 27 | 650 | 7 | — |
| 28 | 700 | 8 | — |
| 29 | 800 | 10 | — |
| **30** | **10,000** | **100** | + 1 Respec Scroll |
| **Total** | **26,500** | **228** | |

Missing a day resets only the spree, not the calendar. Fallback reward: 100 Merits.

---

## 35. Kill Rewards & XP Sharing

**Source:** `KillRewardManager.lua`

### Base XP Formula

`baseXP = xpNeeded × 0.03` (3% of XP needed to next level)

### Tier Multipliers

| Mob Tier | Multiplier |
|---|---|
| Normal | **1×** |
| Miniboss | **8×** |
| Boss | **25×** |

### Level Delta XP Scaling

| Delta (mobLevel − playerLevel) | Multiplier |
|---|---|
| −5 to +5 | **1.0×** |
| ±6 | **0.8×** |
| ±7 | **0.6×** |
| ±8 | **0.4×** |
| ±9 | **0.2×** |
| ≤−10 or ≥+10 | **0.0×** |

### XP Sharing

| Parameter | Value |
|---|---|
| Share Range | **200 studs** |
| Split Method | Equal division by eligible party members in range |

### Wave Completion XP

`waveXP = 15 + (15 × waveNumber)` — e.g. Wave 1 = 30, Wave 6 = 105, Wave 12 = 195.

---

## 36. Drop Scaling

**Source:** `DropManager.lua`, `DropTableConfig.lua`

### Merit Delta Table (mob level − player level)

| Delta Range | Multiplier |
|---|---|
| ≤ −11 | **0.50×** |
| −10 to −7 | **0.50×** |
| −6 to −4 | **0.75×** |
| −3 to +5 | **1.00×** |
| +6 to +8 | **0.90×** |
| +9 to +12 | **0.65×** |
| +13 to +15 | **0.50×** |
| ≥ +16 | **0.50×** |

### Essence Delta Table

| Delta Range | Multiplier |
|---|---|
| ≤ −11 | **0.30×** |
| −10 to −7 | **0.60×** |
| −6 to −4 | **0.85×** |
| −3 to +5 | **1.00×** |
| +6 to +8 | **0.95×** |
| +9 to +12 | **0.80×** |
| +13 to +15 | **0.60×** |
| ≥ +16 | **0.40×** |

### Level Multiplier

`levelMult = 1 + ((mobLevel − 1) × 0.1)` — +10% per mob level above 1.

---

## 37. Party System

**Source:** `PartyManager.lua`

| Parameter | Value |
|---|---|
| Max Party Size | **5** |
| Invite Timeout | **30 s** |
| Max Level Gap | **10** levels |
| XP Bonus per Friend | **+5.0%** |
| XP Bonus per Non-Friend | **+2.5%** |

---

## 38. Leaderboard System

**Source:** `LeaderboardManager.lua`

| Parameter | Value |
|---|---|
| Update Interval | **120 s** |
| Max Entries | **50** per board |
| Boards | PowerLevel, HighestWave, TotalPlayTime |

---

## 39. Networking & Anti-Cheat

**Source:** `NetworkManager.lua`, `MonitoringSystem.lua`

| Parameter | Value |
|---|---|
| Rate Limit | **30** calls per player per event per window |
| Rate Window | **1 s** |
| Suspicious Dodge Rate | **≥ 95%** |
| Distance Buffer | **10** studs beyond skill range |
| Max Hit Report Delay | **3.0 s** |
| Min Hits for Evaluation | **20** |

---

## 40. Gear Rating Weights

**Source:** `GearRating.lua`

| Component | Max Weight |
|---|---|
| Base | **150** |
| Level (cap 200) | **900** |
| Weapon | **2,400** |
| Armor | **1,700** |
| Accessories | **700** |
| Talent Tree | **800** |
| Mastery | **550** |
| **Total Cap** | **~7,200** |

Prestige multiplier cap: **+10%**.

Accessory rarity scores: Common 5, Uncommon 15, Rare 30, Epic 60, Legendary 100.

---

## 41. Run Modifiers & Danger System

**Source:** `RunModifiers.lua`

| Cap | Value |
|---|---|
| Danger Bonus Max | **+45%** |
| Danger Bonus Min | **−25%** |
| Spawn Acceleration Max | **−18%** interval |
| Speed Reduction Max | **−30%** |
| Wave Danger Max | **+12%** per wave |
| Wave Danger Min | **−12%** per wave |
| Miniboss Average Cap | ≤ 1 per **90 s** |

---

## 42. Horde Mode Timing

**Source:** `HordeModeMain.server.lua`, `HordeModeSpawner.lua`

| Parameter | Value |
|---|---|
| Run Duration | **630 s** (10 min 30 s) |
| Vote Interval | **45 s**, alternating supply / threat (7 + 7 per run; *§AGX/X25, 2026-09-26*) |
| Vote Result Display | **3.5 s** |
| Level Tick Interval | **75 s** |
| Max Auto Level | **30** |
| Orbit Radius | **42 studs** |
| Min Spawn Distance | **27 studs** |
| Num Spawners | **4** per player |

---

## 43. Matchmaking

**Source:** `MatchmakingManager.lua`, `TeleportManager.lua`

| Parameter | Value |
|---|---|
| Countdown | **5 s** |
| Max Level Gap | **10** levels |
| Hard Unlock Level | **30** |
| Nightmare Unlock Level | **80** |

---

## 44. Combo System (Defense Line)

**Source:** `DefenseCombo.lua`, `DefenseConfig.lua`

| Parameter | Value |
|---|---|
| Window | **3.0 s** |
| Factor (per level) | **1.20×** |
| Max Level | **5** |
| Decay Rate | **1** level/second after window |

---

## 45. Hit Tracker

**Source:** `HitTracker.lua`

| Parameter | Value |
|---|---|
| Combo Decay Time | **3.0 s** |
| Combo Update Rate | **0.1 s** (10 Hz) |
| Min Combo for Notify | **3** |

---

## 46. HP Regen (Combat Modes)

**Source:** `LaneDefenseMain.server.lua`, `HordeModeMain.server.lua`

| Parameter | Value |
|---|---|
| Vitals Broadcast Interval | **1 s** |
| Default Regen % | **0.5%** of max HP per tick |
| Default Regen Flat | **0** |

---

## 47. Respec Economy

**Source:** `VoteManager.lua`, `CardRegistry.lua`, `InventoryManager.lua`,
`ConsumableConfig.lua`, `TalentManager.lua`, `SharedEventHandlers.lua`

Respec scrolls are the primary soft-currency respec gate; Essence remains
available as a per-level fallback. Scrolls are crafted from fragments
earned during Horde runs.

### Economy Loop

| Step | Rule |
|---|---|
| Fragment source | 10 % per-player roll on each **personal** supply vote. |
| Cap per run | **1 fragment pre-roll per player per run** (first roll — hit or miss — locks out further rolls that run). |
| Supply votes per run | 7 (Horde) |
| Combine ratio | **4 fragments → 1 respec_scroll** (auto-combined inside `InventoryManager.AddItem`) |
| Scroll consumption | Consumed by `TalentManager.RespecTalents` and `SharedEventHandlers.RespecStats` via `InventoryManager.ConsumeItem`. |
| Essence fallback | `PlayerDataConfig.GetRespecCost(level)` — flat **25 Essence** (§AGX/X42, 2026-09-26; was 25/40). The shop scroll costs the same 25. |
| Stack caps | `respec_fragment` = 99, `respec_scroll` = 99 (hoarding is fine). |

### Probability Math

With 7 supply votes per run × 10 % chance capped at 1 roll/run:

```
P(first roll lands on vote k) = 0.9^(k-1) * 0.1   for k in 1..7
P(≥1 fragment / run)          = 1 − 0.9^7         ≈ 0.5217
E[fragments / run]            = P(≥1)             ≈ 0.5217
E[runs for 1 scroll]          = 4 / 0.5217        ≈ 7.67
```

This is intentionally a bit harder than the original ~6-run target (the
1-per-run cap makes it harder than naive 7 × 10 %). Free-respec income is
thus roughly **one scroll every ~8 horde runs**, tuned to feel earned
without gating talent experimentation entirely behind Essence.

### Backwards Compatibility

Legacy grant paths (`DailyLoginManager`, `AchievementManager`) previously
incremented `data.Account.RespecTokens`. These now grant `respec_scroll`
items via `InventoryManager.AddItem`. The `RespecTokens` field remains in
`PlayerDataConfig` for data-migration purposes but is no longer consulted
by any hot code path.

---

## 48. Monetization (Robux)

**Source:** `ShopConfig.lua` (Premium tab), `MonetizationService.lua`, `ShopManager.PurchasePremium` · *Added 2026-09-26 (§AGX/X40).*

### The no-P2W rule

Gameplay currency (Merits, Essence) is **never sold for Robux**, and nothing bought with Robux may turn into currency or power. Refine, reroll and tier-up stay earn-only, and so are not paid random items. Robux buys only:

- cosmetics (no stats),
- appearance changes (`CharacterManager.GrantAppearanceChange`, §AGX/X18) — but only **after** the one free change earned at level 50 (see below, §AGX/X18b),
- non-power convenience or social perks.

Things that are **not** allowed for Robux, even though they look like convenience:

| Not allowed | Why |
|---|---|
| Merit / Essence packs | Direct currency sale. |
| Respec scrolls or tokens | A scroll is worth 25 Essence (§33), so selling one frees 25 Essence for refine or reroll. |
| Consumables (potions, buffs, revives) | Power, and Essence-priced. |
| XP / drop / Merit boosts, extra revives | Power. The wipe-revive stays free 3/2/1, then 1 paid in Essence (§AGX/X40). |
| A cosmetic that is also sold for Merits/Essence | Buying it with Robux frees the Merits/Essence it would have cost. |

**Code guard:** `MonetizationService` only registers Premium entries whose `grant.type` is `AppearanceChange`, `Cosmetics` or `GamePass`. Any other entry is refused with a warning and can't be prompted. A `Cosmetics` bundle that contains an item from the Merit/Essence Cosmetics tab is registered (so receipts are honoured) but can't be prompted.

### Catalog

Every entry is `enabled = false`, with `devProductId = 0` / `gamePassId = 0`, until Pablo creates the product in the Creator Dashboard and pastes its id. The Robux price in `ShopConfig` is for display only: Roblox charges the Dashboard price, so keep the two in sync.

| itemId | Kind | Robux | Grants | Purchase guard |
|---|---|---|---|---|
| `premium_appearance_change` | DevProduct | **49** | 1 appearance change (banked, then applied via `GrantAppearanceChange`) | Character must exist; no unused change (flag, banked token or free Veteran token, §AGX/X18b) |
| `premium_bundle_vanguard` | DevProduct | **99** | `helm_aegis` + `dark_knight` | Not all items owned. **Blocked today:** both are in the Merit/Essence Cosmetics tab |
| `premium_bundle_arcanum` | DevProduct | **99** | `circlet_arcanist` + `shadow_robes` | Same, blocked for the same reason |
| `premium_bundle_wildwood` | DevProduct | **99** | `mask_hunter` + `forest_ranger` | Same, blocked for the same reason |
| `premium_vip` | GamePass | **199** | `VIP` player attribute (nameplate + chat tag; nothing reads it yet) | Not already owned |

The bundles reference the only non-starter cosmetics that exist (all §DISC/D7 placeholders). Before enabling them, either replace them with Robux-exclusive cosmetics or take those items out of the Merit/Essence Cosmetics tab.

### Appearance changes: one free at level 50, then paid (§AGX/X18b)

Pablo: *"You can create some random character at the beginning, but the second change is definitely a decision. One cosmetic change at level 50 with an achievement, then paid."*

| Step | Rule | Code |
|---|---|---|
| Creation | Free, once (first login) | `CharacterManager` / `CharacterCreation` |
| 1st change | **Free**: one-shot achievement **Veteran** (`veteran`, Dedication) at **account level 50** rewards `AppearanceChange ×1` | `AchievementConfig` (single tier `{ 50 }`), `AchievementManager` (`accountLevel` stat from the `Level` attribute; players already ≥ 50 get it on next login) |
| Storage | The free change is **stored**, not auto-opened: `Account.CharacterData.freeAppearanceTokens` (number, missing = 0) | `CharacterManager.AddFreeAppearanceToken` |
| Spending | Menu → Character → **Change appearance** fires `UseAppearanceChange` (1/s): an unused unlocked change reopens the screen for free; else one free token → `GrantAppearanceChange` → creation screen; the §AGX/X18 submit consumes it | `CharacterManager.UseAppearanceChange` |
| Later changes | **Paid** (`premium_appearance_change`, 49 R$). Can't be bought while a free token is unspent | `MonetizationService.canBuy` |
| Client | Attribute `AppearanceChangesAvailable` = free + paid banked + 1 if a granted change is still unused. Menu entry badge = that count; locked "Unlocks at level 50" below 50, else "No changes left". Not available in Combat | `Registry` `appearance`, `BadgeStore` `appearance` |

### Receipts

| Rule | Value |
|---|---|
| ProcessReceipt owner | `MonetizationService` only (one per server; bootstrapped by `ShopManager.Init` in all 5 Places) |
| Idempotency | `PurchaseId` is written to `Account.Monetization.receipts` in the same in-memory step as the grant; a forced `SavePlayer` writes both in one UpdateAsync (§AGX/X3 lock) |
| `PurchaseGranted` | Only when that save returns `"ok"`; otherwise `NotProcessedYet` |
| Receipt history kept | Last **100** purchase ids per player |
| Robux spent | `Account.Monetization.robuxSpent`: private, never on a leaderboard (X46) |
| PolicyService (X46) | Not required while no Robux purchase reaches a random outcome or player trading |

---

## D7. Shop Rotation + Paid Refresh

**Source:** `ShopConfig.lua` (`Rotation`, `Refresh`, `staple`), `ShopManager.lua` (§AGX/D7), `GlobalShopUI.lua` · *Added 2026-09-26 (§DISC/D7). Not yet tested in Studio. The catalog items themselves are still placeholders.*

### What rotates

| Tab | Always sold (`staple = true`) | Rotation pool | Slots | Period |
|---|---|---|---|---|
| Consumables | `health_potion`, `health_potion_large`, `mana_crystal`, `mana_crystal_large`, `respec_scroll` | `health_elixir`, `power_scroll`, `iron_skin_potion`, `fortune_incense`, `crit_oil` (`swiftness_elixir` joins when it becomes usable, X10) | **3 of 5** | **6 h** (00/06/12/18 UTC) |
| Cosmetics | none | all 7 | **4 of 7** | **24 h** (00:00 UTC) |
| Premium (Robux) | all | none | — | never |

Why:
- **Staples never rotate.** Basic healing and mana are needed to play, and the respec scroll is the Essence fallback of §47. Rotating them would gate play or talent experiments behind luck. The two NPC shops sell only staples, so they are unaffected.
- **Buffs and cosmetics rotate.** They are optional, so rotating them gives variety and a reason to check back without blocking anyone. 3 of 5 means each buff is up about 60% of the time, and any buff is at most one 6 h period away most of the time. 4 of 7 cosmetics means each one is shown on about 57% of days.
- **Premium never rotates.** A countdown on a Robux listing is fake urgency, a dark pattern. It also keeps §48 simple.
- Unusable (`enabled = false`) items are left out of the pool, so they never take a slot.

### Per-player, deterministic, no DataStore writes

Each rotation is drawn on the server from the seed `(UserId, tab, periodIndex, roll)`:
- `periodIndex = floor(os.time() / period)`. It is aligned to the UTC epoch, so every server agrees.
- `roll` is the number of paid refreshes of that tab in that period.
- The draw is an FNV-1a hash feeding an xorshift32 partial Fisher-Yates. It is pure Luau, not `Random.new`, so an engine update can't change it.

Properties:
- Nothing is written when a tab rotates.
- Rejoining or hopping servers can't re-roll the stock.
- The client never computes the draw. The server sends the list in `ShopState.rotation`.

The server refuses to sell a rotating item that is not in that player's current rotation. There is a **10 s grace** after a flip, for a click on the last second. This check covers the global shop and the NPC `ShopHandler` route.

Headless check with the luau CLI over 20,000 draws: each consumable is up 59.6–60.7% of the time (target 60%), and each cosmetic 56.6–57.7% (target 57.1%).

### Paid refresh ("Refresh now")

| Rule | Value |
|---|---|
| Scope | Re-rolls **one** tab's current rotation. The timer does not move. |
| Price (nth refresh of the UTC day, shared across tabs) | **5 / 10 / 20 Essence** (≈1,250 / 2,500 / 5,000 Merits at 1 E = 250 M, §33) |
| Daily cap | **3** (max **35 Essence/day**). Resets at 00:00 UTC. |
| Guaranteed change | A re-roll always shows at least one item the previous roll did not. It redraws up to 8 times, and in the 20k-draw test no identical re-roll happened. |
| Refused without charge | Less than 5 min left before the free rotation; the tab doesn't rotate; the pool is not bigger than the slot count; daily cap reached; not enough Essence; **stale request** (the `{period, roll}` the client saw no longer matches, which makes a double-click or replay idempotent) |
| Order | Per-player lock (the shared purchase lock, same pattern as EquipmentRefinement `attemptLock`). Then `SpendEssence`, and its result is checked. Then the counter is written in one assignment, with a refund if that write throws. |
| Storage | `Account.ShopRotation = { day, refreshes, rolls = { [tab] = { period, n } } }`. It saves in the same blob as the Essence it cost, so a lost save loses both. |
| Robux | **Never.** Essence is earn-only (X40, §48), so this is a pure Essence sink. |

### Sink sizing

Essence income (mid-game): Lane Normal ≈ 15 E/run (§33 anchor). Daily login ≈ 7.6 E/day from the calendar plus ≈ 1.2 from the spree (§34).

| Archetype | Runs/day | ≈ Essence/day | Max refresh spend | Share if maxed |
|---|---|---|---|---|
| Casual | 1 | ≈ 24 | 5 (one refresh is the realistic max) | ≈ 21% |
| Core | 4 | ≈ 69 | 35 | ≈ 51% |
| Grinder | 10 | ≈ 159 | 35 | ≈ 22% |

The refresh is an optional convenience sink, and the free rotation is always the no-cost path. Doubling the price and capping at 3 bounds the worst day at 35 E, about 1.4 of a respec (25 E).

Value check: hunting a specific 25 E cosmetic costs about 9 E of refreshes on average (first refresh 5 E, then a 43% chance of needing the 10 E one), a ≈37% impatience premium. Refreshing only to find a Merit-priced buff (≤150 M) is poor value on purpose, because the free 6 h rotation covers that.

Telemetry to add later: refreshes per player-day and the share of players who refresh at least once. The target is >20% participation, or the prices get revisited.

---

*Last updated from full codebase audit, March 2026. All values verified against source files.*
*Respec economy section added in the April 2026 overnight respec-fragment update.*
