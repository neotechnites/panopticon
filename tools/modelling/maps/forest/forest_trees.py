#!/usr/bin/env python3
"""Grow Map 3's wood: trees across the whole ring, as .tscn nodes for
maps/forest/forest.tscn.

    python3 tools/modelling/maps/forest/forest_trees.py            # print the node block
    python3 tools/modelling/maps/forest/forest_trees.py --write    # splice it into maps/forest/forest.tscn
    python3 tools/modelling/maps/forest/forest_trees.py --check    # overlaps and the walkable corridor
    python3 tools/modelling/maps/forest/forest_trees.py --cover    # predict what RingBake will find

Ryan: "for the forest level, im not going to complete it, it just needs to look
good, can you spread trees across the whole thing like in the beginning, it
looks good." The beginning of the lap -- S1 The Stand, a trunk slalom at 14..74
deg -- is what the whole lap is now. The obstacle course this file used to lay
out (thorn hedges, boost pads, the orb, the standing stones) is gone; the wood is
the map.

The layout is the DATA in LAYOUT below, grown once from SEED by grow() so the
same numbers come out every run, and every row is a scene instance: nothing is
welded into forest.glb. Four lines of trees run round the ring:

    LIP   r 47.45  in the lip's fern band, off the walkable lane (a and c only:
                   b's 1.28 m root flare would hang over the drop)
    IN    r 49.9   inside the walkable lane: the corridor runs outside it
    OUT   r 53.8   outside the walkable lane: the corridor runs inside it
    WALL  r 56.55  in the wall-foot fern band, off the walkable lane, between
                   the leaf wall's own 12 trunks and its 12 lower cell mouths

Geometry the rows obey: lane y 23.0 with +-0.12 m relief, deck r 46.7..57.3,
ferns welded at r 46.7..47.6 and r 56.4..57.3 so the baked mesh runs
r 48.25..55.50 (7.25 m). One lane band plus the agent radius eats half of that,
so a lane tree stands IN or OUT and never in the middle, and where the line
swaps sides the two trees are far enough apart along the run for a 3 m corridor
to snake between them. The lap stays walkable (check_course.gd walk=ok) and the
guard's eye is on the ring's axis, so the crown floor at 3.0 m clears every
sightline the trunks do not stop.
"""

import math
import random
import re
import sys

LANE_Y = 22.95          # props sink into the lane's relief rather than float
SEED = 20260922

KINDS = {
    "tree_a":  ("10_tree_a",  "Tree_a"),
    "tree_b":  ("11_tree_b",  "Tree_b"),
    "tree_c":  ("12_tree_c",  "Tree_c"),
    "bush_low":  ("13_bush_low",  "BushLow"),
    "bush_tall": ("14_bush_tall", "BushTall"),
    "boulder": ("15_boulder", "Boulder"),
    "outcrop": ("17_outcrop", "Outcrop"),
}
RESOURCE_PATHS = {
    "10_tree_a": "res://maps/forest/models/forest_tree_prop_a.glb",
    "11_tree_b": "res://maps/forest/models/forest_tree_prop_b.glb",
    "12_tree_c": "res://maps/forest/models/forest_tree_prop_c.glb",
    "13_bush_low": "res://maps/forest/models/forest_bush_low.glb",
    "14_bush_tall": "res://maps/forest/models/forest_bush_tall.glb",
    "15_boulder": "res://maps/forest/models/forest_rock_boulder.glb",
    "17_outcrop": "res://maps/forest/models/forest_rock_outcrop.glb",
}

