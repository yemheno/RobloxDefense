"""Talent tree v3 prototype — PoE-style orbit groups on a galaxy layout.

Groups = (branch, config row). Group centers seeded on the authored compass
direction per branch, radius by tier*row, golden-ratio angular stagger per
row, slight spiral twist, then force relaxation. Members sit on fixed orbit
slots (PoE model). Visual edges are PRUNED: orbit arcs inside a group, one
connector per group pair (real gameplay Edges are untouched by this viz).
"""
import json, math, colorsys, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

SCRATCH = os.path.dirname(os.path.abspath(__file__))
REPO = r"c:\Users\P_Guilleminot\Desktop\Developer\RobloxDefense"
d = json.load(open(os.path.join(SCRATCH, "tree_layout.json")))

BG, INK, INK_DIM = "#0C0C12", "#DCDCE6", "#8C8CA0"
EDGE, GOLD, ORIGIN_C = "#3A3A54", "#C8AA32", "#FFDC64"
PHI = 0.6180339887

TIER = {}
for b in ["warpath", "lifeblood", "precision", "attunement", "resolve"]: TIER[b] = 0
for b in ["juggernaut", "predator", "oracle", "spellblade", "sanctuary"]: TIER[b] = 1
for b in ["bulwark", "huntmaster", "grace", "stormweave", "fortune"]: TIER[b] = 2

def branch_rgb(hue): return colorsys.hsv_to_rgb(hue, 0.55, 0.85)

nodes = {n["id"]: n for n in d["nodes"]}

# ── Build groups: (branch,row) with members ordered by col ─────────────────
groups = {}          # key -> dict
node_group = {}      # node id -> group key
for n in d["nodes"]:
    if n["id"] == "start":
        node_group["start"] = "origin"
        continue
    pre, row, col = n["id"].split("_")
    key = (n["branch"], int(row))
    g = groups.setdefault(key, {"branch": n["branch"], "row": int(row),
                                "hue": n["hue"], "members": []})
    g["members"].append((int(col), n["id"]))
    node_group[n["id"]] = key
for g in groups.values():
    g["members"].sort()
    g["members"] = [mid for _, mid in g["members"]]

# Branch compass angle from AUTHORED config centroid (cx, cy; y is screen-down)
bstat = {}
for n in d["nodes"]:
    if n["id"] == "start": continue
    s = bstat.setdefault(n["branch"], [0.0, 0.0, 0])
    s[0] += n["cx"]; s[1] += n["cy"]; s[2] += 1
bangle = {b: math.atan2(s[1] / s[2], s[0] / s[2]) for b, s in bstat.items()}

# ── Arm angles: idealized pentagon (config's 5/5/5 intent) ─────────────────
# Primaries at exact 72° spacing (phase-anchored to authored Warpath angle);
# hybrids at the midpoint of their two parent primaries (parents = the two
# primary branches with the most real bridge edges into the hybrid);
# masteries inherit their hybrid's angle.
primaries = sorted((b for b, t in TIER.items() if t == 0), key=lambda b: bangle[b])
arm = {}
base = bangle[primaries[0]]
for i, b in enumerate(primaries):
    arm[b] = base + i * 2 * math.pi / 5

cross = {}   # hybrid -> {primary: edge count}
for a, b in d["edges"]:
    na, nb = nodes[a], nodes[b]
    if na["id"] == "start" or nb["id"] == "start": continue
    ba, bb = na["branch"], nb["branch"]
    if ba == bb: continue
    for h, p in ((ba, bb), (bb, ba)):
        if TIER.get(h) == 1 and TIER.get(p) == 0:
            cross.setdefault(h, {}).setdefault(p, 0)
            cross[h][p] += 1
for h, counts in cross.items():
    p1, p2 = sorted(counts, key=counts.get, reverse=True)[:2]
    a1, a2 = arm[p1], arm[p2]
    arm[h] = math.atan2((math.sin(a1) + math.sin(a2)) / 2,
                        (math.cos(a1) + math.cos(a2)) / 2)
for a, b in d["edges"]:
    if a in nodes and b in nodes and a != "start" and b != "start":
        ba, bb = nodes[a]["branch"], nodes[b]["branch"]
        for m, h in ((ba, bb), (bb, ba)):
            if TIER.get(m) == 2 and TIER.get(h) == 1:
                arm.setdefault(m, arm[h])

