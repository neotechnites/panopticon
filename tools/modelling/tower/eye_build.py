"""eye -- THE WATCHING EYE over the tower: a low-poly UNIT sphere (radius 1.0, so the profile's radius is metres)
with an iris cap and a pupil cap, painted by tower/textures/eye.ase. THE GAZE AXIS IS glTF +Z, not Godot's -Z.

Three nodes the scene and the looks address by name: Eye_Sclera, Eye_Iris, Eye_Pupil. No rig, no collider.
Every part is unwrapped as a DISC seen down the gaze axis (centre = the pole, disc edge = the part's rim), so
each slice is a picture of that part head-on; the sclera's back half mirrors its front across the equator.
The caps ride IRIS_BIAS / PUPIL_BIAS proud of the ball; that is a measured depth budget, gated below.

Blender is Z-up and glTF is Y-up: p_gltf = (x, z, -y). So the gaze axis, glTF +Z, is Blender -Y.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import mdl  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================
NAME = "eye"
FACING_YAW = 0.0            # the gaze axis already faces the "front" camera

SEGMENTS = 16               # around the gaze axis; all three parts share it, so their facets line up
SCLERA_RADIUS = 1.0         # the model IS a unit sphere; the scene scales it

# The caps ride on spheres slightly larger than the sclera. The bias is the whole of the clearance and the
# only number to touch if the iris ever z-fights (Ryan, 2026-09-22: "weird artifacts right in the middle of
# its pupil" at 0.005 / 0.008). The rim radii are the apparent sizes from the lane.
IRIS_BIAS = 0.015
IRIS_RIM = 0.580
PUPIL_BIAS = 0.028
PUPIL_RIM = 0.290

# The clearance the build REFUSES to ship below, in metres on the unit ball: 0.00247 z-fought from the lane.
MIN_CLEARANCE = 0.009

IRIS_HALF = math.asin(IRIS_RIM / (SCLERA_RADIUS + IRIS_BIAS))      # radians off the gaze axis
PUPIL_HALF = math.asin(PUPIL_RIM / (SCLERA_RADIUS + PUPIL_BIAS))
# Sclera rings, degrees off the gaze axis: one under each cap's rim, then even steps to the back pole.
SCLERA_RINGS = [math.degrees(PUPIL_HALF), math.degrees(IRIS_HALF), 53.0, 71.5, 90.0, 112.5, 135.0, 157.5]

# The painted disc's diameter as a fraction of its slice; tools/textures/eye_placeholder.py paints to the same.
DISC = 0.94

SCLERA_ROUGH = 0.30
IRIS_ROUGH = 0.22
PUPIL_ROUGH = 0.10

# The gaze direction in Blender coordinates. GAZE, ACROSS, UP export as glTF +Z, +X, +Y.
GAZE = (0.0, -1.0, 0.0)
ACROSS = (1.0, 0.0, 0.0)
UP = (0.0, 0.0, 1.0)


# =============================================================================
# GEOMETRY
# =============================================================================

def _newell(pts):
    nx = ny = nz = 0.0
    for i in range(len(pts)):
        ax, ay, az = pts[i]
        bx, by, bz = pts[(i + 1) % len(pts)]
        nx += (ay - by) * (az + bz)
        ny += (az - bz) * (ax + bx)
        nz += (ax - bx) * (ay + by)
    return (nx, ny, nz)


def _point(radius, theta, phi):
    ct, st, cp, sp = math.cos(theta), math.sin(theta), math.cos(phi), math.sin(phi)
    return tuple(radius * (ct * GAZE[k] + st * (cp * ACROSS[k] + sp * UP[k])) for k in range(3))


def _lathe(obj_name, radius, thetas, uv_span, front_apex=True, back_apex=False):
    """Rings of SEGMENTS vertices at `thetas` (radians off GAZE) on a sphere, smooth, disc-unwrapped.

    `uv_span` is the angle the disc's edge stands for; past 90 degrees the disc folds back on itself, which
    is how the sclera's back half mirrors its front. A face is wound to face away from the origin.
    """
    verts, angles = [], []                       # angles[i] = (theta, phi) of vertex i
    if front_apex:
        verts.append(_point(radius, 0.0, 0.0)); angles.append((0.0, 0.0))
    base = len(verts)
    for theta in thetas:
        for i in range(SEGMENTS):
            phi = 2.0 * math.pi * i / SEGMENTS
            verts.append(_point(radius, theta, phi)); angles.append((theta, phi))
    if back_apex:
        verts.append(_point(radius, math.pi, 0.0)); angles.append((math.pi, 0.0))

    def ring(j, i):
        return base + j * SEGMENTS + (i % SEGMENTS)

    faces = []
    for i in range(SEGMENTS if front_apex else 0):
        faces.append((0, ring(0, i), ring(0, i + 1)))
    for j in range(len(thetas) - 1):
        for i in range(SEGMENTS):
            faces.append((ring(j, i), ring(j, i + 1), ring(j + 1, i + 1), ring(j + 1, i)))
    for i in range(SEGMENTS if back_apex else 0):
        faces.append((len(verts) - 1, ring(len(thetas) - 1, i + 1), ring(len(thetas) - 1, i)))

    fixed = []
    for face in faces:
        pts = [verts[k] for k in face]
        n = _newell(pts)
        c = [sum(p[k] for p in pts) for k in range(3)]
        fixed.append(face if sum(n[k] * c[k] for k in range(3)) > 0.0 else tuple(reversed(face)))

    ob = mdl.mesh(obj_name, verts, fixed)
    ob.data.name = obj_name + "_Mesh"
    uv = ob.data.uv_layers.new(name="UVMap")
    for loop in ob.data.loops:
        theta, phi = angles[loop.vertex_index]
        rho = 0.5 * DISC * min(theta, math.pi - theta) / uv_span
        uv.data[loop.index].uv = (0.5 + rho * math.cos(phi), 0.5 + rho * math.sin(phi))
    ob.data.shade_smooth()
    return ob


# =============================================================================
# THE CLEARANCE INSTRUMENT
#
# Both surfaces are INSCRIBED polyhedra, so neither is where its sphere is, and a cap offset by less than the
# sag the facets differ by is a cap the sclera speckles through. So the build measures it by ray.
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
    """Measure the clearance and REFUSE the build if it is under MIN_CLEARANCE."""
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

def _material(name, albedo, roughness, emissive=None):
    """One drawn slice as base colour (and one as glow), no metal, back faces culled."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    for stem, socket in ((albedo, "Base Color"), (emissive, "Emission Color")):
        if stem is None:
            continue
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = mdl.texture(stem)
        nt.links.new(node.outputs["Color"], bsdf.inputs[socket])
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Emission Strength"].default_value = 1.0 if emissive else 0.0
    mat.use_backface_culling = True
    return mat


