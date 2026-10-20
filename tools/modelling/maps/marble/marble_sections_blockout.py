"""
marble_sections_blockout -- the four lane sections as a GREY BLOCKOUT in maps/marble/marble.tscn
(Ryan 2026-10-19: block it out, get it right, then build it to the hell/forest specs).

A  trapdoors under cover: full-lane trapdoors, a wall on the inner edge over each, its activator
   at the trapdoor's start behind the wall's lead-in; open uncovered ground between.
B  one wall just over a runner's head along the inner edge; trapdoors in the lane, their activators
   on the wall's top, where only the rifle reaches them.
C  aesthetic: evenly spaced buttresses on the outer wall's piers.
D  aesthetic: a column forest, every column a different height, all jumpable, walkable between.

Walls are CSGPolygon3D spins (the shape) over per-lane-cell BoxShape3D colliders; buttresses boxes;
columns cylinders. Trapdoors are maps/marble/props/marble_trapdoor.tscn on marble_build's piers.

    python3 tools/modelling/maps/marble/marble_sections_blockout.py --write   # patch marble.tscn
    python3 tools/modelling/maps/marble/marble_sections_blockout.py --layout out.png
then  python3 tools/modelling/maps/marble/marble_build.py --sync-trapdoors ; model build marble
"""

import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
SCENE = os.path.join(REPO, "maps", "marble", "marble.tscn")

# =============================================================================
# TUNABLES
# =============================================================================

DECK_Y = 23.0
CELL = 360.0 / 128.0            # one lane cell, 2.8125 deg
BAY = 2.0 * CELL                # one bay, pier to pier
INNER_R = 46.7                  # the open lip
STRIP = (46.8, 49.4)            # the section walls' footprint: DECK_RS[0]..[1], kept as deck over every hole
WALL_FACE_R = 59.55             # the lane tier's pilaster faces
TRAP_R = 0.5 * (49.4 + 60.0 * math.cos(math.pi / 64.0))   # marble_build.TRAPDOOR_R
TRAP_CELLS = 4                  # marble_build.TRAPDOOR_CELLS

WALL_H = 3.0                    # A and B: over a 1.8 m runner and his 1.1 m jump; hides the 29.3 m eye from the lane
ACT_BEFORE_DEG = 1.4            # the activator this far before its trapdoor's first pier
ACT_R_LANE = 50.4               # A: on the lane, 1 m outside the wall's face
ACT_R_TOP = 0.5 * (STRIP[0] + STRIP[1])   # B: on the wall top's centre line

# A: three trapdoors, a bay of open ground between, the wall one cell ahead of each (its activator's cover)
A_STARTS = (73.125, 90.0, 106.875)
A_LEAD_CELLS = 1
# B: one wall from B_WALL[0] to B_WALL[1], two trapdoors under it
B_WALL = (258.75, 295.3125)
B_STARTS = (264.375, 281.25)
# C: a buttress on every pier from C_FIRST, C_COUNT of them
C_FIRST, C_COUNT = 196.875, 9
BUTT_W = 1.2                    # across the pier
BUTT_LOW = (2.2, 4.5)           # depth off the wall, height
BUTT_HIGH = (1.2, 7.4)          # ... the set-back upper stage, to the tier cornice's foot
BUTT_EMBED = 0.10               # into the pilaster: no seam of light
# D: rows of columns across the lane, staggered, every height different
D_ARC = (16.0, 57.0)
D_ROWS = (48.1, 50.7, 53.3, 55.9)
D_PITCH = 3.4                   # metres along a row
D_RADIUS = 0.6                  # a 1.2 m top to land on
D_H = (0.7, 3.6)                # lowest and highest top
D_STEP = 0.9                    # a top this far over its neighbour's is a jump up (apex 1.11 m)
D_REACH = 4.3                   # centre to centre, a neighbour you can jump to

GREY = (0.63, 0.61, 0.58)


def rad(b):
    return math.radians(b)


def basis(b):
    """Rows of the basis turning +X onto bearing b (tscn is row-major)."""
    c, s = math.cos(rad(b)), math.sin(rad(b))
    return "%.6f, 0, %.6f, 0, 1, 0, %.6f, 0, %.6f" % (c, -s, s, c)


def at(b, r, y=DECK_Y):
    return (r * math.cos(rad(b)), y, r * math.sin(rad(b)))