# The four lines. (radius, section node, kinds that may stand there with their
# weights, the chance a slot is undergrowth instead of a tree, step range in
# degrees between neighbours on the same line, uniform scale range.)
LIP, IN, OUT, WALL = 47.45, 49.9, 53.8, 56.55
LINES = {
    "Lip":  {"r": LIP,  "trees": (("tree_a", 3), ("tree_c", 2)),
             "under": (("bush_low", 2), ("boulder", 1)), "p_under": 0.28,
             "step": (4.0, 8.0), "scale": (0.85, 1.15)},
    "Lane": {"trees": (("tree_a", 4), ("tree_b", 4), ("tree_c", 3)),
             "under": (("bush_low", 1), ("bush_tall", 2), ("boulder", 1), ("outcrop", 1)),
             "p_under": 0.22, "step": (4.5, 7.5), "scale": (0.9, 1.25)},
    "Wall": {"r": WALL, "trees": (("tree_a", 3), ("tree_b", 4), ("tree_c", 2)),
             "under": (("bush_tall", 2), ("outcrop", 1)), "p_under": 0.25,
             "step": (3.5, 6.5), "scale": (0.9, 1.25)},
}
# Where the wood is not. The finish: portal at 345, the map's own fallen-log
# fence at 350, the bars at 353, the start at 5. The lane lines also leave the
# start pocket and the run-in to the portal open.
CLEAR_ALL = (341.0, 359.0)
CLEAR_LANE = (329.0, 12.0)
LANE_SWAP_MIN_DEG = 6.5     # a side swap needs this much run for the corridor to snake
LANE_RUN = (1, 3)           # trees on one side before the line swaps
# The leaf wall's own trunks (forest_build.TRUNKS, pilasters up to 1 m proud)
# and its lower cell mouths (WALL_CELLS, 3 m wide): a wall tree stands between.
WALL_TRUNKS = [8.0, 38.0, 66.0, 92.0, 120.0, 148.0, 176.0, 204.0, 232.0, 258.0, 286.0, 342.0]
WALL_CELLS = [22.0, 50.0, 78.0, 104.0, 131.0, 158.0, 186.0, 212.0, 240.0, 268.0, 296.0, 318.0]
WALL_TRUNK_CLEAR = 3.5
WALL_CELL_CLEAR = 1.9
# c leans ~17 deg along its local +X. "radial" aim points +X outward, so a lip
# or IN tree leans out across the lane and an OUT or wall tree is spun round to
# lean in across it: the crown hangs over the path, never into the wall or the
# drop. Spread so no two lean alike.
LEAN_JITTER = 25.0

SECTION_NOTES = {
    "Lip": "The lip line: trees and undergrowth in the ravine-edge fern band (r 47.45), off the walkable lane, the leaners' crowns hanging out over the path.",
    "Lane": "The lane line: trunks standing IN (r 49.9) or OUT (r 53.8) of the walkable lane and never mid-lane, swapping sides every one to three trees so the corridor snakes through the wood; the start pocket and the run-in to the portal stay open.",
    "Wall": "The wall line: trees and undergrowth in the wall-foot fern band (r 56.55), off the walkable lane, standing between the leaf wall's own trunks and its lower cell mouths.",
}


def _in_arc(bearing, arc):
    lo, hi = arc
    b = bearing % 360.0
    if lo <= hi:
        return lo <= b <= hi
    return b >= lo or b <= hi


def _pick(rng, table):
    total = sum(w for _, w in table)
    roll = rng.uniform(0.0, total)
    for kind, w in table:
        roll -= w
        if roll <= 0.0:
            return kind
    return table[-1][0]


def _spin(rng, kind, faces_out):
    """Yaw off the radial aim. A leaner leans across the lane; the rest turn freely."""
    if kind == "tree_c":
        return (0.0 if faces_out else 180.0) + rng.uniform(-LEAN_JITTER, LEAN_JITTER)
    return rng.uniform(0.0, 360.0)


def _row(section, kind, bearing, radius, spin, scale):
    return (section, kind, round(bearing % 360.0, 2), radius, "radial", round(spin, 2),
            (round(scale, 3),) * 3)


def _line(rng, name, spec, clear, radius_fn, faces_out_fn, skip_fn=None):
    rows = []
    bearing = rng.uniform(0.0, spec["step"][1])
    while bearing < 360.0:
        step = rng.uniform(*spec["step"])
        if not _in_arc(bearing, clear) and not (skip_fn and skip_fn(bearing)):
            under = rng.random() < spec["p_under"]
            kind = _pick(rng, spec["under"] if under else spec["trees"])
            scale = 1.0 if under else rng.uniform(*spec["scale"])
            faces_out = faces_out_fn()
            rows.append(_row(name, kind, bearing, radius_fn(),
                             _spin(rng, kind, faces_out), scale))
        bearing += step
    return rows


