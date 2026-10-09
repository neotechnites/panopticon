"""beach_broadleaf -- the forest's loose tree (forest_tree_prop) at a reduced spec, grown into the beach's Mesh.
Trunk and limb sockets are the forest's own builders; zones "tbark"/"tleaf" wear forest_bark/forest_sun, box-tiled."""

import math
import os
import sys

_HOME = os.path.dirname(os.path.abspath(__file__))
if _HOME not in sys.path:
    sys.path.insert(0, _HOME)
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d and d not in sys.path]
        break

import forest_tree_build as ft  # noqa: E402  the forest's mesh library and tiles
import forest_tree_prop_build as ftp  # noqa: E402  the forest's loose tree: trunk, patches, collars

# zone -> (forest zone, COLOR_0): the forest's TILES factor for that zone, carried per vertex
ZONES = {"bark": ("tbark", tuple(ft.TILES["bark"][1]) + (1.0,)),
         "leaf": ("tleaf", tuple(ft.TILES["leaf"][1]) + (1.0,))}
CROWN_MIN_Z = 3.0      # the forest prop's rule (the beach asks 2.5): the guard's look passes under
SEED = 6630127

# The forest prop's variant "a" cut down. out/up/r/clump as ftp._limb; bez = limb bends after the collar,
# lats = the leaf ball's rings (the forest's clump_end is (-35, 5, 40, 68)).
SPECS = {
    "near": {
        "sides": 6,
        "path": [(0.00, 0.00, -0.35), (0.00, 0.00, 0.00), (0.03, 0.01, 1.40),
                 (0.10, 0.00, 3.00), (0.18, -0.04, 4.40), (0.26, -0.07, 5.90)],
        "radii": [0.62, 0.48, 0.43, 0.38, 0.31, 0.23],
        "limbs": [ftp._limb(None, 3, 30.0, 0.90, 0.95, (0.17, 0.10), (1.10, 0.30), sides=4),
                  ftp._limb(None, 4, 150.0, 0.95, 0.85, (0.16, 0.10), (1.15, 0.30), sides=4),
                  ftp._limb(None, 4, 270.0, 0.85, 1.00, (0.15, 0.09), (1.05, 0.30), sides=4)],
        "top_clump": (1.45, 0.95),
        "bez": 1, "lats": (-35.0, 5.0, 40.0, 68.0), "cap": True,
    },
    "far": {
        "sides": 5,
        "path": [(0.00, 0.00, -0.35), (0.00, 0.00, 0.00), (0.08, 0.00, 2.90), (0.26, -0.07, 5.90)],
        "radii": [0.62, 0.47, 0.37, 0.23],
        "limbs": [ftp._limb(None, 2, 60.0, 0.90, 0.95, (0.17, 0.10), (1.20, 0.30), sides=4),
                  ftp._limb(None, 2, 240.0, 0.90, 0.90, (0.16, 0.10), (1.20, 0.30), sides=4)],
        "top_clump": (1.55, 0.95),
        "bez": 1, "lats": (-15.0, 40.0), "cap": False,
    },
}
WOB = 0.055
ANG_JAG = 0.05
Z_JAG = 0.05
CLUMP_WOB = 0.16
BEARING_JIT = 20.0     # degrees each limb may swing off its spec bearing, per tree
SIZE_JIT = 0.08        # share each limb's reach and leaf ball may vary, per tree


def _seed(x, y):
    """Deterministic per-tree seed from the foot's position (cm lattice)."""
    i, j = int(round(x * 100.0)), int(round(y * 100.0))
    n = (i * 73856093 ^ j * 19349663 ^ SEED) & 0x7FFFFFFF
    return n or 1


def _clump_end(m, last_ring, centre, radius, zone, rng, lats, squash=0.75, wob=0.25):
    """forest_tree_build.clump_end with its latitude rings as a parameter (fewer rings far off)."""
    segs = len(last_ring)
    rings = [list(last_ring)]
    for lat in lats:
        ring = []
        cl, sl = math.cos(math.radians(lat)), math.sin(math.radians(lat))
        for s in range(segs):
            a = 2.0 * math.pi * s / segs + rng.f() * 0.25
            rr = radius * (1.0 + wob * rng.sf())
            ring.append(m.v((centre[0] + rr * cl * math.cos(a), centre[1] + rr * cl * math.sin(a),
                             centre[2] + rr * sl * squash)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(segs):
            q = (s + 1) % segs
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], ft.sub(m.centroid(idx), centre), zone)
    top = m.v((centre[0], centre[1], centre[2] + radius * squash * (1.0 + wob * rng.sf())))
    for s in range(segs):
        q = (s + 1) % segs
        m.tri(top, rings[-1][s], rings[-1][q], ft.sub(m.centroid((top, rings[-1][s], rings[-1][q])), centre), zone)


def _cyclic(m, ring, centre):
    """A tube's end ring in its own cyclic order, turned ccw about +Z and started at its least azimuth: a tilted
    4-gon sorted by raw azimuth (ftp._by_azimuth) can cross itself."""
    ring = list(ring)
    if ftp._newell([m.verts[v] for v in ring])[2] < 0.0:
        ring.reverse()
    az = [math.atan2(m.verts[v][1] - centre[1], m.verts[v][0] - centre[0]) % (2.0 * math.pi) for v in ring]
    k = az.index(min(az))
    return ring[k:] + ring[:k]


