"""beach_buildings -- the resort's hotel, houses and clock tower at true player scale (3.2 m storeys, 2.1 m doors),
real arcades, balconies, belfries; walls textured at 0.05 m/texel. Pure Python: runs without Blender."""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beach_lib import Mesh, Rng, report  # noqa: E402

CHUNK = "resort"
TILE = 12.8                      # metres per texture tile (256 px at 0.05 m)
STOREY = 3.2                     # one texture row
COL = 3.2                        # facade column pitch (64 px)
WHITE = (1.0, 1.0, 1.0, 1.0)
STONE = (0.9, 0.84, 0.7, 1.0)
RAIL = (1.0, 1.0, 1.0, 1.0)
BRONZE = (0.55, 0.42, 0.22, 1.0)
FLAT = {"plaster": (63.5 / 256.0, 30.0 / 256.0), "house": (0.5, 0.75), "clock": (0.75, 0.25)}
TEXTURED = ("plaster", "house", "clock")
HOUSE_TINTS = ((1.0, 0.93, 0.82), (0.98, 0.86, 0.78), (1.0, 0.97, 0.9), (0.86, 0.92, 0.98), (1.0, 0.9, 0.86),
               (0.92, 0.96, 0.86))


class Frame(object):
    """A building's local frame: f along its front (fwd), s across (side), z up from the terrace z0."""

    def __init__(self, m, uv, x, y, yaw, z0):
        a = math.radians(yaw)
        self.m, self.uv, self.x, self.y, self.z0 = m, uv, x, y, z0
        self.fw = (math.cos(a), math.sin(a))
        self.sd = (-math.sin(a), math.cos(a))

    def p(self, f, s, z):
        return (self.x + self.fw[0] * f + self.sd[0] * s, self.y + self.fw[1] * f + self.sd[1] * s, self.z0 + z)

    def d(self, f, s, z):
        return (self.fw[0] * f + self.sd[0] * s, self.fw[1] * f + self.sd[1] * s, z)

    def poly(self, pts, out, zone, col, uvs=None):
        """A tri or quad from local points, turned to face local direction `out`; uvs per point, or the zone's
        flat texel, or none for the roof."""
        m = self.m
        vs = [m.v(self.p(*q), col) for q in pts]
        if uvs is None and zone in TEXTURED:
            uvs = [FLAT[zone]] * len(pts)
        want = self.d(*out)
        start = len(m.faces)
        m.tri(vs[0], vs[1], vs[2], want, zone, CHUNK)
        if len(vs) == 4:
            m.tri(vs[0], vs[2], vs[3], want, zone, CHUNK)
        if uvs is not None:
            look = dict(zip(vs, uvs))
            for fi in range(start, len(m.faces)):
                for vi in m.faces[fi]:
                    self.uv[(fi, vi)] = look[vi]

    def wall(self, a, b, zlo, zhi, zone, col, u=(0.0, None), v0=None):
        """A vertical quad from corner a to corner b (f, s; a is the left one seen from outside); u spans a whole
        number of 3.2 m columns from u[0], v rises from v0 (default z / 12.8)."""
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        u0 = u[0]
        u1 = u0 + (u[1] if u[1] is not None else max(1, round(ln / COL)) * COL / TILE)
        v0 = zlo / TILE if v0 is None else v0
        v1 = v0 + (zhi - zlo) / TILE
        out = (b[1] - a[1], -(b[0] - a[0]), 0.0)
        self.poly([(a[0], a[1], zlo), (b[0], b[1], zlo), (b[0], b[1], zhi), (a[0], a[1], zhi)], out, zone, col,
                  [(u0, v0), (u1, v0), (u1, v1), (u0, v1)])

    def box(self, f0, f1, s0, s1, z0, z1, zone, col, faces="fbltud"):
        """An axis-aligned box: f front, b back, l (-s), t (+s), u top, d bottom; flat texel."""
        P = self.poly
        if "f" in faces:
            P([(f1, s0, z0), (f1, s1, z0), (f1, s1, z1), (f1, s0, z1)], (1, 0, 0), zone, col)
        if "b" in faces:
            P([(f0, s1, z0), (f0, s0, z0), (f0, s0, z1), (f0, s1, z1)], (-1, 0, 0), zone, col)
        if "l" in faces:
            P([(f0, s0, z0), (f1, s0, z0), (f1, s0, z1), (f0, s0, z1)], (0, -1, 0), zone, col)
        if "t" in faces:
            P([(f1, s1, z0), (f0, s1, z0), (f0, s1, z1), (f1, s1, z1)], (0, 1, 0), zone, col)
        if "u" in faces:
            P([(f0, s0, z1), (f1, s0, z1), (f1, s1, z1), (f0, s1, z1)], (0, 0, 1), zone, col)
        if "d" in faces:
            P([(f0, s0, z0), (f0, s1, z0), (f1, s1, z0), (f1, s0, z0)], (0, 0, -1), zone, col)

    def band(self, fc, sc, hf, hs, z0, z1, proj, zone, col, top=True):
        """A string course: a ring round a hf x hs half-extent shaft, proj proud, outer faces, ledge and soffit."""
        F0, F1, S0, S1 = fc - hf - proj, fc + hf + proj, sc - hs - proj, sc + hs + proj
        self.box(F0, F1, S0, S1, z0, z1, zone, col, "fblt")
        f0, f1, s0, s1 = fc - hf, fc + hf, sc - hs, sc + hs
        for z, out in ((z1, (0, 0, 1)), (z0, (0, 0, -1))):
            if z == z1 and not top:
                continue
            P = self.poly
            P([(F1, S0, z), (F1, S1, z), (f1, s1, z), (f1, s0, z)], out, zone, col)
            P([(F0, S1, z), (F0, S0, z), (f0, s0, z), (f0, s1, z)], out, zone, col)
            P([(F0, S0, z), (F1, S0, z), (f1, s0, z), (f0, s0, z)], out, zone, col)
            P([(F1, S1, z), (F0, S1, z), (f0, s1, z), (f1, s1, z)], out, zone, col)

    def roof(self, fc, sc, hf, hs, h, pitch, eave, col, kind="hip", gable_zone=None, gable_col=WHITE, soffit=False):
        """A hip, gable or pyramid roof over walls of half extents hf x hs topped at h: the slopes meet the wall line at h,
        eaves overhang; underside closed by back slopes, or (soffit) a flat stone ceiling. Returns z(f, s) on the roof."""
        ef, es = hf + eave, hs + eave
        along_s = hs >= hf                       # ridge axis
        half = ef if along_s else es             # half span across the ridge
        ridge_half = max(0.0, (es - ef) if along_s else (ef - es))
        if kind == "gable":
            ridge_half = es if along_s else ef
        hb = h - pitch * eave
        hr = hb + pitch * half
        P = self.poly

        def L(a, b):                             # (across, along) -> (f, s)
            return (fc + a, sc + b) if along_s else (fc + b, sc + a)

        def put(pts, out_a, out_b):
            pts = [q for i, q in enumerate(pts) if q not in pts[:i]]     # a pyramid has no ridge
            o = L(out_a, out_b)
            P([L(a, b) + (z,) for a, b, z in pts], (o[0] - fc, o[1] - sc, 1.0), "roof", col)
            if not soffit:
                P([L(a, b) + (z,) for a, b, z in reversed(pts)], (-(o[0] - fc), -(o[1] - sc), -1.0), "roof", col)

        alongE = es if along_s else ef
        if soffit:
            P([(fc - ef, sc - es, hb), (fc - ef, sc + es, hb), (fc + ef, sc + es, hb), (fc + ef, sc - es, hb)],
              (0, 0, -1), "plaster", STONE)
        if kind == "gable":
            for sgn in (1, -1):
                put([(sgn * half, -alongE, hb), (sgn * half, alongE, hb), (0.0, alongE, hr), (0.0, -alongE, hr)], sgn, 0.0)
            wl = hs if not along_s else hf          # wall half-width across the ridge at the gable ends
            alongW = hs if along_s else hf
            for sgn in (1, -1):
                pts = [L(-wl, sgn * alongW) + (h,), L(wl, sgn * alongW) + (h,), L(0.0, sgn * alongW) + (h + pitch * wl,)]
                o = L(0.0, sgn)
                zone = gable_zone or "roof"
                uvs = None
                if zone in TEXTURED:
                    uvs = [(0.0, 0.5), (2.0 * wl / TILE, 0.5), (wl / TILE, 0.5 + pitch * wl / TILE)]
                P(pts, (o[0] - fc, o[1] - sc, 0.0), zone, gable_col, uvs)
        else:
            for sgn in (1, -1):
                put([(sgn * half, -alongE, hb), (sgn * half, alongE, hb), (0.0, ridge_half, hr), (0.0, -ridge_half, hr)], sgn, 0.0)
                put([(-half, sgn * alongE, hb), (half, sgn * alongE, hb), (0.0, sgn * ridge_half, hr)], 0.0, sgn)

        def z_at(f, s):
            a, b = (f - fc, s - sc) if along_s else (s - sc, f - fc)
            za = hr - pitch * abs(a)
            if kind == "gable":
                return za
            return min(za, hr - pitch * max(0.0, abs(b) - ridge_half))
        return z_at

    def spire(self, fc, sc, z, r, h):
        """A finial: a small diamond on a roof apex, h tall."""
        m = 0.3 * h
        ring = [(fc + r, sc, z + m), (fc, sc + r, z + m), (fc - r, sc, z + m), (fc, sc - r, z + m)]
        for k in range(4):
            a, b = ring[k], ring[(k + 1) % 4]
            o = ((a[0] + b[0]) / 2 - fc, (a[1] + b[1]) / 2 - sc)
            self.poly([a, b, (fc, sc, z + h)], (o[0], o[1], 0.5), "plaster", STONE)
            self.poly([b, a, (fc, sc, z - 0.2)], (o[0], o[1], -0.5), "plaster", STONE)

    def belfry(self, fc, sc, half, zb, post, cap, bell=True):
        """An open belfry over a shaft topped at zb: its floor, four corner posts `post` square, a cap slab, a bell."""
        P = self.poly
        h = half
        P([(fc - h, sc - h, zb), (fc + h, sc - h, zb), (fc + h, sc + h, zb), (fc - h, sc + h, zb)], (0, 0, 1), "plaster", STONE)
        zt = zb + 4.0 - 0.4
        for a in (-1, 1):
            for b in (-1, 1):
                f0, f1 = sorted((fc + a * h, fc + a * (h - post)))
                s0, s1 = sorted((sc + b * h, sc + b * (h - post)))
                self.box(f0, f1, s0, s1, zb, zt, "plaster", WHITE, "fblt")
        self.box(fc - h - cap, fc + h + cap, sc - h - cap, sc + h + cap, zt, zt + 0.4, "plaster", STONE, "fbltd")
        if bell:
            r0, r1, zl, zh = 0.35 * h, 0.15 * h, zt - 1.9, zt - 0.4
            ring_lo = [(fc + r0, sc + r0), (fc - r0, sc + r0), (fc - r0, sc - r0), (fc + r0, sc - r0)]
            ring_hi = [(fc + r1, sc + r1), (fc - r1, sc + r1), (fc - r1, sc - r1), (fc + r1, sc - r1)]
            for k in range(4):
                j = (k + 1) % 4
                o = ((ring_lo[k][0] + ring_lo[j][0]) / 2 - fc, (ring_lo[k][1] + ring_lo[j][1]) / 2 - sc, 0.3)
                P([ring_lo[k] + (zl,), ring_lo[j] + (zl,), ring_hi[j] + (zh,), ring_hi[k] + (zh,)], o, "plaster", BRONZE)
            P([q + (zl,) for q in ring_lo], (0, 0, -1), "plaster", BRONZE)
        return zt + 0.4