def _lane(rng, spec):
    """IN and OUT, one line that swaps sides in runs of LANE_RUN trees. The
    swap step is at least LANE_SWAP_MIN_DEG so the corridor between the last
    tree on one side and the first on the other is a diagonal a body can take."""
    rows = []
    side_out = rng.random() < 0.5
    left_in_run = rng.randint(*LANE_RUN)
    bearing = CLEAR_LANE[1] + rng.uniform(1.0, 4.0)
    while bearing < CLEAR_LANE[0]:
        under = rng.random() < spec["p_under"]
        kind = _pick(rng, spec["under"] if under else spec["trees"])
        scale = 1.0 if under else rng.uniform(*spec["scale"])
        rows.append(_row("Lane", kind, bearing, OUT if side_out else IN,
                         _spin(rng, kind, not side_out), scale))
        left_in_run -= 1
        step = rng.uniform(*spec["step"])
        if left_in_run <= 0:
            side_out = not side_out
            left_in_run = rng.randint(*LANE_RUN)
            step = max(step, LANE_SWAP_MIN_DEG + rng.uniform(0.0, 1.5))
        bearing += step
    return rows


def _near_wall_feature(bearing):
    for b in WALL_TRUNKS:
        d = abs((bearing - b + 180.0) % 360.0 - 180.0)
        if d < WALL_TRUNK_CLEAR:
            return True
    for b in WALL_CELLS:
        d = abs((bearing - b + 180.0) % 360.0 - 180.0)
        if d < WALL_CELL_CLEAR:
            return True
    return False


def grow(seed=SEED):
    rng = random.Random(seed)
    rows = []
    rows += _line(rng, "Lip", LINES["Lip"], CLEAR_ALL, lambda: LIP, lambda: True)
    rows += _lane(rng, LINES["Lane"])
    rows += _line(rng, "Wall", LINES["Wall"], CLEAR_ALL, lambda: WALL, lambda: False,
                  _near_wall_feature)
    return rows


LAYOUT = grow()


def fmt(value):
    if abs(value) < 1e-9:       # a yaw of exactly 90 deg leaves 6e-17 in a cosine
        return "0"
    text = "%.6g" % value
    return "0" if text in ("-0", "0") else text


def basis_rows(yaw_deg):
    """Godot writes a Basis as ROWS; a yaw about Y is (c,0,s, 0,1,0, -s,0,c)."""
    c = math.cos(math.radians(yaw_deg))
    s = math.sin(math.radians(yaw_deg))
    return [c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c]


def yaw_from_x_axis(ax, az):
    """Yaw whose local +X points along (ax, az)."""
    return math.degrees(math.atan2(-az, ax))


def place(kind, bearing, radius, aim, spin, scale=(1.0, 1.0, 1.0)):
    b = math.radians(bearing)
    x, z = radius * math.cos(b), radius * math.sin(b)
    if aim == "radial":
        yaw = yaw_from_x_axis(math.cos(b), math.sin(b))
    elif aim == "broad":
        yaw = yaw_from_x_axis(-math.sin(b), math.cos(b))
    else:
        raise ValueError(aim)
    rows = basis_rows(yaw + spin)
    # Godot writes the basis as ROWS, so a local axis scale multiplies a COLUMN.
    for r in range(3):
        for c in range(3):
            rows[r * 3 + c] *= scale[c]
    return rows + [x, LANE_Y, z]


