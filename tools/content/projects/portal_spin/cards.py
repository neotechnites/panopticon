"""The two stills of the portal_spin short: the PLACEHOLDER comment card and the shader lines (ed473b24)."""
import sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1]
SANS = "/System/Library/Fonts/Supplemental/Arial.ttf"
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
MONO = "/System/Library/Fonts/Menlo.ttc"


def rounded(w, h, r, fill):
    im = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle((0, 0, w * 2 - 1, h * 2 - 1), r * 2, fill=fill)
    return im.resize((w, h), Image.LANCZOS)


# A YouTube-style comment, white, handle and text marked PLACEHOLDER.
card = rounded(1080, 330, 36, (255, 255, 255, 255))
d = ImageDraw.Draw(card)
d.ellipse((48, 48, 148, 148), fill=(92, 107, 192))
d.text((98, 98), "C", font=ImageFont.truetype(BOLD, 56), fill="white", anchor="mm")
d.text((178, 56), "@commenter", font=ImageFont.truetype(BOLD, 40), fill=(15, 15, 15))
d.text((440, 60), "3 days ago", font=ImageFont.truetype(SANS, 34), fill=(96, 96, 96))
d.text((178, 118), "make the portal spin", font=ImageFont.truetype(SANS, 52), fill=(15, 15, 15))
d.text((178, 214), "▲  12     ▼      Reply", font=ImageFont.truetype(SANS, 34), fill=(96, 96, 96))
d.rounded_rectangle((760, 228, 1040, 290), 12, fill=(204, 0, 0))
d.text((900, 259), "PLACEHOLDER", font=ImageFont.truetype(BOLD, 32), fill="white", anchor="mm")
card.save(OUT + "/comment_placeholder.png")

# The lines the spin added, in an editor's dark script pane.
lines = [
    ("// The swirl spins about its centre", (128, 140, 152)),
    ("#define WAVE_SPIN 0.8", (255, 140, 204)),
    ("", None),
    ("vec2 uv = UV;", (220, 225, 232)),
    ("vec2 d = UV - vec2(0.5);", (220, 225, 232)),
    ("float a = TIME * WAVE_SPIN;", (220, 225, 232)),
    ("uv = vec2(0.5) + mat2(vec2(cos(a),sin(a)),", (220, 225, 232)),
    ("      vec2(-sin(a),cos(a))) * d;", (220, 225, 232)),
]
mono = ImageFont.truetype(MONO, 36)
pane = rounded(1080, 120 + 56 * len(lines), 24, (32, 37, 49, 245))
d = ImageDraw.Draw(pane)
d.text((40, 30), "portal_wave.gdshader", font=ImageFont.truetype(SANS, 32), fill=(170, 178, 190))
for i, (text, col) in enumerate(lines):
    y = 92 + 56 * i
    d.text((40, y), str(i + 84), font=mono, fill=(90, 98, 110))
    if text:
        d.text((130, y), text, font=mono, fill=col)
pane.save(OUT + "/shader_lines.png")
