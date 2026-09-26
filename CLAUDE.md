# CLAUDE.md

Rules for agent sessions on RobloxDefense (Roblox, Rojo 7.6.1, Luau, react-lua 17, five places). Read this, then [docs/README.md](docs/README.md). Details live in the linked docs; this file is only the rules.

## Who decides

- **Pablo owns the vision:** game design, mechanics, anything a player would notice as a design change, and monetization. When unsure whether something is design or implementation, ask him as a numbered design question.
- **Agents own code, balance and security:** implementation, refactors, tuning numbers inside the agreed design, and fixing security issues.
- **Unmentioned = fix:** when Pablo reviews a numbered findings list, items he doesn't mention are approved. Direct fixes that don't change behaviour may land without asking.
- **Commits only when Pablo asks.** He live-tests in Studio. In orchestrated sessions he has asked the orchestrator to commit and push each verified batch to `dev`; sub-agents never run git write commands (commit, amend, stash, reset, `add`).
- **Verify agent claims** in the code before acting on them; about half of subagent findings have been wrong.

## Read first

1. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): places, network, ReadyGate, BonusManager sources, **house patterns**, **decided against**.
2. [docs/BACKLOG.md](docs/BACKLOG.md): open items and the questions waiting on Pablo.
3. [docs/BALANCE_NUMBERS.md](docs/BALANCE_NUMBERS.md) before touching any number; [docs/SYSTEMS.md](docs/SYSTEMS.md) for how a system works.
4. [docs/STUDIO_TEST_PLAN.md](docs/STUDIO_TEST_PLAN.md): nothing since `0e6d15e` has run in Studio.

## House patterns

Follow them; cite the anchor in comments. Full text: [ARCHITECTURE § House patterns](docs/ARCHITECTURE.md#house-patterns).

| Pattern | Anchor |
|---|---|
| Per-player lifetime in a labelled, weak-keyed Janitor; guard double wiring | `ARCHITECTURE.md#janitor-per-player` |
| Per-character Janitor with `LinkToInstance` | `#janitor-per-character` |
| Lazy getter, `false` = looked-not-found, two-step `pcall` | `#lazy-getter` |
| Hot-path: resolve once, cache the function ref | `#hot-path-ref-cache` |
| Boot-time server pushes via `ReadyGate.FireClient` | `#readygate-pushes` |
| One module owns a catalog; others derive | `#single-source-of-truth` |
| Loud at boot (warn/error at load), never silent drift | `#loud-at-boot` |
| Grep `src/` for any removed name; deprecated-key sweep for removed save fields | `#stale-callsite-grep` |

## Decided against

Don't reopen these unless Pablo does ([full list](docs/ARCHITECTURE.md#decided-against)):

- Don't "simplify" the hair-accessory weld dance in CharacterManager.
- Sub-agents don't run git write commands; only the session Pablo asked to commit does.
- Don't add a `Validate()` patch for `statDerivation`; the `DerivedStats` catalog is the approach.
- Don't put per-class resource definitions into ClassConfig (they live in `ClassBehavior.CONFIG`).
- Don't remove the empty `Init()` stubs in ClassBehaviors.
- Kept seams: `DeallocateStat`, the TeleportClass path, empty client `ServerReady` handlers, the `achievement` bonus source, `.rbxmx` out of git, the AttackShapes workspace-root scan.

## Tags

- Every fix gets a `§`-tag in its comment, with the **full prefix**: `§AGX/X4`, `§T0P2/X9`, `§SCALE/S2`, never a bare `X4` or `§4.2` (ids collide across rounds).
- One tag line per block, e.g. `-- §AGX/X3, §T0P2/X6`. Grep a tag before concluding something is a bug.
- New work gets a new family or an id from [BACKLOG](docs/BACKLOG.md). Every existing family resolves in [HISTORY § Tag index](docs/HISTORY.md#tag-index).
- Code `TODO` comments cite a BACKLOG id. No `file.lua:NN` pointers in comments (they go stale); name the function or module.
- Comments keep the **why** and the invariant in present tense; bug narratives go to HISTORY or the commit message.

## Luau pitfalls

- **Never `local ok, r = mod and pcall(require, mod)`.** `and` truncates `pcall` to one value: `ok = true`, `r = nil`. Write `local ok, r = false, nil; if mod then ok, r = pcall(require, mod) end` (§AGX/D-FIX: 11 getters always returned nil).
- **A local function called above its definition is a nil global** at runtime (no error until the call). Forward-declare (`local f` at the top, `f = function … end` below) or move it up (§AGX/X1 Horde spawned nothing; §AGX/X50 paid revive soft-locked).
- `x and y or z` returns `z` when `y` is `false`/`nil`.
- NaN passes `>`/`<` checks: write range checks as `not (d <= max)` and validate client numbers with `v == v`.
- Weak-keyed tables (`__mode = "k"`) for anything keyed by Player or Instance.

## Compile check

Run on every touched `.lua` file before handing back (the Luau CLI from the official releases):

```bash
luau-compile --text path/to/File.lua > /dev/null   # syntax: non-zero exit = broken
luau-analyze path/to/File.lua                       # look for "Unknown global" on your own locals
```

`luau-analyze` reports many Roblox globals as unknown; only the names you wrote matter. Also grep for removed names (stale call sites). Report what you checked; Studio testing is Pablo's.

## Docs

- Numbers live only in [BALANCE_NUMBERS](docs/BALANCE_NUMBERS.md); the code wins when they disagree. Update the doc in the same change as the number.
- Open work goes in [BACKLOG](docs/BACKLOG.md) (keep ids); closing an item moves one line to [HISTORY](docs/HISTORY.md#closed-items).
- Pablo's decisions: [DESIGN_DECISIONS](docs/DESIGN_DECISIONS.md). Don't narrate history outside HISTORY.