# Collider footprints, from the contracts: (half-width along local X, half-depth
# along local Z, height). The leaner's trunk drifts 0.42 m off its foot by head
# height, so its footprint is the drifted trunk and not the foot.
FOOTPRINT = {
    "tree_a": (0.45, 0.45, 7.9),
    "tree_b": (0.80, 0.80, 6.7),
    "tree_c": (0.75, 0.58, 7.0),
    "bush_low": (0.86, 0.86, 1.30),
    "bush_tall": (1.29, 1.29, 2.20),
    "boulder": (1.01, 0.87, 1.30),
    "outcrop": (1.21, 1.11, 0.70),
}
# Measured off the baked mesh with tools/harness/check_course.gd --lane-gaps, not
# derived from the deck: the welded ferns at r 56.4..57.3 and hummocks at
# r 46.7..47.6 carry collision, so the walkable lane is 7.25 m, not 10.6 m.
NAV_INNER = 48.25
NAV_OUTER = 55.50
AGENT_R = 0.5           # RingBake.AGENT_RADIUS: the navmesh is eroded by this
CORRIDOR_MIN = 3.0      # metres of raw lane a corridor needs to survive as navmesh
# The bake samples a body from the NAVMESH, which recast floats 0.5 m over the
# grass (check_course.gd --sight reports navmesh_y=23.50 on a lane at y 23.0).
NAV_Y = 23.50
EYE_Y = 28.90
HEAD_M = 1.50           # RingBake.COVER_HEAD_METRES


def _footprints():
    out = []
    for section, kind, bearing, radius, aim, spin, scale in LAYOUT:
        hx, hz, height = FOOTPRINT[kind]
        hx, hz, height = hx * scale[0], hz * scale[2], height * scale[1]
        # Radial half-extent: local X is radial for "radial", tangential for "broad".
        radial = hx if aim == "radial" else hz
        tangential = hz if aim == "radial" else hx
        out.append((section, kind, bearing, radius, radial, tangential, height))
    return out


def check():
    rows = _footprints()
    print("; --- overlaps (centres closer than the two footprints) ---")
    bad = 0
    for i in range(len(rows)):
        for j in range(i + 1, len(rows)):
            a, b = rows[i], rows[j]
            da = abs(a[2] - b[2])
            da = min(da, 360.0 - da)
            gap_t = math.radians(da) * 52.0 - (a[5] + b[5])
            gap_r = abs(a[3] - b[3]) - (a[4] + b[4])
            if gap_t < 0.0 and gap_r < 0.0:
                bad += 1
                print("; OVERLAP %s@%g r%g  vs  %s@%g r%g  (%.2f m, %.2f m)"
                      % (a[1], a[2], a[3], b[1], b[2], b[3], gap_t, gap_r))
    print("; overlaps: %d\n" % bad)

    print("; --- the corridor, eroded by the agent radius, every 0.1 deg ---")
    worst = (99.0, 0.0)
    pinched = []
    for step in range(3600):
        bearing = step / 10.0
        blocked = []
        for section, kind, b, r, radial, tangential, height in rows:
            da = abs(bearing - b)
            da = min(da, 360.0 - da)
            if math.radians(da) * r > tangential + AGENT_R:
                continue
            blocked.append((r - radial - AGENT_R, r + radial + AGENT_R))
        free, edge = 0.0, NAV_INNER
        for lo, hi in sorted(blocked):
            if lo > edge:
                free = max(free, lo - edge)
            edge = max(edge, hi)
        free = max(free, NAV_OUTER - edge)
        if not (5.0 <= bearing <= 335.0):
            continue
        if free < worst[0]:
            worst = (free, bearing)
        if free < CORRIDOR_MIN:
            pinched.append((bearing, free))
    print("; narrowest corridor on the run: %.2f m at %.1f deg" % worst)
    if pinched:
        runs = []
        start, last, low = pinched[0][0], pinched[0][0], pinched[0][1]
        for bearing, free in pinched[1:]:
            if bearing - last > 0.15:
                runs.append((start, last, low))
                start, low = bearing, free
            low = min(low, free)
            last = bearing
        runs.append((start, last, low))
        for lo, hi, free in runs:
            print("; PINCH %.1f..%.1f deg: %.2f m" % (lo, hi, free))
    print("; pinched bearings under %.1f m: %d of 3300\n" % (CORRIDOR_MIN, len(pinched)))

    # Where the lane line swaps sides, the diagonal between the two trees.
    lane = [r for r in rows if r[0] == "Lane"]
    lane.sort(key=lambda r: r[2])
    tight = 99.0
    for a, b in zip(lane, lane[1:]):
        if (a[3] < 52.0) == (b[3] < 52.0):
            continue
        run = math.radians(b[2] - a[2]) * 52.0 - (a[5] + b[5]) - 2 * AGENT_R
        tight = min(tight, run)
    print("; tightest side-swap diagonal on the lane line: %.2f m\n" % tight)


