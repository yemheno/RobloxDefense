# Shell (P3) + HUD regions (P5): opinion and build spec

ArchitectUX, 2026-09-26. Read-only static pass on HEAD `cdba264`. Paths are relative to `/home/user/RobloxDefense/`.
- `S/` = `src/shared/StarterPlayer/StarterPlayerScripts/`
- `L/` = `src/lobby/StarterPlayer/StarterPlayerScripts/`

Nothing here has been run in Studio. Anything marked *(verify in Studio)* depends on engine behaviour I can't check statically.

---

## 0. Opinion: does an icon rail plus a PanelStack fit this game?

1. **Yes, the registry + PanelStack is the right fix.** UX-02, UX-05, UX-06 and UX-07 all come from 3 Apps × 9–14 `useState` booleans (`L/UI/LobbyApp.lua:57-86`, `S/UI/CombatApp.lua:53-77`) with no single owner. InputSystem now has `GetContext`/`OnContextChanged`/`FireAction` (`S/Modules/InputSystem/init.lua:208-296`), and SkillPad/ActionBar already hide outside "Combat" (`S/UI/Common/SkillPad.lua:99-116`). So D6 falls out of one context override.
2. **Main risk: on phones the rail is not the menu.** A 6-icon rail is about 316 pt tall. The phone band between the top-right row and the SkillPad arc (226 pt tall, `Theme.lua:156-160`) or the Lobby jump/PLAY buttons is 40–90 pt. So the rail collapses to one ☰ button plus a full-screen **MenuSheet** on every phone, in tablet combat, and on console (radial). Phone is the primary target, so **the sheet is the main surface: build and polish it first.** The rail is the desktop and tablet-Lobby presentation.
3. **Risk: the right edge is already crowded.** Notify's toast/feed column, the TeammateVitals desktop column and the ⋮ toggle all sit there, and two of them already overlap SkillPad on phones today (findings F1, F2). The rail only works if P5's layout table arbitrates that edge. **Build P3 and P5 together**, as the three parallel agents in §5.
4. **Risk: the icons are delivered but not uploaded.** Every `Theme.Icons` id is `rbxassetid://0` (`S/UI/Common/Theme.lua:68-90`). A rail of glyph fallbacks reads worse than today's labelled drawer, so Pablo's Studio bulk import (TODO.md:658-666) is a hard prerequisite for shipping the rail. Four icons are missing: `play`, `leave`, `emote`, `menu`.
5. **Changes I'd make:**
   - Flyouts only for Character and Progress. Every other group opens directly.
   - **Keep Dash on B.** Context gating already makes B mean Dash in Combat and Back in UI, so drop P7's "move Dash off B".
   - Keep the NPC panels self-subscribing, and have them register with the stack through a hook rather than moving their event listeners into the shell. `NPCDialogue` doubles as the `useRequest` reply channel (`L/UI/NPCDialog.lua:83-129`), so moving it is risky.

---

## 1. Findings found while specifying

1. **F1 🚨 Phone combat: the ⋮ nav toggle sits under SkillPad's Skill 4 (ult) button** *(new; SkillPad landed after the audits)*.
   - **Evidence:**
     - `S/UI/HUD.lua:1050-1053` places the toggle at `AnchorPoint (1,0.5)`, `fromScale(0.985, 0.50)`, 44 px minimum.
     - `S/UI/Common/Theme.lua:158-160` puts the Attack centre 68/68 px in from the corner, with `arcRadius = 128` and Skill 4 at 270°.
     - SkillPad's ScreenGui has `DisplayOrder = 1` (`SkillPad.lua:542`, `Theme.lua:146`). AppGui is 0.
   - **Failure:** on a 750×390 safe area, the toggle spans x 687–739, y 173–217 and Skill 4 spans x 652–712, y 164–224. Skill 4 draws on top and takes taps in the overlap, so the menu toggle is half-covered in combat.
   - **Fix shape:** §3.1 collapses the rail on phones and moves the only menu control to the top-right (48×48 at `UDim2.new(1,-E,0,S)`). This is Wave-2 step W3.

2. **F2 🚨 Phone combat: Notify's toast/feed column overlaps the SkillPad arc and sits above it** *(new)*.
   - **Evidence:**
     - `S/UI/Common/Notify.lua:86` sets `displayOrder = 30`.
     - The column is anchored top-right at `UDim2.new(1, -8, 0, columnTop)` (`:802-807`), with `columnTop = max(safeTop, UI_TopRightBottomPx)` (`:547`).
     - Each toast has a 48×48 ✕ `TextButton` at its right end (`:619-629`).
   - **Failure:** in phone combat (T=58), `columnTop` is about 104. The second toast (160–208) and any feed line land on Skill 4 (y 164–224, x 652–712). The toast ✕ (x 694–742) intercepts taps meant for the ult. The combo-summary toast (`HUD.lua:586-592`) makes two visible toasts common.
   - **Fix shape:** step C4. On phones, Notify's toasts and feed move into the top-centre corridor under the banner, capped above the Dash button. On other form factors the column bottom is capped at `UI_SkillPadTopPx - G`.

3. **F3 🚨 NPC panels still open over menus after the ProximityPrompt migration** *(known: UX-05; the mechanism has changed)*.
   - **Evidence:** the prompt uses its own `KeyboardKeyCode` (`L/Modules/NPCInteraction.lua:60-66`), and the InputSystem Interact action is deliberately unbound (`:97-101`). The UI context therefore never gates it. `prompt.Enabled` only checks `inVillage()` (`:64`).
   - **Failure:** with Stats open, pressing E (or tapping the prompt) next to an NPC opens ShopUI (ZIndex 20) over Stats (ZIndex 10).
   - **Fix shape:** step A9, `prompt.Enabled = inVillage() and InputSystem.GetContext() ~= "UI"`, re-applied on `OnContextChanged`.

4. **F4 🟡 D15 "exit from SocialPlaza" needs a server change.**
   - **Evidence:** `ReturnTeleporter` is only loaded by LaneDefense, HordeMode and CentralBoss (`src/*/ServerScriptService/*Main.server.lua`; the header at `ReturnTeleporter.lua:9` agrees). The SocialPlaza load list (`src/socialplaza/ServerScriptService/SocialPlazaMain.server.lua:37-109`) doesn't include it.
   - **Fix shape:** step B9 adds `ctx.Load(SharedModules, "ReturnTeleporter")`. The module only depends on NetworkManager and TeleportService (`ReturnTeleporter.lua:38-68`).

5. **F5 🟡 Tablet sizes would be scaled twice.**
   - **Evidence:** the Tablet tokens are already enlarged (Attack 112 vs 96, skill 72 vs 60, `Theme.lua:169-185`), while D2 puts a root `UIScale` of 1.2 on top (`Theme.lua:170`, "recorded, not applied").
   - **Failure:** if P1 wraps SkillPad or ActionBar in the root UIScale, tablet controls end up about 1.4× phone size.
   - **Contract for this spec:**
     - SkillPad and ActionBar keep their own unscaled ScreenGuis with form-factor tokens.
     - Everything inside the HUD/Shell uses **phone points** under one UIScale.
     - Attributes are published in real px (§4.3).

6. **F6 ❓ Class-reference click-outside conflicts with D8.** `S/UI/CombatApp.lua:122-131` closes the 0.72×0.78 class reference when the backdrop is clicked. D8 limits click-outside to small dialogs, so the registry sets `dismissOnBackdrop=false` for `class`. That changes behaviour deliberately; say so in the commit message.

