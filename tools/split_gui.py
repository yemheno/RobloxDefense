#!/usr/bin/env python3
"""
tools/split_gui.py
------------------
Splits GUI.rbxmx into one .rbxmx file per top-level AppRoot child so each
panel lives in its own clean, maintainable file.

Output layout (relative to workspace root):
  src/shared/StarterGui/AppGui/
    init.meta.json                  ← ScreenGui class declaration
    AppGuiWiring.rbxmx              ← LocalScript (Disabled=true, kept for reference)
    AppRoot/
      init.meta.json                ← Frame class declaration
      HUD.rbxmx
      ClassMenuBackdrop.rbxmx
      StatsMenuBackdrop.rbxmx
      … (one file per AppRoot child)

Usage:
  python tools/split_gui.py
  # or supply a different source:
  python tools/split_gui.py path/to/Other.rbxmx
"""

import os
import sys
import xml.etree.ElementTree as ET

# ── Paths ─────────────────────────────────────────────────────────────────────
WORKSPACE  = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE     = sys.argv[1] if len(sys.argv) > 1 else os.path.join(WORKSPACE, "GUI.rbxmx")
OUT_ROOT   = os.path.join(WORKSPACE, "src", "shared", "StarterGui", "AppGui")
OUT_APPROOT = os.path.join(OUT_ROOT, "AppRoot")

# ── XML envelope ─────────────────────────────────────────────────────────────
ROBLOX_HEADER = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
    '\t<External>null</External>\n'
    '\t<External>nil</External>\n'
)
ROBLOX_FOOTER = "</roblox>\n"

def item_name(elem):
    """Return the Roblox Name property of an <Item> element."""
    for s in elem.findall("Properties/string"):
        if s.attrib.get("name") == "Name":
            return s.text or "Unknown"
    return "Unknown"

def to_string(elem, indent="\t"):
    """Serialize an ET Element back to an indented XML string."""
    ET.indent(elem, space="\t")
    return ET.tostring(elem, encoding="unicode", xml_declaration=False)

def write_rbxmx(path, item_elem):
    """Wrap a single <Item> element in a valid roblox envelope and write it."""
    body = to_string(item_elem)
    with open(path, "w", encoding="utf-8") as f:
        f.write(ROBLOX_HEADER)
        # ET.indent adds a leading newline; make sure tab indentation stays consistent
        f.write(body)
        f.write("\n")
        f.write(ROBLOX_FOOTER)
    print(f"  wrote  {os.path.relpath(path, WORKSPACE)}")

def write_meta(path, class_name):
    """Write a Rojo init.meta.json that declares an instance's className."""
    with open(path, "w", encoding="utf-8") as f:
        f.write(f'{{\n  "className": "{class_name}"\n}}\n')
    print(f"  wrote  {os.path.relpath(path, WORKSPACE)}")

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print(f"[split_gui] Parsing {os.path.relpath(SOURCE, WORKSPACE)} …")
    tree = ET.parse(SOURCE)
    xml_root = tree.getroot()

    # ScreenGui is the first <Item> in the file
    screen_gui = xml_root.find("Item")
    if screen_gui is None or screen_gui.attrib.get("class") != "ScreenGui":
        sys.exit("[split_gui] ERROR: Expected a ScreenGui as the first Item. Aborting.")

    # Separate AppRoot (Frame) from AppGuiWiring (LocalScript)
    approot_elem = None
    wiring_elem  = None
    for child in screen_gui.findall("Item"):
        name = item_name(child)
        cls  = child.attrib.get("class", "")
        if cls == "Frame" and name == "AppRoot":
            approot_elem = child
        elif cls == "LocalScript" and name == "AppGuiWiring":
            wiring_elem = child

    if approot_elem is None:
        sys.exit("[split_gui] ERROR: AppRoot Frame not found. Aborting.")

    # ── Ensure output directories exist ──────────────────────────────────────
    os.makedirs(OUT_ROOT,    exist_ok=True)
    os.makedirs(OUT_APPROOT, exist_ok=True)

    # ── 1. AppGui/init.meta.json  (ScreenGui) ────────────────────────────────
    write_meta(os.path.join(OUT_ROOT, "init.meta.json"), "ScreenGui")

    # ── 2. AppGui/AppRoot/init.meta.json  (Frame) ────────────────────────────
    write_meta(os.path.join(OUT_APPROOT, "init.meta.json"), "Frame")

    # ── 3. AppGui/AppGuiWiring.rbxmx  (LocalScript, kept Disabled=true) ─────
    if wiring_elem is not None:
        # Ensure Disabled=true is present
        for b in wiring_elem.findall("Properties/bool"):
            if b.attrib.get("name") == "Disabled":
                b.text = "true"
                break
        write_rbxmx(os.path.join(OUT_ROOT, "AppGuiWiring.rbxmx"), wiring_elem)
    else:
        print("  [skip] AppGuiWiring not found in source")

    # ── 4. One .rbxmx per AppRoot child ──────────────────────────────────────
    children = approot_elem.findall("Item")
    print(f"[split_gui] Writing {len(children)} panel files …")
    for child in children:
        name = item_name(child)
        filename = name + ".rbxmx"
        write_rbxmx(os.path.join(OUT_APPROOT, filename), child)

    # ── 5. Remove monolithic init.rbxmx if it exists ─────────────────────────
    old_init = os.path.join(OUT_ROOT, "init.rbxmx")
    if os.path.exists(old_init):
        os.remove(old_init)
        print(f"  removed {os.path.relpath(old_init, WORKSPACE)}")

    print(f"\n[split_gui] Done — {len(children) + (1 if wiring_elem else 0)} files written.")
    print( "[split_gui] Rojo will now serve each panel as an independent instance.")

if __name__ == "__main__":
    main()
