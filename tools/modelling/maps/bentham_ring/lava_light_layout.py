"""Hell's lava lights and heat haze, laid out from the lava itself; prints the bentham_ring.tscn blocks.

  godot --headless --path . --script res://tools/modelling/maps/bentham_ring/lava_dump.gd -- --out=lava.json
  python3 tools/modelling/maps/bentham_ring/lava_light_layout.py lava.json
"""
import json
import math
import sys

RIVER_COLOR = "Color(1, 0.35, 0.06, 1)"
SEA_COLOR = "Color(1, 0.32, 0.08, 1)"

# The sea: an even ring of unshadowed glows over the lava, clear of the tower and the pit wall.
SEA_LIGHTS, SEA_LIGHT_R, SEA_LIGHT_Y, SEA_ENERGY, SEA_RANGE = 10, 34.0, -8.5, 4.4, 60.0
# Rivers, shelf, falls: short lights hung just over the lava along its length.
RIVER_SPACING, RIVER_LIFT, RIVER_ENERGY, RIVER_RANGE = 7.0, 1.5, 2.5, 8.0
SHELF_SPACING = 12.0
FALL_HEIGHTS, FALL_ENERGY, FALL_RANGE = (3.0, 15.0), 2.5, 9.0
# Haze: the crack's panel scaled to the body it stands on.
SEA_HAZE_RINGS, SEA_HAZE_SPACING, SEA_HAZE_FOOT = (18.0, 27.0, 36.0, 44.5), 12.0, -11.9
RIVER_HAZE_SCALE, RIVER_HAZE_SPACING = 1.5, 5.0
FALL_HAZE_SCALE, FALL_HAZE_FEET = 2.5, (-11.0, -3.5, 4.0, 11.5)


def polar(p):
    return math.degrees(math.atan2(p[2], p[0])) % 360.0, math.hypot(p[0], p[2])


def at(r, b, y):
    a = math.radians(b)
    return (r * math.cos(a), y, r * math.sin(a))


def band(points, y_lo, y_hi):
    """Per whole-degree bearing: (r_min, r_max, y_mean) of the lava between y_lo and y_hi."""
    bins = {}
    for p in points:
        if y_lo <= p[1] <= y_hi:
            b, r = polar(p)
            bins.setdefault(int(b), []).append((r, p[1]))
    return {b: (min(q[0] for q in v), max(q[0] for q in v), sum(q[1] for q in v) / len(v)) for b, v in bins.items()}


def along(bins, frac, spacing, inset):
    """Points down the lava's length at fraction frac of its width, every spacing metres."""
    keys = sorted(bins)
    lo, hi = keys[0], keys[-1] + 1
    r_mid = sum((bins[k][0] + bins[k][1]) * 0.5 for k in keys) / len(keys)
    length = math.radians(hi - lo) * r_mid - 2 * inset
    n = max(1, round(length / spacing) + 1)
    out = []
    for i in range(n):
        b = lo + math.degrees((inset + (length * i / (n - 1) if n > 1 else length * 0.5)) / r_mid)
        r0, r1, y = bins[min(keys, key=lambda k: abs(k + 0.5 - b))]
        out.append((r0 + frac * (r1 - r0), b, y))
    return out


def light(name, pos, color, energy, rng):
    return (f'[node name="{name}" type="OmniLight3D" parent="Ring/LavaGlow"]\n'
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})\n"
            f"light_color = {color}\nlight_energy = {energy}\nlight_specular = 0.0\n"
            f"omni_range = {rng}\nomni_attenuation = 1.0\n")


def haze(name, panels, scale, crossed, note):
    flat = ", ".join(f"{x:.2f}, {y:.2f}, {z:.2f}, {w:.3f}" for x, y, z, w in panels)
    return (f'[node name="{name}" type="MeshInstance3D" parent="Ring/LavaHaze"]\n'
            f'editor_description = "{note}"\nscript = ExtResource("31_lava_haze_field")\n'
            f"panels = PackedVector4Array({flat})\npanel_scale = {scale}\n"
            f"crossed = {'true' if crossed else 'false'}\n")


