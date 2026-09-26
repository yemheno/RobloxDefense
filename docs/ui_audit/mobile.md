# UI-MOBILE: mobile layout audit and specification (RobloxDefense)

This was a read-only static pass. No repo files were edited. All paths are relative to `/home/user/RobloxDefense`.
Severity tags (plain text instead of emoji): **[BUG]** = bug, **[SPAG]** = spaghetti, **[MINOR]** = minor, **[DQ]** = design question for Pablo.
Items that overlap known work are tagged *(known: ...)*. None of this touches the Audit_4.7 §10 decided-against list.

## 0. Method and assumptions

- **Viewports, landscape, in Roblox pixels (points):** iPhone **844x390**, small Android **800x360**, tablet **1024x768**. The 1920x1080 figure is included where it shows a bug on PC as well.
- All five React roots set `IgnoreGuiInset = true` (`src/lobby/.../LobbyUI.client.lua:24`, `src/lanedefense/.../LaneDefenseUI.client.lua:24`, `src/hordemode/.../HordeModeUI.client.lua:24`, `src/centralboss/.../CentralBossUI.client.lua:24`, `src/socialplaza/.../SocialPlazaUI.client.lua:24`). So Scale resolves against the full viewport.
- Scale values nest: a child's Scale multiplies its parent's absolute size. Every estimate below walks the parent chain.
- **Unspecified (not in repo, must be checked in Studio or on a device):**
  - Roblox topbar height. `GetGuiInset().Y` is assumed ~58 px (current topbar), so `safeTop` = 68.
  - Roblox PlayerModule geometry:
    - DynamicThumbstick zone is roughly the left 40% x bottom 2/3 of the screen.
    - The jump button on screens whose short side is 500 px or less is 70 px at `(1,-95,1,-90)`. On larger screens it is 120 px at `(1,-170,1,-210)`.
    - The jump button hides when `JumpPower`/`JumpHeight` is 0.
  - Which `ScreenInsets` value the legacy `IgnoreGuiInset=true` maps to (`None` or `DeviceSafeInsets`).
  - Notch inset size.

---

## 1. Current state: findings

### 1.1 Touch input plumbing

**M1 [BUG]: No touch path to Attack, Skill1-4 or Dash in any combat Place. There is also no skill bar or cooldown UI on any platform.**
- **Evidence:**
  - `src/shared/StarterPlayer/StarterPlayerScripts/Modules/InputSystem/InputActions.lua:14-15`: "Touch bindings are empty because mobile on-screen buttons call InputSystem.FireAction() directly".
  - That function does not exist. `InputSystem/init.lua` exports only `Init/BindAction/UnbindAction/SetContext/SetBinding/GetBinding/GetBindingDisplayName/ResetAllBindings/OnBindingChanged/GetAllBindings/LoadBindings` (lines 109-285).
  - Every `Touch = {}` (InputActions.lua:30,41,52,63,74,85).
  - A world tap resolves to `key = Enum.UserInputType.Touch` (init.lua:130-133). `keyToActions[Touch]` is nil, so it returns early (135-136).
  - `PlayerAttack.DoAttack` is only reachable via the `Attack` action (`Modules/PlayerAttack.lua:54-57`). `SkillInput.TryUseSkill` is only reachable via `Skill1-4`/`Dash` (`Modules/SkillInput.lua:32-43`). A grep finds no UI caller for either.
  - `CombatApp.lua:67-171` mounts HUD, BattleClassUI (an info badge), menus, DeathUI and VoteUI. There is no attack or skill control.
  - `SkillInput.lua:15` keeps `skillCooldowns` with no getter and no consumer. `docs/GAME_DOCUMENTATION.md:1876` claims it "tracks local cooldowns for UI display".
- **Failure:** a phone player in LaneDefense, HordeMode or CentralBoss can walk (Roblox thumbstick) but can never attack or cast. The core loop cannot be played on mobile.
- **Fix shape:**
  - Add `InputSystem.FireAction(actionName, state)`. It should apply the same `def.contexts[activeContext]` gate as init.lua:140, then `FireCallbacks`.
  - Add a new `UI/Common/SkillPad.lua`, mounted by `CombatApp` when `formFactor.isTouch`. Buttons fire `Began` on InputBegan and `Ended` on InputEnded (so holds work later).
  - Export `SkillInput.GetCooldown(slot)` for radial wipes.
  - This is feasible: attack and skill direction come from character facing, not the mouse (`PlayerAttack.lua:124,146-153`; `SkillInput.lua:97-98,127-141`).

**M2 [BUG]: NPC interaction is impossible on touch. That blocks the NPC shop, the weapon smith, quests and NPC teleports.**
- **Evidence:**
  - `src/lobby/.../Modules/NPCInteraction.lua:60-65` binds only the `Interact` action (`Touch = {}` at `InputActions.lua:98`).
  - The prompt is a `BillboardGui` containing a `Frame` and a `TextLabel`, with no button (NPCInteraction.lua:138-173). Its label is hard-coded "[E] Talk" (167).
  - ShopUI opens only on the server `NPCShopOpen` push (`src/lobby/.../UI/ShopUI.lua:141`), which requires `NPCInteract`.
- **Failure:** a phone player can't open NPC shops or dialogs.
- **Fix shape [DQ]:**
  - (A) Replace the custom billboard with a native `ProximityPrompt`. It gives touch, gamepad and keyboard for free, and the hold/tap style can be customized.
  - (B) Keep the billboard, but make it a `TextButton` (BillboardGui `Active=true`) and add a contextual "Talk" button to the lobby thumb zone.
  - (A) is the less-code, cross-platform option.

