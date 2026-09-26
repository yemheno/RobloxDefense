# Handoff prompt — paste into Claude Code (VS Code terminal)

> Setup: open the repo folder in VS Code, open the integrated terminal,
> run `claude`, then paste everything below the line as your first message.

---

You are picking up a mature, mid-flight collaboration on **RobloxDefense** — a
Roblox tower-defense/RPG (Rojo 7.6.1 + Luau + react-lua 17, five Places:
Lobby, LaneDefense, HordeMode, CentralBoss, SocialPlaza) heading to first
alpha. A previous Claude session ran a complete tiered audit and a large
improvement campaign. Your job is to continue it seamlessly.

## Read these first, in order
1. `Audit_4.7.md` — the canonical handoff: tier-by-tier methodology, roadmap
   (T0–T10 all closed), house principles, session history.
2. `docs/TODO.md` — living backlog. §-tags (e.g. §T0P2/X4, §SCALE/S2) are
   audit lineage markers used in code comments — grep them to find context.
3. `docs/SCALING_AUDIT.md` — scenario math (world boss / massive horde /
   siege), fixes §SCALE/S1-S6, deferred items ranked.
4. `docs/CODEBASE_REVIEW.md` and `docs/CLAUDE_DESIGN_BRIEF.md`.

## Working agreement with Pablo (owner) — follow exactly
- Pablo decides design; you decide code. One closed system per commit.
- **Pablo commits from his terminal** after HE live-tests in Roblox Studio.
  You never commit unless he says so.
- Standing rule: when he reviews a findings list, items he doesn't mention
  = "please fix". Fixes that are direct and don't change functionality may
  be applied without asking. Design-affecting changes are discussed first.
- Surface findings in numbered batches (X1..Xn style) for his sign-off.
- Loud-at-boot over silent drift; single source of truth; §-tag every fix.
- Agent/subagent findings are ~50% wrong: VERIFY every claim in the actual
  code before fixing. Several "obvious" optimizations were traps (e.g. the
  AttackShapes workspace-root scan finds PLAYER characters — load-bearing;
  horde spawn markers are resizable Parts BY DESIGN, §T3/W9b).
- Asset policy: `.rbxmx` stay out of git by design (managed in Studio).
  `assets/ui/` PNGs are committed. `.env` holds a Roblox Open Cloud key —
  never commit it; rotation has been recommended to Pablo.

## Current state — IMPORTANT
There is a **large uncommitted batch** on top of the last commit. It is
code-complete and host-verified but only partially AST-parse-verified
(the previous environment had a file-sync defect; you have direct FS
access, so verify properly now). The batch contains, roughly:
easy-TODO fixes (§EASY/E1-E7), UIParticles + LightningBar + HUD mana bar,
BootProfiler (§PERF/BP) + hooks in PlaceBootstrap/PlaceLifecycle/
PlayerDataManager/ReadyGate + all 10 client scripts, memory pass
(§MEM/M1-M11), MobAI snapshot + spectator cache (§PERF/F1,F4), Tibia
damage-number batching (§PERF/F5) + pooled DamageNumbers v2 (§PERF/F6,
split own/ally budgets, 0.05 s ally stagger), scaling fixes (§SCALE/S1-S6),
and docs (SCALING_AUDIT, CLAUDE_DESIGN_BRIEF, TODO updates).

**Your first task:**
1. `git status` + `git diff --stat` — review the batch shape.
2. Syntax-verify every modified `.lua` with a REAL Luau parser (install
   `luau-lsp` or use `stylua --check`, or `luau --parse` if available —
   do not use vanilla-Lua parsers, the code uses `continue`, `+=`,
   if-expressions, type annotations).
3. Report anything broken; fix; then hand to Pablo for a live test of:
   armor visual attach (DefaultArmor at ServerStorage.Models.Armors),
   ultimate gate at level 10, class-unlock toast, mana-bar lightning,
   BootProfiler dumps (Output + ServerStorage.BootProfile_SERVER),
   damage numbers (merged `x N`, ally 0.05 s stagger, crits, DoT/heals),
   mob combat regression (targeting/taunt/range — MobAI was refactored),
   horde spawning (markers repositioned on demand now).
4. After his test passes, HE commits.

## Open work queue (task ids from the previous session)
- **#15 Beauty pass**: Pablo bulk-imports `assets/ui/` (27 PNGs) in Studio,
  pastes asset ids into `UI/Common/Theme.lua` (Theme.Icons ×16 +
  Theme.Images ×11, slice rects pre-filled). Then restyle buttons/bars
  onto the 9-slice plates; LightningBar picks up barFrame/barShine/pSpark
  automatically via Theme.GetImage.
- **#18 Talent tree v3**: current radial layout too clumped (screenshot
  confirmed). Plan: PoE-style orbit groups — tag-clusters as groups on
  the existing BFS rings/sectors, members on fixed mini-orbits at angular
  slots, then a few force-relaxation iterations (repulsion + edge springs
  + soft radius constraint). File: `UI/TalentTreeUI.lua`.
- **Scaling deferred** (docs/SCALING_AUDIT.md, ranked): mobs →
  `workspace.Mobs` folder + AttackShapes folder-scan (biggest CPU win,
  needs careful parenting-assumption pass); VitalsUpdate O(P²) → hp
  attributes; AttackFired range-scoping; knockback LinearVelocity pooling;
  non-Humanoid movers decision before any 250-mob horde mode.
- **Bug to investigate**: VisualEquipmentManager still logs AttachClassWeapon
  ×2 on spawn (2 ms apart — suspect CharacterAdded wiring + starter-weapon
  echo both attaching; §VEM-DEDUPE in TODO).
- **Pre-release**: remove admin remote surface (§T0P2-ADMIN, P0/Security);
  set BootProfiler `ENABLED=false`; alpha blockers in TODO §16 (animations,
  mob variety, 28 sounds).

## Suggested housekeeping once settled
Create a `CLAUDE.md` at repo root distilling the working agreement +
§-tag convention + read-first list above, so every future session
auto-loads it.
