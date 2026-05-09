# TODO — Parking Lot

Items identified during the V2 sanity check that are intentionally deferred.
Each entry has enough context that a future session can pick it up cold.

---

## §2.4d — Respawn counter

**Where:** `src/shared/ServerScriptService/Modules/DeathSystem.lua`
**Status:** Not tracked anywhere today.
**Proposed:** Add `data.respawnCount = data.respawnCount + 1` on every
`HandleRespawnRequest` so we can (a) surface death stats in the end-of-run
panel and (b) feed Achievements ("Die 100 times" / "Die 0 times per run").
Needs a small wire-up in `AchievementManager` listener.

## §2.6 — ShopManager full review

**Where:** `src/shared/ServerScriptService/Modules/ShopManager.lua`
**Status:** V2 audit noted the module but did not dig in.
**Proposed:** Separate review pass. Concerns flagged but not yet verified:
- Does purchase validate currency atomically? (race with SpendMerits)
- Are stock limits enforced server-side?
- Does the shop refresh snap to a server clock so players can't dodge
  rotation by reconnecting?

## Accessories — post-alpha polish

**Where:** `InventoryManager.EquipAccessory`, `AccessoryConfig`, bonus pipe.
**Status:** Equip pcall + rollback landed in §2.5c. The deeper items below
are nice-to-have, not shipping blockers.
- Per-slot rarity tiers and how they stack with the 2×Ring constraint.
- Socketing / gem system (if we ever commit to one — currently a stub).
- Client UI: show active-set bonuses in StatsMenu rather than just raw mods.

## Central-boss mode — unfinished

**Where:** `src/centralboss/**`
**Status:** Loads modules, has no authored boss fight.
**Proposed:** Pick a boss, author phases, wire telemetry + rewards. This is
post-alpha; Horde Mode is the alpha's headline mode.

## Infinite Defense / Endless Horde

**Where:** `MobSpawner.CONFIG.MaxWave = 12` (see §2.2e note in the file).
**Status:** Wave loop supports `MaxWave = nil` (infinite) but nothing else
is wired.
**Proposed:** A new place (`src/endlessmode/`) with its own `Main.server.lua`
that reuses `HordeModeSpawner` but selects `MaxWave = nil`, introduces a
procedural difficulty curve past wave 12, and rebalances reward pacing
(current merit/essence payouts assume a 12-wave ceiling).

## BonusTalentPoints grants

**Where:** `TalentManager` reads `data.Account.BonusTalentPoints` but
nothing grants it.
**Status:** Dead branch — harmless but misleading.
**Proposed:** Either (a) wire a real grant path (achievement rewards, daily
streaks, horde victory) and add UI, or (b) strip the field entirely and
add it to the deprecated-keys list in `PlayerDataManager`.

---

## Multi-server matchmaking queue (V3 follow-up)

**Where:** `src/lobby/ServerScriptService/Modules/MatchmakingManager.lua`
**Status:** Today the queue is server-local. A solo player in an empty
lobby server who queues for a 5-player mode will wait forever even if
another server has 4 players queuing for the same mode.
**Proposed:** Build a cross-server queue on top of `MemoryStoreService`:
- One sorted MemoryStoreQueue per `(modeId, difficulty)` tuple.
- Add an entry on Queue, peek-and-claim atomically when forming a match.
- Use `TeleportService:ReserveServer` so multiple lobby servers can
  rendezvous their parties into one game-mode server.
- Gracefully fall back to the current single-server matcher when
  MemoryStore is rate-limited (60 calls/min/player budget).

**Companion UI work:** the queue entry-point in the current lobby UI is
ambiguous — players don't know where to click to enter the queue.
Before the multi-server work ships, add a clear "Find Match" button on
the main lobby HUD that explicitly fires `MatchmakingRequest{action=
"Queue"}` with the currently-selected mode/difficulty. Reuses existing
PartyManager.EnsureParty so solo players don't need to manually create
a party first.

## V3 doc-only items (already commented inline; listing here for memory)

These were written as inline `--` comments during the V3 fix pass; no
follow-up code change is required, but if behaviour ever changes the
notes are the right place to revisit:

- **§LD5** `LaneDefenseMain.server.lua` — `laneDifficulty` derives via
  pcall + tostring; falls back to `"Normal"` on any error. If teleport
  data parsing ever becomes critical, surface a warn instead of silent
  default.