**M3 [BUG]: The emote wheel can't be opened on touch, and its buttons are mis-scaled on every platform.** *(G19 three-copies duplication is known, not re-reported.)*
- **Evidence:**
  - The only opener is `InputSystem.BindAction("EmoteWheel")` (`src/shared/.../UI/EmoteWheel.lua:144-147`), with `Touch = {}` (InputActions.lua:109).
  - Button `Size = UDim2.fromScale(0.038, 0.067)` (EmoteWheel.lua:93) is parented to `Wheel` (`fromScale(0.121, 0.215)`, line 230), not to the screen. The comment "232x232 pixels" shows the conversion was done against 1920x1080.
  - Result: **3.9x5.6 px** on iPhone, 3.7x5.2 on Android, 4.7x11.1 on tablet, 8.8x15.6 at 1920x1080. CenterLabel (191) has the same problem.
  - The wheel is not square on phones (102x84 px). Buttons sit at `WHEEL_RADIUS = 80` px offset (48, 206), which is outside an 84-px-tall wheel.
  - Auto-close checks only W/A/S/D keys (157-167), so thumbstick movement never closes it.
  - Hint text says "Click to emote" (241).
- **Fix shape:**
  - Wheel 240x240 offset with `UIAspectRatioConstraint`. Buttons 72x72 offset.
  - Open from a HUD Emote button on touch.
  - Close when `Humanoid.MoveDirection.Magnitude > 0.1`.

**M4 [BUG]: SocialPlaza has no reachable interactive UI (all platforms; total on mobile).**
- **Evidence:**
  - `src/socialplaza/.../UI/SocialPlazaApp.lua:29` declares `showWardrobe`, but nothing ever sets it to true.
  - `AppearanceBar` (the Wardrobe and Emote buttons) is not mounted anywhere. A grep finds it only in the disabled legacy `src/shared/StarterGui/AppGui/Controllers/Overlays.client.lua:50`.
  - AppearanceBar's Emote button is a no-op (`AppearanceBar.lua:129-133`).
  - Its size is `fromScale(barW/1920, barH/1080)` with 10 px offset padding (`AppearanceBar.lua:84-96,115-120`). On iPhone that gives a 67x27 px bar with about 7 px of content height.
- **Failure:** on a phone, SocialPlaza is a walk-around with no menu, no wardrobe and no emotes.
- **Fix shape:** rebuild AppearanceBar with offset/token sizes, mount it in SocialPlazaApp, and wire `onWardrobeOpen` to `setShowWardrobe(true)` and Emote to the wheel.

**M5 [MINOR]: Input-type detection is static and private.**
- **Evidence:**
  - `DetectPlatform()` runs once at Init (`InputSystem/init.lua:62-69,113`).
  - `activeInputType` has no getter and no change signal.
  - `GetBindingDisplayName` with the default platform returns "—" on touch, because Touch bindings are empty (init.lua:236-237). So BattleClassUI skill badges read "—" on phones (`BattleClassUI.lua:202`).
  - Keyboard-only rebind UI is shown to touch users (`SettingsUI.lua:214,297`; `BattleClassUI.lua:351-363` "Controls / Rebind Keys").
  - `FaceMouse` gates on `MouseEnabled and not TouchEnabled` (`MovementSystem/FaceMouse.lua:58`), while `JoystickAim` gates on `TouchEnabled` alone (`JoystickAim.lua:165`). A touch-screen laptop therefore gets the joystick and no mouse aim.
- **Fix shape:** add `InputSystem.GetActiveInputType()` and `OnInputTypeChanged(cb)`, feed them into `useFormFactor` (§2.7), and hide rebind UI when `isTouch`.

**M6 [MINOR]: Skill-failure feedback goes to chat.**
- **Evidence:** `SkillInput.lua:61-67` uses `SetCore("ChatMakeSystemMessage")`.
- **Failure:** chat is usually collapsed on phones, so a failed cast is silent.
- **Fix shape:** show a toast above the SkillPad.

### 1.2 Safe areas, topbar and the notch

**M7 [BUG]: The lobby entry point (the ☰ Main Menu, the only non-NPC route to `MatchmakingRequest`) and the currency strip sit under Roblox's top bar.**
- **Evidence:**
  - `HUD.lua:525-527`: `Position = fromScale(0.005, 0.008)`, `Size = fromScale(0.05, 0.07)`. That is **42x27 px at (4,3)** on iPhone and 40x25 on Android.
  - Currency strip `Position (0.04,0)`, `Size (0.96,0.055)` (HUD.lua:547-548). It spans y 0-21 px, starting at x 34.
  - HUD computes `safeTop` from `GetGuiInset` (193-194), but neither element uses it.
  - Matchmaking is fired from `MainMenu.lua:163`.
- **Failure:** CoreGui draws above and consumes taps in that band. On a phone the ☰ is entirely under Roblox's own menu button, so a phone player cannot open game modes (the NPC teleport route is also dead, see M2). PC also overlaps, but the ☰ is 96x75 there, so part of it still clicks.
- **Fix shape:** use a SafeArea root (§2.3). Place the menu button top-right, which Roblox's topbar leaves free. Put pills inside `GuiService.TopbarInset` (verify API) or below it.

**M8 [SPAG]: No safe-area handling beyond a one-shot top inset.**
- **Evidence:**
  - Zero uses of `ScreenInsets`, `SafeAreaCompatibility` or `TopbarInset` in any `.lua` file (grep).
  - `GetGuiInset()` is read in render and only `.Y` is used: `HUD.lua:193-194`, `BossHud.lua:62-63`, `TestingUI.lua:186`. `BattleClassUI.lua:152-154` also uses `.X`, which is 0 in landscape.
  - Left-edge content at x ≈ 8-10 px: statusPanel `(0.01, 0.985)` (HUD.lua:585); BattleClass badge `safeLeft = inset.X + 10` (BattleClassUI.lua:153).
- **Failure:** on notched iPhones in landscape, left-anchored HUD content can fall into the cut-out or rounded corner (exact inset unspecified). The `ScreenInsets` mapping of the legacy flag is unspecified, so current behaviour needs a device check.
- **Fix shape:**
  - Split into two ScreenGuis per Place. `AppGui_FullBleed` (`ScreenInsets = None`) holds backdrops, LoadingScreen and dim layers. `AppGui` (`ScreenInsets = DeviceSafeInsets`) holds all interactive UI.
  - Expose insets through `useFormFactor().safe`.

