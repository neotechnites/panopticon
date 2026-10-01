"""
PANOPTICON -- a stylized low-poly cut of the warden's rifle, a test beside the signed-off rifle.glb.

Same silhouette, origin, muzzle and scope axis as rifle_build.py, same atlas and texel density (its
texture, material and unwrap are reused); fewer, chunkier flat facets, ~250 tris.

    tools/modelling/model build rifle_lowpoly
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rifle_build as rb  # noqa: E402
import mdl  # noqa: E402

NAME = "rifle_lowpoly"     # -> weapons/models/rifle_lowpoly.glb
SIDES = 6                  # every round part is a hexagon


def loft(name, sections, cap0=True, cap1=True, top=None):
    """A hull through (y, [(x, z), ...]) sections along +Y; caps optional where a part buries its end."""
    n = len(sections[0][1])
    verts = [(x, y, z) for y, ring in sections for (x, z) in ring]
    faces = []
    for k in range(len(sections) - 1):
        a, b = k * n, (k + 1) * n
        faces += [[a + i, a + (i + 1) % n, b + (i + 1) % n, b + i] for i in range(n)]
    caps = []
    run = 1.0 if sections[-1][0] >= sections[0][0] else -1.0   # a loft may run toward -Y (the stock)
    if cap0:
        caps.append((list(range(n)), -run))
    if cap1:
        caps.append((list(range((len(sections) - 1) * n, len(sections) * n)), run))
    for f in faces:                                    # sides face away from the section centre
        c = [sum(verts[i][d] for i in f) / 4.0 for d in range(3)]
        k = f[0] // n
        ring = sections[k][1]
        cx = sum(p[0] for p in ring) / n
        cz = sum(p[1] for p in ring) / n
        nrm = mdl._newell([verts[i] for i in f])
        if nrm.x * (c[0] - cx) + nrm.z * (c[2] - cz) < 0.0:
            f.reverse()
    for f, sign in caps:
        if mdl._newell([verts[i] for i in f]).y * sign < 0.0:
            f.reverse()
        faces.append(f)
    ob = rb._reg(mdl.mesh(name, verts, faces), top=top)
    ob["open"] = True                                  # wound here; no recalc
    return ob


def rect(x0, x1, z0, z1):
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def hexring(r, cz=0.0):
    return [(r * math.sin(math.pi / 6 + i * math.pi / 3), cz + r * math.cos(math.pi / 6 + i * math.pi / 3))
            for i in range(SIDES)]


def decal(name, y0, y1, z0, z1, x, fit):
    """One quad on the left (-X) wall, stretched over a mark's texel rect."""
    ob = rb._reg(mdl.mesh(name, [(x, y0, z0), (x, y0, z1), (x, y1, z1), (x, y1, z0)], [(0, 1, 2, 3)]), fit=fit)
    ob["open"] = True
    return ob