def block():
    """The scene text: section parents, then one instance per row."""
    counts = {}
    used = {}
    lines = []
    parents = []
    for section, kind, bearing, radius, aim, spin, scale in LAYOUT:
        if section not in used:
            parents.append(section)
            used[section] = set()
        counts[kind] = counts.get(kind, 0) + 1
        resource, stem = KINDS[kind]
        name = "%s_%03ddeg" % (stem, round(bearing))
        suffix = 2
        while name in used[section]:
            name = "%s_%03ddeg_%d" % (stem, round(bearing), suffix)
            suffix += 1
        used[section].add(name)
        numbers = ", ".join(fmt(v) for v in place(kind, bearing, radius, aim, spin, scale))
        lines.append('[node name="%s" parent="Sections/%s" instance=ExtResource("%s")]'
                     % (name, section, resource))
        lines.append("transform = Transform3D(%s)\n" % numbers)
    head = []
    for section in parents:
        head.append('[node name="%s" type="Node3D" parent="Sections"]' % section)
        head.append('editor_description = "%s"\n' % SECTION_NOTES[section])
    return counts, head, lines


def main():
    counts, head, lines = block()
    print("; --- instances ---")
    for kind in KINDS:
        if kind in counts:
            print("; %-12s x %d" % (kind, counts[kind]))
    print("; total instances: %d\n" % len(LAYOUT))
    print("\n".join(head))
    print("\n".join(lines))


SCENE = "maps/forest/forest.tscn"


def write():
    """Splice the block into the scene: the ext_resource lines for the kinds in
    use replace ids 10..21, and everything under Sections/ after the Watch
    markers up to Route is replaced. Nothing else in the file moves."""
    with open(SCENE) as f:
        text = f.read()
    counts, head, lines = block()
    # ext_resources: keep the map's own (ids 1..9), rewrite the prop ids.
    ext = re.findall(r'^\[ext_resource [^\n]*\]\n', text, re.M)
    keep = [e for e in ext if not re.search(r'id="(1\d|2\d)_', e)]
    props = ['[ext_resource type="PackedScene" path="%s" id="%s"]\n' % (RESOURCE_PATHS[rid], rid)
             for rid in sorted(RESOURCE_PATHS) if any(KINDS[k][0] == rid for k in counts)]
    first = text.index(ext[0])
    last = text.index(ext[-1]) + len(ext[-1])
    text = text[:first] + "".join(keep + props) + text[last:]
    subs = len(re.findall(r'^\[sub_resource ', text, re.M))
    text = re.sub(r'^\[gd_scene load_steps=\d+', '[gd_scene load_steps=%d' % (len(keep) + len(props) + subs + 1), text, count=1, flags=re.M)
    # the Sections block
    start = text.index('[node name="Watch" type="Node3D" parent="Sections"]')
    start = text.index('\n\n', text.index('[node name="Lane300"', start)) + 2
    end = text.index('[node name="Route" type="Node3D" parent="."]')
    text = text[:start] + "\n".join(head) + "\n" + "\n".join(lines) + "\n" + text[end:]
    with open(SCENE, "w") as f:
        f.write(text)
    print("wrote %d instances into %s" % (len(LAYOUT), SCENE))


