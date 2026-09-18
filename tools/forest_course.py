#!/usr/bin/env python3
"""Emit Map 3's obstacle-course props as .tscn nodes for scenes/ring/forest.tscn.

    python3 tools/forest_course.py > /tmp/course.txt

The layout is the DATA in COURSE below: one row per placed instance, in lap
order. Nothing is welded into forest.glb; every row is a scene instance.
Geometry the rows obey: lane y 23.0 with +-0.12 m relief, deck r 46.7..57.3,
ferns welded at r 46.7..47.6 and r 56.4..57.3, guard's eye y 28.90 at the
centre, so every shadow falls radially OUTWARD and cover only ever protects
what is outboard of it.
"""

import math
import sys

LANE_Y = 22.95          # props sink into the lane's relief rather than float
PAD_Y = 22.95
ORB_Y = 23.00
CHORD_DEG = 16.25       # a pad's 14.7 m throw as an arc at r 52

KINDS = {
    "tree_a":  ("10_tree_a",  "Tree_a"),
    "tree_b":  ("11_tree_b",  "Tree_b"),
    "tree_c":  ("12_tree_c",  "Tree_c"),
    "bush_low":  ("13_bush_low",  "BushLow"),
    "bush_tall": ("14_bush_tall", "BushTall"),
    "boulder": ("15_boulder", "Boulder"),
    "slab":    ("16_slab",    "Slab"),
    "outcrop": ("17_outcrop", "Outcrop"),
    "thorn_round": ("18_thorns_round", "ThornsRound"),
    "thorn_strip": ("19_thorns_strip", "ThornsStrip"),
    "pad":     ("20_demon_pad", "Pad"),
    "orb":     ("21_speed_orb", "Orb"),
}

