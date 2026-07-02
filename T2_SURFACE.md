# T2 Combat — Surface

> **STATUS: EXECUTED (2026-06-12).** Landed under `§T2/Z<n>` tags:
> Z1 (validate-then-consume hit reports), Z2 (Dead players earn no XP —
> KnockedDown still earns, it's a combat state not AFK), Z3 (**seven**
> direction-block copies — one more than the map found, in
> RainOfArrows — consolidated into `BaseSkills.GetCastDirection`,
> NaN-proof, Aegis/Arcanist keep server-authoritative aim), Z5
> (AttackHandler per-player Janitor), Z6 (18 telemetry prints removed +
> OnMobKilled poll bounded 10 s), Z7 (dead-mob filter + dedup'd the two
> scan blocks in AttackShapes), Z8 (ProjectileConfig comments), Z9
> (only-if-longer refresh at max stacks + Vulnerability keeps the
> stronger mult / longer duration on re-apply — §T1P2-STACKS rule
> implemented; per-debuff maxStacks>1 remains a balance decision).
> **Z4 = won't-fix by design** (Pablo: skills cast once, the effect
> always lands even if the caster leaves).
>
> All 11 touched files verified: AST-parse clean (working view or
> HEAD+patch in-memory where the mount served stale bytes).
>
> Smoke tests: pierce a mob that dies mid-flight → follow-up hit on a
> second mob still lands (Z1); die and stay dead during a party kill →
> no XP tick (Z2); all four classes' directional skills aim correctly,
> incl. Hunter with mouse aim (Z3); double-cast Meteorite on one mob →
> debuff timer never shortens (Z9).
>
> Map: 3 parallel deep-reads over AttackHandler(+DamageHandler),
> SkillManager/SkillEffects/SkillRegistry, ClassSkills×5(+AttackShapes,
> KillRewardManager, ElementalSystem, ProjectileConfig) — 5,931 lines.
> Verification: I re-read AttackHandler + DamageHandler fully and
> spot-verified every High/Critical agent claim. **Seven of them were
> wrong** (see "Refuted" — the combat core is in much better shape than
> the raw maps suggested). IDs `Z1…Z9`. 🚨 bug > 🟡 spaghetti > 🟢 minor.
> **No edits made. Respond per item: `Z1. Yes / No / discuss`.**

---

## 🚨 Bugs

### Z1. Hit slot + target-dedup consumed BEFORE validation — invalid report blocks a legit one
`AttackHandler/init.lua:304-321`. Order today: mark `targetsHit[target]`
+ increment `hitsUsed` (304-306) → THEN check mob alive (308-309) and
range (311-321). A report that fails validation — most commonly lag
(mob died in flight, player moved out of range) — still burns a hit
slot AND permanently dedups that target for the attack, so the player's
follow-up legit hit on the same mob is rejected. For pierce projectiles
(maxHits 3) this visibly eats hits. This is the same bug family as the
old "I swung but no damage" reports.
**Fix shape:** run the alive + range checks first; consume the slot and
mark dedup only when the hit is accepted. ~6-line reorder.

### Z2. Kill-XP recipients: no alive/DeathState gate *(carried G14 — needs DQ-T2A)*
`KillRewardManager.lua` `getEligibleXPRecipients` (~line 169-189):
recipients are filtered only by `member.Parent` + range. A knocked-down
or dead party member inside 60 studs earns full shared XP. The killer
themselves is guaranteed alive (HandleHitReport gates it), but
recipients aren't. Whether that's a bug or co-op-friendly design is
yours to call → **DQ-T2A**. If gating: skip `DeathState ~= "Alive"`
members (or half-XP for downed, your pick).

---

## 🟡 Spaghetti / robustness

