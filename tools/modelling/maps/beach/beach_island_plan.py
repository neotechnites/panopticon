"""
beach_island_plan -- the island the bay is set into, designed top-down at real scale before it is modelled.
Pure Python (the build imports it; `python3 beach_island_plan.py --diagram out.png` draws the plan).

Blender xy in metres, the bay's centre at the origin; +x is the mouth (E), +y the portal side (N).
Heights are metres over the sea. The bay (wall, lane, jetties) is untouched: it is one cove of this island.
"""

import math
import sys

TWO_PI = 2.0 * math.pi
SEA = 22.6                   # WATER_Z

# =============================================================================
# THE COAST -- one closed outline, clockwise from the south jetty root; each point starts a segment of one kind
# =============================================================================

COAST = [
    # east coast south of the bay: the south headland, South Beach's concave sweep, the SE cape
    (-26.0, -78.0, "rock"), (6.0, -104.0, "rock"), (-10.0, -150.0, "rock"), (-40.0, -230.0, "sand"),
    (-80.0, -330.0, "sand"), (-130.0, -430.0, "sand"), (-200.0, -520.0, "rock"), (-300.0, -600.0, "rock"),
    (-440.0, -640.0, "sand"), (-600.0, -620.0, "rock"),
    # the west coast under the massif (unseen from play): sea cliffs
    (-720.0, -560.0, "rock"), (-860.0, -420.0, "cliff"), (-880.0, -240.0, "sand"), (-840.0, -120.0, "sand"),
    (-960.0, -20.0, "cliff"), (-1000.0, 160.0, "cliff"), (-1060.0, 330.0, "cliff"), (-960.0, 440.0, "rock"),
    (-820.0, 520.0, "rock"), (-660.0, 640.0, "sand"), (-480.0, 700.0, "rock"),
    # the north lobe: the north cape, Lookout Point, the north cove behind the north headland
    (-300.0, 660.0, "rock"), (-160.0, 560.0, "sand"), (-80.0, 470.0, "rock"), (-110.0, 380.0, "sand"),
    (-130.0, 280.0, "sand"), (-90.0, 190.0, "sand"), (-30.0, 130.0, "rock"), (6.0, 104.0, "rock"), (-26.0, 78.0, "rock"),
]
BEACH_FLAT = {"sand": 46.0, "rock": 0.0, "cliff": 0.0}    # metres of low backshore behind a sand coast

# =============================================================================
# THE RELIEF -- a spine with one peak, two spurs toward the bay, a broad dome under it all
# =============================================================================

PEAK = (-640.0, 10.0, 340.0, 440.0)   # summit x, y, height, reach: centred behind the bay, a bare crag on a forested cone
SPIRES = ((0.0, 0.0, 1.0, 58.0), (44.0, -30.0, 0.9, 46.0), (-48.0, 26.0, 0.86, 44.0), (22.0, 58.0, 0.78, 38.0),
          (-22.0, -58.0, 0.82, 40.0), (76.0, 22.0, 0.7, 34.0), (-76.0, -18.0, 0.66, 34.0), (10.0, -92.0, 0.6, 30.0))
#   the crag's spires: offset from the summit, share of the crown's height, radius; notches between them
CROWN = (0.66, 150.0, 100.0)           # the crag: share of the height where the cliffs start, radius, where the cliff tops out
RIDGES = (5, 0.3, 0.55)                # radial rock ridges: count, amplitude at the crag, the share of the height they start at
SPINE = [(-560.0, 430.0, 120.0, 150.0), (-600.0, 230.0, 190.0, 170.0), (-640.0, 10.0, 330.0, 150.0),
         (-600.0, -200.0, 200.0, 170.0), (-520.0, -420.0, 110.0, 150.0), (-420.0, -580.0, 40.0, 90.0)]
#   (x, y, height, half width): the massif's ridge line, N-S behind the bay, the peak in its middle
SPUR_N = [(-600.0, 230.0, 190.0, 170.0), (-420.0, 210.0, 105.0, 150.0), (-250.0, 170.0, 56.0, 110.0),
          (-100.0, 120.0, 28.0, 70.0), (0.0, 104.0, 20.0, 40.0)]          # the bay valley's north wall, to the north headland
