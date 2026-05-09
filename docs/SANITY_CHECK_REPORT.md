# Roblox Defense — Alpha Sanity Check Report

**Scope:** Shared combat systems first, then economy, content, and alpha-blockers.
**Target feel:** Moderate — reward-for-effort.
**Date:** 2026-04-22.

This report is organized in three parts per your ask:

1. **Code cleanliness** — repetition, dead code, spaghetti, hot-path noise.
2. **Balance** — progression curves, reward pacing, difficulty, content density.
3. **Missing features** — what an alpha player will immediately notice is absent.

Every finding includes an `Evidence:` line with file paths and line numbers so you can jump to it. Severity tags: **[BLOCKER]** must fix before alpha, **[HIGH]** should fix, **[MEDIUM]** strong improvement, **[LOW]** polish.

---

## TL;DR — The Dreamteam Verdict

The shared combat code is in **genuinely good shape**. The damage pipeline, client-authoritative hit system, bonus aggregation, and skill/XP architecture are the kind of clean you get from real iteration — the BALANCE_REWORK_SPEC and CODE_AUDIT fixes are almost all landed and verifiable in the code. Your March audits did their job.

The alpha-blocking issues are **not** combat code — they are:

- **Content density.** Three mob types total, with Zombie as the sole weighted spawn across all 12 waves. Troll/Ogre only appear as guaranteed miniboss injections. The fight loop at wave 7 is mechanically identical to wave 1, just with bigger numbers.
- **Audio is a ghost town.** `SoundManager` has 28 named sounds, all pointing at `rbxassetid://0`.
- **Animation variety.** Three of four classes share one `rbxassetid://128777973` placeholder for basic attacks.
- **One real file corruption:** `SkillEffects.lua` has 28 trailing NUL bytes.
- **Armor XP still disabled** (commented out in KillRewardManager) — a progression cliff for tanks.

The remaining findings are cleanup and polish. Moderate-difficulty balance math checks out on paper — with the content-density fix, an alpha player should feel the intended reward-for-effort curve.

---

## Part 1 — Code Cleanliness

### 1.1 [BLOCKER] `SkillEffects.lua` has 28 trailing NUL bytes (real file corruption)

The only true file-level corruption I found in the repo. All other "null byte" hits in scans were false positives from grep's binary-file heuristic tripping on CRLF + UTF-8 emoji decorations.

- **Evidence:** `src/shared/ServerScriptService/Modules/SkillEffects.lua` — 38,875 bytes, last 28 are `\0`.
- **Fix:** `tr -d '\0' < SkillEffects.lua > SkillEffects.lua.clean && mv SkillEffects.lua.clean SkillEffects.lua` — then re-save. Luau tolerates trailing NULs silently but they will sometimes cause diff tools, git hooks, or Rojo sync to misbehave.

### 1.2 [HIGH] Production log spam in MobAI and DamageHandler hot paths

A running wave prints dozens of lines per second. This is the single biggest visible problem when you open the Output window. It also costs real CPU under load.

- **Evidence:**
  - `Modules/MobAI.lua:103, 141, 246-250, 584, 950, 954` — printed inside `Update()`, `ApplySkillHit()`, `RegisterMob()`, `UnregisterMob()`.
  - `AttackHandler/DamageHandler.lua` — `DebugPrint` runs on every hit report (user correction from CODE_AUDIT not fully landed).
- **Fix:** Gate every hot-path `print` behind a `DEBUG_MOB_AI = false` / `DEBUG_DAMAGE = false` module constant; leave lifecycle prints (Init, wave start/complete) alone.

### 1.3 [HIGH] `KillRewardManager` armor XP branch is dead code

Kept commented out "for later" but takes up 14 lines and confuses anyone reading the reward flow. If you intend to keep armor XP off for alpha, delete it; if you intend to enable it, wire it. See §2.4 for the gameplay consequence.

- **Evidence:** `Modules/KillRewardManager.lua:309-322`.
- **Fix:** Delete the block or gate behind a single `ARMOR_XP_ENABLED` flag and add a TODO.

### 1.4 [MEDIUM] `WeaponXPSystem` vs `EquipmentXPSystem` are intentionally separate — but mostly parallel

