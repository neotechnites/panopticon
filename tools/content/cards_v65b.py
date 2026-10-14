#!/usr/bin/env python3
"""cards_v65b.py: rough_v65b_beats = v65 with the card eye a true circle: the v4 eye un-foreshortened (rim ellipse fitted and
scaled round about its centre), cut with a clean anti-aliased circle, made once as a high-res sprite and downscaled each frame.

  master   build the circular eye sprite -> ~/Desktop/panopticon-renders/logo/eye_circle_master.png
  all      master, v65's frames/cards/encode on it, then check (eye w/h on screen, PSNR vs v65, sheet beside v65)
"""
import io
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

import cards_v65 as C

MASTER = os.path.expanduser("~/Desktop/panopticon-renders/logo/eye_circle_master.png")
SIZE = 1024             # sprite px; the circle's diameter is SIZE - 2 * PAD (>= 4x the largest on-screen eye, ~155 px)
PAD = 16
V65 = os.path.join(C.RENDERS, "rough_v65_beats.mp4")
C.TAG, C.WORK = "rough_v65b_beats", os.path.join(C.RENDERS, "v65b_work")
C.DUMP, C.OUT = os.path.join(C.WORK, "v64_cards"), os.path.join(C.WORK, "v65b_cards")
C.load.__defaults__ = (C.DUMP,)
EYES = {}               # frame -> (cx, cy, diameter) of the eye as placed


def rim_ellipse(mask):
    """Least-squares conic through the mask's outer rim (outermost pixel on 720 rays): centre, semi-axes, axis angle."""
    m = np.asarray(mask) > 0
    ys, xs = np.nonzero(m)
    c0 = xs.mean(), ys.mean()
    pts = []
    for t in np.linspace(0, 2 * np.pi, 720, endpoint=False):
        r = np.arange(0, 400, 0.25)
        x, y = c0[0] + r * np.cos(t), c0[1] + r * np.sin(t)
        ok = (x >= 0) & (y >= 0) & (x < m.shape[1]) & (y < m.shape[0])
        hit = np.nonzero(m[y[ok].astype(int), x[ok].astype(int)])[0]
        if len(hit):
            pts.append((x[ok][hit[-1]] + 0.5, y[ok][hit[-1]] + 0.5))
    x, y = np.array(pts).T
    A = np.c_[x * x, x * y, y * y, x, y]
    a, b, c, d, e = np.linalg.lstsq(A, np.ones_like(x), rcond=None)[0]
    M = np.array([[a, b / 2], [b / 2, c]])
    ctr = np.linalg.solve(2 * M, [-d, -e])
    k = 1 + ctr @ M @ ctr
    w, V = np.linalg.eigh(M / k)
    return ctr, np.sqrt(1 / w), V                              # semi-axes along V's columns


def master():
    art = Image.open(f"{C.LOGO}/render_6_3696x2118_v4.png").convert("RGB")
    ne = Image.open(f"{C.LOGO}/render_6_noeye_3696x2118_v4.png").convert("RGB")
    diff = ImageChops.difference(art, ne).convert("L").point(lambda v: 255 if v > 6 else 0).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    ctr, ax, V = rim_ellipse(diff)
    R = (SIZE - 2 * PAD) / 2
    inset = 2.0                                                # as the figma builder: cut 2 px inside the rim
    S = V @ np.diag(ax - inset) @ V.T / R                      # sprite offset -> source offset (circle -> rim ellipse)
    h = SIZE / 2
    off = ctr - S @ [h, h]
    rgb = art.transform((SIZE, SIZE), Image.AFFINE, (S[0, 0], S[0, 1], off[0], S[1, 0], S[1, 1], off[1]), Image.BICUBIC)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE] + 0.5
    r = np.hypot(xx - h, yy - h)
    alpha = np.clip(R - r + 0.5, 0, 1)                         # analytic anti-aliased edge
    out = rgb.convert("RGBA"); out.putalpha(Image.fromarray((alpha * 255).round().astype(np.uint8)))
    out.save(MASTER)
    print("rim centre", np.round(ctr, 2), "semi-axes", np.round(ax, 2), "ratio", round(ax.max() / ax.min(), 4), "->", MASTER)
    return out


def eye_source():
    """Sprite, its centre, and the circle's diameter (wordmark.place scales that to the O's ink width)."""
    sp = Image.open(MASTER) if os.path.exists(MASTER) else master()
    return sp, (SIZE / 2, SIZE / 2), SIZE - 2 * PAD


_place = C.place
def place(src, c_src, scale, c_dst, size=(1920, 1080)):
    if src.size == (SIZE, SIZE):
        EYES[len(EYES)] = (c_dst[0], c_dst[1], scale * (SIZE - 2 * PAD))
    return _place(src, c_src, scale, c_dst, size)


def grab(src, n):
    return np.asarray(Image.open(io.BytesIO(subprocess.run(
        ["ffmpeg", "-v", "error", "-i", src, "-vf", f"select=eq(n\\,{n}),scale=in_color_matrix=bt709:in_range=tv:out_range=pc,format=rgb24",
         "-frames:v", "1", "-f", "image2pipe", "-vcodec", "png", "-"], capture_output=True, check=True).stdout)).convert("RGB")).astype(float)


