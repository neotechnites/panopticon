#!/usr/bin/env python3
"""Composes prisoner2_albedo.png from Ryan's 4-swatch prisoner.ase: each UV island of prisoner2.glb gets its
swatch (a quarter of the sheet, any sheet size) tiled 1:1 (nearest, +3 px margin). His pixels are copied verbatim; island masks come from the glb's UVs."""
import json, os, struct, subprocess
import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASEPRITE = os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/Aseprite/Aseprite.app/Contents/MacOS/aseprite")
ASE = os.path.join(ROOT, "characters/textures/prisoner.ase")
SHEET = os.path.join(ROOT, "characters/textures/prisoner_sheet.png")    # his sheet, flattened, as painted
ALBEDO = os.path.join(ROOT, "characters/textures/prisoner2_albedo.png")  # what the glb samples
GLB = os.path.join(ROOT, "characters/models/prisoner2.glb")
TABLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "prisoner_islands.json")
MARGIN = 3
TYPES = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}


def triangles(path):
    """Every triangle of the glb as (positions 3x3, uvs 3x2)."""
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j, data = json.loads(b[20:20 + n]), b[20 + n + 8:]

    def acc(i):
        a = j["accessors"][i]
        v = j["bufferViews"][a["bufferView"]]
        dt, w = np.dtype(TYPES[a["componentType"]]), WIDTH[a["type"]]
        stride = v.get("byteStride") or dt.itemsize * w
        off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        rows = [np.frombuffer(data, dt, w, off + k * stride) for k in range(a["count"])]
        return np.array(rows, dtype=float)

    out = []
    for mesh in j["meshes"]:
        for p in mesh["primitives"]:
            pos, uv = acc(p["attributes"]["POSITION"]), acc(p["attributes"]["TEXCOORD_0"])
            for t in acc(p["indices"]).reshape(-1, 3).astype(int):
                out.append((pos[t], uv[t]))
    return out


def islands(tris):
    """Triangles that share a UV point are one island."""
    parent = list(range(len(tris)))

    def root(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    seen = {}
    for i, (_, uv) in enumerate(tris):
        for u in uv:
            k = tuple(np.round(u * 1024, 0))
            if k in seen:
                parent[root(i)] = root(seen[k])
            else:
                seen[k] = i
    groups = {}
    for i in range(len(tris)):
        groups.setdefault(root(i), []).append(i)
    return list(groups.values())


def raster(uvs, size):
    """Pixels whose centre lies in any of the UV triangles."""
    m = np.zeros((size, size), bool)
    ys, xs = np.mgrid[0:size, 0:size] + 0.5
    for uv in uvs:
        (ax, ay), (bx, by), (cx, cy) = uv * size
        d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(d) < 1e-12:
            continue
        l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / d
        l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / d
        m |= (l1 >= -1e-6) & (l2 >= -1e-6) & (1 - l1 - l2 >= -1e-6)
    return m


def grow(m):
    g = m.copy()
    g[1:] |= m[:-1]; g[:-1] |= m[1:]
    g[:, 1:] |= g[:, :-1].copy(); g[:, :-1] |= g[:, 1:].copy()
    return g


def main():
    subprocess.run([ASEPRITE, "-b", ASE, "--save-as", SHEET], check=True, capture_output=True)
    sheet = np.array(Image.open(SHEET).convert("RGBA"))
    size = sheet.shape[0]
    table = json.load(open(TABLE))
    tris = triangles(GLB)
    owner = np.full((size, size), -1)
    masks, swatch = [], []
    for isl in islands(tris):
        c = np.concatenate([tris[i][0] for i in isl]).mean(0)
        entry = min(table["islands"], key=lambda e: np.linalg.norm(np.array(e["centroid"]) - c))
        masks.append(raster([tris[i][1] for i in isl], size))
        swatch.append(table["swatches"][entry["swatch"]])
    for _ in range(MARGIN + 1):   # ring by ring, so a margin never covers another island
        for k, m in enumerate(masks):
            owner[m & (owner < 0)] = k
        masks = [grow(m) for m in masks]
    out = np.zeros_like(sheet)
    ys, xs = np.nonzero(owner >= 0)
    for y, x in zip(ys, xs):
        fx, fy, fw, fh = swatch[owner[y, x]]
        sx, sy, sw, sh = round(fx * size), round(fy * size), round(fw * size), round(fh * size)
        out[y, x] = sheet[sy + y % sh, sx + x % sw]
    Image.fromarray(out).save(ALBEDO)
    print("composed %d islands -> %s" % (len(swatch), os.path.relpath(ALBEDO, ROOT)))


if __name__ == "__main__":
    main()
