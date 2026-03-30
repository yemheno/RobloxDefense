# Mega Talent Tree Proposal

This proposal expands the current 13-node shared tree into a Path of Exile-style passive web that still fits the current Roblox Defense stat model, level cap, and server-authoritative talent architecture.

The design goal is not to let a level 200 character nearly finish the tree. The design goal is to force real specialization, create meaningful travel decisions, and let all four classes build into multiple endgame identities without hard class locks.

## 1. Summary

| Item | Proposal |
|---|---:|
| Total nodes in tree | **301** |
| Free start node | **1** |
| Allocatable nodes | **300** |
| Small nodes | **210** |
| Notable nodes | **75** |
| Keystone nodes | **15** |
| Cost per node | **1 point** |
| Start node cost | **0** |
| Base points at level 200 | **199** |

This immediately solves the main scaling issue in the current tree: with only 13 nodes, the tree is solved too early. With 300 allocatable nodes and 199 points at level cap, players can build deep, but they cannot trivialize the full board.

## 2. Design Pillars

1. Small nodes should mostly be travel power.
2. Notables should feel like clean mini-payoffs, worth roughly 2 to 3 small nodes.
3. Keystones should change play patterns, not just add raw numbers.
4. Meta economy nodes like XP and Merits should exist, but they should live on outer utility branches so they are never mandatory for pure combat builds.
5. Primary-stat travel nodes should exist because your game already has strong class derivation from MIG, VIT, PRE, MAG, and RSV.
6. The tree should stay class-agnostic at the rules level, but class-biased by geography.

## 3. Balance Guardrails

### Node Value Bands

| Tier | Budget Rule |
|---|---|
| Small | Usually `+1 primary stat`, `+1% to +2%` in a percentage stat, `+2 to +4` in a flat stat, or a light hybrid combination |
| Notable | Usually `+2 primary stats` plus one meaningful secondary bonus, or about `2.5x` a small node's value |
| Keystone | Strong directional passive with an upside and either a condition or a drawback |

### Cap Discipline

The proposal is built around the existing caps and formulas from the live balance doc.

| Stat | Existing Cap | Proposal Rule |
|---|---:|---|
| CritChance | 200% | Large totals exist, but most of the tree's crit chance sits in Precision, Oracle, Predator, and Huntmaster; heavy travel cost prevents universal cap access |
| CritDamage | 1.80x | Total crit damage in the tree is intentionally limited and concentrated in PRE-heavy sectors |
| DamageReduction | 75% | DR mostly lives in Juggernaut, Resolve, Bulwark, and Fortune; it is not broadly available |
| CooldownReduction | 40% | CDR is concentrated in Resolve, Spellblade, and Stormweave; the tree does not hand it out everywhere |
| CastTimeReduction | 40% | Cast speed is concentrated in Precision, Resolve, Oracle, Grace, and Stormweave |
| Lifesteal | 25% | Lifesteal is mainly in Predator, Sanctuary, and Fortune, with keystone tradeoffs preventing free sustain stacking |
| AttackSpeed | +75% | Attack speed is intentionally split across PRE/MIG sectors and some outer Hunter-leaning regions |
| StatusResistance | 60% | Status resistance is largely confined to Resolve and related defensive branches |

### Practical Endgame Intent

1. A pure tank can build high armor, high health, meaningful DR, taunt utility, and retaliation, but gives up crit, meta utility, and caster payoff.
2. A pure ranged DPS can stack crit, attack speed, penetration, and execution tools, but becomes much thinner.
3. An Arcanist can choose wide-area spell spam, boss-focus spell damage, or hybrid attack-skill cadence.
4. A LifeSteward can build raw healing throughput, sustain utility, or progression support, but not all three at full strength.
5. Players who chase XP and Merit efficiency should visibly give up direct combat output.

## 4. Topology

The tree is arranged in three layers.

### Inner Attribute Ring

These are the five core identity sectors connected directly to Origin.

1. Warpath (MIG)
2. Lifeblood (VIT)
3. Precision (PRE)
4. Attunement (MAG)
5. Resolve (RSV)

### Middle Hybrid Ring

These sectors sit between adjacent primaries and create build identities.

1. Juggernaut (MIG/VIT)
2. Predator (PRE/MIG)
3. Oracle (MAG/PRE)
4. Spellblade (RSV/MAG)
5. Sanctuary (VIT/RSV support-utility)

### Outer Mastery Branches