def xform(b, p):
    return "Transform3D(%s, %.4f, %.4f, %.4f)" % (basis(b), p[0], p[1], p[2])


class Scene(object):
    def __init__(self):
        self.subs, self.nodes, self.shapes = [], [], {}

    def sub(self, key, text):
        if key not in self.shapes:
            self.shapes[key] = "Blk_%d" % len(self.shapes)
            self.subs.append('[sub_resource type="%s" id="%s"]\n%s\n' % (text[0], self.shapes[key], text[1]))
        return self.shapes[key]

    def box(self, size):
        size = tuple(round(v, 4) for v in size)
        return (self.sub(("bm",) + size, ("BoxMesh", 'material = SubResource("Blk_mat")\nsize = Vector3(%.4f, %.4f, %.4f)' % size)),
                self.sub(("bs",) + size, ("BoxShape3D", "size = Vector3(%.4f, %.4f, %.4f)" % size)))

    def cyl(self, r, h):
        r, h = round(r, 3), round(h, 3)
        return (self.sub(("cm", r, h), ("CylinderMesh", 'material = SubResource("Blk_mat")\ntop_radius = %.3f\n'
                                        'bottom_radius = %.3f\nheight = %.3f\nradial_segments = 12\nrings = 1' % (r, r, h))),
                self.sub(("cs", r, h), ("CylinderShape3D", "radius = %.3f\nheight = %.3f" % (r, h))))

    def node(self, text):
        self.nodes.append(text)


def solid(sc, parent, name, b, p, mesh, shape, desc=None):
    """A StaticBody3D at bearing b, centre p, with its mesh and its collider."""
    d = 'editor_description = "%s"\n' % desc if desc else ""
    sc.node('[node name="%s" type="StaticBody3D" parent="%s"]\n%stransform = %s\n' % (name, parent, d, xform(b, p)))
    sc.node('[node name="Mesh" type="MeshInstance3D" parent="%s/%s"]\nmesh = SubResource("%s")\n' % (parent, name, mesh))
    sc.node('[node name="Shape" type="CollisionShape3D" parent="%s/%s"]\nshape = SubResource("%s")\n' % (parent, name, shape))


def arc_wall(sc, parent, name, b0, b1, desc):
    """A wall on the strip from bearing b0 to b1 (whole lane cells): one CSG spin to see, a box per cell to hit."""
    n = int(round((b1 - b0) / CELL))
    r0, r1 = STRIP
    sc.node('[node name="%s" type="CSGPolygon3D" parent="%s"]\neditor_description = "%s"\ntransform = %s\n'
            'polygon = PackedVector2Array(%.3f, 0, %.3f, 0, %.3f, %.3f, %.3f, %.3f)\nmode = 1\nspin_degrees = %.4f\n'
            'spin_sides = %d\nmaterial = SubResource("Blk_mat")\n'
            % (name, parent, desc, xform(b1, (0.0, DECK_Y, 0.0)), r0, r1, r1, WALL_H, r0, WALL_H, b1 - b0, n))
    sc.node('[node name="%sBody" type="StaticBody3D" parent="%s"]\n' % (name, parent))
    half = math.radians(CELL / 2.0)
    size = ((r1 - r0) * math.cos(half), WALL_H, 2.0 * r1 * math.sin(half))
    _m, shape = sc.box(size)
    for k in range(n):
        b = b0 + (k + 0.5) * CELL
        rc = 0.5 * (r0 + r1) * math.cos(half)
        sc.node('[node name="Cell%02d" type="CollisionShape3D" parent="%s/%sBody"]\ntransform = %s\nshape = SubResource("%s")\n'
                % (k, parent, name, xform(b, at(b, rc, DECK_Y + WALL_H / 2.0)), shape))


def trapdoor(sc, parent, name, start, act_r, act_y, desc):
    """marble_trapdoor on the pier at its centre, its activator ACT_BEFORE_DEG before its start."""
    centre = start + TRAP_CELLS / 2.0 * CELL
    d = rad(start - ACT_BEFORE_DEG - centre)
    off = (act_r * math.cos(d) - TRAP_R, act_y, act_r * math.sin(d))
    sc.node('[node name="%s" parent="%s" instance=ExtResource("Blk_trapdoor")]\neditor_description = "%s"\n'
            'transform = %s\ntarget_offset = Vector3(%.4f, %.4f, %.4f)\ntarget_yaw_degrees = %.3f\n'
            % (name, parent, desc, xform(centre, at(centre, TRAP_R)), off[0], off[1], off[2], -math.degrees(d)))