def _paint(ob, mat):
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return ob


# =============================================================================
# BUILD
# =============================================================================

def build():
    sclera = _lathe("Eye_Sclera", SCLERA_RADIUS, [math.radians(d) for d in SCLERA_RINGS],
                    0.5 * math.pi, back_apex=True)
    _paint(sclera, _material("M_Sclera", "eye_sclera_albedo", SCLERA_ROUGH))

    iris_radius = SCLERA_RADIUS + IRIS_BIAS
    # open at the centre: everything inside 0.6 of the pupil's angle lies under the opaque pupil
    iris = _lathe("Eye_Iris", iris_radius, [0.6 * PUPIL_HALF, PUPIL_HALF, IRIS_HALF], IRIS_HALF,
                  front_apex=False)
    _paint(iris, _material("M_Iris", "eye_iris_albedo", IRIS_ROUGH, emissive="eye_iris_emissive"))

    pupil_radius = SCLERA_RADIUS + PUPIL_BIAS
    pupil = _lathe("Eye_Pupil", pupil_radius, [0.5 * PUPIL_HALF, PUPIL_HALF], PUPIL_HALF)
    _paint(pupil, _material("M_Pupil", "eye_pupil_albedo", PUPIL_ROUGH))

    _report_clearance("iris", "IRIS_BIAS", iris, sclera, IRIS_RIM, iris_radius, IRIS_BIAS)
    # Twice: the sclera is what the pupil must not sink into, the iris is what it is drawn on top of.
    _report_clearance("pupil_over_sclera", "PUPIL_BIAS", pupil, sclera,
                      PUPIL_RIM, pupil_radius, PUPIL_BIAS)
    _report_clearance("pupil_over_iris", "PUPIL_BIAS", pupil, iris,
                      PUPIL_RIM, pupil_radius, PUPIL_BIAS)

    print("MDL STATS gaze_axis=gltf+Z sclera_pole_z=%.5f" % SCLERA_RADIUS)
    print("MDL STATS iris_apex_z=%.5f half_angle_deg=%.3f" % (iris_radius, math.degrees(IRIS_HALF)))
    print("MDL STATS pupil_apex_z=%.5f half_angle_deg=%.3f" % (pupil_radius, math.degrees(PUPIL_HALF)))
    return [sclera, iris, pupil]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
