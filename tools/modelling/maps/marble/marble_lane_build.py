"""
marble_lane -- the LANE part of Map 2: the spike floor under the rotunda and
the gallery walkway slab partway up the wall of cells. Nothing stands on the
lane. Built into the shared welded _Mesh of marble_build.py against its seam
contract:

    lane_angles()      128 stations: the floor's outer rings, the deck, the
                       nosing, the inner face and the underside
    seam_wall_foot()   192 chord stations at r 60, y FLOOR_Z: the floor's
                       outermost ring, zippered from the 64-station ring at
                       r 59.0 -- left open for marble_wall_build to start from
    seam_slab()        192 stations of the slab tier's cornice front at
                       SLAB_Z0 and DECK_Z: the underside zippers out to the
                       lower ring, the deck margin to the upper -- both left
                       open for the wall's cornice to close onto

THE FLOOR: one disc at FLOOR_Z from a hub at the axis to the wall foot, no
hole under the tower (the tower stands on it). Rings of pitch ~SPIKE_PITCH:
32 stations to r 16, 64 to r 30, 128 out to r 47, then 64 in two coarse rings
under the walkway out to r 59.0, each change of count a zipper. Spikes are stitched into the floor's own cells between SPIKE_R0 and
SPIKE_R1: a cell becomes a low pedestal ring and a pyramid. No terraces, no
sight caps -- the floor is 24 m under the walkway. Every tip is under
FLOOR_Z + 3.0.

THE SLAB: the deck at DECK_Z (128 x DECK_RS facets), a chamfered nosing down
to the open inner edge at INNER_R, the inner face down to SLAB_Z0, the
underside out to OUTER_R and on to the cornice soffit line, the deck margin
out to the cornice top line.

Everything else is closed. The part's boundary is exactly three loops of 192
edges: the floor foot, the slab soffit, the slab top. Alone, the part is TWO
pieces (the floor, the slab): the wall joins them, 24 m apart, into the one
stone.

    python3 tools/modelling/maps/marble/marble_lane_build.py     # audit this part alone
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

if __name__ == "__main__":                # the wall part is not needed to audit this one
    import types
    sys.modules.setdefault("marble_wall_build", types.ModuleType("marble_wall_build"))

import marble_build as mb  # noqa: E402

# =============================================================================
# TUNABLES (the geometry's numbers live in marble_build; these are this part's)
# =============================================================================

PEDESTAL = 0.12             # every spike stands on a low plinth this tall
SPIKE_P = (0.40, 0.55)      # spike probability: floor + span * a smooth field in [0,1]
CLUSTER_K = (2.3, 0.9)      # the field's wavelengths, metres: (radial-ish, along the ring) ... x2 octaves
H_JITTER = (0.85, 1.15)
BASE_FRAC = 0.4             # a base half-width never over this of the cell's smaller side
CENTRE_JIT = 0.6            # base centre wanders this far of the slack, either way
MIN_CELL_W = 0.9            # no spike in a cell narrower than this
TIP_CAP = mb.FLOOR_Z + 3.0  # no tip over this

# the floor's rings, hub outward: (outer radius, station count, pitch) per
# band; ~SPIKE_PITCH where spikes stand, coarse under the walkway where
# nothing stands and nobody alive looks. The outermost is the 64-ring the
# wall foot zippers from.
FLOOR_BANDS = ((16.0, 32, mb.SPIKE_PITCH), (30.0, 64, mb.SPIKE_PITCH),
               (47.0, 128, mb.SPIKE_PITCH), (59.0, 64, 6.0))


def _floor_rings():
    out = []
    r0 = 0.0
    for (r1, n, pitch) in FLOOR_BANDS:
        k = max(1, int(round((r1 - r0) / pitch)))
        for i in range(1, k + 1):
            out.append((r0 + (r1 - r0) * i / k, n))
        r0 = r1
    return tuple(out)


FLOOR_RINGS = _floor_rings()

UP, DOWN = mb.UP, mb.DOWN
TWO_PI = mb.TWO_PI
ANG32 = [TWO_PI * i / 32 for i in range(32)]


# =============================================================================
# HELPERS
# =============================================================================

def _angles(n):
    if n == 128:
        return mb.lane_angles()
    if n == 64:
        return mb.ANG
    return ANG32


def _ring(m, angles, rad, z):
    """Vertex ids of a ring; the registry hands back existing ones."""
    return [m.v((rad * math.cos(a), rad * math.sin(a), z)) for a in angles]


def _er(a):
    return (math.cos(a), math.sin(a), 0.0)


def _et(a):
    return (-math.sin(a), math.cos(a), 0.0)


def _mid(angles, i):
    j = (i + 1) % len(angles)
    return 0.5 * (angles[i] + (angles[j] if j else angles[0] + TWO_PI))


def _field(rad, ang):
    """A smooth seeded 0..1 field over the floor: two octaves of sines, so the
    spikes come in clumps with thin patches between."""
    x, y = rad * math.cos(ang), rad * math.sin(ang)
    k0, k1 = TWO_PI / CLUSTER_K[0] / 3.0, TWO_PI / CLUSTER_K[1] / 3.0
    v = (math.sin(k0 * x + 1.3) * math.cos(k0 * y * 0.8 - 0.7)
         + 0.5 * math.sin(k1 * x * 0.7 - k1 * y * 0.4 + 2.1))
    return 0.5 + v / 3.0            # v in [-1.5, 1.5]


# =============================================================================
# SPIKES -- a floor cell becomes a pedestal ring and a pyramid
# =============================================================================

class _Spikes(object):
    def __init__(self):
        self.r = mb._Rng(mb.SPIKE_SEED)
        self.count = self.small = 0
        self.tip_max = -9.9
        self.tip_min = 9.9

    def cell(self, m, lo_i, lo_j, hi_j, hi_i, r_lo, r_hi, a_i, a_j, z0):
        """Decide and build the spike for one cell; returns False if the cell
        stays a plain floor quad."""
        r = self.r
        if a_j < a_i:
            a_j += TWO_PI
        rc, ac = 0.5 * (r_lo + r_hi), 0.5 * (a_i + a_j)
        if not (mb.SPIKE_R0 <= rc <= mb.SPIKE_R1):
            return False
        depth, width = r_hi - r_lo, rc * (a_j - a_i)
        if width < MIN_CELL_W:
            return False
        p = SPIKE_P[0] + SPIKE_P[1] * _field(rc, ac)
        if r.f() > p:
            return False
        zb = z0 + PEDESTAL
        h = mb.SPIKE_H[0] + (mb.SPIKE_H[1] - mb.SPIKE_H[0]) * r.f()
        h *= H_JITTER[0] + (H_JITTER[1] - H_JITTER[0]) * r.f()
        h = min(h, TIP_CAP - zb)
        small = (self.count + 1) % mb.SMALL_EVERY == 0     # every third spike is a small one
        if small:
            h *= mb.SMALL_H
        bw = mb.BASE_K[0] + mb.BASE_K[1] * h
        cap = BASE_FRAC * min(depth, width)
        if bw > cap:                                    # a fat spike in a small cell: shrink it whole
            bw = cap
            h = (bw - mb.BASE_K[0]) / mb.BASE_K[1]
        if h < 0.3:
            return False
        # the base centre: near the cell's, wandering within the slack
        jr = CENTRE_JIT * (0.5 * depth - bw)
        jt = CENTRE_JIT * (0.5 * width - bw)
        rb = rc + r.sf() * jr
        ab = ac + r.sf() * jt / rc
        er, et = _er(ab), _et(ab)
        cx, cy = rb * math.cos(ab), rb * math.sin(ab)

        def at(sr, st):
            return (cx + er[0] * sr * bw + et[0] * st * bw, cy + er[1] * sr * bw + et[1] * st * bw, zb)

        b0, b1, b2, b3 = m.v(at(-1, -1)), m.v(at(-1, 1)), m.v(at(1, 1)), m.v(at(1, -1))
        m.quad(lo_i, lo_j, b1, b0, UP, "field")          # the pedestal ring, rising to the base
        m.quad(lo_j, hi_j, b2, b1, UP, "field")
        m.quad(hi_j, hi_i, b3, b2, UP, "field")
        m.quad(hi_i, lo_i, b0, b3, UP, "field")
        apex = m.v((cx, cy, zb + h))
        for (p, q, w) in ((b0, b1, (-er[0], -er[1], 0.0)), (b1, b2, et), (b2, b3, er),
                          (b3, b0, (-et[0], -et[1], 0.0))):
            m.tri(p, q, apex, (w[0], w[1], 0.3), "spike")
        tip = zb + h
        self.count += 1
        self.small += 1 if small else 0
        self.tip_max = max(self.tip_max, tip)
        self.tip_min = min(self.tip_min, tip)
        return True


def _spike_band(m, angles, r_lo, r_hi, z, sp):
    """A floor band between two rings of the same station count; each cell a
    plain quad or a stitched spike."""
    lo, hi = _ring(m, angles, r_lo, z), _ring(m, angles, r_hi, z)
    n = len(angles)
    for i in range(n):
        j = (i + 1) % n
        if not sp.cell(m, lo[i], lo[j], hi[j], hi[i], r_lo, r_hi, angles[i], angles[j], z):
            m.quad(lo[i], lo[j], hi[j], hi[i], UP, "field")


# =============================================================================
# THE SPIKE FLOOR
# =============================================================================

def _floor(m, sp):
    """One disc at FLOOR_Z: hub, rings of ~SPIKE_PITCH, zippers where the
    station count doubles, and the wall foot seam as the outermost ring."""
    z = mb.FLOOR_Z
    hub = m.v((0.0, 0.0, z))
    r0, n0 = FLOOR_RINGS[0]
    first = _ring(m, _angles(n0), r0, z)
    for i in range(n0):
        m.tri(hub, first[i], first[(i + 1) % n0], UP, "field")
    for k in range(len(FLOOR_RINGS) - 1):
        (ra, na), (rb, nb) = FLOOR_RINGS[k], FLOOR_RINGS[k + 1]
        if na == nb:
            _spike_band(m, _angles(na), ra, rb, z, sp)
        else:
            outer, inner = _ring(m, _angles(nb), rb, z), _ring(m, _angles(na), ra, z)
            mb._zipper(m, outer, _angles(nb), inner, _angles(na), UP, "field")
    stations, zf = mb.seam_wall_foot()
    outer = [m.v(p) for p in mb.station_pts(stations, zf)]
    rl, nl = FLOOR_RINGS[-1]
    inner = _ring(m, _angles(nl), rl, zf)
    mb._zipper(m, outer, mb.station_angles(stations), inner, _angles(nl), UP, "field")


# =============================================================================
# THE WALKWAY SLAB
# =============================================================================

def _deck(m):
    """The lane at DECK_Z: 128 columns of DECK_RS facets. Nothing stands on
    it; the bars between finish and start are a scene node, as on Map 1."""
    ang = mb.lane_angles()
    n = len(ang)
    z = mb.DECK_Z
    rings = [_ring(m, ang, r, z) for r in mb.DECK_RS]
    for k in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            m.quad(rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i], UP, "floor")


def _edge(m):
    """The open inner edge: the nosing down from the deck to INNER_R, and the
    inner face from there down to the slab's underside, facing the axis."""
    ang = mb.lane_angles()
    n = len(ang)
    deck_in = _ring(m, ang, mb.DECK_RS[0], mb.DECK_Z)
    lip = _ring(m, ang, mb.INNER_R, mb.DECK_Z - mb.LIP)
    foot = _ring(m, ang, mb.INNER_R, mb.SLAB_Z0)
    for i in range(n):
        j = (i + 1) % n
        e = _er(_mid(ang, i))
        m.quad(lip[i], lip[j], deck_in[j], deck_in[i], (-e[0], -e[1], 1.0), "shade")
        m.quad(foot[i], foot[j], lip[j], lip[i], (-e[0], -e[1], 0.0), "shade")