def section_a(sc):
    p = "Elements/SectionA"
    sc.node('[node name="SectionA" type="Node3D" parent="Elements"]\neditor_description = "A, Ryan 2026-10-19: '
            'trapdoors that span the full lane; where there is trapdoor floor there is cover (a wall on the inner edge), '
            'where there is not there is not; an activator at the start of each, behind the wall. %.2f..%.2f deg."\n'
            % (A_STARTS[0] - A_LEAD_CELLS * CELL, A_STARTS[-1] + TRAP_CELLS * CELL))
    for j, s in enumerate(A_STARTS):
        e = s + TRAP_CELLS * CELL
        arc_wall(sc, p, "Wall%d" % (j + 1), s - A_LEAD_CELLS * CELL, e,
                 "Cover over trapdoor %d: r %.1f..%.1f, %.1f m, %.4f..%.4f deg (one cell ahead hides the activator)."
                 % (j + 1, STRIP[0], STRIP[1], WALL_H, s - A_LEAD_CELLS * CELL, e))
        trapdoor(sc, p, "Trapdoor%d" % (j + 1), s, ACT_R_LANE, 0.0,
                 "Trapdoor %d, %.4f..%.4f deg, wall strip to wall foot; its activator on the lane at r %.1f, %.1f deg "
                 "before it, behind Wall%d. A runner shoves it; the rifle cannot see it." % (j + 1, s, e, ACT_R_LANE, ACT_BEFORE_DEG, j + 1))


def section_b(sc):
    p = "Elements/SectionB"
    sc.node('[node name="SectionB" type="Node3D" parent="Elements"]\neditor_description = "B, Ryan 2026-10-19: '
            'a wall slightly higher than a runner along the inner edge; the activators stand on its top, the same ones '
            'runners shove, too high to shove. The runner cannot see the sniper, only where he shoots. %.2f..%.2f deg."\n'
            % B_WALL)
    arc_wall(sc, p, "Wall", B_WALL[0], B_WALL[1],
             "r %.1f..%.1f, %.1f m: from the lane a 1.6 m eye cannot see the tower's 29.3 m eye over it." % (STRIP[0], STRIP[1], WALL_H))
    for j, s in enumerate(B_STARTS):
        trapdoor(sc, p, "Trapdoor%d" % (j + 1), s, ACT_R_TOP, WALL_H,
                 "Trapdoor %d, %.4f..%.4f deg; its activator on the wall top %.1f deg before it: the rifle's only."
                 % (j + 1, s, s + TRAP_CELLS * CELL, ACT_BEFORE_DEG))


def section_c(sc):
    p = "Elements/SectionC"
    sc.node('[node name="SectionC" type="Node3D" parent="Elements"]\neditor_description = "C, aesthetic only: '
            'evenly spaced buttresses, one on every pier of the outer wall, %.3f..%.3f deg, clear of the lane (r < 57.3)."\n'
            % (C_FIRST, C_FIRST + (C_COUNT - 1) * BAY))
    lo_m, lo_s = sc.box((BUTT_LOW[0], BUTT_LOW[1], BUTT_W))
    hi_m, hi_s = sc.box((BUTT_HIGH[0], BUTT_HIGH[1] - BUTT_LOW[1], BUTT_W * 0.8))
    back = WALL_FACE_R + BUTT_EMBED
    for k in range(C_COUNT):
        b = C_FIRST + k * BAY
        solid(sc, p, "Buttress%d" % (k + 1), b, at(b, back - BUTT_LOW[0] / 2.0, DECK_Y + BUTT_LOW[1] / 2.0), lo_m, lo_s,
              "Pier at %.3f deg." % b)
        solid(sc, p, "Buttress%dTop" % (k + 1), b,
              at(b, back - BUTT_HIGH[0] / 2.0, DECK_Y + 0.5 * (BUTT_LOW[1] + BUTT_HIGH[1])), hi_m, hi_s)


