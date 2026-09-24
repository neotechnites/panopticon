"""
PANOPTICON -- marble_arch: a free-standing archway for Map 2 (marble), a
blockout prop Ryan places by hand. Two piers carrying a round arch: the piers
are the cover, the opening is the sight line.

    4.00 m across, 5.00 m tall; 1.20 m thick at the panel, 1.44 at the
    piers, 1.64 at the socle and the cornice
    opening 2.20 m wide, 3.00 m to the crown -- a runner goes through at 11 m/s

It reads as part of the rotunda because it is built out of the rotunda's own
vocabulary. The head is marble_wall_build's arch: a SEMICIRCLE of mb.HEAD_SEG
segments springing off a straight jamb, with the reveal in "shade" -- here the
reveal runs clean through, so the opening is a passage and not a cell, and the
head is cut twice as fine because a runner passes within a hand's width of it. The
mouldings are the wall's, scaled to five metres instead of eight:

    socle       a plain ashlar band 0.70 m tall, SOCLE_PROUD of the face
                ("plinth"), the wall's socle under every sill; the opening
                runs through it, so each pier stands on its own block
    piers       the wall's pilaster, the full width of the pier: PIER_PROUD
                of the recessed panel, fluted ("column"), running from the
                socle's top up INTO the cornice
    panel       the recessed face the arch is cut in ("marble" / "marble2"),
                a 0.20 m margin either side of the jamb and the spandrel over
                the crown
    cornice     a 0.85 m capping band, "band" front over a "shade" soffit --
                the wall's tier cornice, on the socle's own line

ONE CONTIGUOUS MESH. The stone is an axis-aligned cell complex over three
station lists (X, Y, Z) plus the arch; `_band_surface` emits exactly the faces
that separate stone from air, on grid lines both sides agree on, so there are
no T-junctions anywhere and mb._Mesh.v welds every shared vertex. The arch's
spandrel frames and intrados are the only non-grid faces: they are rays from
the springing centre (mb._ray_box, marble_wall's own method), and PANEL_HW and
CORNICE_Z0 are chosen so the ray to the panel box's top corner lands EXACTLY
on the head's 60 degree segment -- so the frame is seg+1 rays, no slivers, and
its side edges land on the Z stations the piers are already cut at.

Origin is the BASE CENTRE: z = 0 is the ground it stands on, x runs across the
face, y is the passage axis (Blender +Z -> Godot +Y, +Y -> -Z). Blender "front"
is -y, so a runner passes through along y and the sight line is down y.

MarbleArchCollision rides in the .glb as a `-colonly` node, built on the same
station lists and the same arch: the socle a body trips over, the piers it takes
cover behind, the arch it runs under, and the opening cut clean through -- the
stone's own outline, ray for ray, so what looks passable is passable. Two things
the eye gets and the body does not: the panel's 0.12 m recess and the cornice's
0.22 m overhang, both collapsed onto the pier line.

    python3 tools/modelling/maps/marble/marble_arch_build.py --check    # geometry, no Blender
    tools/modelling/model build marble_arch                 # the pipeline

The column-0 `import x_build as y` lines are what tools/modelling/model ships
to the PC: keep them at column 0.
"""

import math
import os
import sys

try:
    import bpy
except ImportError:                       # --check on the Mac: geometry only
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import marble_build as mb  # noqa: E402
# marble_build imports its two part modules at its foot; they ride along to the
# PC only when a column-0 `import x_build as y` names them in THIS script.
import marble_lane_build as _ml  # noqa: E402, F401
import marble_wall_build as _mw  # noqa: E402, F401

if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["views"] = ["threequarter", "front"]
    mdl.DEFAULTS["world_grey"] = 0.22
    mdl.DEFAULTS["world_strength"] = 0.60

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "marble_arch"
OBJECT_NAME = "MarbleArch"
COLLIDER_NAME = "MarbleArchCollision-colonly"
FACING_YAW = 0.0            # the face a runner meets is -y: Blender's own front