These are deeper class-leaning annexes that require investment to reach.

1. Bulwark off Juggernaut
2. Huntmaster off Predator
3. Grace off Oracle
4. Stormweave off Spellblade
5. Fortune off Sanctuary

### Adjacency Map

| Sector | Connected To |
|---|---|
| Origin | Warpath, Lifeblood, Precision, Attunement, Resolve |
| Warpath | Origin, Juggernaut, Predator |
| Lifeblood | Origin, Juggernaut, Sanctuary |
| Precision | Origin, Predator, Oracle |
| Attunement | Origin, Oracle, Spellblade |
| Resolve | Origin, Spellblade, Sanctuary |
| Juggernaut | Warpath, Lifeblood, Bulwark |
| Predator | Warpath, Precision, Huntmaster |
| Oracle | Precision, Attunement, Grace |
| Spellblade | Attunement, Resolve, Stormweave |
| Sanctuary | Lifeblood, Resolve, Fortune |
| Bulwark | Juggernaut |
| Huntmaster | Predator |
| Grace | Oracle |
| Stormweave | Spellblade |
| Fortune | Sanctuary |

## 5. Rules Additions Needed

The current talent system already supports flat stat effects and boolean keystone rules. This proposal only needs two extensions.

### A. Primary Stat Talent Effects

Add a talent effect type that can grant primary stats directly.

Example:

```lua
{ primary = "MIG", value = 1 }
```

That bonus should be applied before class stat derivation so each class gets the intended benefit from attribute travel nodes.

### B. New Rule Flags

These are the new keystone-style booleans the proposal expects other systems to read.

1. `Overwhelm`
2. `SecondHeart`
3. `PerfectForm`
4. `ArcSaturation`
5. `CalmUnderFire`
6. `UnyieldingAdvance`
7. `SpellRhythm`
8. `ClaritySurge`
9. `CullTheWeak`
10. `PatronSaint`
11. `LastBastion`
12. `EyeOfTheStorm`
13. `RelentlessQuarry`
14. `SharedGrace`
15. `FortuneFavors`

## 6. Node Catalog

## Origin

| Node | Type | Effect |
|---|---|---|
| Origin | Start | Free. Auto-allocated. No stats. Connects to the five primary sectors. |

## 6.1 Warpath

Warpath is the MIG region. It supports flat physical pressure, penetration, weapon handling, and front-loaded damage.

| Node | Type | Effect |
|---|---|---|
| Brute Force | Small | `+1 MIG` |
| Heavy Grip | Small | `+1 MIG` |
| Blood in the Arms | Small | `+1 MIG` |
| Martial Bearing | Small | `+1 MIG` |
| Weapon Drill I | Small | `+2 FlatAttack` |
| Weapon Drill II | Small | `+2 FlatAttack` |
| Split Mail | Small | `+2 Penetration` |
| Sundering | Small | `+3 Penetration` |
| Killing Stroke | Small | `+2 BonusDamage` |
| Hard Swings | Small | `+2% DamagePercent` |
| Momentum Cut | Small | `+2% AttackSpeed` |
| Cleaving Line | Small | `+2% SkillDamage` |
| Crushing Pace | Small | `+2 Penetration, +1% AttackSpeed` |
| Battlefield Scar | Small | `+8 BonusHealth` |
| Martial Discipline | Notable | `+2 MIG, +4 FlatAttack` |
| Breachmaker | Notable | `+5 Penetration, +3% DamagePercent` |
| Iron Tempo | Notable | `+4% AttackSpeed, +2 BonusDamage` |
| Execution Weight | Notable | `+3 BonusDamage, +3% SkillDamage` |
| Red Steel | Notable | `+2 MIG, +10 BonusHealth, +3 Penetration` |
| Overwhelm | Keystone | Hits against enemies above `70% HP` gain `+15 Penetration` and `+10% DamagePercent`. AttackSpeed is reduced by `6%`. |

## 6.2 Lifeblood

Lifeblood is the VIT region. It is the baseline survival spoke for any build that wants raw effective health, regen, or retaliation.

