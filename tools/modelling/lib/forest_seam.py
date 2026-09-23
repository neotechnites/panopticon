"""
PANOPTICON -- forest_seam: the one ring Map 3's two models share.

Ryan: "for the forest level where the tree is the roof, its pretty good, but
make the roof higher, so make it like a dome that collapses in the middle where
the tree is, and so theres still like a ring of cells above where the player
runs."

So the roof is a DOME THAT SAGS INTO THE MIDDLE. The level's own leaf roof
covers the lane at CEIL_Z; on that roof's inner rim (r 46.7) stands the cell
drum again -- three tiers of barred cells over the ravine -- and the drum's
head at SEAM_R / SEAM_Z is where the tower's crown takes over. From there the
great tree's leaf sheet sweeps INWARD AND DOWN to the crown's rim, so the
highest leaf is at the ring and the lowest is over the tree: a dome collapsed
where the trunk holds it.

The two stay two models, each one contiguous mesh; the mate is THIS ring,
computed here once and used by both builds as their own vertices, so the 240
points are identical floats in both meshes: no seam, no gap, no step.

    seam_ring()   240 world-space points (Blender xyz, z up = Godot y); point i
                  sits at game bearing i * 1.5 deg, forest_build's column i
    seam_z(th)    the ring's height at Blender angle th: SEAM_Z plus three
                  low harmonics so the seam is as lumpy as the leaf either
                  side of it and never reads as a level circle
    sheet_z(rad)  the tower sheet's nominal underside at radius rad (before
                  its lumps): the dome's profile over the ravine, crown rim to
                  seam, for the map's ray tracing
    report(a, b)  the proof: (count, worst distance) between two rings

Heights (world y, the lane is 23.0). Before this pass the whole roof was flat
at 32.6 with the tree's sheet dropping to 32.8 at r 46.7 and no cells above the
lane. Now: the lane roof is CEIL_Z 38.0 (15 m over the grass), the cell drum
carries three tiers from 38.0 to the seam at SEAM_Z 50.0 (27 m over the lane),
and the dome sags from there to the crown rim at 34.1 -- a 15.9 m collapse into
the tree. The guard's room, eye (28.7) and windows are untouched, and every
roof height is above the guard's downward sightline to the lane and above the
tallest lane fixture (the bars, 31.5).
"""

import math
import struct

TOWER_ORIGIN_Y = 25.35      # forest_tree_build.ORIGIN_Y: the Tower node the tree hangs under.
                            # It lives HERE because it is the second thing the two models
                            # share -- the map is at identity and the tree is not, so a seam
                            # point only lands on the same float in both if this number is
                            # the same number on both sides of the join. See settle().
SEAM_R = 47.6               # the cell drum's head: the level stops here, the tree's crown carries on
SEAM_N = 240                # forest_build.NC: one seam vertex per map column
SEAM_Z = 50.0               # the seam's mean height, world y: the dome's high ring
SEAM_WAVES = ((3, 0.35, 0.4), (7, 0.25, 1.9), (11, 0.18, 3.1))   # (harmonic, amplitude, phase)
CEIL_Z = 38.0               # the level's lane roof at the outer wall (r 60), world y
DRUM_R = 46.7               # the cell drum's foot: the lane roof's inner rim (forest_build.UPPER)
CROWN_RIM = (11.0, 34.1)    # (r, y) where the tower's leaf disc rim is and the sheet begins
# (r, y) the tower sheet's rings, rim to seam: z = 34.1 + 15.9 * u ** 0.62 with
# u the fraction of the way out, so the dome is broad and high for most of its
# span and plunges only where the tree holds it down.
SHEET = [(11.0, 34.10), (14.0, 37.45), (19.0, 40.30), (24.5, 42.65), (30.0, 44.70),
         (35.5, 46.50), (41.0, 48.15), (44.5, 49.15), (SEAM_R, SEAM_Z)]
SETTLE_ULPS = 64            # how far settle() may walk to find a shared float (~0.25 mm at y 50)
SHEET_LUMP = 0.6            # the tower sheet billows this much (rings between the rim and the seam only)
TWO_PI = 2.0 * math.pi


def _f32(x):
    """x rounded to the float32 a mesh vertex is actually stored as."""
    return struct.unpack("<f", struct.pack("<f", x))[0]


