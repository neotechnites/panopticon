"""eye -- THE WATCHING EYE, the eyeball that hangs over the tower.

A dark sclera ball with a glowing red iris and a black pupil, authored as a
UNIT sphere so that WatchingEyeProfile.radius_metres can be applied in
scenes/tower/watching_eye.tscn as a uniform scale and mean literally the radius
in metres. THE GAZE AXIS IS glTF +Z, not Godot's conventional -Z; that is why
scripts/tower/watching_eye.gd builds its own basis instead of calling look_at.
Three nodes, three materials, no rig, no animation, no texture, no collider --
nothing here is on the rifle's hit mask.

This file reconstructs a model that predated the modelling pipeline. The sclera
is bit-for-bit the shipped one: a plain Blender UV sphere, 24 segments and 12
rings, smooth-shaded, its default UV map kept (the seam and the two pole fans
are what turn 266 mesh vertices into 323 glTF ones).

THE IRIS AND THE PUPIL ARE NOT WHAT SHIPPED, AND THAT IS THE FIX. They used to
be a sphere squashed to 0.42 along the gaze axis and a flat 24-gon disc, both
pushed forward until they cleared the eyeball -- which put the iris apex at
z=1.04192, 42 mm proud of a 1 m sclera, so from the lane it read as a disc
floating in front of the eye rather than a marking on it. They are now
spherical CAPS concentric with the sclera, lifted off it by nothing but
IRIS_BIAS / PUPIL_BIAS, so the iris curves with the ball at every angle. The
rim radii are unchanged at 0.580 and 0.290, which is what keeps the iris and
the pupil the same apparent size from the lane as before.

THE BIASES ARE NOT COSMETIC, THEY ARE THE DEPTH BUDGET. A cap inscribed in a
sphere sits INSIDE it everywhere except at its own vertices, and two caps with
different ring counts sag by different amounts, so the clearance the renderer
gets is always less than the bias -- it was a third of it. Shipped at 0.005 and
0.008 that left 2.4 mm on a unit ball, 6 mm at the scene's 2.5x, and the iris
z-fought through the middle of the pupil. The clearances are MEASURED below and
the build refuses to install under MIN_CLEARANCE, which is the only reason that
cannot come back as "it looked fine in Blender".

ONE MODEL, THREE LOOKS -- DO NOT ADD A --variant HERE. Ryan asked for a green
eye on the forest and a marble one on the rotunda (2026-09-23), and those are
per-map MATERIALS, not per-map models: scenes/ring/<map>_watching_eye_look.tres
holds three StandardMaterial3Ds and WatchingEye applies them as surface
overrides on ready, matched by the node names the contract pins. The geometry
is identical on every map by construction, so the clearance gate below is
measured once and cannot fall out of step between variants -- which is exactly
what building eye_forest.glb and eye_marble.glb would put at risk, to change
six colours. The three colour blocks below are MAP 1's, and map 1's alone.

Blender is Z-up and glTF is Y-up: p_gltf = (x, z, -y). So the gaze axis, glTF
+Z, is Blender -Y, and the sphere's poles sit on Blender +/-Z = glTF +/-Y.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================
NAME = "eye"
FACING_YAW = 0.0            # the gaze axis already faces the "front" camera

SEGMENTS = 24               # sclera, iris and pupil all share this longitude count
RING_COUNT = 12             # sclera only: Blender UV sphere ring_count

SCLERA_RADIUS = 1.0         # the model IS a unit sphere; the scene scales it

# The caps ride on spheres very slightly larger than the sclera. The bias is
# the whole of the clearance -- millimetres on a one-metre ball -- and it is
# the only number to touch if the iris ever z-fights.
#
# RYAN, 2026-09-22: "the eye started having like, weird artifacts right in the
# middle of its pupil." The biases were 0.005 and 0.008 and the measured
# clearances came out at 0.00239 and 0.00247 -- because both caps are
# INSCRIBED, and the sag their facets differ by ate two thirds of the bias
# before the renderer ever saw it. At the scene's 2.5x that left 6.3 mm of
# depth between a saturated emissive iris and a 0.006-black pupil, which the
# depth buffer cannot separate from the lane: the iris punched through the
# pupil in a ring of bright wedges at 53 percent of the pupil's radius, which
# is exactly where the clearance is thinnest. The rim radii are untouched, so
# nothing about the eye's apparent size or shape moves; only the standoff.
IRIS_BIAS = 0.015
IRIS_RIM = 0.580            # rim radius: the iris's apparent size from the lane
IRIS_RINGS = 4

PUPIL_BIAS = 0.028
PUPIL_RIM = 0.290
PUPIL_RINGS = 2

# The clearance the build REFUSES to ship below, in metres on the unit ball.
# Set from the failure: 0.00247 z-fought from the lane, so the floor is well
# clear of it and the biases above leave 0.01148 -- 28 percent of headroom over
# the floor and 4.6x the number that broke. This is a GATE, not a note; see
# _report_clearance. The old code printed the bad number and installed the
# model anyway, which is exactly how 0.00247 shipped.
MIN_CLEARANCE = 0.009

# Linear base colours, straight into glTF's baseColorFactor.
SCLERA_COLOR = (0.03, 0.03, 0.038, 1.0)
SCLERA_ROUGH = 0.30
IRIS_COLOR = (0.6, 0.01, 0.008, 1.0)
IRIS_ROUGH = 0.22
IRIS_EMISSION = (1.0, 0.03, 0.015, 1.0)
IRIS_EMISSION_STRENGTH = 1.1
PUPIL_COLOR = (0.006, 0.004, 0.006, 1.0)
PUPIL_ROUGH = 0.10

# The gaze direction in Blender coordinates. Exports as glTF +Z.
GAZE = (0.0, -1.0, 0.0)
# The two axes across the gaze. GAZE, ACROSS, UP export as glTF +Z, +X, +Y.
ACROSS = (1.0, 0.0, 0.0)
UP = (0.0, 0.0, 1.0)


# =============================================================================
# GEOMETRY
# =============================================================================

def _sphere(obj_name, radius):
    """A plain Blender UV sphere, smooth, keeping the UV map the primitive makes.

    Both are load-bearing: smooth shading and the seam/pole UV splits are what
    make the exported sclera 323 vertices and 528 triangles, which is the
    shipped eye.glb exactly.
    """
    bpy.ops.mesh.primitive_uv_sphere_add(segments=SEGMENTS, ring_count=RING_COUNT,
                                         radius=radius, location=(0.0, 0.0, 0.0))
    ob = bpy.context.view_layer.objects.active
    ob.name = obj_name
    ob.data.name = obj_name + "_Mesh"
    ob.data.shade_smooth()
    return ob


def _newell(pts):
    nx = ny = nz = 0.0
    for i in range(len(pts)):
        ax, ay, az = pts[i]
        bx, by, bz = pts[(i + 1) % len(pts)]
        nx += (ay - by) * (az + bz)
        ny += (az - bz) * (ax + bx)
        nz += (ax - bx) * (ay + by)
    return (nx, ny, nz)


def _cap(obj_name, radius, rim_radius, segments, rings):
    """A spherical cap of `radius`, centred on the origin, opening along GAZE.

    `rim_radius` is the radius of the circle the cap's edge draws when seen
    down the gaze axis -- so the cap subtends asin(rim_radius / radius) and two
    caps of different radii that share a rim radius look the same size head-on.
    Apex first, then `rings` rings of `segments` vertices; a triangle fan at the
    apex and quad bands below it.
    """
    half_angle = math.asin(rim_radius / radius)
    verts = [tuple(radius * c for c in GAZE)]
    for j in range(1, rings + 1):
        t = half_angle * j / rings
        ct, st = math.cos(t), math.sin(t)
        for i in range(segments):
            phi = 2.0 * math.pi * i / segments
            cp, sp = math.cos(phi), math.sin(phi)
            verts.append(tuple(radius * (ct * GAZE[k] + st * (cp * ACROSS[k] + sp * UP[k]))
                               for k in range(3)))

    def ring(j, i):                      # vertex index in ring j (1-based), column i
        return 1 + (j - 1) * segments + (i % segments)

    faces = []
    for i in range(segments):
        faces.append((0, ring(1, i), ring(1, i + 1)))
    for j in range(1, rings):
        for i in range(segments):
            faces.append((ring(j, i), ring(j, i + 1),
                          ring(j + 1, i + 1), ring(j + 1, i)))

    # The cap is convex about the origin, so a face's outward normal is simply
    # the direction of its own centroid. Wind every face against that rather
    # than trusting the order the loops above happen to produce.
    fixed = []
    for face in faces:
        pts = [verts[k] for k in face]
        n = _newell(pts)
        c = [sum(p[k] for p in pts) for k in range(3)]
        fixed.append(face if sum(n[k] * c[k] for k in range(3)) > 0.0
                     else tuple(reversed(face)))

    ob = mdl.mesh(obj_name, verts, fixed)
    ob.data.name = obj_name + "_Mesh"
    return ob


# =============================================================================
# THE CLEARANCE INSTRUMENT
#
# Both surfaces are INSCRIBED polyhedra, so neither is where its sphere is. The
# sclera's 24x12 facets sag up to 1 - cos(7.5 deg) = 8.6 mm inside radius 1.0,
# and a cap offset from the IDEAL sphere by less than the sag the facets differ
# by is a cap the sclera pokes through -- which renders as black speckle on the
# iris, not as a clean overlap, and is invisible in a diff. So the build
# measures it instead of assuming it: rays from the eye centre through the
# cone, comparing where each faceted surface is actually met.
# =============================================================================

CLEARANCE_LAT = 64          # ray grid; dense enough to land inside every facet
CLEARANCE_LON = 96


def _clearance(cap, sclera, rim_radius, cap_radius):
    """Smallest (cap radius - sclera radius) over the cap's cone, in metres.

    Negative means the sclera stands proud of the cap somewhere: speckle.
    """
    bpy.context.view_layer.update()
    half = math.asin(rim_radius / cap_radius)
    worst = 1e9
    for a in range(CLEARANCE_LAT):
        t = half * (a + 0.5) / CLEARANCE_LAT
        ct, st = math.cos(t), math.sin(t)
        for b in range(CLEARANCE_LON):
            phi = 2.0 * math.pi * (b + 0.5) / CLEARANCE_LON
            cp, sp = math.cos(phi), math.sin(phi)
            d = tuple(ct * GAZE[k] + st * (cp * ACROSS[k] + sp * UP[k]) for k in range(3))
            hit_c, loc_c, _, _ = cap.ray_cast((0.0, 0.0, 0.0), d, distance=2.0)
            hit_s, loc_s, _, _ = sclera.ray_cast((0.0, 0.0, 0.0), d, distance=2.0)
            if not (hit_c and hit_s):
                continue
            worst = min(worst, loc_c.length - loc_s.length)
    return worst


def _report_clearance(label, knob, cap, sclera, rim_radius, cap_radius, bias):
    """Measure the clearance and REFUSE the build if it is under MIN_CLEARANCE.

    This used to print the number and carry on, which is exactly how a 0.00247
    clearance shipped and z-fought in Ryan's face. A positive gap is not the
    test: the renderer needs room, not merely the right ORDER. The build dies
    here instead, because a model that breaks its own contract is not installed
    and this is the eye's real contract.
    """
    gap = _clearance(cap, sclera, rim_radius, cap_radius)
    print("MDL STATS %s_clearance=%+.5f floor=%.5f" % (label, gap, MIN_CLEARANCE))
    if gap < MIN_CLEARANCE:
        raise SystemExit(
            "MDL note %s_clearance=%+.5f is under the %.5f floor -- at the scene's "
            "2.5x that is %.1f mm of depth and the layers z-fight from the lane. "
            "Raise %s to at least %.4f."
            % (label, gap, MIN_CLEARANCE, gap * 2500.0, knob,
               bias + (MIN_CLEARANCE - gap)))
    return gap


# =============================================================================
# MATERIALS
# =============================================================================

def _material(name, color, roughness, emission=None, emission_strength=1.0):
    """Flat colour, no metal, double sided -- the shipped eye's three materials."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    mat.use_backface_culling = False          # exports as doubleSided
    mat.diffuse_color = color
    return mat