**M9 [SPAG]: HUD elements overlap Roblox controls and each other.**
- **Thumbstick zone:**
  - The status panel (HUD.lua:584-586) covers **x 8-278, y 318-384** on iPhone. The defense HP bar (HUD.lua:736-738) covers y 293-312.
  - Both are inside the DynamicThumbstick zone (left 40%, bottom 2/3; unspecified geometry). The left thumb covers HP exactly when HP matters.
  - They are non-Active Frames, so there is no input theft today. But any button added there would steal the thumbstick.
- **TeammateVitals vs nav toggle:**
  - The container height is `(#teammates*42+8)/1080` of the screen (`TeammateVitals.lua:159`), but rows are 38 px offset (41).
  - With 3 teammates on iPhone the rows span y 120-246 at x 752-836. That overlaps the nav toggle, which is at x 772-831, y 177-212 (HUD.lua:860-862).
- **Killfeed vs TeammateVitals:** the killfeed at `safeTop+52` ≈ y 120, x 624-827 (HUD.lua:773-775) is on the same row as TeammateVitals' top (`TeammateVitals.lua:158`).
- **CentralBoss top-centre:**
  - The boss bar at `safeTop+30`, 46 px tall (`BossHud.lua:89-90`) collides with HUD Start/Next Wave at `safeTop+34` (HUD.lua:653,815).
  - The phase banner at `safeTop+84` (`BossHud.lua:142`) collides with the wave banner at `safeTop+88` (HUD.lua:715).
- **Roblox jump button (Lobby/SocialPlaza, phone):** x W-95..W-25, y H-90..H-20. Nothing is there today, and the spec below keeps it that way. In combat, `NoJump` zeroes JumpPower and JumpHeight (`MovementSystem/NoJump.lua:20-21`), so the jump button should hide (PlayerModule behaviour; verify). That frees the bottom-right for the SkillPad.

**M10 [MINOR]: HordeMode's JoystickAim takes the bottom-right slot and drops aim on any finger lift.**
- **Evidence:**
  - `JoystickAim.lua:46-47,120`: 120 px base at `(1,-160,1,-160)`. On iPhone that is x 624-744, y 170-290, exactly where attack and skills belong.
  - It is a separate ScreenGui with `IgnoreGuiInset=false`, `DisplayOrder 5` (108-113), and it is not safe-area aware.
  - `TouchEnded` clears `isAiming` for **any** touch (208-219) without tracking the aiming touch's identity. `TouchMoved` does the same (186-205).
- **Failure:** lifting the movement thumb cancels aim, and the facing snaps back to AutoRotate.
- **Fix shape:** track the `InputObject` that started the aim. See the §2.4 twin-stick option.

### 1.3 Touch target sizes (44 px minimum)

Estimated px (w x h). Anything under 44 px on either axis is marked **(<44)**. Where a finding's number differs from the table, the table is what the code computes.

| # | Element | Source (path:line) | iPhone 844x390 | Android 800x360 | Tablet 1024x768 |
|---|---|---|---|---|---|
| T1 | HUD ☰ menu | HUD.lua:527 | 42x27 **(<44)** | 40x25 **(<44)** | 51x54 |
| T2 | HUD nav toggle ⋮ | HUD.lua:862 | 59x35 **(<44)** | 56x32 **(<44)** | 72x69 |
| T3 | HUD nav grid cell (panel 0.22x0.62, pad 2%, cell 0.47x0.135) | HUD.lua:891,907,914-918 | 84x31 **(<44)** | 79x29 **(<44)** | 102x62 |
| T4 | Start / Next Wave / Return | HUD.lua:654,816,840 | 135x25 **(<44)** | 128x23 **(<44)** | 164x50 |
| T5 | AppWindow close, default windowed 0.82 H (header 0.085, close 0.78 of that, RelativeYY) | AppWindow.lua:42,137-138,193 | 21x21 **(<44)** | 20x20 **(<44)** | 42x42 **(<44)** |
| T6 | ...fullscreen (TalentTree) | AppWindow.lua:166-171 | 26x26 **(<44)** | 24x24 **(<44)** | 51x51 |
| T7 | ...DailyLogin 0.38x0.46 | DailyLoginUI.lua:78 | **12x12** | **11x11** | 23x23 **(<44)** |
| T8 | ...Settings 0.48x0.68 | SettingsUI.lua:473 | 18x18 **(<44)** | 16x16 **(<44)** | 35x35 **(<44)** |
| T9 | ...Leaderboard 0.50x0.72 | LeaderboardUI.lua:179 | 19x19 **(<44)** | 17x17 **(<44)** | 37x37 **(<44)** |
| T10 | ...Stats 0.72x0.78 | StatsMenu.lua:295 | 20x20 **(<44)** | 19x19 **(<44)** | 40x40 **(<44)** |
| T11 | Stats "+" (row 0.115 of leftPanel 0.56x0.76 of body) | StatsMenu.lua:136-137,248-249,344-345 | 34x17 **(<44)** | 32x16 **(<44)** | 41x34 **(<44)** |
| T12 | Wardrobe close (0.019x0.033 of 0.55x0.65 panel) | WardrobeUI.lua:318,340 | **9x8** | **8x8** | 11x17 **(<44)** |
| T13 | Achievements close (0.019x0.033 of header 1x0.09 of 0.72x0.88 panel) | AchievementsUI.lua:282,296,318 | **12x1** | **11x1** | 14x2 (26x3 at 1080p) |
| T14 | Inventory close (0.018x0.031 of 0.50x0.70) | InventoryUI.lua:184,206 | **8x9** | **7x8** | 9x17 **(<44)** |
| T15 | GlobalShop close / tabs (0.06 / 0.06 of 0.55x0.75) | GlobalShopUI.lua:331,366,382 | 28x18 / tab h 18 **(<44)** | 26x16 / 16 **(<44)** | 34x35 / 35 **(<44)** |
| T16 | MainMenu difficulty buttons (0.30x0.85 of 0.60x0.32 of card row 0.145 of 0.62x0.84) | MainMenu.lua:83,146-147,247,233-234 | 94x**13** | 89x**12** | 114x25 **(<44)** |
| T17 | MainMenu Play (0.22x0.55 of card) | MainMenu.lua:155 | 115x26 **(<44)** | 109x24 **(<44)** | 140x51 |
| T18 | MainMenu close | MainMenu.lua:217 | 51x23 **(<44)** | 48x22 **(<44)** | 61x46 |
| T19 | Party invite Accept/Decline (0.38x0.30 of 0.34x0.10 toast) | PartyInviteToast.lua:104,146,165 | 109x**12** | 103x**11** | 132x23 **(<44)** |
| T20 | CharacterCreation gender (0.109x0.041 of 0.25x0.389 panel) | CharacterCreation.lua:92,174-175 | **23x6** | **22x6** | 28x12 (52x17 at 1080p) |
| T21 | CharacterCreation Confirm | CharacterCreation.lua:260 | 88x16 **(<44)** | 83x15 **(<44)** | 107x31 **(<44)** |
| T22 | NPCDialog close (0.08x0.1 of 0.45x0.35) | NPCDialog.lua:460,485 | 30x14 **(<44)** | 29x13 **(<44)** | 37x27 **(<44)** |
| T23 | TalentTree node (fixed px, wheel-zoom only) | TalentTreeUI.lua:42-45,285,291 | 36x36 **(<44)** | 36x36 **(<44)** | 36x36 **(<44)** |
| T24 | TalentTree Respec (0.42x0.85 of slot 0.45x0.8 of header) | TalentTreeUI.lua:612; AppWindow.lua:128 | 160x23 **(<44)** | 151x21 **(<44)** | 194x44 |
| T25 | BattleClassUI Close / Rebind (fixed px) | BattleClassUI.lua:253,352 | 64x24 / h26 **(<44)** | same | same |
| T26 | EmoteWheel buttons | EmoteWheel.lua:93,230 | **4x6** | **4x5** | 5x11 |
| T27 | Wardrobe grid cell (scale inside a `(1,-32,1,-154)` scroll) | WardrobeUI.lua:266,394 | ~29x10 (scroll only **100 px** tall) | ~28x8 (scroll 80 px) | ~35x35 |

