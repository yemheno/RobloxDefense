# T0 Pass-2 — Surface (cross-cutting re-audit)

> **STATUS: SIGNED OFF + EXECUTED.** Pablo approved per-item
> (2026-06-12); all approved fixes are landed in the working tree under
> `§T0P2/X<n>` tags. Decisions: DQ-A = (a) kick-on-overflow,
> DQ-B = lobby-owned difficulty, DQ-C = one-run servers.
> Not fixed by request: X16 (admin surface — parked as §T0P2-ADMIN,
> removal planned), X20/X22 kept as seams. Deferred items live in
> docs/TODO.md §19.
>
> **Suggested smoke tests before commit:**
> 1. TWO fresh accounts on one server (Studio multi-client): create
>    characters, unlock an achievement / equip a cosmetic on A → verify
>    NOTHING appears on B; relog both → saves stay separate (X1).
> 2. Queue Hard from the lobby with an eligible party → combat place
>    console shows "Difficulty resolved: Hard" and mob HP reflects it;
>    Studio direct-join still auto-selects from your level (X2, X7).
> 3. Level up naturally (addXP via admin panel uses the same path now —
>    use a kill) → Player list Power updates; rejoinless level checks
>    see the new level (X4).
> 4. Leave a second client during the join loading moment (X3 — no
>    "ghost" warns later, no stuck entries).
> 5. Let a run go idle 10+ min → vitals/HUD still ticking (X5);
>    shutdown the server with 2+ clients → both saves persist (X6).
> 6. Horde: full run end-to-end → votes fire, run ends, lobby return
>    (X13 deletion didn't regress the timer).
>
> Original surface preserved below for lineage.
>
> Fresh-eyes re-read of every T0 module, full files, with callsite
> cross-checks (§3.2/§3.3 methodology). IDs `X1…X25`. Severity:
> 🚨 bug > 🟡 spaghetti > 🟢 minor > ❓ DQ. Carried items from the
> repo-wide pass (G3/G5/G8/G10) are folded in where they belong.
>
> Scope read end-to-end: PlaceBootstrap, PlaceLifecycle, ReadyGate,
> NetworkManager (server+client), PlayerDataManager + 4 subsystems,
> PlayerDataConfig, TeleportDataReader, ReturnTeleporter,
> SharedEventHandlers, AdminTesting, all 5 place Mains.

---

## 🚨 Bugs

### X1. CreateDefaultData shares nested default tables across players — save cross-contamination
`PlayerDataManager/init.lua:217-226`. The account-defaults copy is only
two levels deep: `data.Account[key] = {}` then `data.Account[key][k] = v`.
When `v` is itself a table it is copied **by reference**. Affected:
`Wardrobe.owned`, `Wardrobe.equipped`, `Achievements.unlocked`,
`Achievements.stats`, `Quests.active`, `Quests.completed` — all of them
actively written by CosmeticManager / AchievementManager / QuestHandler.
Consequences: every **first-visit** player on a server shares these
six tables with each other AND with `PlayerDataConfig.AccountDefaults`
itself; player A's achievement writes appear in player B's fresh save
and get SetAsync'd into both; the polluted config defaults then leak
into every later player's DeepMerge (DeepMerge copies the polluted
scalars into fresh saves). `CharacterData` is exempt only because
SetupPlayer hand-builds a fresh copy at line 233.
**Fix shape:** make CreateDefaultData use a true deep copy (the
codebase already has the recursive pattern inside DeepMerge — extract a
`deepCopy(defaults)` helper and use it for the whole Account block).
One function, removes the hand-maintained CharacterData special case too.

