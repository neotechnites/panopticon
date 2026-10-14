"""beach_shore -- Wuhu's lighthouse, at true player scale (the shore strip's bar, cabanas, torches,
lifeguard tower and boardwalk were struck -- see beach-declutter2). Box-projected zones only (no uv)."""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beach_lib import Mesh, Rng, report  # noqa: E402
from beach_buildings import Frame, STONE, CHUNK, TILE, TEXTURED  # noqa: E402,F401

ZONES = ("plastic", "ashlar")
assert not set(ZONES) & set(TEXTURED)
RED = (0.85, 0.15, 0.12, 1.0)
LH_WHITE = (0.96, 0.96, 0.94, 1.0)
GLASS = (0.2, 0.25, 0.35, 1.0)
DOOR = (0.28, 0.2, 0.14, 1.0)
CANVAS_TINTS = ((1.0, 1.0, 1.0, 1.0), (1.0, 0.95, 0.85, 1.0), (0.9, 0.96, 1.0, 1.0))
ACCENTS = ((0.86, 0.2, 0.18, 1.0), (0.18, 0.42, 0.8, 1.0), (0.98, 0.8, 0.22, 1.0), (0.24, 0.66, 0.38, 1.0))


def _neg(v):
    return tuple(-c for c in v)


def _prism(fr, cf, cs, r0, r1, n, z0, z1, zone, col, rot=0.0, top=False, bottom=False, inward=False):
    """An n-gon prism or frustum (r1 = 0: a cone) about (cf, cs), vertices at rot + k * 360 / n."""
    ang = [math.radians(rot + k * 360.0 / n) for k in range(n)]
    lo = [(cf + r0 * math.cos(a), cs + r0 * math.sin(a), z0) for a in ang]
    hi = [(cf + r1 * math.cos(a), cs + r1 * math.sin(a), z1) for a in ang]
    sg = -1.0 if inward else 1.0
    for k in range(n):
        j = (k + 1) % n
        am = math.radians(rot + (k + 0.5) * 360.0 / n)
        out = (sg * math.cos(am), sg * math.sin(am), 0.0)
        if r1 < 1e-6:
            fr.poly([lo[k], lo[j], (cf, cs, z1)], out, zone, col)
        else:
            fr.poly([lo[k], lo[j], hi[j], hi[k]], out, zone, col)
    for flag, ring, out in ((top, hi, (0, 0, 1)), (bottom, lo, (0, 0, -1))):
        if flag:
            for k in range(1, n - 1):
                fr.poly([ring[0], ring[k], ring[k + 1]], out, zone, col)


def _annulus(fr, ri, ro, n, z, out, zone, col, rot=0.0):
    ang = [math.radians(rot + k * 360.0 / n) for k in range(n)]
    for k in range(n):
        a, b = ang[k], ang[(k + 1) % n]
        fr.poly([(ri * math.cos(a), ri * math.sin(a), z), (ro * math.cos(a), ro * math.sin(a), z),
                 (ro * math.cos(b), ro * math.sin(b), z), (ri * math.cos(b), ri * math.sin(b), z)], out, zone, col)


# =============================================================================
# PIECES
# =============================================================================

