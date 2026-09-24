#!/usr/bin/env python3
"""
rock_bars_check -- measure the two claims rock_bars.glb makes, instead of
asserting them.

The bars across the lane are one object doing two contradictory jobs. They
must be open enough that a prisoner can shoot through them and that the guard
in the tower can see a body behind them -- a screen you cannot shoot or see
through is not bars, it is a wall. They must also be closed enough that a body
cannot walk through, because the point of the barrier is that the finish is
visible from the start and not walkable back to.

"You can shoot through it but you cannot fit through it" is a geometric claim
about a specific mesh, and a mesh gets rebuilt. A sculpt that widens one slot
by four centimetres breaks the barrier silently: the collider still stops the
player in the editor's own test, the renders look the same from the three
angles the build script shoots, and the defect surfaces as "you can walk
through the bars on Map 1" long after the change that caused it. So both
halves are measured here, on the shipped .glb, with no Blender and no Godot.

    python3 tools/modelling/maps/bentham_ring/rock_bars_check.py [--glb PATH]

The widest slot comes from rays cast along the thin axis on a fine grid over
the wall's face: the longest run of samples with no triangle in front of them
is the gap at that height, given in the model's own metres and again times the
scene's X scale, because that is the gap a body actually meets. The sight
lines are segment-versus-mesh tests for the two shots that must work. Only the
visual mesh is measured; the collider answers a different question.

Exits 0 always; the caller reads the numbers.
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

from glb_audit import parse_glb, node_world_matrices, read_accessor  # noqa: E402
from glb_audit import transform_point, IDENTITY4, MODE_TRIANGLES  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

DEFAULT_GLB = os.path.join(REPO, "maps", "bentham_ring", "models", "rock_bars.glb")

# Which geometry is the art. Substring match on node and mesh name, the way
# Godot's own importer decides: the collider carries SKIP_NAME on top.
VISUAL_NAME = "RockBars"
SKIP_NAME = "Collision"

# Slot grid, in the model's own metres. 1 cm across is a tenth of the gap
# being measured; 4 cm up is enough rows to catch a slot that only opens over
# part of its height.
W_STEP = 0.01
H_STEP = 0.04

# Side of one square bucket in the triangle index. Bigger buckets mean fewer
# of them and more triangles tested per sample.
BUCKET_SIZE = 0.50

# The scene's X scale on the RockBars node in maps/bentham_ring/bentham_ring.tscn:
# unscaled since the gate was fitted to the lane at world size.
WORLD_X_SCALE = 1.0

# A player capsule is this wide. A gap at or under it does not pass a body.
BODY_DIAMETER = 0.80

# a. through_slots: prisoner eyes in front, body-height targets behind.
SLOT_EYE_XS = (-4.0, -2.0, 0.0, 2.0, 4.0)
SLOT_EYE_YS = (1.45, 1.65, 1.85)
SLOT_EYE_Z = 6.0
SLOT_TARGET_XS = (-4.0, -2.0, 0.0, 2.0, 4.0)
SLOT_TARGET_YS = (0.3, 0.9, 1.5)
SLOT_TARGET_Z = -4.0

# b. guard_to_body: the guard's tower eye, already converted into this node's
# local frame, against a body standing on either side of the bars.
GUARD_EYE = (-52.540, 4.000, 0.000)
BODY_XS = (-3.0, -1.0, 1.0, 3.0)
BODY_YS = (0.2, 0.9, 1.6)
BODY_ZS = (-3.0, 3.0)

# A ray within PARALLEL_EPS of a triangle's plane has no defined crossing and
# is not a hit; otherwise EDGE_EPS is generous in the triangle's favour, so a
# grazing edge-on hit counts as blocked. Bars you can shoot between only by
# threading the exact seam are not bars you can shoot between.
PARALLEL_EPS = 1e-12
EDGE_EPS = 1e-9


# --- GEOMETRY LOAD


def load_visual_triangles(path):
    """Every triangle of the visual mesh, as (p0, p1, p2) in node-world space."""
    gltf, blob = parse_glb(path)
    meshes = gltf.get("meshes", [])
    worlds = node_world_matrices(gltf)
    tris = []
    for node_index, node in enumerate(gltf.get("nodes", [])):
        mesh_index = node.get("mesh")
        if mesh_index is None:
            continue
        mesh = meshes[mesh_index]
        names = (node.get("name") or "") + " " + (mesh.get("name") or "")
        if VISUAL_NAME not in names or SKIP_NAME in names:
            continue
        matrix = worlds.get(node_index, IDENTITY4)
        moved = matrix != IDENTITY4
        for prim in mesh.get("primitives", []):
            if prim.get("mode", MODE_TRIANGLES) != MODE_TRIANGLES:
                continue
            attributes = prim.get("attributes", {})
            if "POSITION" not in attributes:
                continue
            pts = read_accessor(gltf, blob, attributes["POSITION"])
            if moved:
                pts = [transform_point(matrix, p) for p in pts]
            if "indices" in prim:
                idx = read_accessor(gltf, blob, prim["indices"])
            else:
                idx = list(range(len(pts)))
            for k in range(0, len(idx) - 2, 3):
                tris.append((pts[idx[k]], pts[idx[k + 1]], pts[idx[k + 2]]))
    return tris


def to_local_frame(tris):
    """Re-express triangles as (x = W centred, y = H from the base, z = T centred).

    Which source axis is which is read off the bounding box -- longest is W,
    taller of the remaining two is H, thinnest is T -- never hardcoded, so a
    rebuild that lands the wall on different axes still measures the wall.
    """
    lo = [min(p[a] for t in tris for p in t) for a in range(3)]
    hi = [max(p[a] for t in tris for p in t) for a in range(3)]
    order = sorted(range(3), key=lambda a: hi[a] - lo[a], reverse=True)
    w_axis, h_axis, t_axis = order[0], order[1], order[2]
    w_mid = 0.5 * (lo[w_axis] + hi[w_axis])
    t_mid = 0.5 * (lo[t_axis] + hi[t_axis])

    def place(p):
        return (p[w_axis] - w_mid, p[h_axis] - lo[h_axis], p[t_axis] - t_mid)

    out = [(place(t[0]), place(t[1]), place(t[2])) for t in tris]
    span = (hi[w_axis] - lo[w_axis], hi[h_axis] - lo[h_axis], hi[t_axis] - lo[t_axis])
    return out, span


# --- 1. SLOT WIDTH -- rays along T, so the test is containment in the (W, H) face


def _clamp(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)


def build_face_index(tris, half_w, height):
    """Bucket every triangle by its (x, y) bounding box. Returns (grid, nx, ny)."""
    nx = max(1, int(math.ceil(2.0 * half_w / BUCKET_SIZE)))
    ny = max(1, int(math.ceil(height / BUCKET_SIZE)))
    grid = [[] for _ in range(nx * ny)]
    for tri in tris:
        xs = (tri[0][0], tri[1][0], tri[2][0])
        ys = (tri[0][1], tri[1][1], tri[2][1])
        ix0 = _clamp(int((min(xs) + half_w) / BUCKET_SIZE), 0, nx - 1)
        ix1 = _clamp(int((max(xs) + half_w) / BUCKET_SIZE), 0, nx - 1)
        iy0 = _clamp(int(min(ys) / BUCKET_SIZE), 0, ny - 1)
        iy1 = _clamp(int(max(ys) / BUCKET_SIZE), 0, ny - 1)
        for iy in range(iy0, iy1 + 1):
            for ix in range(ix0, ix1 + 1):
                grid[iy * nx + ix].append(tri)
    return grid, nx, ny


def _covered(tri, x, y):
    """True if (x, y) lies in the triangle's (W, H) projection, boundary included."""
    (ax, ay, _), (bx, by, _), (cx, cy, _) = tri
    d1 = (x - bx) * (ay - by) - (ax - bx) * (y - by)
    d2 = (x - cx) * (by - cy) - (bx - cx) * (y - cy)
    d3 = (x - ax) * (cy - ay) - (cx - ax) * (y - ay)
    neg = d1 < -EDGE_EPS or d2 < -EDGE_EPS or d3 < -EDGE_EPS
    pos = d1 > EDGE_EPS or d2 > EDGE_EPS or d3 > EDGE_EPS
    return not (neg and pos)