Notes:
- Rows T12-T14 and T20-T22 are in menus still queued for conversion *(known: §T10/U3 REMAINING, docs/TODO.md:640-643)*. The mobile numbers are new.
- **T5-T10 are new.** The AppWindow conversion fixed PC, but on phones the close button still scales with window height. The DailyLogin "~12-pixel close" that TODO.md:638-640 records as fixed comes back at 12x12 on iPhone.

### 1.4 Unreadable text

**M11 [SPAG]: 220 `TextScaled = true` sites and zero `UITextSizeConstraint`/`MinTextSize` anywhere in the UI** (grep across `src`).
- Worst estimates on iPhone:
  - Killfeed: a 202x15.6 px box (HUD.lua:773-782) holding strings like "X was slain by Y" (HUD.lua:373-376), about 40 characters. Glyphs come out around 8-9 px.
  - Status-bar value "1234 / 1234" in a 63x17 box (HUD.lua:107-116, width 0.25 of a 0.32-wide panel): about 9-10 px.
  - EmoteWheel hint, 114x9 box (EmoteWheel.lua:239-244): about 7 px.
  - TalentTree legend (TalentTreeUI.lua:678-695): about 7-8 px.
  - TalentTree tooltip description, a wrapped multi-line label in about 15 px of height (TalentTreeUI.lua:403,428-433): about 5-7 px.
  - BattleClassUI key badge `fromScale(0.011, 0.020)` of the SkillRow (BattleClassUI.lua:86).
- Fixed sizes that are too small on phones: `TextSize = 10/11` at BattleClassUI.lua:136,302,329,341 and WardrobeUI.lua:148.
- **Fix shape:** `Theme.Type` tokens per form factor, plus a `ThemedText` primitive. It should set a fixed `TextSize` from the tokens and fall back to `TextScaled` with a `UITextSizeConstraint { MinTextSize = tokens.fontMin, MaxTextSize = tokens.fontMax }`. Lint rule: no bare `TextScaled`.

### 1.5 Panels designed for 16:9 PC that clip on phones

**M12 [BUG]: CharacterCreation, the first screen every new player sees, is unusable on phones.**
- **Evidence:**
  - Panel `fromScale(0.25, 0.389)` (CharacterCreation.lua:174-175) = 211x152 px on iPhone.
  - Children mix offset heights (title 40 px at 185, labels 20 px at 197/222/246) with scale positions, so they overlap.
  - Swatch grid `CellSize 60x60` offset (148) inside a scroll that is 50 px tall (234).
  - Confirm is at `(0.5,0, 1,-58)` (261), which lands at y ≈ 94, inside the swatch area.
  - Gender buttons are 23x6 px (T20). Gender and skin have **no default** (113-114). Confirm errors "Please choose a gender first." (131).
- **Failure:** new mobile players can't get past character creation.
- *(Related: §T10/U3 lists CharacterCreation for fullscreen conversion; the blocking severity on phones is new.)*

**M13 [BUG]: Lobby mode picker.** MainMenu stacks 6 fixed rows at 0.145 each with no ScrollingFrame (MainMenu.lua:233-283). Each row is about 47 px on iPhone. Difficulty buttons are about 13 px tall (T16) and Play is 26 px (T17).

**M14 [BUG]: Wardrobe grid collapses.**
- **Evidence:** offset chrome of 154 px is subtracted from a scale panel height (`WardrobeUI.lua:318,394`). The scroll viewport is 100 px on iPhone and 80 px on Android. Scale cells (266) hold offset-height children of 22/16/32 px (117,130,142).
- **Failure:** cards are clipped.

