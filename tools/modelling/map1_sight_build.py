"""map1_sight -- does the guard see past this wall?

NOT A MODEL. PURE PYTHON -- no bpy, no mdl, so it runs under plain `python3`
and the proof can be re-run without Blender.

The question is not rhetorical, and the answer is not obvious, because the
tower stands at the CENTRE of the ring. A sight line from a guard eye at
r <= 7 m to a body standing just past a radial wall crosses that wall's own
plane out over the void, around r = 18 m, and never touches the wall. A radial
slab therefore casts almost no shadow along the lap on its own: what a wall
across the lane can prove is the other thing -- that no sight line gets OVER
its crest or THROUGH its body, that the only way to see past it is the mouth,
and that the tangential hook at its inner end puts a real shadow on the deck
immediately behind it.

This module measures all of that, from the drawn faces, and hands back the
numbers. It never decides whether they are good enough.
"""

import math

INNER_R = 46.7
OUTER_R = 57.3
LANE_R = 52.0
DECK_Z = 23.0
EYE_H = 1.65
GUARD_EYE_Z = 28.70
JUMP_APEX = 1.11
# Steeper than this and a body slides off instead of standing:
# MovementProfile.max_floor_angle_degrees, 46 deg.
MAX_FLOOR_DEG = 46.0
FLOOR_COS = math.cos(math.radians(MAX_FLOOR_DEG))

# The guard: every eye a body in the tower room can have. THE ROOM FLOOR IS AT
# WORLD 27.05, not 25.35: 25.35 is where the scene hangs the Tower node, and
# the shipped tower.glb carries its own floor 1.70 m above its origin --
# TowerSpawn sits at local 1.95, which its own description calls "floor +
# 0.25". So the eye is 27.05 + 1.65 = 28.70, and 1.11 m more at the apex of a
# jump (the window kerbs are SILL_MIN = 1.20, so he cannot get above that).
# bentham_ring.tscn's note that the eye is 27.00, and MAP1_SECTIONS.md's
# "guard eye y = 27", both predate the floor being raised.
EYE_Z = (28.70, 29.25, 29.81)
EYE_R = (0.0, 3.5, 7.0)
EYE_BEARINGS = 24

# The deck the wall is meant to protect: a band of bearings past it, at the
# lane radius 0.36 m to 8.2 m along the lap, across the walkable width.
BAND_DEG = (0.4, 9.0)
TARGET_R = (47.4, 56.6)
TARGET_STEP = 1.2
BODY_Z = (0.40, 1.00, 1.65)


def place(tris, bearing_deg, lane_r=LANE_R, deck_z=DECK_Z):
    """Local (x radial, y tangential, z up) -> Godot world (x, y up, z).

    x = r cos t, z = r sin t is the scene's own convention: PrisonerStart at
    5 deg sits at (51.80, 23, 4.53) = 52 * (cos 5, ., sin 5).
    """
    t = math.radians(bearing_deg)
    ct, st = math.cos(t), math.sin(t)

    def w(p):
        r = lane_r + p[0]
        return (r * ct - p[1] * st, deck_z + p[2], r * st + p[1] * ct)

    return [tuple(w(q) for q in tri) for tri in tris]


# =============================================================================
# THE PROVER -- segment vs triangle, and the prefilter that pays for it
# =============================================================================
# ~2000 faces against ~30000 sight lines is 60 million triangle tests done
# naively, which is minutes of python. So the faces go into a 1 m uniform grid
# in WORLD space; every segment is clipped to the grid's box and then walked
# cell by cell (Amanatides-Woo), and a tri is tested at most once per segment.
# A line meets ~100 faces instead of all of them.


