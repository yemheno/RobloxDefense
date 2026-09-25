# Agency Checks: multi-agent audit surface (2026-09-25)

> **What this is.** Five agency-agents personas (`.claude/agents/`) each
> checked one domain. A Reality Checker verifier then re-read the cited
> code and confirmed or rejected every finding. Only findings that
> survived verification appear below. They are ID'd `X1…X49` and sorted
> 🚨 bug > 🟡 spaghetti > 🟢 minor > ❓ design question.
> **Status (2026-09-25):** the ⚡ freebies have LANDED; see "Landed fixes"
> at the bottom. Everything else is still open.
> **Originally nothing here was executed.** Everything is static reading;
> there was no Studio or Rojo in the checking environment. Please answer
> per item (`X1. Yes / No / discuss`) as in §3.4.
>
> Source column: `sys` = roblox-systems-scripter, `sec` =
> ai-code-security-auditor, `eco` = economy-designer, `exp` =
> roblox-experience-designer, `perf` = performance-benchmarker.
> ⚡ marks a fix that looks direct and doesn't change functionality
> (standing-rule candidate). *(known: …)* marks overlap with an existing
> audit item.
>
> Paths are relative to `src/shared/ServerScriptService/Modules/`
> unless given in full.

---

## 🚨 Bugs / dangers

### X1. Horde mode spawns zero mobs ⚡ (perf HMS-P1; regression from §SCALE/S1, commit 28e7fd7)
`src/hordemode/ServerScriptService/Modules/HordeModeSpawner.lua:397,524`
call `positionMarkers(...)` inside `createPlayerSpawner` (`:338`). The
only declaration is `local function positionMarkers` at `:597`, below
the callers, so the calls look up a nil global. There is no pcall
around them, so every spawner thread dies on its first tick, and the
`:339` guard then blocks any restart. The orchestrator and the verifier
both checked that there is no forward declaration and no `_G` assignment.
**Fix shape:** add `local positionMarkers` above `:338` and change
`:597` to assign it (or move `:589-603` up). **Studio:** start a Horde
run and look for "attempt to call a nil value".

### X2. BindToClose doesn't wait for leave-saves already running (sys F2)
`PlayerDataManager/init.lua:125-128` returns at once when
`GetPlayers()` is empty. `RemovePlayer` (`:414-419`) starts a force save
that can wait 3 s (`:498-502`) and then yields in `SetAsync`
(`:517-519`). `ReturnTeleporter.lua:103-111` empties a combat server in
one go, which is the **normal** exit path for every run, so the run's
rewards can be lost silently.
**Fix shape:** a `pendingSaves` counter that BindToClose waits on
until it reaches zero.

### X3. No session lock; saves overwrite blindly; no retry on the final save (sys F3 = exp #4 = sec SEC-07; extends TODO §15)
The load is `GetAsync` (`init.lua:238`) and the save is `SetAsync`
(`:518`), with no lock or version check. There is one final save
attempt (`:517-525`), then the in-memory copy is dropped (`:419`). After a
teleport the destination can load before the source's write lands, and
its next save then erases the run's rewards or a lobby purchase.
**Fix shape:** an `UpdateAsync` session lock `{jobId, time}`, with the
destination waiting while the lock is held, plus 2–3 retries on the
final save. A save before teleport helps but isn't sufficient on its own.

### X4. Match teleports go to public servers (sys F1 = exp #3; contradicts the D2 premise)
`src/lobby/ServerScriptService/Modules/TeleportManager.lua:139-150`
has no `ShouldReserveServer`, `ReserveServer` or access code anywhere in
`src/`. D2 (`docs/TODO.md:670-672`, `T5-T9_SWEEP.md:118`) assumes
reserved servers. A second party can join a Horde run in progress, where
the run timer starts at boot (`HordeModeMain:229-243`), or land in a
finished server. It can also share the wipe-revive and XP split.
**Fix shape:** `ShouldReserveServer = true`, and have combat places
reject `PrivateServerId == ""` outside Studio.