- **§HMS3** `HordeModeSpawner.lua:SetPartyAnchorLevel` — conditional
  `sessionStartTime` reset is intentional (Start sets it on first run;
  re-anchor resets it on subsequent calls). Don't simplify the
  `if sessionStartTime ~= 0` guard without re-reading why.
- **§HMS5** `HordeModeSpawner.lua` — speed escalation step counter
  resets on each Start. Pause→Resume effectively cancels prior
  escalation. Probably intended; revisit if pauses become a feature.
- **§VM5** `VoteManager._Resolve` — ties resolve via `math.random`.
  Deterministic replay would need a seedable RNG; not blocking.

---

_Last updated: V3 sweep + fix-session._

---

## V4 Phase A leftovers (for Phase B)

### §G5 — late joiner sees stale game state

**Where:** `GameStateManager` + HUD client.
**Status:** A player who joins during Victory/Defeat misses
`GameStateChanged` (it fired before they connected). Result: HUD shows
IDLE when the actual server is in VICTORY/DEFEAT, so the respawn /
return-to-lobby UI is wrong.
**Proposed:** On `Players.PlayerAdded`, fire `GameStateChanged`
addressed only to the new player with the current state and elapsed
time. Or: have the HUD client `RequestState` on mount and have the
server reply.

### §D1 — DefenseLine hit-animation race (verify in Phase B)

**Where:** `DefenseLine.OnMobReachedLine` → `DefenseAnimation.PlayHitAnimation`.
**Status:** Async animation callback may fire after the line is
destroyed. `DefenseHealth.IsDestroyed` guard inside `TakeDamage` should
catch it but Phase A didn't read DefenseHealth. Confirm in Phase B.

---

## V4 Phase B leftovers

### §AM4 — Wave-progress achievements never advance in HordeMode

**Where:** `AchievementManager.Init` hooks
`MobSpawner.OnWaveCompleted`. HordeMode runs via `HordeModeSpawner`,
which has no equivalent event, so HordeMode players never accumulate
`wavesSurvived` / `highestWave`.
**Status:** Dual-mode achievements are awkward today. The achievement
config is fine; we just need a runtime signal.
**Proposed:** Either (a) emit a synthesised `OnWaveCompleted` from
HordeModeMain whenever the horde level increments
(`HordeModeSpawner.GetLevel()` already exists), or (b) add an explicit
`HordeModeSpawner.OnLevelUp(callback)` hook and rename the achievement
stat to `wavesOrLevelsSurvived`. Option (a) is the cheaper retrofit.

### §HM3-followup — Re-entering a HordeMode session

**Where:** `HordeModeMain.server.lua` `OnStateChanged` "Defending"
branch.
**Status:** The Phase B fix made the reset closure write to the real
locals, but the module-load `SetState("Defending")` call still happens
BEFORE the closure is registered, so the FIRST run never observes the
transition. Module-load values cover the first run. If we ever
re-enter Defending via state-change (e.g. an in-place restart without
teleport-to-lobby), the second entry will reset correctly.
**Proposed:** Move the `SetState("Defending")` call AFTER the
`OnStateChanged` registration so the first entry is also observed.
Carry weight is small; deferring to keep the V4 diff focused.

### §UI1 — DailyLogin / CreateParty optimistic button text

**Where:** `Overlays.client.lua` (`ClaimBtn`) and
`SocialPanel.client.lua` (`CreatePartyBtn`).
**Status:** Buttons swap to "Claimed! ✓" / "Party Created! ✓"
immediately on click, before the server confirms. A server-side
rejection (e.g. already-claimed-today, party-create rate-limited)
leaves the success label up.
**Proposed:** Move the success label change into the
`DailyLoginResult { ok = true }` / `PartyUpdated` handler, and on
`{ ok = false }` re-enable the button with the original label and
display the reason. Cosmetic; not alpha-blocking.

### §UI2 — SocialPanel invite-friend wiring is dead

**Where:** `SocialPanel.client.lua:107-115`. Watches the friend list
for `Frame` children with `InviteBtn` descendants, but
`populateFriendsList` only inserts `TextLabel`s.
**Status:** "Invite friend to party from social panel" is wired in
spirit but the DOM doesn't match. Either rebuild the list to use a
Frame-per-friend layout with InviteBtn, or remove the dead handler.
**Proposed:** Defer until party UX gets a polish pass.

### §UI3 — VoteUI auto-dismiss task.delay not cancelled on unmount

