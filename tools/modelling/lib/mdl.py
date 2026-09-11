"""
mdl -- the modelling library every PANOPTICON build script is written against.

A build script is a normal Python file in tools/modelling/ that:

  * puts every adjustable number in ONE block at the top,
  * defines ``build()`` which creates geometry and returns the objects to
    export,
  * ends with ``mdl.main(...)``.

It is then run by Blender, either by the pipeline::

    tools/modelling/model build runner --views front,side,threequarter

or by hand on the PC::

    blender.exe -b -noaudio -P runner_build.py -- --spec spec.json

Everything below the tunables block -- scene reset, camera placement, framing,
lighting, glTF export, render loop -- lives here so that no build script ever
has to re-derive it, and so that the mistakes recorded in docs/MODELLING.md
cannot be made twice.

THE RULES THIS FILE ENFORCES
----------------------------
* Cameras are ALWAYS aimed with a TRACK_TO constraint on an empty at the
  subject's bounding-box centre. No build script computes ``rotation_euler``.
  Hand-rolled aim trig points at bare ground and the render still "succeeds",
  which is the most expensive failure mode there is: it looks like a modelling
  bug and it is a camera bug.
* Camera DISTANCE is solved from the bounding box, not guessed. A view is asked
  for as an azimuth and an elevation; the framing is arithmetic.
* ``view_transform`` is forced to Standard. Blender's default AgX desaturates
  everything and makes flat-shaded grey read as mud.
* Every run starts from ``read_factory_settings(use_empty=True)``.
* ``view_layer.update()`` is called after every camera move, before the render.
"""

import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

# =============================================================================
# STANDARD VIEWS
# =============================================================================
# (azimuth, elevation, lens_mm) in degrees. Azimuth 0 puts the camera on -Y
# looking towards +Y, which is Blender's own "front". A model whose front does
# not face -Y declares ``facing_yaw`` and every azimuth below rotates with it,
# so "front" always means the front of the MODEL.

VIEWS = {
    "front":        (0.0,    8.0,  55.0),
    "back":         (180.0,  8.0,  55.0),
    "side":         (90.0,   6.0,  55.0),
    "side_left":    (-90.0,  6.0,  55.0),
    "threequarter": (35.0,  18.0,  50.0),
    "hero":         (215.0, 22.0,  50.0),
    "top":          (0.0,   85.0,  55.0),
    "lowangle":     (25.0, -14.0,  40.0),
}

DEFAULT_VIEWS = ("front", "side", "threequarter")

# =============================================================================
# DEFAULTS -- overridden per-run by the spec the pipeline ships
# =============================================================================

DEFAULTS = {
    "engine": "eevee",          # eevee (GPU, interactive session) | cycles (CPU)
    "samples": 64,
    # "auto" shapes each frame to what that particular view of the subject
    # actually occupies. A fixed portrait frame spends half its pixels on empty
    # air either side of a rifle, and half of a person's height on floor.
    "resolution": "auto",
    "res_long_edge": 1200,
    "margin": 1.12,             # framing slack around the bounding box
    "world_grey": 0.16,
    "world_strength": 0.45,
    "ground": True,
    "ground_color": [0.20, 0.20, 0.22, 1.0],
    # Watts at 1 m; mdl scales it by the subject's radius so a rifle and a
    # human land on the same exposure. Standard view transform CLIPS above 1.0
    # with no roll-off, so an over-bright rig does not look bright, it looks
    # like a white silhouette with no surface detail at all.
    "key_energy": 200.0,
    "pose": "anim",             # "rest" mutes the action, to debug a rig
    "frame": None,              # pose an animated rig at this frame before rendering
    "views": list(DEFAULT_VIEWS),
    "cams": [],                 # ad-hoc [az, el, lens] triples
    "turntable": 0,
    "out_dir": ".",
    "glb": True,
}


# =============================================================================
# SCENE
# =============================================================================

