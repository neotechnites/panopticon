#!/usr/bin/env python3
"""
s1_lane_gap -- measure, in metres, the narrowest place a BODY has to squeeze
through to cross one angular section of the PANOPTICON ring.

A section of the map is sculpted as shapes: stalagmites, prisms, spikes, a lip,
a wall. What the match actually cares about is the negative space between them
-- whether a runner crossing S1 has a lane, and how wide the tightest point of
the best lane is. That number is invisible in a render. Three views of a cave
look passable from every angle a build script happens to shoot, and the
bottleneck is a 0.4 m slot two metres off the path the eye follows.

So it is measured, from the built .glb, on the Mac, with no Blender and no
Godot:

    python3 tools/modelling/lib/s1_lane_gap.py <map.glb>
            [--section 15,60] [--band 49.8,54.2] [--json out.json]

WHAT IT MEASURES

An obstacle is a triangle of the deck shell -- radius SHELL_R_IN..SHELL_R_OUT
-- with any vertex standing BODY_LO..BODY_HI metres over the deck. That height
window is the body band: below it is floor relief a body walks over, above it
is ceiling a body walks under, and only what stands inside it can stop one.
"Any vertex" is deliberate: a triangle with one corner in the band is part of
a thing that is in the band.

The plan footprints of those triangles are rasterised onto a CELL-metre grid,
an exact Euclidean distance transform gives every free cell its clearance --
the distance to the nearest obstacle -- and the route across the section is the
one whose WORST clearance is as good as possible (a maximin, or widest-
bottleneck, path). The reported gap is twice that clearance: a corridor whose
centre line is c metres from the nearest obstacle on both sides is 2c wide,
and it is the width a body is compared against, not the half-width.

This is done TWICE and reported twice: once over the collision primitives and
once over the art primitives. They are different meshes with different jobs and
they disagree in exactly the way that hurts -- art that reads as a wide lane
over collision that is not, or a collider that pinches where nothing is drawn.
One number for each, on its own line, is what makes the disagreement visible.

FRAME

glTF is Y-UP, as glb_region_diff explains at length: axis 1 is height, the
ground plane is axes 0 and 2, and the game bearing of a point is
degrees(atan2(z, x)) mod 360 with no sign flip. That is glb_region_diff's
game_bearing_degrees, used here for every bearing this file prints and
reproduced inline (arctan2(z, x)) where a whole vertex array is converted at
once. The deck surface is DECK_Y in that same frame.

Geometry arrives through glb_audit.collect_primitives, which is already the
composition of parse_glb, node_world_matrices and is_collision_name: it pushes
every primitive through its node's world matrix so one space is compared, and
splits art from collision by Godot's own substring rule. Nothing here re-does
any of that.

THE GRID

Cells are CELL metres square in ARC-LENGTH x RADIUS space: the radial axis is
radius in metres, and the angular axis is arc length at the band's mid radius,
R_ref = (band_lo + band_hi) / 2. Working in arc length rather than in degrees
is what makes a distance transform mean metres in both axes at once. The cost
is that an obstacle at radius r has its angular extent scaled by R_ref / r, so
a cell at the inner edge of the shell is about 10% wide in the angular axis
relative to truth. The route is restricted to the band, where the error is
under 5%, and the alternative -- a Cartesian grid -- cannot be walked column by
column from one bearing to the next, which is the question being asked.

The grid spans the section plus MARGIN_DEG either side, because an obstacle
just outside the section still narrows a lane just inside it, and it spans the
whole shell in radius, because an obstacle outside the band still narrows a
lane inside it. The ROUTE is restricted to the section's own bearings and to
the band's own radii. Those two rectangles are deliberately different sizes.

EXACTNESS AND ITS LIMITS

The distance transform is exact -- Felzenszwalb and Huttenlocher's separable
parabola-envelope algorithm, not a chamfer approximation -- but it is exact
about a rasterised world. Two things are quantised: an obstacle triangle marks
every cell its footprint touches (its three edges are supercovered, so a
sliver thinner than a cell still registers as solid rather than vanishing),
and clearance is measured centre to centre. Both round in the safe direction:
the reported gap is never wider than the truth. Measured against slots of a
known width, the understatement is at most two cells -- 0.10 m at CELL 0.05 --
and is usually nothing.

A gap of 0.00 means the band is blocked: no route across the section clears a
single cell of the obstacles.

Prints one line per primitive set and exits 0. Exits 1 only when the file
cannot be read or an argument is wrong -- this measures, it does not judge,
and there is no threshold here for a lane to fail.
"""

