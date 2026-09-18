"""
s3_proof -- section S3 ("The Minefield") of map 1, turned into printed evidence.

S3 is a bargain struck with the guard in the tower: crests a runner can put
between himself and the eye, dips whose pad trigger boxes a running body has
to clear, and pads that buy him fourteen metres of ground at the price of
being seen for the whole flight. None of that is visible in a mesh diff, so
this module measures it instead, off the layout the section is built from:

  * cover -- for a standing and for a crouched body in the dead ground behind
    each crest, how many metres of rock stand over the guard's sight line to
    the head, and whether the crest blocks it at all;
  * dips -- the rim-to-rim gap, and by how much the jumping body's feet clear
    the top of the pad's trigger box, over the whole span where the capsule
    overlaps that box;
  * pads -- where each one throws a runner, and what share of the launched
    flight the guard can see him for (it should be all of it);
  * the corridor -- its bearing span, its radii and its length.

The sight lines are raycast, not assumed: the eye-to-target plan segment is
marched a tenth of a metre at a time and tested against the section's own
height field, ``L["height"]``, and against nothing else. The tower, the props
and the neighbouring sections belong to other modules, and letting them into
this test would only paper over a hole in this one. Because the eye is on the
axis, that march also has a closed form at the crest's own radius -- one
straight interpolation, no sampling error -- and ``check`` returns both, so
this module can be reconciled against the layout's own self-proof to the
millimetre instead of to the step.

``stats`` and ``check`` are the whole public surface, and both read one
private ``_measure`` pass, so the log and the returned numbers cannot
disagree. ``stats`` never asserts: a crest that fails to hide a body prints
SEEN and a negative margin, because that is what a build log is for.

FRAME. A game bearing ``b`` and radius ``r`` are the plan point
(gx, gz) = (r cos b, r sin b) -- Godot x and z. Up is Godot y; the deck top is
y = 23.0 and ``L["height"]`` is metres of rock over it, negative in the
hollows. The guard's eye is the world point (0.0, 27.0, 0.0).

HOW THE LAYOUT IS READ.
  * ``cover["top"]`` is metres of crest OVER THE DECK, so the crest's world y
    is 23.0 + top; ``cover["hide_r"]`` is a radius, and the feet there stand
    on rock at 23.0 + height(hide point) -- the hide spots sit in a scoop of
    dead ground, so this is not the deck.
  * ``dip["along"]`` is the rim-to-rim gap in metres and ``dip["depth"]`` is
    the floor below the RIM, not below the deck; the trigger box is TRIGGER_H
    tall with its bottom face on the floor, and it is the PAD's box, not the
    dip's: it runs from DIP_PAD_NEAR to DIP_PAD_NEAR + 2 * PAD_BOX_ALONG from
    rim0, which is the only span the capsule has to clear.
  * ``dip["pad"]`` indexes ``L["pads"]`` and is logged as ``pads[i]``, the raw
    index, so it cannot be misread as a count.
  * ``pad["land"]`` is a plan point, ``(gx, gz)`` or a full ``(gx, gy, gz)``;
    its bearing and radius are derived here. Pad yaws are normalised into
    [0, 360) for the log -- the solver is free to hand back 460 degrees.
"""

import math

# =============================================================================
# TUNABLES
# =============================================================================

DECK_Y = 23.0             # world y of the deck top: L["height"] is metres over this
GUARD_EYE = (0.0, 27.0, 0.0)      # the guard's eye, world (x, y, z), on the axis

SIGHT_STEP = 0.10         # metres between samples along a sight line's plan segment
SIGHT_MISS = 9.0          # a sight line with nothing on it reports -this, metres
FAR = 999.0               # sentinel for a worst-so-far search, metres

BODY_R = 0.40             # capsule radius of a player body, metres
HEAD_STAND = 1.80         # standing head over the feet, metres
HEAD_CROUCH = 1.20        # crouched head over the feet, metres

RUN_SPEED = 11.0          # ground speed, m/s
JUMP_V = 7.0              # jump take-off speed, m/s
GRAVITY = 22.0            # m/s^2

PAD_LAUNCH = 18.0         # pad launch speed, m/s ...
PAD_ANGLE = 45.0          # ... at this angle over the deck, degrees
PAD_FLIGHT = 1.157        # the launched flight, seconds
PAD_APEX = 3.68           # its apex over the take-off, metres
PAD_RANGE = 14.70         # its flat range, metres: the landing is built from this, so
                          # the arc is flown at PAD_RANGE / PAD_FLIGHT and ends on it