### X5. Any client can start Lane/CentralBoss waves before the game starts (sys F4; partly sec SEC-05)
The `RequestNextWave` handler (`MobSpawner.lua:130-134`) only checks
`waveState == "idle"`. Lane and Boss boot into Idle, and in Idle the
defense line takes no damage (`DefenseLine/init.lua:113`) and wipes are
ignored (`DeathSystem.lua:413`). Wave XP is still paid
(`LaneDefenseMain:321-330`), and all waves done forces VICTORY from any
state (`GameStateManager.lua:78-80`). One event gives an unlosable
farm. `docs/TODO.md:351` wrongly says Lane and Boss auto-start.
**Fix shape:** require `IsDefending()` in the handler and route the
completion through `TriggerVictory`.

### X6. TeleportData `modeId` / `lobbyPlaceId` / level floor are trusted (sys F5; extends G2/X2)
`TeleportDataReader.lua:82-84` takes the payload `modeId`, which drives
the reward multipliers (`KillRewardManager.lua:63-81`,
`DropManager.lua:69-88`). Horde mob stats are hard-wired, so
`modeId="Defense"` gives about 2.2× rewards on easy mobs.
`requiredLevel` is enforced only in the lobby. `lobbyPlaceId`
(`ReturnTeleporter.lua:51-61,110`) is weaker than first reported: a lone
spoofer only bounces themselves.
**Fix shape:** ignore the payload `modeId`, always use
`Shared.PlaceIds.Lobby`, and re-check `requiredLevel` on arrival.

### X7. The Horde vote pause isn't enforced on the server (sec SEC-01)
`HordePauseManager.lua:56-58` sets `HordePaused`, but no server code
reads it (`IsPaused`, `:37`, is never called). AttackHandler and
SkillManager only check DeathState/stun, and the comment at
`VoteManager.lua:333-334` claims a block that doesn't exist. A modified
client can keep hitting frozen mobs through every vote pause. (The
wipe-grace part of the original claim was rejected: everyone is dead
then.)
**Fix shape:** one `isWorldPaused()` check in HandleAttack,
HandleHitReport and TryUseSkill.

### X8. `SaveKeybindings` stores an unbounded client table, so a player can block their own saves (sys F6 = sec SEC-02)
`SharedEventHandlers.lua:272-290` only checks types, uses the default
30/s rate limit, and has no allowlist, size cap or UTF-8 check. If the
profile can't be encoded, every `SetAsync` fails
(`PlayerDataManager/init.lua:516-525`, warning only). The exploit:
refine or reroll, rejoin to undo a bad roll, then send clean binds to
keep a good one.
**Code side confirmed; the engine side needs Studio:** fire
`SaveKeybindings({x={Keyboard="\255"}})`, force a save, and check that
the stored profile is unchanged.
**Fix shape:** allowlist action, platform and `Enum.KeyCode` names; cap
counts and lengths; check `utf8.len`; rate limit to 2/s.

### X9. Refine pity skips the chapter refinement cap ⚡ (eco E1)
The cap check at `EquipmentRefinement.lua:77` doesn't cover the pity
jump at `:162-167` (floor+3), and no other path clamps it. Exact odds of
overshooting per climb in the capped band: Ch1 0.24% (to +9), Ch2 4.23%
(to +12), Ch3 2.25% (to +15). The overshoot persists until tier-up.
**Fix shape:** `nextFloor = math.min(floor + 3, chapterMax)`.

### X10. All 10 consumables can be bought but none can be used (eco E3)
`ShopManager.lua:214-270` charges and stores the item, but no
consumable-use handler exists anywhere; only `respec_scroll` is ever
consumed. Fortune Incense's +15% never applies. **Note:** setting
`enabled=false` alone won't fix it. Only the client UI reads that flag
(`GlobalShopUI.lua:275`), and the NPC shop calls `PurchaseConsumable`
directly (`ShopHandler.lua:96-103`).
**Fix shape:** a server-side check in `PurchaseConsumable` that
rejects everything except `respec_scroll` until use handlers exist.

