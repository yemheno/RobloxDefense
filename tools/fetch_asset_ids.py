#!/usr/bin/env python3
"""
fetch_asset_ids.py
Queries the Roblox Open Cloud API for each ID in asset_ids.txt, gets the
official displayName (e.g. "Images/Xiao_Body_Diffuse"), then fills the
matching entry in AssetMap.lua.

This replaces the old marketplace/productInfo approach, which couldn't access
private assets.  The v1 GET endpoint works for any asset you own.

Requirements:
    .env at project root:
        ROBLOX_OPEN_CLOUD_KEY=<your key>   (needs Asset: Read scope)
        ROBLOX_CREATOR_ID=<your user ID>

Usage:
    python tools/fetch_asset_ids.py            # fill AssetMap.lua
    python tools/fetch_asset_ids.py --dry-run  # preview without writing

Workflow for future uploads:
    1. Bulk import new PNGs in Studio
    2. Chrome plugin (or any method) → paste asset IDs into asset_ids.txt
    3. python tools/fetch_asset_ids.py
    4. Rojo re-sync → AssetMap is live in Studio
    5. Plugin → Load Textures from AssetMap → Setup
"""

import argparse
import os
import re
import time
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

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


def get_api_key():
    """§AGX/X49: ROBLOX_OPEN_CLOUD_KEY preferred, ROBLOX_API_KEY accepted.
    Never print the returned value."""
    return os.environ.get("ROBLOX_OPEN_CLOUD_KEY") or os.environ.get("ROBLOX_API_KEY", "")


WORKSPACE = resolve_workspace()
ASSET_MAP = WORKSPACE / "src/shared/ReplicatedStorage/AssetMap.lua"
IDS_FILE  = WORKSPACE / "tools/asset_ids.txt"
ENV_FILE  = WORKSPACE / ".env"

ASSET_GET_URL = "https://apis.roblox.com/assets/v1/assets/{}"
DELAY         = 0.1   # seconds between requests


def load_env():
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                os.environ.setdefault(k.strip(), v.strip())


def parse_id(line: str):
    """Extract asset ID from a tab-separated Chrome plugin line or bare number."""
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    # Tab-separated: "Images/Xiao_Body_Diffuse\t118584819881440"
    if "\t" in line:
        line = line.split("\t")[-1].strip()
    line = re.sub(r"(?i)^rbxassetid://", "", line)
    try:
        return int(line)
    except ValueError:
        return None


def get_display_name(asset_id: int, api_key: str):
    """Fetch displayName from the Open Cloud v1 assets endpoint."""
    url = ASSET_GET_URL.format(asset_id)
    req = Request(url, headers={
        "x-api-key": api_key,
        "User-Agent": "RobloxDefense/AssetMapFiller",
    })
    with urlopen(req, timeout=10) as resp:
        import json
        data = json.loads(resp.read().decode("utf-8"))
    return data.get("displayName", ""), data.get("assetType", "")


def extract_stem(display_name: str):
    """'Images/Xiao_Body_Diffuse' → 'Xiao_Body_Diffuse', others → None."""
    if not display_name.startswith("Images/"):
        return None
    stem = display_name[len("Images/"):]
    # Handle edge: "Foo.png_Diffuse" style names
    if ".png_" in stem:
        stem = re.sub(r"\.png_", "_", stem)
    stem = re.sub(r"\.png$", "", stem, flags=re.IGNORECASE)
    return stem or None