def _geometry():
    RW = rb.RECEIVER_HALF_W
    Y0, Y1 = rb.RECEIVER_Y0, rb.RECEIVER_Y1
    zs = rb.SCOPE_Z

    # ---- receiver: flat-sided lower and the action's round top in one six-sided bar
    rb.zone(rb.ZONE_BLUED)
    top = rb.RECEIVER_RING_R
    outline = [(-RW, rb.RECEIVER_Z0), (RW, rb.RECEIVER_Z0), (RW, rb.RECEIVER_Z1),
               (0.012, top), (-0.012, top), (-RW, rb.RECEIVER_Z1)]
    loft("receiver", [(Y0, outline), (Y1, outline)])
    decal("eye_stamp", 0.090, 0.174, -0.031, 0.011, -RW - 0.0008, rb.EYE_RECT)

    # ---- bolt: shroud out the back, one chunky wedge down to the knob
    loft("bolt_shroud", [(-0.062, rect(-0.016, 0.016, -0.013, 0.019)), (Y0, rect(-0.016, 0.016, -0.013, 0.019))],
         cap1=False)
    by0, by1 = rb.BOLT_Y
    kx = rb.BOLT_KNOB_X[1]
    rb.frustum("bolt_handle",
               [(RW - 0.004, by0, 0.014), (RW - 0.004, by1, 0.014),
                (RW - 0.004, by1, -0.008), (RW - 0.004, by0, -0.008)],
               [(kx, by0 - 0.007, -0.034), (kx, by1 + 0.007, -0.034),
                (kx, by1 + 0.007, -0.072), (kx, by0 - 0.007, -0.072)])

    # ---- barrel: a hexagonal taper, its root buried in the receiver
    loft("barrel", [(Y1, hexring(rb.BARREL_R0)), (rb.MUZZLE_Y, hexring(rb.BARREL_R1))], cap0=False)

    # ---- scope on the same ADS axis: eyepiece bell, tube, objective flare; open at the eye
    rb.lathe("scope_body", [(rb.OCULAR_Y[0], rb.OCULAR_R), (rb.OCULAR_TAPER, rb.TUBE_R),
                            (rb.FLARE_Y, rb.TUBE_R), (rb.BELL_Y, rb.BELL_R)], zs, sides=SIDES, turn=0.5)
    rb.lathe("objective_glass", [(rb.BELL_Y, rb.BELL_R)], zs, cap=True, sides=SIDES, turn=0.5)["fit"] = rb.GLASS_RECT
    for k, (y0, y1) in enumerate(rb.RING_Y):
        rb.prism("ring%d" % k, y0, y1, (-rb.RING_R, rb.RING_R, rb.RECEIVER_Z1 - 0.002, zs + rb.RING_R))
    knob_top = rb.SADDLE_R * math.cos(math.pi / 8) + rb.KNOB_H
    flat = rb.TUBE_R * math.cos(math.pi / 6)
    rb.knob("knob_elev", (0.0, rb.KNOB_Y, zs + flat - 0.0005), "z", rb.KNOB_R, knob_top - flat + 0.0005, sides=4)
    rb.knob("knob_wind", (flat - 0.0005, rb.KNOB_Y, zs), "x", rb.KNOB_R, knob_top - flat + 0.0005, sides=4)

    # ---- stock: hand-worn wrist, then comb and butt as one loft out to the butt plate's face
    rb.zone(rb.ZONE_WORN)
    loft("wrist", [(Y0, rect(-RW, RW, -0.040, 0.004)), (-0.120, rect(-0.021, 0.021, -0.058, 0.012))],
         cap0=False, cap1=False)
    rb.zone(rb.ZONE_WALNUT)
    loft("stock", [(-0.120, rect(-0.021, 0.021, -0.058, 0.012)), (-0.200, rect(-0.024, 0.024, -0.082, 0.044)),
                   (rb.BUTT_Y, rect(-0.025, 0.025, -0.102, 0.048))], cap0=False, top=rb.ZONE_WORN)
    rb.zone(rb.ZONE_BRASS)
    decal("number_plate", -0.292, -0.240, -0.040, -0.022, -0.0252, rb.PLATE_RECT)

    # ---- belly and forend, two iron bands
    rb.zone(rb.ZONE_WALNUT)
    rb.prism("belly", Y0, Y1, (-RW - 0.001, RW + 0.001, -0.052, -0.030))
    loft("forend", [(Y1 - 0.002, rect(-RW - 0.001, RW + 0.001, -0.052, 0.002)),
                    (rb.FOREND_Y1, rect(-0.020, 0.020, -0.036, 0.004))], cap0=False)
    rb.zone(rb.ZONE_BLUED)
    rb.sleeve("band_rear", rb.BAND_Y[0][0], rb.BAND_Y[0][1], (-0.027, 0.027, -0.050, 0.025))
    rb.sleeve("band_front", rb.BAND_Y[1][0], rb.BAND_Y[1][1], (-0.022, 0.022, -0.040, 0.022))

    # ---- trigger and guard
    rb.guard_u("trigger_guard", 0.011, [(0.000, -0.050), (0.125, -0.050), (0.125, -0.092),
                                        (0.110, -0.092), (0.110, -0.064), (0.015, -0.064),
                                        (0.015, -0.092), (0.000, -0.092)])
    loft("trigger", [(0.044, rect(-0.005, 0.005, -0.082, -0.050)), (0.058, rect(-0.005, 0.005, -0.082, -0.050))])


def build():
    rb._OBJECTS.clear()
    _geometry()
    albedo = rb.build_texture()
    for i, ob in enumerate(rb._OBJECTS):
        if not ob.get("open"):
            rb._outward(ob)
        rb.unwrap(ob, seed=i)
    ob = mdl.join(rb._OBJECTS, rb.OBJECT_NAME)
    mdl.finish(ob, rb.warden_material("RifleWarden", albedo), strip_uvs=False)
    print("MDL STATS muzzle_local_godot=(0, 0, %.3f)" % -rb.MUZZLE_Y)
    return ob


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=rb.FACING_YAW)
