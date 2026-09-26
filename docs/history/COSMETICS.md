# Cosmetics & Animation System

> **Last Updated:** March 2026 · **Post Card/Vote System Audit**  
> **Scope:** Server + Client cosmetic pipeline, GI outfit runtime builds, animation playback layer  
> See [GAME_DOCUMENTATION.md](GAME_DOCUMENTATION.md) §30 for architecture overview. Open gaps tracked in [REVISION_TRACKER.md](REVISION_TRACKER.md) §7.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [CosmeticConfig — Data Catalogue](#2-cosmeticconfig--data-catalogue)
4. [Server-Side Cosmetics](#4-server-side-cosmetics)
   - [CosmeticManager](#41-cosmeticmanager-orchestrator)
   - [PlayerCosmeticManager](#42-playercosmeticmanager)
   - [MobCosmeticManager](#43-mobcosmeticmanager)
5. [Client-Side Cosmetics](#5-client-side-cosmetics)
6. [Network Protocol](#6-network-protocol)
7. [Animation System](#7-animation-system)
   - [AnimationConfig](#71-animationconfig)
   - [AnimationSystem](#72-animationsystem-client-module)
8. [Data Assets](#8-data-assets)

---

## 1. Architecture Overview

```
┌────────────────────────────────── SERVER ──────────────────────────────────┐
│                                                                             │
│  CosmeticManager (init.lua)          ← main server interface               │
│    ├── PlayerCosmeticManager         ← per-player wardrobe + visuals       │
│    └── MobCosmeticManager            ← mob variant skin overrides          │
│                                                                             │
│  AnimationConfig                     ← static IDs + helpers (shared        │
│                                         to all game modes via Rojo)        │
└─────────────────────────────────────────────────────────────────────────────┘
                          │ RemoteEvents │
┌────────────────────────────────── CLIENT ──────────────────────────────────┐
│  CosmeticClient         ← wardrobe cache + equip requests                  │
│  AnimationSystem        ← per-character track cache + play/stop API        │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key architectural decisions:**

- **Server applies visuals.** The server calls `PlayerCosmeticManager.ApplyVisuals` after the character model loads, guaranteeing the outfit is present on all clients via replication.
- **Client owns animations.** `AnimationSystem` runs entirely on the `LocalScript` side. The server never directly controls animation playback.

---

## 2. CosmeticConfig — Data Catalogue

**Location:** `src/shared/ServerScriptService/Modules/CosmeticConfig.lua`

### Slots

| Slot key | Description |
|---|---|
| `HEADGEAR` | Hat/helm/circlet worn on the head joint |
| `OUTFIT` | Full body replacement or overlay |

### Head Presets

Skin-tone presets applied to all six R6 body-part colours:

| ID | Display Name |
|---|---|
| `head_default` | Fair |
| `head_pale` | Pale |
| `head_dark` | Dark |
| `head_scarred` | Scarred |

### Headgear Catalogue

| ID | Rarity | Class lock |
|---|---|---|
| `none` | — | none |
| `hood_basic` | Common | none |
| `helm_aegis` | Uncommon | Aegis |
| `circlet_arcanist` | Uncommon | Arcanist |
| `mask_hunter` | Uncommon | Hunter |

### Outfit Catalogue — Visual Types

Each outfit entry has a `visual` table with a `type` field:

| Type | Behaviour |
|---|---|
| `"color"` | Recolours the R6 parts using `BrickColor`/`Color3` values defined in the config |
| `"model"` | *(stub — reserved for future accessory model support)* |

### Standard Outfits

| ID | Rarity | Class lock | Visual |
|---|---|---|---|
| `default_aegis` | Common | Aegis | color |
| `default_arcanist` | Common | Arcanist | color |
| `default_hunter` | Common | Hunter | color |
| `peasant_garb` | Common | none | color |
| `dark_knight` | Rare | Aegis | color |
| `shadow_robes` | Rare | Arcanist | color |
| `forest_ranger` | Rare | Hunter | color |

### Mob Variants

| Mob | Variant IDs |
|---|---|
| Zombie | `default`, `decayed`, `frozen`, `burning` |
| Ogre | `default`, `armored`, `enraged` |
| Troll | `default`, `elite` |

---

## 4. Server-Side Cosmetics

### 4.1 CosmeticManager (Orchestrator)

**Location:** `src/shared/ServerScriptService/Modules/CosmeticManager/init.lua`

The top-level server module. Game mode `Main` scripts call `CosmeticManager.Init()` once.

**Initialisation flow:**

```
CosmeticManager.Init()
  ├── PlayerCosmeticManager.Init()
  ├── MobCosmeticManager.Init()
  ├── Wire RemoteEvents: GetWardrobe, EquipCosmetic, UnequipCosmetic
  └── Players.PlayerAdded → SetupPlayer()
        └── on CharacterAdded: wait 0.5s → ApplyPlayerVisuals(player)
```

**Public API:**

| Function | Description |
|---|---|
| `Init()` | Bootstrap everything above |
| `ApplyPlayerVisuals(player)` | Re-run the full visual pipeline for a player's current equipped items |
| `EquipCosmetic(player, cosmeticId)` | Server-authoritative equip with ownership + class checks |
| `UnequipCosmetic(player, slot)` | Unequip the item in the given slot; reverts to class default |
| `UnlockCosmetic(player, cosmeticId)` | Add to owned without equipping |
| `HasCosmetic(player, cosmeticId)` | Boolean ownership check |
| `GetWardrobe(player)` | Return `{ owned, equipped }` |
| `GetEquipped(player)` | Return `{ headgear, outfit }` |
| `ApplyMobVariant(mob, variant)` | Delegate to MobCosmeticManager |
| `OnClassSwitched(player, newClass)` | Re-applies class-default outfit if current outfit is no longer valid |
| `ApplyHeadPreset(player, presetId)` | Apply a skin-tone preset to the live character |

---

### 4.2 PlayerCosmeticManager

**Location:** `src/shared/ServerScriptService/Modules/CosmeticManager/PlayerCosmeticManager.lua`

Manages per-player wardrobe data (persisted on the player data object) and drives the visual pipeline on the server-side character model.

#### Wardrobe Data Shape

```lua
data.Account.Wardrobe = {
    owned    = { ["dark_knight"] = true, ["hood_basic"] = true, ... },
    equipped = {
        headgear = "hood_basic",   -- or nil
        outfit   = "dark_knight",  -- or nil → falls back to class default
    }
}
```

`EnsureWardrobeData()` seeds `owned` from `CosmeticConfig.StarterWardrobe` on first join.

#### Visual Pipeline

```
ApplyPlayerVisuals(player)
  └── ApplyVisuals(player, character, wardrobeData)
        ├── ApplyHeadPresetFromData()   ← sets R6 body-part skin colours
        ├── ApplyHeadgearVisual()       ← handles "color" and "model" types
        └── ApplyOutfitVisual()
              ├── visual.type == "color"  → recolour R6 parts
              └── visual.type == "model"  → (stub, not yet implemented)
```

---

### 4.3 MobCosmeticManager

**Location:** `src/shared/ServerScriptService/Modules/CosmeticManager/MobCosmeticManager.lua`

Applies variant overrides (colour/texture swaps) to spawned mob models. Variants are defined in `CosmeticConfig.MobVariants`. Called by game-mode scripts when spawning special mob types (e.g. frozen zombies in horde mode).

---

---

## 5. Client-Side Cosmetics

**Location:** `src/shared/StarterPlayer/StarterPlayerScripts/Modules/CosmeticClient.lua`

Runs in a `LocalScript`. Maintains a local cache of wardrobe state so UI can read it without making round-trips.

### Cache Structure

```lua
local owned    = {}      -- { [cosmeticId] = true }
local equipped = {}      -- { headgear = id?, outfit = id? }
local className = nil    -- set from class-selection event
```

### Listening side (server-push)

| Remote | Payload | Action |
|---|---|---|
| `WardrobeUpdate` | `{ owned, equipped }` | Replace local cache; fire `OnWardrobeUpdated` callbacks |
| `CosmeticEquipped` | `{ slot, cosmeticId, success }` | Update `equipped[slot]`; fire `OnEquipResult` callbacks |

### Calling side (client-request)

| Function | Fires | Notes |
|---|---|---|
| `CosmeticClient.RequestWardrobe()` | `GetWardrobe` RemoteEvent | Triggers a `WardrobeUpdate` reply |
| `CosmeticClient.EquipCosmetic(id)` | `EquipCosmetic` RemoteEvent | Server validates and equips; result arrives via `CosmeticEquipped` |
| `CosmeticClient.UnequipSlot(slot)` | `UnequipCosmetic` RemoteEvent | |

### Event Subscriptions (for UI layers)

```lua
CosmeticClient.OnWardrobeUpdated(function(owned, equipped) ... end)
CosmeticClient.OnEquipResult(function(result) ... end)
```

---

## 6. Network Protocol

```
CLIENT                                    SERVER
  │                                          │
  │──── GetWardrobe (RE) ──────────────────► │
  │◄─── WardrobeUpdate (RE, { owned, equipped }) ◄──
  │                                          │
  │──── EquipCosmetic (RE, cosmeticId) ────► │
  │                          [validate, equip, apply visuals]
  │◄─── CosmeticEquipped (RE, { slot, id, success=true/false })
  │                                          │
  │──── UnequipCosmetic (RE, slot) ────────► │
  │◄─── CosmeticEquipped (RE, { slot, id=nil, success=true })
```

The server is fully authoritative. The client never modifies character appearance directly — it sends intent, the server validates and applies, and the result is replicated via standard Roblox Instance replication.

---

## 7. Animation System

### 7.1 AnimationConfig

**Location:** `src/shared/ServerScriptService/Modules/AnimationConfig.lua`  
**Replicated to:** All game modes via Rojo projects

Provides a single source of truth for animation asset IDs. Modules that need to play animations call the helper functions rather than hardcoding IDs.

#### Player Animation Data

```lua
AnimationConfig.Player = {
    Classes = {
        Aegis       = { basicAttack = "rbxassetid://128777973" },   -- ⚠ placeholder
        Arcanist    = { basicAttack = "rbxassetid://128777973" },   -- ⚠ placeholder
        Hunter      = { basicAttack = "rbxassetid://128777973" },   -- ⚠ placeholder
        LifeSteward = { basicAttack = "rbxassetid://128777973" },   -- ⚠ placeholder
    },
    Defaults = {
        idle = nil, walk = nil, run = nil,
        jump = nil, fall = nil, climb = nil,
        -- nil = use Roblox built-in animation
    }
}
```

> ⚠ All `basicAttack` IDs currently share the same R6 Wave placeholder. Replace per-class when class-specific animations are authored.

**ClassConfig integration:** `ClassConfig` reads attack animation IDs from `AnimationConfig.Player.Classes` via a lazy-loaded `getAnim(className)` helper — no hardcoded animation IDs in ClassConfig.

#### Emotes

Emote definitions live in `ReplicatedStorage/Shared/EmoteConfig.lua` — the single source of truth for both server and client. `AnimationConfig` loads emotes from `EmoteConfig` at init time.

| Key | Asset ID | Looped | Display Name |
|---|---|---|---|
| `Wave` | 507770239 | false | "Wave" |
| `Dance` | 507771019 | true | "Dance" |
| `Laugh` | 507770818 | false | "Laugh" |
| `Point` | 507770453 | false | "Point" |

**EmoteConfig API:**
- `EmoteConfig.Emotes` — array of `{ id, label, icon, animId, looped }`
- `EmoteConfig.GetEmote(emoteId)` — lookup by ID

**Consumer chain:** `EmoteConfig` → `AnimationConfig.GetAllEmotes()` (server) / `EmoteWheel.lua` (client reads `EmoteConfig.Emotes` directly)

#### Mob Animations

Populated at runtime by game-mode scripts:

```lua
AnimationConfig.RegisterMobAnimations(mobId, {
    idle   = "rbxassetid://...",
    walk   = "rbxassetid://...",
    attack = "rbxassetid://...",
})
```

#### Helper Functions

| Function | Returns |
|---|---|
| `GetPlayerAttackAnim(className)` | Attack animation ID for the given class |
| `GetMobAnim(mobId, animName)` | Specific animation ID for a registered mob |
| `GetEmote(name)` | Full emote entry `{ animId, looped, displayName, icon }` |
| `GetAllEmotes()` | Table of all emote entries (for UI listing) |

---

### 7.2 AnimationSystem (Client Module)

**Location:** `src/shared/StarterPlayer/StarterPlayerScripts/Modules/AnimationSystem/init.lua`

Runs in `LocalScripts`. Manages a per-character `AnimationTrack` cache and ensures only one animation plays per category at a time.

#### Categories & Roblox Priority Mapping

| Category string | Roblox `AnimationPriority` |
|---|---|
| `"idle"` | `Idle` |
| `"movement"` | `Movement` |
| `"attack"` | `Action` |
| `"skill"` | `Action2` |
| `"emote"` | `Action3` |

Passing no category defaults to `"idle"`.

#### Initialisation

```lua
AnimationSystem.Init()
-- Hooks Players.LocalPlayer.CharacterAdded → SetupCharacter()
-- SetupCharacter creates/finds an Animator, seeds the track cache,
-- and wires an AncestryChanged cleanup handler.
```

#### Playing an Animation

```lua
local track = AnimationSystem.Play(character, animId, {
    category = "attack",   -- string, controls priority + mutual exclusion
    speed    = 1,          -- playback speed multiplier
    looped   = false,      -- whether the track loops
    fadeIn   = 0.1,        -- fade-in time in seconds
    duration = 1.5,        -- auto-stop after N seconds (non-looped only)
})
```

`Play` stops any currently-active track in the same category before starting the new one.

#### Stopping

```lua
AnimationSystem.Stop(character, category)   -- stop active animation in one category
AnimationSystem.StopAll(character)          -- stop all categories at once
```

#### Querying

```lua
AnimationSystem.IsPlaying(character, category)         -- boolean
AnimationSystem.GetActiveTrack(character, category)    -- AnimationTrack or nil
```

#### Track Caching

`GetOrLoadTrack(character, animId)` loads each `Animation` instance once and caches the resulting `AnimationTrack` per character. Tracks are automatically invalidated and destroyed when the character is removed from `Workspace` (`AncestryChanged`).

---

## 8. Data Assets

These modules live in `ReplicatedStorage` and are used for cosmetic ID and display-name lookups:

| Module | Contents |
|---|---|
| `AssetMap.lua` | 142 texture-slot → Roblox asset ID mappings (all filled) |
| `EmoteConfig.lua` | Canonical emote definitions: id, label, icon, animId, looped (ReplicatedStorage/Shared) |
