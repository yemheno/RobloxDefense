# Balance Numbers

The one home for every tunable gameplay number. Other docs link here instead of repeating values.

- **Code wins.** When this file and `src/` disagree, the code is right and this file is the bug. Fix it here, in the same change.
- **Mechanics** (how a system works) live in [SYSTEMS.md](SYSTEMS.md). Both files use the same system order.
- **Who owns it:** balance is the agents' call (see [CLAUDE.md](../CLAUDE.md)); anything that changes how the game *feels* goes to Pablo first.
- `file:line` citations were checked at `24c4d7e`. Line numbers drift; the file name is the durable part.

**Contents:** [Economy](#economy) · [Progression & respec](#progression--respec) · [Stats & caps](#stats--caps) · [Damage & healing](#damage--healing) · [Classes, skills & resources](#classes-skills--resources) · [Gear](#gear) · [Mobs, waves & modes](#mobs-waves--modes) · [Death & regen](#death--regen) · [Rewards](#rewards) · [Talents](#talents) · [Shop & monetization](#shop--monetization) · [Chapters, party & infrastructure](#chapters-party--infrastructure) · [Old section numbers](#old-section-numbers)

---

## Economy

### Economy anchor

*Added 2026-09-26 (§AGX/X42).* Every fixed Merit↔Essence price derives from **1 Essence ≈ 250 Merits**. Why 250: it sat near the old (now deleted, see [Monetization](#monetization-robux)) Robux packs' ≈ 202:1 and sits just above the auction's global floor (240), and it is the earn ratio of a mid-game player (Lane Normal ≈ 15 E and ≈ 3.7k M per run at level ≈ 60). Late-game players earn Merits faster, so the auction bands below rise with level on purpose.

| Price | Essence | Merit equivalent | Status |
|---|---|---|---|
| Respec (talents or stats) | 25 | 6,250 | Flat, all levels (was 25/40 E, or an unread 20k/50k M) |
| Respec Scroll (shop) | 25 | 6,250 | Was 50 E, 2× a direct respec |
| Wipe-revive (paid) | 25 | 6,250 | Unchanged |
| Veteran Defender quest | 10 + 2,500 M | ≈5,000 | Was 10 M + 300 E |
| Robux packs | — | — | Deleted (§AGX/X40): Robux never buys Merits or Essence, so no Robux:Merit rate exists. See [Monetization](#monetization-robux) |

#### Essence market anchor (Merits per Essence)

| Scope | Min | Max |
|---|---|---|
| Global | **240** | **340** |
| Band 1 | **300** | **420** |
| Band 2 | **350** | **500** |
| Band 3 | **420** | **600** |
| Band 4 | **500** | **750** |

### Currencies

| Currency | Earned from | Spent on | Sold for Robux? |
|---|---|---|---|
| **Merits** | Mob drops (all tiers), Supply Cart / Merit Cache cards, quests, achievements, daily login | Refinement, reroll, cosmetics, consumables | **Never** ([Monetization](#monetization-robux)) |
| **Essence** | Miniboss/boss drops (flat), Scavenge / Essence Drop cards, quests, achievements, daily login | Tier-ups, respec, paid wipe-revive, shop refresh, some cosmetics/consumables | **Never** |

Per-run income: [Drop tables](#drop-tables) (drops) and [Essence card budget](#essence-card-budget) (cards).

---

## Progression & respec

**Source:** `PlayerDataConfig.lua`

| Parameter | Value |
|---|---|
| Points per Level | **1** stat point |
| Class Switch Cooldown | **30 s** (`PlayerDataConfig.lua:417`); waived right after arriving with a party-picked class |

### XP Curve

Formula: `XPRequired(L) = round(120 × 3.2^b × (1 + 0.05p)^1.9)`

Where `b = floor((Level - 1) / 50)` (chapter index) and `p = (Level - 1) % 50` (position within chapter).

Sample XP requirements (computed from `PlayerDataConfig.GetXPForLevel`, `PlayerDataConfig.lua:376-381`):

| Level | XP Required |
|---|---|
| 1 | 120 |
| 2 | 132 |
| 10 | 243 |
| 25 | 537 |
| 50 | 1,262 |
| 51 | 384 (chapter 2 reset) |
| 100 | 4,038 |
| 150 | 12,922 |
| 200 | 41,351 |

### Respec Costs

*Updated 2026-09-26 (§AGX/X42).*

| Bracket | Cost |
|---|---|
| All levels | **25 Essence** or **1 Respec Scroll** |

- Was 25 / 40 Essence (below / from level 100) "or 20,000 / 50,000 Merits". The Merit option was never read by any code path and has been removed: Merit income rises ~10× from level 10 to 200, so a Merit price is a wall early and free late. Essence income is flat, so the level-100 step was dropped too.
- The Respec Scroll sells for the same 25 Essence (shop), so it is never worse than a direct respec. Free respec on each ascension boss clear.

### Class Unlock Requirements

All 4 classes are available from day one: Aegis, Hunter, Arcanist, LifeSteward.

### Respec economy (scrolls and fragments)

**Source:** `VoteManager.lua`, `CardRegistry.lua`, `InventoryManager.lua`,
`ConsumableConfig.lua`, `TalentManager.lua`, `SharedEventHandlers.lua`

Respec scrolls are the primary soft-currency respec gate; a flat 25 Essence
is the fallback at every level. Scrolls are crafted from fragments
earned during Horde runs.

#### Economy Loop

| Step | Rule |
|---|---|
| Fragment source | 10 % per-player roll on each **personal** supply vote. |
| Cap per run | **1 fragment pre-roll per player per run** (first roll — hit or miss — locks out further rolls that run). |
| Supply votes per run | 7 (Horde) |
| Combine ratio | **4 fragments → 1 respec_scroll** (auto-combined inside `InventoryManager.AddItem`) |
| Scroll consumption | Consumed by `TalentManager.RespecTalents` and `SharedEventHandlers.RespecStats` via `InventoryManager.ConsumeItem`. |
| Essence fallback | `PlayerDataConfig.GetRespecCost(level)` — flat **25 Essence** (§AGX/X42, 2026-09-26; was 25/40). The shop scroll costs the same 25. |
| Stack caps | `respec_fragment` = 99, `respec_scroll` = 99 (hoarding is fine). |

#### Probability Math

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

#### Backwards Compatibility

Legacy grant paths (`DailyLoginManager`, `AchievementManager`) previously
incremented `data.Account.RespecTokens`. These now grant `respec_scroll`
items via `InventoryManager.AddItem`. The `RespecTokens` field was removed
from `PlayerDataConfig` and old saves are cleaned by the deprecated-key sweep
(`PlayerDataManager/init.lua:299`).

---

## Stats & caps

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

### Stat caps

One table, `PlayerDataConfig.StatCaps` (`PlayerDataConfig.lua:144-159`). Every reader clamps through `PlayerDataConfig.CapStat`. Values are percent points unless a unit is given.

| Stat | Min | Max | Enforced by |
|---|---|---|---|
| CritChance | 0% | **200%** | `CriticalSystem` |
| CritDamage | 1.0× | **1.80×** | `CriticalSystem` |
| DamageReduction | 0% | **75%** | incoming damage |
| Penetration | 0 | **60** | `DamageSystem.lua:17` (keystones included) |
| CooldownReduction | 0% | **40%** | `SkillManager.StartCooldown` |
| CastTimeReduction | 0% | **40%** | `SkillManager` cast start |
| Lifesteal | 0% | **25%** | lifesteal path |
| AttackSpeed | **−50%** | **+75%** | `ClassManager.GetAttackSpeed` |
| StatusResistance | 0% | **60%** | `MobAI.ApplyEffectToPlayer` |
| MovementSpeed | **−50%** | **+30%** | `DeathSystem` base walk speed |
| AoESize | **−50%** | **+50%** | per-cast shape view in `SkillManager` |

### Combat caps (not in StatCaps)

| Cap | Value | Code |
|---|---|---|
| Multi-crit procs | **2** (max 1.80² = 3.24×) | `CriticalSystem.lua:18-19` |
| Vulnerability multiplier | **×2.0** (non-stacking; strongest wins) | `DamageSystem.lua:22` |
| Mob ArmorReduction (shred) | **0–50%** | `DamageSystem.lua:26` |

Worst single hit: 3.24 (crit) × 1.25 (element) × 2.0 (vulnerability) = **8.1×**.

### Bonus-stat readers

*§AGX/STATS, 2026-09-26.* These six bonus stats had writers (gear rolls, talents, cards, accessories, innates, consumables) and no reader. Each one now has a reader. Every reader clamps with `PlayerDataConfig.CapStat(stat, value)`, which uses `PlayerDataConfig.StatCaps`. Values are percent points.

| Stat | Cap (min / max) | Read by | Effect |
|---|---|---|---|
| MovementSpeed | **−50 / +30** *(new)* | `DeathSystem` (`computeBaseWalkSpeed`, `RefreshMoveSpeed`) | `BaseWalkSpeed = NaturalWalkSpeed × (1 + MS/100)`. MobAI slows and stuns, the cast move-lock and knockdown all work from this base. It's recomputed when the bonus changes (`BonusManager.OnChanged`). |
| AttackSpeed | **−50 / +75** *(existing)* | `ClassManager.GetAttackSpeed` → AttackHandler cooldown check + CombatConfig | attacks/s = weapon speed × (1 + AS/100). When it changes, the client gets a resend, and the server accepts the faster of the old and new cadence for 1 s. |
| AoESize | **−50 / +50** *(new)* | `SkillManager.ExecuteSkill` (per-cast scaled view) → `BaseSkills.GetTargetsInShape` / `GetTargetsInCircle` | Skill `shapeParams` range, width and innerRadius are multiplied by (1 + AoE/100). Angle and cast distance (`maxRange`) are unchanged. |
| CooldownReduction | **0 / 40** *(existing)* | `SkillManager.StartCooldown` | Cooldown × (1 − CDR/100). The reduced value is sent to the client's cooldown sweep. |
| CastTimeReduction | **0 / 40** *(existing)* | `SkillManager.ExecuteSkill` → `StartCasting` | Cast time × (1 − CTR/100). The server end time and the client cast bar both use it. |
| StatusResistance | **0 / 60** *(existing)* | `MobAI.ApplyEffectToPlayer` | Mob-applied Stun and Slow durations × (1 − SR/100). The slow strength is unchanged. |

CDR, CTR and StatusResistance are derived stats. They are read through `GetTotalStat`, so the RSV/PRE class scaling counts along with the bonus. For example, every class starts with about 2–3% CDR (RSV 5 × 0.45–0.65) and 3.5–5% StatusResistance, and these values now have an effect for the first time. AoESize is read as a whole percent (rounded) so the per-cast views can be cached.

Class-resource max bonuses (Determination / Aether / KillerInstinct / LifeEnergy) are read by `ResourceManager` since §AGX/D-FIX2; see [Class resources](#class-resources).

---

## Damage & healing

### Outgoing Damage Pipeline (Player → Mob)

**Source:** `DamageSystem.lua` — 8-step pipeline

```
1. BaseAttack    = PlayerDamage + WeaponAttack + FlatAttack
2. × ActionMultiplier       (skill coefficient, default 1.0)
3. × (1 + DamagePercent/100)  (percent damage bonus)
4. × ArmorMitigation        = 100 / (100 + effectiveArmor)
       effectiveArmor = max(0, mobArmor × (1 - armorReduction%/100) - playerPenetration)
       (armorReduction capped at 50%, playerPenetration capped at 60)
5. × CriticalHit            (multi-crit system, see below)
6. × ElementalMultiplier    (1.25 / 1.0 / 0.85)
7. × VulnerabilityMultiplier (from debuffs on target, capped ×2.0)
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
- **Procs:** max 2 (`CriticalSystem.lua:18-19`)
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

**Critical heals** use the same multi-crit pipeline as damage (`CriticalSystem.ApplyCrit`, §T1.3/B14): ≤200% chance, ≤1.80× per proc, max 2 procs. The old single-roll, 1.50×-capped heal crit is gone. Heal-over-time ticks go through the heal pipeline (HealingPercent and HealingPower apply) but never crit.

`HealingPower` in the formula is the healer's **Damage** stat (MAG-derived) plus the flat `HealingPower` bonus (`HealingSystem.lua:53-54`). Gear rolls `healingPower`, `healingPercent` and `statusResistance` apply since §AGX/D-FIX2.

### Elements

**Source:** `ElementalSystem.lua`

Cycle: **Wood → Earth → Water → Fire → Wood**

| Matchup | Multiplier |
|---|---|
| Attacker beats Defender | **1.25×** (Strong) |
| Defender beats Attacker | **0.85×** (Weak) |
| Same element | **1.0×** (Neutral) |
| Either is None / unrelated pair | **1.0×** (Neutral) |

### Crit damage: no class scaling

*§T1.2-BAL1, decided in §AGX/BAL.* Base 1.50×, cap 1.80× → +0.30× headroom, filled by gear/accessories/talents (+0.28)/Hunter innate (+0.15).
L60 reference builds; E = expected crit multiplier.

| Class | Crit % | CritDmg before | E before | CritDmg after | E after | Δ DPS | (alt: identity stat ×0.002) |
|---|---|---|---|---|---|---|---|
| Aegis | 11.1 | 1.50 | 1.0555 | 1.50 | 1.0555 | 0.00% | +0.63% |
| Arcanist | 12.7 | 1.54 (MAG×0.001) | 1.0686 | 1.50 | 1.0635 | −0.48% | +0.48% |
| Hunter | 46.0 | 1.65 | 1.2990 | 1.65 | 1.2990 | 0.00% | +2.83% (0% once gear hits cap) |
| LifeSteward | 11.6 | 1.50 | 1.0581 | 1.50 | 1.0581 | 0.00% | +0.77% |

Primary-stat scaling would double-dip the stat that already drives Damage/CritChance and is erased by the cap once gear adds ~+0.15×. Crit identity = CritChance coefficients + innate (Hunter +10%, +0.15×).

### Heals after the shared crit pipeline

*§T1.3-BAL1, §AGX/BAL.* Old heal crit: ≤100% chance, ≤1.50×, 1 proc. New: shared pipeline (≤200%, ≤1.80×, 2 geometric procs).
LifeSteward heal base = (10 + 2.5·MAG + HealingPower) × 1.15 (innate HealingPercent).

| Build | Crit % / CritDmg | E old | E new | Lift |
|---|---|---|---|---|
| L30 typical (MAG 20) | 8.9 / 1.55 | 1.044 | 1.049 | +0.4% |
| L60 typical (MAG 35) — reference | 18.6 / 1.70 | 1.093 | 1.130 | +3.4% |
| L100 endgame (MAG 55) | 27.7 / 1.80 | 1.139 | 1.222 | +7.3% |
| L100 crit-lean | 46.3 / 1.80 | 1.232 | 1.370 | +11.3% |
| L100 crit-stack | 90.8 / 1.80 | 1.454 | 1.726 | +18.7% |

Changes: Mending Touch 2.2 → **2.1**, Verdant Bloom burst 1.3 → **1.25** (both inside the lost BALANCE_REWORK_SPEC §31 bands). HoT ticks now go through the heal pipeline (+HealingPercent, +HealingPower, still no crit): +15% at L30, +27% at L60, +35% at L100 per tick.

Realised throughput, one target over 24 s (8× MT + 3× VB + 18 HoT ticks), vs pre-T1.3:
| Build | Pipeline only (no change) | After this pass |
|---|---|---|
| L30 typical | +0.4% | −3.0% |
| L60 typical (reference) | +3.2% | **+0.1%** |
| L100 endgame | +7.0% | +3.9% |
| L100 crit-lean | +10.9% | +7.6% |
| L100 crit-stack | +18.1% | +14.4% |

MAG investment still beats crit stacking in absolute healing, so the heal identity (MAG) is intact. Genesis full-heal now shows its number and grants heal XP.

Gear `critDamage` rolls are percent and are now divided by 100 before they enter the CritDamage multiplier (`PlayerBonusSystem`, §AGX/BAL); before, one roll pinned the 1.80× cap.

---

## Classes, skills & resources

**Source:** `ClassConfig.lua:107-258` (verified at `24c4d7e`).

> **ResourceMax coefficients** below feed the derived `ResourceMax` stat, but the resource bar does **not** read it: `ResourceManager` uses the class base max plus the `ResourceMax` *bonus* and the class-resource bonus key only (`ResourceManager.lua:97-115`). Whether RSV/MAG should raise the bar is an open question for Pablo ([BACKLOG](BACKLOG.md#needs-pablo)).

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
| CritDamage | none (no class scales CritDamage, §AGX/BAL) |
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
| CritDamage | none (no class scales CritDamage, §AGX/BAL) |
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
| CritDamage | none (no class scales CritDamage, §AGX/BAL) |
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
| CritDamage | none (no class scales CritDamage, §AGX/BAL) |
| CastTimeReduction | PRE × 0.25 |
| CooldownReduction | RSV × 0.65 |
| StatusResistance | RSV × 1.0 |
| ResourceMax | MAG × 1.5, RSV × 1.5 |

### Class skills

Source: `ClassSkills/<Class>Skills.lua` (verified at `24c4d7e`). Ultimates (slot 4): `minimumResource = 100` for all four (`AegisSkills.lua:234`, `ArcanistSkills.lua:219`, `HunterSkills.lua:209`, `LifeStewardSkills.lua:203`), cooldown 75 / 75 / 75 / 60 s, and `unlockLevel = 30`. `SkillManager` also has an older level-10 ultimate gate (`SkillManager/init.lua:548`); the level-30 check runs first, so **30 is the effective gate**.

#### Aegis Skills

| Slot | Skill | Cost | CD | Cast | Damage Mult | Shape | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Shield Boomerang | 8 res | 6s | 0s | 1.0× out / 0.7× return | Rect 25×6 | Travel 0.4s, return delay 0.1s |
| 2 | Taunt | 20 res | 12s | 0.5s | 0.45× | Circle r=12 | Pull (str=20, r=12) + Taunt (r=25, 5s) |
| 3 | Sundering Strikes | 16 res | 6s | 0.3s | 0.35× | Cone r=10, 120° | DoT: 0.1× dmg/tick, 1s interval, 6s, max 5 stacks. ArmorReduction: -5%/stack, 6s, max 5 |
| 4 | **Battle Beast** ★ | ALL (min **100**) | 75s | 1.0s | 0 | — | DR% = R/(R+100)×100. Allies get 70% of self DR. 6s. Ally cone: r=20, 120°. Unlock lv30 |
| 5 | Rush (Dash) | 8 res | 5s | 0s | — | — | Distance=18, duration=0.25s, unstoppable=true |

#### Arcanist Skills

| Slot | Skill | Cost | CD | Cast | Damage Mult | Shape | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Arcane Beam | 12 res | 4s | 0.3s | 1.2× | Rect 40×4 | Line/laser |
| 2 | Frost Bind | 20 res | 12s | 0.6s | 0.5× | Circle r=14 | Mouse-targeted (maxRange=40). Slow -50% 3s. DoT 0.15×/tick 1s for 3s. Element: Water |
| 3 | Arcane Surge | 30 res | 16s | 2.0s | 3.0× | Cone r=30, 90° | Knockback str=30. Element: Fire. Full channel required |
| 4 | **Meteorite** ★ | ALL (min **100**) | 75s | 1.5s | base 1.0× | Circle r=20 | Mouse-targeted (maxRange=50). Two hits (Fire+Earth). hitMult = base × (1 + R/100). Vulnerability 1.25× for 3s. Unlock lv30 |
| 5 | Space Jump (Dash) | 10 res | 6s | 0s | — | — | Distance=25, duration=0.15s, unstoppable=false |

#### Hunter Skills

| Slot | Skill | Cost | CD | Cast | Damage Mult | Shape | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Swift Arrow | 8 res | 3s | 0s | 1.2× | Pierce maxHits=3, -20%/target | Instant |
| 2 | Barrage | 16 res | 8s | 0s | 0.5× per arrow | Rect 50×3 | 5 arrows, 0.12s delay. Successive hit scaling: +0.25× per hit (1.0→1.25→1.50→1.75→2.0) |
| 3 | Rain of Arrows | 22 res | 14s | 1.2s | 0.8× per wave | Rect 30×12 | Mouse-targeted (maxRange=50). 2 waves, 0.25s delay. Element: Wood |
| 4 | **Eagle Eye** ★ | ALL (min **100**) | 75s | 0s | 0 | — | CritChance bonus = R × 0.5. -30% AttackSpeed. 6s. Unlock lv30 |
| 5 | Fast Steps (Dash) | 8 res | 5s | 0s | — | — | Distance=22, duration=0.2s, unstoppable=false |

#### Life Steward Skills

| Slot | Skill | Cost | CD | Cast | Heal/Damage | Shape | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Mending Touch | 8 res | 3s | 0.4s | **2.1×** heal | r=30 (targeting) | Heals lowest-HP ally (or self). Can crit. Element: Wood |
| 2 | Verdant Bloom | 18 res | 8s | 0.6s | **1.25×** AoE heal | r=20 | All allies. HoT: 0.08× per tick, 1s, 6s, max 2 stacks. Element: Wood |
| 3 | Nature's Purge | 14 res | 12s | 0.5s | — | r=25 | Cleanse 1 debuff from all allies. Priority: Stun > Slow > DoT |
| 4 | **Genesis** ★ | ALL (min **100**) | 60s | 2.0s | Full heal/revive | r=30 | If knocked-down ally: revive at 70% HP, 20% resource. Else: heal lowest to 100%. Unlock lv30 |
| 5 | Vine Slide (Dash) | 8 res | 6s | 0s | — | — | Distance=22, duration=0.15s, unstoppable=false |

### Class resources

**Source:** `ClassBehaviors/*.lua` `CONFIG` (verified at `24c4d7e`).

**Effective max** = class `MaxResource` (100) + `ResourceMax` bonus + the class's own resource bonus (`Determination` / `Aether` / `KillerInstinct` / `LifeEnergy`, from talents like "+5 Aether" and gear rolls) (`ResourceManager.lua:97-115`, §AGX/D-FIX2). Gear rolls map `mana`→Aether, `focus`→KillerInstinct, `lifeEnergy`→LifeEnergy. Bars can now exceed 100 (up to about 140). Regen rates stay absolute per second.

#### Aegis — Determination

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

#### Arcanist — Aether

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

#### Hunter — Killer Instinct

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

#### Life Steward — Life Energy

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

## Gear

### Weapons: scaling, refinement, tiers, reroll

**Source:** `WeaponConfig.lua`

#### Level Scaling

- Scale percent: **5%** per 10 levels
- Formula: `multiplier = (1 + 0.05) ^ floor(level/10)`

#### XP System

| Parameter | Value |
|---|---|
| XP Level Range | ±10 levels from weapon level |
| XP Base | **1** per kill |
| XP Mob Multipliers | Normal=1, Mini=5, Boss=10 |
| XP Required Formula | `round(80 + 8 × weaponLevel²)` |

Sample XP thresholds: Lv1→2: **88**, Lv10→11: **880**, Lv50→51: **20,080**

#### Refinement System

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

#### Temper Pity System

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

#### Tier System

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

#### Tier Upgrade Costs (Essence)

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

#### Reroll System

- Currency: **Merits**
- Base cost: **300**
- Tier multiplier: **1.46×**
- Formula: `floor(300 × 1.46^(tier-1))`
- Tier I: 300, II: 438, III: 639, VI: ~1,987

#### Starter Weapons

| Class | Starter Weapon |
|---|---|
| Aegis | SwordAndShield |
| Arcanist | ApprenticeWand |
| Hunter | ShortBow |
| LifeSteward | LifeTotem |

### Class weapons

#### Aegis Weapons

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

#### Arcanist Weapons

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

#### Hunter Weapons

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

#### Life Steward Weapons

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

### Armor

**Source:** `ArmorConfig.lua`

Identical structure to weapons. Shares refinement/tier/reroll systems.

#### Key Differences from Weapons

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

#### Starter Armors

| Class | Starter Armor |
|---|---|
| Aegis | PlateArmor |
| Arcanist | SilkRobe |
| Hunter | LeatherArmor |
| LifeSteward | BarkweaveVest |

### Class armors

Arcanist and Hunter armor used to roll `determination` (Aegis-only, so dead); since §AGX/D-FIX2 they roll `mana` (→ Aether) and `focus` (→ Killer Instinct).

#### Aegis Armors

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

#### Arcanist Armors

#### Silk Robe (Starter)

| Param | Value |
|---|---|
| Base DEF | **6** |
| Base HP | **30** |
| Refinement DEF/level | **+1** |

**Bonus Pool:** cooldownReduction (2-10), skillDamage (3-12), bonusHealth (15-60), statusResistance (3-12), critChance (2-10), critDamage (5-20), damageReduction (1-5), movementSpeed (2-8), flatAttack (3-12), mana (3-10), aoeSize (3-12), lifesteal (1-4), thorns (2-8), attackSpeed (1-5)

#### Arcane Vestment (Achievement Unlock)

| Param | Value |
|---|---|
| Base DEF | **9** |
| Base HP | **45** |
| Refinement DEF/level | **+2** |

**Bonus Pool:** skillDamage (5-18), cooldownReduction (3-14), critDamage (8-25), critChance (3-12), statusResistance (4-15), bonusHealth (25-80), aoeSize (5-15), damageReduction (2-8), movementSpeed (2-7), flatAttack (4-15), lifesteal (2-6), mana (4-12), thorns (2-8), attackSpeed (1-4)

#### Hunter Armors

#### Leather Armor (Starter)

| Param | Value |
|---|---|
| Base DEF | **8** |
| Base HP | **35** |
| Refinement DEF/level | **+1** |

**Bonus Pool:** critChance (3-12), movementSpeed (2-8), critDamage (5-20), attackSpeed (1-6), bonusHealth (15-50), statusResistance (2-10), damageReduction (1-5), skillDamage (3-12), flatAttack (3-12), cooldownReduction (2-8), lifesteal (1-4), focus (3-10), aoeSize (2-8), thorns (1-5)

#### Shadow Cloak (Achievement Unlock)

| Param | Value |
|---|---|
| Base DEF | **5** |
| Base HP | **25** |
| Refinement DEF/level | **+1** |

**Bonus Pool:** critChance (5-15), critDamage (8-30), movementSpeed (3-10), attackSpeed (2-8), skillDamage (4-15), flatAttack (5-18), lifesteal (2-6), cooldownReduction (3-12), statusResistance (2-8), bonusHealth (10-40), damageReduction (1-4), focus (2-8), aoeSize (2-8), thorns (1-4)

#### Life Steward Armors

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

### Accessories

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

### Gear rating (Power)

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

## Mobs, waves & modes

### Mob definitions

**Source:** `Mobs/` folder

#### Zombie (Normal)

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

#### Ogre (Miniboss)

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

#### Troll (Miniboss)

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

#### Iron Warden (Boss, CentralBoss only)

Source: `Mobs/IronWarden.lua` (§AGX/X28, placeholder model). Mode hidden until the Studio test.

| Stat | Base Value |
|---|---|
| Health | **4,000** × (1 + 0.75 × (players − 1)) |
| Damage | **30** |
| Armor | **10** |
| Knockback Resist | **1.0** (immune) |
| Speed | **8** |
| Attack Range / Cooldown | **11** / **2.4 s** |
| Element | None |
| Level | highest player level + 0 |

| Phase | Enters at HP | Skills | Attack cooldown × | Speed + | Damage × | Adds |
|---|---|---|---|---|---|---|
| Awakening | 100% | GroundSlam | 1.0 | 0 | 1.0 | — |
| Enraged | 66% | Roar (cd 16 s), GroundSlam | 0.6 | 3 | 1.15 | — |
| Desperation | 33% | Roar (cd 16 s), GroundSlam (cd 8 s) | 0.5 | 3 | 1.25 | 2 every 20 s (Troll/Ogre), max 4 alive |

### Mob scaling

**Source:** `MobRegistry.lua`

Power curve formula: `Multiplier(level) = ((level + 9) / 10) ^ exponent`

| Stat | Exponent |
|---|---|
| Health | **1.28** |
| Damage | **1.15** |
| Armor | **1.05** |
| Speed | **Not scaled** |

POWER_OFFSET = **9**

#### Sample Multipliers

| Level | Health Mult | Damage Mult | Armor Mult |
|---|---|---|---|
| 1 | 1.0× | 1.0× | 1.0× |
| 10 | ~1.76× | ~1.57× | ~1.16× |
| 20 | ~3.32× | ~2.67× | ~1.71× |
| 50 | ~10.6× | ~7.6× | ~4.1× |
| 100 | ~27.0× | ~17.5× | ~7.6× |
| 200 | ~69× | ~39× | ~14× |

Difficulty multipliers are applied **after** level scaling.

### Mob skills

**Source:** `MobSkills/` folder

#### Ground Slam

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

#### Intimidating Roar

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

### Difficulty tiers

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

### Lane waves

**Source:** `WaveConfig.lua`, `MobSpawner.lua`

#### Run Parameters (Lane Defense)

| Parameter | Value |
|---|---|
| Total Waves | **12** |
| Auto-Advance | Yes |
| Auto-Advance Delay | **7s** between waves |

#### Hand-Crafted Waves

*Updated 2026-09-26 (§AGX/X25): all 12 Lane waves are hand-crafted (`WaveConfig.lua:25-38`). Counts are Normal; `countMult` and `intervalMult` from [Difficulty tiers](#difficulty-tiers) apply on top.*

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

#### Procedural Generation (Wave 13+, unused in Lane)

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

#### Wave Mob Level Formula (Party Anchor)

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

#### EliteBounty Card Eligible Waves

Waves where the **EliteBounty** tactical card may appear: **4, 7, 10, 12** only.

### Game modes

**Source:** `GameModeConfig.lua`, `MatchmakingManager.lua`

| Mode | Available | Min/Max Players | Solo? |
|---|---|---|---|
| **Defense** | Yes | 1–4 | Yes |
| **Central Boss** | **No** (hidden until the Studio test, §AGX/X19) | 1–4 | Yes |
| **Horde Mode** | Yes | 1–4 | Yes |
| Arena | No (coming soon) | 2–4 | No |
| Raid | No (coming soon) | 4–4 | No |
| Exploration | No (coming soon) | 1–4 | Yes |


#### Horde Mode Mob Multipliers

Applied on top of difficulty tier multipliers. Horde mobs are weaker at the mob level since the mode compensates with infinite waves and run modifiers.

| Stat | Multiplier |
|---|---|
| HP | **0.60×** |
| Damage | **0.85×** |
| Armor | **0.80×** |

#### Horde Mode Reward Multipliers

| Reward | Multiplier |
|---|---|
| XP | **0.45×** |
| Merits | **0.50×** |
| Essence | **0.60×** |

#### Challenge Modifier Bonuses (stackable, per modifier applied)

| Modifier | XP Bonus | Merits Bonus | Essence Bonus |
|---|---|---|---|
| Standard | **+8%** | **+10%** | **+4%** |
| Lethal | **+12%** | **+15%** | **+6%** |

#### Challenge Modifier Caps (total across all stacked modifiers)

| Bonus Type | Cap |
|---|---|
| XP Bonus | **+40%** |
| Merits Bonus | **+50%** |
| Essence Bonus | **+20%** |

### Horde spawner

**Source:** `HordeModeSpawner.lua:70-116` (verified at `24c4d7e`)

#### Spawn Marker Setup

| Parameter | Value |
|---|---|
| Markers per player | **8** (orbit around player) |
| Orbit radius | **42** studs |
| Min spawn distance from any player | **27** studs |
| Spawn Y offset | **3** studs above ground |

#### Level Progression

| Parameter | Value |
|---|---|
| Starting level | **1** |
| Level tick interval | **75s** — level increases by +1 every 75s |
| Max auto-level | **30** |

#### Phases

| Phase | Start Time | Spawn Interval | Alive Cap | Spawn Weights | Speed Mult |
|---|---|---|---|---|---|
| 1 | 0:00 | **3.2s** | **40** | Zombie 100% | **1.6×** |
| 2 | 4:00 (240s) | **2.7s** | **56** | Zombie 96%, Troll 4% | **1.75×** |
| 3 | 7:00 (420s) | **2.3s** | **72** | Zombie ~90%, Troll ~5%, Ogre ~5% | **1.9×** |

Phase 3 continues indefinitely until the run timer expires.

#### RunModifiers Integration

HordeModeSpawner applies timed modifiers from `RunModifiers.GetModifier()` at each spawn tick:

- Spawn interval: `phase.interval × (1 + spawnIntervalScalar)`
- Alive cap is unaffected by modifiers (hard safety cap)
- Speed is: `phase.speedMult × phase.speedScalar × RunModifiers` (mob-speed card)

### Horde timing

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
| Num Spawners | **8** per player |

### Defense line

**Source:** `DefenseConfig.lua`

#### Chapter Max Health

| Chapter | Max HP |
|---|---|
| 1 | **1,500** |
| 2 | **3,500** |
| 3 | **7,000** |
| 4 | **12,000** |

#### Breach Damage

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

#### Combo System

| Param | Value |
|---|---|
| Enabled | Yes |
| Window | **3.0s** |
| Factor | **1.20×** per combo level |
| Max Level | **5** |
| Decay Rate | **1** level/s |

#### Detection

| Param | Value |
|---|---|
| Range | **5** studs |
| Check Interval | **0.2s** |

#### Visual Thresholds

| State | Threshold |
|---|---|
| Critical | **25%** HP |
| Damaged | **50%** HP |

#### Regen

Currently **disabled** (PerSecond=0, Delay=5s).

### Projectiles

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

## Death & regen

### Death and wipe-revive

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

#### Party-Wipe Revive

*Updated 2026-09-26 (§AGX/X25, documents §AGX/X40).* When the whole party is down, the run pauses for a **15 s** decision window.

| Parameter | Value |
|---|---|
| Free wipe-revives per run | Normal **3**, Hard **2**, Nightmare **1** (unknown difficulty → 1) |
| Paid wipe-revives per run | **1**, after the free ones are used |
| Paid price | **25 Essence** (placeholder; ≈6,250 Merits at the [economy anchor](#economy-anchor)) |
| Paid option shown | Only to players who can already afford it |
| Invulnerability after revive | **3 s** |
| Nothing left to offer | The run ends immediately |

### HP regen (combat places)

**Source:** `LaneDefenseMain.server.lua`, `HordeModeMain.server.lua`

| Parameter | Value |
|---|---|
| Vitals Broadcast Interval | **1 s** |
| Default Regen % | **0.5%** of max HP per tick |
| Default Regen Flat | **0** |

---

## Rewards

### Kill XP

**Source:** `KillRewardManager.lua`

#### Base XP Formula

`baseXP = xpNeeded × 0.03` (3% of XP needed to next level)

#### Tier Multipliers

| Mob Tier | Multiplier |
|---|---|
| Normal | **1×** |
| Miniboss | **8×** |
| Boss | **25×** |

#### Level Delta XP Scaling

| Delta (mobLevel − playerLevel) | Multiplier |
|---|---|
| −5 to +5 | **1.0×** |
| ±6 | **0.8×** |
| ±7 | **0.6×** |
| ±8 | **0.4×** |
| ±9 | **0.2×** |
| ≤−10 or ≥+10 | **0.0×** |

#### XP Sharing

| Parameter | Value |
|---|---|
| Share Range | **200 studs** |
| Split Method | Equal division by eligible party members in range |

#### Wave Completion XP

`waveXP = 15 + (15 × waveNumber)` — e.g. Wave 1 = 30, Wave 6 = 105, Wave 12 = 195.

### Drop tables

**Source:** `DropTableConfig.lua` + `DropManager.lua`

#### Per-Tier Defaults

| Tier | Drop Type | Chance | Min | Max | Scales? |
|---|---|---|---|---|---|
| **Normal** | Merits | 100% | 1 | 3 | Yes |
| **Miniboss** | Merits | 100% | 8 | 15 | Yes |
| | Essence | 30% | 2 | 4 | **No** (flat) |
| **Boss** | Merits | 100% | 25 | 50 | Yes |
| | Essence | 75% | 8 | 20 | **No** (flat) |

#### Level Scaling (Merits only)

Formula: `amount = base × (1 + (scaleLevel - 1) × 0.1)`

Essence drops have `noScale=true` — always flat amounts.

#### Who Gets Drops

*Updated 2026-09-26 (§AGX/X44).* Drops are **personal, one roll per party member per party kill**: every XP-eligible party member (and always the killer) rolls the mob's drop table independently. Amounts scale with the recipient's **own** level, `scaleLevel = min(mob RewardLevel, max(5, own level))`, and the [drop-scaling](#drop-scaling) delta window uses mob RewardLevel − own level. Mode, difficulty, BountyBoard and MeritBonus each apply once. Mob count does not scale with party size, so a party member earns about what a solo player does.

**Per-run budget (Lane, 12 waves, own level L):** Merits ≈ 542 × (1 + 0.1(L−1)) on Normal (≈1.0k at L10, 5.9k at L100, 11.3k at L200); Essence from drops ≈ 4 minibosses × 30% × 3 = **3.6** (×1.25 Hard, ×2 Nightmare).

### Drop scaling

**Source:** `DropManager.lua`, `DropTableConfig.lua`

#### Merit Delta Table (mob level − player level)

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

#### Essence Delta Table

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

#### Level Multiplier

`levelMult = 1 + ((mobLevel − 1) × 0.1)` — +10% per mob level above 1.

### Cards and votes

**Source:** `CardRegistry.lua`, `VoteManager.lua`, `RunModifiers.lua`

#### Vote Parameters

| Parameter | Value |
|---|---|
| Cards shown per vote | **3** |
| Vote duration | **10s** (or early close if all players vote) |
| Tie-break | Random among tied options |
| No-vote fallback | All 3 options equally likely |

#### Horde Vote Cadence (Horde Mode only)

*Updated 2026-09-26 (§AGX/X25): one alternating loop (`HordeModeMain.server.lua:390-438`).*

| Parameter | Value |
|---|---|
| Loop | One vote every **45 s** of play time, alternating supply → threat |
| Supply votes | First at **45 s**, then every **90 s** → **7** per 630 s run |
| Threat votes | First at **90 s**, then every **90 s** → **7** per run |
| Total | **7 + 7** (was documented as 14 supply + 7 threat) |

#### Tactical Vote Cadence (Lane Defense only)

| Parameter | Value |
|---|---|
| Trigger | Start of each wave |
| Total in 12-wave run | **12 votes** (one per wave) |
| Wave gate | Wave waits until vote resolves |

#### Horde Run Duration

| Parameter | Value |
|---|---|
| Play time (paused excluded) | **630s (10:30)** |
| Wall-clock (approx) | ~13:18 (pauses count as ~168s supply + subset threat) |
| End condition | Timer expires → spawner stops → mob clear → TriggerVictory |
| Auto-return to lobby | **10s** after TriggerVictory |

#### RunModifiers Caps (Hard Guardrails)

| Modifier | Cap |
|---|---|
| Danger bonus (max) | **+45%** |
| Danger bonus (min) | **-25%** |
| Spawn acceleration (max) | **-18%** (18% faster) |
| Speed reduction (max) | **-30%** |
| Per-wave danger cap | **±12%** |
| Total danger (combined) | **±45% / -25%** |

#### Supply Cards (Horde Mode)

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

#### Threat Cards (Horde Mode) — 3 Lanes

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

#### Tactical Cards (Lane Defense)

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

#### Essence Card Budget

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

### Run modifiers and danger

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

### Quests

**Source:** `LobbyNPCRegistry.lua`

#### Captain Aldric Quests

| Quest ID | Title | Objectives | Rewards |
|---|---|---|---|
| `first_defense` | A Line in the Sand | Complete 1 Defense mission | 25 Essence, 35% XP |
| `veteran_defender` | Veteran Defender | Complete 5 Defense missions | 2,500 Merits, 10 Essence |

> Both quests are non-repeatable (one-time only).
>
> *Updated 2026-09-26 (§AGX/X41):* was 100 Essence and "10 Merits, 300 Essence" (400 Essence one-time ≈ 111 runs of drops; the second quest's amounts looked swapped). 25 Essence pays the first two tier-ups (10 + 15). 2,500 Merits ≈ 3 runs at the level you finish 5 runs, plus 10 Essence; ≈5,000 Merits of value at the [economy anchor](#economy-anchor).

### Daily login

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

### Achievements

Source: `ReplicatedStorage/Shared/AchievementConfig.lua`. 26 achievements: 25 with **10 tiers** each, plus the one-shot `veteran`. Rewards per tier are in the config; the last column sums all tiers. `RespecToken` rewards grant a `respec_scroll` item (the old `RespecTokens` counter is gone). `TalentPoint` is +1 permanent bonus talent point ([Bonus talent points](#bonus-talent-points)).

| id | Name | Category | Stat | Tier thresholds (T1 … T10) | Total reward (all tiers) |
|---|---|---|---|---|---|
| `kills` | Slayer | Combat | `totalKills` | 50 / 250 / 1K / 4K / 12K / 35K / 100K / 275K / 700K / 2M | 258.9K Merits, 277 Essence, 2 RespecToken |
| `miniboss_slayer` | Elite Hunter | Combat | `killsByTier.miniboss` | 5 / 25 / 75 / 200 / 500 / 1.2K / 3K / 7K / 15K / 35K | 392.85K Merits, 434 Essence, 3 RespecToken |
| `boss_slayer` | Boss Breaker | Combat | `killsByTier.boss` | 1 / 5 / 15 / 40 / 100 / 250 / 600 / 1.5K / 3.5K / 8K | 607.45K Merits, 1 TalentPoint, 560 Essence, 3 RespecToken |
| `critical_striker` | Precision | Combat | `criticalHits` | 25 / 150 / 600 / 2K / 6K / 18K / 50K / 130K / 320K / 800K | 238.755K Merits, 244 Essence, 2 RespecToken |
| `destroyer` | Destroyer | Combat | `totalDamageDealt` | 5K / 30K / 150K / 600K / 2M / 7M / 25M / 80M / 250M / 1B | 238.755K Merits, 244 Essence, 2 RespecToken |
| `combo_king` | Combo King | Combat | `bestCombo` | 10 / 25 / 50 / 100 / 150 / 200 / 250 / 300 / 400 / 500 | 232.7K Merits, 227 Essence, 2 RespecToken |
| `relentless` | Relentless | Combat | `hitsDelivered` | 500 / 2.5K / 10K / 40K / 120K / 350K / 1M / 3M / 8M / 25M | 196.165K Merits, 216 Essence, 2 RespecToken |
| `survivor` | Survivor | Survival | `wavesSurvived` | 10 / 50 / 150 / 400 / 900 / 2K / 5K / 12K / 30K / 75K | 373.73K Merits, 380 Essence, 3 RespecToken |
| `wave_master` | Wave Master | Survival | `highestWave` | 10 / 25 / 50 / 75 / 100 / 125 / 150 / 175 / 200 / 250 | 481.35K Merits, 1 TalentPoint, 511 Essence, 3 RespecToken |
| `thick_skin` | Thick Skin | Survival | `totalDamageTaken` | 2.5K / 15K / 75K / 300K / 1M / 4M / 15M / 50M / 150M / 500M | 196.255K Merits, 208 Essence, 2 RespecToken |
| `life_giver` | Life Giver | Healer | `healingDone` | 1K / 10K / 50K / 200K / 700K / 2M / 7M / 20M / 60M / 200M | 518.725K Merits, 511 Essence, 3 RespecToken |
| `revivalist` | Revivalist | Healer | `revivesDone` | 1 / 5 / 15 / 35 / 75 / 150 / 300 / 600 / 1.2K / 2.5K | 574.075K Merits, 542 Essence, 3 RespecToken |
| `merit_earner` | Merit Earner | Collection | `meritsCollected` | 5K / 25K / 100K / 350K / 1M / 3M / 8M / 20M / 50M / 150M | 490 Essence, 4 RespecToken |
| `essence_hoarder` | Essence Hoarder | Collection | `essenceEarned` | 50 / 150 / 400 / 1K / 2.5K / 6K / 15K / 35K / 80K / 200K | 1.12715M Merits |
| `battle_hardened` | Battle Hardened | Dedication | `hitsReceived` | 250 / 1.5K / 7K / 30K / 100K / 300K / 850K / 2.5M / 7M / 20M | 186.315K Merits, 187 Essence, 2 RespecToken |
| `veteran` | Veteran | Dedication | `accountLevel` | 50 | 1 AppearanceChange, 1 TalentPoint |
| `arms_master` | Arms Master | Weapon | `weaponLevelMax` | 4 / 8 / 12 / 16 / 20 / 24 / 28 / 32 / 36 / 40 | 613.3K Merits, 574 Essence, 3 RespecToken |
| `talent_seeker` | Talent Seeker | Weapon | `talentNodesAllocated` | 3 / 8 / 15 / 24 / 35 / 50 / 70 / 95 / 125 / 160 | 534.95K Merits, 489 Essence, 3 RespecToken |
| `medal_iron_warden` | Iron Warden Medal | Medals | `killsByMobId.iron_warden` | 1 / 3 / 7 / 15 / 30 / 60 / 110 / 185 / 300 / 500 | 767.6K Merits, 914 Essence, 6 RespecToken |
| `medal_void_harbinger` | Void Harbinger Medal | Medals | `killsByMobId.void_harbinger` | 1 / 3 / 7 / 15 / 30 / 55 / 100 / 175 / 280 / 450 | 947.7K Merits, 1.085K Essence, 6 RespecToken |
| `medal_pale_colossus` | Pale Colossus Medal | Medals | `killsByMobId.pale_colossus` | 1 / 3 / 6 / 12 / 25 / 50 / 90 / 155 / 250 / 400 | 1.1031M Merits, 1.261K Essence, 6 RespecToken |
| `medal_abyssal_sovereign` | Abyssal Sovereign Medal | Medals | `killsByMobId.abyssal_sovereign` | 1 / 3 / 6 / 12 / 24 / 45 / 80 / 135 / 220 / 350 | 1.2565M Merits, 1.434K Essence, 6 RespecToken |
| `mastery_cap50` | Iron Devotee | Mastery | `capMasteryKills.cap50` | 1 / 3 / 7 / 15 / 30 / 60 / 110 / 185 / 300 / 500 | 1.1935M Merits, 1 TalentPoint, 1.38K Essence, 6 RespecToken |
| `mastery_cap100` | Void Devotee | Mastery | `capMasteryKills.cap100` | 1 / 3 / 7 / 15 / 30 / 55 / 100 / 175 / 280 / 450 | 1.4007M Merits, 1.596K Essence, 6 RespecToken |
| `mastery_cap150` | Colossus Devotee | Mastery | `capMasteryKills.cap150` | 1 / 3 / 6 / 12 / 25 / 50 / 90 / 155 / 250 / 400 | 1.6019M Merits, 1.772K Essence, 6 RespecToken |
| `mastery_cap200` | Sovereign Devotee | Mastery | `capMasteryKills.cap200` | 1 / 3 / 6 / 12 / 24 / 45 / 80 / 135 / 220 / 350 | 1.8522M Merits, 1.953K Essence, 6 RespecToken |

Boss medals and cap-mastery need boss mobs. Only `iron_warden` exists (CentralBoss, hidden until tested), so the other three medals and `mastery_cap100/150/200` can't be earned yet.

---

## Talents

Source: `ReplicatedStorage/Shared/TalentTreeConfig.lua`, `TalentManager.lua`.

### Tree size and points

| Item | Value |
|---|---|
| Nodes | **301**: 1 free Origin + 300 allocatable (210 small, 75 notable, 15 keystone) in 15 branches |
| Cost | **1** point per node (Origin free) |
| Points | Sum of the levels of every owned weapon, all classes, + `BonusTalentPoints` (minimum 1). Endgame budget ≈ **400** (4 classes × 2 weapons × level 50) |
| Respec | See [Respec costs](#respec-costs) |

### Keystones

12 of 15 have their rule implemented (`TalentTreeConfig.IMPLEMENTED_RULES`, `TalentTreeConfig.lua:752-765`). The other 3 show "(coming soon)" and their penalties are skipped until the rule lands.

| Keystone | Branch | Effect (config text) | Status |
|---|---|---|---|
| Overwhelm | Warpath | Hits on enemies above 70% HP: +15 Penetration, +10% Damage. Attack Speed −6% | ✅ |
| Second Heart | Lifeblood | Once per 45 s, dropping below 35% HP regenerates 8% max HP over 4 s; Damage −12% while active | ✅ |
| Perfect Form | Precision | Stationary 1.5 s: +12% Crit Chance, +0.10× Crit Damage; moving suppresses it for 2 s | ✅ |
| Arc Saturation | Attunement | Skills hitting 4+ targets: +12% Skill Damage, +15% AoE Size. Primary attacks −10% damage | ⏳ needs a per-cast hit-count hook |
| Calm Under Fire | Resolve | Above 80% HP: +6% CDR, +10% Status Resist. Below 40% HP: Attack Speed −8%, DR +8% | ⏳ rule not written; **pending Pablo's OK** ([BACKLOG](BACKLOG.md#needs-pablo)) |
| Unyielding Advance | Juggernaut | +1% DR per enemy within 10 studs (max 10%). Movement Speed −8% | ✅ |
| Cull the Weak | Predator | Hits on enemies below 25% HP: +15% Damage, +2% Lifesteal. Full-HP enemies −5% | ✅ |
| Clarity Surge | Oracle | Crit heals +8 Life Energy; crit skill hits +4 Aether (once per cast). Lifesteal set to 0 | ✅ |
| Spell Rhythm | Spellblade | See [Spell Rhythm](#spell-rhythm) | ✅ (no price: [BACKLOG](BACKLOG.md#needs-pablo)) |
| Patron Saint | Sanctuary | Party aura, see [Keystone party auras](#keystone-party-auras). Damage −10% | ✅ |
| Last Bastion | Bulwark | Determination > 70%: +8% DR, +20% Taunt Duration. < 20%: Movement Speed −10% | ✅ |
| Relentless Quarry | Huntmaster | 4 hits on one enemy within 3 s marks it for 6 s: +10% Crit Chance, +10 Penetration against it | ✅ |
| Shared Grace | Grace | 20% of overheal becomes a 4 s heal over time. Lifesteal ×0.5 | ✅ |
| Eye of the Storm | Stormweave | Single-target skills +18% damage; skills hitting 4+ targets +20% AoE Size. Resource cost +10% | ⏳ needs a per-cast hit-count hook |
| Fortune Favors | Fortune | Party aura, see [Keystone party auras](#keystone-party-auras). Damage −6%, Skill Damage −6% | ✅ |

### Keystone party auras

*§AGX/X11, `StatsManager/PartyAura.lua`.*

- Tick 1 s · range 30 studs (3D) · share = 50% of the OWNER's talent-sourced bonus
- Patron Saint: HealingPower, HealingPercent, XPBonus, MeritBonus (price: −10% Damage)
- Fortune Favors: XPBonus, MeritBonus (price: −6% Damage, −6% Skill Damage)
- Party members only (owner excluded), alive, same party; different owners don't stack per stat: strongest wins. Source: BonusManager "aura_<UserId>".
- The owner never receives their own aura (open question for Pablo, [BACKLOG](BACKLOG.md#needs-pablo)). Since §AGX/D-FIX2 the aura also works in the Lobby (it finds the Lobby PartyManager).

### Spell Rhythm

*§AGX/X11, `StatsManager/KeystoneRules.lua`.*

- +1 Rhythm per skill cast, 5 s per stack, max 3; the next basic attack uses up all stacks for +8% DamagePercent per stack (max +24%). No price.

### Bonus talent points

*§AGX/BTP: +1 each, one-time, ledger-guarded, back-paid on login.*

- boss_slayer T2 (5 bosses) · wave_master T2 (wave 25, Horde only) · veteran (L50) · mastery_cap50 T1
- Total 4 ≈ 1% of the 400-point weapon-level budget.

---

*Last updated from full codebase audit, March 2026. All values verified against source files.*
*Respec economy section added in the April 2026 overnight respec-fragment update.*

---

## Shop & monetization

### Shop prices

**Source:** `ShopConfig.lua`

#### Cosmetics Tab

| Item | Price | Currency | Level Req |
|---|---|---|---|
| hood_basic | **200** | Merits | — |
| helm_aegis | **500** | Merits | 5 |
| circlet_arcanist | **500** | Merits | 5 |
| mask_hunter | **500** | Merits | 5 |
| dark_knight | **25** | Essence | 10 |
| shadow_robes | **25** | Essence | 10 |
| forest_ranger | **25** | Essence | 10 |

#### Consumables Tab

| Item | Price | Currency | Level Req |
|---|---|---|---|
| health_potion | **25** | Merits | — |
| health_potion_large | **100** | Merits | 5 |
| health_elixir | **5** | Essence | 10 |
| mana_crystal | **30** | Merits | — |
| mana_crystal_large | **120** | Merits | 5 |
| power_scroll | **150** | Merits | 5 |
| iron_skin_potion | **150** | Merits | 5 |
| swiftness_elixir | 100 | Merits | 3 |
| fortune_incense | **10** | Essence | 8 |
| crit_oil | **120** | Merits | 5 |
| respec_scroll | **25** | Essence | 10 |

#### Premium Tab (Robux)

*§AGX/X40 (2026-09-26):* the Essence Pack, Merit Bundle and Respec Token x3 were **deleted**. Robux no longer buys gameplay currency or anything that converts into it. The Premium catalog and the no-P2W rule are in [Monetization (Robux)](#monetization-robux).

The two NPC shops sell staples only, built from `ShopConfig` at the same prices (§AGX/X24): Grimjaw (Blacksmith) `health_potion`, Mirael (Enchantress) `mana_crystal`. The old NPC-only items (Iron Sword, Steel Shield, Arcane Focus) were removed.

### Consumables

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
| Swiftness Elixir | **+10%** MovementSpeed ² | 30s | 100 Merits | 3 | 45s | 10 | ✅ live |
| Fortune Incense | **+15%** MeritBonus | 120s | **10** Essence | 8 | 120s | 5 | ✅ live |
| Crit Oil | **+8** CritChance (points) | 45s | **120** Merits | 5 | 60s | 10 | ✅ live |
| Respec Scroll | 1 free respec (talents or stats) | — | **25** Essence | 10 | — | 99 | ✅ used from the respec panels |
| Respec Fragment | 4 auto-combine into 1 Respec Scroll | — | not sold | — | — | 99 | passive |

¹ Ironskin is +12% **Armor**. That is not +12% mitigation: armor mitigation is `100 / (100 + armor)`, so it gains less than 12%. While `PlayerDataConfig.BonusStats` has no `ArmorPercent` key, it's applied as a flat Armor bonus of 12% of the player's Armor at use time, excluding its own previous stack. If `ArmorPercent = 0` is added there, `GetTotalStat` applies it as a true percent and no code change is needed.
² *§AGX/STATS (2026-09-26):* a timed `MovementSpeed` bonus (was the non-existent `MovementSpeedPercent` key). DeathSystem folds MovementSpeed into the X13 `BaseWalkSpeed` (natural 16 × (1 + MovementSpeed/100)), so MobAI slows and stuns still apply on top of it. It adds up with gear, talents, the Hunter innate (+8%) and keystones, and the total is capped at **+30%** (see §STATS caps). A Hunter with the innate +8% and the elixir moves at 16 × 1.18 = 18.9 studs/s.

#### Use rules (server-side, `ConsumableEffects.Use`)

- **Where:** *§AGX/STATS:* only in combat places (LaneDefense, HordeMode, CentralBoss). In the Lobby and SocialPlaza, Use replies "Use this in a run." and nothing is spent. Before this, Fortune Incense boosted the lobby's daily-login Merits. The gate is `DeathSystem.IsActive()`, because only combat places load DeathSystem.
- **Validation:** the player must own the item, be alive (not knocked down or dead), and the run must not be paused (same gate as §AGX/X7). The item's per-player cooldown must also be clear.
- **No waste:** heals are refused at full HP, restores are refused at full resource, and Ironskin is refused with 0 Armor. A refused use doesn't spend the item.
- **Order:** checks → reply text built → `InventoryManager.ConsumeItem` → cooldown armed → effect. *§AGX/STATS:* the item is given back only if the effect errors **before anything was applied**. If it errors after the effect landed (for example, while scheduling the "wore off" notice), the item stays spent and the use succeeds. The cooldown is armed in every case, so a failing effect can't be used over and over for free.
- **Cooldown:** one per item id, per player. Different items, like a Health Potion and a Greater Health Potion, don't share one.
- **Stacking:** using the same buff again **refreshes** its duration and doesn't add a second copy. The BonusManager source is `timed_consumable_<id>`. A config can opt in to `stacks = true`, and none do. Buffs from *different* items, or from a card with the same stat, do add up.
- **Heal over time:** the heal is split into 0.25s ticks. It stops if the player is knocked down, dies, leaves, or respawns into a new character. *§AGX/STATS:* no ticks land during the Horde vote pause, and the remaining ticks resume when it ends.
- **Lifetime:** buffs last only for the current server and end when the player leaves or teleports (lobby → run included). No config sets `persistAcrossTeleport`, which isn't supported yet. Per-player threads live in a Janitor that's destroyed on `PlayerRemoving`.
- **Currency:** everything costs Merits or Essence. Consumables are never sold for Robux ([Monetization](#monetization-robux), X40).

#### Economy notes

- **Sinks:** consumables are a repeatable Merit sink, and Fortune Incense and the Elixir are repeatable Essence sinks. Their cost scales with how often they're used, not with level.
- **Fortune Incense:** 10 Essence for +15% Merits over 120s. It pays off only when 15% of the Merits earned in those 120s is worth more to the player than 10 Essence. It's meant for a dense Merit window, like a Horde wave. *Unspecified:* no Essence↔Merit rate is defined and there's no Merits-per-minute telemetry, so the break-even isn't known. Watch purchases to see whether it's bought at all.
- **Fortune Incense cap:** the +15% adds to talent and gear MeritBonus. Refunds (`raw = true`, X32) ignore it.

### Shop rotation and paid refresh

**Source:** `ShopConfig.lua` (`Rotation`, `Refresh`, `staple`), `ShopManager.lua` (§AGX/D7), `GlobalShopUI.lua` · *Added 2026-09-26 (§DISC/D7). Not yet tested in Studio. The catalog items themselves are still placeholders.*

#### What rotates

| Tab | Always sold (`staple = true`) | Rotation pool | Slots | Period |
|---|---|---|---|---|
| Consumables | `health_potion`, `health_potion_large`, `mana_crystal`, `mana_crystal_large`, `respec_scroll` | `health_elixir`, `power_scroll`, `iron_skin_potion`, `fortune_incense`, `crit_oil`, `swiftness_elixir` (live since §AGX/STATS) | **3 of 6** | **6 h** (00/06/12/18 UTC) |
| Cosmetics | none | all 7 | **4 of 7** | **24 h** (00:00 UTC) |
| Premium (Robux) | all | none | — | never |

Why:
- **Staples never rotate.** Basic healing and mana are needed to play, and the respec scroll is the Essence fallback ([Respec economy](#respec-economy-scrolls-and-fragments)). Rotating them would gate play or talent experiments behind luck. The two NPC shops sell only staples, so they are unaffected.
- **Buffs and cosmetics rotate.** They are optional, so rotating them gives variety and a reason to check back without blocking anyone. 3 of 6 means each buff is in stock 50% of the time (Swiftness joined the pool in §AGX/STATS; it was 3 of 5, 60%). 4 of 7 cosmetics means each one is shown on about 57% of days.
- **Premium never rotates.** A countdown on a Robux listing is fake urgency, a dark pattern. It also keeps [Monetization](#monetization-robux) simple.
- Unusable (`enabled = false`) items are left out of the pool, so they never take a slot.

#### Per-player, deterministic, no DataStore writes

Each rotation is drawn on the server from the seed `(UserId, tab, periodIndex, roll)`:
- `periodIndex = floor(os.time() / period)`. It is aligned to the UTC epoch, so every server agrees.
- `roll` is the number of paid refreshes of that tab in that period.
- The draw is an FNV-1a hash feeding an xorshift32 partial Fisher-Yates. It is pure Luau, not `Random.new`, so an engine update can't change it.

Properties:
- Nothing is written when a tab rotates.
- Rejoining or hopping servers can't re-roll the stock.
- The client never computes the draw. The server sends the list in `ShopState.rotation`.

The server refuses to sell a rotating item that is not in that player's current rotation. There is a **10 s grace** after a flip, for a click on the last second. This check covers the global shop and the NPC `ShopHandler` route.

Headless check with the luau CLI over 20,000 draws (run when the pool was 5): each consumable was up 59.6–60.7% (target 60%), each cosmetic 56.6–57.7% (target 57.1%). With the 6-item pool the target is 50%; not re-run.

#### Paid refresh ("Refresh now")

| Rule | Value |
|---|---|
| Scope | Re-rolls **one** tab's current rotation. The timer does not move. |
| Price (nth refresh of the UTC day, shared across tabs) | **5 / 10 / 20 Essence** (≈1,250 / 2,500 / 5,000 Merits at 1 E = 250 M, [anchor](#economy-anchor)) |
| Daily cap | **3** (max **35 Essence/day**). Resets at 00:00 UTC. |
| Guaranteed change | A re-roll always shows at least one item the previous roll did not. It redraws up to 8 times, and in the 20k-draw test no identical re-roll happened. |
| Refused without charge | Less than 5 min left before the free rotation; the tab doesn't rotate; the pool is not bigger than the slot count; daily cap reached; not enough Essence; **stale request** (the `{period, roll}` the client saw no longer matches, which makes a double-click or replay idempotent) |
| Order | Per-player lock (the shared purchase lock, same pattern as EquipmentRefinement `attemptLock`). Then `SpendEssence`, and its result is checked. Then the counter is written in one assignment, with a refund if that write throws. |
| Storage | `Account.ShopRotation = { day, refreshes, rolls = { [tab] = { period, n } } }`. It saves in the same blob as the Essence it cost, so a lost save loses both. |
| Robux | **Never.** Essence is earn-only (X40, [Monetization](#monetization-robux)), so this is a pure Essence sink. |

#### Sink sizing

Essence income (mid-game): Lane Normal ≈ 15 E/run ([anchor](#economy-anchor)). Daily login ≈ 7.6 E/day from the calendar plus ≈ 1.2 from the spree ([Daily login](#daily-login)).

| Archetype | Runs/day | ≈ Essence/day | Max refresh spend | Share if maxed |
|---|---|---|---|---|
| Casual | 1 | ≈ 24 | 5 (one refresh is the realistic max) | ≈ 21% |
| Core | 4 | ≈ 69 | 35 | ≈ 51% |
| Grinder | 10 | ≈ 159 | 35 | ≈ 22% |

The refresh is an optional convenience sink, and the free rotation is always the no-cost path. Doubling the price and capping at 3 bounds the worst day at 35 E, about 1.4 of a respec (25 E).

Value check: hunting a specific 25 E cosmetic costs about 9 E of refreshes on average (first refresh 5 E, then a 43% chance of needing the 10 E one), a ≈37% impatience premium. Refreshing only to find a Merit-priced buff (≤150 M) is poor value on purpose, because the free 6 h rotation covers that.

Telemetry to add later: refreshes per player-day and the share of players who refresh at least once. The target is >20% participation, or the prices get revisited.

### Auction (config only)

**Source:** `AuctionConfig.lua`

> Config is complete; no auction runtime exists yet (the old "§52.3" reference is to the lost BALANCE_REWORK_SPEC).

#### Auction Bands

| Band | Levels |
|---|---|
| 1 | 1–50 |
| 2 | 51–100 |
| 3 | 101–150 |
| 4 | 151–200 |

#### Trading Restrictions

| Parameter | Value |
|---|---|
| Min Trade Level | **20** |
| Listing Tax | **12%** |
| New Account Cap (first 7 days) | 3 listings/day, 5 purchases/day |

### Monetization (Robux)

**Source:** `ShopConfig.lua` (Premium tab), `MonetizationService.lua`, `ShopManager.PurchasePremium` · *Added 2026-09-26 (§AGX/X40).*

#### The no-P2W rule

Gameplay currency (Merits, Essence) is **never sold for Robux**, and nothing bought with Robux may turn into currency or power. Refine, reroll and tier-up stay earn-only, and so are not paid random items. Robux buys only:

- cosmetics (no stats),
- appearance changes (`CharacterManager.GrantAppearanceChange`, §AGX/X18) — but only **after** the one free change earned at level 50 (see below, §AGX/X18b),
- non-power convenience or social perks.

Things that are **not** allowed for Robux, even though they look like convenience:

| Not allowed | Why |
|---|---|
| Merit / Essence packs | Direct currency sale. |
| Respec scrolls or tokens | A scroll is worth 25 Essence ([anchor](#economy-anchor)), so selling one frees 25 Essence for refine or reroll. |
| Consumables (potions, buffs, revives) | Power, and Essence-priced. |
| XP / drop / Merit boosts, extra revives | Power. The wipe-revive stays free 3/2/1, then 1 paid in Essence (§AGX/X40). |
| A cosmetic that is also sold for Merits/Essence | Buying it with Robux frees the Merits/Essence it would have cost. |

**Code guard:** `MonetizationService` only registers Premium entries whose `grant.type` is `AppearanceChange`, `Cosmetics` or `GamePass`. Any other entry is refused with a warning and can't be prompted. A `Cosmetics` bundle that contains an item from the Merit/Essence Cosmetics tab is registered (so receipts are honoured) but can't be prompted.

#### Catalog

Every entry is `enabled = false`, with `devProductId = 0` / `gamePassId = 0`, until Pablo creates the product in the Creator Dashboard and pastes its id. The Robux price in `ShopConfig` is for display only: Roblox charges the Dashboard price, so keep the two in sync.

| itemId | Kind | Robux | Grants | Purchase guard |
|---|---|---|---|---|
| `premium_appearance_change` | DevProduct | **49** | 1 appearance change (banked, then applied via `GrantAppearanceChange`) | Character must exist; no unused change (flag, banked token or free Veteran token, §AGX/X18b) |
| `premium_bundle_vanguard` | DevProduct | **99** | `helm_aegis` + `dark_knight` | Not all items owned. **Blocked today:** both are in the Merit/Essence Cosmetics tab |
| `premium_bundle_arcanum` | DevProduct | **99** | `circlet_arcanist` + `shadow_robes` | Same, blocked for the same reason |
| `premium_bundle_wildwood` | DevProduct | **99** | `mask_hunter` + `forest_ranger` | Same, blocked for the same reason |
| `premium_vip` | GamePass | **199** | `VIP` player attribute (nameplate + chat tag; nothing reads it yet) | Not already owned |

The bundles reference the only non-starter cosmetics that exist (all §DISC/D7 placeholders). Before enabling them, either replace them with Robux-exclusive cosmetics or take those items out of the Merit/Essence Cosmetics tab.

#### Appearance changes: one free at level 50, then paid (§AGX/X18b)

Pablo: *"You can create some random character at the beginning, but the second change is definitely a decision. One cosmetic change at level 50 with an achievement, then paid."*

| Step | Rule | Code |
|---|---|---|
| Creation | Free, once (first login) | `CharacterManager` / `CharacterCreation` |
| 1st change | **Free**: one-shot achievement **Veteran** (`veteran`, Dedication) at **account level 50** rewards `AppearanceChange ×1` | `AchievementConfig` (single tier `{ 50 }`), `AchievementManager` (`accountLevel` stat from the `Level` attribute; players already ≥ 50 get it on next login) |
| Storage | The free change is **stored**, not auto-opened: `Account.CharacterData.freeAppearanceTokens` (number, missing = 0) | `CharacterManager.AddFreeAppearanceToken` |
| Spending | Menu → Character → **Change appearance** fires `UseAppearanceChange` (1/s): an unused unlocked change reopens the screen for free; else one free token → `GrantAppearanceChange` → creation screen; the §AGX/X18 submit consumes it | `CharacterManager.UseAppearanceChange` |
| Later changes | **Paid** (`premium_appearance_change`, 49 R$). Can't be bought while a free token is unspent | `MonetizationService.canBuy` |
| Client | Attribute `AppearanceChangesAvailable` = free + paid banked + 1 if a granted change is still unused. Menu entry badge = that count; locked "Unlocks at level 50" below 50, else "No changes left". Not available in Combat | `Registry` `appearance`, `BadgeStore` `appearance` |

#### Receipts

| Rule | Value |
|---|---|
| ProcessReceipt owner | `MonetizationService` only (one per server; bootstrapped by `ShopManager.Init` in all 5 Places) |
| Idempotency | `PurchaseId` is written to `Account.Monetization.receipts` in the same in-memory step as the grant; a forced `SavePlayer` writes both in one UpdateAsync (§AGX/X3 lock) |
| `PurchaseGranted` | Only when that save returns `"ok"`; otherwise `NotProcessedYet` |
| Receipt history kept | Last **100** purchase ids per player |
| Robux spent | `Account.Monetization.robuxSpent`: private, never on a leaderboard (X46) |
| PolicyService (X46) | Not required while no Robux purchase reaches a random outcome or player trading |

---

## Chapters, party & infrastructure

### Chapters

**Source:** `ChapterConfig.lua`

#### Chapter Boundaries

| Chapter | Levels | Description |
|---|---|---|
| 1 | 1–50 | Tutorial & early game |
| 2 | 51–100 | Mid-game progression |
| 3 | 101–150 | Late-game push |
| 4 | 151–200 | Endgame mastery |

#### Gear Caps by Chapter

| Chapter | Max Refinement | Max Tier |
|---|---|---|
| 1 | **+8** | **V** |
| 2 | **+11** | **VIII** |
| 3 | **+13** | **X** |
| 4 | **+15** | **XII** |

#### Ascension Crests

Required to advance to the next chapter:

| Chapter Completed | Token Required |
|---|---|
| Chapter 1 → 2 | AscensionCrest_50 |
| Chapter 2 → 3 | AscensionCrest_100 |
| Chapter 3 → 4 | AscensionCrest_150 |

### Class mastery (dormant)

Config exists (`ClassMasteryConfig.lua`) but nothing earns mastery XP: `AddClassMasteryXP` was deleted (§T0P2/X21). Tracked as `§T0P2-MASTERY` in the backlog.

**Source:** `ClassMasteryConfig.lua`

#### Mastery Milestones

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

#### Second Weapon Gate

| Requirement | Value |
|---|---|
| Min Account Level | **60** |
| Required Milestone | `second_weapon` (30,000 mastery XP) |

#### Role Seal Map

| Class | Seal Token |
|---|---|
| Aegis | TankSeal |
| Hunter | DPSSeal |
| LifeSteward | HealerSeal |
| Arcanist | SupportSeal |

### Party

**Source:** `PartyManager.lua`

| Parameter | Value |
|---|---|
| Max Party Size | **5** |
| Invite Timeout | **30 s** |
| Max Level Gap | **10** levels |
| XP Bonus per Friend | **+5.0%** |
| XP Bonus per Non-Friend | **+2.5%** |

### Matchmaking

**Source:** `MatchmakingManager.lua`, `TeleportManager.lua`

| Parameter | Value |
|---|---|
| Countdown | **5 s** |
| Max Level Gap | **10** levels |
| Hard Unlock Level | **30** |
| Nightmare Unlock Level | **80** |

### Leaderboards

**Source:** `LeaderboardManager.lua`

| Parameter | Value |
|---|---|
| Periodic persist | every **7,200 s** per player, staggered, plus on leave (`LeaderboardManager.lua:97`) |
| Board read cache | **30 s** per board (§T5-T9/S4) |
| Max Entries | **50** per board |
| Boards | PowerLevel, HighestWave, TotalPlayTime |

### Networking and monitoring

**Source:** `NetworkManager.lua`, `MonitoringSystem.lua`

| Parameter | Value |
|---|---|
| Rate Limit | **30** calls per player per event per window |
| Rate Window | **1 s** |
| Suspicious Dodge Rate | **≥ 95%** |
| Distance Buffer | **10** studs beyond skill range |
| Max Hit Report Delay | **3.0 s** |
| Min Hits for Evaluation | **20** |

### Hit tracker

**Source:** `HitTracker.lua`

| Parameter | Value |
|---|---|
| Combo Decay Time | **3.0 s** |
| Combo Update Rate | **0.1 s** (10 Hz) |
| Min Combo for Notify | **3** |

---

## Old section numbers

Code comments and old docs cite this file by its pre-2026-09-26 numbers. The old file is `git show 24c4d7e:docs/BALANCE_NUMBERS.md`.

| Old | New heading |
|---|---|
| §1 Player Progression | [Progression & respec](#progression--respec) |
| §2 Primary & Derived Stats · §3 Stat Caps | [Stats & caps](#stats--caps), [Stat caps](#stat-caps) |
| §4 Class Definitions | [Classes, skills & resources](#classes-skills--resources) |
| §5 Class Skills | [Class skills](#class-skills) |
| §6 Class Resource Systems | [Class resources](#class-resources) |
| §7 Elemental · §8 Damage & Healing | [Damage & healing](#damage--healing) |
| §9 Difficulty Tiers | [Difficulty tiers](#difficulty-tiers) |
| §10–§13 Weapons / Armor | [Gear](#gear) |
| §14–§16 Mobs | [Mob definitions](#mob-definitions), [Mob scaling](#mob-scaling), [Mob skills](#mob-skills) |
| §17 Wave Config | [Lane waves](#lane-waves) |
| §18 Drop Tables · §36 Drop Scaling | [Drop tables](#drop-tables), [Drop scaling](#drop-scaling) |
| §19 Death System | [Death and wipe-revive](#death-and-wipe-revive) |
| §20 Defense Line · §44 Combo | [Defense line](#defense-line) |
| §21 Projectile Config | [Projectiles](#projectiles) |
| §22 Shop Prices · §23 Consumables | [Shop prices](#shop-prices), [Consumables](#consumables) |
| §24 Talent Tree | [Talents](#talents) (the old 4-branch table described a tree that no longer exists and was deleted) |
| §25 Achievements | [Achievements](#achievements) (regenerated from `AchievementConfig.lua`) |
| §26 Accessories | [Accessories](#accessories) |
| §27 Game Modes · §28 Horde Spawner · §42 Horde Timing | [Game modes](#game-modes), [Horde spawner](#horde-spawner), [Horde timing](#horde-timing) |
| §29 Card & Event Vote System | [Cards and votes](#cards-and-votes) |
| §30 Quest Rewards | [Quests](#quests) |
| §31 Chapter Config · §32 Class Mastery | [Chapters](#chapters), [Class mastery](#class-mastery-dormant) |
| §33 Auction Config (incl. the 250:1 anchor) | [Economy anchor](#economy-anchor), [Auction](#auction-config-only) |
| §34 Daily Login | [Daily login](#daily-login) |
| §35 Kill Rewards | [Kill XP](#kill-xp) |
| §37 Party · §38 Leaderboard · §39 Networking · §43 Matchmaking · §45 Hit Tracker | [Chapters, party & infrastructure](#chapters-party--infrastructure) |
| §40 Gear Rating | [Gear rating](#gear-rating-power) |
| §41 Run Modifiers | [Run modifiers and danger](#run-modifiers-and-danger) |
| §46 HP Regen | [HP regen](#hp-regen-combat-places) |
| §47 Respec Economy | [Respec economy](#respec-economy-scrolls-and-fragments) |
| §48 Monetization | [Monetization (Robux)](#monetization-robux) |
| §D7 Shop Rotation | [Shop rotation and paid refresh](#shop-rotation-and-paid-refresh) |
| "Combat balance pass" (§AGX/BAL) | [Combat caps](#combat-caps-not-in-statcaps), [Crit damage](#crit-damage-no-class-scaling), [Heals](#heals-after-the-shared-crit-pipeline) |
| "§STATS caps" | [Stat caps](#stat-caps), [Bonus-stat readers](#bonus-stat-readers) |

---

Last verified against code: `24c4d7e` (2026-09-26). Values in the sections below were re-read in `src/` during the docs pass: skills, class derivations and innates, resources, stat caps, combat caps, mobs, mob skills, Horde spawner, chapters, gear rating, run-modifier caps, death, defense line, party, leaderboards, networking, shop rotation, consumable pools, achievements. The rest carry the 2026-09-26 §AGX economy-pass verification.