| Node | Type | Effect |
|---|---|---|
| Hardy Soul | Small | `+1 VIT` |
| Thick Veins | Small | `+1 VIT` |
| Deep Breath | Small | `+1 VIT` |
| Packed Muscle | Small | `+1 VIT` |
| Healthy Frame I | Small | `+10 BonusHealth` |
| Healthy Frame II | Small | `+10 BonusHealth` |
| Iron Constitution | Small | `+1% HealthPercent` |
| Reserves of Flesh | Small | `+12 BonusHealth` |
| Fast Recovery | Small | `+0.15% HpRegen` |
| Knitted Flesh | Small | `+1 FlatHpRegen` |
| Thorn Nerves | Small | `+2 Thorns` |
| Stone Skin | Small | `+3 Armor` |
| Survival Pulse | Small | `+0.15% HpRegen` |
| Hold Together | Small | `+1% HealthPercent` |
| Veteran Hide | Notable | `+2 VIT, +15 BonusHealth` |
| Renewal | Notable | `+0.30% HpRegen, +1 FlatHpRegen` |
| Barbed Blood | Notable | `+4 Thorns, +10 BonusHealth` |
| Natural Plate | Notable | `+5 Armor, +1% HealthPercent` |
| Last Supper | Notable | `+2 VIT, +0.2% HpRegen, +8 BonusHealth` |
| Second Heart | Keystone | Once every `45s`, dropping below `35% HP` grants regeneration equal to `8%` of max HP over `4s`. While active, `DamagePercent -12%`. |

## 6.3 Precision

Precision is the PRE region. It supports crit chance, crit damage, attack speed, and cast speed.

| Node | Type | Effect |
|---|---|---|
| Keen Eye | Small | `+1 PRE` |
| Sure Hand | Small | `+1 PRE` |
| Hunter's Focus | Small | `+1 PRE` |
| Fine Control | Small | `+1 PRE` |
| Edge Alignment I | Small | `+2% CritChance` |
| Edge Alignment II | Small | `+2% CritChance` |
| Steady Finger I | Small | `+0.04x CritDamage` |
| Quick Release I | Small | `+2% AttackSpeed` |
| Rapid Casting I | Small | `+2% CastTimeReduction` |
| Open Vein | Small | `+2 Penetration` |
| Measured Aim | Small | `+1% CritChance` |
| Quick Release II | Small | `+2% AttackSpeed` |
| Steady Finger II | Small | `+0.04x CritDamage` |
| Surgical Habit | Small | `+2% CastTimeReduction` |
| Dead Calm | Notable | `+2 PRE, +4% CritChance` |
| Razor Thought | Notable | `+0.08x CritDamage, +3% CastTimeReduction` |
| Reflex Arc | Notable | `+4% AttackSpeed, +2% CritChance` |
| Thread the Gap | Notable | `+5 Penetration, +2% CritChance` |
| Clean Execution | Notable | `+2 PRE, +0.05x CritDamage, +2% AttackSpeed` |
| Perfect Form | Keystone | If you have not moved for `1.5s`, gain `+12% CritChance` and `+0.10x CritDamage`. Moving suppresses the effect for `2s`. |

## 6.4 Attunement

Attunement is the MAG region. It supports skill damage, AoE growth, healing throughput, and caster resource depth.

| Node | Type | Effect |
|---|---|---|
| Attuned Spark | Small | `+1 MAG` |
| Scholar's Reach | Small | `+1 MAG` |
| Aether Sense | Small | `+1 MAG` |
| Mystic Nerve | Small | `+1 MAG` |
| Spell Weave I | Small | `+2% SkillDamage` |
| Spell Weave II | Small | `+2% SkillDamage` |
| Broad Glyph I | Small | `+3% AoESize` |
| Blessed Practice | Small | `+4 HealingPower` |
| Resonant Mind | Small | `+2% DamagePercent` |
| Broad Glyph II | Small | `+3% AoESize` |
| Soothing Current | Small | `+3% HealingPercent` |
| Spell Weave III | Small | `+3% SkillDamage` |
| Focused Aether | Small | `+5 Aether` |
| Gentle Current | Small | `+4 LifeEnergy` |
| High Casting | Notable | `+2 MAG, +4% SkillDamage` |
| Grand Pattern | Notable | `+6% AoESize, +3% DamagePercent` |
| Deep Reservoir | Notable | `+2 MAG, +10 Aether` |
| Merciful Current | Notable | `+8 HealingPower, +5% HealingPercent` |
| Unbound Formula | Notable | `+5% SkillDamage, +4% AoESize` |
| Arc Saturation | Keystone | Skills that hit `4+` targets gain `+12% SkillDamage` and `+15% AoESize`. Primary attacks deal `-10%` damage. |

## 6.5 Resolve

Resolve is the RSV region. It governs CDR, status resistance, composure, and tempo control.

