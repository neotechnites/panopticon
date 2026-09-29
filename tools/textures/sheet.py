#!/usr/bin/env python3
"""Pack/unpack a home's textures/*.png into one SHEET_<name>.png for editing in Aseprite.

    sheet.py pack   [home...]   # default: all 8 homes below
    sheet.py unpack [home...]

A home is a directory holding a textures/ folder (e.g. "maps/forest", "hub").
Pack writes textures/SHEET_<name>.png + SHEET_<name>.json (name = home's basename).
Unpack reads them back and rewrites the individual PNGs, skipping unchanged ones.
"""
import json
import os
import sys

from PIL import Image

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

DEFAULT_HOMES = [
    "maps/bentham_ring", "maps/forest", "maps/marble",
    "characters", "tower", "weapons", "props", "hub",
]

GUTTER = 4                      # magenta gutter, px
MAGENTA = (255, 0, 255, 255)
LABEL_COLOR = (255, 255, 255, 255)
GLYPH_W, GLYPH_H = 3, 5
CHAR_ADVANCE = GLYPH_W + 1      # 1px letter spacing
LABEL_TOP_PAD = 1
LABEL_BOTTOM_PAD = 1
LABEL_H = LABEL_TOP_PAD + GLYPH_H + LABEL_BOTTOM_PAD