### X2. Teleported difficulty is read at boot, before any player arrives — always "Normal"
`LaneDefenseMain.server.lua:158-164` + `:230-247`,
`HordeModeMain.server.lua:160-164` (then used at `:275` and inside the
vote loop at `:393`), `CentralBossMain.server.lua:144-150`. All three
combat places call `TeleportDataReader.GetDifficulty()` **at bootstrap
time** — but `ProcessPlayer()` (which sets `matchDifficulty` from the
teleport payload) only runs later, inside `WireOnPlayerReady` extras.
Grep confirms `SetDifficulty` has **no later callsite** in any place.
Net effect: the difficulty selected in the lobby never reaches
MobSpawner / HordeModeSpawner / VoteManager — every run plays on
"Normal" scaling regardless of what the party queued for.
**Fix shape:** re-apply difficulty when the first ProcessPlayer
resolves (e.g. `TeleportDataReader.OnDifficultyResolved(cb)` seam, or
call `spawner.SetDifficulty(tdr.GetDifficulty())` inside the same
data-ready hook that anchors party level). Ties into DQ-B (who owns
run difficulty). Note HordeMode's `hordeDifficulty` local must also be
refreshed or the vote loop keeps reporting "Normal".

### X3. Player leaving during DataStore load leaves a zombie entry + fires data-ready for a departed player
`PlayerDataManager/init.lua:264-369`. `SetupPlayer` yields inside
`LoadRawData` (up to ~3 retries with backoff). If the player leaves
during that yield, `RemovePlayer` runs first (clears nothing — data
isn't stored yet), then SetupPlayer **resumes**: stores
`playerDataStore[player]` for a player who's gone (strong key — never
GC'd, never cleaned again), fires every `dataReadyCallbacks` (TalentManager,
InventoryManager, ClassManager, SharedEventHandlers… all set up state
whose PlayerRemoving cleanup already ran), and parents leaderstats to a
departed Player. Permanent per-occurrence leak + downstream state for
ghosts.
**Fix shape:** after `LoadRawData` returns (and after the kick branch),
guard `if not player.Parent then setupInProgress[player] = nil return end`.

### X4. Natural level-up never updates the Level attribute or Power leaderstat
`PlayerLevelSystem.lua:59-94` writes `data.Account.Level` directly and
hand-updates the leaderstat, but never calls
`player:SetAttribute("Level", …)` (grep: only set in
`PlayerDataManager/init.lua:351` setup and `:565` SetAccountData) and
never calls `RefreshPowerScore` (grep: same two sites). So after any
mid-session level-up: the Level **attribute** is stale (consumed by
TeleportDataReader's no-teleport-data fallback at
`TeleportDataReader.lua:63` → wrong difficulty AutoSelect), and the
Power leaderstat ignores level gains until a rejoin or equipment change.
AdminTesting.SetLevel is unaffected (it routes through SetAccountData)
— which is why this never showed in admin testing.
**Fix shape:** in the level-up loop, replace the direct write + manual
leaderstat fiddle with `PlayerDataManager.SetAccountData(player, "Level", …)`
(single write path; it already syncs attribute + leaderstat + power).

### X5. Vitals + regen loops die permanently on the first error
`PlaceLifecycle.lua:190-218` and `:224-257`. Both ambient loops are
bare `while true` bodies inside `task.spawn` with **no pcall**. One
transient error (a character mid-destruction edge in
`StatsManager.GetTotalHealth`, a nil during teleport-out, a future bug
in `GearRating.GetDisplayPower`) kills the loop thread — HP regen
and/or the entire HUD vitals feed silently stop for the **rest of the
server's lifetime**. Contrast: ResourceManager's tick loop already
pcalls per-tick.
**Fix shape:** wrap each iteration body in pcall + `warn` (same pattern
as ResourceManager), keep the loop alive.

### X6. BindToClose saves players sequentially — can exceed the 30 s budget
`PlayerDataManager/init.lua:111-115`. Each `SavePlayer(player, true)`
can wait up to 3 s for an in-flight auto-save **plus** the SetAsync
yield. N players = sum of all of it, sequentially, inside a 30 s
BindToClose window. A 10-player server shutting down mid-auto-save can
run out of budget → the tail of the player list loses progress.
**Fix shape:** `task.spawn` each save, count completions, wait for all
(or deadline) — standard parallel-save pattern.