def lua_fill(stem: str, asset_id: int, lua_text: str, only_empty: bool):
    """Fill the slot for stem in lua_text. Returns (new_text, was_filled)."""
    esc = re.escape(stem)
    # Quoted bracket key first: ["Hu Tao_Body_Diffuse"] = "..."
    p = rf'(\["{esc}"\]\s*=\s*)"[^"]*"'
    m = re.search(p, lua_text)
    if not m:
        p = rf'(\b{esc}\s*=\s*)"[^"]*"'
        m = re.search(p, lua_text)
    if not m:
        return lua_text, False
    if only_empty and m.group(0)[len(m.group(1)):] != '""':
        return lua_text, False
    rbx = f'"rbxassetid://{asset_id}"'
    return lua_text[:m.start()] + m.group(1) + rbx + lua_text[m.end():], True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--overwrite", action="store_true",
                        help="Overwrite already-filled entries (default: skip)")
    args = parser.parse_args()

    load_env()
    api_key = get_api_key()  # §AGX/X49
    if not api_key:
        print("ERROR: ROBLOX_OPEN_CLOUD_KEY (or ROBLOX_API_KEY) not set"); return
    if not ASSET_MAP.exists():
        print("ERROR: AssetMap.lua not found — run gen_manifests_lua.py"); return
    if not IDS_FILE.exists():
        print("ERROR: asset_ids.txt not found"); return

    # Parse unique IDs from the file
    raw_ids = []
    seen = set()
    for line in IDS_FILE.read_text(encoding="utf-8").splitlines():
        aid = parse_id(line)
        if aid and aid not in seen:
            seen.add(aid)
            raw_ids.append(aid)
    print(f"{len(raw_ids)} unique IDs in asset_ids.txt\n")

    lua_text = ASSET_MAP.read_text(encoding="utf-8")
    matched, skipped, failed, not_image = 0, 0, 0, 0

    for i, aid in enumerate(raw_ids, 1):
        print(f"[{i:>3}/{len(raw_ids)}] {aid} ... ", end="", flush=True)
        try:
            name, atype = get_display_name(aid, api_key)
        except HTTPError as e:
            print(f"HTTP {e.code} — skipping")
            failed += 1
            if i < len(raw_ids): time.sleep(DELAY)
            continue
        except Exception as e:
            print(f"ERROR {e} — skipping")
            failed += 1
            if i < len(raw_ids): time.sleep(DELAY)
            continue

        stem = extract_stem(name)
        if not stem:
            print(f"{name!r:<50} [{atype}] — not an Images/* asset, skip")
            not_image += 1
            if i < len(raw_ids): time.sleep(DELAY)
            continue

        new_text, filled = lua_fill(stem, aid, lua_text, only_empty=not args.overwrite)
        if filled:
            lua_text = new_text
            matched += 1
            print(f"✔  {stem}")
        else:
            skipped += 1
            print(f"–  {stem}  (already filled)")

        if i < len(raw_ids): time.sleep(DELAY)

    if not args.dry_run:
        ASSET_MAP.write_text(lua_text, encoding="utf-8")

    still_empty = lua_text.count('= "",')
    filled_total = lua_text.count('"rbxassetid://')
    print(f"\n{'─'*55}")
    print(f"{'[DRY RUN] ' if args.dry_run else ''}Filled: {matched}  Skipped (already set): {skipped}  Failed: {failed}  Non-image: {not_image}")
    print(f"AssetMap.lua:  {filled_total} filled  |  {still_empty} still empty")
    if still_empty == 0:
        print("All entries filled! ✅")
    print(f"{'─'*55}")


if __name__ == "__main__":
    main()


import argparse
import json
import os
import re
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError

# ── Config ────────────────────────────────────────────────────────────────────
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


def get_api_key():
    """§AGX/X49: ROBLOX_OPEN_CLOUD_KEY preferred, ROBLOX_API_KEY accepted.
    Never print the returned value."""
    return os.environ.get("ROBLOX_OPEN_CLOUD_KEY") or os.environ.get("ROBLOX_API_KEY", "")


WORKSPACE = resolve_workspace()
ASSET_MAP = WORKSPACE / "src/shared/ReplicatedStorage/AssetMap.lua"
ENV_FILE  = WORKSPACE / ".env"

# Open Cloud v2 — list creator assets
# Docs: https://create.roblox.com/docs/cloud/reference/Assets
BASE_URL = "https://apis.roblox.com/cloud/v2/users/{uid}/assets"

PAGE_SIZE = 100   # max per page


def load_env():
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                os.environ.setdefault(k.strip(), v.strip())


