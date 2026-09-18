"""map1_wall -- the shared language for map 1's cross-lane rock walls.

NOT A MODEL. There is no build() and no contract file here: this module is
imported by map1_divider_build.py and map1_start_wall_build.py, which are the
models. It is named `*_build.py` because that is what tools/modelling/model
ships to the PC alongside a build script.

PURE PYTHON -- no bpy, no mdl. It builds vertex/face/zone lists and nothing
else, so it can be run and proved with plain `python3` outside Blender. The
Blender half (the hell atlas, the material, the unwrap) is map1_skin_build.py.

THE FRAME. Every wall here spans the lane radially and is authored in the
local frame the .glb ships, which is rock_bars' frame:

    local x  the RADIAL span.  x = 0 is the lane (r = 52.0); x = -5.3 is the
             pit lip (r = 46.7) and x = +5.3 the foot of the outer wall
             (r = 57.3). 10.6 m of deck, exactly as rock_bars spans it.
    local y  TANGENTIAL -- the wall's thickness, and the direction the lap runs.
    local z  UP.  z = 0 is the deck surface (world y = 23.0).

Blender +Z -> Godot +Y, +X -> +X, +Y -> -Z, so in the .glb: X radial, Y up,
Z thickness. Origin is the base centre on the lane.

ONE CONTIGUOUS SHELL BY CONSTRUCTION. The wall is a 2-D grid of vertices --
a front vertex F[k][i] and a back vertex B[k][i] per column k, row i, plus one
ridge vertex R[k] per column. Every face in the wall, the crest, the mouth
soffit, the mouth jambs and the end caps is drawn from that one vertex set and
nothing is ever duplicated or welded afterwards, so `weld_report` returns
components=1 and duplicate_positions=0 for any spec.

The mouth is a hole in that grid, not a boolean: `floor_row[c]` is the lowest
row a cell draws, the jambs are the vertical bands at the columns where
floor_row steps, and the soffit is the down-facing band at floor_row. Cutting
it costs no new vertices, which is why it cannot leak.

The tangential wings ("hooks") that grip the pit lip are likewise not a
separate mass: they are the wall's own thickness swelling near an end, low
down. A radial slab on its own casts no shadow from a tower at the centre of
the ring -- a sight line from the axis to a body just past the wall crosses
the wall's plane out over the void at r ~ 18 m, never through the wall -- so
the cover a divider gives is made by the hook at the lip, and the hook is part
of the same shell.
"""

import math

# =============================================================================
# THE HELL ATLAS ZONES
# =============================================================================
# The four windows of map_base_build.py's 128 px atlas, as (u0, v0, u1, v1).
# map1_skin_build.asserts these against map_base_build's own constants at build
# time: this module is pure python and cannot import it, so the copy is checked
# rather than trusted.

ZONE_ROCK = (0.0, 0.5, 0.5, 1.0)     # dark red rock, the body
ZONE_SHADE = (0.5, 0.5, 1.0, 1.0)    # near-black: facets that sit recessed
ZONE_CARVE = (0.5, 0.0, 1.0, 0.5)    # dressed stone: cut faces, jambs, soffit
ZONE_EMBER = (0.0, 0.0, 0.5, 0.5)    # split open by brimstone -- the only glow

# The ring, from scenes/ring/bentham_ring.tscn's Route/Level1 and
# map_base_build.py. Restated here so a pure-python run has them.
INNER_R = 46.7
OUTER_R = 57.3
LANE_R = 52.0
DECK_Z = 23.0
CEIL_H = 8.5                          # rock ceiling this far over the deck
EYE_H = 1.65                          # a body's eye
BODY_H = 1.80
GUARD_EYE_Z = 28.70                   # room floor 27.05 (the scene's Tower node
                                      # at 25.35 + the glb's own floor 1.70) + EYE_H
JUMP_APEX = 1.11                      # run 11 m/s, jump 7 m/s, g 22