| Node | Type | Effect |
|---|---|---|
| Inner Will | Small | `+1 RSV` |
| Quiet Mind | Small | `+1 RSV` |
| Hardened Nerves | Small | `+1 RSV` |
| Cold Focus | Small | `+1 RSV` |
| Efficient Cycle I | Small | `+1% CooldownReduction` |
| Efficient Cycle II | Small | `+1% CooldownReduction` |
| Resistance Drill I | Small | `+3% StatusResistance` |
| Swift Recovery I | Small | `+2% CastTimeReduction` |
| Efficient Cycle III | Small | `+1.5% CooldownReduction` |
| Resistance Drill II | Small | `+3% StatusResistance` |
| Swift Recovery II | Small | `+2% CastTimeReduction` |
| Ordered Motion I | Small | `+2% MovementSpeed` |
| Ordered Motion II | Small | `+2% MovementSpeed` |
| Guarded Breathing | Small | `+1% DamageReduction` |
| Tempered Will | Notable | `+2 RSV, +3% StatusResistance` |
| Battle Composure | Notable | `+4% CooldownReduction, +3% CastTimeReduction` |
| Enduring Plan | Notable | `+2 RSV, +1% DamageReduction, +2% MovementSpeed` |
| Reserve Discipline | Notable | `+2 RSV, +8% StatusResistance` |
| Quiet Machine | Notable | `+2 RSV, +2% CooldownReduction, +2% CastTimeReduction` |
| Calm Under Fire | Keystone | While above `80% HP`, gain `+6% CDR` and `+10% StatusResistance`. While below `40% HP`, `AttackSpeed -8%` and `DamageReduction +8%`. |

## 6.6 Juggernaut

Juggernaut is the MIG/VIT hybrid sector. It is the frontline route for Aegis and aggressive bruiser builds.

| Node | Type | Effect |
|---|---|---|
| Stone Shoulders | Small | `+1 MIG, +6 BonusHealth` |
| Iron Lungs | Small | `+1 VIT, +2 Armor` |
| Frontline Weight | Small | `+1 MIG, +1% HealthPercent` |
| Holding Ground | Small | `+1 VIT, +2 Armor` |
| Plated Step I | Small | `+3 Armor` |
| Plated Step II | Small | `+3 Armor` |
| Thickened Guard I | Small | `+1% DamageReduction` |
| Thickened Guard II | Small | `+1% DamageReduction` |
| Barbed Plates | Small | `+3 Thorns` |
| Taunting Frame | Small | `+10% TauntDuration` |
| War Endurance | Small | `+12 BonusHealth` |
| Battle Cushion | Small | `+0.15% HpRegen` |
| Held Line | Small | `+3 Armor, +8 BonusHealth` |
| Grit Before Glory | Small | `+1% DamageReduction, +2 Thorns` |
| Iron Bastion | Notable | `+2 MIG, +2 VIT, +5 Armor` |
| Anchored Guard | Notable | `+3% DamageReduction, +15 BonusHealth` |
| Pain Returned | Notable | `+6 Thorns, +3 Armor` |
| Provoker | Notable | `+20% TauntDuration, +1% DamageReduction` |
| Rampart Soul | Notable | `+2 MIG, +2 VIT, +0.2% HpRegen` |
| Unyielding Advance | Keystone | Gain `+1% DamageReduction` for each enemy within `10` studs, up to `10%`. `MovementSpeed -8%`. |

## 6.7 Predator

Predator is the PRE/MIG hybrid sector. It turns precision into chase pressure, penetration, and finishing power.

| Node | Type | Effect |
|---|---|---|
| Hunter's Muscle | Small | `+1 MIG` |
| Killer's Eye | Small | `+1 PRE` |
| Chase Instinct | Small | `+1 MIG` |
| Snap Judgment | Small | `+1 PRE` |
| Fast Draw I | Small | `+2% AttackSpeed` |
| Rending Point I | Small | `+3 Penetration` |
| Blood Taste I | Small | `+0.5% Lifesteal` |
| Open Ground I | Small | `+2% MovementSpeed` |
| Fast Draw II | Small | `+2% AttackSpeed` |
| Mark Weakness | Small | `+2% CritChance` |
| Rending Point II | Small | `+3 Penetration` |
| Blood Taste II | Small | `+0.5% Lifesteal` |
| Open Ground II | Small | `+2% MovementSpeed` |
| Killer's Reserve | Small | `+8 KillerInstinct` |
| Apex Hunter | Notable | `+2 PRE, +2 MIG, +4% AttackSpeed` |
| Fresh Trail | Notable | `+4% MovementSpeed, +1% Lifesteal` |
| Heartseeker | Notable | `+4% CritChance, +5 Penetration` |
| Feeding Frenzy | Notable | `+2 MIG, +2 PRE, +10 KillerInstinct` |
| Pursuit Doctrine | Notable | `+2% AttackSpeed, +2% MovementSpeed, +2 Penetration` |
| Cull the Weak | Keystone | Hits against enemies below `25% HP` gain `+15% DamagePercent` and `+2% Lifesteal`. Hits against full-life enemies deal `-5%` damage. |

