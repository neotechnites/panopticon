#!/usr/bin/env python3
"""
glb_audit -- prove a built .glb is ONE mesh before it is believed.

A prop in PANOPTICON is a single contiguous mesh. That is not a style
preference: a torch that is five loose shells lights wrong, shades wrong along
the seams that are not seams, and collides wrong once the collider is derived
from it. The failure is silent. Godot imports a five-shell torch without a
single warning, the render looks correct from the three angles the build script
happens to shoot, and the defect is found weeks later as "the lighting is odd
on that one prop" -- which reads as a shader bug and is a modelling bug.

So the contiguity claim has to be measured, not eyeballed, and measured on the
machine where the model is built. This runs on the Mac with no Blender and no
Godot: it opens the .glb container itself and does the arithmetic.

    python3 tools/modelling/lib/glb_audit.py <file.glb> [--json]
                                             [--max-tris N] [--components N]

WHAT IT MEASURES

* components -- connected components of the art geometry after welding
  vertices by position, across every art primitive at once. This is the number
  the docstring above is about. One means one mesh.
* dup_position_verts -- vertices sharing a position inside a single primitive.
  A split-normal or split-UV seam produces these legitimately; a large count on
  a flat-shaded rock means the export doubled the geometry.
* degenerate_tris -- triangles with a repeated vertex after welding, or zero
  area. These are always a defect: they shade as black slivers and they make
  the collision cook unstable.
* loose_verts -- welded vertices no triangle references. Dead weight, and a
  sign that something was deleted by vertices rather than by faces.

ART VERSUS COLLISION

Collision hulls are deliberately several disconnected pieces and must never be
judged by the contiguity rule, so anything whose mesh or node name carries a
Godot collision tag (see COLLISION_TAGS) is audited as a separate population.
Matching is by substring, the same way Godot's own glTF importer decides.

The split is a budget rule too: --max-tris gates the ART count only, because
that is the number a contract's max_tris is written about. Collision triangles
are counted and printed, never charged against the art budget.

EXACTNESS

Positions are pushed through their node transforms first, so two primitives
under different nodes are compared in one space. Welding then snaps to
WELD_QUANTUM. "Exact" to a micrometre rather than to the last float bit is
deliberate: the same seam vertex reached through two different node matrices
can differ in the last bit of a float, and a seam is not broken because of it.

Exits 0 after printing AUDIT OK, or 1 after printing AUDIT FAIL <reason>.
"""

import json
import math
import struct
import sys

# =============================================================================
# TUNABLES
# =============================================================================

# Weld grid, in the model's own units (metres). Two positions closer than this
# are the same vertex. A micrometre is far below anything a PANOPTICON prop
# cares about and far above float round-off through a node matrix.
WELD_QUANTUM = 1e-6

# A triangle whose cross-product magnitude is at or below this has no area.
AREA_EPS = 1e-12

# Godot's glTF importer reads these out of mesh and node names. Substring
# match, as Godot does it -- the tags are suffixes by convention, not by rule.
COLLISION_TAGS = ("-colonly", "-convcol", "-col")

# glTF primitive mode 4 is TRIANGLES. Everything else (points, lines, strips,
# fans) is not geometry this audit knows how to reason about, and a PANOPTICON
# build never emits one, so they are counted and skipped rather than guessed at.
MODE_TRIANGLES = 4


# =============================================================================
# GLB CONTAINER AND ACCESSORS
# =============================================================================

GLB_MAGIC = 0x46546C67  # 'glTF'
CHUNK_JSON = 0x4E4F534A  # 'JSON'
CHUNK_BIN = 0x004E4942  # 'BIN\0'

# componentType -> (struct format character, size in bytes)
COMPONENT_TYPES = {
    5120: ("b", 1),
    5121: ("B", 1),
    5122: ("h", 2),
    5123: ("H", 2),
    5125: ("I", 4),
    5126: ("f", 4),
}