# =============================================================================
# The cover predictor: RingBake._sample_cover, modelled on the layout data.
#
# The guard's eye sits on the ring's axis, so the plan projection of every sight
# ray is a RADIAL line. A prop blocks a ray iff the ray's bearing crosses the
# prop's footprint and the prop's silhouette there is taller than the ray. That
# makes the whole bake a 1-D problem per bearing, which is why this predicts the
# real number instead of guessing at it.
SILHOUETTE = {          # (fraction of height, fraction of half-width)
    "boulder": [(0.0, 0.90), (0.16, 1.00), (0.40, 1.00), (0.66, 0.93), (0.84, 0.82), (1.0, 0.52)],
    "outcrop": [(0.0, 0.88), (0.20, 1.00), (0.46, 0.98), (0.72, 0.90), (1.0, 0.62)],
    "bush_low":  [(0.0, 0.78), (0.16, 1.00), (0.46, 0.95), (0.76, 0.84), (1.0, 0.44)],
    "bush_tall": [(0.0, 0.78), (0.16, 1.00), (0.46, 0.95), (0.76, 0.84), (1.0, 0.44)],
    "tree_a":  [(0.0, 1.00), (0.13, 0.76), (0.34, 0.71), (0.55, 0.64), (0.76, 0.55), (1.0, 0.43)],
    "tree_b":  [(0.0, 1.00), (0.13, 0.76), (0.34, 0.65), (0.55, 0.56), (0.76, 0.48), (1.0, 0.39)],
    "tree_c":  [(0.0, 1.00), (0.13, 0.79), (0.34, 0.70), (0.55, 0.60), (0.76, 0.52), (1.0, 0.42)],
}
CHEST_M = 0.90
CELL = 1.5              # RingBake.COVER_SPACING_METRES


def _half_width(kind, frac):
    """Half-width of the silhouette at height fraction frac of its own height."""
    if frac <= 0.0:
        return 1.0
    if frac >= 1.0:
        return 0.0
    table = SILHOUETTE[kind]
    for i in range(1, len(table)):
        if frac <= table[i][0]:
            f0, w0 = table[i - 1]
            f1, w1 = table[i]
            t = (frac - f0) / (f1 - f0)
            return w0 + t * (w1 - w0)
    return table[-1][1]


def _blocked(occ, bearing, radius, sample_h):
    """Is the eye's ray to a body point sample_h metres up at (bearing, radius) stopped?"""
    rise = EYE_Y - NAV_Y
    sink = NAV_Y - LANE_Y       # props stand 0.55 m under the navmesh datum
    for section, kind, b, r, radial, tangential, height in occ:
        if r >= radius:
            continue
        db = abs(bearing - b)
        db = min(db, 360.0 - db)
        offset = math.radians(db) * r
        if offset > tangential:
            continue
        ray_h = rise - (rise - sample_h) * r / radius
        top = height - sink
        if ray_h >= top:
            continue
        frac = (ray_h + sink) / height
        if offset <= tangential * _half_width(kind, frac):
            return True
    return False


def cover():
    occ = _footprints()
    span = int(math.ceil(2 * NAV_OUTER / CELL)) + 1
    lit = {}
    for i in range(span):
        for k in range(span):
            x = -NAV_OUTER + (i + 0.5) * CELL
            z = -NAV_OUTER + (k + 0.5) * CELL
            radius = math.hypot(x, z)
            if not (NAV_INNER <= radius <= NAV_OUTER):
                continue
            bearing = math.degrees(math.atan2(z, x)) % 360.0
            inside = False
            for section, kind, b, r, radial, tangential, height in occ:
                db = abs(bearing - b)
                db = min(db, 360.0 - db)
                if (math.radians(db) * r <= tangential + AGENT_R
                        and abs(radius - r) <= radial + AGENT_R):
                    inside = True
                    break
            if inside:
                continue
            shadow = (_blocked(occ, bearing, radius, CHEST_M)
                      and _blocked(occ, bearing, radius, HEAD_M))
            lit[(i, k)] = (bearing, radius, not shadow)

    keep = set()
    queue = [c for c, v in lit.items() if v[2]]
    while queue:
        i, k = queue.pop()
        for di, dk in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (i + di, k + dk)
            if n in lit and not lit[n][2] and n not in keep:
                keep.add(n)
                queue.append(n)

    bins = {}
    for c in keep:
        bins[int(lit[c][0] // 5) * 5] = bins.get(int(lit[c][0] // 5) * 5, 0) + 1
    print("; predicted cover points: %d  (grid cells on the lane: %d, lit %d)"
          % (len(keep), len(lit), sum(1 for v in lit.values() if v[2])))
    print("; per 5 deg: " + " ".join("%d:%d" % (b, bins[b]) for b in sorted(bins)))


if __name__ == "__main__":
    if "--check" in sys.argv:
        check()
    elif "--cover" in sys.argv:
        cover()
    elif "--write" in sys.argv:
        write()
    else:
        main()
