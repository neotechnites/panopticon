r"""Screen-space text layout: captions, cards and the text already in the footage never overlap.

A box is (x, y, w, h) in output pixels and lives over a time window [t0, t1). Two
boxes conflict when both their rectangles and their windows intersect. The solver
gives every caption the first y slot (0.72 of the height first, then alternately
below and above) that conflicts with nothing already placed, so a card or OCR'd
footage text pushes a caption aside and stacked persistent captions take distinct
slots. If no slot is free the caption is left at its preferred slot, marked, and
G11 fails. ASS is written from the solved boxes, so what G11 checks is what burns.

    python -m cp.layout --ocr <video> [--fps 4]      # print the OCR text boxes of a clip
"""
import concurrent.futures
import csv
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

STYLE = {"font": "Impact", "size": 76, "outline": 5, "shadow": 2, "colour": "&H00FFFFFF", "active": "&H0000FFFF"}
CAPTION_Y = 0.72               # Ryan: captions at 0.72 of the height
SLOT_STEP = 0.06               # next slot, as a fraction of the height
MARGIN = 40                    # px kept clear at the frame edges
WORDS_PER_CHUNK = 3
OCR_FPS = 4
OCR_MIN_CONF = 70
FONT_PATHS = {"Impact": [r"C:\Windows\Fonts\impact.ttf", "/System/Library/Fonts/Supplemental/Impact.ttf",
                         "/Library/Fonts/Impact.ttf"]}
TESSERACT = [r"C:\Program Files\Tesseract-OCR\tesseract.exe", "/opt/homebrew/bin/tesseract", "/usr/bin/tesseract",
             "tesseract"]


def intersects(a, b):
    """Rectangles a, b = (x, y, w, h) share area."""
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def overlaps_t(a0, a1, b0, b1):
    return a0 < b1 and b0 < a1


def conflict(a, b):
    return overlaps_t(a["t0"], a["t1"], b["t0"], b["t1"]) and intersects(a["box"], b["box"])


def contains(outer, inner, slack=8):
    return (inner[0] >= outer[0] - slack and inner[1] >= outer[1] - slack
            and inner[0] + inner[2] <= outer[0] + outer[2] + slack and inner[1] + inner[3] <= outer[1] + outer[3] + slack)


# ---------------------------------------------------------------------------
# text measurement (the box libass will draw)
# ---------------------------------------------------------------------------

_fonts = {}


def _font(size):
    from PIL import ImageFont
    path = next((p for p in FONT_PATHS[STYLE["font"]] if os.path.exists(p)), None)
    if path is None:
        raise SystemExit("layout: font %s not found in %s" % (STYLE["font"], FONT_PATHS[STYLE["font"]]))
    if size not in _fonts:
        base = ImageFont.truetype(path, 100)
        asc, desc = base.getmetrics()
        # libass sizes a font so ascent + descent = Fontsize; PIL sizes the em.
        _fonts[size] = ImageFont.truetype(path, max(1, int(round(size * 100.0 / (asc + desc)))))
    return _fonts[size]


def text_box_size(text, size=None):
    """(w, h) in px of an ASS caption line, outline and shadow included."""
    size = size or STYLE["size"]
    f = _font(size)
    l, t, r, b = f.getbbox(text)
    pad = STYLE["outline"] + STYLE["shadow"]
    return int(r - l + 2 * pad + 2), int(size + 2 * pad)


# ---------------------------------------------------------------------------
# captions from word timings
# ---------------------------------------------------------------------------

def _chunks(words, width):
    """Groups of up to 3 words, fewer when a group would not fit the frame width."""
    out, cur = [], []
    for w in words:
        trial = cur + [w]
        if cur and (len(trial) > WORDS_PER_CHUNK or text_box_size(" ".join(x["w"] for x in trial).upper())[0]
                    > width - 2 * MARGIN):
            out.append(cur)
            cur = [w]
        else:
            cur = trial
    if cur:
        out.append(cur)
    return out