class _Grid(object):
    """The drawn faces in a uniform world-space grid, asked by segment."""

    def __init__(self, wtris, cell=1.0):
        self.cell = cell
        xs = [p[0] for t in wtris for p in t]
        ys = [p[1] for t in wtris for p in t]
        zs = [p[2] for t in wtris for p in t]
        pad = 1e-4
        self.lo = (min(xs) - pad, min(ys) - pad, min(zs) - pad)
        self.hi = (max(xs) + pad, max(ys) + pad, max(zs) + pad)
        self.n = tuple(int((self.hi[i] - self.lo[i]) / cell) + 1
                       for i in range(3))
        self.geom = []
        self.cells = {}
        self.stamp = [-1] * len(wtris)
        self.mark = 0
        n0, n1 = self.n[0], self.n[1]
        for i, t in enumerate(wtris):
            a, b, c = t
            self.geom.append((a,
                              (b[0] - a[0], b[1] - a[1], b[2] - a[2]),
                              (c[0] - a[0], c[1] - a[1], c[2] - a[2])))
            k0 = [0, 0, 0]
            k1 = [0, 0, 0]
            for d in range(3):
                q = min(a[d], b[d], c[d])
                k0[d] = int((q - self.lo[d]) / cell)
                q = max(a[d], b[d], c[d])
                k1[d] = int((q - self.lo[d]) / cell)
            for ix in range(k0[0], k1[0] + 1):
                for iy in range(k0[1], k1[1] + 1):
                    for iz in range(k0[2], k1[2] + 1):
                        self.cells.setdefault(ix + n0 * (iy + n1 * iz),
                                              []).append(i)

    # ---- the one question ------------------------------------------------

    def hit(self, a, b):
        """Does the open segment a->b cross any drawn face?"""
        lo, hi, cell = self.lo, self.hi, self.cell
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        dz = b[2] - a[2]
        t0, t1 = 0.0, 1.0
        for i, (o, d) in enumerate(((a[0], dx), (a[1], dy), (a[2], dz))):
            if -1e-12 < d < 1e-12:
                if o < lo[i] or o > hi[i]:
                    return False
                continue
            u = (lo[i] - o) / d
            v = (hi[i] - o) / d
            if u > v:
                u, v = v, u
            if u > t0:
                t0 = u
            if v < t1:
                t1 = v
            if t0 > t1:
                return False

        n0, n1, n2 = self.n
        idx = [0, 0, 0]
        for i, (o, d) in enumerate(((a[0], dx), (a[1], dy), (a[2], dz))):
            k = int((o + d * t0 - lo[i]) / cell)
            idx[i] = 0 if k < 0 else (self.n[i] - 1 if k >= self.n[i] else k)
        ix, iy, iz = idx
        step = [0, 0, 0]
        tmax = [1e30, 1e30, 1e30]
        tdel = [1e30, 1e30, 1e30]
        for i, (o, d) in enumerate(((a[0], dx), (a[1], dy), (a[2], dz))):
            if d > 1e-12:
                step[i] = 1
                tmax[i] = (lo[i] + (idx[i] + 1) * cell - o) / d
                tdel[i] = cell / d
            elif d < -1e-12:
                step[i] = -1
                tmax[i] = (lo[i] + idx[i] * cell - o) / d
                tdel[i] = -cell / d
        sx, sy, sz = step
        tmx, tmy, tmz = tmax
        tdx, tdy, tdz = tdel

        self.mark += 1
        mark = self.mark
        stamp = self.stamp
        geom = self.geom
        cells = self.cells
        while True:
            lst = cells.get(ix + n0 * (iy + n1 * iz))
            if lst is not None:
                for ti in lst:
                    if stamp[ti] == mark:
                        continue
                    stamp[ti] = mark
                    v0, e1, e2 = geom[ti]
                    pvx = dy * e2[2] - dz * e2[1]
                    pvy = dz * e2[0] - dx * e2[2]
                    pvz = dx * e2[1] - dy * e2[0]
                    det = e1[0] * pvx + e1[1] * pvy + e1[2] * pvz
                    if -1e-12 < det < 1e-12:
                        continue
                    inv = 1.0 / det
                    tx = a[0] - v0[0]
                    ty = a[1] - v0[1]
                    tz = a[2] - v0[2]
                    u = (tx * pvx + ty * pvy + tz * pvz) * inv
                    if u < 0.0 or u > 1.0:
                        continue
                    qx = ty * e1[2] - tz * e1[1]
                    qy = tz * e1[0] - tx * e1[2]
                    qz = tx * e1[1] - ty * e1[0]
                    v = (dx * qx + dy * qy + dz * qz) * inv
                    if v < 0.0 or u + v > 1.0:
                        continue
                    s = (e2[0] * qx + e2[1] * qy + e2[2] * qz) * inv
                    if 1e-7 < s < 1.0:
                        return True
            if tmx < tmy:
                if tmx < tmz:
                    if tmx > t1:
                        return False
                    ix += sx
                    if ix < 0 or ix >= n0:
                        return False
                    tmx += tdx
                else:
                    if tmz > t1:
                        return False
                    iz += sz
                    if iz < 0 or iz >= n2:
                        return False
                    tmz += tdz
            elif tmy < tmz:
                if tmy > t1:
                    return False
                iy += sy
                if iy < 0 or iy >= n1:
                    return False
                tmy += tdy
            else:
                if tmz > t1:
                    return False
                iz += sz
                if iz < 0 or iz >= n2:
                    return False
                tmz += tdz


