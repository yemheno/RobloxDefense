# UI Revamp & Mobile Layout: Plan (2026-09-26)

> Merged from three read-only agency-agent audits (the full reports, cited at `file:line`, are in `docs/ui_audit/`):
> - `visual-system.md` (ui-designer)
> - `structure-and-flow.md` (ux-architect)
> - `mobile.md` (ux-researcher + roblox-experience-designer)
>
> Status (updated 2026-09-26):
> - **P0 bug fixes have landed** (commit 0c93026, tag `§AGX/UX-0n`).
> - **Mobile blockers have landed**, using the recommended defaults for D4/D5/D6/D10/D11/D12. None of this needed D1–D3:
>   - char creation, NPC ProximityPrompts, emote wheel (ff49c04)
>   - SkillPad + PC ActionBar + FormFactor (610f9ac, cda89db)
>   - talent tree touch (84e210d)
>   - safe area/notch/landscape/44 px HUD (cfba00b)
>   - legacy screens at 44 px (b38a8a3)
> - **P4 Notify has landed** (dfefb37), including the wave/run banners, killfeed, combo, boss phase, vote and matchmaking migration (74b7ac8).
> - **D1–D3 decided** (cdba264): Hybrid visuals, fixed + UIScale sizing, icon rail.
> - **P1 Theme v2 has landed** (2e3fdf5): tokens, the component library and the compensated UIScale layer.
> - **P3 Shell and P5 HUD regions have landed** (spec `docs/ui_audit/shell-spec.md`): agents A (e9dab2c: PanelStack, Registry, PanelHost, ServerOpen, BadgeStore, one back route), B (52d7fb3: rail / MenuSheet / radial, leave confirm) and C (8871472: HUD regions + layout table, Notify/SkillPad/ActionBar footprints), then the Wave 2 integration: every place App is now `Shell{place}`, the ☰ + ⋮ drawer (`HUD/LegacyNav`) and the Plaza `AppearanceBar` are deleted, and InventoryUI / LeaderboardUI / DailyLoginUI moved to the shared UI folder (available in every place).
> - **Next:** the W6 Studio pass (shell-spec §5), then P6 screen migration and P7 gamepad focus.
> - Nothing has been tested in Studio yet.

---

## 1. Why it doesn't feel like one game

- **No shared styling.** None of the 38 feature screens `require` `Theme.lua`. There are 29 private palettes, 473 `Color3.fromRGB` literals and **218 distinct colors**.
- **Two accents fighting.** Theme's accent is orange, but it appears in zero screens. The screen bodies use blue in 17 files, so every converted window has an orange header over a blue body.
- **Everything is built several times over:**
  - 14 hand-rolled close buttons
  - 4 tab implementations
  - 8 progress bars
  - 7 card variants
  - 5 window chromes
  - 3 currency icon schemes
- **No single navigation model:**
  - seven different ways to close things
  - no Esc/B/back
  - panels that can stack over each other
  - five different feedback mechanisms, with auto-clear delays of 2, 2.5, 3, 3.5 and 4 s
  - eight elements competing for the top-centre of the screen
- **Scale-on-scale sizing.** Pixel sizes were divided by 1920×1080 and then placed inside panels, so they shrink twice. Close buttons are 1–21 px on phones, and the emote buttons are 4×6 px.

## 2. Mobile today: the game can't be played on a phone

Top blockers, ranked (details in `docs/ui_audit/mobile.md` §3):

1. **Character creation can't be completed.** Gender buttons are 23×6 px, there is no default, and Confirm overlaps the swatches. Every new mobile player is stuck at minute zero.
2. **No touch path for Attack, Skills 1–4 or Dash.** `InputSystem.FireAction` is referenced but doesn't exist, and every Touch binding is empty. There is no skill bar and no cooldown display on any platform.
3. **Can't start a match.** The ☰ menu is under Roblox's top bar, the difficulty buttons are 13 px tall, and Play is 26 px.
4. **Can't talk to NPCs.** The prompt is a non-tappable billboard that says "[E] Talk". Shops, the smith, quests and teleports are all behind it.
5. **Close buttons are 1–21 px on phones.**
6. **The talent tree can't be panned or zoomed by touch,** half the nodes start off-screen, and a tap spends the point immediately.
7. **No safe-area handling:**
   - the notch cuts off content at the left edge
   - HP sits under the left thumbstick
   - teammate vitals run into the menu button
