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
STRIP = (46.8, 49.4)            # DECK_RS[0]..[1]: kept as deck over every hole; the walls stand on its outer edge
TRAP_R = 0.5 * (48.05 + 60.0 * math.cos(math.pi / 64.0))   # marble_build.TRAPDOOR_R
TRAP_CELLS = 4                  # marble_build.TRAPDOOR_CELLS

WALL_H = 7.6                 # marble_wall_arc as authored: 11.4 deg, 7.6 m, over a 11.25 deg trapdoor                    # A and B: over a 1.8 m runner and his 1.1 m jump; hides the 29.3 m eye from the lane
ACT_BEFORE_DEG = 1.4            # the activator this far before its trapdoor's first pier
ACT_R_LANE = 50.4               # A: on the lane, 1 m outside the wall's face
ACT_R_TOP = 47.3                  # B: on the lip wall's top, its centre line

# v2 walls: the map's marble_wall_arc (r 47.3, 11.4 deg, 7.6 m) stood with its outer face on the hole's edge,
# squashed to WALL_H and to one trapdoor's 11.25 deg, so cover is only ever over trapdoor floor
ARC_R = 47.3                 # the lip walls' radius (marble_wall_arc), for LIP_MOVES
WALL_R = ARC_R
WALL_N = 3                   # 4 m walls end to end over a trapdoor's 9.7 m (they overlap a little; the element is not reshaped)
# A: three trapdoors, two bays of open, uncovered ground between; activators in the open, the rifle's too
A_STARTS = (61.875, 84.375, 106.875)
A_LEAD_CELLS = 0
# B: four trapdoors back to back, a wall over each, its activator on the wall top over its own door
B_STARTS = (258.75, 270.0, 281.25, 292.5)
B_WALL = (B_STARTS[0], B_STARTS[-1] + 4 * CELL)
B_ACT_AFTER_DEG = 1.0
# the lip walls moved out of A's and B's way: name -> new mid bearing
LIP_MOVES = {"ArcWall064": 55.9, "ArcWall306": 309.6}
# C: a flying buttress on every other pier: a pier on the inner strip, one arch up onto the outer wall
CEILING_H = 8.0                 # the lane's ceiling (the next tier's floor) over the deck
PIER_R, PIER_W, PIER_H = 47.6, 1.4, 6.6
ARCH_LAND_R, SPAN_LAND_H = 59.55, 7.3  # the span's top lands on the wall face this high
ARCH_T, ARCH_W = 0.7, 1.0
C_FIRST, C_COUNT = 196.875, 5
C_STEP = 2 * BAY
# D: rows of columns across the lane, staggered, every height different
D_ARC = (16.0, 49.0)
BRICK_TILE_M = 6.0              # the map's brick sheet repeats this often on the buttresses (world triplanar)
STONE_GLOW = 0.35               # the same sheet as a faint emission: the arch's underside sees no lamp
D_ROWS = (48.6, 52.6, 56.4)
D_PITCH = 5.2                   # metres along a row
D_RADIUS = 0.6                  # a 1.2 m top to land on
D_H = (8.0 / 3.0, 7.5)          # a third of deck-to-ceiling (8 m) up to the ceiling less 0.5 m: uniform scale of the 5 m column
COLUMN_H = 5.0
D_STEP = 0.9                    # a top this far over its neighbour's is a jump up (apex 1.11 m)
D_REACH = 4.3                   # centre to centre, a neighbour you can jump to



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
        """A BoxMesh and its BoxShape3D for a grey blockout block."""
        size = tuple(round(v, 3) for v in size)
        return (self.sub(("bm",) + size, ("BoxMesh", 'material = SubResource("Blk_stone")\nsize = Vector3(%.3f, %.3f, %.3f)' % size)),
                self.sub(("bs",) + size, ("BoxShape3D", "size = Vector3(%.3f, %.3f, %.3f)" % size)))

    def node(self, text):
        self.nodes.append(text)


