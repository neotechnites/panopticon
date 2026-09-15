"""
marble_lane -- the LANE part of Map 2: the ring lane and its nosings, both
podium walls, the trough and the terraced inner bed with their marble spikes.
Nothing stands on the lane. Built into the shared welded _Mesh of
marble_build.py against its seam contract:

    lane_angles()      128 stations for everything from the inner bed's outer
                       band to the trough's inner rings
    seam_wall_foot()   192 chord stations at r 60, y FIELD_Z: the trough's
                       outermost ring, zippered from the 128-station ring at
                       r 59.7 -- the ONE boundary this part leaves open, for
                       marble_wall_build to start from

Everything else is closed: spikes are stitched into the bed's own floor cells
(a cell becomes a low pedestal ring and a pyramid), terrace risers and the podium walls
join their floors ring to ring, and bands whose two rings have different
station counts are zippered, never left as T-junctions.

    python3 tools/modelling/marble_lane_build.py     # audit this part alone
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import marble_build as mb  # noqa: E402

# =============================================================================
# TUNABLES (the geometry's numbers live in marble_build; these are this part's)
# =============================================================================

PEDESTAL = 0.12             # every spike stands on a low plinth this tall
SPIKE_P = (0.35, 0.55)      # spike probability: floor + span * a smooth field in [0,1]
CLUSTER_K = (2.3, 0.9)      # the field's wavelengths, metres: (radial-ish, along the ring) ... x2 octaves
SHORT_P = 0.15              # ... of the spiked cells, this many are short
SHORT_H = 0.45
H_JITTER = (0.85, 1.15)
BASE_FRAC = 0.4             # a base half-width never over this of the cell's smaller side
CENTRE_JIT = 0.6            # base centre wanders this far of the slack, either way
MIN_CELL_W = 0.9            # no spike in a cell narrower than this
SIGHT_MARGIN = 0.5          # tips stay this far under the guard's line to the lane

# rings of the inner bed, centre outward: (radius, station count). Two rings at
# a terrace riser (the floor changes height there).
INNER_RINGS = ((8.0, 32), (10.0, 32), (12.0, 32), (14.0, 32),
               (16.0, 64), (18.0, 64), (20.0, 64), (22.0, 64),
               (24.0, 64), (26.0, 64), (28.0, 64), (30.0, 64),
               (32.2, 130), (34.4, 130), (36.6, 130), (38.0, 130),
               (40.2, 130), (42.4, 130), (44.6, 130), (mb.INNER_R, 130))
TROUGH_RINGS = (mb.OUTER_R, 58.5, 59.7)

UP, DOWN = mb.UP, mb.DOWN
TWO_PI = mb.TWO_PI
ANG32 = [TWO_PI * i / 32 for i in range(32)]


# =============================================================================
# HELPERS
# =============================================================================

def _floor_z(rad):
    """The inner bed's floor at this radius: FIELD_Z at the lane, stepping down."""
    z = mb.FIELD_Z
    for (r_riser, z_in) in mb.TERRACES:
        if rad < r_riser - 1e-9:
            z = z_in
    return z


def _angles(n):
    if n == 130:
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


def _sight_z(rad):
    return mb.GUARD_EYE_Z - (rad / mb.LANE_R) * (mb.GUARD_EYE_Z - mb.DECK_Z)


def _field(rad, ang):
    """A smooth seeded 0..1 field over the bed: two octaves of sines, so the
    spikes come in clumps with thin patches between."""
    x, y = rad * math.cos(ang), rad * math.sin(ang)
    k0, k1 = TWO_PI / CLUSTER_K[0] / 3.0, TWO_PI / CLUSTER_K[1] / 3.0
    v = (math.sin(k0 * x + 1.3) * math.cos(k0 * y * 0.8 - 0.7)
         + 0.5 * math.sin(k1 * x * 0.7 - k1 * y * 0.4 + 2.1))
    return 0.5 + v / 3.0            # v in [-1.5, 1.5]