# ── Seed group centers ─────────────────────────────────────────────────────
R0, STEP, TIER_GAP = 5.0, 3.55, 2.4     # ring geometry (grid units)
ARM_W = math.radians(30)                # angular room an arm may use
TWIST = 0.011                           # spiral twist (rad per grid unit of r)

def orbit_r(g):
    n = len(g["members"])
    if g["row"] == 5: return 1.75       # 3 notables around keystone
    return 1.30 if n <= 4 and g["row"] <= 3 else 1.55

for key, g in groups.items():
    k = TIER[g["branch"]] * 5 + g["row"]              # 1..15 outward index
    r = R0 + k * STEP + TIER[g["branch"]] * TIER_GAP
    stagger = ((g["row"] * PHI) % 1.0 - 0.5) * ARM_W  # golden-ratio stagger
    a = bangle[g["branch"]] + stagger + TWIST * r     # + spiral twist
    g["r_seed"], g["x"], g["y"] = r, math.cos(a) * r, math.sin(a) * r
    g["orad"] = orbit_r(g)
groups["origin"] = {"branch": "origin", "row": 0, "hue": 0, "members": ["start"],
                    "x": 0.0, "y": 0.0, "r_seed": 0.0, "orad": 0.0}

# ── Collapse real edges to group-pair links ────────────────────────────────
pair_links = set()
for a, b in d["edges"]:
    ga, gb = node_group[a], node_group[b]
    if ga != gb:
        pair_links.add(tuple(sorted((str(ga), str(gb)))))
gkey = {str(k): k for k in groups}
pair_links = [(gkey[a], gkey[b]) for a, b in pair_links]

def is_chain(a, b):   # same branch, consecutive rows
    return (a != "origin" and b != "origin" and a[0] == b[0]
            and abs(a[1] - b[1]) == 1)

# ── Force relaxation on group centers ──────────────────────────────────────
keys = [k for k in groups if k != "origin"]
for it in range(500):
    # pairwise overlap repulsion
    for i in range(len(keys)):
        gi = groups[keys[i]]
        for j in range(i + 1, len(keys)):
            gj = groups[keys[j]]
            dx, dy = gj["x"] - gi["x"], gj["y"] - gi["y"]
            dist = math.hypot(dx, dy) or 0.001
            need = gi["orad"] + gj["orad"] + 1.7
            if dist < need:
                push = 0.5 * (need - dist) / dist
                gi["x"] -= dx * push; gi["y"] -= dy * push
                gj["x"] += dx * push; gj["y"] += dy * push
    # springs along links
    for a, b in pair_links:
        ga, gb = groups[a], groups[b]
        if a == "origin" or b == "origin": continue
        dx, dy = gb["x"] - ga["x"], gb["y"] - ga["y"]
        dist = math.hypot(dx, dy) or 0.001
        rest = ga["orad"] + gb["orad"] + (1.9 if is_chain(a, b) else 3.0)
        k = 0.10 if is_chain(a, b) else 0.02
        pull = k * (dist - rest) / dist
        ga["x"] += dx * pull; ga["y"] += dy * pull
        gb["x"] -= dx * pull; gb["y"] -= dy * pull
    # soft radial constraint (keeps tier ordering)
    for kk in keys:
        g = groups[kk]
        r = math.hypot(g["x"], g["y"]) or 0.001
        adj = 0.05 * (g["r_seed"] - r) / r
        g["x"] += g["x"] * adj; g["y"] += g["y"] * adj

# ── Place members on orbit slots (PoE: fixed slots, phase faces prev group)─
pos = {"start": (0.0, 0.0)}
for key in keys:
    g = groups[key]
    prev = (g["branch"], g["row"] - 1) if g["row"] > 1 else "origin"
    if prev not in groups: prev = "origin"
    pg = groups[prev]
    phase = math.atan2(pg["y"] - g["y"], pg["x"] - g["x"])
    if g["row"] == 5:  # keystone at center, notables on orbit
        ring = [m for m in g["members"] if nodes[m]["type"] != "keystone"]
        ks = [m for m in g["members"] if nodes[m]["type"] == "keystone"]
        for m in ks: pos[m] = (g["x"], g["y"])
    else:
        ring, ks = g["members"], []
    n = len(ring)
    for i, m in enumerate(ring):
        a = phase + (i + 0.5) * 2 * math.pi / max(n, 1)
        pos[m] = (g["x"] + math.cos(a) * g["orad"],
                  g["y"] + math.sin(a) * g["orad"])
    g["_ring"] = ring

