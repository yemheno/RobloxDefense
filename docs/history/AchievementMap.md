# Achievement System Map

**25 achievements · 10 tiers each · 250 total tiers**

All achievements use the same unlock format: reaching a threshold triggers the tier, grants rewards, and fires a client notification. No hard cap — grinding beyond tier 10 is allowed but gives no additional achievement rewards.

---

## Economy reference (reward calibration)

| Anchor | Value |
|--------|-------|
| Essence purchase | 99 Robux = 50 Essence |
| Weapon tier ladder I → XII | ~1,650 Essence total |
| Respec cost | 25–40 Essence |
| Daily login reward | 2–10 Essence/day; day 30 = 100 Essence |
| 30-wave run yield | ~5,000–6,000 Merits |
| Old achievement lifetime cap | ~100K Merits + 500–600 Essence + 2 Respecs |

**Reward bands (tier 10 cap)**

| Band | Merits | Essence | Respecs | Used by |
|------|--------|---------|---------|---------|
| Standard | 100–125K | 100–125 | 1 | kills, crits, damage, combo, hits, thick_skin, battle_hardened |
| Elevated | 200–250K | 175–200 | 2 | miniboss/boss, waves, life_giver, revivalist, arms_master, talent_seeker |
| Premium | 300–400K | 275–350 | 3 | Boss medals |
| Mastery | 350–500K | 325–400 | 3 | Cap mastery |

Cross-reward rule: `merit_earner` gives Essence only; `essence_hoarder` gives Merits only (no compounding feedback loop).

---

## Categories at a glance

| Category   | Count | Description |
|------------|-------|-------------|
| Combat     | 6     | General killing, damage, crits, combos |
| Survival   | 3     | Waves, high-wave runs, damage absorbed |
| Healer     | 2     | Healing done, revives performed |
| Collection | 2     | Merits earned, Essence earned |
| Dedication | 1     | Hits received |
| Weapon     | 2     | Weapon level, talent nodes allocated |
| Medals     | 4     | Per-boss Pokémon-style sigils |
| Mastery    | 4     | Kill each boss at/below its level bracket |

---

## COMBAT

### 1. Slayer `kills`
Kill enemies. · stat: `totalKills`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 50        | 25 M |
| 2  | 250       | 75 M |
| 3  | 1,000     | 200 M |
| 4  | 4,000     | 600 M + 2 E |
| 5  | 12,000    | 2,000 M + 5 E |
| 6  | 35,000    | 6,000 M + 10 E |
| 7  | 100,000   | 15,000 M + 20 E |
| 8  | 275,000   | 35,000 M + 40 E |
| 9  | 700,000   | 75,000 M + 75 E + 1 R |
| 10 | 2,000,000 | 125,000 M + 125 E + 1 R |

### 2. Elite Hunter `miniboss_slayer`
Kill miniboss enemies. · statFn: `killsByTier.miniboss`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 5      | 50 M |
| 2  | 25     | 150 M |
| 3  | 75     | 450 M |
| 4  | 200    | 1,200 M + 3 E |
| 5  | 500    | 3,000 M + 8 E |
| 6  | 1,200  | 8,000 M + 18 E |
| 7  | 3,000  | 20,000 M + 35 E |
| 8  | 7,000  | 50,000 M + 70 E |
| 9  | 15,000 | 110,000 M + 125 E + 1 R |
| 10 | 35,000 | 200,000 M + 175 E + 2 R |

### 3. Boss Breaker `boss_slayer`
Kill boss enemies. · statFn: `killsByTier.boss`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 1     | 100 M |
| 2  | 5     | 350 M |
| 3  | 15    | 1,000 M |
| 4  | 40    | 3,000 M + 5 E |
| 5  | 100   | 8,000 M + 15 E |
| 6  | 250   | 20,000 M + 30 E |
| 7  | 600   | 50,000 M + 60 E |
| 8  | 1,500 | 100,000 M + 100 E |
| 9  | 3,500 | 175,000 M + 150 E + 1 R |
| 10 | 8,000 | 250,000 M + 200 E + 2 R |

### 4. Precision `critical_striker`
Land critical hits. · stat: `criticalHits`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 25      | 20 M |
| 2  | 150     | 60 M |
| 3  | 600     | 175 M |
| 4  | 2,000   | 500 M + 1 E |
| 5  | 6,000   | 1,500 M + 4 E |
| 6  | 18,000  | 4,500 M + 8 E |
| 7  | 50,000  | 12,000 M + 16 E |
| 8  | 130,000 | 30,000 M + 35 E |
| 9  | 320,000 | 65,000 M + 65 E + 1 R |
| 10 | 800,000 | 125,000 M + 115 E + 1 R |

