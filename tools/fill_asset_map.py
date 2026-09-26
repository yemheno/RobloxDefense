#!/usr/bin/env python3
"""
fill_asset_map.py
Parses tools/asset_ids.txt (Chrome plugin export from creator.roblox.com),
then fills the matching entries in AssetMap.lua.

The Chrome plugin emits tab-separated rows:
    Images/Xiao_Body_Diffuse    118584819881440   ← named image (direct fill)
    Image                       131660743054815   ← unnamed (API lookup)
    Meshes/Xiao_Head            98897340758341    ← FBX mesh  (skipped)
    RenderMesh                  117664845530250   ← FBX mesh  (skipped)
    Texture                     84429346238563    ← misc      (skipped)
    base_color_texture          98641863777650    ← misc      (skipped)

Two-pass strategy:
    Pass 1 — Named Images/*:  stem extracted directly, no API needed.
             Named entries always overwrite (they're the most recent upload).
    Pass 2 — Unnamed "Image": API lookup to discover the name, then fill only
             if that slot is still empty (named entries take priority).

Usage:
    python tools/fill_asset_map.py

Future improvement:
    Store ROBLOX_OPEN_CLOUD_KEY=<key> in a .env file at the project root.
    The Open Cloud Assets API can list every uploaded image automatically,
    eliminating the need for the Chrome plugin entirely.
"""

import json
import os
import re
import time
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

# §AGX/X49: repo root derived from this file (tools/ -> repo), overridable
# with --workspace; the old hard-coded Windows path is used only if the
# derived root doesn't look like the repo and that path exists.
_LEGACY_WORKSPACE = Path(r"C:\Users\P_Guilleminot\Desktop\Developer\RobloxDefense")


def resolve_workspace(cli_value=None):
    if cli_value:
        return Path(cli_value).expanduser().resolve()
    repo = Path(__file__).resolve().parent.parent
    if (repo / "src").is_dir():
        return repo
    if _LEGACY_WORKSPACE.exists():
        return _LEGACY_WORKSPACE
    return repo



def _workspace_from_argv():
    # §AGX/X49: optional `--workspace <path>` without disturbing the
    # script's existing argument handling.
    import sys
    argv = sys.argv[1:]
    for i, a in enumerate(argv):
        if a == "--workspace" and i + 1 < len(argv):
            return argv[i + 1]
        if a.startswith("--workspace="):
            return a.split("=", 1)[1]
    return None


WORKSPACE = resolve_workspace(_workspace_from_argv())
ASSET_MAP = WORKSPACE / "src" / "shared" / "ReplicatedStorage" / "AssetMap.lua"
IDS_FILE  = WORKSPACE / "tools" / "asset_ids.txt"
ENV_FILE  = WORKSPACE / ".env"

MARKETPLACE_API = "https://api.roblox.com/marketplace/productInfo?assetId={}"
DELAY           = 0.15   # seconds between API calls to avoid rate-limiting

TYPE_NAMES = {1: "Image", 13: "Decal", 17: "Mesh", 3: "Audio"}


def load_env():
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                os.environ.setdefault(k.strip(), v.strip())


def lua_match(stem: str, lua_text: str):
    """Find the entry for `stem` in the Lua text, handling both key styles:
       bare:    Xiao_Body_Diffuse = "..."
       quoted:  ["Hu Tao_Body_Diffuse"] = "..."
    Returns (match_obj, pattern) or (None, None).
    """
    esc = re.escape(stem)
    # Quoted bracket key: ["Hu Tao_Body_Diffuse"] = "..."
    p = rf'(\["{esc}"\]\s*=\s*)"[^"]*"'
    m = re.search(p, lua_text)
    if m:
        return m, p
    # Bare identifier key: Xiao_Body_Diffuse = "..."
    p = rf'(\b{esc}\s*=\s*)"[^"]*"'
    m = re.search(p, lua_text)
    if m:
        return m, p
    return None, None


def apply_fill(stem: str, asset_id: int, lua_text: str, only_if_empty: bool = False):
    """Fill the slot for `stem` in lua_text.  Returns (new_text, was_filled)."""
    m, pattern = lua_match(stem, lua_text)
    if not m:
        return lua_text, False
    if only_if_empty:
        current_val = m.group(0)[len(m.group(1)):]   # the "..." part
        if current_val != '""':
            return lua_text, False   # already has a value — skip
    rbx_id = f"rbxassetid://{asset_id}"
    new_text = lua_text[:m.start()] + m.group(1) + f'"{rbx_id}"' + lua_text[m.end():]
    return new_text, True


def parse_line(line: str):
    """Parse one tab-separated line from asset_ids.txt.
    Returns (label, asset_id) where label may be e.g. "Images/Xiao_Body_Diffuse"
    or "Image" or "Meshes/Xiao_Head", or (None, None) for blank/comment lines.
    """
    line = line.strip()
    if not line or line.startswith("#"):
        return None, None
    parts = line.split("\t")
    if len(parts) == 2:
        label  = parts[0].strip()
        raw_id = parts[1].strip()
    elif len(parts) == 1:
        # Legacy format: bare number or rbxassetid://
        label  = ""
        raw_id = parts[0].strip()
    else:
        return None, None
    raw_id = re.sub(r"(?i)^rbxassetid://", "", raw_id)
    try:
        return label, int(raw_id)
    except ValueError:
        return None, None