def _riser(m, angles, rad, z_lo, z_hi):
    """A vertical band at a terrace edge; the air is on the inside, so it faces the axis."""
    lo, hi = _ring(m, angles, rad, z_lo), _ring(m, angles, rad, z_hi)
    n = len(angles)
    for i in range(n):
        j = (i + 1) % n
        am = 0.5 * (angles[i] + (angles[j] if j else angles[0] + TWO_PI))
        e = _er(am)
        m.quad(lo[i], lo[j], hi[j], hi[i], (-e[0], -e[1], 0.0), "shade")


def _zip_line(m, side_a, side_b, want, zone):
    """Triangles between two open polylines ordered the same way (the two
    radial edges of a deck column with different station counts)."""
    i = j = 0
    while i < len(side_a) - 1 or j < len(side_b) - 1:
        if j == len(side_b) - 1 or (i < len(side_a) - 1 and side_a[i + 1][1] <= side_b[j + 1][1]):
            m.tri(side_a[i][0], side_a[i + 1][0], side_b[j][0], want, zone)
            i += 1
        else:
            m.tri(side_a[i][0], side_b[j + 1][0], side_b[j][0], want, zone)
            j += 1


# =============================================================================
# SPIKES -- a floor cell becomes a pedestal ring and a pyramid
# =============================================================================

class _Spikes(object):
    def __init__(self):
        self.r = mb._Rng(mb.SPIKE_SEED)
        self.inner = self.small = self.outer = 0
        self.clearance = 9.9
        self.lane_tip = 0.0

    def cell(self, m, lo_i, lo_j, hi_j, hi_i, r_lo, r_hi, a_i, a_j, z0, trough):
        """Decide and build the spike for one cell; returns False if the cell
        stays a plain floor quad."""
        r = self.r
        if a_j < a_i:
            a_j += TWO_PI
        rc, ac = 0.5 * (r_lo + r_hi), 0.5 * (a_i + a_j)
        depth, width = r_hi - r_lo, rc * (a_j - a_i)
        if width < MIN_CELL_W:
            return False
        p = SPIKE_P[0] + SPIKE_P[1] * _field(rc, ac)
        if r.f() > p:
            return False
        if trough:
            h = mb.OUT_H[0] + (mb.OUT_H[1] - mb.OUT_H[0]) * r.f()
            h = min(h, mb.OUT_TIP_CAP - PEDESTAL - z0)
        else:
            t = max(0.0, min(1.0, (46.0 - rc) / 36.0))
            h = (mb.IN_H[0] + (mb.IN_H[1] - mb.IN_H[0]) * t) * (H_JITTER[0] + (H_JITTER[1] - H_JITTER[0]) * r.f())
            h = min(h, _sight_z(rc) - SIGHT_MARGIN - PEDESTAL - z0)
            if rc > mb.IN_CAP_R:
                h = min(h, mb.IN_TIP_CAP - PEDESTAL - z0)
        short = r.f() < SHORT_P
        if short:
            h *= SHORT_H
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
        zb = z0 + PEDESTAL

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
        if trough:
            self.outer += 1
        else:
            self.inner += 1
            self.clearance = min(self.clearance, _sight_z(rb) - tip)
            if rb > mb.IN_CAP_R:
                self.lane_tip = max(self.lane_tip, tip)
        if short:
            self.small += 1
        return True


def _spike_band(m, angles, r_lo, r_hi, z, sp, trough=False, skip=()):
    """A floor band between two rings of the same station count; each cell a
    plain quad or a stitched spike."""
    lo, hi = _ring(m, angles, r_lo, z), _ring(m, angles, r_hi, z)
    n = len(angles)
    for i in range(n):
        j = (i + 1) % n
        if i in skip or not sp.cell(m, lo[i], lo[j], hi[j], hi[i], r_lo, r_hi, angles[i], angles[j], z, trough):
            m.quad(lo[i], lo[j], hi[j], hi[i], UP, "field")


# =============================================================================
# THE LANE
# =============================================================================

