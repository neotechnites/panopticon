#!/usr/bin/env python3
"""Paints the watching eye's PLACEHOLDER textures and packs them into tower/textures/eye.ase.
Procedural and seeded, no source image. Repaint the slices in Aseprite; rerun this only to start over."""

import math
import os
import random
import subprocess
import sys

import numpy as np
from PIL import Image

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(REPO, "tower", "textures")
ASEPRITE = os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/Aseprite/Aseprite.app/Contents/MacOS/aseprite")

# Every slice is a DISC seen down the gaze axis: centre = the pole, edge of the disc = the part's rim.
# DISC is the disc's diameter as a fraction of the slice; eye_build.py maps UVs with the same number.
DISC = 0.94
SCLERA_PX, IRIS_PX, PUPIL_PX = 128, 64, 32
IRIS_T = 0.387      # iris rim on the sclera disc (its half-angle over 90 degrees)
PUPIL_T = 0.47      # pupil rim on the iris disc
SEED = 7


def _grid(n):
    c = (np.arange(n) + 0.5) / n - 0.5
    x, y = np.meshgrid(c, -c)                     # y up, as the eye is seen
    return np.hypot(x, y) / (0.5 * DISC), np.arctan2(y, x)


def _smooth(a, b, t):
    t = np.clip((t - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _ramp(t, stops):
    """Piecewise-linear colour over t; stops = [(t, (r, g, b)), ...]."""
    ts = [s[0] for s in stops]
    return np.stack([np.interp(t, ts, [s[1][k] for s in stops]) for k in range(3)], axis=-1)


def _value_noise(n, cells, rng):
    g = rng.random((cells + 1, cells + 1))
    return np.asarray(Image.fromarray((g * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC), dtype=float) / 255.0


def _stroke(mask, p0, p1, w0, w1):
    """Soft line from p0 to p1 (pixels), width tapering w0 -> w1, max-blended into mask."""
    n = mask.shape[0]
    yy, xx = np.mgrid[0:n, 0:n]
    d = np.array(p1) - np.array(p0)
    ln = max(1e-6, float(d @ d))
    u = np.clip(((xx + 0.5 - p0[0]) * d[0] + (yy + 0.5 - p0[1]) * d[1]) / ln, 0.0, 1.0)
    dist = np.hypot(xx + 0.5 - (p0[0] + u * d[0]), yy + 0.5 - (p0[1] + u * d[1]))
    np.maximum(mask, np.clip(1.0 - dist / (w0 + (w1 - w0) * u), 0.0, 1.0), out=mask)


def _vein(mask, n, rnd, t, phi, t_end, width, lean=0.0, depth=0):
    """A wandering vein from the rim inward, branching as it thins. `lean` is its sideways drift."""
    r_px = 0.5 * DISC * n
    step = 0.03
    while t > t_end and width > 0.4:
        lean = max(-0.9, min(0.9, 0.8 * lean + rnd.uniform(-0.35, 0.35)))
        t2, phi2 = t - step, phi + lean * step / max(t, 0.3)
        a = (n / 2 + r_px * t * math.cos(phi), n / 2 - r_px * t * math.sin(phi))
        b = (n / 2 + r_px * t2 * math.cos(phi2), n / 2 - r_px * t2 * math.sin(phi2))
        _stroke(mask, a, b, width, width * 0.95)
        if depth < 2 and rnd.random() < 0.2:
            _vein(mask, n, rnd, t2, phi2, t2 - rnd.uniform(0.10, 0.22), width * 0.6,
                  lean + rnd.choice((-1, 1)) * rnd.uniform(0.9, 1.5), depth + 1)
        t, phi, width = t2, phi2, width * 0.95


def _pixel(rgb, colours):
    """Quantise to a small palette, the way a hand-drawn sheet is one."""
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")
    return img.quantize(colours, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")


def sclera():
    n, rng, rnd = SCLERA_PX, np.random.default_rng(SEED), random.Random(SEED)
    t, phi = _grid(n)
    tc = np.clip(t, 0.0, 1.0)
    # wet dark flesh: brightest just outside the iris, falling to near black at the ball's edge
    rgb = _ramp(tc, [(0.0, (24, 4, 5)), (IRIS_T - 0.03, (30, 6, 6)), (IRIS_T + 0.07, (96, 30, 23)),
                     (0.62, (80, 23, 18)), (0.85, (52, 12, 11)), (1.0, (26, 6, 6))])
    mottle = _value_noise(n, 9, rng) - 0.5
    rgb *= (1.0 + 0.30 * mottle)[..., None]
    rgb[..., 1] += 14.0 * (_value_noise(n, 5, rng) - 0.5) * _smooth(IRIS_T, 0.6, tc)

    veins = np.zeros((n, n))
    for k in range(17):
        _vein(veins, n, rnd, 1.02, (k + rnd.uniform(-0.3, 0.3)) * 2.0 * math.pi / 17,
              IRIS_T + rnd.uniform(0.04, 0.22), rnd.uniform(1.4, 2.3))
    veins *= _smooth(IRIS_T + 0.02, IRIS_T + 0.10, tc)
    rgb = rgb * (1.0 - 0.9 * veins[..., None]) + np.array((236, 62, 26)) * 0.9 * veins[..., None]

    # the knot the veins root in: hidden under the iris at the front, the back pole of the ball
    root = np.zeros((n, n))
    for k in range(9):
        a = (k + rnd.uniform(-0.3, 0.3)) * 2.0 * math.pi / 9
        r0, r1 = 0.03 * n, rnd.uniform(0.10, 0.16) * n
        _stroke(root, (n / 2 + r0 * math.cos(a), n / 2 + r0 * math.sin(a)),
                (n / 2 + r1 * math.cos(a + 0.3), n / 2 + r1 * math.sin(a + 0.3)), 1.6, 0.6)
    rgb = rgb * (1.0 - 0.7 * root[..., None]) + np.array((150, 30, 18)) * 0.7 * root[..., None]

    rgb += rng.normal(0.0, 3.0, (n, n, 1))
    return _pixel(rgb, 24)


def _spokes(n, rnd, count, t0, t1, width):
    """`count` thin radial strokes on the iris disc, from about t0 out to a random length under t1."""
    mask, r_px = np.zeros((n, n)), 0.5 * DISC * n
    for k in range(count):
        a = (k + rnd.uniform(-0.35, 0.35)) * 2.0 * math.pi / count
        ta, tb = t0 + rnd.uniform(-0.02, 0.05), rnd.uniform(0.5 * (t0 + t1), t1)
        bend = a + rnd.uniform(-0.05, 0.05)
        _stroke(mask, (n / 2 + r_px * ta * math.cos(a), n / 2 - r_px * ta * math.sin(a)),
                (n / 2 + r_px * tb * math.cos(bend), n / 2 - r_px * tb * math.sin(bend)), width, width * 0.6)
    return mask


def iris():
    n, rng, rnd = IRIS_PX, np.random.default_rng(SEED + 1), random.Random(SEED + 1)
    t, _ = _grid(n)
    tc = np.clip(t, 0.0, 1.0)
    # under the pupil -> hot collarette -> blood red -> the dark limbal ring
    rgb = _ramp(tc, [(0.0, (14, 2, 3)), (PUPIL_T - 0.04, (26, 3, 4)), (PUPIL_T + 0.03, (236, 96, 28)),
                     (0.60, (190, 34, 16)), (0.80, (138, 16, 11)), (0.87, (58, 6, 7)), (1.0, (10, 2, 3))])
    rgb *= (0.85 + 0.3 * _value_noise(n, 7, rng))[..., None]
    bright = _spokes(n, rnd, 30, PUPIL_T, 0.84, 1.05) * (1.0 - _smooth(0.78, 0.9, tc))
    crypt = _spokes(n, rnd, 17, PUPIL_T + 0.06, 0.80, 1.2) * (1.0 - _smooth(0.78, 0.9, tc))
    rgb = rgb * (1.0 - 0.6 * crypt[..., None])
    rgb = rgb * (1.0 - 0.8 * bright[..., None]) + np.array((255, 178, 74)) * 0.8 * bright[..., None]
    albedo = _pixel(rgb, 24)

    # the glow is its own drawing: a saturated ember ring the lane can read, fibres hotter, limbal ring dark
    glow = _ramp(tc, [(0.0, (0, 0, 0)), (PUPIL_T - 0.04, (0, 0, 0)), (PUPIL_T + 0.03, (255, 112, 30)),
                      (0.60, (236, 44, 14)), (0.78, (168, 18, 10)), (0.90, (0, 0, 0)), (1.0, (0, 0, 0))])
    glow *= (1.0 - 0.55 * crypt)[..., None]
    glow = glow * (1.0 - 0.85 * bright[..., None]) + np.array((255, 196, 90)) * 0.85 * bright[..., None]
    emissive = _pixel(glow, 16)
    return albedo, emissive


def pupil():
    n, rng = PUPIL_PX, np.random.default_rng(SEED + 2)
    t, _ = _grid(n)
    tc = np.clip(t, 0.0, 1.0)
    rgb = _ramp(tc, [(0.0, (2, 1, 1)), (0.75, (3, 1, 1)), (1.0, (18, 3, 3))])
    rgb += rng.normal(0.0, 1.0, (n, n, 1))
    return _pixel(rgb, 8)


def main():
    os.makedirs(OUT, exist_ok=True)
    iris_albedo, iris_emissive = iris()
    slices = [("eye_sclera_albedo", sclera()), ("eye_iris_albedo", iris_albedo),
              ("eye_iris_emissive", iris_emissive), ("eye_pupil_albedo", pupil())]
    paths = []
    for name, img in slices:
        paths.append(os.path.join(OUT, name + ".png"))
        img.save(paths[-1])
    sheet = os.path.join(OUT, "eye.ase")
    if "--png-only" in sys.argv:
        return
    lua = os.path.join(REPO, "tools", "textures", "make_sheet.lua")
    subprocess.check_call([ASEPRITE, "-b", "--script-param", "out=" + sheet,
                           "--script-param", "pngs=" + ";".join(paths), "--script", lua])
    # the PNGs the game loads are the sheet's own export, exactly as export_sheets.sh writes them
    subprocess.check_call([ASEPRITE, "-b", sheet, "--split-slices",
                           "--save-as", os.path.join(OUT, "{slice}.png")], stdout=subprocess.DEVNULL)
    print("eye.ase: %s" % ", ".join(name for name, _ in slices))


if __name__ == "__main__":
    main()