# The wall's semicircular head, twice as finely cut. A cell of the rotunda is
# 4 m wide and read from twelve metres off across the spike floor; this one a
# runner passes THROUGH, a hand's width from the reveal, and mb.HEAD_SEG
# facets read as a pointed arch at that range. Same circle, same springing,
# same jamb -- twice the segments. SEG must be a multiple of 3, so the panel
# box's top corner (at 60 degrees) is one of the head's own rays.
SEG = 2 * mb.HEAD_SEG

HALF_W = 2.00               # the shaft: 4.00 m across ...
HALF_D = 0.60               # ... 1.20 m thick
TOP_Z = 5.00                # 5.00 m tall

OPEN_HW = 1.10              # the opening: 2.20 m wide ...
SPRING_Z = 1.90             # ... springing here, so the crown is at 3.00

PANEL_HW = 1.30             # the recessed panel: 0.20 m of face each side of
                            # the jamb; the piers are the 0.70 m either side

SOCLE_Z = 0.70              # the socle band, the wall's socle under a sill
SOCLE_PROUD = 0.22          # base and cap on one line ...
CORNICE_PROUD = 0.22        # ... so the piers stand back 0.10 from both
PIER_PROUD = 0.12           # the pilaster, the full width of the pier

CORNER_T = math.pi / 3.0    # the panel box's top corner, as a ray from the
                            # springing centre: a head ray, so no sliver
CORNICE_Z0 = SPRING_Z + PANEL_HW * math.tan(CORNER_T)            # 4.1517

SOCLE_HW = HALF_W + SOCLE_PROUD
SOCLE_HD = HALF_D + SOCLE_PROUD
PIER_HD = HALF_D + PIER_PROUD
CORNICE_HW = HALF_W + CORNICE_PROUD
CORNICE_HD = HALF_D + CORNICE_PROUD

DEDUPE = 1.0e-6             # two rays this close in angle are one ray
EMPTY, SOLID, ARCH = 0, 1, 2
EYE_H = mb.EYE_H            # 1.65: the eye of a 1.8 m prisoner


def _dedupe(vals):
    out = []
    for v in sorted(vals):
        if not out or v - out[-1] > DEDUPE:
            out.append(v)
    return out


def _rays():
    """The head's angles about the springing centre, springing to springing."""
    return [math.pi * k / SEG for k in range(SEG + 1)]


# ---- the station grid the stone is cut on ----------------------------------
# Every ray that leaves the panel box through a SIDE puts a vertex on the
# pier's own return, and every ray that leaves through the TOP puts one on the
# cornice's soffit. Both are grid faces, so both stations are grid stations --
# that is the whole of why this mesh has no T-junction.

SIDE_ZS = _dedupe(SPRING_Z + PANEL_HW * math.tan(t)
                  for t in _rays() if DEDUPE < t < CORNER_T - DEDUPE)
TOP_XS = _dedupe((CORNICE_Z0 - SPRING_Z) * math.cos(t) / math.sin(t)
                 for t in _rays() if CORNER_T + DEDUPE < t < math.pi - CORNER_T - DEDUPE)

X = _dedupe([-CORNICE_HW, -SOCLE_HW, -HALF_W, -PANEL_HW, -OPEN_HW,
             OPEN_HW, PANEL_HW, HALF_W, SOCLE_HW, CORNICE_HW] + TOP_XS)
Y = _dedupe([-CORNICE_HD, -SOCLE_HD, -PIER_HD, -HALF_D,
             HALF_D, PIER_HD, SOCLE_HD, CORNICE_HD])
Z = [0.0, SOCLE_Z, SPRING_Z] + SIDE_ZS + [CORNICE_Z0, TOP_Z]

SOCLE_B, LOWER_B = 0, 1
CORNICE_B = len(Z) - 2      # the arch owns every band between LOWER_B and this

# The cornice soffit breaks over the panel wherever the grid does; the frame's
# rays reach TOP_XS and the box's corners, so anything else is welded in.
SPLITS = tuple((x, CORNICE_Z0) for x in X
               if -PANEL_HW + DEDUPE < x < PANEL_HW - DEDUPE
               and all(abs(x - t) > DEDUPE for t in TOP_XS))


def _mid(vals, k):
    return 0.5 * (vals[k] + vals[k + 1])