COMPONENT_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def parse_glb(path):
    """Return (gltf_dict, bin_bytes) for a binary glTF 2.0 file."""
    with open(path, "rb") as handle:
        data = handle.read()

    if len(data) < 12:
        raise ValueError("file is too short to be a GLB (need at least 12 bytes)")

    magic, version, total_length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise ValueError("not a GLB file: magic is not 'glTF'")
    if version != 2:
        raise ValueError("unsupported GLB version %d, expected 2" % version)
    # A truncated download is the common failure here, so check the declared
    # length against what we actually read rather than trusting the chunks.
    if total_length > len(data):
        raise ValueError(
            "GLB is truncated: header declares %d bytes, file has %d"
            % (total_length, len(data))
        )

    gltf = None
    bin_bytes = b""
    offset = 12
    while offset + 8 <= total_length:
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        if offset + chunk_length > total_length:
            raise ValueError("GLB chunk at byte %d runs past the end of the file" % (offset - 8))
        chunk = data[offset:offset + chunk_length]
        # Chunks are padded to 4 bytes; the padding is not part of the payload.
        offset += chunk_length + (-chunk_length % 4)

        if chunk_type == CHUNK_JSON:
            if gltf is not None:
                raise ValueError("GLB has more than one JSON chunk")
            try:
                gltf = json.loads(chunk.decode("utf-8"))
            except (UnicodeDecodeError, ValueError) as error:
                raise ValueError("GLB JSON chunk is not valid JSON: %s" % error)
        elif chunk_type == CHUNK_BIN:
            if bin_bytes:
                raise ValueError("GLB has more than one BIN chunk")
            bin_bytes = chunk
        # Unknown chunk types are skipped, as the spec requires.

    if gltf is None:
        raise ValueError("GLB has no JSON chunk")
    if not isinstance(gltf, dict):
        raise ValueError("GLB JSON chunk is not an object")
    return gltf, bin_bytes


def read_accessor(gltf, bin_bytes, index):
    """Return accessor `index` as a list of numbers (SCALAR) or tuples (VECn)."""
    accessors = gltf.get("accessors") or []
    if index < 0 or index >= len(accessors):
        raise ValueError("no accessor at index %d" % index)
    accessor = accessors[index]

    if "sparse" in accessor:
        raise ValueError("accessor %d uses sparse storage, which is not supported" % index)

    type_name = accessor.get("type")
    if type_name not in COMPONENT_COUNTS:
        raise ValueError("accessor %d has unsupported type %r" % (index, type_name))
    component_count = COMPONENT_COUNTS[type_name]

    component_type = accessor.get("componentType")
    if component_type not in COMPONENT_TYPES:
        raise ValueError("accessor %d has unsupported componentType %r" % (index, component_type))
    format_char, component_size = COMPONENT_TYPES[component_type]

    count = accessor.get("count")
    if not isinstance(count, int) or count < 0:
        raise ValueError("accessor %d has a bad count %r" % (index, count))

    element_size = component_size * component_count

    # No bufferView means "all zeros" per the glTF spec.
    if "bufferView" not in accessor:
        if component_count == 1:
            zero = 0.0 if component_type == 5126 else 0
            return [zero] * count
        zero_tuple = tuple([0.0 if component_type == 5126 else 0] * component_count)
        return [zero_tuple] * count

    buffer_views = gltf.get("bufferViews") or []
    view_index = accessor["bufferView"]
    if view_index < 0 or view_index >= len(buffer_views):
        raise ValueError("accessor %d points at missing bufferView %r" % (index, view_index))
    view = buffer_views[view_index]

    if view.get("buffer", 0) != 0:
        raise ValueError("accessor %d uses buffer %r; only the GLB buffer 0 is supported"
                         % (index, view.get("buffer")))
    buffers = gltf.get("buffers") or []
    if not buffers:
        raise ValueError("glTF declares no buffers")
    if "uri" in buffers[0]:
        raise ValueError("buffer 0 has a uri; only GLB-embedded buffers are supported")

    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride") or element_size
    if stride < element_size:
        raise ValueError("accessor %d has byteStride %d smaller than its element size %d"
                         % (index, stride, element_size))

    if count == 0:
        return []

    # Last element only needs element_size bytes, not a full stride.
    needed = start + stride * (count - 1) + element_size
    if needed > len(bin_bytes):
        raise ValueError("accessor %d reads past the end of the BIN chunk (needs %d bytes, have %d)"
                         % (index, needed, len(bin_bytes)))

    total_components = count * component_count

    if stride == element_size:
        # The fast path that matters: one unpack of the whole block. A per-element
        # loop here costs seconds on a multi-megabyte mesh.
        block = bin_bytes[start:start + element_size * count]
        values = struct.unpack("<%d%s" % (total_components, format_char), block)
        if component_count == 1:
            return list(values)
        # zip over N copies of one iterator groups the flat run into tuples in C.
        return list(zip(*([iter(values)] * component_count)))

    # Strided (interleaved) data: only here do we pay for a loop.
    unpack_element = struct.Struct("<%d%s" % (component_count, format_char)).unpack_from
    if component_count == 1:
        return [unpack_element(bin_bytes, start + stride * i)[0] for i in range(count)]
    return [unpack_element(bin_bytes, start + stride * i) for i in range(count)]


