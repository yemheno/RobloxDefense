# RobloxDefense — Full Codebase Review (Operational)

> Per `full-code-review-prompt.md`. Evidence-only; unverifiable areas are
> marked **unspecified**, not guessed. Context: Project **RobloxDefense**
> · Engine **Roblox (Luau)** + Rojo file-sync workflow · Platforms:
> PC confirmed, mobile intended (Scale-based UI throughout) — see
> Unspecified · Focus: **full review**. Reviewer state: this session has
> already performed a deep functional audit (T0–T10, see Audit_4.7.md);
> this review covers the OPERATIONAL layer around that code.

---

## 1. Version matrix (as pinned in the repo)

| Component | Version | Evidence |
|---|---|---|
| Rojo (sync/build) | **7.6.1** | `foreman.toml` |
| Remodel | 0.11.0 | `foreman.toml` |
| Wally (pkg mgr) | 0.3.2 | `foreman.toml` |
| React (react-lua) | **17.0.2** (jsdotlua) | `wally.toml`, `wally.lock` |
| ReactRoblox | 17.0.2 (jsdotlua) | `wally.toml`, `wally.lock` |
| Transitive deps | fully locked (jsdotlua 1.2.7 family) | `wally.lock` (committed ✓) |
| Roblox engine | evergreen (platform-controlled) | n/a — not pinnable |
| Studio project settings | **unspecified** (live in the published place, not the repo) | — |

Places: 5 (`lobby/lanedefense/hordemode/centralboss/socialplaza` ×
`.project.json`), PlaceIds centralized in `Shared/init.lua:68-74`.

## 2. Subsystem & ownership map

Solo-owner project (Pablo). Boundaries are clean and documented:

| Layer | Location | State |
|---|---|---|
| Server core (data, network, boot) | `Modules/` (PlayerDataManager, NetworkManager+manifest, ReadyGate, PlaceBootstrap/Lifecycle) | audited T0×2 |
| Combat | AttackHandler, SkillManager, SkillEffects, ClassSkills | audited T2 |
| Mobs/spawning | MobAI, MobSpawner, HordeModeSpawner, MobSpawnHelper | audited T3 |
| Game flow | DeathSystem (incl. wipe-revive), GameStateManager, DefenseLine | audited T4 |
| Meta (economy/progression) | Shop, Currency, Talents, Achievements, Inventory, DailyLogin, Leaderboard | audited T5-T9 |
| Lobby | PartyManager, MatchmakingManager, TeleportManager, PartyRequirements | audited T7 |
| Client UI | react-lua components + AppWindow/Theme standard | T10 in progress |
| Legacy UI (disabled) | `StarterGui/AppGui` + Controllers | neutralized, pending archive |
| Content/assets | `src/**/*.rbxmx`, `ServerStorage` models, `tools/` pipeline scripts | ⚠ see risks |
| Docs/debt | `docs/` (6 files incl. 30KB TODO.md), Audit_4.7.md + surfaces | excellent |

Multiplayer authority model: server-authoritative and *documented in
code* — validated per-audit (cooldowns, tickets, resource, currency all
server-side; client input is advisory; declared manifest with per-event
rate limits). Trust design evidence: NetworkManager manifest §NM-D4,
audit trails §T2/Z*, MonitoringSystem (logging-only, explicitly not
anti-cheat).

## 3. Health signals

