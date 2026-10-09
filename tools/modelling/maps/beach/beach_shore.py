"""beach_shore -- the resort's shore strip at true player scale: tiki huts, a beach bar, cabanas, a boardwalk,
torches, a lifeguard tower and Wuhu's lighthouse. Box-projected zones only (no uv). Pure Python."""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beach_lib import Mesh, Rng, report  # noqa: E402
from beach_buildings import Frame, STONE, WHITE, CHUNK, TILE, TEXTURED  # noqa: E402,F401

ZONES = ("thatch2", "timber", "deck", "canvas2", "plastic", "ashlar")
assert not set(ZONES) & set(TEXTURED)
THATCH = (1.0, 0.97, 0.9, 1.0)
THATCH_UNDER = (0.72, 0.66, 0.56, 1.0)
BAMBOO = (1.0, 0.9, 0.7, 1.0)
STRIP = (0.88, 0.76, 0.54, 1.0)
POST = (0.86, 0.74, 0.6, 1.0)
DARK = (0.3, 0.25, 0.2, 1.0)
DECK = WHITE
PAINT = (0.95, 0.95, 0.9, 1.0)
FLAME = (1.0, 0.6, 0.15, 1.0)
SIGN = (0.95, 0.85, 0.55, 1.0)
RED = (0.85, 0.15, 0.12, 1.0)
LH_WHITE = (0.96, 0.96, 0.94, 1.0)
GLASS = (0.2, 0.25, 0.35, 1.0)
DOOR = (0.28, 0.2, 0.14, 1.0)
CANVAS_TINTS = ((1.0, 1.0, 1.0, 1.0), (1.0, 0.95, 0.85, 1.0), (0.9, 0.96, 1.0, 1.0))
ACCENTS = ((0.86, 0.2, 0.18, 1.0), (0.18, 0.42, 0.8, 1.0), (0.98, 0.8, 0.22, 1.0), (0.24, 0.66, 0.38, 1.0))
BOTTLES = ((0.2, 0.5, 0.25, 1.0), (0.45, 0.28, 0.12, 1.0), (0.3, 0.55, 0.75, 1.0))


def _neg(v):
    return tuple(-c for c in v)


def _shade(col, k):
    return (col[0] * k, col[1] * k, col[2] * k, 1.0)


def _two(fr, pts, out, zone, col, back=None):
    """A poly drawn from both sides (the back optionally shaded)."""
    fr.poly(pts, out, zone, col)
    fr.poly(list(reversed(pts)), _neg(out), zone, back or col)


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


def _beam(fr, a, b, w, h, zone, col, faces="lrud"):
    """A w x h beam from local point a to b: l/r its horizontal sides, u/d its top and bottom."""
    d = [b[k] - a[k] for k in range(3)]
    ln = math.sqrt(sum(c * c for c in d))
    du = [c / ln for c in d]
    sd = (du[1], -du[0], 0.0)
    sl = math.hypot(sd[0], sd[1])
    sd = (1.0, 0.0, 0.0) if sl < 1e-6 else (sd[0] / sl, sd[1] / sl, 0.0)
    up = (sd[1] * du[2] - sd[2] * du[1], sd[2] * du[0] - sd[0] * du[2], sd[0] * du[1] - sd[1] * du[0])

    def c(e, x, y):
        return tuple(e[k] + sd[k] * x * w / 2.0 + up[k] * y * h / 2.0 for k in range(3))
    for key, x0, y0, x1, y1, out in (("l", 1, -1, 1, 1, sd), ("r", -1, 1, -1, -1, _neg(sd)),
                                     ("u", 1, 1, -1, 1, up), ("d", -1, -1, 1, -1, _neg(up))):
        if key in faces:
            fr.poly([c(a, x0, y0), c(b, x0, y0), c(b, x1, y1), c(a, x1, y1)], out, zone, col)