def _bands(z_top, start=-0.5):
    """Storey bands (zlo, zhi, row, storey foot) from the footing to z_top: row 0 the ground storey (its doors),
    rows 1-3 cycling above; a sliver under 0.6 m joins the band below."""
    out, z, k = [], start, 0
    while z < z_top - 0.05:
        hi = min(z_top, (k + 1) * STOREY)
        if z_top - hi < 0.6:
            hi = z_top
        out.append((z, hi, 0 if k == 0 else 1 + (k - 1) % 3, k * STOREY))
        z, k = hi, k + 1
    return out


def _vfix(fr, a, b, bands, zone, col, u=(0.0, None)):
    for zlo, zhi, row, foot in bands:
        fr.wall(a, b, zlo, zhi, zone, col, u, (row * STOREY + zlo - foot) / TILE)


def _outline(fr, pts, bands, zone, col):
    """Walls round a CCW (f, s) outline, each from its left corner."""
    for k in range(len(pts)):
        _vfix(fr, pts[k], pts[(k + 1) % len(pts)], bands, zone, col)


# =============================================================================
# HOTEL
# =============================================================================

def hotel(m, uv, x, y, yaw, z0, body=(40.0, 15.0, 13.0), tower=(9.0, 9.0, 30.0)):
    """The resort hotel: arcaded ground storey, three balconied storeys, cornice, hip roof, entrance portico, and a
    belfry tower on its left end."""
    n0 = len(m.faces)
    fr = Frame(m, uv, x, y, yaw, z0)
    w, d, h = body
    tw, td, th = tower
    hw, hd = w / 2.0, d / 2.0
    fF, rec = hd, hd - 2.4                       # front wall line, arcade back wall
    tl = -hw + 1.5                               # tower's right face (it overlaps the body's left end by 1.5 m)
    ts0, ts1 = -hw - tw + 1.5, tl
    tf0, tf1 = hd - td, hd
    up = [b for b in _bands(h) if b[2]]          # upper storeys
    gnd = [b for b in _bands(h) if not b[2]]
    # body walls: back, right end, left end (mostly in the tower); front recessed on the ground storey
    _vfix(fr, (-hd, hw), (-hd, -hw), _bands(h), "plaster", WHITE)
    _vfix(fr, (hd, hw), (-hd, hw), _bands(h), "plaster", WHITE)
    _vfix(fr, (-hd, -hw), (tf0, -hw), _bands(h), "plaster", WHITE)
    _vfix(fr, (rec, tl), (rec, hw), [(gnd[0][0], 2.9, 0, 0.0)], "plaster", WHITE)
    _vfix(fr, (fF, tl), (fF, hw), [(2.9,) + up[0][1:]] + up[1:], "plaster", WHITE)
    fr.poly([(rec, tl, 2.9), (fF, tl, 2.9), (fF, hw, 2.9), (rec, hw, 2.9)], (0, 0, -1), "plaster", STONE)   # arcade ceiling
    fr.poly([(rec, hw, -0.5), (fF, hw, -0.5), (fF, hw, 2.9), (rec, hw, 2.9)], (0, -1, 0), "plaster", WHITE)  # arcade's right end
    # arcade: 10 pillars 0.6 m square with capitals
    n_p = 10
    for k in range(n_p):
        s = tl + 0.6 + (hw - 0.3 - tl - 0.6) * k / (n_p - 1.0)
        fr.box(fF - 0.6, fF, s - 0.3, s + 0.3, -0.5, 2.65, "plaster", WHITE, "fblt")
        fr.box(fF - 0.7, fF + 0.1, s - 0.4, s + 0.4, 2.65, 2.9, "plaster", STONE, "fbltd")
        fr.box(fF - 0.7, fF + 0.1, s - 0.4, s + 0.4, -0.5, 0.25, "plaster", STONE, "fblt")
    # string courses on the body (ends and back) and the cornice under the roof
    for k in (1, 2, 3):
        fr.band(0.0, 0.0, hd, hw, k * STOREY - 0.15, k * STOREY + 0.15, 0.15, "plaster", STONE)
    fr.band(0.0, 0.0, hd, hw, h - 0.6, h, 0.35, "plaster", STONE, top=False)
    # balconies on each upper storey, the first broken by the portico
    for k in (1, 2, 3):
        zb = k * STOREY
        segs = [(tl + 0.3, -3.2), (3.2, hw - 0.3)] if k == 1 else [(tl + 0.3, hw - 0.3)]
        for s0, s1 in segs:
            fr.box(fF, fF + 1.2, s0, s1, zb - 0.2, zb, "plaster", STONE, "fltud")
            fr.box(fF + 1.05, fF + 1.15, s0, s1, zb + 0.88, zb + 1.0, "plaster", RAIL, "fbltud")
            fr.box(fF + 1.05, fF + 1.15, s0, s1, zb + 0.3, zb + 0.36, "plaster", RAIL, "fbtud")
            n = max(1, int(round((s1 - s0) / 4.0)))
            for j in range(n + 1):
                s = s0 + 0.06 + (s1 - s0 - 0.12) * j / n
                fr.box(fF + 1.04, fF + 1.16, s - 0.06, s + 0.06, zb, zb + 0.88, "plaster", RAIL, "fblt")
            for s in (s0, s1):                    # side rails back to the wall
                fr.box(fF, fF + 1.05, s - 0.05 if s == s1 else s, s if s == s1 else s + 0.05, zb + 0.88, zb + 1.0,
                       "plaster", RAIL, "ltu")
    # portico at the entrance: 6 x 3 m, four pillars, a flat roof
    pf = fF + 3.0
    for s in (-2.6, -0.87, 0.87, 2.6):
        fr.box(pf - 0.5, pf, s - 0.25, s + 0.25, -0.5, 3.2, "plaster", WHITE, "fblt")
        fr.box(pf - 0.6, pf + 0.1, s - 0.35, s + 0.35, -0.5, 0.2, "plaster", STONE, "fblt")
    fr.box(fF, pf + 0.15, -3.0, 3.0, 3.2, 3.5, "plaster", STONE, "fltud")
    fr.box(pf - 0.15, pf + 0.15, -3.0, 3.0, 3.5, 4.0, "plaster", WHITE, "fbltu")
    # the hip roof on the cornice
    fr.roof(0.0, 0.0, hd + 0.35, hw + 0.35, h, 0.5, 0.5, WHITE)
    # the tower
    fc, sc = (tf0 + tf1) / 2.0, (ts0 + ts1) / 2.0
    zs = th - 4.0                                 # shaft top, belfry above
    tb = _bands(zs)
    _outline(fr, [(tf1, ts0), (tf1, ts1), (tf0, ts1), (tf0, ts0)], tb, "plaster", WHITE)
    k = 1
    while k * STOREY < zs - 0.5:
        fr.band(fc, sc, td / 2.0, tw / 2.0, k * STOREY - 0.15, k * STOREY + 0.15, 0.15, "plaster", STONE)
        k += 1
    fr.band(fc, sc, td / 2.0, tw / 2.0, zs - 0.4, zs, 0.3, "plaster", STONE)
    zt = fr.belfry(fc, sc, tw / 2.0, zs, 0.7, 0.3)
    fr.roof(fc, sc, td / 2.0 + 0.3, tw / 2.0 + 0.3, zt, 1.1, 0.3, WHITE, soffit=True)
    apex = zt + 1.1 * (tw / 2.0 + 0.6)
    fr.spire(fc, sc, apex - 0.05, 0.22, 0.8)
    return len(m.faces) - n0


