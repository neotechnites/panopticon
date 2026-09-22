r"""Make and animate the comment card that opens a short.

Runs anywhere ffmpeg does (the Mac builds and checks it, the PC uses it):

    python3 card.py --selftest <outdir>
    python3 card.py --placeholder <out.png> [w h radius]

A short starts on a comment: a white rounded card that slides in from the
right, sits still while the voice reads it, then slides out to the left. That
is three separate jobs and they are separate here, because each one is reused
on its own:

  placeholder  the card shape with nothing on it -- a white rounded rectangle,
               transparent outside. The card's text is drawn on top of this by
               whoever has the comment (a screenshot dropped in its place, or
               drawtext), so the shape is built once and never carries content.
  shadowed     the card lifted off the video: scaled to its on-screen width
               with a blurred black drop shadow behind it, on a transparent
               canvas with enough margin that the blur is not clipped. The
               canvas IS the thing you overlay, so its size is what comes back.
  overlay_args the motion, as an ffmpeg `overlay=` argument string: x eased in
               and out, y fixed, `enable` gating the card to its own window.
               Nothing is rendered -- the caller drops the string into the
               filtergraph of a pass it was already running, so the card costs
               no extra encode.

No PIL, no numpy: the card's pixels are computed here and handed to ffmpeg as
raw RGBA on stdin, so the corner antialiasing is ours and exact.

The returned overlay string quotes its expressions with single quotes, the way
`drawtext=text='...'` does. ffmpeg parses those quotes itself, so pass the
filtergraph as one subprocess argument and never through a shell.

--selftest writes its work into <outdir> and proves the three fit together: it
overlays a card on a 12 s black 1080x1920 clip and measures the card's left
edge back off the pixels -- one frame, a 1 px row at the card's centre y, the
first lit column of a pgm ffmpeg wrote. The expected columns are even: in
the yuv420 path overlay aligns x to the chroma grid (see overlay_args).
"""
import math
import os
import subprocess
import sys

FF = ["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error"]
_TRANSPARENT = "black@0"


def _run(args, stdin=None):
    r = subprocess.run(args, input=stdin, capture_output=True)
    if r.returncode != 0:
        raise SystemExit("ffmpeg failed: %s\n%s" % (
            " ".join(str(a) for a in args[:12]), r.stderr.decode("utf-8", "replace")[-2000:]))
    return r