def captions_for(lines, words, mode, width):
    """lines: [{id, start, dur}] (seconds), words: {id: [{w, t0, t1}]} -> caption items.

    pop: each 3-word chunk shows from its first word to the next chunk (or its last
    word + 0.3 s), clipped to the line. stack: each chunk stays up to the line end.
    """
    if mode == "none":
        return []
    items = []
    for ln in lines:
        ws = words.get(ln["id"]) or []
        if not ws:
            continue
        end = ln["start"] + ln["dur"]
        chunks = _chunks(ws, width)
        for i, ch in enumerate(chunks):
            t0 = ln["start"] + ch[0]["t0"]
            if mode == "stack":
                t1 = end
            elif i + 1 < len(chunks):
                t1 = ln["start"] + chunks[i + 1][0]["t0"]
            else:
                t1 = min(end, ln["start"] + ch[-1]["t1"] + 0.3)
            t1 = min(t1, end)
            text = " ".join(w["w"] for w in ch).upper()
            w, h = text_box_size(text)
            items.append({"kind": "caption", "line": ln["id"], "text": text, "t0": round(t0, 4), "t1": round(t1, 4),
                          "words": [{"w": x["w"].upper(), "t0": round(ln["start"] + x["t0"], 4),
                                     "t1": round(ln["start"] + x["t1"], 4)} for x in ch],
                          "size": (w, h)})
    return items


def _slots(height, h):
    """Centre y values to try, preferred first, alternately below and above."""
    ys, k = [CAPTION_Y * height], 1
    while k < 40:
        for sgn in (1, -1):
            y = (CAPTION_Y + sgn * k * SLOT_STEP) * height
            if MARGIN + h / 2 <= y <= height - MARGIN - h / 2:
                ys.append(y)
        k += 1
        if CAPTION_Y * height + k * SLOT_STEP * height > height and CAPTION_Y * height - k * SLOT_STEP * height < 0:
            break
    return ys


def solve(captions, obstacles, width, height):
    """Place every caption; obstacles are [{kind, box, t0, t1}] fixed in place. Returns (captions, unplaced)."""
    placed = []
    unplaced = []
    for c in sorted(captions, key=lambda c: (c["t0"], c["line"])):
        w, h = c["size"]
        x = (width - w) / 2
        ok = False
        for cy in _slots(height, h):
            box = (int(round(x)), int(round(cy - h / 2)), int(w), int(h))
            trial = dict(c, box=box)
            if not any(conflict(trial, o) for o in obstacles) and not any(conflict(trial, p) for p in placed):
                c["box"], ok = box, True
                break
        if not ok:
            cy = CAPTION_Y * height
            c["box"] = (int(round(x)), int(round(cy - h / 2)), int(w), int(h))
            c["unplaced"] = True
            unplaced.append(c)
        placed.append(c)
    return placed, unplaced


def gate_g11(captions, obstacles):
    """Zero pairwise intersection among every caption, card and footage-text box at every time."""
    boxes = list(captions) + list(obstacles)
    clashes = []
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, b = boxes[i], boxes[j]
            if a["kind"] == "ocr" and b["kind"] == "ocr":
                continue                     # two words of the same footage text are not ours to move
            if conflict(a, b):
                clashes.append("%s '%s' x %s '%s' at %.2f s" % (a["kind"], a.get("text", "")[:20], b["kind"],
                                                               b.get("text", "")[:20], max(a["t0"], b["t0"])))
    if clashes:
        return False, "%d text overlap(s): %s" % (len(clashes), "; ".join(clashes[:3]))
    return True, "%d captions, %d other text boxes, no overlap" % (len(captions), len(obstacles))


# ---------------------------------------------------------------------------
# ASS
# ---------------------------------------------------------------------------