# ── Draw ───────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(15, 15.8), dpi=150)
fig.patch.set_facecolor(BG); ax.set_facecolor(BG)
drawn = 0

# orbit circles + intra-group arcs
th = [i * 2 * math.pi / 90 for i in range(91)]
for key in keys:
    g = groups[key]
    col = branch_rgb(g["hue"])
    ax.plot([g["x"] + math.cos(t) * g["orad"] for t in th],
            [g["y"] + math.sin(t) * g["orad"] for t in th],
            color=col, lw=0.6, alpha=0.20, zorder=2)
    ring = g["_ring"]
    for i in range(len(ring) - 1):   # arc between consecutive cols
        a0 = math.atan2(pos[ring[i]][1] - g["y"], pos[ring[i]][0] - g["x"])
        a1 = math.atan2(pos[ring[i + 1]][1] - g["y"], pos[ring[i + 1]][0] - g["x"])
        da = (a1 - a0) % (2 * math.pi)
        if da > math.pi: a0, da = a1, 2 * math.pi - da
        arc = [a0 + da * t / 24 for t in range(25)]
        ax.plot([g["x"] + math.cos(a) * g["orad"] for a in arc],
                [g["y"] + math.sin(a) * g["orad"] for a in arc],
                color=EDGE, lw=1.5, alpha=0.95, zorder=3)
        drawn += 1
    if g["row"] == 5:                # keystone spoke
        m = ring[-1]
        ax.plot([pos[m][0], g["x"]], [pos[m][1], g["y"]],
                color=EDGE, lw=1.5, alpha=0.95, zorder=3)
        drawn += 1

# one connector per linked group pair (closest member pair)
for a, b in pair_links:
    ga, gb = groups[a], groups[b]
    best = min(((ma, mb) for ma in ga["members"] for mb in gb["members"]),
               key=lambda p: math.dist(pos[p[0]], pos[p[1]]))
    (x0, y0), (x1, y1) = pos[best[0]], pos[best[1]]
    chain = is_chain(a, b) or "origin" in (a, b)
    ax.plot([x0, x1], [y0, y1], color=EDGE, lw=1.5 if chain else 0.9,
            alpha=0.95 if chain else 0.55, zorder=3)
    drawn += 1

# nodes
for n in d["nodes"]:
    x, y = pos[n["id"]]
    if n["id"] == "start":
        ax.scatter(x, y, s=380, marker="*", color=ORIGIN_C,
                   edgecolors="#12121C", linewidths=1.2, zorder=7)
        continue
    col = branch_rgb(n["hue"])
    if n["type"] == "keystone":
        ax.scatter(x, y, s=165, marker="D", color=col, edgecolors=GOLD,
                   linewidths=1.7, zorder=6)
    elif n["type"] == "notable":
        ax.scatter(x, y, s=80, marker="o", color=col, edgecolors="#12121C",
                   linewidths=0.8, zorder=5)
    else:
        ax.scatter(x, y, s=28, marker="o", color=col, zorder=4)

# branch labels at outermost group, offset outward
for b in bstat:
    outer = max((g for g in groups.values() if g["branch"] == b),
                key=lambda g: g["row"])
    r = math.hypot(outer["x"], outer["y"]) or 1
    f = (r + outer["orad"] + 2.6) / r
    ax.text(outer["x"] * f, outer["y"] * f, b.upper(),
            color=branch_rgb(outer["hue"]), fontsize=10.5, fontweight="bold",
            ha="center", va="center", zorder=8,
            bbox=dict(boxstyle="round,pad=0.28", facecolor=BG,
                      edgecolor="none", alpha=0.75))

handles = [
    Line2D([], [], marker="*", ls="none", ms=15, color=ORIGIN_C, label="Origin (free)"),
    Line2D([], [], marker="o", ls="none", ms=5,  color=INK_DIM, label="Small"),
    Line2D([], [], marker="o", ls="none", ms=8,  color=INK_DIM, mec="#12121C", label="Notable"),
    Line2D([], [], marker="D", ls="none", ms=9,  color=INK_DIM, mec=GOLD, label="Keystone (cluster core)"),
]
leg = ax.legend(handles=handles, loc="lower right", frameon=True, fontsize=10,
                labelcolor=INK, borderpad=0.9)
leg.get_frame().set_facecolor("#16161F"); leg.get_frame().set_edgecolor("#2D2D41")