def _thatch(fr, ef, es, ze, rise, rng, fringe=0.6):
    """A hip (pyramid when square) thatch roof over an eave rectangle ef x es at height ze: two stepped courses,
    the underside drawn, a ragged straw fringe. Returns the pitch."""
    pitch = rise / min(ef, es)
    rh, zr = abs(es - ef), ze + rise
    E = [(ef, -es, ze), (ef, es, ze), (-ef, es, ze), (-ef, -es, ze)]
    if es >= ef:
        Ra, Rb = (0.0, -rh, zr), (0.0, rh, zr)
        faces = ((0, Ra, Rb, (1, 0)), (1, Rb, Rb, (0, 1)), (2, Rb, Ra, (-1, 0)), (3, Ra, Ra, (0, -1)))
    else:
        Ra, Rb = (rh, 0.0, zr), (-rh, 0.0, zr)
        faces = ((0, Ra, Ra, (1, 0)), (1, Ra, Rb, (0, 1)), (2, Rb, Rb, (-1, 0)), (3, Rb, Ra, (0, -1)))

    def lerp(p, q, t):
        return tuple(p[k] + (q[k] - p[k]) * t for k in range(3))
    for k, r0, r1, h in faces:
        e0, e1 = E[k], E[(k + 1) % 4]
        out = (h[0], h[1], 1.0)
        nl = math.sqrt(pitch * pitch + 1.0)
        nrm = (h[0] * pitch / nl, h[1] * pitch / nl, 1.0 / nl)
        ts = (0.0, 0.5, 1.0)
        for i in range(2):
            lift = 0.0 if i == 0 else 0.07
            lo = [tuple(c + nrm[q] * lift for q, c in enumerate(lerp(e, r, ts[i]))) for e, r in ((e0, r0), (e1, r1))]
            t1 = ts[i + 1] + (0.05 if i == 0 else 0.0)
            hi = [lerp(e, r, t1) for e, r in ((e0, r0), (e1, r1))]
            if math.dist(hi[0], hi[1]) < 1e-6:
                fr.poly([lo[0], lo[1], hi[0]], out, "thatch2", THATCH)
            else:
                fr.poly([lo[0], lo[1], hi[1], hi[0]], out, "thatch2", THATCH)
        under = [e0, e1, r1] if r0 == r1 else [e0, e1, r1, r0]
        fr.poly(under, (-h[0], -h[1], -1.0), "thatch2", THATCH_UNDER)
        el = math.dist(e0, e1)
        steps = max(1, int(round(el / fringe)))
        for j in range(steps):
            p0, p1 = lerp(e0, e1, j / float(steps)), lerp(e0, e1, (j + 1) / float(steps))
            m = lerp(p0, p1, 0.5)
            tip = (m[0] + h[0] * 0.04, m[1] + h[1] * 0.04, m[2] - rng.u(0.2, 0.36))
            fr.poly([p0, p1, tip], (h[0], h[1], 0.0), "thatch2", THATCH)
    return pitch


def _strips(fr, p0, p1, out, zhi, gaps=()):
    """Vertical bamboo strips 0.12 m wide every 0.7 m, 0.03 m proud of the wall p0 -> p1 (f, s)."""
    ln = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
    u = ((p1[0] - p0[0]) / ln, (p1[1] - p0[1]) / ln)
    n = int((ln - 0.6) / 0.7)
    for i in range(n + 1):
        d = 0.3 + (ln - 0.6) * (i / float(n) if n else 0.5)
        if any(g0 - 0.1 < d < g1 + 0.1 for g0, g1 in gaps):
            continue
        cf, cs = p0[0] + u[0] * d + out[0] * 0.03, p0[1] + u[1] * d + out[1] * 0.03
        a, b = (cf - u[0] * 0.06, cs - u[1] * 0.06), (cf + u[0] * 0.06, cs + u[1] * 0.06)
        fr.poly([(a[0], a[1], -0.3), (b[0], b[1], -0.3), (b[0], b[1], zhi), (a[0], a[1], zhi)],
                (out[0], out[1], 0.0), "timber", STRIP)


# =============================================================================
# PIECES
# =============================================================================