def _size(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                          "-show_entries", "stream=width,height", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip().split(",")
    return int(out[0]), int(out[1])


def _clip(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)


def _n(v):
    """A number for a filter string: no trailing .0 on whole pixels."""
    return "%d" % round(v) if abs(v - round(v)) < 1e-9 else "%.4f" % v


def _write_rgba(raw, w, h, out_png):
    _run(FF + ["-f", "rawvideo", "-pixel_format", "rgba", "-video_size", "%dx%d" % (w, h),
               "-i", "-", "-frames:v", "1", out_png], stdin=raw)


def placeholder(out_png, w=1080, h=400, radius=24):
    """A white rounded rectangle, `radius` px corners, transparent outside.

    Nothing on it: this is the card's shape, not its content. Corners are
    antialiased over one pixel (alpha ramps across the arc), the straight
    edges are hard, so an overlay of this card has an exactly measurable edge.
    """
    r = int(max(0, min(radius, w // 2, h // 2)))
    opaque = bytes((255, 255, 255, 255)) * w
    band = list(range(r)) + list(range(w - r, w))
    rows = []
    for y in range(h):
        dy = max(r - (y + 0.5), (y + 0.5) - (h - r), 0.0)
        if dy <= 0.0:
            rows.append(opaque)
            continue
        px = bytearray(opaque)
        for x in band:
            dx = max(r - (x + 0.5), (x + 0.5) - (w - r), 0.0)
            if dx <= 0.0:
                continue
            a = _clip(r + 0.5 - math.hypot(dx, dy), 0.0, 1.0)
            px[4 * x + 3] = int(round(255 * a))
        rows.append(bytes(px))
    _write_rgba(b"".join(rows), w, h, out_png)
    return out_png


def shadowed(src_png, out_png, width=900, alpha=0.6, blur=24, dx=0, dy=12):
    """Scale `src_png` to `width` wide and drop a soft shadow behind it.

    The shadow is the card's own silhouette painted black at `alpha`, offset
    (dx, dy) and gaussian-blurred by `blur` px. Both sit on a transparent RGBA
    canvas with a margin of 3*blur + the offset, so the blur is never clipped
    and the card's rest position inside the canvas is (margin, margin).

    Returns the canvas size (w, h) -- the canvas is the image you overlay, so
    that is the size to hand to overlay_args.
    """
    sw, sh = _size(src_png)
    cw = int(width)
    ch = max(1, int(round(sh * cw / float(sw))))
    m = int(math.ceil(3 * blur)) + max(abs(int(dx)), abs(int(dy)))
    w, h = cw + 2 * m, ch + 2 * m
    shadow = ("[sil]colorchannelmixer=rr=0:rg=0:rb=0:gr=0:gg=0:gb=0:br=0:bg=0:bb=0:aa=%s,"
              "pad=%d:%d:%d:%d:color=%s" % (_n(alpha), w, h, m + int(dx), m + int(dy), _TRANSPARENT))
    if blur > 0:
        shadow += ",gblur=sigma=%s:steps=3" % _n(blur)
    graph = ("[0:v]scale=%d:%d:flags=lanczos,format=rgba,split=2[card][sil];"
             "%s[shadow];[shadow][card]overlay=%d:%d:format=auto[out]" % (cw, ch, shadow, m, m))
    _run(FF + ["-i", src_png, "-filter_complex", graph, "-map", "[out]", "-frames:v", "1", out_png])
    return w, h


def overlay_args(card_w, card_h, y_frac, t_in, dur_in, t_out, dur_out,
                 canvas_w=1080, canvas_h=1920):
    """The `overlay=` arguments that slide the card in, hold it, slide it out.

    At rest the card is centred horizontally, x = (canvas_w - card_w)/2, and
    its CENTRE sits at y_frac*canvas_h. x starts just off the right edge
    (x = canvas_w), reaches rest over dur_in seconds from t_in on a cubic
    ease-out, holds, then leaves to just off the left edge (x = -card_w) over
    dur_out seconds from t_out on a cubic ease-in. `enable` shows the card only
    between t_in and t_out + dur_out. All times are segment-local seconds, so
    the string drops into the filtergraph of one cut segment unchanged.

    The cubes are written as q*q*q and not pow(q,3): ffmpeg's pow is exp(log)
    and loses the last bits (pow(0.5,3)*1000 evaluates to 124.99...). And in
    the yuv420 path overlay snaps x down to an even column for chroma
    alignment, so the card lands on the even floor of this expression -- worth
    one pixel at most, and the rest position is even by construction whenever
    canvas_w and card_w are.
    """
    rest = (canvas_w - card_w) / 2.0
    x_off_r = float(canvas_w)
    x_off_l = -float(card_w)
    y = int(round(y_frac * canvas_h - card_h / 2.0))
    q = "(1-clip((t-%s)/%s,0,1))" % (_n(t_in), _n(dur_in))
    r = "clip((t-%s)/%s,0,1)" % (_n(t_out), _n(dur_out))
    slide_in = "%s+(%s)*(1-%s*%s*%s)" % (_n(x_off_r), _n(rest - x_off_r), q, q, q)
    slide_out = "%s+(%s)*%s*%s*%s" % (_n(rest), _n(x_off_l - rest), r, r, r)
    x = "if(lt(t,%s),%s,%s)" % (_n(t_out), slide_in, slide_out)
    return "x='%s':y=%d:enable='between(t,%s,%s)'" % (x, y, _n(t_in), _n(t_out + dur_out))


def _pgm_row(path):
    """The grey values of a 1-row P5 pgm ffmpeg wrote."""
    data = open(path, "rb").read()
    fields, i = [], 0
    while len(fields) < 4:
        while i < len(data) and data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b"#":
            while i < len(data) and data[i] != 0x0A:
                i += 1
            continue
        j = i
        while j < len(data) and not data[j:j + 1].isspace():
            j += 1
        fields.append(data[i:j])
        i = j
    if fields[0] != b"P5":
        raise SystemExit("not a binary pgm: %s" % path)
    w = int(fields[1])
    return data[i + 1:i + 1 + w]


def _left_edge(video, t, cy, outdir, tag, fps=60.0, thresh=32):
    """The first lit column of the 1 px row at `cy`, or None if the row is dark.

    Seeks half a frame BEFORE t: ffmpeg's accurate seek keeps the first frame
    at or after the seek point, so the frame measured is the one whose pts is
    exactly t and never its successor.
    """
    pgm = os.path.join(outdir, "row_%s.pgm" % tag)
    _run(FF + ["-ss", "%.4f" % (t - 0.5 / fps), "-i", video, "-frames:v", "1",
               "-vf", "crop=iw:1:0:%d,format=gray" % cy,
               "-f", "image2", "-update", "1", pgm])
    row = _pgm_row(pgm)
    for x, v in enumerate(row):
        if v > thresh:
            return x
    return None


def _selftest(outdir):
    os.makedirs(outdir, exist_ok=True)
    raw = placeholder(os.path.join(outdir, "card_raw.png"))
    print("placeholder %dx%d  %s" % (_size(raw) + (raw,)))
    card = os.path.join(outdir, "card.png")
    sw, sh = shadowed(raw, card)
    print("shadowed    %dx%d  %s" % (sw, sh, card))

    # A hard-edged card so the measured column is the overlay x itself and not
    # the shadow's blurred fringe.
    probe_w, probe_h = 900, 400
    probe = placeholder(os.path.join(outdir, "probe.png"), w=probe_w, h=probe_h)
    y_frac, t_in, dur_in, t_out, dur_out = 0.5, 1.0, 0.6, 8.0, 0.5
    args = overlay_args(probe_w, probe_h, y_frac, t_in, dur_in, t_out, dur_out)
    rest = (1080 - probe_w) / 2.0
    top = int(round(y_frac * 1920 - probe_h / 2.0))
    cy = top + probe_h // 2
    print("overlay     %s" % args)

    black = os.path.join(outdir, "black.mp4")
    _run(FF + ["-f", "lavfi", "-i", "color=c=black:s=1080x1920:r=60:d=12",
               "-c:v", "libx264", "-crf", "0", "-preset", "ultrafast",
               "-pix_fmt", "yuv444p", black])
    over = os.path.join(outdir, "overlaid.mp4")
    _run(FF + ["-i", black, "-loop", "1", "-i", probe,
               "-filter_complex", "[0:v][1:v]overlay=%s[v]" % args, "-map", "[v]",
               "-frames:v", "720", "-c:v", "libx264", "-crf", "0", "-preset", "ultrafast",
               "-pix_fmt", "yuv444p", over])

    def want(t):
        """The expression's own value at t, and the even column overlay uses."""
        if t < t_in or t > t_out + dur_out:
            return None, None
        if t < t_out:
            q = 1.0 - _clip((t - t_in) / dur_in, 0.0, 1.0)
            x = 1080.0 + (rest - 1080.0) * (1 - q * q * q)
        else:
            r = _clip((t - t_out) / dur_out, 0.0, 1.0)
            x = rest + (-probe_w - rest) * r * r * r
        return x, max(0, int(math.floor(x)) // 2 * 2)

    shots = [("t_in-0.05", t_in - 0.05), ("t_in+dur_in/2", t_in + dur_in / 2),
             ("t_in+dur_in+0.1", t_in + dur_in + 0.1), ("t_out-0.05", t_out - 0.05),
             ("t_out+dur_out/2", t_out + dur_out / 2),
             ("t_out+dur_out+0.05", t_out + dur_out + 0.05)]
    print("card %dx%d on 1080x1920, row y=%d, rest x=(1080-%d)/2=%s" % (
        probe_w, probe_h, cy, probe_w, _n(rest)))
    bad = 0
    for name, t in shots:
        x = _left_edge(over, t, cy, outdir, name.replace("/", "_"))
        xf, want_px = want(t)
        if x != want_px:
            bad += 1
        print("  %-19s t=%5.2f  left edge %-18s expected %s" % (
            name, t, "none (card hidden)" if x is None else "%d px" % x,
            "hidden (enable off)" if xf is None else "%d px (expr x=%.2f)" % (want_px, xf)))
    print("%d of %d sample points off" % (bad, len(shots)))
    print("rest position (1080-%d)/2 = %s px" % (probe_w, _n(rest)))

    # The shadowed canvas at rest: its white body starts one margin in, so the
    # two halves agree -- (1080-1068)/2 + 84 = 90, the same column. A short
    # window of its own, because seeking the INPUT rebases the filtergraph's t
    # to zero and `enable` would hide the card.
    rest_sh = (1080 - sw) / 2.0
    margin = (sw - 900) // 2
    sh_args = overlay_args(sw, sh, y_frac, 0.0, 0.1, 5.0, 0.5)
    sh_over = os.path.join(outdir, "overlaid_shadowed.mp4")
    _run(FF + ["-i", black, "-loop", "1", "-i", card,
               "-filter_complex", "[0:v][1:v]overlay=%s[v]" % sh_args, "-map", "[v]",
               "-frames:v", "30", "-c:v", "libx264", "-crf", "0", "-preset", "ultrafast",
               "-pix_fmt", "yuv444p", sh_over])
    sh_cy = int(round(y_frac * 1920 - sh / 2.0)) + sh // 2
    lit = _left_edge(sh_over, 0.2, sh_cy, outdir, "shadowed", thresh=128)
    print("shadowed card at rest: white body at %s px, expected %s+%d margin = %s px" % (
        lit, _n(rest_sh), margin, _n(rest_sh + margin)))


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--selftest":
        _selftest(sys.argv[2])
        return
    if len(sys.argv) >= 3 and sys.argv[1] == "--placeholder":
        a = [int(v) for v in sys.argv[3:6]] or [1080, 400, 24]
        while len(a) < 3:
            a.append([1080, 400, 24][len(a)])
        out = placeholder(sys.argv[2], a[0], a[1], a[2])
        print("placeholder %dx%d radius %d: %s" % (a[0], a[1], a[2], out))
        return
    raise SystemExit("usage: card.py --selftest <outdir> | --placeholder <out.png> [w h radius]")


if __name__ == "__main__":
    main()