### X11. All 15 talent keystones are no-ops, and 7 of them are pure nerfs (eco E10, broadened by the verifier)
`TalentEffectAggregator.HasRule` and `GetActiveRules` (`:62-66,127-135`)
have no callers, and no `rule=true` name appears outside
`TalentTreeConfig`. Their stat penalties still apply through `value`
entries (`:67-74`), so 7 keystones only lower damage and 8 waste a point.
**Fix shape (design call):** hide or disable keystones until each rule
has code behind it, or strip the penalties for now.

### X12. DoT and Thorns kills skip `HandleMobDeath`: corpses stay forever and pay no rewards (perf DMG-P1)
`SkillEffects.lua:427` and `MobAI.lua:1121` call `humanoid:TakeDamage`
directly. The only mob `Died` listener (`MobAI:292`) just unregisters
the mob. Once unregistered, the corpse is invisible to
`MobSpawner.Reset` and DefenseDetection, and it grows every AttackShapes
scan. No XP, drops, weapon XP or achievements are granted.
**Fix shape:** a shared `ApplyRawDamage` that calls `HandleMobDeath`,
plus a 2 s Destroy safety net in `OnMobDied`.

### X13. Roar followed by GroundSlam leaves the player stuck at half speed ⚡ (perf AI-P2)
`MobAI.lua:917-940` restores a captured speed via `task.delay`. The
timeline: Roar at t=0 (slow to 8, 3 s); Slam at t=2 captures 8 and sets
0; at t=3 Roar restores 16; at t=3.5 the stun restores **8**. It also
survives knockdown and revive (`DeathSystem:313,525,631`), so only a
respawn clears it. Ogre and Troll are guaranteed in waves 4, 7, 10 and
12. The same race exists in `SkillManager:178/242`.
**Fix shape:** a per-player base speed plus an active-effects map,
recomputed when an effect expires.

### X50. Paying for the wipe-revive takes the Essence, then soft-locks the run ⚡ (found by `luau-analyze` during the fix pass)
`DeathSystem.HandleWipeRevive` (`:469`) calls `performRevive`, which is
declared `local function` further down (`:589`), so the call looks up a
nil global. By then Essence has been spent, `wipeGraceActive` is false
and the defeat timer has been cancelled. Everyone stays dead, no Defeat
ever fires, and the run hangs.
**Fix shape:** a forward declaration, the same as X1.

## 🟡 Spaghetti / structural

### X14. Teleport failures after the teleport starts are unhandled (sys F7 = exp #7; G4 only covered the synchronous retry)
There is no `TeleportInitFailed` listener. The §L9 `CancelQueue`
(`TeleportManager.lua:185-187`) does nothing, because the queue entry is
already gone (`MatchmakingManager.lua:294,360`). "Launching"
(`MatchmakingUI.lua:53,89`) never clears. When the return teleport fails,
players sit in Idle with no Return button (`HUD.lua:823-824`).
**Fix shape:** a handler that retries and then shows an error, a
`launching` set checked by `IsQueued`, a client timeout, and Return kept
reachable in Idle.

### X15. Leave, kick or join during the queue countdown is ignored (exp #6)
`MatchmakingManager.lua:210` takes a snapshot of the party. PartyManager's
leave, kick and accept paths never notify Matchmaking, so a kicked
player still teleports and a new joiner is left behind.
**Fix shape:** cancel the queue when membership changes, or block
membership changes while queued.

### X16. `PlaceBootstrap` marks a module loaded even when its `Init()` throws ⚡ (sys F8)
`PlaceBootstrap.lua:88-96`. If `PlayerDataManager.Init` throws, the
place runs with no save wiring and only a boot warning.
**Fix shape:** record `ctx.initFailed` and make `RequireLoaded` error on it.