class Rng(object):
    """The house LCG -- map_base_build._Rng, so a wall is byte-identical every
    rebuild and its jitter belongs to the same family as the map's own rock."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def n(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def bits(self):
        return self.n() >> 12          # low bits are short-period

    def f(self):
        return self.n() / float(0x7FFFFFFF)

    def sf(self):
        return self.f() * 2.0 - 1.0

    def i(self, a, b):
        return a + self.bits() % (b - a + 1)

    def pick(self, seq):
        return seq[self.bits() % len(seq)]

    def held(self, n, amp, run):
        """A per-index bias held for runs: it steps, like cleaved rock."""
        out = [0.0] * n
        k = 0
        while k < n:
            m = self.i(*run)
            v = self.sf() * amp
            for kk in range(k, min(k + m, n)):
                out[kk] = v
            k += m
        return out


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


class Mesh(object):
    """Vertex/face accumulator. Every face states which way its normal must
    point and the winding is corrected against it, never assumed."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.zones = []

    def v(self, p):
        self.verts.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.verts) - 1

    def _emit(self, idx, want, zone):
        pts = [self.verts[j] for j in idx]
        n = _newell(pts)
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            idx = list(reversed(idx))
        if len(idx) == 4:              # split: the corners are not coplanar
            self.faces.append((idx[0], idx[1], idx[2]))
            self.faces.append((idx[0], idx[2], idx[3]))
            self.zones.append(zone)
            self.zones.append(zone)
        else:
            self.faces.append(tuple(idx))
            self.zones.append(zone)

    def quad(self, a, b, c, d, want, zone):
        if len({a, b, c, d}) < 4:      # a collapsed cell draws nothing
            return
        self._emit([a, b, c, d], want, zone)

    def tri(self, a, b, c, want, zone):
        if len({a, b, c}) < 3:
            return
        self._emit([a, b, c], want, zone)

    def fan(self, ring, want, zone):
        """Triangulate a closed ring from ring[0]."""
        for i in range(1, len(ring) - 1):
            self.tri(ring[0], ring[i], ring[i + 1], want, zone)

    # ---- proof ------------------------------------------------------------

    def tris(self):
        """[(p0, p1, p2), ...] -- the drawn faces, for the sight prover."""
        return [tuple(self.verts[j] for j in f) for f in self.faces]

    def weld_report(self, eps=1e-6):
        """Contiguity, measured on the authored lists before Blender ever sees
        them: connected components over shared vertices and over welded
        positions, duplicate positions, degenerate and loose."""
        key = {}
        weld = []
        dup = 0
        for p in self.verts:
            k = (round(p[0] / eps), round(p[1] / eps), round(p[2] / eps))
            if k in key:
                dup += 1
            else:
                key[k] = len(key)
            weld.append(key[k])

        def components(index):
            adj = {}
            for f in self.faces:
                ids = [index(j) for j in f]
                for a in ids:
                    adj.setdefault(a, set()).update(ids)
            seen = set()
            comps = 0
            for a in adj:
                if a in seen:
                    continue
                comps += 1
                stack = [a]
                seen.add(a)
                while stack:
                    b = stack.pop()
                    for c in adj[b]:
                        if c not in seen:
                            seen.add(c)
                            stack.append(c)
            return comps, len(seen)

        comps, used = components(lambda j: j)
        wcomps, _ = components(lambda j: weld[j])
        degen = 0
        for f in self.faces:
            a, b, c = (self.verts[j] for j in f)
            u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
            w = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
            cr = (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2],
                  u[0] * w[1] - u[1] * w[0])
            if 0.5 * math.sqrt(cr[0] ** 2 + cr[1] ** 2 + cr[2] ** 2) < 1e-9:
                degen += 1
        return {
            "tris": len(self.faces),
            "verts": len(self.verts),
            "components": comps,
            "welded_components": wcomps,
            "duplicate_positions": dup,
            "degenerate_tris": degen,
            "loose_verts": len(self.verts) - used,
        }


# =============================================================================
# THE SPEC -- every number a wall has. The build scripts are these, filled in.
# =============================================================================