**M15 [SPAG]: GlobalShop, on the other hand, degrades acceptably.** Cards are 90 px offset (GlobalShopUI.lua:122). Buy is `0.16x0.70` of the card = about 70x63 px. The list scrolls (421-429). But tabs are 18 px tall (T15), and the description is a 0.55x0.45 TextScaled box (157) that becomes about 8 px text.

**M16 [MINOR]: VoteUI is acceptable.** Cards are 0.28x0.85 of 0.72x0.38 = 170x126 px on iPhone (VoteUI.lua:70,443). But the offset content stack of 18+28+48 px (89-118) plus the vote count at `(1,-30)` (129) leaves about 14 px of slack on Android (116 px card).

### 1.6 Hover-only interactions

**M17 [BUG]: The talent tree is effectively unusable on touch.**
- **Evidence:**
  - Pan: the drag starts on Touch (TalentTreeUI.lua:666-672), but movement handles only `MouseMovement` (487-494). Touch drags never move the canvas.
  - Zoom: `MouseWheel` only (495-507). No pinch, no buttons.
  - Nodes stay at 36 px (T23).
  - Layout: depth-1 ring radius is `RING_START 5.5 × DEFAULT_CELL 42` = 231 px (50, 42), centred at 0.45 of the body (47). On iPhone the body is about 357 px tall (AppWindow fullscreen body = 0.915 of 390). The centre sits 160 px from the top, so upper and lower depth-1 nodes are already off-canvas, and there is no pan to reach them.
  - Tooltip: shown only on `MouseEnter` (304-309; hover state at 457, render at 589). Tap is `Activated` = **allocate immediately** (297-303). On touch you commit a point before you can read what it does. Respec costs a token or 500 Essence (615).
  - Legend text is PC-only: "Click = Allocate | Drag = Pan | Scroll = Zoom" (692).
- **Fix shape:** see §2.6.

**M18 [MINOR]: Other `MouseEnter` uses are visual-only, so nothing is lost on touch.** EmoteWheel.lua:100-101, WardrobeUI.lua:106-107, VoteUI.lua:148-149 and AppearanceBar.lua:43-44 are hover tint only.

### 1.7 Combat skill bar, emote wheel, talent tree and shop grids on touch (summary)

- **Skill bar:** there isn't one on any platform (M1).
- **Emote wheel:** unreachable on touch and mis-scaled everywhere (M3).
- **Talent tree:** no pan or zoom on touch, and tap commits (M17).
- **Shop grids:**
  - GlobalShop list is OK apart from its tabs (M15).
  - NPC ShopUI is unreachable (M2).
  - Wardrobe grid collapses (M14).
  - The HUD nav "grid" is below 44 px (T2-T3). The comment `HUD.lua:881-886` (§UI-HUD3) says the rework targeted mobile, but cells are still 31 px tall on iPhone.

### 1.8 Orientation

**M19 [DQ]: Orientation.** No `ScreenOrientation` or `DevTouchMovementMode` setting was found in any `.lua` or `.project.json` file. The default `LandscapeSensor` presumably applies, but place files may override it (unspecified). The recommendation is **landscape-only**, set explicitly.

---

## 2. Mobile layout spec

### 2.1 Form factors and breakpoints

Classification uses the viewport short side (`min(ViewportSize.X, Y)`) plus the last input type. The 500 px threshold matches Roblox's own "small screen" switch for its touch controls (unspecified in repo; verify).

| FormFactor | Rule | Status | Layout |
|---|---|---|---|
| **Phone** | touch, short side ≤ 500 | **Primary target**, landscape only | Thumb-zone HUD, panels become full-screen **sheets** |
| **Tablet** | touch, short side > 500 | Supported | Same anchors as Phone, `UIScale` 1.2, windowed panels allowed at ≥ 0.72x0.78 |
| **Desktop** | keyboard/mouse last input | Supported | Today's layout, hover tooltips, key badges |
| **Console** | `GuiService:IsTenFootInterface()` or gamepad-only | Later (gamepad bindings exist: InputActions.lua:29-84) | `UIScale` 1.5, focus navigation (`Selectable`, `GuiService.SelectedObject`), glyph badges |

