# Claude Design — UI Asset Prompt Pack (§T10/ICONS + §BEAUTY)

Copy-paste prompts for Claude Design. Each asset maps 1:1 to a key the code
already expects (`Theme.Icons` now; `Theme.Images` will be added when the
first batch lands).

## Pipeline (per batch)

1. Run the prompt in Claude Design. Always start it with the **STYLE BLOCK**.
2. Export **PNG with transparent background**, at 2× the listed size
   (downscaling hides AI artifacts; Roblox downscales cleanly).
3. Roblox Studio → **Asset Manager → Bulk Import** (or Creator Hub →
   Development Items → Decals). Grab each `rbxassetid://…`.
4. Paste the ids into `UI/Common/Theme.lua` (`Theme.Icons.<key>`).
   Claude wires anything new (buttons/bars/particles) from there.

Placeholders are safe: `rbxassetid://0` renders as the no-icon fallback,
so partial batches never break the UI.

---

## STYLE BLOCK — prepend to every prompt

> Anime action-game UI asset, flat cel-shading with bold 3–4 px dark
> (#12121C) outlines, dynamic 15° forward slant, speed-line motion streaks
> trailing to the left, high contrast, crisp vector-like edges.
> Palette: speed-orange **#FFAA28**, electric-blue **#5ABEFF**, dark navy
> **#12121C**, off-white #F2F2F8. Transparent background. No text.
> Single centered subject, readable when shrunk to 24 px.

---

## A) Menu icons — 16 assets, 256×256 (export 512)

One prompt each: `STYLE BLOCK +` *"minimal glyph icon of &lt;subject&gt;"*

| Theme.Icons key | Subject |
|---|---|
| classes | crossed sword and staff |
| stats | rising bar chart with arrow |
| talents | branching tree of nodes |
| equipment | chest armor plate |
| wardrobe | hanging cape/coat |
| achievements | laurel trophy |
| settings | angular gear |
| shop | coin pouch |
| inventory | open backpack |
| dailyLogin | calendar page with star |
| leaderboard | podium with crown |
| social | two profile silhouettes |
| essence | glowing teardrop crystal (blue) |
| merits | star medal on ribbon (orange) |
| attack | slashing blade arc |
| skillLocked | padlock with chains |

## B) Buttons — 9-slice plates, 128×128 (export 256)

9-slice rule: decoration (corners, bevel, outline) must live in a uniform
**24 px border**; the center must be flat/stretchable. Corners identical.
(Roblox stretches via `SliceCenter = Rect(24,24,104,104)`.)

- **btnPrimary** — `STYLE BLOCK +` "rectangular UI button plate, speed-orange
  gradient (#FFAA28 → darker orange bottom), slanted highlight streak in the
  top border, dark outline, flat stretchable center"
- **btnSecondary** — same, "dark navy plate (#1A1A2E), thin electric-blue
  inner border"
- **btnDanger** — same, "deep red plate, warning chevron corners"
- **btnLocked** — same, "desaturated gray plate, subtle diagonal hatching
  in the border only"

## C) Vitals bar kit (HP / Mana / XP)

- **barFrame** — 9-slice, 256×64 (border 20 px): `STYLE BLOCK +` "sleek
  slanted capsule UI bar frame, dark navy, angled cut ends, thin
  electric-blue trim line, flat empty center"
- **barShine** — 256×64 overlay: "subtle diagonal glass-shine streaks,
  white at 10–20% opacity on transparent" (goes over any fill)
- **Fills are code** (UIGradient) — no asset needed; HP orange-red,
  Mana #5ABEFF, XP gold. Keeps colors tweakable.

## D) 2D particle sprites — WHITE on transparent (code tints them)

All monochrome white so one sprite serves every color via `ImageColor3`.
64×64 unless noted.

- **pGlow** — soft radial glow blob, feathered edge
- **pSpark** — sharp 4-point star spark, thin points
- **pBolt** — 128×32, single jagged lightning segment, horizontally
  tileable (both ends terminate at vertical center of left/right edges)
- **pStreak** — 128×16 horizontal speed streak, tapered tail
- **pEmber** — tiny irregular dot with 1 px glow halo

These drive the `UIParticles` module + `LightningBar` (mana crackle,
button hover sparks, level-up bursts).

## Consistency tips for Claude Design

- Reuse the exact STYLE BLOCK verbatim every time — it is the style anchor.
- Batch related assets in one conversation ("same style as the previous
  icon, now: …") for tighter consistency.
- If an icon comes back with a background, re-ask: "same image, background
  fully transparent, no backdrop shape".
- Reject anything unreadable at 24 px; ask for "thicker strokes, simpler".
