# RobloxDefense

A cooperative defense RPG for Roblox, written in Luau with Rojo and react-lua. Players pick one of four classes, build stats, talents and gear, and defend in three combat modes across five Roblox places.

Owner: Pablo (solo dev). Agent sessions: read [CLAUDE.md](CLAUDE.md) first.

## Places

| Place | Project file | What it is |
|---|---|---|
| Lobby | `lobby.project.json` | Hub: character creation, NPC shops/smiths/quests, party, matchmaking |
| LaneDefense | `lanedefense.project.json` | Waves march down a lane toward a defense line |
| HordeMode | `hordemode.project.json` | Top-down arena, timed run, supply/threat votes |
| CentralBoss | `centralboss.project.json` | Party boss fight (placeholder boss; hidden from the menu until tested) |
| SocialPlaza | `socialplaza.project.json` | Non-combat hub: wardrobe, emotes |

Each project maps `src/<place>/` plus `src/shared/` into its place. PlaceIds are in `src/shared/ReplicatedStorage/Shared/init.lua`.

## Toolchain

| Component | Version | Pinned in |
|---|---|---|
| Rojo | 7.6.1 | `foreman.toml` |
| Wally | 0.3.2 | `foreman.toml` |
| Remodel | 0.11.0 | `foreman.toml` |
| React / ReactRoblox (jsdotlua) | 17.0.2 | `wally.toml`, `wally.lock` |
| Roblox engine | evergreen | — |
| Luau CLI (`luau-compile`, `luau-analyze`) | any recent release | not pinned; used for static checks |

## Setup

```bash
foreman install          # installs rojo, wally, remodel
wally install            # installs React into Packages/
rojo serve lobby.project.json          # or lanedefense / hordemode / centralboss / socialplaza
```

Then connect the Rojo plugin in Studio. For DataStore features (saves, session lock, receipts) turn on *Game Settings → Security → Enable Studio Access to API Services*.

**Assets are place-managed.** `.rbxmx` models (UI backdrops, character templates, mob and weapon models) live in the published places, not in git (`*.rbxmx` is ignored on purpose). A fresh clone syncs code into an existing place; it can't rebuild a place from scratch. `assets/ui/` holds the committed UI icon PNGs.

## Repository layout

```
src/shared/      code used by every place (server modules, client modules, UI, shared configs)
src/<place>/     place-only server and client code (5 places)
docs/            documentation (start at docs/README.md)
tools/           asset and content scripts (below)
assets/ui/       UI icon art (PNG), pending import into Studio
Resources/       source 3D files
RobloxAssetExtractor/   browser extension used to export asset ids
```

## Tools

| Tool | What it does |
|---|---|
| `tools/fetch_asset_ids.py`, `check_mesh_ids.py` | Query the Open Cloud API for asset ids (reads `ROBLOX_OPEN_CLOUD_KEY` from the environment) |
| `tools/fill_asset_map.py`, `gen_meshmap.py` | Build the AssetMap / MeshMap Lua tables from `asset_ids.txt` |
| `tools/mesh_to_obj.py` | Convert a Roblox text `.mesh` to OBJ |
| `tools/roblox_upload.mjs` | Upload assets through Open Cloud |
| `tools/split_gui.py`, `generate_ui.lua` | Old UI generation helpers (legacy stack) |
| `tools/*.ps1` | Windows batch export and renaming helpers |
| `tools/talent_layout/` | Talent-tree layout editor and renderer |

Keep the Open Cloud key in `.env` (ignored); never commit it.

## Documentation

[docs/README.md](docs/README.md) is the index: architecture, systems, balance numbers, design decisions, backlog, Studio test plan and history.