**Where:** `VoteUI.lua:194` and `:232`. Three-second auto-dismiss
`task.delay` chains in the `VoteResult` and `VoteResultPersonal`
handlers continue calling `setVoteData(nil)` and
`setWinnerIndex(nil)` even after the component unmounts.
**Status:** React handles unmount-then-set-state with a warning, not
a crash. Cosmetic.
**Proposed:** Track each delay in a ref and cancel it in the
`useEffect` cleanup, mirroring the pattern already used for the
pending and timer countdowns.

### §V2 — Armor accessory pipeline is implemented but not wired

**Where:** `VisualEquipmentManager.AttachClassArmor`.
**Status:** Function works, no caller wires it. Body appearance is
currently entirely cosmetic (color/material). When real armor visuals
ship, also handle the ServerStorage.Armors lazy-load path.

---

## V4 Live-test pass leftovers

### §EV12 — Lobby click-time event mismatches still pending

**Where:** `Overlays.client.lua` button wiring.
**Status:** Boot is now clean (no "Event not found" warns). However
the following client→server fires still don't match server
listeners — the buttons silently no-op when clicked:

- `EquipItem { itemId }` — Inventory equip button. Server expects
  `EquipAccessory(player, itemId, slot)` (InventoryManager:120). Need
  to pass slot too; the inventory list UI doesn't currently know which
  slot the item is for.
- `NPCDialogChoice { choice }` — NPC dialogue choice button. Server
  expects `NPCResponse { npcId, action = "Choice", ... }`.
- `BuyShopItem { itemId }` — NPC shop buy button. Server expects
  `NPCResponse { npcId, action = "Buy", itemId, quantity }`.
- `BuyGlobalShopItem { itemId }` — Global shop buy. Server expects
  `ShopPurchase { itemId, kind, ... }` via ShopManager.
- `CastVote { option }` — Vote panel. Server expects `VoteCast(slot)`
  / `VoteCastPersonal(slot)` (positional arg).
- `ConfirmCharacterCreation` — Character creation confirm. No server
  listener; CharacterCreation flow wires differently.

**Proposed:** One pass through `Overlays.client.lua` to align each
fire to the server bus. Most are easy; `EquipItem` needs the slot
threaded into the inventory list UI first.

### §RG-MIGRATION — Migrate boot-time FireClient callsites through ReadyGate

**Where:** Any server module that fires push events during `PlayerAdded`
or `CharacterAdded`.
**Status:** `ReadyGate` is wired into all four place bootstraps and the
client-side `ClientReady` handshake is in every `*UI.client.lua`.
`TalentManager.SendState` is the only callsite migrated through it
today (worked example).
**Proposed migration order** — these are the events most exposed to
"server fires before client subscribes" boot races:

1. `AchievementManager.SendData` — fired in response to `GetAchievements`
   (already request-driven, low risk, but the unlock toast push isn't).
2. `CosmeticManager` — `WardrobeUpdate` push during PlayerAdded.
3. `EquipmentHandler` — `EquipmentInfo` reply (already request-driven).
4. `WeaponManager.EnsureStarterWeapon` — fires `WeaponEquipped` during
   PlayerAdded; current symptoms are "weapon icon not showing on first
   spawn" type intermittent bugs.
5. `ArmorManager.EnsureStarterArmor` — same shape as above with
   `ArmorEquipped`.
6. `ResourceManager` — initial `ResourceUpdate` (already in BYPASS_EVENTS
   so this is fine).

For each migration, the change is mechanical: replace
`NetworkManager.FireClient(player, "EventName", payload)` with
`ReadyGate.FireClient(player, "EventName", payload)`. Lazy-load
ReadyGate from the module's existing dependency-loader pattern so we
avoid circular requires.

The ReadyGate file's header comment lists the migration recipe.

### §SR2 — Lobby loads SkillRegistry but never SkillManager

**Where:** `LobbyMain.server.lua:92`.
**Status:** Now safe (§SR1 made SkillRegistry self-sufficient). But
loading the skill registry in a place that has no skill execution is
arguably wasted module-load time and pulls in the whole ClassSkills/*
graph for no UI consumer. If we keep it for cross-place consistency
it's harmless; if we drop it we save a bit of boot time.

**Proposed:** Quick measurement pass — log the SkillRegistry init
time, decide whether the savings are worth removing it from the lobby
load list.