def occ(b, i, j):
    """Is cell (band b, x interval i, y interval j) stone? ARCH marks the
    panel over the springing, whose faces the arch builds instead."""
    x, y = abs(_mid(X, i)), abs(_mid(Y, j))
    if b == SOCLE_B:
        return SOLID if OPEN_HW < x < SOCLE_HW and y < SOCLE_HD else EMPTY
    if b == CORNICE_B:
        return SOLID if x < CORNICE_HW and y < CORNICE_HD else EMPTY
    if PANEL_HW < x < HALF_W:                       # a pier, the full shaft
        return SOLID if y < PIER_HD else EMPTY
    if x > PANEL_HW or y > HALF_D:                  # the panel's recess
        return EMPTY
    if b == LOWER_B:                                # under the springing
        return SOLID if x > OPEN_HW else EMPTY
    return ARCH


# =============================================================================
# ZONES -- the rotunda's atlas cells, by which face of which band
# =============================================================================

def zone_of(axis, sign, b, i, j):
    """The atlas zone of the face the cell complex is about to emit."""
    if axis == "x":
        face = X[i] if sign < 0 else X[i + 1]
        if abs(abs(face) - OPEN_HW) < DEDUPE:
            return "shade"                # the reveal: the passage's jambs
        return "plinth" if b == SOCLE_B else ("band" if b == CORNICE_B else "marble")
    if axis == "y":
        if b == SOCLE_B:
            return "plinth"
        if b == CORNICE_B:
            return "band"
        if abs(_mid(X, i)) > PANEL_HW:
            return "column"               # the pilaster's fluted front
        return "marble" if sign < 0 else "marble2"
    return "plinth" if (b == SOCLE_B and sign < 0) else "shade"


# =============================================================================
# GEOMETRY -- the cell complex, and the arch's rays
# =============================================================================

def _band_surface(m, X, Y, Z, occ, zone_of):
    """Boundary faces of an axis-aligned cell complex into m.
    X, Y, Z ascending station lists (nx+1, ny+1, nz+1 long).
    occ(b, i, j) -> 0 empty | 1 solid | 2 special; outside the grid is 0.
    For every neighbouring cell pair along x, y and z emit ONE m.quad when
    exactly one side is solid and the other empty; emit nothing when either
    side is special. The want-normal points away from the solid cell.
    zone_of(axis, sign, b, i, j) -> str, axis in 'xyz', sign the +-1 outward
    normal direction, (b,i,j) the SOLID cell; pass it as the quad's zone.
    Returns the quad count."""
    nx, ny, nz = len(X) - 1, len(Y) - 1, len(Z) - 1

    def state(b, i, j):
        """The cell's occupancy; outside the grid is empty."""
        if 0 <= b < nz and 0 <= i < nx and 0 <= j < ny:
            return occ(b, i, j)
        return 0

    quads = 0

    # ---- x: the wall at X[i+1] between cells i and i+1, spanning y by z ----
    for b in range(nz):
        for j in range(ny):
            for i in range(-1, nx):
                lo, hi = state(b, i, j), state(b, i + 1, j)
                if lo == 2 or hi == 2 or lo == hi:
                    continue
                x = X[i + 1]
                y0, y1, z0, z1 = Y[j], Y[j + 1], Z[b], Z[b + 1]
                sign = 1 if lo == 1 else -1
                cell = (b, i, j) if lo == 1 else (b, i + 1, j)
                m.quad(m.v((x, y0, z0)), m.v((x, y1, z0)),
                       m.v((x, y1, z1)), m.v((x, y0, z1)),
                       (float(sign), 0.0, 0.0),
                       zone_of("x", sign, cell[0], cell[1], cell[2]))
                quads += 1

    # ---- y: the wall at Y[j+1] between cells j and j+1, spanning x by z ----
    for b in range(nz):
        for i in range(nx):
            for j in range(-1, ny):
                lo, hi = state(b, i, j), state(b, i, j + 1)
                if lo == 2 or hi == 2 or lo == hi:
                    continue
                y = Y[j + 1]
                x0, x1, z0, z1 = X[i], X[i + 1], Z[b], Z[b + 1]
                sign = 1 if lo == 1 else -1
                cell = (b, i, j) if lo == 1 else (b, i, j + 1)
                m.quad(m.v((x0, y, z0)), m.v((x1, y, z0)),
                       m.v((x1, y, z1)), m.v((x0, y, z1)),
                       (0.0, float(sign), 0.0),
                       zone_of("y", sign, cell[0], cell[1], cell[2]))
                quads += 1

    # ---- z: the deck at Z[b+1] between bands b and b+1, spanning x by y ----
    for i in range(nx):
        for j in range(ny):
            for b in range(-1, nz):
                lo, hi = state(b, i, j), state(b + 1, i, j)
                if lo == 2 or hi == 2 or lo == hi:
                    continue
                z = Z[b + 1]
                x0, x1, y0, y1 = X[i], X[i + 1], Y[j], Y[j + 1]
                sign = 1 if lo == 1 else -1
                cell = (b, i, j) if lo == 1 else (b + 1, i, j)
                m.quad(m.v((x0, y0, z)), m.v((x1, y0, z)),
                       m.v((x1, y1, z)), m.v((x0, y1, z)),
                       (0.0, 0.0, float(sign)),
                       zone_of("z", sign, cell[0], cell[1], cell[2]))
                quads += 1

    return quads