def _ts(x):
    x = max(0.0, x)
    cs = int(round(x * 100))
    return "%d:%02d:%02d.%02d" % (cs // 360000, (cs // 6000) % 60, (cs // 100) % 60, cs % 100)


def _esc(s):
    return s.replace("\\", "\\\\").replace("{", "(").replace("}", ")")


def write_ass(path, captions, width, height, offset=0.0, window=None):
    """ASS of the captions, times shifted by -offset and clipped to window=(t0, t1)."""
    st = STYLE
    head = ("[Script Info]\nScriptType: v4.00+\nPlayResX: %d\nPlayResY: %d\nWrapStyle: 2\nScaledBorderAndShadow: yes\n\n"
            "[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, "
            "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, "
            "Alignment, MarginL, MarginR, MarginV, Encoding\n"
            "Style: Cap,%s,%d,%s,%s,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,%d,%d,5,0,0,0,1\n\n"
            "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
            % (width, height, st["font"], st["size"], st["colour"], st["colour"], st["outline"], st["shadow"]))
    ev = []
    for c in captions:
        x, y, w, h = c["box"]
        cx, cy = x + w / 2.0, y + h / 2.0
        ws = c["words"]
        for k, wd in enumerate(ws):
            a = c["t0"] if k == 0 else wd["t0"]
            b = ws[k + 1]["t0"] if k + 1 < len(ws) else c["t1"]
            if window:
                a, b = max(a, window[0]), min(b, window[1])
            if b <= a:
                continue
            txt = " ".join(("{\\c%s&}%s{\\c%s&}" % (st["active"], _esc(o["w"]), st["colour"]) if j == k else _esc(o["w"]))
                           for j, o in enumerate(ws))
            ev.append("Dialogue: 0,%s,%s,Cap,,0,0,0,,{\\an5\\pos(%d,%d)}%s" % (_ts(a - offset), _ts(b - offset),
                                                                              round(cx), round(cy), txt))
    with open(path, "w", encoding="utf-8") as f:
        f.write(head + "\n".join(ev) + "\n")
    return len(ev)


# ---------------------------------------------------------------------------
# OCR of the footage
# ---------------------------------------------------------------------------

def _tesseract():
    for t in TESSERACT:
        if os.path.isabs(t) and os.path.exists(t):
            return t
    found = shutil.which("tesseract")
    if not found:
        raise SystemExit("layout: tesseract not found (G11 needs OCR of the footage)")
    return found


def _ocr_frame(args):
    tess, png, t, half = args
    r = subprocess.run([tess, png, "stdout", "--psm", "11", "tsv"], capture_output=True, text=True, encoding="utf-8",
                       errors="replace")
    out = []
    for row in csv.DictReader(io.StringIO(r.stdout), delimiter="\t", quoting=csv.QUOTE_NONE):
        try:
            conf = float(row.get("conf") or -1)
        except ValueError:
            continue
        text = (row.get("text") or "").strip()
        if conf < OCR_MIN_CONF or len(re.sub(r"[^A-Za-z0-9]", "", text)) < 2:
            continue
        box = (int(row["left"]) * 2, int(row["top"]) * 2, int(row["width"]) * 2, int(row["height"]) * 2)
        out.append({"kind": "ocr", "text": text, "box": box, "t0": round(t - half, 4), "t1": round(t + half, 4),
                    "conf": conf})
    return out


def ocr_boxes(video, offset=0.0, fps=OCR_FPS, jobs=4, workdir=None):
    """Text boxes tesseract reads in the clip at `fps`, as obstacles timed from `offset`.

    Frames are read at half size (boxes scaled back up); a word must read at
    confidence >= 70 with two or more letters or digits, so noise is dropped.
    """
    tess = _tesseract()
    tmp = tempfile.mkdtemp(prefix="cp_ocr_", dir=workdir)
    try:
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", video, "-vf",
                        "fps=%s,scale=iw/2:ih/2,format=gray" % fps, os.path.join(tmp, "f%05d.png")], check=True)
        frames = sorted(f for f in os.listdir(tmp) if f.endswith(".png"))
        half = 0.5 / fps
        work = [(tess, os.path.join(tmp, f), offset + (i + 0.5) / fps, half) for i, f in enumerate(frames)]
        boxes = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
            for got in ex.map(_ocr_frame, work):
                boxes.extend(got)
        return merge_ocr(boxes)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def merge_ocr(boxes):
    """Join a word seen on consecutive frames at about the same place into one timed box."""
    boxes = sorted(boxes, key=lambda b: (b["text"], b["t0"]))
    out = []
    for b in boxes:
        last = out[-1] if out else None
        if (last and last["text"] == b["text"] and b["t0"] <= last["t1"] + 1e-6
                and abs(last["box"][0] - b["box"][0]) < 24 and abs(last["box"][1] - b["box"][1]) < 24):
            x0 = min(last["box"][0], b["box"][0])
            y0 = min(last["box"][1], b["box"][1])
            x1 = max(last["box"][0] + last["box"][2], b["box"][0] + b["box"][2])
            y1 = max(last["box"][1] + last["box"][3], b["box"][1] + b["box"][3])
            last["box"] = (x0, y0, x1 - x0, y1 - y0)
            last["t1"] = b["t1"]
        else:
            out.append(dict(b))
    return out


def drop_owned(ocr, overlays):
    """OCR boxes that are our own card's text are the card, not footage text."""
    return [o for o in ocr if not any(overlaps_t(o["t0"], o["t1"], v["t0"], v["t1"]) and contains(v["box"], o["box"])
                                      for v in overlays)]


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--ocr":
        fps = float(sys.argv[sys.argv.index("--fps") + 1]) if "--fps" in sys.argv else OCR_FPS
        print(json.dumps(ocr_boxes(sys.argv[2], fps=fps), indent=1))
    else:
        raise SystemExit("usage: python -m cp.layout --ocr <video> [--fps 4]")