def tiki_hut(m, uv, x, y, yaw, z0, seed):
    """A bamboo hut 5-7 m square, open doorway on +f into a dark vestibule, thatched hip or pyramid roof."""
    fr, r, n0 = Frame(m, uv, x, y, yaw, z0), Rng(seed * 7919 + 11), len(m.faces)
    if r.f() < 0.5:
        hf = r.u(2.5, 3.0)
        hs = hf + r.u(0.4, 0.5)
    else:
        hf = hs = r.u(2.5, 3.5)
    rise, eave = r.u(1.6, 2.2), 0.7
    ds = r.u(-0.4, 0.4) * (hs - 1.2)
    pitch = _thatch(fr, hf + eave, hs + eave, 2.4, rise, r)
    zw = 2.4 + pitch * eave                        # walls rise to the roof's underside at the wall line
    P = fr.poly
    P([(-hf, hs, -0.5), (-hf, -hs, -0.5), (-hf, -hs, zw), (-hf, hs, zw)], (-1, 0, 0), "timber", BAMBOO)
    for sg in (-1, 1):
        P([(-hf, sg * hs, -0.5), (hf, sg * hs, -0.5), (hf, sg * hs, zw), (-hf, sg * hs, zw)], (0, sg, 0), "timber", BAMBOO)
    d0, d1 = ds - 0.6, ds + 0.6
    P([(hf, -hs, -0.5), (hf, d0, -0.5), (hf, d0, zw), (hf, -hs, zw)], (1, 0, 0), "timber", BAMBOO)
    P([(hf, d1, -0.5), (hf, hs, -0.5), (hf, hs, zw), (hf, d1, zw)], (1, 0, 0), "timber", BAMBOO)
    P([(hf, d0, 2.1), (hf, d1, 2.1), (hf, d1, zw), (hf, d0, zw)], (1, 0, 0), "timber", BAMBOO)
    fi = hf - 1.0                                   # the dark vestibule a metre inside
    P([(fi, d0, -0.5), (fi, d1, -0.5), (fi, d1, 2.1), (fi, d0, 2.1)], (1, 0, 0), "timber", DARK)
    P([(fi, d0, -0.5), (hf, d0, -0.5), (hf, d0, 2.1), (fi, d0, 2.1)], (0, 1, 0), "timber", DARK)
    P([(fi, d1, -0.5), (hf, d1, -0.5), (hf, d1, 2.1), (fi, d1, 2.1)], (0, -1, 0), "timber", DARK)
    P([(fi, d0, 2.1), (hf, d0, 2.1), (hf, d1, 2.1), (fi, d1, 2.1)], (0, 0, -1), "timber", DARK)
    for a in (-hf, hf):
        for b in (-hs, hs):
            fr.box(a - 0.125, a + 0.125, b - 0.125, b + 0.125, -0.5, zw, "timber", POST, "fblt")
    zs = zw - 0.06
    _strips(fr, (-hf, hs), (-hf, -hs), (-1, 0), zs)
    _strips(fr, (-hf, -hs), (hf, -hs), (0, -1), zs)
    _strips(fr, (hf, hs), (-hf, hs), (0, 1), zs)
    _strips(fr, (hf, -hs), (hf, hs), (1, 0), zs, gaps=((d0 + hs, d1 + hs),))
    return len(m.faces) - n0


def beach_bar(m, uv, x, y, yaw, z0):
    """A 9 x 5 m thatched bar open to +f: counter, four stools, a back wall with shelves and bottles, a sign."""
    fr, r, n0 = Frame(m, uv, x, y, yaw, z0), Rng(4242), len(m.faces)
    hf, hs, eave = 2.5, 4.5, 0.6
    pitch = _thatch(fr, hf + eave, hs + eave, 2.8, 1.8, r)
    zb = 2.8 + pitch * eave
    _two(fr, [(-hf, hs, -0.5), (-hf, -hs, -0.5), (-hf, -hs, zb), (-hf, hs, zb)], (-1, 0, 0), "timber", BAMBOO)
    zp = 2.8 + pitch * (eave + 0.15)
    for a in (-hf + 0.15, hf - 0.15):
        for b in (-hs + 0.15, 0.0, hs - 0.15):
            fr.box(a - 0.125, a + 0.125, b - 0.125, b + 0.125, -0.5, zp, "timber", POST, "fblt")
    for k, zs in enumerate((1.3, 1.85)):
        fr.box(-hf, -hf + 0.3, -3.0, 3.0, zs, zs + 0.06, "timber", POST, "fltud")
        for j in range(3):
            s = -2.4 + 2.4 * j + (0.5 if k else 0.0)
            fr.box(-hf + 0.08, -hf + 0.17, s - 0.045, s + 0.045, zs + 0.06, zs + 0.36, "plastic", BOTTLES[(j + k) % 3], "fu")
    fr.box(1.95, 2.4, -3.9, 3.9, -0.5, 1.04, "timber", STRIP, "fblt")
    fr.box(1.85, 2.55, -4.0, 4.0, 1.04, 1.1, "deck", DECK)
    for s in (-2.7, -0.9, 0.9, 2.7):
        fr.box(2.96, 3.04, s - 0.04, s + 0.04, -0.5, 0.72, "timber", POST, "fblt")
        _prism(fr, 3.0, s, 0.175, 0.175, 6, 0.72, 0.78, "deck", DECK, top=True)
    fr.box(2.5, 2.56, -0.75, 0.75, 2.45, 3.05, "plastic", SIGN)
    return len(m.faces) - n0


