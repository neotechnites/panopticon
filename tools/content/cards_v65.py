#!/usr/bin/env python3
"""cards_v65.py: rough_v65_beats = v64 with the capsules' close-lettering eye-as-O wordmark on the title and end cards
and Ryan's kerned O as the O of ONLINE (card2). Every other frame and the audio are v64's.

  frames   dump v64's card frames (bt709 tv -> RGB)
  cards    redraw them: old wordmark / old O painted out on the flat card black, the new one drawn at each frame's zoom
  encode   rough_v65_beats.mp4: v64 with the card frames swapped in (libx264 crf 14 as the PC pass), audio copied
  check    per-frame PSNR v65 vs v64 and a sheet of every card's first, middle and last frame
  all      frames, cards, encode, check
"""
import io
import os
import re
import subprocess
import sys

import numpy as np
import resvg_py
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

RENDERS = os.path.expanduser("~/Desktop/panopticon-renders/trailer_reveal")
LOGO = os.path.expanduser("~/Desktop/panopticon-renders/logo/capsule_placeholder")
BASE_MP4 = os.path.join(RENDERS, "rough_v64_beats.mp4")
TAG = "rough_v65_beats"
WORK = os.path.join(RENDERS, "v65_work")
DUMP, OUT = os.path.join(WORK, "v64_cards"), os.path.join(WORK, "v65_cards")
TITLE, ONLINE, END = (331, 497), (497, 662), (2317, 2648)   # card frame ranges (end exclusive), v64 edit
CARDS = (("title", TITLE), ("online", ONLINE), ("end", END))

# Ryan's Figma wordmark exactly as exported (DX 0): PATHS, OBOX, BASE, CREAM from the capsule builder, as build_figma_eye.py loads them.
_s = open(f"{LOGO}/build_capsule_placeholder_medium.py").read().split("caps = [")[0]
_s = _s.replace("HERE = os.path.dirname(os.path.abspath(__file__))", f"HERE = {LOGO!r}").replace("DX = 48.120", "DX = 0.0")
_g = {}
exec(compile(_s, "capsule_medium", "exec"), _g)
PATHS, OBOX, BASE = _g["PATHS"], _g["OBOX"], _g["BASE"]
assert _g["DX"] == 0.0


def rs(svg):
    return Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=svg)))).convert("RGBA")


def glyphs(idx, k, tx, ty, fill, size=(1920, 1080)):
    """Paths ``idx`` with unit (u, v) -> pixel (tx + k u, ty + k v), v = 0 on the baseline."""
    return rs(f'<svg xmlns="http://www.w3.org/2000/svg" width="{size[0]}" height="{size[1]}">'
              f'<g transform="translate({tx:.4f} {ty:.4f}) scale({k:.6f}) translate(0 {-BASE})" fill="{fill}">'
              + "".join(f'<path d="{PATHS[i]}"/>' for i in idx) + "</g></svg>")


def ink(idx, k=0.5):
    """Ink box (u0, v0, u1, v1) of paths ``idx`` in wordmark units, measured at half coverage."""
    a = np.asarray(glyphs(idx, k, 600 * k, 800 * k, "#fff", (int(4400 * k), int(1200 * k))).getchannel("A")) > 127
    ys, xs = np.nonzero(a)
    return xs.min() / k - 600, ys.min() / k - 800, (xs.max() + 1) / k - 600, (ys.max() + 1) / k - 800


def eye_source():
    """The old shot's tower eye (render_6 v4, what set_C_figma_oldshot used) at full res, with the figma builder's ellipse alpha."""
    art = Image.open(f"{LOGO}/render_6_3696x2118_v4.png").convert("RGB")
    ne = Image.open(f"{LOGO}/render_6_noeye_3696x2118_v4.png").convert("RGB")
    bb = ImageChops.difference(art, ne).convert("L").point(lambda v: 255 if v > 6 else 0).filter(ImageFilter.MaxFilter(3)).getbbox()
    m = Image.new("L", art.size, 0)
    ImageDraw.Draw(m).ellipse((bb[0] + 2, bb[1] + 2, bb[2] - 2, bb[3] - 2), fill=255)
    eye = art.convert("RGBA")
    eye.putalpha(m.filter(ImageFilter.GaussianBlur(1.5)))
    P = 24
    eye = eye.crop((bb[0] - P, bb[1] - P, bb[2] + P, bb[3] + P))
    return eye, (P + (bb[2] - bb[0]) / 2, P + (bb[3] - bb[1]) / 2), bb[2] - bb[0]