Unlike weapon/armor **refinement** and **tier** systems (both refactored to `EquipmentRefinement`/`EquipmentTierSystem` factories — nice job), the XP systems diverged because weapon XP is class-role-specific (DPS mob kills, Tank damage taken, Healer heals, Support buffs/revives). That divergence is real and justified.

What's **not** justified: the `processXP()` level-up loop, XP-bonus application, cap clamp, and `GetXPProgress()` helpers are nearly character-for-character duplicated between the two files.

- **Evidence:**
  - `Modules/WeaponManager/WeaponXPSystem.lua:92-160` — `processXP`.
  - `Modules/EquipmentXPSystem.lua` — same inner loop.
- **Fix:** Factor a shared `EquipmentXPCore` with `AddXPToItem(item, xp, maxLevel, xpFn) → levelsGained`. Each system keeps its own *grant* methods (which is where the role gating / source specificity lives) but share the level-up math.

### 1.5 [MEDIUM] `SkillExecutor` is now only an initializer

The old "pure redirect" `Execute()` method has been removed (CODE_AUDIT #6 landed). What remains is a single `Init()` function — about 65 useful lines gluing dependencies together. This is fine as-is but consider folding into `SkillManager/init.lua` if no new responsibilities land in the next month — one less module to reason about.

- **Evidence:** `Modules/SkillManager/SkillExecutor.lua` (79 lines, 1 public function).

### 1.6 [LOW] Placeholder sound/animation stubs scattered across codebase

Not cleanliness per se but worth auditing in one pass.

- **Evidence:** `SoundManager.lua:47-77` — 28 entries with `id = "rbxassetid://0"`. Also called out in §3 as content gaps.

### 1.7 [LOW] Scattered `TODO` / `stub` markers

All legitimate and documented; none represent unfinished critical paths. Keep them as a reminder but tag them for your own alpha-blocker triage.

- **Evidence:**
  - `ShopManager.lua:229, 243` — MarketplaceService premium purchase not wired.
  - `TalentManager.lua:17` — "TalentPointProvider is an abstract interface (stub for now)". (Works fine for alpha, just means tracking multiple providers isn't generic yet.)
  - `TeleportManager.lua:130` — "VALIDATION (stubs — extend for level/class requirements)". Means anyone can teleport anywhere. Alpha-acceptable for a closed test.
  - `SocialPanel.lua:666` — "Guild tab stub".
  - `SkillRegistry.lua:39` — `result.PLACEHOLDER` branch (feature flag for class-in-dev).

### 1.8 Positive notes (what's genuinely clean)

- **Damage pipeline** in `StatsManager/DamageSystem.lua` — 8-step ordered pipeline (BaseAttack → ActionMult → PercentDmg → Armor → Crit → Element → Vulnerability → floor) is honest, well-commented, testable.
- **BonusManager source separation** (weapon/armor/buff/talent/achievement/innate/acc_*/timed_*) — every bonus is attributable, additions/removals don't fight each other. `SetSourceBonuses` routing in `PlayerBonusSystem.lua:116,179` closes the old race.
- **AttackHandler client-auth tickets** — `pendingAttacks[player][attackId]` with monotonic `lastAttackId`, per-target dedup via `ticket.targetsHit[target]`, pruning on 5s/5-ticket cap. This is the hardest part of any multiplayer combat system and it's correct.
- **BaseSkills.InjectGetters** (lines 245-266) — clean deduplication of getter functions across all 4 class skill modules.
- **WeaponRefinement/ArmorRefinement as thin factory wrappers** (both ≤20 lines calling `CreateRefinementSystem(Config, kind)`) — textbook M1 fix.
- **CriticalSystem** explicit 2-proc cap (`math.min(critProcs, 2)`) closes H8.
- **WaveConfig deepCopy** prevents the old L8 mutation bug.

---

## Part 2 — Balance

I spot-checked numbers against `BALANCE_NUMBERS.md` and the live configs. Headline: **on paper, the moderate-difficulty reward curve works**. The problems below are mostly about *feel* and content density, not broken math.

### 2.1 XP pacing (account level)

- Formula: `xp_to_next = 120 × 3.2^chapter × (1 + 0.05 × partial)^1.9`, which at Chapter 1 / Level 1→2 ≈ **120 XP**.
- Zombie at parity (delta = 0) gives ~4 XP to a DPS (base reward × 1.0 delta multiplier).
- **~30 Zombies = L2.** Wave 1 spawns 10, wave 2 spawns 12, wave 3 spawns 14 = 36 mobs by end of wave 3. That's a clean "ding on wave 3" — great first-run feel.
- Delta window (`±5 full → 0 at ±10`) is symmetric and aggressive; good for preventing farming low-level content.

**Verdict:** Good. This is the cleanest curve in the game.

### 2.2 Damage/HP curves (moderate target)

Spot checks assuming party anchor = player level, Zombie baseline 100 HP / 10 dmg / 2 armor:

- **L1 Aegis vs L1 Zombie:** shape range melee, ~15 dmg average → 7 hits. Feels right for a first-time tank.
- **L7 (≈ wave 12) Aegis vs L7 Zombie:** Zombie HP = `100 × ((7+9)/10)^1.28` ≈ `100 × 1.77` = 177 HP. Aegis with L7 weapon + talents ≈ 30 dmg → 6 hits. **Slight improvement** — the player feels a little stronger than they did at L1, as expected.
- **L12 Aegis tank vs L12 Ogre miniboss:** Ogre HP = `500 × ((12+9)/10)^1.28` ≈ `500 × 2.61` = 1305. Ogre dmg = `40 × ((12+9)/10)^1.15` ≈ `40 × 2.35` = 94. After 20% DR on tank → ~75 received per hit vs 340 HP = **4.5 hits to down**. Ogre dies to ~43 Aegis hits (dps window across ~40s of combat). **This is a satisfying miniboss fight.**

**Verdict:** Moderate target hit. The only caveat is mobs don't visibly counter-scale anything besides raw stats — see 2.4.

### 2.3 Content density (the alpha's biggest feel problem)

- **Only three mob types exist:** Zombie (100/10/2 Earth), Troll (400/35/8 Water, 40% HP Enrage), Ogre (500/40/12 Fire, 30% HP Enrage). Folder check: `Modules/Mobs/` has exactly three files.
- **Zombie is the only weighted spawn** across all 12 waves. Troll and Ogre appear only as `guaranteed` miniboss injections (waves 4, 7, 10, 12), never in the weighted pool.
- Procedural waves after 12 have the same availableMobs = `{"Zombie"}`.
- Element/damage-type variety is therefore 99% Earth.

**Why this matters for moderate-difficulty feel:** The player can learn one counter (positioning, skill rotation, elemental loadout) and re-use it forever. There's no "what mix am I facing" question, no "oh shit, a caster" moment. The game's *mechanics* suggest variety the *content* doesn't deliver.

- **Evidence:** `Modules/WaveConfig.lua:26-38` (every `spawnWeights = { Zombie = 1 }`); `Modules/Mobs/` contains only Zombie.lua, Troll.lua, Ogre.lua.
- **Severity:** [BLOCKER] for alpha perception, even though the code is fine.

### 2.4 Armor XP progression cliff

Weapon XP awards flow through four class-role paths (DPS kills, Tank damage taken, Healer heals, Support buffs) — all wired and verified in `WeaponXPSystem.lua`. But armor XP is commented out in `KillRewardManager.lua:309-322`.

A player at L12 with a level-12 weapon and a **level-1 armor** is the default outcome — no passive armor progression matches weapon progression. Tanks will feel this acutely. Talent-point budgeting is fine but the "I upgraded my weapon, why didn't my armor?" question is unanswered.

**Fix options:**
1. Ship alpha with armor XP off, document it: "armor levels via Equipment Refinement currency sink only."
2. Re-enable the armor XP branch with ~25% of weapon XP per kill.

Recommendation: **option 2**. Simpler player mental model for alpha.

### 2.5 Drop/economy curves

- Normal Zombie: 1-3 Merits (chance 1.0), scale +10%/level. L1 = 1-3, L12 = 2-6 → **~300 Merits per 12-wave run** at parity.
- Miniboss: 8-15 Merits + 30% chance of 2-4 Essence (flat). Four minibosses/run = ~45 Merits + ~4 Essence expected.
- Boss: 25-50 Merits + 75% chance of 8-20 Essence.
- Respec costs: `LOW = 25 Essence / 20k Merits`, `HIGH = 40 Essence / 50k Merits`.

**Spot check:** A full clean run nets roughly 350-500 Merits and 4-6 Essence. A LOW respec costs 25E + 20,000M. **That's ~50 runs per respec.** For alpha, this is too steep — players will not respec, which means they will not experiment, which means classes will feel rigid.

- **Fix:** For alpha only, either (a) reduce LOW respec to 5E / 2,000M, or (b) grant a free respec per account level. The current cost makes sense as a late-game sink, not as an alpha-friction setting.

### 2.6 Skill damage multipliers (class comparison)

Quick sanity table from `ClassSkills/*.lua`:

| Class | Strong skill dmg | Short CD | Ult CD |
|---|---|---|---|
| Aegis | 0.45x (tank-shaped) | 6s | 75s |
| Arcanist | 3.0x (biggest nuke) | 16s | 75s |
| Hunter | 1.2x basic / 0.8x AoE | 3-14s | 75s |
| LifeSteward | heal-focused (0x on most) | 3-12s | 90s |

**Verdict:** Asymmetric and intentional — Arcanist has burst, Hunter has uptime, Aegis has survivability, LifeSteward has party utility. Good. The 75-90s ult cooldowns are long enough to be events, not spam.

### 2.7 Defense line breach damage

`DefenseConfig.BreachBasePct = { normal=4%, elite=8%, miniboss=14%, boss=24% }` × `RemainingHpFactor = 0.5 + 0.5×hpPct`.

- First Zombie breach at full HP: `1500 × 0.04 × 1.0 = 60 dmg` (4% loss).
- Miniboss at full HP: `1500 × 0.14 × 1.0 = 210 dmg` (14% loss).
- Miniboss at 50% HP: `1500 × 0.14 × 0.75 = 157.5 dmg` (10.5% loss — self-dampening as you get closer to loss).

**Verdict:** The self-dampening curve at low HP is the right design choice — prevents death-spiraling a close fight. 4%/breach for normals means you can absorb ~25 normal breaches, which is plenty of slack for an alpha player still learning aggro management. Good.

### 2.8 Wave pacing (the "flat feel" risk)

- Wave 1: 10 Zombies, 2.5s interval → ~25s spawn window
- Wave 12: 32 Zombies + Ogre, 1.3s interval → ~43s spawn window
- 7s between waves (recently bumped from 3s — good change)

Combined with 2.3, wave-to-wave feel is *almost entirely* "same mob, slightly more, slightly faster." The spawn-interval decay is smooth but the content is static. See §3.1 recommendation.

---

## Part 3 — Missing Features (Alpha Blockers vs Nice-to-Haves)

Ranked by "will an alpha player notice in their first 20 minutes".

### 3.1 [BLOCKER] More mob variety

Minimum for a credible alpha: **5-6 mob types** with at least **2 visible elements** in the weighted pool.

Recommended additions (cheap because they reuse your existing MobAI + skill + element system):

1. **Skeleton Archer** — ranged Zombie variant. Water or Air element. Low HP, high kiteability. Teaches the player to close distance.
2. **Wraith** — fast Water mob, 60% Zombie HP, 130% move speed. Teaches kiting.
3. **Imp** — AoE self-destruct Fire mob, small splash on death. Teaches target-prioritization.

Add them to the weighted pool from wave 3 onward. Zombie weight 4, Skeleton 2, Wraith 1, Imp 1 → variety without overwhelming learners.

### 3.2 [BLOCKER] Sound design (every single sound is `rbxassetid://0`)

28 named events in `SoundManager.lua` are all stubs. First time a player swings a sword or a wave starts, the silence will tell them "this is pre-alpha."

- Ship minimum: swing_sword, shoot_bow, cast_wand, hit_normal, hit_crit, enemy_death, player_death, level_up, wave_start, wave_complete, ui_click.
- Free sources: Roblox audio library, Freesound.org (CC-licensed), Zapsplat.

### 3.3 [HIGH] Class animation variety

Three classes share `rbxassetid://128777973` (R6 Wave). LifeSteward has `rbxassetid://128853357` (Point). This is the other side of the "pre-alpha" tell.

- Minimum: one unique basic-attack animation per class. Roblox free catalog has workable stand-ins for melee, ranged, and cast.
- **Evidence:** `Modules/AnimationConfig.lua:42-54`.

### 3.4 [HIGH] Tutorial / first-run onboarding

Zero onboarding code anywhere. `grep` for `tutorial|onboarding|firstRun|FirstTime` across `src/` → no matches. A first-time player loads into the lobby and is expected to know what to do.

- Minimum: one-time popup with "WASD move, LMB attack, 1-4 skills, Q dash, Tab inventory". Can ship as a static UI overlay checked against a `data.HasSeenTutorial` flag.

### 3.5 [HIGH] Armor XP re-enablement (see §2.4)

### 3.6 [HIGH] Premium purchase wiring (if you want monetization at alpha)

`ShopManager.PurchasePremium` is a TODO. If alpha is free-only, skip. If you want to test Robux flow, wire `MarketplaceService:PromptProductPurchase` now.

- **Evidence:** `ShopManager.lua:229,243`.

### 3.7 [MEDIUM] Network rate limiting coverage

`NetworkManager.lua:18,215` has a rate-limiting helper, but I didn't verify every remote has limits applied. Worth a one-hour audit: AttackEvent, PlayerHitReport, SkillActivate, ShopPurchase, ClassSwitch are the ones that matter for exploit prevention.

### 3.8 [MEDIUM] Guild / social features

`SocialPanel.lua:666` has a "Guild tab stub". Fine to ship alpha without guilds; call it out in alpha notes so feedback doesn't fixate on it.

### 3.9 [MEDIUM] Teleport validation

`TeleportManager.lua:130` has "stub — extend for level/class requirements". In a closed alpha this is acceptable but anyone who finds the client-side place IDs can bypass level gates.

### 3.10 [LOW] Mob cosmetic variants

`CosmeticManager.ApplyMobVariant` is wired in `MobSpawner.lua:473`. Worth confirming there's at least one variant per mob so the "applied variant" log doesn't fire on empty data.

### 3.11 [LOW] Leaderboard hookup

`LeaderboardManager.lua` exists and `LeaderboardUI.lua` exists. Worth verifying end-to-end (write on run end, read on lobby entry).

### 3.12 [LOW] Monitoring / telemetry

`MonitoringSystem.lua` exists. Worth confirming it's wired for the alpha — at minimum, track: session length, wave reached, deaths, class picked, currency earned. You'll want this data after the first 50 testers.

---

## Appendix — Priority Matrix for Alpha Readiness

| # | Item | Severity | Est. time | Blocks alpha? |
|---|---|---|---|---|
| 1 | Content: 3 new mob types with 2+ elements | BLOCKER | 2-3 days | Yes |
| 2 | Sound design (11 minimum SFX) | BLOCKER | 1 day | Yes |
| 3 | Remove SkillEffects.lua NUL bytes | BLOCKER | 1 min | Yes |
| 4 | Class basic-attack animations (3 new) | HIGH | 0.5 day | Soft yes |
| 5 | First-run tutorial popup | HIGH | 0.5 day | Soft yes |
| 6 | Re-enable armor XP | HIGH | 2 hrs | No but recommended |
| 7 | Lower alpha respec cost | HIGH | 15 min | No but recommended |
| 8 | Gate hot-path prints (MobAI + DamageHandler) | HIGH | 1 hr | No |
| 9 | Delete dead armor XP code OR wire | MEDIUM | 15 min | No |
| 10 | Network rate-limit audit | MEDIUM | 1 hr | No |
| 11 | Factor shared EquipmentXPCore | MEDIUM | 3 hrs | No |
| 12 | Telemetry confirmation | LOW | 30 min | No |

**Total blocker time:** ~3-4 days of solo-dev work for the items that actually hold back alpha. None of them are in the combat code.

---

## What I Did Not Verify (be aware)

- **DefenseLine.LateInit sequencing** (C7 in old audit) — I assumed resolved based on REVISION_TRACKER but did not trace it end-to-end. Low confidence this is a problem; worth a 10-minute trace before alpha.
- **Per-remote rate-limit coverage** — noted as §3.7; needs its own audit pass.
- **Place-specific scripts** (lanedefense, centralboss, hordemode) — only spot-checked. My focus per your ask was shared combat.
- **Mob cosmetic variant config presence** — noted as §3.10.
- **Data-store save reliability under disconnect** — not audited. Worth its own check.

If any of these are worth a follow-up pass, say the word and I'll dig in.

---

**Session note:** Context is comfortable; I stopped at a natural end rather than at a budget limit. If you want me to do a second pass on any of the "did not verify" items, or on any of the non-combat places (lane defense, central boss, horde mode, social plaza), just tell me which and I'll keep going.
