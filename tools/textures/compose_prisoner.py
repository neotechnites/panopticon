#!/usr/bin/env python3
"""Composes prisoner2_albedo.png from Ryan's 4-swatch prisoner.ase: each face of prisoner2.glb gets the swatch it had on the old model
(prisoner_faces.json; old shoes quarter is skin, its eyes/mouth/soles dark skin), tiled 1:1 across its UVs (+3 px margin)."""
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
TABLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "prisoner_faces.json")
OLD = "870c757:characters/models/prisoner2.glb"   # Ryan's old model: its UV quarters are the authoritative materials
SWATCHES = {"trousers": [0, 0, 0.5, 0.5], "skin": [0, 0.5, 0.5, 0.5], "shirt": [0.5, 0.5, 0.5, 0.5],
            "dark_skin": [0.5, 0, 0.5, 0.5]}
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


def key(pos):
    """Face key: its three vertex positions, sorted, so reordered faces still match."""
    return ",".join("%.4f" % v for vert in sorted(map(tuple, np.round(pos, 4) + 0.0)) for v in vert)


def shoes(p):
    """Old shoes face: dark skin if an eye, the mouth below the nose, or a sole; else skin."""
    (x, y, z), n = p.mean(0), np.cross(p[1] - p[0], p[2] - p[0])
    n = n / (np.linalg.norm(n) + 1e-12)
    eye = 1.60 < y < 1.64 and z > 0.2 and n[2] > 0.5
    mouth = 1.43 < y < 1.50 and z > 0.19 and abs(x) < 0.05 and n[2] > 0.5
    sole = y < 0.01 and n[1] < -0.9
    return "dark_skin" if eye or mouth or sole else "skin"


def build_table():
    """Per-face swatch from the old model (870c757): the quarter its old UVs sat in is its material."""
    old = subprocess.run(["git", "-C", ROOT, "show", OLD], capture_output=True, check=True).stdout
    tmp = os.path.join(ROOT, ".godot", "prisoner_old.glb")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    open(tmp, "wb").write(old)
    quarter = {(0, 0): "trousers", (1, 0): "shoes", (0, 1): "skin", (1, 1): "shirt"}
    faces = {key(p): shoes(p) if q == "shoes" else q
             for p, uv in triangles(tmp) for q in [quarter[tuple(int(c >= 0.5) for c in uv.mean(0))]]}
    os.remove(tmp)
    table = {"_note": "Face (sorted vertex positions) -> swatch, read from the old UVs at " + OLD + ".",
             "swatches": SWATCHES, "faces": faces}
    json.dump(table, open(TABLE, "w"), indent=0)
    return table


def lookup(table, pos):
    k = key(pos)
    if k in table["faces"]:
        return table["faces"][k]
    want = np.array([float(v) for v in k.split(",")])
    best = min(table["faces"], key=lambda f: np.abs(np.array([float(v) for v in f.split(",")]) - want).max())
    assert np.abs(np.array([float(v) for v in best.split(",")]) - want).max() < 1e-3, "face not in table: " + k
    return table["faces"][best]


def raster(uv, size):
    """Pixels whose centre lies in the UV triangle."""
    m = np.zeros((size, size), bool)
    t = uv * size
    (ax, ay), (bx, by), (cx, cy) = t
    d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(d) < 1e-12:
        return m
    x0, y0 = np.clip(np.floor(t.min(0)).astype(int), 0, size)
    x1, y1 = np.clip(np.ceil(t.max(0)).astype(int) + 1, 0, size)
    ys, xs = np.mgrid[y0:y1, x0:x1] + 0.5
    l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / d
    l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / d
    m[y0:y1, x0:x1] = (l1 >= -1e-6) & (l2 >= -1e-6) & (1 - l1 - l2 >= -1e-6)
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
    table = json.load(open(TABLE)) if os.path.exists(TABLE) else build_table()
    tris = triangles(GLB)
    names = list(SWATCHES)
    face = [names.index(lookup(table, p)) for p, _ in tris]
    masks = [np.zeros((size, size), bool) for _ in names]
    for (_, uv), k in zip(tris, face):
        masks[k] |= raster(uv, size)
    owner = np.full((size, size), -1)
    for _ in range(MARGIN + 1):   # ring by ring, so a margin never covers another swatch's faces
        for k, m in enumerate(masks):
            owner[m & (owner < 0)] = k
        masks = [grow(m) for m in masks]
    out = np.zeros_like(sheet)
    ys, xs = np.nonzero(owner >= 0)
    for y, x in zip(ys, xs):
        fx, fy, fw, fh = SWATCHES[names[owner[y, x]]]
        sx, sy, sw, sh = round(fx * size), round(fy * size), round(fw * size), round(fh * size)
        out[y, x] = sheet[sy + y % sh, sx + x % sw]
    Image.fromarray(out).save(ALBEDO)
    old = {n: list(table["faces"].values()).count(n) for n in names}
    now = {n: face.count(n_i) for n_i, n in enumerate(names)}
    print("composed %d faces per face -> %s | old %s | now %s" % (len(tris), os.path.relpath(ALBEDO, ROOT), old, now))


if __name__ == "__main__":
    main()