def arch_chains(hw, sp, seg, u0, u1, z0, z1):
    """Rays from the springing centre (0, sp).

    thetas: the head's seg+1 angles k*pi/seg plus the rays to the four corners
    of the box [u0,u1]x[z0,z1], sorted ascending and deduped to DEDUPE.
    inner[k]: (hw*cos t, sp + hw*sin t), on the head circle.
    outer[k]: where that ray leaves the box (mb._ray_box).

    Requires u0 < -hw < hw < u1, z0 == sp and z1 > sp + hw, so the head stands
    clear of the jambs, springs off the box's floor line and clears its head.
    """
    assert u0 < -hw < hw < u1, "the head must stand clear of both jambs"
    assert abs(z0 - sp) < mb.EPS, "the springing line is the box's floor line"
    assert z1 > sp + hw, "the box must clear the crown of the head"
    assert seg >= 1 and hw > 0.0

    ths = [math.pi * k / seg for k in range(seg + 1)]
    for (x, z) in ((u1, z0), (u1, z1), (u0, z1), (u0, z0)):
        ths.append(math.atan2(z - sp, x) % mb.TWO_PI)
    ths.sort()
    thetas = []
    for t in ths:
        if not thetas or t - thetas[-1] > DEDUPE:
            thetas.append(t)

    inner = [(hw * math.cos(t), sp + hw * math.sin(t)) for t in thetas]
    outer = [mb._ray_box(0.0, sp, t, u0, u1, z0, z1) for t in thetas]
    return (thetas, inner, outer)


def _split_buckets(thetas, cz, splits):
    """The extra outer points, bucketed into the ray interval they fall in and
    ordered along the chain. They are vertices a NEIGHBOURING face puts on the
    box's boundary -- the cornice soffit breaks over the panel at +-OPEN_HW,
    the frame's own rays do not -- and a frame cell that ignores one leaves a
    T-junction, which is a hole in a mesh that is meant to be closed."""
    extra = [[] for _ in range(len(thetas) - 1)]
    for (u, z) in splits:
        t = math.atan2(z - cz, u) % mb.TWO_PI
        for k in range(len(thetas) - 1):
            if thetas[k] + DEDUPE < t < thetas[k + 1] - DEDUPE:
                extra[k].append((t, (u, z)))
                break
        else:
            raise RuntimeError("outer split (%.4f, %.4f) is on a ray, not between two" % (u, z))
    for k in range(len(extra)):
        extra[k].sort()
    return extra