def trapdoor(sc, parent, name, start, act_r, act_y, desc, act_deg=None):
    """marble_trapdoor on the pier at its centre, its activator at act_deg (default ACT_BEFORE_DEG before its start)."""
    centre = start + TRAP_CELLS / 2.0 * CELL
    at_deg = start - ACT_BEFORE_DEG if act_deg is None else act_deg
    d = rad(at_deg - centre)
    off = (act_r * math.cos(d) - TRAP_R, act_y, act_r * math.sin(d))
    sc.node('[node name="%s" parent="%s" instance=ExtResource("Blk_trapdoor")]\neditor_description = "%s"\n'
            'transform = %s\ntarget_offset = Vector3(%.4f, %.4f, %.4f)\ntarget_yaw_degrees = %.3f\n'
            % (name, parent, desc, xform(centre, at(centre, TRAP_R)), off[0], off[1], off[2], -math.degrees(d)))


def wall_over(sc, parent, name, start, desc):
    """The ring's own cover wall (marble_wall_arc.tscn, unscaled) on the lip over one trapdoor, placed as ArcWall064 is."""
    mid = start + TRAP_CELLS / 2.0 * CELL
    sc.node('[node name="%s" parent="%s" instance=ExtResource("Blk_wall")]\neditor_description = "%s"\ntransform = %s\n'
            % (name, parent, desc, xform(mid, at(mid, ARC_R))))


def section_a(sc):
    p = "Elements/SectionA"
    sc.node('[node name="SectionA" type="Node3D" parent="Elements"]\neditor_description = "A, Ryan 2026-10-19: '
            'trapdoors that span the full lane; where there is trapdoor floor there is cover (a wall on the inner edge), '
            'where there is not there is not; an activator at the start of each, out in the open where the rifle and a '
            'runner both reach it (Ryan 22:14). %.3f..%.3f deg."\n' % (A_STARTS[0], A_STARTS[-1] + TRAP_CELLS * CELL))
    for j, s in enumerate(A_STARTS):
        e = s + TRAP_CELLS * CELL
        wall_over(sc, p, "Wall%d" % (j + 1), s, "Cover over trapdoor %d only, %.4f..%.4f deg, %.1f m." % (j + 1, s, e, WALL_H))
        trapdoor(sc, p, "Trapdoor%d" % (j + 1), s, ACT_R_LANE, 0.0,
                 "Trapdoor %d, %.4f..%.4f deg; its activator on the open lane at r %.1f, %.1f deg before it: "
                 "a runner shoves it, the rifle can hit it." % (j + 1, s, e, ACT_R_LANE, ACT_BEFORE_DEG))


def section_b(sc):
    p = "Elements/SectionB"
    sc.node('[node name="SectionB" type="Node3D" parent="Elements"]\neditor_description = "B, Ryan 2026-10-19: '
            'a wall slightly higher than a runner along the inner edge, every metre of it over trapdoor floor; the '
            'activators stand on its top, too high to shove. The runner cannot see the sniper, only where he shoots. '
            '%.2f..%.2f deg."\n' % B_WALL)
    for j, s in enumerate(B_STARTS):
        wall_over(sc, p, "Wall%d" % (j + 1), s, "Over trapdoor %d, %.1f m: a 1.6 m eye cannot see the tower over it." % (j + 1, WALL_H))
        trapdoor(sc, p, "Trapdoor%d" % (j + 1), s, ACT_R_TOP, WALL_H,
                 "Trapdoor %d, %.4f..%.4f deg; its activator on the wall top %.1f deg into it: the rifle's only."
                 % (j + 1, s, s + TRAP_CELLS * CELL, B_ACT_AFTER_DEG), act_deg=s + B_ACT_AFTER_DEG)