PAD_BACK = 1.25           # take-off is the pad centre moved this far back along its facing
ARC_N = 40                # samples along a launched flight
PAD_GROUP = 10            # pads per log line, so the log stays short

TRIGGER_H = 1.00          # pad trigger box height, bottom face on the dip floor
PAD_BOX_ALONG = 1.25      # trigger box half extent along the facing: 2.5 m deep
DIP_PAD_NEAR = 2.00       # the pad's near edge, metres from rim0 along the chord
CLEAR_STEP = 0.02         # step across the box span when testing the jump, metres

FULL_TURN = 360.0         # degrees in a turn
PCT = 100.0               # fractions are logged as percentages


# =============================================================================
# the frame, and the one raycast everything else is measured with
# =============================================================================

def _pol(bearing, radius):
    """A game bearing and radius as the plan point (gx, gz)."""
    a = math.radians(bearing)
    return (radius * math.cos(a), radius * math.sin(a))


def _bearing(gx, gz):
    """The game bearing of a plan point, degrees in 0..360."""
    return math.degrees(math.atan2(gz, gx)) % FULL_TURN


def _facing(yaw):
    """The unit plan vector a pad with this yaw faces."""
    a = math.radians(yaw)
    return (math.cos(a), math.sin(a))


def _plan(p):
    """The plan (gx, gz) of a stored point, be it (gx, gz) or (gx, gy, gz)."""
    return (p[0], p[-1])


def _rock_y(L, gx, gz):
    """World y of the section's rock surface at a plan point."""
    return DECK_Y + L["height"](gx, gz)


def _block(L, target, eye):
    """How far under the section's rock the sight line from the eye to the
    target passes: the largest (surface - line) along it, in metres. Zero or
    less is plain view. Marched on the plan at SIGHT_STEP, both ends open, so
    the rock the target itself stands on is never counted as cover."""
    span = math.hypot(target[0] - eye[0], target[2] - eye[2])
    if span <= SIGHT_STEP:
        return -SIGHT_MISS
    best = -SIGHT_MISS
    for k in range(1, int(span / SIGHT_STEP)):
        f = k * SIGHT_STEP / span
        gx = eye[0] + (target[0] - eye[0]) * f
        gy = eye[1] + (target[1] - eye[1]) * f
        gz = eye[2] + (target[2] - eye[2]) * f
        d = _rock_y(L, gx, gz) - gy
        if d > best:
            best = d
    return best


def _crest_margin(crest_r, crest_top, hide_r, hide_h, head_h, eye):
    """The same margin in closed form, at the crest's own radius: the eye sits
    on the axis, so the sight line is radial and its height at the crest is
    one interpolation. No sampling error, and it is what the layout asserts
    against."""
    head_y = DECK_Y + hide_h + head_h
    line_y = eye[1] + (crest_r / hide_r) * (head_y - eye[1])
    return (DECK_Y + crest_top) - line_y


def _flat_reach():
    """How far a running jump carries on the level, metres."""
    return RUN_SPEED * (JUMP_V + JUMP_V) / GRAVITY


def _jump_rise(s):
    """The feet's rise over the take-off s metres into a level running jump."""
    t = s / RUN_SPEED
    return JUMP_V * t - 0.5 * GRAVITY * t * t


def _arc(L, pad):
    """The launched flight off a pad as ARC_N feet positions (gx, gy, gz),
    from the take-off point PAD_BACK behind the pad centre, standing on
    whatever the height field puts under it."""
    fx, fz = _facing(pad["yaw"])
    cx, cz = _pol(pad["b"], pad["r"])
    ox, oz = cx - PAD_BACK * fx, cz - PAD_BACK * fz
    base = _rock_y(L, ox, oz)
    vy = PAD_LAUNCH * math.sin(math.radians(PAD_ANGLE))
    vx = PAD_RANGE / PAD_FLIGHT
    pts = []
    for k in range(ARC_N):
        t = PAD_FLIGHT * (k + 0.5) / ARC_N
        pts.append((ox + vx * t * fx, base + vy * t - 0.5 * GRAVITY * t * t,
                    oz + vx * t * fz))
    return pts


# =============================================================================
# the measurements
# =============================================================================

