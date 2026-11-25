"""aspens_views -- the review renders: player views of the one Blender scene under the scene's own light
(aspens.tscn's numbers), EEVEE. ASPENS_VIEWS=<dir> on a build writes them there, before the display's 2x lift."""

import math
import os

import bpy

RUNNER_GLB = "characters/models/runner.glb"


def _srgb(c):
    return tuple(((v / 255.0 + 0.055) / 1.055) ** 2.4 if v > 10 else v / 255.0 / 12.92 for v in c) + (1.0,)


def _relight(mat, ab):
    """Godot's sum on one material: albedo x (ambient + sun), then depth fog."""
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if bsdf is None:
        return
    for n in nt.nodes:
        if n.type == "TEX_IMAGE":
            n.interpolation = "Linear"
    src = bsdf.inputs["Base Color"]
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    card = mat.name.endswith(("_leaf", "_tuft"))       # aspens_card.gdshader: unshaded, cut by the tile's alpha
    dif, emi = nt.nodes.new("ShaderNodeBsdfDiffuse"), nt.nodes.new("ShaderNodeEmission")
    emi.inputs["Strength"].default_value = (0.5 * (ab.LEAF_GLOW if mat.name.endswith("_leaf") else 1.0)) if card else ab.AMBIENT
    if src.links:
        for node in (dif, emi):
            nt.links.new(src.links[0].from_socket, node.inputs["Color"])
    else:
        dif.inputs["Color"].default_value = emi.inputs["Color"].default_value = src.default_value
    lit = nt.nodes.new("ShaderNodeAddShader")
    if card:
        dif.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
        for link in list(dif.inputs["Color"].links):
            nt.links.remove(link)
    nt.links.new(dif.outputs[0], lit.inputs[0])
    nt.links.new(emi.outputs[0], lit.inputs[1])
    cam = nt.nodes.new("ShaderNodeCameraData")
    rng = nt.nodes.new("ShaderNodeMapRange")
    rng.inputs["From Min"].default_value, rng.inputs["From Max"].default_value = ab.FOG[0], ab.FOG[1]
    rng.inputs["To Min"].default_value, rng.inputs["To Max"].default_value = 0.0, ab.FOG[2]
    nt.links.new(cam.outputs["View Distance"], rng.inputs["Value"])
    fog = nt.nodes.new("ShaderNodeEmission")
    fog.inputs["Color"].default_value = _srgb(ab.FOG_COL)
    fog.inputs["Strength"].default_value = 0.5
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(rng.outputs["Result"], mix.inputs["Fac"])
    nt.links.new(lit.outputs[0], mix.inputs[1])
    nt.links.new(fog.outputs[0], mix.inputs[2])
    last = mix.outputs[0]
    if card:
        img = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
        gate = nt.nodes.new("ShaderNodeMath")
        gate.operation = "GREATER_THAN"
        gate.inputs[1].default_value = 0.4
        nt.links.new(img.outputs["Alpha"], gate.inputs[0])
        clear, cutout = nt.nodes.new("ShaderNodeBsdfTransparent"), nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(gate.outputs[0], cutout.inputs["Fac"])
        nt.links.new(clear.outputs[0], cutout.inputs[1])
        nt.links.new(last, cutout.inputs[2])
        last = cutout.outputs[0]
        for attr, value in (("surface_render_method", "DITHERED"), ("use_transparent_shadow", True), ("use_backface_culling", False)):
            try:
                setattr(mat, attr, value)
            except Exception:
                pass
    nt.links.new(last, out.inputs["Surface"])


def _world(ab):
    """The sky to the camera only (halved for the 2x display); the light is the materials' own sum."""
    w = bpy.data.worlds.new("AspensSky")
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    geo, sep = nt.nodes.new("ShaderNodeNewGeometry"), nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Incoming"], sep.inputs[0])
    neg = nt.nodes.new("ShaderNodeMath")
    neg.operation = "MULTIPLY"
    neg.inputs[1].default_value = -1.0
    nt.links.new(sep.outputs["Z"], neg.inputs[0])
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.use_clamp = True
    pw.inputs[1].default_value = 0.5
    nt.links.new(neg.outputs[0], pw.inputs[0])
    grad = nt.nodes.new("ShaderNodeMix")
    grad.data_type = "RGBA"
    grad.inputs[6].default_value, grad.inputs[7].default_value = _srgb(ab.SKY_HORIZON), _srgb(ab.SKY_TOP)
    nt.links.new(pw.outputs[0], grad.inputs["Factor"])
    path = nt.nodes.new("ShaderNodeLightPath")
    gain = nt.nodes.new("ShaderNodeMath")
    gain.operation = "MULTIPLY"
    gain.inputs[1].default_value = 0.5
    nt.links.new(path.outputs["Is Camera Ray"], gain.inputs[0])
    nt.links.new(grad.outputs[2], bg.inputs["Color"])
    nt.links.new(gain.outputs[0], bg.inputs["Strength"])
    return w