def cabana(m, uv, x, y, yaw, z0, seed):
    """A 4 x 4 m canvas cabana on a deck: pyramid canvas roof with a coloured valance, back and one side wall,
    a lounger."""
    fr, r, n0 = Frame(m, uv, x, y, yaw, z0), Rng(seed * 7919 + 23), len(m.faces)
    canvas, accent = CANVAS_TINTS[r.i(0, 2)], ACCENTS[r.i(0, 3)]
    side = 1.0 if r.f() < 0.5 else -1.0
    zd, pl = 0.3, 1.85
    zp = zd + 2.6
    fr.box(-2.0, 2.0, -2.0, 2.0, -0.2, zd, "deck", DECK, "fbltu")
    for a in (-pl, pl):
        for b in (-pl, pl):
            fr.box(a - 0.1, a + 0.1, b - 0.1, b + 0.1, -0.5, zp, "timber", POST, "fblt")
    pitch = 1.2 / pl
    ee, ze, apex = pl + 0.5, zp - pitch * 0.5, (0.0, 0.0, zp + 1.2)
    E = [(ee, -ee, ze), (ee, ee, ze), (-ee, ee, ze), (-ee, -ee, ze)]
    for k, h in enumerate(((1, 0), (0, 1), (-1, 0), (0, -1))):
        e0, e1 = E[k], E[(k + 1) % 4]
        _two(fr, [e0, e1, apex], (h[0], h[1], 1.0), "canvas2", canvas, _shade(canvas, 0.82))
        _two(fr, [e0, e1, (e1[0], e1[1], ze - 0.25), (e0[0], e0[1], ze - 0.25)], (h[0], h[1], 0.0), "canvas2", accent)
    _two(fr, [(-pl, pl, zd), (-pl, -pl, zd), (-pl, -pl, zp), (-pl, pl, zp)], (-1, 0, 0), "canvas2", canvas)
    sw = side * pl
    _two(fr, [(-pl, sw, zd), (pl, sw, zd), (pl, sw, zp), (-pl, sw, zp)], (0, side, 0), "canvas2", canvas)
    ls = side * 0.8
    fr.box(-0.95, 1.0, ls - 0.35, ls + 0.35, zd, zd + 0.35, "deck", DECK, "fbltu")
    _two(fr, [(-0.95, ls - 0.33, zd + 0.35), (-0.95, ls + 0.33, zd + 0.35), (-1.4, ls + 0.33, zd + 1.0),
              (-1.4, ls - 0.33, zd + 1.0)], (1.0, 0.0, 0.7), "deck", DECK)
    return len(m.faces) - n0


