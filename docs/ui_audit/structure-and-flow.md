# RobloxDefense UI: information architecture and interaction consistency audit (ui-ux)

> **Frozen as-built spec (2026-09-26).** Kept at this path because code comments cite it. Live summary: [ARCHITECTURE § UI](../ARCHITECTURE.md#ui); its design questions are answered in [DESIGN_DECISIONS § UI](../DESIGN_DECISIONS.md#ui-decisions).

This is a static, read-only pass. I made no edits. Paths are relative to `/home/user/RobloxDefense/`, and all `src/.../UI` paths sit under `StarterPlayer/StarterPlayerScripts/UI`.

**Severity labels.** These map to the project's four levels:
- BUG = 🚨
- SPAGHETTI = 🟡
- MINOR = 🟢
- DESIGN = ❓

**Roblox input sinking.** Some findings depend on how Roblox passes clicks through GUI objects. I couldn't run Studio to confirm this, so those findings are marked *(verify in Studio)*. The relevant fact is that no UI file sets `Active = true` (a grep for `Active *= *true` over every `UI` folder returns nothing). As a result, backdrops and panel Frames probably don't sink clicks.

---

## 1. Screen map

### 1.1 How each app is mounted (the same in all 5 Places)

Every Place's `*UI.client.lua` does the following:
1. It destroys any existing `AppGui`.
2. It creates `ScreenGui "AppGui"` with `ResetOnSpawn=false`, `ZIndexBehavior=Sibling` and `IgnoreGuiInset=true`. **It sets no DisplayOrder, so the value is 0.** See `src/lobby/.../LobbyUI.client.lua:20-25`; the same code is in `LaneDefenseUI`, `HordeModeUI`, `CentralBossUI` and `SocialPlazaUI`.
3. It renders a single React root.
4. After 0.15 s it fires `ClientReady`.

| Place | Root | How it mounts children |
|---|---|---|
| Lobby | `src/lobby/UI/LobbyApp.lua` | Has 14 `useState` booleans (`:55-68`). Its `fullscreenOpen` OR-chain (`:84`) **unmounts** the HUD when any menu is open (`:92`). NPCDialog, ShopUI, WeaponSmithUI, MatchmakingUI, PartyInviteToast, EmoteWheel, AchievementToast and TestingUI are always mounted and manage themselves through server events (`:153-168`). |
| LaneDefense / HordeMode | `LaneDefenseApp.lua` / `HordeModeApp.lua` | Four-line re-exports of `CombatApp`. |
| CentralBoss | `src/centralboss/UI/CentralBossApp.lua:10-15` | A Fragment containing `CombatApp` and `BossHud`. BossHud's root has ZIndex 0 on purpose (`BossHud.lua:83-85`). |
| (combat shared) | `src/shared/UI/CombatApp.lua` | Has 9 booleans (`:43-51`). `fullscreenOpen` (`:64`) unmounts the HUD, BattleClassUI and TeammateVitals (`:73, :85, :143`). DeathUI, VoteUI, AchievementToast and TestingUI are always mounted (`:151-170`). |
| SocialPlaza | `src/socialplaza/UI/SocialPlazaApp.lua` | Only CharacterCreation, WardrobeUI and EmoteWheel. There is no HUD, no Settings and no exit. `AppearanceBar.lua` is never required. |

### 1.2 Panels: how they open, close and layer

"⋮" is the HUD's right-edge drawer (`HUD.lua:859-1088`) and "☰" is its top-left button (`HUD.lua:525-543`, Lobby only).

| Panel | Place(s) | Opens via | Closes via | Root ZIndex / chrome |
|---|---|---|---|---|
| MainMenu (mode select) | Lobby | ☰ | "X" (letter) button (`MainMenu.lua:214-225`); "Play" also closes it | 10, custom chrome |
| ClassMenu | Lobby | ⋮ Classes | AppWindow ✕ | 10, AppWindow |
| BattleClassUI (expanded) | Combat | ⋮ Classes | ✕, or a click on the dim TextButton (`CombatApp.lua:96-104`) | 6/7, custom |
| KeybindSettings | Combat only | "Controls / Rebind Keys" inside BattleClassUI (`BattleClassUI.lua:356-362, 506-509`) | own close | 102-103 |
| StatsMenu, SettingsUI, TalentTreeUI (fullscreen) | Lobby + Combat | ⋮ | AppWindow ✕ | 10, AppWindow |
| EquipmentUI, AchievementsUI, GlobalShopUI | Lobby + Combat | ⋮ | custom ✕ | 10-21, custom (known: §T10/U3) |
| WardrobeUI | all (mounted) | **nothing** (see UX-01) | custom "X" (`WardrobeUI.lua:339-347`) | 20 |
| SocialPanel | Lobby | ⋮ Social | custom ✕ (`SocialPanel.lua:702-711`) | 10/11 |
| InventoryUI, LeaderboardUI, DailyLoginUI | Lobby | ⋮ | ✕ | 10-12 |
| NPCDialog (lore/quest/teleport) | Lobby | E/ButtonA near an NPC → `NPCInteract` → server event `NPCDialogue`/`NPCQuestOffer`/`NPCTeleportOffer` (`NPCDialog.lua:86-111`) | small transparent ✕ (`:483-491`), walking away (`:142`), or reaching a dead tree node | 20 |
| ShopUI | Lobby | E → `NPCShopOpen` (`ShopUI.lua:141`) | ✕ (`:234-243`) or walking away (`:160`) | 20 |
| WeaponSmithUI | Lobby | E → `NPCSmithOpen` (`WeaponSmithUI.lua:333`) | ✕ or walking away (`:414`) | 20 |
| MatchmakingUI (banner) | Lobby | `MatchmakingUpdate` | auto after 2 s, Cancel, or Close on error | 25, top-centre y 0.03 |
| PartyInviteToast | Lobby | `PartyInvite` | Accept, Decline or ✕ | 20, bottom-centre y 0.94 |
| EmoteWheel | Lobby, Plaza | Q / DPadUp toggle (`EmoteWheel.lua:144-148`) | Q again or WASD (keyboard only, `:160-163`) | 30 (known: G19, three copies) |
| CharacterCreation | all | `CharacterCreationRequired` | `onDismiss` after completion | 12, custom fullscreen |
| VoteUI | Combat | server vote | auto | 48/50 |
| DeathUI | Combat | `DeathState` | Revive/Respawn | 100 |
| AchievementToast | Lobby + Combat | `AchievementUnlocked` | auto (queued) | 20, top-centre y 0.07 |
| BossHud | CentralBoss | `BossStateUpdate` | n/a | 0 (bar at safeTop+30, banner at safeTop+84) |
| LootNotification | combat (imperative) | `LootDrop` | fades after 4 s | separate ScreenGui, DisplayOrder 5 |
| Cast bars | combat (imperative) | skill cast | auto | ScreenGui DisplayOrder 8 (`SkillVisuals.lua:649-652`) |
| Damage flash | combat (imperative) | hit | tween | ScreenGui DisplayOrder 100 (`MobVisuals.lua:228-231`) |
| JoystickAim | Horde (touch) | automatic | n/a | ScreenGui DisplayOrder 5, bottom-right with pixel offsets (`JoystickAim.lua:47, 107-112`) |
| LoadingScreen | all | boot | `ServerReady` | DisplayOrder 1000 |

**⋮ drawer contents by Place:**
- **Lobby (11 entries):** Classes, Stats, Equipment, Talents, Achievements, Social, Shop, Settings, Inventory, Leaderboard, Daily Login. The Lobby also has ☰ for MainMenu.
- **Combat (7 entries):** Classes (opens a *different* component, BattleClassUI), Stats, Equipment, Talents, Achievements, Shop, Settings.
- **SocialPlaza:** no menu at all.

Matchmaking has **two** entry points: ☰ MainMenu and the NPC teleport offer inside NPCDialog.

---

## 2. Findings

### UX-01. BUG: WardrobeUI can't be reached in any Place
- **Evidence:**
  - `LobbyApp.lua:97` and `CombatApp.lua:78` pass `onCosmeticsClick`.
  - `HUD.lua:126` destructures `onCosmeticsClick` but never renders a button for it.
  - The nav grid skips from `LayoutOrder = 3` (Equipment, `HUD.lua:954`) to `5` (Talents, `:968`).
  - In SocialPlaza, `setShowWardrobe` is declared (`SocialPlazaApp.lua:29`) and never called with `true`.
  - `AppearanceBar.lua:80`, the component that owns the Wardrobe button, is never required anywhere.
  - `git log -S` shows the HUD has had no cosmetics button since v0.5 (`d862558`).
- **Failure:** players can't equip cosmetics anywhere. The Plaza's stated purpose ("appearance-centric", `SocialPlazaApp.lua:4-9`) is dead.
- **Fix shape:** add a `navWardrobe` button at LayoutOrder 4, and mount `AppearanceBar{onWardrobeOpen = ...}` in SocialPlazaApp. With the proposed registry (§3.2) this becomes a single entry.

### UX-02. BUG: opening any menu unmounts the HUD, which resets combat state to "Idle"
- **Evidence:**
  - `CombatApp.lua:73` renders `hud = (not fullscreenOpen) and ...`, and `LobbyApp.lua:92` does the same.
  - HUD state is local and initialised to `gameState "Idle"` (`HUD.lua:168`), `runEnded false` (`:171`) and `betweenWaves false` (`:192`).
  - The subscription effect is torn down on unmount (`:429-453`).
  - `GameStateChanged` is only broadcast on transitions (`GameStateManager.lua:111`). The only per-player re-push is HordeMode's late-joiner path (`HordeModeMain.server.lua:508`), which isn't triggered by a HUD remount.
- **Failure:** during `Defending`, the player opens Stats and then closes it. The HUD remounts in "Idle" and shows **"▶ Start Game"** (`HUD.lua:651`) in the middle of a wave. Clicking it only produces a server `warn` (`GameStateManager.lua:176-178`), so the player gets no feedback. At the same time:
  - "Next Wave" disappears (`:813`).
  - After a Defeat or Victory, "Return to Lobby" disappears (`:835-837`) and "Start Game" appears instead. This undoes the §AGX/X14 escape hatch.
  - Wave banners and killfeed events that fire while a menu is open are lost.
  - TeammateVitals also unmounts (`CombatApp.lua:143`).
- **Fix shape:** keep the HUD mounted and pass `visible = not fullscreenOpen`. Alternatively, lift run state into a module-level store, the way `cachedDefenseHP` already does at `HUD.lua:30, 200-202`. The shell in §3.3 does this structurally.

### UX-03. BUG: NPC shop, quest and teleport results go to NPCDialog, which closes itself and drops the message
*(Partial overlap, known: §DISC/D8 "no server→client feedback channel", T5-T9_SWEEP.md:96-98. The mechanism described here is new.)*
- **Evidence:**
  - ShopHandler reports purchase results as `FireClient(player, "NPCDialogue", {type="ShopSuccess"/"ShopError", message})` (`ShopHandler.lua:75-117`). QuestHandler does the same with `QuestAccepted`/`QuestError` (`QuestHandler.lua` ~`:249-320`).
  - The React NPCDialog treats every `NPCDialogue` as a lore tree: it sets `tree = data.dialogue` (nil) and node `"start"` (`NPCDialog.lua:86-97`).
  - The render path then finds `node == nil` and calls `closeDialog()` during render (`:160-165`). That sets state inside render and fires `NPCResponse{action="Close"}`.
  - ShopUI's own result listener subscribes to `NPCResponse` (`ShopUI.lua:147-149`), which the server never sends to clients, and ignores it anyway.
  - The only feedback the player sees is "Purchasing…" for 2 s (`ShopUI.lua:121-124`).
- **Failure:** a purchase fails (not enough Essence, level too low) and the player sees "Purchasing…" disappear with no explanation. Accepting a quest works the same way.
- **Fix shape:** in NPCDialog, branch on `data.type` and route `Shop*`/`Quest*`/`Teleport*` to the shared notifier (§3.4) or to ShopUI's inline status. Don't treat these payloads as trees, and never call `closeDialog` during render.

### UX-04. BUG: no touch path for Attack, Skills, Dash or NPC Interact
- **Evidence:**
  - `InputActions.lua:14-15` says "mobile on-screen buttons call `InputSystem.FireAction()`". **`FireAction` doesn't exist**: the only grep hit is that comment.
  - Every `Touch` binding is `{}` (`InputActions.lua:30, 42, 54, 98`).
  - Attack is `MouseButton1`, and a touch arrives as `UserInputType.Touch` (`InputSystem/init.lua:117-131`).
  - No UI file creates skill or attack buttons.
  - The NPC prompt is a non-interactive `BillboardGui`/`TextLabel` (`NPCInteraction.lua:138-167`), and interaction only happens through the `Interact` action (`:60-64`).
- **Failure:** on a phone, the player can move (the Roblox thumbstick) and aim in Horde (JoystickAim), but can't attack, cast, dash, or talk to an NPC. Without NPCs, shop, smith, quests and teleport are all closed off. This blocks the "defined Mobile layout" Pablo asked for.
- **Fix shape:**
  1. Implement `InputSystem.FireAction(name, state)`.
  2. Add an action-cluster component to the bottom-right region (§3.5).
  3. Replace the billboard with a `ProximityPrompt`, which handles touch, gamepad and keyboard natively, or make it an `Active` BillboardGui button.

### UX-05. BUG: a HUD menu and an NPC panel can be open at the same time, and two NPC panels can stack
- **Evidence:**
  - NPC panels aren't part of `fullscreenOpen` (`LobbyApp.lua:84`) and render at ZIndex 20 (`NPCDialog.lua:455`, `ShopUI.lua:208`, `WeaponSmithUI.lua:444`). AppWindow menus render at 10 (`StatsMenu.lua:296` and others).
  - `NPCInteraction` fires `NPCInteract` whenever `nearestNPC` is set (`NPCInteraction.lua:60-64`), without checking whether any panel is open.
  - The shop `blacksmith` at (20, 10) (`LobbyNPCRegistry.lua:67`) is **7 studs** from the smith `refiner` at (25, 15) (`:259`). Both are inside the 12-stud interact range and the 16-stud auto-close range.
- **Failure:** the player opens Stats and presses E beside an NPC. The NPC panel renders **over** Stats, the two close independently, and the backdrops stack their dimming. Similarly, the player opens the Blacksmith shop, steps toward the Refiner and presses E. ShopUI and WeaponSmithUI then overlap at the same ZIndex, and the draw order depends on sibling order.
- **Fix shape:** use the single-open panel stack (§3.3). Have NPCInteraction ask `PanelStack.isOpen()` (or switch to context `"UI"`, see UX-06) before it fires.

### UX-06. SPAGHETTI: the "UI" input context exists but menus never set it, so game input keeps running behind panels
- **Evidence:**
  - `InputSystem/init.lua:22` defines `"UI" — full-screen menus (all game actions suppressed)`.
  - The only caller is HordeMode's pause handler (`HordeModeClient.client.lua:129`). No panel sets it.
  - SettingsUI's rebind capture uses a raw `UserInputService.InputBegan` (`SettingsUI.lua:279-299`), and InputSystem sees the same key press at the same time.
- **Failure:** in combat with Stats or Talents open, Q/E/R/F still cast skills. Pressing Q to rebind a key in Settings during a fight casts Skill 1. Clicks on the windowed backdrop (a plain Frame, `AppWindow.lua:355-361`) can reach `Attack` because nothing sinks them *(verify in Studio)*.
- **Fix shape:** have the panel stack call `SetContext("UI")` on its first push and restore the previous context on its last pop. Give the AppWindow backdrop `Active = true`. The ❓ question of whether skills should be castable with a menu open is Pablo's call (see D-3).

### UX-07. SPAGHETTI: seven close/dismiss conventions
- **Evidence:**
  - AppWindow uses a red square ✕ sized from the header height (`AppWindow.lua:307-326`).
  - MainMenu uses the letter "X" (`MainMenu.lua:220`), and so does WardrobeUI (`WardrobeUI.lua:342`).
  - NPCDialog uses a transparent ✕ at 8%×10% of a panel that's 0.45×0.35 of the screen, about 3.6% of screen width (`NPCDialog.lua:483-491`). ShopUI uses 6%×8% of a 0.5-wide panel (`ShopUI.lua:234-243`).
  - The BattleClassUI reference closes on any click on the dim layer (`CombatApp.lua:96-104`). No other panel supports clicking outside to close.
  - EmoteWheel closes on WASD (`EmoteWheel.lua:160-163`), which doesn't cover gamepad or touch.
  - Distance close exists only on the NPC panels.
  - There is no Esc, B or back handling anywhere: a grep for `KeyCode.Escape` finds it only as a rebind-cancel inside `SettingsUI.lua:283` and `KeybindSettings.lua:169`.
- **Failure:** the player can't predict how to leave a screen. On mobile, the NPC and Shop ✕ targets are well below the 44 pt minimum.
- **Fix shape:** the panel stack owns the close behaviour: ✕ in the chrome, B/Back, optional click-outside, and distance for NPC panels (§3.3). Note that **Esc belongs to the Roblox system menu**, so don't depend on it. Whether `InputBegan` reliably sees Esc is **unspecified**.

### UX-08. SPAGHETTI: ZIndex and DisplayOrder layering is ad hoc; imperative ScreenGuis draw over every menu
- **Evidence:**
  - `AppGui` has DisplayOrder 0.
  - `LootNotification` is 5 (`LootNotification.lua:54`), `JoystickAim` is 5 (`JoystickAim.lua:112`), the cast bar is 8 (`SkillVisuals.lua:652`) and the damage flash is 100 (`MobVisuals.lua:231`).
  - Inside AppGui there are magic numbers: 3, 6, 10, 12, 20, 21, 25, 30, 48, 50, 100 and 102.
- **Failure:** with Talents (fullscreen) or Vote open in combat, the loot counter, cast bar and red damage flash all render *on top of* the menu. On touch, the aim joystick sits over any fullscreen panel.
- **Fix shape:** add `Theme.Layers` (ZIndex bands) and `Theme.DisplayOrder` (for example: world-HUD imperatives 1-4, AppGui 10, flash 11, loading 1000). Hide the imperative GUIs while the stack is non-empty.

### UX-09. SPAGHETTI: the top-centre strip has 8 unrelated occupants
- **Evidence:**
  - MatchmakingUI, y 0.03 (`MatchmakingUI.lua:128-133`)
  - AchievementToast, y 0.07 (`AchievementsUI.lua:444-453`)
  - Start / Countdown / Next Wave, safeTop+34 (`HUD.lua:653, 671, 815`)
  - Wave banner, safeTop+88 (`:715`)
  - BossHud bar at safeTop+30 and phase banner at safeTop+84 (`BossHud.lua:89, 142`)
  - VoteUI pending alert, y 0.12 (`VoteUI.lua:324`)
  - Return button, y 0.14 or 0.22 (`HUD.lua:839`)
- **Failure:** in CentralBoss, a countdown or wave banner lands inside the boss bar's band. In the Lobby, an achievement unlocked during a queue overlaps the matchmaking banner.
- **Fix shape:** have one "banner" region slot with a priority queue (§3.4, §3.5).

### UX-10. MINOR: the ☰ button and currency strip ignore the GUI inset
- **Evidence:**
  - With `IgnoreGuiInset=true`, `menuBtn` sits at (0.005, 0.008) (`HUD.lua:526-527`) and `currencyStrip` at (0.04, 0) (`:547`).
  - `safeTop` is computed at `:193-194` but is only applied to the centred items.
  - BattleClassUI does use a safe left/top (`BattleClassUI.lua:416`).
- **Failure:** the ☰ button likely sits under Roblox's top-bar menu button. On notched phones, the currency strip may fall under the notch. The exact overlap depends on the top-bar version and device, so it is **unspecified**.
- **Fix shape:** add inset-aware region frames in the shell, and set `ScreenInsets = DeviceSafeInsets` where available.

### UX-11. SPAGHETTI: feedback is split across 5 mechanisms with 5 timings
- **Evidence:**
  - Inline status labels auto-clear after different delays:
    - ShopUI: 2 s (`:122`)
    - ClassMenu: 2.5 s (`:282`, no mounted guard)
    - GlobalShopUI: 3 s (`:251`)
    - StatsMenu respec: 3 s (`:235`)
    - SocialPanel `PartyError`: 3.5 s (`:618`)
    - WeaponSmithUI: 3.5 s (`:345`)
  - HUD transient labels: wave banner 3 s, killfeed 4 s, combo summary 4 s (`HUD.lua:302, 377, 388`).
  - A queued toast (achievements).
  - An imperative stacking counter (LootNotification).
  - Server-`warn`-only rejections that the client never sees: `RequestStartGame` (`GameStateManager.lua:176-185`) and the NPC results in UX-03.
  - EquipmentUI subscribes to refine/tier/reroll results and discards the payload (`EquipmentUI.lua:410-429`, `function(_data)`).
- **Failure:** the same kind of event (for example "action rejected") looks different, or doesn't show at all, depending on which screen triggered it.
- **Fix shape:** a single `Notify` service with a fixed set of kinds (§3.4).

### UX-12. MINOR: loading, empty and error states are inconsistent
- **Evidence:**
  - InventoryUI distinguishes "Loading…" from "No accessories owned." (`InventoryUI.lua:71`).
  - LeaderboardUI shows "Loading…" for *any* empty list, including a board that is genuinely empty (`LeaderboardUI.lua:119-124`).
  - DailyLoginUI shows "Loading…" (`:67`).
  - Other panels have no pending state that I could find; whether EquipmentUI renders anything while `weaponData == nil` (`:374`) is **unspecified**.
  - There's no timeout or error state (hang recovery is known: §NM-D6).
- **Fix shape:** add a shared `<AsyncBody state="loading|empty|error|ready">` to AppWindow's body slot.

### UX-13. SPAGHETTI: two keybind editors with different reachability
- **Evidence:**
  - SettingsUI has Skills and Controls rebind tabs (`SettingsUI.lua:4-6, 297-299`), reachable in every place that has ⋮.
  - KeybindSettings is a separate fullscreen editor reachable **only** from the combat BattleClassUI reference (`BattleClassUI.lua:356-362, 506-509`).
  - Both write `SaveKeybindings`.
- **Fix shape:** keep one editor, as a tab inside Settings, and have BattleClassUI deep-link to it through `PanelStack.open("settings", {tab="controls"})`.

### UX-14. BUG *(verify in Studio)*: clicking empty space inside the class reference closes it
- **Evidence:**
  - The panel is a child of a full-screen `TextButton` whose `Activated` closes it (`CombatApp.lua:96-104`).
  - The panel's Frames aren't `Active`, so a click on a non-button area probably falls through to the parent button.
- **Fix shape:** use AppWindow chrome with an `Active` panel, and use one click-outside policy everywhere.

### UX-15. MINOR: no gamepad navigation model
- **Evidence:**
  - There are zero uses of `SelectionGroup`, `NextSelection*`, `GuiService.SelectedObject` or `Selectable` in any UI file.
  - No action opens the menu.
  - `ButtonB` is bound to Dash (`InputActions.lua:40`), which collides with B as the conventional "back".
- **Failure:** gamepad players have to use Roblox's generic virtual-cursor or selection mode. No panel gives initial focus.
- **Fix shape:** set `GuiService.SelectedObject` to a first-focus ref on push, use `SelectionGroup=true` on the panel root, and make B close the top panel while in context "UI". Dash is suppressed there anyway.

### UX-16. DESIGN: SocialPlaza has no shell, no settings and no exit
- **Evidence:**
  - SocialPlaza is intentionally a sandbox (`SocialPlazaMain.server.lua:4-13`).
  - The client has no HUD and no way to return to the Lobby (a grep for `ReturnToLobby`/`Teleport` in `src/socialplaza` finds nothing client-side).
- **Question for Pablo:** is this Place player-facing? If it is, it should get the shell (top bar, Settings, Wardrobe, Return).

### UX-17. MINOR: small consistency leftovers
- **HUD nav labels:** only "Classes" goes through `Locale.Get` (`HUD.lua:925`); the other labels are hard-coded English with mixed emoji prefixes (`:1011, 1028, 1043, 1058, 1075`).
- **Duplicate matchmaking entry points:** see §1.2.
- **Theme adoption:** `Theme` is required only by `Common/*` (3 files); 28 UI files still declare their own `local C = {}` palette, including the six "converted" AppWindow users. *(Known: §T10/U3 recipe step 4. Listed only as a migration input.)*
- **Stale TODO:** TODO §DISC/D8 still lists "[P2] wire useNpcDistanceClose into ShopUI + WeaponSmithUI". That work is **done** (`ShopUI.lua:160`, `WeaponSmithUI.lua:414`), so the TODO line is out of date.
- **Distance close is inconsistent:** ShopUI's distance-close path doesn't send `NPCResponse Close` (`ShopUI.lua:160-163`), but its ✕ path does (`:193-199`). NPCDialog sends it in both paths.

---

## 3. Proposal: one "UI shell"

### 3.1 Principles
1. **One root per Place, one registry for the whole game.** Places declare *which* entries exist. They don't declare *how* those entries open.
2. **The HUD is never unmounted.** It is hidden or dimmed while a panel is open. This fixes UX-02 by construction.
3. **At most one panel open.** Sub-panels (for example Keybinds from Settings) push onto a stack, and any other open request replaces the stack.
4. **Every close path goes through one function**: ✕, B/Back, click-outside (per panel), distance (NPC panels), and server-forced close.

### 3.2 Navigation model: a registry and one menu surface
Add a `UI/Shell/Registry.lua` with entries of this shape:
```lua
{ id="stats", label="menu_stats", icon="stats", component=StatsMenu,
  variant="windowed", places={Lobby=true, Combat=true}, group="character", hotkey=nil }
```
**Groups (the same order in every Place):**
- **Play:** Play/Queue (Lobby), Return (Combat post-run)
- **Character:** Class, Stats, Talents, Equipment, Wardrobe, Inventory
- **Progress:** Achievements, Leaderboard, Daily
- **Social:** Party/Social
- **Store:** Shop
- **System:** Settings

Entries that don't apply to a Place are **shown locked with a reason** (for example "Available in Lobby") rather than hidden. That keeps muscle memory stable across Places.

**Options for how the menu is presented (Pablo's call, D-1):**
- **A. Persistent icon rail** on the right edge: 6 group icons that open flyouts. It's the fastest on PC and mobile, it's always visible, and it suits the icon set that's already been delivered (§T10/ICONS). **This is my recommendation.**
- **B. Keep the ⋮ drawer** but drive it from the registry. Least effort, but the layout is still a 2-column grid of text buttons.
- **C. A radial wheel** (hold Tab / L-stick-click / long-press). Best for gamepad, and it reuses the EmoteWheel geometry. It could be the gamepad presentation of A.

Whichever option is chosen, ☰ MainMenu becomes the "Play" group entry (a primary CTA in the Lobby top bar). The NPC teleporter stays as a diegetic second entry point but opens the **same** panel (MainMenu), not an NPC-specific list.

### 3.3 Panel manager (`UI/Shell/PanelStack.lua`, React context and provider)
**API:** `open(id, props)`, `push(id, props)`, `close(id?)`, `closeTop()`, `isOpen(id?)` and `top()`.

**Rules:**
- **Single-open.** `open` replaces the stack and `push` layers on top.
- **Server-opened panels** (NPCShopOpen, NPCSmithOpen, NPCDialogue, CharacterCreation) are subscribed **once in the shell** and turned into `open(...)` calls. The self-managing `onClose = function() end` mounts go away (`LobbyApp.lua:159-165`).
- **Priority classes:**
  - `system` (Death, Loading) overrides everything and blocks the stack.
  - `modal` (Vote, CharacterCreation) suspends the stack and restores it afterwards.
  - `panel` covers menus and NPC panels.
  - A `modal` arriving during a `panel` hides the panel without destroying its state.
- **Input.** On the first push, save the context and `SetContext("UI")`; restore it on the last pop. Set `GuiService.SelectedObject` to the panel's `firstFocus` ref.
- **Close sources.** The ✕ in AppWindow chrome; `ButtonB` and `Backspace` via a new `InputActions.UIBack` action in context `UI`; click-outside when `entry.dismissOnBackdrop` is set; `useNpcDistanceClose` driven by `entry.npcId`.
- **Chrome.** AppWindow becomes the only chrome. Add a `variant="dialog"` for the NPC bottom sheet and an `Active=true` backdrop.
- **Layers.** Use `Theme.Layers = { hud=1, hudOverlay=5, panel=10, modal=40, toast=60, system=100 }`. No component hard-codes a ZIndex outside its band.

### 3.4 Notification system (`UI/Shell/Notify.lua` plus a host component)
**Kinds, each with one region and one timing:**

| Kind | Region | Behaviour | Replaces |
|---|---|---|---|
| `toast` | top-right stack | max 3 visible, 3.5 s, queued, severity colours from Theme | inline status labels in ClassMenu, GlobalShop, Stats and Social; the NPC results in UX-03 |
| `banner` | top-centre single slot | priority queue: boss phase > run state > wave > matchmaking > achievement | HUD wave banner, BossHud banner, VoteUI alert, MatchmakingUI, AchievementToast |
| `feed` | right, under the objectives | killfeed and loot counter | HUD deathFeed, LootNotification |
| `inline` | inside the panel | `useRequest(eventName)` returns `pending/ok/err`, and the button shows a spinner | optimistic labels (known: §UI1) |

**Server side:** add one generic push event `Notify {kind, key, args, severity}` (ReadyGate-routed). This closes the §DISC/D8 feedback-channel gap for `RequestStartGame` rejections, NPC results and the class-unlock toast (known: TODO §14).

### 3.5 Shared HUD regions
The shell renders fixed, inset-aware region frames. Components mount *into* a region and never position themselves on the screen.

| Region | Lobby | Lane / Horde | CentralBoss | SocialPlaza |
|---|---|---|---|---|
| **Top-left** | Play (queue) CTA + menu rail toggle | class badge (BattleClassUI) | class badge | menu toggle |
| **Top-centre banner** | matchmaking / achievements | Start / Countdown / Next Wave / Return + wave banner | **boss bar** (owns the slot) + phase banner | none |
| **Top-right** | currencies + power | currencies + power | currencies | currencies |
| **Left-middle** | party roster (compact) | **party vitals** (TeammateVitals moves here from `x=1-8px, y=120px`) | party vitals | none |
| **Right-middle** | menu rail | objectives: defense-line HP (Lane), wave/kill count (Horde) + loot feed + killfeed | boss adds / objectives + feeds | menu rail |
| **Bottom-left** | self vitals (HP/Res/XP) | self vitals | self vitals | none |
| **Bottom-centre** | invite toast | **action bar**: Attack, Skill 1-4 with cooldowns (from `SkillInput` `SkillCooldownUpdate`) and key glyphs, Dash; combo above | same | emote hint |
| **Centre** | none | vote, death, combo summary (modal/system layers) | same | emote wheel |

Two notes on this layout:
- There is currently **no skill or cooldown display on any platform**. `SkillInput.lua:14-15, 46-48` tracks cooldowns but nothing renders them. The action bar is new UI, and `Theme.Icons.attack`/`skillLocked` already reserve the art for it.
- The table above is the *PC* layout.

**Mobile (compact) layout.** Switch to compact when `TouchEnabled and not KeyboardEnabled`, or when the shortest viewport side is under about 500 px:
- **Controls:**
  - Bottom-left is left free for the Roblox thumbstick, and self vitals move to a compact strip at top-left under the inset.
  - The action bar becomes a **bottom-right thumb cluster**: a large Attack button, four skills in an arc, and Dash. It uses the new `InputSystem.FireAction`.
  - In HordeMode, JoystickAim moves *into* the cluster (for example, aim-drag on Attack) instead of using its own bottom-right ScreenGui (`JoystickAim.lua:47`).
- **Layout:**
  - The menu rail collapses to one top-left button that opens a fullscreen menu sheet.
  - `windowed` panels are promoted to `fullscreen` automatically.
  - Every hit target gets `UISizeConstraint.MinSize ≈ 44×44`.
  - The NPC prompt becomes a `ProximityPrompt` (UX-04).

### 3.6 Taste decisions for Pablo
- **D-1:** rail (A), drawer (B) or radial (C), or A on PC and mobile with C on gamepad.
- **D-2:** in combat, should menus open as a translucent side sheet that keeps party vitals and the banner visible, or as today's full dim?
- **D-3:** with a menu open in combat, should skills be suppressed (context "UI") or stay live, so that only mouse clicks are sunk?
- **D-4:** should clicking outside a panel close it (today only the class reference does), and should that apply to all panels or only small dialogs?
- **D-5:** should toasts go top-right (my proposal) or bottom-centre?
- **D-6:** should Daily Login auto-open on the first Lobby join of the day (today it's only reachable from the menu)?
- **D-7:** should SocialPlaza get the full shell (UX-16)?

---

## 4. Migration plan (effort is a rough static estimate; Studio testing is extra)

| Phase | Scope | Effort |
|---|---|---|
| **P0: bug fixes, no architecture change** | UX-01 (Wardrobe button + AppearanceBar mount), UX-02 (hide the HUD instead of unmounting it), UX-03 (NPCDialog `type` branch + ShopUI status), UX-14 | 0.5-1 day |
| **P1: shell skeleton** | `Shell/Registry`, `Shell/PanelStack` (context), `Theme.Layers`/`DisplayOrder`, `UIBack` action, SetContext("UI"). Migrate the LobbyApp/CombatApp/SocialPlazaApp boolean tables to the registry. Every panel already takes `onClose`, so each migration is mostly a registry row. Move NPC server-open events into the shell (fixes UX-05) | 2-3 days |
| **P2: Notify** | Host + 4 kinds, the server `Notify` event, and migration of the 6 inline status timers, the HUD banners, AchievementToast, MatchmakingUI and LootNotification | 2 days |
| **P3: HUD regions** | Split `HUD.lua` (1093 lines) into region components (TopBar, Vitals, RunControls, Objectives, NavRail). Move TeammateVitals and the BossHud slot. New ActionBar with cooldowns | 3-4 days |
| **P4: Mobile** | `InputSystem.FireAction`, the touch action cluster, compact mode switch, ProximityPrompt NPCs, min-size constraints, safe insets, windowed→fullscreen promotion | 3-5 days |
| **P5: Gamepad** | SelectionGroup + first-focus on every panel, rail/radial navigation, glyph swap in the action bar | 1.5-2 days |
| **P6: chrome and palette completion** *(known: §T10/U3)* | Convert the 14 remaining panels to AppWindow (`dialog` variant for NPC panels), migrate the 28 local palettes to Theme, merge the keybind editors (UX-13), shared AsyncBody states (UX-12) | 3-4 days |

The recommended order is P0 → P1 → P2, then P3 and P4 together (the mobile layout is a region concern), then P5 and P6. P1 and P6 can overlap, because each AppWindow conversion is also the panel's registry migration.

---

## 5. Verified good
- AppWindow gives every converted menu one `onClose` contract, a standard ✕ and a single chrome (`AppWindow.lua:218-381`). It's the right seam for the stack.
- `useNpcDistanceClose` has a correct no-op contract and cleanup (`useNpcDistanceClose.lua:11-54`) and is wired into NPCDialog, ShopUI and WeaponSmithUI.
- Every Place mounts one `AppGui` with `ResetOnSpawn=false`, destroys stale copies, and fires `ClientReady` after mount (`*UI.client.lua:15-46`).
- LobbyApp, CombatApp and SocialPlazaApp all subscribe to `CharacterCreationRequired` *before* firing `RequestCharacterStatus`, which avoids the join race (`LobbyApp.lua:71-82`).
- HUD task delays are guarded by `mountedRef` (`HUD.lua:302, 312, 377, 388`), and `cachedDefenseHP` survives remounts (`:30, 200-202`).
- MatchmakingUI has a launch timeout and dismissible errors with Retry (`MatchmakingUI.lua:74-88, 150-200`).
- BossHud deliberately sits below the menus (`BossHud.lua:83-85`).
- LoadingScreen is correctly the topmost layer (DisplayOrder 1000, `LoadingScreen.lua:62`).
- TalentTreeUI and SettingsUI already accept `UserInputType.Touch` for pan and slider (`TalentTreeUI.lua:513, 668`; `SettingsUI.lua:80`).
- MatchmakingRequest handling and the NPC shop item id/itemId pair are consistent between client and server (`LobbyNPCRegistry.lua:41-43`).