def arch_faces(m, chains, hd, zone_front, zone_back, zone_reveal, splits=()):
    """Clothe the chains into `m`: the spandrel frame in the plane y = -hd,
    the same frame at y = +hd, and the intrados sweeping the inner chain
    between them. `splits` are extra points on the box's boundary that a
    neighbouring face already breaks at; each is welded into the outer edge of
    the cell it falls in, so the frame carries no T-junction. Returns the
    number of emitted faces."""
    thetas, inner, outer = chains
    n = len(thetas)
    quads = 0
    sp_z = 0.5 * (inner[0][1] + inner[-1][1])
    extra = _split_buckets(thetas, sp_z, splits)

    for (y, want, zone) in ((-hd, (0.0, -1.0, 0.0), zone_front),
                            (+hd, (0.0, 1.0, 0.0), zone_back)):
        vin = [m.v((u, y, z)) for (u, z) in inner]
        vout = [m.v((u, y, z)) for (u, z) in outer]
        for k in range(n - 1):
            if not extra[k]:
                m.quad(vin[k], vin[k + 1], vout[k + 1], vout[k], want, zone)
            else:                     # the outer edge runs back down in angle
                ring = [vin[k], vin[k + 1], vout[k + 1]]
                ring += [m.v((u, y, z)) for (_t, (u, z)) in reversed(extra[k])]
                ring.append(vout[k])
                m.fan(ring, want, zone)
            quads += 1

    # the intrados: the inner chain swept through the passage. The springing
    # centre is the midpoint of the chain's two springing points (thetas[0] is
    # always 0 and thetas[-1] always pi), so it needs no second argument.
    cx = 0.5 * (inner[0][0] + inner[-1][0])
    cz = 0.5 * (inner[0][1] + inner[-1][1])
    vfr = [m.v((u, -hd, z)) for (u, z) in inner]
    vbk = [m.v((u, +hd, z)) for (u, z) in inner]
    for k in range(n - 1):
        mx = 0.5 * (inner[k][0] + inner[k + 1][0])          # the quad's midpoint:
        mz = 0.5 * (inner[k][1] + inner[k + 1][1])          # y cancels, -hd and +hd
        want = (cx - mx, 0.0, cz - mz)                      # pointing at the centre
        if abs(want[0]) + abs(want[2]) < mb.EPS:
            want = (0.0, 0.0, -1.0)
        m.quad(vfr[k], vfr[k + 1], vbk[k + 1], vbk[k], want, zone_reveal)
        quads += 1
    return quads


# =============================================================================
# THE COLLIDER -- the drawn faces, at the pier line, the passage clear
# =============================================================================
# What a body can touch, on the SAME stations and the SAME arch: the socle it
# trips over, the piers it takes cover behind, the arch it runs under. Two
# things the eye gets and the body does not -- the panel's 0.12 m recess and
# the cornice's 0.22 m overhang -- are collapsed onto the pier line: the first
# is a 0.20 m strip beside each jamb, the second is 4.15 m up over a 1.11 m
# jump. The opening is the stone's own outline, ray for ray, so what looks
# passable is passable.

COLL_ZONE = "marble"        # one zone; Godot drops the collider's mesh on import

CX = _dedupe([-SOCLE_HW, -HALF_W, -PANEL_HW, -OPEN_HW,
              OPEN_HW, PANEL_HW, HALF_W, SOCLE_HW] + TOP_XS)
CY = [-SOCLE_HD, -PIER_HD, PIER_HD, SOCLE_HD]


def _coll_occ(b, i, j):
    """The collider's massing, band by band."""
    x, y = abs(_mid(CX, i)), abs(_mid(CY, j))
    if b == SOCLE_B:
        return SOLID if OPEN_HW < x < SOCLE_HW and y < SOCLE_HD else EMPTY
    if y > PIER_HD:
        return EMPTY
    if b == CORNICE_B:
        return SOLID if x < HALF_W else EMPTY
    if b == LOWER_B:
        return SOLID if OPEN_HW < x < HALF_W else EMPTY
    if PANEL_HW < x < HALF_W:
        return SOLID
    return ARCH if x < PANEL_HW else EMPTY


def _coll_zone(axis, sign, b, i, j):
    return COLL_ZONE


def coll_profile():
    """The collider's head polyline -- the stone's own, ray for ray."""
    return arch_chains(OPEN_HW, SPRING_Z, SEG, -PANEL_HW, PANEL_HW,
                       SPRING_Z, CORNICE_Z0)