def boardwalk(m, uv, pts, z_of, width=2.4):
    """A plank path along world (x, y) points: deck top at z_of + 0.2, edge joists 0.1 m proud of its sides,
    posts under both edges at every point."""
    fr, n0 = Frame(m, uv, 0.0, 0.0, 0.0, 0.0), len(m.faces)
    P = [(float(a), float(b)) for a, b in pts]
    if len(P) < 2:
        return 0
    hw = width / 2.0
    dirs = []
    for i in range(len(P) - 1):
        dx, dy = P[i + 1][0] - P[i][0], P[i + 1][1] - P[i][1]
        ln = math.hypot(dx, dy) or 1.0
        dirs.append((dx / ln, dy / ln))
    secs = []
    for i, p in enumerate(P):
        a = dirs[max(0, i - 1)]
        b = dirs[min(i, len(dirs) - 1)]
        na, nb = (-a[1], a[0]), (-b[1], b[0])
        mv = (na[0] + nb[0], na[1] + nb[1])
        ml = math.hypot(*mv) or 1.0
        mv = (mv[0] / ml, mv[1] / ml)
        sc = 1.0 / max(0.5, mv[0] * na[0] + mv[1] * na[1])
        top = z_of(p[0], p[1]) + 0.2

        def at(o):
            return (p[0] + mv[0] * o * sc, p[1] + mv[1] * o * sc)
        secs.append({"top": top, "L": at(hw), "R": at(-hw), "LO": at(hw + 0.1), "RO": at(-hw - 0.1), "n": mv})
    for i, d in enumerate(dirs):
        A, B = secs[i], secs[i + 1]
        ta, tb = A["top"], B["top"]
        fr.poly([A["L"] + (ta,), A["R"] + (ta,), B["R"] + (tb,), B["L"] + (tb,)], (0, 0, 1), "deck", DECK)
        nrm = (-d[1], d[0])
        for e, o, sg in (("L", "LO", 1.0), ("R", "RO", -1.0)):
            out = (nrm[0] * sg, nrm[1] * sg, 0.0)
            fr.poly([A[e] + (ta,), B[e] + (tb,), B[e] + (tb - 0.03,), A[e] + (ta - 0.03,)], out, "deck", DECK)
            fr.poly([A[e] + (ta - 0.03,), B[e] + (tb - 0.03,), B[o] + (tb - 0.03,), A[o] + (ta - 0.03,)], (0, 0, 1),
                    "timber", POST)
            fr.poly([A[o] + (ta - 0.03,), B[o] + (tb - 0.03,), B[o] + (tb - 0.3,), A[o] + (ta - 0.3,)], out, "timber", POST)
    for S, d, sg in ((secs[0], dirs[0], -1.0), (secs[-1], dirs[-1], 1.0)):
        t, out = S["top"], (d[0] * sg, d[1] * sg, 0.0)
        fr.poly([S["L"] + (t,), S["R"] + (t,), S["R"] + (t - 0.03,), S["L"] + (t - 0.03,)], out, "deck", DECK)
        fr.poly([S["LO"] + (t - 0.03,), S["RO"] + (t - 0.03,), S["RO"] + (t - 0.3,), S["LO"] + (t - 0.3,)], out, "timber", POST)
    for i, S in enumerate(secs):
        d = dirs[min(i, len(dirs) - 1)]
        rot = math.degrees(math.atan2(d[1], d[0])) + 45.0
        for o in (hw + 0.05, -hw - 0.05):
            c = (P[i][0] + S["n"][0] * o, P[i][1] + S["n"][1] * o)
            zb = min(z_of(c[0], c[1]) - 0.5, S["top"] - 0.6)
            _prism(fr, c[0], c[1], 0.106, 0.106, 4, zb, S["top"] - 0.3, "timber", POST, rot=rot)
    return len(m.faces) - n0


def torch(m, uv, x, y, z0):
    """A tiki torch: 2.05 m bamboo post, 0.35 m flared head to 2.4 m, a crossed-diamond flame."""
    fr, n0 = Frame(m, uv, x, y, 0.0, z0), len(m.faces)
    fr.box(-0.06, 0.06, -0.06, 0.06, -0.5, 2.05, "timber", BAMBOO, "fblt")
    _prism(fr, 0.0, 0.0, 0.085, 0.25, 4, 2.05, 2.4, "timber", DARK, rot=45.0, top=True)
    for ax in ((1.0, 0.0), (0.0, 1.0)):
        q = [(0.0, 0.0, 2.35), (ax[0] * 0.25, ax[1] * 0.25, 2.65), (0.0, 0.0, 3.15), (-ax[0] * 0.25, -ax[1] * 0.25, 2.65)]
        _two(fr, q, (-ax[1], ax[0], 0.0), "plastic", FLAME)
    return len(m.faces) - n0


