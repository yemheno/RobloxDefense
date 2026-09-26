# ui-visual: visual system audit and proposal (RobloxDefense, static, read-only)

> **Frozen as-built spec (2026-09-26).** Kept at this path because code comments cite it. Live summary: [ARCHITECTURE § UI](../ARCHITECTURE.md#ui); its design questions are answered in [DESIGN_DECISIONS § UI](../DESIGN_DECISIONS.md#ui-decisions).

Path shorthands: `S/` = `src/shared/StarterPlayer/StarterPlayerScripts/UI/`, `L/` = `src/lobby/StarterPlayer/StarterPlayerScripts/UI/`, `CB/` = `src/centralboss/StarterPlayer/StarterPlayerScripts/UI/`, `M/` = `src/shared/StarterPlayer/StarterPlayerScripts/Modules/`.
Severity tags: [BUG] = 🚨, [SPAGHETTI] = 🟡, [MINOR] = 🟢, [DESIGN-Q] = ❓.
Phone figures use an 844x390 dp landscape viewport (iPhone 14 class). They are arithmetic from the code, not Studio measurements. Anything marked "verify" needs the Studio Device Emulator.

## TL;DR
- **Why the UI doesn't feel like one thing.** `Theme.lua` exists, but no feature file requires it. Only `AppWindow`, `LightningBar` and `UIParticles` read it. The 38 feature files carry **29 private palette tables**, with **473 `Color3.fromRGB` literals and 218 distinct colors**. Theme's primary accent is **orange (255,170,40)**, and it appears in **0** feature files. The feature bodies all use **blue (105,190,255)** as their accent (17 files). So every converted window has an orange/blue ribbon header sitting over a blue body.
- **A systemic sizing bug.** Pixel sizes were converted to Scale by dividing by 1920x1080, but they were applied to parents that are not the screen. The result is close buttons, knobs and labels that are 1 to 9 px on PC and under 10 dp on phones (V1).
- **Mobile has no defined layout.** No file uses UIAspectRatio or UITextSizeConstraint, and no UI file checks the input type. Touch skill buttons don't exist either: the `InputSystem.FireAction()` that the touch design relies on was never written (V4).

---

## 1. Inventory

### 1a. Global counts (all 47 UI files, Theme.lua excluded)
| Metric | Count | Notes |
|---|---|---|
| `Color3.fromRGB` literals | 473 | 218 distinct values. Plus 13 `Color3.new` |
| Local palette tables (`local C = {...}`) | 29 | Key naming uses snake_case (`bg_dark`), camelCase (`cardBg`, VoteUI) and PascalCase (`Overlay`, CharacterCreation) |
| `TextScaled = true` | 211 | |
| Fixed `TextSize` | 43 | Values 10,11,12,13,14,16,18,20,22. Heaviest in BattleClassUI (10), EquipmentUI (10), KeybindSettings (7), VoteUI (6), WeaponSmithUI (6) |
| `UITextSizeConstraint` | **0** | |
| `UIAspectRatioConstraint` | **0** | |
| `SizeConstraint` | 2 | Both in AppWindow (§T10/LIVE2) |
| `FontFace` / `Font.new` | 0 | Legacy `Enum.Font` only |
| TextButtons | 83 | 8 of them set `AutoButtonColor=false` |
| Image/ImageButton | 5 | Icon art is delivered but not wired *(known: §T10/ICONS)* |

**Colors grouped by value (top families):**
- Text white `255,255,255` ×31. Text-dim `140,140,160` ×20. The "body text" off-white has 4 variants: `220,220,230` ×17 (17 files), `225,225,230` ×3, `220,220,235` ×5, and Theme's `235,235,245` ×0.
- Accent blue `105,190,255` ×19 across 17 files. There are **21 distinct blues** besides that one (e.g. `80,160,255` ×5, `80,210,255` ×3, `90,190,255` ×3, `60,135,235` ×2, and 1-offs).
- Panel darks: **51 distinct** colors where every channel is under 60. Panel `18,18,24` ×10 (10 files) versus Theme `panel` `18,18,26` (4 files) versus Theme `bg` `12,12,18` (2 files).
- Reds: **17 distinct** (`180,50,50` ×9, `245,100,100` ×5, `200,60,60` ×4, `170,50,50` ×4, `80,36,36` ×5 as close_bg, …). Theme `bad` `225,70,70` ×0.
- Golds/yellows: `255,200,60` ×10, `255,210,60` ×9, `255,180,40` ×5, `255,220,100` ×2 (Theme `gold`).

**Corner radii: 26 distinct values.** Scale: 0.015, 0.02, 0.03, 0.04, 0.05, 0.06, 0.08, 0.1, 0.12, 0.15, 0.18 (×15), 0.2 (×13), 0.25, 0.3 (×15), 0.35 (×13), 0.5 (×14), 1. Offset: 3, 4, 5, 6 (×14), 8 (×11), 10, 12, 16 px.
**Stroke thickness:** 1.5 ×23, 1 ×7, 2 ×6, 3 ×1, 6 ×1, plus 5 computed. `ScrollBarThickness = 4` is consistent across 14 scroll frames, which is good.
**BackgroundTransparency (non-1):** 22 distinct values from 0.05 to 0.78, with 0.25/0.15/0.35/0.30 the most common. Backdrop dims: 0.35 (Wardrobe, Keybind, CombatApp ref), 0.42 (AppWindow), 0.55 (VoteUI).
**Padding:** a mix of scale (`0.02` ×11, `0.03`, `0.04`) and offset (`4`, `6`, `8`, `10` px). No spacing token.
**ZIndex (literal):** 0,2,3,4,5,6,8,9,10,11,12(×30),14,15,16,20(×7),21,25,30,48,50,100–103. Top-level layers today: HUD 1, AppWindow 10 (`S/Common/AppWindow.lua:46`), Wardrobe/Shop/NPC/WeaponSmith/PartyInvite/AchToast 20, Matchmaking 25 (`L/MatchmakingUI.lua:133`), EmoteWheel 30 (`S/EmoteWheel.lua:218`), VoteUI 50 (`S/VoteUI.lua:439`), DeathUI/TestingUI/Keybind 100. Separate ScreenGuis: AppGui DisplayOrder 0 (`L/../LobbyUI.client.lua:20-24`, all 5 places identical), LootNotification 5 (`M/LootNotification.lua:54`), JoystickAim 5, CastBar 8 (`M/SkillVisuals.lua:652`), LoadingScreen 1000.
**Fonts:** Gotham / GothamBold everywhere. GothamBlack appears only in AppWindow and BossHud. `Enum.Font.Code` in TestingUI.

### 1b. Per-file table
"Uses Theme?" = requires Theme directly. "Chrome" = gets Theme **only indirectly** through AppWindow's header/panel. Colors = `Color3.fromRGB/new` literals.

| File | Uses Theme? | # hard-coded colors | Notable deviations |
|---|---|---|---|
| S/HUD.lua | No | 53 | 10 copy-pasted nav buttons (`:921-1087`). Menu button and currency strip sit under the topbar (V3). Inventory glyph is a trumpet (V9) |
| S/DeathUI.lua | No | 24 | Own modal, root Z 100 (`:199,:267`) |
| S/VoteUI.lua | No | 24 | camelCase palette. Micro-scale badges `:128,:478` (V1) |
| S/GlobalShopUI.lua | No | 23 | Own chrome + close `:365-369`. TabButton #3. 💎/🪙 currency glyphs `:356` |
| S/TestingUI.lua | No | 23 | Admin only, Code font. Lowest priority |
| S/TalentTreeUI.lua | No (AppWindow fullscreen) | 22 | Dead `close_bg` `:73` |
| S/CharacterCreation.lua | No | 20 | PascalCase palette. Swatch micro-scale `:67`. Still on the §T10/U3 REMAINING list |
| S/SettingsUI.lua | No (AppWindow) | 20 | Dead `close_bg/close_text` `:41-42`. Slider knob micro-scale `:145` (V1). TabButton #1 `:165`. Title "Settings" not localized `:467` |
| S/AchievementsUI.lua | No | 19 | Own chrome. Close button 26x3 px (V1) `:318`. Toast Z20 `:453` |
| S/WardrobeUI.lua | No | 19 | Mixed offset/scale. Close "X" `:342`, unequip button micro (V1). TabButton #2 `:195` |
| S/EquipmentUI.lua | No | 18 | Own close `:473`. XPBar `:143` (bar #3). BonusRow duplicated in WeaponSmith |
| S/StatsMenu.lua | No (AppWindow) | 17 | Dead `close_bg/close_text` `:34-35` |
| S/ClassMenu.lua | No (AppWindow) | 16 | "Windowed exemplar", but its own palette at `:24-40`. Dead close keys `:38-39`. Contrast issue (V10) |
| S/KeybindSettings.lua | No | 16 | Hand-rolled modal Z100–103. Close button 8x1 px (V1) `:306`. Header fixed at 44 px `:278` |
| S/BattleClassUI.lua | No | 15 | Close button trapped in a UIListLayout (V2). Icon/resource labels under 1 px (V1) |
| L/SocialPanel.lua | No | 22 | Own fullscreen chrome + close `:702`. TabButton #4 `:98` |
| L/InventoryUI.lua | No | 13 | Close button 17x23 px / 8x8 dp (V1) `:206` |
| L/MainMenu.lua | No | 12 | Close "X" `:220` |
| L/WeaponSmithUI.lua | No | 12 | Close `:470`. ActionButton/BonusRow duplicates |
| L/PartyInviteToast.lua | No | 11 | Bottom-center toast `:102`, `BorderSizePixel=2` plus UIStroke `:105-114` |
| L/DailyLoginUI.lua | No (AppWindow) | 10 | Dead `close` key `:28` |
| L/LeaderboardUI.lua | No (AppWindow) | 10 | Dead `close` key `:30` |
| L/NPCDialog.lua | No | 10 | Own close `:482` |
| L/ShopUI.lua | No | 10 | Own close `:234` |
| CB/BossHud.lua | No | 9 | Offset-sized bar (46/22/18 px) `:91-111`. Z0 layering is correct |
| S/EmoteWheel.lua | No | 8 | — |
| S/TeammateVitals.lua | No | 8 | Bar #5 `:80` |
| L/MatchmakingUI.lua | No | 7 | Top bar overlaps the HUD currency strip (V13). "Close" text button `:198` |
| socialplaza/AppearanceBar.lua | No | 7 | — |
| S/CombatApp.lua | No | 1 | Class-reference overlay is a 5th window type `:95-120` |
| S/Common/AppWindow.lua | **Yes** | 1 | `Color3.fromRGB(255,120,120)` close stroke `:150` |
| S/Common/LightningBar.lua | **Yes** | 5 | — |
| S/Common/UIParticles.lua | **Yes** | 2 | — |
| Thin wrappers (LobbyApp, *App, lobby/socialplaza EmoteWheel, useNpcDistanceClose) | n/a | 0 | — |

---

## 2. Components: every distinct implementation

| Kind | Implementations (path:line) | Should become |
|---|---|---|
| **Window chrome** | (1) `S/Common/AppWindow.lua` (6 users + doc example). (2) hand-rolled centered panel: Wardrobe `S/WardrobeUI.lua:303-330`, Achievements `:~275-330`, Inventory `L/InventoryUI.lua:170-215`, Equipment, GlobalShop, MainMenu, ShopUI, NPCDialog, WeaponSmith. (3) fullscreen: `L/SocialPanel.lua`. (4) Keybind modal `S/KeybindSettings.lua:241-389`. (5) combat class reference `S/CombatApp.lua:95-120` + `S/BattleClassUI.lua:380-405` | `Window` (= AppWindow) with `variant = windowed/fullscreen/sheet` |
| **Close button** | 1 canonical (`AppWindow.lua:133-152`) + **14 hand-rolled**: Equipment `:473`, GlobalShop `:365`, Wardrobe `:337` ("X"), Achievements `:315`, Keybind `:303`, BattleClass `:247` ("Close"), Inventory `L:203`, Shop `L:234`, NPCDialog `L:482`, SocialPanel `L:702`, MainMenu `L:214` ("X"), WeaponSmith `L:470`, PartyInviteToast `L:183`, Matchmaking `L:192` ("Close"). Glyphs used: ✕ ×11, X ×2, "Close" ×2. Sizes range from 0.018 to 0.24 scale | `IconButton{icon="close"}` inside Window |
| **Tabs** | 4× `TabButton`: `S/SettingsUI.lua:165` (0.31 scale, r0.2, `tab_on/off`), `S/WardrobeUI.lua:195` (offset 36px, r6px, `tab_bg/active`), `S/GlobalShopUI.lua:205` (1/3 scale, r0.15), `L/SocialPanel.lua:98`. Each uses different active colors and radii | `Tabs{items, value, onChange}` |
| **Primary/secondary buttons** | HUD nav ×10 copy-paste `S/HUD.lua:921-1087`. HUD Start/Next/Return `:651, :813, :835` (3 colors). `ActionButton` ×2: `L/WeaponSmithUI.lua:53`, `S/TestingUI.lua:140`. `ChoiceButton` `L/NPCDialog.lua:39`, `BarButton` `socialplaza/AppearanceBar.lua:34`, `EmoteButton` `S/EmoteWheel.lua:87`, `GenderButton` `S/CharacterCreation.lua:87`, ClassMenu slot button `S/ClassMenu.lua:80-140`, Settings reset `:443` | `Button{variant, size, icon}` |
| **Bars** | 8: `HUD StatusBar` `S/HUD.lua:51`, `LightningBar` `S/Common/LightningBar.lua:124`, `EquipmentUI XPBar` `:143`, `TeammateVitals` `:80`, `AchievementsUI` progress `:175`, `VoteUI` timer `:467`, `BossHud` `CB/BossHud.lua:104`, Settings slider track `S/SettingsUI.lua:125` (interactive) | `Bar{value, kind="hp"/"resource"/"xp"/"boss"/"progress", effect?}`. The slider stays separate |
| **Toast / notification** | 7 placements, no shared host: Achievement toast top-center (0.5,0.07) `S/AchievementsUI.lua:445-448`. PartyInvite bottom-center (0.5,0.94) `L/PartyInviteToast.lua:102`. Matchmaking top-center (0.5,0.03) `L/MatchmakingUI.lua:128`. HUD waveBanner `S/HUD.lua:713`, comboToast `:789`, deathFeed `:772`. LootNotification right edge, separate ScreenGui `M/LootNotification.lua:28-30,:54` | `ToastHost` with named slots and a queue, plus `Toast{kind, title, body, actions}` |
| **Modal / overlay** | DeathUI `:194-200`, VoteUI `:436-440`, KeybindSettings `:241-249`, CombatApp class ref `:95`, CharacterCreation | `Modal{dismissible, onDismiss}` (dim + focus trap) |
| **Duplicated sub-rows** | `BonusRow` ×2 (`S/EquipmentUI.lua:69`, `L/WeaponSmithUI.lua:82`). Cards: ItemCard/ShopItemCard/CosmeticCard/AchievementCard/ModeCard/EquipmentCard/VoteCard (7 variants of one "Card") | `Card{selected, locked, rarity}`, `StatRow` |
| **Currency display** | HUD `CurrencyPill` `S/HUD.lua:496` (♦/★/⚡). GlobalShop header text `:356` (💎/🪙). Loot `[E]`/`[M]` `M/LootNotification.lua:32-33` | `CurrencyPill{currency}` backed by `Theme.Icons.essence/merits` |

---

## 3. Findings (numbered)

**V1 [BUG] The px→Scale conversion was computed against 1920x1080 but applied to parents that are not the screen. The result is micro or invisible controls.**
The constants are pixel values divided by 1920/1080 (e.g. 36/1920 = 0.019, 36/1080 = 0.033). They are then placed inside panels, headers or rows, so the parent size multiplies them a second time. Evidence:
- `S/KeybindSettings.lua:306` `Size = UDim2.fromScale(0.019, 0.026)` on CloseBtn inside a `UDim2.new(1,0,0,44)` header (`:278`). The panel is 0.219 of the screen wide (`:267`), so at 1080p the button is about **8x1 px**. `:366` ResetBtn `fromScale(0.083, 0.028)`. `:119` custom dot `fromScale(0.003, 0.006)`.
- `S/SettingsUI.lua:145` slider knob `fromScale(0.007, 0.013)` of the track, so the knob is effectively invisible.
- `S/BattleClassUI.lua:279` IconLbl `fromScale(0.015, 0.026)` and `:296` ResLbl `fromScale(0.042, 0.019)` inside a 32 px header (`:268`). They are **under 1 px tall**. `:86` key badge `fromScale(0.011, 0.020)`.
- `S/AchievementsUI.lua:318` close `fromScale(0.019, 0.033)` inside a header that is `fromScale(1, 0.09)` of a 0.72x0.88 panel. That is about **26x3 px** at 1080p and 12x1 dp on a phone.
- `S/WardrobeUI.lua:340` close `fromScale(0.019,0.033)` of a 0.55x0.65 panel: 20x23 px at 1080p, **9x8 dp** on a phone. `:379` Unequip `fromScale(0.063,0.026)`: 67x18 px, **29x7 dp** on a phone. `:156` equipped badge `(0.031,0.015)`.
- `L/InventoryUI.lua:206` close `(0.018,0.031)` of a 0.50x0.70 panel: 17x23 px, 8x8 dp on a phone.
- Also `S/VoteUI.lua:128,:478`, `S/CharacterCreation.lua:67`, `S/EquipmentUI.lua:81`, `S/TeammateVitals.lua:132` (Studio stub only).
- *(Partly known: TODO §T10/U3 notes the "~12-pixel close buttons" in DailyLogin/Leaderboard and fixed those by moving them to AppWindow. `S/BattleClassUI.lua:249-251` documents one instance. The **systemic cause** and the non-close cases (knob, labels, badges, reset/unequip buttons) are not recorded.)*
- Failure scenario: the player can't close Keybindings or Achievements, and can't see the volume knob or the class icon.
- Fix shape: route each case through the component library, i.e. close buttons via `Window`/`IconButton`. For leftovers, re-derive the size from the **parent** (for example a square from the parent's height: `fromScale(0.8,0.8)` + `SizeConstraint=RelativeYY`, the AppWindow §T10/LIVE2 pattern) and add a `UISizeConstraint{MinSize=Vector2.new(32,32)}`.

**V2 [BUG] BattleClassUI's Close button is inside a UIListLayout, so its Position and AnchorPoint are ignored.**
`S/BattleClassUI.lua:247-262` sets `AnchorPoint (1,0)`, `Position UDim2.new(1,-8,0,8)` with no `LayoutOrder`. It is a sibling of `Layout = UIListLayout` (`:220`). All panelChildren are moved into the ScrollingFrame together (`:377`). A UIListLayout overrides child positions, so the "top-right" Close renders as the **first row, top-left, above the title** (the title has LayoutOrder 1 and Close defaults to 0). Its 64x24 px fixed size also doesn't scale. This is the combat class-reference window (`S/CombatApp.lua:109-117`).
Fix: move Close out of the list (a sibling of Scroll, on the outer panel), or render the reference through `Window`.

**V3 [BUG, verify] The HUD menu button and currency strip sit under the Roblox topbar.**
AppGui is created with `IgnoreGuiInset = true` in all 5 places (`L/../LobbyUI.client.lua:24`, and likewise in HordeModeUI/LaneDefenseUI/CentralBossUI/SocialPlazaUI `.client.lua:24`), and nothing disables the CoreGui topbar (no `SetCoreGuiEnabled`/`TopbarEnabled` in `src`). The HUD computes `safeTop` from `GuiService:GetGuiInset()` (`S/HUD.lua:193-194`) and uses it for banners and buttons, but **not** for:
- `menuBtn` `Position = UDim2.fromScale(0.005, 0.008)` (`S/HUD.lua:525-528`). This is the top-left corner where the Roblox menu/chat buttons render above game UI.
- `currencyStrip` `Position (0.04, 0)`, `Size (0.96, 0.055)` (`:546-549`). At 1080p that is 59 px tall, the same height as the topbar.
On phones the AppWindow title ribbon is at risk as well: the windowed panel top is at 0.09 x 390 = 35 dp (`AppWindow.lua:191-193`), which is inside a ~58 dp topbar.
Failure: the Lobby ☰ tap hits Roblox's menu, and the currency pills are covered.
Fix: a `SafeArea` wrapper that pads by the inset, or set `ScreenInsets = CoreUISafeInsets` on AppGui for the non-fullscreen layers. HUD elements anchor to that wrapper.

**V4 [BUG, mobile] Touch players have no skill, dash or interact buttons.**
`M/InputSystem/InputActions.lua:14-15`: "Touch bindings are empty because mobile on-screen buttons call InputSystem.FireAction() directly". Every action has `Touch = {}` (`:30,:41,:52,…`), but `InputSystem.FireAction` doesn't exist (the public API is `M/InputSystem/init.lua:109-285` and has no FireAction), and no UI file creates touch buttons. Only `M/MovementSystem/JoystickAim.lua:46-47` (a 120 px aim stick at `UDim2.new(1,-160,1,-160)`) is touch-aware. Whether Attack works via tap-to-click is **unspecified**.
This is the core gap for "a defined Mobile layout".
Fix: add `InputSystem.FireAction(name)` and a `TouchActionPad` component (right thumb arc: Attack large, Skill1–4, Dash, Interact contextual). Mount it only when `InputSystem` detects Touch (`init.lua:62-69`).

**V5 [SPAGHETTI] Theme is not consumed, and its accent contradicts the bodies.**
Zero feature files `require` Theme. The only consumers are `AppWindow.lua:36`, `LightningBar.lua:185-186`, `UIParticles.lua:174`. The TODO §T10/U3 recipe step (4), "migrate hardcoded colors to Theme.Colors", was skipped even in the six "CONVERTED" files: `S/ClassMenu.lua:24-40` still defines its own `C`. Theme `accent = 255,170,40` orange (`Theme.lua:31`) appears in 0 bodies, while `105,190,255` blue is the working accent in 17 files. *(known: §T10/U3 step 4, never executed. Root cause of "doesn't feel like one entity".)*
Fix: extended Theme (§4.3) plus a lint grep in review: no `Color3.fromRGB` outside Theme.

**V6 [SPAGHETTI] Converted windows keep dead close-button palette keys.**
`S/ClassMenu.lua:38-39`, `S/StatsMenu.lua:34-35`, `S/SettingsUI.lua:41-42`, `S/TalentTreeUI.lua:73`, `L/DailyLoginUI.lua:28`, `L/LeaderboardUI.lua:30` all define `close_*` keys, and each file has 0 uses. Delete them during the palette migration.

**V7 [SPAGHETTI] Duplicated components** (details in §2): 14 hand-rolled close buttons, 4 TabButtons, 8 bars, 7 card variants, 2 BonusRows, 2 ActionButtons, 10 copy-pasted HUD nav buttons (`S/HUD.lua:921-1087`, each about 15 identical lines differing only in text, color and callback), and 5 window chromes.

**V8 [MINOR] Currency identity drifts in three ways.**
- Essence: HUD cyan `80,210,255` ♦ (`S/HUD.lua:39,:563`), GlobalShop 💎 (`S/GlobalShopUI.lua:356`), Loot **purple** `140,100,255` "[E]" (`M/LootNotification.lua:33`).
- Merits: ★ / 🪙 / "[M]".
- The design brief makes essence a blue crystal and merits an orange medal (`docs/CLAUDE_DESIGN_BRIEF.md` table A), and `Theme.Icons.essence/merits` exist (`Theme.lua:84-85`), but nothing calls `GetIcon` except AppWindow.
Fix: a single `CurrencyPill` + `Theme.Currency` table.

**V9 [MINOR] The HUD Inventory button shows a trumpet.**
`S/HUD.lua:1043` `Text = "\u{1F3BA} Inventory"`. U+1F3BA is 🎺 TRUMPET. The Inventory window itself uses 🎒 (U+1F392) at `L/InventoryUI.lua:195`. Fix: `\u{1F392}`, or better, `Theme.Icons.inventory` once the ids are in.

**V10 [MINOR] Contrast below WCAG AA** (my calculations from sRGB relative luminance):
- White on `btn_active 45,175,95` is about **2.8:1** (`S/ClassMenu.lua:32`, text `:139`). That fails even the 3:1 large-text bar.
- `text_lock 110,110,132` on `bg_empty 26,26,36` is about **3.5:1** (`S/ClassMenu.lua:36,:165,:175`), which is small text.
- HUD Start `50,160,70` with white is about 3.4:1 (`S/HUD.lua:655-658`); that passes as large text only.
- AppWindow title `textOnAccent` over the ribbon's transparent blue end is about 3.7:1 (`AppWindow.lua:83-90,:111`). OK for large text, but long titles get TextScaled down.
Fix: semantic `onX` text tokens (dark text on bright fills), in §4.1.

**V11 [MINOR, mobile] Touch targets are under 44 dp at 844x390.**
- AppWindow close: header = 0.82 x 390 x 0.085 = 27 dp, so the close is 0.78 x 27 = **21 dp** (`AppWindow.lua:42,:137-138`).
- HUD nav cells: 0.135 of a 0.62 x 390 panel is about **31 dp** tall (`S/HUD.lua:891,:907`).
- ☰: 0.05x0.07 is **42x27 dp** (`:527`). navToggle: **59x35 dp** (`:862`).
- The status panel `0.17` tall with 3 rows (`:586`) gives about 16 dp rows. The value text `"1234 / 1234"` in a 0.25 x ~255 dp column TextScales down to roughly 8 dp.
Fix: `UISizeConstraint.MinSize` on all interactives (the Button/IconButton default), plus a phone layout profile (§4.5).

**V12 [MINOR] No text or aspect constraints anywhere.**
211 TextScaled labels have no `UITextSizeConstraint` (0 in repo), so text runs from giant on 4K to microscopic on phones. The 43 fixed `TextSize` labels (10–22 px) sit inside scale-sized boxes (e.g. `S/WardrobeUI.lua:148` 11 px description, `S/VoteUI.lua:118` 14 px). The two strategies are mixed inside single files. There are 0 `UIAspectRatioConstraint`, so square things (icon shells, close buttons, the HUD ☰) stretch with the viewport aspect.

**V13 [MINOR, verify] Notifications have no host, so they collide.**
`L/MatchmakingUI.lua:125-133` (top-center y 0.03–0.095, Z25) covers HUD pills in the strip at y 0–0.055 (`S/HUD.lua:546-579`, pills about 0.05–0.67 x). The PartyInvite toast (`L/PartyInviteToast.lua:102`, bottom 0.94) stacks with the HUD comboBadge (`S/HUD.lua:688`, bottom 0.92). LootNotification lives in its own ScreenGui at DisplayOrder 5 (`M/LootNotification.lua:54`), so it draws **over every open React window** (AppGui is DisplayOrder 0).
Fix: a `ToastHost` with fixed slots (top-center banner, top-right feed, bottom-center prompt), a queue, and a Z/DisplayOrder token.

**V14 [MINOR] Glyphs stand in for icons.**
Emoji and ASCII are mixed as icons (🛒 `S/HUD.lua:1011`, ⚙ `:1028`, 🏆 `:1058`, 📅 `:1075`, "X" vs "✕"). Emoji render in platform color fonts and vary by OS. Wire `Theme.GetIcon` with the glyph as fallback (the contract already exists at `Theme.lua:94-98`). *(ids pending: known §T10/ICONS)*

**V15 [DESIGN-Q] Legacy `Enum.Font` vs `FontFace`.**
All text uses `Enum.Font.Gotham*`. `FontFace = Font.new(family, weight)` would give a real weight scale (Regular/Medium/Bold/Heavy) from one family. Option: GothamSSm family (closest to today) or BuilderSans (Roblox's current UI face). Verify the asset paths in Studio.

**V16 [DESIGN-Q] The pure-Scale rule vs a reference-resolution UIScale.**
Pablo's rule is "every size in scale" (`S/BattleClassUI.lua:370`, `S/HUD.lua:522-524`). V1 and V11 are consequences of that rule without constraints. Options:
- (a) Keep pure Scale and require `UIAspectRatioConstraint` / `UISizeConstraint` / `UITextSizeConstraint` via components. This is the recommended option; it fits the rule.
- (b) Author in Offset at a 1280x720 reference with one root `UIScale = clamp(min(vw/1280, vh/720), 0.6, 1.6)`. Spacing and radius tokens become exact, but this reverses the rule.

---

## 4. Proposal: a unified design system for Roblox

### 4.1 Tokens (semantic roles; values shown for Direction A, the current anime/speed look)
```lua
Theme.Palette = {  -- raw swatches (never referenced by features)
  navy900=rgb(12,12,18), navy800=rgb(18,18,26), navy700=rgb(24,24,36), navy600=rgb(35,35,50), navy500=rgb(55,55,70),
  orange500=rgb(255,170,40), orange700=rgb(200,120,20), blue400=rgb(90,190,255), blue600=rgb(60,135,235),
  green400=rgb(80,210,120), red500=rgb(225,70,70), gold400=rgb(255,210,60), white=rgb(242,242,248),
}
Theme.Colors = {  -- SEMANTIC (features use ONLY these)
  surface.base / surface.panel / surface.raised / surface.sunken / surface.scrim,
  text.primary(235,235,245) / text.secondary(170,170,190  -- raise from 140 for 4.5:1 on raised) / text.disabled / text.onAccent(20,14,6) / text.onDanger(white),
  accent.primary(orange: CTAs, window ribbon, selection) / accent.secondary(blue: info, resource, links, focus ring),
  state.success / state.warning / state.danger / state.locked,
  border.subtle(α .6) / border.strong / border.focus(=accent.secondary),
  vital.hp / vital.hpLow / vital.resource / vital.xp / vital.boss[1..3] / vital.defense,
  currency.essence(blue400) / currency.merits(gold400) / currency.power(orange500),
  rarity.common/uncommon/rare/epic/legendary,
}
```
Rules: bright fills (success, accent.primary) take `text.onAccent` (dark), which fixes V10. Red/blue fills take white. Currency colors match the brief.

**Type scale (TextScaled + UITextSizeConstraint min/max, in dp)**
| Token | Font (weight) | Min | Max | Use |
|---|---|---|---|---|
| display | Heavy/Black, UPPER | 28 | 64 | Wave/boss banners, Victory |
| title | Heavy | 18 | 36 | Window titles |
| heading | Bold | 15 | 26 | Section and card titles, tabs |
| body | Regular/Medium | 13 | 20 | Descriptions, rows |
| label | Bold | 12 | 18 | Buttons, pills |
| caption | Regular | 11 | 15 | Hints, versions |
| numeric | Bold (tabular) | 12 | 22 | Bar values, currency |
Minimums keep phones legible. Where the min would clip, the phone profile gives the element more height rather than accepting smaller text.

**Spacing:** Scale steps relative to the parent's short side, `space = {xxs=0.005, xs=0.01, sm=0.02, md=0.03, lg=0.045, xl=0.07}`. Each is applied through a `pad(token)` helper that also sets a pixel floor (`UDim.new(scale, 0)` plus a `UISizeConstraint` on containers). Under option (b), use offsets 4/8/12/16/24/32 instead.

**Radii:** `radius = {none=0, sm=UDim.new(0,4), md=UDim.new(0,8), lg=UDim.new(0,12), pill=UDim.new(0.5,0)}`. This collapses 26 values to 5. Offset radii are safe even under the pure-scale rule because they are decorative.
**Strokes:** `stroke = {hair=1, base=1.5, strong=2, focus=2.5}` with `border.*` colors.
**Elevation and Z layers** (siblings under AppRoot, `ZIndexBehavior.Sibling`):
```lua
Theme.Z = { world=0, hud=1, hudFloat=5, window=10, windowOver=20, modal=40, toast=60, tooltip=80, debug=100 }
Theme.DisplayOrder = { app=0, loot=0 --[[move into ToastHost]], castBar=8, flash=100, loading=1000 }
Theme.Elevation = { flat={stroke="hair"}, raised={stroke="base", surface="raised"}, overlay={scrim=0.42} }
```

### 4.2 Component library API (react-lua, `S/Common/`)
```lua
Text{ style="body"|"title"|..., text, color="text.primary", align, wrap }       -- adds UITextSizeConstraint from Theme.Type
Button{ variant="primary"|"secondary"|"danger"|"ghost"|"locked", size="sm"|"md"|"lg",
        label, icon?, disabled?, loading?, onActivated, layoutOrder?, width? }
        -- uses Theme.Images.btn* 9-slice when present else flat fill+stroke; MinSize 44dp on touch
IconButton{ icon="close"|Theme.Icons key, variant="ghost"|"danger", size, onActivated, tooltip? }  -- square: AspectRatio 1
Window{ variant="windowed"|"fullscreen"|"sheet", title, icon?, onClose, headerContent?, size?, z? } -- = AppWindow + SafeArea + Escape/Back closes
Panel{ elevation="flat"|"raised", padding="md", radius="md", children }       -- cards/sections
Tabs{ items={{id,label,icon?}}, value, onChange, fill=true }                   -- replaces 4 TabButtons
Bar{ value, max, kind="hp"|"resource"|"xp"|"boss"|"progress", label?, showValue?, effect=nil|"lightning", segments? }
Toast{ kind="info"|"success"|"warning"|"reward"|"invite", title, body?, icon?, actions?, duration? }
ToastHost{ }  -- mounted once per AppRoot; API ToastService.push(toast, slot="top"|"feed"|"prompt")
Modal{ onDismiss?, dismissible=true, size, children }                          -- scrim + centered Panel, Z.modal
Tooltip{ target ref, text | content, placement="auto" }                        -- Z.tooltip; hover on PC, long-press on touch
CurrencyPill{ currency="essence"|"merits"|"power", value }
SafeArea{ children }                                                           -- pads by GuiService inset
TouchActionPad{ actions={"Attack","Skill1".."Skill4","Dash","Interact"} }      -- mobile only (V4)
```

### 4.3 Extended Theme.lua shape
```lua
Theme.Palette, Theme.Colors (semantic, nested), Theme.Type = { display={font,min,max}, ... },
Theme.Fonts = { heavy=Font.new(FAMILY, Enum.FontWeight.Heavy), bold=..., medium=..., regular=... },
Theme.Space, Theme.Radius, Theme.Stroke, Theme.Z, Theme.DisplayOrder, Theme.Elevation,
Theme.Motion = { fast=TweenInfo.new(0.12), base=TweenInfo.new(0.18, Enum.EasingStyle.Quart), emph=TweenInfo.new(0.25, Enum.EasingStyle.Back) },
Theme.Speed (existing), Theme.Icons (existing + close/back/lock/check), Theme.Images (existing),
Theme.Currency = { essence={icon="essence", glyph="♦", color=...}, merits={...}, power={...} },
Theme.Layout = { profile = "phone"|"tablet"|"desktop", touch = bool }   -- set once from viewport + InputSystem
Theme.GetIcon / GetImage (existing), Theme.textConstraint(style) helper
```
Keep the existing `Theme.Colors.accent/panel/...` keys as aliases for one release so AppWindow/LightningBar keep working.

### 4.4 Migration order (traffic first) and effort
| # | Step | Effort |
|---|---|---|
| 0 | Theme.lua extension + `Text`, `Button`, `IconButton`, `Panel`, `SafeArea`; AppWindow reads new tokens, gains SafeArea + min close size | 1.5 d |
| 1 | **HUD** (every place, always visible): SafeArea fix (V3), `NavButton` map replaces the 10 copies, `Bar`, `CurrencyPill`, phone profile | 1.5 d |
| 2 | **TouchActionPad + InputSystem.FireAction** (V4). Without it, mobile is unplayable in combat | 1.5–2 d |
| 3 | Combat overlays: DeathUI, VoteUI, BattleClassUI/class reference (V2), TeammateVitals, BossHud → `Modal`/`Bar` | 1.5 d |
| 4 | `ToastHost` + migrate Achievement toast, PartyInvite, Matchmaking, HUD banners, LootNotification | 1 d |
| 5 | First-session path: CharacterCreation, MainMenu, NPCDialog, ShopUI, WeaponSmithUI | 2 d |
| 6 | Progression menus: already AppWindow (Class, Stats, Talent, Settings, DailyLogin, Leaderboard), so palette swap + Tabs only; plus Equipment, Inventory, Wardrobe, Achievements, GlobalShop (chrome conversion, fixes V1) | 2.5 d |
| 7 | SocialPanel, KeybindSettings (→ Modal), EmoteWheel, AppearanceBar | 1 d |
| 8 | TestingUI (admin) + delete dead palettes, grep-gate `Color3.fromRGB` outside Theme | 0.5 d |
| | **Total** | **~13–14 dev-days** + Studio device passes |

### 4.5 Mobile layout (defined profile)
- Profile selection: `phone` when `min(viewport) < 500` dp **or** Touch without a keyboard; `tablet` when Touch and the short side is ≥ 500; otherwise `desktop`.
- HUD on phone: vitals top-left under SafeArea as a compact 2-row stack (HP + resource; XP as a thin strip under them). Currency collapses to one pill that expands on tap. Nav opens as a bottom sheet (2x5 grid, 48 dp cells), not a side drawer. The right half belongs to TouchActionPad (Attack 88 dp; Skills 60 dp in an arc; Dash/Interact 52 dp). The JoystickAim default (`JoystickAim.lua:47`) must move to avoid the pad, and the Roblox thumbstick owns the left.
- Windows on phone: `windowed` becomes a near-full `sheet` (0.96 x 0.92 inside SafeArea), with a header of at least 44 dp and the close at least 44 dp. Two-column bodies stack.
- Toasts on phone: a single top slot. Invites become a bottom prompt above the pad.

### 4.6 Two visual directions (Pablo's call)
**A. "Speed Anime": commit to the current Theme intent.**
- Surfaces are dark navy `12,12,18`/`18,18,26`.
- **Orange is the identity**: window ribbons, primary CTAs, selection outlines, active tab underline. Blue is resource, info and focus.
- Headers: slanted ribbon at −8° with 3 motion lines (existing AppWindow). Titles UPPERCASE in Gotham/Heavy.
- Buttons use the delivered 9-slice plates (`btnPrimary` orange gradient with streak, `btnSecondary` navy with blue inner line), plus a 1.5 px dark outline and a slight 6–10° skew on hero CTAs only.
- Bars use `barFrame` + `barShine` with UIGradient fills; the lightning crackle stays on resource.
- Motion: Back-ease pops of 0.18 s, speed-line streak particles on level-up and claims.
- Cost: every body's blue accent (17 files) flips to orange for actions. Largest diff; art is already paid for.

**B. "Clean Tactical Flat": converge on what the bodies already do.**
- Neutral slate surfaces `16,18,24` / `24,27,35` / `32,36,46`. **One accent: electric blue `90,190,255`**. Orange is reserved for rewards and currency only.
- No ribbons or motion lines. The header is a flat bar with a 2 px accent underline and Title Case in BuilderSans Bold.
- Radius 8 dp everywhere, 1 px `border.subtle` strokes. Elevation comes from surface steps, not shadows.
- Buttons are flat fills (primary blue with dark text, secondary outlined, danger red). No 9-slice plates. Icons are the delivered set tinted monochrome (`ImageColor3 = text.secondary`, accent when active).
- Bars are flat rounded fills with a thin track; lightning is reserved for the ultimate/resource-full state.
- Cost: the smallest migration (the bodies' blue already matches). AppWindow chrome is simplified. The 4 button plates and barFrame go unused.

*Hybrid note:* B for bodies and lists (readability on phones) + A only for the window header, primary CTA and HUD vitals. This keeps the anime identity where the eye lands and stays cheap. If Pablo wants a middle path, this is it.

---

## Verified good
- **G19 is effectively resolved.** `L/EmoteWheel.lua` and `socialplaza/.../EmoteWheel.lua` are 11-line re-exports of the shared module (`L/EmoteWheel.lua:8-11`).
- **BossHud layering is correct.** Root `ZIndex = 0` sits under CombatApp's AppRoot so menus cover the bar (`CB/BossHud.lua:83-85`), and the Fragment composition is at `CB/CentralBossApp.lua:10-15`.
- **The AppWindow §T10/LIVE2 fix is correct.** Square icon and close use `SizeConstraint.RelativeYY` with equal scales (`AppWindow.lua:92-99,:133-138`).
- **The `Theme.Images` slice rects match the delivered assets.** Buttons are 256² with `Rect(48,48,208,208)`; barFrame is 512x128 (checked PNG headers in `assets/ui/`). The placeholder contract `GetIcon/GetImage → nil` degrades gracefully (`Theme.lua:94-98,:123-127`).
- **The ScreenGui setup is sane.** One AppGui per place with `ResetOnSpawn=false` and `ZIndexBehavior.Sibling`, and stale-copy destruction first (`L/../LobbyUI.client.lua:15-25`). The disabled legacy `StarterGui/AppGui` stack is known and out of scope (§T10/STACK).
- **Most HUD transient elements are inset-aware.** Banners, Start/Next/Return and the death feed use `safeTop` (`S/HUD.lua:653,:715,:774`), as do BattleClassUI and BossHud (`:152-154`, `CB/BossHud.lua:62-63`). Only the ☰ and the currency strip miss it (V3).
- **ScrollBarThickness is consistently 4** across all 14 scroll frames.
- **No §10 (Audit_4.7) decided-against items were touched or re-proposed.**