# =============================================================================
# NODE TRANSFORMS
#
# Matrices are a flat tuple of 16 floats stored ROW-MAJOR: element (row r,
# column c) is at index r * 4 + c and the translation sits at 3, 7, 11.
# mat_mul(a, b) is the ordinary product a @ b, so b acts on a point first.
# That is what makes glTF's T * R * S mean scale, then rotate, then translate,
# and what makes a world matrix parent_world @ child_local.
# =============================================================================

IDENTITY4 = (
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0,
)


def mat_mul(a, b):
    """Return the matrix product a @ b, both row-major flat tuples of 16."""
    result = [0.0] * 16
    for row in range(4):
        for col in range(4):
            total = 0.0
            for k in range(4):
                total += a[row * 4 + k] * b[k * 4 + col]
            result[row * 4 + col] = total
    return tuple(result)


def _translation_matrix(translation):
    """Row-major translation matrix; offsets go in the last column."""
    x, y, z = translation
    return (
        1.0, 0.0, 0.0, float(x),
        0.0, 1.0, 0.0, float(y),
        0.0, 0.0, 1.0, float(z),
        0.0, 0.0, 0.0, 1.0,
    )


def _rotation_matrix(quaternion):
    """Row-major rotation matrix from a glTF quaternion [x, y, z, w].

    glTF stores the scalar part LAST, unlike most maths texts, so the unpack
    order here is deliberate. The quaternion is normalised first because
    exporters emit values that are only approximately unit length, and an
    unnormalised quaternion silently bakes a scale into the rotation.
    """
    x, y, z, w = (float(v) for v in quaternion)
    length = math.sqrt(x * x + y * y + z * z + w * w)
    if length == 0.0:
        return IDENTITY4
    x, y, z, w = x / length, y / length, z / length, w / length

    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z

    return (
        1.0 - 2.0 * (yy + zz), 2.0 * (xy - wz),       2.0 * (xz + wy),       0.0,
        2.0 * (xy + wz),       1.0 - 2.0 * (xx + zz), 2.0 * (yz - wx),       0.0,
        2.0 * (xz - wy),       2.0 * (yz + wx),       1.0 - 2.0 * (xx + yy), 0.0,
        0.0,                   0.0,                   0.0,                   1.0,
    )


def _scale_matrix(scale):
    """Row-major scale matrix; factors go on the diagonal."""
    x, y, z = scale
    return (
        float(x), 0.0,      0.0,      0.0,
        0.0,      float(y), 0.0,      0.0,
        0.0,      0.0,      float(z), 0.0,
        0.0,      0.0,      0.0,      1.0,
    )