def lua_fill(stem: str, asset_id: int, lua_text: str, only_empty: bool = True):
    """Find the slot for `stem` in lua_text and fill it.  Returns (new_text, filled: bool)."""
    esc = re.escape(stem)
    # Quoted bracket key: ["Hu Tao_Body_Diffuse"] = "..."
    p = rf'(\["{esc}"\]\s*=\s*)"[^"]*"'
    m = re.search(p, lua_text)
    if not m:
        # Bare identifier key: Xiao_Body_Diffuse = "..."
        p = rf'(\b{esc}\s*=\s*)"[^"]*"'
        m = re.search(p, lua_text)
    if not m:
        return lua_text, False
    current = m.group(0)[len(m.group(1)):]
    if only_empty and current != '""':
        return lua_text, False  # already filled — skip
    rbx_id = f'"rbxassetid://{asset_id}"'
    return lua_text[:m.start()] + m.group(1) + rbx_id + lua_text[m.end():], True


def fetch_all_images(api_key: str, creator_id: str):
    """Yield (displayName, assetId) for every Image asset owned by this user."""
    url_base = BASE_URL.format(uid=creator_id)
    params = {
        "assetType": "Image",
        "pageSize": PAGE_SIZE,
    }
    page_token = None
    page = 0

    while True:
        if page_token:
            params["pageToken"] = page_token
        elif "pageToken" in params:
            del params["pageToken"]

        url = url_base + "?" + urlencode(params)
        req = Request(url, headers={"x-api-key": api_key})
        try:
            with urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"HTTP {e.code}: {body}") from e

        assets = data.get("assets", [])
        page += 1
        print(f"  Page {page}: {len(assets)} assets", flush=True)

        for asset in assets:
            name = asset.get("displayName", "")
            # assetId is in the "path" field: "users/NNN/assets/MMMMM"
            path = asset.get("path", "")
            raw_id = path.split("/")[-1] if "/" in path else ""
            if raw_id.isdigit():
                yield name, int(raw_id)

        page_token = data.get("nextPageToken")
        if not page_token:
            break


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="Print matches without writing AssetMap.lua")
    args = parser.parse_args()

    load_env()

    api_key    = get_api_key()  # §AGX/X49
    creator_id = os.environ.get("ROBLOX_CREATOR_ID", "")

    if not api_key:
        print("ERROR: ROBLOX_OPEN_CLOUD_KEY (or ROBLOX_API_KEY) not set")
        return
    if not creator_id:
        print("ERROR: ROBLOX_CREATOR_ID not set in .env")
        return
    if not ASSET_MAP.exists():
        print(f"ERROR: {ASSET_MAP} not found. Run gen_manifests_lua.py first.")
        return

    print(f"Fetching all Image assets for user {creator_id}...")
    try:
        all_images = list(fetch_all_images(api_key, creator_id))
    except RuntimeError as e:
        print(f"API error: {e}")
        print("\nIf you see 403, make sure the API key has 'Assets: Read' scope enabled at:")
        print("  create.roblox.com/dashboard/credentials → your key → Edit → Permissions")
        return

    print(f"  Total images fetched: {len(all_images)}\n")

    lua_text  = ASSET_MAP.read_text(encoding="utf-8")
    matched   = 0
    unmatched = []

    for name, asset_id in all_images:
        new_text, filled = lua_fill(name, asset_id, lua_text, only_empty=True)
        if filled:
            lua_text = new_text
            matched += 1
            print(f"  ✔  {name:<50} → {asset_id}")
        else:
            # Check if it has a slot at all
            esc = re.escape(name)
            has_slot = bool(re.search(rf'\["{esc}"\]|(\b{esc}\s*=)', lua_text))
            if not has_slot:
                unmatched.append((asset_id, name))

    still_empty = lua_text.count('= "",')

    if not args.dry_run:
        ASSET_MAP.write_text(lua_text, encoding="utf-8")
        print(f"\n✅  {matched} entries filled in AssetMap.lua.")
    else:
        print(f"\n[DRY RUN] Would fill {matched} entries.")

    if unmatched:
        print(f"\n⚠   {len(unmatched)} image(s) not in AssetMap (old/unrelated uploads — expected):")
        for uid, uname in unmatched[:20]:
            print(f"     {uid}  {uname!r}")
        if len(unmatched) > 20:
            print(f"     ... and {len(unmatched)-20} more")

    filled_total = lua_text.count('"rbxassetid://')
    print(f"\n{'─'*55}")
    print(f"AssetMap.lua:  {filled_total} filled  |  {still_empty} still empty")
    if still_empty == 0:
        print("               All entries filled! ✅")
    print(f"{'─'*55}")


if __name__ == "__main__":
    main()
