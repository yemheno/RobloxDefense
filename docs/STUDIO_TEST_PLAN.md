# Studio Test Plan: Agency-checks round (2026-09-26)

Everything on `dev` since `0e6d15e` was verified statically only: `luau-compile` / `luau-analyze`, agent code review, and headless layout math. None of it has run in Studio. Work top to bottom: the sections are ordered by **risk × blast radius**. Tick each box and note failures with the tag in brackets (e.g. `§AGX/X3`), so a fix can be traced to its commit.

**Setup:**
- Game Settings → Security → *Enable Studio Access to API Services* ON (the save lock and receipts need DataStores).
- Run `rojo serve <place>.project.json` for each place you test.
- **Device Emulator sizes:** iPhone 844×390 (landscape), Android 800×360, iPad 1024×768, 1080p desktop, and an Xbox controller.

---

## 0. Smoke: every Place boots (5 min)
- [ ] Lobby, LaneDefense, HordeMode, CentralBoss and SocialPlaza each start with **no red errors** in Output, especially `CRITICAL: required module … Init() failed` (`§AGX/X16`, boot now fails hard) and any `attempt to call a nil value`.
- [ ] Exactly one of each of `NotifyGui`, `PanelGui`, `TooltipLayer` in PlayerGui, and no `LootNotificationGui`.

## 1. Save safety: the highest stakes (`§AGX/X2`, `X3`, `X3r*`, `X8`)
- [ ] Lobby → queue → the Lane run ends → back in the Lobby: Merits/XP earned in the run are present.
- [ ] Rejoin the same server quickly after leaving: no data rollback. If a "still being saved" kick appears, it should only happen when the previous save is truly stuck.
- [ ] Stop the server with 1 player just after a run: no data lost, and no BindToClose timeout warning.
- [ ] Fire `SaveKeybindings({x={Keyboard="\255"}, Attack={Keyboard="Q"}})` from the command bar: only `Attack=Q` is kept, and the profile still saves.
- [ ] *Optional:* edit `_session` in the DataStore editor to another jobId with a fresh time. Join: you should be kicked after ~30 s. With an old time (>200 s) the lock should be taken over.

## 2. Core gameplay regressions
- [ ] **Horde spawns mobs** (`§AGX/X1`).
- [ ] **Wipe revive** (`X40`, `X50`):
  - On Normal, the party is wiped → "REVIVE — FREE (3 left)". Use them all.
  - Then the paid option appears only if you have ≥25 Essence; otherwise "Waiting for your party…".
  - Nightmare gives 1 free revive.
- [ ] Roar then GroundSlam (Ogre/Troll): speed returns to normal (`X13`).
- [ ] Damage-over-time or Thorns kill: the corpse disappears and rewards are granted (`X12`).
- [ ] **Party drops:** a healer or tank gets `LootDrop` on party kills; a low-level player in a high-level party gets roughly solo-level Merits (`X44`).
- [ ] Lane: clients can't start waves from Idle; Next Wave works only during a run (`X5`).
- [ ] Horde vote pause: attacks and skills do nothing server-side (`X7`).
- [ ] Refine pity never exceeds the chapter cap (`X9`); the Chapter 3+ refine costs are the new values (`X43`).
- [ ] Mobs are server-owned (Settings → Network → *Are Owners Shown*). Watch server physics in a 72-mob Horde; if it's too expensive, flip `MobSpawnHelper.SERVER_OWNED_TIERS.normal = false` (`X45`).

## 2b. Lifetimes and leaks (`§AGX/T11-JAN`)
- [ ] Join, respawn and leave: cosmetics and the weapon visual re-apply **once** per respawn, not twice.
- [ ] Run `game:SetAttribute("JanitorTelemetry", true)` in the server command bar, wait 60 s: the `*.player` live counts drop back after players leave.
- [ ] A class unlock at login or on level-up shows its toast (it now waits for the client handshake).
- [ ] Lane: Reset or Defeat mid-wave, then start again: one spawn loop, no stray "Wave complete", and a breach still animating at Reset does not damage the new line.
- [ ] Horde: pause/resume, and a player leaving mid-run: their markers vanish and spawning continues for the others.
- [ ] Supply and threat votes still close with the countdown and unpause after 5 s.
- [ ] Victory → auto-return to the Lobby still fires.

