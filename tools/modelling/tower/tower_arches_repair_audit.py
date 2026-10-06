"""Proof for tower_arches_repaired.glb: welded topology, triangle quality, and that the shaft and collider are untouched.
python3 tools/modelling/tower/tower_arches_repair_audit.py [new.glb]"""

import json
import math
import os
import struct
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OLD = os.path.join(REPO, "tower", "models", "tower_arches.glb")
NEW = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "tower", "models", "tower_arches_repaired.glb")
SEAM_Z = 0.6    # glTF y: the cleaned region is everything a triangle reaches above this


def load(path):
    d = open(path, "rb").read()
    jl = struct.unpack_from("<I", d, 12)[0]
    j = json.loads(d[20:20 + jl])
    b = d[20 + jl + 8:]

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
        f = {5126: "f", 5123: "H", 5125: "I"}[a["componentType"]]
        arr = struct.unpack_from("<%d%s" % (a["count"] * n, f), b, bv.get("byteOffset", 0))
        return [tuple(arr[k * n:(k + 1) * n]) for k in range(a["count"])] if n > 1 else list(arr)

    def prim(mi):
        p = j["meshes"][mi]["primitives"][0]
        at = {k: acc(v) for k, v in p["attributes"].items()}
        idx = acc(p["indices"])
        corner = lambda i: tuple(at[k][i] for k in sorted(at))
        tris = [tuple(corner(i) for i in idx[k:k + 3]) for k in range(0, len(idx), 3)]
        return at["POSITION"], idx, tris
    return j, prim


def topo(pos, idx):
    wid, key = [], {}
    for p in pos:
        k = tuple(round(c, 6) for c in p)
        wid.append(key.setdefault(k, len(key)))
    verts = list(key)
    faces = [tuple(wid[i] for i in idx[k:k + 3]) for k in range(0, len(idx), 3)]
    parent = list(range(len(verts)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    directed, degen = {}, 0
    for f in faces:
        for k in range(3):
            e = (f[k], f[(k + 1) % 3])
            directed[e] = directed.get(e, 0) + 1
            parent[find(e[0])] = find(e[1])
        if len(set(f)) < 3:
            degen += 1
    comps = len(set(find(i) for f in faces for i in f))
    man = bnd = dbl = over = 0
    seen = set()
    for (a, b), n in directed.items():
        k = (min(a, b), max(a, b))
        if k in seen:
            continue
        seen.add(k)
        back = directed.get((b, a), 0)
        if n == 1 and back == 1:
            man += 1
        elif n + back == 1:
            bnd += 1
        elif n + back >= 3:
            over += 1
        else:
            dbl += 1
    rk = {}
    dup = 0
    for v in verts:
        k = tuple(round(c, 4) for c in v)
        dup += k in rk
        rk[k] = 1
    return verts, faces, dict(components=comps, manifold=man, boundary=bnd, doubled=dbl, over=over,
                              nonmanifold=bnd + dbl + over, degenerate=degen, duplicate_positions=dup)


def quality(verts, faces, region):
    angs, areas, worst = [], [], []
    for f in faces:
        P = [verts[i] for i in f]
        if not region(P):
            continue
        a = []
        for k in range(3):
            p, q, r = P[k], P[(k + 1) % 3], P[(k + 2) % 3]
            u = [q[i] - p[i] for i in range(3)]
            w = [r[i] - p[i] for i in range(3)]
            lu, lw = math.sqrt(sum(x * x for x in u)), math.sqrt(sum(x * x for x in w))
            c = sum(u[i] * w[i] for i in range(3)) / max(lu * lw, 1e-12)
            a.append(math.degrees(math.acos(max(-1.0, min(1.0, c)))))
        u = [P[1][i] - P[0][i] for i in range(3)]
        w = [P[2][i] - P[0][i] for i in range(3)]
        cr = (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])
        areas.append(0.5 * math.sqrt(sum(x * x for x in cr)))
        angs.append(min(a))
    angs.sort()
    return dict(tris=len(angs), min_angle=round(angs[0], 2), slivers_lt5=sum(a < 5 for a in angs),
                lt10=sum(a < 10 for a in angs), tiny_lt_0p005m2=sum(x < 0.005 for x in areas),
                min_area=round(min(areas), 5))


def creases(verts, faces, region, limit):
    """Edges in the region whose faces fold by more than `limit` degrees (sharp ridges or crevices)."""
    norm = []
    for f in faces:
        P = [verts[i] for i in f]
        u = [P[1][i] - P[0][i] for i in range(3)]
        w = [P[2][i] - P[0][i] for i in range(3)]
        n = (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])
        L = math.sqrt(sum(x * x for x in n)) or 1.0
        norm.append(tuple(x / L for x in n))
    ef = {}
    for fi, f in enumerate(faces):
        for k in range(3):
            ef.setdefault((min(f[k], f[(k + 1) % 3]), max(f[k], f[(k + 1) % 3])), []).append(fi)
    out = 0
    for (a, b), fs in ef.items():
        if len(fs) != 2 or not region([verts[a], verts[b]]):
            continue
        d = sum(norm[fs[0]][i] * norm[fs[1]][i] for i in range(3))
        if math.degrees(math.acos(max(-1.0, min(1.0, d)))) > limit:
            out += 1
    return out


def main():
    jo, po = load(OLD)
    jn, pn = load(NEW)
    cpo, cio, cto = po(0)
    cpn, cin, ctn = pn(0)
    print("collider identical:", cto == ctn, "(%d tris)" % len(ctn))
    print("material identical:", jo["materials"] == jn["materials"], jn["materials"][0]["pbrMetallicRoughness"]["baseColorFactor"])
    print("nodes identical:", jo["nodes"] == jn["nodes"], [n["name"] for n in jn["nodes"]])
    opos, oidx, otris = po(1)
    npos, nidx, ntris = pn(1)
    shaft = lambda t: all(c[sorted(["COLOR_0", "NORMAL", "POSITION", "TEXCOORD_0"]).index("POSITION")][1] <= SEAM_Z for c in t)
    old_keep = [t for t in otris if shaft(t)]
    new_set = set(ntris)
    print("shaft tris outside the cleaned region: %d, present byte-identical in the new mesh: %d"
          % (len(old_keep), sum(t in new_set for t in old_keep)))
    for name, (pos, idx) in (("old", (opos, oidx)), ("new", (npos, nidx))):
        verts, faces, t = topo(pos, idx)
        top = lambda P: max(p[1] for p in P) > SEAM_Z
        q = quality(verts, faces, top)
        cr = creases(verts, faces, top, 100.0)
        print("%s mesh: tris=%d %s" % (name, len(faces), " ".join("%s=%d" % kv for kv in t.items())))
        print("%s crown (above the seam): %s creases_gt100deg=%d" % (name, " ".join("%s=%s" % kv for kv in q.items()), cr))


if __name__ == "__main__":
    sys.exit(main())