import heapq
import json
import math
import os
import sys
import time

import numpy as np

# glb_audit and glb_region_diff live beside this file. Importing them by name
# has to work when this script is run by path from anywhere, the normal case.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from glb_audit import collect_primitives, parse_glb  # noqa: E402
from glb_region_diff import game_bearing_degrees, normalise_degrees  # noqa: E402


# =============================================================================
# TUNABLES
# =============================================================================

# World height of the deck surface, in the .glb's Y-up frame. The build script
# calls it DECK_Z in its own Z-up space; the exporter makes it axis 1 here.
DECK_Y = 23.0

# The deck shell in radius. Wide enough to take in the lip at the inner edge
# and the wall at the outer, because both of them narrow lanes in the band.
SHELL_R_IN = 47.0
SHELL_R_OUT = 57.0

# The body band: height over the deck that a standing body occupies. Below
# BODY_LO is relief a body clears; above BODY_HI is headroom.
BODY_LO = 0.35
BODY_HI = 1.90

# Grid cell, metres. Small enough that a 0.05 m error on a metre-wide lane is
# noise, large enough that the whole shell is a few hundred thousand cells.
CELL = 0.05

# How far outside the section the grid reaches, in degrees. Obstacles this far
# round the ring still narrow lanes inside the section.
MARGIN_DEG = 3.0

# Spacing of the route samples written to --json.
ROUTE_SAMPLE_DEG = 0.5

# Defaults: S1 is the stalactite cave at game bearings 15..60, and the band is
# the lane the route is asked about.
DEFAULT_SECTION = (15.0, 60.0)
DEFAULT_BAND = (49.8, 54.2)

# A triangle whose three corners span more than this in bearing is not a deck
# triangle; it is geometry the angular unwrap cannot place (something crossing
# the whole ring), and it is dropped rather than smeared across the grid.
MAX_TRIANGLE_SPAN_DEG = 30.0

# Stand-in for "no seed in this line" inside the distance transform. Finite,
# not inf: the parabola intersections are a difference over a difference, and
# inf - inf is a nan that poisons a whole row.
EDT_FAR = 1.0e12

FULL_TURN_DEGREES = 360.0


# =============================================================================
# THE GRID
# =============================================================================


class Grid(object):
    """Arc-length x radius raster over one section of the shell.

    Rows are radius (index 0 at SHELL_R_IN), columns are arc length at the
    band's mid radius (index 0 at MARGIN_DEG before the section's start).
    Every index-to-metres conversion in this file goes through here, so the
    rasteriser, the distance transform and the route all agree on where a cell
    is by construction.
    """

    def __init__(self, section_start, span_degrees, reference_radius):
        self.section_start = section_start
        self.span_degrees = span_degrees
        self.reference_radius = reference_radius

        self.arc_min = reference_radius * math.radians(-MARGIN_DEG)
        arc_max = reference_radius * math.radians(span_degrees + MARGIN_DEG)
        self.columns = int(math.ceil((arc_max - self.arc_min) / CELL))

        self.radius_min = SHELL_R_IN
        self.rows = int(math.ceil((SHELL_R_OUT - SHELL_R_IN) / CELL))

    def column_offset_degrees(self, column):
        """Degrees past the section's start at the centre of this column."""
        arc = self.arc_min + (column + 0.5) * CELL
        return math.degrees(arc / self.reference_radius)

    def column_bearing(self, column):
        """Game bearing at the centre of this column, in [0, 360)."""
        return normalise_degrees(self.section_start + self.column_offset_degrees(column))

    def row_radius(self, row):
        """Radius at the centre of this row, in metres."""
        return self.radius_min + (row + 0.5) * CELL

    def column_of_offset(self, offset_degrees):
        """Column holding this many degrees past the section's start."""
        arc = self.reference_radius * math.radians(offset_degrees)
        column = int(math.floor((arc - self.arc_min) / CELL))
        return max(0, min(self.columns - 1, column))

    def row_of_radius(self, radius):
        """Row holding this radius, clamped into the shell."""
        row = int(math.floor((radius - self.radius_min) / CELL))
        return max(0, min(self.rows - 1, row))


