# Design Decisions

Pablo's calls, with their original ids, so nobody re-asks them. Open questions are in [BACKLOG § Needs Pablo](BACKLOG.md#needs-pablo). Numbers are in [BALANCE_NUMBERS.md](BALANCE_NUMBERS.md).

**Contents:** [Principles](#principles) · [Monetization](#monetization) · [Assets](#assets) · [DISC decisions](#disc-decisions) · [UI decisions](#ui-decisions) · [Tier design questions](#tier-design-questions) · [Agency-round decisions](#agency-round-decisions) · [Answered balance questions](#answered-balance-questions)

---

## Principles

From `Audit_4.7.md` §1 and the working agreement.

1. **Pablo owns the vision; agents own code, balance and security.** Game feel, mechanics and anything a player would notice as a design change is Pablo's. Implementation, refactors, balance tuning inside the agreed design, and security are the agents' call. When unsure which it is, ask (surface it as a design question) instead of guessing.
2. **Unmentioned = fix.** When Pablo reviews a numbered findings list, items he doesn't mention are approved. Direct fixes that don't change behaviour may land without asking.
3. **No spaghetti unless removing it is risky.** Documented seams and empty API stubs stay; magic timers, duplicate handlers and dead branches go.
4. **Loud at boot over silent drift.**
5. **Single source of truth.** When two configs describe the same thing, derive one from the other.
6. **Pattern consistency.** A clean pattern that lands in one module gets ported everywhere it applies.
7. **Modular by feature.** State that belongs to system X lives in X, even if another system fires it.
8. **Pablo commits.** He live-tests in Studio, then commits from his terminal; never amend.

## Monetization

Decided 2026-09-26 (`§AGX/X40`, `§AGX/X46`; commits `cdba264`, `1c6e333`).

- **No P2W.** Gameplay currency (Merits, Essence) is **never** sold for Robux, and nothing bought with Robux may turn into currency or power. Refine, reroll and tier-up stay earn-only, so they are not paid random items.
- **Robux buys only** cosmetics with no stats, appearance changes (after the free one at level 50), and non-power convenience or social perks (VIP chat tag).
- **Not allowed for Robux:** currency packs, respec scrolls/tokens, consumables, XP/drop/Merit boosts, extra revives, and any cosmetic also sold for Merits/Essence.
- **The code gate is `ALLOWED_GRANTS`** in `MonetizationService.lua` (`AppearanceChange`, `Cosmetics`, `GamePass`). Widening it is a monetization decision for Pablo, not a code change.
- **Receipts:** one `ProcessReceipt` owner (`MonetizationService`); the `PurchaseId` is written with the grant and saved in one `UpdateAsync` under the session lock; `PurchaseGranted` only after that save succeeds, otherwise `NotProcessedYet`; `enabled` is enforced on the server. (This was the "Receipts checklist".)
- **`Account.Monetization.robuxSpent` is private.** Never on a public leaderboard.
- **PolicyService (X46)** is not needed while nothing bought with Robux reaches a random outcome or player trading. **Tripwire:** before that changes, add `ArePaidRandomItemsRestricted` / `IsPaidItemTradingAllowed` checks and reopen X46 (`§AGX/X46-GUARD`). The planned Essence auction trades an earn-only currency, so it isn't paid item trading.
- **Wipe-revive:** free revives by difficulty, then one paid in Essence; never a Robux upsell under a countdown (X40, supersedes `DISC-D3b`).
- **Premium never rotates** in the shop (a countdown on a Robux listing is fake urgency).
- **Appearance:** "You can create some random character at the beginning, but the second change is definitely a decision. One cosmetic change at level 50 with an achievement, then paid." (Pablo, §AGX/X18b)

Prices: [BALANCE § Monetization](BALANCE_NUMBERS.md#monetization-robux).

## Assets

- **`.rbxmx` assets are place-managed** (G1): the published places hold the authoritative copies; `*.rbxmx` in `.gitignore` is correct. `assets/ui/` PNGs are committed (small, Pablo's call).
- Heavy binaries don't belong in git either (`foreman.exe`, `Leg.obj`, `Leg.mesh` untracked in `3741f10`).
- `.env` holds the Open Cloud key and is never committed.

## DISC decisions

Discussion batch, 2026-06-12 (`T5-T9_SWEEP.md`). Code tag stays `§DISC/Dn`; in prose use `DISC-Dn`.

| Id | Question | Pablo's call |
|---|---|---|
| `DISC-D1` | Respec scroll: shop-only acquisition enough? | Shop path suffices; mission sources later |
| `DISC-D2` | Trust in teleported `partyData` | Party = everyone in the battle map (reserved servers make it true). Persistent parties across hops is a future feature |
| `DISC-D3` | Party wipe (was `T4-DQ-T4A`) | All dead → pause → defeat. Later extended with free/paid wipe-revives (X40) |
| `DISC-D3b` | Robux wipe-revive product | **Won't do** (X40) |
| `DISC-D4` | Cap BonusExpSystem multipliers? | Yes: any single source ≤ +100%, total ≤ +200% (3.0×), warn on clamp |
| `DISC-D5` | Keep the dormant "achievement" bonus source? | **Core.** Achievements will grant permanent stat bonuses and gate features (chapter-50 boss unlock, future class unlocks) |
| `DISC-D6` | MaxLevelGap duplication (G9) | Revised: build `PartyRequirements`, shared by invite and launch checks, for future gates too |
| `DISC-D7` | Shop rotation | Build rotation + paid Essence refresh (implemented as `§AGX/D7`; the agent's parameters await confirmation: `§AGX/D7-ROT`) |
| `DISC-D8` | Silent server-side NPC failures | Revised: NPC UIs auto-close when the player walks away (`useNpcDistanceClose`, 16 studs vs the server's 12) |

## UI decisions

UI revamp, decided 2026-09-26 (`cdba264`; Pablo: "go with your recommendation"). Renamed from `D1…D15` to avoid clashing with `DISC-D7`.

| Id | Question | Decision |
|---|---|---|
| `UI-D1` | Visual direction | **Hybrid:** clean flat blue for bodies and lists; anime orange for headers, the one primary CTA per screen, and HUD vitals |
| `UI-D2` | Sizing model | **Fixed sizes at phone scale + one root `UIScale` per form factor.** Replaces the old pure-Scale rule (V16) |
| `UI-D3` | Menu surface | **Icon rail** (desktop), ☰ sheet (phone), radial on gamepad |
| `UI-D4` | Orientation | Landscape only |
| `UI-D5` | NPC interaction | Native `ProximityPrompt` |
| `UI-D6` | Skills while a menu is open in combat | Suppressed (UI input context) |
| `UI-D7` | Combat menus | Translucent side sheet on PC/tablet; full sheet on phone |
| `UI-D8` | Click outside to close | Small dialogs only |
| `UI-D9` | Toast position | Top-right |
| `UI-D10` | Resource on phone | Bar in the vitals; skills dim when unaffordable |
| `UI-D11` | Horde aim on phone | Twin-stick Attack (press to attack, drag to aim) |
| `UI-D12` | Talent tree on touch | Tap to select + Allocate button |
| `UI-D13` | Currencies in combat on phone | Inside the menu sheet |
| `UI-D14` | Daily Login | Auto-open on the first lobby join of the day, badge on the entry |
| `UI-D15` | SocialPlaza | Full shell (menu, settings, exit) |
| `§T10/STACK` | Two UI stacks | React-lua is canonical; the static `AppGui` stack is disabled and will be archived |

The `docs/ui_audit/*` design questions are answered by this table.

## Tier design questions

| Id | Question | Decision |
|---|---|---|
| `T0P2-DQ-A` (= `G-DQ3`) | ReadyGate overflow | Kick for resync; never evict boot-critical events |
| `T0P2-DQ-B` | Who owns run difficulty | The Lobby. Validated on arrival, resolved once from the first arrival, immutable after |
| `T0P2-DQ-C` | Horde/Lane servers | One run per server |
| `T1P2-DQ-T1A` | Vulnerability cap and stacking | Cap it; strongest application wins, no stacking. (Interim ≤3.0, final ×2.0 in §AGX/BAL) |
| `T1P2-DQ-T1B` | HitTracker `lifetime` block | Deleted; lifetime data lives in achievement and gear-XP tables |
| `T1P2-DQ-T1C` | Penetration cap | Keep **flat** penetration as is (uncapped) and add a separate %-penetration stat with the 60 cap later (`§T1P2-PEN`). ⚠ §AGX/BAL now clamps flat Penetration at 60 (`DamageSystem.lua:133`): conflict raised as `§T1P2-PEN-CAP` |
| `T1.2-DQ1` | CastTimeReduction for non-casters | Caster-only (Arcanist, Life Steward); optional in `DerivedStats` |
| `T1.2-DQ4/DQ5` | Class fields | `attackShape`/`shapeParams`/`baseAttackSpeed` belong to weapons; resources belong to `ClassBehavior.CONFIG` |
| `T2-DQ-T2A` (= `G-DQ1`) | Kill XP for downed/dead players | Dead: none. Knocked down: full (it's a combat state, not AFK) |
| `T2-DQ-T2B` | Debuff stacks | Refresh at max stacks only if the new duration is longer; Vulnerability keeps the stronger multiplier and longer duration. Which debuffs get `maxStacks > 1` is open (`§T1P2-STACKS`) |
| `T2-DQ-T2C` | Direction-code consolidation | Yes (`BaseSkills.GetCastDirection`) |
| `T2 Z4` | Delayed skill waves after the caster leaves | Skills cast once; the effect always lands |
| `T3-DQ-T3A` (W9) | Spawner consolidation | `MobSpawnHelper`: **the spawner never fails** (retry forever with backoff), **uniform scatter** over the whole spawn part (resize parts in Studio) |
| `T4-DQ-T4A` | Party wipe | See `DISC-D3` |
| `G-DQ2` | Mob-skill multiplier order | Refuted at T3; no change |
| `G-DQ4` | Repo hygiene timing | Done; `.rbxmx` stay out of git by design (G1) |
| `§EASY/E1` | Ultimate unlock level | Base level 10. ⚠ Skill configs also set `unlockLevel = 30`, which wins: raised as `§ULT-LEVEL` |

## Agency-round decisions

2026-09-26 (`AGENCY_CHECKS.md` "Status after Pablo's decisions").

| Id | Decision |
|---|---|
| `X9` | A pity jump cut short by the chapter cap lands on the cap and **keeps** the temper bar for the next chapter (balance call) |
| `X18` / `X18b` | Re-creating a character needs an unlocked appearance change: one free at level 50 (Veteran achievement), then paid |
| `X19` | CentralBoss hidden (`available = false`) until its Studio test passes |
| `X23` | The code's pity rules are canonical; docs were aligned |
| `X40` | See [Monetization](#monetization) |
| `X44` | Drops are personal: every eligible party member rolls, scaled by their own level |
| `X46` | Not required under X40; tripwire kept |
| `X47` | Daily login = never-resetting calendar + a streak "spree" bonus |
| `X48` | Onboarding parked until all modes are final |
| Shell | Rail + PanelStack shell adopted as specified in `ui_audit/shell-spec.md` |

## Answered balance questions

Agents own balance; these are the recorded answers so they aren't re-litigated. Values: [BALANCE § Combat caps](BALANCE_NUMBERS.md#combat-caps-not-in-statcaps).

- **Multi-crit:** 2 procs max (max 3.24×).
- **Vulnerability:** ×2.0 cap, non-stacking.
- **Armor shred:** 0–50%; shred alone never zeroes armor.
- **Crit damage class scaling (`§T1.2-BAL1`):** none for any class; headroom to the 1.80× cap comes from gear, talents and the Hunter innate.
- **Heal multipliers (`§T1.3-BAL1`):** heals share the damage crit pipeline; Mending Touch 2.1, Verdant Bloom 1.25 keep L60 throughput on target.
- **Bonus-XP clamps:** `DISC-D4`.
- **Economy anchor:** 1 Essence ≈ 250 Merits (§AGX/X42).