8. **Party invite Accept/Decline buttons are 12 px tall,** on a toast that times out.
9. **220 auto-scaled text labels with no minimum size.** Some render at 5–9 px.
10. **Emotes and SocialPlaza don't work on touch.**

## 3. Target architecture

One UI shell, the same in every Place:

| Piece | What it is |
|---|---|
| **Tokens (`Theme.lua` v2)** | Semantic palette roles (`surface.*`, `text.*`, `accent.primary/secondary`, `state.*`), a type scale with min/max sizes, spacing, 5 radii, strokes, and fixed **layers** (HUD < windows < modals < toasts < tooltips) with DisplayOrder bands. |
| **`FormFactor` + `useFormFactor()`** | Classifies Phone / Tablet / Desktop / Console from the viewport's short side and the last input type. Exposes the per-form-factor size tokens (minimum tap target 48 on phone), the top-bar inset and the UI scale. Replaces the four ad-hoc inset reads. |
| **Safe-area roots** | Two ScreenGuis per Place: a full-bleed one for backdrops, and a `DeviceSafeInsets` one for everything tappable. |
| **Components** | `Text` (with min/max size), `Button`, `IconButton`, `Window` (`variant="auto"`: full-screen sheet on phone, windowed on tablet/PC), `Panel`, `Tabs`, `Bar`, `Card`, `CurrencyPill`, `Modal`, `Toast`/`ToastHost`, `Tooltip` + `usePressHold` (hover on PC, long-press on touch), `SafeArea`, `ActionBar`/`SkillPad`. |
| **Registry + PanelStack** | One table of menu entries, with the same order everywhere; entries that don't apply show as locked rather than hidden. PanelStack enforces one panel open at a time (sub-panels push onto it), routes server-opened panels such as NPCs and character creation, switches input to the `"UI"` context so skills don't fire behind menus, closes consistently via ✕ / Esc / B / back, and keeps the HUD hidden rather than unmounted. |
| **Notify** | Four kinds, each with one screen region and one timing: toast (top-right, 3.5 s, queued), banner (top-centre, single slot with a priority queue), feed (right side, killfeed and loot), and inline (`useRequest` pending/ok/err inside panels). Backed by one server `Notify` push event, which also closes the §DISC/D8 feedback gap. |
| **HUD regions** | Top-left: vitals. Top-centre: banner, or the boss bar in CentralBoss. Top-right: menu and currencies. Left-middle: party. Right-middle: feeds and objectives. Bottom-centre (PC) / bottom-right arc (phone): a **new action bar with cooldowns**. The per-Place UDim2 layouts are in `mobile.md` §2.5. |

**Phone combat layout (landscape).**
- **Left side:** Roblox's movement stick only.
- **Right side:**
  - Attack button (96 px) in the corner.
  - Skills 1–4 (60 px) on an arc around it.
  - Dash (52 px) beside Skill 1.
  - Each skill shows its cooldown as a radial wipe.
- **Top-left:** vitals.
- **Top-right:** the menu button.
- **Panels:** open as full-screen sheets, each with a 48 px close button.

## 4. Decisions for Pablo

> **Decided 2026-09-26 (Pablo: "go with your recommendation"):**
> - D1 = **Hybrid**
> - D2 = **fixed sizes at phone scale plus one root `UIScale` per form factor** (this replaces the old pure-Scale rule, V16)
> - D3 = **icon rail**, with a radial on gamepad
> - D4–D15 = the recommended column below

The **first three block the build**. For the rest, the recommended option applies unless you say otherwise.