def _ledge_z(tris, min_area=0.5, step=0.5):
    """The lowest broad up-facing shelf standing over the deck: what a body
    could jump onto. Local +z is world +y, so a STANDABLE face is one whose
    unit normal has z > FLOOR_COS -- the game's own limit, not a guess: a body
    slides off anything steeper than MovementProfile.max_floor_angle_degrees
    (46 deg, scenes/player/default_movement_profile.tres), so a 50 deg talus
    is not a ledge however broad it is. A looser threshold here reports the
    flare at the foot of a wall as somewhere to stand.

    Area is summed over a SHELF -- up-facing faces that share an edge and sit
    within `step` of each other in z -- and not per triangle. A jagged crest
    on an 11 x 5 grid splits one landable slab into a dozen 0.3 m^2 triangles,
    so a per-triangle threshold would measure the tessellation instead of the
    rock and would never fire at all. Returns None when there is nothing broad
    and flat enough to stand on anywhere over the deck.
    """
    up = {}
    for i, t in enumerate(tris):
        a, b, c = t
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        wx, wy, wz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        nx = uy * wz - uz * wy
        ny = uz * wx - ux * wz
        nz = ux * wy - uy * wx
        ln = math.sqrt(nx * nx + ny * ny + nz * nz)
        if ln < 1e-12 or nz / ln <= FLOOR_COS:
            continue
        up[i] = (0.5 * ln, min(a[2], b[2], c[2]))

    parent = dict((i, i) for i in up)

    def find(i):
        r = i
        while parent[r] != r:
            r = parent[r]
        while parent[i] != r:
            parent[i], i = r, parent[i]
        return r

    edge = {}
    for i in up:
        t = tris[i]
        for k in range(3):
            p, q = t[k], t[(k + 1) % 3]
            kp = (round(p[0] * 1e6), round(p[1] * 1e6), round(p[2] * 1e6))
            kq = (round(q[0] * 1e6), round(q[1] * 1e6), round(q[2] * 1e6))
            key = (kp, kq) if kp <= kq else (kq, kp)
            j = edge.get(key)
            if j is None:
                edge[key] = i
            elif abs(up[i][1] - up[j][1]) <= step:
                ri, rj = find(i), find(j)
                if ri != rj:
                    parent[ri] = rj

    shelf = {}
    for i in up:
        r = find(i)
        area, z = up[i]
        s = shelf.get(r)
        shelf[r] = (area, z) if s is None else (s[0] + area,
                                               z if z < s[1] else s[1])
    best = None
    for area, z in shelf.values():
        if area > min_area and z > 0.0 and (best is None or z < best):
            best = z                      # under the deck is not a ledge
    return best