## 6.8 Oracle

Oracle is the MAG/PRE hybrid sector. It is the spell-crit and heal-crit bridge for Arcanist and LifeSteward builds.

| Node | Type | Effect |
|---|---|---|
| Keen Attunement | Small | `+1 MAG` |
| Pattern Sight | Small | `+1 PRE` |
| Luminous Thought | Small | `+1 MAG` |
| Exacting Ritual | Small | `+1 PRE` |
| Arcanic Aim I | Small | `+2% CritChance` |
| Bright Scalpel I | Small | `+0.04x CritDamage` |
| Soothing Formula I | Small | `+4 HealingPower` |
| Swift Chant I | Small | `+2% CastTimeReduction` |
| Blessed Focus | Small | `+3% HealingPercent` |
| Arcanic Aim II | Small | `+2% CritChance` |
| Bright Scalpel II | Small | `+0.04x CritDamage` |
| Soothing Formula II | Small | `+4 HealingPower` |
| Swift Chant II | Small | `+2% CastTimeReduction` |
| Living Current | Small | `+8 LifeEnergy` |
| Seer's Mercy | Notable | `+2 MAG, +2 PRE, +5% HealingPercent` |
| Surgical Light | Notable | `+4% CritChance, +0.06x CritDamage` |
| Diviner's Pulse | Notable | `+8 HealingPower, +2% CastTimeReduction` |
| Brilliant Recovery | Notable | `+2 PRE, +2 MAG, +10 LifeEnergy` |
| High Invocation | Notable | `+4% HealingPercent, +4% SkillDamage` |
| Clarity Surge | Keystone | Critical heals restore `8 LifeEnergy`. Critical skill hits restore `4 Aether`. Your `Lifesteal` is set to `0` while active. |

## 6.9 Spellblade

Spellblade is the RSV/MAG hybrid sector. It supports rotation smoothness, hybrid cadence, and broad caster rhythm.

| Node | Type | Effect |
|---|---|---|
| Arc Reserve | Small | `+1 MAG` |
| Focus Reserve | Small | `+1 RSV` |
| Mystic Cadence | Small | `+1 MAG` |
| Ordered Casting | Small | `+1 RSV` |
| Spellclock I | Small | `+1.5% CooldownReduction` |
| Spellclock II | Small | `+1.5% CooldownReduction` |
| Sigil Radius | Small | `+3% AoESize` |
| Charged Formula I | Small | `+2% SkillDamage` |
| Focused Channel I | Small | `+2% CastTimeReduction` |
| Reservoir I | Small | `+8 Aether` |
| Charged Formula II | Small | `+2% SkillDamage` |
| Resonant Radius | Small | `+3% AoESize` |
| Focused Channel II | Small | `+2% CastTimeReduction` |
| Reservoir II | Small | `+8 Aether` |
| Stable Rotation | Notable | `+2 RSV, +2 MAG, +3% CooldownReduction` |
| Wide Cast | Notable | `+6% AoESize, +4% SkillDamage` |
| Spell Reservoir | Notable | `+2 MAG, +12 Aether, +2% SkillDamage` |
| Quickened Circuit | Notable | `+2 RSV, +4% CastTimeReduction` |
| Arc Engine | Notable | `+2 RSV, +2 MAG, +3% SkillDamage, +2% CDR` |
| Spell Rhythm | Keystone | Casting a skill grants 1 Rhythm for `5s`. Basic attacks consume Rhythm to gain `+8% AttackSpeed` and `+8% SkillDamage` on your next attack or skill. Max `3` stacks. |

## 6.10 Sanctuary

Sanctuary is the VIT/RSV support-utility sector. It is the bridge into sustain, party utility, and economy play.