| Area | Rating | Evidence |
|---|---|---|
| Repository & branching | 🟡 **Yellow** (revised) | `git remote -v` → empty: no remote. **DECISION (Pablo):** `.rbxmx` assets are deliberately place-managed — authoritative copies live in the published Roblox places, and the files are too heavy for git. Accepted; `.gitignore`'s `*.rbxmx` is therefore CORRECT as-is. Remaining: code has no offsite copy (remote still recommended, cheap), and `foreman.exe`(5.8MB)/`Leg.obj`/`Leg.mesh`/`sourcemap.json` are still tracked — the "too heavy for git" logic applies to them too. |
| Build reproducibility | 🟡 **Yellow** | Toolchain pinned (foreman.toml), deps locked (wally.lock committed). BUT: a fresh clone **cannot build** — the 29 untracked `.rbxmx` are referenced by the project trees. Local Rojo serve/build from THIS disk works. `wally.lock` says `registry = "test"` (curiosity, verify). Studio-side settings (Avatar R6 etc.) unspecified. |
| Architecture map | 🟢 **Green** | §2 above; boundaries enforced by folder layout + 5 project files; authority model verified by audit. |
| Quality gates | 🔴 **Red** | Nothing blocks anything: no CI (`.github` absent), no selene/stylua/.luaurc, no hooks. Merges = hope. (Mitigating: solo dev, disciplined §-tag/audit process — but it's process, not a gate.) |
| Tests | 🔴 **Red** | Zero automated tests (no TestEZ, no `*.spec.lua`). All verification is manual live-testing + this session's AST checks. Nothing protects startup/save-load/packaging on change. |
| Observability | 🟡 **Yellow** | MonitoringSystem exists (suspicious-activity logging, console-sink, opt-in config) ✓ design intent. No perf baseline (frame time/memory per platform) recorded anywhere; no external telemetry sink; DataStore health = console warns only. |
| Content pipeline | 🟡 **Yellow** | Deliberate and scripted (`tools/`: asset id fetchers, mesh converters, UI generator; AssetMap/MeshMap indirection ✓). But: rbxmx assets un-versioned (above), 16 icon slots + 28 sounds + 3/4 attack anims are `rbxassetid://0` placeholders (TODO §16, Theme.Icons), no build-content audit step. |
| Platform configurations | 🟡 **Yellow** | Place differences are explicit in code (5 project.json + per-place Mains) ✓. Dev vs shipping: no build profiles — same tree serves both; admin/testing surface ships enabled (gated, removal planned §T0P2-ADMIN). Mobile: UI is Scale-based by convention but untested target (unspecified). |
| Security | 🟡 **Yellow** | `.env` (Open Cloud key) is untracked & never in history ✓ (verified in-session); **rotation after session sharing: unspecified/not evidenced**. No secret-scanning tooling. Trust design: strong and audit-verified ✓. Admin remote surface = accepted, tracked risk (§T0P2-ADMIN [P0/Security]). |
| Localization & accessibility | 🟡 **Yellow** | Locale module = real, structured, used by UI (en-only; adding a language = one dictionary) ✓ genuine seam. Accessibility: nothing evidenced (no colorblind/scale options) → effectively unspecified/absent. |
| Ownership & debt | 🟢 **Green** | Solo owner, and debt is *accepted*, not ignored: 30KB TODO.md with priority tags (P0-P2/🚀/📝), §-IDs, per-tier sections, closed-item ledger; Audit_4.7.md is a real handoff document. Best-in-class for a solo project. |

## 4. Prioritized risk list

1. **Code-loss exposure (Yellow, revised).** Assets are safe in the
   published places (Pablo's decision, accepted). But the CODE — 30k+
   lines of audited Lua — has no remote and 61 uncommitted files. A
   local commit fixes half; a private remote fixes the rest. Note the
   repo alone can't rebuild a place from scratch (assets come from the
   published place) — acceptable in a Studio-first workflow, worth one
   line in a README so future-you remembers.
2. **No regression gate (Red).** Zero tests + no CI means every change
   (including this session's ~70 touched files) is verified only by
   manual play. The audit process substitutes for now, but one rushed
   change post-alpha can silently break save/load. Evidence: absence
   (per operating rule 2, absence of the artifact IS the finding).
3. **Open Cloud key rotation unevidenced (Yellow, cheap to kill).**
   Flagged twice in-session; no evidence of rotation. `.env` on disk.
4. **Admin remote surface ships (accepted Yellow).** Allowlist-gated,
   but AdminAction/DebugCommand/ModifySystemStat remain attack surface
   until §T0P2-ADMIN lands. Tracked — keep it P0 for release.
5. **Placeholder content in the build path (Yellow).** 28 sound slots,
   16 icons, shop catalog, 3/4 attack animations are placeholder — an
   alpha will *feel* it. Tracked (TODO §16, §T10/ICONS, §DISC/D7).
6. **Toolchain single-point (Low).** foreman.exe was being run from the
   repo copy; foreman itself isn't version-pinned anywhere (the tools it
   installs are). Minor: document the foreman version.

## 5. Unspecified (unverifiable from repo/docs — treat as operational risk)

- GitHub/remote settings (branch protection, reviews): no remote exists.
- Roblox **published-place state** vs this tree (how stale is live?).
- Studio game settings (Avatar type R6 enforcement exists in code as a
  runtime warn, but the authoritative setting lives in the place).
- Open Cloud key rotation status; what the key's scopes are.
- Target platforms actually enabled on the Roblox experience (mobile?).
- Performance baseline on ANY device (never captured).
- DataStore quota headroom under real player counts.
- `wally.lock` `registry = "test"` origin.

## 6. Next actions (priority order per operating rules)

**Tier 1 — reproducibility & survival (do before any more implementing):**
1. ~~Track rbxmx~~ **REVISED (Pablo):** assets are place-managed by
   design; `.gitignore` stays as-is. Instead: untrack the heavy
   leftovers only — `git rm --cached foreman.exe sourcemap.json Leg.obj
   Leg.mesh` (same "too heavy for git" rationale).
2. Commit the working tree (one commit — it was live-tested
   incrementally throughout the session).
3. Create a private GitHub repo; `git remote add origin …; git push`.
   Protects the code layer; assets already live in Roblox's cloud.
4. Rotate the Open Cloud key (5 minutes).
5. Fresh-clone test: clone to a temp folder, `foreman install`,
   `wally install`, `rojo build lobby.project.json` — proves
   reproducibility end-to-end. Fix whatever it surfaces.

**Tier 2 — automation & gates:**
6. Add `selene` + `stylua` configs and a single GitHub Actions workflow:
   lint + `rojo build` all 5 places on push (a build-success gate
   catches the entire class of "won't even start" mistakes — and would
   have replaced this session's AST-parse gymnastics).
7. Smoke tests where they pay: TestEZ for the pure modules
   (PartyRequirements, MobSpawnHelper, DifficultyConfig, XP curve,
   BonusManager aggregation) — high value, no Studio needed, runs in CI
   via run-in-roblox or lune later.
8. Capture a perf baseline once the alpha map is set: one Lane run +
   one Horde run with the MicroProfiler, note frame time/memory —
   TODO §T1.1-JAN2's telemetry idea folds in here.

**Tier 3 — depth (post-alpha):**
9. §T0P2-ADMIN removal, content-audit pass before packaging, archive
   the legacy UI stack, accessibility minimum (colorblind-safe palette
   check on Theme.Colors).

---

*The functional/code layer is in strong shape after the tier audits —
the operational layer is where a "clean start" is actually needed, and
Tier 1 is a single evening of work.*