### X7. Data-ready callbacks fire before leaderstats / Level attribute exist
`PlayerDataManager/init.lua:319-321` fires `dataReadyCallbacks` (via
`task.spawn`, which runs immediately until first yield) **before**
leaderstats creation (`:335`) and `SetAttribute("Level", …)` (`:351`).
Concrete hit: `WireOnPlayerReady` extras → `TeleportDataReader.ProcessPlayer`
fallback reads `player:GetAttribute("Level")` → nil → level-1 party
entry → wrong `DifficultyConfig.AutoSelect` for Studio/direct joins.
Any future data-ready consumer reading leaderstats/attributes hits the
same hole.
**Fix shape:** move the callback fan-out to after attribute +
leaderstats setup (it's ~30 lines down in the same function; no
behavioral change for existing consumers that read only `data`).

### X8. ReadyGate overflow evicts the oldest queued event — boot-critical payloads die first *(carried G5)*
`ReadyGate.lua:189-195`. Queue cap 200, overflow drops `q[1]` — on a
slow client that's exactly the first-queued boot payload (equipment,
achievements, character-creation prompt). Needs DQ-A decision.
**Fix shape (a):** never evict; on overflow mark the client broken and
kick with a resync message. **(b):** flag specific events undroppable
and evict only droppable ones.

### X9. Boot-time pushes still bypass ReadyGate — including the §HM2 late-joiner fix itself
`HordeModeMain.server.lua:466-472` pushes `GameStateChanged` to a
late-joiner via `NetworkManager.FireClient` from the data-ready path —
the exact race ReadyGate exists for; the fix can drop on the floor.
Same class of issue: `PlaceLifecycle.lua:105` fires `ServerReady`
directly; Audit_4.7 §12 lists ServerReady as "BYPASS in ReadyGate" but
`BYPASS_EVENTS` (`ReadyGate.lua:87-93`) does **not** contain it — doc
and code disagree. (Today every client's ServerReady handler body is
empty, so nothing breaks *yet* — see X25.)
**Fix shape:** route both through `ReadyGate.FireClient`; reconcile the
§12 bypass list against `BYPASS_EVENTS` one way or the other.

---

## 🟡 Spaghetti / robustness

### X10. Event manifest drift — 5 events used but unregistered, 5 registered but never fired
Used server-side, missing from `EVENTS` (created ad-hoc, after the
pre-register pass, undocumented, default rate limit): `DeathState`,
`HordePaused`, `ModifySystemStat`, `NPCProximity`, `RequestRespawn`.
In manifest but never referenced by any server module:
`ArmorRefinementResult`, `ArmorTierUp`, `WeaponRefinementResult`,
`WeaponTierUp`, `HealNumber` (dead entries, or pushes that were never
wired — check at T6/T2 respectively).
**Fix shape:** add the missing five with explicit rateLimit/readyGated
metadata; tag the five orphans with a `-- §X10: unwired?` comment for
their owning tier. This is the lint pass the manifest comment promised.

### X11. GetPlayerInfo handler spawns a 10 s retry loop per request — thread amplification
`SharedEventHandlers.lua:174-187`. Each GetPlayerInfo with unloaded
data parks a 40×0.25 s wait loop in the handler thread. Default rate
limit (30/s) lets one client park ~300 concurrent loops. The
data-ready auto-push (`:166-170`) already covers the legitimate case.
**Fix shape:** drop the retry loop — if data is nil, return (client
re-requests or the auto-push lands).

### X12. RespecStats duplicates ResetAllocation inline — and skips the HP reapply
`SharedEventHandlers.lua:237-248` rebuilds `classData.Allocated` by
hand instead of calling `DataManager.ResetAllocation(player)`. The
StatSystem version (`PlayerStatSystem.lua:191-214`) also reapplies
character health; the inline copy doesn't — a respec that drops VIT
leaves the character with inflated current/max HP until the next stat
change or respawn. Classic drift-from-duplication.
**Fix shape:** replace the inline block with
`DataManager.ResetAllocation(player)`.