def widest_gap(tris, half_w, height):
    """Return (widest run of open samples in metres, the height it is at)."""
    grid, nx, ny = build_face_index(tris, half_w, height)
    samples = int(math.floor(2.0 * half_w / W_STEP)) + 1
    rows = int(math.floor(height / H_STEP)) + 1
    best_gap = 0.0
    best_y = 0.0
    for r in range(rows):
        y = r * H_STEP
        base = _clamp(int(y / BUCKET_SIZE), 0, ny - 1) * nx
        run = 0
        row_best = 0
        bucket = ()
        last_ix = -1
        for s in range(samples):
            x = -half_w + s * W_STEP
            ix = _clamp(int((x + half_w) / BUCKET_SIZE), 0, nx - 1)
            if ix != last_ix:
                bucket = grid[base + ix]
                last_ix = ix
            hit = False
            for tri in bucket:
                if _covered(tri, x, y):
                    hit = True
                    break
            if hit:
                run = 0
            else:
                run += 1
                if run > row_best:
                    row_best = run
        if row_best * W_STEP > best_gap:
            best_gap = row_best * W_STEP
            best_y = y
    return best_gap, best_y


# --- 2. SIGHT LINES -- segment versus mesh, Moller-Trumbore


def segment_clear(tris, origin, target):
    """True if the segment origin->target intersects no triangle."""
    dx = target[0] - origin[0]
    dy = target[1] - origin[1]
    dz = target[2] - origin[2]
    for (a, b, c) in tris:
        e1x, e1y, e1z = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        e2x, e2y, e2z = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        px = dy * e2z - dz * e2y
        py = dz * e2x - dx * e2z
        pz = dx * e2y - dy * e2x
        det = e1x * px + e1y * py + e1z * pz
        if -PARALLEL_EPS < det < PARALLEL_EPS:
            continue
        inv = 1.0 / det
        tx, ty, tz = origin[0] - a[0], origin[1] - a[1], origin[2] - a[2]
        u = (tx * px + ty * py + tz * pz) * inv
        if u < -EDGE_EPS or u > 1.0 + EDGE_EPS:
            continue
        qx = ty * e1z - tz * e1y
        qy = tz * e1x - tx * e1z
        qz = tx * e1y - ty * e1x
        v = (dx * qx + dy * qy + dz * qz) * inv
        if v < -EDGE_EPS or u + v > 1.0 + EDGE_EPS:
            continue
        t = (e2x * qx + e2y * qy + e2z * qz) * inv
        if -EDGE_EPS <= t <= 1.0 + EDGE_EPS:
            return False
    return True