def _measure_cover(L, piece, eye):
    """One crest: what it hides, standing and crouched, from the dead ground
    behind it. ``top`` is metres over the deck; the feet are on the rock."""
    b, r, hide_r = piece["b"], piece["r"], piece["hide_r"]
    top = piece["top"]
    hx, hz = _pol(b, hide_r)
    hide_h = L["height"](hx, hz)
    feet = DECK_Y + hide_h
    stand = _block(L, (hx, feet + HEAD_STAND, hz), eye)
    crouch = _block(L, (hx, feet + HEAD_CROUCH, hz), eye)
    return {"b": b, "r": r, "top": top, "crest_y": DECK_Y + top,
            "half_along": piece["half_along"], "half_across": piece["half_across"],
            "hide_r": hide_r, "hide_h": hide_h, "feet_y": feet,
            "stand": stand, "crouch": crouch,
            "stand_blocked": stand > 0.0, "crouch_blocked": crouch > 0.0,
            "crest_stand": _crest_margin(r, top, hide_r, hide_h, HEAD_STAND, eye),
            "crest_crouch": _crest_margin(r, top, hide_r, hide_h, HEAD_CROUCH, eye)}


def _measure_dip(L, dip):
    """One dip: the rim-to-rim gap, and how the jumping body's feet pass over
    the top of its pad's trigger box. ``depth`` is the floor below the RIM,
    the jump starts on rim0, and the only span that matters is the box's."""
    gap = dip["along"]
    depth = dip["depth"]
    x_lo = DIP_PAD_NEAR - BODY_R
    x_hi = DIP_PAD_NEAR + 2.0 * PAD_BOX_ALONG + BODY_R
    worst, at = FAR, x_lo
    for k in range(int(round((x_hi - x_lo) / CLEAR_STEP)) + 1):
        x = x_lo + k * CLEAR_STEP
        feet = depth + _jump_rise(x)
        if feet < worst:
            worst, at = feet, x
    pads = L.get("pads", [])
    idx = int(dip["pad"]) if 0 <= int(dip["pad"]) < len(pads) else -1
    return {"b": dip["b"], "r": dip["r"], "depth": depth, "gap": gap,
            "pad": idx, "feet": worst, "at": at, "margin": worst - TRIGGER_H,
            "box_lo": x_lo, "box_hi": x_hi, "box_top": TRIGGER_H,
            "need": gap, "reach": _flat_reach(),
            "rim0": dip.get("rim0"), "rim1": dip.get("rim1")}


def _measure_launch(L, eye):
    """The launched runner: one pad's arc, sampled, and how much of the
    flight the guard has a clear line to a standing body on it."""
    pads = L.get("pads", [])
    if not pads:
        return None
    pad = pads[0]
    pts = _arc(L, pad)
    seen, peak = 0, -FAR
    for gx, gy, gz in pts:
        if _block(L, (gx, gy + HEAD_STAND, gz), eye) <= 0.0:
            seen += 1
        peak = max(peak, gy - DECK_Y)
    return {"pad": 0, "b": pad["b"], "r": pad["r"], "yaw": pad["yaw"] % FULL_TURN,
            "samples": len(pts), "seen": seen, "seen_frac": seen / float(len(pts)),
            "peak": peak, "apex": PAD_APEX, "range": PAD_RANGE,
            "flight": PAD_FLIGHT}


def _measure_pads(L):
    """Every pad: where it is, where it aims, and where it lands."""
    out = []
    for pad in L.get("pads", []):
        lx, lz = _plan(pad["land"])
        out.append({"b": pad["b"], "r": pad["r"], "yaw": pad["yaw"] % FULL_TURN,
                    "land_b": _bearing(lx, lz), "land_r": math.hypot(lx, lz)})
    return out


def _measure_corridor(L):
    """The corridor: span, radii, station count and length."""
    line = list(L.get("corridor", []))
    if not line:
        return None
    length = 0.0
    for (b0, r0), (b1, r1) in zip(line, line[1:]):
        p, q = _pol(b0, r0), _pol(b1, r1)
        length += math.hypot(q[0] - p[0], q[1] - p[1])
    return {"b0": line[0][0], "b1": line[-1][0], "span": line[-1][0] - line[0][0],
            "r_min": min(r for _b, r in line), "r_max": max(r for _b, r in line),
            "stations": len(line), "length": length}


