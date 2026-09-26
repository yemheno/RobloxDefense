# History

Where old docs went, what every `§`-tag in the code points at, and a one-line record of every closed item. Narrative history lives here and in `git log`, nowhere else.

**Contents:** [Moved files](#moved-files) · [Doc-reference remap](#doc-reference-remap) · [Renamed ids](#renamed-ids) · [Tag index](#tag-index) · [Tier roadmap](#tier-roadmap) · [Closed items](#closed-items) · [Old live-test ledger](#old-live-test-ledger)

---

## Moved files

Docs pass of 2026-09-26 (base `24c4d7e`). Every superseded file was moved **unchanged** with `git mv`, so `git log --follow` still works.

| Old path | New location | Live replacement |
|---|---|---|
| `Audit_4.7.md` | [`docs/history/Audit_4.7.md`](history/Audit_4.7.md) | Principles → [CLAUDE.md](../CLAUDE.md), [DESIGN_DECISIONS](DESIGN_DECISIONS.md#principles); §5 patterns, §10 decided-against, §11 BonusManager keys, §12 ReadyGate events → [ARCHITECTURE](ARCHITECTURE.md); §6–§7 open items → [BACKLOG](BACKLOG.md); §2, §4, §9, §13–§14 → this file |
| `docs/TODO.md` | [`docs/history/TODO.md`](history/TODO.md) | [BACKLOG.md](BACKLOG.md) (open) and [Closed items](#closed-items) |
| `AGENCY_CHECKS.md` | [`docs/history/AGENCY_CHECKS.md`](history/AGENCY_CHECKS.md) | X-items → [Closed items](#agency-checks-2026-09-25--26-agx) / [BACKLOG](BACKLOG.md); decisions and X40 rules → [DESIGN_DECISIONS](DESIGN_DECISIONS.md#monetization) |
| `AUDIT_FINDINGS.md` | [`docs/history/AUDIT_FINDINGS.md`](history/AUDIT_FINDINGS.md) | G-items → [Closed items](#repo-wide-pass-2026-06-12-g) / [BACKLOG](BACKLOG.md); DQ1–DQ4 and G1 → [DESIGN_DECISIONS](DESIGN_DECISIONS.md) |
| `CODEBASE_REVIEW.md` | [`docs/history/CODEBASE_REVIEW.md`](history/CODEBASE_REVIEW.md) | Version matrix → [README](../README.md); ownership map → [ARCHITECTURE](ARCHITECTURE.md#ownership-map); risks → [BACKLOG](BACKLOG.md) |
| `T0_PASS2_SURFACE.md` | [`docs/history/T0_PASS2_SURFACE.md`](history/T0_PASS2_SURFACE.md) | [Tag index](#tag-index); DQ-A/B/C → [DESIGN_DECISIONS](DESIGN_DECISIONS.md) |
| `T1_PASS2_SURFACE.md` | [`docs/history/T1_PASS2_SURFACE.md`](history/T1_PASS2_SURFACE.md) | same |
| `T2_SURFACE.md` | [`docs/history/T2_SURFACE.md`](history/T2_SURFACE.md) | same |
| `T3_SURFACE.md` | [`docs/history/T3_SURFACE.md`](history/T3_SURFACE.md) | same |
| `T4_SURFACE.md` | [`docs/history/T4_SURFACE.md`](history/T4_SURFACE.md) | same |
| `T5-T9_SWEEP.md` | [`docs/history/T5-T9_SWEEP.md`](history/T5-T9_SWEEP.md) | same; `§DISC` D1–D8 → [DESIGN_DECISIONS](DESIGN_DECISIONS.md#disc-decisions) |
| `docs/GAME_DOCUMENTATION.md` | [`docs/history/GAME_DOCUMENTATION.md`](history/GAME_DOCUMENTATION.md) | [SYSTEMS.md](SYSTEMS.md) (mechanics), [ARCHITECTURE.md](ARCHITECTURE.md) (§3–§7, §46–§48), [README](../README.md) (§1–§2). Its §45 duplicated BALANCE and was dropped |
| `docs/COSMETICS.md` | [`docs/history/COSMETICS.md`](history/COSMETICS.md) | [SYSTEMS § Cosmetics & animation](SYSTEMS.md#cosmetics--animation) |
| `docs/AchievementMap.md` | [`docs/history/AchievementMap.md`](history/AchievementMap.md) | Tables → [BALANCE § Achievements](BALANCE_NUMBERS.md#achievements) (regenerated from code); mechanics → [SYSTEMS § Achievements](SYSTEMS.md#achievements) |
| `docs/TALENT_TREE_PROPOSAL.md` | [`docs/history/TALENT_TREE_PROPOSAL.md`](history/TALENT_TREE_PROPOSAL.md) | Implemented (300 nodes). Pillars → [SYSTEMS § Talents](SYSTEMS.md#talents) |
| `docs/SCALING_AUDIT.md` | [`docs/history/SCALING_AUDIT.md`](history/SCALING_AUDIT.md) | Doctrine + hard wall → [ARCHITECTURE § Scaling](ARCHITECTURE.md#scaling); Deferred #1–#7 → [BACKLOG](BACKLOG.md) `§SCALE-D1…D7` (#5 closed) |
| `docs/UI_REVAMP.md` | [`docs/history/UI_REVAMP.md`](history/UI_REVAMP.md) | §3 → [ARCHITECTURE § UI](ARCHITECTURE.md#ui); §4 D1–D15 → [DESIGN_DECISIONS § UI](DESIGN_DECISIONS.md#ui-decisions) as `UI-D1…UI-D15` |
| `docs/HANDOFF_PROMPT.md` | [`docs/history/HANDOFF_PROMPT.md`](history/HANDOFF_PROMPT.md) | [CLAUDE.md](../CLAUDE.md) |
| `docs/BALANCE_NUMBERS.md` | kept in place, reorganised by system | Old numbering: [BALANCE § Old section numbers](BALANCE_NUMBERS.md#old-section-numbers); old text: `git show 24c4d7e:docs/BALANCE_NUMBERS.md` |
| `docs/STUDIO_TEST_PLAN.md`, `docs/CLAUDE_DESIGN_BRIEF.md`, `docs/ui_audit/*.md` | unchanged paths | — |

**Docs deleted before this pass** (recover with `git show`):

| File | Recover with | Notes |
|---|---|---|
| `docs/SANITY_CHECK_REPORT.md`, `_V2`, `_V3`, `_V4`, `_V4_PHASE_A` | `git show d862558:docs/<file>` | Source of most pre-v0.5 tags ([Tag index](#tag-index)) |
| `docs/ALPHA_AUDIT_REPORT.md`, `docs/CODE_AUDIT_REPORT.md`, `docs/SYNTAX_DAMAGE_REPORT.md` | `git show d862558:docs/<file>` | |
| `docs/REVISION_TRACKER.md`, `docs/TODO_PARKING_LOT.md` | `git show d862558:docs/<file>` | Merged into `TODO.md` in `66503b4`. Old docs call them "nonexistent"; they are recoverable |
| `BALANCE_REWORK_SPEC.md`, `FEATURE_TODO.md` | **never in git** | Cited by `ChapterConfig.lua:3` and many bare `§nn` tags. Lost; values now in [BALANCE_NUMBERS](BALANCE_NUMBERS.md) |

## Doc-reference remap

For the code-comment pass. Old reference in a comment → where it points now. The per-file list is in the pass's `comment-remap.md` hand-off.

| Old reference in code | New reference |
|---|---|
| `Audit_4.7 §5.1` (Janitor per player) | `ARCHITECTURE.md#janitor-per-player` |
| `Audit_4.7 §5.2` (LinkToInstance) | `ARCHITECTURE.md#janitor-per-character` |
| `Audit_4.7 §5.3`, `Audit_4.7 §5 lazy getters` | `ARCHITECTURE.md#lazy-getter` |
| `Audit_4.7 §5.4` | `ARCHITECTURE.md#hot-path-ref-cache` |
| `Audit_4.7 §5.5` | `ARCHITECTURE.md#readygate-pushes` |
| `Audit_4.7 §5.6` / `Audit §5.6` | `ARCHITECTURE.md#single-source-of-truth` |
| `Audit_4.7 §10` | `ARCHITECTURE.md#decided-against` |
| `docs/TODO.md §…`, `TODO §<id>` | `BACKLOG <id>` if open, else `HISTORY <id>` (see [Closed items](#closed-items)) |
| `TODO §1 [??]` (crit / vulnerability / armor caps) | closed: `BALANCE_NUMBERS.md#combat-caps-not-in-statcaps` |
| `TODO §3 ("Class Mastery XP source")` | `BACKLOG §T0P2-MASTERY` |
| `TODO §5` (respawn counter) | `BACKLOG §2.4d` |
| `TODO §11` (NM-D6 hang UI) | closed `§NM-D6` → [Closed items](#todo-and-audit_47-items) |
| `TODO §17 / §CB1` | `BACKLOG §AGX/X28-NEXT` |
| `TODO §DISC/D3b` | closed (won't do) → [Closed items](#discussion-batch-disc) |
| `TODO §T1.3-DQ2` | `BACKLOG §T1.3-DQ2` |
| `docs/TODO.md §T10/ICONS` | `BACKLOG §T10/ICONS` |
| `docs/TODO.md §PERF/BP` | closed `§PERF/BP` (keep `ENABLED = false`) |
| `BALANCE_NUMBERS §33` | `BALANCE_NUMBERS.md#economy-anchor` |
| `BALANCE_NUMBERS §48` | `BALANCE_NUMBERS.md#monetization-robux` |
| `BALANCE_NUMBERS §D7` | `BALANCE_NUMBERS.md#shop-rotation-and-paid-refresh` |
| `BALANCE_NUMBERS §Combat` | `BALANCE_NUMBERS.md#combat-caps-not-in-statcaps` / `#crit-damage-no-class-scaling` / `#heals-after-the-shared-crit-pipeline` |
| `BALANCE_NUMBERS §29` | `BALANCE_NUMBERS.md#essence-card-budget` |
| `BALANCE_NUMBERS.md` (whole file) | unchanged path |
| `BALANCE_REWORK_SPEC.md §n` | lost; point at the `BALANCE_NUMBERS.md` section for that system |
| `UI_REVAMP §3 "Notify"`, `UI_REVAMP Notify` | `ARCHITECTURE.md#notify` |
| `UI_REVAMP §3 HUD regions` | `ARCHITECTURE.md#hud-regions` |
| `UI_REVAMP §3` (other) | `ARCHITECTURE.md#ui` |
| `UI_REVAMP.md D1 Hybrid / D2`, `UI_REVAMP.md §4`, `UI_REVAMP D12` | `DESIGN_DECISIONS.md#ui-decisions` (`UI-D1`, `UI-D2`, `UI-D12`) |
| `UI_REVAMP.md §5 P7` | `ARCHITECTURE.md#gamepad` |
| `SCALING_AUDIT §SCALE/S5` | `ARCHITECTURE.md#scaling` (pattern: batch per window) |
| `SCALING_AUDIT Deferred #3` | `BACKLOG §SCALE-D3` |
| `SCALING_AUDIT Deferred #5` | closed by `§AGX/X35` |
| `SCALING_AUDIT's Humanoid budget` | `ARCHITECTURE.md#scaling` |
| `AGENCY_CHECKS X10` | `HISTORY` `§AGX/X10` |
| `AGENCY_CHECKS "Receipts checklist"` | `DESIGN_DECISIONS.md#monetization` (receipts rules) |
| `AUDIT_FINDINGS G1` | `DESIGN_DECISIONS.md#assets` |
| `TODO_PARKING_LOT(.md)` | `BACKLOG` (G23): `§V2` → closed; CentralBoss note → `§AGX/X28-NEXT` |
| `docs/ui_audit/*`, `shell-spec §…`, `mobile.md M…`, `structure-and-flow`, `visual-system.md` | **unchanged** (files stay in place) |

## Renamed ids

| Old | New | Why |
|---|---|---|
| `D7` in UI_REVAMP §4 (combat menus as a side sheet) | **`UI-D7`** | Collided with `§DISC/D7` (shop rotation). The code tag `§DISC/D7` and `§AGX/D7` (its implementation) keep their names |
| `D1…D15` in UI_REVAMP §4 | `UI-D1…UI-D15` | Same namespace rule |
| `D1…D8` in T5-T9_SWEEP | `DISC-D1…DISC-D8` in prose (code tag stays `§DISC/Dn`) | Same |
| `DQ-A/B/C` (T0P2) | `T0P2-DQ-A/B/C` | Namespaced in [DESIGN_DECISIONS](DESIGN_DECISIONS.md) |
| `DQ1…DQ4` (AUDIT_FINDINGS) | `G-DQ1…G-DQ4` | Same |
| Untagged TODO items | new ids in [BACKLOG](BACKLOG.md) marked *new id* (`§16-ANIM`, `§SCALE-D1`, …) | Every open item has an id |

Rule for new tags: always write the full prefix (`§AGX/X4`, never bare `X4`). Bare `X`, `V`, `S`, `M`, `D` numbers collide across rounds.

---

## Tag index

Every `§`-tag family in `src/` (275 families at `24c4d7e`, from `grep -rhoE "§[A-Za-z0-9._-]+" src`) resolves through one row below. "Open" items are in [BACKLOG](BACKLOG.md); everything else is closed.

| Tag family | Era / commit | Where it's explained |
|---|---|---|
| `§AGX/X1`…`§AGX/X50`, `§AGX/X3r1…r12`, `§AGX/X10b`, `§AGX/X18b`, `§AGX/X30b`, `§AGX/X4-REASON`, `§AGX/X40-VIP` | Agency checks, 2026-09-25/26 (`f56fa3d`…`b0bdbee`) | [`history/AGENCY_CHECKS.md`](history/AGENCY_CHECKS.md); status in [Closed items](#agency-checks-2026-09-25--26-agx) |
| `§AGX/UX-01…14`, `§AGX/UI-P1…P7`, `§AGX/UI-P1v2`, `§AGX/UI-FIX`, `§AGX/UI-FREE` | UI revamp, 2026-09-26 (`0c93026`…`1cdd3f4`) | [ARCHITECTURE § UI](ARCHITECTURE.md#ui), [`history/UI_REVAMP.md`](history/UI_REVAMP.md), [`ui_audit/`](ui_audit/) |
| `§AGX/T11-JAN`, `§AGX/SEC`, `§AGX/WC`, `§AGX/D7`, `§AGX/BAL`, `§AGX/BTP`, `§AGX/STATS`, `§AGX/D-FIX`, `§AGX/D-FIX2` | Follow-up rounds, 2026-09-26 (`27ab36e`…`24c4d7e`) | Commit messages (`git log --grep "§AGX/<tag>"`); [Closed items](#follow-up-rounds-2026-09-26) |
| `§T0P2/X1…X25`, `§T0P2/G3`, `§T0P2-*` | T0 pass 2 (`0b1f84f`) | [`history/T0_PASS2_SURFACE.md`](history/T0_PASS2_SURFACE.md); open `§T0P2-*` in BACKLOG |
| `§T0-FOLLOWUP/L1…L4` | T0 follow-ups (`0b1f84f`) | [`history/Audit_4.7.md`](history/Audit_4.7.md) §4.2 |
| `§T1`, `§T1.1/D*`, `§T1.2/D*`, `§T1.2/DQ*`, `§T1.3/B*`, `§T1.4/R*`, `§T1.1-JAN*`, `§T1.2-BAL1`, `§T1.3-BAL1`, `§T1.3-DQ2` | T1 audit (`0b1f84f`) | [`history/Audit_4.7.md`](history/Audit_4.7.md) §4.3–§4.6 |
| `§T1.3/Y*`, `§T1.4/Y*`, `§T1P2/Y2`, `§T1P2`, `§T1P2-*` | T1 pass 2 (`0b1f84f`) | [`history/T1_PASS2_SURFACE.md`](history/T1_PASS2_SURFACE.md) |
| `§T2`, `§T2/Z*` | T2 combat (`b291a39`) | [`history/T2_SURFACE.md`](history/T2_SURFACE.md) |
| `§T3/W*`, `§W9a`, `§W9b` | T3 mobs (`b291a39`) | [`history/T3_SURFACE.md`](history/T3_SURFACE.md) |
| `§T4`, `§T4/V*` | T4 death / game flow (`b291a39`) | [`history/T4_SURFACE.md`](history/T4_SURFACE.md) |
| `§T5`, `§T5/S*`, `§T5-T9`, `§T5-T9/S*`, `§T7`, `§T7/G4` | T5–T9 sweep (`b291a39`) | [`history/T5-T9_SWEEP.md`](history/T5-T9_SWEEP.md) |
| `§DISC`, `§DISC/D1…D8` | Discussion batch (`b291a39`) | [DESIGN_DECISIONS § DISC](DESIGN_DECISIONS.md#disc-decisions) |
| `§T10`, `§T10/U1…U4`, `§T10/STACK`, `§T10/ICONS`, `§T10/LIVE1` | T10 UI outcomes (`b291a39`, `28e7fd7`) | [`history/TODO.md`](history/TODO.md) §19 "T10 UI outcomes"; `U4` and `LIVE1` have no doc (the comment is the record) |
| `§PERF`, `§PERF/*`, `§MEM`, `§MEM/*`, `§EASY`, `§EASY/*` | WIP batch (`28e7fd7`) | [`history/HANDOFF_PROMPT.md`](history/HANDOFF_PROMPT.md) (batch list); `§EASY` items in [`history/TODO.md`](history/TODO.md) |
| `§SCALE`, `§SCALE/S1…S6` | Scaling audit (`28e7fd7`) | [ARCHITECTURE § Scaling](ARCHITECTURE.md#scaling), [`history/SCALING_AUDIT.md`](history/SCALING_AUDIT.md) |
| `§BEAUTY` | Asset brief (`28e7fd7`) | [CLAUDE_DESIGN_BRIEF.md](CLAUDE_DESIGN_BRIEF.md) |
| `§PDM-D*`, `§CFG-D*`, `§CFG-D1.`, `§PB-D*`, `§NM-D*`, `§RG-D*`, `§RG1`, `§RG2`, `§MS-INIT1`, `§CC-*`, `§PERSIST1`, `§HUD-HP1`, `§NM-CLIENT-RACE`, `§FRENZY1`, `§DR-2`, `§DangerBonus`, `§CONFIG`, `§VEM-DEDUPE`, `§14b`, `§14` | T0 / v0.5 session (`66503b4`) | `git show 66503b4:docs/TODO.md`; most have no other doc. Open ones: `§NM-D6` closed, `§PB-D3` closed, `§PDM-D11` open |
| `§L1…L11`, `§LD1…LD4`, `§LD-*` (except `§LD-VE*`, `§LD-W*`), `§VM1…VM4`, `§HMS*`, `§HMS-DIR*`, `§CB1`, `§CB3`, `§U*` | SANITY V3 (pre-v0.5) | `git show d862558:docs/SANITY_CHECK_REPORT_V3.md` (`§CB1` is now `§AGX/X28-NEXT`) |
| `§A1…A3`, `§A2b`, `§S1…S5` (bare), `§Sh1…Sh3`, `§G2`, `§D2`, `§Dr1`, `§AM1…AM7`, `§DL1`, `§HM1…HM12`, `§LN1`, `§NM3`, `§QH1…QH6`, `§ER*`, `§ET*`, `§WB1`, `§AB1`, `§SR1`, `§EV1…EV11`, `§EH1`, `§UI2`, `§UI3`, `§UI-T1…T4`, `§LB2`, `§LB3`, `§VG1…VG5`, `§V2`, `§C*` | SANITY V4 / V4 Phase A (pre-v0.5) | `git show d862558:docs/SANITY_CHECK_REPORT_V4.md` (and `_V4_PHASE_A.md`); `§V2` is TODO §9 AttachClassArmor |
| `§LD-VE*`, `§LD-W*` | Syntax-damage report (pre-v0.5) | `git show d862558:docs/SYNTAX_DAMAGE_REPORT.md` |
| `§D7`, `§Combat`, `§Combat.`, `§33`, `§48`, `§29` *after "BALANCE_NUMBERS"* | Old BALANCE section numbers | [BALANCE § Old section numbers](BALANCE_NUMBERS.md#old-section-numbers) |
| `§5`, `§5.1…§5.6` *after "Audit_4.7" or "pattern"* | Audit_4.7 §5 house patterns | [ARCHITECTURE § House patterns](ARCHITECTURE.md#house-patterns) |
| `§1`, `§3`, `§5`, `§11`, `§14`, `§14b`, `§17` *after "TODO"* | Old TODO sections | [`history/TODO.md`](history/TODO.md); open items in BACKLOG |
| `§0.2`, `§2`, `§2.1…§2.7`, `§3.1…§3.8`, `§4.1…§4.6` *in `UI/Shell`, `UI/HUD`, `UI/Common` files* | UI shell build spec | [`ui_audit/shell-spec.md`](ui_audit/shell-spec.md) (same section numbers) |
| `§2.1a…§2.8c`, `§2.1-`, `§2.2…§2.7c`, `§3.2.3`, `§3.2.6`, `§3.x`, `§1.3` *in server gameplay files* | SANITY V1/V2 section numbers (pre-v0.5) | `git show d862558:docs/SANITY_CHECK_REPORT.md` / `_V2.md` (`§1.3` "armor-XP removed" is V1 §1.3) |
| `§4`, `§4.2…§4.6`, `§4.4-`, `§6`, `§10`…`§13`, `§17`…`§21`, `§29.`, `§29.1`, `§30.1…§30.4`, `§31`, `§36`, `§40`, `§40.2`, `§42.1`, `§47.1…§47.3`, `§48` (as "Consumable Rework"), `§52.3` *in config / economy / data files* | BALANCE_REWORK_SPEC.md (**never in git**) | Lost. The value is in [BALANCE_NUMBERS](BALANCE_NUMBERS.md) under the same system; the comment must carry its own "why" |

**No tag family was retired.** Keep old tags in code (they're grep-able); don't add new bare-number tags.

---

## Tier roadmap

From `Audit_4.7.md` §2. Every tier is closed.

| Tier | Scope | Closed in |
|---|---|---|
| T0 | Bootstrap, network, ReadyGate, persistence | `66503b4` (v0.5 + T0), pass 2 `0b1f84f` |
| T1.1–T1.4 | CharacterManager + Janitor, ClassManager, Stats/BonusManager, ResourceManager | `0b1f84f`; pass 2 (Y1–Y12) same commit |
| T2 | Combat: AttackHandler, HitTracker, SkillManager | `b291a39` (Z1–Z9) |
| T3 | Mobs: MobAI, spawners | `b291a39` (W1–W9) |
| T4 | Death / game flow | `b291a39` (V1–V3) |
| T5–T9 | Votes, equipment, lobby, progression, shop/NPC | `b291a39` (S1–S6, G4, DISC D1–D8) |
| T10 | UI | UI revamp P0–P7 + review fixes, `0c93026`…`e1524b9`; SocialPanel `1cdd3f4` |
| T11 | Cross-cutting: Janitor audit, balance, hang-recovery UI | `27ab36e`, `272ab8e`, `1cdd3f4` |

After the tiers: the agency-checks round (X1–X50, `f56fa3d`…`b0bdbee`) and the follow-up rounds below (`b5d4656`…`24c4d7e`).

---

## Closed items

One line each: id · what landed · commit. Open items are in [BACKLOG](BACKLOG.md).

### Follow-up rounds (2026-09-26)

- `§AGX/D-FIX2` · Healer gear rolls and class-resource bonuses apply; Arcanist/Hunter armor roll mana/focus; no Horde vote over Defeat/Victory; start gate waits for data-ready; PartyAura finds the Lobby PartyManager · `24c4d7e`
- `§AGX/D-FIX` · Lazy getters that always returned nil (`x and pcall(...)` truncation) fixed in 11 places; keystone/shop/aura review fixes · `7f3e503` (first round `ebc7d5e`)
- `§AGX/STATS` / `§AGX/BAL-UNREAD` · Readers for MovementSpeed, AttackSpeed, AoESize, CDR, CastTimeReduction, StatusResistance; Swiftness Elixir live · `a2bf7a0`
- `§AGX/X11-RULES` (12 of 15) · Keystone rules + party auras (Spell Rhythm, Patron Saint, Fortune Favors); remaining 3 in BACKLOG · `272ab8e`, `99ca350`
- `§AGX/BTP` / TODO §3 BonusTalentPoints dead branch · +1 point from 4 achievements, ledger-guarded · `99ca350`
- `§AGX/BAL` · Vulnerability ×2.0, armor-shred 0–50%, Penetration 60 and Lifesteal 25 enforced; no class CritDamage scaling · `272ab8e`, docs `5f86d9e`
- `§T1.3-BAL1` · Mending Touch 2.1, Verdant Bloom 1.25, HoT through the heal pipeline · `272ab8e`
- `§T1.2-BAL1` · No class scales CritDamage · `272ab8e`
- TODO §1 `[??]` multi-crit cap · 2 procs max, already live (`CriticalSystem.lua:18-19`) · `272ab8e`
- TODO §1/§18 `[??]` vulnerability cap · ×2.0 (`DamageSystem.lua:22`) · `272ab8e`
- TODO §1/§18 `[??]` ArmorReduction floor · 50% cap (`DamageSystem.lua:26`) · `272ab8e`
- TODO §2 `[??]` Genesis 70 vs 80 · stale: every ultimate needs 100 · —
- `§DISC/D7` / `§AGX/D7` · Per-player deterministic shop rotation + paid Essence refresh · `bd16d15`
- `§AGX/WC` · Party start gate, party-class consumer (`§T0P2-TPCLASS`), lore persistence, stuck-lock fixes · `a3cc04b`
- `§PB-D3` all-players-ready gate · `a3cc04b`; timeout from player presence `7f3e503`; waits for data-ready `24c4d7e`
- TODO §13 quest & lore persistence · quests in `d862558`, lore flags `a3cc04b`
- `§T0P2-TPCLASS` · `ClassManager.ApplyTeleportClass`, unlock-checked · `a3cc04b`
- `§14b` Wave C follow-ups · `SkillCooldownUpdate` ReadyGate-routed (`a2bf7a0`); reroll lock can't stick (`a3cc04b`)
- `§AGX/X10-CONSUMABLES` / `§AGX/X10b` · Consumable use handlers + Inventory Use button · `cfb1053`; Swiftness `a2bf7a0`
- `§AGX/UI-FREE` · Hang-recovery Rejoin banner (`§NM-D6`), lobby return reason (`§AGX/X4-REASON`), VIP chat tag (`§AGX/X40-VIP`), SocialPanel re-skin (`§T10/U3`) · `1cdd3f4`
- `§T1.1-JAN1` / `§T1.1-JAN2` · Janitor leak audit + telemetry · `27ab36e`, `b12f034`
- `§AGX/SEC` · Admin/debug surface Studio-only (closes `§T0P2-ADMIN` by gating, not by a console module); `BootProfiler.ENABLED = false`; `.venv/` ignored (G24) · `d5e052b`
- `§AGX/X27-OBO` · HighestWave = highest wave/level **completed** in both modes · `d5e052b`
- `§T0P2-ORPHANS` · Dead `HealNumber` event removed (heals use `HealNumberBatch`); the 4 equipment events were never orphans · `3741f10`
- `G16`, `G18` · `foreman.exe`, `Leg.obj`, `Leg.mesh` untracked and ignored · `3741f10`
- `§AGX/X18b` · Veteran: one free appearance change at level 50, then paid · `b0bdbee`
- Backlog reconcile with the agency-checks session · `b5d4656`

### Agency checks (2026-09-25 / 26, `§AGX`)

- `X1` Horde spawned zero mobs (nil forward reference) · `f56fa3d`
- `X2` BindToClose waits for in-flight leave-saves · `09e4a5a`
- `X3` Session-locked `UpdateAsync` saves, final-save retry, 60 s autosave; hardened `X3r1…r12` · `09e4a5a`, `8fd1301`
- `X4` Reserved match servers; public combat servers bounce to Lobby (live test open: `§AGX/X4-LIVE`) · `2329bbd`
- `X5` No pre-game wave farming · `d4cf212`
- `X6` TeleportData `modeId` / lobby id / level floor no longer trusted · `2329bbd`
- `X7` Server-side Horde pause gate · `36cd218`
- `X8` `SaveKeybindings` validated and size-capped · `09e4a5a`
- `X9` Refine pity clamped to the chapter cap; temper kept · `f56fa3d`, `a1acbd2`
- `X10` Unusable consumables refused on the server · `36cd218`
- `X11` Keystone penalties neutralised until rules exist · `36cd218` (rules: see above)
- `X12` DoT/Thorns kills rewarded and cleaned up · `abdd002`
- `X13` Roar + GroundSlam no longer leave players slowed · `f56fa3d`, `a1acbd2`
- `X14` Teleport failures handled (TeleportInitFailed, timeout, Retry) · `2329bbd`
- `X15` Party changes cancel the queue · `2329bbd`
- `X16` Critical `Init()` failure fails boot hard · `f56fa3d`
- `X17` Dash NaN guarded; fail-closed range checks · `f56fa3d`
- `X18` Appearance change behind a flag (`GrantAppearanceChange`) · `3b4d39d`
- `X19` CentralBoss hidden (`available = false`) · `f56fa3d`
- `X20` `ResourceUpdate` only on change · `f56fa3d`, `a1acbd2`
- `X21` `SkillActivated` / visuals range-scoped · `cc776f2`
- `X22` XP HUD pushes batched · `abdd002`, `cc776f2`
- `X23` Temper pity docs match code · `78392c0`
- `X24` NPC shop built from `ShopConfig` · `36cd218`
- `X25` Docs/code mismatches (difficulty, waves, votes, daily login, tiers) fixed · `78392c0`
- `X26` Dev extension escapes asset names · `f56fa3d`
- `X27` HighestWave / PlayTime leaderboards written · `cc776f2`
- `X28` CentralBoss core fight (Iron Warden placeholder); party kill credit · `b19cec8`, `25c6784` (next steps open: `§AGX/X28-NEXT`)
- `X29` NPC responses range-checked · `f56fa3d`
- `X30` / `X30b` Vote index validated; no double resolve · `f56fa3d`, `a1acbd2`
- `X31` `lookDirection` validated · `f56fa3d`
- `X32` Refunds ignore MeritBonus · `36cd218`
- `X33` Spend rejects negative/NaN · `f56fa3d`
- `X34` `PurchasePremium` checks `enabled` · `36cd218`
- `X35` Breach dissolve on the client; `DefenseLineDamaged` throttled (SCALING Deferred #5) · `cc776f2`
- `X36` Spawn lookup cached · `f56fa3d`
- `X37` Defense regen notify fixed · `cc776f2`
- `X38` Horde character waits bounded · `f56fa3d`, `a1acbd2`
- `X39` Daily login claim rolls back on failure · `3b4d39d`
- `X40` Wipe-revive 3/2/1 free + 1 paid; no Robux for gameplay currency · `3b4d39d`, `cdba264`, `1c6e333`
- `X41`, `X42`, `X43` Economy pass (card Essence, 250:1 anchor, softer endgame refine) · `78392c0`
- `X44` Personal party drops · `abdd002`
- `X45` Server-owned mob physics · `668316b`
- `X46` PolicyService · not required while nothing paid is random or tradable; tripwire `§AGX/X46-GUARD` in BACKLOG · `1c6e333`
- `X47` Daily login calendar + spree · `3b4d39d`
- `X49` Tools key/path hygiene · `668316b` (key rotation `G20` open)
- `X50` Paid wipe-revive soft-lock (nil forward reference) · `f56fa3d`
- `X48` onboarding: **open**, parked (BACKLOG 🚀)

### Repo-wide pass (2026-06-12, `G`)

- `G1` `.rbxmx` untracked · won't fix, by design ([DESIGN_DECISIONS § Assets](DESIGN_DECISIONS.md#assets))
- `G2` TeleportData validated · `0b1f84f`, `2329bbd`
- `G3` Boot `WaitForChild("Modules", 10)` + error · `0b1f84f`
- `G4` Teleport retry · `b291a39`, `2329bbd`
- `G5` ReadyGate overflow kicks (T0P2-DQ-A) · `0b1f84f`
- `G6` Party level re-anchored on every data-ready · `b291a39`
- `G7` Mob-skill multiplier order · refuted at T3
- `G9` MaxLevelGap single source (`PartyRequirements`) · `b291a39`
- `G10` `WireOnPlayerReady` latch · `0b1f84f`
- `G11` HitTracker unsubscribe · won't fix
- `G12` Ticket flood · refuted at T2
- `G13` MobAI pending tables purged · `b291a39`
- `G14` Dead players earn no kill XP · `b291a39`
- `G15` VoteManager nil guard · `b291a39`
- `G16`, `G18` · `3741f10`
- `G17` `sourcemap.json` untracked · before 2026-09-26
- `G19` One EmoteWheel · `beff2df`
- `G24` `.venv/` ignored · `d5e052b`
- `G25` Client listener hang · mitigated by the `§NM-D6` watchdog · `1cdd3f4`
- Open: `G8`, `G20`, `G21`, `G22`, `G23` (BACKLOG)

### Discussion batch (`§DISC`)

- `DISC-D1` Respec scroll acquisition confirmed (shop + fragments) · `b291a39`
- `DISC-D2` Party = everyone in the battle map · decision; persistence is BACKLOG 🚀
- `DISC-D3` Party wipe → pause → defeat, now with wipe-revives · `b291a39`, `3b4d39d`
- `DISC-D3b` Robux wipe-revive product · **won't do** (X40)
- `DISC-D4` Bonus-XP clamps (source ≤ +100%, total ≤ 3.0×) · `b291a39`
- `DISC-D5` Achievement source is core · open (BACKLOG `§DISC/D5`)
- `DISC-D6` `PartyRequirements` shared gate · `b291a39`
- `DISC-D7` Shop rotation + refresh · `bd16d15`
- `DISC-D8` NPC UIs auto-close on walk-away (`useNpcDistanceClose`) · `b291a39`, `36cd218`

### TODO and Audit_4.7 items

- `§EV12` wrong-name emitters · moot (only in disabled legacy controllers; list kept for `§T10/STACK`)
- `§SR2` SkillRegistry off Lobby/SocialPlaza loadlists · `66503b4`
- `§UI1`, `§UI2`, `§UI3` · resolved/moot (React panels; `§UI3` mountedRef guard `28e7fd7`)
- `§V2` AttachClassArmor wired · `28e7fd7` (§EASY/E3); art open as `§V2-ART`
- `§VEM-DEDUPE` double attach root-caused · `b291a39` (§T5-T9/S6); 1× check is in `§AGX/STUDIO`
- `§RG-MIGRATION` · Weapon/Armor/Achievement pushes ReadyGate-routed; Wardrobe/Equipment are request/response by design · `66503b4`
- `§T1.1/D7` CharacterCreationRequired via ReadyGate · `0b1f84f`
- `§AM4` Horde wave achievements · `28e7fd7`, `cc776f2`
- Per-remote rate-limit audit · closed by `§NM-D1` · `66503b4`; tuned by `§SCALE/S6` `28e7fd7`
- `§NM-D6` hang-recovery UI · `1cdd3f4`
- OnReady → loading-screen dismiss · `§T10/U1` · `b291a39`
- `§G5` late joiner stale state · `0c93026` (§AGX/UX-02)
- `§HM3-followup` · `66503b4` (§PB-D3)
- Ultimate unlock gate · `28e7fd7` (§EASY/E1); level question open as `§ULT-LEVEL`
- Class unlock toast · `28e7fd7`, ReadyGate `27ab36e`
- `§T1.1` template fan-out by body model · `0b1f84f`
- HitTracker.SaveLifetimeStats stub removed · `b291a39` (§T1.4/Y5)
- DataStore save reliability · `09e4a5a`, `8fd1301`
- TODO §3 / §17 "300-node talent redesign" · stale: the 300-node tree is live in `TalentTreeConfig.lua`
- TODO §3 Class Mastery XP source · merged into `§T0P2-MASTERY`
- TODO §18.3 HealingSystem uses Damage · by design; split tracked as `§T1.3-DQ2`
- TODO §18.6 re-enable weapon/armor XP · stale: weapon XP is live, armor XP was removed
- `§T0P2-RESPEC-SCROLL` main chain · `b291a39`; balance remainder open
- `§T1P2-HITTRACKER` · won't fix (Y6)
- `§T10/U1` LoadingScreen, `§T10/U2` TalentTreeUI rework · `b291a39` (U2 follow-ups open)
- `§T10/U3` window standardization · `05c1b9e`, `582dff1`, `5718f59`, `1cdd3f4`
- `§PERF/BP` BootProfiler · `28e7fd7`; off for shipping `d5e052b`
- `§AGX/UI-P3/P5 W6` · folded into `§AGX/STUDIO`
- `§DISC/D6`, `§DISC/D8` · built · `b291a39`
- Audit_4.7 §6.1–§6.9 tier plans · all tiers closed (see [Tier roadmap](#tier-roadmap))
- Audit_4.7 §7 DQ3/DQ5 · answered by `§AGX/BAL`
- `§T1P2-STACKS` mechanism · `b291a39` (§T2/Z9); the balance call stays open

### Scaling audit (`§SCALE`)

- `S1` Horde markers positioned on demand · `28e7fd7`
- `S2` Mob cast events range-scoped (150 studs) · `28e7fd7`
- `S3` `MobDeath` range-scoped · `28e7fd7`
- `S4` MonitoringSystem allocations, `SAMPLE_RATE` · `28e7fd7`
- `S5` DoT/HoT numbers batched every 0.25 s · `28e7fd7`
- `S6` Per-event rate limits for state-machine events · `28e7fd7`
- Deferred #5 · `§AGX/X35` `cc776f2`

### Tier surfaces

Per-id detail is in the surface files; all landed unless noted.

- **T0 pass 2** `§T0P2/X1…X25` · `0b1f84f`. Kept as seams: X20 (TeleportClass, now consumed), X22 (DeallocateStat). X16 → `§T0P2-ADMIN`, closed by `d5e052b`
- **T1 pass 2** `Y1…Y12` · `0b1f84f`. Y1 → `§T1P2-PEN` (open); Y6 won't fix; Y9, Y10 left as-is
- **T2** `§T2/Z1…Z9` · `b291a39`. Z4 won't fix (effects land even if the caster leaves)
- **T3** `§T3/W1…W9` · `b291a39`
- **T4** `§T4/V1…V3` · `b291a39`
- **T5–T9** `S1…S6`, `§T7/G4` · `b291a39`
- **T1** `D`, `B`, `R` ids (Audit_4.7 §4.3–§4.6) · `0b1f84f`
- **T0 / v0.5** SANITY V1–V4 ids (`§A1-A4`, `§S1-S5`, `§T1-T2`, `§G2`, `§D2`, `§Sh1-Sh3`, `§Dr1`, `§AM1/AM7`, `§DL1-DL3`, `§HM*`, `§LN1`, `§NM3`, `§QH1-QH6`, `§ER/ET/WB/AB`, `§SR1`, `§EV1-EV11`, `§EH1`, `§UI-T*`, `§LD-*`, `§LB2/LB3`, `§PERSIST1`, `§VG2-VG5`, `§HMS-DIR1-3`, `§FRENZY1`, `§NM-CLIENT-RACE`, `§A2/A3`) · `d862558`, `66503b4`

---

## Old live-test ledger

From `Audit_4.7.md` §9. These T1 smoke tests predate [STUDIO_TEST_PLAN.md](STUDIO_TEST_PLAN.md); keep them in mind for a full regression pass.

- **T1.1:** new save → creation panel appears in every place; existing save spawns with the right gender/skin; admin SetGender respawns with template, hair and weapon; Janitor size stable over 50 respawns.
- **T1.2:** fresh save has 4 classes; class switch in Lobby passes GameStateManager silently; switch in the first second of Horde hooks WeaponManager; no `[ClassConfig] missing required derived stat` warns.
- **T1.3:** PowerSurge twice → full second duration; no `[BonusManager] Rejected write to unknown stat` warns.
- **T1.4:** regen pauses during votes; hit → ResourceManager hook fires (Arcanist +6 per kill, Hunter +0.6 per hit).