def count_clear(tris, pairs):
    passed = 0
    for origin, target in pairs:
        if segment_clear(tris, origin, target):
            passed += 1
    return len(pairs), passed


def through_slot_pairs():
    eyes = [(x, y, SLOT_EYE_Z) for x in SLOT_EYE_XS for y in SLOT_EYE_YS]
    targets = [(x, y, SLOT_TARGET_Z) for x in SLOT_TARGET_XS for y in SLOT_TARGET_YS]
    return [(e, t) for e in eyes for t in targets]


def guard_to_body_pairs():
    body = [(x, y, z) for x in BODY_XS for y in BODY_YS for z in BODY_ZS]
    return [(GUARD_EYE, p) for p in body]


# --- REPORT


def main(argv):
    parser = argparse.ArgumentParser(
        description="Measure rock_bars.glb slot width and sight lines.")
    parser.add_argument("--glb", default=DEFAULT_GLB,
                        help="path to the .glb (default: the shipped one)")
    args = parser.parse_args(argv)

    raw = load_visual_triangles(args.glb)
    if raw:
        tris, span = to_local_frame(raw)
        gap, at_y = widest_gap(tris, 0.5 * span[0], span[1])
        slots = count_clear(tris, through_slot_pairs())
        guard = count_clear(tris, guard_to_body_pairs())
    else:
        # No visual mesh is a real answer, not a crash: nothing blocks anything.
        gap, at_y, slots, guard = 0.0, 0.0, (0, 0), (0, 0)
    world_gap = gap * WORLD_X_SCALE

    print("SLOT widest_gap_local=%.3f at_height=%.2f" % (gap, at_y))
    print("SLOT widest_gap_world=%.3f (local x %.2f, the scene's X scale on RockBars)"
          % (world_gap, WORLD_X_SCALE))
    print("SLOT body_blocked=%s body_diameter=%.2f"
          % (bool(raw) and world_gap <= BODY_DIAMETER, BODY_DIAMETER))
    print("SIGHT through_slots_rays=%d passed=%d" % slots)
    print("SIGHT guard_to_body_rays=%d passed=%d" % guard)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