### X13. HordeMode vote + run-timer threads are one-shot, but the state machine pretends to support re-runs
`HordeModeMain.server.lua:377-415` and `:419-445` both exit permanently
once `hordeRunActive` flips false, while the `OnStateChanged` reset
closure (`:237-244`) carefully re-arms timers "on each Defending entry"
— state that no living thread will ever read. If a second run in the
same server is possible, it has no votes and no end-timer; if it isn't,
the reset closure is dead code.
**Fix shape:** decide one way (likely: servers are one-run; delete the
reset closure and add a comment), or restructure the loops to restart
on Defending.

### X14. WireOnPlayerReady double-call wires a second full chain *(carried G10)*
`PlaceLifecycle.lua:113-118` — the `_onReadyFired` latch is local to
each call. A future place calling it twice re-runs Talent/Inventory/
Stats setup per player. Tripwire today, bug tomorrow.
**Fix shape:** module-level `_wiredOnce` warn-and-return guard.

### X15. PlaceBootstrap.Load assumes module returns a table
`PlaceBootstrap.lua:71` — `type(result.Init)` errors (outside any
pcall) if a module returns `true`/function/number. One stray
`return true` module nukes the whole place boot with a confusing error.
**Fix shape:** `if type(result) == "table" and type(result.Init) == "function"`.

### X16. IsAdmin trusts `game.CreatorId` without checking CreatorType
`PlaceBootstrap.lua:35`, `AdminTesting.lua:78`. If the game is ever
moved to a group, `game.CreatorId` is the **group id** — the owner
loses admin (and a player whose UserId happens to equal the group id
would gain it). Works today on a user-owned universe; latent footgun.
**Fix shape:** `if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId`.

### X17. WipeData "cancels" an in-flight save by clearing the flag — it can't
`PlayerDataManager/init.lua:397-419`. Clearing `savingPlayers[key]`
doesn't stop the in-flight `SetAsync`; if one is mid-air, it can land
**after** `RemoveAsync` and resurrect the wiped data. Also breaks the
force-save wait of any concurrent saver. Admin-only path, low traffic.
**Fix shape:** add a `wipedPlayers[key] = true` tombstone checked by
SavePlayer before SetAsync (cleared on rejoin), instead of touching
`savingPlayers`.

### X18. AdminTesting.ResetData / SetLevel leave derived state inconsistent
`AdminTesting.lua:94-134`: ResetData zeroes talents/allocations but
never triggers `TalentEffectAggregator` / BonusManager recalc or an HP
reapply — the player keeps talent stat bonuses until rejoin.
`:137-156`: SetLevel skips `CheckAndUnlockEligibleClasses`, so an
admin jumping to 50 doesn't get level-gated classes until the next
natural level-up. Admin-only, but these are the accounts used for
live-testing tiers — inconsistent state pollutes test results.
**Fix shape:** ResetData → call the respec path + recalc + health
reapply; SetLevel → call CheckAndUnlockEligibleClasses after.

---

## 🟢 Minor / dead code

### X19. `_G.<Place>RequireLoaded` write-only globals
`LobbyMain:28`, `LaneDefenseMain:26`, `HordeModeMain:31`,
`CentralBossMain:27` — grep finds **zero consumers**; SocialPlaza
doesn't even set one. Delete all four (or document the intended
consumer if one is planned).

### X20. TeleportClass attribute is set but never consumed
`TeleportDataReader.lua:81-94` (`ApplyPlayerData`) sets
`player:SetAttribute("TeleportClass", …)`; grep finds no reader.
Dead function + dead attribute — delete, or wire it to whatever was
supposed to honor the party-selected class.

### X21. `AddClassMasteryXP` has zero callers
`PlayerLevelSystem.lua:101-128`. The overflow-XP path was removed in
T0; the earn path is an open TODO (§3). Keep-as-seam or delete — but
today it's unreachable code that still grants BoundTokens if ever
called. Tag it explicitly as a seam if kept.

### X22. Dead pass-throughs in PlayerDataManager
`init.lua:761-763` `DeallocateStat` — zero external callers (UI uses
full respec only). `init.lua:773-775` `ApplyHealthToCharacter` — zero
callers AND silently drops the `freshSpawn` third argument, so any
future caller gets the wrong branch. Delete both (children remain
reachable via GetSystems / direct paths).