def place(src, c_src, scale, c_dst, size=(1920, 1080)):
    """``src`` (RGBA) scaled by ``scale`` about ``c_src`` onto ``c_dst``, Lanczos resampled straight from the full-res source."""
    w, h = src.size
    X0, Y0 = int(np.ceil(c_dst[0] - c_src[0] * scale)), int(np.ceil(c_dst[1] - c_src[1] * scale))
    X1, Y1 = int(np.floor(c_dst[0] + (w - c_src[0]) * scale)), int(np.floor(c_dst[1] + (h - c_src[1]) * scale))
    box = tuple(c_src[i % 2] + ((X0, Y0, X1, Y1)[i] - c_dst[i % 2]) / scale for i in range(4))
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(src.resize((X1 - X0, Y1 - Y0), Image.LANCZOS, box=box), (X0, Y0))
    return layer


def load(n, d=DUMP):
    return np.asarray(Image.open(f"{d}/n{n:04d}.png").convert("RGB")).astype(np.float64)


def moments(a, bg, rows=slice(None)):
    m = np.clip(a.max(2)[rows] - bg.max() - 8, 0, None)
    ys, xs = np.indices(m.shape)
    ys = ys + (rows.start or 0)
    W = m.sum()
    cx, cy = (m * xs).sum() / W, (m * ys).sum() / W
    return cx, cy, np.sqrt((m * ((xs - cx) ** 2 + (ys - cy) ** 2)).sum() / W), W


def zoom(frames, ref, rows=slice(None)):
    """Per frame (s, ax, ay) with frame = a + s * ref coords, from intensity moments, smoothed by a cubic fit over the card."""
    bg = np.median(load(ref).reshape(-1, 3), 0)
    mr = moments(load(ref), bg, rows)
    raw = np.array([(lambda m: (m[2] / mr[2], m[0], m[1]))(moments(load(n), bg, rows)) for n in frames])
    t = np.array(frames, float)
    s = np.polyval(np.polyfit(t, raw[:, 0], 3), t)
    cx, cy = np.polyval(np.polyfit(t, raw[:, 1], 3), t), np.polyval(np.polyfit(t, raw[:, 2], 3), t)
    return {n: (s[i], cx[i] - s[i] * mr[0], cy[i] - s[i] * mr[1]) for i, n in enumerate(frames)}


def solid(a, bg, rows=slice(None)):
    """The cards' text colour: median of the solidly inked pixels."""
    m = a.max(2)[rows]
    px = a[rows][m > 0.85 * np.percentile(m[m > bg.max() + 40], 99)]
    return np.median(px, 0)


def hexc(c):
    return "#%02X%02X%02X" % tuple(int(round(min(255, max(0, v)))) for v in c)


def bbox(a, bg, rows=slice(None)):
    """Ink box at half the text level (wordmark extents)."""
    m = a.max(2)[rows] > (bg.max() + solid(a, bg, rows).max()) / 2
    ys, xs = np.nonzero(m)
    y0 = rows.start or 0
    return xs.min(), ys.min() + y0, xs.max() + 1, ys.max() + 1 + y0


def wordmark(k, tx, ty, fill, gain, eye):
    """Letters (every path but the first O) in ``fill``, the eye in the O slot at the O's ink width, times ``gain``."""
    src, c, ew = eye
    ox0, ox1, oy0, oy1 = OBOX
    lay = glyphs([i for i in range(len(PATHS)) if i != 3], k, tx, ty, fill)
    e = place(src, c, k * (ox1 - ox0) / ew, (tx + k * (ox0 + ox1) / 2, ty + k * (oy0 + oy1) / 2))
    if gain < 1:
        r, g, b, al = e.split()
        e = Image.merge("RGBA", [ch.point(lambda v: v * gain) for ch in (r, g, b)] + [al])
    lay.alpha_composite(e)
    return lay