def section_c(sc):
    """A flying buttress per C_STEP: a square pier on the lane's inner edge, one arch from its top to high on the outer wall."""
    p = "Elements/SectionC"
    sc.node('[node name="SectionC" type="Node3D" parent="Elements"]\neditor_description = "C, aesthetic only: '
            'evenly spaced flying buttresses (grey blocks; there is no buttress element): a pier on the inner edge, one '
            'arch leaning from its top over the lane onto the outer wall; runners pass under. %.3f..%.3f deg."\n'
            % (C_FIRST, C_FIRST + (C_COUNT - 1) * C_STEP))
    pm, ps = sc.box((PIER_W, PIER_H, PIER_W))
    for k in range(C_COUNT):
        b = C_FIRST + k * C_STEP
        name = "Buttress%d" % (k + 1)
        sc.node('[node name="%s" type="StaticBody3D" parent="%s"]\ntransform = %s\n' % (name, p, xform(b, at(b, PIER_R))))
        sc.node('[node name="Pier" type="MeshInstance3D" parent="%s/%s"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %.3f, 0)\nmesh = SubResource("%s")\n'
                % (p, name, PIER_H / 2.0, pm))
        sc.node('[node name="PierShape" type="CollisionShape3D" parent="%s/%s"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %.3f, 0)\nshape = SubResource("%s")\n'
                % (p, name, PIER_H / 2.0, ps))
        # the flying span: one straight block from the pier's top to the wall face, under the lane's 8 m ceiling
        x0, y0, x1, y1 = 0.0, PIER_H, ARCH_LAND_R - PIER_R, SPAN_LAND_H
        L = math.hypot(x1 - x0, y1 - y0)
        ang = math.atan2(y1 - y0, x1 - x0)
        mm, _ = sc.box((L, ARCH_T, ARCH_W))
        ca, sa = math.cos(ang), math.sin(ang)
        cx, cy = 0.5 * (x0 + x1), 0.5 * (y0 + y1) - ARCH_T / 2.0      # its top edge runs pier top to SPAN_LAND_H
        sc.node('[node name="Span" type="MeshInstance3D" parent="%s/%s"]\n'
                'transform = Transform3D(%.6f, %.6f, 0, %.6f, %.6f, 0, 0, 0, 1, %.4f, %.4f, 0)\nmesh = SubResource("%s")\n'
                % (p, name, ca, -sa, sa, ca, cx, cy, mm))


def forest():
    """(bearing, radius, height) of every column, every one reachable from the floor by jumps of D_STEP."""
    cols = []
    for row, r in enumerate(D_ROWS):
        step = math.degrees(D_PITCH / r)
        b = D_ARC[0] + (0.5 * step if row % 2 else 0.0)
        j = 0
        while b <= D_ARC[1]:
            jit = 0.25 * math.sin(j * 2.3 + row * 1.1)
            f = (0.5 + 0.5 * math.sin(j * 2.39 + row * 2.11)) ** 1.3
            cols.append([b + math.degrees(jit / r), r + 0.2 * math.cos(j * 1.9 + row), D_H[0] + (D_H[1] - D_H[0]) * f])
            b += step
            j += 1

    def xy(c):
        return (c[1] * math.cos(rad(c[0])), c[1] * math.sin(rad(c[0])))

    for _ in range(0):                     # v5: no reach rule; the heights only vary (Ryan 23:07)
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
    """The trailer's column (marble_column.glb as trailer_marble_column.spawn_columns places it, turned -bearing),
    scaled uniformly so the forest's tops vary, every one standing on the deck."""
    p = "Elements/SectionD"
    cols = forest()
    sc.node('[node name="SectionD" type="Node3D" parent="Elements"]\neditor_description = "D, aesthetic: a column forest, '
            '%d of the trailer\'s marble_column as it places them (unscaled, rotation (0, -bearing, 0)), scaled uniformly to '
            '%.1f..%.1f m, %.1f..%.1f deg; room to walk between, the lowest jumpable."\n'
            % (len(cols), min(c[2] for c in cols), max(c[2] for c in cols), D_ARC[0], D_ARC[1]))
    for i, (b, r, h) in enumerate(cols):
        k = h / COLUMN_H
        c, sn = math.cos(rad(b)), math.sin(rad(b))
        o = at(b, r)
        sc.node('[node name="Column%02d" parent="%s" instance=ExtResource("Blk_column")]\n'
                'transform = Transform3D(%.6f, 0, %.6f, 0, %.6f, 0, %.6f, 0, %.6f, %.4f, %.4f, %.4f)\n'
                % (i + 1, p, c * k, -sn * k, k, sn * k, c * k, o[0], o[1], o[2]))
    return cols


STONE = ('[sub_resource type="StandardMaterial3D" id="Blk_stone"]\nalbedo_texture = ExtResource("Blk_brick")\n'
         'emission_enabled = true\nemission_texture = ExtResource("Blk_brick")\nemission_energy_multiplier = %.2f\n'
         'uv1_scale = Vector3(%.3f, %.3f, %.3f)\nuv1_triplanar = true\nuv1_world_triplanar = true\ntexture_filter = 0\n')


def build():
    sc = Scene()
    k = 1.0 / BRICK_TILE_M
    sc.subs.append(STONE % (STONE_GLOW, k, k, k))
    section_a(sc)
    section_b(sc)
    section_c(sc)
    section_d(sc)
    return sc