### Z3. Direction-resolution copy-pasta across 4 skill files (5 sites) — with a NaN edge
The same 4-line "clientLook → flatten → fallback" block exists in
`AegisSkills:349`, `ArcanistSkills:340` + `:410`, `HunterSkills:325` +
`:378` — word-for-word in three of them, slightly better in Hunter.
None guard the vector AFTER flattening: a client sending
`lookDirection = (0,1,0)` (magnitude 1, passes the check) flattens to
zero → `.Unit` = NaN → NaN propagates into the cone/rectangle math
(fail-closed, no hits — but sloppy and it poisons AttackShapes'
`flatDirection` at `AttackShapes.lua:98/221` the same way).
**Fix shape:** one `BaseSkills.GetCastDirection(rootPart, inputData)`
helper with the zero-guard after flattening; replace all 5 sites.
Classic kill-the-spaghetti + fixes the NaN edge for free. → **DQ-T2C**
(touches 4 skill files, want it in this pass?)

### Z4. Delayed skill waves don't re-check the caster is still present
`ArcanistSkills.MeteoriteExec` (~:469, the 0.15 s second pass) and
`HunterSkills.RainOfArrowsExec` (~:469, wave 2) fire damage from
`task.delay` without checking the player still exists — a leaver's
"ghost" still deals the delayed wave (and damage math runs with empty
player data, hitting base-stat fallbacks). ShieldBoomerang and Barrage
already do the right early-out; these two drifted.
**Fix shape:** the same `if not player.Parent then return end` /
root-part early-out the other skills use.

### Z5. AttackHandler per-player connections not Janitor-tracked *(aligns §14b)*
`AttackHandler/init.lua:83,102` — `CharacterAdded` +
`GetAttributeChangedSignal("DeathState")` connections per player, never
stored. Player destruction disconnects them in practice (so NOT the
"critical leak" the map agent claimed), but it's the exact pattern L1/L2
already migrated to per-player Janitors, and AttackHandler is on the
§14b candidate list. **Fix shape:** the §5.1 Janitor pattern; or leave
for the §14b sweep — your call.

### Z6. Debug print noise in ClassSkills (16 sites) + `OnMobKilled` unbounded poll
Y12 family: 4-5 telemetry prints per skill file
(Aegis:368/376/465/492, Arcanist:359/432/457, Hunter:362/433/474/493,
LifeSteward:338/376/423/485/524). Plus `DamageHandler.lua:28-31` — a
pre-Init callback registration parks an unbounded 0.05 s poll loop
waiting for KillRewardManager; bound it (or warn+drop after ~10 s).

---

## 🟢 Minor / notes

### Z7. Dead-but-undestroyed mobs in shape targeting
`AttackShapes.getPotentialTargets` doesn't filter health ≤ 0. Impact is
nil in practice — `DamageMob` guards dead mobs and death → immediate
`Destroy()` — so at most a wasted loop iteration. Optional: skip
`Humanoid.Health <= 0` in the collector for cleanliness.

### Z8. ProjectileConfig future templates + coverage
`PiercingArrow`/`FrostBolt`/`ExplosiveShot` unused (future content —
leave, maybe tag), Aegis/LifeSteward intentionally absent from
ClassDefaults (melee/support) — worth a one-line comment so the next
audit doesn't re-flag it.

### Z9. §T1P2-STACKS is smaller than we thought — mob-side machinery already exists
`SkillEffects.lua:269-307`: the stacking path (`ApplyStackingEffects`)
already implements `maxStacks` + `refreshDuration` per mob+effect key —
Sundering Strikes uses it today. Vulnerability just goes through the
separate non-stacking `ApplyVulnerabilityToMob` (`:529-545`, keyed
single entry, overwrite+refresh — NOT the "second debuff gets lost" the
map agent claimed; the keyed entry is replaced atomically). So the T2
stacks work reduces to: (a) route Vulnerability (and any future
stacking debuff) through the existing stacking path with a per-effect
`maxStacks`, (b) implement your rule "at max stacks, refresh only if
new remaining > current remaining" (today `refreshDuration` always
refreshes), (c) the player-buff side (BonusManager.AddTimedBonus)
stays refresh-only unless a buff needs stacks. → **DQ-T2B**.