def reset():
    """Empty scene, no default cube, no default camera, no leftover state."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _link(ob):
    bpy.context.collection.objects.link(ob)
    return ob


def mesh(name, verts, faces):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    return _link(bpy.data.objects.new(name, me))


# =============================================================================
# GEOMETRY HELPERS
# =============================================================================

def _newell(poly):
    n = Vector((0.0, 0.0, 0.0))
    for i in range(len(poly)):
        a, b = Vector(poly[i]), Vector(poly[(i + 1) % len(poly)])
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n


def frustum(name, quad_a, quad_b):
    """Hull between two 4-point rings; quad_a[i] pairs with quad_b[i].

    Winding is auto-corrected against the ring-to-ring axis so every normal
    points outward whichever way round the caller listed the corners.
    """
    qa, qb = list(quad_a), list(quad_b)
    ca = sum((Vector(v) for v in qa), Vector()) / 4.0
    cb = sum((Vector(v) for v in qb), Vector()) / 4.0
    if _newell(qa).dot(cb - ca) < 0.0:
        qa.reverse()
        qb.reverse()
    faces = [(3, 2, 1, 0), (4, 5, 6, 7)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append((i, j, 4 + j, 4 + i))
    return mesh(name, qa + qb, faces)


def prism(name, y0, y1, rect0, rect1=None):
    """Box / tapered box extruded along +Y. rect = (x0, x1, z0, z1)."""
    rect1 = rect0 if rect1 is None else rect1

    def ring(y, r):
        return [(r[0], y, r[2]), (r[1], y, r[2]), (r[1], y, r[3]), (r[0], y, r[3])]

    return frustum(name, ring(y0, rect0), ring(y1, rect1))


def plate_z(name, xy_quad, z0, z1):
    """A flat 4-sided plate lying in XY, given thickness in Z."""
    return frustum(name,
                   [(x, y, z0) for (x, y) in xy_quad],
                   [(x, y, z1) for (x, y) in xy_quad])


def box(name, lo, hi):
    """Axis-aligned box between two opposite corners."""
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    return prism(name, y0, y1, (x0, x1, z0, z1))


def tube(name, y0, y1, radii, cz=0.0, cx=0.0, sides=8):
    """N-gon tube running along +Y. ``radii`` is a float or a per-vertex list."""
    if not isinstance(radii, (list, tuple)):
        radii = [radii] * sides
    verts = []
    for y in (y0, y1):
        for i in range(sides):
            t = 2.0 * math.pi * i / sides
            r = radii[i % len(radii)]
            verts.append((cx + r * math.sin(t), y, cz + r * math.cos(t)))
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((i, j, sides + j, sides + i))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple(range(sides, 2 * sides)))
    return mesh(name, verts, faces)


def _section(sides, rx, rz):
    """Cross-section points in the bone's local XZ plane.

    4 sides gives a RECTANGLE (corners at +/-rx, +/-rz), not a diamond -- a
    diamond makes limbs look like knife blades from every axis-aligned view.
    6 or more gives a regular n-gon inscribed in the rx/rz ellipse with a
    vertex on +X, which is what keeps a hexagonal limb reading as round.
    """
    if sides == 4:
        return [(rx, rz), (-rx, rz), (-rx, -rz), (rx, -rz)]
    pts = []
    for i in range(sides):
        a = 2.0 * math.pi * i / sides
        pts.append((rx * math.cos(a), rz * math.sin(a)))
    return pts


def _basis(direction, up_hint=(0.0, 0.0, 1.0)):
    """Right-handed basis with +Y along ``direction``. Never degenerate."""
    y = Vector(direction).normalized()
    up = Vector(up_hint)
    if abs(y.dot(up)) > 0.995:
        up = Vector((0.0, 1.0, 0.0))
    if abs(y.dot(up)) > 0.995:
        up = Vector((1.0, 0.0, 0.0))
    x = up.cross(y).normalized()
    z = y.cross(x).normalized()
    return x, y, z


def limb(name, head, direction, rings, sides=6, up_hint=(0.0, 0.0, 1.0)):
    """A capped, tapered n-gon tube along ``direction`` from ``head``.

    ``rings`` is [(distance_along_direction, radius_x, radius_z), ...] in the
    limb's own frame, so a limb's shape is a readable table of numbers rather
    than a wall of world-space vertices. This is the workhorse for every
    organic-ish part: torso, thigh, arm, neck, barrel shroud.
    """
    ex, ey, ez = _basis(direction, up_hint)
    origin = Vector(head)
    verts, faces = [], []
    n = len(rings)
    for (t, rx, rz) in rings:
        centre = origin + ey * t
        for (px, pz) in _section(sides, rx, rz):
            verts.append(tuple(centre + ex * px + ez * pz))
    for r in range(n - 1):
        a, b = r * sides, (r + 1) * sides
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((a + i, a + j, b + j, b + i))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple(range((n - 1) * sides, n * sides)))
    return mesh(name, verts, faces)


def mirror_x(ob, name):
    """A mirrored copy across x=0, with winding fixed so normals stay out."""
    me = ob.data.copy()
    me.name = name
    for v in me.vertices:
        v.co.x = -v.co.x
    me.flip_normals()
    return _link(bpy.data.objects.new(name, me))


def merge_parts(parts, name):
    """Fuse tagged parts into one mesh and hand back the vertex-group map.

    ``parts`` is [(bone_name, object), ...]. Returns (object, {bone: [idx]}).

    Done by hand rather than with ``bpy.ops.object.join`` because join gives no
    promise about the order it concatenates vertices in, and the whole point
    here is to know exactly which vertices belong to which bone. Getting that
    wrong produces a model that renders perfectly and deforms like a bin bag.
    """
    verts, faces, groups = [], [], {}
    for bone, ob in parts:
        base = len(verts)
        me = ob.data
        verts.extend(tuple(v.co) for v in me.vertices)
        faces.extend(tuple(base + i for i in p.vertices) for p in me.polygons)
        groups.setdefault(bone, []).extend(range(base, len(verts)))
        bpy.data.objects.remove(ob, do_unlink=True)
    return mesh(name, verts, faces), groups


# =============================================================================
# MATERIAL / FINISHING
# =============================================================================

def flat_material(name, color, roughness=0.9, metallic=0.0, specular=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = tuple(color)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if specular is not None:
            for key in ("Specular IOR Level", "Specular"):
                if key in bsdf.inputs:
                    bsdf.inputs[key].default_value = specular
                    break
    mat.diffuse_color = tuple(color)
    return mat


def join(objects, name):
    """Join into one object. Returns it, with the mesh datablock renamed too."""
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def finish(ob, material, flat=True, strip_uvs=True):
    """Single material, flat shading, no UVs. The house style for these models."""
    me = ob.data
    me.materials.clear()
    me.materials.append(material)
    if flat:
        try:
            me.shade_flat()
        except Exception:
            for p in me.polygons:
                p.use_smooth = False
    if strip_uvs:
        while me.uv_layers:
            me.uv_layers.remove(me.uv_layers[0])
    return ob


# =============================================================================
# ARMATURE
# =============================================================================

def armature(name, bones, connect=()):
    """Build an armature from a table of bones.

    ``bones`` is [(bone, parent_or_None, head, direction, length, local_x), ...]
    where ``local_x`` is the world-space direction the bone's own +X axis must
    point. Roll is SOLVED to satisfy it rather than being typed in, because a
    typed roll is a number nobody can check and the game's per-bone pose
    offsets (scripts/player/prisoner_avatar.gd) are meaningless if the rest
    orientation drifts.
    """
    arm_data = bpy.data.armatures.new(name)
    arm = _link(bpy.data.objects.new(name, arm_data))
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for (bn, parent, head, direction, length, local_x) in bones:
        eb = arm_data.edit_bones.new(bn)
        d = Vector(direction).normalized()
        eb.head = Vector(head)
        eb.tail = Vector(head) + d * length
        eb.roll = 0.0
        if local_x is not None:
            want = Vector(local_x).normalized()
            got = eb.matrix.to_3x3().col[0].normalized()
            axis = eb.matrix.to_3x3().col[1].normalized()
            ang = math.atan2(axis.dot(got.cross(want)), got.dot(want))
            eb.roll = ang
        if parent:
            eb.parent = made[parent]
            eb.use_connect = bn in connect
        made[bn] = eb
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def rigid_bind(ob, arm, groups):
    """Parent ``ob`` to ``arm`` with one vertex group per bone, weight 1.

    ``groups`` maps bone name -> list of vertex indices. Rigid (single
    influence) binding is deliberate for hard-surface low-poly: smooth weights
    on a 500-triangle body produce shrink-wrapped elbows, not deformation.
    """
    for bn, idxs in groups.items():
        vg = ob.vertex_groups.new(name=bn)
        vg.add(list(idxs), 1.0, "REPLACE")
    ob.parent = arm
    ob.matrix_parent_inverse = arm.matrix_world.inverted()
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    mod.use_vertex_groups = True
    return ob


def bake_pose(arm, action_name, frames, fps=30, curves=None, ground=None):
    """Key every posed bone on every frame of ``frames``.

    ``curves`` maps bone name -> callable(frame_index, n) -> dict with any of
    ``euler`` (x, y, z in DEGREES, bone-local) and ``location``.

    ``ground``, if given, is (root_bone, [probe_bone, ...], floor_z): after the
    rest of the pose is applied the root is dropped or lifted so the lowest
    probe-bone tail sits exactly on the floor. That is what stops a run cycle
    skating -- and it is computed from the posed skeleton rather than typed in
    as a bob curve that has to be re-tuned every time a leg length changes.
    """
    scene = bpy.context.scene
    scene.render.fps = fps
    scene.frame_start = 1
    scene.frame_end = len(frames)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"

    if arm.animation_data is None:
        arm.animation_data_create()
    action = bpy.data.actions.new(action_name)
    arm.animation_data.action = action
    try:
        slot = action.slots.new(id_type="OBJECT", name=action_name)
        arm.animation_data.action_slot = slot
    except Exception:
        pass  # Blender < 4.4 has no slotted actions

    curves = curves or {}
    n = len(frames)

    if ground and ground[2] is None:
        # Floor height defaults to wherever the probes already are at rest, so
        # a build script never has to restate a number the rig already knows.
        bpy.context.view_layer.update()
        rest_low = min((arm.matrix_world @ arm.pose.bones[p].tail).z
                       for p in ground[1] if p in arm.pose.bones)
        ground = (ground[0], ground[1], rest_low) + tuple(ground[3:])
        print("MDL ground floor_z=%.4f (from rest pose)" % rest_low)

    for i, fr in enumerate(frames):
        scene.frame_set(fr)
        for pb in arm.pose.bones:
            pb.rotation_euler = (0.0, 0.0, 0.0)
            pb.location = (0.0, 0.0, 0.0)
        for bn, fn in curves.items():
            pb = arm.pose.bones.get(bn)
            if pb is None:
                continue
            out = fn(i, n) or {}
            if "euler" in out:
                pb.rotation_euler = [math.radians(a) for a in out["euler"]]
            if "location" in out:
                pb.location = out["location"]
        if ground:
            _ground(arm, *ground)
        for pb in arm.pose.bones:
            pb.keyframe_insert("rotation_euler", frame=fr)
            pb.keyframe_insert("location", frame=fr)
            pb.keyframe_insert("scale", frame=fr)

    n_curves = 0
    for fc in action_fcurves(action):
        n_curves += 1
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    print("MDL anim '%s' %d curves, frames %d..%d @ %d fps"
          % (action_name, n_curves, frames[0], frames[-1], fps))
    bpy.ops.object.mode_set(mode="OBJECT")
    return action


def action_fcurves(action):
    """Every F-curve in an action, on Blender 4.3 and on Blender 4.4+ alike.

    4.4 moved keyframes out of ``Action.fcurves`` and into
    layer -> strip -> channelbag(slot). The old attribute is simply gone in 5.x,
    so anything that touches interpolation has to go the long way round.
    """
    curves = getattr(action, "fcurves", None)
    if curves is not None:
        return list(curves)
    out = []
    for layer in getattr(action, "layers", []):
        for strip in getattr(layer, "strips", []):
            for slot in action.slots:
                try:
                    bag = strip.channelbag(slot)
                except Exception:
                    bag = None
                if bag is not None:
                    out.extend(bag.fcurves)
    return out


def _ground(arm, root_name, probes, floor_z, max_lift=None):
    """Slide ``root_name`` vertically until the lowest probe tail hits floor_z.

    ``max_lift`` caps how far the root may be pushed UP. Without it a cycle
    where both feet leave the ground at once hoists the whole body, which is
    correct for a bunny hop and wrong for a run.
    """
    root = arm.pose.bones.get(root_name)
    if root is None:
        return
    bpy.context.view_layer.update()
    low = min((arm.matrix_world @ arm.pose.bones[p].tail).z
              for p in probes if p in arm.pose.bones)
    drop = floor_z - low
    if max_lift is not None:
        drop = min(drop, max_lift)
    if abs(drop) < 1e-6:
        return
    # root.location is in the root bone's own rest space, so convert the world
    # offset through the rest matrix rather than assuming +Z is +Y.
    local = root.bone.matrix_local.to_3x3().inverted() @ Vector((0.0, 0.0, drop))
    root.location = Vector(root.location) + local
    bpy.context.view_layer.update()


# =============================================================================
# EXPORT
# =============================================================================

def export_glb(path, objects):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    kwargs = dict(filepath=path, export_format="GLB", use_selection=True,
                  export_apply=False, export_yup=True, export_normals=True,
                  export_texcoords=True)
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB",
                                  use_selection=True)
    return path


# =============================================================================
# RENDER
# =============================================================================

def _bounds(objects):
    deps = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in objects:
        ev = ob.evaluated_get(deps)
        me = ev.to_mesh()
        for v in me.vertices:
            w = ev.matrix_world @ v.co
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
        ev.to_mesh_clear()
    return lo, hi


def _dir(az_deg, el_deg):
    az, el = math.radians(az_deg), math.radians(el_deg)
    return Vector((math.sin(az) * math.cos(el),
                   -math.cos(az) * math.cos(el),
                   math.sin(el))).normalized()


def _fit_distance(lo, hi, direction, lens, res_x, res_y, margin):
    """Smallest camera distance along ``direction`` that contains the box.

    Solved, not guessed. Blender's AUTO sensor fit puts the 36 mm sensor on
    the LONGER image axis, so the half-angles are asymmetric and a naive
    bounding-sphere fit wastes a third of a portrait frame on empty air.
    """
    half = 18.0 / lens
    if res_x >= res_y:
        tan_x, tan_y = half, half * res_y / res_x
    else:
        tan_y, tan_x = half, half * res_x / res_y
    centre = (lo + hi) * 0.5
    ex, ey, ez = _basis(-direction)          # ey is the view direction
    right, up = ex, ez
    need = 0.0
    for cx in (lo.x, hi.x):
        for cy in (lo.y, hi.y):
            for cz in (lo.z, hi.z):
                rel = Vector((cx, cy, cz)) - centre
                depth = rel.dot(direction)
                need = max(need,
                           depth + abs(rel.dot(right)) / tan_x,
                           depth + abs(rel.dot(up)) / tan_y)
    return need * margin


def _auto_resolution(lo, hi, direction, long_edge=1200, short_min=560):
    """Frame shape from the subject's own projected extents for THIS view."""
    ex, _ey, ez = _basis(-direction)
    centre = (lo + hi) * 0.5
    w = h = 1e-6
    for cx in (lo.x, hi.x):
        for cy in (lo.y, hi.y):
            for cz in (lo.z, hi.z):
                rel = Vector((cx, cy, cz)) - centre
                w = max(w, abs(rel.dot(ex)))
                h = max(h, abs(rel.dot(ez)))
    aspect = w / h
    if aspect >= 1.0:
        rx, ry = long_edge, max(short_min, int(long_edge / aspect))
    else:
        ry, rx = long_edge, max(short_min, int(long_edge * aspect))
    return (rx // 2) * 2, (ry // 2) * 2


def setup_scene(spec, objects):
    scene = bpy.context.scene
    engine = spec.get("engine", "eevee").lower()
    if engine == "cycles":
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = int(spec.get("samples", 64))
        scene.cycles.use_denoising = True
    else:
        scene.render.engine = "BLENDER_EEVEE"
        ee = scene.eevee
        _try(ee, "taa_render_samples", int(spec.get("samples", 64)))
        _try(ee, "use_shadows", True)
        _try(ee, "use_raytracing", True)
        _try(ee, "use_fast_gi", True)
        _try(ee, "shadow_ray_count", 2)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    # AgX desaturates flat grey into mud; Standard is the only honest transform
    # when the whole model is one untextured colour.
    _try(scene.view_settings, "view_transform", "Standard")

    grey = float(spec.get("world_grey", 0.20))
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (grey, grey, grey * 1.08, 1.0)
    bg.inputs[1].default_value = float(spec.get("world_strength", 0.75))

    lo, hi = _bounds(objects)
    centre = (lo + hi) * 0.5
    radius = max((hi - lo).length * 0.5, 1e-3)

    if spec.get("ground", True):
        bpy.ops.mesh.primitive_plane_add(size=max(40.0, radius * 30.0),
                                         location=(centre.x, centre.y, lo.z - radius * 0.004))
        g = bpy.context.active_object
        g.data.materials.append(flat_material("Ground", spec.get("ground_color",
                                                                [0.30, 0.30, 0.32, 1.0]),
                                              roughness=0.95))

    target = _link(bpy.data.objects.new("CamTarget", None))
    target.location = centre
    cam = _link(bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"

    lights = []
    for nm, energy in (("key", 1.0), ("fill", 0.28), ("rim", 0.55)):
        ld = bpy.data.lights.new(nm, type="AREA")
        ld.energy = float(spec.get("key_energy", 900.0)) * energy * max(radius, 0.4) ** 2
        ld.size = radius * 1.6
        lights.append((nm, _link(bpy.data.objects.new(nm, ld))))
    return scene, cam, target, lights, lo, hi, centre, radius


def _try(owner, attr, value):
    try:
        setattr(owner, attr, value)
        return True
    except Exception as exc:
        print("MDL note: could not set %s.%s = %r (%s)"
              % (type(owner).__name__, attr, value, exc))
        return False


def _place_lights(lights, centre, radius, az, el):
    """Key/fill/rim relative to the CAMERA, so every azimuth is lit the same.

    A world-fixed rig looks superb from one angle and like a silhouette from
    the opposite one, which costs an entire round trip to discover.
    """
    offsets = {"key": (40.0, 42.0, 3.0), "fill": (-65.0, 6.0, 3.6), "rim": (168.0, 34.0, 3.2)}
    for nm, ob in lights:
        d_az, d_el, dist = offsets[nm]
        ob.location = centre + _dir(az + d_az, min(88.0, el + d_el)) * radius * dist
        con = ob.constraints.new(type="TRACK_TO") if not ob.constraints else ob.constraints[0]
        con.target = bpy.data.objects["CamTarget"]
        con.track_axis = "TRACK_NEGATIVE_Z"
        con.up_axis = "UP_Y"


def resolve_views(spec, facing_yaw):
    """Turn the requested view names / ad-hoc cameras into a render list."""
    out = []
    for nm in spec.get("views") or []:
        if nm not in VIEWS:
            raise SystemExit("MDL ERROR: unknown view %r. Known: %s"
                             % (nm, ", ".join(sorted(VIEWS))))
        az, el, lens = VIEWS[nm]
        out.append((nm, az + facing_yaw, el, lens))
    for i, cam in enumerate(spec.get("cams") or []):
        az, el = float(cam[0]), float(cam[1])
        lens = float(cam[2]) if len(cam) > 2 else 50.0
        out.append(("cam%d_az%g_el%g" % (i + 1, az, el), az + facing_yaw, el, lens))
    n = int(spec.get("turntable") or 0)
    for i in range(n):
        az = 360.0 * i / n
        out.append(("turn%02d" % i, az + facing_yaw, 14.0, 50.0))
    return out


def render(spec, objects, name, facing_yaw=0.0):
    shots = resolve_views(spec, facing_yaw)
    if not shots:
        return []
    scene, cam, target, lights, lo, hi, centre, radius = setup_scene(spec, objects)
    fixed_res = spec.get("resolution")
    if fixed_res in (None, "auto"):
        fixed_res = None
    out_dir = spec.get("out_dir", ".")
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for view_name, az, el, lens in shots:
        cam.data.type = "PERSP"
        cam.data.lens = lens
        d = _dir(az, el)
        res_x, res_y = fixed_res or _auto_resolution(
            lo, hi, d, int(spec.get("res_long_edge", 1200)))
        scene.render.resolution_x, scene.render.resolution_y = int(res_x), int(res_y)
        dist = _fit_distance(lo, hi, d, lens, int(res_x), int(res_y),
                             float(spec.get("margin", 1.12)))
        cam.location = centre + d * dist
        target.location = centre
        _place_lights(lights, centre, radius, az, el)
        bpy.context.view_layer.update()          # constraints have not solved yet
        path = os.path.join(out_dir, "%s_%s.png" % (name, view_name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s  az=%.1f el=%.1f lens=%.0f dist=%.3f %dx%d" %
              (os.path.basename(path), az, el, lens, dist, res_x, res_y))
        written.append(path)
    return written


# =============================================================================
# STATS -- the numbers the agent reads instead of squinting
# =============================================================================

def report(name, objects, extra=None):
    tris = verts = 0
    for ob in objects:
        if ob.type != "MESH":
            continue
        me = ob.data
        me.calc_loop_triangles()
        tris += len(me.loop_triangles)
        verts += len(me.vertices)
    lo, hi = _bounds(objects)
    size = hi - lo
    print("MDL STATS name=%s tris=%d verts=%d" % (name, tris, verts))
    print("MDL STATS bbox_blender lo=(%.4f,%.4f,%.4f) hi=(%.4f,%.4f,%.4f)"
          % (lo.x, lo.y, lo.z, hi.x, hi.y, hi.z))
    print("MDL STATS size=(%.4f,%.4f,%.4f)  godot_height=%.4f" % (size.x, size.y, size.z, size.z))
    for k, v in (extra or {}).items():
        print("MDL STATS %s=%s" % (k, v))
    return {"tris": tris, "verts": verts,
            "bbox": [list(lo), list(hi)]}


# =============================================================================
# ENTRY POINT
# =============================================================================

def _spec_from_argv():
    spec = dict(DEFAULTS)
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        for i, a in enumerate(rest):
            if a == "--spec" and i + 1 < len(rest):
                with open(rest[i + 1]) as fh:
                    spec.update(json.load(fh))
    return spec


def main(name, build, facing_yaw=0.0, glb_name=None, post=None):
    """Run a build script. This is the last line of every build script.

    ``build()`` returns the object (or list of objects) to export and render.
    ``facing_yaw`` is how many degrees to rotate every named view so that
    "front" means the front of this model, whichever way it was authored.
    """
    spec = _spec_from_argv()
    reset()
    result = build()
    objects = list(result) if isinstance(result, (list, tuple)) else [result]

    stats = report(name, [o for o in objects if o.type == "MESH"])

    out_dir = spec.get("out_dir", ".")
    os.makedirs(out_dir, exist_ok=True)
    if spec.get("glb", True):
        path = os.path.join(out_dir, glb_name or (name + ".glb"))
        export_glb(path, objects)
        stats["glb"] = path
        stats["glb_bytes"] = os.path.getsize(path)
        print("MDL EXPORT %s (%d bytes)" % (path, stats["glb_bytes"]))

    if spec.get("pose") == "rest":
        # Clearing the action is NOT enough: Blender leaves every pose bone at
        # whatever it was last evaluated to, so a "rest" render silently shows
        # the last baked frame. The channels have to be zeroed by hand.
        for ob in objects:
            if ob.type != "ARMATURE":
                continue
            if ob.animation_data:
                ob.animation_data.action = None
            for pb in ob.pose.bones:
                pb.location = (0.0, 0.0, 0.0)
                pb.rotation_euler = (0.0, 0.0, 0.0)
                pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
                pb.scale = (1.0, 1.0, 1.0)
        bpy.context.view_layer.update()
        print("MDL pose=rest (action cleared, channels zeroed)")

    if spec.get("frame") is not None:
        bpy.context.scene.frame_set(int(spec["frame"]))
        bpy.context.view_layer.update()
        print("MDL frame=%s" % spec["frame"])

    if post:
        post(spec, objects)

    stats["renders"] = render(spec, [o for o in objects if o.type == "MESH"],
                              name, facing_yaw)
    with open(os.path.join(out_dir, name + ".stats.json"), "w") as fh:
        json.dump(stats, fh, indent=1, default=str)
    print("MDL DONE %s" % name)
    return stats