7. **F7 🟢 `UIScale` on legacy Scale-sized panels overflows the screen.** A 0.88×0.82 AppWindow under `UIScale` 1.2 renders 1.056 wide. The shell therefore applies UIScale **only** to the HUD root and the Shell surfaces, and never to PanelGui, until P6 converts the panels. (This is a P1 note.)

---

## 2. Registry (P3): `S/UI/Shell/Registry.lua`

### 2.1 Places, groups and presentation

**Place kinds** are passed by the App as `place`:
- `Lobby`
- `Plaza` (SocialPlaza)
- `Combat` (LaneDefense, HordeMode, CentralBoss)

**Groups** (the same order in every Place, rail top→bottom, sheet top→bottom, radial clockwise from 12 o'clock):

| # | Group | Button icon (Theme.Icons key; glyph fallback) | Opens |
|---|---|---|---|
| 1 | play | `play` *(missing art)*; fallback text "PLAY" in Lobby, "EXIT" elsewhere | **direct** (one entry per place, via `slot="exit"` alternates) |
| 2 | character | `classes`, fallback "CHAR" | **flyout** (6) |
| 3 | progress | `achievements`, fallback "PROG" | **flyout** (3) |
| 4 | social | `social`, fallback "SOC" | **flyout** (2) |
| 5 | store | `shop`, fallback "SHOP" | **direct** |
| 6 | system | `settings`, fallback "⚙" → use text "SET" | **direct** |

**Direct vs flyout rule:** a group whose entry count for this place (locked entries included) is 1 opens that entry directly. Otherwise it opens a flyout. Locked entries always render, dimmed, with their reason, so muscle memory stays stable across Places.

**Terms used in the table below:**
- **Presentation (PC and tablet):**
  - `windowed`: today's AppWindow.
  - `side`: D7 translucent right sheet, used in combat on Tablet and Desktop.
  - `fullscreen`
  - `dialog`: small centred window, D8 click-outside allowed.
- **Phone:**
  - `sheet`: fills the safe area, 48 px close.
  - `fullscreen`
  - `dialog`: a bottom sheet about 45% of the height.
- **Class** (priority): `system` > `modal` > `panel` > `menu`.

### 2.2 Registry table

Module path notation: `UI.X` = `PlayerScripts.UI.X` (shared); `Lobby.X` = `PlayerScripts.Lobby.UI.X` (`lobby.project.json:46-54`).

| id | module (export / static props) | icon | label key | group·order | places L / P / C | locked rule | opened by (server event) | D8 click-outside | phone | notes |
|---|---|---|---|---|---|---|---|---|---|---|
| `play` | `Lobby.MainMenu` (`onPlay` = close) | `play`* / "PLAY" | `nav_play` | play·1, slot `exit` | L | n/a (P and C show `leave` in the slot) | rail, sheet, MenuToggle, **HUD PLAY CTA** (§4) | no | sheet | The NPC teleporter keeps its own list inside `npcDialog` (❓ UI_REVAMP §3.2 wanted it to open MainMenu). Rail icon shows a pulse while matchmaking is queued (optional). |
| `leave` | action → `Shell.ConfirmDialog` → `FireServer("RequestReturnToLobby")` | `leave`* / "EXIT" | `nav_leave` | play·1, slot `exit` | P, C | P needs B9 (F4) | rail, sheet | yes (dialog) | dialog | ❓ Mid-run leave: the server allows it (`ReturnTeleporter.lua:43-47`, no state gate). Default: allowed behind the confirm. The HUD post-run Return button stays (§4). |
| `class` | L, P: `UI.ClassMenu`. C: `UI.BattleClassUI` `{showBadge=false, expanded=true, panelScale=0.72, panelScaleY=0.78, position=fromScale(.5,.5), anchorPoint=(.5,.5), zIndex=7}` | `classes` | `btn_classes` | character·1 | L P C | none | n/a | **no** (F6) | sheet | Combat is a read-only reference. Switching is server-blocked in combat (`ClassManager.lua:150-156`). |
| `stats` | `UI.StatsMenu` | `stats` | `nav_stats` | character·2 | L P C | none | n/a | no | sheet | badge `stats` |
| `talents` | `UI.TalentTreeUI` | `talents` | `nav_talents` | character·3 | L P C | none | n/a | no | fullscreen | Fullscreen everywhere (no side sheet). Badge `talents`. |
| `equipment` | `UI.EquipmentUI` | `equipment` | `nav_equipment` | character·4 | L P C | none | n/a | no | sheet | |
| `wardrobe` | `UI.WardrobeUI` | `wardrobe` | `nav_wardrobe` | character·5 | L P C | none | n/a | no | sheet | Plaza also gets a quick button (§4) |
| `inventory` | `Lobby.InventoryUI`, or `UI.InventoryUI` after W4 | `inventory` | `nav_inventory` | character·6 | L (P C after W4) | before W4: "Available in the Lobby" | n/a | no | sheet | The server manager loads in all 5 places (`LaneDefenseMain.server.lua:95`, `SocialPlazaMain.server.lua:93`) |
| `achievements` | `UI.AchievementsUI` export `default` | `achievements` | `nav_achievements` | progress·1 | L P C | none | n/a | no | sheet | Badge `achievements`, cleared on open |
| `dailyLogin` | `Lobby.DailyLoginUI` (`UI.` after W4) | `dailyLogin` | `nav_daily` | progress·2 | L (P C after W4) | before W4: "Available in the Lobby" | **auto-open D14** (§3.6), Lobby only | yes (0.38×0.46, `DailyLoginUI.lua:86`) | dialog | badge `daily` |
| `leaderboard` | `Lobby.LeaderboardUI` (`UI.` after W4) | `leaderboard` | `nav_leaderboard` | progress·3 | L (P C after W4) | before W4: "Available in the Lobby" | n/a | no | sheet | |
| `party` | `Lobby.SocialPanel` | `social` | `nav_party` | social·1 | L | P, C: "Parties are formed in the Lobby" | n/a | no | sheet | badge `party` (pending invite) |
| `emotes` | action `UI.EmoteWheel.toggle()` (`EmoteWheel.lua:369-371`) | `emote`* / "EMOTE" | `nav_emotes` | social·2 | L P | C: "Not available in battle" (the EmoteWheel action is Lobby-context only, `InputActions.lua:104-113`) | n/a | n/a | n/a | Not a stack entry: it closes the menu, then toggles the wheel |
| `shop` | `UI.GlobalShopUI` | `shop` | `nav_shop` | store·1 | L P C | none | n/a | no | sheet | |
| `settings` | `UI.SettingsUI` | `settings` | `nav_settings` | system·1 | L P C | none | n/a | no | sheet | Vetoes Back while a key is being captured (A11) |

\* = art not delivered. Add `play`, `leave`, `emote` and `menu` to the Claude Design brief. Until then the glyph fallback renders (`Theme.GetIcon` returns nil for placeholders, `Theme.lua:94-98`).

**Non-rail entries** (same registry, `rail=false`):

| id | module | class | places | opened by | D8 | phone | notes |
|---|---|---|---|---|---|---|---|
| `keybinds` | `UI.KeybindSettings` | panel (sub of `class`) | C | "Controls" inside BattleClassUI (`BattleClassUI.lua:566-567`) | no | sheet | P3 keeps it as BattleClassUI's internal overlay and adds a close handler (A13). P6 merges it into Settings (UX-13). |
| `npcDialog` | `Lobby.NPCDialog` | panel, `mount="always"`, external | L | `NPCDialogue` (type nil/`Dialogue`/`Lore` only), `NPCQuestOffer`, `NPCTeleportOffer` (`NPCDialog.lua:134-176`) | yes (small) | dialog | Distance close stays in the component (`:209-212`) |
| `npcShop` | `Lobby.ShopUI` | panel, always, external | L | `NPCShopOpen` (`ShopUI.lua:167`) | no | sheet | distance close (`:181-184`) |
| `npcSmith` | `Lobby.WeaponSmithUI` | panel, always, external | L | `NPCSmithOpen` (`WeaponSmithUI.lua:333`) | no | sheet | distance close (`:414`) |
| `characterCreation` | `UI.CharacterCreation` (`onDismiss` → close) | **modal**, `closable=false` | L P C | `CharacterCreationRequired` after `RequestCharacterStatus` (moves out of all three Apps into `ServerOpen`) | no | fullscreen | Blocks the daily auto-open until done |
| `leaveConfirm` | `Shell.ConfirmDialog` | modal | P C | the `leave` action | yes | dialog | |
| `vote` | `UI.VoteUI` (self-managed) | modal **presence** | C | VoteUI's own events | n/a | n/a | `useModalPresence("vote", visible)` (A12) |
| `death` | `UI.DeathUI` (self-managed) | system **presence** | C | `LocalPlayer` attribute `DeathState` ∈ {KnockedDown, Dead} (read in `ServerOpen`, no DeathUI edit) | n/a | n/a | |
| `menuSheet` / `menuFlyout` / `menuRadial` | `Shell.MenuSheet` / `MenuFlyout` / `MenuRadial` | **menu** | all | the rail, the ☰ button, MenuToggle | yes (always) | sheet | Choosing an entry calls `replace` (the menu gives way to the panel) |

**Not in the stack** (they keep their ownership):
- MatchmakingUI (a Notify banner plus its own controls)
- PartyInviteToast (an inline request; P6)
- TestingUI (admin)
- EmoteWheel (an overlay; `PanelStack.onOpen` closes it)
- Notify.Host
- SkillPad and ActionBar
- the HUD, TeammateVitals and BossHud
- AppearanceBar, which is **retired in W3** (replaced by the rail/sheet Wardrobe plus the Plaza quick buttons)

### 2.3 Entry schema and API

```lua
-- one entry (all fields except id/kind optional)
{ id="stats", kind="panel"|"action"|"external"|"modal"|"presence",
  group="character", order=2, slot=nil, rail=true,
  label="nav_stats", icon="stats", glyph="STATS",
  module={ folder="UI"|"Lobby", name="StatsMenu", export=nil },   -- or byPlace={Combat=..., default=...}
  props={}, places={Lobby=true, Plaza=true, Combat=true},
  lockedReason={ Combat="nav_locked_lobby" },                      -- Locale keys
  class="panel", presentation="windowed", phone="sheet", combatSide=true,
  dismissOnBackdrop=false, closable=true, mount="onOpen", subOf=nil,
  badge="stats", hotkey=nil }

Registry.Groups                         -- ordered array (§2.1)
Registry.Entries                        -- [id] = entry
Registry.forPlace(place) -> { { group, entries = { { entry, available, lockedReason } } } }
Registry.resolve(entry, place) -> component | nil
    -- lazy require. "UI" -> PlayerScripts.UI:WaitForChild(name).
    -- A place folder -> PlayerScripts:FindFirstChild(<PlaceFolder>) only when it is the
    -- current place's folder; otherwise nil -> the entry is treated as locked (defensive).
    -- PlaceFolder: Lobby="Lobby", Plaza="SocialPlaza", Combat = LaneDefense|HordeMode|CentralBoss.
```

Labels must exist in `S/Modules/Locale.lua`: a missing key renders `"[key]"` (`Locale.lua:83-85`), so B2 adds every `nav_*` / `nav_locked_*` key.

---

## 3. PanelStack (P3): `S/UI/Shell/PanelStack.lua`

This is a module-level store (like Notify, usable from non-React code) plus React hooks.

### 3.1 API

```lua
PanelStack.open(id, props?, reason?) -> ok      -- REPLACE: run close handlers of every menu/panel entry
                                                -- (top-down; a veto aborts and returns false), then push id
PanelStack.push(id, props?) -> ok               -- sub-panel: allowed only if entry.subOf == top().id
PanelStack.pop(reason?) -> ok                   -- close the top entry (runs its close handler)
PanelStack.replace(id, props?) -> ok            -- swap the top entry only (menu -> chosen panel)
PanelStack.close(id, reason?)                   -- close id and everything above it
PanelStack.closeAll(reason?)                    -- reason "system" ignores vetoes
PanelStack.back(reason?)                        -- = pop(reason or "back"); debounced 0.15 s
                                                -- (keyboard and CAS paths can both fire)
PanelStack.openWhenIdle(id, props?)             -- deferred open: fires when the stack is empty
                                                -- and no modal/system presence (D14)
PanelStack.setPresence(key, class, present)     -- class = "modal" | "system"
PanelStack.isOpen(id?) / top() / depth() / getState() / subscribe(cb) -> unsub
PanelStack.onOpen(cb) -> unsub                  -- Shell: EmoteWheel.close()

-- React
PanelStack.useState()                -> { stack, top, blocked, suspended, hudMode }
PanelStack.useCloseHandler(fn)       -- inside a panel: fn(reason) -> false vetoes (not for "system")
PanelStack.useExternal(id, isOpen, closeFn)   -- self-managed panels (NPC): register/unregister
PanelStack.useModalPresence(key, visible)     -- VoteUI
PanelStack.useFirstFocus(ref)                 -- P7 hook (see §3.5)
PanelStack.usePresentation()         -- read by AppWindow: "windowed"|"side"|"sheet"|"fullscreen"|"dialog"
```

**Close reasons:** `"x"` (the component's own ✕), `"self"` (the component already did its cleanup), `"back"`, `"backdrop"`, `"replace"`, `"toggle"`, `"distance"`, `"blocked"`, `"system"`.

### 3.2 Rules

1. **Single open.** At most one root `panel`. `open` replaces it, and only declared sub-panels `push`. A `menu` entry is always at the bottom and is replaced by the panel it opens.
2. **Priority classes: system > modal > panel > menu.**
   - **System present** (death): every panel/menu entry is suspended (hidden, still mounted). New `open` calls return false. An external that asks to open while blocked gets `closeFn("blocked")`, so the server still receives `NPCResponse Close`.
   - **Modal present** (CharacterCreation, leaveConfirm, vote): panels below it are suspended, and new panel opens are rejected (rail dimmed via `state.blocked`). They are restored when the modal ends.
3. **Server-opened panels.**
   - The NPC panels stay mounted and self-subscribed (`mount="always"`).
   - Each one calls `useExternal(id, dataIsSet, closeHelper)`. When `dataIsSet` flips true, the stack runs `open(id)`, replacing Stats or another NPC panel (this fixes UX-05's ShopUI-over-Smith stacking). Stack-initiated closes call `closeHelper(reason)`, which fires `NPCResponse{action="Close"}` exactly as today (`NPCDialog.lua:186-206`, `ShopUI.lua:217-223`, `WeaponSmithUI.lua:428`).
   - When the component closes itself (✕ or distance), it calls `onClose` → `close(id, "self")`, and the helper is not re-run.
4. **Input context (D6).**
   - While `depth() > 0`, the stack holds one `InputSystem.PushUIContext()` token. Presence entries don't hold one; the vote pause already sets "UI" in Horde (`HordeModeClient.client.lua:129`).
   - Effects:
     - SkillPad and ActionBar hide (`SkillPad.lua:116`, `ActionBar.lua:114`).
     - Skill/Attack/Dash are gated (`init.lua:171, 230`).
     - The NPC prompts are disabled (A9).
     - The EmoteWheel Q key is gated.
   - Physical Attack/Skill/Dash handlers act on "Began" only (`PlayerAttack.lua:54-56`, `SkillInput.lua:124-134`), so flipping context mid-press can't leave a hold stuck.
5. **HUD is hidden, never unmounted.**
   - The stack computes `hudMode` and publishes it as the client-local `ReplicatedStorage` attribute `UI_HudMode`. The values:
     - `"full"`: empty stack, or only a `menu` on Desktop/Console (flyout/radial).
     - `"combatSide"`: place=Combat, form factor Tablet/Desktop, top presentation = `side`.
     - `"none"`: everything else (phone sheets, Lobby/Plaza windows, fullscreen, CharacterCreation).
   - The HUD gets `hudMode` as a prop (§4.2 has the per-region visibility).
6. **Layers.**
   - PanelHost portals into its own ScreenGui `PanelGui`:
     - `DisplayOrder 20`
     - `IgnoreGuiInset=true`, then `ScreenInsets=DeviceSafeInsets` (same order as `LobbyUI.client.lua:24-31`)
     - `ResetOnSpawn=false`
   - That puts panels above SkillPad/ActionBar (1), JoystickAim (5) and the cast bar (8, known UX-08), and below NotifyGui (30), so toasts stay readable over panels. The damage flash (100) still draws on top (known UX-08, out of scope).
   - Inside PanelGui, layer Frames at `Theme.Layers`: `panel=10`, `modal=40`. With `ZIndexBehavior.Sibling`, each panel's hard-coded ZIndex (10–21, 100–103) becomes relative to its layer, so **no panel file needs a ZIndex edit.**
   - AppGui keeps the HUD (1), EmoteWheel (30), PartyInviteToast (60), DeathUI (100) and TestingUI (200).

### 3.3 Close routing

| Source | Path |
|---|---|
| ✕ in AppWindow or a custom chrome | component → `props.onClose()` → PanelHost's `onClose` = `close(id, "self")` |
| Keyboard **Backspace** | `InputActions.UIBack` (context UI) → `PanelStack.back()`. A TextBox with focus makes it `gameProcessed`, so it's ignored while typing (`init.lua:155`). |
| Gamepad **B** | `UIBack` as above. **Also**, while `depth() > 0`, PanelStack binds `ContextActionService:BindActionAtPriority("RD_UIBack", fn, false, Enum.ContextActionPriority.High.Value + 1, <keys of GetBinding("UIBack","Gamepad")>)` returning `Sink`, because Roblox's gamepad selection may consume B before `InputBegan` *(verify in Studio)*. The debounce in `back()` prevents a double pop. |
| **Esc** | Not used: the Roblox system menu owns it. |
| Backdrop / scrim | Only when `entry.dismissOnBackdrop` (D8: dialogs, flyouts, sheets of class menu). PanelHost renders a full-layer transparent `TextButton` scrim behind the entry, which calls `back("backdrop")`. The entry's content frame **must be `Active=true`**, otherwise clicks on empty panel space fall through to the scrim (UX-14). AppWindow gets this in A8, NPCDialog in A10, ConfirmDialog is built that way. |
| NPC distance | unchanged hook inside the component → `onClose` → `close(id, "self")` |
| Opening another panel | `open` → the close handler with `"replace"` for each closed entry |
| MenuToggle while anything is open | `closeAll("toggle")` |
| System (death) | suspend (not close); on revive, restore |

**Veto:**
- `SettingsUI` and `KeybindSettings` veto while a key is being captured, and the veto cancels the capture (`SettingsUI.lua:279-340`, `KeybindSettings.lua:169-193`).
- `characterCreation` is `closable=false`.
- `BattleClassUI` closes its KeybindOverlay first, then returns false (A13).

### 3.4 InputActions / InputSystem changes

```lua
-- InputActions.lua (add)
UIBack = { displayName="Back", category="UI", contexts={ UI=true }, rebindable=false,
           defaults={ Keyboard={Enum.KeyCode.Backspace}, Gamepad={Enum.KeyCode.ButtonB}, Touch={} } },
MenuToggle = { displayName="Menu", category="UI", contexts={ Lobby=true, Combat=true, UI=true }, rebindable=false,
           defaults={ Keyboard={Enum.KeyCode.M}, Gamepad={Enum.KeyCode.DPadDown}, Touch={} } },
```

**The Dash-on-B conflict is resolved by context, with no rebinding.**
- `keyToActions[ButtonB]` holds both Dash and UIBack (`init.lua:107-123`). Dispatch fires only the one whose `contexts[activeContext]` is true (`:169-174`).
- The result is B = Dash in Combat and B = Back in UI. The Lobby has no B binding.
- DPadDown is free: DPadUp is the emote wheel, and the skills use X/Y/L1/R1/R2.
- The M key is unused (grep for `KeyCode.M` is empty).
- The two editors list their actions explicitly (`KeybindSettings.lua:55-56`, `SettingsUI.lua:67-69`), so neither new action appears in a rebind list.

```lua
-- InputSystem/init.lua (add; base/override split)
-- activeContext becomes baseContext; effective = (uiOverride > 0) and "UI" or baseContext
function InputSystem.PushUIContext() -> release()   -- ref-counted, release is idempotent
-- SetContext(name) sets baseContext; fires OnContextChanged only if the EFFECTIVE value changed.
-- GetContext() returns the effective value. InputBegan/Ended/FireAction gate on the effective value.
```

This composes with HordePaused (`HordeModeClient.client.lua:129-145`) and SceneController (`L/Modules/SceneController.lua:90-95`). Neither of them can clobber an open menu's "UI" any more, and closing a menu can't un-pause a paused Horde.

### 3.5 Focus hooks for P7 (hooks only in P3; no behaviour unless the input is Gamepad)

- PanelHost gives each entry's layer Frame `SelectionGroup=true` and `SelectionBehaviorUp/Down/Left/Right = Stop`, which traps focus inside the top panel.
- `useFirstFocus(ref)`: when the entry becomes top and `FormFactor.Get().input == "Gamepad"`, set `GuiService.SelectedObject = ref.current`. On pop, restore the SelectedObject that was saved at push.
- P7 decides on `GuiService.AutoSelectGuiEnabled`. P3 doesn't touch it.

### 3.6 Server-open / auto-open (`S/UI/Shell/ServerOpen.lua`, a hook used by Shell)

1. **Character creation.** Subscribe to `CharacterCreationRequired`, then `FireServer("RequestCharacterStatus")` (same race-safe order as `LobbyApp.lua:73-84`), then `open("characterCreation")`. Delete the three copies in the Apps (W2).
2. **Daily login (D14).** Lobby only:
   - On mount, `FireServer("GetDailyLoginStatus")` (not ready-gated, `src/shared/ServerScriptService/Modules/NetworkManager.lua:241-243`).
   - On `DailyLoginStatus{canClaim=true}`, and at most once per client session, call `openWhenIdle("dailyLogin")`. This runs after CharacterCreation if that's open.
   - ❓ "First lobby join of the day": the client can't persist anything, so this rule re-opens on each Lobby visit until the reward is claimed. A strict once-per-day rule needs a profile field (for example `DailyLogin.LastAutoOpenDay`, set by DailyLoginManager). That's Pablo's call; the default is the `canClaim` rule.
3. **Death.** `LocalPlayer:GetAttributeChangedSignal("DeathState")` → `setPresence("death", "system", state ~= "Alive")`.

### 3.7 Badges (`S/UI/Shell/BadgeStore.lua`)

API: `BadgeStore.get(key) -> n`, `subscribe(cb) -> unsub`, `clear(key)`, `useBadge(key)`.

| key | source | set | clear |
|---|---|---|---|
| `daily` | `DailyLoginStatus.canClaim` (`DailyLoginManager.lua:23`) | 1 | `DailyLoginResult` success, or a later status with `canClaim=false` |
| `stats` | `StatsUpdate.unallocated` (`StatsMenu.lua:9`). Fire `GetStats` on mount and whenever `PlayerInfoUpdate.level` increases. | n | server value 0 |
| `talents` | `TalentClient.Subscribe` → `state.pointsAvailable` (`TalentClient.lua:27,55,69`) | n | 0 |
| `achievements` | `AchievementClient.OnUnlocked` (`AchievementClient.lua:86`) | +1 | `clear` when the achievements panel opens |
| `party` | `PartyInvite` (Lobby) | 1 | `PartyUpdate`, or 30 s |

**Rendering** (`Shell/Badge.lua`):
- A circle 16 pt (phone 18) at `AnchorPoint (0.5,0.5)`, `UDim2.new(1,-4,0,4)` of the icon.
- Shows a count when n > 1 (text ≥ 12).
- Colour `Theme.Colors.accent`, text `textOnAccent` (D1 Hybrid: orange accents on the HUD).
- A group badge is the OR of its entries. The collapsed ☰ badge is the OR of everything.

### 3.8 AppWindow changes (A8, `S/UI/Common/AppWindow.lua`)

- **Sinking clicks:**
  - The backdrop Frame and the `Panel` Frame get `Active = true` (`:251-270`; UX-06 click-through).
  - When `usePresentation()` says dismissable, the backdrop becomes a `TextButton` (`AutoButtonColor=false`, `Text=""`) calling `props.onBackdrop`.
- **`presentation`** comes from PanelHost context and overrides `props.variant`, falling back to `props.variant` outside PanelHost:
  - `sheet`: the panel fills the root, header = `tokens.header`, close = `tokens.close`.
  - `side`: right-anchored; width `min(0.46*W, 640)`, full height below the topbar; no dim; only the sheet is `Active`.
  - `dialog`: phone = a bottom sheet at 45% height; elsewhere = the window size passed in.
  - `windowed` and `fullscreen`: as today.
- **Close button:** `max(MIN_CLOSE_PX, tokens.close)` instead of `RelativeYY` of the header (`:197-214`). This covers the 6 AppWindow users at once:
  - ClassMenu, StatsMenu, TalentTree, Settings
  - DailyLogin, Leaderboard (both in the Lobby folder)
  - Custom-chrome panels keep their own layout until P6.

---

## 4. HUD regions (P5): the `S/UI/HUD.lua` split and layout table

### 4.1 Component breakdown

`S/UI/HUD.lua` becomes `S/UI/HUD/init.lua` (Rojo keeps the ModuleScript name `HUD`, so `SharedUI:WaitForChild("HUD")` doesn't change). The split:

| File | Owns (from today's HUD.lua) |
|---|---|
| `HUD/init.lua` | Root. Takes the props below, `useFormFactor`, `useHudLayout`, and renders the regions. The root Frame is `Size = fromScale(1/s, 1/s)` with a `UIScale` child `Scale = s = ff.uiScale`, so the phone-point values stay exact and the frame still covers the safe area (F7). |
| `HUD/RunState.lua` | A **module-level store**, subscribed once at first require, like Notify. Holds `gameState`/`countdown`/`runEnded`/`betweenWaves` (`:253-273, 449-485`), `defenseHP` (`:526-559`, replaces `cachedDefenseHP` `:35`), `defCombo` (`:562-572`) and `combo` (`:488-497`), plus the Notify wave/run banners and feed (`:499-592`) and the `MobDeath` drain (`:596`). Fires `RequestGameState` once (non-Lobby). This makes UX-02 structural. |
| `HUD/PlayerInfo.lua` | Store: HP + DeathState (`:229-236, 598-630`), resource (`:239, 398-404`), XP/level, currency, power (`:242-248, 407-446`) |
| `HUD/Layout.lua` | `useHudLayout(place, ff, hudMode, dyn)` → the region rects (§4.2), the rail band/collapse (§4.4), and the attribute publishing (§4.3) |
| `HUD/StatusBar.lua` | `StatusBar` (`:132-199`), unchanged |
| `HUD/VitalsRegion.lua` | HP/Res/XP stack (`:808-878`). `variant="full"` (Combat) or `"chip"` (Lobby/Plaza: Level + XP, per mobile.md §2.5). |
| `HUD/CurrencyRegion.lua` | Essence/Merits/Power pills (`:698-803`), with `Theme.GetIcon("essence"/"merits")` and the glyph as fallback |
| `HUD/RunControlsRegion.lua` | Start / Countdown / Next Wave / Return (`:880-918, 998-1044`). Publishes `UI_TopCentreButtonsBottomPx`. |
| `HUD/ObjectivesRegion.lua` | Defense-line bar (`:950-973`) + defense-combo badge (`:975-993`) |
| `HUD/ComboRegion.lua` | Combo counter (`:920-945`) |
| `HUD/PartyRegion.lua` | Mounts `TeammateVitals` with a `rect` prop (C2) when `partyInHud` |
| `HUD/PlayCta.lua` | Lobby **PLAY** CTA → `props.onPlay` (the Shell passes `PanelStack.open("play")`) |
| `HUD/QuickButtons.lua` | Touch-only Lobby **Emote** button and Plaza **Emote** + **Wardrobe** buttons (these replace AppearanceBar) |
| `HUD/LegacyNav.lua` | Today's ☰ + ⋮ drawer (`:223-226, 658-695, 726-754, 1046-1320`), verbatim, rendered while `props.legacyNav ~= false`. Deleted in W3. |

**HUD props after P5.** All the old props keep working in Wave 1.
- `place` (defaults to `"Combat"` unless `hideStartButton`, which means `"Lobby"`)
- `hudMode` (defaults to `hidden and "none" or "full"`)
- `railSlot` (element; rendered in the rail rect, receives `{collapsed, rect}`)
- `topCentreSlot` (element; CentralBoss BossHud)
- `partyInHud`, `classBadge` (bool)
- `onPlay`, `onEmote`, `onWardrobe` (functions)
- `legacyNav` (bool, default true)

### 4.2 Layout table

**Symbols:**
- Values are phone points, pre-UIScale (Tablet ×1.2 via the root UIScale, Console ×1.5; Desktop ×1 ❓ P1 may add a 1440p+ step).
- `S = ff.topbar + 10` (same as `HUD.lua:280` and `Notify.lua:534`).
- `E = tokens.edge` (Phone 16, Tablet 20, Desktop 16, Console 48). `G = tokens.gap` (8 / 10 / 8 / 16).
- `W`, `H` = the HUD root's size in points.
- AP = AnchorPoint.

**Combat (LaneDefense / HordeMode / CentralBoss)**

| Region | Phone | Tablet | Desktop | Console |
|---|---|---|---|---|
| menu button (collapsed) | AP(1,0) `UDim2.new(1,-E,0,S)` 48×48 | same (combat band too short, §4.4) | n/a (rail) | AP(1,0) `UDim2.new(1,-E,0,S)` 64×64 glyph chip "☰ ↓" |
| rail | collapsed | collapsed | AP(1,0.5) `UDim2.new(1,-E,0,bandMid)` 56×316 | hidden (radial) |
| currencies | **hidden** (D13, shown in the sheet) | AP(1,0) `UDim2.new(1,-(E+48+G),0,S)` 240×40 | AP(1,0) `UDim2.new(1,-E,0,S)` 300×40 | AP(1,0) `UDim2.new(1,-(E+64+G),0,S)` 300×48 |
| vitals (`full`) | AP(0,0) `UDim2.new(0,E,0,S)` **220×72** | same | AP(0,1) `UDim2.new(0,E,1,-E)` 360×96 | AP(0,1) `UDim2.new(0,E,1,-E)` 420×112 |
| class badge (`BattleClassUI` badge, `position`/`anchorPoint` props) | hidden (in the sheet as `class`) | hidden | AP(0,0) `UDim2.new(0,E,0,S)` 180×40 | AP(0,0) `UDim2.new(0,E,0,S)` 220×48 |
| defense bar (Lane) | AP(0,0) `UDim2.new(0,E,0,S+72+6)` 220×24 | same | AP(0,1) `UDim2.new(0,E,1,-(E+96+6))` 360×24 | AP(0,1) `UDim2.new(0,E,1,-(E+112+8))` 420×28 |
| party (TeammateVitals) | AP(0,0) `UDim2.new(0,E,0,leftBottom+G)`, w 200, rows 28 + gap 4, bottom ≤ 0.60·H, then it scrolls | same | AP(0,1) `UDim2.new(0,E,1,-(leftStackTop+G))`, w 240, rows 38 + 4, top ≥ S+40+G (below the badge) | rows 48 |
| boss slot (CB) | AP(0.5,0) `UDim2.new(0.5,0,0,S)` w = corridor, h 46; reserved = 54 | same | AP(0.5,0) `UDim2.new(0.5,0,0,S)` `UDim2.new(0.36,0,0,46)` | h 56, reserved 64 |
| run controls | AP(0.5,0) `UDim2.new(0.5,0,0,S+reserved)` 200×48; Return `+48+G` below Start in post-run Idle | same | 240×48 | 280×64 |
| banner (Notify) | y = `max(S+88, buttonsBottom+G)` (unchanged rule, `Notify.lua:554-555`); width = min(460, corridor) | same | same | same |
| combo | AP(0.5,1) `UDim2.new(0.5,0,1,-E)` 160×44 | same | AP(0.5,1) `UDim2.new(0.5,0,1,-(actionBarTop+G))` 200×48 | same rule |
| defense combo | AP(0.5,1) at combo top `-G` (220×28) | same | same | same |
| controls | SkillPad, bottom-right (footprint 302×226) | SkillPad (352×266 real px) | ActionBar, bottom-centre, top at 80 | ActionBar (console tokens) |
| Notify column | **centre corridor** under the banner (F2): 1 toast, feed lines until `H - max(E+44+G, dashTop) - G` | right, `-(E+48+G)` from the edge, top = `S+48+G`, bottom ≤ `skillPadTop - G` | right, offset `E + railW + G`, top = `S+40+G` | right |

**Corridor** (top-centre stack width on phone and tablet):

```
leftR  = E + vitalsW + G
rightL = W - (E + 48 + G)
corridor = 2 * min(W/2 - leftR, rightL - W/2)
```
- iPhone 844×390 (750 safe): 262 pt.
- 800×360 Android: 272 pt.

**Lobby**

| Region | Phone | Tablet | Desktop | Console |
|---|---|---|---|---|
| menu / rail | menu button AP(1,0) `UDim2.new(1,-E,0,S)` 48 | rail AP(1,0.5) `UDim2.new(1,-E,0,bandMid)` 56×316 (fits, §4.4) | rail | chip + radial |
| currencies | AP(1,0) `UDim2.new(1,-(E+48+G),0,S)` 240×40 | AP(1,0) `UDim2.new(1,-E,0,S)` 240×40 | 300×40 | 300×48 |
| vitals (`chip`) | AP(0,0) `UDim2.new(0,E,0,S)` 220×40 | same | AP(0,1) `UDim2.new(0,E,1,-E)` 300×48 | 360×56 |
| **PLAY CTA** | AP(1,1) `UDim2.new(1,-20,1,-110)` 140×56 (clear of the jump button at W-95..W-25, H-90..H-20) | AP(1,1) `UDim2.new(1,-190,1,-24)` 140×56 | AP(1,1) `UDim2.new(1,-E,1,-E)` 200×56 | AP(1,1) `UDim2.new(1,-E,1,-E)` 240×64 |
| Emote (touch) | AP(1,1) `UDim2.new(1,-194,1,-24)` 56×56 | AP(1,1) `UDim2.new(1,-338,1,-24)` 56×56 | hidden (Q) | hidden (DPadUp) |
| matchmaking | Notify banner + MatchmakingUI controls (unchanged) | same | same | same |
| party invite | PartyInviteToast, unchanged (P6) | same | same | same |

**SocialPlaza** (D15, full shell). The same as Lobby, except:
- no PLAY CTA
- Emote is AP(1,1) `UDim2.new(1,-110,1,-24)` 64×64
- Wardrobe quick button is AP(1,1) `UDim2.new(1,-20,1,-110)` 56×56

These are mobile.md §2.5's AppearanceBar values.

**Visibility by `hudMode`:**

| Region | `full` | `combatSide` | `none` |
|---|---|---|---|
| vitals, defense bar, party, top-centre (boss / run controls) | shown | **shown** (D7) | hidden |
| rail / menu button, currencies, PLAY, quick buttons, combo, class badge | shown | hidden | hidden |
| Notify toasts | shown | shown | shown (action results from inside panels) |
| Notify feed and banners | shown | shown | feed hidden; banners queue (`staleAfter` drops them) |

### 4.3 Attribute contract

- These are client-local attributes on `ReplicatedStorage`, the existing pattern (`HUD.lua:59-69`).
- **Units:** absolute px relative to the safe-area ScreenGui origin, after UIScale. The HUD multiplies its point values by `uiScale` when publishing and divides by it when consuming.
- `nil` means "region absent".

| Attribute | Publisher | Meaning | Consumers |
|---|---|---|---|
| `UI_TopRightBottomPx` | HUD Layout | bottom of the menu button / currency row | Notify (`:528`), rail band |
| `UI_TopCentreReservedPx` | HUD Layout from the boss slot when `topCentreSlot` is used; BossHud standalone in Wave 1 (`BossHud.lua:91`) | px below `S` owned by the boss bar | Notify (`:529`), run controls |
| `UI_TopCentreButtonsBottomPx` | RunControlsRegion | bottom of the visible button column | Notify (`:530`) |
| `UI_LeftColumnRightPx` **new** | HUD Layout | right edge of the vitals/party column | Notify corridor |
| `UI_RightRailLeftPx` **new** | HUD Layout | width from the safe right edge taken by the rail or menu button (+E) | Notify column offset |
| `UI_SkillPadTopPx`, `UI_SkillPadLeftPx` **new** | SkillPad | footprint distance from the safe bottom / right (arc + Dash); nil when hidden | HUD Layout (band, combo), Notify cap |
| `UI_ActionBarTopPx` **new** | ActionBar | distance from the safe bottom to the bar top (80 at 1080p) | combo placement |
| `UI_HudMode` **new** (string) | PanelStack | `full` / `combatSide` / `none` | Notify; the cast bar (follow-up to UX-08) |
| `UI_TopLeftBottomPx`, `UI_TopLeftXPx`, `UI_NavToggleTopPx` | HUD (legacy) | stays published while `legacyNav`/standalone TeammateVitals exist | **retired in W3** |

### 4.4 Rail band and collapse rule (in `HUD/Layout.lua`)

```
railCell=44, railGap=8, railPad=6 (Theme.Layout[kind].rail, fallback to these numbers)
railH = n*railCell + (n-1)*railGap + 2*railPad        -- n = 6 groups -> 316 pt; railW = 56
top    = UI_TopRightBottomPx/uiScale + G
bottom = H - reserveBR - G, where reserveBR =
         SkillPadTop (touch combat) | jump+PLAY (touch lobby: phone 166, tablet 175) |
         E+56 (desktop lobby PLAY) | 0 (desktop combat: ActionBar is centred)
collapsed = kind=="Phone" or kind=="Console" or (bottom-top) < railH
bandMid   = (top+bottom)/2
```

**Resulting surface by form factor:**

| Form factor | Surface |
|---|---|
| Desktop | rail in every place |
| Tablet | rail in Lobby/Plaza (band ≈ 118..455 = 337 ≥ 316); ☰ in combat (band ≈ 122..410 = 288) |
| Phone | ☰ everywhere |
| Console | radial |

### 4.5 Menu surfaces (B)

- **MenuRail** (props `collapsed`, `rect`, `place`):
  - A vertical `UIListLayout` of 6 `ImageButton`s (44×44, icon 28, glyph fallback text ≥ 12) with Badge.
  - Locked groups dim to `Theme.Colors.locked`.
  - When `state.blocked`, the whole rail dims and ignores input.
- **MenuFlyout** (class menu):
  - Anchored `AP(1,0.5)` at `(railLeft - G, buttonCentreY)`, clamped to the safe area.
  - A horizontal row of tiles, 88×64 on Desktop and 96×72 on Tablet. Each tile is icon 32 + label (≥ 12) + a second line with the locked reason.
  - Clicking a tile runs `PanelStack.replace(entry.id)`. For an action entry, it runs `closeAll("self")` then the action.
- **MenuSheet** (class menu, presentation `sheet`, used on phone, collapsed tablet, and the Desktop M key):
  - Header "MENU" with a 48 close button.
  - A currency pill row (D13).
  - Per group: a section label + a `UIGridLayout` of 96×72 offset cells (`FillDirectionMaxCells = floor((w+G)/(96+G))`, mobile.md §2.6).
  - Locked tiles show their reason; badges sit on the tiles.
- **MenuRadial** (class menu; Console, or any `ff.input=="Gamepad"`):
  - **Stage 1:** 6 group wedges clockwise from 12 o'clock.
  - **Stage 2:** the chosen group's entries (up to 6).
  - **Geometry:** reuse EmoteWheel's `wheelMetrics` (`EmoteWheel.lua:60-67`; export it in B6), clamped to diameter `clamp(short*0.62, 320, 560)`, button ≥ 64.
  - **Selection:** the left-stick direction, deadzone 0.5. PanelStack sinks `Thumbstick1` via CAS at high priority while it's open, so the character doesn't walk *(verify in Studio)*.
  - **Buttons:** A = confirm. B = back (stage 2 → 1, stage 1 → close). Releasing DPadDown after holding ≥ 0.25 s confirms the highlighted wedge. The centre label shows the name and any lock reason or badge.
- **MenuSurface** (B8): binds `MenuToggle`, then picks the surface:
  - Radial for gamepad input.
  - Otherwise MenuSheet.
  - The rail itself is always visible when not collapsed.

---

## 5. Migration: ordered steps, three parallel agents, no shared files

**Wave 1 (parallel, A / B / C).** The public APIs in §2.3, §3.1, §3.4, §4.1 and §4.3 are the contract. Each agent codes against them and none requires another agent's file at load time for its own behaviour. Every new behaviour sits behind a prop that Wave 2 flips, so each commit is bisectable.

### Agent A: stack, input, server-opened panels

**Owns exactly:**
- `S/Modules/InputSystem/init.lua`, `S/Modules/InputSystem/InputActions.lua`
- new `S/UI/Shell/PanelStack.lua`, `S/UI/Shell/Registry.lua`, `S/UI/Shell/BadgeStore.lua`, `S/UI/Shell/PanelHost.lua`, `S/UI/Shell/ServerOpen.lua`
- `S/UI/Common/AppWindow.lua`
- `L/Modules/NPCInteraction.lua`
- `L/UI/NPCDialog.lua`, `L/UI/ShopUI.lua`, `L/UI/WeaponSmithUI.lua`
- `S/UI/SettingsUI.lua`, `S/UI/KeybindSettings.lua`, `S/UI/VoteUI.lua`, `S/UI/BattleClassUI.lua`

**Steps:**
1. **A1** InputSystem: base/override context and `PushUIContext` (§3.4).
2. **A2** InputActions: add `UIBack` and `MenuToggle`. Dash stays on B.
3. **A3** PanelStack: store, rules, CAS B-sink, `UI_HudMode`, debounce (§3).
4. **A4** Registry: the full table (§2.2) with lazy `resolve`.
5. **A5** BadgeStore (§3.7).
6. **A6** PanelHost: the `PanelGui` ScreenGui (DisplayOrder 20), layers, entry wrappers (`Visible = not suspended`, `SelectionGroup`), the D8 scrim, `mount="always"` externals, and the presentation context. Use `Theme.Layers or {panel=10, modal=40}` as a fallback until B1 lands.
7. **A7** ServerOpen (§3.6).
8. **A8** AppWindow (§3.8).
9. **A9** NPCInteraction: prompts disabled in "UI"; re-apply on `OnContextChanged` (F3).
10. **A10** The three NPC panels: `useExternal(...)`. Add `Active=true` on NPCDialog's panel frame. Optionally make ShopUI's distance path send `NPCResponse Close` (UX-17 nit).
11. **A11** SettingsUI and KeybindSettings: veto while capturing.
12. **A12** VoteUI: `useModalPresence("vote", visible)`.
13. **A13** BattleClassUI: its close handler closes the KeybindOverlay first.

### Agent B: menu surfaces, icons, Plaza exit

**Owns exactly:**
- `S/UI/Common/Theme.lua` (additive only: FormFactor requires it, `FormFactor.lua:40`)
- `S/Modules/Locale.lua`
- new `S/UI/Shell/Badge.lua`, `MenuIcon.lua`, `MenuRail.lua`, `MenuFlyout.lua`, `MenuSheet.lua`, `MenuRadial.lua`, `ConfirmDialog.lua`, `MenuSurface.lua`
- `S/UI/EmoteWheel.lua`
- `src/socialplaza/ServerScriptService/SocialPlazaMain.server.lua`

**Steps:**
1. **B1** Theme:
   - `Theme.Layers = {hud=1, panel=10, overlay=30, modal=40, toast=60, system=100, admin=200}`
   - `Theme.DisplayOrder = {controls=1, joystick=5, castBar=8, panels=20, notify=30, flash=100, loading=1000}`
   - `Theme.Layout.<kind>.rail`:
     - Desktop/Tablet: `{cell=44, gap=8, pad=6, icon=28, tile=Vector2(88|96, 64|72)}`
     - Phone: `{collapsed=true, menuButton=48, tile=Vector2(96,72)}`
     - Console: `{collapsed=true, menuButton=64, radial={shortFrac=0.62, min=320, max=560, btnMin=64}}`
   - `Theme.Icons.play/leave/emote/menu` placeholders.
   - After Pablo's bulk import, paste the 16 ids plus 11 images (TODO.md:658-666).
2. **B2** Locale: the `nav_*`, `nav_locked_*`, `nav_leave_confirm*` keys.
3. **B3** Badge + MenuIcon: `Theme.GetIcon(key)` or glyph text.
4. **B4** MenuRail + MenuFlyout (§4.5).
5. **B5** MenuSheet.
6. **B6** MenuRadial + export `wheelMetrics` from EmoteWheel.
7. **B7** ConfirmDialog + the `leave` action.
8. **B8** MenuSurface (binds MenuToggle).
9. **B9** SocialPlazaMain: load ReturnTeleporter (F4).

### Agent C: HUD regions (P5), Notify, control footprints

**Owns exactly:**
- `S/UI/HUD.lua` → `S/UI/HUD/` (init + the §4.1 files)
- `S/UI/TeammateVitals.lua`
- `src/centralboss/StarterPlayer/StarterPlayerScripts/UI/BossHud.lua`
- `S/UI/Common/Notify.lua`, `S/UI/Common/SkillPad.lua`, `S/UI/Common/ActionBar.lua`

**Steps:**
1. **C1** Split HUD.lua (§4.1), with the layout table (§4.2) and rail band (§4.4) in `HUD/Layout.lua`. Keep every old prop working, `legacyNav` defaulting to true, and the legacy attributes published.
2. **C2** TeammateVitals: an optional `rect` prop; when it's set, the attributes are ignored.
3. **C3** BossHud: an optional `slotted` prop. When slotted it renders at (0,0) of the slot and doesn't publish `UI_TopCentreReservedPx`. Standalone behaviour is unchanged.
4. **C4** Notify: read the new attributes; phone corridor placement; cap the column above SkillPad; feed and banner gating on `UI_HudMode` (F2).
5. **C5** SkillPad and ActionBar: publish the footprint attributes (nil when `visible=false`); keep the `hidden` prop.

### Wave 2: one integrator, after A, B and C merge

**Owns:**
- `L/UI/LobbyApp.lua`
- `S/UI/CombatApp.lua`
- `src/socialplaza/StarterPlayer/StarterPlayerScripts/UI/SocialPlazaApp.lua`
- `src/centralboss/StarterPlayer/StarterPlayerScripts/UI/CentralBossApp.lua`
- `src/lanedefense/StarterPlayer/StarterPlayerScripts/UI/LaneDefenseApp.lua`
- `src/hordemode/StarterPlayer/StarterPlayerScripts/UI/HordeModeApp.lua`
- new `S/UI/Shell/Shell.lua`
- deletes `HUD/LegacyNav.lua` and `src/socialplaza/.../UI/AppearanceBar.lua`
- moves the 3 Lobby panels (W4)
- docs

**Steps:**
1. **W1** `Shell.lua` (props `place`, `topCentreSlot`) mounts:
   - the HUD (`hudMode` from `PanelStack.useState()`, `railSlot = MenuSurface`, `partyInHud=true`, `classBadge` from the layout, `onPlay`/`onEmote`/`onWardrobe`)
   - PanelHost, `useServerOpen(place)`, BadgeStore init, `PanelStack.onOpen(EmoteWheel.close)`
   - `Notify.Host`
   - SkillPad or ActionBar (Combat; **no `hidden` prop**, the context hides them)
   - DeathUI, VoteUI (Combat)
   - MatchmakingUI, PartyInviteToast (Lobby)
   - EmoteWheel (Lobby, Plaza)
   - TestingUI
2. **W2** The Apps become thin:
   - `LobbyApp`/`SocialPlazaApp` → `e(Shell, {place="Lobby"|"Plaza"})`.
   - `CombatApp(props)` → `e(Shell, {place="Combat", topCentreSlot=props.topCentreSlot})`.
   - `CentralBossApp` passes `topCentreSlot = e(BossHud, {slotted=true})`.
   - `LaneDefenseApp`/`HordeModeApp` stay re-exports.
   - Remove the 9–14 booleans, the three `CharacterCreationRequired` effects, the separate `battleClass`/`teammateVitals` mounts (`CombatApp.lua:101, 169`) and the class-reference holder (`:117-146`).
3. **W3** HUD `legacyNav=false`; delete `HUD/LegacyNav.lua`; stop the legacy attributes; delete `AppearanceBar.lua` and its require (`SocialPlazaApp.lua:28, 63-65`). This fixes F1.
4. **W4** (❓ default yes) `git mv` InventoryUI, LeaderboardUI and DailyLoginUI from `L/UI/` to `S/UI/`:
   - They only require shared modules (`InventoryUI.lua:13-17`, `LeaderboardUI.lua:13-18`, `DailyLoginUI.lua:13-19`).
   - Their managers load in every place.
   - Then update the Registry `module.folder` and `places`. The Registry is A's file, but A is done by now.
5. **W5** Docs: UI_REVAMP status, and TODO (drop P7's "move Dash off B"; the §DISC/D8 stale line, UX-17).
6. **W6** Studio pass (Pablo), in the Device Emulator at iPhone 844×390, Android 800×360, tablet 1024×768, 1080p, and with a gamepad:
   - Esc does nothing to panels.
   - Backspace and B close the top panel.
   - B still dashes in combat.
   - E near an NPC with Stats open does nothing.
   - The toast column clears Skill 4.

**Estimated effort:** A ≈ 2.5 d, B ≈ 2 d, C ≈ 3 d in parallel, then W ≈ 1 d. That's about 4 calendar days, versus 6 serial days for P3 + P5.

---

## 6. Verified good

- InputSystem already has `FireAction` with hold release (`S/Modules/InputSystem/init.lua:208-234`), plus `SetContext`/`GetContext`/`OnContextChanged` (`:279-296`). Dispatch is context-gated on both paths (`:169-174, 188-193, 230`).
- Attack, Skill 1–4 and Dash handlers act only on "Began" (`S/Modules/PlayerAttack.lua:54-56`, `S/Modules/SkillInput.lua:124-134`), so context flips can't leave a hold stuck.
- SkillPad and ActionBar hide outside "Combat" and while down (`SkillPad.lua:99-116`, `ActionBar.lua:114`), so the UI override hides them with no extra code.
- The HUD stays mounted while menus are open (`HUD.lua:723`, `LobbyApp.lua:96-97`, `CombatApp.lua:88-89`; UX-02 landed).
- `NetworkManager.OnServerEvent` connects independent listeners (`S/Modules/NetworkManager.lua:82-108`), so shell-level listeners (badges, ServerOpen) can sit beside the panels' own.
- `DailyLoginStatus` carries `canClaim` and isn't ready-gated (`DailyLoginManager.lua:23`, server `NetworkManager.lua:241-243`), so D14 is client-only.
- ClassManager allows class switching outside combat and blocks it during combat (`ClassManager.lua:150-156`), so ClassMenu in the Plaza and the read-only reference in combat are both correct.
- ReturnTeleporter has no state gate and no combat dependencies (`ReturnTeleporter.lua:38-68`), so it is safe to load in the Plaza.
- Inventory, DailyLogin, Shop and Leaderboard managers load in all five places (for example `LaneDefenseMain.server.lua:95-98`, `SocialPlazaMain.server.lua:93-96`).
- Notify already avoids the HUD regions through published attributes (`Notify.lua:525-560`), so the new attributes extend an existing contract.
- EmoteWheel is a single shared module with imperative `open`/`close`/`toggle` (`S/UI/EmoteWheel.lua:369-371`; the Lobby and Plaza copies are 11-line re-exports, G19 resolved).
- NPC panels have correct distance-close hooks and send `NPCResponse Close` from their close helpers (`NPCDialog.lua:186-212`, `ShopUI.lua:181-184, 217-223`, `WeaponSmithUI.lua:414, 428`).
- The icon art is in the repo: 12 menu icons plus essence, merits, attack and skillLocked (`assets/ui/*.png`). Glyph fallback is built in (`Theme.lua:94-98`).
- The Rojo mapping is consistent across the 5 project files: shared UI at `PlayerScripts.UI`, place UI at `PlayerScripts.<Place>.UI` (`lobby.project.json:46-54` and the other four).