def _underside(m):
    """The slab's soffit at SLAB_Z0, facing down: INNER_R out to OUTER_R on
    128 stations, then zippered to the cornice's soffit line."""
    ang = mb.lane_angles()
    n = len(ang)
    z = mb.SLAB_Z0
    inner, outer = _ring(m, ang, mb.INNER_R, z), _ring(m, ang, mb.OUTER_R, z)
    for i in range(n):
        j = (i + 1) % n
        m.quad(inner[i], inner[j], outer[j], outer[i], DOWN, "shade")
    stations, z_soffit, _z_top = mb.seam_slab()
    seam = [m.v(p) for p in mb.station_pts(stations, z_soffit)]
    mb._zipper(m, seam, mb.station_angles(stations), outer, ang, DOWN, "shade")


def _margin(m):
    """The plain stone between the paving's outer ring and the cornice's top line."""
    ang = mb.lane_angles()
    stations, _z_soffit, z_top = mb.seam_slab()
    seam = [m.v(p) for p in mb.station_pts(stations, z_top)]
    deck_out = _ring(m, ang, mb.DECK_RS[-1], z_top)
    mb._zipper(m, seam, mb.station_angles(stations), deck_out, ang, UP, "marble2")


# =============================================================================
# THE PART
# =============================================================================