ax.set_title("Talent tree v3 — candidate A: PoE orbit groups (golden-angle stagger + spiral twist)",
             color=INK, fontsize=16, fontweight="bold", pad=20)
ax.text(0.5, 1.007,
        f"76 clusters · orbit slots per PoE model · visual links pruned "
        f"{len(d['edges'])} → {drawn} · gameplay topology unchanged",
        transform=ax.transAxes, ha="center", va="bottom", color=INK_DIM, fontsize=11)

ax.set_aspect("equal")
lim = max(max(abs(p[0]), abs(p[1])) for p in pos.values()) + 6
ax.set_xlim(-lim, lim); ax.set_ylim(lim, -lim)   # y-down, like the game
ax.axis("off")
fig.savefig(os.path.join(REPO, "docs", "talent_tree_v3_A.png"),
            facecolor=BG, bbox_inches="tight")
print("saved A")

# ═══ Candidate B — golden-angle sunflower with SECTOR-COHERENT assignment ═══
# Keep the exact Vogel-spiral point field (the even "galaxy dust" density),
# but assign nodes to points via Hungarian matching against per-node targets:
#   radius  ← global ring index (tier*5 + row)  → depth grows outward
#   angle   ← branch pentagon arm + column offset within the branch wedge
# Grid neighbors get adjacent targets, so the REAL gameplay edges stay short.
from scipy.optimize import linear_sum_assignment
import numpy as np

GA = math.pi * (3 - math.sqrt(5))    # 137.5077°
SCALE = 2.55
others = [n for n in d["nodes"] if n["id"] != "start"]
K = len(others)                       # 300
pts = np.array([[SCALE * math.sqrt(k) * math.cos(k * GA),
                 SCALE * math.sqrt(k) * math.sin(k * GA)] for k in range(1, K + 1)])

def angdiff(a, b):
    return (a - b + math.pi) % (2 * math.pi) - math.pi

# Orient each wedge's column direction toward its bridge partners so the
# cross-branch connections come out short ("careful with the connections").
flip, hyb_of = {}, {}
for b in TIER:
    s = 0.0
    for a, c in d["edges"]:
        if a == "start" or c == "start": continue
        na, nc = nodes[a], nodes[c]
        for me, other in ((na, nc), (nc, na)):
            if me["branch"] == b and other["branch"] != b:
                col = int(me["id"].split("_")[2])
                s += (col - 2.5) * angdiff(arm[other["branch"]], arm[b])
                if TIER[b] == 2 and TIER[other["branch"]] == 1:
                    hyb_of[b] = other["branch"]
    flip[b] = -1.0 if s < 0 else 1.0
for m, h in hyb_of.items():
    flip[m] = flip[h]                  # keep mastery cols aligned with hybrid

WEDGE = 2 * math.pi / 5 * 0.80        # angular room per branch inside its annulus
# Per-band assignment: Vogel points arrive in bands of 20 (K/15), and each
# band belongs to exactly one row-cohort (5 branches × 4 cols). Matching on
# ANGLE only within each band makes row→radius strictly monotonic — no
# keystone can land near the Origin.
BAND = K // 15
pos2 = {"start": (0.0, 0.0)}
p_a_all = np.arctan2(pts[:, 1], pts[:, 0])
for ring in range(1, 16):
    cohort = [n for n in others
              if TIER[n["branch"]] * 5 + int(n["id"].split("_")[1]) == ring]
    t_a = np.array([arm[n["branch"]] + flip[n["branch"]]
                    * ((int(n["id"].split("_")[2]) - 2.5) / 4) * WEDGE
                    for n in cohort])
    idx = list(range((ring - 1) * BAND, ring * BAND))
    p_a = p_a_all[idx]
    da = np.abs((p_a[None, :] - t_a[:, None] + math.pi)
                % (2 * math.pi) - math.pi)
    ri, ci = linear_sum_assignment(da ** 2)
    for i, j in zip(ri, ci):
        pos2[cohort[i]["id"]] = (pts[idx[j]][0], pts[idx[j]][1])

