#!/usr/bin/env python3
"""
mesh_to_obj.py — Convert a Roblox v1.01 text mesh (.mesh) to Wavefront OBJ.

Usage:
    python tools/mesh_to_obj.py Leg.mesh Leg.obj
    python tools/mesh_to_obj.py Leg.mesh          # writes Leg.obj next to input

Roblox v1.01 text mesh format:
    Line 1: "version 1.01"
    Line 2: <numFaces>  (integer)
    Line 3: numFaces * 3 vertex blocks, each: [x,y,z][nx,ny,nz][u,v,0]
    Faces are implicit: triangle i uses vertices i*3, i*3+1, i*3+2

Output OBJ includes positions (v), normals (vn), and UV coordinates (vt).
UV V-axis is flipped: Roblox uses top-left origin, OBJ uses bottom-left.
"""

import re
import sys
from pathlib import Path

# Matches three [a,b,c] groups back-to-back for one vertex
_VERTEX_RE = re.compile(r'\[([^\]]+)\]\[([^\]]+)\]\[([^\]]+)\]')


def parse_mesh_v101(text: str):
    lines = text.splitlines()
    if not lines[0].strip().startswith("version 1.01"):
        raise ValueError(f"Unsupported mesh version: {lines[0]!r}")

    num_faces = int(lines[1].strip())
    data_line = lines[2]

    matches = _VERTEX_RE.findall(data_line)
    expected = num_faces * 3
    if len(matches) != expected:
        raise ValueError(
            f"Expected {expected} vertex blocks ({num_faces} faces × 3), "
            f"got {len(matches)}"
        )

    positions, normals, uvs = [], [], []
    for pos_str, nrm_str, uv_str in matches:
        px, py, pz = [float(v) for v in pos_str.split(",")]
        nx, ny, nz = [float(v) for v in nrm_str.split(",")]
        u, v, _w   = [float(v) for v in uv_str.split(",")]
        positions.append((px, py, pz))
        normals.append((nx, ny, nz))
        uvs.append((u, v))

    return positions, normals, uvs, num_faces


def write_obj(path: Path, positions, normals, uvs, num_faces):
    with open(path, "w") as f:
        f.write(f"# Converted from Roblox v1.01 mesh — {num_faces} faces, {len(positions)} vertices\n\n")

        for px, py, pz in positions:
            f.write(f"v  {px:.6f}  {py:.6f}  {pz:.6f}\n")
        f.write("\n")

        # OBJ bottom-left UV origin vs Roblox top-left → flip V
        for u, v in uvs:
            f.write(f"vt {u:.6f}  {1.0 - v:.6f}\n")
        f.write("\n")

        for nx, ny, nz in normals:
            f.write(f"vn {nx:.6f}  {ny:.6f}  {nz:.6f}\n")
        f.write("\n")

        f.write("g mesh\n")
        for i in range(num_faces):
            a = i * 3 + 1  # OBJ is 1-based
            b = a + 1
            c = a + 2
            f.write(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}\n")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    in_path  = Path(sys.argv[1])
    out_path = Path(sys.argv[2]) if len(sys.argv) >= 3 else in_path.with_suffix(".obj")

    text = in_path.read_text(encoding="utf-8", errors="replace")
    positions, normals, uvs, num_faces = parse_mesh_v101(text)

    print(f"Parsed : {num_faces} faces, {len(positions)} unique-split vertices")
    write_obj(out_path, positions, normals, uvs, num_faces)
    print(f"Written: {out_path}")


if __name__ == "__main__":
    main()