def _measure(L, eye):
    """Every number the log prints, measured once so the two public
    functions cannot tell different stories."""
    covers = [_measure_cover(L, c, eye) for c in L.get("covers", [])]
    stands = [c["stand"] for c in covers]
    crouches = [c["crouch"] for c in covers]
    return {
        "eye": tuple(eye),
        "ext": tuple(L.get("ext", (0.0, 0.0))),
        "covers": covers,
        "worst_stand": min(stands) if stands else -SIGHT_MISS,
        "worst_crouch": min(crouches) if crouches else -SIGHT_MISS,
        "blocked": sum(1 for c in covers if c["stand_blocked"]),
        "cover_n": len(covers),
        "dips": [_measure_dip(L, d) for d in L.get("dips", [])],
        "launch": _measure_launch(L, eye),
        "pads": _measure_pads(L),
        "corridor": _measure_corridor(L),
        "sight_step": SIGHT_STEP,
        "reach": _flat_reach(),
    }


# =============================================================================
# the log
# =============================================================================

def _verdict(margin):
    """BLOCKED or SEEN, for a sight-line margin in metres."""
    return "BLOCKED" if margin > 0.0 else "SEEN"


def _cover_lines(m):
    lines = []
    for k, c in enumerate(m["covers"]):
        lines.append(
            "MDL STATS s3 cover%d bearing=%.2f r=%.2f crest=+%.2f m over deck "
            "hide_r=%.2f hide_h=%+.2f m: standing head %s by %.3f m | crouched %s by "
            "%.3f m | at crest r %+.3f/%+.3f m"
            % (k + 1, c["b"], c["r"], c["top"], c["hide_r"], c["hide_h"],
               _verdict(c["stand"]), c["stand"], _verdict(c["crouch"]), c["crouch"],
               c["crest_stand"], c["crest_crouch"]))
    lines.append(
        "MDL STATS s3 cover worst standing margin=%.3f m, worst crouched margin=%.3f m; "
        "%d of %d crests blocked (positive is metres of rock over the eye-to-head line)"
        % (m["worst_stand"], m["worst_crouch"], m["blocked"], m["cover_n"]))
    return lines


def _dip_lines(m):
    lines = []
    for k, d in enumerate(m["dips"]):
        lines.append(
            "MDL STATS s3 dip%d bearing=%.2f gap=%.2f m floor=%.2f m holds pads[%d]: "
            "feet over the floor %.3f m at worst (box %.2f..%.2f m), margin=%+.3f m over "
            "the box top; jump needs %.2f m of %.2f m reach"
            % (k + 1, d["b"], d["gap"], -d["depth"], d["pad"], d["feet"],
               d["box_lo"], d["box_hi"], d["margin"], d["need"], d["reach"]))
    return lines


def _launch_lines(m):
    g = m["launch"]
    if g is None:
        return []
    return ["MDL STATS s3 launch pads[%d] bearing=%.2f yaw=%.2f %.1f m/s at %.0f deg "
            "%.3f s range=%.2f m peak=+%.2f m over the deck: body seen for %.0f%% of "
            "the flight (%d of %d samples) -- exposed"
            % (g["pad"], g["b"], g["yaw"], PAD_LAUNCH, PAD_ANGLE, g["flight"],
               g["range"], g["peak"], PCT * g["seen_frac"], g["seen"], g["samples"])]


def _pad_lines(m):
    lines = []
    pads = m["pads"]
    for k in range(0, len(pads), PAD_GROUP):
        grp = pads[k:k + PAD_GROUP]
        lines.append(
            "MDL STATS s3 pads %d-%d b/yaw>land_b land_r=%.1f..%.1f m: %s"
            % (k + 1, k + len(grp), min(p["land_r"] for p in grp),
               max(p["land_r"] for p in grp),
               " ".join("%.0f/%.0f>%.1f" % (p["b"], p["yaw"], p["land_b"]) for p in grp)))
    return lines


def _corridor_lines(m):
    c = m["corridor"]
    if c is None:
        return []
    return ["MDL STATS s3 corridor %.2f..%.2f deg (%.2f deg of the section's %.1f..%.1f) "
            "r=%.2f..%.2f m, %d stations, %.2f m long"
            % (c["b0"], c["b1"], c["span"], m["ext"][0], m["ext"][1],
               c["r_min"], c["r_max"], c["stations"], c["length"])]