def _crest_line(tris, x_min, x_max, step=0.5):
    """The wall's crest as a function of radius, measured off the faces: the
    highest rock standing on the wall's own centre plane (local y = 0) at each
    half-metre of radial span. Sampled with a straight-down ray, so a face
    with no vertex over the sample -- a mouth lintel, a flat cap -- is read at
    its true height instead of being missed. Bins with no rock are skipped."""
    prj = []
    for t in tris:
        a, b, c = t
        d = ((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
        if -1e-12 < d < 1e-12:          # edge-on from above: no top to stand on
            continue
        prj.append((a, b, c, 1.0 / d))
    out = []
    n = max(1, int(math.ceil((x_max - x_min) / step)))
    for k in range(n):
        x = x_min + (x_max - x_min) * (k + 0.5) / n
        best = None
        for a, b, c, inv in prj:
            px, py = x - a[0], -a[1]
            u = (px * (c[1] - a[1]) - py * (c[0] - a[0])) * inv
            if u < 0.0 or u > 1.0:
                continue
            v = ((b[0] - a[0]) * py - (b[1] - a[1]) * px) * inv
            if v < 0.0 or u + v > 1.0:
                continue
            z = a[2] + u * (b[2] - a[2]) + v * (c[2] - a[2])
            if best is None or z > best:
                best = z
        if best is not None:
            out.append(best)
    return out


def _eye_points():
    """Every eye a body in the tower room can have, in world space.
    EYE_R x EYE_BEARINGS x EYE_Z -- except that r = 0 is one point on the
    axis, not EYE_BEARINGS copies of the same point."""
    out = []
    for r in EYE_R:
        nb = 1 if r < 1e-9 else EYE_BEARINGS
        for k in range(nb):
            a = 2.0 * math.pi * k / EYE_BEARINGS
            x, z = r * math.cos(a), r * math.sin(a)
            for ez in EYE_Z:
                out.append((x, ez, z))
    return out


def _target_bodies(bearing_deg, lane_r, deck_z):
    """The deck the wall protects: [(r, (world body points, ...)), ...], one
    entry per BODY, sampled every TARGET_STEP along the lap and across the
    walkable width, each body standing at its BODY_Z points."""
    d0, d1 = BAND_DEG
    nb = max(1, int(round(math.radians(d1 - d0) * lane_r / TARGET_STEP)))
    r0, r1 = TARGET_R
    nr = max(1, int(round((r1 - r0) / TARGET_STEP)))
    out = []
    for i in range(nb + 1):
        t = math.radians(bearing_deg + d0 + (d1 - d0) * i / float(nb))
        ct, st = math.cos(t), math.sin(t)
        for j in range(nr + 1):
            r = r0 + (r1 - r0) * j / float(nr)
            out.append((r, tuple((r * ct, deck_z + bz, r * st)
                                 for bz in BODY_Z)))
    return out


def guard_report(tris, bearing_deg, mouth=None, **kw):
    """Measure one wall. ``tris`` are the DRAWN faces in the wall's own local
    frame; ``bearing_deg`` is where on the lap it stands. ``mouth`` is the
    (x_centre, width, head_z) of its way through, or None.

    Returns a dict with exactly these keys:

      eyes, targets, pairs        how many samples were taken
      blocked_pairs               fraction of (eye, body point) lines the wall
                                  stops
      hidden                      fraction of target BODIES hidden from EVERY
                                  guard eye (a body is hidden from an eye when
                                  every one of its BODY_Z points is blocked)
      hidden_inner                ... of the targets inside the lane (r < 52)
      hidden_outer                ... and outside it
      over_crest                  lines that pass over the crest inside the
                                  wall's radial span. MUST be 0.
      through_mouth               lines that get past only through the mouth
      past_the_lip                lines that reach the target without ever
                                  entering the wall's radial span -- the void
                                  crossing no wall in the annulus can stop
      crest_min_z, crest_max_z    the crest over the deck
      sight_max_z                 the highest a guard sight line reaches at
                                  the wall's plane, over the deck
      ledge_z                     the lowest broad up-facing face on the wall
                                  a body could land on. MUST be > 1.11.
      ceiling_clear               metres from the highest vertex to the
                                  gallery ceiling at 8.5 m

    and a "lines" list of the unblocked (eye, target) pairs for the report.
    """
    lane_r = kw.get("lane_r", LANE_R)
    deck_z = kw.get("deck_z", DECK_Z)
    if not tris:
        return dict(eyes=0, targets=0, pairs=0, blocked_pairs=0.0, hidden=0.0,
                    hidden_inner=0.0, hidden_outer=0.0, over_crest=0,
                    through_mouth=0, past_the_lip=0, crest_min_z=0.0,
                    crest_max_z=0.0, sight_max_z=0.0, ledge_z=0.0,
                    ceiling_clear=0.0, lines=[], measured=False)

    # ---- the wall itself, from its own faces ------------------------------
    x_min = y_min = 1e30
    x_max = y_max = z_max = -1e30
    for t in tris:
        for p in t:
            if p[0] < x_min:
                x_min = p[0]
            if p[0] > x_max:
                x_max = p[0]
            if p[1] < y_min:
                y_min = p[1]
            if p[1] > y_max:
                y_max = p[1]
            if p[2] > z_max:
                z_max = p[2]
    r_min, r_max = lane_r + x_min, lane_r + x_max
    ceiling_clear = 8.5 - z_max          # the gallery roof over the deck

    # The crest line: the bar a sight line would have to clear, at its lowest
    # point and its highest.
    crest = _crest_line(tris, x_min, x_max)
    crest_min_z = min(crest) if crest else z_max
    crest_max_z = max(crest) if crest else z_max

    # The lowest thing a body could land on, over the deck.
    ledge_z = _ledge_z(tris)
    if ledge_z is None:
        ledge_z = crest_max_z             # nothing but the crest to stand on

    # ---- the guard, the deck, and every line between them -----------------
    grid = _Grid(place(tris, bearing_deg, lane_r, deck_z))
    eyes = _eye_points()
    bodies = _target_bodies(bearing_deg, lane_r, deck_z)
    t0 = math.radians(bearing_deg)
    ct, st = math.cos(t0), math.sin(t0)
    sky = deck_z + 60.0
    mx = mwid = mhead = 0.0
    if mouth is not None:
        mx, mwid, mhead = mouth
    nz_body = len(BODY_Z)

    def loc(p):
        r = p[0] * ct + p[2] * st
        return (r - lane_r, -p[0] * st + p[2] * ct, p[1] - deck_z)

    eye_loc = [loc(p) for p in eyes]
    blocked = 0
    over_crest = through_mouth = past_the_lip = 0
    hid = hid_in = hid_out = n_in = n_out = 0
    sight_max_z = -1e30
    lines = []

    for r_body, pts in bodies:
        inner = r_body < lane_r
        if inner:
            n_in += 1
        else:
            n_out += 1
        pts_loc = [loc(p) for p in pts]
        body_hidden = True
        for ei in range(len(eyes)):
            a = eyes[ei]
            lax, lay, laz = eye_loc[ei]
            seen = False
            for bi in range(nz_body):
                b = pts[bi]
                lbx, lby, lbz = pts_loc[bi]

                # the highest this line gets where the wall actually stands
                s0, s1, ok = 0.0, 1.0, True
                for pa, pb, mn, mxv in ((lax, lbx, x_min, x_max),
                                        (lay, lby, y_min, y_max)):
                    d = pb - pa
                    if -1e-12 < d < 1e-12:
                        if pa < mn or pa > mxv:
                            ok = False
                            break
                        continue
                    u = (mn - pa) / d
                    v = (mxv - pa) / d
                    if u > v:
                        u, v = v, u
                    if u > s0:
                        s0 = u
                    if v < s1:
                        s1 = v
                    if s0 > s1:
                        ok = False
                        break
                if ok:
                    za = laz + (lbz - laz) * s0
                    zb = laz + (lbz - laz) * s1
                    if zb > za:
                        za = zb
                    if za > sight_max_z:
                        sight_max_z = za

                if grid.hit(a, b):
                    blocked += 1
                    continue
                seen = True
                lines.append((a, b))

                # How did it get past? Where the line crosses the wall's own
                # centre plane is the only place the wall could have been
                # between the eye and the body.
                if (lay <= 0.0 <= lby) or (lby <= 0.0 <= lay):
                    d = lby - lay
                    s = 0.0 if -1e-12 < d < 1e-12 else (-lay / d)
                    cx = lax + (lbx - lax) * s
                    cz = laz + (lbz - laz) * s
                    cr = lane_r + cx
                    if cr < r_min or cr > r_max:
                        past_the_lip += 1
                    elif (mouth is not None and abs(cx - mx) <= 0.5 * mwid
                          and -0.01 <= cz <= mhead):
                        through_mouth += 1
                    elif cz >= 0.0:
                        wp = (a[0] + (b[0] - a[0]) * s,
                              a[1] + (b[1] - a[1]) * s,
                              a[2] + (b[2] - a[2]) * s)
                        if not grid.hit(wp, (wp[0], sky, wp[2])):
                            over_crest += 1   # no rock above it: over the top
                else:
                    past_the_lip += 1
            if seen:
                body_hidden = False
        if body_hidden:
            hid += 1
            if inner:
                hid_in += 1
            else:
                hid_out += 1

    n_eye, n_body_tot = len(eyes), len(bodies)
    pairs = n_eye * n_body_tot * nz_body
    if sight_max_z < -1e29:
        sight_max_z = 0.0
    return dict(eyes=n_eye, targets=n_body_tot, pairs=pairs,
                blocked_pairs=blocked / float(pairs),
                hidden=hid / float(n_body_tot),
                hidden_inner=hid_in / float(n_in or 1),
                hidden_outer=hid_out / float(n_out or 1),
                over_crest=over_crest, through_mouth=through_mouth,
                past_the_lip=past_the_lip, crest_min_z=crest_min_z,
                crest_max_z=crest_max_z, sight_max_z=sight_max_z,
                ledge_z=ledge_z, ceiling_clear=ceiling_clear,
                lines=lines, measured=True)


def format_report(rep):
    """One or two `MDL STATS sight ...` lines, every number named."""
    if not rep.get("measured", True):
        return "MDL STATS sight not measured"
    return ("MDL STATS sight eyes=%d targets=%d pairs=%d blocked_pairs=%.4f "
            "hidden=%.4f hidden_inner=%.4f hidden_outer=%.4f\n"
            "MDL STATS sight over_crest=%d through_mouth=%d past_the_lip=%d "
            "crest_min_z=%.2f crest_max_z=%.2f sight_max_z=%.2f ledge_z=%.2f "
            "ceiling_clear=%.2f unblocked=%d"
            % (rep["eyes"], rep["targets"], rep["pairs"], rep["blocked_pairs"],
               rep["hidden"], rep["hidden_inner"], rep["hidden_outer"],
               rep["over_crest"], rep["through_mouth"], rep["past_the_lip"],
               rep["crest_min_z"], rep["crest_max_z"], rep["sight_max_z"],
               rep["ledge_z"], rep["ceiling_clear"], len(rep["lines"])))
