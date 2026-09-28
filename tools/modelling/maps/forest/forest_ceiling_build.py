"""
PANOPTICON -- forest roof: the leaf gallery over the lane, and the sun through it.

Ryan: "make the roof higher, so make it like a dome that collapses in the middle
where the tree is, and so theres still like a ring of cells above where the
player runs."

So this roof is only the LANE's lid, and it is no longer the level's last word
overhead. It runs from the leaf wall's head at forest_seam.CEIL_Z in to
forest_seam.DRUM_R, where forest_build's cell drum stands on its inner rim and
carries three more tiers of barred cells up to the seam; from the seam the
tree's own sheet sweeps back down to its crown. Nothing here touches the seam
any more: the ring this roof ends on is the drum's foot, not the mate.

Not a model of its own: forest_build.py calls in here with its _Ground (g) and
this module grows the roof into g.m, sharing vertices with the wall's top row
(g.wall[-1]) so the ground stays ONE contiguous mesh. Two calls:

    gallery_rows(g)  the leaf roof over the lane: seven rings r 60 -> 46.7 at
                     y ~38, g.gal[0] IS g.wall[-1] and g.gal[-1] IS the ring
                     forest_build.UPPER stands its drum on
    gallery_faces(g) that roof's faces, its five sun wells and g.rays

Heights (world y, the lane is 23.0):

    gallery roof ...  38.0 at the wall, 15 m up, sagging 0.5 m mid-span and
                      lumped +-0.55: dense leaf over the whole lane
    drum foot .....   g.gal[-1], r 46.7: forest_build's cell drum starts here
                      and climbs to forest_seam.seam_ring() at y 50

The roof follows the wood (Ryan: "the roof doesn't change based on where trees
are"): forest_trees.LAYOUT's trunks pull the underside DOWN over every crown
(TREE_DIP within TREE_REACH of a trunk, summed where trees crowd), the open lane
lifts it (GAP_RISE), and a coarser second lump field (LUMP2) breaks the sheet
into leaf masses the canopy's own lobes hang from (forest_canopy_build reads the
built triangles). Over a crown the quads are "shade", in the open they are
"leaf" with lit "sun" patches: dark undersides, light breaking through the gaps.

The leaves are unbroken: every quad carries a face, so nothing can read as a
hole or a bright polygon from below. The shafts come down THROUGH the closed
leaves from five anchors on the sun's side -- an organic blob of cells round
each (a wobbly radius round a centre, no two alike), lit as "sun" leaf;
forest_build._ray_mesh turns g.rays into one soft shaft per anchor. The wall's
row and the drum's row are never ragged: their vertices are shared with the
leaf wall and with the drum standing on them.

    python3 tools/modelling/maps/forest/forest_build.py --check     proves the whole ground
"""

import math

import forest_seam as fs
import forest_tree_build as ft
import forest_trees
from forest_tree_build import DOWN, pol, add

# =============================================================================
# TUNABLES
# =============================================================================

GALLERY_Z = fs.CEIL_Z       # the leaf roof over the lane: 15 m over the grass
# nine rings, the wall's head inward to the drum's foot: 1.66 m bands against a
# 1.2 m chord at 240 columns, fine enough for the underside to follow the trees
GALLERY_R = [60.0, 58.3, 56.7, 55.0, 53.4, 51.7, 50.0, 48.4, fs.DRUM_R]
GALLERY_SAG = 0.5           # the roof dips this much mid-span (zero at both edges)
GALLERY_LUMP = 0.55         # ... and its underside is lumped this much: leaf clumps, not a lid
LEAF_T = 0.12               # a gallery quad lit enough to be "leaf" rather than "shade"
TREE_DIP = 2.4              # the underside comes down this far over a trunk ...
TREE_REACH = 3.6            # ... fading to nothing this far (x the tree's scale) from it
HEAD_LEAN = {"tree_c": 2.4}  # the leaner's head stands this far (local m) along its +X from its foot
DIP_R = (fs.DRUM_R, 57.3)   # the deck (forest_build.INNER_R..OUTER_R): a tree dip lives over the
DIP_EDGE = 1.2              # walkable annulus only, fading out over this much at either edge
GAP_RISE = 1.3              # and lifts this far over open lane, nothing under it
LUMP2 = 0.9                 # the coarse leaf masses of the sheet itself
LUMP2_WL = (4.5, 11.0)      # their wavelengths, m
SHADE_T = 0.45              # tree weight over which a quad is the crown's dark underside
SUN_GAP = (0.12, 0.25)      # (tree weight under, lump over) which an open quad is lit leaf