def _deck(m):
    """The lane at DECK_Z: 128 columns of DECK_RS facets. Nothing stands on
    it; the bars between finish and start are a scene node, as on Map 1."""
    ang = mb.lane_angles()
    n = len(ang)
    z = mb.DECK_Z
    rs = list(mb.DECK_RS)
    for i in range(n):
        a0, a1 = ang[i], ang[(i + 1) % n]
        lo = [m.v((r * math.cos(a0), r * math.sin(a0), z)) for r in rs]
        hi = [m.v((r * math.cos(a1), r * math.sin(a1), z)) for r in rs]
        for k in range(len(rs) - 1):
            m.quad(lo[k], hi[k], hi[k + 1], lo[k + 1], UP, "floor")
    return 0


def _nosings_and_podiums(m):
    ang = mb.lane_angles()
    n = len(ang)
    z, zl = mb.DECK_Z, mb.DECK_Z - mb.LIP
    deck_in, lip_in = _ring(m, ang, mb.DECK_RS[0], z), _ring(m, ang, mb.INNER_R, zl)
    deck_out, lip_out = _ring(m, ang, mb.DECK_RS[-1], z), _ring(m, ang, mb.OUTER_R, zl)
    foot_in, foot_out = _ring(m, ang, mb.INNER_R, mb.FIELD_Z), _ring(m, ang, mb.OUTER_R, mb.FIELD_Z)
    for i in range(n):
        j = (i + 1) % n
        am = 0.5 * (ang[i] + (ang[j] if j else ang[0] + TWO_PI))
        e = _er(am)
        m.quad(lip_in[i], lip_in[j], deck_in[j], deck_in[i], (-e[0], -e[1], 1.0), "shade")
        m.quad(deck_out[i], deck_out[j], lip_out[j], lip_out[i], (e[0], e[1], 1.0), "shade")
        m.quad(foot_in[i], foot_in[j], lip_in[j], lip_in[i], (-e[0], -e[1], 0.0), "shade")
        m.quad(foot_out[i], foot_out[j], lip_out[j], lip_out[i], e, "shade")


# =============================================================================
# THE BEDS
# =============================================================================

def _strip_columns():
    """Columns that get no spikes: none, now that nothing stands on the lane."""
    return set()


def _trough(m, sp):
    ang = mb.lane_angles()
    skip = _strip_columns()
    for k in range(len(TROUGH_RINGS) - 1):
        _spike_band(m, ang, TROUGH_RINGS[k], TROUGH_RINGS[k + 1], mb.FIELD_Z, sp, trough=True, skip=skip)
    stations, z = mb.seam_wall_foot()
    outer = [m.v(p) for p in mb.station_pts(stations, z)]
    inner = _ring(m, ang, TROUGH_RINGS[-1], mb.FIELD_Z)
    mb._zipper(m, outer, mb.station_angles(stations), inner, ang, UP, "field")


def _inner_bed(m, sp):
    hub = m.v((0.0, 0.0, _floor_z(0.0)))
    r0, n0 = INNER_RINGS[0]
    first = _ring(m, _angles(n0), r0, _floor_z(r0))
    for i in range(n0):
        m.tri(hub, first[i], first[(i + 1) % n0], UP, "field")
    risers = dict(mb.TERRACES)
    skip = _strip_columns()
    for k in range(len(INNER_RINGS) - 1):
        (ra, na), (rb, nb) = INNER_RINGS[k], INNER_RINGS[k + 1]
        z = _floor_z(0.5 * (ra + rb))
        if na == nb:
            _spike_band(m, _angles(na), ra, rb, z, sp, skip=skip if na == 130 else ())
        else:
            outer = _ring(m, _angles(nb), rb, z)
            inner = _ring(m, _angles(na), ra, z)
            mb._zipper(m, outer, _angles(nb), inner, _angles(na), UP, "field")
        if rb in risers and k + 1 < len(INNER_RINGS) - 1:
            _riser(m, _angles(nb), rb, _floor_z(rb - 0.01), _floor_z(rb + 0.01))


