# Docs index

| Doc | For | What's in it |
|---|---|---|
| [../README.md](../README.md) | everyone | What the game is, places, toolchain, setup |
| [../CLAUDE.md](../CLAUDE.md) | agent sessions | The rules: who decides, house patterns, decided-against, tags, Luau pitfalls, compile check |
| [ARCHITECTURE.md](ARCHITECTURE.md) | agents, Pablo | Places and boot, network, ReadyGate events, BonusManager sources, house patterns, decided against, persistence, scaling, UI shell, file tree |
| [SYSTEMS.md](SYSTEMS.md) | Pablo, agents | How each gameplay system works (no numbers) |
| [BALANCE_NUMBERS.md](BALANCE_NUMBERS.md) | Pablo, agents | Every tunable number, in the same system order as SYSTEMS. The code wins |
| [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md) | Pablo | Pablo's calls with their ids: principles, monetization, DISC-D*, UI-D*, tier DQs |
| [BACKLOG.md](BACKLOG.md) | Pablo, agents | Every open item once, by priority; questions waiting on Pablo |
| [STUDIO_TEST_PLAN.md](STUDIO_TEST_PLAN.md) | Pablo | Ordered Studio checklist for everything not yet tested |
| [HISTORY.md](HISTORY.md) | agents | Moved files, doc-reference remap, renamed ids, **tag index**, closed items |
| [CLAUDE_DESIGN_BRIEF.md](CLAUDE_DESIGN_BRIEF.md) | Pablo (tool) | Prompt pack for UI icon/asset generation (§T10/ICONS, §BEAUTY) |

## Folders

- **[`ui_audit/`](ui_audit/)**: the four UI audits and the shell build spec from the 2026-09-26 revamp (`mobile.md`, `structure-and-flow.md`, `visual-system.md`, `shell-spec.md`). **Frozen, as built.** They stay at these paths because about 87 code comments cite them (`shell-spec §4.2`, `mobile.md M9`, …). Their design questions are answered in [DESIGN_DECISIONS § UI](DESIGN_DECISIONS.md#ui-decisions); the live summary is [ARCHITECTURE § UI](ARCHITECTURE.md#ui).
- **[`history/`](history/)**: superseded docs, moved unchanged (audit handoff, old TODO, agency checks, tier surfaces, the old game documentation, …). Read-only. See [HISTORY § Moved files](HISTORY.md#moved-files).

## Rules

- One home per fact: numbers in BALANCE_NUMBERS, mechanics in SYSTEMS, open work in BACKLOG, decisions in DESIGN_DECISIONS, the past in HISTORY.
- Don't add new top-level docs; extend one of the above. Don't edit files in `history/`.
