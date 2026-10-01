"""speed_orb -- the race power-up: a fist-sized ember/soul orb, floating.

A faceted icosahedron (20 tris) so the geometry itself reads as a cracked
shell; the atlas draws each facet as a bright emissive ember core scarred by
dark, non-emissive crack lines. Origin at the centre -- it is a pickup a
script spins and bobs about its own middle, not a floor object.

Contract: one mesh "SpeedOrb" (one surface, one UV set). NO collision -- the
pickup script (scripts/match/speed_powerup.gd) owns its own trigger volume.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import mdl  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================
NAME = "speed_orb"
OBJECT_NAME = "SpeedOrb"

RADIUS = 0.05              # 10 cm diameter: fist-sized

TEX_SIZE = 64
TEX_SEED = 5551212
UV_SCALE = 12.0             # face edges (~0.055 m) fill most of the atlas
UV_PAD = 1.5 / TEX_SIZE
ROUGHNESS = 0.65
METALLIC = 0.0

FACING_YAW = 0.0

# =============================================================================
# GEOMETRY -- a regular icosahedron; the "want" normal is each face's own
# centroid direction, since the shape is convex and centred on the origin.
# =============================================================================

_PHI = (1.0 + 5.0 ** 0.5) / 2.0

_RAW_VERTS = [
    (-1.0, _PHI, 0.0), (1.0, _PHI, 0.0), (-1.0, -_PHI, 0.0), (1.0, -_PHI, 0.0),
    (0.0, -1.0, _PHI), (0.0, 1.0, _PHI), (0.0, -1.0, -_PHI), (0.0, 1.0, -_PHI),
    (_PHI, 0.0, -1.0), (_PHI, 0.0, 1.0), (-_PHI, 0.0, -1.0), (-_PHI, 0.0, 1.0),
]

FACES = [
    (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
    (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
    (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
    (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
]


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


class _Mesh(object):
    """Faces carry an atlas zone; winding is fixed against a wanted normal."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.zones = []

    def v(self, p):
        self.verts.append(tuple(p))
        return len(self.verts) - 1

    def tri(self, a, b, c, want, zone):
        idx = [a, b, c]
        pts = [self.verts[j] for j in idx]
        n = _newell(pts)
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            idx = list(reversed(idx))
        self.faces.append(tuple(idx))
        self.zones.append(zone)

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


def _build_shell():
    m = _Mesh()
    verts = [tuple(c * RADIUS / math.sqrt(1.0 + _PHI * _PHI) for c in v) for v in _RAW_VERTS]
    idx = [m.v(v) for v in verts]
    zone = (0.0, 0.0, 1.0, 1.0)
    for a, b, c in FACES:
        centroid = tuple((verts[a][i] + verts[b][i] + verts[c][i]) / 3.0 for i in range(3))
        m.tri(idx[a], idx[b], idx[c], centroid, zone)
    return m


# =============================================================================
# TEXTURE -- speed_orb_albedo.png, glowing its own albedo
# =============================================================================

class _Rng(object):
    """Tiny deterministic LCG so the model is byte-identical every rebuild."""

    def __init__(self, seed):
        self.s = seed & 0xFFFFFFFF

    def n(self):
        self.s = (1664525 * self.s + 1013904223) & 0xFFFFFFFF
        return self.s

    def f(self):
        return self.n() / 4294967296.0

    def i(self, a, b):
        return a + int(self.f() * (b - a + 1))


def ember_material(name, albedo, emissive):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    for img, socket, y in ((albedo, "Base Color", 260), (emissive, "Emission Color", -220)):
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.interpolation = "Closest"
        node.location = (-460, y)
        nt.links.new(node.outputs["Color"], bsdf.inputs[socket])
    bsdf.inputs["Roughness"].default_value = ROUGHNESS
    bsdf.inputs["Metallic"].default_value = METALLIC
    bsdf.inputs["Emission Strength"].default_value = 1.0  # no KHR extension, no Godot warning
    mat.diffuse_color = (0.6, 0.25, 0.05, 1.0)
    return mat


def unwrap(ob, zones):
    """Per-face planar projection into a random window of the shared zone --
    tower_build.py's scheme, trimmed to the one zone this orb needs."""
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + 7919 + len(me.polygons))
    for pi, poly in enumerate(me.polygons):
        u0, v0, u1, v1 = zones[pi]
        span_u = (u1 - u0) - 2.0 * UV_PAD
        span_v = (v1 - v0) - 2.0 * UV_PAD
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        nrm = poly.normal
        ax = max(range(3), key=lambda i: abs(nrm[i]))
        ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
        fu = -1.0 if r.i(0, 1) else 1.0
        fv = -1.0 if r.i(0, 1) else 1.0
        mi = min(co[ii] for co in cos)
        mj = min(co[jj] for co in cos)
        w = min((max(co[ii] for co in cos) - mi) * UV_SCALE, 1.0)
        h = min((max(co[jj] for co in cos) - mj) * UV_SCALE, 1.0)
        ou = r.f() * (1.0 - w)
        ov = r.f() * (1.0 - h)
        for li, co in zip(poly.loop_indices, cos):
            s = min(ou + (co[ii] - mi) * UV_SCALE, 1.0)
            t = min(ov + (co[jj] - mj) * UV_SCALE, 1.0)
            if fu < 0.0:
                s = 1.0 - s
            if fv < 0.0:
                t = 1.0 - t
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)


def build():
    shell = _build_shell()
    albedo = mdl.texture(NAME + "_albedo")

    ob = shell.object(OBJECT_NAME)
    unwrap(ob, shell.zones)
    # one file: the ember glows its own albedo (the soot differs by <= 4/255)
    mdl.finish(ob, ember_material("SpeedOrb", albedo, albedo), strip_uvs=False)

    print("MDL STATS visual_tris=%d" % len(ob.data.polygons))
    print("MDL STATS diameter=%.3f" % (2.0 * RADIUS))
    return [ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
