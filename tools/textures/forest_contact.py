#!/usr/bin/env python3
"""Green forest trunk contact mask, top-down over the map, read by forest_dapple_lit.gdshader.

R = metres from the nearest trunk's edge / REACH (0 at the bark, 1 at REACH or more); G = that trunk's
ground y, (y - Y0) / YSPAN. Trunks are ForestCanopyCollision-colonly in forest_canopy.glb; props are every
prop glb instanced in forest.tscn, their footprint the hull of the mesh's lowest 0.5 m, ring scaled to size.
    python3 tools/textures/forest_contact.py   -> maps/forest/textures/forest_contact.png
"""
import json
import re
import struct

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt
from scipy.spatial import ConvexHull, Delaunay

EXTENT = 60.0      # metres from the centre to each edge: the mask spans -60..60 in x and z
SIZE = 512         # pixels a side, ~0.23 m
REACH = 4.0        # metres of edge distance R encodes
Y0, YSPAN = 13.0, 20.0
CANOPY = "maps/forest/models/forest_canopy.glb"
GROUND = "maps/forest/models/forest.glb"
SCENE = "maps/forest/forest.tscn"
PROPS = ("bush_low", "bush_tall", "rock_boulder", "rock_outcrop", "rock_slab", "thorns", "bars", "portal")
TRUNK_R = 0.93     # mean trunk footprint radius: a prop of this size gets the trunks' ring
OUT = "maps/forest/textures/forest_contact.png"


def glb(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    return json.loads(b[20:20 + n]), b[20 + n + 8:]


def positions(j, data, prim):
    a = j["accessors"][prim["attributes"]["POSITION"]]
    bv = j["bufferViews"][a["bufferView"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    return np.frombuffer(data, np.float32, a["count"] * 3, off).reshape(-1, 3).astype(np.float64)


def mesh(j, name):
    return next(m for m in j["meshes"] if m["name"] == name)


j, data = glb(CANOPY)
col = positions(j, data, mesh(j, "ForestCanopyCollision-colonly")["primitives"][0])
low = col[col[:, 1] < 24.0]

# Single-linkage on a 0.5 m grid: every connected footprint near the lane is one trunk.
cells = {}
for i, (x, _, z) in enumerate(low):
    cells.setdefault((int(np.floor(x / 0.5)), int(np.floor(z / 0.5))), []).append(i)
seen, trunks = set(), []
for start in cells:
    if start in seen:
        continue
    stack, members = [start], []
    seen.add(start)
    while stack:
        c = stack.pop()
        members += cells[c]
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                k = (c[0] + dx, c[1] + dz)
                if k in cells and k not in seen:
                    seen.add(k)
                    stack.append(k)
    p = low[members]
    base = p[p[:, 1] < p[:, 1].min() + 0.4]
    c = base[:, [0, 2]].mean(0)
    trunks.append((c, np.linalg.norm(base[:, [0, 2]] - c, axis=1).mean()))

gj, gdata = glb(GROUND)
mats = [m["name"] for m in gj["materials"]]
ground = np.concatenate([positions(gj, gdata, p) for p in mesh(gj, "ForestGround")["primitives"]
                         if mats[p["material"]] in ("forest_grass", "forest_verge", "forest_path",
                                                    "forest_edge", "forest_earth")])

t = (np.arange(SIZE) + 0.5) / SIZE * 2 * EXTENT - EXTENT
px, pz = np.meshgrid(t, t)          # row = z, column = x
dist = np.full((SIZE, SIZE), REACH)
gy = np.full((SIZE, SIZE), 23.0)
for c, r in trunks:
    near = np.linalg.norm(ground[:, [0, 2]] - c, axis=1)
    ring = ground[(near > r) & (near < r + 2.0), 1]
    y = float(np.median(ring)) if len(ring) else 23.0
    d = np.hypot(px - c[0], pz - c[1]) - r
    closer = d < dist
    dist[closer] = d[closer]
    gy[closer] = y


def ground_y(c, r):
    near = np.linalg.norm(ground[:, [0, 2]] - c, axis=1)
    ring = ground[(near > r) & (near < r + 2.0), 1]
    return float(np.median(ring)) if len(ring) else 23.0


# Props: forest.tscn instances (parents are untransformed groups), render mesh only.
tscn = open(SCENE).read()
ids = {i: f for f, i in re.findall(r'path="res://maps/forest/(?:models|props)/forest_(\w+)\.(?:glb|tscn)" id="(\w+)"', tscn)}
px_m = 2 * EXTENT / SIZE
props = 0
for res, xf in re.findall(r'instance=ExtResource\("(\w+)"\)\]\n(?:(?!\[node).*\n)*?transform = Transform3D\(([^)]*)\)', tscn):
    name = ids.get(res)
    if name not in PROPS:
        continue
    t9 = np.array([float(v) for v in xf.split(",")])
    basis, origin = t9[:9].reshape(3, 3), t9[9:]
    pj, pdata = glb(f"maps/forest/models/forest_{name}.glb")
    v = np.concatenate([positions(pj, pdata, q) for m in pj["meshes"] if not m["name"].endswith("-colonly")
                        for q in m["primitives"]])
    v = v[v[:, 1] < v[:, 1].min() + 0.5] @ basis.T + origin
    ch = ConvexHull(v[:, [0, 2]])
    hull, r = ch.points[ch.vertices], np.sqrt(ch.volume / np.pi)
    s = np.clip(r / TRUNK_R, 0.6, 1.5)
    lo = np.floor((hull.min(0) + EXTENT) / px_m).astype(int) - int(REACH * s / px_m) - 2
    hi = np.ceil((hull.max(0) + EXTENT) / px_m).astype(int) + int(REACH * s / px_m) + 2
    lo, hi = np.clip(lo, 0, SIZE), np.clip(hi, 0, SIZE)
    wx, wz = px[lo[1]:hi[1], lo[0]:hi[0]], pz[lo[1]:hi[1], lo[0]:hi[0]]
    inside = Delaunay(hull).find_simplex(np.stack([wx, wz], -1)) >= 0
    d = distance_transform_edt(~inside) * px_m / s      # trunk-equivalent metres
    win, gwin = dist[lo[1]:hi[1], lo[0]:hi[0]], gy[lo[1]:hi[1], lo[0]:hi[0]]
    closer = d < win
    win[closer] = d[closer]
    gwin[closer] = ground_y(hull.mean(0), r)
    props += 1

rgb = np.zeros((SIZE, SIZE, 3))
rgb[..., 0] = np.clip(dist / REACH, 0, 1)
rgb[..., 1] = np.clip((gy - Y0) / YSPAN, 0, 1)
Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), "RGB").save(OUT)
print(f"{len(trunks)} trunks, {props} props -> {OUT}")