# aim: how the prop is turned.
#   "run"      local -Z along the run (increasing bearing)
#   "radial"   local +X radially outward, local Z along the lane
#   "broad"    local +X along the lane: a slab's 2.49 m face square to the eye
#   "chord"    local -Z down the 14.7 m pad chord
# A prop stands on one side of the 7.25 m walkable lane or the other, never in
# the middle: one band plus the agent radius already eats half the width, so a
# mid-lane prop leaves two slivers and no corridor. IN puts the corridor OUTSIDE
# it, which is the only side the guard's shadow falls on; OUT leaves the corridor
# inside, in the open. A pad is a 0.1 m plate you run over, so it sits on the
# lane radius.
IN = 50.0
OUT = 53.7
MID = 52.3
# Scales. Nothing on this map is head cover under about 2.6 m (see NAV_Y), so the
# 2.20 m bush and the 2.11 m slab are scaled up in Y to clear it -- the same lever
# map 1 uses on rock_wall (scale y 0.43). X widens the silhouette the guard has to
# see past; a shadow's area is its width times the lane behind it.
BUSH = (1.5, 1.35, 1.0)
STONE = (1.6, 1.4, 1.0)
TRUNK = (1.5, 1.0, 1.5)
COURSE = [
    # ---- Start pocket 5-14: open grass, one boulder on the outside.
    ("Start", "boulder", 10.0, OUT, "radial", 24.0),

    # ---- S1 The Stand 14-74: a trunk slalom. The first four stand INSIDE the
    # lane, so the corridor runs outside them and lies in their shadow; the last
    # three stand OUTSIDE, so the corridor runs inside them in full view. Same
    # stretch, same prop, opposite problem, with an open crossing at 46-52.
    ("S1_Stand", "tree_b", 18.0, IN, "radial", 12.0, TRUNK),
    ("S1_Stand", "tree_a", 26.0, IN, "radial", -40.0),
    ("S1_Stand", "tree_c", 34.0, IN, "radial", 25.0, (1.4, 1.0, 1.4)),
    ("S1_Stand", "tree_b", 42.0, IN, "radial", 130.0),
    ("S1_Stand", "tree_a", 54.0, OUT, "radial", 75.0),
    ("S1_Stand", "tree_c", 62.0, OUT, "radial", -95.0),
    ("S1_Stand", "tree_b", 70.0, OUT, "radial", 160.0, TRUNK),

    # ---- Rest pocket 74-82: one standing stone inside the lane.
    ("Pocket_078", "slab", 78.0, IN, "broad", 0.0, STONE),

    # ---- S2 The Bramble Hedge 82-142: a lethal hedge laid ALONG the lane, 6 m at
    # a time, that changes sides twice. Hoppable at 0.96 m, under the 1.11 m jump
    # apex, so the 2 m width is a choice. The inside runs carry a thicket tall
    # enough to take the guard's head line; the outside run carries none.
    ("S2_Hedge", "bush_tall", 86.0, IN, "broad", 40.0, BUSH),
    ("S2_Hedge", "thorn_strip", 93.0, IN, "broad", 0.0),
    ("S2_Hedge", "thorn_strip", 108.0, OUT, "broad", 0.0),
    ("S2_Hedge", "bush_low", 116.0, OUT, "broad", -30.0),
    ("S2_Hedge", "bush_tall", 126.0, IN, "broad", 115.0, BUSH),
    ("S2_Hedge", "thorn_strip", 134.0, IN, "broad", 0.0),

    # ---- Rest pocket 142-150.
    ("Pocket_146", "slab", 146.0, IN, "broad", 0.0, STONE),

    # ---- S3 The Boulder Field 152-214: three standing stones, 30 deg of open
    # ground apart, are the only head cover. The boulders between them are 1.30 m
    # -- a chest and not a head -- and the 0.70 m shelves are there to be jumped.
    ("S3_Boulders", "slab", 156.0, IN, "broad", 4.0, STONE),
    ("S3_Boulders", "boulder", 164.0, OUT, "radial", 140.0),
    ("S3_Boulders", "outcrop", 171.0, OUT, "radial", 60.0),
    ("S3_Boulders", "boulder", 179.0, IN, "radial", 95.0),
    ("S3_Boulders", "slab", 186.0, IN, "broad", -6.0, STONE),
    ("S3_Boulders", "boulder", 194.0, OUT, "radial", -25.0),
    ("S3_Boulders", "outcrop", 201.0, OUT, "radial", 155.0),
    ("S3_Boulders", "slab", 210.0, IN, "broad", 7.0, STONE),

    # ---- Rest pocket 214-222.
    ("Pocket_218", "slab", 218.0, IN, "broad", 0.0, STONE),

    # ---- S4 The Boost Run 222-282: three pads throw a runner 14.7 m down the
    # lane, straight over a thorn patch, and land him in a thicket's shadow. Walk
    # it instead and the whole stretch is a single outer corridor past the
    # brambles, in the open until the next thicket.
    ("S4_BoostRun", "pad", 224.0, MID, "chord", 0.0),
    ("S4_BoostRun", "bush_low", 227.0, IN, "broad", 20.0),
    ("S4_BoostRun", "thorn_round", 232.0, 49.9, "radial", 0.0),
    ("S4_BoostRun", "orb", 234.0, OUT, "run", 0.0),
    ("S4_BoostRun", "bush_tall", 239.0, 49.6, "broad", -45.0, BUSH),
    ("S4_BoostRun", "pad", 242.0, MID, "chord", 0.0),
    ("S4_BoostRun", "bush_low", 245.0, IN, "broad", 125.0),
    ("S4_BoostRun", "thorn_round", 250.0, 49.9, "radial", 0.0),
    ("S4_BoostRun", "bush_tall", 257.0, 49.6, "broad", 70.0, BUSH),
    ("S4_BoostRun", "pad", 260.0, MID, "chord", 0.0),
    ("S4_BoostRun", "bush_low", 263.0, IN, "broad", -100.0),
    ("S4_BoostRun", "thorn_round", 268.0, 49.9, "radial", 0.0),
    ("S4_BoostRun", "bush_tall", 275.0, 49.6, "broad", 155.0, BUSH),

    # ---- Rest pocket 278-286.
    ("Pocket_282", "slab", 282.0, IN, "broad", 0.0, STONE),

    # ---- S5 The Thicket 286-320: single file. One thicket per bay, sides
    # alternating every 9 deg, so the lane snakes 3.7 m across itself four times
    # and every second bay is the naked one.
    ("S5_Thicket", "bush_tall", 288.0, IN, "broad", 15.0, BUSH),
    ("S5_Thicket", "bush_tall", 297.0, OUT, "broad", -75.0, BUSH),
    ("S5_Thicket", "bush_tall", 306.0, IN, "broad", 105.0, BUSH),
    ("S5_Thicket", "bush_tall", 315.0, OUT, "broad", 35.0, BUSH),

    # ---- S6 The Last Gap 320-335: one bare shelf, one last stone, then 11.8 m
    # of nothing at all to the portal.
    ("S6_LastGap", "outcrop", 324.0, OUT, "radial", 50.0),
    ("S6_LastGap", "slab", 332.0, IN, "broad", 0.0, STONE),
]