def transpose4(m):
    """Swap rows and columns of a flat 16-float matrix."""
    return tuple(m[col * 4 + row] for row in range(4) for col in range(4))


def node_local_matrix(node):
    """Return the local transform of one glTF node dict, row-major.

    A node carries EITHER an explicit 'matrix' OR any mix of
    translation/rotation/scale; the spec forbids both at once.
    """
    explicit = node.get("matrix")
    if explicit is not None:
        # glTF writes 'matrix' column-major, so transposing gives our row-major
        # storage of the very same transform.
        return transpose4(tuple(float(v) for v in explicit))

    translation = node.get("translation", (0.0, 0.0, 0.0))
    rotation = node.get("rotation", (0.0, 0.0, 0.0, 1.0))
    scale = node.get("scale", (1.0, 1.0, 1.0))

    # T * R * S: read right to left, a point is scaled, then rotated, then moved.
    t_times_r = mat_mul(_translation_matrix(translation), _rotation_matrix(rotation))
    return mat_mul(t_times_r, _scale_matrix(scale))


def node_world_matrices(gltf):
    """Return {node index: world matrix} for every node in the glTF.

    Walks down from the scene roots, then treats any node that no root reached
    as a root of its own, so orphaned nodes still get a world matrix.
    """
    nodes = gltf.get("nodes") or []
    world_matrices = {}

    def walk(node_index, parent_world):
        # Guarding on "already has a world matrix" is what stops a malformed
        # file with a cyclic children list from recursing forever; it also
        # means the first (root-most) path to a node wins.
        if node_index in world_matrices:
            return
        if node_index < 0 or node_index >= len(nodes):
            return
        node = nodes[node_index]
        world = mat_mul(parent_world, node_local_matrix(node))
        world_matrices[node_index] = world
        for child_index in node.get("children", ()):
            walk(child_index, world)

    # Prefer the declared scene, but fall back to every scene so that nodes
    # living in a non-default scene are still resolved.
    scenes = gltf.get("scenes") or []
    default_scene = gltf.get("scene")
    scene_order = []
    if isinstance(default_scene, int) and 0 <= default_scene < len(scenes):
        scene_order.append(scenes[default_scene])
    for index, scene in enumerate(scenes):
        if index != default_scene:
            scene_order.append(scene)

    for scene in scene_order:
        for root_index in scene.get("nodes", ()):
            walk(root_index, IDENTITY4)

    # Anything unreached is its own root.
    for node_index in range(len(nodes)):
        walk(node_index, IDENTITY4)

    return world_matrices


def transform_point(m, p):
    """Apply row-major matrix m to 3-tuple p, treating p as a point (w = 1)."""
    x, y, z = (float(v) for v in p)
    out_x = m[0] * x + m[1] * y + m[2] * z + m[3]
    out_y = m[4] * x + m[5] * y + m[6] * z + m[7]
    out_z = m[8] * x + m[9] * y + m[10] * z + m[11]
    return (out_x, out_y, out_z)


# =============================================================================
# TOPOLOGY
# =============================================================================


def weld_key(p, quantum=WELD_QUANTUM):
    """Snap an (x, y, z) position onto the weld grid and return a hashable key.

    Integers, not rounded floats: float keys would reintroduce exactly the
    representation noise we are trying to erase.

    Caveat worth knowing rather than hiding: grid snapping splits a pair of
    positions that straddle a cell boundary. That needs the true coordinate
    to sit within a last-bit of an exact odd multiple of quantum/2 (e.g.
    0.0000005), which authored geometry never does -- authored values land on
    round numbers, and round numbers sit in the middle of a micrometre cell.
    The alternative (neighbour searching every cell) costs 27x for a case
    that does not occur.
    """
    x, y, z = p
    # floor(v / quantum + 0.5) is round-half-up and behaves the same for
    # negative coordinates as positive ones, so a mirrored part welds to
    # its original.
    return (
        int(math.floor(x / quantum + 0.5)),
        int(math.floor(y / quantum + 0.5)),
        int(math.floor(z / quantum + 0.5)),
    )


