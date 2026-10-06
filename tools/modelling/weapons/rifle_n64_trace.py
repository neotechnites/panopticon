"""
The rifle's side picture and the profile traced from it, shared by the model build and the texture painter.

Source: https://commons.wikimedia.org/wiki/File:Rifle_Springfield_M1903A4_with_M84_sight.jpg
Licence: public domain (PD-USGov-Military-Army, a U.S. Army photograph), 640 x 148.

Every trace point is a pixel of that photo (x right toward the muzzle, y down). The picture is the photo
sheared level and reduced; a vertex's UV is its trace point in the picture, its place in metres comes
from PHOTO_TO_Y, so the picture stretches with the model and a repaint needs no rebuild.
"""

SOURCE_URL = "https://upload.wikimedia.org/wikipedia/commons/3/3c/Rifle_Springfield_M1903A4_with_M84_sight.jpg"

# =============================================================================
# TUNABLES
# =============================================================================
PICTURE = (256, 64)         # the slice rifle_side_albedo, texels
REDUCE = 0.4165             # picture texels per photo pixel
PHOTO_ORIGIN = (15.0, 9.0)  # the photo pixel at the picture's top left, once sheared
BORE = (250.0, 53.0, 0.0114)    # the photo's bore line: y = 53 + 0.0114 (x - 250)
METRES_PER_PIXEL = 0.00197      # up and down; along the gun PHOTO_TO_Y decides

# ---- held by the scene: weapons/rifle.tscn's Muzzle, GripHand, ForeHand and rifle_ads.gd's aim pose
BUTT_Y = -0.2655            # rear face of the butt
MUZZLE_Y = 0.9265           # Godot local (0, 0, -MUZZLE_Y): ViewModel/Muzzle
WRIST_Y = -0.075            # GripHand lies on the wrist here
SCOPE_Z = 0.045             # the aim pose's eye height over the bore
SCOPE_REAR = -0.110         # the eyepiece
SCOPE_FRONT = 0.218
SCOPE_DIAMETER_SCALE = 1.35
OCULAR_R = 0.0175 * SCOPE_DIAMETER_SCALE
TUBE_R = 0.0127 * SCOPE_DIAMETER_SCALE

BUTT_SQUEEZE = 0.8          # the butt's length against the action's; what will not fit is sawn off the photo's butt
WRIST_X, BRIDGE_X, HANDGUARD_X, MUZZLE_X = 176.0, 205.0, 298.0, 622.0   # photo x of the seams between stretches
BRIDGE_Y = 0.035            # the receiver bridge: far enough forward that the bolt handle clears the trigger hand
HANDGUARD_Y = SCOPE_FRONT   # the wood over the barrel starts where the scope ends
BUTT_X = WRIST_X - (WRIST_Y - BUTT_Y) / (METRES_PER_PIXEL * BUTT_SQUEEZE)
PHOTO_TO_Y = ((BUTT_X, BUTT_Y), (WRIST_X, WRIST_Y), (BRIDGE_X, BRIDGE_Y), (HANDGUARD_X, HANDGUARD_Y), (MUZZLE_X, MUZZLE_Y))

BUTT_LIFT = 0.012           # the butt and wrist raised so the palm lands mid-wrist; gone before the action
LIFT_X = (176.0, 188.0)
FOREND_DEEPEN = 0.0065      # the fore-end's belly lowered to meet the support palm; gone at magazine and tip
DEEPEN_X = (260.0, 330.0, 440.0, 556.0)