# (bearing, anchor radius, radius in metres, wobble seed): where a sun well comes down
# through the leaves. All on the sun's side (SUN bears 120) so they read as one
# light, and all in bands 1..4 -- never band 0 (the wall's own row) nor band 5
# (the drum's foot), whose vertices are shared and must not be ragged.
# A shaft falls toward bearing 300 at 52 deg, so from 15 m up it travels 11 m of
# plan before it reaches the grass: an anchor over the middle of the lane sails
# past the lip into the ravine. Three of the five are therefore anchored wide of
# the sun's own line (bearings 60, 71 and 168) and high in band 1, where that 11 m
# still lands on the lane; the other two keep the sun's line and fall into the pit.
SHAFTS = [(60.0, 56.7, 2.4, 11), (71.0, 56.7, 2.8, 23), (104.0, 54.45, 2.0, 37),
          (140.0, 54.45, 2.6, 53), (168.0, 56.7, 1.8, 71)]
SHAFT_BANDS = (1, len(GALLERY_R) - 2)   # the wells live in the inner bands, never the wall's row nor the drum's
SHAFT_RAG = (0.45, 0.35)    # every vertex round a well's mouth is pulled this far in y and in
                            # plan: torn leaf, not a staircase of quads
SHAFT_LIT = 1               # a well's own cells and the cells this far round them are the lit
                            # "sun" leaf: the light falls ON the leaves, never past a cut edge.
                            # One ring here: this grid is fine, a well is only a few cells
SHAFT_WOB = (0.30, 0.22, 0.14)   # the blob's radius wobbles at 2, 3 and 5 per turn
SHAFT_HALF = (0.42, 0.5, 2.2)    # the shaft's half width at the top: this x the blob's radius, clamped

SEED = 9110271 + 77         # the roof's own seed: editing it diffs only the roof

TWO_PI = 2.0 * math.pi


# =============================================================================
# THE GALLERY ROOF -- the lane's lid, the wall's head in to the drum's foot
# =============================================================================

def _nc(g):
    return len(g.wall[-1])


def _col_of(nc, b):
    return int(round(b / (360.0 / nc))) % nc


_TREES = []
_LUMP2 = ft._field(ft._Rng(SEED + 313), n=6, wl=LUMP2_WL)


def _trees():
    """(x, y, reach) per tree, centred on its HEAD: a leaner's crown is not over its foot."""
    if not _TREES:
        for (sec, kind, b, rad, aim, spin, sc) in forest_trees.LAYOUT:
            if kind in forest_trees.TREES:
                p = pol(b, rad, 0.0)
                phi = math.radians(-b + spin)                 # the tree's local +X, in Blender's xy
                lean = HEAD_LEAN.get(kind, 0.0) * sc[0]
                _TREES.append((p[0] + lean * math.cos(phi), p[1] + lean * math.sin(phi), TREE_REACH * sc[0]))
    return _TREES


def tree_weight(x, y):
    """0..1: how much wood stands under (x, y): 1 over a trunk, 0 in open lane."""
    t = 0.0
    for (tx, ty, reach) in _trees():
        d2 = (x - tx) ** 2 + (y - ty) ** 2
        if d2 < reach * reach:
            q = 1.0 - d2 / (reach * reach)
            t += q * q
    return min(1.0, t)