def check_bearing_convention():
    """Fail loudly if the vectorised bearing here stops matching its source.

    Every bearing this file prints comes from glb_region_diff's
    game_bearing_degrees, but whole vertex arrays are converted inline with
    arctan2(z, x) because calling a scalar function per vertex costs seconds
    on a map-sized mesh. Two spellings of one convention is exactly how a
    sign flip gets in, so the two are compared on known points once per run.
    A ring binned by the wrong axis produces a plausible report and a
    meaningless answer, which is the failure worth a microsecond.
    """
    probes = ((1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0), (3.0, -4.0))
    ground_x = np.array([p[0] for p in probes])
    ground_z = np.array([p[1] for p in probes])
    inline = np.degrees(np.arctan2(ground_z, ground_x)) % FULL_TURN_DEGREES
    source = np.array([game_bearing_degrees(x, z) for x, z in probes])
    if not np.allclose(inline, source, atol=1e-9):
        raise ValueError("bearing convention drifted from glb_region_diff")


def section_span(section_start, section_end):
    """Width of the half-open section in degrees, going the short way round.

    A section that wraps past 360 (--section 350,10) is twenty degrees, not
    three hundred and forty, exactly as glb_region_diff reads one. A section
    whose two ends are equal is the whole ring.
    """
    span = math.fmod(section_end - section_start, FULL_TURN_DEGREES)
    if span <= 0.0:
        span += FULL_TURN_DEGREES
    return span


# =============================================================================
# OBSTACLES
# =============================================================================


def _supercover_edge(mask, x0, y0, x1, y1, grid):
    """Mark every cell an edge passes through, in cell-centre index space.

    Sampled at half a cell, which is dense enough that no cell on the line is
    stepped over. This is what stops a near-vertical wall triangle -- whose
    plan footprint is thinner than a cell -- from rasterising to nothing and
    reading as open air.
    """
    steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2.0) + 1
    t = np.linspace(0.0, 1.0, steps + 1)
    xs = np.rint(x0 + (x1 - x0) * t).astype(np.int64)
    ys = np.rint(y0 + (y1 - y0) * t).astype(np.int64)
    inside = (xs >= 0) & (xs < grid.columns) & (ys >= 0) & (ys < grid.rows)
    mask[ys[inside], xs[inside]] = True


def _fill_triangle(mask, xs, ys, grid):
    """Mark the cells covered by one triangle's plan footprint.

    xs, ys are the three corners in cell-centre index space. Edges first (see
    _supercover_edge), then the interior by the barycentric sign test on cell
    centres. A degenerate triangle has no interior and is already covered by
    its edges.
    """
    for a, b in ((0, 1), (1, 2), (2, 0)):
        _supercover_edge(mask, xs[a], ys[a], xs[b], ys[b], grid)

    x_lo = max(int(math.floor(min(xs))), 0)
    x_hi = min(int(math.ceil(max(xs))), grid.columns - 1)
    y_lo = max(int(math.floor(min(ys))), 0)
    y_hi = min(int(math.ceil(max(ys))), grid.rows - 1)
    if x_hi < x_lo or y_hi < y_lo:
        return

    ax, bx, cx = xs
    ay, by, cy = ys
    denominator = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(denominator) < 1e-12:
        return

    columns = np.arange(x_lo, x_hi + 1, dtype=np.float64)
    rows = np.arange(y_lo, y_hi + 1, dtype=np.float64)
    px = columns[None, :]
    py = rows[:, None]

    lambda_a = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / denominator
    lambda_b = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / denominator
    inside = (lambda_a >= 0.0) & (lambda_b >= 0.0) & (lambda_a + lambda_b <= 1.0)
    if inside.any():
        mask[y_lo:y_hi + 1, x_lo:x_hi + 1] |= inside