class Mouth(object):
    """The way through: a cut through the wall's full thickness at the lane.

    The floor is the deck, untouched -- no sill, because the lane at r = 52 is
    walkable end to end and bots never jump. `spring_z` is where the jambs
    stop and the corbelled head starts; `head_z` is the crown at the centre.
    """

    def __init__(self, x_centre=0.0, width=3.2, spring_z=2.1, head_z=3.0,
                 steps=2, jag=0.06):
        self.x_centre = x_centre
        self.width = width
        self.spring_z = spring_z
        self.head_z = head_z
        self.steps = steps            # corbel steps each side of the crown
        self.jag = jag                # metres of wobble on a cut edge


class Hook(object):
    """A tangential wing: the wall's own thickness swelling at one end, low
    down, so that end grips the map's rock and casts a shadow along the lap.

    `reach` is how far the wing stands out each way from the wall's centre
    plane (so the mass is 2*reach thick there), `top_z` how high it stands,
    `run` how far along the radial span it fades back to the body thickness.
    """

    def __init__(self, reach=1.8, top_z=3.4, run=2.2, lip=0.0):
        self.reach = reach
        self.top_z = top_z
        self.run = run
        self.lip = lip                # extra drop of the base at this end


class WallSpec(object):
    """One cross-lane wall. Distances in metres, in the local frame above."""

    def __init__(self, **kw):
        # ---- the span ----------------------------------------------------
        self.x_in = -5.7              # inner end: 0.4 m over the pit lip
        self.x_out = 5.8              # outer end: 0.5 m into the outer wall
        self.base_z = -0.45           # the base plane, buried under the deck
        # ---- the body ----------------------------------------------------
        self.crest_z = 6.4            # nominal crest over the deck
        self.crest_jag = (-0.40, 0.95)  # ragged band around it, held in runs
        self.ridge_rise = (0.05, 0.45)  # the ridge line over the crest
        self.ridge_jag = 0.30         # ... and its tangential wander
        self.t_crest = 1.5            # full thickness at the crest
        self.t_body = 3.0             # ... at the deck
        self.t_skirt = 4.4            # ... at the base plane: the flared foot
        self.skirt_z = 0.9            # the skirt has faded by this height
        self.taper_p = 1.35           # thickness falls off with this exponent
        # ---- the rock ----------------------------------------------------
        self.rows = 11                # vertical rows in the body
        self.cols = 5                 # columns per span between the anchors
        self.x_jag = 0.18             # column wander, radial
        self.face_jag = 0.16          # face in/out, held in runs along x
        self.face_run = (1, 3)
        self.row_jag = 0.10           # row height wander
        self.shade_bias = -0.055      # metres of recess past which a face darks
        self.ember_bias = -0.115      # ... and past which a low face splits open
        # ---- the cut and the wings ---------------------------------------
        self.mouth = None
        self.hook_in = None
        self.hook_out = None
        # ---- the collider ------------------------------------------------
        self.coll_rows = 3            # the collider is this grid, jitter off
        self.coll_cols = 1
        self.seed = 1
        for k, v in kw.items():
            if not hasattr(self, k):
                raise KeyError("WallSpec has no field %r" % k)
            setattr(self, k, v)

    # ---- derived ---------------------------------------------------------

    @property
    def span(self):
        return self.x_out - self.x_in

    def r_of(self, x):
        """The ring radius a local x sits at."""
        return LANE_R + x


# =============================================================================
# THE GENERATOR
# =============================================================================