def _runner(repo, at, face):
    """The game's own 1.8 m runner standing at a spot, facing a point: the scale every view is read against."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(repo, RUNNER_GLB))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.location = at
            o.rotation_mode = "XYZ"
            o.rotation_euler = (o.rotation_euler[0], 0.0, math.atan2(face[1] - at[1], face[0] - at[0]) + math.pi / 2.0)
    return new


def post(spec, objects):
    out = os.environ.get("ASPENS_VIEWS")
    if not out:
        return
    import aspens_build as ab
    os.makedirs(out, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    try:
        scene.eevee.taa_render_samples = 16
        scene.eevee.use_raytracing = False
        scene.eevee.shadow_pool_size = "1024"
    except Exception:
        pass
    scene.world = _world(ab)
    start = ab.pol(5.0, ab.START_R, ab.DECK_Z)
    mid = ab.pol(352.0, 52.0, ab.ground_z(*ab.pol(352.0, 52.0, 0.0)[:2]))
    top = (0.0, 0.0, ab.DECK_Z + ab.STUMP_H)
    repo = spec.get("tex_root") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    guard = []
    if os.path.isfile(os.path.join(repo, RUNNER_GLB)):
        _runner(repo, start, top)
        _runner(repo, mid, top)
        guard = _runner(repo, top, start)
    for mat in bpy.data.materials:
        if mat.use_nodes:
            _relight(mat, ab)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = ab.SUN * math.pi          # Blender's diffuse is albedo x E / pi; Godot's is albedo x E
    sun.data.angle = math.radians(1.0)
    scene.collection.objects.link(sun)
    sx, sy, _z = ab.pol(ab.SUN_BEARING, math.cos(math.radians(ab.SUN_EL)), 0.0)
    sun.rotation_mode = "QUATERNION"
    import mathutils
    sun.rotation_quaternion = mathutils.Vector((sx, sy, math.sin(math.radians(ab.SUN_EL)))).to_track_quat("Z", "Y")
    cam = bpy.data.objects.new("ViewCam", bpy.data.cameras.new("ViewCam"))
    scene.collection.objects.link(cam)
    target = bpy.data.objects.new("ViewAim", None)
    scene.collection.objects.link(target)
    con = cam.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
    cam.data.sensor_fit = "VERTICAL"
    cam.data.clip_start, cam.data.clip_end = 0.1, 3000.0
    scene.camera = cam
    eye = (0.0, 0.0, top[2] + ab.EYE)
    grove = ab.pol(205.0, 62.0, 0.0)
    gz = ab.ground_z(grove[0], grove[1])
    look = ab.pol(262.0, 80.0, 0.0)
    views = (
        ("guard_unscoped", eye, (start[0], start[1], start[2] + 1.0), 100.0, (1600, 900)),
        ("guard_scoped", eye, (start[0], start[1], start[2] + 1.0), 20.0, (1600, 900)),
        ("guard_scoped_mid", eye, (mid[0], mid[1], mid[2] + 1.0), 20.0, (1600, 900)),
        ("runner_eye", (start[0] * 1.03, start[1] * 1.03, start[2] + ab.EYE), (0.0, 0.0, top[2] + 0.9), 100.0, (1600, 900)),
        ("istock_framing", (grove[0], grove[1], gz + 1.5), (look[0], look[1], gz + 9.0), 36.0, (1254, 836)),
        ("stump_close", ab.pol(40.0, 13.0, ab.DECK_Z + ab.EYE), (0.0, 0.0, top[2]), 60.0, (1600, 900)),
        ("guard_down", eye, ab.pol(100.0, 16.0, ab.DECK_Z), 100.0, (1600, 900)),
    )
    only = os.environ.get("ASPENS_ONLY")
    for name, pos, aim, fov, res in views:
        if only and name not in only.split(","):
            continue
        for o in guard:
            o.hide_render = name.startswith("guard")
        cam.location, target.location = pos, aim
        cam.data.angle = math.radians(fov)
        scene.render.resolution_x, scene.render.resolution_y = res
        scene.render.resolution_percentage = 100
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(out, "%s_%s.png" % (ab.NAME, name))
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s" % scene.render.filepath)