def _facet(fr, a0, a1, rz, z_lo, z_hi, holes, col):
    """One tower facet between bearings a0, a1 (deg) of radius rz(z), cut round holes (z0, z1, width, dark)
    recessed 0.1 m."""
    c0 = (math.cos(math.radians(a0)), math.sin(math.radians(a0)))
    c1 = (math.cos(math.radians(a1)), math.sin(math.radians(a1)))
    am = math.radians((a0 + a1) / 2.0)
    out = (math.cos(am), math.sin(am), 0.0)
    tg = (c1[0] - c0[0], c1[1] - c0[1], 0.0)
    P = fr.poly

    def at(t, z, d=0.0):
        r = rz(z)
        return (((1 - t) * c0[0] + t * c1[0]) * r - out[0] * d, ((1 - t) * c0[1] + t * c1[1]) * r - out[1] * d, z)
    cur = z_lo
    for hz0, hz1, w, dark in sorted(holes):
        if hz0 > cur:
            P([at(0, cur), at(1, cur), at(1, hz0), at(0, hz0)], out, "plastic", col)
        wd = math.dist(at(0, (hz0 + hz1) / 2), at(1, (hz0 + hz1) / 2))
        t0, t1 = 0.5 - w / (2 * wd), 0.5 + w / (2 * wd)
        P([at(0, hz0), at(t0, hz0), at(t0, hz1), at(0, hz1)], out, "plastic", col)
        P([at(t1, hz0), at(1, hz0), at(1, hz1), at(t1, hz1)], out, "plastic", col)
        P([at(t0, hz0, 0.1), at(t1, hz0, 0.1), at(t1, hz1, 0.1), at(t0, hz1, 0.1)], out, "plastic", dark)
        P([at(t0, hz0), at(t0, hz0, 0.1), at(t0, hz1, 0.1), at(t0, hz1)], tg, "plastic", col)
        P([at(t1, hz0), at(t1, hz0, 0.1), at(t1, hz1, 0.1), at(t1, hz1)], _neg(tg), "plastic", col)
        P([at(t0, hz1), at(t0, hz1, 0.1), at(t1, hz1, 0.1), at(t1, hz1)], (0, 0, -1), "plastic", col)
        P([at(t0, hz0), at(t0, hz0, 0.1), at(t1, hz0, 0.1), at(t1, hz0)], (0, 0, 1), "plastic", col)
        cur = hz1
    if cur < z_hi:
        P([at(0, cur), at(1, cur), at(1, z_hi), at(0, z_hi)], out, "plastic", col)