### 5. Destroyer `destroyer`
Deal total damage. · stat: `totalDamageDealt`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 5,000       | 20 M |
| 2  | 30,000      | 60 M |
| 3  | 150,000     | 175 M |
| 4  | 600,000     | 500 M + 1 E |
| 5  | 2,000,000   | 1,500 M + 4 E |
| 6  | 7,000,000   | 4,500 M + 8 E |
| 7  | 25,000,000  | 12,000 M + 16 E |
| 8  | 80,000,000  | 30,000 M + 35 E |
| 9  | 250,000,000 | 65,000 M + 65 E + 1 R |
| 10 | 1B          | 125,000 M + 115 E + 1 R |

### 6. Combo King `combo_king`
Reach a high hit combo (best single-run combo). · stat: `bestCombo`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 10  | 25 M |
| 2  | 25  | 75 M |
| 3  | 50  | 200 M |
| 4  | 100 | 600 M + 2 E |
| 5  | 150 | 1,800 M + 5 E |
| 6  | 200 | 5,000 M + 10 E |
| 7  | 250 | 12,000 M + 18 E |
| 8  | 300 | 28,000 M + 32 E |
| 9  | 400 | 60,000 M + 60 E + 1 R |
| 10 | 500 | 125,000 M + 100 E + 1 R |

---

## SURVIVAL

### 7. Survivor `survivor`
Complete waves. · stat: `wavesSurvived`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 10     | 30 M |
| 2  | 50     | 100 M |
| 3  | 150    | 300 M |
| 4  | 400    | 800 M + 2 E |
| 5  | 900    | 2,500 M + 6 E |
| 6  | 2,000  | 7,000 M + 14 E |
| 7  | 5,000  | 18,000 M + 28 E |
| 8  | 12,000 | 45,000 M + 55 E |
| 9  | 30,000 | 100,000 M + 100 E + 1 R |
| 10 | 75,000 | 200,000 M + 175 E + 2 R |

### 8. Wave Master `wave_master`
Reach a high wave in a single run. · stat: `highestWave`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 10  | 50 M |
| 2  | 25  | 200 M |
| 3  | 50  | 600 M |
| 4  | 75  | 1,500 M + 4 E |
| 5  | 100 | 4,000 M + 10 E |
| 6  | 125 | 10,000 M + 22 E |
| 7  | 150 | 25,000 M + 45 E |
| 8  | 175 | 60,000 M + 85 E |
| 9  | 200 | 130,000 M + 145 E + 1 R |
| 10 | 250 | 250,000 M + 200 E + 2 R |

### 9. Thick Skin `thick_skin`
Absorb total damage. · stat: `totalDamageTaken`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 2,500       | 20 M |
| 2  | 15,000      | 60 M |
| 3  | 75,000      | 175 M |
| 4  | 300,000     | 500 M + 1 E |
| 5  | 1,000,000   | 1,500 M + 3 E |
| 6  | 4,000,000   | 4,000 M + 7 E |
| 7  | 15,000,000  | 10,000 M + 14 E |
| 8  | 50,000,000  | 25,000 M + 28 E |
| 9  | 150,000,000 | 55,000 M + 55 E + 1 R |
| 10 | 500,000,000 | 100,000 M + 100 E + 1 R |

---

## HEALER

### 10. Life Giver `life_giver`
Heal allies (actual HP healed, no overheal). · stat: `healingDone`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 1,000       | 50 M |
| 2  | 10,000      | 175 M |
| 3  | 50,000      | 500 M |
| 4  | 200,000     | 1,500 M + 4 E |
| 5  | 700,000     | 4,500 M + 10 E |
| 6  | 2,000,000   | 12,000 M + 22 E |
| 7  | 7,000,000   | 30,000 M + 45 E |
| 8  | 20,000,000  | 70,000 M + 85 E |
| 9  | 60,000,000  | 150,000 M + 145 E + 1 R |
| 10 | 200,000,000 | 250,000 M + 200 E + 2 R |