def extract_stem(label: str):
    """Return the AssetMap stem from a label like "Images/Xiao_Body_Diffuse",
    or None if the label doesn't encode a useful stem (mesh, texture, etc.).

    Handles the edge case where a texture file has ".png_" embedded in its name
    (e.g. "Images/Mavuika_Skillobj_mavuika_glass_diffuse.png_") — the Chrome
    plugin strips the trailing "_Diffuse" suffix when ".png_" precedes it.
    We restore the full key by appending "_Diffuse" in that case.
    """
    if not label.startswith("Images/"):
        return None
    stem = label[len("Images/"):]
    # Edge case: "Foo.png_" → file was actually named "Foo.png_Diffuse"
    if stem.endswith(".png_"):
        return stem + "Diffuse"
    # Normal case: strip trailing ".png" extension artifacts
    stem = re.sub(r"\.png_?$", "", stem, flags=re.IGNORECASE)
    return stem or None


def get_product_info(asset_id: int):
    """Returns (name, type_id) from the public marketplace API, or (None, None)."""
    url = MARKETPLACE_API.format(asset_id)
    try:
        req = Request(url, headers={"User-Agent": "RobloxDefense/AssetMapFiller"})
        with urlopen(req, timeout=10) as resp:
            info = json.loads(resp.read().decode("utf-8"))
        return info.get("Name", ""), info.get("AssetTypeId", 0)
    except Exception as e:
        return None, None


def main():
    load_env()

    if not IDS_FILE.exists():
        print(f"ERROR: {IDS_FILE} not found.")
        return
    if not ASSET_MAP.exists():
        print(f"ERROR: {ASSET_MAP} not found. Run gen_manifests_lua.py first.")
        return

    input_lines = IDS_FILE.read_text(encoding="utf-8").splitlines()
    lua_text    = ASSET_MAP.read_text(encoding="utf-8")

    # ── Pass 1: Named Images/* entries — zero API calls needed ────────────────
    print("Pass 1: Filling named Images/* entries...")
    named_filled    = 0
    named_unmatched = []
    seen_named_ids  = set()

    for line in input_lines:
        label, asset_id = parse_line(line)
        if asset_id is None:
            continue
        stem = extract_stem(label)
        if not stem:
            continue
        if asset_id in seen_named_ids:
            continue
        seen_named_ids.add(asset_id)

        lua_text, filled = apply_fill(stem, asset_id, lua_text, only_if_empty=False)
        if filled:
            named_filled += 1
        else:
            named_unmatched.append((asset_id, label, stem))

    ASSET_MAP.write_text(lua_text, encoding="utf-8")
    print(f"  ✅  {named_filled} entries filled directly from named labels.")

    if named_unmatched:
        print(f"  ⚠   {len(named_unmatched)} named entries had no matching key in AssetMap:")
        for uid, lbl, stem in named_unmatched:
            print(f"       {uid}  →  {lbl!r}  (stem tried: {stem!r})")

    # ── Pass 2: Unnamed "Image" entries — API lookup, only fill empty slots ───
    unnamed_ids = []
    seen_unnamed = set()
    for line in input_lines:
        label, asset_id = parse_line(line)
        if asset_id is None or label != "Image":
            continue
        if asset_id in seen_named_ids or asset_id in seen_unnamed:
            continue
        seen_unnamed.add(asset_id)
        unnamed_ids.append(asset_id)

    if not unnamed_ids:
        print("\nPass 2: No unnamed Image entries to look up.")
    else:
        print(f"\nPass 2: Looking up {len(unnamed_ids)} unnamed Image IDs via Roblox API...")
        api_filled    = 0
        api_unmatched = []

        # Collect all API results first, then do one write
        api_results = {}
        for i, asset_id in enumerate(unnamed_ids, start=1):
            print(f"  [{i:>3}/{len(unnamed_ids)}] {asset_id} ... ", end="", flush=True)
            name, type_id = get_product_info(asset_id)
            if name is None:
                print("FAILED — skipping")
            else:
                type_name = TYPE_NAMES.get(type_id, f"Unknown({type_id})")
                print(f"{name!r:<45} ({type_name})")
                if type_id in (1, 13):   # Image or Decal only
                    api_results[asset_id] = name
            if i < len(unnamed_ids):
                time.sleep(DELAY)

        lua_text = ASSET_MAP.read_text(encoding="utf-8")
        for asset_id, name in api_results.items():
            lua_text, filled = apply_fill(name, asset_id, lua_text, only_if_empty=True)
            if filled:
                api_filled += 1
            else:
                m, _ = lua_match(name, lua_text)
                if not m:
                    api_unmatched.append((asset_id, name))
                # else: slot already had a value from Pass 1 — silently skip

        ASSET_MAP.write_text(lua_text, encoding="utf-8")
        print(f"\n  ✅  {api_filled} additional entries filled from API lookup.")

        if api_unmatched:
            print(f"  ⚠   {len(api_unmatched)} unnamed IDs had no matching key (probably old duplicates):")
            for uid, uname in api_unmatched:
                print(f"       {uid}  →  {uname!r}")

    # ── Final summary ──────────────────────────────────────────────────────────
    lua_text    = ASSET_MAP.read_text(encoding="utf-8")
    still_empty = lua_text.count('= "",')
    filled_count = lua_text.count('"rbxassetid://')

    print(f"\n{'─'*55}")
    print(f"AssetMap.lua:  {filled_count} filled  |  {still_empty} still empty")
    if still_empty == 0:
        print("               All entries filled! ✅")
    else:
        print("               Paste more IDs into asset_ids.txt and re-run.")
    print(f"{'─'*55}")


if __name__ == "__main__":
    main()