def _find(parent, node):
    """Union-find root with path halving (iterative: 200k tris would blow the
    recursion limit, and the flattening keeps repeated lookups near O(1))."""
    while parent[node] != node:
        parent[node] = parent[parent[node]]
        node = parent[node]
    return node


def _union(parent, size, a, b):
    """Merge two sets, smaller tree under larger, so trees stay shallow."""
    root_a = _find(parent, a)
    root_b = _find(parent, b)
    if root_a == root_b:
        return
    if size[root_a] < size[root_b]:
        root_a, root_b = root_b, root_a
    parent[root_b] = root_a
    size[root_a] += size[root_b]


def analyze(prims, quantum=WELD_QUANTUM):
    """Audit a list of (positions, indices) primitives sharing one space.

    positions: list of (x, y, z); indices: flat list of ints, length % 3 == 0.
    Returns the counts documented in the module brief.
    """
    total_tris = 0
    total_verts = 0
    dup_position_verts = 0
    degenerate_tris = 0

    # Global weld key -> compact welded vertex id, shared across ALL prims:
    # that sharing is what lets two separately authored halves show up as one
    # component when their seam rings match exactly.
    key_to_welded_id = {}
    welded_positions = []  # representative position per welded id
    parent = []
    size = []
    used_by_triangle = []  # welded ids referenced by at least one triangle

    for positions, indices in prims:
        total_verts += len(positions)
        total_tris += len(indices) // 3

        # Raw vertex index -> welded id, for this prim only.
        local_welded_ids = []
        keys_in_this_prim = set()
        for p in positions:
            key = weld_key(p, quantum)
            keys_in_this_prim.add(key)
            welded_id = key_to_welded_id.get(key)
            if welded_id is None:
                welded_id = len(welded_positions)
                key_to_welded_id[key] = welded_id
                welded_positions.append(p)
                parent.append(welded_id)
                size.append(1)
                used_by_triangle.append(False)
            local_welded_ids.append(welded_id)

        # Duplicates are counted per prim, because a position repeated inside
        # one prim is a split vertex the exporter made (a UV or normal seam),
        # whereas the same position appearing in two prims is the seam we
        # actually want welded.
        dup_position_verts += len(positions) - len(keys_in_this_prim)

        for t in range(0, len(indices), 3):
            a = local_welded_ids[indices[t]]
            b = local_welded_ids[indices[t + 1]]
            c = local_welded_ids[indices[t + 2]]

            # A degenerate triangle still REFERENCES its vertices and still
            # holds them together in the same shell, so it counts for
            # connectivity and against looseness. It is reported, not ignored.
            used_by_triangle[a] = True
            used_by_triangle[b] = True
            used_by_triangle[c] = True

            if a == b or b == c or a == c:
                degenerate_tris += 1
            elif _triangle_is_zero_area(
                welded_positions[a], welded_positions[b], welded_positions[c]
            ):
                degenerate_tris += 1

            _union(parent, size, a, b)
            _union(parent, size, b, c)

    # Components are counted over welded vertices that a triangle touches.
    # An unreferenced vertex is an export leftover, not a shell, so it is
    # reported as loose instead of inflating the component count.
    roots = set()
    loose_verts = 0
    for welded_id in range(len(welded_positions)):
        if used_by_triangle[welded_id]:
            roots.add(_find(parent, welded_id))
        else:
            loose_verts += 1

    return {
        "tris": total_tris,
        "verts": total_verts,
        "welded_verts": len(welded_positions),
        "dup_position_verts": dup_position_verts,
        "degenerate_tris": degenerate_tris,
        "loose_verts": loose_verts,
        "components": len(roots),
    }