def rasterise_obstacles(primitives, grid):
    """Return (mask, triangles_kept) for one primitive set.

    mask[row, column] is True where a body-band triangle of the deck shell
    covers that cell.
    """
    mask = np.zeros((grid.rows, grid.columns), dtype=bool)
    kept = 0

    # Anything more than half the remaining ring past the section start is
    # read as being BEFORE it: that is what puts the margin on the near side
    # of a wrapping section at a small negative offset instead of near 360.
    wrap_threshold = 0.5 * (grid.span_degrees + FULL_TURN_DEGREES)

    for positions, indices in primitives:
        if not positions or len(indices) < 3:
            continue
        points = np.asarray(positions, dtype=np.float64)
        index = np.asarray(indices, dtype=np.int64)
        triangles = index[:(len(index) // 3) * 3].reshape(-1, 3)

        radius = np.hypot(points[:, 0], points[:, 2])
        height = points[:, 1] - DECK_Y
        # game_bearing_degrees, vectorised: axis 2 over axis 0, no sign flip.
        bearing = np.degrees(np.arctan2(points[:, 2], points[:, 0])) % FULL_TURN_DEGREES

        in_shell = (radius >= SHELL_R_IN) & (radius <= SHELL_R_OUT)
        in_body = (height >= BODY_LO) & (height <= BODY_HI)
        wanted = in_shell[triangles].any(axis=1) & in_body[triangles].any(axis=1)
        if not wanted.any():
            continue
        triangles = triangles[wanted]

        offset = (bearing - grid.section_start) % FULL_TURN_DEGREES
        offset = np.where(offset > wrap_threshold, offset - FULL_TURN_DEGREES, offset)

        corner_offsets = offset[triangles]
        span = corner_offsets.max(axis=1) - corner_offsets.min(axis=1)
        placeable = span <= MAX_TRIANGLE_SPAN_DEG
        # Wholly outside the grid's angular window: nothing to rasterise.
        window = (corner_offsets.max(axis=1) >= -MARGIN_DEG) & (
            corner_offsets.min(axis=1) <= grid.span_degrees + MARGIN_DEG)
        keep = placeable & window
        if not keep.any():
            continue
        triangles = triangles[keep]
        corner_offsets = corner_offsets[keep]

        arc = grid.reference_radius * np.radians(corner_offsets)
        cell_x = (arc - grid.arc_min) / CELL - 0.5
        cell_y = (radius[triangles] - grid.radius_min) / CELL - 0.5

        for t in range(triangles.shape[0]):
            _fill_triangle(mask, cell_x[t], cell_y[t], grid)
        kept += triangles.shape[0]

    return mask, kept


# =============================================================================
# EXACT EUCLIDEAN DISTANCE TRANSFORM
#
# Felzenszwalb and Huttenlocher, "Distance Transforms of Sampled Functions".
# The squared distance transform of a 2D grid is the 1D transform applied
# along one axis and then the other, and the 1D transform is the lower
# envelope of one parabola per sample, found in a single forward scan. It is
# exact -- the true squared Euclidean distance in cells, not a chamfer
# approximation -- and linear in the number of cells.
#
# Both passes here run every line of the grid at once as a numpy row, so the
# python loop is over samples (a few hundred) rather than over cells.
# =============================================================================


def _distance_transform_1d(f):
    """Lower envelope of f along axis 1. f is (lines, samples), squared units."""
    lines, samples = f.shape
    if samples == 0:
        return f.copy()

    line_index = np.arange(lines)
    k = np.zeros(lines, dtype=np.int64)          # index of the rightmost parabola
    v = np.zeros((lines, samples), dtype=np.int64)  # parabola locations
    z = np.empty((lines, samples + 1), dtype=np.float64)  # envelope breakpoints
    z[:, 0] = -np.inf
    z[:, 1] = np.inf

    for q in range(1, samples):
        q_value = f[:, q] + float(q) * q
        while True:
            vk = v[line_index, k]
            intersection = (q_value - (f[line_index, vk] + vk * vk)) / (2.0 * q - 2.0 * vk)
            pop = (intersection <= z[line_index, k]) & (k > 0)
            if not pop.any():
                break
            k[pop] -= 1
        vk = v[line_index, k]
        intersection = (q_value - (f[line_index, vk] + vk * vk)) / (2.0 * q - 2.0 * vk)
        k += 1
        v[line_index, k] = q
        z[line_index, k] = intersection
        z[line_index, k + 1] = np.inf

    out = np.empty_like(f)
    k[:] = 0
    for q in range(samples):
        while True:
            advance = z[line_index, k + 1] < float(q)
            if not advance.any():
                break
            k[advance] += 1
        vk = v[line_index, k]
        offset = float(q) - vk
        out[:, q] = offset * offset + f[line_index, vk]
    return out


def distance_transform_cells(mask):
    """Exact Euclidean distance, in cells, from every cell to the nearest True."""
    f = np.where(mask, 0.0, EDT_FAR)
    f = _distance_transform_1d(f)
    f = _distance_transform_1d(np.ascontiguousarray(f.T)).T
    return np.sqrt(np.minimum(f, EDT_FAR))


# =============================================================================
# THE WIDEST-BOTTLENECK ROUTE
# =============================================================================


def widest_route(clearance, grid, band):
    """Maximin route across the section, restricted to the band.

    Returns (bottleneck_clearance, bottleneck_cell, path) where path is a list
    of (row, column) from the section's start bearing to its end bearing.

    Dijkstra with min-of-edge instead of sum-of-edge: the cost of reaching a
    cell is the worst clearance on the best way there, and the best way there
    is the one that maximises it. Popping the largest first makes the first
    pop of a cell final, exactly as popping the smallest does for a sum.
    Neighbours are the eight around a cell; a diagonal step is legal because
    clearance is a field over the plan, not a set of walls, and the value at
    each cell it passes is already accounted for.
    """
    # A row is in the band when its CENTRE is, not when its cell merely
    # touches an edge of it: the route is then reported at radii that are
    # inside the band a caller asked for, and the choice does not turn on
    # which side of an exact cell boundary a float division lands.
    row_lo = grid.rows
    row_hi = -1
    for row in range(grid.rows):
        radius = grid.row_radius(row)
        if band[0] <= radius <= band[1]:
            row_lo = min(row_lo, row)
            row_hi = max(row_hi, row)
    if row_hi < row_lo:
        # A band thinner than one cell: fall back to the cell holding it.
        row_lo = row_hi = grid.row_of_radius(0.5 * (band[0] + band[1]))
    column_lo = grid.column_of_offset(0.0)
    column_hi = grid.column_of_offset(grid.span_degrees)

    height = row_hi - row_lo + 1
    width = column_hi - column_lo + 1
    window = clearance[row_lo:row_hi + 1, column_lo:column_hi + 1]

    best = np.full(height * width, -1.0, dtype=np.float64)
    parent = np.full(height * width, -1, dtype=np.int64)
    settled = np.zeros(height * width, dtype=bool)

    heap = []
    for row in range(height):
        node = row * width
        best[node] = window[row, 0]
        heapq.heappush(heap, (-best[node], node))

    steps = (-1, 0, 1)
    target = -1
    while heap:
        negative_value, node = heapq.heappop(heap)
        if settled[node]:
            continue
        settled[node] = True
        value = -negative_value
        row, column = divmod(node, width)
        if column == width - 1:
            target = node
            break
        for d_row in steps:
            next_row = row + d_row
            if next_row < 0 or next_row >= height:
                continue
            for d_column in steps:
                if d_row == 0 and d_column == 0:
                    continue
                next_column = column + d_column
                if next_column < 0 or next_column >= width:
                    continue
                next_node = next_row * width + next_column
                if settled[next_node]:
                    continue
                candidate = min(value, window[next_row, next_column])
                if candidate > best[next_node]:
                    best[next_node] = candidate
                    parent[next_node] = node
                    heapq.heappush(heap, (-candidate, next_node))

    if target < 0:
        return 0.0, (row_lo, column_lo), []

    path = []
    node = target
    while node >= 0:
        row, column = divmod(node, width)
        path.append((row_lo + row, column_lo + column))
        node = parent[node]
    path.reverse()

    bottleneck = min(clearance[row, column] for row, column in path)
    bottleneck_cell = min(path, key=lambda cell: clearance[cell[0], cell[1]])
    return float(bottleneck), bottleneck_cell, path


def sample_route(path, grid):
    """The route as [bearing, radius] pairs every ROUTE_SAMPLE_DEG degrees.

    A maximin route may double back in bearing, so a sample is the cell on the
    path nearest that bearing rather than the cell at that column: the samples
    are a readable trace of the lane, and the measured numbers above are what
    the route actually is.
    """
    if not path:
        return []
    offsets = np.array([grid.column_offset_degrees(column) for _row, column in path])
    samples = []
    steps = int(math.floor(grid.span_degrees / ROUTE_SAMPLE_DEG)) + 1
    for step in range(steps):
        wanted = step * ROUTE_SAMPLE_DEG
        at = int(np.argmin(np.abs(offsets - wanted)))
        row, column = path[at]
        samples.append([round(grid.column_bearing(column), 3),
                        round(grid.row_radius(row), 3)])
    return samples


# =============================================================================
# MEASUREMENT
# =============================================================================


def measure(path, section, band):
    """Measure both primitive sets of one .glb and return the full result."""
    section_start = normalise_degrees(section[0])
    section_end = normalise_degrees(section[1])
    span = section_span(section_start, section_end)
    band_lo, band_hi = min(band), max(band)
    grid = Grid(section_start, span, 0.5 * (band_lo + band_hi))
    check_bearing_convention()

    gltf, blob = parse_glb(path)
    # collect_primitives is parse_glb's geometry in one world space, already
    # split art from collision by is_collision_name through node_world_matrices.
    art_primitives, collision_primitives, _stats = collect_primitives(gltf, blob)

    sets = {}
    for name, primitives in (("collision", collision_primitives), ("art", art_primitives)):
        mask, kept = rasterise_obstacles(primitives, grid)
        # Capped at the window's diagonal: with no obstacle anywhere in the
        # grid the transform returns its own "no seed" sentinel, and a lane
        # reported as fifty kilometres wide reads as a bug rather than as the
        # true answer, which is "nothing in this window narrows it". The
        # diagonal is the largest distance the window can actually witness,
        # and the obstacle_tris=0 on the note line says which case it is.
        reach = math.hypot(grid.rows, grid.columns) * CELL
        clearance = np.minimum(distance_transform_cells(mask) * CELL, reach)
        bottleneck, cell, route = widest_route(clearance, grid, (band_lo, band_hi))
        sets[name] = {
            "obstacle_tris": kept,
            "obstacle_cells": int(mask.sum()),
            "clearance": bottleneck,
            "gap": 2.0 * bottleneck,
            "bearing": grid.column_bearing(cell[1]),
            "radius": grid.row_radius(cell[0]),
            "route": route,
        }

    return {
        "file": os.path.basename(path),
        "path": path,
        "section": [section_start, section_end],
        "band": [band_lo, band_hi],
        "grid_rows": grid.rows,
        "grid_columns": grid.columns,
        "cell": CELL,
        "collision_gap": sets["collision"]["gap"],
        "art_gap": sets["art"]["gap"],
        "sets": sets,
        "route": sample_route(sets["collision"]["route"], grid),
    }


# =============================================================================
# REPORT
# =============================================================================


def format_block(result):
    """The greppable block. One fact per token, never reordered."""
    lines = ["S1 GAP file=%s section=%.1f,%.1f band=%.2f,%.2f grid=%dx%d cell=%.2f" % (
        result["file"], result["section"][0], result["section"][1],
        result["band"][0], result["band"][1],
        result["grid_rows"], result["grid_columns"], result["cell"])]
    for name in ("collision", "art"):
        measured = result["sets"][name]
        lines.append("S1 GAP %s bottleneck=%.2f m at bearing %.1f r %.1f" % (
            name, measured["gap"], measured["bearing"], measured["radius"]))
    return lines


def json_payload(result):
    """Exactly the four keys the build reads, and nothing it can drift on."""
    return {
        "section": result["section"],
        "band": result["band"],
        "collision_gap": result["collision_gap"],
        "art_gap": result["art_gap"],
        "route": result["route"],
    }


USAGE = """usage: s1_lane_gap.py <map.glb> [--section %.0f,%.0f] [--band %.1f,%.1f]
                       [--json out.json]

  --section A,B   the angular section to cross, in game-bearing degrees.
                  A > B wraps past 360. Default %.0f,%.0f (S1).
  --band LO,HI    the radii the route is allowed to use, in metres.
                  Default %.1f,%.1f.
  --json FILE     write {section, band, collision_gap, art_gap, route} there.

Prints one line per primitive set: the widest bottleneck a body can cross the
section through, in metres, and where that bottleneck is.
""" % (DEFAULT_SECTION + DEFAULT_BAND + DEFAULT_SECTION + DEFAULT_BAND)


def parse_pair(text, flag):
    """Parse 'A,B' into two floats."""
    parts = text.split(",")
    if len(parts) != 2:
        raise ValueError("%s wants two comma-separated numbers, got %r" % (flag, text))
    try:
        return float(parts[0]), float(parts[1])
    except ValueError:
        raise ValueError("%s wants two numbers, got %r" % (flag, text))


def main(argv):
    model_path = None
    section = DEFAULT_SECTION
    band = DEFAULT_BAND
    json_path = None

    rest = list(argv)
    while rest:
        arg = rest.pop(0)
        if arg in ("-h", "--help"):
            sys.stdout.write(USAGE)
            return 0
        if arg in ("--section", "--band", "--json"):
            if not rest:
                sys.stdout.write("S1 GAP FAIL %s needs a value\n" % arg)
                return 1
            value = rest.pop(0)
            try:
                if arg == "--section":
                    section = parse_pair(value, arg)
                elif arg == "--band":
                    band = parse_pair(value, arg)
                else:
                    json_path = value
            except ValueError as error:
                sys.stdout.write("S1 GAP FAIL %s\n" % error)
                return 1
        elif arg.startswith("-"):
            sys.stdout.write("S1 GAP FAIL unknown option %s\n" % arg)
            return 1
        elif model_path is None:
            model_path = arg
        else:
            sys.stdout.write("S1 GAP FAIL more than one file given\n")
            return 1

    if model_path is None:
        sys.stdout.write(USAGE)
        return 1
    if band[0] == band[1]:
        sys.stdout.write("S1 GAP FAIL --band needs two different radii\n")
        return 1

    started = time.time()
    try:
        result = measure(model_path, section, band)
    except (ValueError, OSError, KeyError, IndexError) as error:
        # This runs inside the build pipeline and the pipeline reads the exit
        # code, so an unreadable file is a failed measurement, not a traceback.
        sys.stdout.write("S1 GAP FAIL cannot measure %s: %s\n" % (model_path, error))
        return 1

    for line in format_block(result):
        sys.stdout.write(line + "\n")
    sys.stdout.write("S1 GAP note obstacle_tris collision=%d art=%d seconds=%.1f\n" % (
        result["sets"]["collision"]["obstacle_tris"],
        result["sets"]["art"]["obstacle_tris"],
        time.time() - started))

    if json_path is not None:
        with open(json_path, "w") as handle:
            json.dump(json_payload(result), handle, indent=2, sort_keys=True)
            handle.write("\n")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
