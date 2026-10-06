#!/usr/bin/env python3
"""Hell's heated-rock mask, top-down over the ring, from the chunk .glbs' lava surfaces.
R: metres (x MAX_DIST) to the nearest lava in xz; G: that lava's top y, (y - Y_MIN) / Y_SPAN. Run from the repo root."""
import json, struct, sys
import numpy as np
from PIL import Image
from scipy import ndimage

CHUNKS = ["s1", "s2", "s3", "s4", "s5"]
LAVA = {"LavaSea", "LavaRiver", "LavaCrack"}
SIZE = 1024          # texels a side; keep hot_rock.gdshader's mask_* uniforms equal
HALF = 60.0          # metres from the ring centre to the mask's edge (lava reaches 57)
MAX_DIST = 4.0       # metres R=1 stands for
Y_MIN, Y_SPAN = -16.0, 48.0
OUT = "maps/bentham_ring/textures/hot_rock_mask.png"
MAP_OFFSET = np.array([0.014858246, 0.0, -0.01688385])   # MapBase's transform in bentham_ring.tscn


def lava_triangles(path):
    d = open(path, "rb").read()
    n = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + n])
    binoff = 20 + n + 8
    def acc(i, comps):
        a = j["accessors"][i]; v = j["bufferViews"][a["bufferView"]]
        dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a["componentType"]]
        start = binoff + v.get("byteOffset", 0) + a.get("byteOffset", 0)
        return np.frombuffer(d, dt, a["count"] * comps, start).reshape(a["count"], comps) if comps > 1 else np.frombuffer(d, dt, a["count"], start)
    tris = []
    for node in j["nodes"]:
        if "mesh" not in node or node["name"].endswith("-colonly"):
            continue
        for p in j["meshes"][node["mesh"]]["primitives"]:
            if p.get("material") is None or j["materials"][p["material"]]["name"].split(".")[0] not in LAVA:
                continue
            pos = acc(p["attributes"]["POSITION"], 3) + MAP_OFFSET
            idx = acc(p["indices"], 1).astype(np.int64)
            tris.append(pos[idx.reshape(-1, 3)])
    return np.concatenate(tris) if tris else np.zeros((0, 3, 3))


def raster(tris):
    """Each lava texel's top y: every triangle sampled at under half a texel and stamped with its highest point."""
    top = np.full((SIZE, SIZE), -np.inf)
    px = SIZE / (2 * HALF)
    uv = np.stack([(tris[..., 0] + HALF) * px, (tris[..., 2] + HALF) * px], -1)
    for t, q in zip(tris, uv):
        n = int(np.ceil(max(np.linalg.norm(q[1] - q[0]), np.linalg.norm(q[2] - q[1]), np.linalg.norm(q[0] - q[2])) * 2)) + 1
        a, b = np.meshgrid(np.linspace(0, 1, n + 1), np.linspace(0, 1, n + 1))
        keep = a + b <= 1
        a, b = a[keep], b[keep]
        pts = q[0] + a[:, None] * (q[1] - q[0]) + b[:, None] * (q[2] - q[0])
        ix = np.clip(pts[:, 0].astype(int), 0, SIZE - 1); iy = np.clip(pts[:, 1].astype(int), 0, SIZE - 1)
        np.maximum.at(top, (iy, ix), t[:, 1].max())
    return top


def main():
    tris = np.concatenate([lava_triangles(f"maps/bentham_ring/models/map_base_{c}.glb") for c in CHUNKS])
    top = raster(tris)
    lava = np.isfinite(top)
    dist, (iy, ix) = ndimage.distance_transform_edt(~lava, return_indices=True)
    dist_m = dist * (2 * HALF / SIZE)
    near_y = top[iy, ix]
    r = np.clip(dist_m / MAX_DIST, 0, 1)
    g = np.clip((near_y - Y_MIN) / Y_SPAN, 0, 1)
    img = np.zeros((SIZE, SIZE, 3), np.uint8)
    img[..., 0] = np.round(r * 255); img[..., 1] = np.round(g * 255)
    Image.fromarray(img, "RGB").save(OUT, optimize=True)
    print(f"{OUT}: {len(tris)} lava triangles, {lava.sum()} lava texels")


if __name__ == "__main__":
    sys.exit(main())