# ---- the stock, butt to tip: photo x, top y, bottom y, half width, crown drop, keel rise (metres)
STOCK = (
    (BUTT_X, 67.8, 127.8, 0.019, 0.008, 0.010),
    (100.0, 67.0, 115.8, 0.0225, 0.009, 0.011),
    (134.0, 67.0, 106.0, 0.022, 0.009, 0.011),
    (152.0, 70.0, 111.0, 0.022, 0.008, 0.011),
    (164.0, 68.0, 101.0, 0.021, 0.007, 0.010),
    (176.0, 63.0, 89.0, 0.021, 0.007, 0.010),
    (190.0, 58.5, 85.0, 0.022, 0.006, 0.010),
    (205.0, 55.0, 84.0, 0.025, 0.003, 0.010),
    (232.0, 54.0, 82.5, 0.027, 0.003, 0.008),
    (270.0, 54.0, 80.5, 0.027, 0.003, 0.008),
    (295.0, 54.0, 78.0, 0.026, 0.003, 0.010),
    (300.0, 42.5, 78.0, 0.026, 0.012, 0.011),
    (330.0, 42.0, 77.0, 0.025, 0.012, 0.012),
    (427.0, 47.0, 75.0, 0.0215, 0.011, 0.011),
    (500.0, 49.0, 71.0, 0.019, 0.010, 0.010),
    (556.0, 49.0, 70.0, 0.017, 0.009, 0.009),
)
# ---- the action over the wood, cocking piece to receiver ring: photo x, top y, half width
ACTION = ((186.0, 47.5, 0.007), (191.0, 44.5, 0.012), (205.0, 45.5, 0.014), (298.0, 45.0, 0.016))
ACTION_SINK = 0.002         # its foot below the wood line
# ---- nose cap and bare barrel
NOSE = ((556.0, 582.0), 51.0, 70.5, 0.0185, 0.008)      # photo x span, top y, bottom y, half width, chamfer
BARREL = ((582.0, 0.0095), (612.0, 0.0082), (612.6, 0.0098), (622.0, 0.0098))   # photo x, radius
BARREL_PX = (53.0, 61.0)    # its top and bottom in the photo at the muzzle
# ---- the scope: photo x, top y, bottom y, model y, radius. Its place is the scene's, its pixels the photo's.
SCOPE = (
    (197.0, 17.0, 35.0, SCOPE_REAR, OCULAR_R),
    (213.0, 17.0, 40.0, -0.060, OCULAR_R * 0.965),
    (219.0, 22.5, 36.0, -0.050, TUBE_R),
    (300.0, 23.0, 35.0, 0.106, TUBE_R),
    (304.0, 22.0, 37.0, 0.110, TUBE_R * 1.2),
    (317.0, 22.0, 37.0, 0.134, TUBE_R * 1.2),
    (321.0, 22.5, 36.5, 0.140, TUBE_R * 1.02),
    (333.0, 21.0, 38.0, 0.160, OCULAR_R),
    (359.0, 21.0, 38.0, SCOPE_FRONT, OCULAR_R),
)
TURRET = ((304.0, 317.0), (12.5, 22.5), 0.122, 0.0105, 0.013)   # photo x span, photo y span, model y, radius, height
# ---- the two mounts under the tube: photo x span, photo y span (the ring's foot), model y span
MOUNTS = (((232.0, 241.0), (36.0, 47.0), (-0.024, -0.006)), ((285.0, 296.0), (36.0, 44.0), (0.078, 0.096)))
MOUNT_HALF_W = 0.009
# ---- trigger guard and trigger, photo (x, y) paths
GUARD = ((190.0, 85.0), (192.0, 92.0), (196.0, 97.0), (212.0, 97.5), (217.0, 92.0), (218.0, 84.0))
TRIGGER = ((201.0, 85.0), (200.0, 91.0), (202.0, 95.0))
BOLT_X = (207.0, 52.5, 69.0)    # the bolt handle: photo x, root y, knob y
# ---- cells for faces the side picture cannot reach (ends, rims, strips): picture x, y, w, h
CELLS = {
    "butt": (2, 1, 12, 20),
    "steel": (18, 1, 24, 8),
    "bore": (46, 1, 8, 8),
    "wood": (18, 12, 12, 8),
    "knob": (34, 12, 8, 8),
}


# =============================================================================
# THE MAPPINGS
# =============================================================================

def _ramp(x, pairs):
    """Piecewise linear through (x, value) pairs, held flat past the ends."""
    if x <= pairs[0][0]:
        return pairs[0][1]
    for (a, va), (b, vb) in zip(pairs, pairs[1:]):
        if x <= b:
            return va + (vb - va) * (x - a) / (b - a)
    return pairs[-1][1]


def bore(x):
    return BORE[1] + BORE[2] * (x - BORE[0])


def model_y(x):
    """Metres along the gun of photo column x."""
    return _ramp(x, PHOTO_TO_Y)


def lift(x):
    return BUTT_LIFT * _ramp(x, ((LIFT_X[0], 1.0), (LIFT_X[1], 0.0)))


def deepen(x):
    a, b, c, d = DEEPEN_X
    return -FOREND_DEEPEN * _ramp(x, ((a, 0.0), (b, 1.0), (c, 1.0), (d, 0.0)))


def model_z(x, y, keel=False):
    """Metres over the bore of photo pixel (x, y) on the stock; keel: the bottom line, which the fore-end deepens."""
    return (bore(x) - y) * METRES_PER_PIXEL + lift(x) + (deepen(x) if keel else 0.0)


def picture_px(x, y):
    """Picture texel (column, row) of photo pixel (x, y)."""
    return ((x - PHOTO_ORIGIN[0]) * REDUCE + 1.0, (y - BORE[2] * (x - BORE[0]) - PHOTO_ORIGIN[1]) * REDUCE)


def uv(x, y):
    """Blender UV of photo pixel (x, y)."""
    c, r = picture_px(x, y)
    return (c / PICTURE[0], 1.0 - r / PICTURE[1])


def cell_uv(name, s, t):
    """Blender UV of the point (s, t), each 0..1, of a cell, half a texel inside its edge."""
    x, y, w, h = CELLS[name]
    return ((x + 0.5 + s * (w - 1.0)) / PICTURE[0], 1.0 - (y + 0.5 + t * (h - 1.0)) / PICTURE[1])