def write():
    text = open(SCENE).read()
    text = re.sub(r'\[ext_resource [^\n]*id="Blk_[a-z]+"\]\n', "", text)
    text = re.sub(r'\[sub_resource type="[^"]+" id="Blk_[^"]+"\]\n(?:[^\[\n][^\n]*\n)*\n', "", text)
    cut = re.search(r'\n\[node name="Section[A-D]" ', text)
    if cut:
        text = text[:cut.start() + 1]
    sc = build()
    for name, mid in LIP_MOVES.items():
        c, sn = math.cos(rad(mid)), math.sin(rad(mid))
        text = re.sub(r'(\[node name="%s"[^\n]*\]\neditor_description = "[^"]*"\ntransform = )Transform3D\([^)]*\)' % name,
                      lambda m: m.group(1) + "Transform3D(%.6f, 0, %.6f, 0, 1, 0, %.6f, 0, %.6f, %.4f, 23.0, %.4f)"
                      % (c, -sn, sn, c, ARC_R * c, ARC_R * sn), text)
    ext = ('[ext_resource type="PackedScene" path="res://maps/marble/props/marble_trapdoor.tscn" id="Blk_trapdoor"]\n'
           '[ext_resource type="PackedScene" path="res://maps/marble/props/marble_wall_arc.tscn" id="Blk_wall"]\n'
           '[ext_resource type="PackedScene" path="res://maps/marble/models/marble_column.glb" id="Blk_column"]\n'
           '[ext_resource type="Texture2D" path="res://maps/marble/textures/marble_brick_albedo.png" id="Blk_brick"]\n')
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
    for b0, b1 in ((-6.25, 13.45), (50.2, 61.6), (120.1, 131.6), (182.4, 193.9), (247.1, 258.5), (303.9, 315.3)):
        band(b0, b1, 46.9, 47.7, (140, 130, 110))
    for b0, b1, label in ((131.7, 175.0, "5hr scope"), (188.0, 206.0, "10ar/10br"), (311.0, 345.0, "12sr run")):
        band(b0, b1, 61.0, 63.0, (90, 120, 200))
        x, y = P(0.5 * (b0 + b1), 64.5)
        g.text((x - 25, y - 6), label, fill=(150, 180, 255))
    for s in A_STARTS:
        band(s, s + TRAP_CELLS * CELL, STRIP[1], 59.4, (150, 40, 40))
        band(s, s + TRAP_CELLS * CELL, WALL_R - 0.475, WALL_R + 0.475, (235, 235, 235))
        x, y = P(s - ACT_BEFORE_DEG, ACT_R_LANE)
        g.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 210, 0))
    band(B_WALL[0], B_WALL[1], WALL_R - 0.475, WALL_R + 0.475, (235, 235, 235))
    for s in B_STARTS:
        band(s, s + TRAP_CELLS * CELL, STRIP[1], 59.4, (150, 40, 40))
        x, y = P(s + B_ACT_AFTER_DEG, ACT_R_TOP)
        g.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 210, 0))
    for k in range(C_COUNT):
        b = C_FIRST + k * C_STEP
        band(b - 0.8, b + 0.8, PIER_R - PIER_W / 2.0, PIER_R + PIER_W / 2.0, (235, 235, 235))
        band(b - 0.5, b + 0.5, PIER_R + PIER_W / 2.0, ARCH_LAND_R, (150, 150, 150))
    for b, r, h in forest():
        x, y = P(b, r)
        v = int(120 + 135 * (h - D_H[0]) / (D_H[1] - D_H[0]))
        g.ellipse([x - D_RADIUS * S, y - D_RADIUS * S, x + D_RADIUS * S, y + D_RADIUS * S], fill=(v, v, v))
    for b, label in ((5.0, "start 5"), (345.0, "portal 345"), (353.0, "bars 353")):
        x, y = P(b, 52.0)
        g.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(60, 220, 90))
        x, y = P(b, 41.0)
        g.text((x - 20, y - 6), label, fill=(60, 220, 90))
    for b0, b1, name in ((A_STARTS[0], A_STARTS[-1] + TRAP_CELLS * CELL, "A trapdoors + cover"),
                         (B_WALL[0], B_WALL[1], "B wall, activators on top"),
                         (C_FIRST, C_FIRST + (C_COUNT - 1) * C_STEP, "C flying buttresses"),
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
