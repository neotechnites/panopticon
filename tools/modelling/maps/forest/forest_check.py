"""Contiguity proof for the forest meshes (Mac side, --check only).

prove(mesh, name) prints one line of numbers: connected components over
shared vertex ids, vertices that share a position without sharing an id
(duplicates at seams), edges with more than two faces (non-manifold),
edges with one face (open: ceiling gaps, tube caps, fern sheets),
degenerate and sliver faces. Returns the dict. A contiguous model is
components=1 and duplicates=0.
"""

import math


def _newell(pts):
    nx = ny = nz = 0.0
    n = len(pts)
    for i in range(n):
        ax, ay, az = pts[i]
        bx, by, bz = pts[(i + 1) % n]
        nx += (ay - by) * (az + bz)
        ny += (az - bz) * (ax + bx)
        nz += (ax - bx) * (ay + by)
    return (nx, ny, nz)


def _min_angle(pts):
    out = math.pi
    for k in range(3):
        p, q, r = pts[k], pts[(k + 1) % 3], pts[(k + 2) % 3]
        u = (q[0] - p[0], q[1] - p[1], q[2] - p[2])
        v = (r[0] - p[0], r[1] - p[1], r[2] - p[2])
        lu = math.sqrt(sum(x * x for x in u))
        lv = math.sqrt(sum(x * x for x in v))
        if lu < 1e-12 or lv < 1e-12:
            return 0.0
        d = sum(u[i] * v[i] for i in range(3)) / (lu * lv)
        out = min(out, math.acos(max(-1.0, min(1.0, d))))
    return out


def prove(m, name, sliver_deg=3.0, quiet=False):
    faces = [f for f in m.faces if f is not None]
    nv = len(m.verts)
    parent = list(range(nv))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    used = [False] * nv
    edges = {}
    degen = sliver = 0
    for f in faces:
        pts = [m.verts[i] for i in f]
        n = _newell(pts)
        if math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) < 1e-9:
            degen += 1
        elif _min_angle(pts) < math.radians(sliver_deg):
            sliver += 1
        for k in range(3):
            a, b = f[k], f[(k + 1) % 3]
            used[a] = True
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[ra] = rb
            e = (a, b) if a < b else (b, a)
            edges[e] = edges.get(e, 0) + 1
    roots = set(find(i) for i in range(nv) if used[i])
    unused = sum(1 for u in used if not u)
    bypos = {}
    for i, p in enumerate(m.verts):
        if not used[i]:
            continue
        key = (round(p[0], 5), round(p[1], 5), round(p[2], 5))
        bypos.setdefault(key, []).append(i)
    dups = sum(len(v) - 1 for v in bypos.values() if len(v) > 1)
    nonman = sum(1 for c in edges.values() if c > 2)
    open_e = sum(1 for c in edges.values() if c == 1)
    comp_sizes = {}
    for i in range(nv):
        if used[i]:
            r = find(i)
            comp_sizes[r] = comp_sizes.get(r, 0) + 1
    biggest = max(comp_sizes.values()) if comp_sizes else 0
    out = {"tris": len(faces), "verts": nv - unused, "components": len(roots),
           "biggest_component_verts": biggest, "duplicate_positions": dups,
           "nonmanifold_edges": nonman, "open_edges": open_e, "degenerate": degen,
           "slivers": sliver, "unused_verts": unused}
    if not quiet:
        print("PROVE %s tris=%d verts=%d components=%d (biggest %d verts) duplicate_positions=%d "
              "nonmanifold_edges=%d open_edges=%d degenerate=%d slivers(<%.0fdeg)=%d unused_verts=%d"
              % (name, out["tris"], out["verts"], out["components"], biggest, dups, nonman,
                 open_e, degen, sliver_deg, sliver, unused))
    return out


def components_report(m, top=6):
    """The largest few islands, with a sample vertex each: what is not welded."""
    faces = [f for f in m.faces if f is not None]
    nv = len(m.verts)
    parent = list(range(nv))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for f in faces:
        for k in range(3):
            ra, rb = find(f[k]), find(f[(k + 1) % 3])
            if ra != rb:
                parent[ra] = rb
    zones = {}
    sizes = {}
    for fi, f in enumerate(faces):
        r = find(f[0])
        sizes[r] = sizes.get(r, 0) + 1
        z = m.zones[fi] if fi < len(m.zones) else "?"
        zones.setdefault(r, {}).setdefault(z, 0)
        zones[r][z] += 1
    order = sorted(sizes, key=lambda r: -sizes[r])
    print("PROVE islands=%d" % len(order))
    for r in order[:top]:
        p = m.verts[r]
        print("  island faces=%d at (%.1f, %.1f, %.1f) zones=%s" % (sizes[r], p[0], p[1], p[2], zones[r]))
    small = [r for r in order if sizes[r] < 200]
    if small:
        z = {}
        for r in small:
            for k, v in zones[r].items():
                z[k] = z.get(k, 0) + v
        print("  %d small islands (<200 faces), zones=%s" % (len(small), z))