def eye_ratio(a, cx, cy, d):
    """On-screen eye width/height in the decoded frame: red-dominant pixels in the O slot, rows filled rim to rim, second moments."""
    x0, y0, s = int(cx - 0.6 * d), int(cy - 0.6 * d), int(1.2 * d)
    w = a[y0:y0 + s, x0:x0 + s]
    pk = np.percentile(w[..., 0], 99.5)                          # thresholds relative to the eye's own level (the end card fades)
    m = (w[..., 0] - w[..., 1] > 0.08 * pk) & (w[..., 0] > 0.13 * pk)
    f = np.zeros_like(m)
    for i, row in enumerate(m):
        xs = np.nonzero(row)[0]
        if len(xs): f[i, xs[0]:xs[-1] + 1] = True
    for j in range(f.shape[1]):                                 # and columns, so the pupil and rim gaps are closed both ways
        ys = np.nonzero(m[:, j])[0]
        if len(ys): f[ys[0]:ys[-1] + 1, j] = True
    ys, xs = np.nonzero(f)
    wd, ht = 4 * xs.std(), 4 * ys.std()
    return wd, ht, wd / ht


def runs(ns):
    out = []
    for n in ns:
        if out and n == out[-1][1] + 1: out[-1][1] = n
        else: out.append([n, n])
    return out


def check():
    out = os.path.join(C.RENDERS, C.TAG + ".mp4")
    log = os.path.join(C.WORK, "psnr_v65b_vs_v65.log")
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", out, "-i", V65, "-lavfi", f"psnr=stats_file={log}", "-f", "null", "-"], check=True)
    rows = []
    for line in open(log):
        d = dict(kv.split(":") for kv in line.split() if ":" in kv)
        rows.append((int(d["n"]) - 1, float(d["psnr_avg"]) if d["psnr_avg"] != "inf" else 99.0))
    card = lambda n: any(a <= n < b for _, (a, b) in C.CARDS)
    changed = [n for n, p in rows if p < 99]
    other = [p for n, p in rows if not card(n)]
    spill = [n for n in changed if not card(n)]
    rep = [f"frames {len(rows)}; frames that differ: {len(changed)}; outside the cards: {len(spill)}"
           + (f" ({', '.join(f'{a}-{b}' for a, b in runs(spill))}, the encoder's lookahead before a card, PSNR >= {min(other):.2f} dB)" if spill else ""),
           "  every other non-card frame is bit-identical to v65"]
    for name, (a, b) in C.CARDS:
        ps = [p for n, p in rows if a <= n < b]
        rep.append(f"  {name} {a}-{b - 1}: PSNR {min(ps):.2f}-{max(ps):.2f} dB")
    eyes = json.load(open(os.path.join(C.WORK, "eyes.json")))
    F = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 26)
    tw, th, M = 960, 540, 40
    picks = [(name, n) for name, (a, b) in C.CARDS if name != "online" for n in (a, (a + b - 1) // 2, b - 1)]
    sheet = Image.new("RGB", (2 * tw + 3 * M + 2 * 400, len(picks) * (th + M) + M), "#1E1A17")
    dr = ImageDraw.Draw(sheet)
    for r, (name, n) in enumerate(picks):
        cx, cy, dd = eyes[str(n)]
        for v, (lab, src) in enumerate(((C.TAG[6:10] + "b", out), ("v65", V65))):
            a = grab(src, n)
            if v == 0:
                wd, ht, q = eye_ratio(a, cx, cy, dd)
                rep.append(f"  eye {name} frame {n}: {wd:.1f} x {ht:.1f} px, w/h {q:.3f} (O ink width {dd:.1f})")
            im = Image.fromarray(a.astype(np.uint8))
            x, y = M + v * (tw + M + 400), M + r * (th + M)
            sheet.paste(im.resize((tw, th), Image.LANCZOS), (x, y))
            z = im.crop((int(cx - 0.75 * dd), int(cy - 0.75 * dd), int(cx + 0.75 * dd), int(cy + 0.75 * dd))).resize((360, 360), Image.LANCZOS)
            sheet.paste(z, (x + tw + 20, y + 90))
            dr.text((x, y - 32), f"{name} card  frame {n}  {'v65b' if v == 0 else 'v65'}", fill="#E6DDCA", font=F)
    p = os.path.join(C.RENDERS, "v65b_proof", "v65b_vs_v65_cards_sheet.png")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    sheet.save(p)
    open(os.path.join(C.WORK, "check_v65b.txt"), "w").write("\n".join(rep) + "\n")
    print("\n".join(rep)); print(p)


def build():
    os.makedirs(C.WORK, exist_ok=True)
    master()
    C.eye_source, C.place = eye_source, place
    C.frames()
    # Map placements to frames: cards() places the eye once per title/end frame, in frame order.
    C.cards()
    ns = [n for name, (a, b) in C.CARDS if name == "title" for n in range(a, b)] + [n for name, (a, b) in C.CARDS if name == "end" for n in range(a, b)]
    assert len(EYES) == len(ns), (len(EYES), len(ns))
    json.dump({n: EYES[i] for i, n in enumerate(ns)}, open(os.path.join(C.WORK, "eyes.json"), "w"))
    C.encode()
    subprocess.run(["rm", "-rf", C.DUMP, os.path.join(C.WORK, "seq0"), os.path.join(C.WORK, "seq1")], check=True)


if __name__ == "__main__":
    {"master": master, "all": lambda: (build(), check()), "check": check}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