SECTION_NOTES = {
    "Start": "Start pocket 5-14 deg: open grass and one boulder on the outside.",
    "S1_Stand": "S1 The Stand 14-74 deg: a trunk slalom, four trunks inside the lane so the corridor runs outside them in their shadow, then three outside so it runs inside them in full view.",
    "Pocket_078": "Rest pocket 74-82 deg: one standing stone inside the lane.",
    "S2_Hedge": "S2 The Bramble Hedge 82-142 deg: a lethal hedge laid along the lane in 6 m runs that change sides twice, hoppable at 0.96 m, with a thicket tall enough for head cover on the inside runs only.",
    "Pocket_146": "Rest pocket 142-150 deg: one standing stone inside the lane.",
    "S3_Boulders": "S3 The Boulder Field 152-214 deg: three standing stones 30 deg apart are the only head cover; the boulders between them hide a chest and not a head and the shelves are there to be jumped.",
    "Pocket_218": "Rest pocket 214-222 deg: one standing stone inside the lane.",
    "S4_BoostRun": "S4 The Boost Run 222-282 deg: three pads throw a runner 14.7 m down the lane over a thorn patch into a thicket's shadow; walking it is one outer corridor past the brambles.",
    "Pocket_282": "Rest pocket 278-286 deg: one standing stone inside the lane.",
    "S5_Thicket": "S5 The Thicket 286-320 deg: single file, one thicket per bay with the sides alternating every 9 deg, so every second bay is the naked one.",
    "S6_LastGap": "S6 The Last Gap 320-335 deg: one bare shelf, one last stone, then 11.8 m of nothing to the portal.",
}


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


def yaw_from_forward(fx, fz):
    """Yaw whose local -Z points along (fx, fz)."""
    return math.degrees(math.atan2(-fx, -fz))


def yaw_from_x_axis(ax, az):
    """Yaw whose local +X points along (ax, az)."""
    return math.degrees(math.atan2(-az, ax))


def place(kind, bearing, radius, aim, spin, scale=(1.0, 1.0, 1.0)):
    b = math.radians(bearing)
    x, z = radius * math.cos(b), radius * math.sin(b)
    y = {"pad": PAD_Y, "orb": ORB_Y}.get(kind, LANE_Y)
    if aim == "radial":
        yaw = yaw_from_x_axis(math.cos(b), math.sin(b))
    elif aim == "broad":
        yaw = yaw_from_x_axis(-math.sin(b), math.cos(b))
    elif aim == "run":
        yaw = yaw_from_forward(-math.sin(b), math.cos(b))
    elif aim == "chord":
        end = math.radians(bearing + CHORD_DEG)
        yaw = yaw_from_forward(math.cos(end) - math.cos(b), math.sin(end) - math.sin(b))
    else:
        raise ValueError(aim)
    rows = basis_rows(yaw + spin)
    # Godot writes the basis as ROWS, so a local axis scale multiplies a COLUMN.
    for r in range(3):
        for c in range(3):
            rows[r * 3 + c] *= scale[c]
    return rows + [x, y, z]