# 3x5 bitmap font, rows top->bottom, '#' = lit. Covers [a-z0-9_.] -- the only
# characters that appear in these repo's texture file names.
FONT = {
    "0": ["###", "#.#", "#.#", "#.#", "###"],
    "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["###", "..#", "###", "#..", "###"],
    "3": ["###", "..#", "###", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"],
    "5": ["###", "#..", "###", "..#", "###"],
    "6": ["###", "#..", "###", "#.#", "###"],
    "7": ["###", "..#", "..#", "..#", "..#"],
    "8": ["###", "#.#", "###", "#.#", "###"],
    "9": ["###", "#.#", "###", "..#", "###"],
    "a": [".#.", "#.#", "###", "#.#", "#.#"],
    "b": ["##.", "#.#", "##.", "#.#", "##."],
    "c": [".##", "#..", "#..", "#..", ".##"],
    "d": ["##.", "#.#", "#.#", "#.#", "##."],
    "e": ["###", "#..", "##.", "#..", "###"],
    "f": ["###", "#..", "##.", "#..", "#.."],
    "g": [".##", "#..", "#.#", "#.#", ".##"],
    "h": ["#.#", "#.#", "###", "#.#", "#.#"],
    "i": ["###", ".#.", ".#.", ".#.", "###"],
    "j": ["..#", "..#", "..#", "#.#", ".#."],
    "k": ["#.#", "#.#", "##.", "#.#", "#.#"],
    "l": ["#..", "#..", "#..", "#..", "###"],
    "m": ["#.#", "###", "#.#", "#.#", "#.#"],
    "n": ["###", "#.#", "#.#", "#.#", "#.#"],
    "o": [".#.", "#.#", "#.#", "#.#", ".#."],
    "p": ["##.", "#.#", "##.", "#..", "#.."],
    "q": [".#.", "#.#", "#.#", ".##", "..#"],
    "r": ["##.", "#.#", "##.", "#.#", "#.#"],
    "s": [".##", "#..", ".#.", "..#", "##."],
    "t": ["###", ".#.", ".#.", ".#.", ".#."],
    "u": ["#.#", "#.#", "#.#", "#.#", ".#."],
    "v": ["#.#", "#.#", "#.#", ".#.", ".#."],
    "w": ["#.#", "#.#", "#.#", "###", "#.#"],
    "x": ["#.#", "#.#", ".#.", "#.#", "#.#"],
    "y": ["#.#", "#.#", ".#.", ".#.", ".#."],
    "z": ["###", "..#", ".#.", "#..", "###"],
    "_": ["...", "...", "...", "...", "###"],
    ".": ["...", "...", "...", "...", ".#."],
}


def draw_text(canvas, x, y, text):
    """Blit text at (x, y) using the 3x5 FONT, one glyph cell at a time."""
    for i, ch in enumerate(text.lower()):
        glyph = FONT.get(ch)
        if glyph is None:
            continue
        gx = x + i * CHAR_ADVANCE
        for row in range(GLYPH_H):
            for col in range(GLYPH_W):
                if glyph[row][col] == "#":
                    canvas.putpixel((gx + col, y + row), LABEL_COLOR)


def list_textures(home_dir):
    tex_dir = os.path.join(home_dir, "textures")
    names = sorted(
        f for f in os.listdir(tex_dir)
        if f.endswith(".png") and not f.startswith("SHEET_")
    )
    return tex_dir, names


def kind_of(name):
    return "emissive" if name.endswith("_emissive.png") else "albedo"


def pack_home(home):
    home_dir = os.path.join(REPO_ROOT, home)
    tex_dir, names = list_textures(home_dir)
    name = os.path.basename(home.rstrip("/"))

    blocks = {"albedo": [], "emissive": []}
    for fname in names:
        img = Image.open(os.path.join(tex_dir, fname))
        mode = img.mode
        rgba = img.convert("RGBA")
        blocks[kind_of(fname)].append({"file": fname, "img": rgba, "mode": mode})

    def layout(entries):
        x = 0
        cols = []
        for e in entries:
            label_w = len(e["file"]) * CHAR_ADVANCE - 1
            col_w = max(e["img"].width, label_w)
            cols.append((x, col_w, e))
            x += col_w + GUTTER
        width = x - GUTTER if entries else 0
        height = (LABEL_H + max(e["img"].height for e in entries)) if entries else 0
        return cols, width, height

    albedo_cols, albedo_w, albedo_h = layout(blocks["albedo"])
    emissive_cols, emissive_w, emissive_h = layout(blocks["emissive"])

    canvas_w = max(albedo_w, emissive_w)
    canvas_h = albedo_h + (GUTTER + emissive_h if blocks["emissive"] else 0)
    if canvas_w == 0 or canvas_h == 0:
        raise SystemExit(f"sheet.py: no textures found in {tex_dir}")

    canvas = Image.new("RGBA", (canvas_w, canvas_h), MAGENTA)
    manifest = {"canvas": [canvas_w, canvas_h], "textures": []}

    block_top = 0
    for cols, block_h in ((albedo_cols, albedo_h), (emissive_cols, emissive_h)):
        for x, col_w, e in cols:
            draw_text(canvas, x, block_top + LABEL_TOP_PAD, e["file"])
            iy = block_top + LABEL_H
            canvas.paste(e["img"], (x, iy))
            manifest["textures"].append({
                "file": e["file"],
                "kind": kind_of(e["file"]),
                "mode": e["mode"],
                "rect": [x, iy, e["img"].width, e["img"].height],
            })
        block_top += block_h + GUTTER

    out_png = os.path.join(tex_dir, f"SHEET_{name}.png")
    out_json = os.path.join(tex_dir, f"SHEET_{name}.json")
    canvas.save(out_png)
    with open(out_json, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(f"pack {home}: {out_png} ({canvas_w}x{canvas_h}, {len(manifest['textures'])} textures)")


def unpack_home(home):
    home_dir = os.path.join(REPO_ROOT, home)
    tex_dir = os.path.join(home_dir, "textures")
    name = os.path.basename(home.rstrip("/"))
    sheet_png = os.path.join(tex_dir, f"SHEET_{name}.png")
    sheet_json = os.path.join(tex_dir, f"SHEET_{name}.json")
    if not os.path.exists(sheet_png) or not os.path.exists(sheet_json):
        raise SystemExit(f"sheet.py: no sheet for {home} (run pack first)")

    sheet = Image.open(sheet_png).convert("RGBA")
    with open(sheet_json) as f:
        manifest = json.load(f)

    written, skipped = 0, 0
    for t in manifest["textures"]:
        x, y, w, h = t["rect"]
        crop = sheet.crop((x, y, x + w, y + h)).convert(t["mode"])
        path = os.path.join(tex_dir, t["file"])
        if os.path.exists(path):
            existing = Image.open(path).convert(t["mode"])
            if existing.size == crop.size and existing.tobytes() == crop.tobytes():
                skipped += 1
                continue
        crop.save(path)
        written += 1
    print(f"unpack {home}: {written} written, {skipped} unchanged")


def resolve_homes(args):
    return args if args else list(DEFAULT_HOMES)


def main(argv):
    if len(argv) < 2 or argv[1] not in ("pack", "unpack"):
        print(__doc__)
        return 2
    cmd, homes = argv[1], resolve_homes(argv[2:])
    for home in homes:
        (pack_home if cmd == "pack" else unpack_home)(home)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