def yaw_tangent(b):
    return -math.radians(b) - math.pi * 0.5


def main(path):
    lava = json.load(open(path))
    lights, sea_panels, river_panels, fall_panels = [], [], [], []

    for k in range(SEA_LIGHTS):
        lights.append(light(f"Sea{k:02d}", at(SEA_LIGHT_R, 18.0 + 360.0 * k / SEA_LIGHTS, SEA_LIGHT_Y),
                            SEA_COLOR, SEA_ENERGY, SEA_RANGE))
    for r in SEA_HAZE_RINGS:
        n = max(6, round(2 * math.pi * r / SEA_HAZE_SPACING))
        for i in range(n):
            b = 360.0 * (i + 0.5 * (r % 2)) / n
            x, _, z = at(r, b, 0.0)
            sea_panels.append((x, SEA_HAZE_FOOT, z, math.radians(b * 3.0)))

    for chunk in ("s2", "s4", "s5"):
        pts = lava[f"{chunk}/LavaRiver"]
        deck = band(pts, 21.5, 23.6)
        tag = chunk.upper()
        for i, (r, b, y) in enumerate(along(deck, 0.5, RIVER_SPACING, 3.0)):
            lights.append(light(f"{tag}_River{i:02d}", at(r, b, y + RIVER_LIFT), RIVER_COLOR, RIVER_ENERGY, RIVER_RANGE))
        rows = (0.5,) if chunk == "s2" else (0.27, 0.73)
        for j, frac in enumerate(rows):
            for r, b, y in along(deck, frac, RIVER_HAZE_SPACING, 2.0 + 2.5 * j):
                x, _, z = at(r, b, 0.0)
                river_panels.append((x, y - 0.9, z, math.radians(b * 2.0 + 45.0)))
        shelf = band(pts, 27.5, 29.5)
        if shelf:
            for i, (r, b, y) in enumerate(along(shelf, 0.5, SHELF_SPACING, 2.0)):
                lights.append(light(f"{tag}_Shelf{i:02d}", at(r, b, y + RIVER_LIFT), RIVER_COLOR, RIVER_ENERGY, RIVER_RANGE))
            for r, b, y in along(shelf, 0.5, RIVER_HAZE_SPACING * 0.8, 2.0):
                x, _, z = at(r, b, 0.0)
                river_panels.append((x, y - 0.9, z, math.radians(b * 2.0 + 45.0)))
        fall = band(pts, -9.0, 21.0)
        if fall:
            keys = sorted(fall)
            for side, k in (("A", keys[0]), ("B", keys[-1])):
                for h, y in enumerate(FALL_HEIGHTS):
                    lights.append(light(f"{tag}_FallBank{side}{h}", at(fall[k][0] - 2.0, k + 0.5, y),
                                        RIVER_COLOR, FALL_ENERGY, FALL_RANGE))
            for _, b, _ in along(fall, 0.0, LAVA_HAZE_WIDTH * FALL_HAZE_SCALE, LAVA_HAZE_WIDTH * FALL_HAZE_SCALE * 0.5 + 0.5):
                r_face = fall[min(keys, key=lambda k: abs(k + 0.5 - b))][0]
                for foot in FALL_HAZE_FEET:
                    x, _, z = at(r_face - 1.2, b, 0.0)
                    fall_panels.append((x, foot, z, yaw_tangent(b)))

    print("\n".join(lights))
    print(haze("Sea", sea_panels, 2.5, True, "Heat off the lava sea: the crack's haze at 2.5x, in rings round the tower."))
    print(haze("Rivers", river_panels, RIVER_HAZE_SCALE, True, "Heat off the S2, S4 and S5 rivers and the S5 shelf, down their length."))
    print(haze("Falls", fall_panels, FALL_HAZE_SCALE, False, "Heat rising up the S4 and S5 falls: one face-on panel each, stacked."))
    print(f"; lights {len(lights)}  haze panels sea {len(sea_panels)} rivers {len(river_panels)} falls {len(fall_panels)}", file=sys.stderr)


LAVA_HAZE_WIDTH = 2.4

if __name__ == "__main__":
    main(sys.argv[1])