## 2c. Connection, return reason, VIP, Social (`§AGX/UI-FREE`)
- [ ] Stall `ServerReady` (comment out the PlaceLifecycle fire): the "Still connecting…" banner with **Rejoin** appears once the loading screen drops (~25 s). Let it arrive late: the banner clears and "Connected." shows once.
- [ ] The action banner fits on a phone (844×390) and at 1080p, with Rejoin ≥44 px.
- [ ] `player:SetAttribute("VIP", true)` on the server → a blue `[VIP]` before the name in chat, in every place.
- [ ] Social panel (phone and desktop): orange ribbon header, Party/Guild tabs (LB/RB on pad), member list scrolls, "DISBAND PARTY" and "REFRESH" fit their buttons, leader-only Kick/Lead, and party errors show as a toast.
- [ ] *Published only:* a public-server bounce shows the return-reason toast in the Lobby.

## 2d. Party start gate, party class, lore, locks (`§AGX/WC`)
- [ ] **Solo, all three combat places:** Lane/CentralBoss show Start once the HUD is up (a "Waiting for party (1/1)" banner may flash). Horde auto-starts after load; the first supply vote comes ~45 s after `start gate OPEN`, not after server boot.
- [ ] **Team Test, 2 players:** hold client 2 at loading. Client 1 sees "Waiting for party (1/2)…" and Start is refused. It opens when client 2 is ready, or ~20 s later with a "dropped from the wait" warning. Same for Horde.
- [ ] Hide and show the HUD while waiting: the banner comes back.
- [ ] *Published:* queue as an unlocked non-Aegis class → you arrive as that class. A locked class name is ignored with a warning.
- [ ] Talk to a lobby lore NPC, close, rejoin: `TalkedTo_<id>` is set right after load.
- [ ] Normal weapon/armor reroll and refinement still work. (Optional: inject an `error()` mid-reroll; the next reroll is not stuck on "already in progress".)

## 2e. Keystones and combat balance (`§AGX/X11`, `§AGX/BAL`)
- [ ] All 5 places boot with KeystoneRules loaded. The Talent UI shows "(coming soon)" on exactly 6 keystones.
- [ ] Overwhelm / Cull the Weak: damage differs on full-HP, <70% and <25% mobs; Cull's lifesteal heals.
- [ ] Second Heart: drop under 35% → 4 heal ticks and lower outgoing damage for 4 s; not again within 45 s.
- [ ] Perfect Form: stand still 2 s → more crits; one step removes it for 2 s.
- [ ] Unyielding Advance / Last Bastion: less damage taken in a crowd and at high Determination; Taunt lasts longer above 70%.
- [ ] Clarity Surge: no lifesteal; resource bumps on crit heals and crit skill hits. Shared Grace: overheal on a full-HP ally becomes a heal over time.
- [ ] Genesis full heal shows its number. Verdant Bloom ticks are ~15% bigger. Healer feel check: does a Life Steward still feel strong?
- [ ] Equip gear with a crit-damage roll: Stats shows crit damage like 1.5 → 1.6, not pinned at 1.8.