def _hole_wall(fr, f, s0, s1, zlo, zhi, h, col, dark, zone="timber", depth=0.1):
    """A wall at f facing +f from s0 to s1, round a hole h = (hs0, hs1, hz0, hz1) recessed `depth` to a dark back."""
    hs0, hs1, hz0, hz1 = h
    P, o = fr.poly, (1, 0, 0)
    P([(f, s0, zlo), (f, s1, zlo), (f, s1, hz0), (f, s0, hz0)], o, zone, col)
    P([(f, s0, hz1), (f, s1, hz1), (f, s1, zhi), (f, s0, zhi)], o, zone, col)
    P([(f, s0, hz0), (f, hs0, hz0), (f, hs0, hz1), (f, s0, hz1)], o, zone, col)
    P([(f, hs1, hz0), (f, s1, hz0), (f, s1, hz1), (f, hs1, hz1)], o, zone, col)
    b = f - depth
    P([(b, hs0, hz0), (b, hs1, hz0), (b, hs1, hz1), (b, hs0, hz1)], o, "plastic", dark)
    P([(b, hs0, hz0), (f, hs0, hz0), (f, hs0, hz1), (b, hs0, hz1)], (0, 1, 0), zone, col)
    P([(b, hs1, hz0), (f, hs1, hz0), (f, hs1, hz1), (b, hs1, hz1)], (0, -1, 0), zone, col)
    P([(b, hs0, hz1), (f, hs0, hz1), (f, hs1, hz1), (b, hs1, hz1)], (0, 0, -1), zone, col)
    P([(b, hs0, hz0), (f, hs0, hz0), (f, hs1, hz0), (b, hs1, hz0)], (0, 0, 1), zone, col)


def lifeguard_tower(m, uv, x, y, yaw, z0):
    """A 3 x 3 m white cabin on a 2.6 m deck platform: window and red cross on +f, thatch shed roof, a ladder up
    the front, a rail round the deck."""
    fr, n0 = Frame(m, uv, x, y, yaw, z0), len(m.faces)
    zp, F0, F1, PS = 2.6, -2.0, 2.4, 2.2
    fr.box(F0, F1, -PS, PS, zp - 0.2, zp, "deck", DECK)
    for a in (F0 + 0.15, F1 - 0.15):
        for b in (-PS + 0.15, PS - 0.15):
            fr.box(a - 0.1, a + 0.1, b - 0.1, b + 0.1, -0.5, zp - 0.2, "timber", POST, "fblt")
    C0, C1, CS, hb, hf = -1.8, 1.2, 1.5, 2.2, 2.6
    P = fr.poly
    P([(C0, CS, zp), (C0, -CS, zp), (C0, -CS, zp + hb), (C0, CS, zp + hb)], (-1, 0, 0), "timber", PAINT)
    for sg in (-1, 1):
        P([(C0, sg * CS, zp), (C1, sg * CS, zp), (C1, sg * CS, zp + hf), (C0, sg * CS, zp + hb)], (0, sg, 0), "timber", PAINT)
    _hole_wall(fr, C1, -CS, CS, zp, zp + hf, (-0.1, 0.9, zp + 1.0, zp + 2.2), PAINT, GLASS)
    cs, cz, f = -0.85, zp + 1.6, C1 + 0.02
    for s0, s1, z0_, z1_ in ((-0.1, 0.1, -0.3, 0.3), (-0.3, -0.1, -0.1, 0.1), (0.1, 0.3, -0.1, 0.1)):
        P([(f, cs + s0, cz + z0_), (f, cs + s1, cz + z0_), (f, cs + s1, cz + z1_), (f, cs + s0, cz + z1_)], (1, 0, 0),
          "plastic", RED)
    k = (hf - hb) / (C1 - C0)
    ov = 0.4
    ra, rb = C1 + ov, C0 - ov
    za, zb = zp + hf + k * ov, zp + hb - k * ov
    rs = CS + ov
    for z_a, z_b, out, col in ((za + 0.15, zb + 0.15, (k, 0, 1), THATCH), (za, zb, (-k, 0, -1), THATCH_UNDER)):
        P([(ra, -rs, z_a), (ra, rs, z_a), (rb, rs, z_b), (rb, -rs, z_b)], out, "thatch2", col)
    P([(ra, -rs, za), (ra, rs, za), (ra, rs, za + 0.15), (ra, -rs, za + 0.15)], (1, 0, 0), "thatch2", THATCH)
    P([(rb, -rs, zb), (rb, rs, zb), (rb, rs, zb + 0.15), (rb, -rs, zb + 0.15)], (-1, 0, 0), "thatch2", THATCH)
    for sg in (-1, 1):
        P([(rb, sg * rs, zb), (ra, sg * rs, za), (ra, sg * rs, za + 0.15), (rb, sg * rs, zb + 0.15)], (0, sg, 0),
          "thatch2", THATCH)
    for s in (-0.35, 0.35):
        _beam(fr, (3.4, s, -0.3), (2.1, s, 3.6), 0.08, 0.08, "timber", POST)
    for i in range(8):
        z = 0.3 + 0.3 * i
        fl = 3.4 - (z + 0.3) / 3.0
        _beam(fr, (fl, -0.35, z), (fl, 0.35, z), 0.05, 0.05, "timber", POST, "lud")
    a0, a1, sr = F0 + 0.05, F1 - 0.05, PS - 0.05
    for pf, ps in ((a0, -sr), (a0, sr), (a1, -sr), (a1, sr), (a1, -0.45), (a1, 0.45)):
        fr.box(pf - 0.04, pf + 0.04, ps - 0.04, ps + 0.04, zp, zp + 1.0, "timber", POST, "fblt")
    zr = zp + 1.0
    for p, q in (((a0, -sr), (a0, sr)), ((a0, -sr), (a1, -sr)), ((a0, sr), (a1, sr)), ((a1, -sr), (a1, -0.45)),
                 ((a1, 0.45), (a1, sr))):
        _beam(fr, p + (zr,), q + (zr,), 0.08, 0.08, "timber", POST)
    return len(m.faces) - n0


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