| Node | Type | Effect |
|---|---|---|
| Gentle Step I | Small | `+2% MovementSpeed` |
| Humble Learning I | Small | `+2% XPBonus` |
| Full Pouch I | Small | `+3% MeritBonus` |
| Kind Touch I | Small | `+3 HealingPower` |
| Shared Breath I | Small | `+0.15% HpRegen` |
| Gentle Step II | Small | `+2% MovementSpeed` |
| Humble Learning II | Small | `+2% XPBonus` |
| Full Pouch II | Small | `+3% MeritBonus` |
| Kind Touch II | Small | `+3 HealingPower` |
| Shared Breath II | Small | `+0.15% HpRegen` |
| Warmth | Small | `+2% HealingPercent` |
| Life Reservoir | Small | `+8 LifeEnergy` |
| Field Dressing | Small | `+1 FlatHpRegen` |
| Pilgrim's Pace | Small | `+2% MovementSpeed` |
| Caretaker | Notable | `+6 HealingPower, +4% HealingPercent` |
| Trailblazer | Notable | `+5% MovementSpeed, +0.2% HpRegen` |
| Learned Hands | Notable | `+5% XPBonus, +5% MeritBonus` |
| Wellspring | Notable | `+2% HealingPercent, +10 LifeEnergy, +1 FlatHpRegen` |
| Fellowship | Notable | `+4% MovementSpeed, +3% XPBonus, +4% MeritBonus` |
| Patron Saint | Keystone | Nearby party members gain `50%` of your `HealingPower`, `HealingPercent`, `XPBonus`, and `MeritBonus` from talents. Your own `DamagePercent -10%`. |

## 6.11 Bulwark

Bulwark is the outer Juggernaut mastery branch. It is deliberately deep, narrow, and heavily Aegis-leaning.

| Node | Type | Effect |
|---|---|---|
| Guard Oath I | Small | `+3 Armor` |
| Guard Oath II | Small | `+3 Armor` |
| Veteran Plate I | Small | `+1% DamageReduction` |
| Thick Shielding I | Small | `+12 BonusHealth` |
| Resolute Body I | Small | `+6 Determination` |
| Hooked Plate I | Small | `+3 Thorns` |
| Guarded Posture I | Small | `+10% TauntDuration` |
| Bastion Breath | Small | `+0.15% HpRegen` |
| Veteran Plate II | Small | `+1% DamageReduction` |
| Thick Shielding II | Small | `+12 BonusHealth` |
| Resolute Body II | Small | `+6 Determination` |
| Hooked Plate II | Small | `+3 Thorns` |
| Guarded Posture II | Small | `+10% TauntDuration` |
| Adamant Frame | Small | `+1% HealthPercent` |
| Shield Eater | Notable | `+5 Armor, +1% DamageReduction` |
| Defender's Rule | Notable | `+15% TauntDuration, +10 Determination` |
| Grudgeborn | Notable | `+6 Thorns, +12 BonusHealth` |
| Adamant Oath | Notable | `+2% HealthPercent, +0.2% HpRegen` |
| Thickest Wall | Notable | `+6 Armor, +15 BonusHealth, +1% DamageReduction` |
| Last Bastion | Keystone | While `Determination > 70%`, gain `+8% DamageReduction` and `+20% TauntDuration`. While `Determination < 20%`, `MovementSpeed -10%`. |

## 6.12 Huntmaster

Huntmaster is the outer Predator mastery branch. It is the dedicated Hunter finisher lane.

| Node | Type | Effect |
|---|---|---|
| Blood Mark I | Small | `+2% CritChance` |
| Blood Mark II | Small | `+2% CritChance` |
| Quick Feet I | Small | `+2% MovementSpeed` |
| Killer's Wheel I | Small | `+2% AttackSpeed` |
| Open Rib I | Small | `+3 Penetration` |
| Instinct Reserve I | Small | `+8 KillerInstinct` |
| Quick Feet II | Small | `+2% MovementSpeed` |
| Killer's Wheel II | Small | `+2% AttackSpeed` |
| Open Rib II | Small | `+3 Penetration` |
| Instinct Reserve II | Small | `+8 KillerInstinct` |
| Sharp Intent I | Small | `+0.04x CritDamage` |
| Sharp Intent II | Small | `+0.04x CritDamage` |
| Sightline | Small | `+1 PRE` |
| Draw Weight | Small | `+1 MIG` |
| First Blood | Notable | `+4% CritChance, +4 Penetration` |
| Running Kill | Notable | `+4% MovementSpeed, +3% AttackSpeed` |
| Cold Magazine | Notable | `+12 KillerInstinct, +0.05x CritDamage` |
| Long Pursuit | Notable | `+1 PRE, +1 MIG, +3% MovementSpeed` |
| Merciless Trail | Notable | `+5 Penetration, +2% CritChance, +2% AttackSpeed` |
| Relentless Quarry | Keystone | Damaging the same enemy `4` times within `3s` marks it for `6s`: you gain `+10% CritChance` and `+10 Penetration` against that target. Hitting a different target removes the mark. |