def stats(L, eye=GUARD_EYE):
    """Returns a list of one-line strings, each already prefixed
    'MDL STATS s3 ...', ready to print in build order."""
    m = _measure(L, eye)
    return (_cover_lines(m) + _dip_lines(m) + _launch_lines(m)
            + _pad_lines(m) + _corridor_lines(m))


def check(L, eye=GUARD_EYE):
    """Returns a dict of the measured numbers behind those lines."""
    return _measure(L, eye)


# =============================================================================
# the self-test: a synthetic section, so this file proves itself without the
# build. A flat field, two crests with their scoops of dead ground, two pads,
# one dip, whose saucer is NOT sculpted into the field -- the jump is measured
# off dip["depth"], exactly as the layout measures it. s3_minefield is never
# imported here, because this module is only ever
# handed a layout; the numbers below are shaped like the real one's so the two
# self-proofs can be read side by side.
# =============================================================================

DEMO_EXT = (143.0, 202.0)         # the bearings the section owns
DEMO_FIELD = 0.0          # the synthetic pad field is flat: nothing over the deck
DEMO_FLAT_Q = 0.35        # a crest is dead level out to here, of its half extent ...
DEMO_P = 2.0              # ... then falls as cos^this: steep flanks, a flat crown
DEMO_TOP = 2.05           # crest over the deck, metres
DEMO_R = 50.25            # the crests sit at this fixed radius
DEMO_HALF = (1.05, 0.70)  # crest half length along the corridor, half thickness across
DEMO_HIDE_OFF = 1.60      # the hide spot sits this far outward of the crest centre
DEMO_HIDE = (1.40, 0.30)  # the scoop of dead ground behind a crest: radius, depth
DEMO_BEARINGS = (146.5, 159.5)    # the two crests
DEMO_DIP = {"b": 150.8, "r": 52.75, "depth": 0.52, "along": 6.00, "pad": 1}
DEMO_PADS = [(146.0, 52.75, 236.0), (150.8, 52.75, 600.8)]   # bearing, radius, yaw:
                          # the second is deliberately over a turn, to prove the log
                          # normalises it into [0, 360)
DEMO_CORR_N = 8           # corridor stations across the section
DEMO_CORR_R = (52.60, 52.90)      # its radius, wandering between these


def _demo_covers():
    """The synthetic crests, in the layout's own dict shape."""
    return [{"b": b, "r": DEMO_R, "top": DEMO_TOP, "half_along": DEMO_HALF[0],
             "half_across": DEMO_HALF[1], "hide_r": DEMO_R + DEMO_HIDE_OFF}
            for b in DEMO_BEARINGS]


def _demo_crest(piece, gx, gz):
    """A crest's height over the deck at a plan point: flat crown, steep
    flanks, nothing outside its footprint."""
    a = math.radians(piece["b"])
    cx, cz = _pol(piece["b"], piece["r"])
    ex, ez = gx - cx, gz - cz
    across = (ex * math.cos(a) + ez * math.sin(a)) / piece["half_across"]
    along = (-ex * math.sin(a) + ez * math.cos(a)) / piece["half_along"]
    q = math.hypot(along, across)
    if q >= 1.0:
        return 0.0
    if q <= DEMO_FLAT_Q:
        return piece["top"]
    f = (q - DEMO_FLAT_Q) / (1.0 - DEMO_FLAT_Q)
    return piece["top"] * math.cos(0.5 * math.pi * f) ** DEMO_P


def _demo_height(gx, gz):
    """The synthetic height field: a flat field, a scoop of dead ground behind
    each crest, and the crests themselves on top -- so a crest always reaches
    its full height and the hide spot always reads the scoop."""
    h = DEMO_FIELD
    for piece in _demo_covers():
        hx, hz = _pol(piece["b"], piece["hide_r"])
        q = math.hypot(gx - hx, gz - hz) / DEMO_HIDE[0]
        if q < 1.0:
            h = min(h, -DEMO_HIDE[1] * math.cos(0.5 * math.pi * q) ** DEMO_P)
    for piece in _demo_covers():
        crest = _demo_crest(piece, gx, gz)
        if crest > 0.0:
            h = max(h, crest)
    return h