### X23. BONUS_STAT_MAPPING carries stale resource keys
`PlayerBonusSystem.lua:104-107` maps `rage`/`mana`/`focus` to BonusStats
keys that don't exist in `PlayerDataConfig.BonusStats` (old resource
names; the current four are Determination/Aether/KillerInstinct/
LifeEnergy). Registries roll none of them (grep), so it's inert — but
if a weapon ever rolls one, BonusManager warn-rejects it at runtime.
Delete the three rows.

### X24. ReadyGate niggles
`ReadyGate.lua:115` drain `print` → make it conditional or `warn`-level
only when large; `readyCallbacks` (`:82,166-168`) is append-only with no
unsubscribe — fine for module-lifetime use, worth a comment saying so.

### X25. Doc/code mismatches worth one sweep
AdminTesting header says "UserId must match game.CreatorId" but the
code (correctly) also honors the allowlist, and `WipeAndKick` /
`ResetCooldowns` are missing from the header's action list. Every
client's `ServerReady` handler body is empty (5 places) — either it's
the future loading-screen hook (comment it) or delete the listeners.
`PlaceLifecycle.lua:209-210`'s `or 0.5` / `or 0` regen fallbacks are
dead (GetTotalStat never returns nil) — harmless, remove for clarity.

---

## ❓ Design questions

- **DQ-A (X8).** ReadyGate overflow: kick-and-resync (a) or undroppable
  flags (b)? My lean: (a) — a client that can't drain 200 queued boot
  events within the session is broken; kicking is more honest than a
  half-initialized session.
- **DQ-B (X2).** Who owns run difficulty? Today: TeleportDataReader
  module-global, last-arriving player's payload wins, never validated,
  never re-pushed. Proposal: difficulty resolves ONCE from the first
  arriving batch (validated against DifficultyConfig — folds in G2's
  validation), then a single `OnDifficultyResolved` push to spawner +
  VoteManager; later arrivals can't change it.
- **DQ-C (X13).** Are HordeMode servers one-run-only by design? Decides
  whether the fix is "delete reset closure" or "restartable loops".

---

## Verified-good this pass (no action)

PlaceBootstrap admin allowlist is single-sourced; ClassManager's
RequestClassSwitch enforces known-class + not-in-combat + cooldown +
unlock; SkillManager.ResetAllCooldowns exists (AdminTesting call is
valid); rate-limiter buckets are cleaned on PlayerRemoving + stale
sweep; SavePlayer force/dedup logic is sound (§PERSIST1 holds);
DeepMerge itself deep-copies correctly (X1 is only in CreateDefaultData);
client NetworkManager's deferred-listener stub Disconnect is correct;
LaneDefense party-anchor mirrors Horde's deferred pattern correctly.

---

## Proposed action set

Ordered by what I'd land first after your sign-off. All edits follow
§5 patterns, get §-tags (`§T0P2/X<n>`), paren/keyword sanity checks,
and stale-callsite greps. You live-test, you commit (per §1.2).

- **Batch 1 — data integrity (X1, X3, X6, X7):** all inside
  PlayerDataManager/init.lua. Highest stakes, one file, one smoke test
  (two fresh accounts on one server + leave-during-load + shutdown save).
- **Batch 2 — run correctness (X2 + DQ-B, X4, X13 + DQ-C):** difficulty
  propagation seam, level-up via SetAccountData, horde loop decision.
- **Batch 3 — boot hardening (X5, X8 + DQ-A, X9, G3 timeouts, X14, X15):**
  PlaceLifecycle/ReadyGate/PlaceBootstrap + the five Mains' WaitForChild.
- **Batch 4 — hygiene (X10–X12, X16–X25):** manifest sync, handler
  fixes, dead-code sweep.

Reply per item or per batch (e.g. "Batch 1 yes; X13 discuss; DQ-A a,
DQ-B yes, DQ-C one-run").