### X17. Dash can produce a NaN position (sec SEC-03; this call site wasn't covered by §T2/Z3)
`ClassSkills/BaseSkills.lua:158-161`: `moveDirection=(0,1,0)` flattens to
zero, and `.Unit` of that is NaN. The range checks at
`AttackHandler/init.lua:339-341` and `MobAI.lua:788,1007,1060` fail open
on NaN. Whether the engine keeps a NaN CFrame is unverified, so this is
🟡, or 🚨 if Studio shows it sticks.
**Fix shape (⚡):** zero-guard the direction and write the checks as
`not (d <= max)`.

### X18. Character creation can be re-submitted any time and accepts `bodyModel = math.huge` (sys F10 = sec SEC-04)
`CharacterManager.lua:553-556 → 419-466` has no `isCreated` guard, and
`CharacterConfig.lua:47-51` has no upper bound. Every call rebuilds the
whole character at up to 30/s. It also makes the planned paid
appearance presets (§T1.1-CC4) free. **❓ Is this intended?**
**Fix shape:** reject when already created (or route changes through a
priced path), clamp the body model to `1..BodyModelCount`, and rate
limit to 1/s.

### X19. CentralBoss can be picked from the Main Menu, but the arena is empty and has no way back (exp #8; content gap known TODO §17)
`MainMenu.lua:48` and `GameModeConfig.lua:48` set `available = true`.
The Return button only appears on Victory or Defeat, and neither can
happen there.
**Fix shape (⚡):** set `available = false` in both until §CB1 lands.

### X20. `ResourceUpdate` is force-sent on every tick while the resource is full or empty (perf RM-P1)
`ResourceManager.lua:312-313,533`: about 10 events/s per player at
full, and about 60/s during a knockdown at 0. Each event re-renders the
whole HUD (`HUD.lua:207-213`). This affects combat places only (the lobby
claim was rejected).
**Fix shape (⚡):** force only when the value changed, and have the
client skip unchanged values.

### X21. `SkillActivated` is broadcast to everyone with the full skill table (perf SKL-P1; extends Deferred #3)
`SkillManager/init.lua:211`, and every non-caster drops it
(`SkillVisuals.lua:77`). `SendVisualToAll` has 19 call sites with no
range limit. **Don't delete the event:** it's the only thing that plays
cast-time animations.
**Fix shape:** `FireClient(caster)` plus range-scoped visuals.

### X22. XP HUD pushes are sent once per kill per recipient, with a `pcall(require)` rebuild per kill (perf RWD-P1)
`KillRewardManager.lua:128-150,301-310`,
`PlayerDataManager/init.lua:875-891`. The fan-out is capped by party
size (5), so it's smaller than first estimated.
**Fix shape:** a dirty flag flushed every 0.25 s (the S5 pattern), and
cache the party list.

### X23. The pity rules in the docs and in the code differ by about 14× (eco E2)
`BALANCE_NUMBERS.md:536-538` (per-band temper, guaranteed next roll,
reset on any success) against the code (per-step, jump to floor+3, reset
on ceiling). Expected cost to reach +15: docs about 32.5M, code 2.39M.
**❓ Pablo:** which rule is canonical? Then align the other.

### X24. The NPC shop shows a different price and currency from what it charges (eco E11)
`LobbyNPCRegistry.lua:45-48,74-77` shows 10 and 15 Essence while
ShopConfig charges 25 and 30 Merits. `iron_sword`, `steel_shield` and
`arcane_focus` exist only in the NPC registry, so buying them always
fails.
**Fix shape:** build the NPC listing from `ShopConfig.FindByItemId`.