## 2f. Review fixes (`§AGX/D-FIX`)
- [ ] Horde: make `HordeModeSpawner.Start` `error()` temporarily → a "Spawner start failed" warning, but the run timer still ends the run and votes still appear.
- [ ] Block ClientReady on the client temporarily: Horde starts and Lane's Start works after ~20 s (Lane refuses with "Waiting for party (0/1)" until then).
- [ ] Horde gate open: HUD goes straight to Defending, no Start-button flicker.
- [ ] Horde with a level ≥2 account: no wave credited at run start. A second player joining mid-run neither credits a wave nor resets the horde level.
- [ ] Force an `error()` in `RollBonuses` (or refinement's `GetCeilingBelow`): the exact Merits/Essence come back with a "refunded" toast. An error after the item changed: no refund, a "reopen the menu" toast, and the next attempt still works.
- [ ] Several Horde votes back to back: one countdown each, and the world unpauses ~5 s after each resolve.

## 3. Teleports and matchmaking (`X4`, `X6`, `X14`, `X15`)
Studio can't test reserved servers. Check what it can:
- [ ] Kick, leave, join or disband during the countdown → "Party changed — queue cancelled".
- [ ] "Launching" times out after 20 s with Retry / Close.
- [ ] The countdown number shows (not "?").
- [ ] Return button reachable after a run.

**Live test (published):** match → a new reserved server per party; joining a public combat server bounces you to the Lobby.

## 4. Central Boss (`X28`)
- [ ] Temporarily set `available = true` in `GameModeConfig` and `MainMenu` ("FLIP HERE").
- [ ] Start → the Iron Warden spawns. Use `DebugCommand("bossHP", 0.6/0.3)` to force phases 2 and 3 (Roar, faster attacks, adds). Kill it → Victory, plus boss drops and `boss_slayer` for **every** party member.
- [ ] The boss bar sits in the top-centre slot, and Start / Next / banners stack below it.

## 5. UI shell: menus, back, input (`§AGX/UI-P3`, `UI-FIX`)
- [ ] **Desktop:** the right-edge rail. Character and Progress open flyouts; the other groups open directly.
- [ ] **Phone:** ☰ top-right → MenuSheet in two rows (no scroll on iPhone), with PLAY as the only orange button in the body.
- [ ] **Gamepad:** D-pad Down → radial.
- [ ] **Back:**
  - Backspace or B closes the top panel **only**. B with a panel open must **not** dash.
  - B with nothing open dashes in combat.
  - Esc opens the Roblox menu only.
- [ ] With Stats open near an NPC, E or tapping the prompt does nothing.
- [ ] Opening a menu hides the SkillPad / ActionBar and blocks skills. Closing it restores combat; the input must never stay stuck in "UI".
- [ ] Closing a menu mid-wave keeps Next Wave / Return correct (`UX-02`).
- [ ] Knocked down or dead: panels hide, and they reappear on revive.
- [ ] A Horde vote opened while the radial is up: you can still walk and vote (`UI-FIX 5`).
- [ ] **SocialPlaza:** Talents and Achievements show data; EXIT → confirm → Lobby.
- [ ] New player: Character Creation first; Daily Login auto-opens after it (once per session).

## 6. Mobile (phone 844×390 and 800×360)
- [ ] Character Creation completes with a single tap on Confirm (defaults preselected).
- [ ] **SkillPad:**
  - Attack (hold repeats), skills and dash work.
  - Cooldown wipes show; unaffordable skills dim from the start.
  - Horde: drag from Attack to aim.
- [ ] Toasts sit centred under the banner, clear of Skill 4 and Dash. The ☰ is not under the ult.
- [ ] Talent tree: pan, pinch, fit; tap selects, then Allocate. The Refund button stays disabled (the server has no single refund).
- [ ] NPCs: the native "Talk – <name>" prompt opens the shop, smith and dialog.
- [ ] Every close button and tap target is ≥44 px; nothing sits under the top bar or the notch.
- [ ] Emote wheel opens from the HUD quick button; it closes on an outside tap or thumbstick movement.

## 7. Look and feel: Hybrid Theme v2 (1080p and phone)
- [ ] Mount `UI/Common/_Showcase` (command in its header) and review every component at each size.
- [ ] Orange appears only on window ribbons, one primary button per screen, and HUD vitals; bodies are blue on navy.
- [ ] Each re-skinned screen opens as a sheet on phone and a window on desktop:
  - Stats, Class, Equipment, Wardrobe, Achievements, Talents
  - Shop, Settings, Character Creation, Main Menu, NPC Shop / Smith / Dialog
  - Death, Vote, Class reference, Inventory, Leaderboard, Daily Login
- [ ] Settings → Controls is the only keybind editor. While a key is being captured, clicking ✕ or a tab must **not** bind a mouse button (`UI-FIX R1`).
- [ ] Main Menu: select a mode card, then one "Play <mode>" button.
- [ ] The lightning resource bar stays inside its track at 1080p (`UI-FIX 4`).
- [ ] Tooltips inside panels appear above the panel (`UI-FIX 3`).

## 8. Gamepad (`§AGX/UI-P7`, `UI-FIX`)
- [ ] One blue focus ring on every control. The hint strip "A Select · B Back · LB/RB Tabs" shows only on the pad.
- [ ] Settings: LB/RB switch tabs, the D-pad adjusts sliders, and the right stick scrolls.
- [ ] Opening Stats focuses a "+" (not Respec). The talent tree focuses the Origin, with stick pan and trigger zoom.
- [ ] Start Game and Next Wave are **not** auto-focused, but Return is. Death focuses Revive or Respawn; Vote focuses the first card.
- [ ] Horde twin-stick and the camera still work after opening and closing a panel.
- [ ] A party invite can be accepted with the pad.
- [ ] While a panel with a scrollable list is open, the right stick scrolls the list, not the camera. That is intended; check it feels right.
- [ ] Talent tree on a pad: a double A press does **not** allocate; use the Allocate button.
- [ ] On a phone or console with no keyboard, Settings → Controls key badges show as locked (rebinding needs a keyboard).

## 9. Economy and monetization spot-checks
- [ ] **Veteran free appearance change** (`§AGX/X18b`):
  - At level 49, "Change appearance" is locked ("Unlocks at level 50").
  - Reach level 50 → Veteran toast, and a badge on the Character group. The creation screen does **not** open.
  - Tap the entry → the creation screen opens → submit. It then reads "No changes left".
  - The paid appearance change is refused while the free change is still unused.
  - Leave mid-creation and rejoin: the entry reopens the screen without using up a second change.
  - An account already past 50 gets Veteran on login.
  - Locked in combat places.
  - The gamepad radial shows all 7 Character entries.
- [ ] Respec costs 25 Essence everywhere (UI labels too); the respec scroll costs 25.
- [ ] **Consumables** (`§AGX/X10b`): the 8 potions/buffs are buyable; Swiftness shows "Coming soon".
  - Inventory → Use on a potion: refused at full HP (count unchanged); when hurt, HP rises over ~2 s and the count drops. Reuse within the cooldown says "on cooldown".
  - Mana Crystal refused when the bar is full. Power Scroll / Crit Oil refresh their timer instead of stacking, and the Feed says "… wore off." after 45 s.
  - Fortune Incense: kill Merits +15%. Ironskin: Armor +~12%, no compounding on refresh.
  - Knocked down or Horde paused: Use refused.
  - Leave mid-buff and rejoin: the buff is gone, and MeritBonus in Stats is back to gear/talent only.
- [ ] **Shop rotation** (`§AGX/D7`):
  - Consumables: 5 staples + exactly 3 buffs; Cosmetics: 4 of 7; Premium: no rotation bar. "Rotates in hh:mm" matches the next 00/06/12/18 UTC (Consumables) or 00:00 UTC (Cosmetics).
  - Rejoin or change server: same stock. A second account sees different stock.
  - Refresh: first tap "Confirm (5 ◆)", second tap re-rolls (≥1 new item, timer unchanged). Then 10, then 20; after 3, "No refreshes left". Survives rejoin.
  - Fire `ShopRefresh` twice in one frame with the same payload: charged once. Buying an item not in your stock is rejected with no charge.
  - NPC shops still sell potions and crystals; Swiftness still can't be bought.
- [ ] Daily login: the calendar day advances per claim, and the spree resets after a missed day (`X47`).
- [ ] Leaderboards: Highest Wave and Play Time have entries after a run (`X27`).
- [ ] **Premium:** everything is disabled until you create the real products. When you do, follow `docs/BALANCE_NUMBERS.md` §48 and the steps in commit `1c6e333`.

---

**Only you can do these (no agent can):**
- Bulk-import the delivered menu icons and paste the ids into `Theme.Icons` (also add `play`, `leave`, `emote`, `menu`).
- Rotate the Open Cloud key (G20).
- Create the DevProducts / GamePass.
- Run the live reserved-server test after publishing.