def _ulp_walk(x, steps):
    """The float32 ``steps`` ulps from float32 x (steps may be negative)."""
    bits = struct.unpack("<i", struct.pack("<f", x))[0]
    bits = (bits + steps) if bits >= 0 else (bits - steps)
    return struct.unpack("<f", struct.pack("<i", bits))[0]


def settle(z):
    """The nearest height to z that BOTH models can hold as the same float.

    The map is at identity, so it stores the seam's world height as
    float32(z). The tree is authored in world coordinates and exported
    shifted by -TOWER_ORIGIN_Y, so it stores float32(z - origin) and the
    engine puts it back at float32(float32(z - origin) + float32(origin)).
    Those two are one ulp apart for most z -- a 4 micron step all the way
    round a 240-vertex ring, which is the difference between "the same
    vertex" and "two vertices that are very close".

    So the ring does not sit on the arithmetic's nominal height: it sits on
    the nearest height that survives the round trip unchanged. The walk is
    over float32 ulps, so it moves a seam point by at most a couple of
    microns and the answer is the same on arm64 and on x86-64 (IEEE 754
    round-to-nearest, no library call). Raises if no such height exists
    within SETTLE_ULPS -- silently returning the nominal value would put the
    gap back and leave the proof saying zero.
    """
    o32 = _f32(TOWER_ORIGIN_Y)
    for step in range(SETTLE_ULPS + 1):
        for cand in ((_f32(z),) if step == 0 else
                     (_ulp_walk(z, step), _ulp_walk(z, -step))):
            if _f32(_f32(_f32(cand - TOWER_ORIGIN_Y) + o32)) == cand:
                return cand
    raise ValueError("no float32 seam height near %r survives the tower shift" % (z,))


def seam_z(th):
    """The seam's height at Blender xy angle th (radians), settled onto a float
    both models can hold (see settle): the ring is the join, not a target."""
    z = SEAM_Z
    for (k, amp, ph) in SEAM_WAVES:
        z += amp * math.sin(k * th + ph)
    return settle(z)


def seam_ring():
    """The 240 shared points, world coordinates. Point i is at game bearing
    i * 360 / SEAM_N (forest_tree_build.pol's convention: Blender angle -bearing)."""
    pts = []
    for i in range(SEAM_N):
        th = math.radians(-(i * 360.0 / SEAM_N))
        pts.append((SEAM_R * math.cos(th), SEAM_R * math.sin(th), seam_z(th)))
    return pts


def sheet_z(rad):
    """The tower sheet's nominal underside at radius rad, crown rim to seam."""
    if rad <= SHEET[0][0]:
        return SHEET[0][1]
    for k in range(len(SHEET) - 1):
        (r0, z0), (r1, z1) = SHEET[k], SHEET[k + 1]
        if r0 <= rad <= r1:
            return z0 + (z1 - z0) * (rad - r0) / (r1 - r0)
    return SEAM_Z


def cross_glb_error():
    """The worst distance between where the MAP puts a seam vertex and where
    the engine puts the TOWER's own copy of it: the number settle() exists to
    drive to zero. Both sides are taken through the float32 a vertex is really
    stored as, and the tower's through the shift and back."""
    o32 = _f32(TOWER_ORIGIN_Y)
    worst = 0.0
    for (x, y, z) in seam_ring():
        mapped = (_f32(x), _f32(y), _f32(z))
        tower = (_f32(x), _f32(y), _f32(_f32(_f32(z - TOWER_ORIGIN_Y) + o32)))
        worst = max(worst, math.dist(mapped, tower))
    return worst


def report(a, b):
    """(count, worst distance) between two rings given as point lists, matched
    by nearest point: what 'matched vertex for vertex' means in numbers."""
    worst = 0.0
    for p in a:
        d = min(math.sqrt(sum((p[k] - q[k]) ** 2 for k in range(3))) for q in b)
        worst = max(worst, d)
    return (min(len(a), len(b)), worst)


if __name__ == "__main__":
    ring = seam_ring()
    zs = [p[2] for p in ring]
    print("SEAM r=%.1f n=%d z=%.2f..%.2f mean=%.2f cross_glb_error=%.1e"
          % (SEAM_R, len(ring), min(zs), max(zs), sum(zs) / len(zs), cross_glb_error()))