# =============================================================================
# HOUSES
# =============================================================================

def house(m, uv, x, y, yaw, z0, seed):
    """A village house from `seed`: a rectangle or an L, one or two 3 m storeys, hip or gable roof, chimney, maybe a
    porch. Returns (w, d, tris) of its footprint."""
    n0 = len(m.faces)
    r = Rng(seed * 7919 + 13)
    fr = Frame(m, uv, x, y, yaw, z0)
    n = r.i(1, 2)
    H = 3.0 * n
    tint = HOUSE_TINTS[r.i(0, len(HOUSE_TINTS) - 1)] + (1.0,)
    roof_col = (r.u(0.9, 1.0), r.u(0.88, 1.0), r.u(0.88, 1.0), 1.0)
    L_shape = r.f() < 0.45
    w = round(r.u(6.5, 10.5) * 2) / 2.0
    d = round(r.u(6.0, min(9.0, w)) * 2) / 2.0
    hw, hd = w / 2.0, d / 2.0
    bands = [(-0.5, min(STOREY, H), 0, 0.0)] + ([(STOREY, H, 1, STOREY)] if H > STOREY else [])
    pitch = r.u(0.45, 0.6)
    kind = "gable" if r.f() < 0.5 else "hip"
    mirror = -1 if r.f() < 0.5 else 1
    if L_shape:
        ww = round(r.u(3.5, min(5.0, w - 2.5)) * 2) / 2.0
        dw = round(r.u(2.5, 3.5) * 2) / 2.0
        d = min(d, 11.0 - dw)
        hd = d / 2.0
        fd = d + dw
        hd0 = fd / 2.0                                     # centre the whole footprint on (x, y)
        mf0, mf1 = -hd0, -hd0 + d
        pts = [(mf1, -hw), (mf1, hw - ww), (hd0, hw - ww), (hd0, hw), (mf0, hw), (mf0, -hw)]
        if mirror < 0:
            pts = [(f, -s) for f, s in reversed(pts)]
        _outline(fr, pts, bands, "house", tint)
        zf = fr.roof((mf0 + mf1) / 2.0, 0.0, hd, hw, H, pitch, 0.5, roof_col, kind, "house", tint)
        wf0 = (mf0 + mf1) / 2.0
        wsc = mirror * (hw - ww / 2.0)
        fr.roof((wf0 + hd0) / 2.0, wsc, (hd0 - wf0) / 2.0, ww / 2.0, H, pitch + 0.15, 0.5, roof_col, "gable", "house", tint)
        porch = (mf1, -hw + 0.4, hw - ww - 0.3) if r.f() < 0.6 else None
        d_out = fd
        main_fc = (mf0 + mf1) / 2.0
    else:
        pts = [(hd, -hw), (hd, hw), (-hd, hw), (-hd, -hw)]
        _outline(fr, pts, bands, "house", tint)
        zf = fr.roof(0.0, 0.0, hd, hw, H, pitch, 0.5, roof_col, kind, "house", tint)
        porch = (hd, -hw + 0.6, hw - 0.6) if r.f() < 0.5 else None
        d_out = d
        main_fc = 0.0
    if porch is not None:
        pf, s0, s1 = porch
        zp = min(2.85, H - pitch * 0.5 - 0.08)
        if mirror < 0 and L_shape:
            s0, s1 = -s1, -s0
        fr.box(pf, pf + 1.5, s0, s1, -0.3, 0.25, "house", STONE, "fltu")
        for s in (s0 + 0.15, s1 - 0.15):
            fr.box(pf + 1.2, pf + 1.4, s - 0.1, s + 0.1, 0.25, zp - 0.3, "house", WHITE, "fblt")
        fr.box(pf + 1.2, pf + 1.4, s0 + 0.05, s1 - 0.05, zp - 0.5, zp - 0.3, "house", WHITE, "fbltd")    # beam
        fr.poly([(pf, s0, zp), (pf + 1.7, s0, zp - 0.3), (pf + 1.7, s1, zp - 0.3), (pf, s1, zp)], (0.2, 0, 1), "roof", roof_col)
        fr.poly([(pf, s1, zp - 0.05), (pf + 1.7, s1, zp - 0.35), (pf + 1.7, s0, zp - 0.35), (pf, s0, zp - 0.05)], (0, 0, -1), "house", WHITE)
        fr.poly([(pf + 1.7, s0, zp - 0.35), (pf + 1.7, s1, zp - 0.35), (pf + 1.7, s1, zp - 0.3), (pf + 1.7, s0, zp - 0.3)], (1, 0, 0), "house", WHITE)
    # chimney on the back slope near one end
    cs = r.u(0.3, 0.7) * hw * (1 if r.f() < 0.5 else -1)
    cf = main_fc - hd * r.u(0.15, 0.45)
    zr = zf(cf, cs)
    zr = max(zr, zf(cf + 0.4, cs + 0.4), zf(cf - 0.4, cs - 0.4), zf(cf + 0.4, cs - 0.4), zf(cf - 0.4, cs + 0.4))
    fr.box(cf - 0.4, cf + 0.4, cs - 0.4, cs + 0.4, H - 0.5, zr + 1.5, "house", tint, "fbltu")
    fr.box(cf - 0.5, cf + 0.5, cs - 0.5, cs + 0.5, zr + 1.3, zr + 1.5, "house", STONE, "fbltd")
    return w, d_out, len(m.faces) - n0