## 6.13 Grace

Grace is the outer Oracle mastery branch. It is the most specialized healer/support lane.

| Node | Type | Effect |
|---|---|---|
| Soft Light I | Small | `+4 HealingPower` |
| Soft Light II | Small | `+4 HealingPower` |
| Open Palms I | Small | `+3% HealingPercent` |
| Swift Prayer I | Small | `+2% CastTimeReduction` |
| Living Wells I | Small | `+8 LifeEnergy` |
| Comforting Presence I | Small | `+0.15% HpRegen` |
| Open Palms II | Small | `+3% HealingPercent` |
| Swift Prayer II | Small | `+2% CastTimeReduction` |
| Living Wells II | Small | `+8 LifeEnergy` |
| Comforting Presence II | Small | `+0.15% HpRegen` |
| Clear Vision I | Small | `+1 MAG` |
| Clear Vision II | Small | `+1 PRE` |
| Sanctuary Step | Small | `+2% MovementSpeed` |
| Breath Returned | Small | `+1 FlatHpRegen` |
| Merciful Timing | Notable | `+6 HealingPower, +4% CastTimeReduction` |
| Overflowing Grace | Notable | `+5% HealingPercent, +10 LifeEnergy` |
| Walking Chapel | Notable | `+4% MovementSpeed, +0.2% HpRegen` |
| Restoration Theory | Notable | `+1 MAG, +1 PRE, +5 HealingPower` |
| Kindled Hope | Notable | `+1 FlatHpRegen, +3% HealingPercent, +6 LifeEnergy` |
| Shared Grace | Keystone | Overhealing a target grants them `20%` of the excess as a `4s` heal-over-time effect. Your `Lifesteal` is reduced by `50%`. |

## 6.14 Stormweave

Stormweave is the outer Spellblade mastery branch. It offers the deepest Arcanist-focused scaling and target-profile flexibility.

| Node | Type | Effect |
|---|---|---|
| Aether Loom I | Small | `+8 Aether` |
| Aether Loom II | Small | `+8 Aether` |
| Wide Spiral I | Small | `+4% AoESize` |
| Wild Formula I | Small | `+3% SkillDamage` |
| Quick Sigils I | Small | `+2% CastTimeReduction` |
| Charged Reserve I | Small | `+1% CooldownReduction` |
| Wide Spiral II | Small | `+4% AoESize` |
| Wild Formula II | Small | `+3% SkillDamage` |
| Quick Sigils II | Small | `+2% CastTimeReduction` |
| Charged Reserve II | Small | `+1% CooldownReduction` |
| Spell Battery I | Small | `+2% DamagePercent` |
| Spell Battery II | Small | `+2% DamagePercent` |
| Crackling Intellect | Small | `+1 MAG` |
| Measured Surge | Small | `+1 RSV` |
| Spellwake | Notable | `+5% SkillDamage, +5% AoESize` |
| Burning Diagram | Notable | `+4% DamagePercent, +3% CastTimeReduction` |
| Overfull Vessel | Notable | `+14 Aether, +2% CDR` |
| Master Conduit | Notable | `+1 MAG, +1 RSV, +4% SkillDamage` |
| Echo Chamber | Notable | `+6% AoESize, +2% DamagePercent` |
| Eye of the Storm | Keystone | If a skill hits only `1` target, it deals `+18%` damage. If it hits `4+` targets, it gains `+20% AoESize`. Resource consumption `+10%`. |

## 6.15 Fortune

Fortune is the outer Sanctuary mastery branch. It contains the deepest economy bonuses and a small amount of safety so it can support progression-oriented players.