def _triangle_is_zero_area(p0, p1, p2):
    """True when the three welded corners are collinear (or coincident).

    Twice the area is the magnitude of the edge cross product; comparing the
    squared magnitude avoids a sqrt in the inner loop of a 200k-tri mesh.
    """
    ux = p1[0] - p0[0]
    uy = p1[1] - p0[1]
    uz = p1[2] - p0[2]
    vx = p2[0] - p0[0]
    vy = p2[1] - p0[1]
    vz = p2[2] - p0[2]
    cx = uy * vz - uz * vy
    cy = uz * vx - ux * vz
    cz = ux * vy - uy * vx
    cross_magnitude_squared = cx * cx + cy * cy + cz * cz
    return cross_magnitude_squared <= AREA_EPS * AREA_EPS

# =============================================================================
# ART VERSUS COLLISION
# =============================================================================


def is_collision_name(name):
    """True if this mesh or node name carries a Godot collision tag."""
    lowered = (name or "").lower()
    return any(tag in lowered for tag in COLLISION_TAGS)


def collect_primitives(gltf, blob):
    """Pull every triangle primitive out of the file, in one shared space.

    Returns (art, collision, stats). ``art`` and ``collision`` are each a list
    of (positions, indices) ready for analyze(). Geometry is gathered per NODE,
    not per mesh, because a mesh instanced by two nodes really is in the scene
    twice and a contiguity claim about the scene has to see both copies.
    """
    meshes = gltf.get("meshes", [])
    nodes = gltf.get("nodes", [])
    worlds = node_world_matrices(gltf)

    art = []
    collision = []
    skipped_modes = 0
    instanced = set()

    for node_index, node in enumerate(nodes):
        mesh_index = node.get("mesh")
        if mesh_index is None:
            continue
        instanced.add(mesh_index)
        mesh = meshes[mesh_index]
        into = collision if (
            is_collision_name(node.get("name")) or is_collision_name(mesh.get("name"))
        ) else art

        matrix = worlds.get(node_index, IDENTITY4)
        # The identity case is not just faster, it is exact: skipping the
        # multiply means an untransformed mesh welds on the bits it was built
        # with rather than on the bits float arithmetic hands back.
        moved = matrix != IDENTITY4

        for prim in mesh.get("primitives", []):
            if prim.get("mode", MODE_TRIANGLES) != MODE_TRIANGLES:
                skipped_modes += 1
                continue
            attributes = prim.get("attributes", {})
            if "POSITION" not in attributes:
                continue
            positions = read_accessor(gltf, blob, attributes["POSITION"])
            if moved:
                positions = [transform_point(matrix, p) for p in positions]
            if "indices" in prim:
                indices = read_accessor(gltf, blob, prim["indices"])
            else:
                # An unindexed primitive is three-at-a-time in order.
                indices = list(range(len(positions)))
            into.append((positions, indices))

    stats = {
        "meshes": len(meshes),
        "uninstanced_meshes": len(meshes) - len(instanced),
        "skipped_modes": skipped_modes,
    }
    return art, collision, stats


# =============================================================================
# REPORT
# =============================================================================


def audit(path, max_tris=None, want_components=None):
    """Audit one .glb and return the full result dict, including pass/fail."""
    gltf, blob = parse_glb(path)
    art, collision, stats = collect_primitives(gltf, blob)

    art_result = analyze(art)
    col_result = analyze(collision)

    name = path.rsplit("/", 1)[-1]
    result = {
        "file": name,
        "path": path,
        "meshes": stats["meshes"],
        "surfaces": len(art) + len(collision),
        "tris": art_result["tris"] + col_result["tris"],
        "verts": art_result["verts"] + col_result["verts"],
        "uninstanced_meshes": stats["uninstanced_meshes"],
        "skipped_primitives": stats["skipped_modes"],
        "art": art_result,
        "collision": col_result,
    }

    # Order matters: report the defect that makes the model wrong before the
    # one that makes it merely over budget.
    reason = None
    if art_result["degenerate_tris"] > 0:
        reason = "art has %d degenerate triangle(s)" % art_result["degenerate_tris"]
    elif want_components is not None and art_result["components"] != want_components:
        reason = "art components=%d, wanted %d" % (
            art_result["components"], want_components)
    elif max_tris is not None and art_result["tris"] > max_tris:
        # Gated on the ART triangles alone -- the "art tris=" the block prints
        # -- because that is what every contract's max_tris describes. Collision
        # hulls are a purpose-built, separately authored population whose cost
        # is a cook, not a draw; folding them into the art budget silently
        # charges a model for its collider and fails a model that is inside the
        # budget its contract wrote down. The first line still prints tris= as
        # the art+collision total, so both numbers stay readable.
        reason = "art tris=%d over budget %d" % (art_result["tris"], max_tris)

    result["ok"] = reason is None
    result["fail_reason"] = reason
    return result