# Collider footprints, from the contracts: (half-width along local X, half-depth
# along local Z, height, lethal). Thorn footprints are the TrapVolume box, which
# the bake carves with LETHAL_INFLATION_METRES 0.8 either side.
FOOTPRINT = {
    "tree_a": (0.45, 0.45, 7.9, False),
    "tree_b": (0.80, 0.80, 6.7, False),
    "tree_c": (0.58, 0.58, 7.0, False),
    "bush_low": (0.86, 0.86, 1.30, False),
    "bush_tall": (1.29, 1.29, 2.20, False),
    "boulder": (1.01, 0.87, 1.30, False),
    "slab": (1.25, 0.33, 2.11, False),
    "outcrop": (1.21, 1.11, 0.70, False),
    "thorn_round": (1.10, 1.10, 0.96, True),
    "thorn_strip": (3.00, 1.00, 0.96, True),
    "pad": (1.25, 1.25, 0.10, False),
    "orb": (0.0, 0.0, 0.0, False),
}
INFLATION = 0.8         # RingBake.LETHAL_INFLATION_METRES
# Measured off the baked mesh with tools/harness/check_course.gd --lane-gaps, not
# derived from the deck: the welded ferns at r 56.4..57.3 and hummocks at
# r 46.7..47.6 carry collision, so the walkable lane is 7.25 m, not 10.6 m.
NAV_INNER = 48.25
NAV_OUTER = 55.50
AGENT_R = 0.5           # RingBake.AGENT_RADIUS: the navmesh is eroded by this
CORRIDOR_MIN = 3.0      # metres of raw lane a corridor needs to survive as navmesh
# The bake samples a body from the NAVMESH, which recast floats 0.5 m over the
# grass (check_course.gd --sight reports navmesh_y=23.50 on a lane at y 23.0).
# So a "head" is 2.0 m over the grass and only an occluder taller than ~2.6 m
# takes the guard's head line. This one number is why 2.2 m props are chest
# cover and nothing more.
NAV_Y = 23.50
EYE_Y = 28.90
LANE_TOP = NAV_Y
HEAD_M = 1.50           # RingBake.COVER_HEAD_METRES


def head_shadow_metres(height):
    """How far outboard of an occluder this tall a head at NAV_Y+1.5 stays hidden."""
    rise = EYE_Y - NAV_Y
    over = height - (NAV_Y - PAD_Y)     # the prop's top, measured from the navmesh
    if over <= HEAD_M:
        return 0.0
    if over >= rise:
        return NAV_OUTER - NAV_INNER
    return 52.0 * ((rise - HEAD_M) / (rise - over) - 1.0)


def check():
    rows = []
    for row in COURSE:
        section, kind, bearing, radius, aim, spin = row[:6]
        sx, sy, sz = row[6] if len(row) > 6 else (1.0, 1.0, 1.0)
        hx, hz, height, lethal = FOOTPRINT[kind]
        hx, hz, height = hx * sx, hz * sz, height * sy
        if lethal:
            hx, hz = hx + INFLATION, hz + INFLATION
        # Radial half-extent: local X is radial for "radial", tangential for "broad".
        radial = hx if aim in ("radial", "chord") else hz
        tangential = hz if aim in ("radial", "chord") else hx
        rows.append((section, kind, bearing, radius, radial, tangential, height, lethal))

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
        for section, kind, b, r, radial, tangential, height, lethal in rows:
            if kind in ("orb", "pad"):
                continue    # a pad is a 0.1 m plate you walk onto, not an obstacle
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


def main():
    counts = {}
    used = {}
    lines = []
    parents = []
    for row in COURSE:
        section, kind, bearing, radius, aim, spin = row[:6]
        scale = row[6] if len(row) > 6 else (1.0, 1.0, 1.0)
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

    print("; --- ext_resource lines for the scene header ---")
    for kind in KINDS:
        if kind in counts:
            print("; %-12s x %d" % (kind, counts[kind]))
    print("; total instances: %d\n" % len(COURSE))
    for section in parents:
        print('[node name="%s" type="Node3D" parent="Sections"]' % section)
        print('editor_description = "%s"\n' % SECTION_NOTES[section])
    print("\n".join(lines))