def _spec(variant, seed):
    """The variant's spec with this tree's own limb bearings and sizes."""
    base = SPECS[variant]
    r = ft._Rng(seed ^ 0x2545F49)
    limbs = []
    for lb in base["limbs"]:
        k = 1.0 + SIZE_JIT * r.sf()
        limbs.append(dict(lb, bearing=lb["bearing"] + BEARING_JIT * r.sf(), out=lb["out"] * k,
                          clump=(lb["clump"][0] * (1.0 + SIZE_JIT * r.sf()), lb["clump"][1])))
    return dict(base, seed=seed, limbs=limbs, wob=WOB, ang_jag=ANG_JAG, z_jag=Z_JAG, clump_wob=CLUMP_WOB)


def grow(variant, seed):
    """The tree at the origin, unit scale, as a compacted forest _Mesh; returns (mesh, crown_lowest_z)."""
    spec = _spec(variant, seed)
    rng = ft._Rng(seed)
    m = ft._Mesh()
    trunk = ftp.build_trunk(m, rng, spec)
    if not spec["cap"]:                      # the far tree's foot is buried: drop the forest's cap fan
        n = spec["sides"]
        for fi in range(len(m.faces) - n, len(m.faces)):
            m.faces[fi] = None
            m.zones[fi] = None
    first_v = len(m.verts)
    for limb in spec["limbs"]:                # ftp.build_crown, its bezier count and leaf rings cut down
        bands, count = limb["patch"]
        quads, root, plane_n = ftp._patch(m, trunk["rings"], limb["band"], bands, count, limb["bearing"])
        d = ftp._dir_of(limb["bearing"])
        elbow = ft.add(root, d, limb["out"])
        tip = (elbow[0], elbow[1], elbow[2] + limb["up"])
        collar = ft.add(root, plane_n, ftp.STUB * limb["r"][0])
        path = [root, collar] + ft.bez(collar, elbow, tip, spec["bez"])[1:]
        flat = ftp._collar(m, quads, limb["bearing"], root, limb["r"][0])
        ring0 = ft.socket_ring(m, quads, path, limb["r"][0], limb["sides"], "bark", flat=flat, at_start=True)
        rings = ft.tube(m, path, tuple(limb["r"]), limb["sides"], "bark", caps=(False, False),
                        wob=spec["wob"], rng=rng, first_ring=ring0)
        centre = ft.add(path[-1], ft.frames(path)[-1][0], limb["clump"][1])
        _clump_end(m, _cyclic(m, rings[-1], centre), centre, limb["clump"][0], "leaf", rng,
                   spec["lats"], wob=spec["clump_wob"])
    tc = trunk["top_centre"]
    top = (tc[0], tc[1], tc[2] + spec["top_clump"][1])
    _clump_end(m, ftp._by_azimuth(m, trunk["top_ring"], top), top, spec["top_clump"][0], "leaf", rng,
               spec["lats"], wob=spec["clump_wob"])
    lowest = min(p[2] for p in m.verts[first_v:])
    assert lowest >= CROWN_MIN_Z - 1e-9, "crown at z=%.2f, below %.1f" % (lowest, CROWN_MIN_Z)
    return m.compact(), lowest


def broadleaf(m, uv, x, y, z, yaw_deg, scale, variant, chunk):
    """One tree into beach_lib.Mesh m, foot at (x, y, z), yaw_deg ccw about +Z; uv untouched (box-tiled Sheets)."""
    fm, _low = grow(variant, _seed(x, y))
    c, s = math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))
    ids = {}
    n0 = len(m.faces)
    for f, zone in zip(fm.faces, fm.zones):
        name, col = ZONES[zone]
        g = []
        for vi in f:
            key = (vi, zone)                  # a ring shared by bark and leaf is split: COLOR_0 is per zone
            if key not in ids:
                px, py, pz = fm.verts[vi]
                ids[key] = m.v((x + scale * (c * px - s * py), y + scale * (s * px + c * py), z + scale * pz), col)
            g.append(ids[key])
        m.tri_as(g[0], g[1], g[2], name, chunk)
    return len(m.faces) - n0


def _check():
    import beach_lib as il
    for variant in ("near", "far"):
        m = il.Mesh()
        for k in range(3):
            x, y = 7.3 * k - 4.1, 2.9 * k + 1.7
            n = broadleaf(m, {}, x, y, 0.5, 40.0 * k, 1.0, variant, "trees")
            fm, low = grow(variant, _seed(x, y))
            zs = [p[2] for p in fm.verts]
            crown_r = max(math.hypot(p[0], p[1]) for p in fm.verts)
            print("%s tree %d tris=%d height=%.2f crown_low=%.2f crown_r=%.2f"
                  % (variant, k, n, max(zs), low, crown_r))
        il.report(m, "beach_broadleaf_" + variant)
        xs, ys, zs = zip(*m.verts)
        print("%s bbox x=%.2f..%.2f y=%.2f..%.2f z=%.2f..%.2f"
              % (variant, min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))


if __name__ == "__main__":
    if "--check" in sys.argv:
        _check()