# =============================================================================
# CLOCK TOWER
# =============================================================================

def clock_tower(m, uv, x, y, z0, w=7.0, h=32.0):
    """A square shaft with string courses, a 5 m clock face on each side 6 m below the top, an open belfry and a
    pyramid roof with a finial."""
    n0 = len(m.faces)
    fr = Frame(m, uv, x, y, 0.0, z0)
    hw = w / 2.0
    zs = h - 4.4                                  # shaft top; belfry to h
    tb = _bands(zs)
    _vfix(fr, (hw, -hw), (hw, hw), tb, "plaster", WHITE, (0.0, 2 * COL / TILE))
    _vfix(fr, (hw, hw), (-hw, hw), tb, "plaster", WHITE, (0.0, 2 * COL / TILE))
    _vfix(fr, (-hw, hw), (-hw, -hw), tb, "plaster", WHITE, (0.0, 2 * COL / TILE))
    _vfix(fr, (-hw, -hw), (hw, -hw), tb, "plaster", WHITE, (0.0, 2 * COL / TILE))
    zc0, zc1 = h - 11.0, h - 6.0                  # clock panel
    k = 1
    while k * STOREY < zs - 0.5:
        zk = k * STOREY
        if not (zc0 - 0.6 < zk < zc1 + 0.6):
            fr.band(0.0, 0.0, hw, hw, zk - 0.15, zk + 0.15, 0.15, "plaster", STONE)
        k += 1
    fr.band(0.0, 0.0, hw, hw, zs - 0.4, zs, 0.3, "plaster", STONE)
    # clock faces: a panel 0.25 m proud on each side
    p = 0.25
    for k in range(4):
        a = math.radians(90.0 * k)
        nf, ns = math.cos(a), math.sin(a)          # outward
        tf, ts = -ns, nf                           # to the viewer's right
        c = (nf * (hw + p), ns * (hw + p))
        lo = (c[0] - tf * 2.5, c[1] - ts * 2.5)
        hi = (c[0] + tf * 2.5, c[1] + ts * 2.5)
        fr.poly([lo + (zc0,), hi + (zc0,), hi + (zc1,), lo + (zc1,)], (nf, ns, 0), "clock", WHITE,
                [(0.0, 0.5), (0.5, 0.5), (0.5, 1.0), (0.0, 1.0)])
        blo = (lo[0] - nf * p, lo[1] - ns * p)
        bhi = (hi[0] - nf * p, hi[1] - ns * p)
        fr.poly([bhi + (zc0,), hi + (zc0,), hi + (zc1,), bhi + (zc1,)], (tf, ts, 0), "plaster", STONE)
        fr.poly([lo + (zc0,), blo + (zc0,), blo + (zc1,), lo + (zc1,)], (-tf, -ts, 0), "plaster", STONE)
        fr.poly([blo + (zc1,), bhi + (zc1,), hi + (zc1,), lo + (zc1,)], (0, 0, 1), "plaster", STONE)
        fr.poly([lo + (zc0,), hi + (zc0,), bhi + (zc0,), blo + (zc0,)], (0, 0, -1), "plaster", STONE)
    zt = fr.belfry(0.0, 0.0, hw, zs, 0.6, 0.3)
    fr.roof(0.0, 0.0, hw + 0.3, hw + 0.3, zt, 1.2, 0.3, WHITE, soffit=True)
    fr.spire(0.0, 0.0, zt + 1.2 * (hw + 0.6) - 0.05, 0.2, 0.8)
    return len(m.faces) - n0