### X25. Places where the docs and code disagree (eco E12)
- **Difficulty (Hard):** HP 1.5 vs 1.45, damage 1.3 vs 1.25, armor 1.2 vs 1.15.
- **Lane waves:** the docs say 5 waves; the code has 12 (252 mobs).
- **Horde votes:** the docs say 14+7; the code has 7+7.
- **Daily login:** 280 vs 228 Essence per 30 days.
- **Tier table sum:** 1,460 vs 1,650.
- **Talent points:** the docs say `Level−1`; the code uses the sum of weapon levels.
- **Comment:** `TalentManager.lua:98` says 8×50 = 320.

Docs-only fixes once X23 is decided.

### X26. XSS in the dev browser extension (sec SEC-10; not game code)
`RobloxAssetExtractor/background.js:101-106` puts scraped asset names
into HTML without escaping, then opens the result as a blob page with
roblox.com's origin. Whether it can be exploited depends on the name
filter and the CSP, and needs a browser test.
**Fix shape (⚡):** fill the table with `textContent`.

## 🟢 Minor

- **X27. Two leaderboards are always empty** (sys F9 = exp #5). Nothing
  writes `HighestWaveReached` or `TotalPlayTime`
  (`PlayerDataConfig.lua:190-191`), and `LeaderboardManager.lua:128`
  skips zero scores. The wave part of Power's prestige bonus is always 0.
- **X28. 9 of 25 achievements can't be earned** (exp #11). There is no
  boss-tier mob, and `boss_slayer`, the four `medal_*` and the four
  `mastery_cap*` achievements all need one. A D5 gate on the level-50 cap
  would block progression if it lands before a boss does.
- **X29. NPC responses skip `INTERACT_RANGE`; smiths ignore
  `smithType`** (sec SEC-06; `NPCManager/init.lua:291-310`,
  `WeaponSmithHandler.lua:113-143`). Low impact. ⚡
- **X30. `VoteCast` accepts `1.5` or NaN, and doesn't check voter
  eligibility** (sec SEC-08; `VoteManager.lua:484-488`). It only amounts
  to abstaining; the "swing the vote" claim was rejected. ⚡
- **X31. `lookDirection` is relayed to other clients unchecked** (sec
  SEC-09; `AttackHandler/init.lua:261,277-293`). Accept only a non-NaN
  Vector3 and clamp its length. ⚡
- **X32. MeritBonus (up to 32%) also multiplies shop refunds** (eco E5;
  `CurrencyManager.lua:88-93`, `ShopManager.lua:200,264`). Add a
  raw/no-bonus flag for refunds.
- **X33. `SpendMerits` / `SpendEssence` accept negative amounts** (eco E6;
  `CurrencyManager.lua:136-166`). Latent. Mirror the guard on the Add
  side. ⚡
- **X34. `PurchasePremium` doesn't check `enabled` on the server** (exp
  #2a; `ShopManager.lua:278-291`). Latent until Robux purchases exist.
- **X35. A defense-line breach tweens every mob part on the server** (perf
  DL-P1; `DefenseAnimation.lua:59-86`). *(known: the broadcast is
  Deferred #5; the print is G21.)* Anchor the mob and let the client
  dissolve it.
- **X36. `findSpawnLocation` scans all workspace descendants on every
  full-death respawn** (perf DS-P1; `DeathSystem.lua:570-584`). Cache
  the result. ⚡
- **X37. Defense regen runs every Heartbeat and only notifies when a
  frame heals 1 HP or more** (perf DL-P2; `DefenseHealth.lua:226-238`).
  Latent while regen is disabled.
- **X38. Horde `CharacterAdded:Wait()` threads leak when the player
  leaves first** (perf HMS-P2; `HordeModeSpawner.lua:684-693,708-714`). ⚡
- **X39. The daily login claim is used up even when the reward grant
  fails** (exp #10; `DailyLoginManager.lua:205-237`: `lastClaimDate` is
  written first and it still returns `true`). *(known: the lock and
  pcall, §DL1-DL3; the missing rollback is new.)*

## ❓ Design questions (factually verified; the call is Pablo's)

- **X40. The wipe-revive is a paid prompt on a 10 s countdown, and new
  players have 0 Essence** (exp #1; `DeathSystem.lua:42-54,675,688`,
  `DeathUI.lua:298-344`). A solo player hits it on their first death,
  and a Robux product is planned for this flow. That is a Roblox policy
  risk. *(known: §DISC/D3, D3b; the policy angle is new.)*
- **X41. Vote cards give about 19× more Essence than drops** (eco E4).
  Scavenge gives about 70 per run against 3.6 from drops, and Horde's
  EssenceDrop skips the ×0.6 multiplier. The quest rewards "10 Merits /
  300 Essence" look swapped (`LobbyNPCRegistry.lua:94-117`).
- **X42. The implied Merit:Essence rates disagree** (eco E7): 202
  (Robux), 240–750 (auction anchor), 800 or 1,250 (respec). The Merit
  respec option is never read. The 50-Essence respec scroll costs more
  than a direct respec at 25 or 40. `SharedEventHandlers.lua:216-227`
  ignores whether the spend succeeded.
- **X43. The late-game Merit wall** (eco E8): 4.5M Merits per piece;
  Chapter 4 alone is about 350 runs, roughly 58 h per piece.
- **X44. Only the player who lands the kill gets drops, and RewardLevel
  is the party's highest level** (eco E9;
  `KillRewardManager.lua:331-334`, `MobSpawner.lua:185-188`). Tanks and
  healers starve, and a carried level-5 player gets 3.9× Merits.
- **X45. Mob physics ownership is never pinned** (perf AI-P1). There is
  no `SetNetworkOwner` anywhere, and the line check trusts the mob's
  position. Decide per tier, together with the lightweight-mover
  project.
- **X46. Add PolicyService before the Essence auction ships**, and never
  make `Leaderboard.RobuxSpent` public (exp #12).
- **X47. Daily login is hard to find, and missing one UTC day resets a
  30-day streak** (exp #10; `HUD.lua:1060`,
  `DailyLoginManager.lua:122,192`).

## Not verified (single-source, lower confidence)

- **X48. No onboarding** (exp #9). There is no tutorial or first-run
  flag, the entry point is an unlabelled "☰" (`HUD.lua:516-526`), and
  nothing points players to Commander Vex. No verifier checked this;
  the "Find Match" button is already in TODO §7.
- **X49. Tools hygiene** (sec SEC-11). No secrets were found in the
  tree or history. Remaining items:
  - `roblox_upload.mjs` takes `--api_key` on the command line, which
    leaves the key in shell history.
  - The key's environment variable is named `ROBLOX_API_KEY` in one
    script and `ROBLOX_OPEN_CLOUD_KEY` in the Python tools.
  - `.gitignore` doesn't cover `.env.*`.
  - Two Python tools hard-code a `C:\Users\...` path.
  - G20 (rotate the key) is still open.

## Receipts checklist (for when monetization is wired; exp #2)
There is no `ProcessReceipt` or MarketplaceService yet, and every Premium
entry is disabled. When they're wired:
- Put one shared receipt module in all five Places.
- Record the `PurchaseId` in the same `UpdateAsync` as the grant; this
  depends on X3.
- Return `NotProcessedYet` on any failure.
- Enforce `enabled` on the server (X34).

## Rejected by verification
- exp #2b "RespecToken grants a removed counter": it's the reward-type
  name, and both granters map it to `respec_scroll`
  (`DailyLoginManager.lua:214-218`, `AchievementManager.lua:570-573`).
- sec SEC-01 wipe-grace exploit: every player is Dead during the grace
  window, so all handlers reject.
- sec SEC-08 "swing a vote": junk indexes only amount to abstaining.
- perf RM-P1 lobby claim: the lobby has no DeathSystem, so there are no
  regen ticks there.

## Verified good (highlights)
- **Networking:**
  - Every client-to-server remote is rate limited through
    `NetworkManager.OnClientEvent`.
  - There are no RemoteFunctions and no `InvokeClient`.
  - Hit reports are advisory: an attack ticket plus a server distance
    check.
- **Player data:**
  - A load failure kicks the player instead of handing out defaults.
  - Leaving during a load is guarded, and the wipe tombstone holds.
  - The G4 teleport retry and the S3 level floor are in the lobby.
- **Economy:**
  - Shop, refine, tier, reroll and respec paths deduct before granting,
    under per-player locks.
  - There is no sell path, so no buy-then-sell loops.
  - Difficulty multipliers are applied exactly once.
- **Performance and cleanup:**
  - The MobAI snapshot and cleanup, weak-keyed SkillEffects tables, the
    DamageHandler batching, and the cached projectile query params.
- **Text:** no player-typed text reaches other players.

## Landed fixes (⚡ freebies, tag `§AGX/X<n>`)
All of these are pending a Studio live test. Syntax was checked with
the official `luau-compile`, and `luau-analyze` confirms the X1 and X50
nil-global errors are gone.

| ID | Change |
|---|---|
| X1 | Forward-declared `positionMarkers` in HordeModeSpawner. |
| X50 | Forward-declared `performRevive` in DeathSystem. |
| X9 | Pity jump is clamped to `chapterMax`. If there's no room under the cap, temper carries over. |
| X13 | Player Stun/Slow are recomputed from humanoid expiry attributes and a stamped `BaseWalkSpeed`. Knockdown captures the base speed and clears mob effects. Cast lock uses `CastMoveLock` and restores `MoveFxSpeed`. |
| X16 | `ctx.initFailed` is recorded; `RequireLoaded` errors if a critical module's Init failed. |
| X17 | Dash direction is flattened before the magnitude check, with NaN and wrong-type input rejected. The hit-report range check is now fail-closed. |
| X19 | CentralBoss `available = false` in both MainMenu and GameModeConfig (matchmaking checks it on the server). |
| X20 | Boundary force-notify only fires when the value changed. |
| X26 | Extension HTML-escapes asset names and ids. |
| X29 | NPC responses need to be within 2× `INTERACT_RANGE`. The smithType match was left out, because the UI may offer several actions. |
| X30 | Vote index must be an integer, and the voter must be eligible. |
| X31 | `lookDirection` must be a finite Vector3, and is normalised before the relay. |
| X33 | Spend rejects negative, NaN and infinite amounts. Zero is still a successful no-op. |
| X36 | The SpawnLocation lookup is cached. |
| X38 | Horde character waits are bounded (exit on leave or after 60 s). |

### Review follow-ups (code-reviewer pass on the freebies)
| ID | Change |
|---|---|
| X13 | Each slow keeps its own expiry, so a short strong slow no longer lasts as long as a long weak one. The recompute re-arms if a timer fires early. Mob effects are ignored while downed and cleared on knockdown (`MobAI.ClearPlayerMoveEffects`). |
| X9 | A pity jump that the cap cuts short now lands on the cap and **keeps** the temper bar for the next chapter, instead of spending it for +1. *(Balance call.)* |
| X20 | Also pushes when the effective max changes (a gear or talent change to the max resource). |
| X29 | ShopUI and WeaponSmithUI auto-close on walk-away (`useNpcDistanceClose`), so they can't hang on "Refining…". |
| X38 | The 60 s cutoff was removed; the wait loop exits only when the character appears or the player leaves. |
| X30b | **Pre-existing bug found in review:** a late `VoteCast` during the result grace window could re-run `_Resolve` and apply a second card. Fixed with a `voteResolved` flag. |
| X16 | No change. Note that boot now fails **hard** when a `RequireLoaded` module's `Init()` throws. Check that every place still boots in Studio. |
