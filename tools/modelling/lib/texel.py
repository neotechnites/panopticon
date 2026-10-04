"""
texel -- one texel density per material class, tiling texture files, and
world-locked UVs, for the map meshes.

A map's material classes are Sheets. Each Sheet wears one tiling PNG from a
home's textures/ (drawn by hand; the build only references it), sampled REPEAT,
its faces projected in world cylindrical coordinates at a fixed metres-per-texel.
So texels are the same size everywhere in a class and the only UV seams are
where the projection axis changes -- a corner, which is a hard edge anyway.

Projection ("cyl"), chosen per face from its normal in the ring's frame:
    |n_z| largest ..... floor/ceiling: u = arc, v = radius
    |n_r| largest ..... wall:          u = arc, v = z
    |n_t| largest ..... side/reveal:   u = radius, v = z
arc = bearing * ref_r, and the sheet's period round the ring is forced to a
whole number of repeats (per_rev), so the ring closes on itself with no seam.
ref_r is a number or a callable of the face centre (a map spanning several
radii picks the region's own), and the per-vertex bearing is unwrapped about
the face centre so a face astride bearing 180 is continuous too.

Other modes: "box" (world x/y/z by the normal's largest axis: flat discs and
small things with no ring to close); for decoration that IS designed to a
face, "fit" (the face fills the sheet 0..1 on both axes), "fit_u" / "fit_v"
(one axis fits, the other is world), "window" (the old per-face random
window, kept only for faces another agent owns), "custom" (the build supplies
per-vertex UVs). A sheet may be wider than tall (width): one bay across, N
courses up, so drawn joints land on the geometry's own lines.

    from texel import Sheet, unwrap, materials, finish
    SHEETS = {"rock": Sheet("rock", ref_r=47.0), ...}
    order = unwrap(ob, classes, SHEETS, seed=SEED)           # UVs, per polygon class
    mats = materials("map_base", SHEETS)                     # <stem>_albedo.png (+ _emissive.png)
    finish(ob, classes, mats)                                # slots + material_index

    python3 tools/modelling/lib/texel.py --selftest
"""

import math
import os
import sys

try:
    import bpy
except ImportError:                  # --check / --selftest on the Mac: no Blender
    bpy = None

# =============================================================================
# TUNABLES
# =============================================================================

MPT = 0.05              # metres per texel: every class on every map, unless the Sheet says otherwise
TILE = 256              # texels per sheet side: TILE * MPT = 12.8 m before the sheet repeats
ROUGHNESS = 0.95
METALLIC = 0.0

TWO_PI = 2.0 * math.pi
EPS = 1e-9


# =============================================================================
# RNG
# =============================================================================