def _demo_pad(bearing, radius, yaw):
    """A pad, with the landing the flat range carries it to."""
    fx, fz = _facing(yaw)
    cx, cz = _pol(bearing, radius)
    ox, oz = cx - PAD_BACK * fx, cz - PAD_BACK * fz
    return {"b": bearing, "r": radius, "yaw": yaw,
            "land": (ox + PAD_RANGE * fx, oz + PAD_RANGE * fz)}


def _demo_dip():
    """The synthetic dip, with rim0 and rim1 as PLAN POINTS on the chord, the
    way the layout stores them."""
    d = dict(DEMO_DIP)
    ux, uz = _facing(d["b"] + 90.0)           # the chord runs tangentially
    cx, cz = _pol(d["b"], d["r"])
    d["rim0"] = (cx - 0.5 * d["along"] * ux, cz - 0.5 * d["along"] * uz)
    d["rim1"] = (cx + 0.5 * d["along"] * ux, cz + 0.5 * d["along"] * uz)
    return d


def _demo_layout():
    """The same shape of dict s3_minefield.layout() returns."""
    line = []
    for k in range(DEMO_CORR_N):
        f = k / float(DEMO_CORR_N - 1)
        b = DEMO_EXT[0] + (DEMO_EXT[1] - DEMO_EXT[0]) * f
        r = DEMO_CORR_R[0] + (DEMO_CORR_R[1] - DEMO_CORR_R[0]) \
            * (0.5 - 0.5 * math.cos(2.0 * math.pi * f))
        line.append((b, r))
    return {"ext": DEMO_EXT, "height": _demo_height, "covers": _demo_covers(),
            "pads": [_demo_pad(*p) for p in DEMO_PADS], "dips": [_demo_dip()],
            "corridor": line}


def _demo_main():
    """Print every line, then the dict behind them, then the line widths."""
    L = _demo_layout()
    lines = stats(L)
    for line in lines:
        print(line)
    m = check(L)
    print("--- check() ---")
    print("eye=%s ext=%s cover_n=%d blocked=%d worst_stand=%.4f worst_crouch=%.4f"
          % (m["eye"], m["ext"], m["cover_n"], m["blocked"],
             m["worst_stand"], m["worst_crouch"]))
    for k, c in enumerate(m["covers"]):
        print("cover%d top=%.2f crest_y=%.2f hide_r=%.2f hide_h=%+.2f feet_y=%.2f "
              "marched %.4f/%.4f (%s/%s) closed form %.4f/%.4f"
              % (k + 1, c["top"], c["crest_y"], c["hide_r"], c["hide_h"], c["feet_y"],
                 c["stand"], c["crouch"], c["stand_blocked"], c["crouch_blocked"],
                 c["crest_stand"], c["crest_crouch"]))
    for k, d in enumerate(m["dips"]):
        print("dip%d gap=%.2f depth=%.2f feet=%.4f at=%.2f box=%.2f..%.2f margin=%.4f "
              "pad=%d rim0=(%.3f, %.3f) rim1=(%.3f, %.3f)"
              % (k + 1, d["gap"], d["depth"], d["feet"], d["at"], d["box_lo"],
                 d["box_hi"], d["margin"], d["pad"], d["rim0"][0], d["rim0"][1],
                 d["rim1"][0], d["rim1"][1]))
    g = m["launch"]
    print("launch pad=%d yaw=%.2f seen=%d/%d frac=%.3f peak=%.3f range=%.2f flight=%.3f"
          % (g["pad"], g["yaw"], g["seen"], g["samples"], g["seen_frac"], g["peak"],
             g["range"], g["flight"]))
    for k, p in enumerate(m["pads"]):
        print("pads[%d] b=%.2f r=%.2f yaw=%.2f land_b=%.3f land_r=%.3f"
              % (k, p["b"], p["r"], p["yaw"], p["land_b"], p["land_r"]))
    c = m["corridor"]
    print("corridor %.2f..%.2f span=%.2f r=%.2f..%.2f stations=%d length=%.3f"
          % (c["b0"], c["b1"], c["span"], c["r_min"], c["r_max"],
             c["stations"], c["length"]))
    print("reach=%.3f m sight_step=%.2f m" % (m["reach"], m["sight_step"]))
    print("--- %d lines, longest %d chars, all ascii=%s ---"
          % (len(lines), max(len(x) for x in lines),
             all(x.isascii() for x in lines)))


if __name__ == "__main__":
    _demo_main()
