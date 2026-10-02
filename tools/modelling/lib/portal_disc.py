"""The finish portal's swirl as portal_build.py lays it: one double-sided sheet, rings in
from a pinned rim, see-through, with a "Wave" UV share for portal_wave.gdshader."""

import math

DISC_RINGS = 6          # rings in from the rim, so the wave has vertices to travel over
DISC_SEGS = 24          # rim vertices: the outline's corners plus points along its edges
WAVE_RAMP = 0.5         # metres in from the rim the wave reaches full height; the rim is pinned
ALPHA = 0.55            # the swirl's see-through, glTF BLEND


def rim(outline):
    """The outline as DISC_SEGS (x, z, k): k is the outline index at a kept corner, else None."""
    cuts = [1] * len(outline)
    seg = lambda i: math.dist(outline[i], outline[(i + 1) % len(outline)]) / cuts[i]
    for _ in range(DISC_SEGS - len(outline)):
        cuts[max(range(len(outline)), key=seg)] += 1
    pts = []
    for i, (ax, az) in enumerate(outline):
        bx, bz = outline[(i + 1) % len(outline)]
        pts += [(ax + (bx - ax) * c / cuts[i], az + (bz - az) * c / cuts[i], None if c else i)
                for c in range(cuts[i])]
    return pts


def sheet(m, rim_ids, rim_xz, centre_z, zone):
    """Rings shrinking from rim_ids (at rim_xz, y = 0) to a centre at (0, 0, centre_z)."""
    want = (0.0, -1.0, 0.0)
    rings = [rim_ids]
    for k in range(1, DISC_RINGS):
        f = 1.0 - k / float(DISC_RINGS)
        rings.append([m.v((x * f, 0.0, centre_z + (z - centre_z) * f)) for (x, z) in rim_xz])
    n = len(rim_ids)
    for a, b in zip(rings, rings[1:]):
        for j in range(n):
            jj = (j + 1) % n
            m.quad(a[j], a[jj], b[jj], b[j], want, zone)
    c = m.v((0.0, 0.0, centre_z))
    for j in range(n):
        m.tri(rings[-1][j], rings[-1][(j + 1) % n], c, want, zone)


def see_through(mat):
    """The swirl's material as portal_build's PortalGlow: ALPHA, blended, both faces, no depth write."""
    mat.node_tree.nodes.get("Principled BSDF").inputs["Alpha"].default_value = ALPHA
    mat.blend_method = "BLEND"
    mat.show_transparent_back = False
    mat.use_backface_culling = False


def wave_uv(ob, mat_name, rim_xz):
    """UV2.x: the wave's share, 0 on the rim (and everything not mat_name), rising WAVE_RAMP in."""
    me = ob.data
    glow = {i for i, mt in enumerate(me.materials) if mt.name.split(".")[0] == mat_name}
    disc = {v for p in me.polygons if p.material_index in glow for v in p.vertices}

    def seg(px, pz, a, b):
        ex, ez = b[0] - a[0], b[1] - a[1]
        t = max(0.0, min(1.0, ((px - a[0]) * ex + (pz - a[1]) * ez) / max(ex * ex + ez * ez, 1e-12)))
        return math.hypot(px - a[0] - t * ex, pz - a[1] - t * ez)

    w = {}
    n = len(rim_xz)
    for v in disc:
        co = me.vertices[v].co
        d = min(seg(co.x, co.z, rim_xz[k], rim_xz[(k + 1) % n]) for k in range(n))
        w[v] = min(1.0, d / WAVE_RAMP)
    uv_name = me.uv_layers[0].name
    layer = me.uv_layers.new(name="Wave")
    layer.data.foreach_set("uv", [c for lp in me.loops for c in (w.get(lp.vertex_index, 0.0), 0.0)])
    me.uv_layers[uv_name].active = True
    me.uv_layers[uv_name].active_render = True
    print("MDL STATS wave disc_verts=%d peak=%.2f" % (len(disc), max(w.values())))