# =============================================================================
# THE PART
# =============================================================================

def build(m):
    sp = _Spikes()
    _inner_bed(m, sp)
    _nosings_and_podiums(m)
    _deck(m)
    _trough(m, sp)
    return {"spikes_inner": sp.inner, "spikes_small": sp.small, "spikes_outer": sp.outer,
            "sight_clearance": round(sp.clearance, 2), "lane_tip_max": round(sp.lane_tip, 2)}


def collider(c):
    """Light and purpose-built: flat deck, podium walls, trough floor, the
    terraces with their risers. Not required to be one
    surface -- Godot makes a concave shape of it."""
    ang = mb.lane_angles()
    n = len(ang)
    z = mb.DECK_Z
    rings = [_ring(c, ang, r, z) for r in (mb.INNER_R, 52.0, mb.OUTER_R)]
    for k in range(2):
        for i in range(n):
            j = (i + 1) % n
            c.quad(rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i], UP, "floor")
    foot_in, foot_out = _ring(c, ang, mb.INNER_R, mb.FIELD_Z), _ring(c, ang, mb.OUTER_R, mb.FIELD_Z)
    wall_foot = _ring(c, ang, mb.WALL_R, mb.FIELD_Z)
    for i in range(n):
        j = (i + 1) % n
        e = _er(0.5 * (ang[i] + (ang[j] if j else ang[0] + TWO_PI)))
        c.quad(foot_in[i], foot_in[j], rings[0][j], rings[0][i], (-e[0], -e[1], 0.0), "shade")
        c.quad(foot_out[i], foot_out[j], rings[2][j], rings[2][i], e, "shade")
        c.quad(foot_out[i], foot_out[j], wall_foot[j], wall_foot[i], UP, "field")
    # the terraces, 64 stations
    hub = c.v((0.0, 0.0, _floor_z(0.0)))
    prev = _ring(c, mb.ANG, 8.0, _floor_z(0.0))
    for i in range(64):
        c.tri(hub, prev[i], prev[(i + 1) % 64], UP, "field")
    for rad in (22.0, 30.0, 38.0, mb.INNER_R):
        z_in = _floor_z(rad - 0.01)
        ring = _ring(c, mb.ANG, rad, z_in)
        for i in range(64):
            j = (i + 1) % 64
            c.quad(prev[i], prev[j], ring[j], ring[i], UP, "field")
        prev = ring
        if rad != mb.INNER_R:
            top = _ring(c, mb.ANG, rad, _floor_z(rad + 0.01))
            for i in range(64):
                j = (i + 1) % 64
                e = _er(mb.ANG[i] + math.pi / 64)
                c.quad(ring[i], ring[j], top[j], top[i], (-e[0], -e[1], 0.0), "shade")
            prev = top


if __name__ == "__main__":
    m = mb._Mesh()
    n0 = 0
    counts = {}
    sp = _Spikes()
    for name, fn in (("inner_bed", lambda: _inner_bed(m, sp)), ("nosings_podiums", lambda: _nosings_and_podiums(m)),
                     ("deck", lambda: _deck(m)), ("trough", lambda: _trough(m, sp))):
        fn()
        counts[name] = len(m.faces) - n0
        n0 = len(m.faces)
    info = {"spikes_inner": sp.inner, "spikes_small": sp.small, "spikes_outer": sp.outer,
            "sight_clearance": round(sp.clearance, 2), "lane_tip_max": round(sp.lane_tip, 2)}
    a = mb.audit(m, "lane")
    print("parts", counts)
    print("boundary loops", mb.boundary_loops(m)[:3])
    print("info", info)
    c = mb._Mesh()
    collider(c)
    mb.audit(c, "lane_coll")
    ok = a["components"] == 1 and a["boundary_edges"] == 192 and a["doubled_edges"] == 0 \
        and a["over_edges"] == 0 and a["degenerate"] == 0 and a["duplicate_positions"] == 0
    print("LANE PART %s" % ("OK" if ok else "FAILED"))
    sys.exit(0 if ok else 1)