### 11. Revivalist `revivalist`
Revive fallen allies. · stat: `revivesDone`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 1     | 75 M |
| 2  | 5     | 250 M |
| 3  | 15    | 750 M |
| 4  | 35    | 2,000 M + 5 E |
| 5  | 75    | 6,000 M + 12 E |
| 6  | 150   | 15,000 M + 25 E |
| 7  | 300   | 40,000 M + 50 E |
| 8  | 600   | 90,000 M + 95 E |
| 9  | 1,200 | 170,000 M + 155 E + 1 R |
| 10 | 2,500 | 250,000 M + 200 E + 2 R |

---

## COLLECTION

### 12. Merit Earner `merit_earner`
Accumulate Merits (lifetime total). · stat: `meritsCollected`
**Rewards Essence only** — avoids feedback loop for Merit spenders.

| Tier | Threshold   | Rewards |
|------|-------------|---------|
| 1  | 5,000       | 2 E |
| 2  | 25,000      | 5 E |
| 3  | 100,000     | 10 E |
| 4  | 350,000     | 18 E |
| 5  | 1,000,000   | 30 E |
| 6  | 3,000,000   | 45 E |
| 7  | 8,000,000   | 65 E |
| 8  | 20,000,000  | 85 E + 1 R |
| 9  | 50,000,000  | 105 E + 1 R |
| 10 | 150,000,000 | 125 E + 2 R |

### 13. Essence Hoarder `essence_hoarder`
Accumulate Essence (lifetime total). · stat: `essenceEarned`
**Rewards Merits only** — avoids feedback loop for Essence earners.

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 50      | 150 M |
| 2  | 150     | 500 M |
| 3  | 400     | 1,500 M |
| 4  | 1,000   | 5,000 M |
| 5  | 2,500   | 15,000 M |
| 6  | 6,000   | 40,000 M |
| 7  | 15,000  | 90,000 M |
| 8  | 35,000  | 175,000 M |
| 9  | 80,000  | 300,000 M |
| 10 | 200,000 | 500,000 M |

---

## DEDICATION

### 14. Battle Hardened `battle_hardened`
Be struck by enemy attacks. · stat: `hitsReceived`

| Tier | Threshold  | Rewards |
|------|------------|---------|
| 1  | 250        | 15 M |
| 2  | 1,500      | 50 M |
| 3  | 7,000      | 150 M |
| 4  | 30,000     | 400 M + 1 E |
| 5  | 100,000    | 1,200 M + 3 E |
| 6  | 300,000    | 3,500 M + 6 E |
| 7  | 850,000    | 9,000 M + 12 E |
| 8  | 2,500,000  | 22,000 M + 25 E |
| 9  | 7,000,000  | 50,000 M + 50 E + 1 R |
| 10 | 20,000,000 | 100,000 M + 90 E + 1 R |