---

## ❓ Design questions

- **DQ-T2A (Z2).** Should knocked-down/dead party members within XP
  range earn shared kill XP? (Options: full / none / reduced.)
- **DQ-T2B (Z9).** Stacks design confirm: move Vulnerability onto the
  existing stacking path; which debuffs get `maxStacks > 1`? And confirm
  the refresh rule at max stacks (only-if-longer, per your earlier
  answer).
- **DQ-T2C (Z3).** Green-light the `GetCastDirection` consolidation
  (touches BaseSkills + 4 class files) in this pass?

---

## ✅ Refuted this pass (map agents flagged, verification cleared)

1. **"Client can flood attack tickets 10-50×"** — no: `CheckCooldown`
   at `AttackHandler:217` gates ticket CREATION by the server-side class
   attack cooldown, before any ticket exists. G12 is closed.
2. **"Ultimates trust client `resourceUsed`"** — no:
   `SkillManager.ExecuteSkill:435-440` reads the resource server-side,
   zeroes it, and OVERWRITES `inputData.resourceUsed` before the skill
   runs. Spoof impossible.
3. **"Taunt doesn't apply to mobs"** — it does:
   `SkillEffects.ApplyTaunt:678-698` sets `mobData.tauntEndTime` on
   every mob in range (MobAI's targeting reads it) + the IsTaunting
   attribute.
4. **"Same-frame double-kill reward race"** — no: `DamageMob:74` dead
   guard + single-threaded task execution; second killer's call sees
   health ≤ 0.
5. **"Lifesteal self-damage risk"** — no: clamped heal-only, and
   damage is floored ≥ 1 so the heal can't go negative.
6. **"SkillEffects leaks leaver effects (no PlayerRemoving)"** —
   `TickPlayerEffects:951-962` sweeps `not p.Parent` entries every tick;
   worst case a few hundred ms of retention. A PlayerRemoving hook would
   be determinism polish only.
7. **"Second Vulnerability lost when first expires"** — no: single
   keyed entry (`Vulnerability_direct`) is replaced atomically;
   overwrite+refresh semantics, no early-clear.

## ✅ Verified solid (no action)

SkillManager: atomic cast-lock watertight, server-authoritative
cooldowns from SkillRegistry, resource deducted before effects with
interrupt refund (`:282-285`), vote-interrupt nil-safe. AttackHandler:
range checks vs server positions, monotonic attackId with respawn
reset (§A2/§A3 held up), DeathState gates on both attack + hit-report.
DamageHandler: element resolution, §42.1 pipeline order, kill flow
pcall-guarded. Heals all route through the crit-unified
`StatsManager.CalculateHeal`. No direct `data.Bonus` writes anywhere in
ClassSkills. `GetForwardCastPosition` is fully server-authoritative
(§LD-SK1 fix held). No dead skills; all magic numbers live in skill
tables with §-references.

---

## Proposed action set

- **Batch A — correctness (Z1, Z4):** hit-report reorder + the two
  missing early-outs. Small, high-value.
- **Batch B — spaghetti kill (Z3 + DQ-T2C):** `GetCastDirection` in
  BaseSkills, replace 5 sites, zero-guard included.
- **Batch C — stacks (Z9 + DQ-T2B):** route Vulnerability through the
  stacking path + only-if-longer refresh rule at max stacks. Replaces
  the Y2 interim clamp with the real thing (clamp can stay as
  belt-and-suspenders).
- **Batch D — hygiene (Z5, Z6, Z7, Z8):** Janitor pattern or defer to
  §14b, prints sweep, poll bound, comments.
- **Z2 waits on DQ-T2A.**

Reply per item/batch (e.g. "A yes, B yes, C yes — vuln maxStacks 3,
D yes but Z5 defer; DQ-T2A none for dead / full for knocked-down").