def lighthouse(m, uv, x, y, z0, h=25.0):
    """Wuhu's lighthouse: tapered white 12-sided tower on an ashlar plinth, door and two slits on +f, a railed
    gallery, a glazed lantern, a red cap and finial."""
    fr, n0 = Frame(m, uv, x, y, 0.0, z0), len(m.faces)
    zt, rb, rt, n = 0.8 * h, 3.2, 2.2, 12

    def rz(z):
        return rb + (rt - rb) * z / zt
    _prism(fr, 0.0, 0.0, 3.6, 3.6, n, -0.5, 0.6, "ashlar", STONE, rot=15.0)
    _annulus(fr, rz(0.6), 3.6, n, 0.6, (0, 0, 1), "ashlar", STONE, rot=15.0)
    for k in range(n):
        holes = ()
        if k == 0:
            holes = ((0.6, 2.7, 1.2, DOOR), (0.38 * h, 0.38 * h + 1.4, 0.5, GLASS), (0.6 * h, 0.6 * h + 1.4, 0.5, GLASS))
        _facet(fr, 30.0 * k - 15.0, 30.0 * k + 15.0, rz, 0.6, zt, holes, LH_WHITE)
    zg = zt + 0.3
    _prism(fr, 0.0, 0.0, 3.0, 3.0, n, zt, zg, "plastic", LH_WHITE, rot=15.0)
    _annulus(fr, rt, 3.0, n, zt, (0, 0, -1), "plastic", LH_WHITE, rot=15.0)
    _annulus(fr, 1.6, 3.0, n, zg, (0, 0, 1), "plastic", LH_WHITE, rot=15.0)
    for k in range(n):
        a = math.radians(15.0 + 30.0 * k)
        pf, ps = 2.88 * math.cos(a), 2.88 * math.sin(a)
        fr.box(pf - 0.05, pf + 0.05, ps - 0.05, ps + 0.05, zg, zg + 1.0, "plastic", LH_WHITE, "fblt")
    zr = zg + 1.0
    _prism(fr, 0.0, 0.0, 2.92, 2.92, n, zr, zr + 0.08, "plastic", LH_WHITE, rot=15.0)
    _prism(fr, 0.0, 0.0, 2.84, 2.84, n, zr, zr + 0.08, "plastic", LH_WHITE, rot=15.0, inward=True)
    _annulus(fr, 2.84, 2.92, n, zr + 0.08, (0, 0, 1), "plastic", LH_WHITE, rot=15.0)
    _annulus(fr, 2.84, 2.92, n, zr, (0, 0, -1), "plastic", LH_WHITE, rot=15.0)
    zl = zg + 0.12 * h
    for k in range(n):
        a0, a1 = 30.0 * k - 15.0, 30.0 * k + 15.0
        c0 = (1.6 * math.cos(math.radians(a0)), 1.6 * math.sin(math.radians(a0)))
        c1 = (1.6 * math.cos(math.radians(a1)), 1.6 * math.sin(math.radians(a1)))
        out = (math.cos(math.radians(30.0 * k)), math.sin(math.radians(30.0 * k)), 0.0)

        def q(t0, t1, z0_, z1_, col):
            p0 = (c0[0] + (c1[0] - c0[0]) * t0, c0[1] + (c1[1] - c0[1]) * t0)
            p1 = (c0[0] + (c1[0] - c0[0]) * t1, c0[1] + (c1[1] - c0[1]) * t1)
            fr.poly([p0 + (z0_,), p1 + (z0_,), p1 + (z1_,), p0 + (z1_,)], out, "plastic", col)
        q(0.0, 1.0, zg, zg + 0.4, LH_WHITE)
        q(0.0, 1.0, zl - 0.25, zl, LH_WHITE)
        q(0.0, 0.12, zg + 0.4, zl - 0.25, LH_WHITE)
        q(0.12, 1.0, zg + 0.4, zl - 0.25, GLASS)
    zc = zl + 0.08 * h
    _prism(fr, 0.0, 0.0, 1.9, 0.0, n, zl, zc, "plastic", RED, rot=15.0, bottom=True)
    fr.box(-0.04, 0.04, -0.04, 0.04, zc - 0.2, zc + 0.6, "plastic", RED, "fblt")
    _prism(fr, 0.0, 0.0, 0.18, 0.0, 4, zc + 0.75, zc + 1.0, "plastic", RED)
    _prism(fr, 0.0, 0.0, 0.18, 0.0, 4, zc + 0.75, zc + 0.5, "plastic", RED)
    return len(m.faces) - n0