SPUR_S = [(-600.0, -200.0, 200.0, 170.0), (-420.0, -200.0, 110.0, 150.0), (-250.0, -175.0, 56.0, 110.0),
          (-100.0, -125.0, 28.0, 70.0), (0.0, -104.0, 20.0, 40.0)]        # its south wall, to the south headland
DOME = [(-560.0, 440.0, 50.0, 300.0), (-620.0, 10.0, 80.0, 400.0), (-540.0, -400.0, 50.0, 300.0)]   # the massif's foot
KNOBS = [(-6.0, 104.0, 20.0, 36.0), (-6.0, -104.0, 20.0, 36.0), (-80.0, 470.0, 30.0, 60.0),
         (-300.0, -600.0, 24.0, 60.0), (-480.0, 700.0, 40.0, 80.0), (-900.0, 100.0, 60.0, 110.0)]   # (x, y, height, radius)
PLAIN = (1.9, 0.028, 10.0)             # the coastal flats: height at the coast, rise per metre, flat cap
TREE_LINE = 205.0
ROCK_LINE = 212.0                      # rock from the tree line up: the crag
NOISE = (160.0, 7.0)                   # the cartoon hills' wobble: wavelength, amplitude (grows with height)

# =============================================================================
# LANDMARKS -- few, true scale, where distance makes them read
# =============================================================================

HOTEL = {"x": -252.0, "y": -104.0, "yaw": 40.0, "body": (40.0, 15.0, 13.0), "tower": (9.0, 9.0, 30.0)}
#   on the south spur's inner flank facing NE over the bay; the tower on its north end; the pool terrace in front
VILLAGE = {"x": -256.0, "y": 112.0, "rx": 46.0, "ry": 30.0, "houses": 26}    # a clustered mass on the north spur's
CLOCK_TOWER = {"x": -250.0, "y": 110.0, "w": 7.0, "h": 32.0}               # inner flank, facing SE over the bay
ROAD = [(-276.0, -80.0), (-306.0, -50.0), (-326.0, -14.0), (-328.0, 24.0), (-312.0, 60.0), (-290.0, 90.0),
        (-270.0, 104.0)]              # hotel terrace -> round the valley head on the 30 m contour -> the village square
ROAD_W = 3.0
HORIZON_ISLES = [(352.0, 2900.0, 900.0, 150.0, 3), (28.0, 2750.0, 520.0, 110.0, 2), (300.0, 2950.0, 620.0, 80.0, 2)]
#   (bearing, r, width, height, peaks): on the horizon line inside the sea mesh (3 km), fogged to the horizon band

# =============================================================================
# FIELDS
# =============================================================================

_POLY = []