def collider(c):
    """marble_arch's purpose-built collider: ONE closed solid over the model's
    own Z stations, with the archway's opening cut clean through along y."""
    quads = _band_surface(c, CX, CY, Z, _coll_occ, _coll_zone)
    quads += arch_faces(c, coll_profile(), PIER_HD,
                        COLL_ZONE, COLL_ZONE, COLL_ZONE, splits=SPLITS)
    return quads


# =============================================================================
# THE STONE
# =============================================================================

def _stone():
    """The archway in one welded mesh, and the numbers."""
    m = mb._Mesh()
    grid = _band_surface(m, X, Y, Z, occ, zone_of)
    chains = arch_chains(OPEN_HW, SPRING_Z, SEG, -PANEL_HW, PANEL_HW,
                         SPRING_Z, CORNICE_Z0)
    # the cornice soffit breaks over the panel at the opening's own jamb lines:
    # the frame's rays do not reach them, so they are welded in as splits.
    arch = arch_faces(m, chains, HALF_D, "marble", "marble2", "shade", splits=SPLITS)
    return m, {"grid_quads": grid, "arch_quads": arch, "rays": len(chains[0])}


def _poly_half(inner, z):
    """Half the clear opening at height z, off a head polyline actually built
    -- the jamb under the springing, the polyline (never the ideal circle) over it."""
    if z <= SPRING_Z:
        return OPEN_HW
    best = 0.0
    for k in range(len(inner) - 1):
        (x0, z0), (x1, z1) = inner[k], inner[k + 1]
        if min(z0, z1) - DEDUPE <= z <= max(z0, z1) + DEDUPE and abs(z1 - z0) > DEDUPE:
            best = max(best, abs(x0 + (x1 - x0) * (z - z0) / (z1 - z0)))
    return best


def _poly_z(inner, x):
    """The head polyline's height over x, off the outline actually built."""
    best = 0.0
    for k in range(len(inner) - 1):
        (x0, z0), (x1, z1) = inner[k], inner[k + 1]
        if min(x0, x1) - DEDUPE <= x <= max(x0, x1) + DEDUPE and abs(x1 - x0) > DEDUPE:
            best = max(best, z0 + (z1 - z0) * (x - x0) / (x1 - x0))
    return best


def clearances():
    """What the opening gives a runner, read off the two polylines that were
    built: the stone's (seg+1 rays, the tighter one) and the collider's."""
    vis = arch_chains(OPEN_HW, SPRING_Z, SEG, -PANEL_HW, PANEL_HW,
                      SPRING_Z, CORNICE_Z0)[1]
    col = coll_profile()[1]
    return {"width": 2.0 * _poly_half(vis, 1.80),          # at a standing runner's head
            "crown": _poly_z(vis, 0.0),
            "headroom": _poly_z(vis, 0.60),                # over a 1.2 m corridor
            "coll_width": 2.0 * _poly_half(col, 1.80),
            "coll_crown": _poly_z(col, 0.0)}


# =============================================================================
# RENDERS -- the prop beside a man, and the sight line down the passage
# =============================================================================

PROXY_H = 1.8                     # a standing prisoner
PROXY_W = 0.6                     # shoulders
PROXY_D = 0.3                     # chest
PROXY_X = 2.9                     # clear of the pier at x 2.0
PROXY_Y = 0.0                     # level with the passage's mouth
PROXY_COLOR = (0.13, 0.55, 0.20, 1.0)


SCALE_DIST = 11.0                 # metres out from the origin
SCALE_AZ = 25.0                   # degrees round from -Y towards the proxy
SCALE_LENS = 35.0
SCALE_RES = (1400, 900)
SCALE_TARGET = (0.4, 0.0, 2.2)    # between the archway's centre and the proxy

THROUGH_Y = -4.2                  # 3.5 m in front of the near face
THROUGH_LENS = 24.0
THROUGH_RES = (900, 1200)
THROUGH_TARGET = (0.0, 1.2, 2.0)  # through the opening, a shade above the eye