def _stages(m, sp):
    return (("floor", lambda: _floor(m, sp)), ("deck", lambda: _deck(m)), ("edge", lambda: _edge(m)),
            ("underside", lambda: _underside(m)), ("margin", lambda: _margin(m)))


def _info(sp):
    return {"spikes": sp.count, "spikes_small": sp.small,
            "tip_max": round(sp.tip_max, 2), "tip_min": round(sp.tip_min, 2)}


def build(m):
    sp = _Spikes()
    for _name, fn in _stages(m, sp):
        fn()
    return _info(sp)


def collider(c):
    """Light and purpose-built: the floor disc, the flat deck, the inner face,
    the underside. Not required to be one surface -- Godot makes a concave
    shape of it. The spikes are not colliders: a body that leaves the walkway
    is dead by the kill cylinder before it lands."""
    z = mb.FLOOR_Z
    hub = c.v((0.0, 0.0, z))
    prev = _ring(c, mb.ANG, 30.0, z)
    for i in range(64):
        c.tri(hub, prev[i], prev[(i + 1) % 64], UP, "field")
    foot = _ring(c, mb.ANG, mb.WALL_R, z)
    for i in range(64):
        j = (i + 1) % 64
        c.quad(prev[i], prev[j], foot[j], foot[i], UP, "field")
    ang = mb.lane_angles()
    n = len(ang)
    r_out = mb.WALL_R - mb.BAND_PROUD
    rings = [_ring(c, ang, r, mb.DECK_Z) for r in (mb.INNER_R, 52.0, r_out)]
    for k in range(2):
        for i in range(n):
            j = (i + 1) % n
            c.quad(rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i], UP, "floor")
    under_in, under_out = _ring(c, ang, mb.INNER_R, mb.SLAB_Z0), _ring(c, ang, r_out, mb.SLAB_Z0)
    for i in range(n):
        j = (i + 1) % n
        e = _er(_mid(ang, i))
        c.quad(under_in[i], under_in[j], rings[0][j], rings[0][i], (-e[0], -e[1], 0.0), "shade")
        c.quad(under_in[i], under_in[j], under_out[j], under_out[i], DOWN, "shade")


if __name__ == "__main__":
    m = mb._Mesh()
    n0 = 0
    counts = {}
    sp = _Spikes()
    for name, fn in _stages(m, sp):
        fn()
        counts[name] = len(m.faces) - n0
        n0 = len(m.faces)
    info = _info(sp)
    a = mb.audit(m, "lane")
    loops = mb.boundary_loops(m)
    print("parts", counts)
    print("info", info)
    print("boundary loops", [(n, round(r, 2), round(z, 2)) for (n, r, z) in loops])
    c = mb._Mesh()
    collider(c)
    mb.audit(c, "lane_coll")
    ok = a["components"] == 2 and a["boundary_edges"] == 576 and a["doubled_edges"] == 0 \
        and a["over_edges"] == 0 and a["degenerate"] == 0 and a["duplicate_positions"] == 0 \
        and len(loops) == 3 and all(n == 192 for (n, _r, _z) in loops) \
        and info["tip_max"] <= TIP_CAP + 1e-6
    print("LANE PART %s (pieces=%d: floor + slab; the wall joins them)" % ("OK" if ok else "FAILED", a["components"]))
    sys.exit(0 if ok else 1)