def _window(x, y):
    """0 at the wall's row and the drum's foot (both shared, never moved), 1 mid-span."""
    rad = math.hypot(x, y)
    u = (GALLERY_R[0] - rad) / (GALLERY_R[0] - GALLERY_R[-1])
    return math.sin(math.pi * max(0.0, min(1.0, u)))


def deck_window(x, y):
    """1 over the walkable deck, 0 past the pit lip and the wall foot: no dip
    (and no crown, forest_canopy_build) hangs over the drop or into the wall."""
    rad = math.hypot(x, y)
    u = min(rad - DIP_R[0], DIP_R[1] - rad) / DIP_EDGE
    u = max(0.0, min(1.0, u))
    return u * u * (3.0 - 2.0 * u)


def gallery_z(g, x, y):
    """The gallery roof's underside at (x, y): down over the trees, up over the
    open lane, lumped like leaf masses; flat at both shared edges."""
    w = _window(x, y)
    t = tree_weight(x, y) * deck_window(x, y)
    z = GALLERY_Z - GALLERY_SAG * w + GALLERY_LUMP * g.ceil_f(x * 0.9, y * 0.9)
    return z + w * (GAP_RISE * (1.0 - t) - TREE_DIP * t + LUMP2 * _LUMP2(x, y))


def gallery_rows(g):
    """Ring 0 IS the leaf wall's top row; rings 1..6 are the roof's own, the last
    of them at forest_seam.DRUM_R -- an ordinary lumped roof ring, which the
    cell drum then stands on (forest_build.UPPER[0] IS this row)."""
    m = g.m
    nc = _nc(g)
    g.gal.append(g.wall[-1])
    for rad in GALLERY_R[1:]:
        row = []
        for i in range(nc):
            p = pol(i * 360.0 / nc, rad, 0.0)
            row.append(m.v((p[0], p[1], gallery_z(g, p[0], p[1]))))
        g.gal.append(row)


def gal_quad_ids(g, k, i):
    """The four ids of gallery quad (column i, band k)."""
    n = len(g.gal[k])
    q = (i + 1) % n
    return (g.gal[k][i], g.gal[k][q], g.gal[k + 1][q], g.gal[k + 1][i])


def _leafy(g, ids, thr=LEAF_T, k=0.9, off=0.0):
    """Shade under a crown; in the open, lit leaf on the lumps, leaf where the
    underside bulges down into the light, shade in the hollows."""
    c = g.m.centroid(ids)
    t = tree_weight(c[0], c[1])
    if t > SHADE_T:
        return "shade"
    if t < SUN_GAP[0] and _LUMP2(c[0], c[1]) > SUN_GAP[1]:
        return "sun"
    return "leaf" if g.ceil_f(c[0] * k + off, c[1] * k) > thr else "shade"


def _blob_r(rng_ph, ang, radius):
    """The well's wobbly radius at angle ``ang``: never a circle, never a box."""
    f = 1.0
    for (k, amp) in zip((2.0, 3.0, 5.0), SHAFT_WOB):
        f += amp * math.sin(k * ang + rng_ph[int(k) % 3])
    return radius * max(0.35, f)


def _shaft_cells(g):
    """Per shaft: the gallery quads its light comes through (an organic blob, no
    two alike) and their centres. The quads keep their faces: the light falls
    on them."""
    out = []
    lo, hi = SHAFT_BANDS
    nc = len(g.gal[lo])
    for (b, anchor_r, radius, seed) in SHAFTS:
        r = ft._Rng(SEED + seed)
        ph = (r.f() * TWO_PI, r.f() * TWO_PI, r.f() * TWO_PI)
        c = pol(b, anchor_r, 0.0)
        band = max(lo, min(hi - 1, next(k for k in range(len(GALLERY_R) - 1) if GALLERY_R[k + 1] <= anchor_r)))
        cells, pts = [], []
        for k in range(lo, hi):
            for i in range(nc):
                p = g.m.centroid(gal_quad_ids(g, k, i))
                d = (p[0] - c[0], p[1] - c[1])
                dist = math.hypot(d[0], d[1])
                if dist > radius * 1.7:
                    continue
                if dist <= _blob_r(ph, math.atan2(d[1], d[0]), radius):
                    cells.append((i, k))
                    pts.append(p)
        if not pts:                                   # a blob too small for one quad
            k, i = band, _col_of(nc, b)
            cells = [(i, k)]
            pts = [g.m.centroid(gal_quad_ids(g, k, i))]
        cells, pts = _one_blob(cells, pts, nc)        # no stray speck off to the side
        out.append({"b": b, "radius": radius, "cells": cells, "pts": pts,
                    "centre": tuple(sum(p[j] for p in pts) / float(len(pts)) for j in range(3))})
    return out


