"""Shared by Map 4's builds: the welding face accumulator, its contiguity audit, the ice sheets.
Blender +Z is Godot +Y; a game bearing of b degrees is Blender angle -b."""

import math

try:
    import bpy
except ImportError:                       # --check on the Mac: geometry only
    bpy = None

TEX_PX = 128            # texels per side of every ice sheet: 6.4 m at texel.MPT (20 px/m)
DOME_ALPHA = 0.83       # the roof's opacity: the sky shows faintly through (glTF BLEND, blend_mix)
WELD = 1.0e-4
TWO_PI = 2.0 * math.pi


def _newell(pts):
    nx = ny = nz = 0.0
    for i in range(len(pts)):
        ax, ay, az = pts[i]
        bx, by, bz = pts[(i + 1) % len(pts)]
        nx += (ay - by) * (az + bz)
        ny += (az - bz) * (ax + bx)
        nz += (ax - bx) * (ay + by)
    return (nx, ny, nz)


class Mesh(object):
    """Face accumulator: welds by position, and every face states which way its normal points."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.zones = []
        self._index = {}

    def v(self, p):
        key = (round(p[0] / WELD), round(p[1] / WELD), round(p[2] / WELD))
        i = self._index.get(key)
        if i is None:
            i = len(self.verts)
            self.verts.append((float(p[0]), float(p[1]), float(p[2])))
            self._index[key] = i
        return i

    def face(self, idx, want, zone):
        n = _newell([self.verts[j] for j in idx])
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            idx = list(reversed(idx))
        for k in range(1, len(idx) - 1):
            self.faces.append((idx[0], idx[k], idx[k + 1]))
            self.zones.append(zone)

    def object(self, name):
        import mdl
        return mdl.mesh(name, self.verts, self.faces)


def audit(m):
    """components, boundary edges, edges on more than two faces, degenerate faces, duplicate positions."""
    edges = {}
    for f in m.faces:
        for k in range(3):
            a, b = f[k], f[(k + 1) % 3]
            e = (a, b) if a < b else (b, a)
            edges[e] = edges.get(e, 0) + 1
    parent = list(range(len(m.verts)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for (a, b) in edges:
        parent[find(a)] = find(b)
    used = {i for f in m.faces for i in f}
    degen = 0
    for f in m.faces:
        n = _newell([m.verts[i] for i in f])
        if math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) < 1.0e-8:
            degen += 1
    pos = {(round(x, 5), round(y, 5), round(z, 5)) for (x, y, z) in m.verts}
    return {"components": len({find(i) for i in used}),
            "boundary": sum(1 for c in edges.values() if c == 1),
            "over": sum(1 for c in edges.values() if c > 2),
            "degenerate": degen,
            "dup_pos": len(m.verts) - len(pos),
            "tris": len(m.faces)}


def sheet(tx, cls, **kw):
    """A Sheet on maps/ice/textures/ice_<cls>_albedo.png ("ice" is ice_albedo.png), 20 px/m."""
    stem = "ice" if cls == "ice" else "ice_" + cls
    return tx.Sheet(cls, size=TEX_PX, stem=stem, **kw)


def see_through(mat, alpha):
    """Alpha-blended (glTF BLEND -> Godot blend_mix), front faces only."""
    mat.node_tree.nodes.get("Principled BSDF").inputs["Alpha"].default_value = alpha
    mat.blend_method = "BLEND"
    if hasattr(mat, "surface_render_method"):
        mat.surface_render_method = "BLENDED"
    mat.show_transparent_back = False
    mat.use_backface_culling = True