def wall_solid(spec, collider=False):
    """The wall, as one contiguous Mesh.

    Returns a Mesh whose `weld_report()["components"]` is 1 and whose
    `duplicate_positions` is 0. With ``collider=True`` the same shape is built
    on spec.coll_cols/coll_rows with every jitter at zero and no ridge: the
    nominal envelope of the drawn faces, mouth and hooks included, which is
    what ships as the `-colonly` node.

    See the module docstring for the grid; the build scripts hold the numbers.
    """
    m = Mesh()
    rng = Rng(spec.seed)
    mouth = spec.mouth
    zt = float(spec.crest_z)
    nrows = max(2, int(spec.coll_rows if collider else spec.rows))
    ncol = max(1, int(spec.coll_cols if collider else spec.cols))
    steps = 0 if (collider or mouth is None) else max(0, int(mouth.steps))

    # ---- the row lines ---------------------------------------------------
    # z = 0 is always one of them, so the mouth's floor is the deck itself
    # and nothing has to be trimmed to it; spring_z and every corbel step are
    # lines too, so the jambs and the soffit land on the spec's own numbers
    # rather than on whichever row happened to fall nearby. The collider
    # takes steps = 0, so its head is one flat band at spring_z -- the mouth
    # it opens is the part of the art's mouth that is clear at every x.
    zs = [float(spec.base_z), 0.0]
    i_spring = i_head = None
    rest = nrows - 1
    if mouth is not None and rest >= steps + 2:
        head = mouth.spring_z if steps == 0 else mouth.head_z
        free = rest - steps
        lo = max(1e-3, mouth.spring_z)
        hi = max(1e-3, zt - head)
        n_lo = max(1, min(free - 1, int(free * lo / (lo + hi) + 0.5)))
        n_hi = free - n_lo
        for j in range(1, n_lo + 1):
            zs.append(mouth.spring_z * j / float(n_lo))
        for j in range(1, steps + 1):
            zs.append(mouth.spring_z
                      + (head - mouth.spring_z) * j / float(steps))
        for j in range(1, n_hi + 1):
            zs.append(head + (zt - head) * j / float(n_hi))
        i_spring = 1 + n_lo
        i_head = i_spring + steps
    else:
        for j in range(1, rest + 1):
            zs.append(zt * j / float(rest))

    # ---- the columns -----------------------------------------------------
    # The anchors are the two ends, the mouth's two jambs, and the x at which
    # each hook has faded back to the body thickness. `cols` interior columns
    # go across the widest anchor span and every other span takes the same
    # column width to within half a column, so no span gets a sliver.
    xin, xout = float(spec.x_in), float(spec.x_out)
    hooks = []
    if spec.hook_in is not None and spec.hook_in.run > 1e-6:
        hooks.append((spec.hook_in, xin, 1.0))
    if spec.hook_out is not None and spec.hook_out.run > 1e-6:
        hooks.append((spec.hook_out, xout, -1.0))

    cut = mouth is not None and i_spring is not None and mouth.width > 1e-6
    mx0 = mx1 = 0.0
    if cut:
        mx0 = mouth.x_centre - 0.5 * mouth.width
        mx1 = mouth.x_centre + 0.5 * mouth.width
        cut = xin < mx0 and mx1 < xout
    anc = [xin, xout] + ([mx0, mx1] if cut else [])
    anc.sort()
    for hk, x0, sgn in hooks:
        xh = x0 + sgn * hk.run
        if xh <= xin or xh >= xout:
            continue
        if min(abs(xh - a) for a in anc) < 0.30:
            continue                   # closer than that and it is a sliver
        anc.append(xh)
        anc.sort()

    wide = max(anc[k + 1] - anc[k] for k in range(len(anc) - 1))
    wtar = wide / float(ncol + 1)
    xs = [anc[0]]
    fixed = [True]
    for k in range(len(anc) - 1):
        a, b = anc[k], anc[k + 1]
        n = max(0, int((b - a) / wtar + 0.5 + 1e-9) - 1)
        for j in range(1, n + 1):
            xs.append(a + (b - a) * j / float(n + 1))
            fixed.append(False)
        xs.append(b)
        fixed.append(True)
    ncols = len(xs)
    nk = ncols - 1                     # column segments
    gap = min(xs[k + 1] - xs[k] for k in range(nk))
    if not collider:
        xj = min(spec.x_jag, 0.30 * gap)
        for k in range(ncols):
            if not fixed[k]:
                xs[k] += rng.sf() * xj

    # ---- the held jitter -------------------------------------------------
    # Every one of these steps in runs of columns, the way cleaved rock does,
    # and every one of them is zero on the collider.
    crest = [zt] * ncols
    rz = [zt] * ncols
    ridy = [0.0] * ncols
    fo = [[[0.0] * ncols for _ in range(3)] for _ in range(2)]
    rj = [[0.0] * (nrows + 1) for _ in range(ncols)]
    if not collider:
        c0, c1 = spec.crest_jag
        hv = rng.held(ncols, 1.0, spec.face_run)
        for k in range(ncols):
            crest[k] = zt + c0 + 0.5 * (hv[k] + 1.0) * (c1 - c0)
        r0, r1 = spec.ridge_rise
        for k in range(ncols):
            rz[k] = r0 + rng.f() * (r1 - r0)
            ridy[k] = rng.sf() * spec.ridge_jag
        for f in range(2):
            for b in range(3):
                fo[f][b] = rng.held(ncols, spec.face_jag, spec.face_run)
        amp = min(spec.row_jag,
                  0.33 * min(zs[i + 1] - zs[i] for i in range(nrows)))
        for k in range(ncols):
            inm = cut and mx0 - 1e-6 <= xs[k] <= mx1 + 1e-6
            for i in range(1, nrows):
                if inm and i <= i_head:
                    continue           # the dressed courses stay true
                rj[k][i] = rng.sf() * amp
        for k in range(ncols):
            floor_k = zs[nrows - 1] + rj[k][nrows - 1]
            if crest[k] < floor_k + 0.12:
                crest[k] = floor_k + 0.12
            rz[k] += crest[k]
    else:
        for k in range(ncols):
            rz[k] = crest[k]           # no ridge: the collider top is flat

    # ---- thickness, the hooks, the lip -----------------------------------
    def _u(hk, x0, sgn, x):
        """1.0 where the hook is full, 0.0 where it has faded to the body."""
        u = (hk.run - sgn * (x - x0)) / hk.run
        u = 0.0 if u < 0.0 else (1.0 if u > 1.0 else u)
        return u * u * (3.0 - 2.0 * u)

    def _uany(x):
        u = 0.0
        for hk, x0, sgn in hooks:
            v = _u(hk, x0, sgn, x)
            if v > u:
                u = v
        return u

    def _reach(x, z):
        """The wing's half-thickness here: full to top_z less its shoulder,
        then rolled over. The roll is a third of the wing's height, which
        keeps every face of it steeper than 45 deg: nothing lands on it."""
        out = 0.0
        for hk, x0, sgn in hooks:
            u = _u(hk, x0, sgn, x)
            if u <= 0.0:
                continue
            fade = max(1e-3, 0.35 * hk.top_z)
            if z <= hk.top_z - fade:
                v = 1.0
            else:
                v = (hk.top_z - z) / fade
                v = 0.0 if v < 0.0 else v
            r = hk.reach * u * v
            if r > out:
                out = r
        return out

    def _lip(x):
        d = 0.0
        for hk, x0, sgn in hooks:
            v = hk.lip * _u(hk, x0, sgn, x)
            if v > d:
                d = v
        return d

    def _off(f, k, z):
        """The face's in/out bias at this height: three held bands, blended,
        so the rock cleaves along x and never leans back over z."""
        t = z / zt
        t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
        b = fo[f]
        if t < 0.5:
            u = t * 2.0
            return b[0][k] * (1.0 - u) + b[1][k] * u
        u = (t - 0.5) * 2.0
        return b[1][k] * (1.0 - u) + b[2][k] * u

    def _half(x, z, extra):
        """Half the thickness at (x, z). The body tapers to the crest, the
        skirt flares under the deck, the wing overrides both where it stands,
        and the skirt is dropped where the wing has taken over."""
        tz = z if z > 0.0 else 0.0
        if tz > zt:
            tz = zt
        t = spec.t_body + ((spec.t_crest - spec.t_body)
                           * (tz / zt) ** spec.taper_p)
        sk = 0.0
        if spec.skirt_z > 1e-6:
            s = (spec.base_z + spec.skirt_z - z) / spec.skirt_z
            s = 0.0 if s < 0.0 else (1.0 if s > 1.0 else s)
            sk = (spec.t_skirt - spec.t_body) * s
        h = 0.5 * t
        r = _reach(x, z)
        if r > h:
            h = r
        h += 0.5 * sk * (1.0 - _uany(x)) + extra
        return h if h > 0.15 else 0.15

    def _zn(bias, low):
        if bias < spec.ember_bias and low:
            return ZONE_EMBER
        if bias < spec.shade_bias:
            return ZONE_SHADE
        return ZONE_ROCK

    # ---- the mouth, as the lowest row each cell draws --------------------
    floor = [0] * nk
    if cut:
        seg = [c for c in range(nk)
               if xs[c] >= mx0 - 1e-6 and xs[c + 1] <= mx1 + 1e-6]
        ns = len(seg)
        for j, c in enumerate(seg):
            floor[c] = i_spring + min(steps, min(j, ns - 1 - j))
    # A column exists from the lowest row either of its two cells draws, so
    # nothing below the cut is authored and no vertex is left loose.
    col_low = []
    for k in range(ncols):
        lo_k = floor[k] if k < nk else floor[k - 1]
        if k > 0 and floor[k - 1] < lo_k:
            lo_k = floor[k - 1]
        col_low.append(lo_k)

    # ---- the one vertex set ----------------------------------------------
    F = [{} for _ in range(ncols)]
    B = [{} for _ in range(ncols)]
    R = [0] * ncols
    for k in range(ncols):
        x = xs[k]
        drop = _lip(x)
        for i in range(col_low[k], nrows + 1):
            if i == 0:
                z = zs[0] - drop
            elif i == nrows:
                z = crest[k]
            else:
                z = zs[i] + rj[k][i]
            F[k][i] = m.v((x, -_half(x, z, _off(0, k, z)), z))
            B[k][i] = m.v((x, _half(x, z, _off(1, k, z)), z))
        hc = _half(x, crest[k], 0.0)
        ry = ridy[k]
        if ry > 0.5 * hc:
            ry = 0.5 * hc
        elif ry < -0.5 * hc:
            ry = -0.5 * hc
        R[k] = m.v((x, ry, rz[k]))

    # ---- the faces, all of them off that one set -------------------------
    for c in range(nk):
        fr = floor[c]
        for i in range(fr, nrows):
            zm = 0.5 * (zs[i] + zs[i + 1])
            low = zm < 0.45 * zt
            bf = 0.5 * (_off(0, c, zm) + _off(0, c + 1, zm))
            bb = 0.5 * (_off(1, c, zm) + _off(1, c + 1, zm))
            m.quad(F[c][i], F[c + 1][i], F[c + 1][i + 1], F[c][i + 1],
                   (0.0, -1.0, 0.0), _zn(bf, low))
            m.quad(B[c][i], B[c + 1][i], B[c + 1][i + 1], B[c][i + 1],
                   (0.0, 1.0, 0.0), _zn(bb, low))
        m.quad(F[c][nrows], F[c + 1][nrows], R[c + 1], R[c],
               (0.0, 0.0, 1.0), ZONE_ROCK)
        m.quad(R[c], R[c + 1], B[c + 1][nrows], B[c][nrows],
               (0.0, 0.0, 1.0), ZONE_ROCK)
        if fr > 0:                     # the soffit: the mouth's own ceiling
            m.quad(F[c][fr], F[c + 1][fr], B[c + 1][fr], B[c][fr],
                   (0.0, 0.0, -1.0), ZONE_CARVE)

    for k in range(1, nk):             # the jambs: where floor_row steps
        a, b = floor[k - 1], floor[k]
        if a == b:
            continue
        want = (1.0, 0.0, 0.0) if b > a else (-1.0, 0.0, 0.0)
        for i in range(min(a, b), max(a, b)):
            m.quad(F[k][i], B[k][i], B[k][i + 1], F[k][i + 1],
                   want, ZONE_CARVE)

    for k, want in ((0, (-1.0, 0.0, 0.0)), (ncols - 1, (1.0, 0.0, 0.0))):
        for i in range(col_low[k], nrows):
            m.quad(F[k][i], B[k][i], B[k][i + 1], F[k][i + 1], want, ZONE_ROCK)
        if rz[k] - crest[k] > 1e-6:    # flat-topped collider closes already
            m.tri(F[k][nrows], B[k][nrows], R[k], want, ZONE_ROCK)
    return m