# =============================================================================
# CHECK
# =============================================================================

def _check():
    def bbox(m):
        vs = [m.verts[i] for f in m.faces for i in f]
        return (tuple(round(min(p[k] for p in vs), 2) for k in range(3)),
                tuple(round(max(p[k] for p in vs), 2) for k in range(3)))

    def zf(x, y):
        return 0.3 * math.sin(x * 0.2) + 0.05 * y

    walk = [(0.0, 0.0), (3.0, 0.0), (6.0, 1.0), (8.5, 2.8), (10.5, 5.0), (12.0, 7.6)]
    cases = [("tiki_hut%d" % s, 220, (lambda m, uv, s=s: tiki_hut(m, uv, 0.0, 0.0, 20.0, 0.0, s))) for s in range(1, 7)]
    cases += [("beach_bar", 320, lambda m, uv: beach_bar(m, uv, 0.0, 0.0, 20.0, 0.0))]
    cases += [("cabana%d" % s, 120, (lambda m, uv, s=s: cabana(m, uv, 0.0, 0.0, 20.0, 0.0, s))) for s in range(1, 5)]
    cases += [("boardwalk", 10 ** 6, lambda m, uv: boardwalk(m, uv, walk, zf)),
              ("torch", 40, lambda m, uv: torch(m, uv, 0.0, 0.0, 0.0)),
              ("lifeguard_tower", 260, lambda m, uv: lifeguard_tower(m, uv, 0.0, 0.0, 20.0, 0.0)),
              ("lighthouse", 700, lambda m, uv: lighthouse(m, uv, 0.0, 0.0, 0.0))]
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