def lighthouse(m, uv, x, y, z0, h=25.0, plinth=1.1, step=1.0):
    """Wuhu's lighthouse: a wide ashlar foundation step (r 4.6, `step` tall) and plinth (r 3.6, to `plinth`) from
    z0, the tapered white 12-sided tower on the plinth's top, door and two slits on +f, a railed gallery, a glazed
    lantern, a red cap and finial. The caller sets z0 under the lowest terrain corner and plinth over the highest."""
    fr, n0 = Frame(m, uv, x, y, 0.0, z0), len(m.faces)
    zt, rb, rt, n = 0.8 * h, 3.2, 2.2, 12
    _prism(fr, 0.0, 0.0, 4.6, 4.6, n, 0.0, step, "ashlar", STONE, rot=15.0)
    _annulus(fr, 3.6, 4.6, n, step, (0, 0, 1), "ashlar", STONE, rot=15.0)
    if plinth > step + 0.05:
        _prism(fr, 0.0, 0.0, 3.6, 3.6, n, step, plinth, "ashlar", STONE, rot=15.0)
    _annulus(fr, rb, 3.6, n, plinth, (0, 0, 1), "ashlar", STONE, rot=15.0)
    ft = Frame(m, uv, x, y, 0.0, z0 + plinth)                   # the tower's own frame: its foot at the plinth's top

    def rz(z):
        return rb + (rt - rb) * z / zt
    for k in range(n):
        holes = ()
        if k == 0:
            holes = ((0.0, 2.1, 1.2, DOOR), (0.38 * h, 0.38 * h + 1.4, 0.5, GLASS), (0.6 * h, 0.6 * h + 1.4, 0.5, GLASS))
        _facet(ft, 30.0 * k - 15.0, 30.0 * k + 15.0, rz, 0.0, zt, holes, LH_WHITE)
    zg = zt + 0.3
    _prism(ft, 0.0, 0.0, 3.0, 3.0, n, zt, zg, "plastic", LH_WHITE, rot=15.0)
    _annulus(ft, rt, 3.0, n, zt, (0, 0, -1), "plastic", LH_WHITE, rot=15.0)
    _annulus(ft, 1.6, 3.0, n, zg, (0, 0, 1), "plastic", LH_WHITE, rot=15.0)
    for k in range(n):
        a = math.radians(15.0 + 30.0 * k)
        pf, ps = 2.88 * math.cos(a), 2.88 * math.sin(a)
        ft.box(pf - 0.05, pf + 0.05, ps - 0.05, ps + 0.05, zg, zg + 1.0, "plastic", LH_WHITE, "fblt")
    zr = zg + 1.0
    _prism(ft, 0.0, 0.0, 2.92, 2.92, n, zr, zr + 0.08, "plastic", LH_WHITE, rot=15.0)
    _prism(ft, 0.0, 0.0, 2.84, 2.84, n, zr, zr + 0.08, "plastic", LH_WHITE, rot=15.0, inward=True)
    _annulus(ft, 2.84, 2.92, n, zr + 0.08, (0, 0, 1), "plastic", LH_WHITE, rot=15.0)
    _annulus(ft, 2.84, 2.92, n, zr, (0, 0, -1), "plastic", LH_WHITE, rot=15.0)
    zl = zg + 0.12 * h
    for k in range(n):
        a0, a1 = 30.0 * k - 15.0, 30.0 * k + 15.0
        c0 = (1.6 * math.cos(math.radians(a0)), 1.6 * math.sin(math.radians(a0)))
        c1 = (1.6 * math.cos(math.radians(a1)), 1.6 * math.sin(math.radians(a1)))
        out = (math.cos(math.radians(30.0 * k)), math.sin(math.radians(30.0 * k)), 0.0)

        def q(t0, t1, z0_, z1_, col):
            p0 = (c0[0] + (c1[0] - c0[0]) * t0, c0[1] + (c1[1] - c0[1]) * t0)
            p1 = (c0[0] + (c1[0] - c0[0]) * t1, c0[1] + (c1[1] - c0[1]) * t1)
            ft.poly([p0 + (z0_,), p1 + (z0_,), p1 + (z1_,), p0 + (z1_,)], out, "plastic", col)
        q(0.0, 1.0, zg, zg + 0.4, LH_WHITE)
        q(0.0, 1.0, zl - 0.25, zl, LH_WHITE)
        q(0.0, 0.12, zg + 0.4, zl - 0.25, LH_WHITE)
        q(0.12, 1.0, zg + 0.4, zl - 0.25, GLASS)
    zc = zl + 0.08 * h
    _prism(ft, 0.0, 0.0, 1.9, 0.0, n, zl, zc, "plastic", RED, rot=15.0, bottom=True)
    ft.box(-0.04, 0.04, -0.04, 0.04, zc - 0.2, zc + 0.6, "plastic", RED, "fblt")
    _prism(ft, 0.0, 0.0, 0.18, 0.0, 4, zc + 0.75, zc + 1.0, "plastic", RED)
    _prism(ft, 0.0, 0.0, 0.18, 0.0, 4, zc + 0.75, zc + 0.5, "plastic", RED)
    return len(m.faces) - n0


# =============================================================================
# CHECK
# =============================================================================

def _check():
    def bbox(m):
        vs = [m.verts[i] for f in m.faces for i in f]
        return (tuple(round(min(p[k] for p in vs), 2) for k in range(3)),
                tuple(round(max(p[k] for p in vs), 2) for k in range(3)))

    cases = [("lighthouse", 700, lambda m, uv: lighthouse(m, uv, 0.0, 0.0, 0.0))]
    for name, cap, build in cases:
        m, uv = Mesh(), {}
        n = build(m, uv)
        report(m, name)
        print("%s tris=%d bbox=%s" % (name, n, bbox(m)))
        assert n == len(m.faces) and n <= cap, (name, n, cap)
        assert not uv, name
        bad = set(m.zones) - set(ZONES)
        assert not bad, (name, bad)
        assert set(m.chunks) == {CHUNK}


if __name__ == "__main__":
    if "--check" in sys.argv:
        _check()
