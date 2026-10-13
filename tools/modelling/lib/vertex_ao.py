"""Vertex ambient occlusion baked into COLOR_0: short hemisphere rays from each face corner against
the model itself darken contact edges and cavities; apply() moves class tints into COLOR_0 with it."""
import math

SAMPLES = 32        # rays a corner
DIST = 3.0          # metres a ray looks: contact and cavities, not the far side of the rotunda
FLOOR = 0.45        # a fully closed corner keeps this much light
LIFT = 0.004        # metres off the face before a ray starts


def _dirs(n):
    """n cosine-weighted directions about +Z (a fixed Fibonacci spiral: the same bake every build)."""
    from mathutils import Vector
    out = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(n):
        r = math.sqrt((i + 0.5) / n)
        a = golden * i
        out.append(Vector((r * math.cos(a), r * math.sin(a), math.sqrt(max(0.0, 1.0 - r * r)))))
    return out


def bake(ob, samples=SAMPLES, dist=DIST, floor=FLOOR):
    """{loop index: occlusion} for every face corner of ob, rays against ob's own mesh."""
    from mathutils.bvhtree import BVHTree
    me = ob.data
    mw = ob.matrix_world
    bvh = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    dirs = _dirs(samples)
    occ = {}
    cache = {}
    for p in me.polygons:
        n = (mw.to_3x3() @ p.normal).normalized()
        c = mw @ p.center
        t = n.orthogonal().normalized()
        b = n.cross(t)
        frame = [t * d.x + b * d.y + n * d.z for d in dirs]
        for li in p.loop_indices:
            vi = me.loops[li].vertex_index
            key = (vi, round(n.x, 3), round(n.y, 3), round(n.z, 3))
            if key in cache:
                occ[li] = cache[key]
                continue
            co = mw @ me.vertices[vi].co
            o = co + (c - co) * 0.02 + n * LIFT
            hit = 0.0
            for d in frame:
                loc, _nrm, _idx, d_hit = bvh.ray_cast(o, d, dist)
                if loc is not None:
                    hit += 1.0 - d_hit / dist
            v = 1.0 - (1.0 - floor) * hit / samples
            cache[key] = v
            occ[li] = v
    return occ


def _tint_mix(mat):
    """The Multiply over the albedo (adding one when the class has no tint) and its tint."""
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    link = next((lk for lk in nt.links if lk.to_socket == bsdf.inputs["Base Color"]), None)
    if link is None:
        return None, None
    src = link.from_node
    if src.type == "MIX" and src.blend_type == "MULTIPLY":
        tint = tuple(src.inputs[7].default_value)[:3]
        return src, tint
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(link.from_socket, mix.inputs[6])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    return mix, (1.0, 1.0, 1.0)


def apply(ob, occ, keep=(), only=None):
    """Col = each corner's class tint x its occlusion; keep: white; only: the classes that darken."""
    me = ob.data
    tints = {}
    for i, mat in enumerate(me.materials):
        if mat is None or any(mat.name.endswith("_" + k) or mat.name == k for k in keep):
            tints[i] = None
            continue
        mix, tint = _tint_mix(mat)
        if mix is None:
            tints[i] = None
            continue
        col = mat.node_tree.nodes.new("ShaderNodeVertexColor")
        col.layer_name = "Col"
        mat.node_tree.links.new(col.outputs["Color"], mix.inputs[7])
        tints[i] = tint
    flat = [1.0] * (4 * len(me.loops))
    for p in me.polygons:
        tint = tints.get(p.material_index)
        if tint is None:
            continue
        name = me.materials[p.material_index].name
        dark = only is None or any(name.endswith("_" + c) for c in only)
        for li in p.loop_indices:
            a = occ.get(li, 1.0) if dark else 1.0
            flat[4 * li:4 * li + 3] = [tint[0] * a, tint[1] * a, tint[2] * a]
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    attr.data.foreach_set("color", flat)
    me.color_attributes.active_color_index = 0
    me.color_attributes.render_color_index = 0
    vals = list(occ.values())
    print("MDL STATS vertex_ao %s corners=%d mean=%.3f min=%.3f" % (ob.name, len(vals), sum(vals) / max(1, len(vals)), min(vals) if vals else 1.0))