def forest():
    """(bearing, radius, height) of every column, every one reachable from the floor by jumps of D_STEP."""
    cols = []
    for row, r in enumerate(D_ROWS):
        step = math.degrees(D_PITCH / r)
        b = D_ARC[0] + (0.5 * step if row % 2 else 0.0)
        j = 0
        while b <= D_ARC[1]:
            jit = 0.25 * math.sin(j * 2.3 + row * 1.1)
            f = 0.5 + 0.5 * math.sin(j * 1.37 + row * 2.11) * math.cos(j * 0.53 - row * 0.7)
            cols.append([b + math.degrees(jit / r), r + 0.2 * math.cos(j * 1.9 + row), D_H[0] + (D_H[1] - D_H[0]) * f])
            b += step
            j += 1

    def xy(c):
        return (c[1] * math.cos(rad(c[0])), c[1] * math.sin(rad(c[0])))

    for _ in range(50):                    # lower any top nobody can reach until all can
        reach = [c[2] <= D_STEP for c in cols]
        changed = True
        while changed:
            changed = False
            for i, c in enumerate(cols):
                if reach[i]:
                    continue
                for k, o in enumerate(cols):
                    if reach[k] and math.dist(xy(c), xy(o)) <= D_REACH and c[2] - o[2] <= D_STEP:
                        reach[i] = changed = True
                        break
        if all(reach):
            break
        for i, c in enumerate(cols):
            if not reach[i]:
                best = max((o[2] for k, o in enumerate(cols) if reach[k] and math.dist(xy(c), xy(o)) <= D_REACH),
                           default=0.0)
                c[2] = min(c[2], best + D_STEP * 0.95)
    return cols


def section_d(sc):
    p = "Elements/SectionD"
    cols = forest()
    sc.node('[node name="SectionD" type="Node3D" parent="Elements"]\neditor_description = "D, aesthetic: a column forest, '
            '%d columns %.1f..%.1f m tall across the lane, %.1f..%.1f deg, every top jumpable, room to walk between."\n'
            % (len(cols), min(c[2] for c in cols), max(c[2] for c in cols), D_ARC[0], D_ARC[1]))
    for i, (b, r, h) in enumerate(cols):
        m, s = sc.cyl(D_RADIUS, h)
        solid(sc, p, "Column%02d" % (i + 1), b, at(b, r, DECK_Y + h / 2.0), m, s)
    return cols


def build():
    sc = Scene()
    sc.subs.append('[sub_resource type="StandardMaterial3D" id="Blk_mat"]\nalbedo_color = Color(%.2f, %.2f, %.2f, 1)\n' % GREY)
    section_a(sc)
    section_b(sc)
    section_c(sc)
    section_d(sc)
    return sc


def write():
    text = open(SCENE).read()
    text = re.sub(r'\[ext_resource [^\n]*id="Blk_trapdoor"\]\n', "", text)
    text = re.sub(r'\[sub_resource type="[^"]+" id="Blk_[^"]+"\]\n(?:[^\[\n][^\n]*\n)*\n', "", text)
    cut = re.search(r'\n\[node name="Section[A-D]" ', text)
    if cut:
        text = text[:cut.start() + 1]
    sc = build()
    ext = '[ext_resource type="PackedScene" path="res://maps/marble/props/marble_trapdoor.tscn" id="Blk_trapdoor"]\n'
    first_sub = text.index("\n[sub_resource ") + 1
    text = text[:first_sub].rstrip("\n") + "\n" + ext + "\n" + "\n".join(sc.subs) + "\n" + text[first_sub:]
    text = text.rstrip("\n") + "\n\n" + "\n".join(sc.nodes)
    open(SCENE, "w").write(text)
    print("wrote %d sub-resources, %d nodes" % (len(sc.subs), len(sc.nodes)))


