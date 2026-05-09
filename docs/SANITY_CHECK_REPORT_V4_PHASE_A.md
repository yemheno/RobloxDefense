# Sanity Check Report — V4 Phase A

Coverage: modules V1/V2/V3 only grazed — Skills, Talents, DefenseLine,
GameStateManager, ShopManager, Drops, AttackHandler, HitTracker.

Phase B (scheduled at 04:01 local) will cover Cosmetics, Achievements,
DailyLogin, HordeModeMain end-to-end, HordePauseManager,
HordeModeMapLoader, lobby NPCs/SceneManager, Weapon/Armor refinement,
remaining client UI.

Severity tags: **P0** ship-blocker · **P1** likely visible bug ·
**P2** quality / future-proof · **Doc** comment only.

---

## §S — SkillManager

### §S1 (P0) — atomic per-player request lock

`TryUseSkill` performed cooldown + casting checks before deducting
resource and starting cooldown. Two `SkillRequest` packets in the same
network frame would both pass the checks and both spend resource —
duplicated cast worth real damage. Added a per-player `skillRequestLock`
that rejects reentrant calls outright.

### §S2 (P1) — UpdateCasting iteration safety

`pairs(playerCasting)` while `CompleteCasting` set
`playerCasting[player] = nil` is undefined for hash mutation. Switched
to the same two-pass collect-then-mutate pattern UpdateBuffs already
uses.

### §S3 (P1) — knockdown during cast → interrupt

`CompleteCasting` had no `CanPlayerAct` check. A player knocked down
mid-cast would still execute the skill on cast-time expiry. Now routes
through `InterruptCasting`.

### §S4 + §S5 (P1) — Parent guards on Complete/Interrupt

`SetAttribute` on a leaving Player throws. Added `if not player.Parent`
short-circuits in both functions.

### §S7 (Doc)

`BUFF_STAT_MAP` aliases `AttackSpeedDown → AttackSpeed`; callsites are
expected to pass a negative `amount`. Document only.

---

## §T — TalentManager

### §T1 (P0) — respec deduct-first

`RespecAll` cleared the talent table BEFORE consuming the scroll/essence.
Any failure in the deduct left the player with zero talents AND zero
charge taken. Reordered: deduct first, abort on failure, only respec
once the cost is locked in.

### §T2 (P1) — atomic AllocateNode lock

Same race shape as §S1 — two `AllocateTalent` packets could both pass
the points check before either mutated the allocated table. Added
per-player `allocateLock`.

### §T4 (Doc) — `BonusTalentPoints` dead branch

Already noted in `TODO_PARKING_LOT.md`. Confirmed: no code grants it.

---

## §G — GameStateManager

### §G2 (P1) — idempotent ReturnToLobby

Both auto-return delays (Victory and Defeat fire at 10s) and any manual
caller could queue multiple teleport sweeps + double reset. Added
`_returnInFlight` latch released after a 2-second tail.

### §G4 (Doc) — ResetGame timing

`ReturnToLobby` fires teleport callbacks on `task.spawn` and immediately
calls `SetState(IDLE)` → `ResetGame` which destroys mobs and heals
players. Remaining-on-server players see the cleanup happen before
their teleport-out animation completes. Cosmetic; document.

### §G5 (P1) — late joiner state sync

A player who joins during Victory/Defeat misses the GameStateChanged
event. **Deferred to Phase B** — needs a check on the HUD client side
to call `RequestStartGame` or a fresh state on player-added. Adding to
parking lot.

---

## §D — DefenseLine

### §D2 (P1) — LateInit idempotency

`Init` task.defers a LateInit, but place bootstraps explicitly call
LateInit too — running twice. Added `_lateInitDone` latch.

### §D1 (Doc) — animation-callback safety

`OnMobReachedLine` runs an async hit-animation. If the line is destroyed
mid-animation, the callback still fires `TakeDamage`. `DefenseHealth.IsDestroyed`
guard inside should catch it but verify in Phase B.

---

## §Sh — ShopManager

### §Sh1 (P0) — purchase deduct-first

Both `PurchaseCosmetic` and `PurchaseConsumable` granted the item
BEFORE attempting `SpendMerits/SpendEssence`. If the spend ever
returned false (concurrent spend race, balance bug), the player kept
the item for free. Refactored to deduct-first; on grant failure,
refund the cost.

### §Sh2 + §Sh3 (P1) — concurrent purchase lock

Two `ShopPurchase` packets in the same frame could both pass `canAfford`
checks and both grant. Added `withPurchaseLock(player, fn)` wrapper
shared by all three Purchase* paths.

### §Sh4 (Doc)

Failed purchases no longer need a SendShopState refresh because nothing
mutated. Kept the behaviour as-is.

---

## §Dr — DropManager

### §Dr1 (P1) — Parent guard in ProcessKill

If the killer disconnected between damage hit and mob-death rewards,
`AddMerits` and `FireClient` ran on a leaving Player. Added early
`player.Parent` short-circuit.

### §Dr2 / §Dr3 (Doc)

RNG seed and difficulty cache documented; no fix needed.

---

## §A — AttackHandler

### §A1 (P1) — bounded ticket eviction

`pruneTickets` evicted at most one ticket per call. A flood of
`attackId`s in one frame could grow the table beyond the 5-ticket cap
until enough subsequent prunes ran. Now loops while over cap.

### §A2 / §A3 / §A4 (Doc)

Lifecycle is already correct; documented for memory.

---

## Files edited in Phase A

- `src/shared/ServerScriptService/Modules/SkillManager/init.lua`
- `src/shared/ServerScriptService/Modules/TalentManager.lua`
- `src/shared/ServerScriptService/Modules/GameStateManager.lua`
- `src/shared/ServerScriptService/Modules/DefenseLine/init.lua`
- `src/shared/ServerScriptService/Modules/ShopManager.lua`
- `src/shared/ServerScriptService/Modules/DropManager.lua`
- `src/shared/ServerScriptService/Modules/AttackHandler/init.lua`

All 7 pass structural `function+do+if == end` balance.

---

_Phase A complete. Phase B fires at 04:01 local — covers Cosmetics,
Achievements, DailyLogin, HordeModeMain end-to-end, lobby NPCs,
remaining client UI._