| # | Question | Options | Recommendation |
|---|---|---|---|
| **D1** | **Visual direction** | A "Speed Anime": commit to orange ribbons and CTAs using the delivered button art. B "Clean Tactical Flat": blue accent, flat, minimal. **Hybrid**: B for bodies and lists, A for headers, CTAs and HUD vitals. | Hybrid: it keeps the anime identity where the eye lands, reads well on phones, and is cheap |
| **D2** | **Sizing model** | (a) fixed sizes at phone scale plus one root `UIScale` per form factor; (b) keep pure-Scale sizing and add min/max constraints through the components | (a): the only option that guarantees 44+ px tap targets. It does break your "pure Scale" rule (V16), so it's your call. |
| **D3** | **Menu surface** | A: icon rail on the right edge; B: ⋮ drawer driven by the registry; C: radial | A, with C as the gamepad presentation |
| D4 | Orientation | landscape-only, or also portrait | Landscape-only |
| D5 | NPC interaction | native `ProximityPrompt`, or a custom tappable billboard | ProximityPrompt |
| D6 | Skills while a menu is open in combat | suppressed (UI context), or live | Suppressed |
| D7 | Combat menus | translucent side sheet that keeps vitals visible, or today's full dim | Side sheet on PC and tablet; full sheet on phone |
| D8 | Click outside a panel to close | all panels, or only small dialogs | Small dialogs only |
| D9 | Toast position | top-right, or bottom-centre | Top-right |
| D10 | Resource display on phone | bar in the vitals with skills dimming when unaffordable, or a ring around Attack | Bar plus dimming |
| D11 | Horde aim on phone | twin-stick Attack (press to attack, drag to aim), or a separate aim stick | Twin-stick |
| D12 | Talent tree on touch | tap to select plus an Allocate button, or long-press to inspect | Tap plus Allocate (respec costs Essence) |
| D13 | Currencies in combat on phone | inside the menu sheet, or a small pill at the top | Inside the menu sheet |
| D14 | Daily Login | auto-open on the first lobby join of the day | Yes, with a badge on the menu entry |
| D15 | SocialPlaza | full shell (menu, settings, exit) | Yes |

## 5. Phased plan

| Phase | Scope | Est. |
|---|---|---|
| **P0** ✅ | UX-01 (Wardrobe reachable), UX-02 (HUD survives menus), UX-03 (NPC results inline, lore chats fixed), UX-14 (class panel click-through), trumpet → backpack icon | done |
| **P1 Foundations** (Theme v2 landed, 2e3fdf5) | Theme v2 tokens and layers, `FormFactor`/`useFormFactor`, safe-area roots, `Text`/`Button`/`IconButton`/`Window(auto)`. Fix ☰ and the currency strip under the top bar. Fix the AppWindow close-button sizing, which fixes every converted window at once. | 3 d |
| **P2 Mobile blockers** | `InputSystem.FireAction` plus `ActionBar`/`SkillPad` with cooldowns (this also gives PC a skill bar). NPC interaction (D5). Convert CharacterCreation, MainMenu and PartyInviteToast. Set orientation (D4). | 4–5 d |
| **P3 Shell** ✅ (code; Studio pass pending) | Registry, PanelStack and UI input context; Esc/B/back; one panel open at a time; route NPC panels through the stack (fixes UX-05, NPC panels stacking over menus); menu surface (D3). | 3 d |
| **P4 Notify** ✅ | ToastHost, banner queue, feed, `useRequest`, and the server `Notify` event. Replace the five existing mechanisms. | 2 d |
| **P5 HUD regions** ✅ (code; Studio pass pending) | Split `HUD.lua` into region components with a per-form-factor layout table; stop BossHud colliding with the wave banner and Start; keep teammate vitals and the class badge mounted too. | 3 d |
| **P6 Screen migration** | Convert the remaining screens to the components and tokens: Talent tree (touch pan/zoom and D12), Wardrobe, Inventory, Achievements, Stats (48 px +, hold-to-repeat), Emote wheel, GlobalShop tabs, Settings (merge the two keybind editors). Palette sweep and contrast fixes. | 5 d |
| **P7 Gamepad** | SelectionGroups, first focus (P3 left the hooks). B = back already works through context gating (B = Dash in Combat, Back in UI), so Dash stays on B. | 2 d |

**Total: about 22–24 dev-days** plus Studio Device Emulator passes (iPhone 844×390, small Android 800×360, tablet 1024×768, 1080p). P1 and P2 alone (about 7–8 days) make the game playable on phones.

**Migration rule:** each screen is converted **once**, straight to the new tokens and components, in the §T10/U3 queue order. No screen is restyled twice.