# ── Semantic palette: 5 stat hues in pentagon order; hybrids blend their
#    parents; masteries deepen their hybrid's hue (sectors = color wheel) ──
HUES = [0.98, 0.13, 0.33, 0.58, 0.78]  # crimson, amber, emerald, azure, violet
prim_sorted = sorted(primaries, key=lambda b: arm[b] % (2 * math.pi))
# rotate so Warpath (MIG) = crimson and Attunement (MAG) lands on azure
shift = prim_sorted.index("warpath")
prim_sorted = prim_sorted[shift:] + prim_sorted[:shift]
bhue = {b: HUES[i] for i, b in enumerate(prim_sorted)}
for h, counts in cross.items():
    p1, p2 = sorted(counts, key=counts.get, reverse=True)[:2]
    a1, a2 = bhue[p1] * 2 * math.pi, bhue[p2] * 2 * math.pi
    mid = math.atan2((math.sin(a1) + math.sin(a2)) / 2,
                     (math.cos(a1) + math.cos(a2)) / 2)
    bhue[h] = (mid / (2 * math.pi)) % 1.0
for m, h in hyb_of.items():
    bhue[m] = bhue[h]
SV = [(0.60, 0.95), (0.70, 0.85), (0.80, 0.74)]        # per tier
pal = {b: colorsys.hsv_to_rgb(bhue[b], *SV[TIER[b]]) for b in TIER}
print("PALETTE:", {b: "#%02X%02X%02X" % tuple(int(c * 255) for c in pal[b])
                   for b in sorted(pal, key=lambda b: (TIER[b], arm[b]))})

fig2, ax2 = plt.subplots(figsize=(15, 15.8), dpi=150)
fig2.patch.set_facecolor(BG); ax2.set_facecolor(BG)

# ── Rewire: degree-bounded radial arborescence ("one in, ≤3 out") ─────────
# Greedy geometric DCMST: nodes processed inward→outward, each picks the
# cheapest parent CLOSER to the origin, cost penalizing tangential edges;
# parents capped at 3 children; keystones are always leaves. Branch entries:
# 2 innermost nodes of each primary attach to Origin; each hybrid's 2
# innermost attach one to EACH parent primary (both stat routes stay real);
# each mastery's 2 innermost attach to its hybrid.
CHILD_CAP, TANGENT_PEN, R_REF = 3, 1.5, 15.0
rad = {i: math.hypot(*pos2[i]) for i in pos2}
children = {i: 0 for i in pos2}
parent_of, fallbacks = {}, 0

def edge_cost(u, v):
    ux, uy = pos2[u]; vx, vy = pos2[v]
    dx, dy = vx - ux, vy - uy
    dist = math.hypot(dx, dy) or 1e-9
    if v in entry_anchor:                          # entries: pure nearest
        return dist
    rd = math.hypot(vx, vy) or 1e-9
    cosr = (dx * vx / rd + dy * vy / rd) / dist   # edge dir · radial dir at v
    beta = TANGENT_PEN * min(1.0, rad[v] / R_REF) # near center: pure nearest
    return dist * (1 + beta * (1 - cosr))

by_branch2 = {}
for n in others:
    by_branch2.setdefault(n["branch"], []).append(n["id"])
for b in by_branch2:
    by_branch2[b].sort(key=lambda i: rad[i])

# entries: hybrids only keep parents whose RENDERED wedge is angularly
# adjacent (<60° between wedge centroids); a far parent's entry re-anchors
# to the adjacent one (colors as the guide)
wedge_ang = {}
for b, ids in by_branch2.items():
    mx = sum(pos2[i][0] for i in ids) / len(ids)
    my = sum(pos2[i][1] for i in ids) / len(ids)
    wedge_ang[b] = math.atan2(my, mx)
# Parent branch(es) per branch: primaries ← Origin; hybrids ← their one/two
# ADJACENT parent primaries (wedge centroids < 60° apart); masteries ← hybrid.
parent_branches = {}
for b in by_branch2:
    if TIER[b] == 0:
        parent_branches[b] = ["__origin__", "__origin__"]
    elif TIER[b] == 1:
        ps = sorted(cross[b], key=cross[b].get, reverse=True)[:2]
        near = [p for p in ps
                if abs(angdiff(wedge_ang[p], wedge_ang[b])) < math.pi / 3]
        p1 = near[0] if near else ps[0]
        p2 = near[1] if len(near) > 1 else p1
        parent_branches[b] = [p1, p2]
    else:
        parent_branches[b] = [hyb_of[b], hyb_of[b]]