def layout(path):
    """Top-down: the ring, the four sections, the markers and the trailer cameras' stretches."""
    from PIL import Image, ImageDraw
    W = 1400
    S = W / 2.0 / 66.0
    img = Image.new("RGB", (W, W), (24, 24, 28))
    g = ImageDraw.Draw(img)

    def P(b, r):                           # top-down, +X right, +Z down (Godot's top view)
        return (W / 2 + r * math.cos(rad(b)) * S, W / 2 + r * math.sin(rad(b)) * S)

    def band(b0, b1, r0, r1, fill):
        n = max(2, int((b1 - b0) / 0.5))
        pts = [P(b0 + (b1 - b0) * k / n, r0) for k in range(n + 1)] + [P(b1 - (b1 - b0) * k / n, r1) for k in range(n + 1)]
        g.polygon(pts, fill=fill)

    band(0, 360, INNER_R, 59.55, (70, 70, 72))
    g.ellipse([W / 2 - 7 * S, W / 2 - 7 * S, W / 2 + 7 * S, W / 2 + 7 * S], fill=(150, 140, 120))
    for b0, b1 in ((-6.25, 13.45), (58.6, 70.0), (120.1, 131.6), (182.4, 193.9), (247.1, 258.5), (300.6, 312.0)):
        band(b0, b1, 46.9, 47.7, (140, 130, 110))
    for b0, b1, label in ((131.7, 175.0, "5hr scope"), (188.0, 206.0, "10ar/10br"), (311.0, 345.0, "12sr run")):
        band(b0, b1, 61.0, 63.0, (90, 120, 200))
        x, y = P(0.5 * (b0 + b1), 64.5)
        g.text((x - 25, y - 6), label, fill=(150, 180, 255))
    for s in A_STARTS:
        band(s, s + TRAP_CELLS * CELL, STRIP[1], 59.4, (150, 40, 40))
        band(s - A_LEAD_CELLS * CELL, s + TRAP_CELLS * CELL, STRIP[0], STRIP[1], (235, 235, 235))
        x, y = P(s - ACT_BEFORE_DEG, ACT_R_LANE)
        g.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 210, 0))
    band(B_WALL[0], B_WALL[1], STRIP[0], STRIP[1], (235, 235, 235))
    for s in B_STARTS:
        band(s, s + TRAP_CELLS * CELL, STRIP[1], 59.4, (150, 40, 40))
        x, y = P(s - ACT_BEFORE_DEG, ACT_R_TOP)
        g.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 210, 0))
    for k in range(C_COUNT):
        b = C_FIRST + k * BAY
        band(b - 0.6, b + 0.6, WALL_FACE_R - BUTT_LOW[0], WALL_FACE_R, (235, 235, 235))
    for b, r, h in forest():
        x, y = P(b, r)
        v = int(120 + 135 * (h - D_H[0]) / (D_H[1] - D_H[0]))
        g.ellipse([x - D_RADIUS * S, y - D_RADIUS * S, x + D_RADIUS * S, y + D_RADIUS * S], fill=(v, v, v))
    for b, label in ((5.0, "start 5"), (345.0, "portal 345"), (353.0, "bars 353")):
        x, y = P(b, 52.0)
        g.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(60, 220, 90))
        x, y = P(b, 41.0)
        g.text((x - 20, y - 6), label, fill=(60, 220, 90))
    for b0, b1, name in ((A_STARTS[0] - CELL, A_STARTS[-1] + TRAP_CELLS * CELL, "A trapdoors + cover"),
                         (B_WALL[0], B_WALL[1], "B wall, activators on top"),
                         (C_FIRST, C_FIRST + (C_COUNT - 1) * BAY, "C buttresses"),
                         (D_ARC[0], D_ARC[1], "D column forest")):
        x, y = P(0.5 * (b0 + b1), 36.0)
        g.text((x - 50, y - 12), name, fill=(255, 255, 255))
        g.text((x - 50, y + 2), "%.1f..%.1f deg" % (b0, b1), fill=(200, 200, 200))
    for b in range(0, 360, 30):
        x, y = P(b, 68.0)
        g.text((x - 8, y - 6), "%d" % b, fill=(160, 160, 160))
    g.text((20, 20), "Marble, top-down (Godot top view: +X right, +Z down). Lap runs 5 -> 345 deg, increasing bearing.", fill=(255, 255, 255))
    g.text((20, 38), "white: section walls / buttresses / columns (lighter = taller)   red: trapdoor holes   yellow: activators", fill=(220, 220, 220))
    g.text((20, 56), "tan: the six existing lip walls   blue: trailer camera stretches   green: start, portal, bars", fill=(220, 220, 220))
    img.save(path)
    print("layout ->", path)


if __name__ == "__main__":
    if "--write" in sys.argv:
        write()
    if "--layout" in sys.argv:
        layout(sys.argv[sys.argv.index("--layout") + 1])
    if "--forest" in sys.argv:
        for c in forest():
            print("%.2f deg r %.2f h %.2f" % tuple(c))