# =============================================================================
# TERRACE
# =============================================================================

def terrace(m, uv, x, y, yaw, w, d, z_top, z_low):
    """A flat building platform: grass top at z_top, a stone skirt down to z_low, a 0.6 m lip round its edge with a
    3 m gap mid-front (the door side)."""
    n0 = len(m.faces)
    fr = Frame(m, uv, x, y, yaw, 0.0)
    hw, hd = w / 2.0, d / 2.0
    ROCK, GRASS = (0.9, 0.86, 0.78, 1.0), (0.95, 1.0, 0.85, 1.0)
    fr.poly([(-hd, -hw, z_top), (hd, -hw, z_top), (hd, hw, z_top), (-hd, hw, z_top)], (0, 0, 1), "grass", GRASS)
    fr.box(-hd, hd, -hw, hw, z_low, z_top, "rock", ROCK, "fblt")
    z1, t = z_top + 0.6, 0.4
    fr.box(-hd, -hd + t, -hw, hw, z_top, z1, "rock", ROCK, "fbltu")                 # back
    for sg in (-1, 1):
        s0, s1 = sorted((sg * hw, sg * (hw - t)))
        fr.box(-hd + t, hd, s0, s1, z_top, z1, "rock", ROCK, "fbltu")              # sides
        s0, s1 = sorted((sg * (hw - t), sg * min(1.5, hw - t)))
        if s1 - s0 > 0.05:
            fr.box(hd - t, hd, s0, s1, z_top, z1, "rock", ROCK, "fbu" + ("t" if sg < 0 else "l"))   # front, gap mid
    return len(m.faces) - n0