*(The Relentless `relentless` achievement for hitsDelivered is defined in the code under Combat as achievement #7 in the Lua table — same stat band as Slayer.)*

---

## WEAPON

### 15. Arms Master `arms_master`
Reach high weapon levels. · stat: `weaponLevelMax`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 4  | 200 M |
| 2  | 8  | 600 M |
| 3  | 12 | 1,500 M + 3 E |
| 4  | 16 | 4,000 M + 8 E |
| 5  | 20 | 10,000 M + 18 E |
| 6  | 24 | 22,000 M + 35 E |
| 7  | 28 | 50,000 M + 60 E |
| 8  | 32 | 100,000 M + 100 E |
| 9  | 36 | 175,000 M + 150 E + 1 R |
| 10 | 40 | 250,000 M + 200 E + 2 R |

### 16. Talent Seeker `talent_seeker`
Allocate talent nodes (cumulative lifetime count). · stat: `talentNodesAllocated`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 3   | 100 M |
| 2  | 8   | 350 M |
| 3  | 15  | 1,000 M + 2 E |
| 4  | 24  | 2,500 M + 5 E |
| 5  | 35  | 6,000 M + 12 E |
| 6  | 50  | 15,000 M + 25 E |
| 7  | 70  | 35,000 M + 50 E |
| 8  | 95  | 75,000 M + 85 E |
| 9  | 125 | 150,000 M + 135 E + 1 R |
| 10 | 160 | 250,000 M + 175 E + 2 R |

---

## MEDALS

Boss medals track total kills of a specific boss. Wire mob IDs in MobRegistry when bosses are added.

### 17. Iron Warden Medal `medal_iron_warden`
Defeat the Iron Warden (boss, ~lv50 content). · statFn: `killsByMobId["iron_warden"]`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 1   | 200 M |
| 2  | 3   | 600 M + 3 E |
| 3  | 7   | 1,800 M + 8 E |
| 4  | 15  | 5,000 M + 18 E |
| 5  | 30  | 12,000 M + 35 E |
| 6  | 60  | 28,000 M + 65 E |
| 7  | 110 | 65,000 M + 110 E |
| 8  | 185 | 130,000 M + 170 E + 1 R |
| 9  | 300 | 225,000 M + 230 E + 2 R |
| 10 | 500 | 300,000 M + 275 E + 3 R |

### 18. Void Harbinger Medal `medal_void_harbinger`
Defeat the Void Harbinger (boss, ~lv100 content). · statFn: `killsByMobId["void_harbinger"]`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 1   | 300 M |
| 2  | 3   | 900 M + 5 E |
| 3  | 7   | 2,500 M + 12 E |
| 4  | 15  | 7,000 M + 25 E |
| 5  | 30  | 17,000 M + 48 E |
| 6  | 55  | 40,000 M + 85 E |
| 7  | 100 | 85,000 M + 140 E |
| 8  | 175 | 170,000 M + 205 E + 1 R |
| 9  | 280 | 275,000 M + 265 E + 2 R |
| 10 | 450 | 350,000 M + 300 E + 3 R |

### 19. Pale Colossus Medal `medal_pale_colossus`
Defeat the Pale Colossus (boss, ~lv150 content). · statFn: `killsByMobId["pale_colossus"]`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 1   | 400 M |
| 2  | 3   | 1,200 M + 7 E |
| 3  | 6   | 3,500 M + 16 E |
| 4  | 12  | 9,000 M + 33 E |
| 5  | 25  | 22,000 M + 62 E |
| 6  | 50  | 52,000 M + 108 E |
| 7  | 90  | 110,000 M + 170 E |
| 8  | 155 | 210,000 M + 240 E + 1 R |
| 9  | 250 | 320,000 M + 300 E + 2 R |
| 10 | 400 | 375,000 M + 325 E + 3 R |

### 20. Abyssal Sovereign Medal `medal_abyssal_sovereign`
Defeat the Abyssal Sovereign (boss, ~lv200 content). · statFn: `killsByMobId["abyssal_sovereign"]`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 1   | 500 M |
| 2  | 3   | 1,500 M + 9 E |
| 3  | 6   | 4,500 M + 20 E |
| 4  | 12  | 12,000 M + 42 E |
| 5  | 24  | 28,000 M + 78 E |
| 6  | 45  | 65,000 M + 130 E |
| 7  | 80  | 135,000 M + 200 E |
| 8  | 135 | 250,000 M + 275 E + 1 R |
| 9  | 220 | 360,000 M + 330 E + 2 R |
| 10 | 350 | 400,000 M + 350 E + 3 R |

---

## MASTERY

Cap mastery achievements increment only when the boss is killed while the player is **at or below** the level cap. This is gated server-side in `AchievementManager.OnKill` via `CapMasteryMap`.

### 21. Iron Devotee `mastery_cap50`
Kill iron_warden at level ≤ 50. · statFn: `capMasteryKills.cap50`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 1   | 500 M |
| 2  | 3   | 2,000 M + 8 E |
| 3  | 7   | 6,000 M + 20 E |
| 4  | 15  | 15,000 M + 42 E |
| 5  | 30  | 35,000 M + 80 E |
| 6  | 60  | 75,000 M + 135 E |
| 7  | 110 | 150,000 M + 200 E |
| 8  | 185 | 250,000 M + 265 E + 1 R |
| 9  | 300 | 310,000 M + 305 E + 2 R |
| 10 | 500 | 350,000 M + 325 E + 3 R |

### 22. Void Devotee `mastery_cap100`
Kill void_harbinger at level ≤ 100. · statFn: `capMasteryKills.cap100`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 1   | 700 M |
| 2  | 3   | 2,500 M + 10 E |
| 3  | 7   | 7,500 M + 26 E |
| 4  | 15  | 20,000 M + 55 E |
| 5  | 30  | 45,000 M + 100 E |
| 6  | 55  | 95,000 M + 165 E |
| 7  | 100 | 185,000 M + 235 E |
| 8  | 175 | 285,000 M + 295 E + 1 R |
| 9  | 280 | 360,000 M + 345 E + 2 R |
| 10 | 450 | 400,000 M + 365 E + 3 R |

### 23. Colossus Devotee `mastery_cap150`
Kill pale_colossus at level ≤ 150. · statFn: `capMasteryKills.cap150`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 1   | 900 M |
| 2  | 3   | 3,000 M + 13 E |
| 3  | 6   | 9,000 M + 33 E |
| 4  | 12  | 24,000 M + 68 E |
| 5  | 25  | 55,000 M + 120 E |
| 6  | 50  | 115,000 M + 195 E |
| 7  | 90  | 220,000 M + 265 E |
| 8  | 155 | 325,000 M + 320 E + 1 R |
| 9  | 250 | 400,000 M + 368 E + 2 R |
| 10 | 400 | 450,000 M + 390 E + 3 R |

### 24. Sovereign Devotee `mastery_cap200`
Kill abyssal_sovereign at level ≤ 200. · statFn: `capMasteryKills.cap200`

| Tier | Threshold | Rewards |
|------|-----------|---------|
| 1  | 1   | 1,200 M |
| 2  | 3   | 4,000 M + 16 E |
| 3  | 6   | 12,000 M + 40 E |
| 4  | 12  | 30,000 M + 82 E |
| 5  | 24  | 70,000 M + 145 E |
| 6  | 45  | 145,000 M + 225 E |
| 7  | 80  | 265,000 M + 300 E |
| 8  | 135 | 375,000 M + 355 E + 1 R |
| 9  | 220 | 450,000 M + 390 E + 2 R |
| 10 | 350 | 500,000 M + 400 E + 3 R |

---

## New stats added to PlayerData

These fields are added to `data.Account` by `AchievementManager.DefaultStats()` / `MergeDefaults()`:

| Stat field | Type | Description |
|------------|------|-------------|
| `totalKills` | number | Total enemies killed |
| `killsByMobId` | table | `{ [mobId] = count }` |
| `killsByTier` | table | `{ normal, miniboss, boss }` |
| `hitsDelivered` | number | Total hits landed |
| `hitsReceived` | number | Total times hit |
| `totalDamageDealt` | number | Cumulative damage dealt |
| `totalDamageTaken` | number | Cumulative damage absorbed |
| `criticalHits` | number | Total crits landed |
| `bestCombo` | number | Best combo ever achieved |
| `wavesSurvived` | number | Total waves completed |
| `highestWave` | number | Single-run peak wave |
| `healingDone` | number | Total HP healed to allies |
| `revivesDone` | number | Total revives performed |
| `meritsCollected` | number | Lifetime Merits earned |
| `essenceEarned` | number | Lifetime Essence earned |
| `weaponLevelMax` | number | Highest weapon level ever reached |
| `talentNodesAllocated` | number | Cumulative nodes allocated (not decremented on respec) |
| `capMasteryKills` | table | `{ cap50, cap100, cap150, cap200 }` |

---

## Files modified

| File | Change |
|------|--------|
| `ReplicatedStorage/Shared/AchievementConfig.lua` | Full rewrite — 25 achievements × 10 tiers, CapMasteryMap, FormatNumber |
| `ServerScriptService/Modules/AchievementManager.lua` | Full rewrite — new DefaultStats, MergeDefaults, all hook methods |
| `ServerScriptService/Modules/CurrencyManager.lua` | Added `OnEssenceAdded` callback registration + `AddEssence` fires callbacks |
| `ServerScriptService/Modules/SkillEffects.lua` | Added `getAM()` lazy loader; calls `am.OnHealingDone` after `HealPlayer` |
| `ServerScriptService/Modules/ClassSkills/LifeStewardSkills.lua` | Calls `am.OnReviveDone` after revive XP grant in `GenesisExec` |
| `ServerScriptService/Modules/WeaponManager/WeaponXPSystem.lua` | Added `getAM()` lazy loader; calls `am.OnWeaponLevelUp` on level-up |
| `ServerScriptService/Modules/TalentManager.lua` | Calls `am.OnTalentAllocated` after node allocation in `AllocateNode` |

---

## CapMasteryMap (boss IDs to wire in MobRegistry)

```lua
AchievementConfig.CapMasteryMap = {
    ["iron_warden"]       = { statKey = "cap50",  levelCap = 50  },
    ["void_harbinger"]    = { statKey = "cap100", levelCap = 100 },
    ["pale_colossus"]     = { statKey = "cap150", levelCap = 150 },
    ["abyssal_sovereign"] = { statKey = "cap200", levelCap = 200 },
}
```

These boss IDs auto-wire into both the medal achievements and the cap mastery achievements the moment the bosses are added to MobRegistry with matching IDs. No code changes required.