def _one_blob(cells, pts, nc):
    """The blob's biggest 4-connected island: a lone lit cell off to the side reads
    as a stray bright patch, not as one shaft coming through."""
    want = set(cells)
    seen = set()
    best = None
    for start in cells:
        if start in seen:
            continue
        stack, island = [start], []
        seen.add(start)
        while stack:
            (i, k) = stack.pop()
            island.append((i, k))
            for (di, dk) in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                n = ((i + di) % nc, k + dk)
                if n in want and n not in seen:
                    seen.add(n)
                    stack.append(n)
        if best is None or len(island) > len(best):
            best = island
    keep = set(best)
    out = [(c, p) for (c, p) in zip(cells, pts) if c in keep]
    return [c for (c, _p) in out], [p for (_c, p) in out]


def _rag_rims(g, cells):
    """Pull every vertex round a well's mouth about: the leaf there hangs torn and
    uneven, not as a staircase of quads. The vertices are shared, so the leaves
    round it move too -- which is why the wall's row (0) and the DRUM's row
    (the last) are never in a well's band and are never touched here."""
    r = ft._Rng(SEED + 911)
    fixed = set(g.gal[0]) | set(g.gal[-1])
    ids = set()
    for (i, k) in cells:
        ids.update(gal_quad_ids(g, k, i))
    for vid in sorted(ids):
        if vid in fixed:                    # shared with the wall or with the tower: contractual
            continue
        (x, y, z) = g.m.verts[vid]
        rad = math.hypot(x, y)
        t = (-y / rad, x / rad, 0.0) if rad > 1e-6 else (1.0, 0.0, 0.0)
        p = add((x, y, z), t, SHAFT_RAG[1] * r.sf())
        rr = 1.0 + SHAFT_RAG[1] * r.sf() / max(1.0, rad)
        g.m.verts[vid] = (p[0] * rr, p[1] * rr, z + SHAFT_RAG[0] * r.sf())


def gallery_faces(g):
    """The roof's faces, facing DOWN, and its five sun wells."""
    m = g.m
    nc = _nc(g)
    g.shafts = _shaft_cells(g)
    mouths = set()
    for sh in g.shafts:
        mouths.update(sh["cells"])
    lit = set()                                   # the wells' own cells and the leaf round them
    for (i, k) in mouths:
        for di in range(-SHAFT_LIT, SHAFT_LIT + 1):
            for dk in range(-SHAFT_LIT, SHAFT_LIT + 1):
                lit.add(((i + di) % nc, k + dk))
    _rag_rims(g, mouths)
    for k in range(len(g.gal) - 1):
        for i in range(nc):                   # every quad carries a face: the leaf is unbroken
            ids = gal_quad_ids(g, k, i)
            zone = "sun" if (i, k) in lit else _leafy(g, ids)
            m.quad(ids[0], ids[1], ids[2], ids[3], DOWN, zone)
    for sh in g.shafts:
        half = min(SHAFT_HALF[2], max(SHAFT_HALF[1], SHAFT_HALF[0] * sh["radius"]))
        g.rays.append((sh["pts"], half))
    print("MDL STATS roof gallery_y=%.1f r=%.1f..%.1f rings=%d shafts=%d well_cells=%d"
          % (GALLERY_Z, GALLERY_R[-1], GALLERY_R[0], len(g.gal), len(SHAFTS), len(mouths)))