def _paint(ob, mat, smooth=True):
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    if smooth:
        ob.data.shade_smooth()
    return ob


# =============================================================================
# BUILD
# =============================================================================

def build():
    sclera = _sphere("Eye_Sclera", SCLERA_RADIUS)
    _paint(sclera, _material("M_Sclera", SCLERA_COLOR, SCLERA_ROUGH), smooth=False)

    iris_radius = SCLERA_RADIUS + IRIS_BIAS
    iris = _cap("Eye_Iris", iris_radius, IRIS_RIM, SEGMENTS, IRIS_RINGS)
    _paint(iris, _material("M_Iris", IRIS_COLOR, IRIS_ROUGH,
                           emission=IRIS_EMISSION,
                           emission_strength=IRIS_EMISSION_STRENGTH))

    pupil_radius = SCLERA_RADIUS + PUPIL_BIAS
    pupil = _cap("Eye_Pupil", pupil_radius, PUPIL_RIM, SEGMENTS, PUPIL_RINGS)
    _paint(pupil, _material("M_Pupil", PUPIL_COLOR, PUPIL_ROUGH))

    _report_clearance("iris", "IRIS_BIAS", iris, sclera, IRIS_RIM, iris_radius, IRIS_BIAS)
    # Twice, because the pupil sits over BOTH: the sclera is what it must not
    # sink into, the iris is what it is drawn on top of. Measuring only against
    # the sclera would pass a pupil that the iris speckles through.
    _report_clearance("pupil_over_sclera", "PUPIL_BIAS", pupil, sclera,
                      PUPIL_RIM, pupil_radius, PUPIL_BIAS)
    _report_clearance("pupil_over_iris", "PUPIL_BIAS", pupil, iris,
                      PUPIL_RIM, pupil_radius, PUPIL_BIAS)

    print("MDL STATS gaze_axis=gltf+Z sclera_pole_z=%.5f" % SCLERA_RADIUS)
    print("MDL STATS iris_apex_z=%.5f proud=%.5f half_angle_deg=%.3f"
          % (iris_radius, iris_radius - SCLERA_RADIUS,
             math.degrees(math.asin(IRIS_RIM / iris_radius))))
    print("MDL STATS pupil_apex_z=%.5f proud=%.5f half_angle_deg=%.3f"
          % (pupil_radius, pupil_radius - SCLERA_RADIUS,
             math.degrees(math.asin(PUPIL_RIM / pupil_radius))))
    return [sclera, iris, pupil]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