Portrait: **not supported.** Lock landscape. [DQ: Pablo's call, but every current panel assumes a wide aspect.]

### 2.2 Tokens (add to Theme.lua as `Theme.Layout[formFactor]`)

| Token | Phone | Tablet | Desktop | Console |
|---|---|---|---|---|
| minTarget (any tappable) | **48** (44 absolute floor) | 48 | 32 | 64 |
| gap between targets | 8 | 10 | 8 | 16 |
| edge margin (inside safe area) | 16 | 20 | 16 | 48 |
| attack button | 96 | 112 | n/a | n/a |
| skill button | 60 | 72 | 52 (bar) | n/a |
| font min / body / title / HUD number max | 12 / 16 / 22 / 28 | 14 / 18 / 26 / 32 | 12 / 16 / 28 / 32 | 20 / 24 / 36 / 40 |
| window header height | 56 | 64 | 56 | 80 |
| close button | 48 | 48 | 40 | 64 |

Design everything in **offset at Phone reference** and scale up with a root `UIScale`. This is the recommended option (A). [DQ, taste]
- (A) Offset plus a root `UIScale` per form factor. Predictable touch sizes, and it avoids the scale-of-scale collapse that caused T12-T27.
- (B) Keep Scale, but add `UISizeConstraint`/`UITextSizeConstraint` minimums everywhere.
- (C) Scale inside `UIAspectRatioConstraint` boxes.

(A) is the only one that makes "44 px" a guarantee rather than an estimate.

### 2.3 Safe-area root

Each Place UI script creates two ScreenGuis:
- `AppGui_FullBleed` with `ScreenInsets = None`, for dim backdrops and sheets' backgrounds.
- `AppGui` with `ScreenInsets = DeviceSafeInsets`, for everything tappable.

Topbar avoidance:
- Use `T = GuiService.TopbarInset.Height`. Verify the API exists in this engine version; fall back to `GetGuiInset().Y`.
- Only the **top-left and top-centre** band needs avoiding. The top-right corner is free for the game's menu button (verify against `TopbarInset.Max.X`).

### 2.4 Thumb-zone map, combat (phone landscape)

```
+----------------------------------------------------------------------+
| [Roblox topbar]   [Wave/Boss bar T+4, centre]                [=]menu |
| [HP ██████  ]                                                        |
| [Res ▓▓▓▓   ]           (combo / toasts, upper-centre)               |
| [XP ─────   ]                                                        |
| [mates x3   ]                                              (S4)      |
|                                                     (S3)             |
|  LEFT THUMB: Roblox dynamic                    (S2)                  |
|  thumbstick (keep clear:                                             |
|  no buttons, no bars)                  [Dash] (S1)      ( ATTACK )   |
+----------------------------------------------------------------------+
```
- **Left:** Roblox movement stick only. Move vitals **out** of the bottom-left, up to the top-left under the topbar.
- **Right:** Attack (96 px) in the corner, with Skill1-4 (60 px) on a 128 px arc at 180°, 210°, 240° and 270°.
  - Chord between neighbours = 2·128·sin 15° ≈ 66 px, which is ≥ 60 + 6 gap.
  - Dash (52 px) sits left of S1 on the bottom row.
- **Resource:**
  - (A, recommended) A Resource bar in the top-left vitals stack, and each skill button dims and shows its cost when unaffordable.
  - (B) A radial resource ring around the Attack button. [DQ, taste]
- **Cooldowns:** a radial wipe plus a seconds label on each skill, fed by `SkillInput.GetCooldown(slot)` (M1).
- **HordeMode aim [DQ]:**
  - (A, recommended) A twin-stick Attack button. Press = attack; drag = aim (reuse JoystickAim's facing maths, JoystickAim.lua:65-99); hold = auto-repeat at attack speed. This removes the separate aim stick.
  - (B) Keep JoystickAim, but move it to the Attack slot and push the skill arc outward.

### 2.5 Per-Place HUD layout, phone landscape

All positions are relative to the safe-area `AppGui`. `T` = topbar height. All sizes are offset in phone points; tablet gets `UIScale` 1.2.

**Common (all Places)**

| Element | AnchorPoint | Position | Size |
|---|---|---|---|
| Menu button (opens nav sheet) | (1,0) | `UDim2.new(1,-16, 0,8)` | `UDim2.fromOffset(48,48)` |
| Toast stack (killfeed, SkillFailed, achievements) | (0.5,0) | `UDim2.new(0.5,0, 0,T+52)` | `UDim2.new(0.42,0, 0,28)` per line, max 3 |

**LaneDefense / HordeMode / CentralBoss (combat)**

| Element | AnchorPoint | Position | Size |
|---|---|---|---|
| Vitals stack (HP 22, Res 14, XP 6, gaps 4) | (0,0) | `UDim2.new(0,16, 0,T+6)` | `UDim2.new(0.30,0, 0,54)` |
| TeammateVitals (rows 28 px) | (0,0) | `UDim2.new(0,16, 0,T+66)` | `UDim2.new(0.20,0, 0,n*32)` |
| Wave banner (LD/Horde) / Boss bar (CB) | (0.5,0) | `UDim2.new(0.5,0, 0,T+4)` | `UDim2.new(0.42,0, 0,40)` |
| Defense-line HP (LD) / Phase label (CB) | (0.5,0) | `UDim2.new(0.5,0, 0,T+48)` | `UDim2.new(0.36,0, 0,16)` |
| Start / Next Wave / Return | (0.5,0) | `UDim2.new(0.5,0, 0,T+72)` | `UDim2.fromOffset(200,48)` |
| Combo counter | (0.5,0.5) | `UDim2.fromScale(0.5,0.34)` | `UDim2.fromOffset(160,44)` |
| **Attack** | (0.5,0.5) | `UDim2.new(1,-68, 1,-68)` | `UDim2.fromOffset(96,96)` |
| Skill1 (180°) | (0.5,0.5) | `UDim2.new(1,-196, 1,-68)` | `UDim2.fromOffset(60,60)` |
| Skill2 (210°) | (0.5,0.5) | `UDim2.new(1,-179, 1,-132)` | 60x60 |
| Skill3 (240°) | (0.5,0.5) | `UDim2.new(1,-132, 1,-179)` | 60x60 |
| Skill4 / ultimate (270°) | (0.5,0.5) | `UDim2.new(1,-68, 1,-196)` | 60x60 (gold ring) |
| Dash | (0.5,0.5) | `UDim2.new(1,-276, 1,-52)` | `UDim2.fromOffset(52,52)` |
| Class badge | hidden on Phone; shown in the nav sheet | n/a | n/a |

The arc's leftmost edge is at W-226 (618 px on iPhone), well clear of the thumbstick zone (x < 338). The arc's top is at H-226 (y 164).

**Lobby (jump button visible; small-screen jump at x W-95..W-25, y H-90..H-20)**

| Element | AnchorPoint | Position | Size |
|---|---|---|---|
| Level + XP chip | (0,0) | `UDim2.new(0,16, 0,T+6)` | `UDim2.fromOffset(220,40)` |
| Currency pills (Essence / Merits / Power) | (1,0) | `UDim2.new(1,-72, 0,8)` | `UDim2.fromOffset(240,40)` |
| Matchmaking status bar | (0.5,0) | `UDim2.new(0.5,0, 0,T+6)` | `UDim2.new(0.40,0, 0,44)` |
| **PLAY** (opens mode sheet) | (1,1) | `UDim2.new(1,-20, 1,-110)` | `UDim2.fromOffset(140,56)` |
| Interact (contextual, only when an NPC is near) | (1,1) | `UDim2.new(1,-110, 1,-24)` | `UDim2.fromOffset(72,72)` |
| Emote | (1,1) | `UDim2.new(1,-194, 1,-24)` | `UDim2.fromOffset(56,56)` |
| Party invite toast | (0.5,0) | `UDim2.new(0.5,0, 0,T+56)` | `UDim2.fromOffset(360,104)`, buttons 150x44 |

On tablet (large jump at x W-170..W-50, y H-210..H-90), shift PLAY to `UDim2.new(1,-190, 1,-24)` and Interact to `UDim2.new(1,-190, 1,-96)`.

**SocialPlaza:** Menu (common). Wardrobe `(1,1)` at `UDim2.new(1,-20, 1,-110)`, 56x56. Emote `(1,1)` at `UDim2.new(1,-110, 1,-24)`, 64x64. That is AppearanceBar rebuilt with these values (M4).

### 2.6 Panels become sheets; hover becomes long-press

**AppWindow `variant = "auto"` (new default):**
- **Phone:** a sheet.
  - Full-bleed dim; the panel fills the safe area.
  - Header `UDim2.new(1,0,0,56)`; title `TextSize` 22.
  - Close 48x48 at `UDim2.new(1,-8,0,4)` with anchor `(1,0)`.
  - Body is a `ScrollingFrame` (`AutomaticCanvasSize.Y`, `ScrollBarThickness 6`, `ElasticBehavior.WhenScrollable`).
  - Tabs become a 44-px segmented bar under the header, or a horizontally scrolling chip row when there are more than 4.
  - Tap-outside does not close (avoids accidental loss); a back gesture is not needed.
- **Tablet and Desktop:** today's windowed panel, but header height = `max(0.085·H, 56)`. Implement with `UISizeConstraint` on the header or offset height. Close = token size, **not** `RelativeYY` of the header.
- **Grids:** `UIGridLayout.CellSize` in offset (shop/wardrobe 112x140; nav tiles 96x72). Use `FillDirectionMaxCells` = `floor((width+gap)/(cell+gap))`.
- **Stat allocation:** 48-px "+" plus hold-to-repeat, and "+5".

**Tooltips:** `usePressHold(onHold, {holdTime = 0.35, moveCancel = 10})`.
- On touch, `InputBegan(Touch)` starts a `task.delay`. `InputEnded` or more than 10 px of movement cancels it.
- If the hold fired, the following `Activated` is swallowed.
- A single `TooltipHost` at the app root renders above the finger, clamped to the safe area.
- On Desktop the same hook maps to `MouseEnter`/`MouseLeave`.

**Talent tree on touch:**
- Tap **selects** a node. A bottom detail sheet (name, effects, cost) shows an **Allocate** / **Refund** 48-px button.
- Desktop keeps hover plus click. [DQ: tap-select with confirm (recommended, since respec costs Essence) or long-press-inspect with tap-to-allocate.]
- Pan: handle `Enum.UserInputType.Touch` in InputChanged, or use the canvas `TouchPan`.
- Zoom: `TouchPinch`, plus +/−/"fit" buttons (48 px). Clamp nodes so they never render below `minTarget` on touch.
- The initial zoom fits the ring layout to the body.

### 2.7 Helper API: `UI/Common/useFormFactor.lua` (plus a non-React `FormFactor` module)

```lua
-- Modules/FormFactor.lua (singleton; also usable by JoystickAim/InputSystem)
-- FormFactor.Get() -> {
--   kind      = "Phone" | "Tablet" | "Desktop" | "Console",
--   input     = "Touch" | "Gamepad" | "KeyboardMouse",   -- live, from LastInputType
--   isTouch   = boolean,
--   viewport  = Vector2, short = number,
--   topbar    = number,            -- GuiService.TopbarInset.Height (fallback GetGuiInset().Y)
--   tokens    = Theme.Layout[kind],
--   uiScale   = number,
-- }
-- FormFactor.Changed(cb) -> disconnect()
local PHONE_MAX_SHORT = 500
local function classify(vp, input)
    if GuiService:IsTenFootInterface() then return "Console" end
    if input == "Gamepad" and not UserInputService.TouchEnabled then return "Console" end
    if input == "Touch" or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
        return (math.min(vp.X, vp.Y) <= PHONE_MAX_SHORT) and "Phone" or "Tablet"
    end
    return "Desktop"
end
-- Recompute on: workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"),
-- UserInputService.LastInputTypeChanged (debounced 0.25 s so a stray key on a
-- tablet doesn't flip layouts), GuiService:GetPropertyChangedSignal("TopbarInset").
-- (UserInputService.PreferredInput is newer and cleaner if it exists in this
-- engine version; unspecified, so verify, else use LastInputType.)

-- UI/Common/useFormFactor.lua
local function useFormFactor()
    local ff, setFF = React.useState(FormFactor.Get())
    React.useEffect(function() return FormFactor.Changed(setFF) end, {})
    return ff
end
```

Consumers:
- `AppWindow` (variant auto, header and close tokens).
- `HUD` (layout table per kind).
- `SkillPad` (mount only when `isTouch`).
- `ThemedText` (font tokens).
- `usePressHold`.
- `InputSystem` (`GetActiveInputType`/`OnInputTypeChanged` delegate to FormFactor).
- `JoystickAim` (gate on `FormFactor.Get().isTouch`).

One source of truth replaces the four per-component `GetGuiInset()` reads (M8).

---

## 3. Top 10 mobile blockers (ranked by impact)

1. **CharacterCreation can't be completed on phones** (M12). Gender buttons are 23x6 px with no default, and Confirm overlaps the swatches. Evidence: `src/shared/StarterPlayer/StarterPlayerScripts/UI/CharacterCreation.lua:92,113-114,131,174-175,234,260-261`. Every new mobile player is stopped at minute zero.
2. **No attack or skill input on touch** (M1). Evidence: `Modules/InputSystem/InputActions.lua:14-15,30-85`; `Modules/InputSystem/init.lua:130-136` (no `FireAction`); `UI/CombatApp.lua:67-171` (no SkillPad); `Modules/SkillInput.lua:15`.
3. **Can't start a match from the lobby** (M7 + M13). The ☰ menu sits under the Roblox topbar (`UI/HUD.lua:525-527`). Difficulty buttons are 13 px and Play is 26 px (`lobby/.../UI/MainMenu.lua:83,146-147,155,233-234`).
4. **NPC interaction impossible** (M2). Shops, smith, quests and teleports are all behind it. Evidence: `lobby/.../Modules/NPCInteraction.lua:60-65,138-173`; `InputActions.lua:98`; `lobby/.../UI/ShopUI.lua:141`.
5. **Close buttons 1-21 px on phones, and no tap-outside close.** AppWindow is new (`UI/Common/AppWindow.lua:42,137-138,181-188`), with DailyLogin at 12 px (`lobby/.../UI/DailyLoginUI.lua:78`). Legacy menus *(known: §T10/U3)* are worse: `AchievementsUI.lua:318` (≈1 px tall), `WardrobeUI.lua:340`, `lobby/.../InventoryUI.lua:206`. Players get trapped in menus.
6. **Talent tree unusable on touch** (M17). No pan (`TalentTreeUI.lua:487-494`), no pinch (495-507), rings off-canvas (42,50,47), and tap commits a point before the tooltip shows (297-309).
7. **Safe area and overlaps** (M8, M9). No ScreenInsets (all five `*UI.client.lua:24`). HP sits under the left thumb (`HUD.lua:584-586`). TeammateVitals and the killfeed collide with the nav toggle (`TeammateVitals.lua:158-159`; `HUD.lua:773-775,860-862`). The boss bar collides with Start and banners (`centralboss/.../BossHud.lua:89,142` vs `HUD.lua:653,715,815`).
8. **Party invite Accept/Decline are 12 px tall on a timed toast** (T19). Evidence: `lobby/.../UI/PartyInviteToast.lua:104,146,165`. Mobile players can't join friends.
9. **Unreadable text: 220 TextScaled sites with no minimum** (M11). Evidence: `HUD.lua:107-116,773-782`; `TalentTreeUI.lua:428-433,689-695`; `EmoteWheel.lua:239-244`; `BattleClassUI.lua:86,136,302`.
10. **Emotes and SocialPlaza dead on touch** (M3, M4). Evidence: `EmoteWheel.lua:93,144-147,157-167,230`; `socialplaza/.../UI/SocialPlazaApp.lua:29,53`; `socialplaza/.../UI/AppearanceBar.lua:129-133` (unmounted).

Honourable mentions: Stats "+" at 34x17 (`StatsMenu.lua:136-137`), Wardrobe grid collapse (`WardrobeUI.lua:266,394`), HUD nav cells 31 px (`HUD.lua:907`), and the JoystickAim any-finger-lift bug (`JoystickAim.lua:208-219`).

**Suggested order of work:**
1. `FormFactor` + tokens + SafeArea root.
2. `InputSystem.FireAction` + SkillPad.
3. AppWindow `auto` sheet.
4. Convert CharacterCreation, MainMenu and PartyInviteToast.
5. ProximityPrompt / Interact button.
6. Talent-tree touch.
7. `ThemedText` sweep.

This lines up with the §T10/U3 conversion queue, so each menu is converted once, to the new tokens.

## 4. Design questions for Pablo

- **DQ1:** Portrait. Recommend landscape-only.
- **DQ2:** Offset + UIScale (A) vs scale + constraints (B) as the unified sizing model.
- **DQ3:** NPC talk. Native ProximityPrompt vs a custom tappable billboard.
- **DQ4:** Resource display. Vitals bar + dim skills vs a ring around Attack.
- **DQ5:** HordeMode. Twin-stick Attack vs a separate aim stick.
- **DQ6:** Talent touch. Tap-select + Allocate button vs long-press inspect.
- **DQ7:** Currency in combat. Hidden on Phone (in the nav sheet) vs a compact pill in the topbar band.

## 5. Verified good

- `DeathUI` buttons use pixel heights of 46 and 44 px (`DeathUI.lua:332,365`). They meet the minimum on every device.
- `JoystickAim` uses a fixed 120-px base and runs only on touch (`JoystickAim.lua:46,165-169`).
- `InputSystem` returns early on `gameProcessed` (`init.lua:118,148`). On-screen SkillPad buttons won't double-fire actions.
- Attack and skill direction come from character facing, not the mouse (`PlayerAttack.lua:124,146-153`; `SkillInput.lua:97-98,127-141`). Touch buttons need no aim logic in Lane and Boss modes.
- `NoJump` zeroes `JumpPower`/`JumpHeight` in all three combat Places (`NoJump.lua:20-21`; `HordeModeClient.client.lua:101`; `LaneDefenseClient.client.lua:87`; `CentralBossClient.client.lua:96`). This should hide Roblox's jump button and free the bottom-right for the SkillPad (PlayerModule behaviour; verify on device).
- The `SettingsUI` volume slider accepts Touch (`SettingsUI.lua:79-80`).
- TalentTree drag start and end accept Touch (`TalentTreeUI.lua:512-514,667-669`). Only the move and zoom handlers are mouse-only.
- `AppWindow` icon and close use `RelativeYY` squares (`AppWindow.lua:99,138`), so they stay square. The size basis is the problem, not the shape.
- `BossHud` bar uses a fixed 46 px height (`BossHud.lua:90`), which is legible on phones.
- `GlobalShop` item cards use a 90 px offset height with a large Buy button and a scrolling list (`GlobalShopUI.lua:122,182,421-429`). That is touch-friendly apart from the tabs.
- `VoteUI` cards are about 170x126 px on iPhone (`VoteUI.lua:70,443`). The whole card is the tap target (143-150).
- `BattleClassUI` expanded panel is scale-bound with an inner `ScrollingFrame` (`BattleClassUI.lua:385-405`), so it never overflows the viewport.
- `LoadingScreen`, `MobVisuals` and `LootNotification` use `IgnoreGuiInset=true` for full-bleed layers (`LoadingScreen.lua:63`, `MobVisuals.lua:230`, `LootNotification.lua:53`). That is correct for non-interactive overlays.
- The disabled legacy `StarterGui/AppGui` stack was not audited *(known: §T10/STACK)*.