# =============================================================================
# TEXTURES -- 0.05 m per texel, 64 px storey rows, row 0 at the image bottom (v up)
# =============================================================================

PLASTER = (240, 229, 205)
LINE = (214, 198, 168)
PLINTH = (198, 178, 146)
SURROUND = (218, 202, 170)
GLASS = (36, 50, 76)
GLINT = (70, 96, 130)
FRAMEC = (250, 248, 240)
SHUT = (66, 138, 128)
SHUT_D = (48, 108, 100)
SHUT_H = (72, 110, 168)
SHUT_HD = (54, 86, 136)
DOOR = (126, 76, 42)
DOOR_D = (96, 56, 30)


def _paint():
    from PIL import Image, ImageDraw
    out = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..",
                                        "maps", "beach", "textures"))

    def canvas():
        im = Image.new("RGB", (256, 256), PLASTER)
        return im, ImageDraw.Draw(im)

    def R(dr, row, x0, h0, x1, h1, col):
        """Fill x0..x1 (inclusive) between h0 and h1 px above the row's foot."""
        y1 = 255 - 64 * row - h0
        y0 = 255 - 64 * row - h1
        dr.rectangle((x0, y0, x1, y1), fill=col)

    def arch(dr, row, cx, half, h_spring, col):
        y = 255 - 64 * row - h_spring
        dr.pieslice((cx - half, y - half, cx + half - 1, y + half - 1), 180, 360, fill=col)

    def glass(dr, row, x0, h0, x1, h1, cross=True):
        R(dr, row, x0, h0, x1, h1, GLASS)
        for k in range(0, x1 - x0 + 4, 2):           # a diagonal glint band
            xa = x0 + k
            ha = h1 - 3 - k
            if x0 <= xa <= x1 and h0 <= ha <= h1:
                R(dr, row, xa, max(h0, ha - 4), min(x1, xa + 1), ha, GLINT)
        if cross:
            cx = (x0 + x1) // 2
            R(dr, row, cx, h0, cx + 1, h1, FRAMEC)

    def shutters(dr, row, x0, x1, h0, h1, wide, c, cd):
        for a, b in ((x0 - wide, x0 - 1), (x1 + 1, x1 + wide)):
            R(dr, row, a, h0, b, h1, c)
            for hh in range(h0 + 2, h1, 3):
                R(dr, row, a + 1, hh, b - 1, hh, cd)
            R(dr, row, a, h0, b, h0, cd)

    def window(dr, row, cx, h0, h1, half, c, cd, wide=10):
        x0, x1 = cx - half, cx + half - 1
        R(dr, row, x0 - 2, h0 - 3, x1 + 2, h0 - 1, SURROUND)          # sill
        R(dr, row, x0 - 1, h1 + 1, x1 + 1, h1 + 3, SURROUND)          # lintel
        R(dr, row, x0, h0, x1, h1, FRAMEC)
        glass(dr, row, x0 + 2, h0 + 2, x1 - 2, h1 - 2)
        R(dr, row, x0 + 2, (h0 + h1) // 2 + 3, x1 - 2, (h0 + h1) // 2 + 4, FRAMEC)
        shutters(dr, row, x0, x1, h0, h1, wide, c, cd)

    def door(dr, row, cx, half, top, arched):
        x0, x1 = cx - half, cx + half - 1
        if arched:
            spring = top - half
            R(dr, row, x0 - 3, 0, x1 + 3, spring, SURROUND)
            arch(dr, row, cx, half + 3, spring, SURROUND)
            R(dr, row, x0, 0, x1, spring, DOOR)
            arch(dr, row, cx, half, spring, GLASS)
            arch(dr, row, cx, half - 3, spring, GLINT)
            R(dr, row, x0, spring - 1, x1, spring, FRAMEC)
            R(dr, row, x0 - 3, spring - 1, x0 - 1, spring + 1, LINE)
            R(dr, row, x1 + 1, spring - 1, x1 + 3, spring + 1, LINE)
            R(dr, row, cx - 2, top, cx + 1, top + 3, PLINTH)             # keystone
        else:
            R(dr, row, x0 - 3, 0, x1 + 3, top + 3, SURROUND)
            R(dr, row, x0, 0, x1, top, DOOR)
            spring = top
        R(dr, row, cx, 0, cx, spring - 2, DOOR_D)                        # leaves
        for xa in (x0 + 3, cx + 3):
            R(dr, row, xa, 4, xa + half - 7, spring // 2 - 2, DOOR_D)
            R(dr, row, xa, spring // 2 + 2, xa + half - 7, spring - 5, DOOR_D)
            R(dr, row, xa + 1, 5, xa + half - 8, spring // 2 - 3, DOOR)
            R(dr, row, xa + 1, spring // 2 + 3, xa + half - 8, spring - 6, DOOR)
        R(dr, row, cx + 3, spring // 2 - 1, cx + 4, spring // 2, (220, 180, 80))   # handle

    # ---- hotel plaster: 4 columns of 64 px per row
    im, dr = canvas()
    R(dr, 0, 0, 0, 255, 5, PLINTH)
    R(dr, 0, 0, 6, 255, 6, LINE)
    for c in range(4):
        cx = 64 * c + 32
        if c % 2 == 0:
            door(dr, 0, cx, 12, 42, True)
        else:                                    # an arched shop window
            x0, x1 = cx - 14, cx + 13
            R(dr, 0, x0 - 3, 7, x1 + 3, 34, SURROUND)
            arch(dr, 0, cx, 17, 34, SURROUND)
            R(dr, 0, x0, 10, x1, 34, FRAMEC)
            arch(dr, 0, cx, 14, 34, FRAMEC)
            glass(dr, 0, x0 + 2, 12, x1 - 2, 34)
            arch(dr, 0, cx, 12, 34, GLASS)
            R(dr, 0, x0 + 2, 33, x1 - 2, 34, FRAMEC)
            R(dr, 0, cx - 2, 48, cx + 1, 51, PLINTH)
    R(dr, 0, 0, 60, 255, 63, LINE)
    for row in (1, 2, 3):
        R(dr, row, 0, 61, 255, 63, LINE)
        for c in range(4):
            cx = 64 * c + 32
            if c == 2:                           # balcony door
                x0, x1 = cx - 12, cx + 11
                R(dr, row, x0 - 1, 47, x1 + 1, 49, SURROUND)
                R(dr, row, x0, 1, x1, 46, FRAMEC)
                glass(dr, row, x0 + 2, 3, x1 - 2, 44)
                R(dr, row, x0 + 2, 30, x1 - 2, 31, FRAMEC)
                R(dr, row, x0 + 2, 16, x1 - 2, 17, FRAMEC)
                shutters(dr, row, x0, x1, 1, 46, 10, SHUT, SHUT_D)
            else:
                window(dr, row, cx, 18, 46, 10, SHUT, SHUT_D)
    im.save(os.path.join(out, "beach_plaster_albedo.png"))

    # ---- houses: door and two windows, then windows, then plain plaster (gables, chimneys)
    im, dr = canvas()
    R(dr, 0, 0, 0, 255, 4, PLINTH)
    for cx in (43, 213):
        window(dr, 0, cx, 18, 44, 11, SHUT_H, SHUT_HD)
    door(dr, 0, 128, 12, 42, False)
    R(dr, 0, 116, 0, 139, 1, PLINTH)
    for cx in (43, 128, 213):
        window(dr, 1, cx, 16, 44, 11, SHUT_H, SHUT_HD)
    R(dr, 1, 0, 0, 255, 1, LINE)
    im.save(os.path.join(out, "beach_house_albedo.png"))

    # ---- clock: one face in the top-left quarter, plaster elsewhere
    S = 4
    big = Image.new("RGB", (128 * S, 128 * S), (206, 188, 152))
    bd = ImageDraw.Draw(big)
    c = 64 * S
    bd.rectangle((3 * S, 3 * S, 125 * S - 1, 125 * S - 1), fill=(222, 206, 172))
    for rr, col in ((60, (64, 52, 40)), (57, (196, 156, 64)), (53, (250, 248, 238))):
        bd.ellipse((c - rr * S, c - rr * S, c + rr * S, c + rr * S), fill=col)
    for k in range(12):
        a = math.radians(30.0 * k)
        r0, r1, wd = (40, 51, 5) if k % 3 == 0 else (44, 51, 3)
        dx, dy = math.sin(a), -math.cos(a)
        bd.line((c + dx * r0 * S, c + dy * r0 * S, c + dx * r1 * S, c + dy * r1 * S), fill=(30, 28, 26), width=wd * S)
    for ang, ln, wd in ((300.0, 28, 6), (60.0, 42, 4)):
        a = math.radians(ang)
        bd.line((c, c, c + math.sin(a) * ln * S, c - math.cos(a) * ln * S), fill=(30, 28, 26), width=wd * S)
    bd.ellipse((c - 5 * S, c - 5 * S, c + 5 * S, c + 5 * S), fill=(30, 28, 26))
    im, dr = canvas()
    im.paste(big.resize((128, 128), Image.LANCZOS), (0, 0))
    im.save(os.path.join(out, "beach_clock_albedo.png"))
    print("textures ->", out)


# =============================================================================
# CHECK
# =============================================================================

def _check():
    def bbox(m, n0):
        vs = [m.verts[i] for f in m.faces[n0:] for i in f]
        return tuple(round(min(p[k] for p in vs), 2) for k in range(3)), tuple(round(max(p[k] for p in vs), 2) for k in range(3))

    def uv_ok(m, uv):
        for fi, f in enumerate(m.faces):
            if m.zones[fi] in TEXTURED:
                for vi in f:
                    assert (fi, vi) in uv, "face %d (%s) lacks uv" % (fi, m.zones[fi])

    total = Mesh()
    tuv = {}
    m, uv = Mesh(), {}
    n = hotel(m, uv, 0.0, 0.0, 30.0, 0.0)
    report(m, "hotel")
    print("hotel tris=%d bbox=%s" % (n, bbox(m, 0)))
    uv_ok(m, uv)
    assert n <= 3000
    hotel(total, tuv, 0.0, 0.0, 30.0, 0.0)
    for s in range(1, 7):
        m, uv = Mesh(), {}
        w, d, n = house(m, uv, 0.0, 0.0, 15.0 * s, 0.0, s)
        report(m, "house%d" % s)
        print("house%d w=%.1f d=%.1f tris=%d bbox=%s" % (s, w, d, n, bbox(m, 0)))
        uv_ok(m, uv)
        assert n <= 160
        house(total, tuv, 60.0 + 14.0 * s, 0.0, 15.0 * s, 0.0, s)
    m, uv = Mesh(), {}
    n = clock_tower(m, uv, 0.0, 0.0, 0.0)
    report(m, "clock_tower")
    print("clock_tower tris=%d bbox=%s" % (n, bbox(m, 0)))
    uv_ok(m, uv)
    assert n <= 400
    clock_tower(total, tuv, -40.0, 0.0, 0.0)
    m, uv = Mesh(), {}
    n = terrace(m, uv, 0.0, 0.0, 30.0, 14.0, 10.0, 2.0, -3.0)
    report(m, "terrace")
    print("terrace tris=%d bbox=%s" % (n, bbox(m, 0)))
    assert n <= 80
    terrace(total, tuv, 0.0, 60.0, 30.0, 14.0, 10.0, 2.0, -3.0)
    report(total, "all")
    uv_ok(total, tuv)
    print("all bbox=%s" % (bbox(total, 0),))


if __name__ == "__main__":
    if "--textures" in sys.argv:
        _paint()
    if "--check" in sys.argv:
        _check()