def h2(i, j, seed):
    n = (i * 374761393 + j * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return (n & 0xFFFFFF) / float(0x1000000)


def vnoise(x, y, seed):
    i, j = math.floor(x), math.floor(y)
    fx, fy = x - i, y - j
    fx, fy = fx * fx * (3.0 - 2.0 * fx), fy * fy * (3.0 - 2.0 * fy)
    a, b, c, d = h2(i, j, seed), h2(i + 1, j, seed), h2(i, j + 1, seed), h2(i + 1, j + 1, seed)
    return 2.0 * (a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy) - 1.0


def fbm(x, y, seed, octaves=3):
    s, amp, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        s += amp * vnoise(x * (1 << o), y * (1 << o), seed + 17 * o)
        tot += amp
        amp *= 0.5
    return s / tot


def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def smooth(t):
    t = clamp(t)
    return t * t * (3.0 - 2.0 * t)


def ramp(x, a, b):
    return smooth((x - a) / (b - a))


def bell(x):
    x = abs(x)
    return 0.0 if x >= 1.0 else (1.0 - x * x) ** 2


def coast_poly():
    """The outline smoothed (Chaikin x3), every point tagged with its segment's kind."""
    if _POLY:
        return _POLY
    pts = [(x, y, k) for x, y, k in COAST]
    for _ in range(3):
        nxt = []
        n = len(pts)
        for i in range(n):
            p, q = pts[i], pts[(i + 1) % n]
            nxt.append((0.75 * p[0] + 0.25 * q[0], 0.75 * p[1] + 0.25 * q[1], p[2]))
            nxt.append((0.25 * p[0] + 0.75 * q[0], 0.25 * p[1] + 0.75 * q[1], p[2]))
        pts = nxt
    _POLY.extend(pts)
    return _POLY


def coast_fields(x, y):
    """(signed metres inside the coast, nearest sand, nearest rock, nearest cliff): unsigned by kind."""
    poly = coast_poly()
    n = len(poly)
    best = 1e18
    kinds = {"sand": 1e18, "rock": 1e18, "cliff": 1e18}
    inside = False
    for i in range(n):
        ax, ay, k = poly[i]
        bx, by, _k = poly[(i + 1) % n]
        if (ay > y) != (by > y):
            if x < ax + (bx - ax) * (y - ay) / (by - ay):
                inside = not inside
        dx, dy = bx - ax, by - ay
        ll = dx * dx + dy * dy
        t = clamp(((x - ax) * dx + (y - ay) * dy) / ll) if ll > 0.0 else 0.0
        px, py = ax + dx * t - x, ay + dy * t - y
        d2 = px * px + py * py
        if d2 < best:
            best = d2
        if d2 < kinds[k]:
            kinds[k] = d2
    d = math.sqrt(best)
    return (d if inside else -d), math.sqrt(kinds["sand"]), math.sqrt(kinds["rock"]), math.sqrt(kinds["cliff"])


def _line_h(line, x, y, power=1.0):
    """A ridge or spur: height and half width interpolated along a polyline, a bell across it."""
    h = 0.0
    for (ax, ay, ha, wa), (bx, by, hb, wb) in zip(line, line[1:]):
        vx, vy = bx - ax, by - ay
        ll = vx * vx + vy * vy
        u = clamp(((x - ax) * vx + (y - ay) * vy) / ll)
        off = math.hypot(x - (ax + vx * u), y - (ay + vy * u))
        w = wa + (wb - wa) * u
        h = max(h, (ha + (hb - ha) * u) * bell(off / w) ** power)
    return h


def peak_h(x, y):
    """The peak: a concave forested cone carrying a bare rocky crag (Maka Wuhu): cliffs up to a crown of spires with
    notches between them, and shallow radial ridges on the skirt."""
    px, py, hh, reach = PEAK
    dx, dy = x - px, y - py
    dist = math.hypot(dx, dy)
    d = dist / reach
    if d >= 1.0:
        return 0.0
    a = math.atan2(dy, dx)
    n, amp, _start = RIDGES
    crest = abs(math.sin(0.5 * n * a + 0.6)) ** 0.5 - 0.5
    share, r_out, r_in = CROWN
    skirt = hh * share * (1.0 - d) ** 1.5 * (1.0 + amp * 0.35 * crest * (1.0 - d))
    spire = 0.0
    for ox, oy, sh, rad in SPIRES:
        e = math.hypot(dx - ox, dy - oy) / rad
        if e < 1.0:
            spire = max(spire, sh * (1.0 - e) ** 0.7)
    crown = hh * (share + (1.0 - share) * (0.3 + 0.7 * spire))
    t = clamp((r_out - dist) / (r_out - r_in))
    mask = 0.5 * t + 0.5 * (math.floor(t * 3.0) + smooth((t * 3.0) % 1.0 * 4.0 - 1.5)) / 3.0   # two ledges in the cliff band
    return skirt + (crown - skirt) * mask


def skeleton_h(x, y):
    h = peak_h(x, y)
    h = max(h, _line_h(SPINE, x, y, 0.8), _line_h(SPUR_N, x, y, 0.9), _line_h(SPUR_S, x, y, 0.9))
    for kx, ky, kh, kr in KNOBS:
        h = max(h, kh * bell(math.hypot(x - kx, y - ky) / kr) ** 0.7)
    return h


def raw_h(x, y, inside):
    """The land before the coast caps and the landmarks' terraces."""
    h0, rise, cap = PLAIN
    plain = h0 + min(rise * max(inside - 8.0, 0.0), cap)
    dome = _line_h(DOME, x, y, 0.6)
    h = max(plain + dome, skeleton_h(x, y))
    h += NOISE[1] * (0.4 + h / 120.0) * fbm(x / NOISE[0], y / NOISE[0], 71, 2) * ramp(inside, 20.0, 60.0)
    return h


def coast_cap(inside, ds, dr, dc):
    """How high the land may stand this close to each kind of coast."""
    cap = 0.075 * min(ds, 16.0) + 0.045 * max(ds - 16.0, 0.0) + 3.0 * max(ds - BEACH_FLAT["sand"], 0.0)
    cap = min(cap, 2.0 + 0.55 * dr + 3.0 * max(dr - 30.0, 0.0))
    cap = min(cap, 1.5 + 2.4 * dc + 3.0 * max(dc - 40.0, 0.0))
    return cap


_PADS = []


def pads():
    """(x, y, r_in, r_out, h) terraces: the hotel's, the clock tower's, each house's (built lazily by the build)."""
    return _PADS


def land_h(x, y, terraces=True):
    """Metres over the sea anywhere on the island (negative at sea)."""
    inside, ds, dr, dc = coast_fields(x, y)
    if inside <= 0.0:
        return max(0.25 * inside, -9.0)
    h = min(raw_h(x, y, inside), coast_cap(inside, ds, dr, dc))
    if terraces:
        for px, py, r_in, r_out, ph in _PADS:
            dd = math.hypot(x - px, y - py)
            if dd < r_out:
                h = ph + (h - ph) * ramp(dd, r_in, r_out)
    return h


def pol(bearing_deg, r):
    a = math.radians(-bearing_deg)
    return r * math.cos(a), r * math.sin(a)


def bearing_of(x, y):
    return (-math.degrees(math.atan2(y, x))) % 360.0


# =============================================================================
# THE DIAGRAM
# =============================================================================

def _skyline(grid, eye, b0, b1, step=0.5):
    """Max elevation angle per bearing bin from `eye` (x, y, z over the sea), over the sampled land."""
    ex, ey, ez = eye
    nb = int((b1 - b0) / step)
    out = [-90.0] * nb
    dist = [0.0] * nb
    for (x, y, h) in grid:
        if h <= 0.0:
            continue
        b = (bearing_of(x - ex, y - ey) - b0) % 360.0
        if b >= b1 - b0:
            continue
        d = math.hypot(x - ex, y - ey)
        if d < 30.0:
            continue
        el = math.degrees(math.atan2(h - ez, d))
        k = int(b / step)
        if el > out[k]:
            out[k], dist[k] = el, d
    return out, dist


def diagram(path):
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 20)
    small = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 15)
    big = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 28)
    S = 0.68                                   # px per metre
    X0, X1, Y0, Y1 = -1100.0, 460.0, -760.0, 800.0
    W, H = int((X1 - X0) * S), int((Y1 - Y0) * S)
    STRIP = 230
    img = Image.new("RGB", (W + 40, H + 2 * STRIP + 170), (14, 70, 110))
    dr = ImageDraw.Draw(img)

    def P(x, y):
        return (20 + (x - X0) * S, 20 + (Y1 - y) * S)

    # the land, hypsometric, 6 m cells
    cell = 6.0
    grid = []
    nx, ny = int((X1 - X0) / cell), int((Y1 - Y0) / cell)
    pix = img.load()
    for j in range(ny):
        y = Y1 - (j + 0.5) * cell
        for i in range(nx):
            x = X0 + (i + 0.5) * cell
            h = land_h(x, y)
            grid.append((x, y, h))
            if h > -0.01 and math.hypot(x, y) < 78.0 and x > -80.0:
                h = 0.3                                            # the bay's sand stands in for the sculpt
            if h <= 0.0:
                c = (40, 150, 170) if h > -3.0 else (22, 105, 140) if h > -8.0 else (14, 70, 110)
            elif h < 2.6 and coast_fields(x, y)[1] < BEACH_FLAT["sand"] + 6.0:
                c = (246, 236, 200)
            elif h < 6.0:
                c = (170, 205, 120)
            elif h < TREE_LINE:
                t = h / TREE_LINE
                c = (int(60 - 20 * t), int(150 - 45 * t), int(55 - 15 * t))
            elif h < ROCK_LINE:
                c = (150, 170, 90)
            else:
                c = (205, 150, 80)
            px0, py0 = P(x - cell / 2, y + cell / 2)
            for yy in range(int(py0), int(py0 + cell * S) + 1):
                for xx in range(int(px0), int(px0 + cell * S) + 1):
                    if 0 <= xx < img.width and 0 <= yy < img.height:
                        pix[xx, yy] = c
    # contours every 25 m (100 m heavier), from the same grid
    hmap = {}
    for (x, y, h) in grid:
        hmap[(round(x, 1), round(y, 1))] = h
    for j in range(ny - 1):
        y = Y1 - (j + 0.5) * cell
        for i in range(nx - 1):
            x = X0 + (i + 0.5) * cell
            h = hmap[(round(x, 1), round(y, 1))]
            hr = hmap[(round(x + cell, 1), round(y, 1))]
            hd = hmap[(round(x, 1), round(y - cell, 1))]
            for lvl in range(25, 400, 25):
                if (h - lvl) * (hr - lvl) < 0.0 or (h - lvl) * (hd - lvl) < 0.0:
                    c = (40, 30, 20) if lvl % 100 == 0 else (70, 60, 40)
                    px0, py0 = P(x, y)
                    dr.point((px0, py0), fill=c)
                    if lvl % 100 == 0:
                        dr.point((px0 + 1, py0), fill=c)
    # the coast line
    poly = coast_poly()
    dr.line([P(x, y) for x, y, _k in poly] + [P(poly[0][0], poly[0][1])], fill=(30, 30, 30), width=2)
    # the spine and spurs
    for line, col in ((SPINE, (120, 60, 20)), (SPUR_N, (120, 60, 20)), (SPUR_S, (120, 60, 20))):
        pts = [P(x, y) for x, y, _h, _w in line]
        for a, b in zip(pts, pts[1:]):
            dr.line([a, b], fill=col, width=3)
    for x, y, h, _w in SPINE[1:-1] + SPUR_N[1:-1] + SPUR_S[1:-1]:
        dr.text((P(x, y)[0] + 4, P(x, y)[1] - 8), "%d" % h, fill=(60, 30, 10), font=small)
    px, py = P(PEAK[0], PEAK[1])
    dr.polygon([(px, py - 14), (px - 12, py + 8), (px + 12, py + 8)], fill=(230, 60, 30), outline=(0, 0, 0))
    dr.text((px + 16, py - 12), "PEAK %d m" % PEAK[2], fill=(0, 0, 0), font=font)
    # the bay as it is: wall arc, lane, jetties, yacht
    wall = [P(*pol(b, 75.0)) for b in range(60, 301, 4)]
    dr.line(wall, fill=(90, 90, 90), width=3)
    lane = [P(*pol(b, 68.5)) for b in range(60, 301, 4)]
    dr.line(lane, fill=(230, 40, 40), width=2)
    for b in (60.0, 300.0):
        hx, hy = pol(b - (8.5 if b == 60.0 else -8.5), 70.5)
        dr.ellipse([P(hx - 7, hy + 7), P(hx + 7, hy - 7)], fill=(120, 120, 120), outline=(0, 0, 0))
    dr.rectangle([P(-10, 4), P(10, -4)], fill=(255, 255, 255), outline=(0, 0, 0))
    dr.text(P(-30, -14), "yacht (guard)", fill=(0, 0, 0), font=small)
    dr.text(P(30, -62), "start", fill=(0, 0, 0), font=small)
    dr.text(P(30, 76), "portal", fill=(0, 0, 0), font=small)
    dr.text(P(-70, -50), "lane", fill=(200, 0, 0), font=small)
    # landmarks
    hx, hy = HOTEL["x"], HOTEL["y"]
    bw, bd, _bh = HOTEL["body"]
    dr.rectangle([P(hx - bd / 2, hy + bw / 2), P(hx + bd / 2, hy - bw / 2)], fill=(255, 255, 255), outline=(0, 0, 0))
    tw = HOTEL["tower"][0]
    dr.rectangle([P(hx - tw / 2, hy + bw / 2 + tw), P(hx + tw / 2, hy + bw / 2)], fill=(255, 230, 200), outline=(0, 0, 0))
    dr.text((P(hx, hy)[0] - 150, P(hx, hy)[1] - 10), "HOTEL 40x15, 4 st + tower 30", fill=(0, 0, 0), font=small)
    vx, vy, vrx, vry = VILLAGE["x"], VILLAGE["y"], VILLAGE["rx"], VILLAGE["ry"]
    dr.ellipse([P(vx - vrx, vy + vry), P(vx + vrx, vy - vry)], outline=(255, 255, 255), width=2)
    for k in range(VILLAGE["houses"]):
        a, rr = h2(k, 3, 5) * TWO_PI, math.sqrt(h2(k, 4, 5))
        qx, qy = P(vx + math.cos(a) * rr * vrx * 0.9, vy + math.sin(a) * rr * vry * 0.9)
        dr.rectangle([qx - 3, qy - 2, qx + 3, qy + 2], fill=(255, 255, 255), outline=(0, 0, 0))
    cx, cy = P(CLOCK_TOWER["x"], CLOCK_TOWER["y"])
    dr.rectangle([cx - 4, cy - 4, cx + 4, cy + 4], fill=(230, 60, 30), outline=(0, 0, 0))
    dr.text((P(vx, vy)[0] + vrx * S + 6, P(vx, vy)[1] - 10), "VILLAGE %d houses, clock tower %d m" % (VILLAGE["houses"], CLOCK_TOWER["h"]), fill=(0, 0, 0), font=small)
    dr.line([P(x, y) for x, y in ROAD], fill=(230, 200, 120), width=3)
    dr.text(P(-330, 150), "road 5% grade,\ncut shelf", fill=(60, 40, 0), font=small)
    # names
    for text, (x, y) in (("SOUTH BEACH", (-100, -330)), ("north cove", (-170, 300)), ("Lookout Point", (-60, 490)),
                         ("south headland", (-5, -125)), ("north headland", (-5, 118)), ("sea cliffs", (-1090, 60)),
                         ("west beach", (-600, -690)), ("SE cape", (-330, -640)), ("north shore", (-700, 680)),
                         ("bay valley", (-200, -20)), ("south flat\n(palm grove)", (-230, -330)), ("north cape", (-520, 740))):
        dr.text(P(x, y), text, fill=(0, 0, 0), font=font)
    # the views
    for (ex, ey), col, name in (((-68.5, 0.0), (255, 90, 90), "runner, lane 180"), ((0.0, 0.0), (255, 255, 120), "guard, yacht")):
        for ang in (180.0 - 65.0, 180.0 + 65.0):
            qx, qy = pol(ang, 900.0)
            dr.line([P(ex, ey), P(ex + qx, ey + qy)], fill=col, width=1)
    # the horizon islands and the sun
    for b, r, w, h, humps in HORIZON_ISLES:
        qx, qy = pol(b, 1.0)
        ax, ay = P(qx * 180.0, qy * 180.0)
        bx, by = P(qx * 240.0, qy * 240.0)
        dr.line([(ax, ay), (bx, by)], fill=(255, 255, 255), width=3)
        dr.text((bx - 40, by - 24), "isle %d km, %dx%d m" % (round(r / 1000.0), w, h), fill=(255, 255, 255), font=small)
    sx, sy = pol(15.0, 1.0)
    dr.line([P(120, 0), P(120 + sx * 90, sy * 90)], fill=(255, 220, 60), width=4)
    dr.text(P(130, 36), "sun, bearing 15, 35 deg up", fill=(255, 220, 60), font=small)
    # scale, north
    dr.line([P(-980, -720), P(-480, -720)], fill=(255, 255, 255), width=4)
    dr.text(P(-980, -700), "500 m", fill=(255, 255, 255), font=font)
    dr.text(P(300, 860), "N = +y (up)\nE = the mouth (right)", fill=(255, 255, 255), font=font)
    dr.text((20, 2), "BEACH ISLAND PLAN  1 px = %.2f m   contours 25 m (100 m heavy)   green = forest, pale = flats/beach, ochre = bare rock" % (1 / S),
            fill=(255, 255, 255), font=small)

    # the two skylines
    def strip(y0, eye, title, screen_deg):
        sk, dist = _skyline(grid, eye, 90.0, 270.0)
        dr.rectangle([20, y0, 20 + W, y0 + STRIP], fill=(150, 200, 240))
        n = len(sk)
        base = y0 + STRIP - 30
        scale = (STRIP - 60) / 40.0                               # 40 deg of elevation
        for k in range(n):
            if sk[k] <= -90.0:
                continue
            xx = 20 + int(W * k / float(n))
            el = max(sk[k], 0.0)
            t = clamp((dist[k] - 150.0) / 900.0)
            c = (int(60 + 100 * t), int(140 + 60 * t), int(60 + 150 * t))
            dr.line([(xx, base), (xx, base - el * scale)], fill=c, width=max(1, int(W / n) + 1))
        dr.line([(20, base), (20 + W, base)], fill=(0, 60, 120), width=2)
        ys = base - screen_deg * scale
        dr.line([(20, ys), (20 + W, ys)], fill=(255, 80, 80), width=1)
        dr.text((26, ys - 18), "palm screen at the wall (%d deg)" % screen_deg, fill=(200, 0, 0), font=small)
        for lab, (lx, ly, lh) in (("hotel", (HOTEL["x"], HOTEL["y"], 13.0)), ("village", (VILLAGE["x"], VILLAGE["y"], 8.0)),
                                  ("peak", (PEAK[0], PEAK[1], 0.0))):
            b = (bearing_of(lx - eye[0], ly - eye[1]) - 90.0) % 360.0
            xx = 20 + int(W * b / 180.0)
            dr.line([(xx, base + 2), (xx, base + 14)], fill=(0, 0, 0), width=2)
            dr.text((xx - 20, base + 14), lab, fill=(0, 0, 0), font=small)
        for deg in (10, 20, 30):
            dr.text((20 + W - 60, base - deg * scale - 8), "%d deg" % deg, fill=(0, 40, 80), font=small)
        dr.text((26, y0 + 4), title, fill=(0, 0, 0), font=font)
        dr.text((26, y0 + 28), "bearings 90 (S, left) .. 180 (W) .. 270 (N, right); colour = distance (dark near, pale far)", fill=(0, 0, 0), font=small)

    strip(H + 40, (-68.5, 0.0, 2.0), "SKYLINE from the runner on the lane at bearing 180 (eye 2.0 m over the sea), looking inland", 22)
    strip(H + 50 + STRIP, (0.0, 0.0, 6.3), "SKYLINE from the guard on the flybridge (eye 6.3 m over the sea)", 4)
    img.save(path)
    print("diagram -> %s  (%d x %d)" % (path, img.width, img.height))


if __name__ == "__main__":
    if "--diagram" in sys.argv:
        diagram(sys.argv[sys.argv.index("--diagram") + 1])
    else:
        pts = ROAD
        length = sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))
        print("road %.0f m, %.1f -> %.1f m: grade %.1f%%" % (length, land_h(*pts[0]), land_h(*pts[-1]), 100.0 * (land_h(*pts[-1]) - land_h(*pts[0])) / length))
        for name, (x, y) in (("wall 180", (-80.0, 0.0)), ("hotel", (HOTEL["x"], HOTEL["y"])), ("village", (VILLAGE["x"], VILLAGE["y"])),
                             ("peak", (PEAK[0], PEAK[1])), ("hump", (-620.0, 40.0)), ("south beach", (-70.0, -300.0))):
            print("%-12s h=%.1f" % (name, land_h(x, y)))