# Entries = the CLOSEST PAIRS between a branch and its parent branch(es);
# then each branch grows its internal tree outward from its entries
# (Prim / space-colonization style — no center shots, no long arcs).
entry_anchor = {}
for tier in (0, 1, 2):
    for b, ids in by_branch2.items():
        if TIER[b] != tier: continue
        entries = []
        used_entries = set()
        for pb in parent_branches[b]:
            pool = ["start"] if pb == "__origin__" else \
                   [u for u in by_branch2[pb] if nodes[u]["type"] != "keystone"]
            pairs = sorted(((math.dist(pos2[u], pos2[v]), u, v)
                            for u in pool for v in ids
                            if v not in used_entries
                            and (u == "start" or children[u] < CHILD_CAP)))
            _, u, v = pairs[0]
            parent_of[v] = u
            children[u] = children.get(u, 0) + 1
            used_entries.add(v)
            entries.append(v)
            entry_anchor[v] = pool
        placed = set(entries)
        while len(placed) < len(ids):
            best = None
            for u in placed:
                if nodes[u]["type"] == "keystone" or children[u] >= CHILD_CAP:
                    continue
                for v in ids:
                    if v in placed: continue
                    c = edge_cost(u, v)
                    if best is None or c < best[0]: best = (c, u, v)
            if best is None:                      # all placed saturated
                fallbacks += 1
                cand = sorted(((math.dist(pos2[u], pos2[v]), u, v)
                               for u in placed for v in ids if v not in placed))
                _, u, v = cand[0]
            else:
                _, u, v = best
            parent_of[v] = u
            children[u] = children.get(u, 0) + 1
            placed.add(v)

# ── Repair passes ──────────────────────────────────────────────────────────
def seg_cross(a, b, c, d):
    if len({a, b, c, d}) < 4: return False        # shared endpoint ≠ crossing
    (ax_, ay), (bx, by_) = pos2[a], pos2[b]
    (cx, cy), (dx_, dy_) = pos2[c], pos2[d]
    def o(px, py, qx, qy, rx, ry):
        v = (qx - px) * (ry - py) - (qy - py) * (rx - px)
        return 0 if abs(v) < 1e-12 else (1 if v > 0 else -1)
    return (o(ax_, ay, bx, by_, cx, cy) != o(ax_, ay, bx, by_, dx_, dy_) and
            o(cx, cy, dx_, dy_, ax_, ay) != o(cx, cy, dx_, dy_, bx, by_))

def in_subtree(candidate, root_child):
    u = candidate
    while u in parent_of:
        if u == root_child: return True
        u = parent_of[u]
    return False

def repair_pool(v):
    """Wider than pool_of: any same-branch non-keystone (laterals allowed),
    plus the original entry pool for entry nodes."""
    if v in entry_anchor:
        return [u for u in entry_anchor[v]
                if u == "start" or nodes[u]["type"] != "keystone"]
    b = nodes[v]["branch"]
    return [u for u in by_branch2[b]
            if u != v and nodes[u]["type"] != "keystone"]

def reassign(v, u):
    old = parent_of[v]
    parent_of[v] = u
    children[old] -= 1; children[u] = children.get(u, 0) + 1

# 1) lateral repair: kill long in-branch arcs by hanging the node off its
#    true nearest neighbour (real trees have lateral twigs)
LATERAL_MAX = 9.0
for v in sorted(parent_of, key=lambda v: -math.dist(pos2[parent_of[v]], pos2[v])):
    old = parent_of[v]
    if math.dist(pos2[old], pos2[v]) <= LATERAL_MAX: break
    cands = [u for u in repair_pool(v)
             if (u == "start" or children.get(u, 0) < CHILD_CAP)
             and not in_subtree(u, v)]
    if not cands: continue
    u = min(cands, key=lambda u: math.dist(pos2[u], pos2[v]))
    if math.dist(pos2[u], pos2[v]) < 0.7 * math.dist(pos2[old], pos2[v]):
        reassign(v, u)