class Rng(object):
    """Deterministic LCG: the "window" mode's per-face offsets."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def n(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def bits(self):
        return self.n() >> 12

    def f(self):
        return self.n() / float(0x7FFFFFFF)

    def sf(self):
        return self.f() * 2.0 - 1.0

    def u(self, a, b):
        return a + (b - a) * self.f()

    def i(self, a, b):
        return a + self.bits() % (b - a + 1)

    def pick(self, seq):
        return seq[self.bits() % len(seq)]


# =============================================================================
# SHEETS
# =============================================================================

class Sheet(object):
    """One material class: a tiling image and how faces project into it.

    name       class name; image stem <map>_<name>
    mpt        metres per texel (the period is size * mpt)
    size       texels per side
    ref_r      cyl mode: radius the arc is measured at -- a number or f(centre) -> r
    phase      (u0, v0) metres subtracted before projection: put a joint on a sill
    mode       "cyl" | "fit" | "fit_u" | "fit_v" | "window" | "custom"
    stem       image stem when the class wears another model's texture (default <map>_<name>)
    mpt_u      metres per texel across, when one drawing spans another model's repeat
    tint       linear RGB multiplied over the albedo (glTF baseColorFactor): one drawing, another palette
    glow       False: never bind an emissive image, though the stem has one (another class's glow)
    region     (u0, v0, u1, v1) of a shared image this class lives in; an axis narrower than the
               image is wrapped per face (see to_region), a full one still repeats
    canvas     (w, h) of that whole image
    local      a face that straddles a repeat is moved whole into the region (no world phase)
    rect       (u0, v0, u1, v1): the projected UVs squeezed into this part of the image (an atlas cell)
    glow_stem  emissive image stem when the albedo file is shared and only this class glows
    turn       u and v swapped after projection: an upright drawing laid along a band
    """

    def __init__(self, name, mpt=MPT, size=TILE, ref_r=None, phase=(0.0, 0.0),
                 mode="cyl", roughness=ROUGHNESS, metallic=METALLIC, cull=True,
                 width=None, stem=None, mpt_u=None, tint=None, glow=True,
                 region=None, canvas=None, local=False, rect=None, glow_stem=None, turn=False):
        self.name = name
        self.turn = turn
        self.glow = glow
        self.glow_stem = glow_stem
        self.region = region
        self.canvas = canvas
        self.local = local
        self.rect = rect
        self.tint = tint
        self.stem = stem
        self.mpt = mpt
        self.mpt_u = mpt_u or mpt
        self.size = size
        self.width = width or size          # non-square sheets: width x size
        self.ref_r = ref_r
        self.phase = phase
        self.mode = mode
        self.roughness = roughness
        self.metallic = metallic
        self.cull = cull
        self._per_rev = {}
        if mode == "cyl" and ref_r is None:
            raise ValueError("Sheet %s: cyl mode needs ref_r" % name)
        if mode not in ("cyl", "box", "fit", "fit_u", "fit_v", "window", "custom"):
            raise ValueError("Sheet %s: unknown mode %s" % (name, mode))

    @property
    def metres(self):
        """The sheet's period in metres up (v): size * mpt."""
        return self.size * self.mpt

    @property
    def metres_u(self):
        """The sheet's period in metres across (u): width * mpt_u. A sheet
        wider than tall can hold one bay across and N courses up."""
        return self.width * self.mpt_u

    def px(self, metres):
        """A metre pitch in texels."""
        return int(round(metres / self.mpt))

    def ring(self, centre):
        """(ref_r, period_u) for a face: the period round the ring at ref_r is
        the nearest whole division of the circumference, so the last repeat
        meets the first. Cached per distinct ref_r."""
        ref = self.ref_r(centre) if callable(self.ref_r) else self.ref_r
        key = round(ref, 6)
        if key not in self._per_rev:
            n = max(1, int(round(TWO_PI * ref / self.metres_u)))
            self._per_rev[key] = (ref, TWO_PI * ref / n, n)
        return self._per_rev[key]

    def per_rev(self):
        """{ref_r: (period_u, repeats)} seen so far: the report's numbers."""
        return {k: (v[1], v[2]) for k, v in self._per_rev.items()}


# =============================================================================
# PROJECTION -- pure functions, testable without Blender
# =============================================================================

def _frame(cos):
    cx = sum(c[0] for c in cos) / len(cos)
    cy = sum(c[1] for c in cos) / len(cos)
    cz = sum(c[2] for c in cos) / len(cos)
    ac = math.atan2(cy, cx)
    return (cx, cy, cz), ac


def axis_of(normal, centre):
    """'floor' | 'wall' | 'side' by the face normal in the ring's frame at its centre."""
    ac = math.atan2(centre[1], centre[0])
    rx, ry = math.cos(ac), math.sin(ac)
    nr = normal[0] * rx + normal[1] * ry
    nt = -normal[0] * ry + normal[1] * rx
    nz = normal[2]
    if abs(nz) >= max(abs(nr), abs(nt)):
        return "floor"
    return "wall" if abs(nr) >= abs(nt) else "side"


def cyl_uv(cos, normal, sheet):
    """UVs (in sheet repeats) for one face's vertices, world-locked."""
    centre, ac = _frame(cos)
    ref, period_u, _n = sheet.ring(centre)
    period_v = sheet.metres
    u0, v0 = sheet.phase
    ax = axis_of(normal, centre)
    out = []
    for co in cos:
        rad = math.hypot(co[0], co[1])
        th = math.atan2(co[1], co[0])
        th = ac + (th - ac + math.pi) % TWO_PI - math.pi        # unwrapped about the face
        arc = th * ref
        if ax == "floor":
            u, v = (arc - u0) / period_u, (rad - v0) / period_v
        elif ax == "wall":
            u, v = (arc - u0) / period_u, (co[2] - v0) / period_v
        else:
            u, v = (rad - u0) / sheet.metres_u, (co[2] - v0) / period_v
        out.append((u, v))
    return out


def box_uv(cos, normal, sheet):
    """World box projection: (x, y) on a floor, (y, z) or (x, z) on a wall by
    the normal's largest axis. For flat discs and small things with no ring
    to close: a square grid stays square everywhere."""
    ax = max(range(3), key=lambda i: abs(normal[i]))
    ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
    u0, v0 = sheet.phase
    return [((co[ii] - u0) / sheet.metres_u, (co[jj] - v0) / sheet.metres) for co in cos]


def face_plane(cos, normal):
    """(along, up) coordinates in the face's own plane: 'up' is world z
    projected into the plane (or radius, for a floor), 'along' is across."""
    centre, ac = _frame(cos)
    ax = axis_of(normal, centre)
    if ax == "floor":
        rc = math.hypot(centre[0], centre[1])
        pts = []
        for co in cos:
            th = math.atan2(co[1], co[0])
            th = ac + (th - ac + math.pi) % TWO_PI - math.pi
            pts.append(((th - ac) * rc, math.hypot(co[0], co[1])))
        return pts
    ex = (-normal[1], normal[0])
    ln = math.hypot(ex[0], ex[1]) or 1.0
    ex = (ex[0] / ln, ex[1] / ln)
    return [(co[0] * ex[0] + co[1] * ex[1], co[2]) for co in cos]


def fit_uv(cos, normal, sheet, fit):
    """'fit': the face fills 0..1 both ways; 'fit_u' / 'fit_v': that axis
    fills, the other is world metres at the sheet's density."""
    pts = face_plane(cos, normal)
    mi = min(p[0] for p in pts)
    mj = min(p[1] for p in pts)
    w = max(p[0] for p in pts) - mi
    h = max(p[1] for p in pts) - mj
    su = 1.0 / max(w, EPS) if fit in ("fit", "fit_u") else 1.0 / sheet.metres_u
    sv = 1.0 / max(h, EPS) if fit in ("fit", "fit_v") else 1.0 / sheet.metres
    return [((p[0] - mi) * su, (p[1] - mj) * sv) for p in pts]


def window_uv(cos, normal, sheet, r):
    """The old per-face random window: a face's own patch of the sheet at
    the sheet's density, random offset and flips. Legacy; faces another agent
    owns keep the look they had."""
    pts = face_plane(cos, normal)
    mi = min(p[0] for p in pts)
    mj = min(p[1] for p in pts)
    w = min((max(p[0] for p in pts) - mi) / sheet.metres_u, 1.0)
    h = min((max(p[1] for p in pts) - mj) / sheet.metres, 1.0)
    ou, ov = r.f() * (1.0 - w), r.f() * (1.0 - h)
    fu = -1.0 if r.i(0, 1) else 1.0
    fv = -1.0 if r.i(0, 1) else 1.0
    out = []
    for p in pts:
        s = min(ou + (p[0] - mi) / sheet.metres_u, 1.0)
        t = min(ov + (p[1] - mj) / sheet.metres, 1.0)
        if fu < 0.0:
            s = 1.0 - s
        if fv < 0.0:
            t = 1.0 - t
        out.append((s, t))
    return out


def to_region(sheet, uvs):
    """UVs in repeats -> the sheet's region of its shared image. On a narrow axis the face
    moves by whole repeats into [0, 1] (or by its own minimum when `local`); returns the
    UVs and whether the face still overflowed."""
    if sheet.region is None:
        return uvs, False
    out = [list(uv) for uv in uvs]
    over = False
    for ax in (0, 1):
        lo, hi = sheet.region[ax], sheet.region[ax + 2]
        if hi - lo >= 1.0 - EPS:
            continue
        mn = min(uv[ax] for uv in uvs)
        mx = max(uv[ax] for uv in uvs)
        k = math.floor(mn + 1e-6)
        if mx - k > 1.0 + 1e-6 and sheet.local:
            k = mn
        over = over or mx - k > 1.0 + 1e-4
        e = 0.05 / float(sheet.canvas[ax])           # a twentieth of a texel inside the edge
        for uv in out:
            uv[ax] = min(max(lo + (uv[ax] - k) * (hi - lo), lo + e), hi - e)
    return [tuple(uv) for uv in out], over


# =============================================================================
# BLENDER SIDE
# =============================================================================

def unwrap(ob, classes, sheets, seed=0, face_uv=None, groups=None, custom=None):
    """Write the UV layer. classes[pi] names the polygon's Sheet (or a key of
    ``custom``: fn(me, uvl, poly) does that class itself). face_uv[pi] maps
    vertex index -> (u, v) for "custom" sheets. groups[pi] (a face id shared
    by a quad's two triangles) keeps a "fit" window whole across a quad."""
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = Rng(0x5EED + seed * 7919 + len(me.polygons))
    face_uv = face_uv or {}
    custom = custom or {}
    fitted = {}
    members = {}
    pending = {}                                    # region classes, placed per face below
    if groups is not None:
        for q, gid in enumerate(groups):
            members.setdefault(gid, []).append(q)
    for pi, poly in enumerate(me.polygons):
        cls = classes[pi]
        if cls in custom:
            custom[cls](me, uvl, poly)
            continue
        sheet = sheets[cls]
        loops = list(poly.loop_indices)
        cos = [tuple(me.vertices[me.loops[li].vertex_index].co) for li in loops]
        if sheet.mode == "custom":
            uvs = [face_uv[pi][me.loops[li].vertex_index] for li in loops]
        elif sheet.mode == "cyl":
            uvs = cyl_uv(cos, tuple(poly.normal), sheet)
        elif sheet.mode == "box":
            uvs = box_uv(cos, tuple(poly.normal), sheet)
        elif sheet.mode == "window":
            uvs = window_uv(cos, tuple(poly.normal), sheet, r)
        else:
            gid = groups[pi] if groups is not None else None
            if gid is not None and gid in fitted:
                uvs = [fitted[gid][me.loops[li].vertex_index] for li in loops]
            else:
                if gid is not None:                         # the whole emitted face at once
                    gl = [li for q in members[gid] for li in me.polygons[q].loop_indices]
                    gcos = [tuple(me.vertices[me.loops[li].vertex_index].co) for li in gl]
                    guv = fit_uv(gcos, tuple(poly.normal), sheet, sheet.mode)
                    fitted[gid] = {me.loops[li].vertex_index: uv for li, uv in zip(gl, guv)}
                    uvs = [fitted[gid][me.loops[li].vertex_index] for li in loops]
                else:
                    uvs = fit_uv(cos, tuple(poly.normal), sheet, sheet.mode)
        if sheet.turn:
            uvs = [(v, u) for (u, v) in uvs]
        if sheet.rect is not None:
            a0, b0, a1, b1 = sheet.rect
            uvs = [(a0 + u * (a1 - a0), b0 + v * (b1 - b0)) for (u, v) in uvs]
        if sheet.region is not None:
            key = (cls, groups[pi] if groups is not None else pi)
            pending.setdefault(key, []).append((loops, uvs))
            continue
        for li, uv in zip(loops, uvs):
            uvl.data[li].uv = uv
    over = 0
    for key in sorted(pending, key=str):
        faces = pending[key]
        placed, bad = to_region(sheets[key[0]], [uv for _l, uvs in faces for uv in uvs])
        over += bad
        k = 0
        for loops, uvs in faces:
            for li in loops:
                uvl.data[li].uv = placed[k]
                k += 1
    if over:
        print("TEXEL WARNING %d faces overflow their region" % over)
    return uvl


def image(stem):
    """<home>/textures/<stem>.png, found anywhere in the repo; an error when it is missing."""
    import mdl
    return mdl.texture(stem)


def png_size(stem):
    """(w, h) of <home>/textures/<stem>.png, read from the file."""
    import mdl
    return mdl.texture_size(stem)


_IMAGES = {}         # stem -> (albedo, emissive-or-None): classes sharing a drawing share its images


def images(prefix, sheet):
    """(albedo, emissive-or-None) for a Sheet: <stem>_albedo.png, and <glow>_emissive.png when one exists."""
    import mdl
    stem = sheet.stem or "%s_%s" % (prefix, sheet.name)
    glow = sheet.glow_stem or stem
    if (stem, glow) not in _IMAGES:
        emi = image(glow + "_emissive") if mdl.texture_file(glow + "_emissive.png") else None
        _IMAGES[(stem, glow)] = (image(stem + "_albedo"), emi)
    alb, emi = _IMAGES[(stem, glow)]
    return alb, (emi if sheet.glow else None)


def material(name, albedo, emissive, roughness=ROUGHNESS, metallic=METALLIC, cull=True, tint=None):
    """Principled, nearest-sampled, REPEAT: the same PS1 finish the atlases had.
    tint: a Multiply over the albedo, which the glTF exporter writes as baseColorFactor."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    pairs = [(albedo, "Base Color", 260)]
    if emissive is not None:
        pairs.append((emissive, "Emission Color", -220))
    for img, socket, y in pairs:
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.interpolation = "Closest"
        node.extension = "REPEAT"
        node.location = (-460, y)
        out = node.outputs["Color"]
        if tint is not None and socket == "Base Color":
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = (tint[0], tint[1], tint[2], 1.0)
            mix.location = (-200, y)
            nt.links.new(out, mix.inputs[6])
            out = mix.outputs[2]
        nt.links.new(out, bsdf.inputs[socket])
    if emissive is None:
        bsdf.inputs["Emission Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Emission Strength"].default_value = 1.0   # exactly 1.0: no KHR warning
    mat.use_backface_culling = cull
    return mat


def materials(prefix, sheets, names=None):
    """{class: material} for every Sheet; names[class] overrides the material name."""
    out = {}
    names = names or {}
    for cls in sorted(sheets):
        sh = sheets[cls]
        alb, emi = images(prefix, sh)
        out[cls] = material(names.get(cls, "%s_%s" % (prefix, cls)), alb, emi,
                            sh.roughness, sh.metallic, sh.cull, sh.tint)
    return out


def finish(ob, classes, mats, flat=True):
    """Material slots in sorted class order, material_index per polygon,
    flat shading, UVs kept. Returns the slot order."""
    me = ob.data
    order = sorted(set(classes))
    me.materials.clear()
    for cls in order:
        me.materials.append(mats[cls])
    slot = {cls: i for i, cls in enumerate(order)}
    for pi, poly in enumerate(me.polygons):
        poly.material_index = slot[classes[pi]]
    if flat:
        try:
            me.shade_flat()
        except Exception:
            for p in me.polygons:
                p.use_smooth = False
    return order


def report(sheets):
    """One line per Sheet: density and ring repeats, for the build log."""
    for cls in sorted(sheets):
        sh = sheets[cls]
        rings = ", ".join("r%.1f: %.3f m x%d" % (k, v[0], v[1]) for k, v in sorted(sh.per_rev().items()))
        print("TEXEL %-10s %dx%d %.4f m/texel period %.2f x %.2f m mode=%s %s"
              % (cls, sh.width, sh.size, sh.mpt, sh.metres_u, sh.metres, sh.mode, rings))


# =============================================================================
# HELL ROCK -- one drawing; rock, shade, carve and ember are colour factors on it
# =============================================================================
# The rock emits nothing: no class binds the tile's emissive image.

HELL_STEM = "hell_rock"
HELL_TINT = {"rock": (1.0, 0.4715, 0.4196), "shade": (0.1159, 0.0847, 0.1299),
             "carve": (0.6409, 1.0, 1.0), "ember": (0.036, 0.0296, 0.0361)}
HELL_ZONES = (((0.0, 0.5, 0.5, 1.0), "rock"), ((0.5, 0.5, 1.0, 1.0), "shade"),
              ((0.5, 0.0, 1.0, 0.5), "carve"), ((0.0, 0.0, 0.5, 0.5), "ember"))   # the old 128 atlas
HELL_ATLAS_UV = 1.25    # an old atlas UV onto the tile: 128 texels at 0.125 m -> 256 at 0.05 m
HELL_NAMES = {"rock": "HellRock", "shade": "HellShade", "carve": "HellCarve", "ember": "HellEmber"}
PROPS_STEM = "hell_props"   # the portal swirl, its own file


def hell_sheet(cls, **kw):
    """A texel Sheet for one hell rock class: the one tile, the class's factor, no emission."""
    return Sheet(cls, stem=HELL_STEM, tint=HELL_TINT[cls], glow=False, **kw)


def hell_atlas_material(roughness=ROUGHNESS, cull=False, name="HellRock"):
    """The one tile for a model once on the old atlas: its class factors ride in the Col attribute (COLOR_0)."""
    sh = hell_sheet("rock", mode="box", roughness=roughness, cull=cull)
    alb, _emi = images("", sh)
    mat = material(name, alb, None, sh.roughness, sh.metallic, sh.cull)
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(tex.outputs["Color"], mix.inputs[6])
    nt.links.new(col.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    mat.diffuse_color = (0.13, 0.04, 0.04, 1.0)
    return mat


def props_image():
    """hell_props_albedo: the portal swirl's own file."""
    return image(PROPS_STEM + "_albedo")


def retile(ob, mat, src=("HellRock",), glow=None):
    """Faces on the old 128 hell atlas move onto the one tile (mat, from hell_atlas_material):
    UVs scaled by HELL_ATLAS_UV, the quadrant's class factor into Col. glow = (zone, material)
    sends that zone's faces onto hell_props, the zone filling it. Returns {class: faces}."""
    me = ob.data
    uvl = me.uv_layers.active.data
    old = list(me.materials)
    base = [m.name.split(".")[0] if m is not None else None for m in old]
    order, keep = [], {}
    for i, (m, b) in enumerate(zip(old, base)):          # the tile takes the first src slot's place
        if b not in src:
            keep[i] = len(order)
            order.append(m)
        elif mat not in order:
            keep[i] = len(order)
            order.append(mat)
        else:
            keep[i] = order.index(mat)
    want, count = {}, {}
    white = (1.0, 1.0, 1.0)
    colour = [white] * len(me.loops)
    for p in me.polygons:
        if base[p.material_index] not in src:
            continue
        loops = list(p.loop_indices)
        uvs = [tuple(uvl[li].uv) for li in loops]
        if glow is not None:
            u0, v0, u1, v1 = glow[0]
            if all(u0 - EPS <= u <= u1 + EPS and v0 - EPS <= v <= v1 + EPS for u, v in uvs):
                for li, (u, v) in zip(loops, uvs):
                    uvl[li].uv = ((u - u0) / (u1 - u0), (v - v0) / (v1 - v0))
                want[p.index] = "glow"
                count["glow"] = count.get("glow", 0) + 1
                continue
        cu = sum(u for u, _v in uvs) / len(uvs)
        cv = sum(v for _u, v in uvs) / len(uvs)
        cls = next((c for z, c in HELL_ZONES if z[0] <= cu <= z[2] and z[1] <= cv <= z[3]), "rock")
        for li, (u, v) in zip(loops, uvs):
            uvl[li].uv = (u * HELL_ATLAS_UV, v * HELL_ATLAS_UV)
            colour[li] = HELL_TINT[cls]
        want[p.index] = "rock"
        count[cls] = count.get(cls, 0) + 1
    slot = {"rock": order.index(mat)}
    if "glow" in count:
        slot["glow"] = len(order)
        order.append(glow[1])
    idx = [keep[p.material_index] if p.index not in want else slot[want[p.index]] for p in me.polygons]
    me.materials.clear()
    for m in order:
        me.materials.append(m)
    for p, i in zip(me.polygons, idx):
        p.material_index = i
    for m in old:
        if m is not None and m is not mat and m.name.split(".")[0] in src and m.users == 0:
            bpy.data.materials.remove(m)
    mat.name = src[0]
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    attr.data.foreach_set("color", [v for c in colour for v in (c[0], c[1], c[2], 1.0)])
    print("MDL STATS %s retiled: %s" % (ob.name, " ".join("%s=%d" % kv for kv in sorted(count.items()))))
    return count


# =============================================================================
# SELFTEST
# =============================================================================

def _selftest():
    sh = Sheet("rock", ref_r=47.0)
    ref, per, n = sh.ring((47.0, 0.0, 0.0))
    assert n == round(TWO_PI * 47.0 / 12.8) and abs(per * n - TWO_PI * 47.0) < 1e-9
    # a wall quad astride bearing 180 (Blender -x): continuous u across the seam
    a = (-47.0 * math.cos(0.02), 47.0 * math.sin(0.02), 23.0)
    b = (-47.0 * math.cos(0.02), -47.0 * math.sin(0.02), 23.0)
    uv = cyl_uv([a, b, (b[0], b[1], 26.0), (a[0], a[1], 26.0)], (1.0, 0.0, 0.0), sh)
    assert abs((uv[1][0] - uv[0][0]) * per - 0.04 * 47.0) < 1e-6, uv   # 1.88 m of arc
    assert abs((uv[3][1] - uv[0][1]) * sh.metres - 3.0) < 1e-6
    # the same vertex reached from the face on the other side of the seam: same texel
    d = (-47.0 * math.cos(0.05), 47.0 * math.sin(0.05), 23.0)
    uv2 = cyl_uv([d, a, (a[0], a[1], 26.0), (d[0], d[1], 26.0)], (1.0, 0.0, 0.0), sh)
    du = (uv2[1][0] - uv[0][0])
    assert abs(du - round(du)) < 1e-6, (uv2[1], uv[0])
    assert axis_of((0.0, 0.0, 1.0), (50.0, 0.0, 0.0)) == "floor"
    assert axis_of((1.0, 0.0, 0.0), (50.0, 0.0, 0.0)) == "wall"
    assert axis_of((0.0, 1.0, 0.0), (50.0, 0.0, 0.0)) == "side"
    f = fit_uv([(50.0, 0.0, 0.0), (50.0, 2.0, 0.0), (50.0, 2.0, 1.0), (50.0, 0.0, 1.0)],
               (1.0, 0.0, 0.0), sh, "fit")
    assert max(p[0] for p in f) == 1.0 and max(p[1] for p in f) == 1.0
    print("TEXEL SELFTEST OK")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