| Node | Type | Effect |
|---|---|---|
| Lucky Coin I | Small | `+3% MeritBonus` |
| Lucky Coin II | Small | `+3% MeritBonus` |
| Eager Mind I | Small | `+2% XPBonus` |
| Traveler's Pace I | Small | `+2% MovementSpeed` |
| Field Lessons I | Small | `+1 FlatHpRegen` |
| Small Harvest I | Small | `+0.5% Lifesteal` |
| Eager Mind II | Small | `+2% XPBonus` |
| Traveler's Pace II | Small | `+2% MovementSpeed` |
| Field Lessons II | Small | `+1 FlatHpRegen` |
| Small Harvest II | Small | `+0.5% Lifesteal` |
| Safe Route I | Small | `+1% DamageReduction` |
| Safe Route II | Small | `+1% DamageReduction` |
| Learned Route | Small | `+1 RSV` |
| Patient Work | Small | `+1 VIT` |
| Packed Caravan | Notable | `+5% MeritBonus, +3% XPBonus` |
| Road Wisdom | Notable | `+4% MovementSpeed, +1 FlatHpRegen` |
| Lasting Effort | Notable | `+1 VIT, +1 RSV, +0.5% Lifesteal` |
| Veteran Trader | Notable | `+6% MeritBonus, +2% XPBonus` |
| Untaxed Breath | Notable | `+2% MovementSpeed, +1% DamageReduction, +1 FlatHpRegen` |
| Fortune Favors | Keystone | You and nearby party members gain `50%` of your `XPBonus` and `MeritBonus` from talents. Your own `DamagePercent` and `SkillDamage` are each reduced by `6%`. |

## 7. Recommended Visual Layout

### Center

1. Origin in the middle.
2. Five primary spokes radiating outward.

### Ring 1

1. Warpath at upper-left.
2. Lifeblood at upper-mid.
3. Precision at upper-right.
4. Attunement at lower-right.
5. Resolve at lower-left.

### Ring 2

1. Juggernaut between Warpath and Lifeblood.
2. Predator between Warpath and Precision.
3. Oracle between Precision and Attunement.
4. Spellblade between Attunement and Resolve.
5. Sanctuary between Resolve and Lifeblood.

### Ring 3

1. Bulwark extends beyond Juggernaut.
2. Huntmaster extends beyond Predator.
3. Grace extends beyond Oracle.
4. Stormweave extends beyond Spellblade.
5. Fortune extends beyond Sanctuary.

This gives you a tree that visually reads well, supports the current pan-based UI model, and is still much easier to browse than a fully organic PoE web.

## 8. Implementation Notes Against Current Repo

### Talent Config

The current shared tree config is data-driven already, which is good. This proposal is compatible with that approach, but the node count jumps from `13` live nodes to `301` total nodes.

### Talent Effects

Your current aggregator already sums flat stats and stores boolean rule toggles. That is enough for this proposal if you add primary-stat support.

### UI

The current tree UI supports panning, node sizes by type, and static edge rendering. For a 301-node board, I would strongly recommend these additions before implementation.

1. Zoom levels.
2. Sector labels.
3. Search or filter by stat tag.
4. Mini-map or overview.
5. Tooltip comparison showing current total for the stat.

### Gear Rating

The current power formula assumes a talent tree max weight of `56`, based on `32` small, `4` notable, and `4` keystone nodes. That no longer fits.

Recommended update:

1. Set the new theoretical weight to `420` if you want full-tree normalization.
2. Better option: normalize by expected endgame spend rather than total tree size, so talent score reflects build completion, not board size.

Suggested replacement:

```text
T = clamp01(weightedTalents / 199)
```

That makes the rating follow actual attainable spend at level cap.

## 9. Why This Tree Fits The Current Game

1. It is built directly around MIG, VIT, PRE, MAG, and RSV, which are already your game's core identity system.
2. It respects the current caps on crit, DR, CDR, attack speed, and lifesteal.
3. It preserves your current idea that talents are persistent, server-authoritative, and data-driven.
4. It keeps support and economy nodes in the tree, but moves them far enough out that they are optional, not mandatory.
5. It gives every class at least three distinct endgame pathing identities.

## 10. Suggested Next Pass After Approval

If you approve this direction, the clean implementation sequence is:

1. Expand the config format to support primary-stat nodes.
2. Replace the current tiny cross-tree with the 15-sector board.
3. Add rule handlers for the 15 keystones.
4. Update UI with zoom and sector labels.
5. Re-normalize talent contribution in the gear rating formula.
6. Run a balance sweep around level `50`, `100`, `150`, and `200` checkpoints.