# 2) uncrossing: reroute the LONGER edge of each crossing pair to the
#    candidate that minimizes (crossings created, cost)
x0 = None
for sweep in range(30):
    edges_now = [(parent_of[v], v) for v in parent_of]
    xpairs = [(e1, e2) for i, e1 in enumerate(edges_now)
              for e2 in edges_now[i + 1:] if seg_cross(*e1, *e2)]
    if x0 is None: x0 = len(xpairs)
    if not xpairs: break
    changed = False
    for pair in sorted(xpairs, key=lambda p: -max(
            math.dist(pos2[p[0][0]], pos2[p[0][1]]),
            math.dist(pos2[p[1][0]], pos2[p[1][1]]))):
        e_a, e_b = sorted(pair, key=lambda e: -math.dist(pos2[e[0]], pos2[e[1]]))
        for (u_old, v) in (e_a, e_b):             # try longer edge first
            if parent_of.get(v) != u_old: continue
            others_e = [(parent_of[w], w) for w in parent_of if w != v]
            cur_x = sum(1 for e in others_e if seg_cross(u_old, v, *e))
            if cur_x == 0: continue
            best = None
            for u in sorted(repair_pool(v),
                            key=lambda u: math.dist(pos2[u], pos2[v]))[:24]:
                if u == u_old or in_subtree(u, v): continue
                if u != "start" and children.get(u, 0) >= CHILD_CAP + 1: continue
                if math.dist(pos2[u], pos2[v]) > 2.0 * math.dist(pos2[u_old], pos2[v]) + 2:
                    continue
                nx = sum(1 for e in others_e if seg_cross(u, v, *e))
                cand = (nx, math.dist(pos2[u], pos2[v]), u)
                if best is None or cand < best: best = cand
            if best and best[0] < cur_x:
                reassign(v, best[2]); changed = True
                break
    if not changed: break
edges_now = [(parent_of[v], v) for v in parent_of]
xlist = [(e1, e2) for i, e1 in enumerate(edges_now)
         for e2 in edges_now[i + 1:] if seg_cross(*e1, *e2)]
tree_edges = edges_now
print(f"CROSSINGS: {x0} initial -> {len(xlist)} after repair passes")
for (u1, v1), (u2, v2) in xlist:
    print(f"  X: {u1}->{v1}  ×  {u2}->{v2}")

lens = []
for a, b in tree_edges:
    (x0, y0), (x1, y1) = pos2[a], pos2[b]
    lens.append(math.hypot(x1 - x0, y1 - y0))
    same = (a != "start" and nodes[a]["branch"] == nodes[b]["branch"])
    ax2.plot([x0, x1], [y0, y1],
             color=EDGE if same else "#4A4A6E",
             lw=0.8 if same else 1.1,
             alpha=0.65 if same else 0.7, zorder=2 if same else 3)

deg = {}
for i in children:
    if i != "start": deg[children[i]] = deg.get(children[i], 0) + 1
print(f"TREE: {len(tree_edges)} edges (was {len(d['edges'])}) · "
      f"out-degree histogram {dict(sorted(deg.items()))} · fallbacks {fallbacks}")

for n in d["nodes"]:
    if n["id"] == "start":
        ax2.scatter(0, 0, s=380, marker="*", color=ORIGIN_C,
                    edgecolors="#12121C", linewidths=1.2, zorder=7); continue
    x, y = pos2[n["id"]]
    col = pal[n["branch"]]
    if n["type"] == "keystone":
        ax2.scatter(x, y, s=165, marker="D", color=col, edgecolors=GOLD,
                    linewidths=1.7, zorder=6)
    elif n["type"] == "notable":
        ax2.scatter(x, y, s=80, marker="o", color=col, edgecolors="#12121C",
                    linewidths=0.8, zorder=5)
    else:
        ax2.scatter(x, y, s=28, marker="o", color=col, zorder=4)

# per-node id tags (sector_row_col) so specific nodes can be called out
for n in others:
    x, y = pos2[n["id"]]
    ax2.annotate(n["id"], (x, y), xytext=(3, -4), textcoords="offset points",
                 fontsize=3.4, color="#7A7A94", zorder=9)

# labels at branch centroid, pushed outward
for b in bstat:
    px = [pos2[n["id"]] for n in others if n["branch"] == b]
    mx = sum(p[0] for p in px) / len(px); my = sum(p[1] for p in px) / len(px)
    r = math.hypot(mx, my) or 1
    rr = max(math.hypot(*p) for p in px) + (3.8 if TIER[b] == 2 else 2.4)
    ax2.text(mx / r * rr, my / r * rr, b.upper(), color=pal[b],
             fontsize=10.5, fontweight="bold", ha="center", va="center", zorder=8,
             bbox=dict(boxstyle="round,pad=0.28", facecolor=BG,
                       edgecolor="none", alpha=0.75))

leg2 = ax2.legend(handles=handles, loc="lower right", frameon=True, fontsize=10,
                  labelcolor=INK, borderpad=0.9)
leg2.get_frame().set_facecolor("#16161F"); leg2.get_frame().set_edgecolor("#2D2D41")