def frames():
    os.makedirs(DUMP, exist_ok=True)
    sel = "+".join(f"between(n\\,{a}\\,{b - 1})" for _, (a, b) in CARDS)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", BASE_MP4, "-vf", f"select='{sel}',scale=in_color_matrix=bt709:in_range=tv:out_range=pc,format=rgb24",
                    "-fps_mode", "passthrough", "-start_number", "0", f"{DUMP}/%04d.png"], check=True)
    ns = [n for _, (a, b) in CARDS for n in range(a, b)]
    for i, n in enumerate(ns):
        os.replace(f"{DUMP}/{i:04d}.png", f"{DUMP}/n{n:04d}.png")
    print(len(ns), "frames ->", DUMP)


def cards():
    os.makedirs(OUT, exist_ok=True)
    eye = eye_source()
    wu0, wv0, wu1, wv1 = ink(range(len(PATHS)))

    # Title: the whole card is the wordmark. New ink box = old ink box (width, centre) on the first frame, then the card's zoom.
    a, b = TITLE
    ref = load(a); bg = np.median(ref.reshape(-1, 3), 0)
    z = zoom(range(a, b), a)
    boxes = []
    for n in range(a, b):
        s, ax, ay = z[n]; x0, y0, x1, y1 = bbox(load(n), bg)
        boxes.append(((x0 - ax) / s, (y0 - ay) / s, (x1 - ax) / s, (y1 - ay) / s))
    x0, y0, x1, y1 = np.mean(boxes, 0)
    k0 = (x1 - x0) / (wu1 - wu0)
    tx0, ty0 = (x0 + x1) / 2 - k0 * (wu0 + wu1) / 2, (y0 + y1) / 2 - k0 * (wv0 + wv1) / 2
    fill = hexc(np.median([solid(load(n), bg) for n in range(a, b, 15)], 0))
    print("title: old ink box", np.round([x0, y0, x1, y1], 1), "k", round(k0, 5), "fill", fill, "zoom", round(z[a][0], 4), "->", round(z[b - 1][0], 4))
    for n in range(a, b):
        s, ax, ay = z[n]
        im = Image.new("RGBA", (1920, 1080), tuple(int(v) for v in bg) + (255,))
        im.alpha_composite(wordmark(k0 * s, ax + s * tx0, ay + s * ty0, fill, 1.0, eye))
        im.convert("RGB").save(f"{OUT}/n{n:04d}.png")

    # End card: static; the wordmark (above the "Wishlist on Steam" line) is replaced, the line and the fade are v64's.
    a, b = END
    ref = load(a); bg = np.median(ref.reshape(-1, 3), 0)
    rows_ink = np.nonzero(ref.max(2).max(1) > bg.max() + 40)[0]
    j = np.argmax(np.diff(rows_ink))
    gap, sub = (rows_ink[j] + 1 + rows_ink[j + 1]) // 2, rows_ink[j + 1]   # mid-gap row; the subtitle's first row
    top = slice(0, int(gap))
    x0, y0, x1, y1 = bbox(ref, bg, top)
    k0 = (x1 - x0) / (wu1 - wu0)
    tx0, ty0 = (x0 + x1) / 2 - k0 * (wu0 + wu1) / 2, (y0 + y1) / 2 - k0 * (wv0 + wv1) / 2
    col = solid(ref, bg, top)
    msk = ref.max(2)[top] > bg.max() + 40
    lvl = ref[top][msk].sum()
    print("end: old ink box", (x0, y0, x1, y1), "erase to row", gap, "subtitle from", sub, "k", round(k0, 5), "fill", hexc(col))
    for n in range(a, b):
        f = load(n)
        g = min(1.0, f[top][msk].sum() / lvl)
        f[top] = bg
        im = Image.fromarray(f.round().astype(np.uint8)).convert("RGBA")
        lay = wordmark(k0, tx0, ty0, hexc(bg + (col - bg) * g), g, eye)
        im.alpha_composite(lay)
        im.convert("RGB").save(f"{OUT}/n{n:04d}.png")
        assert lay.getchannel("A").crop((0, int(sub) - 3, 1920, 1080)).getbbox() is None, "new wordmark reaches the subtitle"

    # ONLINE card (frames/card2.png on the PC: ONLINE / ASYMMETRIC / MULTIPLAYER): the O of ONLINE becomes Ryan's kerned O.
    a, b = ONLINE
    ref = load(a); bg = np.median(ref.reshape(-1, 3), 0)
    m = ref.max(2) > (bg.max() + solid(ref, bg).max()) / 2
    rows_ink = np.nonzero(m.any(1))[0]
    brk = np.nonzero(np.diff(rows_ink) > 4)[0]
    l1 = slice(int(rows_ink[0]), int(rows_ink[brk[0]] + 1))  # the first line, ONLINE
    cols = np.nonzero(m[l1].any(0))[0]
    runs = np.split(cols, np.nonzero(np.diff(cols) > 1)[0] + 1)
    assert len(runs) == 6, f"ONLINE line: {len(runs)} glyph runs"
    tops, bots = [], []
    for r in runs[1:]:                                        # N L I N E: flat cap tops and baselines
        ys = np.nonzero(m[l1, r[0]:r[-1] + 1].any(1))[0] + l1.start
        tops.append(ys[0]); bots.append(ys[-1] + 1)
    cap_top, base = np.median(tops), np.median(bots)
    rt, rb = [], []
    for i in (2, 4, 5, 6, 9):                                 # Ryan's flat-topped caps N P T I N
        u0, v0, u1, v1 = ink([i]); rt.append(v0); rb.append(v1)
    kO = (base - cap_top) / (np.median(rb) - np.median(rt))
    ox0, ox1, oy0, oy1 = OBOX
    o = runs[0]; ocx = (o[0] + o[-1] + 1) / 2
    txO, tyO = ocx - kO * (ox0 + ox1) / 2, base - kO * np.median(rb)
    om = np.zeros(m.shape, bool); om[l1, o[0]:o[-1] + 1] = ref.max(2)[l1, o[0]:o[-1] + 1] > bg.max() + 6
    omask = Image.fromarray((om * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7))
    z = zoom(range(a, b), a)
    fill = hexc(np.median([solid(load(n), bg, l1) for n in range(a, b, 15)], 0))
    print("online: cap", cap_top, "base", base, "old O cols", o[0], o[-1] + 1, "k", round(kO, 5), "fill", fill)
    for n in range(a, b):
        s, ax, ay = z[n]
        f = load(n)
        mk = np.asarray(omask.transform((1920, 1080), Image.AFFINE, (1 / s, 0, -ax / s, 0, 1 / s, -ay / s), Image.BILINEAR)) > 0
        f[mk] = bg
        im = Image.fromarray(f.round().astype(np.uint8)).convert("RGBA")
        im.alpha_composite(glyphs([3], kO * s, ax + s * txO, ay + s * tyO, fill))
        im.convert("RGB").save(f"{OUT}/n{n:04d}.png")
    print("cards ->", OUT)