# =============================================================================
# The cover predictor: RingBake._sample_cover, modelled on the layout data.
#
# The guard's eye sits on the ring's axis, so the plan projection of every sight
# ray is a RADIAL line. A prop blocks a ray iff the ray's bearing crosses the
# prop's footprint and the prop's silhouette there is taller than the ray. That
# makes the whole bake a 1-D problem per bearing, which is why this predicts the
# real number instead of guessing at it.
#
# Silhouette taper matters more than footprint: a ray to a head 1.5 m up passes
# an occluder 1.6-2.1 m off the ground, and that is where a bush or a trunk is
# already narrower than its base.
SILHOUETTE = {          # (fraction of height, fraction of half-width)
    "slab":    [(0.0, 1.00), (0.20, 0.99), (0.42, 0.98), (0.62, 0.95), (0.82, 0.90), (1.0, 0.66)],
    "boulder": [(0.0, 0.90), (0.16, 1.00), (0.40, 1.00), (0.66, 0.93), (0.84, 0.82), (1.0, 0.52)],
    "outcrop": [(0.0, 0.88), (0.20, 1.00), (0.46, 0.98), (0.72, 0.90), (1.0, 0.62)],
    "bush_low":  [(0.0, 0.78), (0.16, 1.00), (0.46, 0.95), (0.76, 0.84), (1.0, 0.44)],
    "bush_tall": [(0.0, 0.78), (0.16, 1.00), (0.46, 0.95), (0.76, 0.84), (1.0, 0.44)],
    "tree_a":  [(0.0, 1.00), (0.13, 0.76), (0.34, 0.71), (0.55, 0.64), (0.76, 0.55), (1.0, 0.43)],
    "tree_b":  [(0.0, 1.00), (0.13, 0.76), (0.34, 0.65), (0.55, 0.56), (0.76, 0.48), (1.0, 0.39)],
    "tree_c":  [(0.0, 1.00), (0.13, 0.79), (0.34, 0.70), (0.55, 0.60), (0.76, 0.52), (1.0, 0.42)],
    "pad":     [(0.0, 1.00), (1.0, 1.00)],
}
CHEST_M = 0.90
CELL = 1.5              # RingBake.COVER_SPACING_METRES
LETHAL_CLEAR = 1.0      # RingBake.COVER_LETHAL_CLEARANCE_METRES


def _half_width(kind, height, frac):
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


def _occluders():
    out = []
    for row in COURSE:
        section, kind, bearing, radius, aim, spin = row[:6]
        sx, sy, sz = row[6] if len(row) > 6 else (1.0, 1.0, 1.0)
        if kind in ("orb", "thorn_round", "thorn_strip"):
            continue        # thorns are 0.96 m spikes: a hazard, never an occluder
        hx, hz, height, _ = FOOTPRINT[kind]
        hx, hz, height = hx * sx, hz * sz, height * sy
        radial = hx if aim in ("radial", "chord") else hz
        tangential = hz if aim in ("radial", "chord") else hx
        out.append((kind, bearing, radius, radial, tangential, height))
    return out


def _lethal_boxes():
    out = []
    for row in COURSE:
        section, kind, bearing, radius, aim, spin = row[:6]
        if not FOOTPRINT[kind][3]:
            continue
        hx, hz = FOOTPRINT[kind][0], FOOTPRINT[kind][1]
        out.append((bearing, radius, hx + INFLATION + LETHAL_CLEAR, hz + INFLATION + LETHAL_CLEAR))
    return out


def _blocked(occ, bearing, radius, sample_h):
    """Is the eye's ray to a body point sample_h metres up at (bearing, radius) stopped?"""
    rise = EYE_Y - NAV_Y
    sink = NAV_Y - PAD_Y        # props stand 0.55 m under the navmesh datum
    for kind, b, r, radial, tangential, height in occ:
        if r >= radius:
            continue
        db = abs(bearing - b)
        db = min(db, 360.0 - db)
        offset = math.radians(db) * r
        if offset > tangential:
            continue
        # The ray's height over the NAVMESH where it passes this prop's radius.
        ray_h = rise - (rise - sample_h) * r / radius
        top = height - sink
        if ray_h >= top:
            continue
        frac = (ray_h + sink) / height
        if offset <= tangential * _half_width(kind, height, frac):
            return True
    return False


def cover():
    occ = _occluders()
    lethal = _lethal_boxes()
    # The cover grid is world-axis-aligned at CELL metres, phased off the navmesh
    # bounding box, so walk the same lattice rather than a polar one.
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
            # A cell inside a prop's own eroded footprint carries no navmesh.
            inside = False
            for kind, b, r, radial, tangential, height in occ:
                db = abs(bearing - b)
                db = min(db, 360.0 - db)
                if (math.radians(db) * r <= tangential + AGENT_R
                        and abs(radius - r) <= radial + AGENT_R):
                    inside = True
                    break
            if inside:
                continue
            for b, r, hx, hz in lethal:
                db = abs(bearing - b)
                db = min(db, 360.0 - db)
                if math.radians(db) * r <= hz and abs(radius - r) <= hx:
                    inside = True
                    break
            if inside:
                continue
            shadow = (_blocked(occ, bearing, radius, CHEST_M)
                      and _blocked(occ, bearing, radius, HEAD_M))
            lit[(i, k)] = (bearing, radius, not shadow)

    # The flood: a shadow cell counts only once light reaches its 4-neighbourhood.
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
    else:
        main()