SUN_ENERGY = 2.2
SUN_PITCH = 52.0                  # degrees down from vertical
SUN_YAW = 35.0                    # degrees, so the +X pier casts into frame
FILL_ENERGY = 1400.0
FILL_AT = (5.0, -7.0, 4.0)        # off the camera's shoulder, shade detail
WORLD_GREY = (0.40, 0.42, 0.45, 1.0)
WORLD_STRENGTH = 0.7


def render(spec, objects):
    """marble_arch's own shots, called as ``mdl.main(post=render)``.

    Builds a render-only ground plane and prisoner proxy, takes 'scale' and
    'through', then deletes everything it made -- mdl.main renders the named
    views next and those frames must hold the archway and nothing else.
    """
    scene = bpy.context.scene

    bpy.ops.mesh.primitive_plane_add(size=60.0, location=(0.0, 0.0, -0.004))
    ground = bpy.context.active_object
    ground.name = "ShotGround"
    ground.data.materials.append(mdl.flat_material("ShotGround", (0.26, 0.26, 0.27, 1.0),
                                                   roughness=0.95))

    proxy = mdl.box("ScaleProxy",
                    (PROXY_X - PROXY_W * 0.5, PROXY_Y - PROXY_D * 0.5, 0.0),
                    (PROXY_X + PROXY_W * 0.5, PROXY_Y + PROXY_D * 0.5, PROXY_H))
    mdl.finish(proxy, mdl.flat_material("ScaleProxy", PROXY_COLOR, roughness=0.85))

    target = mdl._link(bpy.data.objects.new("ShotTarget", None))
    cam = mdl._link(bpy.data.objects.new("ShotCam", bpy.data.cameras.new("ShotCam")))
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE" if spec.get("engine", "eevee") != "cycles" else "CYCLES"
    mdl._try(scene.view_settings, "view_transform", "Standard")

    world = bpy.data.worlds.new("ArchGrey")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = WORLD_GREY
    bg.inputs[1].default_value = WORLD_STRENGTH

    sd = bpy.data.lights.new("Sun", type="SUN")
    sd.energy = SUN_ENERGY
    sun = mdl._link(bpy.data.objects.new("Sun", sd))
    sun.rotation_euler = (math.radians(SUN_PITCH), 0.0, math.radians(SUN_YAW))
    fd = bpy.data.lights.new("Fill", type="POINT")
    fd.energy = FILL_ENERGY
    fill = mdl._link(bpy.data.objects.new("Fill", fd))
    fill.location = FILL_AT

    out_dir = spec.get("out_dir", ".")
    os.makedirs(out_dir, exist_ok=True)

    def shot(name, loc, tgt, lens, res):
        cam.data.type = "PERSP"
        cam.data.lens = lens
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()          # the constraint has not solved yet
        path = os.path.join(out_dir, "%s_%s.png" % ("marble_arch", name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    az = math.radians(SCALE_AZ)
    shot("scale",
         (SCALE_DIST * math.sin(az), -SCALE_DIST * math.cos(az), EYE_H),
         SCALE_TARGET, SCALE_LENS, SCALE_RES)
    shot("through", (0.0, THROUGH_Y, EYE_H), THROUGH_TARGET, THROUGH_LENS, THROUGH_RES)

    for ob in (ground, proxy, target, cam, sun, fill):
        bpy.data.objects.remove(ob, do_unlink=True)
    scene.world = None
    bpy.data.worlds.remove(world, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    stone, info = _stone()
    coll = mb._Mesh()
    coll_quads = collider(coll)
    a = mb.audit(stone, "arch")
    albedo, emissive = mb._sheet("marble", mb.build_texture)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    ob = stone.object(OBJECT_NAME)
    mb.unwrap(ob, stone.zones, stone.groups, seed=5)
    mdl.finish(ob, mb.stone_material("Marble", albedo, emissive), strip_uvs=False)
    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    cl = clearances()
    print("MDL STATS visual_tris=%d collision_tris=%d grid_quads=%d arch_quads=%d coll_quads=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons),
             info["grid_quads"], info["arch_quads"], coll_quads))
    print("MDL STATS contiguity components=%d boundary=%d doubled=%d over=%d degenerate=%d dup_pos=%d"
          % (a["components"], a["boundary_edges"], a["doubled_edges"], a["over_edges"],
             a["degenerate"], a["duplicate_positions"]))
    print("MDL STATS width=%.2f height=%.2f depth=%.2f cornice_depth=%.2f opening=%.2fx%.2f "
          "headroom_1.2m=%.2f pier=%.2fx%.2f spring=%.2f cornice_z=%.4f rays=%d "
          "coll_opening=%.2fx%.2f"
          % (2.0 * HALF_W, TOP_Z, 2.0 * PIER_HD, 2.0 * CORNICE_HD, cl["width"], cl["crown"],
             cl["headroom"], HALF_W - PANEL_HW, 2.0 * PIER_HD, SPRING_Z, CORNICE_Z0,
             info["rays"], cl["coll_width"], cl["coll_crown"]))
    return [ob, coll_ob]


def _min_angle(m, tri):
    """The thinnest corner of one triangle, in degrees. The thin ones here are
    the mouldings themselves -- a 0.04 m fillet across a 1.1 m face is 2 deg and
    is meant to be -- so this is reported, and only a true sliver is gated."""
    P = [m.verts[i] for i in tri]
    out = 180.0
    for k in range(3):
        a, b, c = P[k], P[(k + 1) % 3], P[(k + 2) % 3]
        u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        lu = math.sqrt(sum(x * x for x in u))
        lv = math.sqrt(sum(x * x for x in v))
        if lu < 1e-12 or lv < 1e-12:
            return 0.0
        dot = sum(u[i] * v[i] for i in range(3)) / (lu * lv)
        out = min(out, math.degrees(math.acos(max(-1.0, min(1.0, dot)))))
    return out


def _slivers(m, label):
    angs = sorted(_min_angle(m, t) for t in m.faces)
    print("%s min triangle angle %.2f deg; under 3 deg: %d, under 5 deg: %d of %d"
          % (label, angs[0], sum(1 for a in angs if a < 3.0),
             sum(1 for a in angs if a < 5.0), len(angs)))
    return angs[0]


def _check():
    """--check: build without Blender and prove one closed contiguous mesh."""
    stone, info = _stone()
    coll = mb._Mesh()
    coll_quads = collider(coll)
    a = mb.audit(stone, "arch")
    c = mb.audit(coll, "coll")
    print("info: %s coll_quads=%d" % (" ".join("%s=%s" % kv for kv in sorted(info.items())),
                                      coll_quads))
    print("loops: stone=%s coll=%s" % (mb.boundary_loops(stone)[:3], mb.boundary_loops(coll)[:3]))
    cl = clearances()
    print("size %.2f x %.2f x %.2f m (cornice %.2f deep); opening %.2f wide to the springing "
          "%.2f, crown %.2f, headroom %.2f over the middle 1.2 m; pier %.2f wide x %.2f deep; "
          "collider opening %.2f x %.2f"
          % (2.0 * HALF_W, 2.0 * PIER_HD, TOP_Z, 2.0 * CORNICE_HD, cl["width"], SPRING_Z,
             cl["crown"], cl["headroom"], HALF_W - PANEL_HW, 2.0 * PIER_HD,
             cl["coll_width"], cl["coll_crown"]))
    zs = [v[2] for v in stone.verts]
    xs = [v[0] for v in stone.verts]
    ys = [v[1] for v in stone.verts]
    print("bbox x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f"
          % (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
    lo_stone = _slivers(stone, "arch")
    lo_coll = _slivers(coll, "coll")
    closed = (a["components"] == 1 and a["boundary_edges"] == 0 and a["doubled_edges"] == 0
              and a["over_edges"] == 0 and a["degenerate"] == 0 and a["duplicate_positions"] == 0)
    coll_ok = (c["components"] == 1 and c["boundary_edges"] == 0 and c["doubled_edges"] == 0
               and c["over_edges"] == 0 and c["degenerate"] == 0)
    ok = (closed and coll_ok and cl["crown"] > 2.95 and cl["width"] > 2.15
          and cl["coll_width"] >= cl["width"] - DEDUPE
          and cl["coll_crown"] >= cl["crown"] - DEDUPE
          and lo_stone > 0.5 and lo_coll > 0.5)
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, post=render)