def encode():
    out = os.path.join(RENDERS, TAG + ".mp4")
    seqs = []
    for i, (a, b) in enumerate(((TITLE[0], ONLINE[1]), END)):
        d = os.path.join(WORK, f"seq{i}")
        os.makedirs(d, exist_ok=True)
        for n in range(a, b):
            p = f"{d}/{n:04d}.png"
            if os.path.lexists(p): os.remove(p)
            os.symlink(f"{OUT}/n{n:04d}.png", p)
        seqs.append((d, a, b))
    rgb2yuv = "scale=in_range=pc:out_color_matrix=bt709:out_range=tv,format=yuv420p,setsar=1"
    fc = (f"[0:v]split=2[s0][s1];[s0]trim=end_frame={TITLE[0]},setpts=PTS-STARTPTS[p0];"
          f"[1:v]{rgb2yuv},setpts=PTS-STARTPTS[p1];"
          f"[s1]trim=start_frame={ONLINE[1]}:end_frame={END[0]},setpts=PTS-STARTPTS[p2];"
          f"[2:v]{rgb2yuv},setpts=PTS-STARTPTS[p3];[p0][p1][p2][p3]concat=n=4:v=1:a=0,fps=60[v]")
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", BASE_MP4]
    for d, a, b in seqs:
        cmd += ["-framerate", "60", "-start_number", str(a), "-i", f"{d}/%04d.png"]
    cmd += ["-filter_complex", fc, "-map", "[v]", "-map", "0:a", "-c:v", "libx264", "-preset", "medium", "-crf", "14", "-pix_fmt", "yuv420p",
            "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "iec61966-2-1", "-color_range", "tv", "-c:a", "copy", "-movflags", "+faststart", out]
    subprocess.run(cmd, check=True)
    print(out)


def check():
    out = os.path.join(RENDERS, TAG + ".mp4")
    log = os.path.join(WORK, "psnr_v65_vs_v64.log")
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", out, "-i", BASE_MP4, "-lavfi", f"psnr=stats_file={log}", "-f", "null", "-"], check=True)
    rows = []
    for line in open(log):
        d = dict(kv.split(":") for kv in line.split() if ":" in kv)
        rows.append((int(d["n"]) - 1, float(d["psnr_avg"]) if d["psnr_avg"] != "inf" else 99.0))
    card = lambda n: any(a <= n < b for _, (a, b) in CARDS)
    other = [p for n, p in rows if not card(n)]
    incard = [p for n, p in rows if card(n)]
    low = [n for n, p in rows if p < 40]
    rep = [f"frames {len(rows)} (v64 {int(subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v', '-show_entries', 'stream=nb_frames', '-of', 'csv=p=0', BASE_MP4], capture_output=True, text=True).stdout)})",
           f"non-card frames: {len(other)}, PSNR min {min(other):.2f} dB, median {np.median(other):.2f} dB (re-encode only)",
           f"card frames: {len(incard)}, PSNR min {min(incard):.2f} dB, median {np.median(incard):.2f} dB",
           f"frames under 40 dB: {len(low)}, all inside the cards: {all(card(n) for n in low)}"
           + (f" ({low[0]}-{low[-1]})" if low else "")]
    for name, (a, b) in CARDS:
        ps = [p for n, p in rows if a <= n < b]
        rep.append(f"  {name} {a}-{b - 1}: PSNR {min(ps):.2f}-{max(ps):.2f} dB")
    open(os.path.join(WORK, "psnr_v65_vs_v64.txt"), "w").write("\n".join(rep) + "\n")
    print("\n".join(rep))
    # Sheet: every card's first, middle and last frame, v65 over v64.
    F = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 26)
    tw, th, M = 960, 540, 40
    sheet = Image.new("RGB", (3 * tw + 4 * M, len(CARDS) * 2 * (th + M) + M), "#1E1A17")
    d = ImageDraw.Draw(sheet)
    for r, (name, (a, b)) in enumerate(CARDS):
        for c, n in enumerate((a, (a + b - 1) // 2, b - 1)):
            for v, (lab, src) in enumerate((("v65", out), ("v64", BASE_MP4))):
                im = Image.open(io.BytesIO(subprocess.run(["ffmpeg", "-v", "error", "-i", src, "-vf", f"select=eq(n\\,{n}),scale=in_color_matrix=bt709:in_range=tv:out_range=pc,format=rgb24",
                                                           "-frames:v", "1", "-f", "image2pipe", "-vcodec", "png", "-"], capture_output=True, check=True).stdout)).resize((tw, th), Image.LANCZOS)
                x, y = M + c * (tw + M), M + (2 * r + v) * (th + M)
                sheet.paste(im, (x, y))
                d.text((x, y - 32), f"{name} card  frame {n}  {lab}", fill="#E6DDCA", font=F)
    p = os.path.join(RENDERS, "v65_proof", "v65_cards_sheet.png")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    sheet.save(p)
    print(p)


if __name__ == "__main__":
    steps = {"frames": frames, "cards": cards, "encode": encode, "check": check}
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "all":
        for f in steps.values(): f()
    else:
        steps.get(arg, lambda: sys.exit(__doc__))()