def format_block(result):
    """The greppable block. One fact per token, never reordered."""
    art = result["art"]
    col = result["collision"]
    lines = [
        "AUDIT file=%s meshes=%d surfaces=%d tris=%d verts=%d" % (
            result["file"], result["meshes"], result["surfaces"],
            result["tris"], result["verts"]),
        "AUDIT art tris=%d components=%d dup_position_verts=%d degenerate_tris=%d loose_verts=%d" % (
            art["tris"], art["components"], art["dup_position_verts"],
            art["degenerate_tris"], art["loose_verts"]),
        "AUDIT collision components=%d tris=%d" % (col["components"], col["tris"]),
    ]
    if result["skipped_primitives"]:
        lines.append("AUDIT note skipped_non_triangle_primitives=%d"
                     % result["skipped_primitives"])
    if result["uninstanced_meshes"]:
        lines.append("AUDIT note meshes_in_file_but_not_in_scene=%d"
                     % result["uninstanced_meshes"])
    return lines


USAGE = """usage: glb_audit.py <file.glb> [--json] [--max-tris N] [--components N]

  --json          print the result as one JSON object instead of the block
  --max-tris N    fail if the ART triangle count exceeds N -- the "art tris="
                  on the second line, collision hulls excluded. This is what a
                  contract's max_tris means; the first line's tris= is the
                  art+collision total and is reported, not gated
  --components N  fail unless the art geometry is exactly N connected pieces;
                  a prop wants --components 1
"""


def main(argv):
    path = None
    as_json = False
    max_tris = None
    want_components = None

    rest = list(argv)
    while rest:
        arg = rest.pop(0)
        if arg == "--json":
            as_json = True
        elif arg in ("-h", "--help"):
            sys.stdout.write(USAGE)
            return 0
        elif arg in ("--max-tris", "--components"):
            if not rest:
                sys.stderr.write("AUDIT FAIL %s needs a number\n" % arg)
                return 1
            try:
                value = int(rest.pop(0))
            except ValueError:
                sys.stderr.write("AUDIT FAIL %s needs a number\n" % arg)
                return 1
            if arg == "--max-tris":
                max_tris = value
            else:
                want_components = value
        elif arg.startswith("-"):
            sys.stderr.write("AUDIT FAIL unknown option %s\n" % arg)
            return 1
        elif path is None:
            path = arg
        else:
            sys.stderr.write("AUDIT FAIL more than one file given\n")
            return 1

    if path is None:
        sys.stderr.write(USAGE)
        return 1

    try:
        result = audit(path, max_tris=max_tris, want_components=want_components)
    except (ValueError, OSError, KeyError, IndexError) as exc:
        # A file that cannot be read is a failed audit, not a traceback: this
        # runs inside the build pipeline and the pipeline reads the exit code.
        sys.stdout.write("AUDIT FAIL cannot read %s: %s\n" % (path, exc))
        return 1

    if as_json:
        sys.stdout.write(json.dumps(result, indent=2, sort_keys=True) + "\n")
    else:
        for line in format_block(result):
            sys.stdout.write(line + "\n")
        if result["ok"]:
            sys.stdout.write("AUDIT OK\n")
        else:
            sys.stdout.write("AUDIT FAIL %s\n" % result["fail_reason"])

    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