ax2.set_title("Talent tree v3 — candidate B: golden-angle sunflower, sector-coherent",
              color=INK, fontsize=16, fontweight="bold", pad=20)
ax2.text(0.5, 1.007,
         f"PROPOSED REWIRE: radial arborescence · one in / ≤3 out / keystones are leaves · "
         f"{len(tree_edges)} edges (was {len(d['edges'])}) · "
         f"length mean {sum(lens)/len(lens):.1f} / max {max(lens):.1f} grid units",
         transform=ax2.transAxes, ha="center", va="bottom", color=INK_DIM, fontsize=11)
ax2.set_aspect("equal"); ax2.axis("off")
lim2 = SCALE * math.sqrt(K) + 6
ax2.set_xlim(-lim2, lim2); ax2.set_ylim(lim2, -lim2)
fig2.savefig(os.path.join(REPO, "docs", "talent_tree_v3_B.png"),
             facecolor=BG, bbox_inches="tight")
print("saved B; edge len mean %.2f max %.2f" % (sum(lens)/len(lens), max(lens)))

# ── standalone zoomed core view (radius ≤ 18) with readable id tags ────────
fig3, ax3 = plt.subplots(figsize=(12, 12), dpi=150)
fig3.patch.set_facecolor(BG); ax3.set_facecolor(BG)
LIM3 = 16
for a, b in tree_edges:
    (x0_, y0_), (x1_, y1_) = pos2[a], pos2[b]
    if max(abs(x0_), abs(y0_), abs(x1_), abs(y1_)) > LIM3 + 6: continue
    same = (a != "start" and nodes[a]["branch"] == nodes[b]["branch"])
    ax3.plot([x0_, x1_], [y0_, y1_], color=EDGE if same else "#4A4A6E",
             lw=1.2 if same else 1.5, alpha=0.8, zorder=2)
for n in d["nodes"]:
    x, y = pos2[n["id"]]
    if max(abs(x), abs(y)) > LIM3 + 4: continue
    if n["id"] == "start":
        ax3.scatter(x, y, s=500, marker="*", color=ORIGIN_C,
                    edgecolors="#12121C", linewidths=1.4, zorder=7)
        continue
    col = pal[n["branch"]]
    s, mk = (240, "D") if n["type"] == "keystone" else \
            (130, "o") if n["type"] == "notable" else (55, "o")
    ec = GOLD if n["type"] == "keystone" else "#12121C"
    ax3.scatter(x, y, s=s, marker=mk, color=col, edgecolors=ec,
                linewidths=1.0, zorder=5)
    ax3.annotate(n["id"], (x, y), xytext=(5, -7), textcoords="offset points",
                 fontsize=7.5, color="#9A9AB4", zorder=9)
ax3.set_title("v3 candidate B — core zoom (r ≤ 16)", color=INK,
              fontsize=14, fontweight="bold", pad=12)
ax3.set_aspect("equal"); ax3.axis("off")
ax3.set_xlim(-LIM3, LIM3); ax3.set_ylim(LIM3, -LIM3)
fig3.savefig(os.path.join(REPO, "docs", "talent_tree_v3_B_center.png"),
             facecolor=BG, bbox_inches="tight")
print("saved center zoom")
long_edges = sorted(((l, a, b) for l, (a, b) in zip(lens, tree_edges)), reverse=True)[:8]
for l, a, b in long_edges:
    print(f"  LONG {l:5.1f}  {a} - {b}")

# ── Emit editor data (tools/talent_layout/layout_b.js) ─────────────────────
edata = {"origin": "start", "nodes": [], "edges": [list(e) for e in tree_edges]}
edata["nodes"].append({"id": "start", "x": 0.0, "y": 0.0, "type": "origin",
                       "branch": "origin", "name": "Origin", "color": ORIGIN_C})
for n in others:
    x, y = pos2[n["id"]]
    hexc = "#%02X%02X%02X" % tuple(int(c * 255) for c in pal[n["branch"]])
    edata["nodes"].append({"id": n["id"], "x": round(x, 3), "y": round(y, 3),
                           "type": n["type"], "branch": n["branch"],
                           "name": n["name"], "color": hexc})
with open(os.path.join(REPO, "tools", "talent_layout", "layout_b.js"), "w",
          encoding="utf-8") as f:
    f.write("const DATA = " + json.dumps(edata) + ";")
print("saved layout_b.js")
